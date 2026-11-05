import SwiftUI
import UIKit

enum Fmt {
    /// "30", "29.5" — counts can be fractional when half tablets are used.
    static func count(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
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
