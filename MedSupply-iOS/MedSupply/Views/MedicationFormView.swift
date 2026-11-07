import PhotosUI
import SwiftData
import SwiftUI

/// Editable copy of a medication so Cancel discards changes.
struct MedicationDraft {
    var brandName = ""
    var genericName = ""
    var rxcui: String?
    var dose = ""
    var frequency: Frequency = .onceDaily
    var customDosesPerDay: Double? = 1
    var scheduleNumber: Double? = 1
    var unitsPerDose: Double? = 1
    var unitName = "tablet"
    var count: Double?
    var countDate = Date()
    var pharmacyName = ""
    var pharmacyPhone = ""
    var rxNumber = ""
    var prescriber = ""
    var prescriberPhone = ""
    var isControlled = false
    var refillsRemaining: Int?
    var hasExpiration = false
    var rxExpirationDate = Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? .now
    var notes = ""
    var imageData: Data?

    init() {}

    init(_ m: Medication) {
        brandName = m.brandName
        genericName = m.genericName
        rxcui = m.rxcui
        dose = m.dose
        frequency = m.frequency
        customDosesPerDay = m.customDosesPerDay
        scheduleNumber = m.scheduleNumber
        unitsPerDose = m.unitsPerDose
        unitName = m.unitName
        pharmacyName = m.pharmacyName
        pharmacyPhone = m.pharmacyPhone
        rxNumber = m.rxNumber
        prescriber = m.prescriber
        prescriberPhone = m.prescriberPhone
        isControlled = m.isControlled
        refillsRemaining = m.refillsRemaining
        hasExpiration = m.rxExpirationDate != nil
        if let exp = m.rxExpirationDate { rxExpirationDate = exp }
        notes = m.notes
        imageData = m.imageData
    }

