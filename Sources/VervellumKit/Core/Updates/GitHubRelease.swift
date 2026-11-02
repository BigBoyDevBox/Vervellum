import Foundation

/// The subset of GitHub's Releases API we care about.
/// See <https://docs.github.com/en/rest/releases/releases>.
///
/// Reusable across apps — depends only on Foundation.
struct GitHubRelease: Decodable {
    let tagName: String
    let name: String?
    let body: String?
    let htmlURL: URL
    let prerelease: Bool
    let draft: Bool
    let publishedAt: Date?
    let assets: [Asset]

    struct Asset: Decodable {
        let name: String
        let contentType: String
        let size: Int
        let browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case contentType = "content_type"
            case size
            case browserDownloadURL = "browser_download_url"
        }
    }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name, body
        case htmlURL = "html_url"
        case prerelease, draft
        case publishedAt = "published_at"
        case assets
    }

    /// The best asset to download for this machine.
    ///
    /// Three questions in order: does the name name this operating system, does it name
    /// this architecture (a universal build is the fallback), and only then is a disk
    /// image preferred over a zip or pkg. The extension alone used to decide everything,
    /// which picks whichever same-extension asset GitHub lists first when a release ever
    /// carries more than one — an Intel-only zip on an Apple-silicon Mac, downloaded and
    /// then unable to install. Ties keep the release's own order.
    var preferredAsset: Asset? {
        let preference = ["dmg", "zip", "pkg"]
        func rank(_ asset: Asset) -> Int {
            let ext = (asset.name as NSString).pathExtension.lowercased()
            return preference.firstIndex(of: ext) ?? preference.count
        }
        func affinity(_ asset: Asset) -> Int { Self.assetAffinity(asset.name) }
        return assets.enumerated().min { lhs, rhs in
            let leftAffinity = affinity(lhs.element)
            let rightAffinity = affinity(rhs.element)
            if leftAffinity != rightAffinity { return leftAffinity > rightAffinity }
            let leftRank = rank(lhs.element)
            let rightRank = rank(rhs.element)
            if leftRank != rightRank { return leftRank < rightRank }
            return lhs.offset < rhs.offset
        }?.element
    }

    /// How well an asset name matches the machine running the updater.
    ///
    /// Platform first (8), exact architecture second (4), a universal build last (2).
    /// A `.dmg` counts as a macOS name and a `.deb` as a Linux one, so the extension
    /// still helps when a release names its artifacts by type rather than by platform.
    static func assetAffinity(_ name: String) -> Int {
        let lowered = name.lowercased()
        var score = 0
        #if os(macOS)
        if lowered.contains("macos") || lowered.contains("osx") || lowered.contains("darwin")
            || lowered.hasSuffix(".dmg") { score += 8 }
        #elseif os(Linux)
        if lowered.contains("linux") || lowered.hasSuffix(".deb") { score += 8 }
        #endif
        #if arch(arm64)
        let exactArchitecture = ["arm64", "aarch64"]
        #elseif arch(x86_64)
        let exactArchitecture = ["x86_64", "amd64"]
        #else
        let exactArchitecture: [String] = []
        #endif
        if exactArchitecture.contains(where: { lowered.contains($0) }) {
            score += 4
        } else if lowered.contains("universal") {
            score += 2
        }
        return score
    }

    /// A trimmed, length-capped form of the release body, suitable for an alert's
    /// informative text (markdown is shown as-is — GitHub bodies are mostly plain).
    func releaseNotes(maxLength: Int = 600) -> String? {
        guard let body = body?.trimmingCharacters(in: .whitespacesAndNewlines), !body.isEmpty else { return nil }
        guard body.count > maxLength else { return body }
        let end = body.index(body.startIndex, offsetBy: maxLength)
        return String(body[..<end]).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
}
