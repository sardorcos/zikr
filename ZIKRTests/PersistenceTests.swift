import Foundation
import Testing
@testable import ZIKR

private func tempDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("zikr-tests-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Suite("Persistence")
struct PersistenceTests {
    @Test func roundTrip() throws {
        let file = DataFile(directory: tempDirectory())
        let saved = try file.update { data in
            data.counters.append(try CounterEngine.create(title: "A", initial: 5, goal: 10, interval: nil, dailyGoal: nil, note: "n"))
            data.onboardingDone = true
        }
        guard case .loaded(let loaded, let dropped) = file.load() else {
            Issue.record("expected loaded")
            return
        }
        #expect(dropped == 0)
        #expect(loaded == saved)
    }

    @Test func missingFileStartsEmpty() {
        let file = DataFile(directory: tempDirectory())
        guard case .missing = file.load() else {
            Issue.record("expected missing")
            return
        }
    }

    @Test func corruptFileIsQuarantinedNotOverwritten() throws {
        let directory = tempDirectory()
        let file = DataFile(directory: directory)
        try Data("{ not json".utf8).write(to: file.url)
        guard case .corrupt(let quarantined) = file.load() else {
            Issue.record("expected corrupt")
            return
        }
        let moved = try #require(quarantined)
        #expect(try String(contentsOf: moved, encoding: .utf8) == "{ not json")
        #expect(!FileManager.default.fileExists(atPath: file.url.path))
    }

    @Test func updateRefusesToOverwriteUnreadableFile() throws {
        let file = DataFile(directory: tempDirectory())
        try Data("garbage".utf8).write(to: file.url)
        #expect(throws: PersistenceError.self) {
            try file.update { $0.onboardingDone = true }
        }
        #expect(try String(contentsOf: file.url, encoding: .utf8) == "garbage")
    }

    @Test func restoreWorksOverUnreadableFile() throws {
        let file = DataFile(directory: tempDirectory())
        try Data("garbage".utf8).write(to: file.url)
        var replacement = ZikrData()
        replacement.onboardingDone = true
        try file.replace(with: replacement)
        guard case .loaded(let loaded, _) = file.load() else {
            Issue.record("expected loaded")
            return
        }
        #expect(loaded.onboardingDone)
        #expect(file.quarantinedFiles().isEmpty)
    }

    @Test func quarantineMovesFileAside() throws {
        let file = DataFile(directory: tempDirectory())
        try Data("garbage".utf8).write(to: file.url)
        let moved = try #require(file.quarantineCurrentFile())
        #expect(!FileManager.default.fileExists(atPath: file.url.path))
        #expect(try String(contentsOf: moved, encoding: .utf8) == "garbage")
    }

    @Test func newerSchemaIsNeverOverwritten() throws {
        let file = DataFile(directory: tempDirectory())
        try Data(#"{"schemaVersion": 99, "counters": []}"#.utf8).write(to: file.url)
        guard case .newerVersion(99) = file.load() else {
            Issue.record("expected newerVersion")
            return
        }
        #expect(throws: PersistenceError.newerVersion(99)) {
            try file.update { $0.onboardingDone = true }
        }
    }

    @Test func missingFieldsUseDefaults() throws {
        // A file written by a future 1.x that dropped or renamed optional fields must still load.
        let json = #"{"schemaVersion": 4, "counters": [{"title": "Only title"}]}"#
        let (data, dropped) = try DataFile.decode(Data(json.utf8))
        #expect(dropped == 0)
        #expect(data.counters.first?.title == "Only title")
        #expect(data.counters.first?.value == 0)
        #expect(data.settings.haptics == true)
    }

    @Test func brokenElementIsSkippedAndCounted() throws {
        let json = #"{"schemaVersion": 4, "counters": [{"title": "Good"}, 42, {"title": "Also good"}]}"#
        let (data, dropped) = try DataFile.decode(Data(json.utf8))
        #expect(data.counters.map(\.title) == ["Good", "Also good"])
        #expect(dropped == 1)
    }

    @Test func mergesExternalChanges() throws {
        let file = DataFile(directory: tempDirectory())
        let counter = try CounterEngine.create(title: "A", initial: 0, goal: nil, interval: nil, dailyGoal: nil, note: "")
        try file.update { $0.counters = [counter] }
        // Widget adds one…
        try file.update { data in _ = try Actions.tap(&data, ref: .counter(counter.id)) }
        // …then the app replays its own queued tap on top of the current file.
        let result = try file.update { data in _ = try Actions.tap(&data, ref: .counter(counter.id)) }
        #expect(result.counters.first?.value == 2)
    }

    @Test func snapshotsKeepSevenDays() throws {
        let file = DataFile(directory: tempDirectory())
        try file.update { $0.onboardingDone = true }
        let start = Date()
        for day in 0..<10 { file.makeDailySnapshot(now: DayKey.shifted(start, days: -day)) }
        #expect(file.snapshots().count == 7)
    }
}

