import Foundation

protocol AIServiceProtocol {
    func getSuggestions(for items: [CleanupItem], enhancedContext: EnhancedAIContext?, learningPreferences: AILearningPreferences?) async throws -> [AISuggestion]
    func sendChatMessage(_ message: String, context: ChatContext?) async throws -> String
    var serviceType: AIServiceType { get }
}

struct ChatContext {
    let fileSystemInfo: FileSystemInfo?
    let enhancedContext: EnhancedAIContext?
    let conversationHistory: [ChatMessage]
    
    struct FileSystemInfo {
        let totalDiskSpace: Int64
        let availableDiskSpace: Int64
        let homeDirectoryContents: [String]
        let recentFiles: [String]
    }
}

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: MessageRole
    let content: String
    let timestamp: Date
    
    enum MessageRole {
        case user
        case assistant
    }
}

struct AIServiceFactory {
    static func createService(for type: AIServiceType, preferences: AppPreferences) -> any AIServiceProtocol {
        switch type {
        case .lmStudio:
            return LMStudioService(
                endpoint: preferences.lmStudioEndpoint,
                model: preferences.lmStudioModel
            )
        case .siriAI:
            return SiriAIService()
        }
    }
}

