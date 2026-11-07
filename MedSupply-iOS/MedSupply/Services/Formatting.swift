import SwiftUI
import UIKit

enum Fmt {
    /// "30", "20.25": up to two decimals, since counts can be fractional with partial tablets.
    static func count(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }

    /// Dose amounts with common fractions: 0.25 → "¼", 1.5 → "1½".
    static func amount(_ value: Double) -> String {
        let whole = value.rounded(.down)
        let glyphs: [(Double, String)] = [(0.25, "¼"), (0.5, "½"), (0.75, "¾"), (1.0 / 3, "⅓"), (2.0 / 3, "⅔")]
        if let match = glyphs.first(where: { abs((value - whole) - $0.0) < 0.01 }) {
            return whole == 0 ? match.1 : "\(Int(whole))\(match.1)"
        }
        return count(value)
    }

    /// Pluralizes a dose form for a count: 1 patch, 8 patches, 0.25 tablet, 30 tablets.
    static func unit(_ name: String, count: Double) -> String {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, count > 1 || count == 0 else { return n }
        let lower = n.lowercased()
        if ["ml", "mg", "g", "mcg"].contains(lower) || lower.hasSuffix("s") && !lower.hasSuffix("ss") { return n }
        if ["ch", "sh", "x", "z", "ss"].contains(where: { lower.hasSuffix($0) }) { return n + "es" }
        if lower.hasSuffix("y"), let before = lower.dropLast().last, !"aeiou".contains(before) {
            return String(n.dropLast()) + "ies"
        }
        return n + "s"
    }

    static func date(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }

    static func telURL(_ phone: String) -> URL? {
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        return digits.isEmpty ? nil : URL(string: "tel:\(digits)")
    }
}

extension SupplyStatus {
    var color: Color {
        switch self {
        case .noProjection: return .gray
        case .ok: return .green
        case .reorderNow: return .orange
        case .ordered: return .blue
        case .out: return .red
        }
    }
}

extension String {
    /// "twice a week" → "Twice a week".
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

enum ImageUtil {
    /// Shrinks photos to keep the database small (max 1024 px on the long side, JPEG).
    static func downscaled(_ data: Data, maxDimension: CGFloat = 1024) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        return downscaled(image, maxDimension: maxDimension)
    }

    static func downscaled(_ image: UIImage, maxDimension: CGFloat = 1024) -> Data? {
        let size = image.size
        let scale = min(1, maxDimension / max(size.width, size.height))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: 0.8)
    }
}
