import Foundation

struct AISuggestion: Identifiable, Codable {
    let id: UUID
    let category: CleanupCategoryType
    let reason: String
    let estimatedSpace: Int64? // in bytes
    let confidence: Double // 0.0 to 1.0
    let timestamp: Date
    
    init(
        id: UUID = UUID(),
        category: CleanupCategoryType,
        reason: String,
        estimatedSpace: Int64? = nil,
        confidence: Double = 0.5,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.category = category
        self.reason = reason
        self.estimatedSpace = estimatedSpace
        self.confidence = confidence
        self.timestamp = timestamp
    }
}

struct AISuggestionResponse {
    let suggestions: [AISuggestion]
    let source: AIServiceType
    let timestamp: Date
    
    init(
        suggestions: [AISuggestion],
        source: AIServiceType,
        timestamp: Date = Date()
    ) {
        self.suggestions = suggestions
        self.source = source
        self.timestamp = timestamp
    }
}

enum AIServiceType: String, Codable {
    case lmStudio = "lm_studio"
    case siriAI = "siri_ai"
}

