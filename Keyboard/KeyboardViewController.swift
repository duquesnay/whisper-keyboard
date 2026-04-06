import UIKit
import WhisperKit

class KeyboardViewController: UIInputViewController {

    private var whisperKit: WhisperKit?
    private var isRecording = false
    private var micButton: UIButton!
    private var statusLabel: UILabel!

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadModel()
    }

    // MARK: - UI

    private func setupUI() {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 8
        stackView.alignment = .center
        stackView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            stackView.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            stackView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
        ])

        // Top row: globe + status
        let topRow = UIStackView()
        topRow.axis = .horizontal
        topRow.spacing = 12

        let globeButton = UIButton(type: .system)
        globeButton.setImage(UIImage(systemName: "globe"), for: .normal)
        globeButton.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        topRow.addArrangedSubview(globeButton)

        statusLabel = UILabel()
        statusLabel.text = "Loading model..."
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabel
        topRow.addArrangedSubview(statusLabel)

        stackView.addArrangedSubview(topRow)

        // Mic button
        micButton = UIButton(type: .system)
        micButton.setImage(UIImage(systemName: "mic.circle.fill"), for: .normal)
        micButton.setPreferredSymbolConfiguration(.init(pointSize: 44), forImageIn: .normal)
        micButton.tintColor = .systemBlue
        micButton.addTarget(self, action: #selector(micTapped), for: .touchUpInside)
        micButton.isEnabled = false
        stackView.addArrangedSubview(micButton)
    }

    // MARK: - WhisperKit

    private func loadModel() {
        Task {
            do {
                whisperKit = try await WhisperKit(
                    model: "large-v3-turbo",
                    verbose: false
                )
                await MainActor.run {
                    statusLabel.text = "Ready -- tap mic to dictate"
                    micButton.isEnabled = true
                }
            } catch {
                await MainActor.run {
                    statusLabel.text = "Model error: \(error.localizedDescription)"
                }
            }
        }
    }

    @objc private func micTapped() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        guard whisperKit != nil else { return }
        isRecording = true
        micButton.tintColor = .systemRed
        statusLabel.text = "Listening..."

        // TODO: Start audio capture and stream to WhisperKit
        // WhisperKit supports streaming transcription
    }

    private func stopRecording() {
        isRecording = false
        micButton.tintColor = .systemBlue
        statusLabel.text = "Transcribing..."

        // TODO: Stop recording, run transcription, insert text
        // self.textDocumentProxy.insertText(transcribedText)
        // statusLabel.text = "Ready"
    }
}
