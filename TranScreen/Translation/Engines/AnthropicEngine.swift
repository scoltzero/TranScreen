import Foundation

struct AnthropicCompatibleEngine: TranslationEngine {
    let engineType = EngineType.anthropicCompatible
    let configID: UUID
    let endpoint: String
    let modelID: String
    let apiKey: String
    let temperature: Double
    let systemPrompt: String
    let customPrompt: String

    private static let apiVersion = "2023-06-01"

    init(config: EngineConfig) throws {
        self.configID = config.id
        guard let ep = config.endpointURL, !ep.isEmpty else {
            throw TranslationError.invalidEndpoint
        }
        guard let model = config.modelID, !model.isEmpty else {
            throw TranslationError.missingModelID
        }
        self.endpoint = Self.messagesEndpoint(from: ep)
        self.modelID = model
        self.apiKey = config.apiKey
        self.temperature = config.temperature
        self.systemPrompt = config.systemPrompt
        self.customPrompt = config.customPrompt
    }

    private func loadAPIKey() throws -> String {
        return apiKey
    }

    private static func messagesEndpoint(from endpoint: String) -> String {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if trimmed.hasSuffix("/messages") {
            return trimmed
        }
        if trimmed.hasSuffix("/v1") {
            return "\(trimmed)/messages"
        }
        return "\(trimmed)/v1/messages"
    }

    private func buildSystemPrompt(from sourceLang: String, to targetLang: String) -> String {
        var parts = [systemPrompt]
        parts.append("You are a professional translator. Translate the following numbered texts from \(sourceLang) to \(targetLang). Return ONLY the translated texts in the same numbered format.")
        if !customPrompt.isEmpty {
            parts.append(customPrompt)
        }
        return parts.joined(separator: "\n\n")
    }

    func translate(texts: [String], from sourceLang: String, to targetLang: String) async throws -> [String] {
        let apiKey = try loadAPIKey()
        let numbered = texts.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        let body: [String: Any] = [
            "model": modelID,
            "max_tokens": 2048,
            "temperature": temperature,
            "system": buildSystemPrompt(from: sourceLang, to: targetLang),
            "messages": [["role": "user", "content": numbered]]
        ]

        guard let url = URL(string: endpoint) else { throw TranslationError.invalidEndpoint }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TranslationError.networkError(URLError(.badServerResponse))
        }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw TranslationError.invalidResponse("HTTP \(http.statusCode): \(body)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let text = content.first?["text"] as? String else {
            throw TranslationError.invalidResponse("Anthropic 响应格式错误")
        }

        return parseNumberedResponse(text, expectedCount: texts.count)
    }

    func testConnection() async throws -> Bool {
        _ = try await translate(texts: ["Hello"], from: "en", to: "zh-Hans")
        return true
    }
}
