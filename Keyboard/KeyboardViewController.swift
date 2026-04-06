import KeyboardKit
import SwiftUI
import UIKit

final class DictationState: ObservableObject {
    @Published var isRecording = false
    @Published var statusText = "Tap mic to dictate"
}

class KeyboardViewController: KeyboardInputViewController {

    let dictationState = DictationState()
    private var pollTimer: Timer?
    private var lastSeenDate: TimeInterval?

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
                            self?.micTapped()
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

        startPolling()
    }

    // MARK: - Mic action

    private func micTapped() {
        // Clear previous result
        AppGroup.defaults.removeObject(forKey: SharedKeys.lastTranscription)
        AppGroup.defaults.removeObject(forKey: SharedKeys.lastTranscriptionTimestamp)

        dictationState.isRecording = true
        dictationState.statusText = "Opening app..."

        // Open container app via deep link
        openContainerApp()
    }

    private func openContainerApp() {
        guard let url = URL(string: "whisperkey://dictate") else { return }

        // Walk the responder chain to find UIApplication and open the URL
        var responder: UIResponder? = self
        while let next = responder?.next {
            if let application = next as? UIApplication {
                application.open(url, options: [:], completionHandler: nil)
                return
            }
            responder = next
        }

        // Fallback: selector-based approach
        let selector = NSSelectorFromString("openURL:")
        responder = self
        while let next = responder?.next {
            if next.responds(to: selector) {
                next.perform(selector, with: url)
                return
            }
            responder = next
        }
    }

    // MARK: - Polling for results

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkForTranscription()
        }
    }

    private func checkForTranscription() {
        let defaults = AppGroup.defaults

        // Check dictation status for UI updates
        if let rawStatus = defaults.string(forKey: SharedKeys.dictationStatus) {
            DispatchQueue.main.async { [weak self] in
                switch rawStatus {
                case "recording":
                    self?.dictationState.isRecording = true
                    // Show partial transcription preview if available, otherwise "Listening..."
                    // Note: partial text is displayed only as a status preview, never inserted
                    if let partial = defaults.string(forKey: SharedKeys.partialTranscription), !partial.isEmpty {
                        self?.dictationState.statusText = partial
                    } else {
                        self?.dictationState.statusText = "Listening..."
                    }
                case "transcribing":
                    self?.dictationState.isRecording = false
                    self?.dictationState.statusText = "Transcribing..."
                default:
                    break
                }
            }
        }

        // Check for completed transcription
        guard let text = defaults.string(forKey: SharedKeys.lastTranscription),
              !text.isEmpty else { return }

        let timestamp = defaults.double(forKey: SharedKeys.lastTranscriptionTimestamp)
        if let lastSeen = lastSeenDate, timestamp <= lastSeen { return }

        // New transcription available
        lastSeenDate = timestamp
        DispatchQueue.main.async { [weak self] in
            self?.textDocumentProxy.insertText(text)
            self?.dictationState.isRecording = false
            self?.dictationState.statusText = "Tap mic to dictate"
        }

        // Clean up
        defaults.removeObject(forKey: SharedKeys.lastTranscription)
        defaults.removeObject(forKey: SharedKeys.lastTranscriptionTimestamp)
        defaults.set(DictationStatus.idle.rawValue, forKey: SharedKeys.dictationStatus)
    }

    deinit {
        pollTimer?.invalidate()
    }
}
