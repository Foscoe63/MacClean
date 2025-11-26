import SwiftUI
import AppKit
import Combine

@MainActor
class MenuBarManager: ObservableObject {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private let cleanupEngine: CleanupEngine
    private let preferencesManager: PreferencesManager
    private var updateTimer: Timer?
    @Published var diskSpaceAvailable: Int64 = 0
    @Published var diskSpaceTotal: Int64 = 0
    
    init(cleanupEngine: CleanupEngine, preferencesManager: PreferencesManager) {
        self.cleanupEngine = cleanupEngine
        self.preferencesManager = preferencesManager
    }
    
    func setupMenuBar() {
        // Create status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        // Create popover
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 300, height: 450)
        popover?.behavior = .transient
        popover?.contentViewController = NSHostingController(
            rootView: MenuBarView()
                .environment(cleanupEngine)
                .environment(preferencesManager)
        )
        
        // Update menu bar icon
        updateMenuBarIcon()
        
        // Set up periodic updates
        updateTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateMenuBarIcon()
            }
        }
        
        // Initial background scan check
        checkCleanupNeeded()
    }
    
    func removeMenuBar() {
        updateTimer?.invalidate()
        updateTimer = nil
        
        if let statusItem = statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
        popover = nil
    }
    
    private func updateMenuBarIcon() {
        guard let button = statusItem?.button else { return }
        
        // Get disk space
        let fileManager = FileManager.default
        if let homeURL = fileManager.urls(for: .userDirectory, in: .userDomainMask).first,
           let attributes = try? fileManager.attributesOfFileSystem(forPath: homeURL.path),
           let total = attributes[.systemSize] as? Int64,
           let free = attributes[.systemFreeSize] as? Int64 {
            diskSpaceTotal = total
            diskSpaceAvailable = free
            
            let usedPercent = Double(total - free) / Double(total) * 100
            let freeGB = Double(free) / 1_000_000_000
            
            // Create icon with disk space text
            let iconText: String
            if freeGB < 10 {
                iconText = String(format: "%.1fGB", freeGB)
            } else {
                iconText = String(format: "%.0fGB", freeGB)
            }
            
            // Create attributed string for button
            let attributedTitle = NSMutableAttributedString(string: iconText)
            attributedTitle.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium), range: NSRange(location: 0, length: iconText.count))
            
            // Color based on available space
            let color: NSColor
            if freeGB < 10 {
                color = .systemRed
            } else if freeGB < 50 {
                color = .systemOrange
            } else {
                color = .systemGreen
            }
            attributedTitle.addAttribute(.foregroundColor, value: color, range: NSRange(location: 0, length: iconText.count))
            
            button.attributedTitle = attributedTitle
            button.action = #selector(togglePopover)
            button.target = self
            button.toolTip = "MacClean - \(String(format: "%.1f", freeGB)) GB free (\(String(format: "%.0f", usedPercent))% used)"
        } else {
            // Fallback to icon if disk space unavailable
            button.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "MacClean")
            button.action = #selector(togglePopover)
            button.target = self
        }
    }
    
    private func checkCleanupNeeded() {
        Task {
            // Quick background scan
            let quickCategories: Set<CleanupCategoryType> = [.userCaches, .downloads, .trash]
            let results = await cleanupEngine.scanCategories(quickCategories)
            let totalSize = results.compactMap { $0.estimatedSize }.reduce(0, +)
            
            // Check if cleanup is needed (more than 1GB available to clean)
            if totalSize > 1_000_000_000 && preferencesManager.preferences.showNotifications {
                let sizeGB = Double(totalSize) / 1_000_000_000
                NotificationService.shared.sendCleanupNeededNotification(
                    spaceAvailable: totalSize,
                    message: String(format: "%.1f GB can be freed", sizeGB)
                )
            }
        }
    }
    
    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        
        if let popover = popover {
            if popover.isShown {
                popover.performClose(nil)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                // Refresh data when popover opens
                updateMenuBarIcon()
            }
        }
    }
}
