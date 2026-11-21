import Foundation

enum EngineError: Error, Equatable, Sendable {
    case notFound
    case archived
    case invalidTitle
    case valueOutOfRange
    case goalOutOfRange
    case intervalOutOfRange
    case dailyGoalOutOfRange
    case stepTargetOutOfRange
    case counterLimit
    case programLimit
    case stepLimit
    case noSteps
    case pinLimit
    case reminderLimit
    case nothingToUndo
    case noActiveItem

    /// Localization key for the user-facing message.
    var messageKey: String {
        switch self {
        case .notFound: return "error.notFound"
        case .archived: return "error.archived"
        case .invalidTitle: return "error.invalidTitle"
        case .valueOutOfRange: return "error.valueOutOfRange"
        case .goalOutOfRange: return "error.goalOutOfRange"
        case .intervalOutOfRange: return "error.intervalOutOfRange"
        case .dailyGoalOutOfRange: return "error.dailyGoalOutOfRange"
        case .stepTargetOutOfRange: return "error.stepTargetOutOfRange"
        case .counterLimit: return "error.counterLimit"
        case .programLimit: return "error.programLimit"
        case .stepLimit: return "error.stepLimit"
        case .noSteps: return "error.noSteps"
        case .pinLimit: return "error.pinLimit"
        case .reminderLimit: return "error.reminderLimit"
        case .nothingToUndo: return "error.nothingToUndo"
        case .noActiveItem: return "error.noActiveItem"
        }
    }
}

// MARK: - Day keys

/// Day keys are always Gregorian "yyyy-MM-dd" in the device time zone, independent of the
/// calendar the user selected in iOS Settings (Hijri, Buddhist, …), so stored history never
/// shifts when the device calendar changes. Dates are still *displayed* in the user's calendar.
enum DayKey {
    static func calendar(timeZone: TimeZone = .current) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    static func key(_ date: Date, calendar: Calendar = DayKey.calendar()) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func date(_ key: String, calendar: Calendar = DayKey.calendar()) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }

    static func isValid(_ key: String) -> Bool {
        let parts = key.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return false }
        return (1970...2200).contains(y) && (1...12).contains(m) && (1...31).contains(d)
    }

    static func shifted(_ date: Date, days: Int, calendar: Calendar = DayKey.calendar()) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date.addingTimeInterval(Double(days) * 86_400)
    }
}

// MARK: - Validation helpers

enum Validate {
    static func title(_ raw: String) throws -> String {
        let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= Limits.titleLength else { throw EngineError.invalidTitle }
        return clean
    }

    static func note(_ raw: String) -> String {
        String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Limits.noteLength))
    }

    static func optionalPositive(_ value: Int?, _ error: EngineError) throws -> Int? {
        guard let value else { return nil }
        guard (1...Limits.maxValue).contains(value) else { throw error }
        return value
    }
}

// MARK: - Tap outcome

enum TapOutcome: Equatable, Sendable {
    case counted
    case intervalReached
    case dailyGoalReached
    case goalReached
    case stepCompleted
    case programCompleted
}

struct TapResult: Equatable, Sendable {
    var title: String
    var value: Int
    var outcome: TapOutcome
}

// MARK: - Counter engine

enum CounterEngine {
    static func create(title: String, initial: Int, goal: Int?, interval: Int?, dailyGoal: Int?,
                       note: String, now: Date = Date()) throws -> Counter {
        let clean = try Validate.title(title)
        guard (0...Limits.maxValue).contains(initial) else { throw EngineError.valueOutOfRange }
        var counter = Counter(title: clean)
        counter.value = initial
        counter.goal = try Validate.optionalPositive(goal, .goalOutOfRange)
        counter.interval = try Validate.optionalPositive(interval, .intervalOutOfRange)
        counter.dailyGoal = try Validate.optionalPositive(dailyGoal, .dailyGoalOutOfRange)
        counter.note = Validate.note(note)
        counter.createdAt = now
        counter.updatedAt = now
        if initial != 0 {
            counter.journal.append(JournalEntry(kind: .baseline, at: now, before: 0, after: initial))
        }
        return counter
    }

    static func update(_ counter: inout Counter, title: String, goal: Int?, interval: Int?, dailyGoal: Int?,
                       note: String, now: Date = Date()) throws {
        let clean = try Validate.title(title)
        let g = try Validate.optionalPositive(goal, .goalOutOfRange)
        let i = try Validate.optionalPositive(interval, .intervalOutOfRange)
        let d = try Validate.optionalPositive(dailyGoal, .dailyGoalOutOfRange)
        counter.title = clean
        counter.goal = g
        counter.interval = i
        counter.dailyGoal = d
        counter.note = Validate.note(note)
        counter.updatedAt = now
    }

