import Foundation

struct OpenAICompatibleEngine: TranslationEngine {
    let engineType = EngineType.openAICompatible
    let configID: UUID
    let endpoint: String
    let modelID: String
    let apiKey: String
    let temperature: Double
    let systemPrompt: String
    let customPrompt: String

    init(config: EngineConfig) throws {
        self.configID = config.id
        guard let ep = config.endpointURL, !ep.isEmpty else {
            throw TranslationError.invalidEndpoint
        }
        guard let model = config.modelID, !model.isEmpty else {
            throw TranslationError.missingModelID
        }
        self.endpoint = ep
        self.modelID = model
        self.apiKey = config.apiKey
        self.temperature = config.temperature
        self.systemPrompt = config.systemPrompt
        self.customPrompt = config.customPrompt
    }

    private var chatCompletionsEndpoint: String {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if trimmed.hasSuffix("/chat/completions") {
            return trimmed
        }
        return "\(trimmed)/chat/completions"
    }

    private func buildSystemPrompt(from sourceLang: String, to targetLang: String) -> String {
        var parts = [systemPrompt]
        parts.append("Translate the following numbered texts from \(sourceLang) to \(targetLang). Return ONLY the translated texts in the same numbered format.")
        if !customPrompt.isEmpty {
            parts.append(customPrompt)
        }
        return parts.joined(separator: "\n\n")
    }

    func translate(texts: [String], from sourceLang: String, to targetLang: String) async throws -> [String] {
        let numbered = texts.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        let body: [String: Any] = [
            "model": modelID,
            "messages": [
                ["role": "system", "content": buildSystemPrompt(from: sourceLang, to: targetLang)],
                ["role": "user", "content": numbered]
            ],
            "temperature": temperature,
            "max_tokens": 2048
        ]
        let responseText = try await postJSON(to: chatCompletionsEndpoint, body: body, apiKey: apiKey)
        return parseNumberedResponse(responseText, expectedCount: texts.count)
    }

    func testConnection() async throws -> Bool {
        let body: [String: Any] = [
            "model": modelID,
            "messages": [["role": "user", "content": "Say OK"]],
            "max_tokens": 5
        ]
        _ = try await postJSON(to: chatCompletionsEndpoint, body: body, apiKey: apiKey)
        return true
    }

    private func postJSON(to urlString: String, body: [String: Any], apiKey: String) async throws -> String {
        guard let url = URL(string: urlString) else { throw TranslationError.invalidEndpoint }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TranslationError.networkError(URLError(.badServerResponse))
        }
        if http.statusCode == 429 { throw TranslationError.rateLimited }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw TranslationError.invalidResponse("HTTP \(http.statusCode): \(body)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw TranslationError.invalidResponse("无法解析 OpenAI 响应")
        }
        return content
    }
}