@Suite("Migration")
struct MigrationTests {
    @Test func legacyV3IsConverted() throws {
        let counterID = UUID()
        let tapID = UUID()
        let json = """
        {"schemaVersion":3,"language":"uz","appearance":"dark","haptics":false,"activeCounterID":"\(counterID.uuidString)",
         "counters":[{"id":"\(counterID.uuidString)","title":"Old","value":379,"goal":40000,"interval":100,"dailyGoal":500,
           "note":"","pinned":true,"archived":false,"createdAt":0,"updatedAt":0,
           "events":[
             {"id":"\(UUID().uuidString)","kind":"baseline","at":0,"day":"1448-05-01","delta":0,"valueAfter":377},
             {"id":"\(tapID.uuidString)","kind":"tap","at":100,"day":"x","delta":1,"valueAfter":378},
             {"id":"\(UUID().uuidString)","kind":"tap","at":200,"day":"x","delta":1,"valueAfter":379},
             {"id":"\(UUID().uuidString)","kind":"time","at":300,"day":"x","delta":0,"valueAfter":379,"durationSeconds":24},
             {"id":"\(UUID().uuidString)","kind":"adjustment","at":400,"day":"x","delta":0,"valueAfter":379}
           ]}],
         "reminders":[{"counterID":"\(counterID.uuidString)","hour":21,"minute":0,"weekdays":[1,2],"enabled":true}]}
        """
        let (data, _) = try Migration.decode(Data(json.utf8))
        #expect(data.schemaVersion == ZikrData.currentSchema)
        #expect(data.settings.language == .uz)
        #expect(data.settings.haptics == false)
        let c = try #require(data.counters.first)
        #expect(c.value == 379)
        #expect(c.daily.values.reduce(0, +) == 2)
        #expect(c.daily.keys.allSatisfy(DayKey.isValid))
        #expect(c.seconds.values.reduce(0, +) == 24)
        #expect(c.journal.last?.kind == .adjustment)
        #expect(c.journal.last?.before == 379)
        #expect(data.reminders.first?.target == .counter(counterID))
        #expect(data.active == .counter(counterID))
    }

    @Test func sanitizeClampsAndRejectsDuplicates() throws {
        var data = ZikrData()
        var c = Counter(title: String(repeating: "x", count: 200))
        c.value = -5
        c.goal = 0
        c.daily = ["bad": 3, "2026-01-01": 4]
        data.counters = [c]
        data.reminders = [Reminder(target: .counter(UUID()))]
        let clean = try Migration.sanitize(data)
        #expect(clean.counters[0].title.count == Limits.titleLength)
        #expect(clean.counters[0].value == 0)
        #expect(clean.counters[0].goal == nil)
        #expect(clean.counters[0].daily == ["2026-01-01": 4])
        #expect(clean.reminders.isEmpty)

        data.counters = [c, c]
        #expect(throws: PersistenceError.invalidBackup) { try Migration.sanitize(data) }
    }

    @Test func rejectsNonZikrFiles() {
        #expect(throws: PersistenceError.self) { try Migration.decodeBackup(Data(#"{"hello":"world"}"#.utf8)) }
        #expect(throws: PersistenceError.self) { try Migration.decodeBackup(Data("[1,2,3]".utf8)) }
    }
}

@Suite("Localization")
struct LocalizationTests {
    @Test func everyLanguageHasEveryKey() {
        let keys = Set(L10nTables.en.keys)
        for language in AppLanguage.allCases {
            #expect(Set(L10n.table(language).keys) == keys, "\(language)")
        }
    }

    @Test func russianPlurals() {
        #expect(L10n.plural("unit.days", 1, .ru).hasSuffix("день"))
        #expect(L10n.plural("unit.days", 3, .ru).hasSuffix("дня"))
        #expect(L10n.plural("unit.days", 11, .ru).hasSuffix("дней"))
        #expect(L10n.plural("unit.days", 21, .ru).hasSuffix("день"))
    }

    @Test func positionalFormat() {
        #expect(L10n.format("program.stepOf", .en, ["2", "3"]) == "Step 2 of 3")
    }

    @Test func preferredLanguage() {
        #expect(AppLanguage.preferred(["uz-Cyrl-UZ"]) == .uzCyrl)
        #expect(AppLanguage.preferred(["uz-Latn-UZ"]) == .uz)
        #expect(AppLanguage.preferred(["kk-KZ"]) == .ru)
        #expect(AppLanguage.preferred(["de-DE"]) == .en)
    }
}
