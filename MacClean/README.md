# MacClean

A professional macOS cleanup application built with Swift 6.2 for macOS 26 Tahoe.

## Features

- **Comprehensive Cleanup**: Clean user and system caches, logs, browser caches, downloads, and trash
- **AI-Powered Suggestions**: Get intelligent cleanup recommendations from LM Studio or Siri AI
- **Progress Tracking**: Real-time progress bar with detailed status updates
- **Selective Cleaning**: Choose exactly what to clean with an intuitive interface
- **Professional UI**: Modern, clean interface built with SwiftUI
- **Preferences**: Comprehensive settings for customization

## Requirements

- macOS 26 Tahoe or later
- Xcode with Swift 6.2
- Admin privileges (for system cleanup)

## Setup Instructions

### Creating the Xcode Project

1. Open Xcode
2. Create a new project:
   - Choose "macOS" → "App"
   - Product Name: `MacClean`
   - Interface: SwiftUI
   - Language: Swift
   - Minimum Deployment: macOS 26.0
3. Set the bundle identifier (e.g., `com.yourcompany.MacClean`)
4. Add all source files to the project:
   - Drag the `Views`, `Models`, `Services`, and `Utilities` folders into the project
   - Ensure "Copy items if needed" is checked
   - Add to target: MacClean
5. Add the test files:
   - Add `Tests/MacCleanTests` and `Tests/MacCleanUITests` folders
   - Ensure they're added to the test targets

### Project Configuration

1. **Build Settings**:
   - Swift Language Version: Swift 6.2
   - macOS Deployment Target: 26.0

2. **Capabilities**:
   - Add "App Sandbox" capability
   - For system cleanup, you may need to request admin privileges at runtime

3. **Info.plist**:
   - The provided `Info.plist` is a template
   - Xcode will generate most entries automatically
   - Ensure minimum system version is set to 26.0

### Running the App

1. Build and run the project in Xcode
2. The app will launch with the main window
3. Click "Scan" to analyze cleanup opportunities
4. Select categories to clean
5. Click "Clean Selected" to start cleanup

## AI Integration

### LM Studio Setup

1. Install and run LM Studio
2. Start a local server (default: `http://localhost:1234`)
3. Load a model
4. In MacClean preferences, set the API endpoint and model name

### Siri AI

Siri AI integration uses on-device processing. No additional setup required.

## Architecture

- **Models**: Data structures for cleanup items, results, and preferences
- **Services**: Cleanup engine and AI service integrations
- **Views**: SwiftUI views for the main interface and preferences
- **Utilities**: Helper classes for file operations, authorization, and preferences

## Testing

Run unit tests:
```bash
xcodebuild test -scheme MacClean -destination 'platform=macOS'
```

## License

Copyright © 2024 MacClean. All rights reserved.

