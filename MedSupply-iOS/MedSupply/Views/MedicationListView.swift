import SwiftData
import SwiftUI

struct MedicationListView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query private var allMeds: [Medication]
    @AppStorage("showArchived") private var showArchived = false

    @State private var now = Date()
    @State private var showingAdd = false
    @State private var showingSettings = false
    @State private var showingImport = false
    @State private var refillTarget: Medication?
    @State private var cameraTarget: Medication?
    @State private var deleteTarget: Medication?

    private var active: [Medication] {
        allMeds.filter { !$0.isArchived }.sorted(by: runOutOrder)
    }
    private var needsReorder: [Medication] { active.filter { $0.status(on: now).needsAttention } }
    private var others: [Medication] { active.filter { !$0.status(on: now).needsAttention } }
    private var archived: [Medication] {
        allMeds.filter(\.isArchived).sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List {
                if !needsReorder.isEmpty {
                    Section("Reorder now") { rows(needsReorder) }
                }
                if !others.isEmpty {
                    Section(needsReorder.isEmpty ? "Medications" : "Other medications") { rows(others) }
                }
                if showArchived && !archived.isEmpty {
                    Section("Archived") { rows(archived) }
                }
            }
            .overlay {
                if active.isEmpty {
                    ContentUnavailableView {
                        Label("No medications", systemImage: "pills")
                    } description: {
                        Text("Add a medication to start tracking its supply.")
                    } actions: {
                        Button("Add medication") { showingAdd = true }
                            .buttonStyle(.borderedProminent)
                        Button("Import from spreadsheet") { showingImport = true }
                    }
                }
            }
            .navigationTitle("Med Supply")
            .navigationDestination(for: Medication.self) { MedicationDetailView(med: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Toggle("Show archived", isOn: $showArchived)
                        Button { showingImport = true } label: {
                            Label("Import from spreadsheet…", systemImage: "square.and.arrow.down")
                        }
                        Button { showingSettings = true } label: { Label("Settings", systemImage: "gear") }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAdd = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add medication")
                }
            }
            .sheet(isPresented: $showingAdd) { MedicationFormView(medication: nil) }
            .sheet(isPresented: $showingSettings, onDismiss: sync) { SettingsView() }
            .sheet(isPresented: $showingImport) { ImportView() }
            .sheet(item: $refillTarget) { RefillSheet(med: $0) }
            .fullScreenCover(item: $cameraTarget) { med in
                MacroCameraView { image in
                    med.imageData = ImageUtil.downscaled(image)
                    try? context.save()
                }
            }
            .confirmationDialog("Delete \(deleteTarget?.displayName ?? "")?",
                                isPresented: Binding(get: { deleteTarget != nil },
                                                     set: { if !$0 { deleteTarget = nil } }),
                                titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let med = deleteTarget {
                        context.delete(med)
                        sync()
                    }
                    deleteTarget = nil
                }
            } message: {
                Text("This removes the medication and its refill history. Archive it instead to keep the history.")
            }
        }
        .task {
            DataMigrations.run(context: context)
            await NotificationManager.requestAuthorization()
            sync()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                now = Date()
                sync()
            }
        }
    }

    @ViewBuilder
    private func rows(_ meds: [Medication]) -> some View {
        ForEach(meds) { med in
            NavigationLink(value: med) {
                // Tapping the placeholder pill icon opens the camera; a real photo just opens the row.
                MedicationRow(med: med, now: now,
                              onPhotoTap: med.imageData == nil ? { cameraTarget = med } : nil)
            }
                .swipeActions(edge: .leading) {
                    Button { refillTarget = med } label: { Label("Refill", systemImage: "plus.circle") }
                        .tint(.green)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { deleteTarget = med } label: { Label("Delete", systemImage: "trash") }
                    Button {
                        med.isArchived.toggle()
                        sync()
                    } label: {
                        Label(med.isArchived ? "Unarchive" : "Archive", systemImage: "archivebox")
                    }
                    .tint(.gray)
                }
        }
    }

    private func runOutOrder(_ a: Medication, _ b: Medication) -> Bool {
        switch (a.runOutDate, b.runOutDate) {
        case let (x?, y?): return x < y
        case (nil, _?): return false
        case (_?, nil): return true
        default: return a.displayName < b.displayName
        }
    }

    private func sync() {
        NotificationManager.syncAll(context: context)
    }
}

struct MedicationRow: View {
    let med: Medication
    var now: Date = .now
    var onPhotoTap: (() -> Void)?

    var body: some View {
        let status = med.status(on: now)
        HStack(spacing: 12) {
            if let onPhotoTap {
                Button(action: onPhotoTap) {
                    MedicationThumbnail(data: med.imageData, size: 48, showsCameraBadge: true)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Take photo of \(med.displayName)")
            } else {
                MedicationThumbnail(data: med.imageData, size: 48)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(med.displayName).font(.headline)
                    if med.isControlled {
                        Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary)
                            .accessibilityLabel("Controlled substance")
                    }
                }
                if let subtitle = subtitle {
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
                Text(detailLine).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            StatusBadge(status: status)
        }
        .padding(.vertical, 2)
    }

    /// Generic name and strength, so two strengths of the same drug are distinguishable.
    private var subtitle: String? {
        let parts = [med.secondaryName ?? "", med.dose].filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var detailLine: String {
        var parts = ["\(med.countText(med.estimatedCount(on: now))) left"]
        if let runOut = med.runOutDate { parts.append("out \(Fmt.date(runOut))") }
        return parts.joined(separator: " · ")
    }
}

struct StatusBadge: View {
    let status: SupplyStatus

    var body: some View {
        Text(status.label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(status.color.opacity(0.18), in: Capsule())
            .foregroundStyle(status.color)
    }
}

struct MedicationThumbnail: View {
    let data: Data?
    var size: CGFloat
    /// Small camera badge in the corner, used where tapping the thumbnail opens the camera.
    var showsCameraBadge = false

    var body: some View {
        thumbnail
            .overlay(alignment: .bottomTrailing) {
                if showsCameraBadge {
                    Image(systemName: "camera.circle.fill")
                        .font(.system(size: max(14, size * 0.3)))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.accentColor)
                        .offset(x: 4, y: 4)
                }
            }
    }

    private var thumbnail: some View {
        Group {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "pills.fill")
                    .font(.system(size: size * 0.45))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.secondarySystemBackground))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.2))
    }
}
