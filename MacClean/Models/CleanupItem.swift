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
        estimatedSize: Int64? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.category = category
        self.isEnabled = isEnabled
        self.requiresAdmin = requiresAdmin
        self.estimatedSize = estimatedSize
    }
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
    // Docker
    case dockerCache = "docker_cache"
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
        case .dockerCache: return "Docker Cache"
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
        case .systemLogs: return "System-wide logs"
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
        case .dockerCache: return "Docker images, containers, and build cache"
        case .edgeCache: return "Microsoft Edge browser cache"
        case .braveCache: return "Brave browser cache"
        case .spotifyCache: return "Spotify application cache"
        case .slackCache: return "Slack application cache"
        case .zoomCache: return "Zoom application cache"
        case .iosBackups: return "Old iOS device backups"
        }
    }
}

