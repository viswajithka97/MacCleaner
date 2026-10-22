import Foundation
import UserNotifications

/// Posts the app's notifications: low disk, memory pressure, big Trash, weekly reminder.
@MainActor
final class NotificationService {
    static let shared = NotificationService()

    private let center = UNUserNotificationCenter.current()
    /// When each kind of alert was last shown (so we don't nag).
    private var lastShown: [String: Date] = [:]
    private let weeklyID = "weekly-smart-care"

    private init() {}

    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Shows a notification at most once every `minimumInterval` seconds per id.
    func post(id: String, title: String, body: String, minimumInterval: TimeInterval = 6 * 3600) {
        if let last = lastShown[id], Date().timeIntervalSince(last) < minimumInterval { return }
        lastShown[id] = Date()
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: "\(id)-\(UUID().uuidString)", content: content, trigger: nil)
        center.add(request)
    }

    /// Schedules (or removes) a repeating Monday 10:00 reminder to run Smart Care.
    func updateWeeklyReminder(enabled: Bool) {
        center.removePendingNotificationRequests(withIdentifiers: [weeklyID])
        guard enabled else { return }
        requestAuthorization()
        let content = UNMutableNotificationContent()
        content.title = "Time for Smart Care"
        content.body = "Give your Mac a quick clean-up and check-up with MacCleaner."
        content.sound = .default
        var date = DateComponents()
        date.weekday = 2      // Monday
        date.hour = 10
        let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
        center.add(UNNotificationRequest(identifier: weeklyID, content: content, trigger: trigger))
    }
}
