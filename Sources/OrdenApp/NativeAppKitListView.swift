import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ImageIO
import OrdenCore

private func decodeNativeListCGThumbnail(atPath path: String, maxPixelSize: Int) -> CGImage? {
    let url = URL(fileURLWithPath: path) as CFURL
    let srcOpts: [CFString: Any] = [kCGImageSourceShouldCache: false]
    guard let source = CGImageSourceCreateWithURL(url, srcOpts as CFDictionary) else { return nil }
    let thumbOpts: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceShouldCacheImmediately: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
    ]
    return CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOpts as CFDictionary)
}

@MainActor
private enum NativeListSharedCache {
    static let iconCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 2048
        return cache
    }()

    static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .short
        df.timeStyle = .short
        return df
    }()

    private static let rasterExtensions: Set<String> = [
        "png", "jpg", "jpeg", "webp", "heic", "gif", "tiff", "bmp"
    ]

    static func icon(for entry: FileEntry, onThumbnailLoaded: @escaping @MainActor (NSImage) -> Void) -> NSImage {
        if entry.isDirectory {
            if entry.path.lowercased().hasSuffix(".app") {
                let appKey = "app:\(entry.path)" as NSString
                if let cached = iconCache.object(forKey: appKey) {
                    return cached
                }
                let img = NSWorkspace.shared.icon(forFile: entry.path)
                iconCache.setObject(img, forKey: appKey)
                return img
            }
            let folderKey = "folder:generic" as NSString
            if let cached = iconCache.object(forKey: folderKey) {
                return cached
            }
            let img = NSWorkspace.shared.icon(for: .folder)
            iconCache.setObject(img, forKey: folderKey)
            return img
        }

        let ext = (entry.name as NSString).pathExtension.lowercased()
        let modStamp = Int(entry.dateModified.timeIntervalSince1970)
        if rasterExtensions.contains(ext) {
            let thumbKey = "thumb:\(entry.path):\(modStamp)" as NSString
            if let thumb = iconCache.object(forKey: thumbKey) {
                return thumb
            }
            let pathCopy = entry.path
            Task(priority: .utility) {
                guard let cg = await Task.detached(priority: .utility, operation: {
                    decodeNativeListCGThumbnail(atPath: pathCopy, maxPixelSize: 56)
                }).value else { return }
                let nsImg = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
                iconCache.setObject(nsImg, forKey: thumbKey)
                onThumbnailLoaded(nsImg)
            }
        }

        let extKey = "ext:\(ext)" as NSString
        if let cached = iconCache.object(forKey: extKey) {
            return cached
        }
        let fallback: NSImage
        if !ext.isEmpty, let ut = UTType(filenameExtension: ext) {
            fallback = NSWorkspace.shared.icon(for: ut)
        } else {
            fallback = NSWorkspace.shared.icon(for: .data)
        }
        iconCache.setObject(fallback, forKey: extKey)
        return fallback
    }
}

@MainActor
private final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, keyEquivalent: String = "", handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(invoke), keyEquivalent: keyEquivalent)
        self.target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func invoke() {
        handler()
    }
}

@MainActor
private final class FindaroTableRowView: NSTableRowView {
    var zebra: Bool = false
    var isArmedOrange: Bool = false

    override var isEmphasized: Bool {
        get { true }
        set {}
    }

    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }
        let color = isArmedOrange
            ? NSColor.systemOrange.withAlphaComponent(0.28)
            : NSColor(OrdenTheme.rowSelectionFill)
        color.setFill()
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 1), xRadius: 6, yRadius: 6)
        path.fill()
    }

    override func drawBackground(in dirtyRect: NSRect) {
        if isArmedOrange && !isSelected {
            NSColor.systemOrange.withAlphaComponent(0.16).setFill()
            bounds.fill()
            return
        }
        if zebra {
            NSColor.labelColor.withAlphaComponent(0.03).setFill()
            bounds.fill()
        }
    }
}

