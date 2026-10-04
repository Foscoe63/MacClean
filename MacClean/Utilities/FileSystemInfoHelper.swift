import Foundation

class FileSystemInfoHelper {
    static func gatherFileSystemInfo() async -> ChatContext.FileSystemInfo? {
        let fileManager = FileManager.default
        
        // .userDirectory is /Users, so use the current user's home folder instead
        let homePath = fileManager.homeDirectoryForCurrentUser.path
        
        // Get total and available disk space
        var totalSpace: Int64 = 0
        var availableSpace: Int64 = 0
        
        if let diskSpace = DiskSpace.current() {
            totalSpace = diskSpace.total
            availableSpace = diskSpace.available
        }
        
        // Get home directory contents
        var homeContents: [String] = []
        if let contents = try? fileManager.contentsOfDirectory(atPath: homePath) {
            homeContents = contents.filter { !$0.hasPrefix(".") } // Filter hidden files
        }
        
        // Get recent files from common locations
        var recentFiles: [String] = []
        
        // Check Downloads folder
        if let downloadsURL = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first,
           let downloads = try? fileManager.contentsOfDirectory(at: downloadsURL, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) {
            let sortedDownloads = downloads.sorted { url1, url2 in
                let date1 = (try? url1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                let date2 = (try? url2.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                return date1 > date2
            }
            recentFiles.append(contentsOf: sortedDownloads.prefix(10).map { $0.lastPathComponent })
        }
        
        // Check Documents folder
        if let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first,
           let documents = try? fileManager.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) {
            let sortedDocuments = documents.sorted { url1, url2 in
                let date1 = (try? url1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                let date2 = (try? url2.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                return date1 > date2
            }
            recentFiles.append(contentsOf: sortedDocuments.prefix(5).map { $0.lastPathComponent })
        }
        
        return ChatContext.FileSystemInfo(
            totalDiskSpace: totalSpace,
            availableDiskSpace: availableSpace,
            homeDirectoryContents: homeContents,
            recentFiles: Array(recentFiles.prefix(15))
        )
    }
}

