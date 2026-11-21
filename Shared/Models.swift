import Foundation

// MARK: - Limits

enum Limits {
    static let maxValue = 1_000_000_000
    static let titleLength = 80
    static let noteLength = 1_000
    static let activeCounters = 100
    static let activePrograms = 50
    static let steps = 30
    static let reminders = 8
    static let pinned = 3
    static let undoLog = 100
    static let journal = 200
    static let backupBytes = 20 * 1024 * 1024
}

// MARK: - Settings

enum AppLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case ru
    case uz
    case uzCyrl = "uz-Cyrl"
    case en

    var id: String { rawValue }

    var nativeName: String {
        switch self {
        case .ru: return "Русский"
        case .uz: return "O‘zbekcha"
        case .uzCyrl: return "Ўзбекча"
        case .en: return "English"
        }
    }

    var locale: Locale {
        switch self {
        case .ru: return Locale(identifier: "ru_RU")
        case .uz: return Locale(identifier: "uz_Latn_UZ")
        case .uzCyrl: return Locale(identifier: "uz_Cyrl_UZ")
        case .en: return Locale(identifier: "en_US")
        }
    }

    /// Picks the best supported language from the device's preferred languages.
    static func preferred(_ preferred: [String] = Locale.preferredLanguages) -> AppLanguage {
        for raw in preferred {
            let id = raw.lowercased()
            if id.hasPrefix("uz-cyrl") { return .uzCyrl }
            if id.hasPrefix("uz") { return .uz }
            if id.hasPrefix("ru") { return .ru }
            if id.hasPrefix("en") { return .en }
            // Central Asian users usually read Russian better than English.
            if ["kk", "ky", "tg", "tk", "be"].contains(where: { id.hasPrefix($0) }) { return .ru }
        }
        return .en
    }
}

enum AppAppearance: String, Codable, CaseIterable, Identifiable, Sendable {
    case system, light, dark
    var id: String { rawValue }
}

struct AppSettings: Codable, Equatable, Sendable {
    /// nil = follow the device language.
    var language: AppLanguage? = nil
    var appearance: AppAppearance = .system
    var haptics: Bool = true
    var keepScreenOn: Bool = true
    var nightShowDigits: Bool = true
    var nightDigitsOpacity: Double = 0.35

    init() {}

    enum CodingKeys: String, CodingKey {
        case language, appearance, haptics, keepScreenOn, nightShowDigits, nightDigitsOpacity
    }
}

extension AppSettings {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        language = c.optional(.language)
        appearance = c.value(.appearance, default: .system)
        haptics = c.value(.haptics, default: true)
        keepScreenOn = c.value(.keepScreenOn, default: true)
        nightShowDigits = c.value(.nightShowDigits, default: true)
        nightDigitsOpacity = min(1, max(0.1, c.value(.nightDigitsOpacity, default: 0.35)))
    }
}

// MARK: - References

struct ItemRef: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable { case counter, program }
    var kind: Kind
    var id: UUID

    static func counter(_ id: UUID) -> ItemRef { ItemRef(kind: .counter, id: id) }
    static func program(_ id: UUID) -> ItemRef { ItemRef(kind: .program, id: id) }

    var storageString: String { "\(kind.rawValue):\(id.uuidString)" }

    init(kind: Kind, id: UUID) {
        self.kind = kind
        self.id = id
    }

    init?(storageString: String) {
        let parts = storageString.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let kind = Kind(rawValue: parts[0]), let id = UUID(uuidString: parts[1]) else {
            return nil
        }
        self.kind = kind
        self.id = id
    }
}

// MARK: - Counter

struct TapRecord: Codable, Equatable, Sendable {
    var day: String
    var at: Date
}

enum JournalKind: String, Codable, Sendable {
    case baseline, adjustment
}

struct JournalEntry: Codable, Identifiable, Equatable, Sendable {
    var id: UUID = UUID()
    var kind: JournalKind
    var at: Date
    var before: Int
    var after: Int
}

/// A free counter. History is stored as per-day aggregates, so the file stays small
/// no matter how many taps a person makes. Only a short tail of taps is kept for undo.
struct Counter: Codable, Identifiable, Equatable, Sendable {
    var id: UUID = UUID()
    var title: String
    var value: Int = 0
    var goal: Int? = nil
    var interval: Int? = nil
    var dailyGoal: Int? = nil
    var note: String = ""
    var pinned: Bool = false
    var archived: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    /// Day key → net taps that day (taps minus undos). Corrections are never counted here.
    var daily: [String: Int] = [:]
    /// Day key → seconds measured with the stopwatch.
    var seconds: [String: Int] = [:]
    /// The most recent taps that can still be undone (cleared by a manual correction).
    var undoLog: [TapRecord] = []
    var journal: [JournalEntry] = []

