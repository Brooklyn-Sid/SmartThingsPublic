import Foundation

/// User-adjustable reminder settings, stored in UserDefaults (read by views via @AppStorage).
enum ReminderSettings {
    static let leadDaysStandardKey = "leadDaysStandard"
    static let leadDaysControlledKey = "leadDaysControlled"
    static let reminderHourKey = "reminderHour"
    static let reminderMinuteKey = "reminderMinute"

    static let defaultLeadDaysStandard = 7
    static let defaultLeadDaysControlled = 3
    static let defaultHour = 9
    static let defaultMinute = 0

    private static var defaults: UserDefaults { .standard }

    private static func int(_ key: String, _ fallback: Int) -> Int {
        defaults.object(forKey: key) as? Int ?? fallback
    }

    static func leadDays(controlled: Bool) -> Int {
        controlled
            ? int(leadDaysControlledKey, defaultLeadDaysControlled)
            : int(leadDaysStandardKey, defaultLeadDaysStandard)
    }

    static var hour: Int { int(reminderHourKey, defaultHour) }
    static var minute: Int { int(reminderMinuteKey, defaultMinute) }
}
