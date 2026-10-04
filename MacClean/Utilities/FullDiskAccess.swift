import AppKit

/// Detects whether MacClean has Full Disk Access, which some caches (Safari, Mail) and the Trash need.
enum FullDiskAccess {
    /// The TCC database is only readable by apps that have Full Disk Access.
    static var isGranted: Bool {
        let probe = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db")
        return FileManager.default.isReadableFile(atPath: probe.path)
    }
    
    /// Opens System Settings at Privacy & Security > Full Disk Access.
    static func openSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
        NSWorkspace.shared.open(url)
    }
}
