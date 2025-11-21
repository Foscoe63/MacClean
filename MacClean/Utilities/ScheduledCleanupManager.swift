import Foundation
import UserNotifications

@Observable
class ScheduledCleanupManager {
    private let userDefaults = UserDefaults.standard
    private let scheduleKey = "com.macclean.scheduledCleanup"
    
    var isEnabled: Bool = false
    var frequency: CleanupFrequency = .weekly
    var scheduledTime: Date = Calendar.current.date(bySettingHour: 2, minute: 0, second: 0, of: Date()) ?? Date()
    var categories: Set<CleanupCategoryType> = []
    
    enum CleanupFrequency: String, Codable, CaseIterable {
        case daily = "Daily"
        case weekly = "Weekly"
        case monthly = "Monthly"
        
        var interval: TimeInterval {
            switch self {
            case .daily: return 24 * 60 * 60
            case .weekly: return 7 * 24 * 60 * 60
            case .monthly: return 30 * 24 * 60 * 60
            }
        }
    }
    
    init() {
        loadSchedule()
    }
    
    func enable() {
        isEnabled = true
        scheduleNextCleanup()
        saveSchedule()
    }
    
    func disable() {
        isEnabled = false
        cancelScheduledCleanup()
        saveSchedule()
    }
    
    func scheduleNextCleanup() {
        guard isEnabled else { return }
        
        // Cancel existing notifications
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["scheduledCleanup"])
        
        // Calculate next cleanup time
        let calendar = Calendar.current
        let now = Date()
        var nextDate = calendar.date(bySettingHour: calendar.component(.hour, from: scheduledTime),
                                     minute: calendar.component(.minute, from: scheduledTime),
                                     second: 0,
                                     of: now) ?? now
        
        // If the time has passed today, schedule for next period
        if nextDate <= now {
            switch frequency {
            case .daily:
                nextDate = calendar.date(byAdding: .day, value: 1, to: nextDate) ?? nextDate
            case .weekly:
                nextDate = calendar.date(byAdding: .day, value: 7, to: nextDate) ?? nextDate
            case .monthly:
                nextDate = calendar.date(byAdding: .month, value: 1, to: nextDate) ?? nextDate
            }
        }
        
        // Create notification trigger
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: nextDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        
        // Create notification
        let content = UNMutableNotificationContent()
        content.title = "Scheduled Cleanup"
        content.body = "It's time to clean your Mac! Click to start the cleanup process."
        content.sound = .default
        content.categoryIdentifier = "SCHEDULED_CLEANUP"
        
        let request = UNNotificationRequest(
            identifier: "scheduledCleanup",
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to schedule cleanup: \(error)")
            }
        }
    }
    
    private func cancelScheduledCleanup() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["scheduledCleanup"])
    }
    
    private func loadSchedule() {
        if let data = userDefaults.data(forKey: scheduleKey),
           let decoded = try? JSONDecoder().decode(ScheduledCleanupData.self, from: data) {
            self.isEnabled = decoded.isEnabled
            self.frequency = decoded.frequency
            self.scheduledTime = decoded.scheduledTime
            self.categories = Set(decoded.categories.compactMap { CleanupCategoryType(rawValue: $0) })
        }
    }
    
    private func saveSchedule() {
        let data = ScheduledCleanupData(
            isEnabled: isEnabled,
            frequency: frequency,
            scheduledTime: scheduledTime,
            categories: categories.map { $0.rawValue }
        )
        if let encoded = try? JSONEncoder().encode(data) {
            userDefaults.set(encoded, forKey: scheduleKey)
        }
    }
}

private struct ScheduledCleanupData: Codable {
    let isEnabled: Bool
    let frequency: ScheduledCleanupManager.CleanupFrequency
    let scheduledTime: Date
    let categories: [String]
}

