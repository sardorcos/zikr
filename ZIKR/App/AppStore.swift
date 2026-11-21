import Observation
import SwiftUI
import UIKit
import WidgetKit

enum AppTab: Hashable {
    case home, items, stats, settings
}

enum LoadIssue: Equatable {
    case corrupt(URL?)
    case newerVersion(Int)
}

struct AlertInfo: Identifiable {
    enum Action { case openNotificationSettings }
    let id = UUID()
    var title: String
    var message: String
    var action: Action? = nil
}

struct CompletionInfo: Identifiable, Equatable {
    let id = UUID()
    var title: String
    var programID: UUID
}

enum StarterChoice: CaseIterable, Identifiable {
    case freeCount, goal100, program
    var id: Self { self }
}

/// Routes a tapped notification to the store, even if it arrives before the UI exists.
@MainActor
enum NotificationRouter {
    static var pending: String?
    static var handler: (@MainActor (String) -> Void)?

    static func route(_ ref: String) {
        if let handler { handler(ref) } else { pending = ref }
    }
}

/// Single source of truth for the UI. Every change is applied to memory immediately (instant
/// UI) and replayed onto the shared file by `SyncEngine`.
@Observable
@MainActor
final class AppStore {
    private(set) var data: ZikrData
    var loadIssue: LoadIssue?
    var alert: AlertInfo?
    var tab: AppTab = .home
    var completion: CompletionInfo?
    var nightModePresented = false
    var recoveredElements = 0
    private(set) var timerRef: ItemRef?
    private(set) var timerStart: Date?
    private(set) var liveActivityRef: ItemRef?
    /// Changes when a program is completed inside night mode (the sheet cannot be shown there).
    private(set) var nightCompletionToken = 0
    /// Bumped at midnight / time-zone change; views that show "today" read it so they refresh.
    private(set) var dayRefresh = 0

    @ObservationIgnored let file: DataFile
    @ObservationIgnored let haptics = Haptics()
    @ObservationIgnored let liveActivity = LiveActivityController()
    @ObservationIgnored private let sync: SyncEngine
    @ObservationIgnored private var darwinObserver: DarwinObserver?
    @ObservationIgnored private var inFlight = 0
    @ObservationIgnored private var lastWidgetReload = Date.distantPast
    @ObservationIgnored private var widgetReloadScheduled = false
    @ObservationIgnored private var lastLiveUpdate = Date.distantPast
    @ObservationIgnored private var liveUpdateScheduled = false
    @ObservationIgnored private var lastFailureAlert = Date.distantPast
    @ObservationIgnored private var idleTask: Task<Void, Never>?
    @ObservationIgnored private var reminderTask: Task<Void, Never>?
    @ObservationIgnored private var backgroundSaveID: UIBackgroundTaskIdentifier = .invalid
    @ObservationIgnored private var lastSeenDay = DayKey.key(Date())

    init(file: DataFile = .shared) {
        self.file = file
        self.sync = SyncEngine(file: file)
        var issue: LoadIssue?
        var recovered = 0
        switch file.load() {
        case .missing:
            data = ZikrData()
        case .loaded(let loaded, let dropped):
            data = loaded
            recovered = dropped
        case .corrupt(let url):
            data = ZikrData()
            issue = .corrupt(url)
        case .newerVersion(let version):
            data = ZikrData()
            issue = .newerVersion(version)
        }
        loadIssue = issue
        recoveredElements = recovered
        if issue != nil { sync.setBlocked(true) }

        sync.onCommitted = { [weak self] result, count in self?.didCommit(result, count: count) }
        sync.onFailure = { [weak self] error in self?.didFailToSave(error) }
        darwinObserver = DarwinObserver(name: DarwinNotifier.name) { [weak self] in self?.reloadFromDisk() }
        NotificationRouter.handler = { [weak self] ref in self?.openFromNotification(ref) }
        if let pending = NotificationRouter.pending {
            NotificationRouter.pending = nil
            openFromNotification(pending)
        }
        liveActivityRef = currentLiveRef()
    }

    // MARK: Localization helpers

    var language: AppLanguage { data.settings.language ?? AppLanguage.preferred() }
    var locale: Locale { language.locale }
    func t(_ key: String) -> String { L10n.t(key, language) }
    func f(_ key: String, _ args: String...) -> String { L10n.format(key, language, args) }
    func p(_ key: String, _ count: Int) -> String { L10n.plural(key, count, language) }
    func num(_ value: Int) -> String { L10n.number(value, language) }

