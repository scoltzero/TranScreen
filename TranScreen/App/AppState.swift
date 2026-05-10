import SwiftUI
import ScreenCaptureKit
import NaturalLanguage
import ImageIO
import UniformTypeIdentifiers

@MainActor
final class AppState: ObservableObject {

    // MARK: - Mode
    enum Mode: Equatable {
        case idle
        case regionSelecting
        case regionTranslating(CGRect)
        case fullScreenMask
        case fullScreenRegionSelecting
    }

    @Published var mode: Mode = .idle {
        didSet { handleModeTransition(from: oldValue, to: mode) }
    }
    @Published var overlayOpacity: Double = 0.5
    @Published var translatedBlocks: [TranslatedBlock] = []
    @Published var hasScreenRecordingPermission = false
    @Published var hasAccessibilityPermission = false
    @Published var isProcessing = false
    @Published var lastError: String?
    @Published var showingOriginal = false
    @Published var selectedRegion: CGRect = .zero

    // 调试信息
    @Published var debugCapturedSize: CGSize = .zero
    @Published var debugOCRCount: Int = 0

    // MARK: - 子系统
    private(set) var panelController: OverlayPanelController?
    private(set) lazy var hotkeyManager = HotkeyManager(appState: self)

    private let screenCapture = ScreenCaptureManager()
    private let ocrEngine = OCREngine()
    private let textMerger = TextMerger()
    let translationManager = TranslationManager()

    private var fullScreenTask: Task<Void, Never>?
    private let diffDetector = DiffDetector()

    /// Holds the clean original capture so the screenshot button saves the
    /// pre-overlay image (no dimming, no translation labels). Cleared on idle.
    private var lastCapturedImage: CGImage?

    var settings: AppSettings?

    // MARK: - 计算属性
    var sourceLang: String { settings?.sourceLang ?? "auto" }
    var targetLang: String { settings?.targetLang ?? "zh-Hans" }
    var scanInterval: TimeInterval {
        (settings?.powerSavingEnabled == true) ? 5.0 : (settings?.scanInterval ?? 2.0)
    }

    // MARK: - 初始化
    init() {
        checkPermissions()
        setupPanelController()
    }

    private func setupPanelController() {
        panelController = OverlayPanelController(appState: self)
    }

    func checkPermissions() {
        hasScreenRecordingPermission = CGPreflightScreenCaptureAccess()
        hasAccessibilityPermission = AXIsProcessTrusted()
    }

