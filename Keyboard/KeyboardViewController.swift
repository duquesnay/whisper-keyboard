import UIKit

class KeyboardViewController: UIInputViewController {

    private var micButton: UIButton!
    private var statusLabel: UILabel!
    private var isRecording = false

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        listenForTranscription()
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
        statusLabel.text = "Tap mic to dictate"
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
        stackView.addArrangedSubview(micButton)
    }

    // MARK: - Dictation Control (via Darwin notifications to container app)

    @objc private func micTapped() {
        if isRecording {
            stopDictation()
        } else {
            startDictation()
        }
    }

    private func startDictation() {
        isRecording = true
        micButton.tintColor = .systemRed
        statusLabel.text = "Listening..."

        AppGroup.defaults.set(false, forKey: SharedKeys.stopRequested)
        DarwinNotificationCenter.post(DarwinNotificationName.startRecording)
    }

    private func stopDictation() {
        isRecording = false
        micButton.tintColor = .systemBlue
        statusLabel.text = "Transcribing..."

        AppGroup.defaults.set(true, forKey: SharedKeys.stopRequested)
        DarwinNotificationCenter.post(DarwinNotificationName.stopRecording)
    }

    // MARK: - Receive Transcription

    private func listenForTranscription() {
        DarwinNotificationCenter.addObserver(for: DarwinNotificationName.transcriptionReady) { [weak self] in
            DispatchQueue.main.async {
                self?.handleTranscriptionReady()
            }
        }

        DarwinNotificationCenter.addObserver(for: DarwinNotificationName.statusChanged) { [weak self] in
            DispatchQueue.main.async {
                self?.handleStatusChanged()
            }
        }
    }

    private func handleTranscriptionReady() {
        guard let text = AppGroup.defaults.string(forKey: SharedKeys.lastTranscription), !text.isEmpty else {
            statusLabel.text = "No transcription"
            return
        }

        textDocumentProxy.insertText(text)
        statusLabel.text = "Tap mic to dictate"
        isRecording = false
        micButton.tintColor = .systemBlue
    }

    private func handleStatusChanged() {
        guard let rawStatus = AppGroup.defaults.string(forKey: SharedKeys.dictationStatus),
              let dictationStatus = DictationStatus(rawValue: rawStatus) else { return }

        switch dictationStatus {
        case .recording:
            statusLabel.text = "Listening..."
        case .transcribing:
            statusLabel.text = "Transcribing..."
        case .error:
            statusLabel.text = "Error -- try again"
            isRecording = false
            micButton.tintColor = .systemBlue
        case .idle, .ready:
            break
        }
    }
}
