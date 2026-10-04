import Foundation

struct FileScanner {
    /// Lists regular files only. Folders are left out on purpose: deleting a folder would also
    /// delete any file inside it that the user excluded in the preview.
    nonisolated static func scanFilesSync(at url: URL) -> [CleanupFile] {
        var files: [CleanupFile] = []
        let fileManager = FileManager.default
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles],
            errorHandler: nil
        ) else { return [] }
        
        for case let fileURL as URL in enumerator {
            guard let resources = try? fileURL.resourceValues(forKeys: Set(keys)),
                  resources.isRegularFile == true else {
                continue
            }
            
            files.append(CleanupFile(
                path: fileURL.path,
                size: Int64(resources.fileSize ?? 0),
                modificationDate: resources.contentModificationDate ?? Date()
            ))
        }
        return files
    }
}
