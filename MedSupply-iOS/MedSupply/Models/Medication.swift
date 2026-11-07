import Foundation
import SwiftData

/// How often a medication is taken. Used only to project when the supply runs out.
enum Frequency: String, CaseIterable, Identifiable, Codable {
    case onceDaily
    case twiceDaily
    case threeTimesDaily
    case fourTimesDaily
    case everyOtherDay
    case weekly
    case timesPerWeek
    case everyNDays
    case custom
    case asNeeded

    var id: String { rawValue }

    var label: String {
        switch self {
        case .onceDaily: return "Once a day"
        case .twiceDaily: return "Twice a day"
        case .threeTimesDaily: return "3 times a day"
        case .fourTimesDaily: return "4 times a day"
        case .everyOtherDay: return "Every other day"
        case .weekly: return "Once a week"
        case .timesPerWeek: return "Times per week"
        case .everyNDays: return "Every few days"
        case .custom: return "Custom (doses per day)"
        case .asNeeded: return "As needed (estimate)"
        }
    }

    /// Doses per day for fixed schedules; nil when the user supplies the number.
    var fixedDosesPerDay: Double? {
        switch self {
        case .onceDaily: return 1
        case .twiceDaily: return 2
        case .threeTimesDaily: return 3
        case .fourTimesDaily: return 4
        case .everyOtherDay: return 0.5
        case .weekly: return 1.0 / 7.0
        case .timesPerWeek, .everyNDays, .custom, .asNeeded: return nil
        }
    }

    /// Schedules that take a whole number: "N times per week" or "every N days".
    var usesScheduleNumber: Bool { self == .timesPerWeek || self == .everyNDays }

    /// Schedules described by a (possibly fractional) number of doses per day.
    var usesDosesPerDay: Bool { self == .custom || self == .asNeeded }

    /// Converts any schedule to doses per day. Used only for the supply math, not for display.
    func dosesPerDay(custom: Double, number: Double) -> Double {
        switch self {
        case .timesPerWeek: return max(0, number) / 7
        case .everyNDays: return number > 0 ? 1 / number : 0
        case .custom, .asNeeded: return custom
        default: return fixedDosesPerDay ?? 0
        }
    }

    /// How the schedule is written on a prescription: "twice a week", "every 28 days".
    func describe(custom: Double, number: Double) -> String {
        switch self {
        case .onceDaily: return "once a day"
        case .twiceDaily: return "twice a day"
        case .threeTimesDaily: return "3 times a day"
        case .fourTimesDaily: return "4 times a day"
        case .everyOtherDay: return "every other day"
        case .weekly: return "once a week"
        case .timesPerWeek:
            switch number {
            case 1: return "once a week"
            case 2: return "twice a week"
            default: return "\(Fmt.count(number)) times a week"
            }
        case .everyNDays:
            switch number {
            case 1: return "every day"
            case 2: return "every other day"
            case 7: return "once a week"
            default: return "every \(Fmt.count(number)) days"
            }
        case .custom:
            return custom == 1 ? "once a day" : "\(Fmt.count(custom)) times a day"
        case .asNeeded:
            return custom > 0 ? "as needed (about \(Fmt.count(custom)) a day)" : "as needed"
        }
    }
}

/// Dose forms offered in the editor. Any other text is allowed too (e.g. from an import).
enum DoseUnit {
    static let common = ["tablet", "capsule", "patch", "injection", "pen", "vial", "spray",
                         "drop", "puff", "dose", "ml"]
}

enum HistoryKind: String, Codable {
    case initial
    case refill
    case recount

    var label: String {
        switch self {
        case .initial: return "Starting count"
        case .refill: return "Refill"
        case .recount: return "Recount"
        }
    }
}

/// A log entry recorded whenever the count is set: first entry, refill, or manual recount.
@Model
final class RefillEvent {
    var date: Date = Date()
    var kindRaw: String = HistoryKind.refill.rawValue
    /// Units added (refill) — zero for recounts / initial entries.
    var quantity: Double = 0
    var countBefore: Double = 0
    var countAfter: Double = 0
    var medication: Medication?

    var kind: HistoryKind { HistoryKind(rawValue: kindRaw) ?? .refill }

    init(date: Date, kind: HistoryKind, quantity: Double, countBefore: Double, countAfter: Double) {
        self.date = date
        self.kindRaw = kind.rawValue
        self.quantity = quantity
        self.countBefore = countBefore
        self.countAfter = countAfter
    }
}

/// All properties have defaults and the relationship is optional so the store
/// stays compatible with CloudKit sync if it is turned on later.
@Model
final class Medication {
    var id: UUID = UUID()
    var createdAt: Date = Date()

