import Foundation
import UserNotifications

@Observable
class NotificationService {
    static let shared = NotificationService()
    
    private init() {
        requestAuthorization()
    }
    
    private func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Notification authorization error: \(error)")
            }
        }
    }
    
    func sendCleanupCompleteNotification(spaceFreed: Int64, itemsDeleted: Int, movedToTrash: Bool = false) {
        let content = UNMutableNotificationContent()
        content.title = "Cleanup Complete"
        if movedToTrash {
            content.body = "Moved \(itemsDeleted) items to Trash. Empty Trash to free up space."
        } else {
            content.body = "Freed \(ByteCountFormatter.string(fromByteCount: spaceFreed, countStyle: .file)) by deleting \(itemsDeleted) items"
        }
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request)
    }
    
    func sendScanCompleteNotification(itemsFound: Int, totalSize: Int64) {
        let content = UNMutableNotificationContent()
        content.title = "Scan Complete"
        content.body = "Found \(itemsFound) items totaling \(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file))"
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request)
    }
    
    func sendAISuggestionsNotification(count: Int) {
        let content = UNMutableNotificationContent()
        content.title = "AI Suggestions Ready"
        content.body = "\(count) cleanup suggestions available"
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request)
    }
}

