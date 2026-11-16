import Foundation

/// One entry of Colibri's model catalogue, from `coli setup --list --json`.
public struct CatalogueEntry: Sendable, Equatable, Decodable, Identifiable {
    public var id: String
    public var name: String
    public var family: String?
    public var repo: String?
    public var downloadGB: Double?
    public var ramMinGB: Double?
    public var ramGoodGB: Double?
    public var denseGB: Double?
    public var kind: String?
    public var runs: String?
    public var summary: String?
    public var status: String?
    public var fits: Bool?
    public var reason: String?
    public var recommended: Bool?
    public var licenseNote: String?

    enum CodingKeys: String, CodingKey {
        case id, name, family, repo, kind, runs, summary, status, fits, reason, recommended
        case downloadGB = "download_gb"
        case ramMinGB = "ram_min_gb"
        case ramGoodGB = "ram_good_gb"
        case denseGB = "dense_gb"
        case licenseNote = "license_note"
    }
}
