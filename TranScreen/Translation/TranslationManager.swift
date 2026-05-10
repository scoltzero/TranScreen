import Foundation

@MainActor
final class TranslationManager: ObservableObject {
    private let cache = TranslationCache()
    private var engines: [any TranslationEngine] = []

    func updateEngines(from configs: [EngineConfig]) {
        engines = configs
            .filter { $0.isEnabled }
            .sorted { $0.sortOrder < $1.sortOrder }
            .compactMap { config in
                do { return try buildEngine(from: config) } catch {
                    print("构建引擎 \(config.displayName) 失败: \(error)")
                    return nil
                }
            }
    }

    func translate(
        blocks: [MergedTextBlock],
        from sourceLang: String,
        to targetLang: String
    ) async throws -> [TranslatedBlock] {
        let texts = blocks.map(\.text)
        let translations = try await translateTexts(texts, from: sourceLang, to: targetLang)

        return zip(blocks, translations).map { block, translation in
            TranslatedBlock(
                originalText: block.text,
                translatedText: translation,
                visionBoundingBox: block.boundingBox,
                isVertical: block.isVertical
            )
        }
    }

    private func translateTexts(_ texts: [String], from source: String, to target: String) async throws -> [String] {
        var results = [String](repeating: "", count: texts.count)
        var uncachedIndices: [Int] = []
        var uncachedTexts: [String] = []

        for (i, text) in texts.enumerated() {
            if let cached = await cache.get(text, from: source, to: target) {
                results[i] = cached
            } else {
                uncachedIndices.append(i)
                uncachedTexts.append(text)
            }
        }

        guard !uncachedTexts.isEmpty else { return results }

        var lastError: Error = TranslationError.allEnginesFailed
        for engine in engines {
            do {
                let translated = try await engine.translate(texts: uncachedTexts, from: source, to: target)
                for (i, (text, translation)) in zip(uncachedTexts, translated).enumerated() {
                    await cache.set(text, translation: translation, from: source, to: target)
                    results[uncachedIndices[i]] = translation
                }
                return results
            } catch {
                lastError = error
                print("引擎 \(engine.engineType.displayName) 失败: \(error), 降级...")
                continue
            }
        }

        throw lastError
    }

    private func buildEngine(from config: EngineConfig) throws -> any TranslationEngine {
        switch config.engineType {
        case .apple:
            return AppleTranslationEngine(configID: config.id)
        case .openAICompatible:
            return try OpenAICompatibleEngine(config: config)
        case .anthropicCompatible:
            return try AnthropicCompatibleEngine(config: config)
        case .googleCompatible:
            return try GoogleCompatibleEngine(config: config)
        case .deepL:
            return try DeepLEngine(config: config)
        case .ollama:
            return try OllamaEngine(config: config)
        }
    }
}
