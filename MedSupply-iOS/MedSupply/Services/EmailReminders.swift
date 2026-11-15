import Foundation

/// Sends the reorder schedule to the user's Google Apps Script (see email-reminders/Code.gs),
/// which emails reminders from Gmail on the right day, even when the phone or app is off.
enum EmailReminders {
    static let enabledKey = "emailEnabled"
    static let urlKey = "emailScriptURL"
    static let secretKey = "emailSecret"
    static let recipientsKey = "emailRecipients"
    static let lastSyncKey = "emailLastSync"
    static let lastErrorKey = "emailLastError"

    private static var defaults: UserDefaults { .standard }

    static var isEnabled: Bool { defaults.bool(forKey: enabledKey) }
    static var scriptURL: URL? {
        let text = (defaults.string(forKey: urlKey) ?? "").trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: text), url.scheme == "https" else { return nil }
        return url
    }
    static var recipients: [String] { parseRecipients(defaults.string(forKey: recipientsKey) ?? "") }

    /// The shared secret the script checks. Created once on this phone.
    static var secret: String {
        if let existing = defaults.string(forKey: secretKey), !existing.isEmpty { return existing }
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789")
        let new = String((0..<24).map { _ in alphabet.randomElement()! })
        defaults.set(new, forKey: secretKey)
        return new
    }

    static func parseRecipients(_ text: String) -> [String] {
        text.split(whereSeparator: { $0 == "," || $0 == ";" || $0 == " " || $0 == "\n" })
            .map(String.init)
            .filter { $0.contains("@") }
    }

    struct ScriptError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    // MARK: - Payload

    private struct Payload: Encodable {
        let secret: String
        let recipients: [String]
        let timeZone: String
        let test: Bool
        let meds: [Med]
    }

    private struct Med: Encodable {
        let id: String
        let name: String
        let generic: String
        let dose: String
        let schedule: String
        let onHand: String
        let onHandFinal: String
        let reorderDate: String
        let runOutDate: String
        let ordered: Bool
        let controlled: Bool
        let pharmacy: String
        let pharmacyPhone: String
        let rxNumber: String
        let prescriber: String
        let prescriberPhone: String
        let refillsRemaining: Int?
        let rxExpiration: String?
    }

    private struct Response: Decodable {
        let ok: Bool
        let error: String?
        let message: String?
    }

    private static func ymd(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Builds the payload on the main actor (the models live there).
    @MainActor
    private static func payload(for meds: [Medication], test: Bool) -> Payload {
        let items: [Med] = meds.compactMap { med in
            guard !med.isArchived, let runOut = med.runOutDate, let reorder = med.reorderDate else { return nil }
            return Med(
                id: med.id.uuidString,
                name: med.displayName,
                generic: med.secondaryName ?? "",
                dose: med.dose,
                schedule: med.scheduleText,
                onHand: med.countText(med.estimatedCount(on: reorder)),
                onHandFinal: med.countText(med.estimatedCount(
                    on: Calendar.current.date(byAdding: .day, value: -1, to: runOut) ?? runOut)),
                reorderDate: ymd(reorder),
                runOutDate: ymd(runOut),
                ordered: med.orderPlacedDate != nil,
                controlled: med.isControlled,
                pharmacy: med.pharmacyName,
                pharmacyPhone: med.pharmacyPhone,
                rxNumber: med.rxNumber,
                prescriber: med.prescriber,
                prescriberPhone: med.prescriberPhone,
                refillsRemaining: med.refillsRemaining,
                rxExpiration: med.rxExpirationDate.map(ymd)
            )
        }
        return Payload(secret: secret, recipients: recipients, timeZone: TimeZone.current.identifier,
                       test: test, meds: items)
    }

    // MARK: - Sending

    /// Fire-and-forget update after any data change. Records the outcome for the Settings screen.
    @MainActor
    static func push(_ meds: [Medication]) {
        guard isEnabled, let url = scriptURL, !recipients.isEmpty else { return }
        let body = payload(for: meds, test: false)
        Task {
            do {
                _ = try await post(body, to: url)
                defaults.set(Date().timeIntervalSinceReferenceDate, forKey: lastSyncKey)
                defaults.removeObject(forKey: lastErrorKey)
            } catch {
                defaults.set(error.localizedDescription, forKey: lastErrorKey)
            }
        }
    }

    /// Sends the data and asks the script to email a test message. Returns the script's message.
    @MainActor
    static func sendTest(_ meds: [Medication]) async throws -> String {
        guard let url = scriptURL else {
            throw ScriptError(message: "Enter the script's Web app URL (it starts with https://script.google.com/).")
        }
        guard !recipients.isEmpty else { throw ScriptError(message: "Enter at least one email address.") }
        let message = try await post(payload(for: meds, test: true), to: url)
        defaults.set(Date().timeIntervalSinceReferenceDate, forKey: lastSyncKey)
        defaults.removeObject(forKey: lastErrorKey)
        return message
    }

    private static func post(_ payload: Payload, to url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        // Apps Script reads the raw body; text/plain avoids a CORS-style preflight on Google's side.
        request.setValue("text/plain;charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)
        request.timeoutInterval = 30

        // Google answers with a redirect to the result, which URLSession follows automatically.
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else {
            throw ScriptError(message: "The script didn't answer as expected. Check that it is deployed as a Web app with access set to \"Anyone\", and that the URL ends in /exec.")
        }
        guard response.ok else { throw ScriptError(message: response.error ?? "The script reported an error.") }
        return response.message ?? "Sent."
    }
}
