import SwiftUI
import UIKit

/// A date row that expands into a calendar and collapses again as soon as a day is picked.
/// (The standard compact DatePicker leaves its popup open until you tap elsewhere.)
struct CollapsingDatePicker: View {
    let title: String
    @Binding var selection: Date
    var range: ClosedRange<Date>?

    @State private var expanded = false

    var body: some View {
        Button {
            withAnimation { expanded.toggle() }
        } label: {
            LabeledContent(title) {
                Text(Fmt.date(selection))
                    .foregroundStyle(expanded ? Color.accentColor : Color.secondary)
            }
        }
        .foregroundStyle(.primary)

        if expanded {
            calendar
                .datePickerStyle(.graphical)
                .labelsHidden()
                .onChange(of: selection) { _, _ in
                    withAnimation { expanded = false }
                }
        }
    }

    @ViewBuilder
    private var calendar: some View {
        if let range {
            DatePicker(title, selection: $selection, in: range, displayedComponents: .date)
        } else {
            DatePicker(title, selection: $selection, displayedComponents: .date)
        }
    }
}

/// Full-screen view of a medication photo, with pinch to zoom.
struct PhotoViewer: View {
    let data: Data?
    var title: String = ""

    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let data, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(scale)
                        .gesture(
                            MagnifyGesture()
                                .onChanged { scale = min(5, max(1, lastScale * $0.magnification)) }
                                .onEnded { _ in lastScale = scale }
                        )
                        .onTapGesture(count: 2) {
                            withAnimation {
                                scale = scale > 1 ? 1 : 2.5
                                lastScale = scale
                            }
                        }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

extension Fmt {
    /// Number as typed into a text field: "30", "20.25" (no thousands separators).
    static func plain(_ value: Double) -> String {
        value.formatted(.number.grouping(.never).precision(.fractionLength(0...2)))
    }

    /// Parses a typed number, accepting "," as the decimal separator too.
    static func parse(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }
}
