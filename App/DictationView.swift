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

            if let text = AppGroup.defaults.string(forKey: SharedKeys.lastTranscription), !text.isEmpty,
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
            hasStarted = true
            if dictation.isModelReady {
                dictation.startRecording()
            }
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
