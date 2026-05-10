import Foundation

enum TranslationError: Error, LocalizedError {
    case noAPIKey
    case invalidEndpoint
    case networkError(Error)
    case rateLimited
    case invalidResponse(String)
    case missingModelID
    case allEnginesFailed
    case notAvailable

    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "未配置 API Key"
        case .invalidEndpoint: return "Endpoint URL 无效"
        case .networkError(let e): return "网络错误: \(e.localizedDescription)"
        case .rateLimited: return "请求过于频繁"
        case .invalidResponse(let s): return "响应格式错误: \(s)"
        case .missingModelID: return "未配置 Model ID"
        case .allEnginesFailed: return "所有翻译引擎均失败"
        case .notAvailable: return "引擎不可用"
        }
    }
}

protocol TranslationEngine: Sendable {
    var engineType: EngineType { get }
    var configID: UUID { get }

    func translate(texts: [String], from sourceLang: String, to targetLang: String) async throws -> [String]
    func testConnection() async throws -> Bool
}

// 数字编号响应解析（所有 LLM 引擎共用）
func parseNumberedResponse(_ text: String, expectedCount: Int) -> [String] {
    var results = text.components(separatedBy: "\n")
        .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        .map { line -> String in
            // 移除 "1. " / "1) " / "1、" 格式前缀
            let pattern = #"^\d+[.)、]\s*"#
            return line.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        .filter { !$0.isEmpty }
    while results.count < expectedCount { results.append("") }
    return Array(results.prefix(expectedCount))
}
