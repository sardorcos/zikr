import AppIntents
import Foundation
import WidgetKit

/// A counter or program exposed to the system (widget configuration, Shortcuts, Siri).
struct ItemEntity: AppEntity, Identifiable, Hashable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("entity.item", defaultValue: "Counter"))
    static let defaultQuery = ItemEntityQuery()

    /// `ItemRef.storageString`.
    var id: String
    var title: String
    var isProgram: Bool

    var ref: ItemRef? { ItemRef(storageString: id) }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)",
                              image: DisplayRepresentation.Image(systemName: isProgram ? "list.number" : "circle.circle"))
    }
}

struct ItemEntityQuery: EntityQuery {
    init() {}

    func entities(for identifiers: [ItemEntity.ID]) async throws -> [ItemEntity] {
        let all = Self.all()
        return identifiers.compactMap { id in all.first { $0.id == id } }
    }

    func suggestedEntities() async throws -> [ItemEntity] {
        Self.all()
    }

    static func all() -> [ItemEntity] {
        guard let data = DataFile.shared.peek() else { return [] }
        let counters = data.activeCounters.map {
            ItemEntity(id: ItemRef.counter($0.id).storageString, title: $0.title, isProgram: false)
        }
        let programs = data.activePrograms.map {
            ItemEntity(id: ItemRef.program($0.id).storageString, title: $0.title, isProgram: true)
        }
        return counters + programs
    }
}

/// Lets the user pick which counter a widget shows. Empty = follow the current counter.
struct SelectItemIntent: WidgetConfigurationIntent {
    static let title = LocalizedStringResource("widget.configTitle", defaultValue: "Counter")
    static let description: IntentDescription? = IntentDescription(
        LocalizedStringResource("widget.configDescription",
                                defaultValue: "Choose which counter the widget shows. Leave empty to follow the current one."))

    @Parameter(title: LocalizedStringResource("entity.item", defaultValue: "Counter"))
    var item: ItemEntity?

    init() {}

    init(item: ItemEntity?) {
        self.item = item
    }
}
