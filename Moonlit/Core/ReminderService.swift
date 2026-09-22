import Foundation
import UserNotifications

struct ReminderSchedule: Equatable {
    var intervalHours: Int
    var startHour: Int
    var endHour: Int
}
actor ReminderService {
    static let shared = ReminderService()
    private let center = UNUserNotificationCenter.current()

    func requestPermission() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .badge, .sound])
    }

    func schedule(_ schedule: ReminderSchedule) async throws {
        guard schedule.intervalHours > 0,
              (0...23).contains(schedule.startHour),
              (0...23).contains(schedule.endHour),
              schedule.startHour <= schedule.endHour else {
            throw ReminderError.invalidSchedule
        }

        let requests = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(
            withIdentifiers: requests.map(\.identifier).filter { $0.hasPrefix("moonlit-reminder-") }
        )

        for hour in stride(from: schedule.startHour, through: schedule.endHour, by: schedule.intervalHours) {
            let content = UNMutableNotificationContent()
            content.title = "A little moment for your moon ♡"
            content.body = "Show your person what your world looks like right now."
            content.sound = .default
            content.userInfo = ["destination": "camera"]

            let trigger = UNCalendarNotificationTrigger(
                dateMatching: DateComponents(hour: hour, minute: 0),
                repeats: true
            )
            try await center.add(UNNotificationRequest(
                identifier: "moonlit-reminder-\(hour)",
                content: content,
                trigger: trigger
            ))
        }
    }
}

enum ReminderError: LocalizedError {
    case invalidSchedule
    var errorDescription: String? { "Please choose valid active hours and an interval above zero." }
}
