import Foundation

public enum AppGroup {
    public static let identifier = "group.com.guillaumeduquesnay.whisper-keyboard"

    public static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier)!
    }

    public static var containerURL: URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: identifier
        )
    }

    public static var modelDirectoryURL: URL? {
        containerURL?.appendingPathComponent("WhisperModels", isDirectory: true)
    }
}
