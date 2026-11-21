import Foundation

enum PersistenceError: Error, Equatable {
    case corrupt
    case newerVersion(Int)
    case unsupportedFormat
    case tooLarge
    case invalidBackup
}

enum LoadOutcome {
    case missing
    case loaded(ZikrData, droppedElements: Int)
    /// The unreadable file was moved aside (never overwritten); `quarantined` is its new location.
    case corrupt(quarantined: URL?)
    /// Written by a newer version of the app. Nothing may be written until the app is updated.
    case newerVersion(Int)
}

struct SnapshotInfo: Identifiable, Hashable {
    var url: URL
    var day: String
    var id: URL { url }
}

/// Single JSON file in the App Group container, shared between the app, the widget extension
/// and App Intents. All access goes through NSFileCoordinator, every write is atomic, and a
/// file that cannot be decoded is never overwritten.
final class DataFile: @unchecked Sendable {
    static let shared = DataFile(directory: AppGroup.dataDirectory)

    let directory: URL
    let url: URL
    let snapshotsDirectory: URL

    init(directory: URL) {
        self.directory = directory
        self.url = directory.appendingPathComponent("zikr-data.json")
        self.snapshotsDirectory = directory.appendingPathComponent("Snapshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: snapshotsDirectory, withIntermediateDirectories: true)
    }

    // MARK: Coding

    static func encode(_ data: ZikrData) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(data)
    }

    /// Decodes the current format or migrates an older one.
    static func decode(_ raw: Data) throws -> (ZikrData, droppedElements: Int) {
        try Migration.decode(raw)
    }

    // MARK: Read

