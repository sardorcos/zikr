import Foundation

/// Reads every data format the app has ever written and upgrades it to the current schema.
enum Migration {
    private struct VersionProbe: Decodable { var schemaVersion: Int? }

    /// Schema version written in the file, or nil if it is not a JSON object.
    static func schemaVersion(of raw: Data) -> Int? {
        (try? JSONDecoder().decode(VersionProbe.self, from: raw))?.schemaVersion
    }

    static func decode(_ raw: Data) throws -> (ZikrData, droppedElements: Int) {
        guard raw.count <= Limits.backupBytes else { throw PersistenceError.tooLarge }
        let probe: VersionProbe
        do { probe = try JSONDecoder().decode(VersionProbe.self, from: raw) } catch { throw PersistenceError.corrupt }
        let version = probe.schemaVersion ?? 0
        if version > ZikrData.currentSchema { throw PersistenceError.newerVersion(version) }
        switch version {
        case ZikrData.currentSchema:
            let diagnostics = DecodeDiagnostics()
            let decoder = JSONDecoder()
            decoder.userInfo[DecodeDiagnostics.key] = diagnostics
            do {
                var data = try decoder.decode(ZikrData.self, from: raw)
                data.schemaVersion = ZikrData.currentSchema
                return (data, diagnostics.droppedElements)
            } catch {
                throw PersistenceError.corrupt
            }
        case 3:
            do {
                let legacy = try JSONDecoder().decode(LegacyV3.Data.self, from: raw)
                return (try sanitize(LegacyV3.convert(legacy)), 0)
            } catch {
                throw PersistenceError.corrupt
            }
        default:
            throw PersistenceError.unsupportedFormat
        }
    }

    /// Decodes and repairs a backup chosen by the user. Rejects files that are not ZIKR data.
    static func decodeBackup(_ raw: Data) throws -> ZikrData {
        let (data, _) = try decode(raw)
        return try sanitize(data)
    }

    /// Clamps every value into its valid range and drops broken references.
    static func sanitize(_ input: ZikrData) throws -> ZikrData {
        var data = input
        let counterIDs = data.counters.map(\.id)
        let programIDs = data.programs.map(\.id)
        guard Set(counterIDs).count == counterIDs.count, Set(programIDs).count == programIDs.count else {
            throw PersistenceError.invalidBackup
        }
        guard data.counters.count <= Limits.activeCounters * 5, data.programs.count <= Limits.activePrograms * 5 else {
            throw PersistenceError.invalidBackup
        }

        func cleanTitle(_ s: String) -> String {
            let t = String(s.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Limits.titleLength))
            return t.isEmpty ? "—" : t
        }
        func cleanDaily(_ d: [String: Int]) -> [String: Int] {
            d.filter { DayKey.isValid($0.key) && $0.value > 0 }.mapValues { min($0, Limits.maxValue) }
        }
        func positive(_ v: Int?) -> Int? {
            guard let v, (1...Limits.maxValue).contains(v) else { return nil }
            return v
        }

        for i in data.counters.indices {
            data.counters[i].title = cleanTitle(data.counters[i].title)
            data.counters[i].value = min(Limits.maxValue, max(0, data.counters[i].value))
            data.counters[i].goal = positive(data.counters[i].goal)
            data.counters[i].interval = positive(data.counters[i].interval)
            data.counters[i].dailyGoal = positive(data.counters[i].dailyGoal)
            data.counters[i].note = String(data.counters[i].note.prefix(Limits.noteLength))
            data.counters[i].daily = cleanDaily(data.counters[i].daily)
            data.counters[i].seconds = cleanDaily(data.counters[i].seconds)
            data.counters[i].undoLog = Array(data.counters[i].undoLog.filter { DayKey.isValid($0.day) }.suffix(Limits.undoLog))
            data.counters[i].journal = Array(data.counters[i].journal.suffix(Limits.journal))
        }
        for i in data.programs.indices {
            data.programs[i].title = cleanTitle(data.programs[i].title)
            data.programs[i].steps = Array(data.programs[i].steps.prefix(Limits.steps)).map { step in
                var s = step
                s.title = cleanTitle(s.title)
                s.target = min(Limits.maxValue, max(1, s.target))
                return s
            }
            if data.programs[i].steps.isEmpty {
                data.programs[i].steps = [ProgramStep(title: "1", target: 33)]
            }
            data.programs[i].note = String(data.programs[i].note.prefix(Limits.noteLength))
            data.programs[i].daily = cleanDaily(data.programs[i].daily)
            data.programs[i].completions = cleanDaily(data.programs[i].completions)
            data.programs[i].seconds = cleanDaily(data.programs[i].seconds)
            if var session = data.programs[i].session {
                let steps = data.programs[i].steps
                session.stepIndex = min(max(0, session.stepIndex), steps.count - 1)
                session.count = min(max(0, session.count), steps[session.stepIndex].target - 1)
                session.dayRuns = session.dayRuns.filter { DayKey.isValid($0.day) && $0.count > 0 }
                data.programs[i].session = session
            }
            if let done = data.programs[i].lastCompleted,
               !DayKey.isValid(done.day) || data.programs[i].session != nil {
                data.programs[i].lastCompleted = nil
            }
        }

