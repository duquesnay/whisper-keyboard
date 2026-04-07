import Foundation

public enum SharedKeys {
    public static let dictationStatus = "wk.dictationStatus"
    public static let lastTranscription = "wk.lastTranscription"
    public static let lastTranscriptionTimestamp = "wk.lastTranscriptionTimestamp"
    public static let activeModel = "wk.activeModel"
    public static let modelReady = "wk.modelReady"
    public static let waveformEnergy = "wk.waveformEnergy"
    public static let stopRequested = "wk.stopRequested"
    public static let startRequested = "wk.startRequested"
    public static let language = "wk.language"
    public static let partialTranscription = "wk.partialTranscription"
    public static let sessionHeartbeat = "wk.sessionHeartbeat"
}

public enum DictationStatus: String {
    case idle
    case recording
    case transcribing
    case ready
    case error
}
