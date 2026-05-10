import SwiftUI
import SwiftData

struct EngineSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \EngineConfig.sortOrder) private var engines: [EngineConfig]
    @EnvironmentObject var appState: AppState

    @State private var showAddSheet = false
    @State private var editingEngine: EngineConfig?
    @State private var testResults: [UUID: TestResult] = [:]

    enum TestResult { case testing, success, failure(String) }

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(engines) { engine in
                    EngineRow(engine: engine, testResult: testResults[engine.id]) {
                        testEngine(engine)
                    } onEdit: {
                        editingEngine = engine
                    }
                }
                .onMove(perform: moveEngines)
                .onDelete(perform: deleteEngines)
            }
            .listStyle(.inset)

            Divider()

            HStack {
                Button { showAddSheet = true } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderless)
                Spacer()
                Text("拖拽调整优先级").font(.caption).foregroundStyle(.secondary)
            }
            .padding(8)
        }
        .sheet(isPresented: $showAddSheet) {
            EngineEditSheet(engine: nil) { config in
                config.sortOrder = engines.count
                modelContext.insert(config)
                try? modelContext.save()
                refreshEnginesInAppState()
            }
        }
        .sheet(item: $editingEngine) { engine in
            EngineEditSheet(engine: engine) { _ in
                try? modelContext.save()
                refreshEnginesInAppState()
            }
        }
    }

    // 从 modelContext 重新拉取最新引擎列表注入 AppState
    // 必要：@Query 在 insert/delete 后不会同步更新，直接传 engines 会用旧快照
    private func refreshEnginesInAppState() {
        let descriptor = FetchDescriptor<EngineConfig>(sortBy: [SortDescriptor(\.sortOrder)])
        let fresh = (try? modelContext.fetch(descriptor)) ?? []
        appState.reloadEngines(from: fresh)
    }

    private func deleteEngines(at indexSet: IndexSet) {
        for i in indexSet {
            let engine = engines[i]
            modelContext.delete(engine)
        }
        try? modelContext.save()
        for (i, engine) in engines.enumerated() { engine.sortOrder = i }
        try? modelContext.save()
        refreshEnginesInAppState()
    }

    private func moveEngines(from source: IndexSet, to destination: Int) {
        var reordered = engines
        reordered.move(fromOffsets: source, toOffset: destination)
        for (i, engine) in reordered.enumerated() { engine.sortOrder = i }
        try? modelContext.save()
        refreshEnginesInAppState()
    }

    private func testEngine(_ engine: EngineConfig) {
        testResults[engine.id] = .testing
        Task {
            do {
                let testEng = try buildTestEngine(from: engine)
                _ = try await testEng.testConnection()
                testResults[engine.id] = .success
            } catch {
                testResults[engine.id] = .failure(error.localizedDescription)
            }
        }
    }

    private func buildTestEngine(from config: EngineConfig) throws -> any TranslationEngine {
        switch config.engineType {
        case .apple: return AppleTranslationEngine(configID: config.id)
        case .openAICompatible: return try OpenAICompatibleEngine(config: config)
        case .anthropicCompatible: return try AnthropicCompatibleEngine(config: config)
        case .googleCompatible: return try GoogleCompatibleEngine(config: config)
        case .deepL: return try DeepLEngine(config: config)
        case .ollama: return try OllamaEngine(config: config)
        }
    }
}

struct EngineRow: View {
    let engine: EngineConfig
    let testResult: EngineSettingsView.TestResult?
    let onTest: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(get: { engine.isEnabled }, set: { engine.isEnabled = $0 }))
                .labelsHidden()

            Image(systemName: engineIcon(engine.engineType))
                .foregroundStyle(.secondary).frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(engine.displayName).font(.body)
                Text(engine.engineType.displayName).font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            if let result = testResult {
                switch result {
                case .testing:
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                case .success: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                case .failure(let msg): Image(systemName: "xmark.circle.fill").foregroundStyle(.red).help(msg)
                }
            }

            Button("测试") { onTest() }.buttonStyle(.borderless).foregroundStyle(.blue)
            Button(action: onEdit) { Image(systemName: "pencil") }.buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }

    private func engineIcon(_ type: EngineType) -> String {
        switch type {
        case .apple: return "apple.logo"
        case .openAICompatible: return "bolt.circle"
        case .anthropicCompatible: return "brain.head.profile"
        case .googleCompatible: return "sparkles"
        case .deepL: return "globe"
        case .ollama: return "desktopcomputer"
        }
    }
}

