import Foundation

struct DeepLEngine: TranslationEngine {
    let engineType = EngineType.deepL
    let configID: UUID
    let apiKey: String

    init(config: EngineConfig) throws {
        self.configID = config.id
        self.apiKey = config.apiKey
    }

    private func loadAPIKey() throws -> (key: String, isFree: Bool) {
        guard !apiKey.isEmpty else {
            throw TranslationError.noAPIKey
        }
        return (apiKey, apiKey.hasSuffix(":fx"))
    }

    private func endpoint(isFree: Bool) -> String {
        isFree ? "https://api-free.deepl.com/v2/translate" : "https://api.deepl.com/v2/translate"
    }

    func translate(texts: [String], from sourceLang: String, to targetLang: String) async throws -> [String] {
        let (apiKey, isFree) = try loadAPIKey()
        guard let url = URL(string: endpoint(isFree: isFree)) else { throw TranslationError.invalidEndpoint }

        var components = URLComponents()
        components.queryItems = texts.map { URLQueryItem(name: "text", value: $0) }
        components.queryItems?.append(URLQueryItem(name: "source_lang", value: sourceLang.uppercased()))
        components.queryItems?.append(URLQueryItem(name: "target_lang", value: targetLang.uppercased()))

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("DeepL-Auth-Key \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = components.query?.data(using: .utf8)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TranslationError.networkError(URLError(.badServerResponse))
        }
        if http.statusCode == 456 { throw TranslationError.rateLimited }
        guard http.statusCode == 200 else {
            throw TranslationError.networkError(URLError(.badServerResponse))
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let translations = json["translations"] as? [[String: Any]] else {
            throw TranslationError.invalidResponse("DeepL 响应格式错误")
        }

        return translations.compactMap { $0["text"] as? String }
    }

    func testConnection() async throws -> Bool {
        _ = try await translate(texts: ["Hello"], from: "EN", to: "ZH")
        return true
    }
}
