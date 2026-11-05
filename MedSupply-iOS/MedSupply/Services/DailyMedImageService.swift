import Foundation

/// Finds product images (pill photos, bottle/carton labels) from the FDA labels published on
/// NLM DailyMed. WebMD has no public API and its terms prohibit scraping, so DailyMed is used instead.
/// Docs: https://dailymed.nlm.nih.gov/dailymed/app-support-web-services.cfm
struct DailyMedImageService {
    struct Candidate: Identifiable, Hashable {
        let url: URL
        let labelTitle: String
        var id: URL { url }
    }

    private let base = URL(string: "https://dailymed.nlm.nih.gov/dailymed/services/v2/")!

    /// Searches labels by drug name and gathers their images.
    func images(for drugName: String, maxLabels: Int = 6, maxImages: Int = 40) async throws -> [Candidate] {
        var comps = URLComponents(url: base.appendingPathComponent("spls.json"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "drug_name", value: drugName),
            URLQueryItem(name: "pagesize", value: String(maxLabels)),
        ]
        let (data, _) = try await URLSession.shared.data(from: comps.url!)
        let labels = try JSONDecoder().decode(SPLListResponse.self, from: data).data

        // Fetch each label's media list in parallel, keeping the original label order.
        let perLabel = await withTaskGroup(of: (Int, [Candidate]).self) { group in
            for (index, label) in labels.enumerated() {
                group.addTask { (index, (try? await self.media(setid: label.setid, title: label.title ?? "")) ?? []) }
            }
            var results: [(Int, [Candidate])] = []
            for await item in group { results.append(item) }
            return results.sorted { $0.0 < $1.0 }.flatMap(\.1)
        }

        var seen = Set<URL>()
        return Array(perLabel.filter { seen.insert($0.url).inserted }.prefix(maxImages))
    }

    private func media(setid: String, title: String) async throws -> [Candidate] {
        let url = base.appendingPathComponent("spls/\(setid)/media.json")
        let (data, _) = try await URLSession.shared.data(from: url)
        let media = try JSONDecoder().decode(MediaResponse.self, from: data).data.media ?? []
        return media.compactMap { item in
            let type = (item.mime_type ?? "").lowercased()
            guard type.contains("jpeg") || type.contains("png") || type.contains("jpg"),
                  let url = URL(string: item.url) else { return nil }
            return Candidate(url: url, labelTitle: title)
        }
    }

    static func download(_ url: URL) async throws -> Data {
        let (data, _) = try await URLSession.shared.data(from: url)
        return data
    }
}

private struct SPLListResponse: Decodable {
    struct Item: Decodable {
        let setid: String
        let title: String?
    }
    let data: [Item]
}

private struct MediaResponse: Decodable {
    struct Payload: Decodable { let media: [Item]? }
    struct Item: Decodable {
        let name: String?
        let mime_type: String?
        let url: String
    }
    let data: Payload
}