    var hasName: Bool {
        !brandName.trimmingCharacters(in: .whitespaces).isEmpty
            || !genericName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Doses per day for the supply math.
    var dailyUsage: Double {
        frequency.dosesPerDay(custom: customDosesPerDay ?? 0, number: scheduleNumber ?? 0) * (unitsPerDose ?? 1)
    }

    var scheduleText: String {
        "\(Fmt.amount(unitsPerDose ?? 1)) \(Fmt.unit(unitName, count: unitsPerDose ?? 1)) "
            + frequency.describe(custom: customDosesPerDay ?? 0, number: scheduleNumber ?? 1)
    }

    func isValid(isNew: Bool) -> Bool {
        guard hasName, (unitsPerDose ?? 0) > 0 else { return false }
        if frequency.usesDosesPerDay, (customDosesPerDay ?? -1) < 0 { return false }
        if frequency.usesScheduleNumber, (scheduleNumber ?? 0) <= 0 { return false }
        return !isNew || (count ?? -1) >= 0
    }

    func apply(to m: Medication) {
        let trim: (String) -> String = { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        m.brandName = trim(brandName)
        m.genericName = trim(genericName)
        m.rxcui = rxcui
        m.dose = trim(dose)
        m.frequency = frequency
        m.customDosesPerDay = customDosesPerDay ?? 0
        m.scheduleNumber = scheduleNumber ?? 1
        m.unitsPerDose = unitsPerDose ?? 1
        let unit = trim(unitName)
        m.unitName = unit.isEmpty ? "tablet" : unit
        m.pharmacyName = trim(pharmacyName)
        m.pharmacyPhone = trim(pharmacyPhone)
        m.rxNumber = trim(rxNumber)
        m.prescriber = trim(prescriber)
        m.prescriberPhone = trim(prescriberPhone)
        m.isControlled = isControlled
        m.refillsRemaining = refillsRemaining
        m.rxExpirationDate = hasExpiration ? rxExpirationDate : nil
        m.notes = trim(notes)
        m.imageData = imageData
    }
}

struct MedicationFormView: View {
    /// nil when adding a new medication.
    let medication: Medication?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var allMeds: [Medication]

    @State private var draft = MedicationDraft()
    @State private var loaded = false

    @State private var lookupInProgress = false
    @State private var lookupMessage: String?
    @State private var brandChoices: [String] = []
    @State private var showingBrandChoices = false

    @State private var photoItem: PhotosPickerItem?
    @State private var showingImageSearch = false
    @State private var showingCamera = false

    private var isNew: Bool { medication == nil }

    private enum NameField { case brand, generic }

    var body: some View {
        NavigationStack {
            Form {
                nameSection
                photoSection
                doseSection
                if isNew { countSection }
                prescriptionSection
                pharmacySection
                prescriberSection
                Section("Notes") {
                    TextField("Notes (e.g. take with food, mail-order)", text: $draft.notes, axis: .vertical)
                        .lineLimit(2...6)
                }
            }
            .navigationTitle(isNew ? "Add Medication" : "Edit Medication")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!draft.isValid(isNew: isNew))
                }
            }
            .confirmationDialog("Which brand?", isPresented: $showingBrandChoices, titleVisibility: .visible) {
                ForEach(brandChoices.prefix(20), id: \.self) { name in
                    Button(name) { draft.brandName = name }
                }
                Button("None (generic only)", role: .cancel) {}
            }
            .sheet(isPresented: $showingImageSearch) {
                DrugImageSearchView(query: imageQuery) { data in
                    draft.imageData = ImageUtil.downscaled(data) ?? data
                }
            }
            .fullScreenCover(isPresented: $showingCamera) {
                MacroCameraView { image in draft.imageData = ImageUtil.downscaled(image) }
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        draft.imageData = ImageUtil.downscaled(data)
                    }
                }
            }
            .onAppear {
                guard !loaded else { return }
                if let medication { draft = MedicationDraft(medication) }
                loaded = true
            }
        }
    }

    // MARK: - Sections

    private var nameSection: some View {
        Section {
            HStack {
                TextField("Brand name", text: $draft.brandName)
                    .textInputAutocapitalization(.words)
                    .onSubmit { lookup(from: .brand) }
                lookupButton(.brand)
            }
            HStack {
                TextField("Generic name", text: $draft.genericName)
                    .textInputAutocapitalization(.never)
                    .onSubmit { lookup(from: .generic) }
                lookupButton(.generic)
            }
            if lookupInProgress {
                HStack { ProgressView(); Text("Looking up…").foregroundStyle(.secondary) }
            } else if let lookupMessage {
                Text(lookupMessage).font(.footnote).foregroundStyle(.secondary)
            }
        } header: {
            Text("Medication")
        } footer: {
            Text("Enter either name and tap the magnifier to fill in the other (NIH RxNorm).")
        }
    }

    private func lookupButton(_ field: NameField) -> some View {
        let text = field == .brand ? draft.brandName : draft.genericName
        return Button { lookup(from: field) } label: { Image(systemName: "magnifyingglass") }
            .buttonStyle(.borderless)
            .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty || lookupInProgress)
    }

    private var photoSection: some View {
        Section("Photo") {
            if let data = draft.imageData, let image = UIImage(data: data) {
                HStack {
                    Spacer()
                    Image(uiImage: image).resizable().scaledToFit()
                        .frame(maxHeight: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    Spacer()
                }
                Button("Remove photo", role: .destructive) { draft.imageData = nil }
            }
            Button { showingImageSearch = true } label: {
                Label("Find image online", systemImage: "globe")
            }
            .disabled(!draft.hasName)
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label("Choose from photos", systemImage: "photo")
            }
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button { showingCamera = true } label: {
                    Label("Take close-up photo of pill", systemImage: "camera")
                }
            }
        }
    }

    private var doseSection: some View {
        Section("Dose & frequency") {
            TextField("Dose (e.g. 20 mg)", text: $draft.dose)
            Picker("How often", selection: $draft.frequency) {
                ForEach(Frequency.allCases) { Text($0.label).tag($0) }
            }
            switch draft.frequency {
            case .timesPerWeek:
                LabeledContent("Times per week") {
                    TextField("2", value: $draft.scheduleNumber, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
            case .everyNDays:
                LabeledContent("Every how many days") {
                    TextField("28", value: $draft.scheduleNumber, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
            case .custom, .asNeeded:
                LabeledContent(draft.frequency == .asNeeded ? "Average doses per day" : "Doses per day") {
                    TextField("1", value: $draft.customDosesPerDay, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
            default:
                EmptyView()
            }
            LabeledContent("Amount per dose") {
                TextField("1", value: $draft.unitsPerDose, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
            Picker("Form", selection: $draft.unitName) {
                ForEach(unitOptions, id: \.self) { Text($0.capitalized).tag($0) }
            }
            if (draft.unitsPerDose ?? 0) > 0 {
                Text("Takes \(draft.scheduleText)")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    /// Common forms, plus the current value if it came from an import and isn't in the list.
    private var unitOptions: [String] {
        let current = draft.unitName.trimmingCharacters(in: .whitespaces)
        return DoseUnit.common.contains(current) || current.isEmpty ? DoseUnit.common : DoseUnit.common + [current]
    }

    private var countSection: some View {
        Section {
            LabeledContent("Current count (\(Fmt.unit(draft.unitName, count: 2)))") {
                TextField("Required", value: $draft.count, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
            CollapsingDatePicker(title: "Counted on", selection: $draft.countDate,
                                 range: Date.distantPast...Date())
        } header: {
            Text("Supply")
        } footer: {
            if let count = draft.count, let runOut = projectedRunOut(count) {
                Text("Projected to run out \(Fmt.date(runOut)).")
            }
        }
    }

    private var prescriptionSection: some View {
        Section("Prescription") {
            TextField("Rx number", text: $draft.rxNumber)
                .textInputAutocapitalization(.characters)
            Toggle("Controlled substance", isOn: $draft.isControlled)
            LabeledContent("Refills remaining") {
                TextField("Optional", value: $draft.refillsRemaining, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
            }
            Toggle("Track Rx expiration", isOn: $draft.hasExpiration)
            if draft.hasExpiration {
                CollapsingDatePicker(title: "Expires", selection: $draft.rxExpirationDate)
            }
        }
    }

    private var pharmacySection: some View {
        Section {
            TextField("Pharmacy", text: $draft.pharmacyName)
            TextField("Pharmacy phone", text: $draft.pharmacyPhone)
                .keyboardType(.phonePad)
        } header: {
            HStack {
                Text("Pharmacy")
                Spacer()
                let options = pharmacyOptions
                if !options.isEmpty {
                    Menu("Use saved") {
                        ForEach(options, id: \.name) { option in
                            Button(option.name) {
                                draft.pharmacyName = option.name
                                draft.pharmacyPhone = option.phone
                            }
                        }
                    }
                    .font(.caption)
                    .textCase(nil)
                }
            }
        }
    }

    private var prescriberSection: some View {
        Section {
            TextField("Doctor", text: $draft.prescriber)
            TextField("Doctor's phone", text: $draft.prescriberPhone)
                .keyboardType(.phonePad)
        } header: {
            HStack {
                Text("Prescribing doctor")
                Spacer()
                let options = prescriberOptions
                if !options.isEmpty {
                    Menu("Use saved") {
                        ForEach(options, id: \.name) { option in
                            Button(option.name) {
                                draft.prescriber = option.name
                                draft.prescriberPhone = option.phone
                            }
                        }
                    }
                    .font(.caption)
                    .textCase(nil)
                }
            }
        }
    }

    // MARK: - Helpers

    private struct Contact { let name: String; let phone: String }

    private var pharmacyOptions: [Contact] {
        uniqueContacts(allMeds.map { Contact(name: $0.pharmacyName, phone: $0.pharmacyPhone) })
    }

    private var prescriberOptions: [Contact] {
        uniqueContacts(allMeds.map { Contact(name: $0.prescriber, phone: $0.prescriberPhone) })
    }

    private func uniqueContacts(_ contacts: [Contact]) -> [Contact] {
        var seen = Set<String>()
        return contacts
            .filter { !$0.name.isEmpty && seen.insert($0.name.lowercased().filter { !$0.isWhitespace }).inserted }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var imageQuery: String {
        let generic = draft.genericName.trimmingCharacters(in: .whitespaces)
        let brand = draft.brandName.trimmingCharacters(in: .whitespaces)
        return brand.isEmpty ? generic : brand
    }

    private func projectedRunOut(_ count: Double) -> Date? {
        SupplyMath.runOutDate(start: count, refreshed: draft.countDate, dailyUsage: draft.dailyUsage)
    }

    private func lookup(from field: NameField) {
        let term = field == .brand ? draft.brandName : draft.genericName
        guard !term.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        lookupInProgress = true
        lookupMessage = nil
        Task {
            defer { lookupInProgress = false }
            do {
                let result = try await RxNormService().lookup(term)
                draft.rxcui = result.rxcui
                if result.inputWasBrand {
                    // Typed a brand (in either field): fill generic, keep the brand.
                    if field == .generic { draft.brandName = result.brandNames.first ?? term }
                    if let generic = result.genericName { draft.genericName = generic }
                    lookupMessage = result.genericName.map { "Generic: \($0)" } ?? "No generic name found."
                } else {
                    // Typed a generic (in either field).
                    if let generic = result.genericName { draft.genericName = generic }
                    if field == .brand { draft.brandName = "" }
                    switch result.brandNames.count {
                    case 0:
                        lookupMessage = "No brand name in RxNorm (generic only)."
                    case 1:
                        draft.brandName = result.brandNames[0]
                        lookupMessage = "Brand: \(result.brandNames[0])"
                    default:
                        lookupMessage = "\(result.brandNames.count) brands found."
                        brandChoices = result.brandNames
                        showingBrandChoices = true
                    }
                }
            } catch {
                lookupMessage = "Lookup failed: \(error.localizedDescription)"
            }
        }
    }

    private func save() {
        let med = medication ?? Medication()
        draft.apply(to: med)
        if isNew {
            context.insert(med)
            med.recordInitialCount(draft.count ?? 0, on: draft.countDate)
        }
        NotificationManager.syncAll(context: context)
        dismiss()
    }
}
