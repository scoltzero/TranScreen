import Foundation

struct GoogleCompatibleEngine: TranslationEngine {
    let engineType = EngineType.googleCompatible
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

    private func loadAPIKey() throws -> String {
        return apiKey
    }

    private func generateContentURL(apiKey: String) throws -> URL {
        var urlString = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if urlString.contains("{model}") {
            urlString = urlString.replacingOccurrences(of: "{model}", with: modelID)
        } else if !urlString.contains(":generateContent") {
            urlString = urlString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if urlString.hasSuffix("/v1") || urlString.hasSuffix("/v1beta") {
                urlString += "/models/\(modelID):generateContent"
            } else {
                urlString += "/v1beta/models/\(modelID):generateContent"
            }
        }

        guard var components = URLComponents(string: urlString) else {
            throw TranslationError.invalidEndpoint
        }
        if !apiKey.isEmpty {
            var items = components.queryItems ?? []
            if !items.contains(where: { $0.name == "key" }) {
                items.append(URLQueryItem(name: "key", value: apiKey))
            }
            components.queryItems = items
        }
        guard let url = components.url else {
            throw TranslationError.invalidEndpoint
        }
        return url
    }

    private func buildSystemPrompt(from sourceLang: String, to targetLang: String) -> String {
        var parts = [systemPrompt]
        parts.append("Translate from \(sourceLang) to \(targetLang). Return ONLY numbered translations.")
        if !customPrompt.isEmpty {
            parts.append(customPrompt)
        }
        return parts.joined(separator: "\n\n")
    }

    func translate(texts: [String], from sourceLang: String, to targetLang: String) async throws -> [String] {
        let apiKey = try loadAPIKey()
        let url = try generateContentURL(apiKey: apiKey)

        let numbered = texts.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        let fullPrompt = "\(buildSystemPrompt(from: sourceLang, to: targetLang))\n\n\(numbered)"

        let body: [String: Any] = [
            "contents": [["parts": [["text": fullPrompt]]]],
            "generationConfig": ["temperature": temperature, "maxOutputTokens": 2048]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
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
              let candidates = json["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String else {
            throw TranslationError.invalidResponse("Gemini 响应格式错误")
        }

        return parseNumberedResponse(text, expectedCount: texts.count)
    }

    func testConnection() async throws -> Bool {
        _ = try await translate(texts: ["Hello"], from: "en", to: "zh-Hans")
        return true
    }
}
