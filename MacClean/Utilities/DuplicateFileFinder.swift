import Foundation

struct DuplicateFile: Identifiable {
    let id: UUID
    let path: URL
    let size: Int64
    let hash: String
    let groupID: UUID
    
    init(id: UUID = UUID(), path: URL, size: Int64, hash: String, groupID: UUID) {
        self.id = id
        self.path = path
        self.size = size
        self.hash = hash
        self.groupID = groupID
    }
}

@Observable
class DuplicateFileFinder {
    var duplicates: [UUID: [DuplicateFile]] = [:]
    var isScanning = false
    var progress: Double = 0.0
    var currentStatus = ""
    
    func findDuplicates(in directories: [URL], minSize: Int64 = 1024) async {
        await MainActor.run {
            isScanning = true
            progress = 0.0
            currentStatus = "Scanning files..."
            duplicates = [:]
        }
        
        var fileGroups: [String: [DuplicateFile]] = [:]
        var totalFiles = 0
        var processedFiles = 0
        
        // First pass: collect files by size
        var sizeGroups: [Int64: [URL]] = [:]
        
        for directory in directories {
            // Collect URLs synchronously to avoid async iterator issues
            let urls = await collectFileURLs(from: directory)
            
            for fileURL in urls {
                guard let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                      let isRegularFile = resourceValues.isRegularFile,
                      isRegularFile,
                      let size = resourceValues.fileSize,
                      Int64(size) >= minSize else {
                    continue
                }
                
                totalFiles += 1
                sizeGroups[Int64(size), default: []].append(fileURL)
            }
        }
        
        await MainActor.run {
            currentStatus = "Analyzing \(sizeGroups.count) file groups..."
        }
        
        // Second pass: hash files with same size
        for (size, urls) in sizeGroups where urls.count > 1 {
            for url in urls {
                if Task.isCancelled { return }
                
                do {
                    let hash = try await hashFile(at: url)
                    let duplicate = DuplicateFile(path: url, size: size, hash: hash, groupID: UUID())
                    
                    fileGroups[hash, default: []].append(duplicate)
                    
                    processedFiles += 1
                    await MainActor.run {
                        progress = Double(processedFiles) / Double(totalFiles)
                        currentStatus = "Processed \(processedFiles) of \(totalFiles) files..."
                    }
                } catch {
                    // Skip files that can't be hashed
                    continue
                }
            }
        }
        
        // Group duplicates
        var groupedDuplicates: [UUID: [DuplicateFile]] = [:]
        for (_, files) in fileGroups where files.count > 1 {
            let groupID = UUID()
            for var file in files {
                file = DuplicateFile(id: file.id, path: file.path, size: file.size, hash: file.hash, groupID: groupID)
                groupedDuplicates[groupID, default: []].append(file)
            }
        }
        
        await MainActor.run {
            duplicates = groupedDuplicates
            isScanning = false
            progress = 1.0
            currentStatus = "Found \(groupedDuplicates.count) duplicate groups"
        }
    }
    
    private func collectFileURLs(from directory: URL) async -> [URL] {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var urls: [URL] = []
                guard let enumerator = FileManager.default.enumerator(
                    at: directory,
                    includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
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
    
    private func hashFile(at url: URL) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let data = try Data(contentsOf: url)
                    let hash = data.hashValue.description
                    continuation.resume(returning: hash)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func deleteDuplicates(keeping: [DuplicateFile]) async throws -> (deleted: Int, spaceFreed: Int64) {
        var deleted = 0
        var spaceFreed: Int64 = 0
        
        let filesToKeep = Set(keeping.map { $0.id })
        
        for (_, group) in duplicates {
            for file in group where !filesToKeep.contains(file.id) {
                do {
                    try FileManager.default.removeItem(at: file.path)
                    deleted += 1
                    spaceFreed += file.size
                } catch {
                    // Continue with other files
                    print("Failed to delete \(file.path): \(error)")
                }
            }
        }
        
        return (deleted, spaceFreed)
    }
}

