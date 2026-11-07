import SwiftData
import SwiftUI

struct MedicationDetailView: View {
    @Bindable var med: Medication
    @Environment(\.modelContext) private var context

    @State private var showingRefill = false
    @State private var showingRecount = false
    @State private var showingEdit = false
    @State private var showingCamera = false

    var body: some View {
        List {
            Section {
                HStack(spacing: 16) {
                    Button { showingCamera = true } label: {
                        MedicationThumbnail(data: med.imageData, size: 88, showsCameraBadge: true)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(med.imageData == nil ? "Take photo" : "Retake photo")
                    VStack(alignment: .leading, spacing: 4) {
                        Text(med.displayName).font(.title2.bold())
                        if let generic = med.secondaryName {
                            Text(generic).foregroundStyle(.secondary)
                        }
                        if !med.dose.isEmpty { Text(med.dose).font(.subheadline) }
                        if med.isControlled {
                            Label("Controlled substance", systemImage: "lock.fill")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Supply") {
                HStack {
                    Text("Status")
                    Spacer()
                    StatusBadge(status: med.status())
                }
                LabeledContent("On hand (estimated)", value: med.countText(med.estimatedCount()))
                LabeledContent("Schedule", value: med.scheduleText.capitalizedFirst)
                if let runOut = med.runOutDate {
                    LabeledContent("Runs out", value: Fmt.date(runOut))
                }
                if let reorder = med.reorderDate {
                    LabeledContent("Reorder reminder",
                                   value: "\(Fmt.date(reorder)) (\(med.leadDays) days before)")
                } else {
                    Text("Set how often it's taken to get a run-out estimate.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                LabeledContent("Count last refreshed", value: Fmt.date(med.lastRefreshedDate))
                if let ordered = med.orderPlacedDate {
                    LabeledContent("Reordered", value: Fmt.date(ordered))
                }
            }

            Section {
                Button { showingRefill = true } label: {
                    Label("Refill", systemImage: "plus.circle.fill").font(.headline)
                }
                Button { showingRecount = true } label: {
                    Label("Recount (correct the count)", systemImage: "number.circle")
                }
                Button {
                    med.orderPlacedDate = med.orderPlacedDate == nil ? .now : nil
                    sync()
                } label: {
                    if med.orderPlacedDate == nil {
                        Label("Mark as reordered", systemImage: "cart.badge.plus")
                    } else {
                        Label("Undo reordered", systemImage: "arrow.uturn.backward")
                    }
                }
                ShareLink(item: med.refillRequestText) {
                    Label("Share refill info", systemImage: "square.and.arrow.up")
                }
            } footer: {
                Text("Marking as reordered silences reminders until the refill is recorded.")
            }

            Section("Prescription") {
                if !med.rxNumber.isEmpty {
                    LabeledContent("Rx number") { Text(med.rxNumber).textSelection(.enabled) }
                }
                if let refills = med.refillsRemaining {
                    LabeledContent("Refills remaining", value: "\(refills)")
                        .foregroundStyle(refills == 0 ? .red : .primary)
                }
                if let exp = med.rxExpirationDate {
                    LabeledContent("Prescription expires", value: Fmt.date(exp))
                        .foregroundStyle(exp < .now ? .red : .primary)
                }
                LabeledContent("Controlled substance", value: med.isControlled ? "Yes" : "No")
            }

            if !med.pharmacyName.isEmpty || !med.pharmacyPhone.isEmpty {
                Section("Pharmacy") {
                    if !med.pharmacyName.isEmpty { Text(med.pharmacyName) }
                    phoneLink(med.pharmacyPhone)
                }
            }

            if !med.prescriber.isEmpty || !med.prescriberPhone.isEmpty {
                Section("Prescribing doctor") {
                    if !med.prescriber.isEmpty { Text(med.prescriber) }
                    phoneLink(med.prescriberPhone)
                }
            }

            if !med.notes.isEmpty {
                Section("Notes") { Text(med.notes) }
            }

            if !med.sortedHistory.isEmpty {
                Section("History") {
                    ForEach(med.sortedHistory) { event in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(event.kind.label)
                                Text(Fmt.date(event.date)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(historyDetail(event)).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section {
                Button(med.isArchived ? "Unarchive" : "Archive (stopped taking)") {
                    med.isArchived.toggle()
                    sync()
                }
            }
        }
        .navigationTitle(med.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("Edit") { showingEdit = true }
        }
        .sheet(isPresented: $showingRefill) { RefillSheet(med: med) }
        .sheet(isPresented: $showingRecount) { RecountSheet(med: med) }
        .sheet(isPresented: $showingEdit) { MedicationFormView(medication: med) }
        .fullScreenCover(isPresented: $showingCamera) {
            MacroCameraView { image in
                med.imageData = ImageUtil.downscaled(image)
                try? context.save()
            }
        }
    }

    @ViewBuilder
    private func phoneLink(_ phone: String) -> some View {
        if let url = Fmt.telURL(phone) {
            Link(destination: url) { Label(phone, systemImage: "phone.fill") }
        }
    }

    private func historyDetail(_ event: RefillEvent) -> String {
        switch event.kind {
        case .refill:
            return "+\(Fmt.count(event.quantity)) → \(Fmt.count(event.countAfter))"
        case .recount:
            return "\(Fmt.count(event.countBefore)) → \(Fmt.count(event.countAfter))"
        case .initial:
            return Fmt.count(event.countAfter)
        }
    }

    private func sync() {
        NotificationManager.syncAll(context: context)
    }
}
