import Foundation

/// Reads medications from a CSV file (e.g. a Google Sheet downloaded as CSV).
/// Columns are matched by header name, so column order doesn't matter and extra columns are ignored.
enum MedicationImporter {
    struct Row: Identifiable {
        let id = UUID()
        let line: Int
        var draft: MedicationDraft
        var warnings: [String]
    }

    struct ParseError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Accepted header names (lowercased, punctuation stripped) for each field.
    private enum Field: CaseIterable {
        case brand, generic, dose, unitsPerDose, schedule, count, countDate
        case pharmacy, pharmacyPhone, rxNumber, prescriber, prescriberPhone
        case refills, controlled, notes

        var aliases: [String] {
            switch self {
            case .brand: return ["medication name", "brand name", "brand", "medication", "name", "drug"]
            case .generic: return ["generic name", "generic"]
            case .dose: return ["strength", "dose", "dosage"]
            case .unitsPerDose: return ["amount per dose", "pills per dose", "units per dose", "quantity per dose"]
            case .schedule: return ["schedule", "frequency", "how often"]
            case .count: return ["quantity on hand", "count", "current count", "on hand", "quantity", "qty on hand"]
            case .countDate: return ["count verified date", "last date refreshed", "last refreshed",
                                     "count date", "date counted", "last count date"]
            case .pharmacy: return ["pharmacy"]
            case .pharmacyPhone: return ["pharmacy phone"]
            case .rxNumber: return ["prescription number", "rx number", "rx", "rx no", "prescription"]
            case .prescriber: return ["prescribing doctor", "prescriber", "doctor", "physician"]
            case .prescriberPhone: return ["doctor phone", "prescriber phone"]
            case .refills: return ["refills remaining", "refills", "refills left"]
            case .controlled: return ["controlled", "controlled substance"]
            case .notes: return ["notes", "note", "comments"]
            }
        }
    }

    // MARK: - Parsing

    static func parse(_ text: String, today: Date = .now) throws -> [Row] {
        let table = csvRows(text).filter { !$0.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty } }
        guard let header = table.first else { throw ParseError(message: "The file is empty.") }

        var columns: [Field: Int] = [:]
        for (index, title) in header.enumerated() {
            let key = normalizeHeader(title)
            for field in Field.allCases where columns[field] == nil && field.aliases.contains(key) {
                columns[field] = index
            }
        }
        guard columns[.brand] != nil || columns[.generic] != nil else {
            throw ParseError(message: "Couldn't find a medication name column. The first row should be column headers such as \"Medication name\" and \"Generic name\".")
        }

