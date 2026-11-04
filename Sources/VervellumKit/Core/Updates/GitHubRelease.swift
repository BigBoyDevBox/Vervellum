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
    /// Platform dominates: naming this OS scores +8, naming a *different* OS scores
    /// -8, and saying nothing scores 0 — an explicitly foreign name has to lose to a
    /// token-less one for this machine, because without the penalty its architecture
    /// token alone (+4) would outrank an unlabelled build (0), and the updater would
    /// download an archive it cannot install. Within the right platform an exact
    /// architecture is +4 and a universal build is +2. A `.dmg`/`.pkg` counts as a
    /// macOS name and a `.deb`/`.rpm`/`.AppImage` as a Linux one, so the extension
    /// still helps when a release names its artifacts by type rather than by platform.
    static func assetAffinity(_ name: String) -> Int {
        let lowered = name.lowercased()
        var score = 0
        // A token beginning with "." is a file extension, so it only matches at the
        // end of the name; every other token is a substring anywhere.
        func matches(_ token: String) -> Bool {
            token.hasPrefix(".") ? lowered.hasSuffix(token) : lowered.contains(token)
        }
        #if os(macOS)
        let platformTokens = ["macos", "osx", "darwin", ".dmg", ".pkg"]
        let otherPlatformTokens = [
            "linux", ".deb", ".rpm", ".appimage",
            "windows", "win32", "win64", ".exe", ".msi",
        ]
        #elseif os(Linux)
        let platformTokens = ["linux", ".deb", ".rpm", ".appimage"]
        let otherPlatformTokens = [
            "mac", "macos", "darwin", "osx", ".dmg", ".pkg",
            "windows", "win32", "win64", ".exe", ".msi",
        ]
        #else
        // Unknown platforms recognise no tokens either way; only the generic
        // architecture scoring below applies.
        let platformTokens: [String] = []
        let otherPlatformTokens: [String] = []
        #endif
        if platformTokens.contains(where: matches) {
            score += 8
        } else if otherPlatformTokens.contains(where: matches) {
            score -= 8
        }
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
