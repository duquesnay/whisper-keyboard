import AVFoundation
import WhisperKit

@MainActor
class DictationService: ObservableObject {
    @Published var status: DictationStatus = .idle
    @Published var modelStatus: String = "Not downloaded"
    @Published var isModelReady = false

    private var whisperKit: WhisperKit?
    private var audioEngine: AVAudioEngine?
    private var audioSamples: [Float] = []
    private let targetSampleRate: Double = 16000

    // MARK: - Model Management

    func downloadModel() async {
        modelStatus = "Downloading..."
        do {
            whisperKit = try await WhisperKit(
                WhisperKitConfig(
                    model: "openai_whisper-small",
                    verbose: false,
                    prewarm: true,
                    load: true
                )
            )
            modelStatus = "Ready"
            isModelReady = true
            AppGroup.defaults.set(true, forKey: SharedKeys.modelReady)
        } catch {
            modelStatus = "Error: \(error.localizedDescription)"
        }
    }

    // MARK: - Recording

    func startRecording() {
        guard isModelReady else { return }

        audioSamples = []
        status = .recording
        writeStatus(.recording)

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .default)
            try session.setActive(true)

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
                skipSpecialTokens: true
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
        DarwinNotificationCenter.addObserver(for: DarwinNotificationName.startRecording) { [weak self] in
            Task { @MainActor in
                self?.startRecording()
            }
        }
        DarwinNotificationCenter.addObserver(for: DarwinNotificationName.stopRecording) { [weak self] in
            Task { @MainActor in
                self?.stopRecording()
            }
        }
    }
}