        return table.dropFirst().enumerated().compactMap { offset, cells in
            func value(_ field: Field) -> String {
                guard let i = columns[field], i < cells.count else { return "" }
                return cells[i].trimmingCharacters(in: .whitespacesAndNewlines)
            }

            var draft = MedicationDraft()
            var warnings: [String] = []
            draft.brandName = value(.brand)
            draft.genericName = value(.generic)
            guard draft.hasName else { return nil }

            draft.dose = value(.dose)
            draft.pharmacyName = value(.pharmacy)
            draft.pharmacyPhone = value(.pharmacyPhone)
            draft.rxNumber = value(.rxNumber)
            draft.prescriber = value(.prescriber)
            draft.prescriberPhone = value(.prescriberPhone)
            draft.notes = value(.notes)
            draft.refillsRemaining = Int(value(.refills))
            draft.isControlled = parseBool(value(.controlled))

            let amountText = value(.unitsPerDose)
            if let unit = parseUnit(amountText) { draft.unitName = unit }
            if amountText.isEmpty {
                draft.unitsPerDose = 1
            } else if let amount = parseAmount(amountText), amount > 0 {
                draft.unitsPerDose = amount
            } else {
                draft.unitsPerDose = 1
                warnings.append("Couldn't read amount per dose \"\(amountText)\"; using 1.")
            }

            let scheduleText = value(.schedule)
            if let parsed = parseSchedule(scheduleText) {
                draft.frequency = parsed.0
                if parsed.0.usesScheduleNumber {
                    draft.scheduleNumber = parsed.1
                } else {
                    draft.customDosesPerDay = parsed.1
                }
            } else {
                draft.frequency = .onceDaily
                warnings.append(scheduleText.isEmpty ? "No schedule; using once a day."
                                                     : "Couldn't read schedule \"\(scheduleText)\"; using once a day.")
            }

            let countText = value(.count).replacingOccurrences(of: ",", with: "")
            if let count = Double(countText), count >= 0 {
                draft.count = count
            } else {
                draft.count = 0
                warnings.append("No count on hand; using 0.")
            }

            let dateText = value(.countDate)
            if let date = parseDate(dateText), date <= today {
                draft.countDate = date
            } else {
                draft.countDate = today
                if !dateText.isEmpty { warnings.append("Couldn't read count date \"\(dateText)\"; using today.") }
            }

            if draft.frequency == .asNeeded {
                warnings.append("As-needed: set the average doses per day to get a run-out estimate.")
            }
            return Row(line: offset + 2, draft: draft, warnings: warnings)
        }
    }

    // MARK: - Field parsers (internal for tests)

    /// "1 tablet" → 1, "¼ tablet" → 0.25, "1 1/2 tablets" → 1.5, "2" → 2.
    static func parseAmount(_ text: String) -> Double? {
        let fractions: [Character: String] = ["¼": " 1/4", "½": " 1/2", "¾": " 3/4", "⅓": " 1/3",
                                              "⅔": " 2/3", "⅛": " 1/8"]
        let expanded = text.map { fractions[$0] ?? String($0) }.joined()
        var total: Double = 0
        var found = false
        for token in expanded.split(whereSeparator: { $0 == " " || $0 == "\u{00A0}" }) {
            if let number = Double(token) {
                total += number
                found = true
            } else if token.contains("/") {
                let parts = token.split(separator: "/")
                guard parts.count == 2, let n = Double(parts[0]), let d = Double(parts[1]), d != 0 else { break }
                total += n / d
                found = true
            } else {
                break
            }
        }
        return found ? total : nil
    }

    /// The dose form from text like "1 patch", "¼ tablet", "2 capsules" → "patch", "tablet", "capsule".
    static func parseUnit(_ text: String) -> String? {
        let words = text.lowercased()
            .split(whereSeparator: { $0 == " " || $0 == "\u{00A0}" })
            .map(String.init)
            .filter { word in !word.contains(where: { $0.isNumber || "¼½¾⅓⅔⅛/.".contains($0) }) }
        guard let word = words.first else { return nil }
        let candidates = [word, word.hasSuffix("es") ? String(word.dropLast(2)) : word,
                          word.hasSuffix("s") ? String(word.dropLast()) : word]
        if let known = candidates.first(where: { DoseUnit.common.contains($0) }) { return known }
        if ["pill", "pills", "tab", "tabs"].contains(word) { return "tablet" }
        if ["cap", "caps"].contains(word) { return "capsule" }
        if ["shot", "shots"].contains(word) { return "injection" }
        return candidates[2]
    }

    /// Returns the frequency and a number whose meaning depends on it: N for times-per-week and
    /// every-N-days schedules, doses per day for custom / as-needed ones.
    static func parseSchedule(_ text: String) -> (Frequency, Double)? {
        let s = text.lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ").joined(separator: " ")
        guard !s.isEmpty else { return nil }

        let fixed: [(Frequency, [String])] = [
            (.onceDaily, ["daily", "once daily", "once a day", "1x daily", "1x a day", "every day", "qd", "nightly", "every morning", "every night", "at bedtime"]),
            (.twiceDaily, ["twice daily", "twice a day", "2x daily", "2x a day", "bid", "2 times daily", "2 times a day", "every 12 hours"]),
            (.threeTimesDaily, ["three times daily", "three times a day", "3x daily", "3x a day", "tid", "3 times daily", "3 times a day", "every 8 hours"]),
            (.fourTimesDaily, ["four times daily", "four times a day", "4x daily", "4x a day", "qid", "4 times daily", "4 times a day", "every 6 hours"]),
            (.everyOtherDay, ["every other day", "alternate days", "qod"]),
            (.weekly, ["weekly", "once weekly", "once a week", "1x weekly", "1x a week", "every week"]),
            (.asNeeded, ["as needed", "prn"]),
        ]
        for (frequency, phrases) in fixed where phrases.contains(s) {
            return (frequency, frequency == .asNeeded ? 0 : (frequency.fixedDosesPerDay ?? 1))
        }

        let words = s.split(separator: " ").map(String.init)
        let wordNumbers = ["once": 1.0, "one": 1, "twice": 2, "two": 2, "three": 3, "four": 4, "five": 5,
                           "six": 6, "seven": 7, "other": 2]
        func number(_ word: String) -> Double? {
            Double(word.replacingOccurrences(of: "x", with: "")) ?? wordNumbers[word]
        }
        func unitDays(_ word: String) -> Double? {
            if word.hasPrefix("day") { return 1 }
            if word.hasPrefix("week") { return 7 }
            if word.hasPrefix("month") { return 30 }
            return nil
        }

        // "every 28 days", "every 2 weeks", "every other week", "every month"
        if words.first == "every", (2...3).contains(words.count) {
            let n = words.count == 3 ? number(words[1]) : 1
            if let n, n > 0, let days = unitDays(words[words.count - 1]) {
                return (.everyNDays, n * days)
            }
        }
        // "twice weekly", "3 times a week", "2x per week", "once monthly"
        if let n = number(words[0]), n > 0, let last = words.last {
            let unit: Double? = last == "weekly" ? 7 : last == "monthly" ? 30 : last == "daily" ? 1 : unitDays(last)
            let middleOK = words.dropFirst().dropLast().allSatisfy { ["times", "time", "a", "per", "x"].contains($0) }
            if let unit, middleOK {
                if unit == 7 { return (.timesPerWeek, n) }
                if n == 1 && unit > 1 { return (.everyNDays, unit) }
                return (.custom, n / unit)
            }
        }
        return nil
    }

    /// "11/1/2026", "11/03/26", "2026-11-01".
    static func parseDate(_ text: String) -> Date? {
        let t = text.trimmingCharacters(in: .whitespaces)
        var comps = DateComponents()
        let slash = t.split(separator: "/").map { Int($0) }
        let dash = t.split(separator: "-").map { Int($0) }
        if slash.count == 3, let m = slash[0], let d = slash[1], let y = slash[2] {
            comps.year = y < 100 ? 2000 + y : y
            comps.month = m
            comps.day = d
        } else if dash.count == 3, let y = dash[0], let m = dash[1], let d = dash[2], y > 1000 {
            comps.year = y
            comps.month = m
            comps.day = d
        } else {
            return nil
        }
        guard (1...12).contains(comps.month ?? 0), (1...31).contains(comps.day ?? 0) else { return nil }
        comps.hour = 12
        return Calendar.current.date(from: comps)
    }

    static func parseBool(_ text: String) -> Bool {
        let s = text.lowercased().trimmingCharacters(in: .whitespaces)
        return ["yes", "y", "true", "x", "1", "controlled", "ii", "iii", "iv", "v",
                "c-ii", "cii", "c2", "schedule ii"].contains(s)
    }

    private static func normalizeHeader(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "#", with: " no")
            .components(separatedBy: CharacterSet.alphanumerics.union(.whitespaces).inverted).joined()
            .split(separator: " ").joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    /// Minimal RFC 4180 CSV reader: quoted fields, escaped quotes, commas/newlines inside quotes.
    static func csvRows(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var chars = Array(text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text)
        chars.append("\n")
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" {
                        field.append("\"")
                        i += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(c)
                }
            } else if c == "\"" {
                inQuotes = true
            } else if c == "," {
                row.append(field)
                field = ""
            } else if c == "\n" || c == "\r" || c == "\r\n" {
                row.append(field)
                rows.append(row)
                row = []
                field = ""
                if c == "\r", i + 1 < chars.count, chars[i + 1] == "\n" { i += 1 }
            } else {
                field.append(c)
            }
            i += 1
        }
        // The appended trailing newline can produce one empty final row.
        if let last = rows.last, last.count == 1, last[0].isEmpty { rows.removeLast() }
        return rows
    }
}
