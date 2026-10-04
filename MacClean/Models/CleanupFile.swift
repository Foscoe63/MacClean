import Foundation

nonisolated struct CleanupFile: Identifiable, Codable, Equatable, Hashable, Sendable {
    let id: UUID
    let path: String
    let size: Int64
    let modificationDate: Date
    var isExcluded: Bool
    
    init(
        id: UUID = UUID(),
        path: String,
        size: Int64,
        modificationDate: Date,
        isExcluded: Bool = false
    ) {
        self.id = id
        self.path = path
        self.size = size
        self.modificationDate = modificationDate
        self.isExcluded = isExcluded
    }
    
    var url: URL {
        URL(fileURLWithPath: path)
    }
    
    var name: String {
        url.lastPathComponent
    }
}