struct EngineEditSheet: View {
    let engine: EngineConfig?
    let onSave: (EngineConfig) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedType: EngineType = .openAICompatible
    @State private var displayName = ""
    @State private var endpointURL = ""
    @State private var modelID = ""
    @State private var apiKey = ""
    @State private var isEnabled = true
    @State private var temperature: Double = 0.3
    @State private var systemPrompt: String = "你是一个有用的翻译助手"
    @State private var customPrompt: String = ""

    var body: some View {
        VStack(spacing: 0) {
            Text(engine == nil ? "添加翻译引擎" : "编辑翻译引擎")
                .font(.headline).padding()
            Divider()

            Form {
                Picker("引擎类型", selection: $selectedType) {
                    ForEach(EngineType.allCases) { Text($0.displayName).tag($0) }
                }
                .onChange(of: selectedType) { _, t in
                    if displayName.isEmpty { displayName = t.displayName }
                    // Compatible engines intentionally do not prefill official providers.
                    switch t {
                    case .openAICompatible:
                        break
                    case .anthropicCompatible, .googleCompatible:
                        break
                    case .ollama:
                        if endpointURL.isEmpty { endpointURL = "http://localhost:11434" }
                        if modelID.isEmpty { modelID = "llama3" }
                    case .apple, .deepL:
                        break
                    }
                }

                TextField("显示名称", text: $displayName)

                if selectedType.requiresEndpoint {
                    TextField(endpointPlaceholder, text: $endpointURL)
                }

                if selectedType.requiresModelID {
                    TextField("Model ID", text: $modelID).help(modelIDHint)
                }

                if selectedType.supportsAPIKey {
                    SecureField(selectedType.requiresAPIKey ? "API Key" : "API Key（可选）", text: $apiKey)
                    Text(apiKeyHelpText)
                        .font(.caption).foregroundStyle(.secondary)
                }

                if selectedType.supportsTemperature {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Temperature: \(temperature, specifier: "%.2f")")
                            .font(.callout)
                        Slider(value: $temperature, in: 0...2.0, step: 0.05)
                        Text("越低越稳定，越高越有创造性")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                if selectedType.supportsCustomPrompt {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("系统提示词").font(.callout).bold()
                        TextField("初始化系统提示词", text: $systemPrompt)
                            .help("发送给模型的系统级指令，定义翻译助手的基本行为")
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("自定义提示词").font(.callout).bold()
                        TextField("翻译风格、术语偏好等额外指令", text: $customPrompt)
                            .help("额外附加到系统提示词的用户自定义指令")
                    }
                }

                if selectedType == .apple {
                    AppleLanguagePackSection()
                }

                Toggle("启用此引擎", isOn: $isEnabled)
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("保存") { save() }.keyboardShortcut(.defaultAction).disabled(!canSave)
            }
            .padding()
        }
        .frame(width: 480, height: 560)
        .onAppear { loadExisting() }
    }

    private var modelIDHint: String {
        switch selectedType {
        case .openAICompatible: return "填写你的 OpenAI-compatible 服务支持的模型名"
        case .anthropicCompatible: return "填写你的 Anthropic-compatible 服务支持的模型名"
        case .googleCompatible: return "填写你的 Google-compatible 服务支持的模型名"
        case .ollama: return "如: llama3, mistral, qwen2"
        default: return ""
        }
    }

    private var canSave: Bool {
        let hasName = !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasEndpoint = !endpointURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasModel = !modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasRequiredKey = !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if !hasName { return false }
        if selectedType.requiresEndpoint && !hasEndpoint { return false }
        if selectedType.requiresModelID && !hasModel { return false }
        if selectedType.requiresAPIKey && !hasRequiredKey { return false }
        return true
    }

