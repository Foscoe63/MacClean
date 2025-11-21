import Foundation
import SwiftUI

@Observable
@MainActor
class AppPreferences {
    var enabledCategories: Set<CleanupCategoryType>
    var aiServiceType: AIServiceType
    var lmStudioEndpoint: String
    var lmStudioModel: String
    var siriAIEnabled: Bool
    var requireConfirmation: Bool
    var showNotifications: Bool
    var autoScanOnLaunch: Bool
    var totalSpaceFreed: Int64 // Cumulative total space freed in bytes
    var sizeThresholdWarningGB: Double // Size threshold in GB to show warning (0 = disabled)
    var moveToTrash: Bool // Move files to Trash instead of permanent deletion
    
    init(
        enabledCategories: Set<CleanupCategoryType> = Set(CleanupCategoryType.allCases),
        aiServiceType: AIServiceType = .lmStudio,
        lmStudioEndpoint: String = "http://localhost:1234/v1",
        lmStudioModel: String = "",
        siriAIEnabled: Bool = true,
        requireConfirmation: Bool = true,
        showNotifications: Bool = true,
        autoScanOnLaunch: Bool = false,
        totalSpaceFreed: Int64 = 0,
        sizeThresholdWarningGB: Double = 10.0, // Default: warn if deleting more than 10GB
        moveToTrash: Bool = true // Default: move to Trash for safety
    ) {
        self.enabledCategories = enabledCategories
        self.aiServiceType = aiServiceType
        self.lmStudioEndpoint = lmStudioEndpoint
        self.lmStudioModel = lmStudioModel
        self.siriAIEnabled = siriAIEnabled
        self.requireConfirmation = requireConfirmation
        self.showNotifications = showNotifications
        self.autoScanOnLaunch = autoScanOnLaunch
        self.totalSpaceFreed = totalSpaceFreed
        self.sizeThresholdWarningGB = sizeThresholdWarningGB
        self.moveToTrash = moveToTrash
    }
    
    var formattedTotalSpaceFreed: String {
        ByteCountFormatter.string(fromByteCount: totalSpaceFreed, countStyle: .file)
    }
}

// Codable representation for persistence
// Marked as nonisolated to allow use in FileDocument contexts
nonisolated struct AppPreferencesData: Codable {
    let enabledCategories: [String]
    let aiServiceType: String
    let lmStudioEndpoint: String
    let lmStudioModel: String
    let siriAIEnabled: Bool
    let requireConfirmation: Bool
    let showNotifications: Bool
    let autoScanOnLaunch: Bool
    let totalSpaceFreed: Int64?
    let sizeThresholdWarningGB: Double?
    let moveToTrash: Bool?
    
    nonisolated init(
        enabledCategories: [String],
        aiServiceType: String,
        lmStudioEndpoint: String,
        lmStudioModel: String,
        siriAIEnabled: Bool,
        requireConfirmation: Bool,
        showNotifications: Bool,
        autoScanOnLaunch: Bool,
        totalSpaceFreed: Int64?,
        sizeThresholdWarningGB: Double?,
        moveToTrash: Bool?
    ) {
        self.enabledCategories = enabledCategories
        self.aiServiceType = aiServiceType
        self.lmStudioEndpoint = lmStudioEndpoint
        self.lmStudioModel = lmStudioModel
        self.siriAIEnabled = siriAIEnabled
        self.requireConfirmation = requireConfirmation
        self.showNotifications = showNotifications
        self.autoScanOnLaunch = autoScanOnLaunch
        self.totalSpaceFreed = totalSpaceFreed
        self.sizeThresholdWarningGB = sizeThresholdWarningGB
        self.moveToTrash = moveToTrash
    }
    
    @MainActor
    init(from preferences: AppPreferences) {
        self.enabledCategories = preferences.enabledCategories.map { $0.rawValue }
        self.aiServiceType = preferences.aiServiceType.rawValue
        self.lmStudioEndpoint = preferences.lmStudioEndpoint
        self.lmStudioModel = preferences.lmStudioModel
        self.siriAIEnabled = preferences.siriAIEnabled
        self.requireConfirmation = preferences.requireConfirmation
        self.showNotifications = preferences.showNotifications
        self.autoScanOnLaunch = preferences.autoScanOnLaunch
        self.totalSpaceFreed = preferences.totalSpaceFreed
        self.sizeThresholdWarningGB = preferences.sizeThresholdWarningGB
        self.moveToTrash = preferences.moveToTrash
    }
    
    @MainActor
    func toPreferences() -> AppPreferences {
        AppPreferences(
            enabledCategories: Set(enabledCategories.compactMap { CleanupCategoryType(rawValue: $0) }),
            aiServiceType: AIServiceType(rawValue: aiServiceType) ?? .lmStudio,
            lmStudioEndpoint: lmStudioEndpoint,
            lmStudioModel: lmStudioModel,
            siriAIEnabled: siriAIEnabled,
            requireConfirmation: requireConfirmation,
            showNotifications: showNotifications,
            autoScanOnLaunch: autoScanOnLaunch,
            totalSpaceFreed: totalSpaceFreed ?? 0,
            sizeThresholdWarningGB: sizeThresholdWarningGB ?? 10.0,
            moveToTrash: moveToTrash ?? true
        )
    }
}