    // Identity
    var brandName: String = ""
    var genericName: String = ""
    /// RxNorm concept id from the name lookup, if one was found.
    var rxcui: String?
    var dose: String = ""

    // Usage
    var frequencyRaw: String = Frequency.onceDaily.rawValue
    /// Used when frequency is .custom or .asNeeded.
    var customDosesPerDay: Double = 1
    /// Units taken per dose, e.g. 2 tablets, or 0.25 for a quarter tablet.
    var unitsPerDose: Double = 1
    /// Dose form, singular: "tablet", "patch", "injection"…
    var unitName: String = "tablet"
    /// N for "N times per week" or "every N days".
    var scheduleNumber: Double = 1

    // Supply
    /// Count on hand as of `lastRefreshedDate`. The current count is projected from this.
    var countAtLastRefresh: Double = 0
    var lastRefreshedDate: Date = Date()
    /// Set when she marks the medication as reordered; cleared on the next refill.
    var orderPlacedDate: Date?

    // Prescription
    var pharmacyName: String = ""
    var pharmacyPhone: String = ""
    var rxNumber: String = ""
    var prescriber: String = ""
    var prescriberPhone: String = ""
    var isControlled: Bool = false
    var refillsRemaining: Int?
    var rxExpirationDate: Date?
    var notes: String = ""

    @Attribute(.externalStorage) var imageData: Data?
    var isArchived: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \RefillEvent.medication)
    var history: [RefillEvent]? = []

    init() {}

    // MARK: - Derived values

    var frequency: Frequency {
        get { Frequency(rawValue: frequencyRaw) ?? .onceDaily }
        set { frequencyRaw = newValue.rawValue }
    }

    var dosesPerDay: Double { frequency.dosesPerDay(custom: customDosesPerDay, number: scheduleNumber) }

    /// Units consumed per day.
    var dailyUsage: Double { dosesPerDay * unitsPerDose }

    /// "1 patch twice a week", "¼ tablet once a day".
    var scheduleText: String {
        "\(Fmt.amount(unitsPerDose)) \(Fmt.unit(unitName, count: unitsPerDose)) "
            + frequency.describe(custom: customDosesPerDay, number: scheduleNumber)
    }

    /// "8 patches", "20.25 tablets".
    func countText(_ count: Double) -> String {
        "\(Fmt.count(count)) \(Fmt.unit(unitName, count: count))"
    }

    var displayName: String {
        let brand = brandName.trimmingCharacters(in: .whitespaces)
        return brand.isEmpty ? genericName : brand
    }

    /// Generic name shown under the brand name (nil when there is nothing extra to show).
    var secondaryName: String? {
        let brand = brandName.trimmingCharacters(in: .whitespaces)
        let generic = genericName.trimmingCharacters(in: .whitespaces)
        guard !brand.isEmpty, !generic.isEmpty,
              brand.caseInsensitiveCompare(generic) != .orderedSame else { return nil }
        return generic
    }

    var leadDays: Int { ReminderSettings.leadDays(controlled: isControlled) }

    func estimatedCount(on date: Date = .now) -> Double {
        SupplyMath.estimatedCount(start: countAtLastRefresh, refreshed: lastRefreshedDate,
                                  dailyUsage: dailyUsage, on: date)
    }

    /// First day she will not have a full day's supply.
    var runOutDate: Date? {
        SupplyMath.runOutDate(start: countAtLastRefresh, refreshed: lastRefreshedDate, dailyUsage: dailyUsage)
    }

    /// The day the reorder reminder fires.
    var reorderDate: Date? {
        guard let runOut = runOutDate else { return nil }
        return Calendar.current.date(byAdding: .day, value: -leadDays, to: runOut)
    }

    func daysRemaining(from date: Date = .now) -> Int? {
        guard let runOut = runOutDate else { return nil }
        return SupplyMath.days(from: date, to: runOut)
    }

    func status(on date: Date = .now) -> SupplyStatus {
        guard let left = daysRemaining(from: date) else { return .noProjection }
        if orderPlacedDate != nil { return .ordered(daysLeft: left) }
        if left <= 0 { return .out }
        if left <= leadDays { return .reorderNow(daysLeft: left) }
        return .ok(daysLeft: left)
    }

    var sortedHistory: [RefillEvent] {
        (history ?? []).sorted { $0.date > $1.date }
    }

    /// Most recent refill quantity, used to pre-fill the refill sheet.
    var lastRefillQuantity: Double? {
        sortedHistory.first(where: { $0.kind == .refill })?.quantity
    }

    // MARK: - Mutations

    /// Adds `quantity` to the projected count on `date` and makes `date` the new refresh date.
    func recordRefill(quantity: Double, on date: Date) {
        let before = estimatedCount(on: date)
        countAtLastRefresh = before + quantity
        lastRefreshedDate = date
        orderPlacedDate = nil
        if let remaining = refillsRemaining, remaining > 0 {
            refillsRemaining = remaining - 1
        }
        appendHistory(RefillEvent(date: date, kind: .refill, quantity: quantity,
                                  countBefore: before, countAfter: countAtLastRefresh))
    }

    /// Replaces the projected count with an actual count (corrects drift from missed/extra doses).
    func recordRecount(count: Double, on date: Date) {
        let before = estimatedCount(on: date)
        countAtLastRefresh = count
        lastRefreshedDate = date
        appendHistory(RefillEvent(date: date, kind: .recount, quantity: 0,
                                  countBefore: before, countAfter: count))
    }

    func recordInitialCount(_ count: Double, on date: Date) {
        countAtLastRefresh = count
        lastRefreshedDate = date
        appendHistory(RefillEvent(date: date, kind: .initial, quantity: 0,
                                  countBefore: 0, countAfter: count))
    }

    private func appendHistory(_ event: RefillEvent) {
        if history == nil { history = [] }
        history?.append(event)
    }

    /// Plain-text summary for calling in or texting a refill request.
    var refillRequestText: String {
        var lines = ["Refill request"]
        var name = displayName
        if let generic = secondaryName { name += " (\(generic))" }
        if !dose.isEmpty { name += " \(dose)" }
        lines.append("Medication: \(name)")
        if !rxNumber.isEmpty { lines.append("Rx #: \(rxNumber)") }
        if !pharmacyName.isEmpty {
            lines.append("Pharmacy: \(pharmacyName)\(pharmacyPhone.isEmpty ? "" : " \(pharmacyPhone)")")
        }
        if !prescriber.isEmpty { lines.append("Prescriber: \(prescriber)") }
        return lines.joined(separator: "\n")
    }
}

