import Foundation
import UserNotifications

enum NotificationManager {
    static func requestPermission() async -> Bool {
        do {
            let center = UNUserNotificationCenter.current()
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            return granted
        } catch {
            print("通知許可エラー:", error)
            return false
        }
    }

    static func scheduleBusNotification(
        routeName: String,
        stopName: String,
        depart: Date,
        minutesBefore: Int = 5,
        identifier: String
    ) async throws {
        let center = UNUserNotificationCenter.current()

        let triggerDate = depart.addingTimeInterval(TimeInterval(-minutesBefore * 60))
        // すでに通知時刻を過ぎていたら予約しない
        guard triggerDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "まもなくバスの時間です"
        content.body = "\(routeName) \(stopName) 発 \(formatHM(depart)) の \(minutesBefore)分前です"
        content.sound = .default

        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: triggerDate)

        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        try await center.add(request)
    }

    static func cancelNotification(identifier: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    static func pendingRequests() async -> [UNNotificationRequest] {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
                continuation.resume(returning: requests)
            }
        }
    }

    private static func formatHM(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
