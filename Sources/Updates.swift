import Foundation

struct TokiRelease: Decodable {
    let tag: String

    enum CodingKeys: String, CodingKey { case tag = "tag_name" }

    var downloadPage: URL {
        URL(string: "https://github.com/HeiTang/Toki/releases/tag")!.appendingPathComponent(tag)
    }

    static func latest(after installedVersion: String) async throws -> TokiRelease? {
        let url = URL(string: "https://api.github.com/repos/HeiTang/Toki/releases/latest")!
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try newerRelease(from: data, than: installedVersion)
    }

    static func newerRelease(from data: Data, than installedVersion: String) throws -> TokiRelease? {
        let release = try JSONDecoder().decode(TokiRelease.self, from: data)
        let version = String(release.tag.dropFirst())
        let format = #"\A[0-9]+\.[0-9]+\.[0-9]+\z"#
        guard release.tag.hasPrefix("v"),
              version.range(of: format, options: .regularExpression) != nil,
              installedVersion.range(of: format, options: .regularExpression) != nil else {
            throw URLError(.cannotParseResponse)
        }
        return version.compare(installedVersion, options: .numeric) == .orderedDescending ? release : nil
    }
}
