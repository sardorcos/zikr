import Foundation
import Testing
@testable import ZIKR

private let utc5 = TimeZone(secondsFromGMT: 5 * 3600)!
private var calendar: Calendar { DayKey.calendar(timeZone: utc5) }
private func date(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

@Suite("Counter engine")
struct CounterEngineTests {
    @Test func startingValueIsNotCountedAsActivity() throws {
        let c = try CounterEngine.create(title: "  Test  ", initial: 377, goal: 40_000, interval: 100, dailyGoal: 500, note: "")
        #expect(c.title == "Test")
        #expect(c.value == 377)
        #expect(c.daily.isEmpty)
        #expect(c.journal.first?.kind == .baseline)
    }

    @Test func tapsAreCreditedToTheirDay() throws {
        var c = try CounterEngine.create(title: "A", initial: 0, goal: nil, interval: nil, dailyGoal: nil, note: "")
        try CounterEngine.tap(&c, now: date("2026-11-20T23:59:50+05:00"), calendar: calendar)
        try CounterEngine.tap(&c, now: date("2026-11-21T00:00:10+05:00"), calendar: calendar)
        #expect(c.value == 2)
        #expect(c.daily["2026-11-20"] == 1)
        #expect(c.daily["2026-11-21"] == 1)
    }

    @Test func undoRemovesTapFromOriginalDay() throws {
        var c = try CounterEngine.create(title: "A", initial: 0, goal: nil, interval: nil, dailyGoal: nil, note: "")
        try CounterEngine.tap(&c, now: date("2026-11-20T23:59:50+05:00"), calendar: calendar)
        try CounterEngine.undo(&c, now: date("2026-11-21T08:00:00+05:00"))
        #expect(c.value == 0)
        #expect(c.daily["2026-11-20"] == nil)
    }

    @Test func correctionDoesNotFakeActivityAndBlocksOlderUndo() throws {
        var c = try CounterEngine.create(title: "A", initial: 377, goal: nil, interval: nil, dailyGoal: nil, note: "")
        try CounterEngine.tap(&c, calendar: calendar)
        try CounterEngine.adjust(&c, to: 500)
        #expect(c.value == 500)
        #expect(c.daily.values.reduce(0, +) == 1)
        #expect(throws: EngineError.nothingToUndo) { try CounterEngine.undo(&c) }
    }

    @Test func outcomes() throws {
        var c = try CounterEngine.create(title: "A", initial: 0, goal: 6, interval: 3, dailyGoal: 4, note: "")
        let now = Date()
        #expect(try CounterEngine.tap(&c, now: now) == .counted)
        #expect(try CounterEngine.tap(&c, now: now) == .counted)
        #expect(try CounterEngine.tap(&c, now: now) == .intervalReached)
        #expect(try CounterEngine.tap(&c, now: now) == .dailyGoalReached)
        #expect(try CounterEngine.tap(&c, now: now) == .counted)
        #expect(try CounterEngine.tap(&c, now: now) == .goalReached)
    }

    @Test func undoLogIsBounded() throws {
        var c = try CounterEngine.create(title: "A", initial: 0, goal: nil, interval: nil, dailyGoal: nil, note: "")
        for _ in 0..<(Limits.undoLog + 50) { try CounterEngine.tap(&c) }
        #expect(c.undoLog.count == Limits.undoLog)
        #expect(c.value == Limits.undoLog + 50)
    }

    @Test func validation() {
        #expect(throws: EngineError.invalidTitle) {
            try CounterEngine.create(title: "   ", initial: 0, goal: nil, interval: nil, dailyGoal: nil, note: "")
        }
        #expect(throws: EngineError.goalOutOfRange) {
            try CounterEngine.create(title: "A", initial: 0, goal: 0, interval: nil, dailyGoal: nil, note: "")
        }
        #expect(throws: EngineError.valueOutOfRange) {
            try CounterEngine.create(title: "A", initial: -1, goal: nil, interval: nil, dailyGoal: nil, note: "")
        }
    }

    @Test func maximumValue() throws {
        var c = try CounterEngine.create(title: "A", initial: Limits.maxValue, goal: nil, interval: nil, dailyGoal: nil, note: "")
        #expect(throws: EngineError.valueOutOfRange) { try CounterEngine.tap(&c) }
    }
}

@Suite("Day keys")
struct DayKeyTests {
    @Test func gregorianRegardlessOfDeviceCalendar() {
        var islamic = Calendar(identifier: .islamicUmmAlQura)
        islamic.timeZone = utc5
        let d = date("2026-11-21T12:00:00+05:00")
        // The key must not depend on the calendar the user picked in iOS Settings.
        #expect(DayKey.key(d, calendar: calendar) == "2026-11-21")
        #expect(islamic.component(.year, from: d) != 2026)
    }

    @Test func validation() {
        #expect(DayKey.isValid("2026-11-21"))
        #expect(!DayKey.isValid("1448-05-01"))
        #expect(!DayKey.isValid("2026-13-01"))
        #expect(!DayKey.isValid("garbage"))
    }
}

@Suite("Program engine")
struct ProgramEngineTests {
    private func program() throws -> Program {
        try ProgramEngine.create(title: "P", steps: [StepDraft(title: "A", target: 2), StepDraft(title: "B", target: 1)], note: "")
    }

