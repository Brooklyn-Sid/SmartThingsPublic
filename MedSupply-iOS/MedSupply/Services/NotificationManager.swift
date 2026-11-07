import Foundation
import SwiftData
import UserNotifications

/// Schedules local reorder reminders. Everything is derived from stored data, so the simplest
/// correct approach is to clear and rebuild all pending reminders after any change.
@MainActor
enum NotificationManager {
    static let categoryID = "REORDER"
    static let markOrderedActionID = "MARK_ORDERED"
    static let medIDKey = "medID"

    private static var center: UNUserNotificationCenter { .current() }

    static func requestAuthorization() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    static func registerCategories() {
        let markOrdered = UNNotificationAction(identifier: markOrderedActionID,
                                               title: "Mark as reordered", options: [])
        let category = UNNotificationCategory(identifier: categoryID, actions: [markOrdered],
                                              intentIdentifiers: [], options: [])
        center.setNotificationCategories([category])
    }

    /// Rebuilds every pending reminder and the app badge from the current data.
    static func syncAll(context: ModelContext) {
        try? context.save()
        let meds = (try? context.fetch(FetchDescriptor<Medication>())) ?? []
        center.removeAllPendingNotificationRequests()
        for med in meds { schedule(med) }
        let attention = meds.filter { !$0.isArchived && $0.status().needsAttention }.count
        Task { try? await center.setBadgeCount(attention) }
    }

    private static func schedule(_ med: Medication) {
        guard !med.isArchived, med.orderPlacedDate == nil, let runOut = med.runOutDate else { return }

        // Main reminder: lead days before run-out (7 standard / 3 controlled by default).
        if let date = fireDate(daysBefore: med.leadDays, runOut: runOut), date > .now {
            add(id: "\(med.id.uuidString)-reorder", med: med, date: date,
                title: "Time to reorder \(med.displayName)",
                body: body(for: med, at: date, runOut: runOut))
        }
        // Follow-up the day before run-out, only if it still hasn't been marked as reordered.
        if med.leadDays > 1, let date = fireDate(daysBefore: 1, runOut: runOut), date > .now {
            add(id: "\(med.id.uuidString)-final", med: med, date: date,
                title: "\(med.displayName) runs out tomorrow",
                body: "Not marked as reordered yet. " + body(for: med, at: date, runOut: runOut))
        }
    }

    private static func fireDate(daysBefore: Int, runOut: Date) -> Date? {
        let cal = Calendar.current
        guard let day = cal.date(byAdding: .day, value: -daysBefore, to: runOut) else { return nil }
        return cal.date(bySettingHour: ReminderSettings.hour, minute: ReminderSettings.minute,
                        second: 0, of: day)
    }

    private static func body(for med: Medication, at date: Date, runOut: Date) -> String {
        var parts: [String] = []
        let left = med.countText(med.estimatedCount(on: date))
        parts.append("About \(left) left; runs out \(runOut.formatted(date: .abbreviated, time: .omitted)).")
        if !med.pharmacyName.isEmpty {
            parts.append(med.rxNumber.isEmpty ? "Pharmacy: \(med.pharmacyName)."
                                              : "Rx #\(med.rxNumber) at \(med.pharmacyName).")
        }
        if med.refillsRemaining == 0 {
            let doctor = med.prescriber.isEmpty ? "the prescriber" : med.prescriber
            parts.append("No refills left: contact \(doctor) for a new prescription.")
        }
        if let exp = med.rxExpirationDate, exp <= runOut {
            parts.append("Prescription expires \(exp.formatted(date: .abbreviated, time: .omitted)).")
        }
        return parts.joined(separator: " ")
    }

    private static func add(id: String, med: Medication, date: Date, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = categoryID
        content.userInfo = [medIDKey: med.id.uuidString]
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}