@MainActor
private final class FindaroSectionCellView: NSTableCellView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let hintLabel = NSTextField(labelWithString: "")

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(OrdenTheme.accent).withAlphaComponent(0.08).cgColor

        titleLabel.font = .systemFont(ofSize: 11, weight: .bold)
        titleLabel.textColor = NSColor(OrdenTheme.accent)
        titleLabel.lineBreakMode = .byTruncatingTail

        hintLabel.font = .systemFont(ofSize: 10, weight: .medium)
        hintLabel.textColor = .tertiaryLabelColor
        hintLabel.alignment = .right

        addSubview(titleLabel)
        addSubview(hintLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(category: FileCategory, count: Int) {
        titleLabel.stringValue = "\(category.labelLocalized.uppercased()) · \(count)"
        hintLabel.stringValue = L10n.s("clic = todos", "click = all")
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let w = bounds.width
        let h = bounds.height
        let hintW: CGFloat = 90
        titleLabel.frame = NSRect(x: 14, y: floor((h - 15) / 2), width: max(60, w - hintW - 28), height: 15)
        hintLabel.frame = NSRect(x: max(14, w - hintW - 14), y: floor((h - 14) / 2), width: hintW, height: 14)
    }
}

@MainActor
private final class FindaroEntryCellView: NSTableCellView {
    private let iconImageView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let pathLabel = NSTextField(labelWithString: "")
    private let copyButton = NSButton()
    private var metaLabels: [NSTextField] = []

    private(set) var representedPath: String = ""
    private var activeColumns: [ListColumn] = []
    private var isCompact: Bool = false
    private var showRowPaths: Bool = true
    var onCopyPath: (() -> Void)?

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        iconImageView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(iconImageView)

        nameLabel.font = .systemFont(ofSize: 13, weight: .medium)
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.maximumNumberOfLines = 1
        addSubview(nameLabel)

        pathLabel.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.maximumNumberOfLines = 1
        addSubview(pathLabel)

        for _ in 0..<6 {
            let lbl = NSTextField(labelWithString: "")
            lbl.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            lbl.textColor = .secondaryLabelColor
            lbl.lineBreakMode = .byTruncatingTail
            lbl.isHidden = true
            addSubview(lbl)
            metaLabels.append(lbl)
        }

        copyButton.bezelStyle = .inline
        copyButton.isBordered = false
        copyButton.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
        copyButton.contentTintColor = NSColor(OrdenTheme.accent)
        copyButton.toolTip = L10n.s("Copiar ruta completa", "Copy full path")
        copyButton.target = self
        copyButton.action = #selector(handleCopyTap)
        addSubview(copyButton)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    @objc private func handleCopyTap() {
        onCopyPath?()
    }

