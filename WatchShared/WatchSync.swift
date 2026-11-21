import Foundation

/// Wire format between the iPhone app and the Apple Watch app (WatchConnectivity).
///
/// The iPhone is the source of truth. It sends a `WatchSnapshot` (application context) after every
/// change; the watch sends each tap as a `WatchTap` through `transferUserInfo`, which the system
/// queues and delivers even if the phone is out of reach. Every tap has a UUID; the phone reports the
/// IDs it has applied so the watch can drop them from its pending queue (exactly-once counting).
enum WatchSync {
    static let snapshotKey = "zikr.snapshot"
    static let tapKey = "zikr.tap"
    /// How many applied tap IDs the phone echoes back in each snapshot.
    static let appliedWindow = 300
}

struct WatchStep: Codable, Equatable, Sendable {
    var title: String
    var target: Int
}

struct WatchItem: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable { case counter, program }

    /// `ItemRef.storageString` ("counter:UUID" / "program:UUID").
    var id: String
    var kind: Kind
    var title: String
    /// Counter: total value. Program: count inside the current step.
    var value: Int
    /// Counter only: overall goal and "signal every N taps".
    var goal: Int?
    var interval: Int?
    /// Program only.
    var steps: [WatchStep]
    var stepIndex: Int
    var today: Int
    var pinned: Bool
}

struct WatchSnapshot: Codable, Equatable, Sendable {
    var items: [WatchItem]
    var activeID: String?
    /// App language raw value ("ru", "uz", "uz-Cyrl", "en").
    var language: String
    var haptics: Bool
    var applied: [UUID]
    var generatedAt: Date

    static let empty = WatchSnapshot(items: [], activeID: nil, language: "", haptics: true, applied: [], generatedAt: .distantPast)

    func encoded() -> Data? { try? JSONEncoder().encode(self) }
    static func decode(_ data: Data?) -> WatchSnapshot? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(WatchSnapshot.self, from: data)
    }
}

struct WatchTap: Codable, Equatable, Identifiable, Sendable {
    var id: UUID = UUID()
    /// `ItemRef.storageString` of the counter or program.
    var ref: String
    /// +1 for a tap, -1 for undo.
    var delta: Int
    /// When it happened on the wrist (attributes the tap to the right day).
    var at: Date

    func encoded() -> Data? { try? JSONEncoder().encode(self) }
    static func decode(_ data: Data?) -> WatchTap? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(WatchTap.self, from: data)
    }
}

/// Applies a tap to a watch item the same way the phone's engine does, for instant display on the
/// wrist before the phone confirms. Returns the milestone reached, if any.
enum WatchEmulation {
    enum Milestone: Equatable, Sendable { case none, interval, goal, step, programCompleted }

    static func apply(_ delta: Int, to item: inout WatchItem) -> Milestone {
        switch item.kind {
        case .counter:
            if delta < 0 {
                item.value = max(0, item.value - 1)
                item.today = max(0, item.today - 1)
                return .none
            }
            item.value += 1
            item.today += 1
            if let goal = item.goal, goal > 0, item.value == goal { return .goal }
            if let interval = item.interval, interval > 0, item.value % interval == 0 { return .interval }
            return .none
        case .program:
            guard !item.steps.isEmpty else { return .none }
            if delta < 0 {
                if item.value > 0 {
                    item.value -= 1
                    item.today = max(0, item.today - 1)
                }
                return .none
            }
            item.value += 1
            item.today += 1
            let index = min(item.stepIndex, item.steps.count - 1)
            guard item.value >= item.steps[index].target else { return .none }
            if index + 1 < item.steps.count {
                item.stepIndex = index + 1
                item.value = 0
                return .step
            }
            item.stepIndex = 0
            item.value = 0
            return .programCompleted
        }
    }
}
