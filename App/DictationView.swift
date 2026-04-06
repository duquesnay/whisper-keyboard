import SwiftUI

struct DictationView: View {
    @ObservedObject var dictation: DictationService
    @Binding var isPresented: Bool
    @State private var hasStarted = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: iconName)
                .font(.system(size: 80))
                .foregroundStyle(iconColor)

            Text(statusText)
                .font(.title2)
                .foregroundStyle(.secondary)

            if !dictation.isModelReady {
                Text("Model: \(dictation.modelStatus)")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if dictation.status == .recording {
                // Show streaming text in real-time as speech is recognized
                streamingTextView
            } else if let text = AppGroup.defaults.string(forKey: SharedKeys.lastTranscription), !text.isEmpty,
                      dictation.status == .ready {
                Text(text)
                    .font(.body)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
                    .padding(.horizontal)
            }

            Spacer()

            HStack(spacing: 40) {
                Button("Cancel") {
                    if dictation.status == .recording {
                        dictation.stopRecording()
                    }
                    isPresented = false
                }
                .foregroundStyle(.secondary)

                if dictation.isModelReady {
                    Button(dictation.status == .recording ? "Done" : "Start") {
                        if dictation.status == .recording {
                            dictation.stopRecording()
                        } else {
                            dictation.startRecording()
                        }
                    }
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 12)
                    .background(dictation.status == .recording ? Color.red : Color.blue)
                    .cornerRadius(25)
                }
            }
            .padding(.bottom, 40)
        }
        .onAppear {
            guard !hasStarted else { return }
            if dictation.isModelReady {
                hasStarted = true
                dictation.startRecording()
            }
            // If model not ready yet, onChange will catch it
        }
        .onChange(of: dictation.isModelReady) { _, ready in
            if ready && !hasStarted {
                hasStarted = true
                dictation.startRecording()
            }
        }
        .onChange(of: dictation.status) { _, newStatus in
            if newStatus == .ready {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    isPresented = false
                }
            }
        }
    }

    // Streaming text view shown while recording; layers confirmed / unconfirmed / current
    // with decreasing emphasis so the user can see what's locked in vs still in flux.
    @ViewBuilder
    private var streamingTextView: some View {
        let hasAny = !dictation.confirmedText.isEmpty
            || !dictation.unconfirmedText.isEmpty
            || !dictation.currentText.isEmpty

        if hasAny {
            ScrollViewReader { proxy in
                ScrollView {
                    (
                        Text(dictation.confirmedText).foregroundStyle(.primary)
                        + Text(dictation.confirmedText.isEmpty || dictation.unconfirmedText.isEmpty ? "" : " ")
                        + Text(dictation.unconfirmedText).foregroundStyle(.secondary)
                        + Text(dictation.unconfirmedText.isEmpty || dictation.currentText.isEmpty ? "" : " ")
                        + Text(dictation.currentText).foregroundStyle(.tertiary)
                    )
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id("streamingText")
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
                .padding(.horizontal)
                .frame(maxHeight: 200)
                .onChange(of: dictation.currentText) { _, _ in
                    withAnimation {
                        proxy.scrollTo("streamingText", anchor: .bottom)
                    }
                }
            }
        }
    }

    private var iconName: String {
        switch dictation.status {
        case .recording: return "waveform.circle.fill"
        case .transcribing: return "brain"
        default: return "mic.circle.fill"
        }
    }

    private var iconColor: Color {
        switch dictation.status {
        case .recording: return .red
        case .transcribing: return .orange
        default: return .blue
        }
    }

    private var statusText: String {
        if !dictation.isModelReady {
            return "Loading model..."
        }
        switch dictation.status {
        case .idle: return "Ready"
        case .recording: return "Listening..."
        case .transcribing: return "Transcribing..."
        case .ready: return "Done!"
        case .error: return "Error"
        }
    }
}