    func configure(
        entry: FileEntry,
        columns: [ListColumn],
        isCompact: Bool,
        showRowPaths: Bool,
        isCut: Bool,
        isMeasuringSizes: Bool,
        onCopy: @escaping () -> Void
    ) {
        self.representedPath = entry.path
        self.activeColumns = columns
        self.isCompact = isCompact
        self.showRowPaths = showRowPaths
        self.onCopyPath = onCopy
        self.alphaValue = isCut ? 0.44 : 1.0

        if isCut {
            nameLabel.attributedStringValue = NSAttributedString(
                string: entry.name,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                    .foregroundColor: NSColor.secondaryLabelColor,
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue
                ]
            )
        } else {
            nameLabel.attributedStringValue = NSAttributedString(
                string: entry.name,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                    .foregroundColor: NSColor.labelColor
                ]
            )
        }

        pathLabel.stringValue = entry.path
        pathLabel.isHidden = !showRowPaths

        let targetPath = entry.path
        iconImageView.image = NativeListSharedCache.icon(for: entry) { [weak self] loadedThumb in
            guard let self, self.representedPath == targetPath else { return }
            self.iconImageView.image = loadedThumb
        }

        for (idx, lbl) in metaLabels.enumerated() {
            guard idx < columns.count else {
                lbl.isHidden = true
                continue
            }
            let col = columns[idx]
            let w = isCompact ? col.compactWidth : col.width
            guard w > 0 else {
                lbl.isHidden = true
                continue
            }
            lbl.isHidden = false
            lbl.alignment = (col == .size) ? .right : .left
            switch col {
            case .kind:
                lbl.stringValue = entry.category.labelLocalized
                lbl.textColor = .secondaryLabelColor
                lbl.font = .systemFont(ofSize: 11, weight: .regular)
            case .dateAdded:
                lbl.stringValue = NativeListSharedCache.dateFormatter.string(from: entry.dateAdded)
                lbl.textColor = .secondaryLabelColor
                lbl.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            case .dateModified:
                lbl.stringValue = NativeListSharedCache.dateFormatter.string(from: entry.dateModified)
                lbl.textColor = .secondaryLabelColor
                lbl.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            case .dateCreated:
                lbl.stringValue = NativeListSharedCache.dateFormatter.string(from: entry.dateCreated)
                lbl.textColor = .secondaryLabelColor
                lbl.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            case .dateLastOpened:
                lbl.stringValue = entry.dateLastOpened == .distantPast
                    ? "—"
                    : NativeListSharedCache.dateFormatter.string(from: entry.dateLastOpened)
                lbl.textColor = entry.dateLastOpened == .distantPast ? .tertiaryLabelColor : .secondaryLabelColor
                lbl.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            case .size:
                if entry.size <= 0 && entry.isDirectory {
                    lbl.stringValue = isMeasuringSizes ? "…" : "—"
                } else {
                    lbl.stringValue = FolderSizer.format(entry.size)
                }
                lbl.textColor = entry.size > 500_000_000 ? .systemOrange : .secondaryLabelColor
                lbl.font = .monospacedDigitSystemFont(
                    ofSize: 11,
                    weight: entry.size > 100_000_000 ? .semibold : .regular
                )
            }
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let w = bounds.width
        let h = bounds.height
        let spacing: CGFloat = isCompact ? 8 : 12

        copyButton.frame = NSRect(x: max(0, w - 38), y: floor((h - 28) / 2), width: 28, height: 28)

        var cursorX = copyButton.frame.minX
        for idx in stride(from: min(activeColumns.count, metaLabels.count) - 1, through: 0, by: -1) {
            let col = activeColumns[idx]
            let colW = isCompact ? col.compactWidth : col.width
            guard colW > 0 else { continue }
            cursorX -= (spacing + colW)
            metaLabels[idx].frame = NSRect(x: cursorX, y: floor((h - 16) / 2), width: colW, height: 16)
        }

        iconImageView.frame = NSRect(x: 15, y: floor((h - 20) / 2), width: 20, height: 20)

        let textX: CGFloat = 46
        let textW = max(60, cursorX - spacing - textX)
        if showRowPaths {
            let totalTextH: CGFloat = 32
            let topY = floor((h - totalTextH) / 2)
            nameLabel.frame = NSRect(x: textX, y: topY, width: textW, height: 18)
            pathLabel.frame = NSRect(x: textX, y: topY + 18, width: textW, height: 14)
        } else {
            nameLabel.frame = NSRect(x: textX, y: floor((h - 18) / 2), width: textW, height: 18)
        }
    }
}

@MainActor
private final class MarqueeOverlayNSView: NSView {
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let accent = NSColor(OrdenTheme.accent)
        accent.withAlphaComponent(0.18).setFill()
        let path = NSBezierPath(roundedRect: bounds, xRadius: 3, yRadius: 3)
        path.fill()
        accent.withAlphaComponent(0.85).setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

@MainActor
fileprivate final class FindaroFastTableView: NSTableView {
    var trailingChromeWidth: CGFloat = 38
    var onActivatePane: (() -> Void)?
    var onIsSectionOrGapRow: ((Int) -> Bool)?
    var onRowTapSpecial: ((Int) -> Void)?
    var onMetaEntryClick: ((Int, NSEvent) -> Void)?
    var onBackgroundClick: (() -> Void)?
    var onMarqueeBegin: ((Bool) -> Void)?
    var onMarqueeUpdate: ((NSRange, Bool) -> Void)?
    var onBuildContextMenu: ((Int) -> NSMenu?)?
    var onClearDropTarget: (() -> Void)?

    private let marqueeOverlay = MarqueeOverlayNSView(frame: .zero)

    override var acceptsFirstResponder: Bool { false }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        onClearDropTarget?()
        super.draggingExited(sender)
    }