    private var endpointPlaceholder: String {
        switch selectedType {
        case .openAICompatible:
            return "Endpoint URL（如: https://your-host/v1）"
        case .anthropicCompatible:
            return "Endpoint URL（如: https://your-host/v1 或 .../v1/messages）"
        case .googleCompatible:
            return "Endpoint URL（如: https://your-host/v1beta）"
        case .ollama:
            return "Endpoint (默认: http://localhost:11434)"
        default:
            return "Endpoint URL"
        }
    }

    private var apiKeyHelpText: String {
        if selectedType.requiresAPIKey {
            return "API Key 将保存在本机应用配置中，不会请求系统钥匙串权限"
        }
        return "API Key 可留空，适合本地服务或已在端点侧处理鉴权的兼容接口"
    }

    private func loadExisting() {
        guard let engine else { return }
        selectedType = engine.engineType
        displayName = engine.displayName
        endpointURL = engine.endpointURL ?? ""
        modelID = engine.modelID ?? ""
        isEnabled = engine.isEnabled
        temperature = engine.temperature
        systemPrompt = engine.systemPrompt
        customPrompt = engine.customPrompt
        apiKey = engine.apiKey
    }

    private func save() {
        let config: EngineConfig
        if let existing = engine {
            existing.displayName = displayName
            existing.engineType = selectedType
            existing.endpointURL = endpointURL.isEmpty ? nil : endpointURL
            existing.modelID = modelID.isEmpty ? nil : modelID
            existing.apiKey = selectedType.supportsAPIKey ? apiKey : ""
            existing.isEnabled = isEnabled
            existing.temperature = temperature
            existing.systemPrompt = systemPrompt
            existing.customPrompt = customPrompt
            config = existing
        } else {
            config = EngineConfig(
                displayName: displayName,
                engineType: selectedType,
                endpointURL: endpointURL.isEmpty ? nil : endpointURL,
                modelID: modelID.isEmpty ? nil : modelID,
                apiKey: selectedType.supportsAPIKey ? apiKey : "",
                isEnabled: isEnabled,
                temperature: temperature,
                systemPrompt: systemPrompt,
                customPrompt: customPrompt
            )
        }
        onSave(config)
        dismiss()
    }
}

// MARK: - Apple 翻译语言包准备
struct AppleLanguagePackSection: View {
    @State private var sourceLang = "en"
    @State private var targetLang = "zh-Hans"
    @State private var status: String?
    @State private var isPreparing = false

    private let langs: [(String, String)] = [
        ("en", "英语"), ("zh-Hans", "简体中文"), ("zh-Hant", "繁体中文"),
        ("ja", "日语"), ("ko", "韩语"), ("fr", "法语"), ("de", "德语"),
        ("es", "西班牙语"), ("ru", "俄语"), ("it", "意大利语"), ("pt", "葡萄牙语")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("语言包").font(.callout).bold()
            Text("Apple 翻译需要先下载对应语言包才能离线使用。点击下载将弹出系统对话框确认。")
                .font(.caption).foregroundStyle(.secondary)

            HStack {
                Picker("从", selection: $sourceLang) {
                    ForEach(langs, id: \.0) { Text($0.1).tag($0.0) }
                }
                Picker("到", selection: $targetLang) {
                    ForEach(langs, id: \.0) { Text($0.1).tag($0.0) }
                }
            }

            HStack {
                Button {
                    prepare()
                } label: {
                    if isPreparing {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .controlSize(.small)
                    } else {
                        Text("下载/检查语言包")
                    }
                }
                .disabled(isPreparing)

                if let status {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func prepare() {
        guard #available(macOS 15, *) else {
            status = "需要 macOS 15 或更新"
            return
        }
        isPreparing = true
        status = "准备中..."
        Task {
            do {
                try await AppleTranslationBridge.shared.prepareLanguagePack(from: sourceLang, to: targetLang)
                status = "✅ 语言包就绪"
            } catch {
                status = "❌ \(error.localizedDescription)"
            }
            isPreparing = false
        }
    }
}