    static func today(_ counter: Counter, now: Date = Date(), calendar: Calendar = DayKey.calendar()) -> Int {
        counter.daily[DayKey.key(now, calendar: calendar)] ?? 0
    }

    @discardableResult
    static func tap(_ counter: inout Counter, now: Date = Date(), calendar: Calendar = DayKey.calendar()) throws -> TapOutcome {
        guard !counter.archived else { throw EngineError.archived }
        guard counter.value < Limits.maxValue else { throw EngineError.valueOutOfRange }
        let day = DayKey.key(now, calendar: calendar)
        counter.value += 1
        counter.daily[day, default: 0] += 1
        counter.updatedAt = now
        counter.undoLog.append(TapRecord(day: day, at: now))
        if counter.undoLog.count > Limits.undoLog {
            counter.undoLog.removeFirst(counter.undoLog.count - Limits.undoLog)
        }
        if let goal = counter.goal, counter.value == goal { return .goalReached }
        if let daily = counter.dailyGoal, counter.daily[day] == daily { return .dailyGoalReached }
        if let interval = counter.interval, interval > 0, counter.value % interval == 0 { return .intervalReached }
        return .counted
    }

    /// Undoes the most recent tap that happened after the last manual correction.
    /// The tap is removed from the day on which it was made, not from today.
    static func undo(_ counter: inout Counter, now: Date = Date()) throws {
        guard let last = counter.undoLog.last, counter.value > 0 else { throw EngineError.nothingToUndo }
        counter.undoLog.removeLast()
        counter.value -= 1
        let remaining = (counter.daily[last.day] ?? 0) - 1
        counter.daily[last.day] = remaining > 0 ? remaining : nil
        counter.updatedAt = now
    }

    /// A manual correction changes the total but never fakes daily activity.
    static func adjust(_ counter: inout Counter, to newValue: Int, now: Date = Date()) throws {
        guard (0...Limits.maxValue).contains(newValue) else { throw EngineError.valueOutOfRange }
        guard newValue != counter.value else { return }
        counter.journal.append(JournalEntry(kind: .adjustment, at: now, before: counter.value, after: newValue))
        if counter.journal.count > Limits.journal {
            counter.journal.removeFirst(counter.journal.count - Limits.journal)
        }
        counter.value = newValue
        counter.undoLog.removeAll()
        counter.updatedAt = now
    }

    static func record(seconds: Int, on counter: inout Counter, now: Date = Date(),
                       calendar: Calendar = DayKey.calendar()) {
        guard seconds > 0 else { return }
        counter.seconds[DayKey.key(now, calendar: calendar), default: 0] += min(seconds, 86_400)
        counter.updatedAt = now
    }
}

// MARK: - Program engine

struct StepDraft: Equatable, Sendable {
    var title: String
    var target: Int
}

enum ProgramEngine {
    static func validatedSteps(_ drafts: [StepDraft], keeping existing: [ProgramStep] = []) throws -> [ProgramStep] {
        guard !drafts.isEmpty else { throw EngineError.noSteps }
        guard drafts.count <= Limits.steps else { throw EngineError.stepLimit }
        return try drafts.enumerated().map { index, draft in
            let title = try Validate.title(draft.title)
            guard (1...Limits.maxValue).contains(draft.target) else { throw EngineError.stepTargetOutOfRange }
            var step = ProgramStep(title: title, target: draft.target)
            if index < existing.count { step.id = existing[index].id }
            return step
        }
    }

    static func create(title: String, steps drafts: [StepDraft], note: String, now: Date = Date()) throws -> Program {
        let clean = try Validate.title(title)
        var program = Program(title: clean, steps: try validatedSteps(drafts))
        program.note = Validate.note(note)
        program.createdAt = now
        program.updatedAt = now
        return program
    }

    static func update(_ program: inout Program, title: String, steps drafts: [StepDraft], note: String,
                       now: Date = Date()) throws {
        let clean = try Validate.title(title)
        let steps = try validatedSteps(drafts, keeping: program.steps)
        let structureChanged = steps.count != program.steps.count
        program.title = clean
        program.steps = steps
        program.note = Validate.note(note)
        program.updatedAt = now
        if structureChanged {
            program.session = nil
            program.lastCompleted = nil
        } else if var session = program.session {
            session.stepIndex = min(session.stepIndex, steps.count - 1)
            session.count = min(session.count, steps[session.stepIndex].target - 1)
            program.session = session
        }
    }

