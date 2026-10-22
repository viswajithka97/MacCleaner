import Foundation
import UserNotifications
import Combine

@MainActor
final class NotificationManager: ObservableObject {
    static let shared = NotificationManager()

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func scheduleWeeklySmartCareIfNeeded(settings: AppSettings) {
        guard settings.notifyWeeklySmartCare else {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["weekly-smart-care"])
            return
        }
        let content = UNMutableNotificationContent()
        content.title = "Smart Care reminder"
        content.body = "Run Smart Care this week to keep caches, trash, and malware checks fresh."
        var date = DateComponents()
        date.weekday = 2
        date.hour = 10
        let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
        let request = UNNotificationRequest(identifier: "weekly-smart-care", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    func post(id: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
