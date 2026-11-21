import Foundation
import Observation
import WatchConnectivity
import WatchKit

/// Watch-side state. Shows the phone's snapshot plus taps that the phone has not confirmed yet,
/// so counting on the wrist is instant and works without the phone nearby. Pending taps and the
/// last snapshot are persisted, so nothing is lost if the watch app is closed.
@Observable
@MainActor
final class WatchModel: NSObject {
    private(set) var snapshot: WatchSnapshot = .empty
    private(set) var pending: [WatchTap] = []
    var selectedID: String?
    private(set) var lastMilestone: WatchEmulation.Milestone = .none
    private(set) var milestoneToken = 0
    private(set) var phoneReachable = false

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private let snapshotKey = "zikr.watch.snapshot"
    @ObservationIgnored private let pendingKey = "zikr.watch.pending"
    @ObservationIgnored private let selectedKey = "zikr.watch.selected"

    override init() {
        super.init()
        #if DEBUG
        if let demo = WatchScreenshotDemo.snapshotIfRequested() {
            snapshot = demo
            selectedID = demo.activeID
            return
        }
        #endif
        snapshot = WatchSnapshot.decode(defaults.data(forKey: snapshotKey)) ?? .empty
        pending = (try? JSONDecoder().decode([WatchTap].self, from: defaults.data(forKey: pendingKey) ?? Data())) ?? []
        selectedID = defaults.string(forKey: selectedKey)
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    // MARK: Derived state

    var language: String {
        if !snapshot.language.isEmpty { return snapshot.language }
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? "en"
        if preferred.hasPrefix("uz-cyrl") { return "uz-Cyrl" }
        if preferred.hasPrefix("uz") { return "uz" }
        if preferred.hasPrefix("ru") { return "ru" }
        return "en"
    }

    /// Items with unconfirmed taps applied on top of the phone's numbers.
    var items: [WatchItem] {
        var byID = Dictionary(uniqueKeysWithValues: snapshot.items.map { ($0.id, $0) })
        for tap in pending {
            guard var item = byID[tap.ref] else { continue }
            _ = WatchEmulation.apply(tap.delta, to: &item)
            byID[tap.ref] = item
        }
        return snapshot.items.compactMap { byID[$0.id] }
    }

    var current: WatchItem? {
        let list = items
        if let selectedID, let item = list.first(where: { $0.id == selectedID }) { return item }
        if let active = snapshot.activeID, let item = list.first(where: { $0.id == active }) { return item }
        return list.first
    }

    var hasData: Bool { !snapshot.items.isEmpty }
    var unsyncedCount: Int { pending.count }

    // MARK: Actions

    func select(_ id: String) {
        selectedID = id
        defaults.set(id, forKey: selectedKey)
    }

    func tap() { record(+1) }

    func undo() {
        guard let item = current, canUndo(item) else { return }
        record(-1)
    }

    func canUndo(_ item: WatchItem) -> Bool { item.value > 0 || item.today > 0 }

    private func record(_ delta: Int) {
        guard var item = current else { return }
        let milestone = WatchEmulation.apply(delta, to: &item)
        let tap = WatchTap(ref: item.id, delta: delta, at: Date())
        pending.append(tap)
        persistPending()
        if snapshot.haptics { play(delta < 0 ? .directionDown : haptic(for: milestone)) }
        if milestone != .none {
            lastMilestone = milestone
            milestoneToken += 1
        }
        send(tap)
    }

    private func haptic(for milestone: WatchEmulation.Milestone) -> WKHapticType {
        switch milestone {
        case .none: return .click
        case .interval: return .directionUp
        case .goal, .step: return .success
        case .programCompleted: return .notification
        }
    }

    private func play(_ type: WKHapticType) {
        WKInterfaceDevice.current().play(type)
    }

    // MARK: Sync

    private func send(_ tap: WatchTap) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated, let data = tap.encoded() else { return }
        // Queued by the system and delivered even if the phone is not reachable right now.
        _ = WCSession.default.transferUserInfo([WatchSync.tapKey: data])
    }

    /// Re-queues taps that were recorded before the session was activated.
    private func resendUnqueued() {
        let queued = Set(WCSession.default.outstandingUserInfoTransfers.compactMap {
            WatchTap.decode($0.userInfo[WatchSync.tapKey] as? Data)?.id
        })
        for tap in pending where !queued.contains(tap.id) {
            send(tap)
        }
    }

    private func adopt(_ incoming: WatchSnapshot) {
        let applied = Set(incoming.applied)
        pending.removeAll { applied.contains($0.id) }
        persistPending()
        snapshot = incoming
        if let data = incoming.encoded() { defaults.set(data, forKey: snapshotKey) }
        if let selectedID, !incoming.items.contains(where: { $0.id == selectedID }) {
            self.selectedID = nil
            defaults.removeObject(forKey: selectedKey)
        }
    }

    private func persistPending() {
        if let data = try? JSONEncoder().encode(pending) { defaults.set(data, forKey: pendingKey) }
    }

    func requestRefresh() {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated, WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(["refresh": true], replyHandler: nil, errorHandler: nil)
    }
}

extension WatchModel: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let context = session.receivedApplicationContext
        let reachable = session.isReachable
        Task { @MainActor in
            if let snap = WatchSnapshot.decode(context[WatchSync.snapshotKey] as? Data) { self.adopt(snap) }
            self.phoneReachable = reachable
            self.resendUnqueued()
            self.requestRefresh()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let snap = WatchSnapshot.decode(applicationContext[WatchSync.snapshotKey] as? Data) else { return }
        Task { @MainActor in self.adopt(snap) }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in
            self.phoneReachable = reachable
            if reachable { self.requestRefresh() }
        }
    }
}
