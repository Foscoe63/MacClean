import Foundation
import SwiftUI

nonisolated struct LargeFile: Identifiable, Hashable, Sendable {
    let id: UUID
    let path: URL
    let size: Int64
    let modifiedDate: Date?
    
    init(id: UUID = UUID(), path: URL, size: Int64, modifiedDate: Date? = nil) {
        self.id = id
        self.path = path
        self.size = size
        self.modifiedDate = modifiedDate
    }
    
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
    
    var fileName: String {
        path.lastPathComponent
    }
}

/// Finds the biggest files in the user's folders so they can be reviewed and moved to the Trash.
@Observable
class LargeFileFinder {
    var largeFiles: [LargeFile] = []
    var isScanning = false
    var currentStatus = ""
    
    func findLargeFiles(in directories: [URL], minSize: Int64 = 100_000_000) async {
        isScanning = true
        currentStatus = "Scanning for large files..."
        largeFiles = []
        
        let found = await LargeFileScanner.scan(directories, minSize: minSize)
        
        largeFiles = found
        isScanning = false
        let threshold = ByteCountFormatter.string(fromByteCount: minSize, countStyle: .file)
        currentStatus = found.isEmpty
            ? "No files larger than \(threshold)"
            : "Found \(found.count) files larger than \(threshold)"
    }
    
    /// Moves the chosen files to the Trash (never deletes permanently) and logs each one.
    /// - Returns: How many files were moved and how much space they take up.
    func moveToTrash(_ files: [LargeFile]) async -> (moved: Int, size: Int64) {
        let outcome = await LargeFileScanner.trash(files)
        DeletionLogManager.shared.logDeletions(outcome.logEntries)
        
        let trashedPaths = Set(outcome.logEntries.filter(\.success).map(\.filePath))
        largeFiles.removeAll { trashedPaths.contains($0.path.path) }
        return (outcome.itemsDeleted, outcome.spaceFreed)
    }
}

/// Background work for `LargeFileFinder`.
nonisolated enum LargeFileScanner {
    @concurrent
    static func scan(_ directories: [URL], minSize: Int64) async -> [LargeFile] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey, .contentModificationDateKey]
        var found: [LargeFile] = []
        
        for directory in directories {
            // Skip package contents so apps and libraries show up as their own items, not thousands of parts
            guard let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: nil
            ) else { continue }
            
            for case let fileURL as URL in enumerator {
                if Task.isCancelled { return found.sorted { $0.size > $1.size } }
                
                guard let values = try? fileURL.resourceValues(forKeys: Set(keys)),
                      values.isRegularFile == true else { continue }
                
                let size = Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
                if size >= minSize {
                    found.append(LargeFile(path: fileURL, size: size, modifiedDate: values.contentModificationDate))
                }
            }
        }
        
        return found.sorted { $0.size > $1.size }
    }
    
    @concurrent
    static func trash(_ files: [LargeFile]) async -> DeletionOutcome {
        var outcome = DeletionOutcome()
        for file in files {
            outcome.record(deleting: file.path, size: file.size, category: "Large Files") {
                var resultingURL: NSURL?
                try FileManager.default.trashItem(at: file.path, resultingItemURL: &resultingURL)
                return resultingURL.map { $0 as URL }
            }
        }
        return outcome
    }
}
