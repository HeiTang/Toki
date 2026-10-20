import AppKit

func importAndNamingTests() throws {
    func check(_ ok: @autoclosure () throws -> Bool, _ message: String) throws {
        if try !ok() { throw RenameError(message: "Import/naming: " + message) }
    }
    func rejects(_ message: String, _ operation: () throws -> Void) throws {
        var rejected = false
        do { try operation() } catch { rejected = true }
        try check(rejected, message)
    }
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("photodate-features-" + UUID().uuidString)
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }
    let folder = root.appendingPathComponent("照片"), other = root.appendingPathComponent("其他")
    try fm.createDirectory(at: folder, withIntermediateDirectories: true)
    try fm.createDirectory(at: other, withIntermediateDirectories: true)
    let photo = folder.appendingPathComponent("原始_{index}.jpg")
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8, bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    try bitmap.representation(using: .jpeg, properties: [:])!.write(to: photo)
    let task = Process(); task.executableURL = URL(fileURLWithPath: try exiftoolPath())
    task.arguments = ["-overwrite_original", "-DateTimeOriginal=2024:02:29 12:34:56", photo.path]
    task.standardOutput = FileHandle.nullDevice; try task.run(); task.waitUntilExit()
    try check(task.terminationStatus == 0, "fixture metadata")
    let second = other.appendingPathComponent("B.JPG"); try fm.copyItem(at: photo, to: second)
    let child = folder.appendingPathComponent("child"); try fm.createDirectory(at: child, withIntermediateDirectories: true)
    let third = child.appendingPathComponent("C.jpg"); try fm.copyItem(at: photo, to: third)
    let missing = folder.appendingPathComponent("無日期.jpg"); try bitmap.representation(using: .jpeg, properties: [:])!.write(to: missing)
    let symlink = root.appendingPathComponent("link.jpg"); try fm.createSymbolicLink(at: symlink, withDestinationURL: photo)
    try check(try collectImportFiles([folder, photo, folder, second], recursive: false).count == 3, "mixed sources deduplicate without importing siblings")
    try check(try collectImportFiles([folder, child, photo], recursive: true).count == 3, "overlapping recursive folders deduplicate")
    try check(try validateImportSources([photo, photo.resolvingSymlinksInPath()]).count == 1, "alternate parent paths do not import the same file twice")
    try rejects("reject symbolic links") { _ = try validateImportSources([symlink]) }
    try rejects("reject remote URLs") { _ = try validateImportSources([URL(string: "https://example.com/a.jpg")!]) }
    let unsupported = root.appendingPathComponent("notes.txt"); try Data().write(to: unsupported)
    try rejects("mixed invalid input is explicit, not silently ignored") { _ = try validateImportSources([photo, unsupported]) }
    let stamp = "20240229_123456"
    try check(try namingStem(defaultNamingRule, timestamp: stamp, original: photo, index: 1) == stamp, "default matches previous version")
    try check(try namingStem("旅行_{yyyy}-{MM}-{dd}_{HH}-{mm}-{ss}_{name}_{index}", timestamp: stamp, original: photo, index: 12) == "旅行_2024-02-29_12-34-56_原始_{index}_0012", "tokens and literal braces in original names are not recursively substituted")
    for rule in ["", "  ", "{unknown}", "{yyyy", "../{name}", "A/B", "A:B", ".hidden", "A\nB"] { try rejects("invalid template " + rule) { try validateNamingRule(rule) } }
    let plan = try scan([folder, photo, second], recursive: false, fallback: false, namingRule: "旅行_{yyyy}-{MM}-{dd}_{index}")
    try check(plan.count == 3 && plan.filter(\.actionable).count == 2, "only selected inputs and valid dates become candidates")
    try check(plan.filter(\.actionable).allSatisfy { $0.original.deletingLastPathComponent() == $0.destination!.deletingLastPathComponent() }, "custom names never move folders")
    let bytes = try Data(contentsOf: photo), secondBytes = try Data(contentsOf: second)
    let log = try apply(plan, root: folder)
    try check(plan.filter(\.actionable).allSatisfy { fm.fileExists(atPath: $0.destination!.path) }, "multi-directory rename uses existing apply")
    let completed = plan.filter(\.actionable)
    let sequenceMap = Dictionary(uniqueKeysWithValues: completed.map { ($0.destination!, $0.sequence) })
    let rescan = try scan(completed.map { $0.destination! }, recursive: false, fallback: false, namingRule: "旅行_{yyyy}-{MM}-{dd}_{index}", sequenceNumbers: sequenceMap)
    try check(rescan.allSatisfy { !$0.actionable }, "batch sequence stays stable after rename and rescan")
    try check(try undo(log) == 2 && Data(contentsOf: photo) == bytes && Data(contentsOf: second) == secondBytes, "existing journal restores all directories with content unchanged")
    let occupied = folder.appendingPathComponent("旅行.jpg"); try bytes.write(to: occupied)
    let collision = try scan([photo], recursive: false, fallback: false, namingRule: "旅行")
    try check(collision[0].destination?.lastPathComponent == "旅行_1.jpg" && collision[0].status == "同名已加序號", "custom collision suffix is explicit")
    let long = folder.appendingPathComponent(String(repeating: "照", count: 70) + ".jpg"); try bytes.write(to: long)
    let invalidPlan = try scan([long], recursive: false, fallback: false, namingRule: "旅行旅行旅行旅行旅行旅行旅行旅行旅行旅行_{name}")
    try check(invalidPlan[0].destination == nil && invalidPlan[0].status.hasPrefix("命名錯誤"), "oversized output cannot execute or masquerade as metadata error")
    let pasteboard = NSPasteboard(name: .init("PhotoDateDropTest-" + UUID().uuidString)); defer { pasteboard.releaseGlobally() }
    pasteboard.writeObjects([photo as NSURL, second as NSURL])
    let drop = DropImportView(frame: .zero)
    try check(Set(drop.importURLs(from: pasteboard)) == Set([photo, second]), "external file URL pasteboard parsing")
    var dropped: [URL] = []; drop.onImport = { dropped = $0 }; drop.canImport = { false }
    try check(!drop.acceptDrop(from: pasteboard) && dropped.isEmpty, "busy or modal destination rejects drop without replacing the batch")
    drop.canImport = { true }
    try check(drop.acceptDrop(from: pasteboard) && Set(dropped) == Set([photo, second].map { $0.resolvingSymlinksInPath().standardizedFileURL }), "valid external drop reaches the import callback")
    pasteboard.clearContents(); pasteboard.writeObjects([unsupported as NSURL]); dropped = []
    try check(!drop.acceptDrop(from: pasteboard) && dropped.isEmpty, "unsupported drop never reaches import")
    let ui = AppDelegate(); ui.buildInterface(); defer { ui.window.delegate = nil; ui.window.close() }
    ui.rows = collision; ui.root = folder; ui.rebuildVisibleRows()
    try check(ui.needsAttention(collision[0]) && ui.displayStatus(collision[0]) == "同名已加序號", "custom suffix reaches attention filter")
    ui.namingField.stringValue = "{bad}"; ui.updateNamingSample(); try check(!ui.settingsApply.isEnabled, "invalid rule disables apply")
    ui.namingField.stringValue = "旅行_{yyyy}-{MM}-{dd}_{index}"; ui.updateNamingSample(); try check(ui.settingsApply.isEnabled && ui.namingSample.stringValue.contains("旅行_2024-02-29_0001.jpg"), "valid rule shows an honest sample")
    let preferences = ui.makeSettingsPanel()
    try check(ui.settingsTabs.numberOfTabViewItems == 2 && ui.settingsTabs.tabViewItems[1].label == "命名", "naming belongs inside settings")
    try check(ui.settingsTabs.tabViewType == .noTabsNoBorder, "settings has no redundant framed tab container")
    ui.namingField.stringValue = "旅行_"
    let tokenButton = NSButton(); tokenButton.tag = 0; ui.insertNamingToken(tokenButton)
    try check(ui.namingField.stringValue == "旅行_{yyyy}", "token button inserts supported variable")
    ui.namingField.stringValue = "{bad}"; ui.updateNamingSample()
    try check(!ui.namingError.isHidden && !ui.settingsApply.isEnabled, "invalid format shows inline error")
    ui.resetNaming(); try check(ui.namingError.isHidden && ui.settingsApply.isEnabled, "reset clears format error")
    preferences.close()
    print("Import and naming tests passed")
}