    static func today(_ program: Program, now: Date = Date(), calendar: Calendar = DayKey.calendar()) -> Int {
        program.daily[DayKey.key(now, calendar: calendar)] ?? 0
    }

    @discardableResult
    static func tap(_ program: inout Program, now: Date = Date(), calendar: Calendar = DayKey.calendar()) throws -> TapOutcome {
        guard !program.archived else { throw EngineError.archived }
        guard !program.steps.isEmpty else { throw EngineError.noSteps }
        let day = DayKey.key(now, calendar: calendar)
        var session = program.session ?? ProgramSession(stepIndex: 0, count: 0, startedAt: now, dayRuns: [])
        if session.stepIndex >= program.steps.count { session = ProgramSession(stepIndex: 0, count: 0, startedAt: now, dayRuns: []) }
        // Any new tap makes the previous completion final.
        program.lastCompleted = nil
        session.count += 1
        session.dayRuns.push(day)
        program.daily[day, default: 0] += 1
        program.updatedAt = now

        guard session.count >= program.steps[session.stepIndex].target else {
            program.session = session
            return .counted
        }
        if session.stepIndex + 1 < program.steps.count {
            session.stepIndex += 1
            session.count = 0
            program.session = session
            return .stepCompleted
        }
        program.completions[day, default: 0] += 1
        program.lastCompleted = CompletedRun(day: day, startedAt: session.startedAt, dayRuns: session.dayRuns)
        program.session = nil
        return .programCompleted
    }

    private static func decrement(_ dict: inout [String: Int], _ key: String) {
        let remaining = (dict[key] ?? 0) - 1
        dict[key] = remaining > 0 ? remaining : nil
    }

    /// Steps back one tap. At the start of a step it returns to the end of the previous step;
    /// right after completion it reopens the last step.
    static func undo(_ program: inout Program, now: Date = Date(), calendar: Calendar = DayKey.calendar()) throws {
        if program.session == nil, let done = program.lastCompleted, !program.steps.isEmpty {
            var runs = done.dayRuns
            let tapDay = runs.pop() ?? done.day
            let last = program.steps.count - 1
            let reopened = ProgramSession(stepIndex: last, count: max(0, program.steps[last].target - 1),
                                          startedAt: done.startedAt, dayRuns: runs)
            program.session = (reopened.stepIndex == 0 && reopened.count == 0) ? nil : reopened
            decrement(&program.completions, done.day)
            decrement(&program.daily, tapDay)
            program.lastCompleted = nil
            program.updatedAt = now
            return
        }
        guard var session = program.session else { throw EngineError.nothingToUndo }
        if session.count == 0 {
            guard session.stepIndex > 0 else { throw EngineError.nothingToUndo }
            session.stepIndex -= 1
            session.count = max(0, program.steps[session.stepIndex].target - 1)
        } else {
            session.count -= 1
        }
        let day = session.dayRuns.pop() ?? DayKey.key(now, calendar: calendar)
        decrement(&program.daily, day)
        program.updatedAt = now
        program.session = (session.stepIndex == 0 && session.count == 0) ? nil : session
    }

    static func restart(_ program: inout Program, now: Date = Date()) {
        program.session = nil
        program.lastCompleted = nil
        program.updatedAt = now
    }

    static func record(seconds: Int, on program: inout Program, now: Date = Date(),
                       calendar: Calendar = DayKey.calendar()) {
        guard seconds > 0 else { return }
        program.seconds[DayKey.key(now, calendar: calendar), default: 0] += min(seconds, 86_400)
        program.updatedAt = now
    }
}

// MARK: - Actions on the whole data set (shared by the app, widgets and intents)

/// A compact, display-ready description of an item, used by widgets and Live Activities.
struct ItemStatus: Equatable, Sendable {
    var ref: ItemRef
    var title: String
    var value: Int
    var target: Int?
    var today: Int
    /// For programs: "2/3".
    var stepPosition: String?
    var stepTitle: String?

    var fraction: Double? {
        guard let target, target > 0 else { return nil }
        return min(1, Double(value) / Double(target))
    }
}