    enum CodingKeys: String, CodingKey {
        case id, title, value, goal, interval, dailyGoal, note, pinned, archived
        case createdAt, updatedAt, daily, seconds, undoLog, journal
    }
}

extension Counter {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(title: c.value(.title, default: "—"))
        id = c.value(.id, default: UUID())
        value = c.value(.value, default: 0)
        goal = c.optional(.goal)
        interval = c.optional(.interval)
        dailyGoal = c.optional(.dailyGoal)
        note = c.value(.note, default: "")
        pinned = c.value(.pinned, default: false)
        archived = c.value(.archived, default: false)
        createdAt = c.value(.createdAt, default: Date())
        updatedAt = c.value(.updatedAt, default: createdAt)
        daily = c.value(.daily, default: [:])
        seconds = c.value(.seconds, default: [:])
        undoLog = c.lossyArray(.undoLog)
        journal = c.lossyArray(.journal)
    }
}

// MARK: - Program

struct ProgramStep: Codable, Identifiable, Equatable, Sendable {
    var id: UUID = UUID()
    var title: String
    var target: Int

    enum CodingKeys: String, CodingKey { case id, title, target }
}

extension ProgramStep {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(title: c.value(.title, default: "—"), target: max(1, c.value(.target, default: 1)))
        id = c.value(.id, default: UUID())
    }
}

/// Taps grouped by day, newest last. Lets undo credit the right day without storing every tap.
struct DayRun: Codable, Equatable, Sendable {
    var day: String
    var count: Int
}

extension Array where Element == DayRun {
    mutating func push(_ day: String) {
        if let last = indices.last, self[last].day == day {
            self[last].count += 1
        } else {
            append(DayRun(day: day, count: 1))
        }
    }

    /// Removes one tap from the newest run and returns its day.
    mutating func pop() -> String? {
        guard let last = indices.last else { return nil }
        let day = self[last].day
        self[last].count -= 1
        if self[last].count <= 0 { removeLast() }
        return day
    }
}

/// An in-progress run through a program. Persisted so progress survives app restarts.
struct ProgramSession: Codable, Equatable, Sendable {
    var stepIndex: Int = 0
    var count: Int = 0
    var startedAt: Date = Date()
    var dayRuns: [DayRun] = []

    enum CodingKeys: String, CodingKey { case stepIndex, count, startedAt, dayRuns }
}

extension ProgramSession {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        stepIndex = max(0, c.value(.stepIndex, default: 0))
        count = max(0, c.value(.count, default: 0))
        startedAt = c.value(.startedAt, default: Date())
        dayRuns = c.lossyArray(.dayRuns)
    }
}

/// The run that was just completed, kept so the final tap can still be undone.
struct CompletedRun: Codable, Equatable, Sendable {
    var day: String
    var startedAt: Date
    var dayRuns: [DayRun]
}

/// A user-built sequence of steps (for example 33 + 33 + 34). The app ships no texts:
/// every title is written by the user.
struct Program: Codable, Identifiable, Equatable, Sendable {
    var id: UUID = UUID()
    var title: String
    var steps: [ProgramStep]
    var note: String = ""
    var pinned: Bool = false
    var archived: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var daily: [String: Int] = [:]
    var completions: [String: Int] = [:]
    var seconds: [String: Int] = [:]
    var session: ProgramSession? = nil
    var lastCompleted: CompletedRun? = nil

    var totalTarget: Int { steps.reduce(0) { $0 + $1.target } }
    var totalCompletions: Int { completions.values.reduce(0, +) }

    enum CodingKeys: String, CodingKey {
        case id, title, steps, note, pinned, archived, createdAt, updatedAt
        case daily, completions, seconds, session, lastCompleted
    }
}

extension Program {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(title: c.value(.title, default: "—"), steps: c.lossyArray(.steps))
        id = c.value(.id, default: UUID())
        note = c.value(.note, default: "")
        pinned = c.value(.pinned, default: false)
        archived = c.value(.archived, default: false)
        createdAt = c.value(.createdAt, default: Date())
        updatedAt = c.value(.updatedAt, default: createdAt)
        daily = c.value(.daily, default: [:])
        completions = c.value(.completions, default: [:])
        seconds = c.value(.seconds, default: [:])
        session = c.optional(.session)
        lastCompleted = c.optional(.lastCompleted)
    }
}

