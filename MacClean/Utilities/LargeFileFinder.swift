import Foundation
import SwiftUI

struct LargeFile: Identifiable {
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

@Observable
class LargeFileFinder {
    var largeFiles: [LargeFile] = []
    var isScanning = false
    var progress: Double = 0.0
    var currentStatus = ""
    
    func findLargeFiles(in directories: [URL], minSize: Int64 = 100_000_000) async {
        await MainActor.run {
            isScanning = true
            progress = 0.0
            currentStatus = "Scanning for large files..."
            largeFiles = []
        }
        
        var foundFiles: [LargeFile] = []
        var totalFiles = 0
        var processedFiles = 0
        
        // Count total files first
        for directory in directories {
            let urls = await collectFileURLs(from: directory, keys: [.isRegularFileKey])
            
            for fileURL in urls {
                guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                      let isRegularFile = resourceValues.isRegularFile,
                      isRegularFile else {
                    continue
                }
                totalFiles += 1
            }
        }
        
        // Scan for large files
        for directory in directories {
            let urls = await collectFileURLs(from: directory, keys: [.fileSizeKey, .isRegularFileKey, .contentModificationDateKey])
            
            for fileURL in urls {
                if Task.isCancelled { return }
                
                guard let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .contentModificationDateKey]),
                      let isRegularFile = resourceValues.isRegularFile,
                      isRegularFile,
                      let size = resourceValues.fileSize,
                      Int64(size) >= minSize else {
                    processedFiles += 1
                    await MainActor.run {
                        progress = Double(processedFiles) / Double(totalFiles)
                    }
                    continue
                }
                
                let largeFile = LargeFile(
                    path: fileURL,
                    size: Int64(size),
                    modifiedDate: resourceValues.contentModificationDate
                )
                foundFiles.append(largeFile)
                
                processedFiles += 1
                await MainActor.run {
                    progress = Double(processedFiles) / Double(totalFiles)
                    currentStatus = "Found \(foundFiles.count) large files..."
                }
            }
        }
        
        // Sort by size (largest first)
        foundFiles.sort { $0.size > $1.size }
        
        await MainActor.run {
            largeFiles = foundFiles
            isScanning = false
            progress = 1.0
            currentStatus = "Found \(foundFiles.count) large files"
        }
    }
    
    private func collectFileURLs(from directory: URL, keys: [URLResourceKey]) async -> [URL] {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var urls: [URL] = []
                guard let enumerator = FileManager.default.enumerator(
                    at: directory,
                    includingPropertiesForKeys: keys,
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                ) else {
                    continuation.resume(returning: [])
                    return
                }
                
                for case let fileURL as URL in enumerator {
                    urls.append(fileURL)
                }
                
                continuation.resume(returning: urls)
            }
        }
    }
    
    func deleteFiles(_ files: [LargeFile]) async throws -> (deleted: Int, spaceFreed: Int64) {
        var deleted = 0
        var spaceFreed: Int64 = 0
        
        for file in files {
            do {
                try FileManager.default.removeItem(at: file.path)
                deleted += 1
                spaceFreed += file.size
            } catch {
                print("Failed to delete \(file.path): \(error)")
            }
        }
        
        return (deleted, spaceFreed)
    }
}