enum Actions {
    /// The active item if it still exists and is not archived, otherwise the first pinned,
    /// then the first item in the list.
    static func resolvedActive(_ data: ZikrData) -> ItemRef? {
        if let ref = data.active, data.isLive(ref) { return ref }
        if let c = data.activeCounters.first(where: \.pinned) { return .counter(c.id) }
        if let p = data.activePrograms.first(where: \.pinned) { return .program(p.id) }
        if let c = data.activeCounters.first { return .counter(c.id) }
        if let p = data.activePrograms.first { return .program(p.id) }
        return nil
    }

    static func status(_ data: ZikrData, ref: ItemRef?, now: Date = Date()) -> ItemStatus? {
        guard let ref = ref ?? resolvedActive(data) else { return nil }
        switch ref.kind {
        case .counter:
            guard let c = data.counter(ref.id) else { return nil }
            return ItemStatus(ref: ref, title: c.title, value: c.value, target: c.goal,
                              today: CounterEngine.today(c, now: now), stepPosition: nil, stepTitle: nil)
        case .program:
            guard let p = data.program(ref.id), !p.steps.isEmpty else { return nil }
            let session = p.session ?? ProgramSession()
            let index = min(session.stepIndex, p.steps.count - 1)
            return ItemStatus(ref: ref, title: p.title, value: session.count, target: p.steps[index].target,
                              today: ProgramEngine.today(p, now: now),
                              stepPosition: "\(index + 1)/\(p.steps.count)", stepTitle: p.steps[index].title)
        }
    }

    @discardableResult
    static func tap(_ data: inout ZikrData, ref: ItemRef?, now: Date = Date()) throws -> TapResult {
        guard let ref = ref ?? resolvedActive(data) else { throw EngineError.noActiveItem }
        switch ref.kind {
        case .counter:
            guard let i = data.counters.firstIndex(where: { $0.id == ref.id }) else { throw EngineError.notFound }
            let outcome = try CounterEngine.tap(&data.counters[i], now: now)
            return TapResult(title: data.counters[i].title, value: data.counters[i].value, outcome: outcome)
        case .program:
            guard let i = data.programs.firstIndex(where: { $0.id == ref.id }) else { throw EngineError.notFound }
            let outcome = try ProgramEngine.tap(&data.programs[i], now: now)
            let p = data.programs[i]
            return TapResult(title: p.title, value: p.session?.count ?? 0, outcome: outcome)
        }
    }

    @discardableResult
    static func undo(_ data: inout ZikrData, ref: ItemRef?, now: Date = Date()) throws -> Int {
        guard let ref = ref ?? resolvedActive(data) else { throw EngineError.noActiveItem }
        switch ref.kind {
        case .counter:
            guard let i = data.counters.firstIndex(where: { $0.id == ref.id }) else { throw EngineError.notFound }
            try CounterEngine.undo(&data.counters[i], now: now)
            return data.counters[i].value
        case .program:
            guard let i = data.programs.firstIndex(where: { $0.id == ref.id }) else { throw EngineError.notFound }
            try ProgramEngine.undo(&data.programs[i], now: now)
            return data.programs[i].session?.count ?? 0
        }
    }

    static func record(seconds: Int, ref: ItemRef, in data: inout ZikrData, now: Date = Date()) {
        switch ref.kind {
        case .counter:
            if let i = data.counters.firstIndex(where: { $0.id == ref.id }) {
                CounterEngine.record(seconds: seconds, on: &data.counters[i], now: now)
            }
        case .program:
            if let i = data.programs.firstIndex(where: { $0.id == ref.id }) {
                ProgramEngine.record(seconds: seconds, on: &data.programs[i], now: now)
            }
        }
    }

    static func setArchived(_ archived: Bool, ref: ItemRef, in data: inout ZikrData, now: Date = Date()) throws {
        switch ref.kind {
        case .counter:
            guard let i = data.counters.firstIndex(where: { $0.id == ref.id }) else { throw EngineError.notFound }
            if !archived && data.activeCounters.count >= Limits.activeCounters { throw EngineError.counterLimit }
            data.counters[i].archived = archived
            if archived { data.counters[i].pinned = false }
            data.counters[i].updatedAt = now
        case .program:
            guard let i = data.programs.firstIndex(where: { $0.id == ref.id }) else { throw EngineError.notFound }
            if !archived && data.activePrograms.count >= Limits.activePrograms { throw EngineError.programLimit }
            data.programs[i].archived = archived
            if archived { data.programs[i].pinned = false }
            data.programs[i].updatedAt = now
        }
        if archived {
            data.reminders.removeAll { $0.target == ref }
            if data.active == ref { data.active = nil }
            data.active = resolvedActive(data)
        }
    }

