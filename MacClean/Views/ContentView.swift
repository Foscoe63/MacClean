import SwiftUI

struct ContentView: View {
    @Environment(CleanupEngine.self) var cleanupEngine
    @Environment(PreferencesManager.self) var preferencesManager
    @State private var cleanupItems: [CleanupItem] = []
    @State private var selectedCategories: Set<CleanupCategoryType> = []
    @State private var aiSuggestions: [AISuggestion] = []
    @State private var isLoadingSuggestions = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isScanning = false
    @State private var showChatbot = false
    @State private var showConfirmation = false
    @State private var showHistory = false
    @State private var showFilePreview = false
    @State private var showSizeWarning = false
    @State private var showUndoAlert = false
    @State private var showDiskUsage = false
    @State private var showAnalytics = false
    @State private var showSystemHealth = false
    @State private var lastCleanupSpaceFreed: Int64 = 0
    @State private var cleanupTask: Task<Void, Never>?
    private let notificationService = NotificationService.shared
    private let historyManager = CleanupHistoryManager()
    private let undoManager = CleanupUndoManager.shared
    @State private var undoResultMessage = ""
    @State private var showUndoResult = false
    
    private var totalSpaceToClean: Int64 {
        cleanupItems
            .filter { selectedCategories.contains($0.category) }
            .compactMap { $0.estimatedSize }
            .reduce(0, +)
    }
    
    private var confirmationMessage: String {
        let categoryText = selectedCategories.count == 1 ? "category" : "categories"
        let spaceText = ByteCountFormatter.string(fromByteCount: totalSpaceToClean, countStyle: .file)
        let destination = preferencesManager.preferences.moveToTrash
            ? "Items will be moved to the Trash."
            : "Items will be deleted permanently. This cannot be undone."
        var message = "You are about to clean \(selectedCategories.count) \(categoryText) (about \(spaceText)). \(destination)"
        let personalCategories = selectedCategories
            .filter { $0.riskLevel == .personalData }
            .map(\.displayName)
            .sorted()
        if !personalCategories.isEmpty {
            message += "\n\nWarning: this includes your personal files in \(personalCategories.joined(separator: ", "))."
        }
        if selectedCategories.contains(where: { $0.requiresAdminCleanup }) {
            message += "\n\nSystem caches and logs are always deleted permanently and need your administrator password."
        }
        return message
    }
    
    private var shouldShowSizeWarning: Bool {
        let thresholdBytes = Int64(preferencesManager.preferences.sizeThresholdWarningGB * 1_000_000_000)
        return preferencesManager.preferences.sizeThresholdWarningGB > 0 && totalSpaceToClean > thresholdBytes
    }
    
    private var sidebarView: some View {
        VStack(alignment: .leading, spacing: 16) {
                // Space Freed Counter - Use history manager for accurate totals
                let totalFreed = historyManager.totalSpaceFreed
                if totalFreed > 0 {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Total Space Freed")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                        
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.title2)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ByteCountFormatter.string(fromByteCount: totalFreed, countStyle: .file))
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.green)
                                
