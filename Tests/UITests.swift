import AppKit

func p0UISelfTest() throws {
    func check(_ value: @autoclosure () -> Bool, _ message: String) throws {
        if !value() { throw RenameError(message: "P0 UI: \(message)") }
    }
    let app = AppDelegate()
    app.buildInterface()
    defer { app.window.delegate = nil; app.window.close() }
    try check(!app.commandEnabled(#selector(AppDelegate.renameCurrent)), "empty state cannot rename")
    try check(!app.commandEnabled(#selector(AppDelegate.exportCSV)), "empty state cannot export")
    try check(app.commandEnabled(#selector(AppDelegate.restoreLog)), "journal picker remains available without folder")
    try check(app.locationRow.isHidden && app.footerRow.isHidden && app.inspector.isHidden && app.split.isHidden, "empty state has no folder strip, footer or inspector")
    try check(app.window.subtitle.isEmpty && app.status.stringValue.isEmpty, "empty state has no version or capability boilerplate")
    app.toggleInspector()
    try check(app.inspector.isHidden && !app.commandEnabled(#selector(AppDelegate.toggleInspector)), "inspector cannot distract from empty state")
    let root = URL(fileURLWithPath: "/tmp/photodate-p0-ui-test")
    let a = root.appendingPathComponent("A.jpg"), b = root.appendingPathComponent("B.jpg")
    let missing = root.appendingPathComponent("missing.png")
    try check(app.scope.superview === app.actionRow && app.renameButton.superview === app.actionRow, "scope and rename share the action row")
    app.root = root
    app.rows = [
        PlanRow(original: a, destination: root.appendingPathComponent("20240101_120000.jpg"), identity: nil,
                date: "2024:01:01 12:00:00", source: "ExifIFD:DateTimeOriginal", status: "可重新命名"),
        PlanRow(original: b, destination: root.appendingPathComponent("20240101_120000_1.jpg"), identity: nil,
                date: "2024:01:01 12:00:00", source: "ExifIFD:DateTimeOriginal", status: "可重新命名"),
        PlanRow(original: missing, destination: nil, identity: nil, date: "—", source: "—", status: "跳過：無有效時間欄位")
    ]
    app.updateLocation(root)
    try check(app.locationButton.menu?.items.contains(where: { $0.title == root.lastPathComponent }) == true && app.locationButton.toolTip == root.path, "expanded location preserves selected folder and full path")
    app.rebuildVisibleRows()
    try check(!app.locationRow.isHidden && !app.footerRow.isHidden && !app.inspector.isHidden && !app.split.isHidden, "import restores context and inspector")
    try check(app.displayStatus(app.rows[1]) == "同名已加序號", "collision suffix is visible without changing the plan")
    try check(app.renameButton.title == "重新命名…" && app.candidateLabel.stringValue == "本次更名 2 個檔案", "stable action label and complete count")
    try check(!app.table.usesAlternatingRowBackgroundColors, "empty table area has no repeated stripes")
    try check(app.status.stringValue == "顯示 3 / 3 個檔案", "footer reports visibility without duplicate execution counts")
    try check(app.attentionLabel.stringValue == "2 個檔案需檢查", "attention count includes collision suffix and missing date")
    try check(app.heading.superview === app.summary.superview, "preview title and summary share the left header group")
    try check(app.attentionRow.arrangedSubviews.first is NSBox && !app.attentionExplanation.stringValue.isEmpty, "attention banner groups the count and explanation")
    let oldCell = app.tableView(app.table, viewFor: app.table.tableColumns[0], row: 0) as! PreviewCellView
    let newCell = app.tableView(app.table, viewFor: app.table.tableColumns[1], row: 0) as! PreviewCellView
    let statusCell = app.tableView(app.table, viewFor: app.table.tableColumns[2], row: 0) as! PreviewCellView
    try check(oldCell.imageView?.image != nil && newCell.imageView?.image == nil && statusCell.imageView?.image != nil, "filename and status symbols are decorative and new names remain plain")
    try check(newCell.textField!.font!.isFixedPitch, "new filenames use a monospaced system font")
    let rowView = app.tableView(app.table, rowViewForRow: 1)!
    try check((rowView as? PreviewRowView)?.alternate == true, "alternating background belongs to actual rows only")
    app.filter.selectedSegment = 2; app.rows = [app.rows[2]]; app.rebuildVisibleRows()
    try check(!app.tableEmptyLabel.isHidden && !app.tableScroll.isHidden, "empty filter retains headers and an explicit empty message")
    app.window.contentView?.layoutSubtreeIfNeeded()
    let emptyRect = app.tableEmptyLabel.convert(app.tableEmptyLabel.bounds, to: app.tableContainer)
    try check(abs(emptyRect.midY - app.tableContainer.bounds.midY) < 1 && emptyRect.minY > 24, "empty-filter message sits in the table body, away from the headers")
    app.rows = [PlanRow(original: a, destination: root.appendingPathComponent("20240101_120000.jpg"), identity: nil, date: "2024:01:01 12:00:00", source: "ExifIFD:DateTimeOriginal", status: "可重新命名"), PlanRow(original: b, destination: root.appendingPathComponent("20240101_120000_1.jpg"), identity: nil, date: "2024:01:01 12:00:00", source: "ExifIFD:DateTimeOriginal", status: "可重新命名"), PlanRow(original: missing, destination: nil, identity: nil, date: "—", source: "—", status: "跳過：無有效時間欄位")]
    app.filter.selectedSegment = 0; app.rebuildVisibleRows()
    try check(app.tableEmptyLabel.isHidden, "empty-filter overlay clears after changing the filter")
    let conforming = PlanRow(original: a, destination: a, identity: nil, date: "2024:01:01 12:00:00", source: "ExifIFD:DateTimeOriginal", status: "檔名已符合")
    try check(!app.needsAttention(conforming), "already matching filenames are not warnings")
    app.table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
    for _ in 0..<6 { app.increasePreviewText() }
    try check(app.table.selectedRowIndexes == IndexSet(integer: 0) && app.selectedURLs == Set([a]), "text enlargement preserves visible selection and batch scope")
    try check(app.previewTextScale == 2 && app.candidates.count == 2 && app.settings == ScanSettings(), "preview scaling is bounded and does not alter the rename plan")
    app.selectedURLs = [a]; app.updateDetail()
    try check(app.fileNameLabel.font!.pointSize == 26 && app.timeLabel.font!.pointSize == 26 && app.table.rowHeight >= 42, "preview and inspector text enlarge to 200 percent")
    if let cell = app.tableView(app.table, viewFor: app.table.tableColumns.first, row: 0) as? PreviewCellView {
        cell.frame = NSRect(x: 0, y: 0, width: 180, height: app.table.rowHeight); cell.layoutSubtreeIfNeeded()
        try check(cell.textField!.font!.pointSize == 26 && abs(cell.textField!.frame.midY - cell.bounds.midY) < 0.5, "enlarged table text remains centered")
        try check(cell.imageView!.frame.maxX < cell.textField!.frame.minX && abs(cell.imageView!.frame.midY - cell.bounds.midY) < 0.5, "decorative icon stays centered without overlapping enlarged text")
    }
    app.resetPreviewText(); app.clearSelection()
    try check(app.previewTextScale == 1 && app.table.rowHeight == 38, "reset restores original text and row size")
    app.window.setFrame(NSRect(origin: app.window.frame.origin, size: NSSize(width: 960, height: 640)), display: false)
    app.fitPreviewColumns()
    try check(app.window.frame.size == NSSize(width: 960, height: 640), "preview honors the actual minimum window frame")
    let contentBounds = app.window.contentView!.bounds
    for view in [app.locationRow!, app.attentionRow!, app.tableContainer, app.footerRow!, app.actionRow!] as [NSView] {
        let rect = view.convert(view.bounds, to: app.window.contentView!)
        try check(contentBounds.contains(rect), "minimum window keeps preview controls within the content area")
    }
    let panel = app.makeSettingsPanel()
    panel.contentView?.layoutSubtreeIfNeeded()
    try check(panel.contentView!.bounds.width == 540 && panel.contentView!.bounds.height == 560, "settings have explicit usable dimensions")
    for control in [app.recursive, app.fallback, app.quickTimeUTC, app.outputTimeZone, app.settingsApply] as [NSView] {
        let rect = control.convert(control.bounds, to: panel.contentView!)
        try check(rect.width > 0 && rect.height > 0 && panel.contentView!.bounds.contains(rect), "settings controls fit within the sheet")
    }
    let scanBox = app.recursive.superview?.superview?.superview as? NSBox
    let timeBox = app.quickTimeUTC.superview?.superview?.superview as? NSBox
    try check(scanBox != nil && timeBox != nil && scanBox !== timeBox, "settings use distinct scan and time groups")
    try check(app.fallback.accessibilityLabel() == "使用照片備用時間（需核對）" && app.fallback.accessibilityHelp()?.contains("需核對") == true, "fallback warning remains associated with its checkbox")
    let utcRect = app.quickTimeUTC.convert(app.quickTimeUTC.bounds, to: panel.contentView!)
    let zoneRect = app.outputTimeZone.convert(app.outputTimeZone.bounds, to: panel.contentView!)
    try check(zoneRect.maxY < utcRect.minY && zoneRect.width < timeBox!.bounds.width, "time-zone control sits below UTC inside its group")
    app.quickTimeUTC.state = .off; app.updateTimeZoneControl()
    try check(!app.outputTimeZone.isEnabled, "raw QuickTime mode disables time-zone conversion")
    panel.close()
    app.updateLocation(root.appendingPathComponent(String(repeating: "長路徑資料夾/", count: 12)))
    for size in [NSSize(width: 960, height: 640), NSSize(width: 1180, height: 760)] {
        app.window.setContentSize(size); app.fitPreviewColumns()
        try check(app.table.tableColumns.reduce(0) { $0 + $1.width } <= app.tableScroll.contentSize.width + 1, "all preview columns fit the available width")
        try check(app.locationButton.alignmentRect(forFrame: app.locationButton.frame).width == 260 && app.locationButton.pullsDown, "location is compact and expands on demand")
        let locationRect = app.window.contentView!.convert(app.locationRow.alignmentRect(forFrame: app.locationRow.frame), from: app.locationRow.superview)
        let headingRect = app.window.contentView!.convert(app.heading.alignmentRect(forFrame: app.heading.frame), from: app.heading.superview)
        try check(abs(locationRect.minX - headingRect.minX) < 0.5, "location and preview use the same leading inset")
        try check(app.locationLabel.stringValue == "所在位置", "folder name is not duplicated in the content header")
        if let cell = app.tableView(app.table, viewFor: app.table.tableColumns.first, row: 0) as? PreviewCellView {
            let host = NSView(frame: NSRect(x: 0, y: 0, width: 180, height: 38)); host.addSubview(cell)
            cell.frame = host.bounds; host.layoutSubtreeIfNeeded()

            try check(abs(cell.textField!.frame.midY - cell.bounds.midY) < 0.5 && cell.textField!.frame.minX == 34, "table cell centers text and uses shared inset")
        } else { throw RenameError(message: "missing reusable table cell") }
    }
    app.table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
    app.window.contentView?.layoutSubtreeIfNeeded()
    try check(app.window.toolbar?.items.contains(where: { $0.itemIdentifier.rawValue == "settings" && $0.action == #selector(AppDelegate.showSettings) }) == true, "scan settings have a toolbar entry")
    try check(app.detail.isHidden && !app.technicalRow.isHidden, "technical details are collapsed by default")
    try check(app.fileNameLabel.stringValue == "A.jpg" && app.sourceLabel.stringValue == "EXIF 拍攝時間", "inspector shows file and readable source")
    app.technicalToggle.state = .on; app.toggleTechnicalDetails()
    try check(!app.detail.isHidden && app.detail.stringValue.contains("ExifIFD:DateTimeOriginal"), "disclosure preserves raw metadata")
    app.technicalToggle.state = .off; app.toggleTechnicalDetails()
    app.selectedURLs = [a, b]; app.updateDetail()
    try check(app.fileNameLabel.toolTip == nil, "multi-selection never retains a previous file tooltip")
    try check(app.fileNameLabel.stringValue == "已選取 2 個檔案" && app.technicalRow.isHidden && app.revealButton.isHidden, "multi-selection does not present one file as batch metadata")
    app.selectedURLs = [missing]; app.updateDetail()
    try check(!app.warningLabel.isHidden && app.warningLabel.stringValue == "跳過 · 無有效日期", "missing date remains visible outside disclosure")
    app.selectedURLs.removeAll(); app.updateDetail()
    try check(app.image.isHidden && app.revealButton.isHidden && app.fileNameLabel.stringValue == "選取檔案以查看資訊", "empty inspector avoids blank preview")
    app.toggleInspector()
    try check(app.inspector.isHidden, "inspector can be hidden")
    app.root = nil; app.refreshControls()
    app.root = root; app.refreshControls()
    try check(app.inspector.isHidden, "temporary empty state does not overwrite user's inspector preference")
    app.toggleInspector()
    try check(!app.inspector.isHidden, "inspector can be restored")
    app.selectedURLs = [a, b]; app.scope.selectItem(at: 1)
    try check(app.candidates.map(\.original) == [a, b], "selected scope uses original plan order")
    app.filter.selectedSegment = 1; app.rebuildVisibleRows()
    try check(app.visibleIndices == [1, 2] && app.candidates.count == 2, "filter does not change selected scope")
    try check(app.commandEnabled(#selector(AppDelegate.clearSelection)), "hidden selection remains clearable")
    app.table.sortDescriptors = [NSSortDescriptor(key: "old", ascending: false)]
    app.filter.selectedSegment = 0; app.rebuildVisibleRows()
    try check(app.visibleIndices.first == 2 && app.candidates.map(\.original) == [a, b], "display sort does not alter rename plan")
    app.scope.selectItem(at: 0)
    try check(app.candidates.count == 2, "all scope ignores filter and skips invalid rows")
    app.busyMessage.stringValue = "正在重新命名並保留復原紀錄…"
    app.busy = true; app.refreshControls()
    try check(app.accessibilityStatusText == app.busyMessage.stringValue, "busy announcement does not announce a premature result")
    try check(!app.renameButton.isEnabled && !app.commandEnabled(#selector(AppDelegate.restoreLog)), "busy disables file mutations")
    try check(app.tableScroll.isHidden && app.summary.isHidden && !app.progressRow.isHidden && !app.previewSpacer.isHidden && app.resultRow.isHidden, "busy state uses a compact progress row and keeps old results hidden")
    try check(!app.windowShouldClose(app.window), "busy window cannot close")
    if let sheet = app.window.attachedSheet { app.window.endSheet(sheet) }
    app.busy = false; app.sheetPending = false
    app.heading.stringValue = "掃描失敗"; app.summary.stringValue = "舊的預覽數量"
    try check(app.accessibilityStatusText == "掃描失敗。請查看錯誤資訊。", "scan failure announcement excludes stale counts")
    app.heading.stringValue = "操作已停止"; app.summary.stringValue = "部分操作可能已完成；請核對檔案與復原紀錄。"
    try check(app.accessibilityStatusText.contains("部分操作可能已完成"), "failed execution announcement preserves uncertainty")
    app.resultFrozen = true; app.completedURLs = [a]; app.attemptedURLs = [a, b]
    app.refreshControls()
    try check(app.footerRow.isHidden, "result actions do not repeat footer instructions")
    app.filter.selectedSegment = 2; app.rebuildVisibleRows()
    try check(app.filter.label(forSegment: 2) == "已更名" && app.visibleIndices == [0], "result filter shows successful rows")
    app.filter.selectedSegment = 1; app.rebuildVisibleRows()
    try check(Set(app.visibleIndices) == Set([1, 2]), "result attention keeps uncertain and missing rows")
    app.selectedURLs = [a]; app.updateDetail()
    try check(app.destinationCaption.stringValue == "原始檔名" && app.destinationLabel.stringValue == "A.jpg", "completed inspector preserves the original name as history")
    try check(app.displayStatus(app.rows[0]) == "已重新命名", "successful rows retain result")
    try check(app.displayStatus(app.rows[1]) == "結果未確認，請核對", "failed batch does not invent per-file outcome")
    try check(!app.commandEnabled(#selector(AppDelegate.renameAll)), "stale plan cannot execute twice")
    app.lastLog = root.appendingPathComponent(".photodate-test.json")
    try check(app.commandEnabled(#selector(AppDelegate.restoreLast)), "successful journal offers direct restore")
    app.restoredResult = true; app.filter.selectedSegment = 0; app.rebuildVisibleRows()
    try check(app.visibleIndices.count == 3 && app.filter.isHidden, "restore returns all rows without a stale success filter")
    try check(app.displayStatus(app.rows[0]) == "待重新掃描" && app.table.tableColumns[1].title == "先前預覽檔名", "restore labels stale preview clearly")
    app.selectedURLs = [a]; app.updateDetail()
    try check(app.destinationCaption.stringValue == "先前預覽檔名", "restored inspector identifies the stale preview")
    try check(app.displayStatus(conforming) == "待重新掃描", "restoring after a rescan never claims that stale names still match")
    app.status.toolTip = "舊的 CSV 路徑"; app.refreshControls()
    try check(app.status.toolTip == nil, "refreshed preview never retains an old export tooltip")
    app.restoredResult = false
    let priorHeading = app.heading.stringValue
    app.heading.stringValue = "復原已停止"
    app.completedURLs.removeAll(); app.attemptedURLs.removeAll()
    try check(app.displayStatus(conforming) == "結果未確認，請核對" && app.needsAttention(conforming), "restore failure after a rescan marks stale matching names as uncertain and keeps them in attention")
    app.heading.stringValue = priorHeading
    try check(app.settings == ScanSettings(), "default metadata settings preserved")
    app.sheetPending = true
    try check(!app.commandEnabled(#selector(AppDelegate.rescan)), "pending confirmation freezes plan")
    app.sheetPending = false
    let systemCommand = NSMenuItem(title: "系統命令", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
    try check(app.validateMenuItem(systemCommand), "system file panel commands are not disabled by app validation")
    let longName = String(repeating: "旅遊照片與家人合照-", count: 10) + ".jpg"
    let longURL = root.appendingPathComponent(longName)
    app.rows = [PlanRow(original: longURL, destination: a, identity: nil, date: "2024:01:01 12:00:00", source: "ExifIFD:DateTimeOriginal", status: "可重新命名")]
    app.completedURLs = [longURL]; app.selectedURLs = [longURL]
    for scale: CGFloat in [1, 2] {
        app.previewTextScale = scale; app.applyPreviewTextSize()
        app.window.contentView?.layoutSubtreeIfNeeded()
        try check(app.destinationCaption.stringValue == "原始檔名" && app.destinationLabel.stringValue == longName && app.destinationLabel.toolTip == longName, "completed long name remains available in text and tooltip")
        for field in [app.fileNameLabel, app.destinationLabel] {
            try check(field.maximumNumberOfLines == 2 && field.frame.height <= ceil(field.font!.boundingRectForFont.height) * 2 + 4, "filename fields remain bounded at normal and maximum text size")
        }
    }
    app.resultFrozen = false; app.restoredResult = false; app.completedURLs.removeAll(); app.attemptedURLs.removeAll()
    app.resultLabel.stringValue = ""; app.selectedURLs.removeAll(); app.filter.selectedSegment = 0; app.scope.selectItem(at: 0)
    app.rows = (0..<1000).map { index in
        PlanRow(original: root.appendingPathComponent("照片-\(index).jpg"), destination: root.appendingPathComponent("20240101_120000_\(index).jpg"), identity: nil, date: "2024:01:01 12:00:00", source: "ExifIFD:DateTimeOriginal", status: "可重新命名")
    }
    app.previewTextScale = 1; app.applyPreviewTextSize()
    try check(app.table.numberOfRows == 1000 && app.candidates.count == 1000 && app.candidateLabel.stringValue == "本次更名 1000 個檔案", "large batches keep table and execution counts consistent")
    let selected = app.rows[500].original
    app.selectedURLs = [selected]; app.scope.selectItem(at: 1); app.filter.selectedSegment = 1; app.rebuildVisibleRows()
    try check(app.candidates.count == 1 && app.selectedURLs == [selected], "large-batch filtering preserves the explicit selected scope")
    let appearanceSuite = "PhotoDateAppearanceTest-" + UUID().uuidString
    let testPreferences = UserDefaults(suiteName: appearanceSuite)!
    let originalAppearance = NSApp.appearance
    defer { testPreferences.removePersistentDomain(forName: appearanceSuite); NSApp.appearance = originalAppearance }
    app.appearanceDefaults = testPreferences
    let rowSnapshot = app.rows.map(\.original), selectionSnapshot = app.selectedURLs, settingsSnapshot = app.settings
    let choice = NSMenuItem(title: "", action: #selector(AppDelegate.changeAppearance(_:)), keyEquivalent: ""); choice.target = app
    try check(app.appearanceChoice == 0, "appearance defaults to following the system")
    for (tag, name) in [(1, NSAppearance.Name.aqua), (2, NSAppearance.Name.darkAqua)] {
        choice.tag = tag; app.changeAppearance(choice)
        try check(NSApp.appearance?.name == name, "appearance switches immediately")
        let reloaded = AppDelegate(); reloaded.appearanceDefaults = UserDefaults(suiteName: appearanceSuite)!
        try check(reloaded.appearanceChoice == tag, "appearance persists independently of the current controller")
        for item in app.appearanceMenuItem().submenu!.items {
            try check(app.validateMenuItem(item) && item.state == (item.tag == tag ? .on : .off), "both appearance menus reflect the persisted choice")
        }
    }
    choice.tag = 0; app.changeAppearance(choice)
    try check(NSApp.appearance == nil, "follow system removes the application override")
    testPreferences.set(99, forKey: "PhotoDateAppearance"); app.applyAppearance()
    try check(app.appearanceChoice == 0 && NSApp.appearance == nil, "invalid appearance preference safely follows the system")
    try check(app.rows.map(\.original) == rowSnapshot && app.selectedURLs == selectionSnapshot && app.settings == settingsSnapshot, "appearance switching does not change preview, selection or scan configuration")
    try importAndNamingTests()
    print("P0 UI self-tests passed")
}

func p0StatusContrastTest() throws {
    let app = AppDelegate(); app.buildInterface()
    defer { app.window.delegate = nil; app.window.close() }
    let root = URL(fileURLWithPath: "/tmp/p0-status-contrast")
    app.root = root
    app.rows = [
        PlanRow(original: root.appendingPathComponent("warning.mp4"), destination: root.appendingPathComponent("20240101_120000.mp4"), identity: nil, date: "2024:01:01 12:00:00", source: "QuickTime:CreateDate", status: "影片建立時間，請核對"),
        PlanRow(original: root.appendingPathComponent("error.jpg"), destination: nil, identity: nil, date: "—", source: "—", status: "錯誤：讀取失敗"),
        PlanRow(original: root.appendingPathComponent("missing.jpg"), destination: nil, identity: nil, date: "—", source: "—", status: "跳過：無有效時間欄位")
    ]
    app.rebuildVisibleRows()
    for scale: CGFloat in [1, 2] {
        app.previewTextScale = scale; app.applyPreviewTextSize()
        for index in app.rows.indices {
            let cell = app.tableView(app.table, viewFor: app.table.tableColumns[2], row: index) as! PreviewCellView
            guard cell.textField!.textColor == .labelColor,
                  cell.textField!.font!.pointSize == 13 * scale else {
                throw RenameError(message: "P0 status contrast: status must use readable native primary text at both scales")
            }
        }
        app.selectedURLs = [app.rows[0].original]; app.updateDetail()
        guard app.warningLabel.textColor == .labelColor else { throw RenameError(message: "P0 status contrast: inspector warning must remain readable") }
    }
    let expected: [NSColor] = [.systemOrange, .systemRed, .secondaryLabelColor, .systemGreen, .secondaryLabelColor]
    app.rows += [
        PlanRow(original: root.appendingPathComponent("ready.jpg"), destination: root.appendingPathComponent("20240101_120001.jpg"), identity: nil, date: "2024:01:01 12:00:01", source: "ExifIFD:DateTimeOriginal", status: "可重新命名"),
        PlanRow(original: root.appendingPathComponent("20240101_120002.jpg"), destination: root.appendingPathComponent("20240101_120002.jpg"), identity: nil, date: "2024:01:01 12:00:02", source: "ExifIFD:DateTimeOriginal", status: "檔名已符合")
    ]
    app.rebuildVisibleRows()
    for appearance in [NSAppearance.Name.aqua, .darkAqua] {
        app.window.appearance = NSAppearance(named: appearance)
        for index in app.rows.indices {
            let cell = app.tableView(app.table, viewFor: app.table.tableColumns[2], row: index) as! PreviewCellView
            cell.backgroundStyle = .normal
            guard cell.imageView?.contentTintColor == expected[index] else { throw RenameError(message: "status icon must use its semantic color in both appearances") }
            cell.backgroundStyle = .emphasized
            guard cell.imageView?.contentTintColor == .alternateSelectedControlTextColor else { throw RenameError(message: "selected status icon must retain native contrast") }
            cell.backgroundStyle = .normal
            guard cell.imageView?.contentTintColor == expected[index], cell.textField?.textColor == .labelColor else { throw RenameError(message: "deselection must restore icon color without coloring status text") }
        }
    }
    print("P0 status contrast tests passed")
}

func p0EmptyPreviewTest() throws {
    let app = AppDelegate(); app.buildInterface()
    defer { app.window.delegate = nil; app.window.close() }
    let root = URL(fileURLWithPath: "/tmp/p0-empty-preview")
    app.root = root; app.rows = []
    app.heading.stringValue = "沒有可處理的照片或影片"
    app.resultLabel.stringValue = "請選擇其他資料夾，或重新掃描。"
    app.refreshControls()
    guard app.tableScroll.isHidden && app.actionRow.isHidden && app.actionDivider.isHidden && app.footerRow.isHidden && app.inspector.isHidden && app.summary.isHidden && !app.locationRow.isHidden && !app.resultRow.isHidden,
          !app.commandEnabled(#selector(AppDelegate.renameCurrent)),
          !app.commandEnabled(#selector(AppDelegate.toggleInspector)),
          app.commandEnabled(#selector(AppDelegate.rescan)),
          app.commandEnabled(#selector(AppDelegate.chooseFolder)) else { throw RenameError(message: "P0 empty preview: unavailable batch controls must not distract from recovery") }
    app.window.contentView!.layoutSubtreeIfNeeded()
    let host = app.window.contentView!
    let location = app.locationRow.convert(app.locationRow.bounds, to: host)
    let title = app.heading.convert(app.heading.bounds, to: host)
    let result = app.resultRow.convert(app.resultRow.bounds, to: host)
    guard location.minY - title.maxY < 48 && title.minY - result.maxY < 48 else {
        throw RenameError(message: "P0 empty preview: title and recovery must remain grouped under location")
    }
    app.heading.stringValue = "掃描失敗"; app.resultLabel.stringValue = "沒有讀取權限"; app.refreshControls()
    guard app.tableScroll.isHidden && app.inspector.isHidden && !app.resultRow.isHidden else { throw RenameError(message: "P0 empty preview: scan failure must retain error and recovery") }
    app.rows = [PlanRow(original: root.appendingPathComponent("no-date.png"), destination: nil, identity: nil, date: "—", source: "—", status: "跳過：無有效時間欄位")]
    app.resultLabel.stringValue = ""; app.rebuildVisibleRows()
    guard !app.tableScroll.isHidden && !app.actionRow.isHidden && !app.inspector.isHidden && app.inspectorVisible else { throw RenameError(message: "P0 empty preview: actual skipped rows remain inspectable and inspector preference survives") }
    app.rows = []; app.root = nil; app.resultFrozen = true; app.restoredResult = true
    app.heading.stringValue = "復原完成"; app.summary.stringValue = "已復原 2 個檔名。"
    app.resultLabel.stringValue = "復原紀錄已保留。"; app.refreshControls()
    guard !app.split.isHidden && app.emptyView.isHidden && !app.heading.isHidden && !app.summary.isHidden && !app.resultRow.isHidden && app.locationRow.isHidden && app.tableScroll.isHidden else {
        throw RenameError(message: "restoring a journal before folder import must show its outcome")
    }
    print("P0 empty preview tests passed")
}
