import Foundation

struct FileScanner {
    nonisolated static func scanFilesSync(at url: URL) -> [CleanupFile] {
        var files: [CleanupFile] = []
        let fileManager = FileManager.default
        
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles],
            errorHandler: nil
        ) else { return [] }
        
        for case let fileURL as URL in enumerator {
            let resources = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let size = Int64(resources?.fileSize ?? 0)
            let date = resources?.contentModificationDate ?? Date()
            
            files.append(CleanupFile(
                path: fileURL.path,
                size: size,
                modificationDate: date
            ))
        }
        return files
    }
}