    var colorScheme: ColorScheme? {
        switch data.settings.appearance {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    // MARK: Derived state

    var activeRef: ItemRef? { Actions.resolvedActive(data) }
    var activeStatus: ItemStatus? { Actions.status(data, ref: activeRef) }
    var hasItems: Bool { !data.activeCounters.isEmpty || !data.activePrograms.isEmpty }

    // MARK: Core mutation pipeline

    @discardableResult
    private func mutate<T>(_ body: @escaping (inout ZikrData) throws -> T) -> Result<T, Error> {
        guard loadIssue == nil else { return .failure(PersistenceError.corrupt) }
        var copy = data
        do {
            let value = try body(&copy)
            data = copy
            inFlight += 1
            sync.enqueue { d in _ = try body(&d) }
            return .success(value)
        } catch {
            return .failure(error)
        }
    }

    /// Throws to the caller (forms show the message inline).
    @discardableResult
    func run<T>(_ body: @escaping (inout ZikrData) throws -> T) throws -> T {
        try mutate(body).get()
    }

    /// Shows an alert on failure.
    @discardableResult
    func attempt(_ body: @escaping (inout ZikrData) throws -> Void) -> Bool {
        switch mutate(body) {
        case .success: return true
        case .failure(let error): show(error); return false
        }
    }

    private func didCommit(_ result: ZikrData, count: Int) {
        inFlight = max(0, inFlight - count)
        reloadWidgetsSoon()
        // Adopt the file state (which may include widget/intent changes) once nothing newer is pending.
        if inFlight == 0 && result != data {
            data = result
            scheduleLiveActivityUpdate()
        }
    }

    private func didFailToSave(_ error: Error) {
        guard Date().timeIntervalSince(lastFailureAlert) > 30 else { return }
        lastFailureAlert = Date()
        alert = AlertInfo(title: t("common.error"), message: t("error.saveFailed"))
    }

    func reloadFromDisk() {
        guard loadIssue == nil, inFlight == 0 else { return }
        sync.reload { [weak self] fresh in
            guard let self, let fresh, self.inFlight == 0, fresh != self.data else { return }
            self.data = fresh
            // The change came from a widget, Control Center or Siri: keep the Lock Screen in step.
            self.scheduleLiveActivityUpdate()
        }
    }

    func message(for error: Error) -> String {
        if let engine = error as? EngineError { return t(engine.messageKey) }
        if let persistence = error as? PersistenceError {
            switch persistence {
            case .corrupt, .unsupportedFormat, .invalidBackup: return t("error.backupInvalid")
            case .newerVersion: return t("error.backupNewer")
            case .tooLarge: return t("error.backupTooLarge")
            }
        }
        return t("error.saveFailed")
    }

    func show(_ error: Error) {
        alert = AlertInfo(title: t("common.error"), message: message(for: error))
    }

    // MARK: Scene lifecycle

    func sceneBecameActive() {
        haptics.prepare()
        if DayKey.key(Date()) != lastSeenDay { refreshForNewDay() }
        reloadFromDisk()
        liveActivityRef = currentLiveRef()
    }

    func sceneEnteredBackground() {
        idleTask?.cancel()
        UIApplication.shared.isIdleTimerDisabled = false
        pauseTimer()
        pushLiveActivity()
        // Write off the main thread; a background task keeps the app alive until it is done.
        endBackgroundSave()
        backgroundSaveID = UIApplication.shared.beginBackgroundTask(withName: "zikr.save") { [weak self] in
            MainActor.assumeIsolated { self?.endBackgroundSave() }
        }
        sync.flushAsync { [weak self] in
            guard let self else { return }
            self.file.makeDailySnapshot()
            WidgetCenter.shared.reloadAllTimelines()
            self.endBackgroundSave()
        }
    }

    private func endBackgroundSave() {
        guard backgroundSaveID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundSaveID)
        backgroundSaveID = .invalid
    }

    // MARK: Counting

    func tap() {
        guard let ref = activeRef else { return }
        let now = Date()
        switch mutate({ d in try Actions.tap(&d, ref: ref, now: now) }) {
        case .success(let result):
            if data.settings.haptics { haptics.play(result.outcome) }
            announce(result)
            keepAwakeWhileCounting()
            if result.outcome == .programCompleted {
                if liveActivityRef == ref {
                    liveActivity.update(status: Actions.status(data, ref: ref), completed: true)
                    lastLiveUpdate = Date()
                }
                if nightModePresented {
                    nightCompletionToken += 1
                } else {
                    completion = CompletionInfo(title: result.title, programID: ref.id)
                }
            }
            scheduleLiveActivityUpdate()
        case .failure(let error):
            if data.settings.haptics { haptics.warning() }
            show(error)
        }
    }

    func undo() {
        guard let ref = activeRef else { return }
        let now = Date()
        switch mutate({ d in try Actions.undo(&d, ref: ref, now: now) }) {
        case .success:
            if data.settings.haptics { haptics.undo() }
            scheduleLiveActivityUpdate()
        case .failure(let error):
            show(error)
        }
    }

    /// VoiceOver users hear milestones they cannot feel or see.
    private func announce(_ result: TapResult) {
        guard UIAccessibility.isVoiceOverRunning else { return }
        let key: String?
        switch result.outcome {
        case .counted: key = nil
        case .intervalReached: key = "a11y.round"
        case .dailyGoalReached: key = "a11y.dailyGoalReached"
        case .goalReached: key = "a11y.goalReached"
        case .stepCompleted: key = "a11y.stepDone"
        case .programCompleted: key = "completion.title"
        }
        if let key { AccessibilityNotification.Announcement(t(key)).post() }
    }

    /// Keeps the screen on for two minutes after the last tap, so it does not lock mid-count.
    func keepAwakeWhileCounting() {
        guard data.settings.keepScreenOn else { return }
        UIApplication.shared.isIdleTimerDisabled = true
        idleTask?.cancel()
        idleTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(120))
            guard !Task.isCancelled, !self.nightModePresented else { return }
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    /// Called at midnight / time-zone change so "today" values refresh while the app is open.
    func refreshForNewDay() {
        lastSeenDay = DayKey.key(Date())
        dayRefresh += 1
        reloadWidgetsSoon()
    }

    func canUndo(_ ref: ItemRef?) -> Bool {
        guard let ref else { return false }
        switch ref.kind {
        case .counter: return !(data.counter(ref.id)?.undoLog.isEmpty ?? true)
        case .program:
            guard let program = data.program(ref.id) else { return false }
            return program.session != nil || program.lastCompleted != nil
        }
    }

    func select(_ ref: ItemRef) {
        if let running = timerRef, running != ref { pauseTimer() }
        attempt { d in d.active = ref }
        tab = .home
    }

    // MARK: Counters

    func createCounter(title: String, initial: Int, goal: Int?, interval: Int?, dailyGoal: Int?, note: String) throws {
        guard data.activeCounters.count < Limits.activeCounters else { throw EngineError.counterLimit }
        let counter = try CounterEngine.create(title: title, initial: initial, goal: goal, interval: interval,
                                               dailyGoal: dailyGoal, note: note)
        try run { d in
            guard !d.counters.contains(where: { $0.id == counter.id }) else { return }
            guard d.activeCounters.count < Limits.activeCounters else { throw EngineError.counterLimit }
            d.counters.append(counter)
            d.active = .counter(counter.id)
        }
    }

    func updateCounter(id: UUID, title: String, goal: Int?, interval: Int?, dailyGoal: Int?, note: String) throws {
        let now = Date()
        try run { d in
            guard let i = d.counters.firstIndex(where: { $0.id == id }) else { throw EngineError.notFound }
            try CounterEngine.update(&d.counters[i], title: title, goal: goal, interval: interval,
                                     dailyGoal: dailyGoal, note: note, now: now)
        }
        resyncReminders()
    }

    func adjust(counterID: UUID, to value: Int) throws {
        let now = Date()
        try run { d in
            guard let i = d.counters.firstIndex(where: { $0.id == counterID }) else { throw EngineError.notFound }
            try CounterEngine.adjust(&d.counters[i], to: value, now: now)
        }
        scheduleLiveActivityUpdate()
    }

    // MARK: Programs

    func createProgram(title: String, steps: [StepDraft], note: String) throws {
        guard data.activePrograms.count < Limits.activePrograms else { throw EngineError.programLimit }
        let program = try ProgramEngine.create(title: title, steps: steps, note: note)
        try run { d in
            guard !d.programs.contains(where: { $0.id == program.id }) else { return }
            guard d.activePrograms.count < Limits.activePrograms else { throw EngineError.programLimit }
            d.programs.append(program)
            d.active = .program(program.id)
        }
    }

    func updateProgram(id: UUID, title: String, steps: [StepDraft], note: String) throws {
        let now = Date()
        try run { d in
            guard let i = d.programs.firstIndex(where: { $0.id == id }) else { throw EngineError.notFound }
            try ProgramEngine.update(&d.programs[i], title: title, steps: steps, note: note, now: now)
        }
        resyncReminders()
        scheduleLiveActivityUpdate()
    }

    func restartProgram(id: UUID) {
        let now = Date()
        attempt { d in
            guard let i = d.programs.firstIndex(where: { $0.id == id }) else { throw EngineError.notFound }
            ProgramEngine.restart(&d.programs[i], now: now)
        }
        scheduleLiveActivityUpdate()
    }

    // MARK: Organizing

    func togglePin(_ ref: ItemRef) {
        attempt { d in try Actions.togglePin(ref, in: &d) }
    }

    func archive(_ ref: ItemRef) {
        if timerRef == ref { pauseTimer() }
        let now = Date()
        if attempt({ d in try Actions.setArchived(true, ref: ref, in: &d, now: now) }) {
            if liveActivityRef == ref { endLiveActivity() }
            resyncReminders()
        }
    }

    func unarchive(_ ref: ItemRef) {
        let now = Date()
        attempt { d in try Actions.setArchived(false, ref: ref, in: &d, now: now) }
    }

    func delete(_ ref: ItemRef) {
        if timerRef == ref { timerRef = nil; timerStart = nil }
        attempt { d in Actions.delete(ref, in: &d) }
        if liveActivityRef == ref { endLiveActivity() }
        resyncReminders()
    }

    // MARK: Reminders

    func reminder(for ref: ItemRef) -> Reminder? {
        data.reminders.first { $0.target == ref }
    }

    /// Returns true when saved.
    func saveReminder(_ reminder: Reminder) async -> Bool {
        if reminder.enabled {
            if await ReminderScheduler.requestAuthorization() == .denied {
                alert = AlertInfo(title: t("reminders.deniedTitle"), message: t("reminders.deniedMessage"),
                                  action: .openNotificationSettings)
                return false
            }
        }
        guard attempt({ d in try Actions.setReminder(reminder, in: &d) }) else { return false }
        resyncReminders()
        return true
    }

    /// Rebuilds pending notifications. Runs strictly one after another and always from the
    /// latest data, so an older run can never re-add a reminder a newer one removed.
    func resyncReminders() {
        let previous = reminderTask
        reminderTask = Task { @MainActor in
            await previous?.value
            await ReminderScheduler.resync(self.data, language: self.language)
        }
    }

    private func openFromNotification(_ raw: String) {
        guard let ref = ItemRef(storageString: raw), data.isLive(ref) else { return }
        select(ref)
    }

    // MARK: Settings

    func setLanguage(_ value: AppLanguage?) {
        attempt { d in d.settings.language = value }
        resyncReminders()
        WidgetCenter.shared.reloadAllTimelines()
    }

    func setAppearance(_ value: AppAppearance) { attempt { d in d.settings.appearance = value } }
    func setHaptics(_ value: Bool) { attempt { d in d.settings.haptics = value } }
    func setKeepScreenOn(_ value: Bool) { attempt { d in d.settings.keepScreenOn = value } }
    func setNightShowDigits(_ value: Bool) { attempt { d in d.settings.nightShowDigits = value } }
    func setNightOpacity(_ value: Double) { attempt { d in d.settings.nightDigitsOpacity = min(1, max(0.1, value)) } }

    func completeOnboarding(with choice: StarterChoice?) {
        do {
            switch choice {
            case .freeCount?:
                try createCounter(title: t("starter.freeTitle"), initial: 0, goal: nil, interval: 33, dailyGoal: nil, note: "")
            case .goal100?:
                try createCounter(title: t("starter.goalTitle"), initial: 0, goal: 100, interval: nil, dailyGoal: nil, note: "")
            case .program?:
                let steps = [33, 33, 34].enumerated().map { StepDraft(title: f("starter.step", num($0.offset + 1)), target: $0.element) }
                try createProgram(title: t("starter.programTitle"), steps: steps, note: "")
            case nil:
                break
            }
        } catch {
            show(error)
        }
        attempt { d in d.onboardingDone = true }
    }

    // MARK: Stopwatch

    func startTimer() {
        guard let ref = activeRef else { return }
        if timerRef != nil { pauseTimer() }
        timerRef = ref
        timerStart = Date()
    }

    func pauseTimer(at date: Date = Date()) {
        guard let ref = timerRef, let start = timerStart else { return }
        timerRef = nil
        timerStart = nil
        let seconds = Int(date.timeIntervalSince(start))
        guard seconds > 0 else { return }
        attempt { d in Actions.record(seconds: seconds, ref: ref, in: &d, now: date) }
    }

    func elapsed(at date: Date) -> Int {
        guard let start = timerStart else { return 0 }
        return max(0, Int(date.timeIntervalSince(start)))
    }

    // MARK: Backup

    func makeBackupFile() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Exports", isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = "ZIKR-backup-\(DayKey.key(Date())).json"
        let url = directory.appendingPathComponent(name)
        try DataFile.encode(data).write(to: url, options: .atomic)
        return url
    }

