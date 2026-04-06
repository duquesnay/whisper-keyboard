# WhisperKeyboard

Offline voice dictation keyboard for iOS using WhisperKit (Whisper on CoreML/Neural Engine).

## Goal

Replace Whispr Flow with a free, self-owned, offline custom keyboard that:
- Streams transcription in real-time as user speaks
- Auto-detects French and English (including mixed)
- Works in any app without switching back to the host app
- No subscription, no cloud dependency

## Architecture

WhisperKit cannot run inside the keyboard extension (~50MB memory limit). The container app does all heavy lifting.

- **Container App** (WhisperKeyboard): Downloads models, runs WhisperKit, captures audio via AVAudioEngine, stays alive in background via Background Audio mode
- **Keyboard Extension** (WhisperKeyboardExtension): UI only -- mic button, status display, text insertion via textDocumentProxy
- **Shared/** : App Group constants, Darwin notification helpers, shared keys
- **Communication**: Darwin Notifications (pings) + App Group UserDefaults (data)

```
Container App (background)     Keyboard Extension (foreground)
├── AVAudioEngine             ├── Mic button UI
├── WhisperKit (STT)          ├── Status display
├── Background Audio mode     ├── Globe key (switch keyboard)
└── Model management          └── textDocumentProxy.insertText()
```

## Tech Stack

- Swift / SwiftUI (app) + UIKit (keyboard extension)
- WhisperKit (Argmax) for on-device speech recognition
- CoreML / Apple Neural Engine
- Xcode project generated via xcodegen (project.yml)

## Key Constraints

- Keyboard extensions have ~50MB memory limit -- WhisperKit runs in container app only
- Container app must stay alive in background (Background Audio capability)
- "Allow Full Access" required for microphone access via keyboard extension
- Models stored in shared App Group container
- Darwin notifications carry no payload -- read data from App Group UserDefaults after receiving

## Development

```bash
# Generate Xcode project
xcodegen generate

# Open in Xcode
open WhisperKeyboard.xcodeproj

# Build for device (CLI)
xcodebuild -project WhisperKeyboard.xcodeproj -scheme WhisperKeyboard \
  -destination 'platform=iOS,name=iPhone majeur' \
  -allowProvisioningUpdates build

# Install on device
xcrun devicectl device install app --device 79D4256F-37C7-5086-B0E8-30E17ED51AD0 \
  ~/Library/Developer/Xcode/DerivedData/WhisperKeyboard-*/Build/Products/Debug-iphoneos/WhisperKeyboard.app
```

## Target Device

iPhone 16 Plus (A18, iOS 17+)

## Backlog

GitHub Issues: https://github.com/duquesnay/whisper-keyboard/issues
Milestone: v0.1 Daily Driver