    static func delete(_ ref: ItemRef, in data: inout ZikrData) {
        switch ref.kind {
        case .counter: data.counters.removeAll { $0.id == ref.id }
        case .program: data.programs.removeAll { $0.id == ref.id }
        }
        data.reminders.removeAll { $0.target == ref }
        if data.active == ref { data.active = nil }
        data.active = resolvedActive(data)
    }

    static func pinnedCount(_ data: ZikrData) -> Int {
        data.activeCounters.filter(\.pinned).count + data.activePrograms.filter(\.pinned).count
    }

    static func togglePin(_ ref: ItemRef, in data: inout ZikrData) throws {
        let pinnedNow = pinnedCount(data)
        switch ref.kind {
        case .counter:
            guard let i = data.counters.firstIndex(where: { $0.id == ref.id }) else { throw EngineError.notFound }
            if !data.counters[i].pinned && pinnedNow >= Limits.pinned { throw EngineError.pinLimit }
            data.counters[i].pinned.toggle()
        case .program:
            guard let i = data.programs.firstIndex(where: { $0.id == ref.id }) else { throw EngineError.notFound }
            if !data.programs[i].pinned && pinnedNow >= Limits.pinned { throw EngineError.pinLimit }
            data.programs[i].pinned.toggle()
        }
    }

    static func setReminder(_ reminder: Reminder, in data: inout ZikrData) throws {
        var next = data.reminders.filter { $0.target != reminder.target }
        if reminder.enabled {
            guard data.isLive(reminder.target) else { throw EngineError.notFound }
            next.append(reminder)
        }
        guard next.count <= Limits.reminders else { throw EngineError.reminderLimit }
        data.reminders = next
    }
}

// MARK: - Statistics

enum Stats {
    /// Net taps per day across every counter and program, archived ones included.
    static func overallDaily(_ data: ZikrData) -> [String: Int] {
        var totals: [String: Int] = [:]
        for c in data.counters { for (k, v) in c.daily { totals[k, default: 0] += v } }
        for p in data.programs { for (k, v) in p.daily { totals[k, default: 0] += v } }
        return totals.filter { $0.value > 0 }
    }

    static func daily(_ data: ZikrData, ref: ItemRef?) -> [String: Int] {
        guard let ref else { return overallDaily(data) }
        switch ref.kind {
        case .counter: return data.counter(ref.id)?.daily ?? [:]
        case .program: return data.program(ref.id)?.daily ?? [:]
        }
    }

    static func seconds(_ data: ZikrData, ref: ItemRef?) -> Int {
        switch ref?.kind {
        case .counter?: return data.counter(ref!.id)?.seconds.values.reduce(0, +) ?? 0
        case .program?: return data.program(ref!.id)?.seconds.values.reduce(0, +) ?? 0
        case nil:
            return data.counters.reduce(0) { $0 + $1.seconds.values.reduce(0, +) }
                + data.programs.reduce(0) { $0 + $1.seconds.values.reduce(0, +) }
        }
    }

    /// Sum over the last `days` days, today included.
    static func sum(_ daily: [String: Int], lastDays days: Int, now: Date = Date(),
                    calendar: Calendar = DayKey.calendar()) -> Int {
        (0..<max(0, days)).reduce(0) { total, offset in
            total + (daily[DayKey.key(DayKey.shifted(now, days: -offset, calendar: calendar), calendar: calendar)] ?? 0)
        }
    }

    /// Consecutive active days with grace: one missed day within any 7-day span does not break
    /// the streak; a second one does. Today being empty so far never breaks it.
    static func softStreak(activeDays: Set<String>, now: Date = Date(), calendar: Calendar = DayKey.calendar()) -> Int {
        var streak = 0
        var misses: [Int] = []
        var offset = 0
        while offset < 3_700 {
            let key = DayKey.key(DayKey.shifted(now, days: -offset, calendar: calendar), calendar: calendar)
            if activeDays.contains(key) {
                streak += 1
            } else if offset > 0 {
                misses.append(offset)
                misses = misses.filter { $0 > offset - 7 }
                if misses.count > 1 { break }
            }
            offset += 1
        }
        return streak
    }

    static func bestDay(_ daily: [String: Int]) -> (key: String, value: Int)? {
        daily.max { $0.value < $1.value }.map { ($0.key, $0.value) }
    }
}