    func previewBackup(_ raw: Data) throws -> ZikrData {
        try Migration.decodeBackup(raw)
    }

    func restore(_ replacement: ZikrData) throws {
        pauseTimer()
        sync.flush()
        var next = replacement
        next.onboardingDone = true
        try file.replace(with: next)
        data = next
        inFlight = 0
        endLiveActivity()
        resyncReminders()
        WidgetCenter.shared.reloadAllTimelines()
    }

    func snapshots() -> [SnapshotInfo] { file.snapshots() }

    func restoreSnapshot(_ snapshot: SnapshotInfo) throws {
        let raw = try Data(contentsOf: snapshot.url)
        try restore(try Migration.decodeBackup(raw))
    }

    // MARK: Recovery

    /// Starts with empty data. The unreadable file is moved aside (never deleted).
    func startFresh() {
        file.quarantineCurrentFile()
        loadIssue = nil
        data = ZikrData()
        sync.setBlocked(false)
    }

    func recoverFromSnapshot(_ snapshot: SnapshotInfo) {
        do {
            let raw = try Data(contentsOf: snapshot.url)
            let restored = try Migration.decodeBackup(raw)
            loadIssue = nil
            sync.setBlocked(false)
            try restore(restored)
        } catch {
            show(error)
        }
    }

