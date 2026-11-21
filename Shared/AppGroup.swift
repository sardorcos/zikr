import Foundation

/// Shared App Group container used by the app, the widgets and the App Intents.
enum AppGroup {
    static let identifier: String = {
        if let value = Bundle.main.object(forInfoDictionaryKey: "ZIKRAppGroup") as? String,
           value.hasPrefix("group."), !value.contains("$(") {
            return value
        }
        return "group.com.example.zikr"
    }()

    static var isSharedContainerAvailable: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) != nil
    }

    /// Falls back to the private Application Support directory when the App Group is not
    /// provisioned (SwiftUI previews, misconfigured signing) so the app keeps working.
    static var containerURL: URL {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) {
            return url
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    static var dataDirectory: URL {
        containerURL.appendingPathComponent("ZIKR", isDirectory: true)
    }
}

enum RuntimeInfo {
    static let isAppExtension: Bool = Bundle.main.bundlePath.hasSuffix(".appex")

    static var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(short) (\(build))"
    }

    static var privacyPolicyURL: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "ZIKRPrivacyPolicyURL") as? String,
              raw.hasPrefix("https://") else { return nil }
        return URL(string: raw)
    }

    static var supportURL: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "ZIKRSupportURL") as? String,
              raw.hasPrefix("https://") else { return nil }
        return URL(string: raw)
    }
}
