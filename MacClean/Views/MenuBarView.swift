import SwiftUI

struct MenuBarView: View {
    @Environment(CleanupEngine.self) var cleanupEngine
    @Environment(PreferencesManager.self) var preferencesManager
    @State private var isScanning = false
    @State private var quickScanResults: [CleanupItem] = []
    @State private var diskSpaceAvailable: Int64 = 0
    @State private var diskSpaceTotal: Int64 = 0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(.blue)
                Text("MacClean")
                    .font(.headline)
            }
            .padding(.horizontal)
            .padding(.top, 8)
            
            Divider()
            
            // Disk Space Info
            VStack(alignment: .leading, spacing: 4) {
                Text("Disk Space")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if diskSpaceTotal > 0 {
                    let used = diskSpaceTotal - diskSpaceAvailable
                    let usedPercent = Double(used) / Double(diskSpaceTotal) * 100
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Available: \(ByteCountFormatter.string(fromByteCount: diskSpaceAvailable, countStyle: .file))")
                                .font(.subheadline)
                            Text("Used: \(String(format: "%.1f", usedPercent))%")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        // Progress bar
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.2))
                                    .frame(height: 4)
                                    .cornerRadius(2)
                                
                                Rectangle()
                                    .fill(usedPercent > 80 ? Color.red : usedPercent > 60 ? Color.orange : Color.green)
                                    .frame(width: geometry.size.width * CGFloat(usedPercent / 100), height: 4)
                                    .cornerRadius(2)
                            }
                        }
                        .frame(width: 60, height: 4)
                    }
                } else {
                    Text("Loading...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)
            
            Divider()
            
            // Quick Stats
            let totalFreed = preferencesManager.preferences.totalSpaceFreed
            if totalFreed > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Total Space Freed")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(ByteCountFormatter.string(fromByteCount: totalFreed, countStyle: .file))
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.green)
                }
                .padding(.horizontal)
                
                Divider()
            }
            
            // Quick Actions
            VStack(spacing: 8) {
                Button(action: quickScan) {
                    HStack {
                        Image(systemName: isScanning ? "hourglass" : "magnifyingglass")
                        Text(isScanning ? "Scanning..." : "Quick Scan")
                        Spacer()
                    }
                }
                .disabled(isScanning)
                
                if !quickScanResults.isEmpty {
                    let totalSize = quickScanResults.compactMap { $0.estimatedSize }.reduce(0, +)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Found:")
                            Spacer()
                            Text(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file))
                                .foregroundColor(.orange)
                                .fontWeight(.semibold)
                        }
                        .font(.caption)
                        
                        Button("Clean Now") {
                            performQuickCleanup()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    .padding(.horizontal)
                }
                
                Button(action: openMainWindow) {
                    HStack {
                        Image(systemName: "app.fill")
                        Text("Open MacClean")
                        Spacer()
                    }
                }
                
                Button(action: openPreferences) {
                    HStack {
                        Image(systemName: "gearshape")
                        Text("Preferences")
                        Spacer()
                    }
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            
            Divider()
            
            // Quit
            Button(action: quitApp) {
                HStack {
                    Image(systemName: "power")
                    Text("Quit MacClean")
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .frame(width: 300)
        .onAppear {
            loadDiskSpace()
        }
    }
    
    private func loadDiskSpace() {
        Task {
            let fileManager = FileManager.default
            if let homeURL = fileManager.urls(for: .userDirectory, in: .userDomainMask).first,
               let attributes = try? fileManager.attributesOfFileSystem(forPath: homeURL.path),
               let total = attributes[.systemSize] as? Int64,
               let free = attributes[.systemFreeSize] as? Int64 {
                await MainActor.run {
                    diskSpaceTotal = total
                    diskSpaceAvailable = free
                }
            }
        }
    }
    
    private func quickScan() {
        isScanning = true
        Task {
            // Quick scan of common categories
            let quickCategories: Set<CleanupCategoryType> = [
                .userCaches, .downloads, .trash
            ]
            let results = await cleanupEngine.scanCategories(quickCategories)
            await MainActor.run {
                quickScanResults = results
                isScanning = false
            }
        }
    }
    
    private func performQuickCleanup() {
        guard !quickScanResults.isEmpty else { return }
        
        let moveToTrash = preferencesManager.preferences.moveToTrash
        
        Task {
            // Use the scan results directly as CleanupItems
            await cleanupEngine.cleanCategories(quickScanResults, moveToTrash: moveToTrash) { progress, status in
                Task { @MainActor in
                    cleanupEngine.currentProgress = progress
                    cleanupEngine.currentStatus = status
                }
            }
            
            await MainActor.run {
                quickScanResults = []
                // Refresh disk space after cleanup
                loadDiskSpace()
            }
        }
    }
    
    private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.title == "MacClean" }) {
            window.makeKeyAndOrderFront(nil)
        }
    }
    
    private func openPreferences() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
    
    private func quitApp() {
        NSApp.terminate(nil)
    }
}

#Preview {
    MenuBarView()
        .environment(CleanupEngine())
        .environment(PreferencesManager())
}
