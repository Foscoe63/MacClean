import SwiftUI

@main
struct MacCleanApp: App {
    @State private var cleanupEngine = CleanupEngine()
    @State private var preferencesManager = PreferencesManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(cleanupEngine)
                .environment(preferencesManager)
                .frame(minWidth: 800, minHeight: 600)
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
}