enum SupplyStatus: Equatable {
    case noProjection
    case ok(daysLeft: Int)
    case reorderNow(daysLeft: Int)
    case ordered(daysLeft: Int)
    case out

    var needsAttention: Bool {
        switch self {
        case .reorderNow, .out: return true
        default: return false
        }
    }

    var label: String {
        switch self {
        case .noProjection: return "No estimate"
        case .ok(let d), .reorderNow(let d): return d == 1 ? "1 day" : "\(d) days"
        case .ordered: return "Ordered"
        case .out: return "Out"
        }
    }
}

/// Pure date/count arithmetic, kept separate so it can be unit tested.
enum SupplyMath {
    static func days(from start: Date, to end: Date, calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: start),
                                to: calendar.startOfDay(for: end)).day ?? 0
    }

    /// Count on hand at the start of `date`'s day.
    static func estimatedCount(start: Double, refreshed: Date, dailyUsage: Double, on date: Date,
                               calendar: Calendar = .current) -> Double {
        guard dailyUsage > 0 else { return start }
        let elapsed = max(0, days(from: refreshed, to: date, calendar: calendar))
        return max(0, start - Double(elapsed) * dailyUsage)
    }

    /// The first day without a full day's supply, e.g. 30 pills at 1/day refreshed on Nov 5 → Dec 5.
    static func runOutDate(start: Double, refreshed: Date, dailyUsage: Double,
                           calendar: Calendar = .current) -> Date? {
        guard dailyUsage > 0 else { return nil }
        let daysOfSupply = Int((start / dailyUsage + 1e-9).rounded(.down))
        return calendar.date(byAdding: .day, value: daysOfSupply, to: calendar.startOfDay(for: refreshed))
    }
}

/// One-time fixes to data saved by earlier versions of the app.
enum DataMigrations {
    /// Earlier imports stored "Twice weekly" / "Every 28 days" as fractional doses per day.
    /// Converts those to the times-per-week / every-N-days schedules. Safe to run on every launch.
    static func run(context: ModelContext) {
        let meds = (try? context.fetch(FetchDescriptor<Medication>())) ?? []
        var changed = false
        for med in meds where med.frequency == .custom && med.customDosesPerDay > 0 && med.customDosesPerDay < 1 {
            let perDay = med.customDosesPerDay
            let perWeek = perDay * 7
            let everyDays = 1 / perDay
            if perWeek >= 1, abs(perWeek - perWeek.rounded()) < 0.01 {
                med.frequency = .timesPerWeek
                med.scheduleNumber = perWeek.rounded()
                changed = true
            } else if abs(everyDays - everyDays.rounded()) < 0.01 {
                med.frequency = .everyNDays
                med.scheduleNumber = everyDays.rounded()
                changed = true
            }
        }
        if changed { try? context.save() }
    }
}
