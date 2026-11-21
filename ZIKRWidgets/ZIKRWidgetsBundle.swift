import SwiftUI
import WidgetKit

@main
struct ZIKRWidgetsBundle: WidgetBundle {
    var body: some Widget {
        CounterWidget()
        CounterLiveActivity()
        CounterControl()
    }
}
