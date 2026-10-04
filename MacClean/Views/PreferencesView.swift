import SwiftUI
import UniformTypeIdentifiers
import Foundation

struct PreferencesView: View {
    @Environment(PreferencesManager.self) var preferencesManager
    @Environment(CleanupEngine.self) var cleanupEngine
    @State private var selectedTab: PreferenceTab = .general
    
    enum PreferenceTab: String, CaseIterable {
        case general = "General"
        case aiSettings = "AI Settings"
        case advanced = "Advanced"
    }
    
    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralPreferencesView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .tag(PreferenceTab.general)
            
            AISettingsPreferencesView()
                .tabItem {
                    Label("AI Settings", systemImage: "sparkles")
                }
                .tag(PreferenceTab.aiSettings)
            
            AdvancedPreferencesView()
                .tabItem {
                    Label("Advanced", systemImage: "slider.horizontal.3")
                }
                .tag(PreferenceTab.advanced)
        }
        .frame(width: 600, height: 500)
    }
}

struct GeneralPreferencesView: View {
    @Environment(PreferencesManager.self) var preferencesManager
    
    var body: some View {
        Form {
            Section {
                Text("Select which cleanup categories should be available for selection.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section("Cleanup Categories") {
                ForEach(CleanupCategoryType.allCases, id: \.self) { category in
                    Toggle(isOn: Binding(
                        get: { preferencesManager.preferences.enabledCategories.contains(category) },
                        set: { isEnabled in
                            if isEnabled {
                                preferencesManager.preferences.enabledCategories.insert(category)
                            } else {
                                preferencesManager.preferences.enabledCategories.remove(category)
                            }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(category.displayName)
                                .font(.subheadline)
                            
                            Text(category.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct AISettingsPreferencesView: View {
    @Environment(PreferencesManager.self) var preferencesManager
    @State private var testConnectionResult: String = ""
    @State private var isTestingConnection = false
    
    var body: some View {
        Form {
            Section {
                Text("Configure AI service for cleanup suggestions.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section("AI Service") {
                Picker("Service", selection: Binding(
                    get: { preferencesManager.preferences.aiServiceType },
                    set: { preferencesManager.preferences.aiServiceType = $0 }
                )) {
                    Text("LM Studio").tag(AIServiceType.lmStudio)
                    Text("Apple Intelligence").tag(AIServiceType.siriAI)
                }
                .pickerStyle(.segmented)
            }
            
            if preferencesManager.preferences.aiServiceType == .lmStudio {
                Section("LM Studio Configuration") {
                    TextField("API Endpoint", text: Binding(
                        get: { preferencesManager.preferences.lmStudioEndpoint },
                        set: { newValue in
                            preferencesManager.preferences.lmStudioEndpoint = newValue
                            // Explicitly save when endpoint changes
                            preferencesManager.save()
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        // Normalize URL when user finishes editing
                        normalizeEndpoint()
                    }
                    
                    TextField("Model Name (optional)", text: Binding(
                        get: { preferencesManager.preferences.lmStudioModel },
                        set: { newValue in
                            preferencesManager.preferences.lmStudioModel = newValue
                            preferencesManager.save()
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                    
                    Button("Test Connection") {
                        testLMStudioConnection()
                    }
                    .disabled(isTestingConnection)
                    
                    if !testConnectionResult.isEmpty {
                        Text(testConnectionResult)
                            .font(.caption)
                            .foregroundColor(testConnectionResult.contains("Success") ? .green : .red)
                    }
                }
            } else {
                Section("Apple Intelligence") {
                    Text(AppleIntelligenceService.availabilityDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
    
    private func normalizeEndpoint() {
        var endpoint = preferencesManager.preferences.lmStudioEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // If no protocol specified, add http://
        if !endpoint.hasPrefix("http://") && !endpoint.hasPrefix("https://") {
            endpoint = "http://\(endpoint)"
        }
        
        // If no path specified, add /v1
        if !endpoint.contains("/v1") && !endpoint.hasSuffix("/") {
            endpoint = "\(endpoint)/v1"
        }
        
        if endpoint != preferencesManager.preferences.lmStudioEndpoint {
            preferencesManager.preferences.lmStudioEndpoint = endpoint
            preferencesManager.save()
        }
    }
    
    private func testLMStudioConnection() {
        // Normalize endpoint before testing
        normalizeEndpoint()
        
        isTestingConnection = true
        testConnectionResult = "Testing connection..."
        
        Task {
            do {
                let service = LMStudioService(
                    endpoint: preferencesManager.preferences.lmStudioEndpoint,
                    model: preferencesManager.preferences.lmStudioModel
                )
                
                // Use the simpler testConnection method
                try await service.testConnection()
                
                await MainActor.run {
                    testConnectionResult = "✓ Successfully connected to LM Studio"
                    isTestingConnection = false
                }
            } catch let error as AIServiceError {
                await MainActor.run {
                    testConnectionResult = "✗ \(error.localizedDescription)"
                    isTestingConnection = false
                }
            } catch {
                await MainActor.run {
                    // Fallback for any other errors
                    if let urlError = error as? URLError {
                        var message = "✗ Connection failed: "
                        switch urlError.code {
                        case .cannotConnectToHost:
                            message += "Cannot connect to \(preferencesManager.preferences.lmStudioEndpoint).\n\nPlease ensure:\n• LM Studio is running\n• API server is started (Settings → Local Server → Start Server)\n• Port matches your endpoint (default: 1234)"
                        case .notConnectedToInternet:
                            message += "No internet connection (not required for local LM Studio)"
                        case .timedOut:
                            message += "Connection timed out. Check if LM Studio is running."
                        default:
                            message += urlError.localizedDescription
                        }
                        testConnectionResult = message
                    } else {
                        testConnectionResult = "✗ Error: \(error.localizedDescription)"
                    }
                    isTestingConnection = false
                }
            }
        }
    }
}

struct AdvancedPreferencesView: View {
    @Environment(PreferencesManager.self) var preferencesManager
    @State private var scheduledCleanupManager = ScheduledCleanupManager()
    @State private var showDeletionLog = false
    @State private var showExportSettings = false
    @State private var showImportSettings = false
    @State private var showProtectedPathPicker = false
    
    var body: some View {
        Form {
            Section {
                Text("Advanced settings for MacClean behavior.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section("Safety") {
                Toggle("Require confirmation before cleaning", isOn: Binding(
                    get: { preferencesManager.preferences.requireConfirmation },
                    set: { preferencesManager.preferences.requireConfirmation = $0 }
                ))
                
                Toggle("Move to Trash (instead of permanent deletion)", isOn: Binding(
                    get: { preferencesManager.preferences.moveToTrash },
                    set: { newValue in
                        preferencesManager.preferences.moveToTrash = newValue
                        preferencesManager.save()
                    }
                ))
                
                Text("When enabled, files are moved to Trash first, allowing recovery. Disable for immediate permanent deletion.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack {
                    Text("Size threshold warning (GB)")
                    Spacer()
                    TextField("", value: Binding(
                        get: { preferencesManager.preferences.sizeThresholdWarningGB },
                        set: { newValue in
                            preferencesManager.preferences.sizeThresholdWarningGB = max(0, newValue)
                            preferencesManager.save()
                        }
                    ), format: .number.precision(.fractionLength(1)))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                }
                
                Text("Show warning when deleting more than this amount. Set to 0 to disable.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section("Deletion Log") {
                Button("View Deletion Log") {
                    showDeletionLog = true
                }
                
                Text("View detailed log of all deleted files with timestamps and paths.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            Text("View detailed log of all deleted files with timestamps and paths.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section("Protected Paths") {
                if preferencesManager.preferences.protectedPaths.isEmpty {
                    Text("No protected paths added.")
                        .foregroundColor(.secondary)
                        .italic()
                } else {
                    ForEach(preferencesManager.preferences.protectedPaths, id: \.self) { path in
                        HStack {
                            Image(systemName: "folder.fill")
                                .foregroundColor(.blue)
                            Text(path)
                                .truncationMode(.middle)
                                .lineLimit(1)
                            Spacer()
                            Button(action: {
                                if let index = preferencesManager.preferences.protectedPaths.firstIndex(of: path) {
                                    preferencesManager.preferences.protectedPaths.remove(at: index)
                                    preferencesManager.save()
                                }
                            }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                
                Button("Add Folder") {
                    showProtectedPathPicker = true
                }
                
                Text("Files in these folders will never be deleted.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section("Settings") {
                Button("Export Settings") {
                    showExportSettings = true
                }
                
                Button("Import Settings") {
                    showImportSettings = true
                }
                
                Text("Export or import your MacClean preferences.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section("Notifications") {
                Toggle("Show notifications", isOn: Binding(
                    get: { preferencesManager.preferences.showNotifications },
                    set: { preferencesManager.preferences.showNotifications = $0 }
                ))
            }
            
            Section("Menu Bar") {
                Toggle("Show menu bar icon", isOn: Binding(
                    get: { preferencesManager.preferences.showMenuBarIcon },
                    set: { preferencesManager.preferences.showMenuBarIcon = $0 }
                ))
                Text("Quick access to MacClean from the menu bar")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section("Scheduled Cleanup") {
                Toggle("Enable scheduled cleanup", isOn: Binding(
                    get: { scheduledCleanupManager.isEnabled },
                    set: { enabled in
                        if enabled {
                            scheduledCleanupManager.enable()
                        } else {
                            scheduledCleanupManager.disable()
                        }
                    }
                ))
                
                if scheduledCleanupManager.isEnabled {
                    Picker("Frequency", selection: Binding(
                        get: { scheduledCleanupManager.frequency },
                        set: { newValue in
                            scheduledCleanupManager.frequency = newValue
                            scheduledCleanupManager.scheduleNextCleanup()
                        }
                    )) {
                        ForEach(ScheduledCleanupManager.CleanupFrequency.allCases, id: \.self) { frequency in
                            Text(frequency.rawValue).tag(frequency)
                        }
                    }
                    
                    DatePicker("Time", selection: Binding(
                        get: { scheduledCleanupManager.scheduledTime },
                        set: { newValue in
                            scheduledCleanupManager.scheduledTime = newValue
                            scheduledCleanupManager.scheduleNextCleanup()
                        }
                    ), displayedComponents: .hourAndMinute)
                }
            }
            
            Section("Startup") {
                Toggle("Auto-scan on launch", isOn: Binding(
                    get: { preferencesManager.preferences.autoScanOnLaunch },
                    set: { preferencesManager.preferences.autoScanOnLaunch = $0 }
                ))
            }
            
            Section {
                Button("Reset to Defaults") {
                    preferencesManager.resetToDefaults()
                }
                .foregroundColor(.red)
            }
        }
        .formStyle(.grouped)
        .padding()
        .sheet(isPresented: $showDeletionLog) {
            DeletionLogView()
                .frame(width: 900, height: 700)
        }
        .fileExporter(
            isPresented: $showExportSettings,
            document: SettingsDocument(preferences: preferencesManager.preferences),
            contentType: .json,
            defaultFilename: "MacClean_Settings_\(Date().formatted(date: .numeric, time: .omitted)).json"
        ) { result in
            if case .success = result {
                // Settings exported successfully
            }
        }
        .fileImporter(
            isPresented: $showImportSettings,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    importSettings(from: url)
                }
            case .failure(let error):
                print("Failed to import settings: \(error)")
            }
        }
        .fileImporter(
            isPresented: $showProtectedPathPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                for url in urls {
                    let path = url.path
                    if !preferencesManager.preferences.protectedPaths.contains(path) {
                        preferencesManager.preferences.protectedPaths.append(path)
                    }
                }
                preferencesManager.save()
            case .failure(let error):
                print("Failed to select folder: \(error)")
            }
        }
    }
    
    private func importSettings(from url: URL) {
        Task { @MainActor in
            do {
                let data = try Data(contentsOf: url)
                let decoder = JSONDecoder()
                let importedData = try decoder.decode(AppPreferencesData.self, from: data)
                preferencesManager.preferences = importedData.toPreferences()
                preferencesManager.save()
            } catch {
                print("Failed to import settings: \(error)")
            }
        }
    }
}

struct SettingsDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    
    var preferences: AppPreferences
    private var _importedData: AppPreferencesData?
    
    @MainActor
    init(preferences: AppPreferences) {
        self.preferences = preferences
        self._importedData = nil
    }
    
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let decoder = JSONDecoder()
        // Decode AppPreferencesData (now nonisolated)
        let importedData = try decoder.decode(AppPreferencesData.self, from: data)
        // Create preferences using MainActor.assumeIsolated since FileDocument runs on MainActor
        self.preferences = MainActor.assumeIsolated {
            AppPreferences(
                enabledCategories: Set(importedData.enabledCategories.compactMap { CleanupCategoryType(rawValue: $0) }),
                aiServiceType: AIServiceType(rawValue: importedData.aiServiceType) ?? .lmStudio,
                lmStudioEndpoint: importedData.lmStudioEndpoint,
                lmStudioModel: importedData.lmStudioModel,
                siriAIEnabled: importedData.siriAIEnabled,
                requireConfirmation: importedData.requireConfirmation,
                showNotifications: importedData.showNotifications,
                autoScanOnLaunch: importedData.autoScanOnLaunch,
                totalSpaceFreed: importedData.totalSpaceFreed ?? 0,
                sizeThresholdWarningGB: importedData.sizeThresholdWarningGB ?? 10.0,

                moveToTrash: importedData.moveToTrash ?? true,
                protectedPaths: importedData.protectedPaths ?? [],
                showMenuBarIcon: importedData.showMenuBarIcon ?? true
            )
        }
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        // Create AppPreferencesData inside MainActor.assumeIsolated to access all preferences properties
        let data = MainActor.assumeIsolated {
            AppPreferencesData(
                enabledCategories: preferences.enabledCategories.map { $0.rawValue },
                aiServiceType: preferences.aiServiceType.rawValue,
                lmStudioEndpoint: preferences.lmStudioEndpoint,
                lmStudioModel: preferences.lmStudioModel,
                siriAIEnabled: preferences.siriAIEnabled,
                requireConfirmation: preferences.requireConfirmation,
                showNotifications: preferences.showNotifications,
                autoScanOnLaunch: preferences.autoScanOnLaunch,
                totalSpaceFreed: preferences.totalSpaceFreed,
                sizeThresholdWarningGB: preferences.sizeThresholdWarningGB,
                moveToTrash: preferences.moveToTrash,
                protectedPaths: preferences.protectedPaths,
                showMenuBarIcon: preferences.showMenuBarIcon
            )
        }
        let encodedData = try encoder.encode(data)
        return FileWrapper(regularFileWithContents: encodedData)
    }
}

#Preview {
    PreferencesView()
        .environment(PreferencesManager())
        .environment(CleanupEngine())
}