    func requestPermissions() {
        CGRequestScreenCaptureAccess()
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - 状态机转换
    private func handleModeTransition(from old: Mode, to new: Mode) {
        if case .fullScreenMask = old { stopFullScreenTimer() }

        guard let panel = panelController else { return }

        switch new {
        case .idle:
            panel.hide()
            translatedBlocks = []
            lastCapturedImage = nil
            isProcessing = false
            lastError = nil

        case .regionSelecting:
            panel.showForSelection()

        case .regionTranslating(let rect):
            panel.showForTranslation(region: rect)
            processRegionCapture(region: rect)

        case .fullScreenMask:
            panel.showFullScreenMask()
            startFullScreenTimer()

        case .fullScreenRegionSelecting:
            panel.showFullScreenForRegionSelection()
        }
    }

    // MARK: - 公开动作
    func enterRegionSelect() {
        // 不做预检查 - ScreenCaptureKit 会在实际截图时由系统处理授权弹窗
        // CGPreflightScreenCaptureAccess 在进程中会缓存结果，授权后需重启才更新
        checkPermissions()  // 仅刷新菜单栏 UI 状态，不阻塞流程
        mode = .regionSelecting
    }

    func toggleFullScreenMask() {
        checkPermissions()
        mode = (mode == .fullScreenMask) ? .idle : .fullScreenMask
    }

    func exitToIdle() {
        mode = .idle
    }

    func adjustOpacity(by delta: Double) {
        overlayOpacity = max(0.1, min(0.9, overlayOpacity + delta))
        settings?.overlayOpacity = overlayOpacity
    }

    func handleRegionSelected(_ rect: CGRect) {
        selectedRegion = rect
        showingOriginal = false
        mode = .regionTranslating(rect)
    }

    func copyDisplayedText() {
        let text = translatedBlocks.map {
            showingOriginal ? $0.originalText : ($0.translatedText.isEmpty ? $0.originalText : $0.translatedText)
        }.joined(separator: "\n")
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @discardableResult
    func saveScreenshot(of region: CGRect) -> Bool {
        guard let cgImage = lastCapturedImage else {
            lastError = "无可保存的截图"
            return false
        }

        let imageToSave: CGImage
        if showingOriginal || translatedBlocks.isEmpty {
            imageToSave = cgImage
        } else if let rendered = renderDisplayedRegionScreenshot(baseImage: cgImage, region: region) {
            imageToSave = rendered
        } else {
            lastError = "无法生成译文截图"
            return false
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let suffix = showingOriginal ? "original" : "translated"
        let filename = "TranScreen_\(suffix)_\(formatter.string(from: Date())).png"
        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true)
        let url = downloadsURL.appendingPathComponent(filename)

        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            lastError = "无法创建图片输出"
            return false
        }
        CGImageDestinationAddImage(dest, imageToSave, nil)
        if CGImageDestinationFinalize(dest) {
            lastError = nil
            return true
        } else {
            lastError = "截图保存失败"
            return false
        }
    }

    private func renderDisplayedRegionScreenshot(baseImage: CGImage, region: CGRect) -> CGImage? {
        let imageSize = CGSize(width: region.width, height: region.height)
        let scale = CGFloat(baseImage.width) / max(region.width, 1)
        let nsImage = NSImage(cgImage: baseImage, size: imageSize)
        let screen = OverlayCoordinateSpace.screen(containing: region)
        let localRegion = OverlayCoordinateSpace.localRect(for: region, in: screen)
        let content = DisplayedRegionScreenshotView(
            baseImage: nsImage,
            blocks: translatedBlocks,
            showingOriginal: showingOriginal,
            localRegion: localRegion
        )
        .frame(width: imageSize.width, height: imageSize.height)

        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(imageSize)
        renderer.scale = scale
        renderer.isOpaque = true
        return renderer.cgImage
    }

    // MARK: - 核心 Pipeline：选区截图翻译
    func processRegionCapture(region: CGRect) {
        isProcessing = true
        lastError = nil
        Task {
            do {
                let image = try await screenCapture.captureRegion(region)
                let imageSize = CGSize(width: image.width, height: image.height)
                self.debugCapturedSize = imageSize
                self.lastCapturedImage = image

                guard image.width > 10, image.height > 10 else {
                    self.lastError = "选区太小（\(image.width)×\(image.height)px），无法识别"
                    self.isProcessing = false
                    self.mode = .idle
                    return
                }

                let ocrResults = try await ocrEngine.recognize(image: image)
                self.debugOCRCount = ocrResults.count
                guard !ocrResults.isEmpty else {
                    self.lastError = "未识别到文字"
                    self.isProcessing = false
                    return
                }

                let textBlocks = ocrResults.map { TextBlock(from: $0) }
                let mapper = CoordinateMapper(captureRegion: region, imageSize: imageSize)
                let edgeDetector = EdgeDetector()
                let segmenter = RegionSegmenter()

                // RegionSegmenter is still used for paragraph gap splitting (so each
                // visual paragraph translates independently), but we no longer use
                // its representativeHeight — font size is per-block median to avoid
                // collapsing title + body into one shared size when the cluster
                // detector merges them.
                let regions = segmenter.segment(blocks: textBlocks)

                var allMerged: [MergedTextBlock] = []
                var blockEdges: [UUID: LineGeometry] = [:]

                for textRegion in regions {
                    let merged = textMerger.merge(blocks: textRegion.blocks)
                    for mb in merged {
                        let edges = edgeDetector.detectLineEdges(blocks: mb.lines)
                        if let e = edges { blockEdges[mb.id] = e }
                    }
                    allMerged.append(contentsOf: merged)
                }

                guard !allMerged.isEmpty else {
                    self.lastError = "未识别到文字"
                    self.isProcessing = false
                    return
                }

                // Per-block bg color sampled now (used in the per-block fill).
                var blockBg: [UUID: (Double, Double, Double)] = [:]
                for mb in allMerged {
                    blockBg[mb.id] = BackgroundSampler.sampleBackgroundColor(image: image, normalizedBox: mb.boundingBox)
                }

                // Resolve source language
                let resolvedSource = (sourceLang == "auto")
                    ? Self.detectLanguage(from: allMerged.map(\.text))
                    : sourceLang

                // Lookup by text — translation API returns blocks in input order but
                // we want O(1) lookup against the original metadata.
                var metaByText: [String: (edges: LineGeometry?, lineBoxes: [CGRect], bg: (Double, Double, Double))] = [:]
                for mb in allMerged {
                    let bg = blockBg[mb.id] ?? (1, 1, 1)
                    metaByText[mb.text] = (blockEdges[mb.id], mb.lines.map(\.boundingBox), bg)
                }

                // Translate all blocks
                do {
                    let translated = try await translationManager.translate(
                        blocks: allMerged,
                        from: resolvedSource,
                        to: targetLang
                    )
                    let rendered = translated.map { block -> TranslatedBlock in
                        var b = block
                        b.captureRegion = region
                        b.screenRect = mapper.mapToSwiftUI(visionBox: b.visionBoundingBox)

                        let meta = metaByText[block.originalText]

                        // Font size from this block's own median line height — stable
                        // across paragraphs of the same actual size, but title and
                        // body get distinct sizes because their line heights differ.
                        let lineBoxes = meta?.lineBoxes ?? [b.visionBoundingBox]
                        b.fontSize = mapper.adaptiveFontSize(forLineBoxes: lineBoxes)
                        b.screenLineRects = lineBoxes.map { mapper.mapToSwiftUI(visionBox: $0) }

                        // Background color (already sampled above)
                        let bg = meta?.bg ?? (1, 1, 1)
                        b.bgRed = bg.0; b.bgGreen = bg.1; b.bgBlue = bg.2

                        // Text color — sample per OCR line, then dominant across lines.
                        // Pass the just-computed bg as reference so we filter "pixels
                        // different from background" rather than "pixels different from
                        // box mean luminance" (the latter mis-labels the abundant white
                        // pixels of a white-on-black/black-on-white line as text).
                        let (tr, tg, tb) = BackgroundSampler.sampleTextColor(
                            image: image,
                            normalizedBoxes: lineBoxes,
                            background: bg
                        )
                        b.textR = tr; b.textG = tg; b.textB = tb

                        // Line edges for indentation awareness
                        if let edges = meta?.edges {
                            b.lineEdges = (left: edges.leftEdge, right: edges.rightEdge)
                        }
                        return b
                    }
                    self.translatedBlocks = rendered
                    self.isProcessing = false
                } catch {
                    let fallback = allMerged.map { mb -> TranslatedBlock in
                        var b = TranslatedBlock(
                            originalText: mb.text,
                            translatedText: "",
                            visionBoundingBox: mb.boundingBox,
                            isVertical: mb.isVertical
                        )
                        b.captureRegion = region
                        b.screenRect = mapper.mapToSwiftUI(visionBox: b.visionBoundingBox)
                        b.screenLineRects = mb.lines.map { mapper.mapToSwiftUI(visionBox: $0.boundingBox) }
                        let bg = blockBg[mb.id] ?? (1, 1, 1)
                        b.bgRed = bg.0; b.bgGreen = bg.1; b.bgBlue = bg.2
                        return b
                    }
                    self.translatedBlocks = fallback
                    self.lastError = "翻译失败: \(error.localizedDescription)"
                    self.isProcessing = false
                }

            } catch {
                self.lastError = error.localizedDescription
                self.isProcessing = false
                self.mode = .idle
            }
        }
    }

    // MARK: - 全屏模式定时扫描
    private func startFullScreenTimer() {
        stopFullScreenTimer()
        fullScreenTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(scanInterval))
                guard !Task.isCancelled, mode == .fullScreenMask else { break }
                await processFullScreenCapture()
            }
        }
    }

    private func stopFullScreenTimer() {
        fullScreenTask?.cancel()
        fullScreenTask = nil
        Task { await diffDetector.reset() }
    }

    private func processFullScreenCapture() async {
        do {
            let image = try await screenCapture.captureFullScreen()
            let changedRegions = await diffDetector.detectChangedRegions(current: image)
            guard !changedRegions.isEmpty else { return }

            let ocrResults = try await ocrEngine.recognize(image: image)
            guard !ocrResults.isEmpty else { return }

            let textBlocks = ocrResults.map { TextBlock(from: $0) }
            let mergedBlocks = textMerger.merge(blocks: textBlocks)

            let translated = try await translationManager.translate(
                blocks: mergedBlocks,
                from: sourceLang,
                to: targetLang
            )

            let screenFrame = NSScreen.main?.frame ?? .zero
            let imageSize = CGSize(width: image.width, height: image.height)
            let mapper = CoordinateMapper(captureRegion: screenFrame, imageSize: imageSize)

            let lineBoxesByText: [String: [CGRect]] = Dictionary(
                uniqueKeysWithValues: mergedBlocks.map { ($0.text, $0.lines.map(\.boundingBox)) }
            )

            let rendered = translated.map { block -> TranslatedBlock in
                var b = block
                b.captureRegion = screenFrame
                b.screenRect = mapper.mapToSwiftUI(visionBox: b.visionBoundingBox)
                let lineBoxes = lineBoxesByText[block.originalText] ?? [block.visionBoundingBox]
                b.screenLineRects = lineBoxes.map { mapper.mapToSwiftUI(visionBox: $0) }
                b.fontSize = mapper.adaptiveFontSize(forLineBoxes: lineBoxes)
                let (r, g, bl) = BackgroundSampler.sampleBackgroundColor(image: image, normalizedBox: b.visionBoundingBox)
                b.bgRed = r; b.bgGreen = g; b.bgBlue = bl
                return b
            }

            self.translatedBlocks = rendered

        } catch {
            print("全屏扫描错误: \(error)")
        }
    }

    // MARK: - 热键和引擎管理
    func startHotkeyMonitoring(with bindings: [HotkeyBinding]) {
        hotkeyManager.loadBindings(bindings)
    }

    func reloadEngines(from configs: [EngineConfig]) {
        translationManager.updateEngines(from: configs)
    }

    // MARK: - 语言检测
    static func detectLanguage(from texts: [String]) -> String {
        let combined = texts.joined(separator: " ")
        guard !combined.isEmpty else { return "en" }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(combined)
        guard let lang = recognizer.dominantLanguage else { return "en" }

        // NLLanguage → BCP-47 (Apple Translation / 通用 API)
        switch lang {
        case .simplifiedChinese: return "zh-Hans"
        case .traditionalChinese: return "zh-Hant"
        case .english: return "en"
        case .japanese: return "ja"
        case .korean: return "ko"
        case .french: return "fr"
        case .german: return "de"
        case .spanish: return "es"
        case .italian: return "it"
        case .portuguese: return "pt"
        case .russian: return "ru"
        case .dutch: return "nl"
        case .arabic: return "ar"
        case .thai: return "th"
        case .vietnamese: return "vi"
        default: return lang.rawValue
        }
    }
}

