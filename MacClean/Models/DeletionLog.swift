import Foundation

nonisolated struct DeletionLogEntry: Codable, Identifiable, Sendable {
    let id: UUID
    let timestamp: Date
    let filePath: String
    let fileSize: Int64
    let category: String
    let success: Bool
    let errorMessage: String?
    /// Where the item landed in the Trash, so it can be put back. `nil` for permanent deletions.
    let trashPath: String?
    
    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        filePath: String,
        fileSize: Int64,
        category: String,
        success: Bool = true,
        errorMessage: String? = nil,
        trashPath: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.filePath = filePath
        self.fileSize = fileSize
        self.category = category
        self.success = success
        self.errorMessage = errorMessage
        self.trashPath = trashPath
    }
}

class DeletionLogManager {
    static let shared = DeletionLogManager()
    
    private let logFileName = "deletion_log.json"
    private var logFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent("MacClean", isDirectory: true)
        
        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)
        
        return appFolder.appendingPathComponent(logFileName)
    }
    
    private init() {}
    
    func logDeletion(
        filePath: String,
        fileSize: Int64,
        category: String,
        success: Bool = true,
        errorMessage: String? = nil,
        trashPath: String? = nil
    ) {
        logDeletions([
            DeletionLogEntry(
                filePath: filePath,
                fileSize: fileSize,
                category: category,
                success: success,
                errorMessage: errorMessage,
                trashPath: trashPath
            )
        ])
    }
    
    /// Appends a batch of entries with a single read and write of the log file.
    func logDeletions(_ newEntries: [DeletionLogEntry]) {
        guard !newEntries.isEmpty else { return }
        
        var entries = loadLogEntries()
        entries.append(contentsOf: newEntries)
        
        // Keep only last 10,000 entries to prevent log file from growing too large
        if entries.count > 10_000 {
            entries = Array(entries.suffix(10_000))
        }
        
        saveLogEntries(entries)
    }
    
    func getAllLogEntries() -> [DeletionLogEntry] {
        loadLogEntries()
    }
    
    func getLogEntries(since date: Date) -> [DeletionLogEntry] {
        loadLogEntries().filter { $0.timestamp >= date }
    }
    
    func getLogEntries(for category: String) -> [DeletionLogEntry] {
        loadLogEntries().filter { $0.category == category }
    }
    
    func getTotalSpaceFreed() -> Int64 {
        // Only count space freed from permanent deletions (not moved to Trash)
        // Note: This is an approximation - we can't distinguish moveToTrash vs permanent from logs alone
        // For accurate totals, use CleanupHistoryManager instead
        loadLogEntries()
            .filter { $0.success }
            .reduce(0) { $0 + $1.fileSize }
    }
    
    func getTotalFilesDeleted() -> Int {
        loadLogEntries().filter { $0.success }.count
    }
    
    func clearLog() {
        saveLogEntries([])
    }
    
    func exportLog(to url: URL) throws {
        let entries = loadLogEntries()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        let data = try encoder.encode(entries)
        try data.write(to: url)
    }
    
    private func loadLogEntries() -> [DeletionLogEntry] {
        let filePath = logFileURL.path
        
        guard FileManager.default.fileExists(atPath: filePath) else {
            return []
        }
        
        guard let data = try? Data(contentsOf: logFileURL) else {
            print("Failed to read deletion log file at: \(filePath)")
            return []
        }
        
        guard !data.isEmpty else {
            print("Deletion log file is empty")
            return []
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        do {
            return try decoder.decode([DeletionLogEntry].self, from: data)
        } catch {
            print("Failed to decode deletion log: \(error)")
            print("Log file path: \(filePath)")
            if let jsonString = String(data: data, encoding: .utf8) {
                print("Log file content (first 500 chars): \(String(jsonString.prefix(500)))")
            }
            return []
        }
    }
    
    private func saveLogEntries(_ entries: [DeletionLogEntry]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        do {
            let data = try encoder.encode(entries)
            try data.write(to: logFileURL)
        } catch {
            print("Failed to save deletion log: \(error)")
        }
    }
}