    // MARK: Live Activity

    func toggleLiveActivity() {
        guard let status = activeStatus else { return }
        if liveActivityRef == status.ref {
            endLiveActivity()
            return
        }
        guard liveActivity.isSupported else {
            alert = AlertInfo(title: t("live.title"), message: t("live.disabled"))
            return
        }
        do {
            try liveActivity.start(status: status, language: language)
            liveActivityRef = status.ref
        } catch {
            alert = AlertInfo(title: t("live.title"), message: t("live.failed"))
        }
    }

    func endLiveActivity() {
        liveActivity.endAll()
        liveActivityRef = nil
    }

    private func currentLiveRef() -> ItemRef? {
        liveActivity.currentItemID.flatMap(ItemRef.init(storageString:))
    }

    private func scheduleLiveActivityUpdate() {
        guard liveActivityRef != nil else { return }
        let elapsed = Date().timeIntervalSince(lastLiveUpdate)
        if elapsed >= 1 {
            pushLiveActivity()
        } else if !liveUpdateScheduled {
            liveUpdateScheduled = true
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1 - elapsed))
                self.liveUpdateScheduled = false
                self.pushLiveActivity()
            }
        }
    }

    private func pushLiveActivity() {
        lastLiveUpdate = Date()
        guard let ref = liveActivityRef else { return }
        liveActivity.update(status: Actions.status(data, ref: ref))
    }

    // MARK: Widgets

    private func reloadWidgetsSoon() {
        let elapsed = Date().timeIntervalSince(lastWidgetReload)
        if elapsed >= 2 {
            lastWidgetReload = Date()
            WidgetCenter.shared.reloadAllTimelines()
        } else if !widgetReloadScheduled {
            widgetReloadScheduled = true
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                self.widgetReloadScheduled = false
                self.lastWidgetReload = Date()
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }
}
