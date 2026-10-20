import Foundation
import AppKit

func selfTest() throws {
    func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw RenameError(message: message) }
    }
    if Bundle.main.bundlePath.hasSuffix(".app") {
        let bundled = Bundle.main.resourceURL!.appendingPathComponent("ExifTool/exiftool").path
        let resolved = try exiftoolPath()
        try check(resolved == bundled, "packaged App must use bundled ExifTool")
        print("Bundled ExifTool: \(resolved)")
    }
    try check(stamp("2024:02:29 23:59:59+09:00", source: "test")?.filename == "20240229_235959", "valid leap day / local wall time")
    try check(stamp("1900:01:01 12:00:00", source: "test") != nil, "historical photograph")
    try check(stamp("2023:02:29 12:00:00", source: "test") == nil, "invalid leap day")
    try check(stamp("0000:00:00 00:00:00", source: "test") == nil, "zero timestamp")
    try check(stamp("2025:13:01 12:00:00", source: "test") == nil, "invalid month")
    try check(stamp("2025:01:01 24:00:00", source: "test") == nil, "invalid hour")
    try check(chooseStamp(["ExifIFD:CreateDate":"2025:01:01 12:00:00"], fallback: false) == nil, "photo fallback opt in")
    try check(chooseStamp(["QuickTime:CreateDate":"2020:08:08 09:24:26"], fallback: false)?.filename == "20200808_172426", "video works with default options")
    try check(chooseStamp(["QuickTime:CreateDate":"0000:00:00 00:00:00"], fallback: false) == nil, "invalid video time skipped")
    try check(chooseStamp(["ExifIFD:DateTimeOriginal":"2024:01:01 12:00:00", "ExifIFD:CreateDate":"2025:01:01 12:00:00"], fallback: true)?.filename == "20240101_120000", "capture date priority")
    let videoMetadata: [String: Any] = ["QuickTime:CreateDate": "2020:08:08 09:24:26"]
    try check(chooseStamp(videoMetadata, fallback: true)?.filename == "20200808_172426", "DJI UTC to Taipei")
    try check(chooseStamp(videoMetadata, fallback: true, quickTimeUTC: false)?.filename == "20200808_092426", "UTC conversion disabled")
    try check(chooseStamp(videoMetadata, fallback: true, outputTimeZone: TimeZone(secondsFromGMT: 0)!)?.filename == "20200808_092426", "UTC output")
    try check(chooseStamp(["QuickTime:CreateDate": "2020:12:31 20:00:00"], fallback: true)?.filename == "20210101_040000", "year rollover")
    let ny = TimeZone(identifier: "America/New_York")!
    try check(chooseStamp(videoMetadata, fallback: true, outputTimeZone: ny)?.filename == "20200808_052426", "summer DST")
    try check(chooseStamp(["QuickTime:CreateDate": "2020:01:08 09:24:26"], fallback: true, outputTimeZone: ny)?.filename == "20200108_042426", "winter offset")
    try check(chooseStamp(["Keys:CreationDate": "2020:08:08 17:24:26+08:00"], fallback: false, outputTimeZone: ny)?.filename == "20200808_172426", "explicit offset not shifted twice")
    try check(chooseStamp(["ExifIFD:DateTimeOriginal": "2020:08:08 17:24:26"], fallback: false)?.filename == "20200808_172426", "EXIF preserved")
    try check(chooseStamp(["Track1:MediaCreateDate": "2020:08:08 09:24:26"], fallback: true)?.filename == "20200808_172426", "track UTC conversion")
    try check(chooseStamp(videoMetadata, fallback: true)?.display.contains("09:24:26 [按 UTC 解讀] → 2020-08-08 17:24:26 +08:00") == true, "visible conversion provenance")
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("photodate-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let photo = root.appendingPathComponent("A.jpg")
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8, bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    try bitmap.representation(using: .jpeg, properties: [:])!.write(to: photo)
    let writer = Process()
    writer.executableURL = URL(fileURLWithPath: try exiftoolPath())
    writer.arguments = ["-overwrite_original", "-DateTimeOriginal=2024:02:29 12:34:56", photo.path]
    writer.standardOutput = FileHandle.nullDevice
    try writer.run(); writer.waitUntilExit()
    try check(writer.terminationStatus == 0, "fixture metadata write")
    try FileManager.default.copyItem(at: photo, to: root.appendingPathComponent("B.jpg"))
    let child = root.appendingPathComponent("child")
    try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
    try FileManager.default.copyItem(at: photo, to: child.appendingPathComponent("C.jpg"))
    try bitmap.representation(using: .jpeg, properties: [:])!.write(to: root.appendingPathComponent("missing.jpg"))
    try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link.jpg"), withDestinationURL: photo)
    let plan = try scan(root, recursive: false, fallback: false)
    try check(plan.count == 3, "exclude subfolders and symlinks")
    try check(plan.filter(\.actionable).count == 2, "skip missing EXIF")
    try check(plan[0].destination?.lastPathComponent == "20240229_123456.jpg", "real EXIF read")
    try check(plan[1].destination?.lastPathComponent == "20240229_123456_1.jpg", "collision suffix")
    let recursivePlan = try scan(root, recursive: true, fallback: false)
    try check(recursivePlan.count == 4, "recursive scan")
    let photoLog = try apply(plan, root: root)
    let secondPlan = try scan(root, recursive: false, fallback: false)
    try check(secondPlan.filter(\.actionable).isEmpty, "second run stable")
    let restoredPhotos = try undo(photoLog)
    try check(restoredPhotos == 2, "real photo undo")
    let source = root.appendingPathComponent("original.jpg"), target = root.appendingPathComponent("20240101_120000.jpg")
    try Data("fixture".utf8).write(to: source)
    let identity = try Identity(source)
    let row = PlanRow(original: source, destination: target, identity: identity, date: "", source: "", status: "")
    let log = try apply([row], root: root)
    try check(FileManager.default.fileExists(atPath: target.path), "renamed")
    let restored = try undo(log)
    try check(restored == 1, "undo count")
    try check(tryIdentity(source) == identity, "preserved identity")
    let repeated = try undo(log); try check(repeated == 0, "idempotent undo")
    try Data("occupied".utf8).write(to: target)
    do { _ = try apply([row], root: root); throw RenameError(message: "overwrite allowed") }
    catch { try check(error.localizedDescription != "overwrite allowed", "collision rejected") }
    do { try moveExclusive(source, target); throw RenameError(message: "exclusive overwrite allowed") }
    catch { try check(error.localizedDescription != "exclusive overwrite allowed", "atomic collision rejected") }
    try FileManager.default.removeItem(at: target)
    let log2 = try apply([row], root: root)
    try Data("changed contents".utf8).write(to: target)
    do { _ = try undo(log2); throw RenameError(message: "changed file restored") }
    catch { try check(error.localizedDescription != "changed file restored", "modified file blocks undo") }
    let original2 = root.appendingPathComponent("pending.jpg"), destination2 = root.appendingPathComponent("pending-renamed.jpg")
    try Data("pending".utf8).write(to: original2)
    let pending = JournalEntry(original: original2, destination: destination2, identity: try Identity(original2))
    let log3 = root.appendingPathComponent("interrupted.json")
    try saveJournal(Journal(created: Date(), entries: [pending]), at: log3)
    let undone = try undo(log3); try check(undone == 0, "journal before rename survives interruption")
}
private func tryIdentity(_ url: URL) -> Identity? { try? Identity(url) }
