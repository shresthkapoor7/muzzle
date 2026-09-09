import Foundation

struct AppVersion: Comparable {
    private let components: [Int]

    init?(_ value: String) {
        let value = value.hasPrefix("v") ? String(value.dropFirst()) : value
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...3).contains(parts.count),
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isASCII && $0.isNumber }) }) else { return nil }
        let numbers = parts.compactMap { Int($0) }
        guard numbers.count == parts.count else { return nil }
        components = numbers + Array(repeating: 0, count: 3 - numbers.count)
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.components.lexicographicallyPrecedes(rhs.components)
    }
}

struct GitHubRelease: Decodable, Sendable {
    struct Asset: Decodable, Sendable {
        let name: String
        let browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    let tagName: String
    let htmlURL: URL
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case draft, prerelease, assets
    }

    func update(currentVersion: String, architecture: String) throws -> AvailableUpdate? {
        guard let current = AppVersion(currentVersion) else { throw UpdateError.invalidCurrentVersion }
        guard !draft, !prerelease else { return nil }
        guard let latest = AppVersion(tagName), Self.isRepositoryReleaseURL(htmlURL) else {
            throw UpdateError.invalidRelease
        }
        guard latest > current else { return nil }
        let version = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
        let names = ["Muzzle-\(version)-\(architecture).dmg", "Muzzle-v\(version)-\(architecture).dmg"]
        guard let asset = assets.first(where: {
            names.contains($0.name) && Self.isRepositoryReleaseURL($0.browserDownloadURL)
                && $0.browserDownloadURL.path.hasPrefix("/shresthkapoor7/muzzle/releases/download/")
        }) else { throw UpdateError.missingAsset }
        return AvailableUpdate(version: version, releaseURL: htmlURL, downloadURL: asset.browserDownloadURL)
    }

    private static func isRepositoryReleaseURL(_ url: URL) -> Bool {
        url.scheme == "https" && url.host == "github.com" && url.user == nil && url.password == nil
            && url.path.hasPrefix("/shresthkapoor7/muzzle/releases/")
    }
}

struct AvailableUpdate: Sendable {
    let version: String
    let releaseURL: URL
    let downloadURL: URL
}

enum UpdateError: LocalizedError {
    case invalidCurrentVersion, invalidRelease, missingAsset, http(Int)

    var errorDescription: String? {
        switch self {
        case .invalidCurrentVersion: "This build has no valid version number. Build the Muzzle app bundle before checking for updates."
        case .invalidRelease: "GitHub returned an invalid release. Try again later."
        case .missingAsset: "The latest release does not yet have a DMG for this Mac. Try again after release packaging finishes."
        case .http(let status): "GitHub update check failed (HTTP \(status)). Try again later."
        }
    }
}

struct UpdateChecker: Sendable {
    static let endpoint = URL(string: "https://api.github.com/repos/shresthkapoor7/muzzle/releases/latest")!
    static var architecture: String {
        #if arch(arm64)
        "arm64"
        #else
        "x86_64"
        #endif
    }

    func check(currentVersion: String, session: URLSession = .shared) async throws -> AvailableUpdate? {
        guard AppVersion(currentVersion) != nil else { throw UpdateError.invalidCurrentVersion }
        var request = URLRequest(url: Self.endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Muzzle/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        return try Self.decodeResponse(data: data, response: response, currentVersion: currentVersion)
    }

    static func decodeResponse(data: Data, response: URLResponse, currentVersion: String) throws -> AvailableUpdate? {
        guard let response = response as? HTTPURLResponse else { throw UpdateError.invalidRelease }
        if response.statusCode == 404 { return nil }
        guard response.statusCode == 200 else { throw UpdateError.http(response.statusCode) }
        return try JSONDecoder().decode(GitHubRelease.self, from: data)
            .update(currentVersion: currentVersion, architecture: Self.architecture)
    }
}