                                Text("All time")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.green.opacity(0.1))
                        )
                        .padding(.horizontal)
                    }
                    .padding(.top, 8)
                }
                
                HStack {
                    Text("Cleanup Categories")
                        .font(.headline)
                    
                    Spacer()
                    
                    if !cleanupItems.isEmpty {
                        HStack(spacing: 8) {
                            Button("Select Safe") {
                                selectedCategories = Set(cleanupItems.map { $0.category }.filter { $0.riskLevel == .safe })
                            }
                            .help("Select caches and logs that apps can rebuild")
                            .buttonStyle(.borderless)
                            .font(.caption)
                            
                            Button("Deselect All") {
                                selectedCategories.removeAll()
                            }
                            .buttonStyle(.borderless)
                            .font(.caption)
                        }
                    }
                }
                .padding(.horizontal)
                
                if cleanupItems.isEmpty {
                    Text("Click 'Scan' to analyze cleanup opportunities")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    List {
                        ForEach(cleanupItems) { item in
                            CleanupItemRow(item: item, isSelected: selectedCategories.contains(item.category))
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if selectedCategories.contains(item.category) {
                                        selectedCategories.remove(item.category)
                                    } else {
                                        selectedCategories.insert(item.category)
                                    }
                                }
                        }
                    }
                    .listStyle(.sidebar)
                }
                
                Spacer()
                
                VStack(spacing: 12) {
                    Button(action: scanForCleanup) {
                        HStack {
                            if isScanning {
                                ProgressView()
                                    .frame(width: 16, height: 16)
                            } else {
                                Image(systemName: "magnifyingglass")
                            }
                            Text("Scan")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    // Accessibility improvements
                    .accessibilityLabel("Scan for cleanup items")
                    .buttonStyle(.borderedProminent)
                    .disabled(isScanning || cleanupEngine.isCleaning)
                    .keyboardShortcut("r", modifiers: .command)
                    
                    Button(action: startCleanup) {
                        HStack {
                            Image(systemName: "trash")
                            Text("Clean Selected")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    // Accessibility improvements
                    .accessibilityLabel("Start cleaning selected categories")
                    .buttonStyle(.bordered)
                    .disabled(selectedCategories.isEmpty || cleanupEngine.isCleaning)
                }
                .padding()
        }
        .frame(minWidth: 250)
    }
    
    private var detailView: some View {
        ScrollView {
                VStack(spacing: 24) {
                    // Progress Section
                    if cleanupEngine.isCleaning {
                        VStack(spacing: 12) {
                            CleanupProgressView(
                                progress: cleanupEngine.currentProgress,
                                status: cleanupEngine.currentStatus
                            )
                            
                            Button("Cancel") {
                                // The engine stops after the current item and reports what was already cleaned
                                cleanupTask?.cancel()
                                cleanupEngine.currentStatus = "Cancelling..."
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.horizontal)
                    }
                    
                    // AI Suggestions Section
                    if !aiSuggestions.isEmpty {
                        AISuggestionsSection(suggestions: aiSuggestions)
                            .padding(.horizontal)
                    }
                    
                    // Results Section
                    if let summary = cleanupEngine.summary {
                        CleanupResultsSection(summary: summary)
                            .padding(.horizontal)
                    }
                    
                    // Welcome/Info Section
                    if !cleanupEngine.isCleaning && cleanupEngine.summary == nil {
                        WelcomeSection(
                            onGetSuggestions: fetchAISuggestions,
                            onOpenChatbot: { showChatbot = true },
                            isLoading: isLoadingSuggestions
                        )
                        .padding(.horizontal)
                    }
            }
            .padding(.vertical)
        }
    }
    
    private var toolbarContent: some View {
        HStack(spacing: 12) {
            Button(action: { showDiskUsage = true }) {
                Image(systemName: "chart.pie.fill")
            }
            .help("View Disk Usage")
            
            Button(action: { showHistory = true }) {
                Image(systemName: "clock.arrow.circlepath")
            }
            .help("View Cleanup History")
            
            Button(action: { showAnalytics = true }) {
                Image(systemName: "chart.bar.xaxis")
            }
            .help("View Cleanup Analytics")
            
            Button(action: { showSystemHealth = true }) {
                Image(systemName: "heart.circle.fill")
            }
            .help("View System Health Dashboard")
            
            SettingsLink {
                Image(systemName: "gearshape")
            }
        }
    }
    
    var body: some View {
        NavigationSplitView {
            sidebarView
        } detail: {
            detailView
        }
        .navigationTitle("MacClean")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                toolbarContent
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .sheet(isPresented: $showChatbot) {
            ChatbotView()
                .environment(preferencesManager)
        }
        .sheet(isPresented: $showHistory) {
            CleanupHistoryView(historyManager: historyManager)
        }
        .sheet(isPresented: $showDiskUsage) {
            DiskUsageView()
        }
        .sheet(isPresented: $showAnalytics) {
            CleanupAnalyticsView()
        }
        .sheet(isPresented: $showSystemHealth) {
            SystemHealthDashboardView(cleanupEngine: cleanupEngine)
                .environment(cleanupEngine)
        }
        .confirmationDialog("Confirm Cleanup", isPresented: $showConfirmation, titleVisibility: .visible) {
            Button("Preview Files") {
                showFilePreview = true
            }
            Button("Clean", role: .destructive) {
                performCleanup()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            VStack(alignment: .leading, spacing: 8) {
                Text(confirmationMessage)
                Button("Show Preview") {
                    showFilePreview = true
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
        }
        .alert("Large Deletion Warning", isPresented: $showSizeWarning) {
            Button("Continue Anyway", role: .destructive) {
                if preferencesManager.preferences.requireConfirmation {
                    showConfirmation = true
                } else {
                    performCleanup()
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            let thresholdGB = preferencesManager.preferences.sizeThresholdWarningGB
            let sizeGB = Double(totalSpaceToClean) / 1_000_000_000
            return Text("You are about to delete \(String(format: "%.1f", sizeGB)) GB of data. This exceeds your warning threshold of \(String(format: "%.1f", thresholdGB)) GB. Are you sure you want to continue?")
        }
        .sheet(isPresented: $showFilePreview) {
            NavigationStack {
                FilePreviewView(
                    cleanupItems: $cleanupItems,
                    selectedCategories: selectedCategories
                )
                .navigationTitle("Cleanup Preview")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") {
                            showFilePreview = false
                        }
                    }
                }
            }
            .frame(width: 600, height: 400)
        }
        .alert("Cleanup Complete", isPresented: $showUndoAlert) {
            Button("Undo") {
                let outcome = undoManager.undoLastCleanup()
                undoResultMessage = outcome.failed == 0
                    ? "Restored \(outcome.restored) items from the Trash."
                    : "Restored \(outcome.restored) items. \(outcome.failed) could not be restored because they are no longer in the Trash or their original location is in use."
                showUndoResult = true
                scanForCleanup()
            }
            Button("OK", role: .cancel) { }
        } message: {
            Text("Moved \(ByteCountFormatter.string(fromByteCount: lastCleanupSpaceFreed, countStyle: .file)) to Trash. Empty Trash to free up space. You can undo this action.")
        }
        .alert("Undo Cleanup", isPresented: $showUndoResult) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(undoResultMessage)
        }
        .onAppear {
            loadSelectedCategories()
            // Recalculate totalSpaceFreed from history to ensure accuracy
            // This fixes any incorrect values from before the moveToTrash fix
            preferencesManager.preferences.totalSpaceFreed = historyManager.totalSpaceFreed
            preferencesManager.save()
            
            if preferencesManager.preferences.autoScanOnLaunch {
                scanForCleanup()
            }
        }
        .onChange(of: preferencesManager.preferences.enabledCategories) { _, _ in
            // Reload selected categories when preferences change
            loadSelectedCategories()
        }
    }
    
    private func loadSelectedCategories() {
        // Pre-select only categories that are safe to clean; riskier ones need an explicit click
        selectedCategories = preferencesManager.preferences.enabledCategories
            .filter { $0.riskLevel == .safe }
    }
    
    private func scanForCleanup() {
        isScanning = true
        Task {
            // Use enabled categories from preferences for scanning
            let categoriesToScan = preferencesManager.preferences.enabledCategories.isEmpty 
                ? Set(CleanupCategoryType.allCases) 
                : preferencesManager.preferences.enabledCategories
            let items = await cleanupEngine.scanCategories(categoriesToScan)
            await MainActor.run {
                cleanupItems = items
                if selectedCategories.isEmpty {
                    selectedCategories = Set(items.map { $0.category }.filter { $0.riskLevel == .safe })
                }
                isScanning = false
                
                // Send notification if enabled
                if preferencesManager.preferences.showNotifications {
                    let totalSize = items.compactMap { $0.estimatedSize }.reduce(0, +)
                    notificationService.sendScanCompleteNotification(
                        itemsFound: items.count,
                        totalSize: totalSize
                    )
                }
            }
        }
    }
    
    private func startCleanup() {
        guard !selectedCategories.isEmpty else { return }
        
        // Check size threshold first
        if shouldShowSizeWarning {
            showSizeWarning = true
        } else if preferencesManager.preferences.requireConfirmation {
            showConfirmation = true
        } else {
            performCleanup()
        }
    }
    
    private func performCleanup() {
        let startTime = Date()
        let moveToTrash = preferencesManager.preferences.moveToTrash
        let protectedPaths = preferencesManager.preferences.protectedPaths
        
        let itemsToClean = cleanupItems.filter { selectedCategories.contains($0.category) }
        
        cleanupTask = Task {
            await cleanupEngine.cleanCategories(itemsToClean, moveToTrash: moveToTrash, protectedPaths: protectedPaths) { progress, status in
                Task { @MainActor in
                    cleanupEngine.currentProgress = progress
                    cleanupEngine.currentStatus = status
                }
            }
            
            await MainActor.run {
                // Update total space freed counter and history
                if let summary = cleanupEngine.summary {
                    // Only permanent deletions free space; items in the Trash are counted once the Trash is emptied
                    let spaceFreed = summary.totalSpaceFreed
                    
                    // Add to history
                    let entry = CleanupHistoryEntry(
                        categories: selectedCategories.map { $0.rawValue },
                        itemsDeleted: summary.totalItemsDeleted,
                        spaceFreed: spaceFreed,
                        duration: Date().timeIntervalSince(startTime),
                        success: summary.failedCategories == 0
                    )
                    historyManager.addEntry(entry)
                    
                    // Recalculate totalSpaceFreed from history entries (always accurate)
                    preferencesManager.preferences.totalSpaceFreed = historyManager.totalSpaceFreed
                    preferencesManager.save()
                    
                    // Track undo entry if moving to trash
                    if moveToTrash {
                        // Get recent deletion log entries for undo
                        let recentEntries = DeletionLogManager.shared.getLogEntries(since: startTime)
                        let deletedFiles = recentEntries
                            .filter { $0.success && $0.trashPath != nil }
                            .map { entry in
                                UndoEntry.DeletedFileInfo(
                                    originalPath: entry.filePath,
                                    trashPath: entry.trashPath,
                                    size: entry.fileSize
                                )
                            }
                        
                        if !deletedFiles.isEmpty {
                            undoManager.addUndoEntry(
                                category: selectedCategories.map { $0.displayName }.joined(separator: ", "),
                                filesDeleted: deletedFiles,
                                spaceFreed: summary.totalSpaceMovedToTrash
                            )
                            lastCleanupSpaceFreed = deletedFiles.reduce(0) { $0 + $1.size }
                            
                            // Show undo alert
                            showUndoAlert = true
                        }
                    }
                    
                    // Send notification if enabled
                    if preferencesManager.preferences.showNotifications {
                        notificationService.sendCleanupCompleteNotification(
                            spaceFreed: spaceFreed,
                            itemsDeleted: summary.totalItemsDeleted,
                            movedToTrash: moveToTrash && spaceFreed == 0
                        )
                    }
                }
            }
        }
    }
    
    private func fetchAISuggestions() {
        guard !cleanupItems.isEmpty else {
            scanForCleanup()
            return
        }
        
        isLoadingSuggestions = true
        Task {
            do {
                let service = AIServiceFactory.createService(
                    for: preferencesManager.preferences.aiServiceType,
                    preferences: preferencesManager.preferences
                )
                
                // Build enhanced context and learning preferences
                let enhancedContext = await EnhancedContextBuilder.buildContext(
                    cleanupEngine: cleanupEngine,
                    preferencesManager: preferencesManager
                )
                let learningPreferences = AILearningManager.shared.getUserPreferences()
                
                let suggestions = try await service.getSuggestions(
                    for: cleanupItems,
                    enhancedContext: enhancedContext,
                    learningPreferences: learningPreferences
                )
                
                await MainActor.run {
                    aiSuggestions = suggestions
                    isLoadingSuggestions = false
                    
                    // Send notification if enabled
                    if preferencesManager.preferences.showNotifications && !suggestions.isEmpty {
                        notificationService.sendAISuggestionsNotification(count: suggestions.count)
                    }
                }
            } catch let error as AIServiceError {
                await MainActor.run {
                    errorMessage = "Failed to get AI suggestions: \(error.localizedDescription)"
                    showError = true
                    isLoadingSuggestions = false
                }
            } catch let urlError as URLError {
                await MainActor.run {
                    var message = "Failed to connect to AI service: "
                    switch urlError.code {
                    case .cannotConnectToHost:
                        message += "Cannot connect to the server. Please check your endpoint settings."
                    case .timedOut:
                        message += "Connection timed out. The server may be slow to respond."
                    case .notConnectedToInternet:
                        message += "No internet connection (not required for local LM Studio)."
                    default:
                        message += urlError.localizedDescription
                    }
                    errorMessage = message
                    showError = true
                    isLoadingSuggestions = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to get AI suggestions: \(error.localizedDescription)"
                    showError = true
                    isLoadingSuggestions = false
                }
            }
        }
    }
}

struct CleanupItemRow: View {
    let item: CleanupItem
    let isSelected: Bool

    var body: some View {
        HStack {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isSelected ? .blue : .secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(item.description)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let size = item.estimatedSize {
                    Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                        .font(.caption2)
                        .foregroundColor(.blue)
                }

                if let warning = item.category.riskLevel.warningText {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundColor(item.category.riskLevel == .personalData ? .red : .orange)
                }
            }

            Spacer()

            if item.requiresAdmin {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
        .padding(.vertical, 4)
        // Combine elements for a single accessibility element
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.name + ", " + (item.estimatedSize.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "size unknown"))
    }
}

struct AISuggestionsSection: View {
    let suggestions: [AISuggestion]
    
    var body: some View {
        contentBody
    }

    // Extracted large view hierarchy to aid type‑checking performance
    @ViewBuilder
    private var contentBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(.blue)
                Text("AI Suggestions")
                    .font(.headline)
            }
            
            ForEach(suggestions) { suggestion in
                AISuggestionCard(suggestion: suggestion)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }
}

struct AISuggestionCard: View {
    let suggestion: AISuggestion
    @State private var hasInteracted = false

    // Build a concise accessibility description once to avoid complex inline concatenation
    private var accessibilityDescription: String {
        suggestion.category.displayName + ", " +
        (suggestion.estimatedSpace.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "no size") +
        ", Reason: " + suggestion.reason
    }

    var body: some View {
        cardContent
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityDescription)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(NSColor.textBackgroundColor))
            )
    }

    // Extracted sub‑view to reduce type‑checking complexity
    @ViewBuilder
    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerView
            Text(suggestion.reason)
                .font(.caption)
                .foregroundColor(.secondary)
            confidenceView
            interactionButtonsOrConfirmation
        }
    }

    @ViewBuilder
    private var headerView: some View {
        HStack {
            Text(suggestion.category.displayName)
                .font(.subheadline)
                .fontWeight(.semibold)
            Spacer()
            if let space = suggestion.estimatedSpace {
                Text(ByteCountFormatter.string(fromByteCount: space, countStyle: .file))
                    .font(.caption)
                    .foregroundColor(.blue)
            }
        }
    }

    @ViewBuilder
    private var confidenceView: some View {
        HStack {
            ProgressView(value: suggestion.confidence)
                .frame(width: 100)
            Text("\(Int(suggestion.confidence * 100))% confidence")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private var interactionButtonsOrConfirmation: some View {
        if !hasInteracted {
            HStack(spacing: 8) {
                Button(action: recordAccept) {
                    Label("Accept", systemImage: "checkmark.circle")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(action: recordReject) {
                    Label("Reject", systemImage: "xmark.circle")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        } else {
            Text("Feedback recorded")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private func recordAccept() {
        AILearningManager.shared.recordFeedback(
            suggestionId: suggestion.id,
            category: suggestion.category.rawValue,
            accepted: true
        )
        hasInteracted = true
    }

    private func recordReject() {
        AILearningManager.shared.recordFeedback(
            suggestionId: suggestion.id,
            category: suggestion.category.rawValue,
            accepted: false
        )
        hasInteracted = true
    }
}

struct CleanupResultsSection: View {
    @Environment(CleanupEngine.self) var cleanupEngine
    let summary: CleanupSummary
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: summary.wasCancelled ? "stop.circle.fill" : "checkmark.circle.fill")
                    .foregroundColor(summary.wasCancelled ? .orange : .green)
                Text(summary.wasCancelled ? "Cleanup Cancelled" : "Cleanup Complete")
                    .font(.headline)
                
                Spacer()
                
                Button("Start New Scan") {
                    cleanupEngine.reset()
                }
                .buttonStyle(.bordered)
            }
            
            HStack(spacing: 32) {
                VStack(alignment: .leading) {
                    Text("Space Freed")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(summary.formattedSpaceFreed)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                }
                
                if summary.totalSpaceMovedToTrash > 0 {
                    VStack(alignment: .leading) {
                        Text("Moved to Trash")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(summary.formattedSpaceMovedToTrash)
                            .font(.title2)
                            .fontWeight(.bold)
                    }
                    .help("Empty the Trash to free this space")
                }
                
                VStack(alignment: .leading) {
                    Text("Items Deleted")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(summary.totalItemsDeleted)")
                        .font(.title2)
                        .fontWeight(.bold)
                }
                
                VStack(alignment: .leading) {
                    Text("Categories")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(summary.successfulCategories) successful")
                        .font(.subheadline)
                        .foregroundColor(.green)
                }
            }
            
            if !summary.results.isEmpty {
                Divider()
                
                Text("Details")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                ForEach(summary.results) { result in
                    CleanupResultRow(result: result)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }
}

struct CleanupResultRow: View {
    let result: CleanupResult
    
    var body: some View {
        HStack {
            Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(result.success ? .green : .red)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(result.category.displayName)
                    .font(.subheadline)
                
                if result.success {
                    Text("\(result.itemsDeleted) items • \(ByteCountFormatter.string(fromByteCount: result.spaceFreed, countStyle: .file))\(result.movedToTrash ? " moved to Trash" : " freed")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else if let error = result.error {
                    // Enable text selection so users can copy error details
                    Text(error.localizedDescription)
                        .font(.caption)
                        .foregroundColor(.red)
                        .textSelection(.enabled)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

struct WelcomeSection: View {
    let onGetSuggestions: () -> Void
    let onOpenChatbot: () -> Void
    let isLoading: Bool
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 48))
                .foregroundColor(.blue)
            
            Text("Welcome to MacClean")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Select cleanup categories and click 'Scan' to analyze your system, or get AI-powered suggestions for what to clean.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            VStack(spacing: 12) {
                Button(action: onGetSuggestions) {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .frame(width: 16, height: 16)
                        } else {
                            Image(systemName: "sparkles")
                        }
                        Text("Get AI Suggestions")
                    }
                    .frame(maxWidth: 200)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading)
                
                Button(action: onOpenChatbot) {
                    HStack {
                        Image(systemName: "message.fill")
                        Text("Chatbot")
                    }
                    .frame(maxWidth: 200)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    ContentView()
        .environment(CleanupEngine())
        .environment(PreferencesManager())
}
