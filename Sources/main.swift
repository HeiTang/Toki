import AppKit

let app = NSApplication.shared
if CommandLine.arguments.contains("--self-test") {
    do { try selfTest(); try p0UISelfTest(); try p0StatusContrastTest(); try p0EmptyPreviewTest(); print("All self-tests passed") }
    catch { fputs("Self-test failed: \(error)\n", stderr); exit(1) }
} else {
    // 僅供外觀驗收，正常啟動跟隨系統，不保存使用者偏好。
    if CommandLine.arguments.contains("--ui-test-light") { app.appearance = NSAppearance(named: .aqua) }
    if CommandLine.arguments.contains("--ui-test-dark") { app.appearance = NSAppearance(named: .darkAqua) }
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    withExtendedLifetime(delegate) { app.run() }
}
