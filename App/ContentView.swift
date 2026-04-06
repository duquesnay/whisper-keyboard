import SwiftUI

struct ContentView: View {
    @StateObject private var dictation = DictationService()

    var body: some View {
        NavigationStack {
            List {
                Section("Setup") {
                    HStack {
                        Text("Whisper Model")
                        Spacer()
                        Text(dictation.modelStatus)
                            .foregroundStyle(.secondary)
                    }

                    if !dictation.isModelReady {
                        Button(action: { Task { await dictation.downloadModel() } }) {
                            Label("Download Model", systemImage: "arrow.down.circle")
                        }
                    }
                }

                Section("Dictation") {
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(dictation.status.rawValue)
                            .foregroundStyle(.secondary)
                    }

                    if dictation.isModelReady {
                        Button(action: {
                            if dictation.status == .recording {
                                dictation.stopRecording()
                            } else {
                                dictation.startRecording()
                            }
                        }) {
                            Label(
                                dictation.status == .recording ? "Stop" : "Test Dictation",
                                systemImage: dictation.status == .recording ? "stop.circle.fill" : "mic.circle.fill"
                            )
                        }
                        .tint(dictation.status == .recording ? .red : .blue)
                    }

                    if let text = AppGroup.defaults.string(forKey: SharedKeys.lastTranscription), !text.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Last transcription:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(text)
                        }
                    }
                }

                Section("Debug") {
                    HStack {
                        Text("Notifications received")
                        Spacer()
                        Text("\(dictation.notificationsReceived)")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Keyboard Setup") {
                    Text("1. Go to Settings > General > Keyboard")
                    Text("2. Tap 'Keyboards' > 'Add New Keyboard'")
                    Text("3. Select 'WhisperKeyboard'")
                    Text("4. Enable 'Allow Full Access' (required for microphone)")
                }

                Section("Languages") {
                    Label("French", systemImage: "checkmark.circle.fill")
                    Label("English", systemImage: "checkmark.circle.fill")
                    Text("Auto-detection enabled")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("WhisperKeyboard")
        }
        .onAppear {
            // Set up background audio session before user leaves the app so it
            // persists in background and keeps the process alive for Darwin notifications.
            dictation.setupBackgroundAudio()
            dictation.listenForKeyboardCommands()
        }
    }
}

#Preview {
    ContentView()
}
