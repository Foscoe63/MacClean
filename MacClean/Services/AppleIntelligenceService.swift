import Foundation
import FoundationModels

/// On-device suggestions and chat through Apple Intelligence (the Foundation Models framework).
/// Nothing leaves the Mac. When the model is unavailable (unsupported Mac, Apple Intelligence
/// turned off, or the model still downloading) it falls back to MacClean's built-in tips.
struct AppleIntelligenceService: AIServiceProtocol {
    let serviceType: AIServiceType = .siriAI
    private let fallback = SiriAIService()
    
    static var isModelAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability {
            return true
        }
        return false
    }
    
    /// A short explanation for Settings of why the on-device model can or cannot be used.
    static var availabilityDescription: String {
        switch SystemLanguageModel.default.availability {
        case .available:
            return "Apple Intelligence is ready. Suggestions and chat run entirely on this Mac."
        case .unavailable(.deviceNotEligible):
            return "This Mac doesn't support Apple Intelligence, so MacClean uses its built-in tips."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Turn on Apple Intelligence in System Settings to get on-device suggestions. Until then MacClean uses its built-in tips."
        case .unavailable(.modelNotReady):
            return "The Apple Intelligence model is still downloading. MacClean uses its built-in tips until it's ready."
        case .unavailable:
            return "Apple Intelligence is unavailable, so MacClean uses its built-in tips."
        }
    }
    
    func getSuggestions(for items: [CleanupItem], enhancedContext: EnhancedAIContext?, learningPreferences: AILearningPreferences?) async throws -> [AISuggestion] {
        guard Self.isModelAvailable, !items.isEmpty else {
            return try await fallback.getSuggestions(for: items, enhancedContext: enhancedContext, learningPreferences: learningPreferences)
        }
        
        let categoryLines = items.map { item in
            let size = ByteCountFormatter.string(fromByteCount: item.estimatedSize ?? 0, countStyle: .file)
            let note = item.category.riskLevel.warningText.map { " (\($0))" } ?? ""
            return "- \(item.category.rawValue): \(item.name), \(size)\(note)"
        }
        var prompt = "Scan results on this Mac:\n" + categoryLines.joined(separator: "\n")
        if let context = enhancedContext {
            prompt += "\n\nDisk usage: \(Int(context.systemHealthMetrics.diskUsagePercent))%."
            if let days = context.systemHealthMetrics.daysSinceLastCleanup {
                prompt += " Last cleanup: \(days) days ago."
            }
        }
        if let preferences = learningPreferences, !preferences.avoidedCategories.isEmpty {
            prompt += "\nThe user usually rejects suggestions for: \(preferences.avoidedCategories.joined(separator: ", "))."
        }
        prompt += "\n\nRecommend up to five categories to clean, most useful first."
        
        let session = LanguageModelSession(instructions: """
            You help people free up disk space on a Mac. Recommend only categories from the list you are given, \
            using their identifier exactly as written before the colon. Prefer large caches that apps rebuild. \
            Only suggest personal files such as Downloads or device backups with a clear warning.
            """)
        let response = try await session.respond(to: prompt, generating: GeneratedCleanupPlan.self)
        
        let itemsByCategory = Dictionary(items.map { ($0.category, $0) }, uniquingKeysWith: { first, _ in first })
        let suggestions = response.content.suggestions.prefix(5).compactMap { generated -> AISuggestion? in
            guard let category = CleanupCategoryType(rawValue: generated.categoryID),
                  let item = itemsByCategory[category] else {
                return nil
            }
            return AISuggestion(
                category: category,
                reason: generated.reason,
                estimatedSpace: item.estimatedSize,
                confidence: min(1, max(0, generated.confidence))
            )
        }
        
        // An empty or unusable answer still gives the user something helpful
        if suggestions.isEmpty {
            return try await fallback.getSuggestions(for: items, enhancedContext: enhancedContext, learningPreferences: learningPreferences)
        }
        return suggestions
    }
    
    func sendChatMessage(_ message: String, context: ChatContext?) async throws -> String {
        guard Self.isModelAvailable else {
            return try await fallback.sendChatMessage(message, context: context)
        }
        
        var instructions = "You are MacClean's assistant. Help people understand their Mac's storage and clean up safely. Keep answers short and practical. Never claim to have deleted anything yourself."
        if let info = context?.fileSystemInfo {
            let available = ByteCountFormatter.string(fromByteCount: info.availableDiskSpace, countStyle: .file)
            let total = ByteCountFormatter.string(fromByteCount: info.totalDiskSpace, countStyle: .file)
            instructions += " The disk has \(available) free of \(total)."
        }
        
        // Replay recent turns so follow-up questions have context
        let history = (context?.conversationHistory ?? []).suffix(6).map { turn in
            "\(turn.role == .user ? "User" : "Assistant"): \(turn.content)"
        }
        let prompt = history.isEmpty
            ? message
            : history.joined(separator: "\n") + "\nUser: " + message
        
        let session = LanguageModelSession(instructions: instructions)
        return try await session.respond(to: prompt).content
    }
}

@Generable
nonisolated struct GeneratedCleanupPlan {
    @Guide(description: "Cleanup recommendations, most useful first.")
    let suggestions: [GeneratedSuggestion]
}

@Generable
nonisolated struct GeneratedSuggestion {
    @Guide(description: "The category identifier exactly as listed before the colon, for example user_caches.")
    let categoryID: String
    @Guide(description: "One or two sentences on why cleaning it helps and anything to be careful about.")
    let reason: String
    @Guide(description: "How confident you are that cleaning this is safe and useful, from 0.0 to 1.0.")
    let confidence: Double
}