// MARK: - Reminder

struct Reminder: Codable, Identifiable, Equatable, Sendable {
    var id: UUID = UUID()
    var target: ItemRef
    var hour: Int = 21
    var minute: Int = 0
    /// Foundation weekday numbers: Sunday = 1 … Saturday = 7.
    var weekdays: [Int] = [1, 2, 3, 4, 5, 6, 7]
    var enabled: Bool = true

    enum CodingKeys: String, CodingKey { case id, target, hour, minute, weekdays, enabled }
}

extension Reminder {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let target: ItemRef = try c.decode(ItemRef.self, forKey: .target)
        self.init(target: target)
        id = c.value(.id, default: UUID())
        hour = min(23, max(0, c.value(.hour, default: 21)))
        minute = min(59, max(0, c.value(.minute, default: 0)))
        weekdays = c.value(.weekdays, default: [1, 2, 3, 4, 5, 6, 7]).filter { (1...7).contains($0) }
        enabled = c.value(.enabled, default: true)
    }
}

// MARK: - Root

struct ZikrData: Codable, Equatable, Sendable {
    static let currentSchema = 4

    var schemaVersion: Int = ZikrData.currentSchema
    var settings = AppSettings()
    var counters: [Counter] = []
    var programs: [Program] = []
    var reminders: [Reminder] = []
    var active: ItemRef? = nil
    var onboardingDone: Bool = false

    init() {}

    enum CodingKeys: String, CodingKey {
        case schemaVersion, settings, counters, programs, reminders, active, onboardingDone
    }

    var activeCounters: [Counter] { counters.filter { !$0.archived } }
    var activePrograms: [Program] { programs.filter { !$0.archived } }

    func counter(_ id: UUID) -> Counter? { counters.first { $0.id == id } }
    func program(_ id: UUID) -> Program? { programs.first { $0.id == id } }

    func title(of ref: ItemRef) -> String? {
        switch ref.kind {
        case .counter: return counter(ref.id)?.title
        case .program: return program(ref.id)?.title
        }
    }

    func isLive(_ ref: ItemRef) -> Bool {
        switch ref.kind {
        case .counter: return counter(ref.id).map { !$0.archived } ?? false
        case .program: return program(ref.id).map { !$0.archived } ?? false
        }
    }
}

extension ZikrData {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        schemaVersion = c.value(.schemaVersion, default: ZikrData.currentSchema)
        settings = c.value(.settings, default: AppSettings())
        counters = c.lossyArray(.counters)
        programs = c.lossyArray(.programs)
        reminders = c.lossyArray(.reminders)
        active = c.optional(.active)
        onboardingDone = c.value(.onboardingDone, default: false)
    }
}

// MARK: - Tolerant decoding

/// Counts elements that were skipped while decoding, so the app can tell the user and keep
/// the original file instead of silently overwriting it.
final class DecodeDiagnostics: @unchecked Sendable {
    var droppedElements = 0
    static let key = CodingUserInfoKey(rawValue: "zikr.diagnostics")!
}

private struct SkipElement: Decodable {
    init(from decoder: Decoder) throws {}
}

struct LossyArray<Element: Decodable>: Decodable {
    var elements: [Element]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var result: [Element] = []
        while !container.isAtEnd {
            if let element = try? container.decode(Element.self) {
                result.append(element)
            } else {
                // A failed decode does not advance the container, so consume the element.
                _ = try? container.decode(SkipElement.self)
                (decoder.userInfo[DecodeDiagnostics.key] as? DecodeDiagnostics)?.droppedElements += 1
            }
        }
        elements = result
    }
}

extension KeyedDecodingContainer {
    func value<T: Decodable>(_ key: Key, default fallback: @autoclosure () -> T) -> T {
        if let decoded = try? decodeIfPresent(T.self, forKey: key) {
            return decoded
        }
        return fallback()
    }

    func optional<T: Decodable>(_ key: Key) -> T? {
        if let decoded = try? decodeIfPresent(T.self, forKey: key) {
            return decoded
        }
        return nil
    }

    func lossyArray<T: Decodable>(_ key: Key) -> [T] {
        if let decoded = try? decodeIfPresent(LossyArray<T>.self, forKey: key) {
            return decoded.elements
        }
        return []
    }
}
