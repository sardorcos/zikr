import AppIntents
import SwiftUI
import WidgetKit

/// Control Center / Lock Screen / Action button control (iOS 18).
struct CounterControl: ControlWidget {
    static let kind = "ZIKRCounterControl"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: IncrementIntent()) {
                Label(L10n.t("control.label", .preferred()), systemImage: "plus.circle.fill")
            }
        }
        .displayName(LocalizedStringResource("control.name", defaultValue: "ZIKR +1"))
        .description(LocalizedStringResource("control.description", defaultValue: "Adds one to the current counter."))
    }
}
