import SwiftUI

@main
struct WhisperKeyboardApp: App {
    @StateObject private var dictation = DictationService()
    @State private var showDictation = false

    var body: some Scene {
        WindowGroup {
            ContentView(dictation: dictation)
                .fullScreenCover(isPresented: $showDictation) {
                    DictationView(dictation: dictation, isPresented: $showDictation)
                }
                .onOpenURL { url in
                    guard url.scheme == "whisperkey", url.host == "dictate" else { return }
                    showDictation = true
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
