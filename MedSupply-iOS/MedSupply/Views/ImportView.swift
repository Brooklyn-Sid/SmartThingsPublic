import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Pick a CSV file, preview what will be imported, then add the medications.
struct ImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var existing: [Medication]

    @State private var showingPicker = true
    @State private var rows: [MedicationImporter.Row] = []
    @State private var selected: Set<UUID> = []
    @State private var error: String?
    @State private var fileName: String?

    var body: some View {
        NavigationStack {
            List {
                if let error {
                    Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
                }
                if rows.isEmpty {
                    Section {
                        Text("Choose a CSV file with one medication per row and column headers in the first row. In Google Sheets: File › Download › Comma-separated values (.csv), then AirDrop it to this iPhone and save it to Files.")
                            .font(.callout).foregroundStyle(.secondary)
                        Button("Choose file…") { showingPicker = true }
                    }
                } else {
                    Section {
                        ForEach(rows) { row in
                            Button { toggle(row) } label: { rowView(row) }
                                .buttonStyle(.plain)
                        }
                    } header: {
                        Text(fileName ?? "Preview")
                    } footer: {
                        Text("Rows already in the app are unchecked. Controlled-substance status can't be guessed from the name; if the file has no \"Controlled\" column, set it on each controlled medication afterwards.")
                    }
                }
            }
            .navigationTitle("Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import \(selected.count)") { importSelected() }
                        .disabled(selected.isEmpty)
                }
            }
            .fileImporter(isPresented: $showingPicker,
                          allowedContentTypes: [.commaSeparatedText, .plainText, .text]) { result in
                load(result)
            }
        }
    }

    private func rowView(_ row: MedicationImporter.Row) -> some View {
        let d = row.draft
        let isSelected = selected.contains(row.id)
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text([d.brandName.isEmpty ? d.genericName : d.brandName, d.dose]
                        .filter { !$0.isEmpty }.joined(separator: " "))
                    .font(.headline)
                Text(summary(d)).font(.caption).foregroundStyle(.secondary)
                if isDuplicate(d) {
                    Text("Already in the app").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(row.warnings, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
        }
        .contentShape(Rectangle())
    }

    private func summary(_ d: MedicationDraft) -> String {
        var schedule = d.frequency.label
        if d.frequency.fixedDosesPerDay == nil, let perDay = d.customDosesPerDay, perDay > 0 {
            schedule = "every \(Fmt.count(1 / perDay)) days"
            if perDay >= 1 { schedule = "\(Fmt.count(perDay))/day" }
        }
        var parts = ["\(Fmt.count(d.count ?? 0)) on hand", schedule]
        if let units = d.unitsPerDose, units != 1 { parts.append("\(Fmt.count(units)) per dose") }
        if let runOut = SupplyMath.runOutDate(
            start: d.count ?? 0, refreshed: d.countDate,
            dailyUsage: (d.frequency.fixedDosesPerDay ?? d.customDosesPerDay ?? 0) * (d.unitsPerDose ?? 1)) {
            parts.append("out \(Fmt.date(runOut))")
        }
        return parts.joined(separator: " · ")
    }

    private func key(name: String, dose: String) -> String {
        name.lowercased().trimmingCharacters(in: .whitespaces) + "|" +
            dose.lowercased().filter { !$0.isWhitespace }
    }

    private func isDuplicate(_ d: MedicationDraft) -> Bool {
        let k = key(name: d.brandName.isEmpty ? d.genericName : d.brandName, dose: d.dose)
        return existing.contains { key(name: $0.displayName, dose: $0.dose) == k }
    }

    private func toggle(_ row: MedicationImporter.Row) {
        if selected.contains(row.id) { selected.remove(row.id) } else { selected.insert(row.id) }
    }

    private func load(_ result: Result<URL, Error>) {
        error = nil
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                throw MedicationImporter.ParseError(message: "Couldn't read the file as text.")
            }
            rows = try MedicationImporter.parse(text)
            fileName = url.lastPathComponent
            selected = Set(rows.filter { !isDuplicate($0.draft) }.map(\.id))
            if rows.isEmpty { error = "No medications found in that file." }
        } catch let err as CocoaError where err.code == .userCancelled {
            // Picker cancelled: leave the screen as it was.
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func importSelected() {
        var imported: [Medication] = []
        for row in rows where selected.contains(row.id) {
            let med = Medication()
            row.draft.apply(to: med)
            context.insert(med)
            med.recordInitialCount(row.draft.count ?? 0, on: row.draft.countDate)
            imported.append(med)
        }
        NotificationManager.syncAll(context: context)
        let missingNames = imported.filter { $0.brandName.isEmpty || $0.genericName.isEmpty }
        if !missingNames.isEmpty {
            Task { await fillMissingNames(missingNames) }
        }
        dismiss()
    }

    /// Best effort: fill a blank brand or generic name from RxNorm, same as the form's lookup.
    @MainActor
    private func fillMissingNames(_ meds: [Medication]) async {
        for med in meds {
            let term = med.brandName.isEmpty ? med.genericName : med.brandName
            guard let result = try? await RxNormService().lookup(term) else { continue }
            med.rxcui = med.rxcui ?? result.rxcui
            if med.genericName.isEmpty, let generic = result.genericName { med.genericName = generic }
            if med.brandName.isEmpty, result.brandNames.count == 1 { med.brandName = result.brandNames[0] }
        }
        try? context.save()
    }
}