    override func mouseDown(with event: NSEvent) {
        if window?.firstResponder is NSTextView {
            window?.makeFirstResponder(nil)
        }
        onActivatePane?()

        let localStart = convert(event.locationInWindow, from: nil)
        if let hit = hitTest(localStart), hit is NSButton {
            super.mouseDown(with: event)
            return
        }

        let clicked = row(at: localStart)
        let isSpecial = clicked >= 0 ? (onIsSectionOrGapRow?(clicked) ?? false) : false
        let inTrailing = localStart.x >= max(220, bounds.width - trailingChromeWidth)

        if clicked >= 0 && !isSpecial && !inTrailing {
            super.mouseDown(with: event)
            return
        }

        guard let win = window else { return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let additive = flags.contains(.shift) || flags.contains(.command)
        var committed = false

        if marqueeOverlay.superview == nil {
            marqueeOverlay.isHidden = true
            addSubview(marqueeOverlay)
        }

        while let next = win.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            let current = convert(next.locationInWindow, from: nil)
            switch next.type {
            case .leftMouseDragged:
                autoscroll(with: next)
                let dist = hypot(current.x - localStart.x, current.y - localStart.y)
                if dist >= PressDragSelectLogic.moveThreshold {
                    if !committed {
                        committed = true
                        onMarqueeBegin?(additive)
                        marqueeOverlay.isHidden = false
                    }
                    let rect = NSRect(
                        x: min(localStart.x, current.x),
                        y: min(localStart.y, current.y),
                        width: max(1, abs(current.x - localStart.x)),
                        height: max(1, abs(current.y - localStart.y))
                    )
                    marqueeOverlay.frame = rect
                    marqueeOverlay.needsDisplay = true
                    let range = rows(in: rect)
                    onMarqueeUpdate?(range, additive)
                }
            case .leftMouseUp:
                marqueeOverlay.isHidden = true
                if !committed {
                    if clicked == -1 {
                        onBackgroundClick?()
                    } else if isSpecial {
                        onRowTapSpecial?(clicked)
                    } else {
                        onMetaEntryClick?(clicked, event)
                    }
                }
                return
            default:
                break
            }
        }
        marqueeOverlay.isHidden = true
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let pt = convert(event.locationInWindow, from: nil)
        let r = row(at: pt)
        guard r >= 0 else { return nil }
        return onBuildContextMenu?(r)
    }
}

