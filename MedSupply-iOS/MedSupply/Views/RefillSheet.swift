import SwiftData
import SwiftUI

/// Asks for the count being added, adds it to the current (projected) count, and sets the refresh date.
struct RefillSheet: View {
    let med: Medication
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var quantity: Double?
    @State private var date = Date()
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Number of \(Fmt.unit(med.unitName, count: 2)) added", value: $quantity, format: .number)
                        .keyboardType(.decimalPad)
                        .focused($focused)
                        .font(.title2)
                    DatePicker("Date picked up", selection: $date,
                               in: Calendar.current.startOfDay(for: med.lastRefreshedDate)...Date(),
                               displayedComponents: .date)
                } header: {
                    Text("How many are being added?")
                } footer: {
                    if let qty = med.lastRefillQuantity {
                        Text("Last refill was \(med.countText(qty)).")
                    }
                }

                Section("Result") {
                    LabeledContent("On hand now (estimated)", value: med.countText(onHand))
                    if let qty = quantity, qty > 0 {
                        LabeledContent("New count", value: med.countText(onHand + qty))
                        if let runOut = SupplyMath.runOutDate(start: onHand + qty, refreshed: date,
                                                              dailyUsage: med.dailyUsage) {
                            LabeledContent("New run-out date", value: Fmt.date(runOut))
                        }
                    }
                }
            }
            .navigationTitle("Refill \(med.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled((quantity ?? 0) <= 0)
                }
            }
            .onAppear {
                quantity = med.lastRefillQuantity
                focused = true
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var onHand: Double { med.estimatedCount(on: date) }

    private func save() {
        guard let qty = quantity, qty > 0 else { return }
        med.recordRefill(quantity: qty, on: date)
        NotificationManager.syncAll(context: context)
        dismiss()
    }
}

/// Replaces the projected count with an actual count.
struct RecountSheet: View {
    let med: Medication
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var count: Double?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Number of \(Fmt.unit(med.unitName, count: 2))", value: $count, format: .number)
                        .keyboardType(.decimalPad)
                        .focused($focused)
                        .font(.title2)
                } header: {
                    Text("How many are actually on hand?")
                } footer: {
                    Text("The app estimates \(med.countText(med.estimatedCount())). Recounting fixes drift from missed or extra doses.")
                }
            }
            .navigationTitle("Recount")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let count, count >= 0 else { return }
                        med.recordRecount(count: count, on: .now)
                        NotificationManager.syncAll(context: context)
                        dismiss()
                    }
                    .disabled(count == nil)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium])
    }
}
