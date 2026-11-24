# Music iOS App Guidelines

This is a native SwiftUI iOS 17+ application built with SwiftData, AVFoundation, WidgetKit, App Intents, and ActivityKit.

## Architecture & Structure

- **App entry:** `App/MusicApp.swift`
- **Models:** `Models/LibraryModels.swift` (SwiftData models: `Track`, `Playlist`, `Album`)
- **Services:** `Services/` (Playback, Download, Equalizer, Connectivity, Search, Merge, WidgetData, etc.)
- **Views:** `Views/` (SwiftUI views, DesignSystem components, DocumentPicker, URLImportView)
- **ViewModels:** `ViewModels/`
- **Widgets:** `Widgets/` (`MusicWidgets.swift` WidgetKit bundle)
- **Intents:** `Intents/` (`MusicAppIntents.swift` App Intents)
- **Tests:** `Tests/` (`MusicPhase5Tests.swift` XCTest suite)
- **Xcode Project Specification:** `project.yml` (managed via `xcodegen`)

## Build & Test Commands

Use `xcodegen` and `xcodebuild`:

```bash
# Generate Xcode project from project.yml
xcodegen generate

# Build the Music iOS application and Widget Extension
xcodebuild -scheme Music -destination "platform=iOS Simulator,name=iPhone 17" build

# Run unit tests
xcodebuild test -scheme Music -destination "platform=iOS Simulator,name=iPhone 17"
```

## Conventions

- Code targets iOS 17.0+.
- SwiftUI for all UI; follow Swift 6 concurrency rules (`@MainActor`, `Sendable`).
- Do not check in build artifacts (`.build/`, `DerivedData/`, `*.xcuserdata`).
