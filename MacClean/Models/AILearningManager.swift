import Foundation

struct SuggestionFeedback: Codable, Identifiable {
    let id: UUID
    let suggestionId: UUID
    let category: String
    let accepted: Bool
    let timestamp: Date
    let reason: String?
    
    init(
        id: UUID = UUID(),
        suggestionId: UUID,
        category: String,
        accepted: Bool,
        timestamp: Date = Date(),
        reason: String? = nil
    ) {
        self.id = id
        self.suggestionId = suggestionId
        self.category = category
        self.accepted = accepted
        self.timestamp = timestamp
        self.reason = reason
    }
}

@Observable
class AILearningManager {
    static let shared = AILearningManager()
    
    private let feedbackFileName = "ai_learning_feedback.json"
    private var feedbackFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent("MacClean", isDirectory: true)
        try? FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)
        return appFolder.appendingPathComponent(feedbackFileName)
    }
    
    private var feedbackHistory: [SuggestionFeedback] = []
    
    private init() {
        loadFeedbackHistory()
    }
    
    func recordFeedback(suggestionId: UUID, category: String, accepted: Bool, reason: String? = nil) {
        let feedback = SuggestionFeedback(
            suggestionId: suggestionId,
            category: category,
            accepted: accepted,
            reason: reason
        )
        feedbackHistory.append(feedback)
        
        // Keep only last 1000 entries
        if feedbackHistory.count > 1000 {
            feedbackHistory = Array(feedbackHistory.suffix(1000))
        }
        
        saveFeedbackHistory()
    }
    
    func getUserPreferences() -> AILearningPreferences {
        let categoryAcceptance: [String: Double] = Dictionary(
            grouping: feedbackHistory,
            by: { $0.category }
        ).mapValues { feedbacks in
            let accepted = feedbacks.filter { $0.accepted }.count
            return Double(accepted) / Double(feedbacks.count)
        }
        
        let preferredCategories = categoryAcceptance
            .filter { $0.value > 0.7 }
            .sorted { $0.value > $1.value }
            .map { $0.key }
        
        let avoidedCategories = categoryAcceptance
            .filter { $0.value < 0.3 }
            .sorted { $0.value < $1.value }
            .map { $0.key }
        
        return AILearningPreferences(
            preferredCategories: preferredCategories,
            avoidedCategories: avoidedCategories,
            categoryAcceptanceRates: categoryAcceptance,
            totalFeedbackCount: feedbackHistory.count,
            averageAcceptanceRate: calculateAverageAcceptanceRate()
        )
    }
    
    private func calculateAverageAcceptanceRate() -> Double {
        guard !feedbackHistory.isEmpty else { return 0.5 }
        let accepted = feedbackHistory.filter { $0.accepted }.count
        return Double(accepted) / Double(feedbackHistory.count)
    }
    
    private func loadFeedbackHistory() {
        guard FileManager.default.fileExists(atPath: feedbackFileURL.path),
              let data = try? Data(contentsOf: feedbackFileURL) else {
            feedbackHistory = []
            return
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        do {
            feedbackHistory = try decoder.decode([SuggestionFeedback].self, from: data)
        } catch {
            print("Failed to decode feedback history: \(error)")
            feedbackHistory = []
        }
    }
    
    private func saveFeedbackHistory() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        do {
            let data = try encoder.encode(feedbackHistory)
            try data.write(to: feedbackFileURL)
        } catch {
            print("Failed to save feedback history: \(error)")
        }
    }
}

struct AILearningPreferences {
    let preferredCategories: [String]
    let avoidedCategories: [String]
    let categoryAcceptanceRates: [String: Double]
    let totalFeedbackCount: Int
    let averageAcceptanceRate: Double
}




