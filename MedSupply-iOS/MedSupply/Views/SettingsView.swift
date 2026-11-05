import SwiftUI
import UserNotifications

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @AppStorage(ReminderSettings.leadDaysStandardKey) private var leadStandard = ReminderSettings.defaultLeadDaysStandard
    @AppStorage(ReminderSettings.leadDaysControlledKey) private var leadControlled = ReminderSettings.defaultLeadDaysControlled
    @AppStorage(ReminderSettings.reminderHourKey) private var hour = ReminderSettings.defaultHour
    @AppStorage(ReminderSettings.reminderMinuteKey) private var minute = ReminderSettings.defaultMinute

    @State private var notificationsAllowed: Bool?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper("Regular: \(leadStandard) days before", value: $leadStandard, in: 1...30)
                    Stepper("Controlled: \(leadControlled) days before", value: $leadControlled, in: 1...30)
                    DatePicker("Reminder time", selection: timeBinding, displayedComponents: .hourAndMinute)
                } header: {
                    Text("Reorder reminders")
                } footer: {
                    Text("A second reminder fires the day before run-out if the medication hasn't been marked as reordered.")
                }

                Section("Notifications") {
                    switch notificationsAllowed {
                    case .some(true):
                        Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    case .some(false):
                        Label("Turned off: reminders won't appear", systemImage: "xmark.octagon.fill")
                            .foregroundStyle(.red)
                        Button("Open iPhone Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                    case .none:
                        ProgressView()
                    }
                }

                Section("Data sources") {
                    Text("Brand/generic names: NIH National Library of Medicine RxNorm. Images: NLM DailyMed (FDA labels). This app does not give medical advice.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
            .task {
                let settings = await UNUserNotificationCenter.current().notificationSettings()
                notificationsAllowed = [.authorized, .provisional].contains(settings.authorizationStatus)
            }
        }
    }

    private var timeBinding: Binding<Date> {
        Binding(
            get: { Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now },
            set: { date in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
                hour = comps.hour ?? ReminderSettings.defaultHour
                minute = comps.minute ?? ReminderSettings.defaultMinute
            }
        )
    }
}
