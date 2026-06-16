import Foundation
import UserNotifications

/// Schedules local bill-due reminders. Everything here is local: no push
/// server, no remote payload, just UNUserNotificationCenter acting on the
/// due dates already stored in SwiftData.
@MainActor
final class NotificationManager {
    static let shared = NotificationManager()
    private init() {}

    func requestAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        }
    }

    /// Schedules a day-before reminder and a due-date alert for one bill, replacing any existing ones.
    func schedule(for bill: Bill) {
        cancel(for: bill)
        let center = UNUserNotificationCenter.current()

        let dueContent = UNMutableNotificationContent()
        dueContent.title = "\(bill.name) is due today"
        dueContent.body = "\(bill.amount.currencyString) due today."
        dueContent.sound = .default
        if let dueTrigger = trigger(for: bill.nextDueDate, hour: 9) {
            center.add(UNNotificationRequest(identifier: identifier(for: bill, suffix: "due"), content: dueContent, trigger: dueTrigger))
        }

        let reminderContent = UNMutableNotificationContent()
        reminderContent.title = "\(bill.name) due tomorrow"
        reminderContent.body = bill.autopay
            ? "\(bill.amount.currencyString) due tomorrow \u{2014} autopay will cover it."
            : "\(bill.amount.currencyString) due tomorrow \u{2014} make sure funds are available."
        reminderContent.sound = .default
        if let dayBefore = Calendar.current.date(byAdding: .day, value: -1, to: bill.nextDueDate),
           let reminderTrigger = trigger(for: dayBefore, hour: 9) {
            center.add(UNNotificationRequest(identifier: identifier(for: bill, suffix: "reminder"), content: reminderContent, trigger: reminderTrigger))
        }
    }

    func cancel(for bill: Bill) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [
            identifier(for: bill, suffix: "due"),
            identifier(for: bill, suffix: "reminder"),
        ])
    }

    /// Re-schedules every still-upcoming bill. Safe to call on every app launch.
    func rescheduleAll(bills: [Bill]) {
        for bill in bills where bill.nextDueDate > .now {
            schedule(for: bill)
        }
    }

    private func identifier(for bill: Bill, suffix: String) -> String {
        "bill-\(bill.id.uuidString)-\(suffix)"
    }

    private func trigger(for date: Date, hour: Int) -> UNCalendarNotificationTrigger? {
        guard date > .now else { return nil }
        var components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        components.hour = hour
        return UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
    }
}
