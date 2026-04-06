import Foundation

public enum DarwinNotificationName {
    public static let startRecording = "com.guillaumeduquesnay.whisper-keyboard.startRecording" as CFString
    public static let stopRecording = "com.guillaumeduquesnay.whisper-keyboard.stopRecording" as CFString
    public static let statusChanged = "com.guillaumeduquesnay.whisper-keyboard.statusChanged" as CFString
    public static let transcriptionReady = "com.guillaumeduquesnay.whisper-keyboard.transcriptionReady" as CFString
    public static let waveformUpdate = "com.guillaumeduquesnay.whisper-keyboard.waveformUpdate" as CFString
}

// Darwin notifications require C function pointers -- no Swift closure capture allowed.
// We store callbacks in a global dictionary keyed by notification name.
private var _darwinCallbacks: [String: () -> Void] = [:]
private let _darwinCallbackLock = NSLock()

private let _darwinCallback: CFNotificationCallback = { _, _, cfName, _, _ in
    guard let cfName else { return }
    let key = cfName.rawValue as String
    _darwinCallbackLock.lock()
    let cb = _darwinCallbacks[key]
    _darwinCallbackLock.unlock()
    cb?()
}

public enum DarwinNotificationCenter {
    public static func post(_ name: CFString) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(name), nil, nil, true
        )
    }

    public static func addObserver(for name: CFString, callback: @escaping () -> Void) {
        _darwinCallbackLock.lock()
        _darwinCallbacks[name as String] = callback
        _darwinCallbackLock.unlock()
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            nil, _darwinCallback, name, nil, .deliverImmediately
        )
    }

    public static func removeObserver(for name: CFString) {
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            nil, CFNotificationName(name), nil
        )
        _darwinCallbackLock.lock()
        _darwinCallbacks.removeValue(forKey: name as String)
        _darwinCallbackLock.unlock()
    }
}
