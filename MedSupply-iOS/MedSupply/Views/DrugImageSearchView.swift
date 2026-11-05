import SwiftUI
import UIKit

/// Shows images from DailyMed drug labels so the user can pick the one that matches.
struct DrugImageSearchView: View {
    let query: String
    let onSelect: (Data) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var candidates: [DailyMedImageService.Candidate] = []
    @State private var loading = true
    @State private var error: String?
    @State private var downloading: URL?

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 8)]

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView("Searching DailyMed…")
                } else if let error {
                    ContentUnavailableView("Search failed", systemImage: "wifi.exclamationmark",
                                           description: Text(error))
                } else if candidates.isEmpty {
                    ContentUnavailableView("No images found", systemImage: "photo",
                                           description: Text("Try the other name, or take a photo of the pill or bottle."))
                } else {
                    ScrollView {
                        Text("Images come from FDA drug labels. Tap the one that matches her pill or bottle; label images can show a different strength or manufacturer.")
                            .font(.footnote).foregroundStyle(.secondary)
                            .padding(.horizontal)
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(candidates) { candidate in
                                Button { select(candidate) } label: { tile(candidate) }
                                    .buttonStyle(.plain)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle(query)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .task { await search() }
        }
    }

    private func tile(_ candidate: DailyMedImageService.Candidate) -> some View {
        AsyncImage(url: candidate.url) { phase in
            switch phase {
            case .success(let image): image.resizable().scaledToFit()
            case .failure: Image(systemName: "exclamationmark.triangle").foregroundStyle(.secondary)
            default: ProgressView()
            }
        }
        .frame(height: 104)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            if downloading == candidate.url { ProgressView().controlSize(.large) }
        }
    }

    private func search() async {
        do {
            candidates = try await DailyMedImageService().images(for: query)
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    private func select(_ candidate: DailyMedImageService.Candidate) {
        guard downloading == nil else { return }
        downloading = candidate.url
        Task {
            defer { downloading = nil }
            if let data = try? await DailyMedImageService.download(candidate.url), UIImage(data: data) != nil {
                onSelect(data)
                dismiss()
            }
        }
    }
}

/// Minimal camera wrapper (SwiftUI has no native camera capture view).
struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