private struct DisplayedRegionScreenshotView: View {
    let baseImage: NSImage
    let blocks: [TranslatedBlock]
    let showingOriginal: Bool
    let localRegion: CGRect

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(nsImage: baseImage)
                .resizable()
                .interpolation(.high)
                .frame(width: localRegion.width, height: localRegion.height)

            ForEach(blocks) { block in
                let maxW = max(30, block.screenRect.width)
                let xOffset = clamp(
                    block.screenRect.minX - localRegion.minX,
                    min: 0,
                    max: max(0, localRegion.width - maxW)
                )
                let yOffset = max(0, block.screenRect.minY - localRegion.minY - 1)

                ForEach(Array(textCoverRects(for: block).enumerated()), id: \.offset) { _, rect in
                    background(for: block)
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX - localRegion.minX, y: rect.minY - localRegion.minY)
                }

                translatedLabel(for: block)
                    .frame(width: maxW, alignment: .topLeading)
                    .fixedSize(horizontal: false, vertical: true)
                    .background(background(for: block))
                    .offset(x: xOffset, y: yOffset)
            }
        }
        .frame(width: localRegion.width, height: localRegion.height, alignment: .topLeading)
        .clipped()
    }

    @ViewBuilder
    private func translatedLabel(for block: TranslatedBlock) -> some View {
        let displayText = showingOriginal
            ? block.originalText
            : (block.translatedText.isEmpty ? block.originalText : block.translatedText)

        Text(displayText.isEmpty ? "[空]" : displayText)
            .font(.system(size: block.fontSize, weight: .regular, design: .default))
            .foregroundStyle(textColor(for: block))
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .rotationEffect(block.isVertical ? .degrees(90) : .degrees(0))
    }

    private func background(for block: TranslatedBlock) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color(red: block.bgRed, green: block.bgGreen, blue: block.bgBlue))
    }

    private func textCoverRects(for block: TranslatedBlock) -> [CGRect] {
        let rects = block.screenLineRects.isEmpty ? [block.screenRect] : block.screenLineRects
        return rects.map {
            $0.insetBy(dx: -3, dy: -2)
        }
    }

    private func textColor(for block: TranslatedBlock) -> Color {
        let hasTextSample = block.textR > 0.01 || block.textG > 0.01 || block.textB > 0.01
        if hasTextSample {
            return Color(red: block.textR, green: block.textG, blue: block.textB)
        }
        return block.isLightBackground ? .black : .white
    }

    private func clamp(_ value: CGFloat, min lower: CGFloat, max upper: CGFloat) -> CGFloat {
        Swift.max(lower, Swift.min(upper, value))
    }
}
