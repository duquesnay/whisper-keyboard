import AVFoundation
import WhisperKit

@MainActor
class DictationService: ObservableObject {
    @Published var status: DictationStatus = .idle
    @Published var modelStatus: String = "Not downloaded"
    @Published var isModelReady = false
    @Published var notificationsReceived = 0

    private var whisperKit: WhisperKit?
    private var audioEngine: AVAudioEngine?
    private var audioSamples: [Float] = []
    private let targetSampleRate: Double = 16000
    private var silencePlayer: AVAudioPlayer?
    private var pollTimer: Timer?

    private static let modelVariant = "openai_whisper-small"

    // MARK: - Model Management

    func downloadModel() async {
        // Use App Group container so model survives app reinstalls
        guard let modelDir = AppGroup.modelDirectoryURL else {
            modelStatus = "Error: no App Group container"
            return
        }

        // Check if model already exists locally
        let localModelPath = modelDir.appendingPathComponent(Self.modelVariant).path
        let modelExists = FileManager.default.fileExists(atPath: localModelPath)

        if modelExists {
            modelStatus = "Loading..."
            do {
                whisperKit = try await WhisperKit(
                    WhisperKitConfig(
                        model: Self.modelVariant,
                        modelFolder: localModelPath,
                        verbose: false,
                        prewarm: true,
                        load: true,
                        download: false
                    )
                )
                modelStatus = "Ready"
                isModelReady = true
                return
            } catch {
                modelStatus = "Redownloading..."
            }
        }

        // Download model to App Group container
        modelStatus = "Downloading..."
        do {
            try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)

            let folderURL = try await WhisperKit.download(
                variant: Self.modelVariant,
                from: "argmaxinc/whisperkit-coreml",
                progressCallback: { progress in
                    Task { @MainActor in
                        self.modelStatus = "Downloading \(Int(progress.fractionCompleted * 100))%"
                    }
                }
            )

            // Copy downloaded model to App Group container
            let destPath = modelDir.appendingPathComponent(Self.modelVariant)
            if FileManager.default.fileExists(atPath: destPath.path) {
                try FileManager.default.removeItem(at: destPath)
            }
            try FileManager.default.copyItem(at: folderURL, to: destPath)

            whisperKit = try await WhisperKit(
                WhisperKitConfig(
                    model: Self.modelVariant,
                    modelFolder: destPath.path,
                    verbose: false,
                    prewarm: true,
                    load: true,
                    download: false
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
        guard isModelReady else { return }

        audioSamples = []
        status = .recording
        writeStatus(.recording)

        do {
            // Audio session is already active (set up at launch via setupBackgroundAudio).
            // We only need to wire up the engine and tap here.
            audioEngine = AVAudioEngine()
            guard let audioEngine else { return }

            let inputNode = audioEngine.inputNode
            let hwFormat = inputNode.outputFormat(forBus: 0)

            inputNode.installTap(onBus: 0, bufferSize: 4096, format: hwFormat) { [weak self] buffer, _ in
                self?.processAudioBuffer(buffer, from: hwFormat)
            }

            try audioEngine.start()
        } catch {
            status = .error
            writeStatus(.error)
        }
    }

    func stopRecording() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil

        Task { await transcribe() }
    }

    // MARK: - Transcription

    private func transcribe() async {
        guard let whisperKit, !audioSamples.isEmpty else {
            status = .idle
            writeStatus(.idle)
            return
        }

        status = .transcribing
        writeStatus(.transcribing)

        do {
            let options = DecodingOptions(
                task: .transcribe,
                temperature: 0.0,
                usePrefillPrompt: true,
                skipSpecialTokens: true,
                withoutTimestamps: true,
                noSpeechThreshold: 0.6
            )

            let results = try await whisperKit.transcribe(
                audioArray: audioSamples,
                decodeOptions: options
            )

            let text = results.map { $0.text }
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            AppGroup.defaults.set(text, forKey: SharedKeys.lastTranscription)
            AppGroup.defaults.set(Date().timeIntervalSince1970, forKey: SharedKeys.lastTranscriptionTimestamp)

            status = .ready
            writeStatus(.ready)
            DarwinNotificationCenter.post(DarwinNotificationName.transcriptionReady)
        } catch {
            status = .error
            writeStatus(.error)
        }
    }

    // MARK: - Audio Processing

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, from sourceFormat: AVAudioFormat) {
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ) else { return }

        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else { return }

        let ratio = targetSampleRate / sourceFormat.sampleRate
        let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCount) else { return }

        var error: NSError?
        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        guard error == nil, let channelData = outputBuffer.floatChannelData else { return }
        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: Int(outputBuffer.frameLength)))
        audioSamples.append(contentsOf: samples)

        // Write waveform energy for keyboard extension UI
        let energy = samples.reduce(0) { $0 + abs($1) } / Float(samples.count)
        AppGroup.defaults.set(energy, forKey: SharedKeys.waveformEnergy)
        DarwinNotificationCenter.post(DarwinNotificationName.waveformUpdate)
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
