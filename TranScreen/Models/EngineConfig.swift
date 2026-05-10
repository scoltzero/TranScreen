import SwiftData
import Foundation

enum EngineType: String, Codable, CaseIterable, Identifiable {
    case apple = "apple"
    case openAICompatible = "openai_compatible"
    case anthropicCompatible = "anthropic_compatible"
    case googleCompatible = "google_compatible"
    case deepL = "deepl"
    case ollama = "ollama"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .apple: return "Apple 翻译（离线）"
        case .openAICompatible: return "OpenAI Compatible"
        case .anthropicCompatible: return "Anthropic Compatible"
        case .googleCompatible: return "Google Compatible"
        case .deepL: return "DeepL"
        case .ollama: return "Ollama（本地）"
        }
    }

    var supportsAPIKey: Bool {
        switch self {
        case .apple, .ollama: return false
        default: return true
        }
    }

    var requiresAPIKey: Bool {
        switch self {
        case .deepL: return true
        case .apple, .openAICompatible, .anthropicCompatible, .googleCompatible, .ollama:
            return false
        }
    }

    var requiresEndpoint: Bool {
        switch self {
        case .openAICompatible, .anthropicCompatible, .googleCompatible, .ollama: return true
        default: return false
        }
    }

    var requiresModelID: Bool {
        switch self {
        case .openAICompatible, .anthropicCompatible, .googleCompatible, .ollama: return true
        default: return false
        }
    }

    var supportsTemperature: Bool {
        switch self {
        case .openAICompatible, .anthropicCompatible, .googleCompatible, .ollama: return true
        default: return false
        }
    }

    var supportsCustomPrompt: Bool {
        supportsTemperature
    }
}

@Model
final class EngineConfig {
    @Attribute(.unique) var id: UUID
    var displayName: String
    var engineTypeRaw: String
    var endpointURL: String?
    var modelID: String?
    var apiKey: String = ""
    var isEnabled: Bool
    var sortOrder: Int
    var createdAt: Date
    var temperature: Double = 0.3
    var systemPrompt: String = "你是一个有用的翻译助手"
    var customPrompt: String = ""

    var engineType: EngineType {
        get {
            switch engineTypeRaw {
            case "anthropic": return .anthropicCompatible
            case "gemini": return .googleCompatible
            default: return EngineType(rawValue: engineTypeRaw) ?? .openAICompatible
            }
        }
        set { engineTypeRaw = newValue.rawValue }
    }

    init(
        displayName: String,
        engineType: EngineType,
        endpointURL: String? = nil,
        modelID: String? = nil,
        apiKey: String = "",
        isEnabled: Bool = true,
        sortOrder: Int = 0,
        temperature: Double = 0.3,
        systemPrompt: String = "你是一个有用的翻译助手",
        customPrompt: String = ""
    ) {
        self.id = UUID()
        self.displayName = displayName
        self.engineTypeRaw = engineType.rawValue
        self.endpointURL = endpointURL
        self.modelID = modelID
        self.apiKey = apiKey
        self.isEnabled = isEnabled
        self.sortOrder = sortOrder
        self.createdAt = Date()
        self.temperature = temperature
        self.systemPrompt = systemPrompt
        self.customPrompt = customPrompt
    }
}
