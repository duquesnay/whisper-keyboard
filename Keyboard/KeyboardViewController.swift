import KeyboardKit
import SwiftUI

// MARK: - DictationState

/// Observable state model shared between the view controller and SwiftUI toolbar.
final class DictationState: ObservableObject {
    @Published var isRecording = false
    @Published var statusText = "Tap mic to dictate"
}

// MARK: - KeyboardViewController

class KeyboardViewController: KeyboardInputViewController {

    let dictationState = DictationState()

    // MARK: - KeyboardKit Setup

    override func viewWillSetupKeyboardView() {
        // Per KeyboardKit docs: do NOT call super here
        setupKeyboardView { [weak self] controller in
            WhisperKeyboardView(
                dictationState: self?.dictationState ?? DictationState(),
                viewController: self,
                services: controller.services
            )
        }

        listenForTranscription()
    }

    // MARK: - Dictation control

    func startDictation() {
        dictationState.isRecording = true
        dictationState.statusText = "Listening..."
        AppGroup.defaults.set(true, forKey: SharedKeys.startRequested)
        AppGroup.defaults.set(false, forKey: SharedKeys.stopRequested)
        DarwinNotificationCenter.post(DarwinNotificationName.startRecording)
    }

    func stopDictation() {
        dictationState.isRecording = false
        dictationState.statusText = "Transcribing..."
        AppGroup.defaults.set(true, forKey: SharedKeys.stopRequested)
        AppGroup.defaults.set(false, forKey: SharedKeys.startRequested)
        DarwinNotificationCenter.post(DarwinNotificationName.stopRecording)
    }

    func toggleDictation() {
        if dictationState.isRecording {
            stopDictation()
        } else {
            startDictation()
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
            dictationState.isRecording = true
            dictationState.statusText = "Listening..."
        case .transcribing:
            dictationState.isRecording = false
            dictationState.statusText = "Transcribing..."
        case .error:
            dictationState.isRecording = false
            dictationState.statusText = "Error -- try again"
        case .idle, .ready:
            break
        }
    }
}

// MARK: - WhisperKeyboardView

/// Top-level SwiftUI view wrapping KeyboardView with a custom mic toolbar.
struct WhisperKeyboardView: View {

    @ObservedObject var dictationState: DictationState
    weak var viewController: KeyboardViewController?
    var services: Keyboard.Services

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("WHISPER")
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
                Spacer()
                Button {
                    viewController?.toggleDictation()
                } label: {
                    Image(systemName: dictationState.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(dictationState.isRecording ? .red : .blue)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.yellow.opacity(0.3))

            KeyboardView(
                services: services,
                buttonContent: { $0.view },
                buttonView: { $0.view },
                collapsedView: { $0.view },
                emojiKeyboard: { $0.view },
                toolbar: { _ in EmptyView() }
            )
        }
    }
}

// MARK: - WhisperToolbar

/// SwiftUI toolbar with globe key switcher, status label, and mic button.
struct WhisperToolbar: View {

    @ObservedObject var dictationState: DictationState
    weak var viewController: KeyboardViewController?

    var body: some View {
        HStack(spacing: 12) {
            if let vc = viewController {
                GlobeButton(viewController: vc)
                    .frame(width: 28, height: 28)
            }

            Text(dictationState.statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)

            Button {
                viewController?.toggleDictation()
            } label: {
                Image(systemName: dictationState.isRecording ? "mic.fill" : "mic.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(dictationState.isRecording ? Color.red : Color.blue)
                    .animation(.easeInOut(duration: 0.15), value: dictationState.isRecording)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

// MARK: - GlobeButton

/// Wraps UIKit's handleInputModeList for keyboard switching.
/// This API requires a UIEvent which only UIKit can supply, so UIViewRepresentable is necessary.
private struct GlobeButton: UIViewRepresentable {

    weak var viewController: KeyboardViewController?

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "globe"), for: .normal)
        button.addTarget(
            viewController,
            action: #selector(KeyboardInputViewController.handleInputModeList(from:with:)),
            for: .allTouchEvents
        )
        return button
    }

    func updateUIView(_ uiView: UIButton, context: Context) {}
}