struct NativeAppKitListView: NSViewRepresentable {
    @ObservedObject var browser: BrowserModel
    let pane: BrowserModel.PaneFocus
    let rows: [ListPaneRow]
    let columns: [ListColumn]
    let rowHeight: CGFloat
    let isCompact: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(browser: browser, pane: pane)
    }

    func makeNSView(context: Context) -> NSScrollView {
        FileDragArmMonitor.shared.invalidateFrames()

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        let tableView = FindaroFastTableView()
        tableView.headerView = nil
        tableView.style = .plain
        tableView.intercellSpacing = .zero
        tableView.backgroundColor = .clear
        tableView.allowsMultipleSelection = true
        tableView.allowsEmptySelection = true
        tableView.usesAutomaticRowHeights = false
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle

        let mainCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("FindaroMainCol"))
        mainCol.resizingMask = .autoresizingMask
        tableView.addTableColumn(mainCol)

        let coord = context.coordinator
        coord.tableView = tableView
        tableView.delegate = coord
        tableView.dataSource = coord
        tableView.target = coord
        tableView.doubleAction = #selector(Coordinator.handleDoubleClick(_:))
        tableView.registerForDraggedTypes([.fileURL])
        tableView.setDraggingSourceOperationMask([.copy, .move], forLocal: false)
        tableView.setDraggingSourceOperationMask([.copy, .move], forLocal: true)

        coord.wireCallbacks(on: tableView)
        scrollView.documentView = tableView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coord = context.coordinator
        coord.browser = browser
        coord.pane = pane
        coord.sync(
            rows: rows,
            columns: columns,
            rowHeight: rowHeight,
            isCompact: isCompact
        )
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var browser: BrowserModel
        var pane: BrowserModel.PaneFocus
        fileprivate weak var tableView: FindaroFastTableView?

        private var rows: [ListPaneRow] = []
        private var columns: [ListColumn] = []
        private var rowHeight: CGFloat = 44
        private var isCompact: Bool = false

        private var lastDataSignature: Int = 0
        private var lastRevealToken: Int = -1
        private var lastFocusID: String?
        private var isProgrammaticSelection = false
        private var marqueeBaseIDs: Set<String> = []

        private var isSecondary: Bool { pane == .secondary }

        init(browser: BrowserModel, pane: BrowserModel.PaneFocus) {
            self.browser = browser
            self.pane = pane
        }

        fileprivate func wireCallbacks(on tv: FindaroFastTableView) {
            tv.onActivatePane = { [weak self] in
                guard let self, self.browser.dualPaneEnabled else { return }
                if self.browser.focusedPane != self.pane {
                    self.browser.focusPane(self.pane)
                }
            }
            tv.onIsSectionOrGapRow = { [weak self] rowIdx in
                guard let self, self.rows.indices.contains(rowIdx) else { return false }
                if case .entry = self.rows[rowIdx] { return false }
                return true
            }
            tv.onRowTapSpecial = { [weak self] rowIdx in
                guard let self, self.rows.indices.contains(rowIdx) else { return }
                switch self.rows[rowIdx] {
                case .section(let category, _), .gap(let category):
                    self.browser.selectVisibleCategory(category, pane: self.pane)
                case .entry:
                    break
                }
            }
            tv.onMetaEntryClick = { [weak self] rowIdx, event in
                guard let self, self.rows.indices.contains(rowIdx),
                      case .entry(let entry) = self.rows[rowIdx] else { return }
                if event.clickCount == 2 {
                    if self.isSecondary {
                        self.browser.openSecondaryEntry(entry)
                    } else {
                        self.browser.activateEntry(entry)
                    }
                    return
                }
                if self.isSecondary {
                    self.browser.clickSelectSecondary(entry.id)
                } else {
                    self.browser.clickSelect(entry.id)
                }
            }
            tv.onBackgroundClick = { [weak self] in
                guard let self else { return }
                self.browser.cancelSelectionFromBackgroundTap(activating: self.pane)
            }
            tv.onMarqueeBegin = { [weak self] additive in
                guard let self else { return }
                let active = self.isSecondary ? self.browser.secondarySelectedIDs : self.browser.selectedIDs
                self.marqueeBaseIDs = additive ? active : []
                if !additive {
                    if self.isSecondary {
                        self.browser.clearSecondarySelection()
                    } else {
                        self.browser.clearSelection()
                    }
                }
            }
            tv.onMarqueeUpdate = { [weak self] nsRange, additive in
                guard let self else { return }
                var hits = Set<String>()
                if nsRange.length > 0 {
                    let upper = min(self.rows.count, nsRange.location + nsRange.length)
                    if nsRange.location < upper {
                        for idx in nsRange.location..<upper {
                            if case .entry(let e) = self.rows[idx] {
                                hits.insert(e.id)
                            }
                        }
                    }
                }
                if self.isSecondary {
                    self.browser.applySecondaryMarqueeSelection(hitIDs: hits, base: self.marqueeBaseIDs, additive: additive)
                } else {
                    self.browser.applyMarqueeSelection(hitIDs: hits, base: self.marqueeBaseIDs, additive: additive)
                }
            }
            tv.onBuildContextMenu = { [weak self] rowIdx in
                self?.buildContextMenu(forRow: rowIdx)
            }
            tv.onClearDropTarget = { [weak self] in
                self?.browser.folderDropTargetPath = nil
            }
        }

        func sync(
            rows: [ListPaneRow],
            columns: [ListColumn],
            rowHeight: CGFloat,
            isCompact: Bool
        ) {
            guard let tv = tableView else { return }
            tv.trailingChromeWidth = ListColumn.totalWidth(columns, compact: isCompact) + 38

            var hasher = Hasher()
            hasher.combine(rows.count)
            for r in rows {
                hasher.combine(r.id)
                if case .entry(let e) = r {
                    hasher.combine(e.size)
                    hasher.combine(e.dateModified.timeIntervalSince1970)
                }
            }
            for col in columns {
                hasher.combine(col.id)
            }
            hasher.combine(Int(rowHeight))
            hasher.combine(isCompact)
            hasher.combine(browser.showRowPaths)
            hasher.combine(browser.isMeasuringSizes)
            hasher.combine(browser.fileDragArmedPaths)
            for item in browser.shelf where item.intent == .move {
                hasher.combine(item.path)
            }
            let sig = hasher.finalize()

            if sig != lastDataSignature {
                self.rows = rows
                self.columns = columns
                self.rowHeight = rowHeight
                self.isCompact = isCompact
                self.lastDataSignature = sig
                isProgrammaticSelection = true
                tv.reloadData()
                isProgrammaticSelection = false
            }

            syncSelectionToTable(tv)

            if !isSecondary, browser.revealToken != lastRevealToken {
                lastRevealToken = browser.revealToken
                if let revealID = browser.revealEntryID,
                   let idx = self.rows.firstIndex(where: {
                       if case .entry(let e) = $0 { return e.id == revealID }
                       return false
                   }) {
                    tv.scrollRowToVisible(idx)
                }
            }

            let focus = isSecondary ? browser.secondarySelectionFocusID : browser.selectionFocusID
            if focus != lastFocusID {
                lastFocusID = focus
                if let focus,
                   let idx = self.rows.firstIndex(where: {
                       if case .entry(let e) = $0 { return e.id == focus }
                       return false
                   }) {
                    tv.scrollRowToVisible(idx)
                }
            }
        }

        private func syncSelectionToTable(_ tv: NSTableView) {
            let wanted = isSecondary ? browser.secondarySelectedIDs : browser.selectedIDs
            var indexSet = IndexSet()
            if !wanted.isEmpty {
                for (idx, r) in rows.enumerated() {
                    if case .entry(let e) = r, wanted.contains(e.id) {
                        indexSet.insert(idx)
                    }
                }
            }
            guard tv.selectedRowIndexes != indexSet else { return }
            isProgrammaticSelection = true
            tv.selectRowIndexes(indexSet, byExtendingSelection: false)
            isProgrammaticSelection = false
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            rows.count
        }

        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            guard rows.indices.contains(row) else { return rowHeight }
            switch rows[row] {
            case .section:
                return ListPaneLayout.sectionHeight
            case .gap:
                return ListPaneLayout.gapHeight
            case .entry:
                return rowHeight
            }
        }

        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
            guard rows.indices.contains(row) else { return false }
            if case .entry = rows[row] { return true }
            return false
        }

        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            let id = NSUserInterfaceItemIdentifier("FindaroRow")
            let rv = (tableView.makeView(withIdentifier: id, owner: nil) as? FindaroTableRowView)
                ?? {
                    let v = FindaroTableRowView()
                    v.identifier = id
                    return v
                }()
            rv.zebra = row.isMultiple(of: 2)
            if rows.indices.contains(row), case .entry(let entry) = rows[row] {
                rv.isArmedOrange = browser.isFileDragArmed(path: entry.path)
            } else {
                rv.isArmedOrange = false
            }
            return rv
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard rows.indices.contains(row) else { return nil }
            switch rows[row] {
            case .section(let category, let count):
                let id = NSUserInterfaceItemIdentifier("FindaroSectionCell")
                let cell = (tableView.makeView(withIdentifier: id, owner: nil) as? FindaroSectionCellView)
                    ?? {
                        let c = FindaroSectionCellView(frame: .zero)
                        c.identifier = id
                        return c
                    }()
                cell.configure(category: category, count: count)
                return cell

            case .gap:
                let id = NSUserInterfaceItemIdentifier("FindaroGapCell")
                if let reused = tableView.makeView(withIdentifier: id, owner: nil) {
                    return reused
                }
                let gap = NSView()
                gap.identifier = id
                return gap

            case .entry(let entry):
                let id = NSUserInterfaceItemIdentifier("FindaroEntryCell")
                let cell = (tableView.makeView(withIdentifier: id, owner: nil) as? FindaroEntryCellView)
                    ?? {
                        let c = FindaroEntryCellView(frame: .zero)
                        c.identifier = id
                        return c
                    }()
                let b = browser
                cell.configure(
                    entry: entry,
                    columns: columns,
                    isCompact: isCompact,
                    showRowPaths: b.showRowPaths,
                    isCut: b.isCutPending(path: entry.path),
                    isMeasuringSizes: b.isMeasuringSizes,
                    onCopy: { [weak b] in
                        b?.copyPath(entry)
                    }
                )
                return cell
            }
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isProgrammaticSelection, let tv = tableView else { return }
            var ids = Set<String>()
            var firstID: String?
            for idx in tv.selectedRowIndexes where rows.indices.contains(idx) {
                if case .entry(let e) = rows[idx] {
                    ids.insert(e.id)
                    if firstID == nil { firstID = e.id }
                }
            }
            browser.applyNativeTableSelection(ids: ids, focusID: firstID, pane: pane)
        }

        @objc func handleDoubleClick(_ sender: Any?) {
            guard let tv = tableView else { return }
            let r = tv.clickedRow
            guard rows.indices.contains(r), case .entry(let entry) = rows[r] else { return }
            if isSecondary {
                browser.openSecondaryEntry(entry)
            } else {
                browser.activateEntry(entry)
            }
        }

        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
            guard rows.indices.contains(row), case .entry(let entry) = rows[row] else { return nil }
            return NSURL(fileURLWithPath: entry.path)
        }

        func tableView(
            _ tableView: NSTableView,
            draggingSession session: NSDraggingSession,
            endedAt screenPoint: NSPoint,
            operation: NSDragOperation
        ) {
            browser.folderDropTargetPath = nil
            if operation != [] {
                browser.clearArmedFileDrag()
                browser.reload()
                if browser.dualPaneEnabled {
                    browser.reloadSecondary()
                }
            }
        }

        func tableView(
            _ tableView: NSTableView,
            validateDrop info: any NSDraggingInfo,
            proposedRow row: Int,
            proposedDropOperation dropOperation: NSTableView.DropOperation
        ) -> NSDragOperation {
            let op: NSDragOperation = NSEvent.modifierFlags.contains(.option) ? .copy : .move
            if dropOperation == .on,
               rows.indices.contains(row),
               case .entry(let target) = rows[row],
               target.isDirectory {
                browser.folderDropTargetPath = target.path
                return op
            }
            browser.folderDropTargetPath = nil
            tableView.setDropRow(-1, dropOperation: .on)
            return op
        }

        func tableView(
            _ tableView: NSTableView,
            acceptDrop info: any NSDraggingInfo,
            row: Int,
            dropOperation: NSTableView.DropOperation
        ) -> Bool {
            browser.folderDropTargetPath = nil
            guard let urls = info.draggingPasteboard.readObjects(
                forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true]
            ) as? [URL], !urls.isEmpty else {
                return false
            }
            let paths = urls.map(\.path)
            if dropOperation == .on,
               rows.indices.contains(row),
               case .entry(let target) = rows[row],
               target.isDirectory {
                browser.dropPaths(paths, intoFolder: target.path)
                return true
            }
            let copy = NSEvent.modifierFlags.contains(.option)
            if browser.dualPaneEnabled {
                if isSecondary {
                    return browser.dropPathsOnSecondary(paths, copy: copy)
                } else {
                    return browser.dropPathsOnPrimary(paths, copy: copy)
                }
            }
            browser.addPathsToShelf(paths, intent: copy ? .copy : .move)
            return true
        }

        private func buildContextMenu(forRow rowIdx: Int) -> NSMenu? {
            guard rows.indices.contains(rowIdx), case .entry(let entry) = rows[rowIdx] else { return nil }
            let b = browser
            let sec = isSecondary

            let ensureAlone: @MainActor () -> Void = {
                if sec { b.selectSecondaryOnly(entry.id) } else { b.selectOnly(entry.id) }
            }
            let ensureIncluded: @MainActor () -> Void = {
                if sec {
                    if !b.secondarySelectedIDs.contains(entry.id) {
                        b.selectSecondaryOnly(entry.id)
                    } else {
                        b.focusPane(.secondary)
                    }
                } else if !b.selectedIDs.contains(entry.id) {
                    b.selectOnly(entry.id)
                }
            }

            ensureIncluded()
            let selectedCount = sec ? b.secondarySelectedIDs.count : b.selectedIDs.count

            let menu = NSMenu()
            menu.addItem(ClosureMenuItem(title: L10n.s("Abrir", "Open")) {
                ensureAlone()
                if sec { b.openSecondaryEntry(entry) } else { b.open(entry) }
            })

            if !entry.isDirectory {
                let apps = b.appsForOpening(entry)
                if !apps.isEmpty {
                    let openWithItem = NSMenuItem(title: L10n.s("Abrir con", "Open With"), action: nil, keyEquivalent: "")
                    let sub = NSMenu()
                    for app in apps {
                        sub.addItem(ClosureMenuItem(title: app.name) {
                            b.open(entry, withApplicationAt: app.url)
                        })
                    }
                    openWithItem.submenu = sub
                    menu.addItem(openWithItem)
                }
            }

            menu.addItem(ClosureMenuItem(title: L10n.s("Vista rápida", "Quick Look")) {
                ensureAlone()
                b.openPreviewExplicitly()
            })
            menu.addItem(ClosureMenuItem(title: L10n.s("Obtener información", "Get Info")) {
                ensureAlone()
                b.showInfo(entry)
            })

            if entry.isDirectory {
                if b.isFavorite(entry.path) {
                    menu.addItem(ClosureMenuItem(title: L10n.s("Quitar de Favoritos", "Remove from Favorites")) {
                        b.removeFavorite(entry.path)
                    })
                } else {
                    menu.addItem(ClosureMenuItem(title: L10n.s("Añadir a Favoritos", "Add to Favorites")) {
                        b.addFavorite(entry.path)
                    })
                }
            }

            menu.addItem(.separator())

            menu.addItem(ClosureMenuItem(
                title: selectedCount > 1
                    ? L10n.s("Renombrado masivo…", "Batch Rename…")
                    : L10n.s("Renombrar", "Rename")
            ) {
                ensureIncluded()
                b.promptRename()
            })
            if selectedCount == 1 {
                menu.addItem(ClosureMenuItem(title: L10n.s("Renombrado masivo…", "Batch Rename…")) {
                    ensureIncluded()
                    b.promptBatchRename()
                })
            }

            menu.addItem(ClosureMenuItem(title: L10n.s("Duplicar", "Duplicate")) {
                ensureIncluded()
                b.duplicateSelection()
            })
            menu.addItem(ClosureMenuItem(title: L10n.s("Comprimir", "Compress")) {
                ensureIncluded()
                b.compressSelection()
            })
            if ArchiveOps.isExtractable(entry.path) {
                menu.addItem(ClosureMenuItem(title: L10n.s("Descomprimir aquí", "Extract here")) {
                    ensureAlone()
                    b.extractArchive(entry, intoSecondary: sec)
                })
            }

            menu.addItem(.separator())

            menu.addItem(ClosureMenuItem(title: L10n.s("Copiar a bandeja", "Copy to Tray")) {
                ensureIncluded()
                b.addSelectionToShelf(intent: .copy)
            })
            menu.addItem(ClosureMenuItem(title: L10n.s("Cortar a bandeja", "Cut to Tray")) {
                ensureIncluded()
                b.addSelectionToShelf(intent: .move)
            })
            menu.addItem(ClosureMenuItem(title: L10n.s("Copiar ruta completa", "Copy Full Path")) {
                b.copyPath(entry)
            })
            menu.addItem(ClosureMenuItem(
                title: DefaultFileViewerManager.isEnabled
                    ? L10n.s("Abrir carpeta en Finder", "Open folder in Finder")
                    : L10n.s("Mostrar en Finder", "Show in Finder")
            ) {
                b.revealInFinder(entry)
            })

            if b.dualPaneEnabled {
                menu.addItem(.separator())
                if sec {
                    menu.addItem(ClosureMenuItem(title: L10n.s("Mover a Origen", "Move to Origin")) {
                        ensureIncluded()
                        b.transferSecondarySelectionToPrimary(copy: false)
                    })
                    menu.addItem(ClosureMenuItem(title: L10n.s("Copiar a Origen", "Copy to Origin")) {
                        ensureIncluded()
                        b.transferSecondarySelectionToPrimary(copy: true)
                    })
                } else {
                    menu.addItem(ClosureMenuItem(title: L10n.s("Mover a Destino", "Move to Destination")) {
                        ensureIncluded()
                        b.transferPrimarySelectionToSecondary(copy: false)
                    })
                    menu.addItem(ClosureMenuItem(title: L10n.s("Copiar a Destino", "Copy to Destination")) {
                        ensureIncluded()
                        b.transferPrimarySelectionToSecondary(copy: true)
                    })
                }
            }

            menu.addItem(.separator())

            if b.activeIsTrash {
                menu.addItem(ClosureMenuItem(title: L10n.s("Sacar de la Papelera", "Restore from Trash")) {
                    ensureIncluded()
                    b.restoreSelectionFromTrash()
                })
                menu.addItem(ClosureMenuItem(title: L10n.s("Eliminar para siempre", "Delete Permanently")) {
                    ensureIncluded()
                    b.permanentlyDeleteSelection(confirm: true)
                })
            } else {
                menu.addItem(ClosureMenuItem(title: L10n.s("Mover a la Papelera", "Move to Trash")) {
                    ensureIncluded()
                    b.moveSelectionToTrash()
                })
            }

            return menu
        }
    }
}
