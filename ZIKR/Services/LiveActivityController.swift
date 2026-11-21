import ActivityKit
import Foundation

/// Starts and stops the Lock Screen / Dynamic Island counting session.
@MainActor
final class LiveActivityController {
    var isSupported: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    func isRunning(for ref: ItemRef) -> Bool {
        Activity<ZikrActivityAttributes>.activities.contains { $0.attributes.itemID == ref.storageString }
    }

    var hasAny: Bool { !Activity<ZikrActivityAttributes>.activities.isEmpty }

    var currentItemID: String? {
        Activity<ZikrActivityAttributes>.activities.first { $0.activityState == .active }?.attributes.itemID
    }

    func start(status: ItemStatus, language: AppLanguage) throws {
        endAll()
        let attributes = ZikrActivityAttributes(itemID: status.ref.storageString,
                                                todayLabel: L10n.t("common.today", language),
                                                addLabel: L10n.t("live.add", language),
                                                doneLabel: L10n.t("live.done", language))
        let content = ActivityContent(state: ZikrActivityAttributes.ContentState(status: status),
                                      staleDate: Date().addingTimeInterval(8 * 3600))
        _ = try Activity.request(attributes: attributes, content: content, pushType: nil)
    }

    func update(status: ItemStatus?, completed: Bool = false) {
        guard let status else { return }
        for activity in Activity<ZikrActivityAttributes>.activities where activity.attributes.itemID == status.ref.storageString {
            let state = ZikrActivityAttributes.ContentState(status: status, completed: completed)
            Task { await activity.update(ActivityContent(state: state, staleDate: Date().addingTimeInterval(8 * 3600))) }
        }
    }

    func endAll() {
        for activity in Activity<ZikrActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
