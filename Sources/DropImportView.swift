import AppKit

final class DropImportView: NSView {
    var canImport: () -> Bool = { true }
    var onImport: ([URL]) -> Void = { _ in }
    private var highlighted = false { didSet { needsDisplay = true } }
    override init(frame: NSRect) { super.init(frame: frame); registerForDraggedTypes([.fileURL]) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func importURLs(from pasteboard: NSPasteboard) -> [URL] {
        (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let urls = importURLs(from: sender.draggingPasteboard)
        highlighted = canImport() && sender.draggingSourceOperationMask.contains(.copy) && (try? validateImportSources(urls)) != nil
        return highlighted ? .copy : []
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { draggingEntered(sender) }
    override func draggingExited(_ sender: NSDraggingInfo?) { highlighted = false }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { canImport() && highlighted }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        highlighted = false
        return acceptDrop(from: sender.draggingPasteboard)
    }
    func acceptDrop(from pasteboard: NSPasteboard) -> Bool {
        let urls = importURLs(from: pasteboard)
        guard canImport(), let validated = try? validateImportSources(urls) else { return false }
        onImport(validated); return true
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if highlighted {
            NSColor.controlAccentColor.setStroke()
            let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 6, dy: 6), xRadius: 8, yRadius: 8)
            border.lineWidth = 3; border.stroke()
        }
    }
}
