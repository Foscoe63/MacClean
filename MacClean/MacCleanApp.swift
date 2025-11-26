import SwiftUI

@main
struct MacCleanApp: App {
    @State private var cleanupEngine = CleanupEngine()
    @State private var preferencesManager = PreferencesManager()
    @State private var menuBarManager: MenuBarManager?
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(cleanupEngine)
                .environment(preferencesManager)
                .frame(minWidth: 800, minHeight: 600)
                .onAppear {
                    setupMenuBar()
                }
                .onChange(of: preferencesManager.preferences.showMenuBarIcon) { _, newValue in
                    if newValue {
                        setupMenuBar()
                    } else {
                        menuBarManager?.removeMenuBar()
                        menuBarManager = nil
                    }
                }
        }
        .windowStyle(.automatic)
        .commands {
            CommandGroup(replacing: .appSettings) {
                SettingsLink()
                    .keyboardShortcut(",", modifiers: .command)
            }
        }
        
        Settings {
            PreferencesView()
                .environment(preferencesManager)
                .environment(cleanupEngine)
        }
    }
    
    @MainActor
    private func setupMenuBar() {
        guard preferencesManager.preferences.showMenuBarIcon else { return }
        if menuBarManager == nil {
            menuBarManager = MenuBarManager(
                cleanupEngine: cleanupEngine,
                preferencesManager: preferencesManager
            )
            menuBarManager?.setupMenuBar()
        }
    }
}

