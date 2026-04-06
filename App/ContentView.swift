import SwiftUI

struct ContentView: View {
    @State private var modelStatus = "Not downloaded"
    @State private var isDownloading = false

    var body: some View {
        NavigationStack {
            List {
                Section("Setup") {
                    HStack {
                        Text("Whisper Model")
                        Spacer()
                        Text(modelStatus)
                            .foregroundStyle(.secondary)
                    }

                    Button(action: downloadModel) {
                        Label("Download Model", systemImage: "arrow.down.circle")
                    }
                    .disabled(isDownloading)
                }

                Section("Instructions") {
                    Text("1. Go to Settings > General > Keyboard")
                    Text("2. Tap 'Keyboards' > 'Add New Keyboard'")
                    Text("3. Select 'WhisperKeyboard'")
                    Text("4. Enable 'Allow Full Access' (required for microphone)")
                    Text("5. Switch to WhisperKeyboard when typing in any app")
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
    }

    private func downloadModel() {
        isDownloading = true
        modelStatus = "Downloading..."
        // TODO: WhisperKit model download via shared App Group container
    }
}

#Preview {
    ContentView()
}
