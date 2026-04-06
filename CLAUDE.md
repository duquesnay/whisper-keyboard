# WhisperKeyboard

Offline voice dictation keyboard for iOS using WhisperKit (Whisper on CoreML/Neural Engine).

## Goal

Replace Whispr Flow with a free, self-owned, offline custom keyboard that:
- Runs Whisper locally on iPhone (A18 Neural Engine)
- Auto-detects French and English
- Works in any app without switching back to the host app
- No subscription, no cloud dependency

## Architecture

- **Container App** (WhisperKeyboard): Downloads models, shows setup instructions
- **Keyboard Extension** (WhisperKeyboardExtension): Custom keyboard with mic button, runs WhisperKit for STT
- **Shared App Group**: Models downloaded by the app are accessible by the extension

## Tech Stack

- Swift / SwiftUI (app) + UIKit (keyboard extension)
- WhisperKit (Argmax) for on-device speech recognition
- CoreML / Apple Neural Engine
- Xcode project generated via xcodegen (project.yml)

## Key Constraints

- Keyboard extensions have limited memory (~50MB). large-v3-turbo may not fit; may need to use smaller models or stream from the app.
- "Allow Full Access" required for microphone in keyboard extension.
- Models stored in shared App Group container so both app and extension can access them.

## Development

```bash
# Generate Xcode project
xcodegen generate

# Open in Xcode
open WhisperKeyboard.xcodeproj
```

## Target Device

iPhone 16 (A18, iOS 17+)
