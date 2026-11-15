import SwiftData
import SwiftUI
import UIKit
import UserNotifications

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @AppStorage(ReminderSettings.leadDaysStandardKey) private var leadStandard = ReminderSettings.defaultLeadDaysStandard
    @AppStorage(ReminderSettings.leadDaysControlledKey) private var leadControlled = ReminderSettings.defaultLeadDaysControlled
    @AppStorage(ReminderSettings.reminderHourKey) private var hour = ReminderSettings.defaultHour
    @AppStorage(ReminderSettings.reminderMinuteKey) private var minute = ReminderSettings.defaultMinute

    @State private var notificationsAllowed: Bool?

    @Query private var meds: [Medication]
    @AppStorage(EmailReminders.enabledKey) private var emailEnabled = false
    @AppStorage(EmailReminders.urlKey) private var scriptURL = ""
    @AppStorage(EmailReminders.recipientsKey) private var recipients = ""
    @AppStorage(EmailReminders.lastSyncKey) private var lastSync: Double = 0
    @AppStorage(EmailReminders.lastErrorKey) private var lastError = ""
    @State private var testing = false
    @State private var testResult: String?
    @State private var copied = false

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

                emailSection

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

    private var emailSection: some View {
        Section {
            Toggle("Send email reminders", isOn: $emailEnabled)
            if emailEnabled {
                TextField("Email to (comma-separated)", text: $recipients, axis: .vertical)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Script URL (https://script.google.com/…/exec)", text: $scriptURL, axis: .vertical)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.footnote)
                LabeledContent("Secret key") {
                    HStack {
                        Text(EmailReminders.secret).font(.footnote.monospaced()).textSelection(.enabled)
                        Button(copied ? "Copied" : "Copy") {
                            UIPasteboard.general.string = EmailReminders.secret
                            copied = true
                        }
                        .buttonStyle(.borderless)
                    }
                }
                Button {
                    Task { await sendTest() }
                } label: {
                    HStack {
                        Text("Send test email")
                        if testing { Spacer(); ProgressView() }
                    }
                }
                .disabled(testing)
                if let testResult {
                    Text(testResult).font(.footnote)
                } else if !lastError.isEmpty {
                    Text("Last update failed: \(lastError)").font(.footnote).foregroundStyle(.red)
                } else if lastSync > 0 {
                    Text("Last sent to the script \(Date(timeIntervalSinceReferenceDate: lastSync).formatted(date: .abbreviated, time: .shortened)).")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Email reminders")
        } footer: {
            Text("Emails come from your Gmail through a Google Apps Script, on the same days as the phone reminders, even if the phone is off. Setup steps: MedSupply-iOS/email-reminders/README.md.")
        }
    }

    @MainActor
    private func sendTest() async {
        testing = true
        testResult = nil
        do {
            let message = try await EmailReminders.sendTest(meds)
            testResult = "✓ \(message) Check the inbox (and spam folder)."
            lastError = ""
        } catch {
            testResult = "✗ \(error.localizedDescription)"
        }
        testing = false
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
