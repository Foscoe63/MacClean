# MacClean Setup Guide

## Quick Start

1. **Open Xcode** and create a new macOS App project
2. **Configure the project**:
   - Product Name: `MacClean`
   - Interface: SwiftUI
   - Language: Swift
   - Minimum Deployment: macOS 26.0
   - Bundle Identifier: `com.yourcompany.MacClean` (or your preferred identifier)

3. **Add Source Files**:
   - Drag all folders (`Models`, `Views`, `Services`, `Utilities`) into the Xcode project
   - Ensure "Copy items if needed" is checked
   - Add to target: MacClean

4. **Add Test Files**:
   - Add the `Tests` folder to the project
   - Create test targets if they don't exist:
     - MacCleanTests (Unit Tests)
     - MacCleanUITests (UI Tests)

5. **Build Settings**:
   - Swift Language Version: Swift 6.2
   - macOS Deployment Target: 26.0

6. **Build and Run**:
   - Select the MacClean scheme
   - Press Cmd+R to build and run

## Project Structure

```
MacClean/
├── MacCleanApp.swift          # Main app entry point
├── Models/                     # Data models
│   ├── CleanupItem.swift
│   ├── CleanupResult.swift
│   ├── AISuggestion.swift
│   └── AppPreferences.swift
├── Views/                      # SwiftUI views
│   ├── ContentView.swift      # Main window
│   ├── PreferencesView.swift   # Preferences window
│   └── ProgressView.swift      # Progress component
├── Services/                   # Business logic
│   ├── CleanupEngine.swift    # Cleanup orchestration
│   ├── CleanupCategory.swift  # Cleanup protocol
│   ├── AIServiceProtocol.swift
│   ├── LMStudioService.swift
│   └── SiriAIService.swift
├── Utilities/                  # Helper classes
│   ├── FileManager+Extensions.swift
│   ├── AuthorizationHelper.swift
│   └── PreferencesManager.swift
└── Tests/                      # Test files
    ├── MacCleanTests/
    └── MacCleanUITests/
```

## Features Implemented

✅ Professional SwiftUI interface
✅ Modular cleanup engine with extensible categories
✅ Progress tracking with animated progress bar
✅ AI integration (LM Studio and Siri AI)
✅ Preferences window with tabs
✅ User and system cache cleanup
✅ Browser cache cleanup (Safari, Chrome, Firefox)
✅ Logs cleanup
✅ Downloads and Trash cleanup
✅ Selective cleanup (user chooses what to clean)
✅ Settings persistence
✅ Unit and UI tests

## Notes

- The app uses Swift 6.2's Observation framework for state management
- Admin privileges are requested when needed for system cleanup
- Preferences are automatically saved with debouncing
- AI suggestions require LM Studio to be running (for LM Studio mode) or use Siri AI (on-device)

## Troubleshooting

**Build Errors:**
- Ensure all files are added to the MacClean target
- Check that Swift 6.2 is selected in Build Settings
- Verify macOS 26.0 is set as minimum deployment

**Runtime Issues:**
- For system cleanup, the app will request admin privileges
- LM Studio must be running on localhost:1234 for LM Studio integration
- Check Console.app for any error messages

