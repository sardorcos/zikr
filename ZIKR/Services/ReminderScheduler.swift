import Foundation
import UserNotifications

/// Keeps pending local notifications in sync with the reminders stored in the data file.
/// Always rebuilds the full set, so archived/deleted items, restored backups and language
/// changes can never leave stale notifications behind.
enum ReminderScheduler {
    static let prefix = "zikr-reminder-"

    enum Authorization { case granted, denied }

    static func requestAuthorization() async -> Authorization {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return .granted
        case .denied:
            return .denied
        default:
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            return granted ? .granted : .denied
        }
    }

    static func resync(_ data: ZikrData, language: AppLanguage) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)

        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        for reminder in data.reminders where reminder.enabled && data.isLive(reminder.target) {
            guard let title = data.title(of: reminder.target) else { continue }
            for weekday in Set(reminder.weekdays) where (1...7).contains(weekday) {
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = L10n.t("reminder.body", language)
                content.sound = .default
                content.userInfo = ["ref": reminder.target.storageString]
                content.threadIdentifier = reminder.target.storageString
                var components = DateComponents()
                components.weekday = weekday
                components.hour = reminder.hour
                components.minute = reminder.minute
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
                let request = UNNotificationRequest(identifier: "\(prefix)\(reminder.id.uuidString)-\(weekday)",
                                                    content: content, trigger: trigger)
                try? await center.add(request)
            }
        }
    }
}
