import AppIntents
import Foundation
import WidgetKit

/// Shared mutations performed outside the main app UI (widgets, Control Center, Action button,
/// Siri/Shortcuts, Live Activity button). They write the file directly and notify the app.
enum SharedActions {
    @discardableResult
    static func tap(ref: ItemRef? = nil, now: Date = Date()) throws -> TapResult {
        var result = TapResult(title: "", value: 0, outcome: .counted)
        try DataFile.shared.update { data in
            result = try Actions.tap(&data, ref: ref, now: now)
        }
        didChange()
        return result
    }

    @discardableResult
    static func undo(ref: ItemRef? = nil, now: Date = Date()) throws -> Int {
        var value = 0
        try DataFile.shared.update { data in
            value = try Actions.undo(&data, ref: ref, now: now)
        }
        didChange()
        return value
    }

    static func didChange() {
        DarwinNotifier.post()
        WidgetCenter.shared.reloadAllTimelines()
        ControlCenter.shared.reloadAllControls()
    }
}

struct IntentFailure: Error, CustomLocalizedStringResourceConvertible {
    var key: String
    var localizedStringResource: LocalizedStringResource {
        switch key {
        case "error.noActiveItem":
            return LocalizedStringResource("intent.error.noActive", defaultValue: "Open ZIKR and create a counter first.")
        default:
            return LocalizedStringResource("intent.error.generic", defaultValue: "Could not update the counter.")
        }
    }

    static func from(_ error: Error) -> IntentFailure {
        if let engine = error as? EngineError { return IntentFailure(key: engine.messageKey) }
        return IntentFailure(key: "generic")
    }
}

/// +1 to the current counter or program step (or to a chosen one). Used by the Action button,
/// Back Tap (via Shortcuts), Siri, the Control Center control and the interactive widget.
///
/// Conforms to `LiveActivityIntent` so the system runs it in the app process even when it is
/// triggered from a widget or Control Center; that lets it update the Live Activity too.
struct IncrementIntent: LiveActivityIntent {
    static let title = LocalizedStringResource("intent.increment.title", defaultValue: "Add one")
    static let description: IntentDescription? = IntentDescription(LocalizedStringResource("intent.increment.description",
                                                                       defaultValue: "Adds one to the current counter in ZIKR."))
    static let openAppWhenRun: Bool = false

    @Parameter(title: LocalizedStringResource("entity.item", defaultValue: "Counter"))
    var item: ItemEntity?

    init() {}

    init(item: ItemEntity?) {
        self.item = item
    }

    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        do {
            let result = try SharedActions.tap(ref: item?.ref)
            await LiveActivitySync.refresh()
            return .result(value: result.value, dialog: IntentDialog(stringLiteral: "\(result.title): \(result.value)"))
        } catch {
            throw IntentFailure.from(error)
        }
    }
}

struct UndoIntent: LiveActivityIntent {
    static let title = LocalizedStringResource("intent.undo.title", defaultValue: "Undo last tap")
    static let description: IntentDescription? = IntentDescription(LocalizedStringResource("intent.undo.description",
                                                                       defaultValue: "Removes the last tap from the current counter."))
    static let openAppWhenRun: Bool = false

    @Parameter(title: LocalizedStringResource("entity.item", defaultValue: "Counter"))
    var item: ItemEntity?

    init() {}

    init(item: ItemEntity?) {
        self.item = item
    }

    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        do {
            let value = try SharedActions.undo(ref: item?.ref)
            await LiveActivitySync.refresh()
            return .result(value: value, dialog: IntentDialog(stringLiteral: "\(value)"))
        } catch {
            throw IntentFailure.from(error)
        }
    }
}

struct CurrentCountIntent: AppIntent {
    static let title = LocalizedStringResource("intent.current.title", defaultValue: "Current count")
    static let description: IntentDescription? = IntentDescription(LocalizedStringResource("intent.current.description",
                                                                       defaultValue: "Tells the value of the current counter."))
    static let openAppWhenRun: Bool = false

    init() {}

    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        guard let data = DataFile.shared.peek(), let status = Actions.status(data, ref: nil) else {
            throw IntentFailure(key: "error.noActiveItem")
        }
        return .result(value: status.value, dialog: IntentDialog(stringLiteral: "\(status.title): \(status.value)"))
    }
}

/// Button inside the Live Activity. Runs in the app process so it can update the activity.
struct LiveIncrementIntent: LiveActivityIntent {
    static let title = LocalizedStringResource("intent.increment.title", defaultValue: "Add one")
    static let isDiscoverable: Bool = false

    @Parameter(title: LocalizedStringResource("intent.param.item", defaultValue: "Item"))
    var itemID: String

    init() {}

    init(itemID: String) {
        self.itemID = itemID
    }

    func perform() async throws -> some IntentResult {
        // Never fall back to "the current item": the Lock Screen shows a specific one.
        guard let ref = ItemRef(storageString: itemID) else { throw IntentFailure(key: "error.notFound") }
        do {
            try SharedActions.tap(ref: ref)
        } catch {
            throw IntentFailure.from(error)
        }
        await LiveActivitySync.refresh()
        return .result()
    }
}
