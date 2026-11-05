import Foundation

/// Brand ↔ generic lookup using the free NIH/NLM RxNorm API (no key required).
/// Docs: https://lhncbc.nlm.nih.gov/RxNav/APIs/RxNormAPIs.html
struct RxNormService {
    struct Result {
        var rxcui: String
        /// True when the typed name resolved to a brand name (RxNorm term type BN).
        var inputWasBrand: Bool
        var genericName: String?
        var brandNames: [String]
    }

    enum LookupError: LocalizedError {
        case notFound
        var errorDescription: String? { "No match found in RxNorm. Check the spelling." }
    }

    private let base = URL(string: "https://rxnav.nlm.nih.gov/REST/")!
    private let session: URLSession = .shared

    func lookup(_ term: String) async throws -> Result {
        let name = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw LookupError.notFound }

        let rxcui = try await findRxcui(name)
        let props = try await properties(rxcui)

        switch props.tty {
        case "BN":
            let generics = try await related(rxcui, ttys: ["IN", "MIN"])
            return Result(rxcui: rxcui, inputWasBrand: true,
                          genericName: preferredGeneric(generics), brandNames: [props.name])
        case "IN", "MIN":
            let brands = try await related(rxcui, ttys: ["BN"])
            return Result(rxcui: rxcui, inputWasBrand: false,
                          genericName: props.name, brandNames: uniqueNames(brands))
        default:
            // Salt forms (PIN) or full drug strings like "atorvastatin 20 MG Oral Tablet".
            let rel = try await related(rxcui, ttys: ["BN", "IN", "MIN"])
            let generics = rel.filter { $0.tty == "IN" || $0.tty == "MIN" }
            var brands = rel.filter { $0.tty == "BN" }
            if brands.isEmpty, let ing = generics.first {
                brands = try await related(ing.rxcui, ttys: ["BN"])
            }
            return Result(rxcui: rxcui, inputWasBrand: props.tty == "SBD" || props.tty == "BPCK",
                          genericName: preferredGeneric(generics) ?? props.name,
                          brandNames: uniqueNames(brands))
        }
    }

    // MARK: - API calls

    private func findRxcui(_ name: String) async throws -> String {
        // Exact / normalized match first.
        let exact: IdGroupResponse = try await get("rxcui.json", ["name": name, "search": "2"])
        if let id = exact.idGroup.rxnormId?.first { return id }
        // Fall back to approximate (spelling-tolerant) match, RxNorm concepts only.
        let approx: ApproxResponse = try await get("approximateTerm.json",
                                                   ["term": name, "maxEntries": "1", "option": "1"])
        if let id = approx.approximateGroup.candidate?.first?.rxcui { return id }
        throw LookupError.notFound
    }

    private func properties(_ rxcui: String) async throws -> PropertiesResponse.Props {
        let resp: PropertiesResponse = try await get("rxcui/\(rxcui)/properties.json", [:])
        guard let props = resp.properties else { throw LookupError.notFound }
        return props
    }

    private func related(_ rxcui: String, ttys: [String]) async throws -> [RelatedResponse.Concept] {
        let resp: RelatedResponse = try await get("rxcui/\(rxcui)/related.json",
                                                  ["tty": ttys.joined(separator: " ")])
        return (resp.relatedGroup.conceptGroup ?? []).flatMap { $0.conceptProperties ?? [] }
    }

    private func get<T: Decodable>(_ path: String, _ query: [String: String]) async throws -> T {
        var comps = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        let (data, response) = try await session.data(from: comps.url!)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - Helpers

    /// Prefer a single combined ingredient (MIN, e.g. "acetaminophen / hydrocodone") over listing parts.
    private func preferredGeneric(_ concepts: [RelatedResponse.Concept]) -> String? {
        if let min = concepts.first(where: { $0.tty == "MIN" }) { return min.name }
        let ins = concepts.filter { $0.tty == "IN" }.map(\.name)
        return ins.isEmpty ? nil : ins.joined(separator: " / ")
    }

    private func uniqueNames(_ concepts: [RelatedResponse.Concept]) -> [String] {
        var seen = Set<String>()
        return concepts.map(\.name)
            .filter { seen.insert($0.lowercased()).inserted }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}

// MARK: - Response types

private struct IdGroupResponse: Decodable {
    struct IdGroup: Decodable { let rxnormId: [String]? }
    let idGroup: IdGroup
}

private struct ApproxResponse: Decodable {
    struct Group: Decodable { let candidate: [Candidate]? }
    struct Candidate: Decodable { let rxcui: String? }
    let approximateGroup: Group
}

private struct PropertiesResponse: Decodable {
    struct Props: Decodable {
        let rxcui: String
        let name: String
        let tty: String
    }
    let properties: Props?
}

struct RelatedResponse: Decodable {
    struct Group: Decodable { let conceptGroup: [ConceptGroup]? }
    struct ConceptGroup: Decodable {
        let tty: String?
        let conceptProperties: [Concept]?
    }
    struct Concept: Decodable {
        let rxcui: String
        let name: String
        let tty: String
    }
    let relatedGroup: Group
}
