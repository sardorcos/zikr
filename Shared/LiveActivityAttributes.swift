import Foundation
import ActivityKit

/// Lock Screen / Dynamic Island counting session.
struct ZikrActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var title: String
        var value: Int
        var target: Int?
        var today: Int
        var stepPosition: String?
        var stepTitle: String?
        var completed: Bool
    }

    /// `ItemRef.storageString` of the item being counted.
    var itemID: String
    /// Localized labels captured when the activity starts (widgets cannot read app settings fast enough).
    var todayLabel: String
    var addLabel: String
    var doneLabel: String
}

extension ZikrActivityAttributes.ContentState {
    init(status: ItemStatus, completed: Bool = false) {
        self.init(title: status.title, value: status.value, target: status.target, today: status.today,
                  stepPosition: status.stepPosition, stepTitle: status.stepTitle, completed: completed)
    }
}

/// Pushes the current file state into running Live Activities. Only works in the app process.
enum LiveActivitySync {
    static func refresh() async {
        guard !RuntimeInfo.isAppExtension else { return }
        let activities = Activity<ZikrActivityAttributes>.activities
        guard !activities.isEmpty, let data = DataFile.shared.peek() else { return }
        for activity in activities {
            guard let ref = ItemRef(storageString: activity.attributes.itemID),
                  data.isLive(ref), let status = Actions.status(data, ref: ref) else {
                await activity.end(nil, dismissalPolicy: .immediate)
                continue
            }
            let state = ZikrActivityAttributes.ContentState(status: status)
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
    }
}
