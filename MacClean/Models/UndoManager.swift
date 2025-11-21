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

class UndoManager {
    static let shared = UndoManager()
    
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
    
    func undoLastCleanup() -> Bool {
        guard let entry = undoEntries.first else {
            return false
        }
        
        let fileManager = FileManager.default
        var restoredCount = 0
        
        for fileInfo in entry.filesDeleted {
            // Try to restore from Trash if trash path is available
            if let trashPath = fileInfo.trashPath,
               fileManager.fileExists(atPath: trashPath) {
                do {
                    let trashURL = URL(fileURLWithPath: trashPath)
                    let originalURL = URL(fileURLWithPath: fileInfo.originalPath)
                    
                    // Create parent directory if it doesn't exist
                    try? fileManager.createDirectory(
                        at: originalURL.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    
                    // Move back from Trash
                    try fileManager.moveItem(at: trashURL, to: originalURL)
                    restoredCount += 1
                } catch {
                    print("Failed to restore \(fileInfo.originalPath): \(error)")
                }
            }
        }
        
        // Remove entry after attempting restore
        removeUndoEntry(entry)
        
        return restoredCount > 0
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