        // Respect limits on active items by archiving the overflow instead of deleting it.
        var activeCount = 0
        for i in data.counters.indices where !data.counters[i].archived {
            activeCount += 1
            if activeCount > Limits.activeCounters { data.counters[i].archived = true }
        }
        activeCount = 0
        for i in data.programs.indices where !data.programs[i].archived {
            activeCount += 1
            if activeCount > Limits.activePrograms { data.programs[i].archived = true }
        }
        var pinned = 0
        for i in data.counters.indices where data.counters[i].pinned {
            pinned += 1
            if pinned > Limits.pinned || data.counters[i].archived { data.counters[i].pinned = false }
        }
        for i in data.programs.indices where data.programs[i].pinned {
            pinned += 1
            if pinned > Limits.pinned || data.programs[i].archived { data.programs[i].pinned = false }
        }

        let snapshot = data
        data.reminders = Array(data.reminders
            .filter { snapshot.isLive($0.target) && !$0.weekdays.isEmpty }
            .map { r in
                var x = r
                x.hour = min(23, max(0, r.hour))
                x.minute = min(59, max(0, r.minute))
                x.weekdays = Array(Set(r.weekdays.filter { (1...7).contains($0) })).sorted()
                return x
            }
            .prefix(Limits.reminders))
        if let active = data.active, !data.isLive(active) { data.active = nil }
        data.active = Actions.resolvedActive(data)
        data.schemaVersion = ZikrData.currentSchema
        return data
    }
}

/// Format written by the restored 0.3.0 project (one event per tap).
enum LegacyV3 {
    struct Data: Decodable {
        var schemaVersion: Int
        var language: String?
        var appearance: String?
        var haptics: Bool?
        var counters: [Counter]
        var activeCounterID: UUID?
        var reminders: [Reminder]?
    }

    struct Counter: Decodable {
        var id: UUID
        var title: String
        var value: Int
        var goal: Int?
        var interval: Int?
        var dailyGoal: Int?
        var note: String?
        var pinned: Bool?
        var archived: Bool?
        var createdAt: Date?
        var updatedAt: Date?
        var events: [Event]?
    }

    struct Event: Decodable {
        var id: UUID
        var kind: String
        var at: Date
        var day: String
        var delta: Int
        var valueAfter: Int
        var targetID: UUID?
        var durationSeconds: Int?
    }

    struct Reminder: Decodable {
        var id: UUID?
        var counterID: UUID
        var hour: Int
        var minute: Int
        var weekdays: [Int]
        var enabled: Bool
    }

    static func convert(_ legacy: Data) -> ZikrData {
        var data = ZikrData()
        data.settings.language = legacy.language.flatMap(AppLanguage.init(rawValue:))
        data.settings.appearance = legacy.appearance.flatMap(AppAppearance.init(rawValue:)) ?? .system
        data.settings.haptics = legacy.haptics ?? true
        data.onboardingDone = true
        let calendar = DayKey.calendar()

        for old in legacy.counters {
            var c = ZikrCounter(title: old.title)
            c.id = old.id
            c.value = old.value
            c.goal = old.goal
            c.interval = old.interval
            c.dailyGoal = old.dailyGoal
            c.note = old.note ?? ""
            c.pinned = old.pinned ?? false
            c.archived = old.archived ?? false
            c.createdAt = old.createdAt ?? Date()
            c.updatedAt = old.updatedAt ?? c.createdAt
            let events = old.events ?? []
            // Old day keys could come from a non-Gregorian device calendar: recompute them
            // from timestamps. An undo is credited to the day of the tap it reversed.
            let tapDates = Dictionary(events.filter { $0.kind == "tap" }.map { ($0.id, $0.at) }, uniquingKeysWith: { a, _ in a })
            var lastValue = 0
            for e in events {
                defer { lastValue = e.valueAfter }
                switch e.kind {
                case "tap":
                    c.daily[DayKey.key(e.at, calendar: calendar), default: 0] += 1
                case "undo":
                    let source = e.targetID.flatMap { tapDates[$0] } ?? e.at
                    c.daily[DayKey.key(source, calendar: calendar), default: 0] -= 1
                case "time":
                    c.seconds[DayKey.key(e.at, calendar: calendar), default: 0] += max(0, e.durationSeconds ?? 0)
                case "adjustment":
                    c.journal.append(JournalEntry(kind: .adjustment, at: e.at, before: lastValue, after: e.valueAfter))
                case "baseline":
                    c.journal.append(JournalEntry(kind: .baseline, at: e.at, before: 0, after: e.valueAfter))
                default:
                    break
                }
            }
            c.daily = c.daily.filter { $0.value > 0 }
            c.journal = Array(c.journal.suffix(Limits.journal))
            data.counters.append(c)
        }
        data.reminders = (legacy.reminders ?? []).filter(\.enabled).map { old in
            var r = ZikrReminder(target: .counter(old.counterID))
            r.id = old.id ?? UUID()
            r.hour = old.hour
            r.minute = old.minute
            r.weekdays = old.weekdays
            return r
        }
        if let id = legacy.activeCounterID { data.active = .counter(id) }
        return data
    }
}

// Aliases so the legacy namespace can refer to the current model types without ambiguity.
typealias ZikrCounter = Counter
typealias ZikrReminder = Reminder
