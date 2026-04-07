import SwiftUI

@main
struct WhisperKeyboardApp: App {
    @StateObject private var dictation = DictationService()

    var body: some Scene {
        WindowGroup {
            ContentView(dictation: dictation)
                .onOpenURL { url in
                    guard url.scheme == "whisperkey", url.host == "dictate" else { return }
                    // URL launch from keyboard extension → start recording immediately
                    if dictation.isModelReady {
                        dictation.startRecording()
                    }
                    // If model not ready yet, the user will see the loading state
                    // and can tap the mic button once it's ready.
                }
                .task {
                    // Setup audio session at app launch, before any UI
                    dictation.setupBackgroundAudio()
                    dictation.listenForKeyboardCommands()
                    // Auto-download model if not ready
                    if !dictation.isModelReady {
                        await dictation.downloadModel()
                    }
                }
        }
    }
}
