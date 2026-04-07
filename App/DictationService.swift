import AVFoundation
import WhisperKit

@MainActor
class DictationService: ObservableObject {
    @Published var status: DictationStatus = .idle
    @Published var modelStatus: String = "Not downloaded"
    @Published var isModelReady = false
    @Published var notificationsReceived = 0
    @Published var confirmedText: String = ""
    @Published var unconfirmedText: String = ""
    @Published var currentText: String = ""

    private var whisperKit: WhisperKit?
    private var streamTranscriber: AudioStreamTranscriber?
    private var silencePlayer: AVAudioPlayer?
    private var pollTimer: Timer?

    private static let modelVariant = "openai_whisper-small"

    // MARK: - Model Management

    func downloadModel() async {
        guard let modelDir = AppGroup.modelDirectoryURL else {
            modelStatus = "Error: no App Group container"
            return
        }

        // WhisperKit handles download + caching when given downloadBase.
        // If model already exists at that path, it loads from cache without re-downloading.
        modelStatus = "Loading..."
        do {
            try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)

            whisperKit = try await WhisperKit(
                WhisperKitConfig(
                    model: Self.modelVariant,
                    downloadBase: modelDir,
                    verbose: true,
                    prewarm: true,
                    load: true
                )
            )
            modelStatus = "Ready"
            isModelReady = true
        } catch {
            modelStatus = "Error: \(error.localizedDescription)"
        }
    }

    // MARK: - Background Audio

    // Activates the audio session with playAndRecord category so the OS keeps the
    // container app alive in the background. Must be called before the user leaves
    // the app so the session persists when the app is backgrounded.
    func setupBackgroundAudio() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.defaultToSpeaker, .allowBluetoothHFP, .mixWithOthers]
            )
            try session.setActive(true)
            startSilenceLoop()
        } catch {
            print("[DictationService] Failed to configure background audio session: \(error)")
        }
    }

    // Play a silent audio loop to keep the app process alive in background.
    // iOS kills background apps that have an audio session but no active audio stream.
    private func startSilenceLoop() {
        let sampleRate: Double = 16000
        let duration: Double = 1.0
        let frameCount = Int(sampleRate * duration)
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else { return }
        buffer.frameLength = AVAudioFrameCount(frameCount)
        // Buffer is already zeroed (silence)

        do {
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("silence.wav")
            let file = try AVAudioFile(forWriting: tempURL, settings: format.settings)
            try file.write(from: buffer)

            silencePlayer = try AVAudioPlayer(contentsOf: tempURL)
            silencePlayer?.numberOfLoops = -1 // infinite loop
            silencePlayer?.volume = 0.0
            silencePlayer?.play()
        } catch {
            print("[DictationService] Failed to start silence loop: \(error)")
        }
    }

    // MARK: - Recording

    func startRecording() {
        guard isModelReady, let wk = whisperKit else { return }

        // Reset streaming state
        confirmedText = ""
        unconfirmedText = ""
        currentText = ""
        status = .recording
        writeStatus(.recording)

        // Stop silence player -- AudioStreamTranscriber's AudioProcessor manages the
        // audio session tap itself, and a concurrent player can conflict.
        silencePlayer?.stop()

        let options = DecodingOptions(
            task: .transcribe,
            language: "fr",
            temperature: 0.0,
            usePrefillPrompt: true,
            skipSpecialTokens: true,
            withoutTimestamps: false,
            noSpeechThreshold: 0.6
        )

        // Capture weak self for the callback, which is called from the actor's context
        let transcriber = AudioStreamTranscriber(
            audioEncoder: wk.audioEncoder,
            featureExtractor: wk.featureExtractor,
            segmentSeeker: wk.segmentSeeker,
            textDecoder: wk.textDecoder,
            tokenizer: wk.tokenizer!,
            audioProcessor: wk.audioProcessor,
            decodingOptions: options,
            stateChangeCallback: { [weak self] _, newState in
                // Filter out Whisper artifacts: [silence], (bruit de porte), *music*, etc.
                func clean(_ text: String) -> String {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty { return "" }
                    // Remove bracketed/parenthesized annotations and asterisk annotations
                    let pattern = #"\[.*?\]|\(.*?\)|\*.*?\*"#
                    let cleaned = trimmed.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
                    // Remove lines with common Whisper artifacts
                    let lower = cleaned.lowercased()
                    if lower.contains("waiting") || lower.contains("silence") || lower.contains("musique") || lower.contains("music") {
                        return ""
                    }
                    return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
                }

                let confirmed = newState.confirmedSegments.map { clean($0.text) }.filter { !$0.isEmpty }.joined(separator: " ")
                let unconfirmed = newState.unconfirmedSegments.map { clean($0.text) }.filter { !$0.isEmpty }.joined(separator: " ")
                let current = clean(newState.currentText)

                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.confirmedText = confirmed
                    self.unconfirmedText = unconfirmed
                    self.currentText = current

                    let partial = [confirmed, unconfirmed, current]
                        .filter { !$0.isEmpty }
                        .joined(separator: " ")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !partial.isEmpty {
                        AppGroup.defaults.set(partial, forKey: SharedKeys.partialTranscription)
                    }
                }
            }
        )

        streamTranscriber = transcriber

        Task {
            do {
                try await transcriber.startStreamTranscription()
            } catch {
                await MainActor.run {
                    self.status = .error
                    self.writeStatus(.error)
                }
            }
        }
    }

    func stopRecording() {
        // Capture text from published properties
        var finalText = [confirmedText, unconfirmedText, currentText]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Fallback: use partialTranscription if published properties were already cleared
        if finalText.isEmpty, let partial = AppGroup.defaults.string(forKey: SharedKeys.partialTranscription) {
            finalText = partial.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Stop the actor
        let transcriber = streamTranscriber
        streamTranscriber = nil
        Task {
            await transcriber?.stopStreamTranscription()
        }

        // Write final result for keyboard extension to pick up
        AppGroup.defaults.set(finalText, forKey: SharedKeys.lastTranscription)
        AppGroup.defaults.set(Date().timeIntervalSince1970, forKey: SharedKeys.lastTranscriptionTimestamp)
        AppGroup.defaults.removeObject(forKey: SharedKeys.partialTranscription)

        status = .ready
        writeStatus(.ready)
        DarwinNotificationCenter.post(DarwinNotificationName.transcriptionReady)

        // Restart silence player to keep the process alive in background
        silencePlayer?.play()
    }

    /// Reset to idle state after dictation is complete.
    /// Called by the UI to transition away from the "done" screen.
    func resetToIdle() {
        status = .idle
        writeStatus(.idle)
    }

    // MARK: - IPC

    private func writeStatus(_ dictationStatus: DictationStatus) {
        AppGroup.defaults.set(dictationStatus.rawValue, forKey: SharedKeys.dictationStatus)
        DarwinNotificationCenter.post(DarwinNotificationName.statusChanged)
    }

    func listenForKeyboardCommands() {
        // Darwin notifications as primary (work when app is foreground)
        DarwinNotificationCenter.addObserver(for: DarwinNotificationName.startRecording) { [weak self] in
            Task { @MainActor in
                self?.notificationsReceived += 1
                self?.startRecording()
            }
        }
        DarwinNotificationCenter.addObserver(for: DarwinNotificationName.stopRecording) { [weak self] in
            Task { @MainActor in
                self?.notificationsReceived += 1
                self?.stopRecording()
            }
        }

        // Polling as fallback (works when app is background with active audio)
        startPolling()
    }

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkForKeyboardCommands()
            }
        }
    }

    private func checkForKeyboardCommands() {
        let defaults = AppGroup.defaults

        if defaults.bool(forKey: SharedKeys.startRequested) {
            defaults.set(false, forKey: SharedKeys.startRequested)
            notificationsReceived += 1
            if status != .recording {
                startRecording()
            }
        }

        if defaults.bool(forKey: SharedKeys.stopRequested) {
            defaults.set(false, forKey: SharedKeys.stopRequested)
            notificationsReceived += 1
            if status == .recording {
                stopRecording()
            }
        }
    }
}
