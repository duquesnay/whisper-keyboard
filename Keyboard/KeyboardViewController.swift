import KeyboardKit
import SwiftUI

final class DictationState: ObservableObject {
    @Published var isRecording = false
    @Published var statusText = "Tap mic to dictate"
}

class KeyboardViewController: KeyboardInputViewController {

    let dictationState = DictationState()

    override func viewWillSetupKeyboardView() {
        setupKeyboardView { [weak self] controller in
            KeyboardView(
                services: controller.services,
                buttonContent: { $0.view },
                buttonView: { $0.view },
                collapsedView: { $0.view },
                emojiKeyboard: { $0.view },
                toolbar: { _ in
                    HStack(spacing: 12) {
                        Text(self?.dictationState.statusText ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Button {
                            self?.toggleDictation()
                        } label: {
                            Image(systemName: self?.dictationState.isRecording == true ? "stop.circle.fill" : "mic.circle.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(self?.dictationState.isRecording == true ? Color.red : Color.blue)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
            )
        }

        listenForTranscription()
    }

    // MARK: - Dictation control

    func toggleDictation() {
        if dictationState.isRecording {
            dictationState.isRecording = false
            dictationState.statusText = "Transcribing..."
            AppGroup.defaults.set(true, forKey: SharedKeys.stopRequested)
            AppGroup.defaults.set(false, forKey: SharedKeys.startRequested)
            DarwinNotificationCenter.post(DarwinNotificationName.stopRecording)
        } else {
            dictationState.isRecording = true
            dictationState.statusText = "Listening..."
            AppGroup.defaults.set(true, forKey: SharedKeys.startRequested)
            AppGroup.defaults.set(false, forKey: SharedKeys.stopRequested)
            DarwinNotificationCenter.post(DarwinNotificationName.startRecording)
        }
    }

    // MARK: - Receive Transcription

    private func listenForTranscription() {
        DarwinNotificationCenter.addObserver(for: DarwinNotificationName.transcriptionReady) { [weak self] in
            DispatchQueue.main.async { self?.handleTranscriptionReady() }
        }
        DarwinNotificationCenter.addObserver(for: DarwinNotificationName.statusChanged) { [weak self] in
            DispatchQueue.main.async { self?.handleStatusChanged() }
        }
    }

    private func handleTranscriptionReady() {
        guard let text = AppGroup.defaults.string(forKey: SharedKeys.lastTranscription), !text.isEmpty else {
            dictationState.isRecording = false
            dictationState.statusText = "Tap mic to dictate"
            return
        }
        textDocumentProxy.insertText(text)
        dictationState.isRecording = false
        dictationState.statusText = "Tap mic to dictate"
    }

    private func handleStatusChanged() {
        guard let rawStatus = AppGroup.defaults.string(forKey: SharedKeys.dictationStatus),
              let status = DictationStatus(rawValue: rawStatus) else { return }
        switch status {
        case .recording:
            dictationState.statusText = "Listening..."
        case .transcribing:
            dictationState.statusText = "Transcribing..."
        case .error:
            dictationState.isRecording = false
            dictationState.statusText = "Error -- try again"
        case .idle, .ready:
            break
        }
    }
}
