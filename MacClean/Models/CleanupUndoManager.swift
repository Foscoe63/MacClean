import Foundation

struct UndoEntry: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let category: String
    let filesDeleted: [DeletedFileInfo]
    let spaceFreed: Int64
    
    struct DeletedFileInfo: Codable {
        let originalPath: String
        let trashPath: String?
        let size: Int64
    }
}

/// Tracks cleanups that moved items to the Trash so they can be put back.
/// Named to avoid clashing with Foundation's `UndoManager`.
class CleanupUndoManager {
    static let shared = CleanupUndoManager()
    
    private let undoFileName = "undo_history.json"
    private var undoFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent("MacClean", isDirectory: true)
        try? FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)
        return appFolder.appendingPathComponent(undoFileName)
    }
    
    private var undoEntries: [UndoEntry] = []
    
    private init() {
        loadUndoEntries()
    }
    
    func addUndoEntry(category: String, filesDeleted: [UndoEntry.DeletedFileInfo], spaceFreed: Int64) {
        let entry = UndoEntry(
            id: UUID(),
            timestamp: Date(),
            category: category,
            filesDeleted: filesDeleted,
            spaceFreed: spaceFreed
        )
        
        undoEntries.insert(entry, at: 0) // Add to beginning
        
        // Keep only last 10 entries
        if undoEntries.count > 10 {
            undoEntries = Array(undoEntries.prefix(10))
        }
        
        saveUndoEntries()
    }
    
    func getLatestUndoEntry() -> UndoEntry? {
        undoEntries.first
    }
    
    func getAllUndoEntries() -> [UndoEntry] {
        undoEntries
    }
    
    func removeUndoEntry(_ entry: UndoEntry) {
        undoEntries.removeAll { $0.id == entry.id }
        saveUndoEntries()
    }
    
    func clearUndoHistory() {
        undoEntries.removeAll()
        saveUndoEntries()
    }
    
    /// Moves the latest cleanup's items from the Trash back to where they were.
    /// - Returns: How many items were restored and how many could not be.
    func undoLastCleanup() -> (restored: Int, failed: Int) {
        guard let entry = undoEntries.first else {
            return (0, 0)
        }
        
        let fileManager = FileManager.default
        var restoredCount = 0
        var failedCount = 0
        
        for fileInfo in entry.filesDeleted {
            guard let trashPath = fileInfo.trashPath,
                  fileManager.fileExists(atPath: trashPath) else {
                // Already emptied from the Trash or never trashed
                failedCount += 1
                continue
            }
            
            let trashURL = URL(fileURLWithPath: trashPath)
            let originalURL = URL(fileURLWithPath: fileInfo.originalPath)
            
            // Never overwrite something that has been recreated at the original location
            guard !fileManager.fileExists(atPath: originalURL.path) else {
                failedCount += 1
                continue
            }
            
            do {
                try fileManager.createDirectory(
                    at: originalURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try fileManager.moveItem(at: trashURL, to: originalURL)
                restoredCount += 1
            } catch {
                print("Failed to restore \(fileInfo.originalPath): \(error)")
                failedCount += 1
            }
        }
        
        removeUndoEntry(entry)
        return (restoredCount, failedCount)
    }
    
    private func loadUndoEntries() {
        guard FileManager.default.fileExists(atPath: undoFileURL.path),
              let data = try? Data(contentsOf: undoFileURL) else {
            undoEntries = []
            return
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        do {
            undoEntries = try decoder.decode([UndoEntry].self, from: data)
        } catch {
            print("Failed to decode undo history: \(error)")
            undoEntries = []
        }
    }
    
    private func saveUndoEntries() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        do {
            let data = try encoder.encode(undoEntries)
            try data.write(to: undoFileURL)
        } catch {
            print("Failed to save undo history: \(error)")
        }
    }
}

