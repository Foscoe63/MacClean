import Foundation
import SwiftUI

@Observable
class PreferencesManager {
    private let userDefaults = UserDefaults.standard
    private let preferencesKey = "com.macclean.preferences"
    private var saveTask: Task<Void, Never>?
    
    var preferences: AppPreferences {
        didSet {
            // Debounce saves to avoid excessive writes
            saveTask?.cancel()
            saveTask = Task {
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                if !Task.isCancelled {
                    savePreferences()
                }
            }
        }
    }
    
    init() {
        if let data = userDefaults.data(forKey: preferencesKey) {
            // Try to decode with new format first
            if let decoded = try? JSONDecoder().decode(AppPreferencesData.self, from: data) {
                self.preferences = decoded.toPreferences()
            } else {
                // Fallback: try decoding without totalSpaceFreed and set default
                self.preferences = AppPreferences()
            }
        } else {
            self.preferences = AppPreferences()
        }
        
        // Recalculate totalSpaceFreed from history to ensure accuracy
        // This fixes any incorrect values from before the moveToTrash fix
        let historyManager = CleanupHistoryManager()
        self.preferences.totalSpaceFreed = historyManager.totalSpaceFreed
    }
    
    private func savePreferences() {
        let data = AppPreferencesData(from: preferences)
        if let encoded = try? JSONEncoder().encode(data) {
            userDefaults.set(encoded, forKey: preferencesKey)
        }
    }
    
    func save() {
        savePreferences()
    }
    
    func resetToDefaults() {
        preferences = AppPreferences()
    }
}

