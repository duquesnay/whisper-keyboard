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

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Restart polling every time the keyboard appears (extension may have been suspended)
        startPolling()
        // Immediately check for pending transcription
        checkForTranscription()
    }

    override func viewWillSetupKeyboardView() {
        setupKeyboardView { [weak self] controller in
            KeyboardView(
                services: controller.services,
                buttonContent: { $0.view },
                buttonView: { $0.view },
                collapsedView: { $0.view },
                emojiKeyboard: { $0.view },
                toolbar: { _ in
                    HStack(spacing: 10) {
                        // Status: show tail of partial text or status message
                        HStack(spacing: 6) {
                            if self?.dictationState.isRecording == true {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 6, height: 6)
                            }
                            Text(self?.toolbarDisplayText ?? "Tap mic to dictate")
                                .font(.caption)
                                .foregroundStyle(self?.dictationState.isRecording == true ? .primary : .secondary)
                                .lineLimit(1)
                                .truncationMode(.head)
                        }
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

    /// Truncated display text for the toolbar: shows the last ~50 characters
    /// of the partial transcription with a leading ellipsis, so the user sees
    /// the most recent words rather than a truncated beginning.
    private var toolbarDisplayText: String {
        let raw = dictationState.statusText
        if !dictationState.isRecording { return raw }
        // During recording, show tail of partial transcription
        let maxLength = 50
        if raw.count <= maxLength { return raw }
        let tail = String(raw.suffix(maxLength))
        // Find the first word boundary to avoid cutting mid-word
        if let spaceIndex = tail.firstIndex(of: " ") {
            return "..." + String(tail[tail.index(after: spaceIndex)...])
        }
        return "..." + tail
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

        // Check for completed transcription (try lastTranscription first, partialTranscription as fallback)
        let rawStatus = defaults.string(forKey: SharedKeys.dictationStatus) ?? ""
        let text: String? = {
            if let t = defaults.string(forKey: SharedKeys.lastTranscription), !t.isEmpty { return t }
            if rawStatus == "ready", let t = defaults.string(forKey: SharedKeys.partialTranscription), !t.isEmpty { return t }
            return nil
        }()
        guard let text, !text.isEmpty else { return }

        let timestamp = defaults.double(forKey: SharedKeys.lastTranscriptionTimestamp)
        if let lastSeen = lastSeenDate, timestamp <= lastSeen { return }

        // New transcription available
        lastSeenDate = timestamp
        DispatchQueue.main.async { [weak self] in
            self?.dictationState.isRecording = false
            self?.dictationState.statusText = "Inserting..."
            self?.textDocumentProxy.insertText(text)
            // Brief delay so user sees confirmation before reset
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self?.dictationState.statusText = "Tap mic to dictate"
            }
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
