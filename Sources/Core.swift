import Foundation
import Darwin

struct RenameError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
struct Stamp {
    let filename: String
    let display: String
    let source: String
}
let quickTimeIntegerTags: Set<String> = ["QuickTime:CreateDate", "Track1:MediaCreateDate", "Track1:TrackCreateDate"]

func stamp(_ raw: String, source: String, quickTimeUTC: Bool = false, outputTimeZone: TimeZone = TimeZone(identifier: "Asia/Taipei")!) -> Stamp? {
    let pattern = #"^(\d{4})[:-](\d{2})[:-](\d{2})[ T](\d{2}):(\d{2}):(\d{2})"#
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)) else { return nil }
    let parts = (1...6).compactMap { Range(match.range(at: $0), in: raw).flatMap { Int(raw[$0]) } }
    guard parts.count == 6, parts[0] > 0 else { return nil }
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(secondsFromGMT: 0)!
    let c = DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: parts[3], minute: parts[4], second: parts[5])
    guard let date = cal.date(from: c), cal.dateComponents([.year,.month,.day,.hour,.minute,.second], from: date) == c else { return nil }
    if quickTimeUTC && quickTimeIntegerTags.contains(source) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = cal
        formatter.timeZone = outputTimeZone
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let filename = formatter.string(from: date)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss XXX"
        return Stamp(filename: filename, display: "\(raw) [按 UTC 解讀] → \(formatter.string(from: date)) [\(outputTimeZone.identifier)]", source: source)
    }
    return Stamp(filename: String(format: "%04d%02d%02d_%02d%02d%02d", arguments: parts), display: raw, source: source)
}
let primaryTags = ["ExifIFD:DateTimeOriginal", "XMP-exif:DateTimeOriginal", "Keys:CreationDate", "UserData:DateTimeOriginal"]
let videoTags = ["QuickTime:CreateDate", "Track1:MediaCreateDate", "Track1:TrackCreateDate"]
let fallbackTags = ["ExifIFD:CreateDate", "XMP-xmp:CreateDate"]
func chooseStamp(_ metadata: [String: Any], fallback: Bool, quickTimeUTC: Bool = true, outputTimeZone: TimeZone = TimeZone(identifier: "Asia/Taipei")!) -> Stamp? {
    for key in primaryTags + videoTags + (fallback ? fallbackTags : []) {
        if let value = metadata[key] as? String, let result = stamp(value, source: key, quickTimeUTC: quickTimeUTC, outputTimeZone: outputTimeZone) { return result }
    }
    return nil
}
struct Identity: Codable, Equatable {
    let device: UInt64
    let inode: UInt64
    let size: UInt64
    let modified: Date
    init(_ url: URL) throws {
        let a = try FileManager.default.attributesOfItem(atPath: url.path)
        guard a[.type] as? FileAttributeType == .typeRegular else { throw RenameError(message: "不處理符號連結或非一般檔案：\(url.lastPathComponent)") }
        device = (a[.systemNumber] as! NSNumber).uint64Value
        inode = (a[.systemFileNumber] as! NSNumber).uint64Value
        size = (a[.size] as! NSNumber).uint64Value
        modified = a[.modificationDate] as! Date
    }
}
struct PlanRow {
    let original: URL
    let destination: URL?
    let identity: Identity?
    let date: String
    let source: String
    let status: String
    var sequence: Int = 0
    var actionable: Bool { destination != nil && destination != original }
}
let extensions: Set<String> = ["jpg","jpeg","heic","heif","png","tif","tiff","webp","gif","dng","raw","cr2","cr3","nef","arw","orf","rw2","raf","mov","mp4","m4v","avi","mkv"]
func exiftoolPath() throws -> String {
    if let resources = Bundle.main.resourceURL {
        let bundled = resources.appendingPathComponent("ExifTool/exiftool").path
        if FileManager.default.isExecutableFile(atPath: bundled) { return bundled }
    }
    // 開發時直接執行 Swift binary，仍可使用系統安裝的 ExifTool。
    if !Bundle.main.bundlePath.hasSuffix(".app") {
        for path in ["/opt/homebrew/bin/exiftool", "/usr/local/bin/exiftool", "/usr/bin/exiftool"] {
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
    }
    throw RenameError(message: "App 內的 ExifTool 遺失或無法執行，請重新下載並安裝 Toki。")
}
let defaultNamingRule = "{yyyy}{MM}{dd}_{HH}{mm}{ss}"
let namingTokens = ["yyyy", "MM", "dd", "HH", "mm", "ss", "name", "index"]
func validateNamingRule(_ rule: String) throws {
    guard !rule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, rule.utf8.count <= 200 else { throw RenameError(message: "命名規則不可空白，且最多 200 UTF-8 位元組。") }
    var remainder = rule
    for token in namingTokens { remainder = remainder.replacingOccurrences(of: "{\(token)}", with: "") }
    guard !remainder.contains("{"), !remainder.contains("}") else { throw RenameError(message: "有不支援或未閉合的變數。請使用列出的命名變數。") }
    guard !rule.hasPrefix("."), !rule.contains("/"), !rule.contains(":"), !rule.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw RenameError(message: "檔名不可由句點開頭，或包含 /、:、控制字元。") }
}
func namingStem(_ rule: String, timestamp: String, original: URL, index: Int) throws -> String {
    try validateNamingRule(rule)
    let digits = Array(timestamp.replacingOccurrences(of: "_", with: ""))
    guard digits.count == 14, digits.allSatisfy({ $0.isNumber }) else { throw RenameError(message: "拍攝日期無法用於命名。") }
    let values = ["yyyy": String(digits[0..<4]), "MM": String(digits[4..<6]), "dd": String(digits[6..<8]), "HH": String(digits[8..<10]), "mm": String(digits[10..<12]), "ss": String(digits[12..<14]), "name": original.deletingPathExtension().lastPathComponent, "index": String(format: "%04d", index)]
    let regex = try NSRegularExpression(pattern: #"\{(yyyy|MM|dd|HH|mm|ss|name|index)\}"#)
    var result = rule
    for match in regex.matches(in: rule, range: NSRange(rule.startIndex..., in: rule)).reversed() {
        let key = String(rule[Range(match.range(at: 1), in: rule)!])
        result.replaceSubrange(Range(match.range, in: result)!, with: values[key]!)
    }
    guard !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !result.hasPrefix("."), !result.contains("/"), !result.contains(":"), !result.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw RenameError(message: "命名結果不可空白、以句點開頭，或包含 /、:、控制字元。") }
    return result
}
func validateImportSources(_ inputs: [URL]) throws -> [URL] {
    guard !inputs.isEmpty else { throw RenameError(message: "請加入照片、影片或資料夾。") }
    var result = Set<URL>()
    for input in inputs {
        guard input.isFileURL else { throw RenameError(message: "僅支援本機檔案與資料夾。") }
        let url = input.standardizedFileURL
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .isPackageKey])
        guard values.isSymbolicLink != true, values.isPackage != true,
              values.isDirectory == true || (values.isRegularFile == true && extensions.contains(url.pathExtension.lowercased())) else { throw RenameError(message: "不支援此項目或符號連結：\(url.lastPathComponent)") }
        result.insert(url.resolvingSymlinksInPath().standardizedFileURL)
    }
    return result.sorted { $0.path < $1.path }
}
func collectImportFiles(_ inputs: [URL], recursive: Bool) throws -> [URL] {
    let fm = FileManager.default
    var files = Set<URL>()
    let options: FileManager.DirectoryEnumerationOptions = recursive ? [.skipsHiddenFiles, .skipsPackageDescendants] : [.skipsHiddenFiles, .skipsPackageDescendants, .skipsSubdirectoryDescendants]
    for url in try validateImportSources(inputs) {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey])
        if values.isDirectory != true { files.insert(url); continue }
        var enumerationError: Error?
        guard let iterator = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: options, errorHandler: { _, error in enumerationError = error; return false }) else { throw RenameError(message: "無法讀取資料夾：\(url.lastPathComponent)") }
        for case let file as URL in iterator {
            if file.lastPathComponent == "original_backup" { iterator.skipDescendants(); continue }
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if values.isRegularFile == true && values.isSymbolicLink != true && extensions.contains(file.pathExtension.lowercased()) { files.insert(file.standardizedFileURL) }
        }
        if let error = enumerationError { throw error }
    }
    return files.sorted { $0.path < $1.path }
}
func scan(_ root: URL, recursive: Bool, fallback: Bool, quickTimeUTC: Bool = true, outputTimeZone: TimeZone = TimeZone(identifier: "Asia/Taipei")!) throws -> [PlanRow] {
    try scan([root], recursive: recursive, fallback: fallback, quickTimeUTC: quickTimeUTC, outputTimeZone: outputTimeZone)
}
func scan(_ inputs: [URL], recursive: Bool, fallback: Bool, quickTimeUTC: Bool = true, outputTimeZone: TimeZone = TimeZone(identifier: "Asia/Taipei")!, namingRule: String = defaultNamingRule, sequenceNumbers: [URL: Int] = [:]) throws -> [PlanRow] {
    try validateNamingRule(namingRule)
    let tool = try exiftoolPath()
    let fm = FileManager.default
    let files = try collectImportFiles(inputs, recursive: recursive)
    var reserved = Set<String>()
    var rows: [PlanRow] = []
    var namingIndex = sequenceNumbers.values.max() ?? 0
    for url in files {
        var naming = false
        do {
            let identity = try Identity(url)
            let task = Process(), pipe = Pipe()
            task.executableURL = URL(fileURLWithPath: tool)
            task.arguments = ["-j", "-G1", "-s", "-api", "QuickTimeUTC=0", "-DateTimeOriginal", "-CreateDate", "-CreationDate", "-MediaCreateDate", "-TrackCreateDate", "--", url.path]
            task.standardOutput = pipe
            task.standardError = FileHandle.nullDevice
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            guard task.terminationStatus == 0, let metadata = (try JSONSerialization.jsonObject(with: data) as? [[String: Any]])?.first else { throw RenameError(message: "中繼資料讀取失敗") }
            guard try Identity(url) == identity else { throw RenameError(message: "掃描期間檔案已變更") }
            guard let date = chooseStamp(metadata, fallback: fallback, quickTimeUTC: quickTimeUTC, outputTimeZone: outputTimeZone) else {
                rows.append(PlanRow(original: url, destination: nil, identity: identity, date: "—", source: "—", status: "跳過：無有效時間欄位")); continue
            }
            naming = true
            let sequence: Int
            if let known = sequenceNumbers[url] { sequence = known } else { namingIndex += 1; sequence = namingIndex }
            let stem = try namingStem(namingRule, timestamp: date.filename, original: url, index: sequence)
            var index = 0
            var target: URL
            repeat {
                let suffix = index == 0 ? "" : "_\(index)"
                let filename = stem + suffix + "." + url.pathExtension
                guard filename.utf8.count <= 255 else { throw RenameError(message: "新檔名過長，含副檔名與序號最多 255 UTF-8 位元組。") }
                target = url.deletingLastPathComponent().appendingPathComponent(filename)
                index += 1
            } while reserved.contains(target.path.lowercased()) || (target != url && fm.fileExists(atPath: target.path))
            reserved.insert(target.path.lowercased())
            let warning = videoTags.contains(date.source) ? "影片建立時間，請核對" : (fallbackTags.contains(date.source) ? "備用時間，請核對" : "可重新命名")
            rows.append(PlanRow(original: url, destination: target, identity: identity, date: date.display, source: date.source, status: target == url ? "檔名已符合" : (index > 1 && warning == "可重新命名" ? "同名已加序號" : warning), sequence: sequence))
        } catch {
            rows.append(PlanRow(original: url, destination: nil, identity: nil, date: "—", source: "—", status: "\(naming ? "命名錯誤" : "錯誤")：\(error.localizedDescription)"))
        }
    }
    return rows
}
struct JournalEntry: Codable {
    let original: URL
    let destination: URL
    let identity: Identity
}
struct Journal: Codable {
    let created: Date
    let entries: [JournalEntry]
}
func saveJournal(_ journal: Journal, at url: URL) throws {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(journal).write(to: url, options: .atomic)
}
func moveExclusive(_ from: URL, _ to: URL) throws {
    let result = from.path.withCString { src in to.path.withCString { dst in renamex_np(src, dst, UInt32(RENAME_EXCL)) } }
    if result != 0 { throw RenameError(message: "\(from.lastPathComponent)：\(String(cString: strerror(errno)))") }
}
func apply(_ rows: [PlanRow], root: URL) throws -> URL {
    let entries = rows.filter(\.actionable).map { JournalEntry(original: $0.original, destination: $0.destination!, identity: $0.identity!) }
    guard !entries.isEmpty else { throw RenameError(message: "沒有可重新命名的檔案") }
    for entry in entries {
        guard try Identity(entry.original) == entry.identity else { throw RenameError(message: "檔案已變更，請重新掃描：\(entry.original.lastPathComponent)") }
        guard !FileManager.default.fileExists(atPath: entry.destination.path) else { throw RenameError(message: "目的檔名已存在，請重新掃描") }
    }
    let log = root.appendingPathComponent(".photodate-\(UUID().uuidString).json")
    try saveJournal(Journal(created: Date(), entries: entries), at: log)
    do {
        for entry in entries {
            guard try Identity(entry.original) == entry.identity else { throw RenameError(message: "執行期間檔案已變更") }
            try moveExclusive(entry.original, entry.destination)
        }
    } catch {
        throw RenameError(message: "部分操作可能已完成。請使用「復原紀錄」選擇 \(log.path) 復原。\n\(error.localizedDescription)")
    }
    return log
}
func undo(_ log: URL) throws -> Int {
    let journal = try JSONDecoder().decode(Journal.self, from: Data(contentsOf: log))
    var pending: [JournalEntry] = []
    for entry in journal.entries.reversed() {
        guard entry.original.isFileURL, entry.destination.isFileURL,
              entry.original.deletingLastPathComponent() == entry.destination.deletingLastPathComponent() else { throw RenameError(message: "紀錄包含不合法路徑") }
        if (try? Identity(entry.original)) == entry.identity { continue }
        guard !FileManager.default.fileExists(atPath: entry.original.path), (try? Identity(entry.destination)) == entry.identity else { throw RenameError(message: "無法安全復原：\(entry.destination.lastPathComponent) 已變更、遺失，或原檔名已被占用。") }
        pending.append(entry)
    }
    for entry in pending {
        guard try Identity(entry.destination) == entry.identity else { throw RenameError(message: "復原期間檔案已變更") }
        try moveExclusive(entry.destination, entry.original)
    }
    return pending.count
}
