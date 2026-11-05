import SwiftData
import SwiftUI
import UIKit
import UserNotifications

enum SharedModel {
    /// One container shared by the UI and the notification action handler.
    static let container: ModelContainer = {
        do {
            return try ModelContainer(for: Medication.self, RefillEvent.self)
        } catch {
            fatalError("Could not open the medication database: \(error)")
        }
    }()
}

@main
struct MedSupplyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            MedicationListView()
        }
        .modelContainer(SharedModel.container)
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        NotificationManager.registerCategories()
        return true
    }

    /// Show reminders even while the app is open.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    /// Handles the "Mark as reordered" button on a reminder.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        guard response.actionIdentifier == NotificationManager.markOrderedActionID,
              let idString = response.notification.request.content.userInfo[NotificationManager.medIDKey] as? String,
              let medID = UUID(uuidString: idString) else { return }

        await MainActor.run {
            let context = SharedModel.container.mainContext
            let descriptor = FetchDescriptor<Medication>(predicate: #Predicate<Medication> { $0.id == medID })
            if let med = try? context.fetch(descriptor).first {
                med.orderPlacedDate = .now
                NotificationManager.syncAll(context: context)
            }
        }
    }
}