    @Test func advancesAndCompletes() throws {
        var p = try program()
        #expect(try ProgramEngine.tap(&p) == .counted)
        #expect(try ProgramEngine.tap(&p) == .stepCompleted)
        #expect(p.session?.stepIndex == 1)
        #expect(try ProgramEngine.tap(&p) == .programCompleted)
        #expect(p.session == nil)
        #expect(p.totalCompletions == 1)
        #expect(p.daily.values.reduce(0, +) == 3)
    }

    @Test func undoStepsBackAcrossSteps() throws {
        var p = try program()
        try ProgramEngine.tap(&p)
        try ProgramEngine.tap(&p)          // now at step B, count 0
        try ProgramEngine.undo(&p)         // back to step A, count 1
        #expect(p.session?.stepIndex == 0)
        #expect(p.session?.count == 1)
        try ProgramEngine.undo(&p)
        #expect(p.session == nil)
        #expect(p.daily.isEmpty)
        #expect(throws: EngineError.nothingToUndo) { try ProgramEngine.undo(&p) }
    }

    @Test func completionCanBeUndone() throws {
        var p = try program()
        try ProgramEngine.tap(&p)
        try ProgramEngine.tap(&p)
        #expect(try ProgramEngine.tap(&p) == .programCompleted)
        try ProgramEngine.undo(&p)
        #expect(p.totalCompletions == 0)
        #expect(p.session?.stepIndex == 1)
        #expect(p.session?.count == 0)
        #expect(p.daily.values.reduce(0, +) == 2)
        // A new tap after completion makes it final.
        try ProgramEngine.tap(&p)
        #expect(p.totalCompletions == 1)
        try ProgramEngine.tap(&p)
        #expect(p.lastCompleted == nil)
    }

    @Test func longStepUndoUsesTheRightDay() throws {
        var p = try ProgramEngine.create(title: "P", steps: [StepDraft(title: "A", target: 5_000)], note: "")
        let day1 = date("2026-11-20T10:00:00+05:00")
        let day2 = date("2026-11-21T10:00:00+05:00")
        for _ in 0..<1_000 { try ProgramEngine.tap(&p, now: day1, calendar: calendar) }
        try ProgramEngine.tap(&p, now: day2, calendar: calendar)
        try ProgramEngine.undo(&p, now: day2, calendar: calendar)
        try ProgramEngine.undo(&p, now: day2, calendar: calendar)
        #expect(p.daily["2026-11-21"] == nil)
        #expect(p.daily["2026-11-20"] == 999)
        #expect(p.session?.dayRuns.count == 1)
    }

    @Test func editingStructureResetsSession() throws {
        var p = try program()
        try ProgramEngine.tap(&p)
        try ProgramEngine.update(&p, title: "P", steps: [StepDraft(title: "A", target: 5)], note: "")
        #expect(p.session == nil)
    }

    @Test func requiresSteps() {
        #expect(throws: EngineError.noSteps) { try ProgramEngine.create(title: "P", steps: [], note: "") }
    }
}

@Suite("Actions and stats")
struct ActionsTests {
    @Test func archivingRemovesRemindersAndMovesActive() throws {
        var data = ZikrData()
        let a = try CounterEngine.create(title: "A", initial: 0, goal: nil, interval: nil, dailyGoal: nil, note: "")
        let b = try CounterEngine.create(title: "B", initial: 0, goal: nil, interval: nil, dailyGoal: nil, note: "")
        data.counters = [a, b]
        data.active = .counter(a.id)
        try Actions.setReminder(Reminder(target: .counter(a.id)), in: &data)
        try Actions.setArchived(true, ref: .counter(a.id), in: &data)
        #expect(data.reminders.isEmpty)
        #expect(data.active == .counter(b.id))
    }

    @Test func pinLimit() throws {
        var data = ZikrData()
        for i in 0..<4 {
            data.counters.append(try CounterEngine.create(title: "\(i)", initial: 0, goal: nil, interval: nil, dailyGoal: nil, note: ""))
        }
        for i in 0..<3 { try Actions.togglePin(.counter(data.counters[i].id), in: &data) }
        #expect(throws: EngineError.pinLimit) { try Actions.togglePin(.counter(data.counters[3].id), in: &data) }
    }

    @Test func softStreakAllowsOneMissPerWeek() {
        let now = date("2026-11-21T12:00:00+05:00")
        func key(_ offset: Int) -> String { DayKey.key(DayKey.shifted(now, days: -offset, calendar: calendar), calendar: calendar) }
        // Active today and the 5 previous days except day 2.
        let days: Set<String> = [key(0), key(1), key(3), key(4), key(5)]
        #expect(Stats.softStreak(activeDays: days, now: now, calendar: calendar) == 5)
        // Two misses within a week break it.
        let broken: Set<String> = [key(0), key(2), key(4)]
        #expect(Stats.softStreak(activeDays: broken, now: now, calendar: calendar) == 2)
        // An empty today does not break yesterday's streak.
        #expect(Stats.softStreak(activeDays: [key(1), key(2)], now: now, calendar: calendar) == 2)
        #expect(Stats.softStreak(activeDays: [], now: now, calendar: calendar) == 0)
    }
}
