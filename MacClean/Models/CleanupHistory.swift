import Foundation

struct CleanupHistoryEntry: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let categories: [String]
    let itemsDeleted: Int
    let spaceFreed: Int64
    let duration: TimeInterval
    let success: Bool
    
    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        categories: [String],
        itemsDeleted: Int,
        spaceFreed: Int64,
        duration: TimeInterval,
        success: Bool = true
    ) {
        self.id = id
        self.timestamp = timestamp
        self.categories = categories
        self.itemsDeleted = itemsDeleted
        self.spaceFreed = spaceFreed
        self.duration = duration
        self.success = success
    }
    
    var formattedSpaceFreed: String {
        ByteCountFormatter.string(fromByteCount: spaceFreed, countStyle: .file)
    }
    
    var formattedDuration: String {
        if duration < 60 {
            return String(format: "%.1f seconds", duration)
        } else {
            let minutes = Int(duration / 60)
            let seconds = Int(duration.truncatingRemainder(dividingBy: 60))
            return "\(minutes)m \(seconds)s"
        }
    }
}

@Observable
class CleanupHistoryManager {
    private let userDefaults = UserDefaults.standard
    private let historyKey = "com.macclean.cleanupHistory"
    private let maxEntries = 100
    
    var entries: [CleanupHistoryEntry] = []
    
    init() {
        loadHistory()
    }
    
    func addEntry(_ entry: CleanupHistoryEntry) {
        entries.insert(entry, at: 0)
        
        // Keep only the most recent entries
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        
        saveHistory()
    }
    
    func clearHistory() {
        entries = []
        saveHistory()
    }
    
    var totalSpaceFreed: Int64 {
        entries.reduce(0) { $0 + $1.spaceFreed }
    }
    
    var totalItemsDeleted: Int {
        entries.reduce(0) { $0 + $1.itemsDeleted }
    }
    
    func entriesForPeriod(days: Int) -> [CleanupHistoryEntry] {
        let cutoffDate = Date().addingTimeInterval(-TimeInterval(days * 24 * 60 * 60))
        return entries.filter { $0.timestamp >= cutoffDate }
    }
    
    var weeklyStats: (spaceFreed: Int64, itemsDeleted: Int) {
        let weekEntries = entriesForPeriod(days: 7)
        return (
            spaceFreed: weekEntries.reduce(0) { $0 + $1.spaceFreed },
            itemsDeleted: weekEntries.reduce(0) { $0 + $1.itemsDeleted }
        )
    }
    
    var monthlyStats: (spaceFreed: Int64, itemsDeleted: Int) {
        let monthEntries = entriesForPeriod(days: 30)
        return (
            spaceFreed: monthEntries.reduce(0) { $0 + $1.spaceFreed },
            itemsDeleted: monthEntries.reduce(0) { $0 + $1.itemsDeleted }
        )
    }
    
    private func loadHistory() {
        if let data = userDefaults.data(forKey: historyKey),
           let decoded = try? JSONDecoder().decode([CleanupHistoryEntry].self, from: data) {
            entries = decoded
        }
    }
    
    private func saveHistory() {
        if let encoded = try? JSONEncoder().encode(entries) {
            userDefaults.set(encoded, forKey: historyKey)
        }
    }
    
    func exportHistory() -> String {
        var csv = "Date,Time,Categories,Items Deleted,Space Freed,Duration,Success\n"
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd,HH:mm:ss"
        
        for entry in entries {
            let dateTime = formatter.string(from: entry.timestamp)
            let categories = entry.categories.joined(separator: "; ")
            let success = entry.success ? "Yes" : "No"
            
            csv += "\(dateTime),\"\(categories)\",\(entry.itemsDeleted),\(entry.spaceFreed),\(entry.formattedDuration),\(success)\n"
        }
        
        return csv
    }
}

