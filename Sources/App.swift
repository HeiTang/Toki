import AppKit
import UniformTypeIdentifiers

final class InspectorDocumentView: NSView {
    override var isFlipped: Bool { true }
}

final class PreviewRowView: NSTableRowView {
    var alternate = false
    override func drawBackground(in dirtyRect: NSRect) {
        NSColor.alternatingContentBackgroundColors[alternate ? 1 : 0].setFill()
        bounds.fill()
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 0.5).fill()
    }
}

final class PreviewCellView: NSTableCellView {
    var iconTint: NSColor = .secondaryLabelColor { didSet { updateIconTint() } }
    override var backgroundStyle: NSView.BackgroundStyle { didSet { updateIconTint() } }
    private func updateIconTint() {
        imageView?.contentTintColor = backgroundStyle == .emphasized ? .alternateSelectedControlTextColor : iconTint
    }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let label = NSTextField(labelWithString: "")
        addSubview(label); textField = label
        let icon = NSImageView(); icon.setAccessibilityElement(false)
        addSubview(icon); imageView = icon
    }
    override func layout() {
        super.layout()
        guard let label = textField else { return }
        let height = label.intrinsicContentSize.height
        let hasIcon = imageView?.image != nil
        let iconSize: CGFloat = 16
        imageView?.isHidden = !hasIcon
        imageView?.frame = NSRect(x: 10, y: (bounds.height - iconSize) / 2, width: iconSize, height: iconSize)
        let inset: CGFloat = hasIcon ? 34 : 10
        label.frame = NSRect(x: inset, y: (bounds.height - height) / 2, width: max(0, bounds.width - inset - 10), height: height)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

struct ScanSettings: Equatable {
    var recursive = false
    var fallback = false
    var quickTimeUTC = true
    var timeZoneID = "Asia/Taipei"
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate,
    NSTableViewDataSource, NSTableViewDelegate, NSToolbarDelegate,
    NSMenuItemValidation, NSToolbarItemValidation, NSTextFieldDelegate {
    var window: NSWindow!
    let table = NSTableView()
    var locationRow: NSStackView!
    var footerRow: NSStackView!
    var inspectorVisible = true
    var previewTextScale: CGFloat = 1
    let locationLabel = NSTextField(labelWithString: "所在位置")
    let locationButton = NSPopUpButton(frame: .zero, pullsDown: true)
    let tableScroll = NSScrollView()
    let tableContainer = NSView()
    let tableEmptyLabel = NSTextField(labelWithString: "沒有符合篩選的項目")
    let emptyView = NSView()
    let previewSpacer = NSView()
    let emptyButton = NSButton(title: "加入檔案或資料夾…", target: nil, action: nil)
    let busyMessage = NSTextField(wrappingLabelWithString: "")
    let actionDivider = NSBox()
    let attentionLabel = NSTextField(wrappingLabelWithString: "")
    let attentionExplanation = NSTextField(wrappingLabelWithString: "")
    var attentionRow: NSStackView!
    let candidateLabel = NSTextField(labelWithString: "")
    var actionRow: NSStackView!
    var settingsPanel: NSPanel?
    let settingsApply = NSButton(title: "套用", target: nil, action: nil)
    let copyPathButton = NSButton(title: "完整路徑", target: nil, action: nil)
    let heading = NSTextField(labelWithString: "加入照片或影片所在資料夾")
    let summary = NSTextField(wrappingLabelWithString: "先預覽拍攝時間與新檔名，再確認更名。")
    let status = NSTextField(wrappingLabelWithString: "不使用 Finder 建立／修改日期。")
    let resultLabel = NSTextField(wrappingLabelWithString: "")
    let detail = NSTextField(wrappingLabelWithString: "選取一列，核對完整路徑、時間來源與換算結果。")
    let fileNameLabel = NSTextField(wrappingLabelWithString: "")
    let destinationCaption = NSTextField(labelWithString: "新檔名")
    let destinationLabel = NSTextField(wrappingLabelWithString: "")
    let timeLabel = NSTextField(wrappingLabelWithString: "")
    let sourceLabel = NSTextField(wrappingLabelWithString: "")
    let warningLabel = NSTextField(wrappingLabelWithString: "")
    var fileInfo: NSStackView!
    var technicalRow: NSStackView!
    let technicalToggle = NSButton()
    let image = NSImageView()
    let progress = NSProgressIndicator()
    let scope = NSPopUpButton(frame: .zero, pullsDown: false)
    let filter = NSSegmentedControl(labels: ["全部", "需注意", "可更名"], trackingMode: .selectOne, target: nil, action: nil)
    let recursive = NSButton(checkboxWithTitle: "包含子資料夾", target: nil, action: nil)
    let fallback = NSButton(checkboxWithTitle: "使用照片備用時間（需核對）", target: nil, action: nil)
    let quickTimeUTC = NSButton(checkboxWithTitle: "QuickTime 時間按 UTC 解讀", target: nil, action: nil)
    let outputTimeZone = NSPopUpButton(frame: .zero, pullsDown: false)
    var renameButton: NSButton!
    var restoreLastButton: NSButton!
    var clearButton: NSButton!
    var revealButton: NSButton!
    var progressRow: NSStackView!
    var resultRow: NSStackView!
    var resultActions: NSStackView!
    var resultRescanButton: NSButton!
    var split: NSSplitView!
    var inspector: NSView!
    var moreButton: NSPopUpButton?
    var rows: [PlanRow] = []
    var visibleIndices: [Int] = []
    var selectedURLs = Set<URL>()
    var root: URL?
    var busy = false
    var sheetPending = false
    var resultFrozen = false
    var restoredResult = false
    var completedURLs = Set<URL>()
    var attemptedURLs = Set<URL>()
    var lastLog: URL?
    var settings = ScanSettings()
    var importURLs: [URL] = []
    var sequenceNumbers: [URL: Int] = [:]
    var namingRule = defaultNamingRule
    let namingField = NSTextField(string: "")
    let namingSample = NSTextField(wrappingLabelWithString: "")
    var settingsTabs = NSTabView()
    var settingsSections = NSSegmentedControl()
    var namingReset = NSButton()
    var settingsTabHeight: NSLayoutConstraint?
    let namingError = NSTextField(wrappingLabelWithString: "")
    var namingDetails = NSTextField(wrappingLabelWithString: "")
    var appearanceDefaults = UserDefaults.standard
    private var updatingSelection = false
    private var toolbarButtons: [(NSButton, Selector)] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !CommandLine.arguments.contains("--ui-test-light") && !CommandLine.arguments.contains("--ui-test-dark") { applyAppearance() }
        if let rule = appearanceDefaults.string(forKey: "PhotoDateNamingRule"), (try? validateNamingRule(rule)) != nil { namingRule = rule }
        buildInterface()
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func buildInterface() {
        makeMenus()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 760),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Toki"
        window.subtitle = ""
        window.minSize = NSSize(width: 960, height: 640)
        window.setFrameAutosaveName("PhotoDateRenamerP0")
        window.delegate = self
        window.toolbarStyle = .unified
        scope.addItems(withTitles: ["全部可用項目", "選取項目"])
        scope.target = self; scope.action = #selector(scopeChanged)
        scope.setAccessibilityLabel("更名範圍")
        let toolbar = NSToolbar(identifier: "PhotoDateToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        if CommandLine.arguments.contains("--ui-test-small") {
            window.setFrame(NSRect(origin: window.frame.origin, size: NSSize(width: 960, height: 640)), display: false)
        }

        let content = DropImportView()
        content.canImport = { [weak self] in self.map { !$0.busy && !$0.sheetPending } ?? false }
        content.onImport = { [weak self] in self?.importItems($0) }
        window.contentView = content
        locationLabel.isSelectable = true
        locationLabel.font = .systemFont(ofSize: 12)
        locationLabel.textColor = .secondaryLabelColor
        locationLabel.lineBreakMode = .byTruncatingMiddle
        locationLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        locationButton.bezelStyle = .rounded
        locationButton.cell?.lineBreakMode = .byTruncatingMiddle
        locationButton.widthAnchor.constraint(equalToConstant: 260).isActive = true
        locationButton.setAccessibilityLabel("所在位置：上層資料夾")
        locationButton.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        copyPathButton.target = self; copyPathButton.action = #selector(showFolderPath); copyPathButton.bezelStyle = .rounded
        copyPathButton.setAccessibilityLabel("查看匯入來源完整路徑")
        locationRow = NSStackView(views: [locationLabel, locationButton, copyPathButton, NSView()])
        locationRow.spacing = 8; locationRow.alignment = .centerY
        split = NSSplitView(); split.isVertical = true; split.dividerStyle = .thin
        let main = NSView(); inspector = NSView()
        split.addArrangedSubview(main); split.addArrangedSubview(inspector)
        split.setHoldingPriority(.defaultLow, forSubviewAt: 0)
        split.setHoldingPriority(.defaultHigh, forSubviewAt: 1)
        inspector.widthAnchor.constraint(equalToConstant: 300).isActive = true
        main.widthAnchor.constraint(greaterThanOrEqualToConstant: 530).isActive = true

        heading.font = .systemFont(ofSize: 17, weight: .semibold)
        summary.textColor = .secondaryLabelColor
        filter.selectedSegment = 0; filter.target = self; filter.action = #selector(filterChanged)
        filter.setAccessibilityLabel("預覽清單篩選")
        let titleGroup = NSStackView(views: [heading, summary])
        titleGroup.orientation = .vertical; titleGroup.alignment = .leading; titleGroup.spacing = 5
        summary.font = .systemFont(ofSize: 12)
        summary.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleGroup.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let header = NSStackView(views: [titleGroup, NSView(), filter])
        header.alignment = .centerY; header.spacing = 12
        resultLabel.isSelectable = true
        restoreLastButton = button("復原這次…", #selector(restoreLast))
        resultRescanButton = button("重新掃描", #selector(rescan))
        resultActions = NSStackView(views: [restoreLastButton, resultRescanButton]); resultActions.spacing = 8
        let resultBody = NSStackView(views: [resultLabel, resultActions])
        resultBody.orientation = .vertical; resultBody.alignment = .leading; resultBody.spacing = 12
        let resultBox = NSBox(); resultBox.boxType = .custom; resultBox.titlePosition = .noTitle
        resultBox.borderWidth = 1; resultBox.cornerRadius = 8
        resultBox.borderColor = .separatorColor; resultBox.fillColor = .controlBackgroundColor
        resultBox.contentViewMargins = .zero
        install(resultBody, in: resultBox.contentView!, inset: 14)
        resultLabel.widthAnchor.constraint(equalTo: resultBody.widthAnchor).isActive = true
        resultRow = NSStackView(views: [resultBox])
        resultBox.widthAnchor.constraint(equalTo: resultRow.widthAnchor).isActive = true
        resultLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        resultLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        progress.style = .spinning; progress.controlSize = .small; progress.isIndeterminate = true
        progressRow = NSStackView(views: [progress, busyMessage]); progressRow.spacing = 8
        progressRow.setAccessibilityLabel("作業進行中")

        for (id, title, width, minimum) in [("old", "原始檔名", 240.0, 160.0),
            ("new", "新檔名", 250.0, 170.0), ("status", "狀態", 200.0, 140.0)] {
            let column = NSTableColumn(identifier: .init(id))
            column.title = title; column.width = width; column.minWidth = minimum
            column.resizingMask = [.autoresizingMask, .userResizingMask]
            column.sortDescriptorPrototype = NSSortDescriptor(key: id, ascending: true)
            table.addTableColumn(column)
        }
        table.dataSource = self; table.delegate = self
        table.allowsMultipleSelection = true
        table.usesAlternatingRowBackgroundColors = false
        table.style = .fullWidth
        table.intercellSpacing = NSSize(width: 0, height: 2)
        table.rowHeight = 38
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.setAccessibilityLabel("原始檔名、新檔名與更名狀態預覽")
        table.menu = commandMenu([("在 Finder 顯示", #selector(revealFile)), ("取消選取", #selector(clearSelection))])
        let scroll = tableScroll; scroll.documentView = table
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = false; scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        tableEmptyLabel.textColor = .secondaryLabelColor; tableEmptyLabel.translatesAutoresizingMaskIntoConstraints = false
        install(scroll, in: tableContainer, inset: 0)
        tableContainer.addSubview(tableEmptyLabel)
        NSLayoutConstraint.activate([tableEmptyLabel.centerXAnchor.constraint(equalTo: tableContainer.centerXAnchor),
            tableEmptyLabel.centerYAnchor.constraint(equalTo: tableContainer.centerYAnchor)])
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        emptyButton.target = self; emptyButton.action = #selector(chooseFolder); emptyButton.bezelStyle = .rounded
        let emptyTitle = NSTextField(labelWithString: "以拍攝日期重新命名")
        emptyTitle.font = .systemFont(ofSize: 18, weight: .semibold)
        let emptyHint = NSTextField(labelWithString: "拖入照片、影片或資料夾，或選擇檔案來建立預覽。")
        emptyHint.textColor = .secondaryLabelColor
        let emptyIcon = NSImageView(image: NSImage(systemSymbolName: "folder.badge.plus", accessibilityDescription: nil)!)
        emptyIcon.contentTintColor = .controlAccentColor
        emptyIcon.widthAnchor.constraint(equalToConstant: 48).isActive = true
        emptyIcon.heightAnchor.constraint(equalToConstant: 48).isActive = true
        let emptyBody = NSStackView(views: [emptyIcon, emptyTitle, emptyHint, emptyButton])
        emptyBody.orientation = .vertical; emptyBody.spacing = 16
        emptyBody.translatesAutoresizingMaskIntoConstraints = false; emptyView.addSubview(emptyBody)
        NSLayoutConstraint.activate([emptyBody.centerXAnchor.constraint(equalTo: emptyView.centerXAnchor),
            emptyBody.centerYAnchor.constraint(equalTo: emptyView.centerYAnchor)])
        emptyView.heightAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
        emptyView.setContentHuggingPriority(.defaultLow, for: .vertical)
        status.textColor = .secondaryLabelColor; status.isSelectable = true
        status.font = .systemFont(ofSize: 11)
        status.maximumNumberOfLines = 2
        renameButton = button("重新命名…", #selector(renameCurrent))
        renameButton.bezelColor = .controlAccentColor
        renameButton.widthAnchor.constraint(equalToConstant: 130).isActive = true
        candidateLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        candidateLabel.lineBreakMode = .byTruncatingTail
        let scopeTitle = NSTextField(labelWithString: "更名範圍")
        scopeTitle.textColor = .secondaryLabelColor
        actionRow = NSStackView(views: [scopeTitle, scope, candidateLabel, NSView(), renameButton]); actionRow.spacing = 12
        actionDivider.boxType = .separator
        attentionLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        attentionExplanation.font = .systemFont(ofSize: 12)
        attentionExplanation.textColor = .secondaryLabelColor
        let attentionText = NSStackView(views: [attentionLabel, attentionExplanation])
        attentionText.orientation = .vertical; attentionText.alignment = .leading; attentionText.spacing = 4
        let attentionIcon = NSImageView(image: NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)!)
        attentionIcon.contentTintColor = .secondaryLabelColor; attentionIcon.setAccessibilityElement(false)
        attentionIcon.widthAnchor.constraint(equalToConstant: 18).isActive = true
        attentionIcon.heightAnchor.constraint(equalToConstant: 18).isActive = true
        let attentionBody = NSStackView(views: [attentionIcon, attentionText])
        attentionBody.alignment = .top; attentionBody.spacing = 12
        let attentionBox = NSBox(); attentionBox.boxType = .custom; attentionBox.titlePosition = .noTitle
        attentionBox.borderWidth = 1; attentionBox.cornerRadius = 8
        attentionBox.borderColor = .separatorColor; attentionBox.fillColor = .controlBackgroundColor
        attentionBox.contentViewMargins = .zero
        install(attentionBody, in: attentionBox.contentView!, inset: 14)
        attentionRow = NSStackView(views: [attentionBox])
        attentionBox.widthAnchor.constraint(equalTo: attentionRow.widthAnchor).isActive = true
        clearButton = button("取消選取", #selector(clearSelection))
        footerRow = NSStackView(views: [status, clearButton]); footerRow.spacing = 8
        status.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let stack = NSStackView(views: [locationRow!, header, attentionRow, resultRow, progressRow, tableContainer, footerRow!, actionDivider, actionRow, previewSpacer])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12; stack.distribution = .fill
        install(stack, in: main, inset: 18)
        previewSpacer.setContentHuggingPriority(.defaultLow, for: .vertical)
        for view in [locationRow!, header, attentionRow!, resultRow!, progressRow!, footerRow!, actionRow!] as [NSView] {
            view.setContentHuggingPriority(.defaultHigh, for: .vertical)
        }
        let fullWidthViews: [NSView] = [locationRow!, header, attentionRow, resultRow, progressRow, tableContainer, footerRow!, actionDivider, actionRow, previewSpacer]
        for view in fullWidthViews {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
        makeInspector()
        let outer = NSStackView(views: [split, emptyView])
        outer.orientation = .vertical; outer.alignment = .leading; outer.spacing = 12
        install(outer, in: content, inset: 12)
        emptyView.widthAnchor.constraint(equalTo: outer.widthAnchor).isActive = true
        split.widthAnchor.constraint(equalTo: outer.widthAnchor).isActive = true
        split.heightAnchor.constraint(greaterThanOrEqualToConstant: 450).isActive = true
        refreshControls()
    }

    func makeInspector() {
        let title = NSTextField(labelWithString: "檔案資訊"); title.font = .systemFont(ofSize: 13, weight: .semibold)
        fileNameLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        for value in [fileNameLabel, destinationLabel] {
            value.maximumNumberOfLines = 2; value.lineBreakMode = .byTruncatingMiddle
        }
        for label in [fileNameLabel, destinationLabel, timeLabel, sourceLabel, warningLabel, detail] { label.isSelectable = true }
        func field(_ title: String, _ value: NSTextField) -> NSStackView {
            let caption = value === destinationLabel ? destinationCaption : NSTextField(labelWithString: title)
            caption.font = .systemFont(ofSize: 11); caption.textColor = .secondaryLabelColor
            let stack = NSStackView(views: [caption, value]); stack.orientation = .vertical
            stack.alignment = .leading; stack.spacing = 4
            value.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            return stack
        }
        image.imageScaling = .scaleProportionallyUpOrDown
        image.setAccessibilityLabel("選取照片預覽")
        image.heightAnchor.constraint(equalToConstant: 140).isActive = true
        let divider = NSBox(); divider.boxType = .separator
        fileInfo = NSStackView(views: [fileNameLabel, field("更名為", destinationLabel), divider,
                                      field("採用時間", timeLabel), field("時間來源", sourceLabel), warningLabel])
        fileInfo.orientation = .vertical; fileInfo.alignment = .leading; fileInfo.spacing = 16
        for view in fileInfo.arrangedSubviews { view.widthAnchor.constraint(equalTo: fileInfo.widthAnchor).isActive = true }
        technicalToggle.setButtonType(.pushOnPushOff); technicalToggle.bezelStyle = .disclosure
        technicalToggle.title = ""; technicalToggle.target = self; technicalToggle.action = #selector(toggleTechnicalDetails)
        technicalToggle.setAccessibilityLabel("展開技術詳細資訊")
        let technicalTitle = NSTextField(labelWithString: "技術詳細資訊")
        technicalTitle.textColor = .secondaryLabelColor; technicalTitle.font = .systemFont(ofSize: 11)
        technicalRow = NSStackView(views: [technicalToggle, technicalTitle]); technicalRow.spacing = 4
        detail.font = .systemFont(ofSize: 11); detail.textColor = .secondaryLabelColor
        revealButton = button("在 Finder 顯示", #selector(revealFile))
        let body = NSStackView(views: [title, image, fileInfo, technicalRow, detail, revealButton])
        body.orientation = .vertical; body.alignment = .leading; body.spacing = 18
        let document = InspectorDocumentView()
        let scroll = NSScrollView(); scroll.documentView = document; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        inspector.addSubview(scroll); pin(scroll, to: inspector)
        document.translatesAutoresizingMaskIntoConstraints = false
        document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
        install(body, in: document, inset: 18)
        let fullWidthViews: [NSView] = [image, fileInfo, detail]
        for view in fullWidthViews { view.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true }
        updateDetail()
    }

    func makeMenus() {
        let menu = NSMenu()
        func add(_ title: String, _ submenu: NSMenu) {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: ""); item.submenu = submenu; menu.addItem(item)
        }
        let app = NSMenu()
        app.addItem(withTitle: "關於 Toki", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        let preferences = NSMenuItem(title: "設定…", action: #selector(showSettings), keyEquivalent: ","); preferences.target = self; app.addItem(preferences); app.addItem(.separator())
        app.addItem(withTitle: "結束 Toki", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        add("Toki", app)
        let file = commandMenu([("加入檔案或資料夾…", #selector(chooseFolder)), ("重新掃描", #selector(rescan)),
            ("設定…", #selector(showSettings)), ("依目前範圍重新命名…", #selector(renameCurrent)),
            ("全部可用項目重新命名…", #selector(renameAll)), ("選取項目重新命名…", #selector(renameSelected)),
            ("匯出預覽 CSV…", #selector(exportCSV)), ("在 Finder 顯示", #selector(revealFile)),
            ("復原這次更名…", #selector(restoreLast)), ("選擇復原紀錄…", #selector(restoreLog))])
        file.items[0].keyEquivalent = "o"; file.items[1].keyEquivalent = "r"
        file.items[6].keyEquivalent = "e"; file.items[6].keyEquivalentModifierMask = [.command, .shift]
        add("檔案", file)
        let edit = NSMenu()
        edit.addItem(withTitle: "複製", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "全選", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        add("編輯", edit)
        let view = commandMenu([("顯示／隱藏檢查器", #selector(toggleInspector)), ("取消選取", #selector(clearSelection))])
        view.items[0].keyEquivalent = "i"; view.items[0].keyEquivalentModifierMask = [.command, .option]
        view.addItem(.separator())
        for (title, action, key) in [("放大預覽文字", #selector(increasePreviewText), "+"), ("縮小預覽文字", #selector(decreasePreviewText), "-"), ("預覽文字回復原始大小", #selector(resetPreviewText), "0")] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key); item.target = self; view.addItem(item)
        }
        view.addItem(.separator()); view.addItem(appearanceMenuItem())
        add("顯示", view)
        add("說明", commandMenu([("使用說明與素材限制…", #selector(showUsage))]))
        NSApp.mainMenu = menu
    }

    var appearanceChoice: Int {
        let choice = appearanceDefaults.integer(forKey: "PhotoDateAppearance")
        return (0...2).contains(choice) ? choice : 0
    }
    func applyAppearance() {
        switch appearanceChoice {
        case 1: NSApp.appearance = NSAppearance(named: .aqua)
        case 2: NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil
        }
    }
    @objc func changeAppearance(_ sender: NSMenuItem) {
        guard (0...2).contains(sender.tag) else { return }
        appearanceDefaults.set(sender.tag, forKey: "PhotoDateAppearance")
        applyAppearance()
    }
    func appearanceMenuItem() -> NSMenuItem {
        let parent = NSMenuItem(title: "外觀", action: nil, keyEquivalent: "")
        let menu = NSMenu()
        for (choice, title) in ["跟隨系統", "淺色", "深色"].enumerated() {
            let item = NSMenuItem(title: title, action: #selector(changeAppearance(_:)), keyEquivalent: "")
            item.target = self; item.tag = choice; item.state = choice == appearanceChoice ? .on : .off
            menu.addItem(item)
        }
        parent.submenu = menu
        return parent
    }

    func commandMenu(_ commands: [(String, Selector)]) -> NSMenu {
        let menu = NSMenu()
        for (title, action) in commands {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self; menu.addItem(item)
        }
        return menu
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.init("add"), .init("rescan"), .init("settings"), .flexibleSpace, .init("inspector"), .init("more")]
    }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: id)
        let title: String, symbol: String, action: Selector
        switch id.rawValue {
        case "add": title = "加入檔案或資料夾…"; symbol = "folder.badge.plus"; action = #selector(chooseFolder)
        case "rescan": title = "重新掃描"; symbol = "arrow.clockwise"; action = #selector(rescan)
        case "settings": title = "設定…"; symbol = "slider.horizontal.3"; action = #selector(showSettings)
        case "inspector": title = "顯示／隱藏檢查器"; symbol = "sidebar.right"; action = #selector(toggleInspector)
        case "more":
            let more = NSPopUpButton(frame: .zero, pullsDown: true); moreButton = more
            more.menu = commandMenu([("更多動作", #selector(noAction)), ("匯出預覽 CSV…", #selector(exportCSV)),
                ("在 Finder 顯示", #selector(revealFile)), ("復原這次更名…", #selector(restoreLast)), ("選擇復原紀錄…", #selector(restoreLog))])
            more.menu?.addItem(.separator()); more.menu?.addItem(appearanceMenuItem())
            more.menu?.items.first?.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "更多動作")
            more.setAccessibilityLabel("更多動作"); item.label = "更多動作"; item.view = more; return item
        default: return nil
        }
        item.label = title; item.toolTip = title; item.target = self; item.action = action
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        return item
    }

    func button(_ title: String, _ action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action); button.bezelStyle = .rounded
        toolbarButtons.append((button, action)); return button
    }
    func install(_ view: NSView, in parent: NSView, inset: CGFloat) {
        parent.addSubview(view); pin(view, to: parent, inset: inset)
    }
    func pin(_ view: NSView, to parent: NSView, inset: CGFloat = 0) {
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([view.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: inset),
            view.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -inset),
            view.topAnchor.constraint(equalTo: parent.topAnchor, constant: inset),
            view.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -inset)])
    }

    var selectedRows: [PlanRow] { rows.filter { selectedURLs.contains($0.original) } }
    var candidates: [PlanRow] { (scope.indexOfSelectedItem == 1 ? selectedRows : rows).filter(\.actionable) }
    func commandEnabled(_ action: Selector?) -> Bool {
        guard let action else { return false }
        if action == #selector(changeAppearance(_:)) { return true }
        if action == #selector(toggleInspector) { return root != nil && !rows.isEmpty }
        if busy || sheetPending { return false }
        switch action {
        case #selector(chooseFolder), #selector(showSettings), #selector(showUsage), #selector(restoreLog): return true
        case #selector(increasePreviewText): return previewTextScale < 2
        case #selector(decreasePreviewText), #selector(resetPreviewText): return previewTextScale > 1
        case #selector(scopeChanged): return !resultFrozen && !rows.isEmpty
        case #selector(rescan), #selector(revealFile), #selector(copyFolderPath): return root != nil
        case #selector(exportCSV): return !rows.isEmpty
        case #selector(showAttention): return !rows.isEmpty
        case #selector(clearSelection): return !selectedURLs.isEmpty
        case #selector(restoreLast): return lastLog != nil
        case #selector(renameCurrent): return root != nil && !resultFrozen && !candidates.isEmpty
        case #selector(renameAll): return root != nil && !resultFrozen && rows.contains(where: \.actionable)
        case #selector(renameSelected): return root != nil && !resultFrozen && selectedRows.contains(where: \.actionable)
        default: return false
        }
    }
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        guard item.target === self else { return true }
        if item.action == #selector(changeAppearance(_:)) { item.state = item.tag == appearanceChoice ? .on : .off }
        return commandEnabled(item.action)
    }
    func validateToolbarItem(_ item: NSToolbarItem) -> Bool { commandEnabled(item.action) }
    func refreshControls() {
        for (button, action) in toolbarButtons { button.isEnabled = commandEnabled(action) }
        moreButton?.isEnabled = !busy && !sheetPending
        scope.isEnabled = !busy && !sheetPending && !resultFrozen && !rows.isEmpty
        filter.isEnabled = !busy && !sheetPending && !rows.isEmpty
        renameButton?.title = "重新命名…"
        renameButton?.setAccessibilityLabel("依目前範圍確認重新命名")
        candidateLabel.stringValue = resultFrozen ? "結果已保留，重新掃描後可再次更名" : (candidates.isEmpty ? "沒有可更名的檔案" : "本次更名 \(candidates.count) 個檔案")
        candidateLabel.toolTip = candidateLabel.stringValue
        let hasContext = root != nil || resultFrozen || busy
        split.isHidden = !hasContext
        locationRow.isHidden = root == nil
        footerRow.isHidden = root == nil || busy || resultFrozen || rows.isEmpty
        let hideInspector = root == nil || !inspectorVisible || rows.isEmpty
        if inspector.isHidden != hideInspector {
            inspector.isHidden = hideInspector
            if hideInspector { split.removeArrangedSubview(inspector); inspector.removeFromSuperview() }
            else { split.addArrangedSubview(inspector); split.setHoldingPriority(.defaultHigh, forSubviewAt: 1) }
            split.adjustSubviews(); split.needsDisplay = true
        }
        emptyView.isHidden = hasContext
        tableScroll.isHidden = root == nil || busy || rows.isEmpty
        tableContainer.isHidden = tableScroll.isHidden
        previewSpacer.isHidden = !hasContext || (!busy && !rows.isEmpty)
        actionRow?.isHidden = root == nil || busy || resultFrozen || rows.isEmpty
        filter.isHidden = root == nil || rows.isEmpty || restoredResult
        table.tableColumns.first(where: { $0.identifier.rawValue == "new" })?.title = restoredResult ? "先前預覽檔名" : "新檔名"
        filter.setLabel(resultFrozen ? "已更名" : "可更名", forSegment: 2)
        heading.isHidden = !hasContext; summary.isHidden = !hasContext || busy || (rows.isEmpty && !resultFrozen)
        status.isHidden = busy
        actionDivider.isHidden = root == nil || busy || resultFrozen || rows.isEmpty
        let attentionCount = rows.filter(needsAttention).count
        attentionRow?.isHidden = root == nil || busy || resultFrozen || attentionCount == 0
        attentionLabel.stringValue = "\(attentionCount) 個檔案需檢查"
        attentionExplanation.stringValue = "請在「需注意」篩選中核對時間來源、同名序號與保留原名的項目。"
        copyPathButton.isHidden = root == nil; locationButton.isHidden = root == nil
        copyPathButton.isEnabled = root != nil && !busy && !sheetPending
        clearButton?.isHidden = selectedURLs.isEmpty
        progressRow?.isHidden = !busy
        if busy { progress.startAnimation(nil) } else { progress.stopAnimation(nil) }
        resultRow?.isHidden = busy || resultLabel.stringValue.isEmpty
        tableEmptyLabel.isHidden = tableScroll.isHidden || !visibleIndices.isEmpty
        restoreLastButton?.isHidden = lastLog == nil
        resultRescanButton?.isHidden = root == nil
        resultActions?.isHidden = lastLog == nil && root == nil
        let count = rows.filter(\.actionable).count
        if !busy && resultLabel.stringValue.isEmpty {
            summary.stringValue = root == nil ? "先預覽拍攝時間與新檔名，再確認更名。" : "\(rows.count) 個檔案 · \(count) 個可更名 · \(rows.count-count) 個保留原名"
        }
        if !busy {
            status.toolTip = nil
            status.stringValue = root == nil ? "" : (resultFrozen ? "結果已保留；可復原或重新掃描。" : "顯示 \(visibleIndices.count) / \(rows.count) 個檔案\(selectedURLs.isEmpty ? "" : " · 已選 \(selectedURLs.count) 個")")
        }
        emptyButton.isEnabled = commandEnabled(#selector(chooseFolder))
        fitPreviewColumns()
        window?.toolbar?.validateVisibleItems()
    }
    func fitPreviewColumns() {
        window?.contentView?.layoutSubtreeIfNeeded()
        let width = tableScroll.contentSize.width
        guard width > 0 else { return }
        table.setFrameSize(NSSize(width: width, height: table.frame.height))
        table.sizeToFit()
    }
    func windowDidResize(_ notification: Notification) { fitPreviewColumns() }
    func setBusy(_ value: Bool, _ text: String) {
        busy = value; busyMessage.stringValue = text; refreshControls()
        if value { postStatusAnnouncement() }
    }
    var accessibilityStatusText: String {
        if busy { return busyMessage.stringValue }
        let outcome = heading.stringValue == "掃描失敗" ? "請查看錯誤資訊。" : summary.stringValue
        return "\(heading.stringValue)。\(outcome)"
    }
    func postStatusAnnouncement() {
        precondition(Thread.isMainThread)
        NSAccessibility.post(element: NSApplication.shared, notification: .announcementRequested, userInfo: [
            .announcement: accessibilityStatusText, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }
    func displayStatus(_ row: PlanRow) -> String {
        if resultFrozen && heading.stringValue == "復原已停止" && row.destination != nil { return "結果未確認，請核對" }
        if restoredResult && row.destination != nil { return "待重新掃描" }
        if completedURLs.contains(row.original) { return "已重新命名" }
        if resultFrozen && attemptedURLs.contains(row.original) { return "結果未確認，請核對" }
        if row.status == "可重新命名", hasSequenceSuffix(row) { return "同名已加序號" }
        return row.status
    }
    func hasSequenceSuffix(_ row: PlanRow) -> Bool {
        guard row.actionable, let name = row.destination?.deletingPathExtension().lastPathComponent else { return false }
        return name.range(of: "^\\d{8}_\\d{6}_\\d+$", options: .regularExpression) != nil
    }
    func needsAttention(_ row: PlanRow) -> Bool {
        if completedURLs.contains(row.original) { return false }
        return row.destination == nil || displayStatus(row).contains("核對") || row.status == "同名已加序號" || hasSequenceSuffix(row) || (resultFrozen && attemptedURLs.contains(row.original))
    }
    func rebuildVisibleRows() {
        visibleIndices = rows.indices.filter { index in
            let row = rows[index]
            switch filter.selectedSegment {
            case 1: return needsAttention(row)
            case 2: return resultFrozen ? completedURLs.contains(row.original) : row.actionable
            default: return true
            }
        }
        if let sort = table.sortDescriptors.first, let key = sort.key {
            visibleIndices.sort { a, b in
                let lhs = value(rows[a], key: key), rhs = value(rows[b], key: key)
                let comparison = lhs.localizedStandardCompare(rhs)
                if comparison == .orderedSame { return rows[a].original.path < rows[b].original.path }
                return sort.ascending ? comparison == .orderedAscending : comparison == .orderedDescending
            }
        }
        updatingSelection = true
        table.reloadData()
        table.selectRowIndexes(IndexSet(visibleIndices.indices.filter { selectedURLs.contains(rows[visibleIndices[$0]].original) }), byExtendingSelection: false)
        updatingSelection = false
        updateDetail(); refreshControls()
    }
    func value(_ row: PlanRow, key: String) -> String {
        switch key { case "old": return row.original.lastPathComponent
        case "new": return row.destination?.lastPathComponent ?? "—"
        default:
            let state = displayStatus(row)
            if state == "跳過：無有效時間欄位" { return "跳過 · 無有效日期" }
            if state.hasPrefix("命名錯誤") { return "命名失敗" }
            if state.hasPrefix("錯誤") { return "讀取失敗" }
            return state }
    }
    func numberOfRows(in tableView: NSTableView) -> Int { visibleIndices.count }
    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) { rebuildVisibleRows() }
    func selectionShouldChange(in tableView: NSTableView) -> Bool { updatingSelection || (!busy && !sheetPending) }
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { !busy && !sheetPending }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = rows[visibleIndices[row]], key = tableColumn?.identifier.rawValue ?? "status"
        let id = NSUserInterfaceItemIdentifier(key)
        let cell = tableView.makeView(withIdentifier: id, owner: self) as? PreviewCellView ?? PreviewCellView(frame: .zero)
        cell.identifier = id
        let label = cell.textField!
        let emphasized = key == "status" && ((item.status.hasPrefix("錯誤") || item.status.hasPrefix("命名錯誤")) || displayStatus(item).contains("核對"))
        label.font = key == "new" ? .monospacedSystemFont(ofSize: 13 * previewTextScale, weight: .regular) : .systemFont(ofSize: 13 * previewTextScale, weight: emphasized ? .semibold : .regular)
        let symbol: String?
        var iconTint: NSColor = .secondaryLabelColor
        if key == "old" {
            symbol = UTType(filenameExtension: item.original.pathExtension)?.conforms(to: .movie) == true ? "video" : "photo"
        } else if key == "status" {
            let state = displayStatus(item)
            if state.hasPrefix("錯誤") || state.hasPrefix("命名錯誤") { symbol = "xmark.octagon.fill"; iconTint = .systemRed }
            else if state.contains("核對") || state == "待重新掃描" { symbol = "exclamationmark.triangle.fill"; iconTint = .systemOrange }
            else if item.destination == nil { symbol = "minus.circle" }
            else { symbol = "checkmark.circle.fill"; iconTint = state == "檔名已符合" ? .secondaryLabelColor : .systemGreen }
        } else { symbol = nil }
        cell.imageView?.image = symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
        cell.iconTint = iconTint
        label.stringValue = value(item, key: key)
        label.lineBreakMode = key == "status" ? .byTruncatingTail : .byTruncatingMiddle
        label.toolTip = key == "status" ? displayStatus(item) : key == "old" ? item.original.path : item.destination?.path ?? label.stringValue; label.setAccessibilityLabel("\(tableColumn?.title ?? "狀態")：\(label.stringValue)")
        label.textColor = .labelColor
        return cell
    }
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let view = PreviewRowView()
        view.alternate = row % 2 == 1
        return view
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !updatingSelection else { return }
        let visibleURLs = Set(visibleIndices.map { rows[$0].original })
        selectedURLs.subtract(visibleURLs)
        selectedURLs.formUnion(table.selectedRowIndexes.compactMap { visibleIndices.indices.contains($0) ? rows[visibleIndices[$0]].original : nil })
        updateDetail(); refreshControls()
    }
    func currentURL(_ row: PlanRow) -> URL {
        if let destination = row.destination, let identity = row.identity, (try? Identity(destination)) == identity { return destination }
        return row.original
    }
    @objc func increasePreviewText() { previewTextScale = min(2, previewTextScale + 0.25); applyPreviewTextSize() }
    @objc func decreasePreviewText() { previewTextScale = max(1, previewTextScale - 0.25); applyPreviewTextSize() }
    @objc func resetPreviewText() { previewTextScale = 1; applyPreviewTextSize() }
    func applyPreviewTextSize() {
        table.rowHeight = max(38, ceil(NSFont.systemFont(ofSize: 13 * previewTextScale).boundingRectForFont.height) + 16)
        tableScroll.tile(); rebuildVisibleRows()
    }
    func updateDetail() {
        fileNameLabel.font = .systemFont(ofSize: 13 * previewTextScale, weight: .semibold)
        for value in [destinationLabel, timeLabel, sourceLabel, warningLabel] { value.font = .systemFont(ofSize: 13 * previewTextScale) }
        for group in fileInfo.arrangedSubviews.compactMap({ $0 as? NSStackView }) {
            (group.arrangedSubviews.first as? NSTextField)?.font = .systemFont(ofSize: 11 * previewTextScale)
        }
        (technicalRow.arrangedSubviews.last as? NSTextField)?.font = .systemFont(ofSize: 11 * previewTextScale)
        detail.font = .systemFont(ofSize: 11 * previewTextScale)
        image.image = nil; image.isHidden = true; fileNameLabel.toolTip = nil
        detail.isHidden = true; technicalRow.isHidden = true; revealButton.isHidden = true
        destinationLabel.stringValue = ""; destinationLabel.toolTip = nil; timeLabel.stringValue = ""; sourceLabel.stringValue = ""
        warningLabel.isHidden = true
        fileInfo.arrangedSubviews.dropFirst().forEach { $0.isHidden = true }
        guard selectedURLs.count == 1, let row = rows.first(where: { selectedURLs.contains($0.original) }) else {
            fileNameLabel.stringValue = selectedURLs.isEmpty ? "選取檔案以查看資訊" : "已選取 \(selectedURLs.count) 個檔案"
            return
        }
        fileInfo.arrangedSubviews.dropFirst().forEach { $0.isHidden = false }
        fileNameLabel.stringValue = currentURL(row).lastPathComponent
        fileNameLabel.toolTip = fileNameLabel.stringValue
        let completed = completedURLs.contains(row.original) && !restoredResult
        destinationCaption.stringValue = restoredResult ? "先前預覽檔名" : (completed ? "原始檔名" : "新檔名")
        destinationLabel.stringValue = completed ? row.original.lastPathComponent : (row.destination?.lastPathComponent ?? "—")
        destinationLabel.toolTip = destinationLabel.stringValue
        // 僅整理核心已有的顯示字串，不重新解析或換算拍攝日期。
        timeLabel.stringValue = row.date.components(separatedBy: " → ").last ?? row.date
        let sources = ["ExifIFD:DateTimeOriginal": "EXIF 拍攝時間", "XMP-exif:DateTimeOriginal": "XMP 拍攝時間",
                       "Keys:CreationDate": "影片拍攝時間（Keys）", "UserData:DateTimeOriginal": "影片拍攝時間（UserData）",
                       "ExifIFD:CreateDate": "EXIF 備用時間", "XMP-xmp:CreateDate": "XMP 備用時間"]
        sourceLabel.stringValue = sources[row.source] ?? (quickTimeIntegerTags.contains(row.source) ? "QuickTime 建立時間" : row.source)
        let state = displayStatus(row)
        warningLabel.stringValue = value(row, key: "status")
        warningLabel.toolTip = state
        warningLabel.isHidden = state == "可重新命名"
        warningLabel.textColor = .labelColor
        detail.stringValue = "時間欄位\n\(row.source)\n\n原始時間／換算結果\n\(row.date)\n\n\(restoredResult ? "先前預覽路徑" : "完整路徑")\n\(currentURL(row).path)"
        technicalRow.isHidden = false; detail.isHidden = technicalToggle.state != .on
        revealButton.isHidden = false
        // shortcut: 保留既有同步圖片預覽，非同步縮圖與影片預覽在 P1 再評估。
        if !["mov", "mp4", "m4v", "avi", "mkv"].contains(row.original.pathExtension.lowercased()) {
            image.image = NSImage(contentsOf: currentURL(row)); image.isHidden = image.image == nil
        }
    }
    @objc func toggleTechnicalDetails() {
        technicalToggle.setAccessibilityLabel(technicalToggle.state == .on ? "收合技術詳細資訊" : "展開技術詳細資訊")
        updateDetail()
    }
    @objc func showUsage() {
        guard commandEnabled(#selector(showUsage)) else { return }
        alert("使用說明與素材限制", "預設檔名為 YYYYMMDD_HHMMSS。可在「設定 > 命名」自訂文字、日期、原檔名與流水號，保留原副檔名；同名自動加 _1、_2。\n\n只改檔名，不改寫媒體內容。復原紀錄不是媒體備份。\n\n不連動 XMP／AAE 或 Live Photo 配對；請先從 Photos 匯出至一般資料夾。")
    }
    @objc func noAction() {}
    @objc func scopeChanged() { refreshControls() }
    @objc func showAttention() { filter.selectedSegment = 1; rebuildVisibleRows() }
    @objc func filterChanged() { rebuildVisibleRows() }
    @objc func toggleInspector() {
        guard root != nil else { return }
        inspectorVisible.toggle(); refreshControls()
    }
    @objc func clearSelection() { selectedURLs.removeAll(); rebuildVisibleRows() }
    func importItems(_ urls: [URL]) {
        guard !busy && !sheetPending else { return }
        do {
            let inputs = try validateImportSources(urls)
            let first = inputs[0]
            let directory = try first.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
            sequenceNumbers.removeAll()
            importURLs = inputs; root = directory ? first : first.deletingLastPathComponent()
            updateImportLocation()
            lastLog = nil; scope.selectItem(at: 0); filter.selectedSegment = 0
            rescan()
        } catch { alert("無法加入項目", error.localizedDescription) }
    }
    func updateImportLocation() {
        guard let root else { return }
        if importURLs.count == 1, importURLs[0] == root {
            locationLabel.stringValue = "所在位置"; updateLocation(root); window.title = root.lastPathComponent
        } else {
            locationLabel.stringValue = "來源"
            let menu = NSMenu()
            menu.addItem(NSMenuItem(title: "\(importURLs.count) 個來源", action: nil, keyEquivalent: "")); menu.addItem(.separator())
            for url in importURLs { let item = NSMenuItem(title: url.lastPathComponent, action: nil, keyEquivalent: ""); item.toolTip = url.path; menu.addItem(item) }
            locationButton.menu = menu; locationButton.toolTip = importURLs.map(\.path).joined(separator: "\n")
            locationButton.setAccessibilityLabel("匯入來源：\(importURLs.count) 個項目")
            window.title = importURLs.count == 1 ? importURLs[0].lastPathComponent : "\(importURLs.count) 個來源"
        }
    }
    @objc func chooseFolder() {
        guard commandEnabled(#selector(chooseFolder)) else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = true; panel.allowsMultipleSelection = true
        panel.prompt = "加入並預覽"; panel.directoryURL = root
        sheetPending = true; refreshControls()
        panel.beginSheetModal(for: window) { response in
            self.sheetPending = false
            if response == .OK { self.importItems(panel.urls) } else { self.refreshControls() }
        }
    }
    func makeNamingView() -> NSView {
        namingField.stringValue = namingRule; namingField.delegate = self
        namingField.setAccessibilityLabel("自訂命名範本"); namingField.placeholderString = defaultNamingRule
        namingField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        let title = NSTextField(labelWithString: "檔名格式"); title.font = .systemFont(ofSize: 16, weight: .semibold)
        let subtitle = NSTextField(labelWithString: "設定新檔名的組成方式。")
        subtitle.font = .systemFont(ofSize: 12); subtitle.textColor = .secondaryLabelColor
        let heading = NSStackView(views: [title, subtitle]); heading.orientation = .vertical; heading.alignment = .leading; heading.spacing = 4
        let label = NSTextField(labelWithString: "命名範本"); label.font = .systemFont(ofSize: 12, weight: .semibold)
        let tokens = NSStackView(); tokens.spacing = 6
        for (index, name) in ["年", "月", "日", "時", "分", "秒", "原檔名", "流水號"].enumerated() {
            let button = NSButton(title: name, target: self, action: #selector(insertNamingToken(_:)))
            button.bezelStyle = .rounded; button.controlSize = .small; button.tag = index
            button.toolTip = "插入 {" + namingTokens[index] + "}"
            button.setAccessibilityLabel("插入" + name + "變數")
            tokens.addArrangedSubview(button)
        }
        let hint = NSTextField(labelWithString: "可直接輸入文字，或在游標位置插入變數。")
        hint.font = .systemFont(ofSize: 11); hint.textColor = .secondaryLabelColor
        namingError.font = .systemFont(ofSize: 11); namingError.textColor = .systemRed; namingError.isHidden = true
        let editor = NSStackView(views: [label, namingField, tokens, hint, namingError])
        editor.orientation = .vertical; editor.alignment = .leading; editor.spacing = 8
        for view in [namingField, namingError] { view.widthAnchor.constraint(equalTo: editor.widthAnchor).isActive = true }
        let previewTitle = NSTextField(labelWithString: "更名預覽"); previewTitle.font = label.font
        let original = NSTextField(labelWithString: "IMG_4822.jpg")
        let date = NSTextField(labelWithString: "2024/02/29 12:34:56")
        for view in [original, date] { view.font = .systemFont(ofSize: 11); view.textColor = .secondaryLabelColor }
        let source = NSStackView(views: [original, NSView(), date]); source.spacing = 8
        namingSample.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        namingSample.setAccessibilityLabel("更名預覽結果")
        let sampleStack = NSStackView(views: [source, namingSample]); sampleStack.orientation = .vertical; sampleStack.alignment = .leading; sampleStack.spacing = 10
        let box = NSBox(); box.boxType = .custom; box.titlePosition = .noTitle; box.borderColor = .separatorColor
        box.fillColor = .controlBackgroundColor; box.cornerRadius = 8; box.contentViewMargins = .zero
        install(sampleStack, in: box.contentView!, inset: 14)
        for view in [source, namingSample] { view.widthAnchor.constraint(equalTo: sampleStack.widthAnchor).isActive = true }
        let previewHint = NSTextField(labelWithString: "範例資料 · 副檔名自動保留")
        previewHint.font = hint.font; previewHint.textColor = .secondaryLabelColor
        let preview = NSStackView(views: [previewTitle, box, previewHint]); preview.orientation = .vertical; preview.alignment = .leading; preview.spacing = 8
        box.widthAnchor.constraint(equalTo: preview.widthAnchor).isActive = true
        let disclosure = NSButton(title: "", target: self, action: #selector(toggleNamingDetails(_:)))
        disclosure.setButtonType(.onOff); disclosure.bezelStyle = .disclosure
        disclosure.setAccessibilityLabel("展開同名、日期與流水號規則")
        disclosure.widthAnchor.constraint(equalToConstant: 16).isActive = true
        let disclosureLabel = NSTextField(labelWithString: "同名、日期與流水號規則")
        disclosureLabel.font = .systemFont(ofSize: 11); disclosureLabel.textColor = .secondaryLabelColor
        let disclosureRow = NSStackView(views: [disclosure, disclosureLabel]); disclosureRow.spacing = 6
        disclosure.font = .systemFont(ofSize: 11); disclosure.contentTintColor = .secondaryLabelColor
        namingDetails = NSTextField(wrappingLabelWithString: "同名時自動加序號；沒有有效拍攝日期的檔案保留原名。流水號至少四位，初次依完整路徑排序，在本次匯入內保留。")
        namingDetails.font = hint.font; namingDetails.textColor = .secondaryLabelColor; namingDetails.isHidden = true
        let body = NSStackView(views: [heading, editor, preview, disclosureRow, namingDetails, NSView()])
        body.orientation = .vertical; body.alignment = .leading; body.spacing = 20
        for view in [heading, editor, preview, namingDetails] as [NSView] { view.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true }
        let host = NSView(); install(body, in: host, inset: 0)
        return host
    }
    @objc func insertNamingToken(_ sender: NSButton) {
        guard namingTokens.indices.contains(sender.tag) else { return }
        let token = "{" + namingTokens[sender.tag] + "}"
        if let editor = namingField.currentEditor() as? NSTextView {
            editor.insertText(token, replacementRange: editor.selectedRange())
        } else {
            namingField.stringValue += token
            settingsPanel?.makeFirstResponder(namingField)
        }
        updateNamingSample()
    }
    @objc func toggleNamingDetails(_ sender: NSButton) {
        namingDetails.isHidden = sender.state != .on
        settingsTabHeight?.constant = sender.state == .on ? 430 : 360
        settingsPanel?.setContentSize(NSSize(width: 540, height: sender.state == .on ? 610 : 540))
    }
    @objc func selectSettingsSection(_ sender: NSSegmentedControl) {
        settingsTabs.selectTabViewItem(at: sender.selectedSegment)
        namingReset.isHidden = sender.selectedSegment != 1
        let naming = sender.selectedSegment == 1
        let expanded = naming && !namingDetails.isHidden
        settingsTabHeight?.constant = naming ? (expanded ? 430 : 360) : 380
        settingsPanel?.setContentSize(NSSize(width: 540, height: naming ? (expanded ? 610 : 540) : 560))
    }
    func updateNamingSample() {
        do {
            let sample = try namingStem(namingField.stringValue, timestamp: "20240229_123456", original: URL(fileURLWithPath: "/IMG_4822.jpg"), index: 1) + ".jpg"
            guard sample.utf8.count <= 255 else { throw RenameError(message: "命名範例過長。") }
            namingSample.stringValue = "→ " + sample; namingSample.textColor = .labelColor; namingError.stringValue = ""; namingError.isHidden = true; settingsApply.isEnabled = true
        } catch { namingSample.stringValue = "無法產生預覽"; namingSample.textColor = .secondaryLabelColor; namingError.stringValue = error.localizedDescription; namingError.isHidden = false; settingsApply.isEnabled = false }
    }
    func controlTextDidChange(_ notification: Notification) { if notification.object as AnyObject? === namingField { updateNamingSample() } }
    @objc func resetNaming() { namingField.stringValue = defaultNamingRule; updateNamingSample() }
    func makeSettingsPanel() -> NSPanel {
        recursive.state = settings.recursive ? .on : .off
        fallback.state = settings.fallback ? .on : .off
        quickTimeUTC.state = settings.quickTimeUTC ? .on : .off
        if outputTimeZone.numberOfItems == 0 { outputTimeZone.addItems(withTitles: TimeZone.knownTimeZoneIdentifiers.sorted()) }
        outputTimeZone.selectItem(withTitle: settings.timeZoneID)
        outputTimeZone.setAccessibilityLabel("QuickTime 輸出時區")
        quickTimeUTC.target = self; quickTimeUTC.action = #selector(updateTimeZoneControl)
        updateTimeZoneControl()
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 540, height: 560), styleMask: [.titled], backing: .buffered, defer: false)
        panel.title = "設定"; panel.isReleasedWhenClosed = false
        let scanTitle = NSTextField(labelWithString: "掃描範圍"); scanTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        let timeTitle = NSTextField(labelWithString: "時間處理"); timeTitle.font = scanTitle.font
        func group(_ views: [NSView], height: CGFloat) -> NSBox {
            let box = NSBox(); box.boxType = .custom; box.titlePosition = .noTitle
            box.borderWidth = 1; box.cornerRadius = 8
            box.borderColor = .separatorColor; box.fillColor = .controlBackgroundColor
            box.contentViewMargins = .zero
            let stack = NSStackView(views: views)
            stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 14
            let content = box.contentView!
            content.addSubview(stack); stack.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
                stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
                stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
                stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -16),
                box.heightAnchor.constraint(equalToConstant: height)
            ])
            for view in views { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
            return box
        }
        fallback.title = "使用照片備用時間"
        let fallbackHint = NSTextField(labelWithString: "可能是數位化或編輯時間，需核對。")
        fallbackHint.font = .systemFont(ofSize: 11); fallbackHint.textColor = .secondaryLabelColor
        fallback.setAccessibilityLabel("使用照片備用時間（需核對）")
        fallback.setAccessibilityHelp(fallbackHint.stringValue)
        let indent = NSView(); indent.widthAnchor.constraint(equalToConstant: 18).isActive = true
        let fallbackHintRow = NSStackView(views: [indent, fallbackHint]); fallbackHintRow.spacing = 0
        let fallbackGroup = NSStackView(views: [fallback, fallbackHintRow])
        fallbackGroup.orientation = .vertical; fallbackGroup.alignment = .leading; fallbackGroup.spacing = 3
        fallbackHintRow.widthAnchor.constraint(equalTo: fallbackGroup.widthAnchor).isActive = true
        let zoneTitle = NSTextField(labelWithString: "輸出時區")
        let zoneRow = NSStackView(views: [zoneTitle, NSView(), outputTimeZone]); zoneRow.spacing = 12
        outputTimeZone.widthAnchor.constraint(equalTo: zoneRow.widthAnchor, multiplier: 0.65).isActive = true
        outputTimeZone.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let zoneDivider = NSBox(); zoneDivider.boxType = .separator
        let scanGroup = group([recursive], height: 64)
        let timeGroup = group([fallbackGroup, quickTimeUTC, zoneDivider, zoneRow], height: 176)
        scanGroup.setAccessibilityLabel("掃描範圍"); timeGroup.setAccessibilityLabel("時間處理")
        let explanation = NSTextField(wrappingLabelWithString: "僅換算 QuickTime 建立時間；其他拍攝時間保留原值。關閉 UTC 解讀時不換算時區。")
        explanation.font = .systemFont(ofSize: 12); explanation.textColor = .secondaryLabelColor
        let cancel = NSButton(title: "取消", target: self, action: #selector(cancelSettings)); cancel.bezelStyle = .rounded; cancel.keyEquivalent = "\u{1b}"
        settingsApply.title = "套用"
        settingsApply.target = self; settingsApply.action = #selector(applySettings); settingsApply.bezelStyle = .rounded; settingsApply.keyEquivalent = "\r"
        namingReset = NSButton(title: "回復預設", target: self, action: #selector(resetNaming)); namingReset.bezelStyle = .rounded; namingReset.isHidden = true
        let buttons = NSStackView(views: [namingReset, NSView(), cancel, settingsApply]); buttons.spacing = 8
        let divider = NSBox(); divider.boxType = .separator
        let spacer = NSView(); spacer.setContentHuggingPriority(.defaultLow, for: .vertical)
        let scanBody = NSStackView(views: [scanTitle, scanGroup, timeTitle, timeGroup, explanation, spacer])
        scanBody.orientation = .vertical; scanBody.alignment = .leading; scanBody.spacing = 12
        for view in [scanGroup, timeGroup, explanation, spacer] as [NSView] { view.widthAnchor.constraint(equalTo: scanBody.widthAnchor).isActive = true }
        let scanHost = NSView(); install(scanBody, in: scanHost, inset: 0)
        settingsTabs = NSTabView()
        settingsTabs.tabViewType = .noTabsNoBorder
        let scanTab = NSTabViewItem(identifier: "scan"); scanTab.label = "掃描"; scanTab.view = scanHost
        let namingTab = NSTabViewItem(identifier: "naming"); namingTab.label = "命名"; namingTab.view = makeNamingView()
        settingsTabs.addTabViewItem(scanTab); settingsTabs.addTabViewItem(namingTab); settingsTabs.selectTabViewItem(at: 0)
        settingsTabHeight = settingsTabs.heightAnchor.constraint(equalToConstant: 380); settingsTabHeight?.isActive = true
        settingsSections = NSSegmentedControl(labels: ["掃描", "命名"], trackingMode: .selectOne, target: self, action: #selector(selectSettingsSection(_:)))
        settingsSections.selectedSegment = 0
        let applyHint = NSTextField(labelWithString: "套用後更新更名預覽。")
        applyHint.font = .systemFont(ofSize: 11); applyHint.textColor = .secondaryLabelColor
        let body = NSStackView(views: [settingsSections, settingsTabs, divider, buttons, applyHint])
        body.orientation = .vertical; body.alignment = .centerX; body.spacing = 12
        install(body, in: panel.contentView!, inset: 24)
        for view in [settingsTabs, divider, buttons, applyHint] as [NSView] { view.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true }
        updateNamingSample()
        return panel
    }
    @objc func showSettings() {
        guard commandEnabled(#selector(showSettings)) else { return }
        let panel = makeSettingsPanel(); settingsPanel = panel
        sheetPending = true; refreshControls()
        window.beginSheet(panel) { _ in
            self.settingsPanel = nil; self.sheetPending = false; self.refreshControls()
        }
    }
    @objc func cancelSettings() {
        guard let panel = settingsPanel else { return }
        window.endSheet(panel); panel.orderOut(nil)
    }
    @objc func applySettings() {
        guard let panel = settingsPanel else { return }
        let new = ScanSettings(recursive: recursive.state == .on, fallback: fallback.state == .on,
            quickTimeUTC: quickTimeUTC.state == .on, timeZoneID: outputTimeZone.titleOfSelectedItem ?? "")
        guard TimeZone(identifier: new.timeZoneID) != nil else { NSSound.beep(); return }
        do { try validateNamingRule(namingField.stringValue) } catch { settingsTabs.selectTabViewItem(at: 1); settingsSections.selectedSegment = 1; selectSettingsSection(settingsSections); updateNamingSample(); return }
        guard settingsApply.isEnabled else { settingsTabs.selectTabViewItem(at: 1); settingsSections.selectedSegment = 1; selectSettingsSection(settingsSections); return }
        let changed = new != settings || namingRule != namingField.stringValue
        namingRule = namingField.stringValue; appearanceDefaults.set(namingRule, forKey: "PhotoDateNamingRule")
        settings = new; window.endSheet(panel); panel.orderOut(nil)
        sheetPending = false
        if changed && root != nil { rescan() } else { refreshControls() }
    }
    func updateLocation(_ folder: URL) {
        locationButton.setAccessibilityLabel("所在位置：上層資料夾")
        let parent = folder.deletingLastPathComponent()
        let menu = NSMenu()
        let title = NSMenuItem(title: parent.path == "/" ? "磁碟根目錄" : parent.lastPathComponent, action: nil, keyEquivalent: "")
        title.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        menu.addItem(title); menu.addItem(.separator())
        var ancestor = folder
        while true {
            menu.addItem(NSMenuItem(title: ancestor.path == "/" ? "磁碟根目錄" : ancestor.lastPathComponent, action: nil, keyEquivalent: ""))
            if ancestor.path == "/" { break }
            ancestor = ancestor.deletingLastPathComponent()
        }
        menu.addItem(.separator())
        let copy = NSMenuItem(title: "複製完整路徑", action: #selector(copyFolderPath), keyEquivalent: "")
        copy.target = self; menu.addItem(copy)
        locationButton.menu = menu; locationButton.toolTip = folder.path
    }
    @objc func showFolderPath() {
        guard let root, !busy && !sheetPending else { return }
        let panel = NSAlert(); panel.messageText = importURLs.isEmpty || (importURLs.count == 1 && importURLs[0] == root) ? "資料夾完整路徑" : "匯入來源"; panel.informativeText = (importURLs.isEmpty ? [root] : importURLs).map(\.path).joined(separator: "\n") + (importURLs.count > 1 ? "\n\n復原紀錄存放於：\n" + root.path : "")
        panel.addButton(withTitle: "完成"); panel.addButton(withTitle: "複製路徑")
        sheetPending = true; refreshControls()
        panel.beginSheetModal(for: window) { response in
            if response == .alertSecondButtonReturn { self.copyFolderPath() }
            self.sheetPending = false; self.refreshControls()
        }
    }
    @objc func copyFolderPath() {
        guard let root else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString((importURLs.isEmpty ? [root] : importURLs).map(\.path).joined(separator: "\n"), forType: .string)
    }
    @objc func updateTimeZoneControl() { outputTimeZone.isEnabled = quickTimeUTC.state == .on }
    @objc func rescan() {
        guard !busy && !sheetPending, let root else { return }
        let options = settings
        let inputs = importURLs.isEmpty ? [root] : importURLs
        let rule = namingRule
        let sequences = sequenceNumbers
        guard let zone = TimeZone(identifier: options.timeZoneID) else { alert("無效時區", "請選擇有效的輸出時區。"); return }
        resultFrozen = false; restoredResult = false; completedURLs.removeAll(); attemptedURLs.removeAll()
        resultLabel.stringValue = ""; selectedURLs.removeAll(); rows = []; rebuildVisibleRows()
        heading.stringValue = "讀取中繼資料"
        setBusy(true, "掃描中…大型資料夾可能需要幾分鐘；目前不會變更任何檔案。")
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try scan(inputs, recursive: options.recursive, fallback: options.fallback,
                                          quickTimeUTC: options.quickTimeUTC, outputTimeZone: zone, namingRule: rule, sequenceNumbers: sequences) }
            DispatchQueue.main.async {
                self.setBusy(false, ""); self.heading.stringValue = "更名預覽"
                switch result {
                case .success(let rows):
                    self.rows = rows
                    for row in rows where row.sequence > 0 { self.sequenceNumbers[row.original] = row.sequence }
                    if rows.isEmpty {
                        self.heading.stringValue = "沒有可處理的照片或影片"
                        self.summary.stringValue = ""
                        self.resultLabel.stringValue = "請選擇其他資料夾，或重新掃描。"
                        self.resultLabel.textColor = .labelColor
                    }
                case .failure(let error):
                    self.heading.stringValue = "掃描失敗"; self.resultLabel.stringValue = error.localizedDescription
                    self.resultLabel.textColor = .labelColor
                }
                self.rebuildVisibleRows(); self.postStatusAnnouncement()
            }
        }
    }
    @objc func revealFile() {
        guard commandEnabled(#selector(revealFile)) else { return }
        if visibleIndices.indices.contains(table.selectedRow) {
            let url = currentURL(rows[visibleIndices[table.selectedRow]])
            if FileManager.default.fileExists(atPath: url.path) { NSWorkspace.shared.activateFileViewerSelecting([url]); return }
        }
        if let root { NSWorkspace.shared.open(root) }
    }
    @objc func renameCurrent() { rename(scope.indexOfSelectedItem == 1 ? selectedRows : rows, scopeName: scope.titleOfSelectedItem ?? "全部可用項目") }
    @objc func renameAll() { rename(rows, scopeName: "全部可用項目") }
    @objc func renameSelected() { rename(selectedRows, scopeName: "選取項目") }
    func rename(_ candidates: [PlanRow], scopeName: String) {
        guard let root, !busy && !sheetPending && !resultFrozen else { return }
        let selected = candidates.filter(\.actionable)
        guard !selected.isEmpty else { return }
        let alert = NSAlert(); alert.messageText = "重新命名 \(selected.count) 個檔案？"
        let warnings = selected.filter { $0.status.contains("核對") }.count
        alert.informativeText = "範圍：\(scopeName)\n\(selected.count) 個檔案更名，\(rows.count-selected.count) 個保留原名。"
            + (warnings > 0 ? "\n\(warnings) 個時間來源需核對。" : "")
            + (importURLs.count > 1 ? "\n復原紀錄將存放於：\(root.path)" : "")
            + "\n\n依預覽更名並保留復原紀錄，不改寫媒體內容。請避免其他程式同時整理檔案。"
        alert.addButton(withTitle: "取消"); alert.addButton(withTitle: "確認重新命名")
        sheetPending = true; refreshControls()
        alert.beginSheetModal(for: window) { response in
            self.sheetPending = false
            guard response == .alertSecondButtonReturn else { self.refreshControls(); return }
            self.lastLog = nil; self.attemptedURLs = Set(selected.map(\.original))
            self.heading.stringValue = "正在重新命名"
            self.setBusy(true, "正在重新命名並保留復原紀錄…")
            DispatchQueue.global(qos: .userInitiated).async {
                let result = Result { try apply(selected, root: root) }
                DispatchQueue.main.async {
                    self.resultFrozen = true; self.setBusy(false, "")
                    switch result {
                    case .success(let log):
                        for row in selected { if let number = self.sequenceNumbers.removeValue(forKey: row.original) { self.sequenceNumbers[row.destination!] = number } }
                        self.importURLs = self.importURLs.map { url in selected.first(where: { $0.original == url })?.destination ?? url }; self.updateImportLocation()
                        self.lastLog = log; self.completedURLs = Set(selected.map(\.original))
                        self.heading.stringValue = "更名完成"
                        self.summary.stringValue = "已更名 \(selected.count) 個檔案 · 其餘 \(self.rows.count-selected.count) 個不變"
                        self.resultLabel.stringValue = "可復原這次更名，或重新掃描建立新的預覽。"
                        self.resultLabel.textColor = .labelColor
                    case .failure(let error):
                        self.heading.stringValue = "操作已停止"
                        self.summary.stringValue = "部分操作可能已完成；請核對檔案與復原紀錄。"
                        self.resultLabel.stringValue = error.localizedDescription
                        self.resultLabel.textColor = .labelColor
                    }
                    self.rebuildVisibleRows(); self.postStatusAnnouncement()
                }
            }
        }
    }
    @objc func restoreLast() {
        guard commandEnabled(#selector(restoreLast)), let log = lastLog else { return }; confirmRestore(log)
    }
    @objc func restoreLog() {
        guard commandEnabled(#selector(restoreLog)) else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.showsHiddenFiles = true
        panel.directoryURL = lastLog?.deletingLastPathComponent() ?? root
        panel.message = "選擇 .photodate- 開頭的 JSON 復原紀錄；多次操作請從最新紀錄往回復原。"
        sheetPending = true; refreshControls()
        panel.beginSheetModal(for: window) { response in
            self.sheetPending = false
            if response == .OK, let log = panel.url { self.confirmRestore(log) } else { self.refreshControls() }
        }
    }
    func confirmRestore(_ log: URL) {
        let alert = NSAlert(); alert.messageText = "依這份紀錄復原檔名？"
        alert.informativeText = "會核對檔案識別與原檔名是否被占用；檔案已變更或遺失時會停止。"
        let path = NSPathControl(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        path.url = log; path.pathStyle = .popUp; path.toolTip = log.path
        path.setAccessibilityLabel("此次復原紀錄路徑")
        alert.accessoryView = path
        alert.addButton(withTitle: "取消"); alert.addButton(withTitle: "確認復原")
        sheetPending = true; refreshControls()
        alert.beginSheetModal(for: window) { response in
            self.sheetPending = false
            guard response == .alertSecondButtonReturn else { self.refreshControls(); return }
            self.heading.stringValue = "正在復原"
            self.setBusy(true, "正在核對檔案並復原…")
            DispatchQueue.global(qos: .userInitiated).async {
                let result = Result { try undo(log) }
                DispatchQueue.main.async {
                    self.setBusy(false, "")
                    switch result {
                    case .success(let count):
                        if let data = try? Data(contentsOf: log), let journal = try? JSONDecoder().decode(Journal.self, from: data) {
                            for entry in journal.entries { if let number = self.sequenceNumbers.removeValue(forKey: entry.destination) { self.sequenceNumbers[entry.original] = number } }
                            self.importURLs = self.importURLs.map { url in journal.entries.first(where: { $0.destination == url })?.original ?? url }; self.updateImportLocation()
                        }
                        self.lastLog = nil; self.completedURLs.removeAll(); self.attemptedURLs.removeAll()
                        self.resultFrozen = true; self.restoredResult = true; self.filter.selectedSegment = 0
                        self.selectedURLs.removeAll(); self.heading.stringValue = "復原完成"
                        self.summary.stringValue = "已復原 \(count) 個檔名。重新掃描後可建立新的更名預覽。"
                        self.resultLabel.stringValue = "復原紀錄已保留。"
                        self.resultLabel.textColor = .labelColor
                    case .failure(let error):
                        self.resultFrozen = true; self.completedURLs.removeAll()
                        self.heading.stringValue = "復原已停止"
                        self.summary.stringValue = "復原可能部分完成；請核對檔案與紀錄，重新掃描前不允許再次更名。"
                        self.resultLabel.stringValue = error.localizedDescription; self.resultLabel.textColor = .labelColor
                    }
                    self.rebuildVisibleRows(); self.postStatusAnnouncement()
                }
            }
        }
    }
    @objc func exportCSV() {
        guard commandEnabled(#selector(exportCSV)) else { return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Toki-preview.csv"; panel.allowedContentTypes = [.commaSeparatedText]
        sheetPending = true; refreshControls()
        panel.beginSheetModal(for: window) { response in
            self.sheetPending = false
            guard response == .OK, let url = panel.url else { self.refreshControls(); return }
            func quote(_ value: String) -> String {
                let safe = ["=", "+", "-", "@", "\t", "\r"].contains(where: { value.hasPrefix($0) }) ? "'" + value : value
                return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            }
            let data = [["原始路徑", "新路徑", "原始時間／換算結果", "來源", "狀態"]] + self.rows.map {
                [$0.original.path, $0.destination?.path ?? "", $0.date, $0.source, self.displayStatus($0)]
            }
            do {
                try ("\u{FEFF}" + data.map { $0.map(quote).joined(separator: ",") }.joined(separator: "\r\n")).write(to: url, atomically: true, encoding: .utf8)
                self.refreshControls(); self.status.stringValue = "已匯出預覽：\(url.lastPathComponent)"; self.status.toolTip = url.path
            } catch { self.alert("匯出失敗", error.localizedDescription) }
        }
    }
    func alert(_ title: String, _ message: String) {
        guard window.attachedSheet == nil else { NSSound.beep(); return }
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = message
        sheetPending = true; refreshControls()
        alert.beginSheetModal(for: window) { _ in self.sheetPending = false; self.refreshControls() }
    }
    func windowDidEndSheet(_ notification: Notification) {
        DispatchQueue.main.async { self.refreshControls() }
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if busy || sheetPending { alert("作業進行中", "請等目前作業或對話框完成再關閉視窗。"); return false }; return true
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if busy || sheetPending { alert("作業進行中", "請等目前作業或對話框完成再結束。"); return .terminateCancel }; return .terminateNow
    }
}
