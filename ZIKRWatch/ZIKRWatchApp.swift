import SwiftUI

@main
struct ZIKRWatchApp: App {
    @State private var model = WatchModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                CounterScreen()
            }
            .environment(model)
            .tint(WatchTheme.primary)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.requestRefresh() }
        }
    }
}

enum WatchTheme {
    static let primary = Color(red: 0.38, green: 0.74, blue: 0.57)
    static let gold = Color(red: 0.87, green: 0.74, blue: 0.45)
}
