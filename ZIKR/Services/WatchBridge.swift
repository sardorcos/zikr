import Foundation
import WatchConnectivity

/// iPhone side of the Apple Watch link. Publishes a snapshot of the active counters and programs
/// as WatchConnectivity application context after every change, and applies taps coming from the
/// watch through `AppStore` (the same engine as taps on the phone). Applied tap IDs are remembered
/// so a tap is never counted twice, even if the system redelivers it.
@MainActor
final class WatchBridge: NSObject {
    static let shared = WatchBridge()

    /// Applies one tap from the watch. Returns false if it could not be applied (e.g. the item was deleted).
    var applyTap: ((WatchTap) -> Bool)?
    /// Supplies the snapshot contents (items, active item, language, haptics) on demand.
    var makeSnapshot: (() -> WatchSnapshot)?

    private var applied: [UUID] = []
    private var appliedSet: Set<UUID> = []
    private var pushScheduled = false
    private var lastPushed: WatchSnapshot?
    private let appliedKey = "zikr.watch.applied"

    private override init() {
        super.init()
        let saved = (UserDefaults.standard.array(forKey: appliedKey) as? [String] ?? []).compactMap(UUID.init(uuidString:))
        applied = saved
        appliedSet = Set(saved)
    }

    var isSupported: Bool { WCSession.isSupported() }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// Coalesces bursts of changes (fast counting) into one context update.
    func scheduleSnapshot() {
        guard WCSession.isSupported(), !pushScheduled else { return }
        pushScheduled = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            self.pushScheduled = false
            self.pushNow()
        }
    }

    private func pushNow() {
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled,
              var snapshot = makeSnapshot?() else { return }
        snapshot.applied = Array(applied.suffix(WatchSync.appliedWindow))
        var comparable = snapshot
        comparable.generatedAt = lastPushed?.generatedAt ?? comparable.generatedAt
        guard comparable != lastPushed, let data = snapshot.encoded() else { return }
        do {
            try session.updateApplicationContext([WatchSync.snapshotKey: data])
            lastPushed = snapshot
        } catch {
            // The context is retried with the next change; counting on the phone is unaffected.
        }
    }

    private func receive(_ tap: WatchTap) {
        guard !appliedSet.contains(tap.id) else {
            scheduleSnapshot()
            return
        }
        _ = applyTap?(tap)
        // Remember the ID even if it failed (deleted item): the watch must drop it either way.
        applied.append(tap.id)
        appliedSet.insert(tap.id)
        if applied.count > WatchSync.appliedWindow * 2 {
            let drop = applied.prefix(applied.count - WatchSync.appliedWindow * 2)
            drop.forEach { appliedSet.remove($0) }
            applied.removeFirst(drop.count)
        }
        UserDefaults.standard.set(applied.map(\.uuidString), forKey: appliedKey)
        scheduleSnapshot()
    }
}

extension WatchBridge: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.scheduleSnapshot() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Switching to another watch: reactivate for the new one.
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.scheduleSnapshot() }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let tap = WatchTap.decode(userInfo[WatchSync.tapKey] as? Data) else { return }
        Task { @MainActor in self.receive(tap) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        // The watch asks for a fresh snapshot when it opens.
        Task { @MainActor in
            self.lastPushed = nil
            self.scheduleSnapshot()
        }
    }
}

// MARK: - Snapshot from the app data

extension WatchSnapshot {
    @MainActor
    static func from(_ data: ZikrData, language: AppLanguage, now: Date = Date()) -> WatchSnapshot {
        var items: [WatchItem] = []
        for c in data.activeCounters {
            items.append(WatchItem(id: ItemRef.counter(c.id).storageString, kind: .counter, title: c.title, value: c.value,
                                   goal: c.goal, interval: c.interval, steps: [], stepIndex: 0,
                                   today: CounterEngine.today(c, now: now), pinned: c.pinned))
        }
        for p in data.activePrograms where !p.steps.isEmpty {
            let session = p.session ?? ProgramSession()
            items.append(WatchItem(id: ItemRef.program(p.id).storageString, kind: .program, title: p.title, value: session.count,
                                   goal: nil, interval: nil, steps: p.steps.map { WatchStep(title: $0.title, target: $0.target) },
                                   stepIndex: min(session.stepIndex, p.steps.count - 1),
                                   today: ProgramEngine.today(p, now: now), pinned: p.pinned))
        }
        items.sort { ($0.pinned ? 0 : 1, $0.title.lowercased()) < ($1.pinned ? 0 : 1, $1.title.lowercased()) }
        return WatchSnapshot(items: items, activeID: Actions.resolvedActive(data)?.storageString, language: language.rawValue,
                             haptics: data.settings.haptics, applied: [], generatedAt: now)
    }
}
