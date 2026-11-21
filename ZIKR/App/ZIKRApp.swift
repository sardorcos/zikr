import SwiftUI
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        guard let ref = response.notification.request.content.userInfo["ref"] as? String else { return }
        await MainActor.run { NotificationRouter.route(ref) }
    }
}

@main
struct ZIKRApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = AppStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(\.locale, store.locale)
                .preferredColorScheme(store.colorScheme)
                .tint(Color.zPrimary)
                .onAppear { store.resyncReminders() }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                    store.refreshForNewDay()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: store.sceneBecameActive()
            case .background: store.sceneEnteredBackground()
            default: break
            }
        }
    }
}
