import SwiftUI
import SwiftData

@main
struct TranScreenApp: App {
    @StateObject private var appState = AppState()

    init() {
        L10n.applySavedLanguage()
    }

    let sharedModelContainer: ModelContainer = {
        let schema = Schema([EngineConfig.self, AppSettings.self, HotkeyBinding.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("SwiftData ModelContainer 初始化失败: \(error)")
        }
    }()

    var body: some Scene {
        MenuBarExtra("TranScreen", image: "MenuBarIcon") {
            MenuBarView()
                .environmentObject(appState)
                .modelContainer(sharedModelContainer)
                .onAppear { initializeApp() }
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
                .modelContainer(sharedModelContainer)
        }
    }

    @MainActor
    private func initializeApp() {
        let ctx = sharedModelContainer.mainContext

        // 加载或创建 AppSettings
        let settingsDesc = FetchDescriptor<AppSettings>()
        if let settings = try? ctx.fetch(settingsDesc).first {
            settings.displayLanguage = AppDisplayLanguage.normalized(settings.displayLanguage)
            L10n.setPreferredLanguage(settings.displayLanguage)
            appState.settings = settings
            appState.overlayOpacity = settings.overlayOpacity
        } else {
            let settings = AppSettings()
            L10n.setPreferredLanguage(settings.displayLanguage)
            ctx.insert(settings)
            try? ctx.save()
            appState.settings = settings
        }

        // 加载引擎配置；首次启动自动添加 Apple 翻译为默认引擎
        let engineDesc = FetchDescriptor<EngineConfig>(sortBy: [SortDescriptor(\.sortOrder)])
        var engines = (try? ctx.fetch(engineDesc)) ?? []
        if engines.isEmpty, #available(macOS 15, *) {
            let apple = EngineConfig(
                displayName: "Apple 翻译（离线）",
                engineType: .apple,
                isEnabled: true,
                sortOrder: 0
            )
            ctx.insert(apple)
            try? ctx.save()
            engines = [apple]
        }
        appState.reloadEngines(from: engines)

        // 加载或初始化快捷键配置
        let hotkeyDesc = FetchDescriptor<HotkeyBinding>()
        let existingBindings = (try? ctx.fetch(hotkeyDesc)) ?? []
        if existingBindings.isEmpty {
            for action in HotkeyAction.allCases {
                ctx.insert(HotkeyBinding(action: action))
            }
            try? ctx.save()
        }
        let allBindings = (try? ctx.fetch(hotkeyDesc)) ?? []
        appState.startHotkeyMonitoring(with: allBindings)

        appState.checkPermissions()
    }
}