    func load() -> LoadOutcome {
        var outcome: LoadOutcome = .missing
        var coordinationError: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forMoving, error: &coordinationError) { target in
            guard FileManager.default.fileExists(atPath: target.path) else {
                outcome = .missing
                return
            }
            do {
                let raw = try Data(contentsOf: target)
                let (data, dropped) = try Self.decode(raw)
                if let version = Migration.schemaVersion(of: raw), version < ZikrData.currentSchema {
                    // Keep the original before the first write replaces it with the new schema.
                    try? FileManager.default.copyItem(at: target, to: self.timestampedURL(prefix: "pre-migration-v\(version)"))
                }
                if dropped > 0 {
                    // Keep the untouched original next to the data before anything rewrites it.
                    try? FileManager.default.copyItem(at: target, to: self.timestampedURL(prefix: "recovered"))
                }
                outcome = .loaded(data, droppedElements: dropped)
            } catch PersistenceError.newerVersion(let version) {
                outcome = .newerVersion(version)
            } catch {
                let destination = self.timestampedURL(prefix: "corrupt")
                do {
                    try FileManager.default.moveItem(at: target, to: destination)
                    outcome = .corrupt(quarantined: destination)
                } catch {
                    outcome = .corrupt(quarantined: nil)
                }
            }
        }
        if coordinationError != nil, case .missing = outcome, FileManager.default.fileExists(atPath: url.path) {
            return .corrupt(quarantined: nil)
        }
        return outcome
    }

    /// Read-only access for widgets. Never moves or rewrites anything.
    func peek() -> ZikrData? {
        var result: ZikrData?
        var error: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [], error: &error) { target in
            guard let raw = try? Data(contentsOf: target) else { return }
            result = try? Self.decode(raw).0
        }
        return result
    }

    // MARK: Write

    /// Coordinated read-modify-write. If the file exists but cannot be read, nothing is written.
    @discardableResult
    func update(_ body: (inout ZikrData) throws -> Void) throws -> ZikrData {
        var result: Result<ZikrData, Error> = .failure(PersistenceError.corrupt)
        var coordinationError: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forMerging, error: &coordinationError) { target in
            do {
                var data: ZikrData
                if FileManager.default.fileExists(atPath: target.path) {
                    data = try Self.decode(try Data(contentsOf: target)).0
                } else {
                    data = ZikrData()
                }
                try body(&data)
                try Self.encode(data).write(to: target, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                result = .success(data)
            } catch {
                result = .failure(error)
            }
        }
        if let coordinationError { throw coordinationError }
        return try result.get()
    }

    /// Replaces the whole file (restore from backup or snapshot) without reading it first, so it
    /// also works when the current file is unreadable. The previous file is kept.
    func replace(with data: ZikrData) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.copyItem(at: url, to: timestampedURL(prefix: "before-restore"))
            pruneFiles(prefix: "before-restore", keep: 3)
        }
        let raw = try Self.encode(data)
        var writeError: Error?
        var coordinationError: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { target in
            do {
                try raw.write(to: target, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            } catch {
                writeError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let writeError { throw writeError }
    }

    /// Moves the current file aside (used when starting fresh after an unreadable file).
    @discardableResult
    func quarantineCurrentFile() -> URL? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let destination = timestampedURL(prefix: "corrupt")
        do {
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        } catch {
            try? FileManager.default.copyItem(at: url, to: destination)
            try? FileManager.default.removeItem(at: url)
            return FileManager.default.fileExists(atPath: destination.path) ? destination : nil
        }
    }

    func rawContents() throws -> Data {
        var raw: Data?
        var readError: Error?
        var coordinationError: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [], error: &coordinationError) { target in
            do { raw = try Data(contentsOf: target) } catch { readError = error }
        }
        if let coordinationError { throw coordinationError }
        if let readError { throw readError }
        return raw ?? Data()
    }

    // MARK: Snapshots

    /// Keeps one copy of the data per day for the last 7 days.
    func makeDailySnapshot(now: Date = Date()) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let day = DayKey.key(now)
        let destination = snapshotsDirectory.appendingPathComponent("snapshot-\(day).json")
        if FileManager.default.fileExists(atPath: destination.path) {
            try? FileManager.default.removeItem(at: destination)
        }
        if let raw = try? rawContents(), !raw.isEmpty {
            try? raw.write(to: destination, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        let all = snapshots()
        for old in all.dropFirst(7) { try? FileManager.default.removeItem(at: old.url) }
    }

    /// Newest first.
    func snapshots() -> [SnapshotInfo] {
        let files = (try? FileManager.default.contentsOfDirectory(at: snapshotsDirectory, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.lastPathComponent.hasPrefix("snapshot-") && $0.pathExtension == "json" }
            .map { url in
                let day = url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "snapshot-", with: "")
                return SnapshotInfo(url: url, day: day)
            }
            .sorted { $0.day > $1.day }
    }

    func quarantinedFiles() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { name in ["corrupt-", "recovered-", "pre-migration-"].contains { name.lastPathComponent.hasPrefix($0) } }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    // MARK: Helpers

    private func timestampedURL(prefix: String) -> URL {
        let stamp = Int(Date().timeIntervalSince1970)
        return directory.appendingPathComponent("\(prefix)-\(stamp)-\(UUID().uuidString.prefix(6)).json")
    }

    private func pruneFiles(prefix: String, keep: Int) {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let matching = files.filter { $0.lastPathComponent.hasPrefix(prefix + "-") }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for old in matching.dropFirst(keep) { try? FileManager.default.removeItem(at: old) }
    }
}

// MARK: - Cross-process change notifications

enum DarwinNotifier {
    static var name: String { AppGroup.identifier + ".changed" }

    static func post() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterPostNotification(center, CFNotificationName(name as CFString), nil, nil, true)
    }
}

/// Observes a Darwin notification posted by another process (widget, intent) that changed the file.
final class DarwinObserver {
    private let handler: @MainActor () -> Void
    private let name: String

    init(name: String, handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        self.name = name
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(center, observer, { _, observer, _, _, _ in
            guard let observer else { return }
            let me = Unmanaged<DarwinObserver>.fromOpaque(observer).takeUnretainedValue()
            DispatchQueue.main.async {
                MainActor.assumeIsolated { me.handler() }
            }
        }, name as CFString, nil, .deliverImmediately)
    }

    deinit {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterRemoveObserver(center, Unmanaged.passUnretained(self).toOpaque(),
                                           CFNotificationName(name as CFString), nil)
    }
}
