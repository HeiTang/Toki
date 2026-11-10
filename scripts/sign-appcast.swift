import CryptoKit
import Foundation

struct AppcastError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

func writeAppcast() throws {
    let arguments = CommandLine.arguments
    guard arguments.count == 3,
          let url = URLComponents(string: arguments[2]),
          let host = url.host, !host.isEmpty,
          url.scheme == "https" || (url.scheme == "http" && host == "localhost"),
          url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
          let archiveURL = url.url, archiveURL.lastPathComponent == "Toki-macos-arm64.zip" else {
        throw AppcastError("Usage: swift scripts/sign-appcast.swift DIST_DIR ZIP_URL")
    }
    let dist = URL(fileURLWithPath: arguments[1], isDirectory: true)
    let info = try Data(contentsOf: dist.appendingPathComponent("Toki.app/Contents/Info.plist"))
    guard let plist = try PropertyListSerialization.propertyList(from: info, format: nil) as? [String: Any],
          let version = plist["CFBundleShortVersionString"] as? String,
          version.range(of: #"\A[0-9]+\.[0-9]+\.[0-9]+\z"#, options: .regularExpression) != nil,
          let build = plist["CFBundleVersion"] as? String,
          build.range(of: #"\A[1-9][0-9]*\z"#, options: .regularExpression) != nil,
          let minimum = plist["LSMinimumSystemVersion"] as? String,
          minimum.range(of: #"\A[0-9]+\.[0-9]+(\.[0-9]+)?\z"#, options: .regularExpression) != nil,
          let publicKey = plist["SUPublicEDKey"] as? String else {
        throw AppcastError("Packaged App requires valid version, build, minimum macOS and SUPublicEDKey")
    }
    guard let secret = ProcessInfo.processInfo.environment["TOKI_SPARKLE_PRIVATE_KEY"],
          let seed = Data(base64Encoded: secret.trimmingCharacters(in: .whitespacesAndNewlines)),
          seed.count == 32 else {
        throw AppcastError("TOKI_SPARKLE_PRIVATE_KEY must contain a base64 Ed25519 seed")
    }
    let key = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
    guard key.publicKey.rawRepresentation.base64EncodedString() == publicKey else {
        throw AppcastError("Signing key does not match the public key in the packaged App")
    }
    let archive = try Data(contentsOf: dist.appendingPathComponent(archiveURL.lastPathComponent))
    let signature = try key.signature(for: archive).base64EncodedString()
    let minimumVersion = minimum.split(separator: ".").count == 2 ? minimum + ".0" : minimum
    let escapedURL = archiveURL.absoluteString.replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "\"", with: "&quot;")
    let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
          <channel>
            <title>Toki</title>
            <item>
              <title>Toki \(version)</title>
              <sparkle:version>\(build)</sparkle:version>
              <sparkle:shortVersionString>\(version)</sparkle:shortVersionString>
              <sparkle:minimumSystemVersion>\(minimumVersion)</sparkle:minimumSystemVersion>
              <sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>
              <enclosure url="\(escapedURL)" length="\(archive.count)" sparkle:edSignature="\(signature)" type="application/octet-stream" />
            </item>
          </channel>
        </rss>
        """
    try Data(xml.utf8).write(to: dist.appendingPathComponent("appcast.xml"), options: .atomic)
}

do { try writeAppcast() }
catch {
    FileHandle.standardError.write(Data(("Appcast: " + error.localizedDescription + "\n").utf8))
    exit(1)
}
