# WhisperKeyboard -- Project Framing

## Why
Replace Whispr Flow with a free, self-owned, offline voice dictation keyboard for iOS that works seamlessly in any app without app switching.

**Pain points with Whispr Flow:**
- Paid subscription
- Online (not offline)
- Must switch to Wispr app and back for keyboard authorization on every app change

## What (v0.1 -- Daily Driver)
A custom iOS keyboard that transcribes speech to text in real-time, offline, in French and English (including mixed).

### Done Criteria (v0.1)
- [ ] Streaming transcription: text appears while speaking (#2)
- [ ] Fully offline after initial model download
- [ ] Bilingual FR/EN with code-switching (#3)
- [ ] No app switching needed (#1, #4)
- [ ] Works in any iOS app with a text field

### Out of Scope (v0.1)
- Full keyboard layout (typing keys)
- Punctuation commands
- Multiple model selection in-app
- iPad support
- macOS companion

## Architecture
```
Container App (background)     Keyboard Extension (foreground)
├── AVAudioEngine             ├── Mic button UI
├── WhisperKit (STT)          ├── Status display
├── Background Audio mode     ├── Globe key (switch keyboard)
└── Model management          └── textDocumentProxy.insertText()

Communication: Darwin Notifications + App Group UserDefaults
```

**Key constraint:** WhisperKit cannot run in keyboard extension (~50MB RAM limit). Container app does all heavy lifting.

## Tech Stack
- Swift / SwiftUI + UIKit
- WhisperKit (Argmax) -- CoreML on Neural Engine
- Model: openai_whisper-small (250MB)
- xcodegen for project generation
- Target: iPhone 16 Plus (A18), iOS 17+

## Team
Solo dev + AI (Claude Code)

## Risks
| Risk | Impact | Mitigation |
|------|--------|------------|
| Container app killed by iOS | Dictation stops | Background Audio capability, silent audio session |
| Whisper-small too slow for streaming | Poor UX | Try smaller model or Parakeet |
| FR/EN code-switching inaccurate | Core feature broken | Test with real usage, tune prompts |
| Model too large for device storage | Can't install | Offer model size selection |

## Backlog
GitHub Issues: https://github.com/duquesnay/whisper-keyboard/issues
