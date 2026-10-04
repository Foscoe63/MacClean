import Foundation

struct CleanupItem: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var description: String
    var category: CleanupCategoryType
    var isEnabled: Bool
    var requiresAdmin: Bool
    var estimatedSize: Int64? // in bytes
    
    init(
        id: UUID = UUID(),
        name: String,
        description: String,
        category: CleanupCategoryType,
        isEnabled: Bool = true,
        requiresAdmin: Bool = false,
        estimatedSize: Int64? = nil,
        files: [CleanupFile]? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.category = category
        self.isEnabled = isEnabled
        self.requiresAdmin = requiresAdmin
        self.estimatedSize = estimatedSize
        self.files = files
    }
    
    var files: [CleanupFile]?
}

enum CleanupCategoryType: String, Codable, CaseIterable {
    case userCaches = "user_caches"
    case systemCaches = "system_caches"
    case userLogs = "user_logs"
    case systemLogs = "system_logs"
    case safariCache = "safari_cache"
    case chromeCache = "chrome_cache"
    case firefoxCache = "firefox_cache"
    case downloads = "downloads"
    case trash = "trash"
    // Developer tools
    case xcodeDerivedData = "xcode_derived_data"
    case xcodeArchives = "xcode_archives"
    case npmCache = "npm_cache"
    case cocoapodsCache = "cocoapods_cache"
    case homebrewCache = "homebrew_cache"
    case swiftPMCache = "swiftpm_cache"
    case simulatorCaches = "simulator_caches"
    case xcodeDeviceSupport = "xcode_device_support"
    case gradleCache = "gradle_cache"
    case pipCache = "pip_cache"
    case yarnCache = "yarn_cache"
    // More browsers
    case edgeCache = "edge_cache"
    case braveCache = "brave_cache"
    // Application-specific
    case spotifyCache = "spotify_cache"
    case slackCache = "slack_cache"
    case zoomCache = "zoom_cache"
    // System maintenance
    case iosBackups = "ios_backups"
    
    var displayName: String {
        switch self {
        case .userCaches: return "User Caches"
        case .systemCaches: return "System Caches"
        case .userLogs: return "User Logs"
        case .systemLogs: return "System Logs"
        case .safariCache: return "Safari Cache"
        case .chromeCache: return "Chrome Cache"
        case .firefoxCache: return "Firefox Cache"
        case .downloads: return "Downloads Folder"
        case .trash: return "Trash"
        case .xcodeDerivedData: return "Xcode Derived Data"
        case .xcodeArchives: return "Xcode Archives"
        case .npmCache: return "npm Cache"
        case .cocoapodsCache: return "CocoaPods Cache"
        case .homebrewCache: return "Homebrew Cache"
        case .swiftPMCache: return "Swift Package Manager Cache"
        case .simulatorCaches: return "Simulator Caches"
        case .xcodeDeviceSupport: return "Xcode Device Support"
        case .gradleCache: return "Gradle Cache"
        case .pipCache: return "pip Cache"
        case .yarnCache: return "Yarn Cache"
        case .edgeCache: return "Edge Cache"
        case .braveCache: return "Brave Cache"
        case .spotifyCache: return "Spotify Cache"
        case .slackCache: return "Slack Cache"
        case .zoomCache: return "Zoom Cache"
        case .iosBackups: return "iOS Backups"
        }
    }
    
    var description: String {
        switch self {
        case .userCaches: return "Application caches in your user library"
        case .systemCaches: return "System-wide application caches"
        case .userLogs: return "Application logs in your user library"
        case .systemLogs: return "Rotated and archived system logs"
        case .safariCache: return "Safari browser cache and temporary files"
        case .chromeCache: return "Google Chrome browser cache"
        case .firefoxCache: return "Mozilla Firefox browser cache"
        case .downloads: return "Files in your Downloads folder"
        case .trash: return "Items in the Trash"
        case .xcodeDerivedData: return "Xcode build artifacts and derived data"
        case .xcodeArchives: return "Old Xcode archive files"
        case .npmCache: return "npm package manager cache"
        case .cocoapodsCache: return "CocoaPods dependency cache"
        case .homebrewCache: return "Homebrew package cache"
        case .swiftPMCache: return "Downloaded Swift packages, fetched again on the next build"
        case .simulatorCaches: return "iOS Simulator caches"
        case .xcodeDeviceSupport: return "Debug symbols for devices you have connected; re-copied when a device is plugged in"
        case .gradleCache: return "Gradle build and dependency cache"
        case .pipCache: return "Python pip download cache"
        case .yarnCache: return "Yarn package cache"
        case .edgeCache: return "Microsoft Edge browser cache"
        case .braveCache: return "Brave browser cache"
        case .spotifyCache: return "Spotify application cache"
        case .slackCache: return "Slack application cache"
        case .zoomCache: return "Zoom application cache"
        case .iosBackups: return "All iPhone and iPad backups stored on this Mac"
        }
    }

    /// How much care a category needs before it is cleaned.
    var riskLevel: CleanupRiskLevel {
        switch self {
        case .userCaches, .userLogs, .safariCache, .chromeCache, .firefoxCache,
             .xcodeDerivedData, .npmCache, .cocoapodsCache, .homebrewCache,
             .swiftPMCache, .simulatorCaches, .gradleCache, .pipCache, .yarnCache,
             .edgeCache, .braveCache, .spotifyCache, .slackCache, .zoomCache:
            return .safe
        case .systemCaches, .systemLogs, .trash, .xcodeArchives, .xcodeDeviceSupport:
            return .review
        case .downloads, .iosBackups:
            return .personalData
        }
    }

    /// Categories cleaned through an administrator-authorized shell command.
    var requiresAdminCleanup: Bool {
        self == .systemCaches || self == .systemLogs
    }

    /// Categories selected for cleaning when the user has not chosen otherwise.
    static var safeDefaults: Set<CleanupCategoryType> {
        Set(allCases.filter { $0.riskLevel == .safe })
    }
}

/// Risk classification used to decide what may be pre-selected and what needs an explicit opt-in.
enum CleanupRiskLevel: Sendable {
    /// Regenerable data such as caches and logs. Safe to pre-select.
    case safe
    /// Data that is usually safe to remove but cannot be regenerated (Trash, archives) or needs admin rights.
    case review
    /// The user's own files. Never pre-selected; always called out before cleaning.
    case personalData

    var warningText: String? {
        switch self {
        case .safe: return nil
        case .review: return "Cannot be regenerated once removed"
        case .personalData: return "Contains your personal files"
        }
    }
}
