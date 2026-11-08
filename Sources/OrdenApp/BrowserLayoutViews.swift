import SwiftUI
import AppKit
import OrdenCore

// MARK: - Selector tipo Finder

struct ViewModePicker: View {
    @EnvironmentObject private var browser: BrowserModel

    var body: some View {
        HStack(spacing: 0) {
            ForEach(BrowserViewMode.allCases) { mode in
                Button {
                    browser.setViewMode(mode)
                } label: {
                    Image(systemName: mode.symbolName)
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 28, height: 22)
                        .background(
                            browser.viewMode == mode
                                ? Color.primary.opacity(0.14)
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .help(mode.labelSpanish)
            }
        }
        .padding(3)
        .background(Color.primary.opacity(0.08), in: Capsule())
    }
}

// MARK: - Checkbox compartido (igual que lista)

struct SelectionCheckButton: View {
    @EnvironmentObject private var browser: BrowserModel
    let entryID: String

    private var isSelected: Bool {
        browser.selectedIDs.contains(entryID)
    }

    var body: some View {
        Button {
            browser.toggleSelection(entryID)
        } label: {
            Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                .font(.body)
                .foregroundStyle(isSelected ? OrdenTheme.accent : .secondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Marcar / desmarcar")
    }
}

/// Misma lógica que `FileRowButton.selectRow`.
/// El doble clic para abrir lo maneja el gesto SwiftUI de cada fila (no frames AppKit).
@MainActor
func browserSelectEntry(_ browser: BrowserModel, entry: FileEntry, openOnDoubleClick: Bool = true) {
    _ = openOnDoubleClick
    if FindaroTextInput.isEditing {
        NSApp.keyWindow?.makeFirstResponder(nil)
    }
    browser.clickSelect(entry.id)
}

// MARK: - Iconos (misma selección que lista: marquee + jalar carpetas)

struct IconsBrowserView: View {
    @EnvironmentObject private var browser: BrowserModel
    @Environment(\.ordenWindowWidth) private var windowWidth
    @Environment(\.ordenLayoutGeneration) private var layoutGeneration
    @Environment(\.ordenMetrics) private var metrics

    /// Celda según pantalla — layout y hit-test DEBEN usar el mismo `colCount`.
    private var cellW: CGFloat { metrics.iconCell }
    private var cellH: CGFloat { metrics.iconCell }
    private var spacing: CGFloat { metrics.iconSpacing }
    private var gridPadding: CGFloat { metrics.contentPadding }

    @State private var localWidth: CGFloat = 0
    @State private var marqueeStart: CGPoint?
    @State private var marqueeCurrent: CGPoint?
    @State private var marqueeBase: Set<String> = []
    @State private var marqueeAdditive = false
    @State private var folderDragPaths: [String] = []
    @State private var folderDragStarted = false

    /// Ancho efectivo: preferir medida local; si no, la del resize de ventana.
    private var containerWidth: CGFloat {
        if localWidth > 1 { return localWidth }
        if windowWidth > 1 { return windowWidth - 32 } // padding del detail
        return 900
    }

    /// Columnas reales: mismo número para LazyVGrid y para el marquee.
    private var colCount: Int {
        let inner = max(cellW, containerWidth - gridPadding * 2)
        return max(1, Int(floor((inner + spacing) / (cellW + spacing))))
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.fixed(cellW), spacing: spacing), count: colCount)
    }

    private var rowCount: Int {
        let n = browser.visibleEntries.count
        guard n > 0 else { return 0 }
        return Int(ceil(Double(n) / Double(colCount)))
    }

    private var gridContentHeight: CGFloat {
        guard rowCount > 0 else { return 0 }
        return CGFloat(rowCount) * cellH + CGFloat(max(0, rowCount - 1)) * spacing
    }

    var body: some View {
        VStack(spacing: 0) {
            iconsHeader
                .fixedSize(horizontal: false, vertical: true)

            Divider().opacity(0.35)

            ScrollView {
                VStack(spacing: 0) {
                    LazyVGrid(columns: gridColumns, alignment: .leading, spacing: spacing) {
                        ForEach(browser.visibleEntries) { entry in
                            IconsItemCell(entry: entry)
                                .frame(width: cellW, height: cellH)
                        }
                    }
                    .id("icons-grid-\(colCount)-\(layoutGeneration)")
                    .padding(gridPadding)

                    // Zona vacía: igual que lista — clic cancela; arrastre inicia marquee
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .frame(height: 320)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            browser.cancelSelectionFromBackgroundTap(activating: .primary)
                        }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .coordinateSpace(name: "iconsGrid")
                .overlay(alignment: .topLeading) {
                    if let rect = marqueeRect {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(OrdenTheme.accent.opacity(0.18))
                            .overlay(
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .strokeBorder(OrdenTheme.accent.opacity(0.85), lineWidth: 1)
                            )
                            .frame(width: rect.width, height: rect.height)
                            .offset(x: rect.minX, y: rect.minY)
                            .allowsHitTesting(false)
                    }
                }
                .contentShape(Rectangle())
                .highPriorityGesture(iconsMarqueeGesture)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .readLayoutWidth { w in
                if abs(w - localWidth) >= 1 {
                    localWidth = w
                }
            }
            .onTapGesture {
                browser.cancelSelectionFromBackgroundTap(activating: .primary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(OrdenTheme.panelFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.06), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onChange(of: browser.selectionCancelToken) { _, _ in
            resetMarquee()
        }
        .onChange(of: layoutGeneration) { _, _ in
            // El resize ya actualizó windowWidth; limpiar marquee a medias
            resetMarquee()
        }
    }

    private var iconsHeader: some View {
        HStack(spacing: 12) {
            Button {
                browser.toggleSelectAllVisible()
            } label: {
                Image(systemName: browser.allVisibleSelected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(OrdenTheme.accent)
                    .frame(width: 22)
            }
            .buttonStyle(.plain)
            .help("Seleccionar / quitar todos")

            Text("Iconos")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(browser.selectedIDs.count) sel.")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func resetMarquee() {
        marqueeStart = nil
        marqueeCurrent = nil
        marqueeBase = []
        folderDragPaths = []
        folderDragStarted = false
    }

    private var marqueeRect: CGRect? {
        guard folderDragPaths.isEmpty else { return nil }
        guard let start = marqueeStart, let current = marqueeCurrent else { return nil }
        return CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: max(abs(current.x - start.x), 1),
            height: max(abs(current.y - start.y), 1)
        )
    }

    private var iconsMarqueeGesture: some Gesture {
        DragGesture(minimumDistance: PressDragSelectLogic.moveThreshold, coordinateSpace: .named("iconsGrid"))
            .onChanged { value in
                if marqueeStart == nil {
                    let flags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
                    if flags.contains(.command), !browser.hasArmedFileDrag {
                        return
                    }
                    if browser.hasArmedFileDrag {
                        marqueeStart = value.startLocation
                        marqueeCurrent = value.location
                        folderDragPaths = browser.peekArmedFileDrag()
                        folderDragStarted = false
                        return
                    }
                    if browser.fileDragArmingPath != nil { return }
                    if !browser.selectedIDs.isEmpty {
                        marqueeStart = value.startLocation
                        marqueeCurrent = value.location
                        folderDragPaths = browser.selectedEntries.map(\.path)
                        folderDragStarted = false
                        return
                    }
                    marqueeStart = value.startLocation
                    marqueeCurrent = value.location
                    folderDragPaths = []
                    marqueeAdditive = flags.contains(.shift)
                    marqueeBase = marqueeAdditive ? browser.selectedIDs : []
                    if !marqueeAdditive { browser.clearSelection() }
                }
                if !folderDragPaths.isEmpty {
                    let dist = hypot(value.translation.width, value.translation.height)
                    if !folderDragStarted, dist >= PressDragSelectLogic.moveThreshold {
                        folderDragStarted = true
                        _ = browser.startDragWithPaths(folderDragPaths)
                    }
                    return
                }
                marqueeCurrent = value.location
                applyIconsMarquee()
            }
            .onEnded { _ in
                if folderDragPaths.isEmpty { applyIconsMarquee() }
                resetMarquee()
            }
    }

    private func applyIconsMarquee() {
        guard let start = marqueeStart, let current = marqueeCurrent else { return }
        let entries = browser.visibleEntries
        guard !entries.isEmpty else { return }

        let rect = CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: max(abs(current.x - start.x), 1),
            height: max(abs(current.y - start.y), 1)
        )

        let contentBottom = gridPadding + gridContentHeight
        if rect.minY >= contentBottom {
            browser.applyMarqueeSelection(hitIDs: [], base: marqueeBase, additive: marqueeAdditive)
            return
        }

        let cols = colCount
        var hits = Set<String>()
        for (idx, entry) in entries.enumerated() {
            let row = idx / cols
            let col = idx % cols
            let cell = CGRect(
                x: gridPadding + CGFloat(col) * (cellW + spacing),
                y: gridPadding + CGFloat(row) * (cellH + spacing),
                width: cellW,
                height: cellH
            )
            if cell.intersects(rect) {
                hits.insert(entry.id)
            }
        }
        browser.applyMarqueeSelection(hitIDs: hits, base: marqueeBase, additive: marqueeAdditive)
    }
}

private struct IconsItemCell: View {
    @EnvironmentObject private var browser: BrowserModel
    let entry: FileEntry

    private var isSelected: Bool {
        browser.selectedIDs.contains(entry.id)
    }

    private var isCut: Bool {
        browser.isCutPending(path: entry.path)
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                SelectionCheckButton(entryID: entry.id)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)

            Button {
                browserSelectEntry(browser, entry: entry)
            } label: {
                VStack(spacing: 6) {
                    ZStack {
                        FileTypeIcon(category: entry.category, path: entry.path, size: 36)
                        FileDragArmChrome.Overlay(path: entry.path, size: 44)
                    }
                    .frame(width: 48, height: 48)
                    Text(entry.name)
                        .font(.caption)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 96)
                        .foregroundStyle(isCut ? .secondary : .primary)
                        .strikethrough(isCut)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(isCut ? 0.42 : 1)
        .background(
            isSelected ? OrdenTheme.accent.opacity(0.28) : Color.clear,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .fileDragArmHighlight(path: entry.path)
        .reportFileDragArmFrame(path: entry.path)
        .folderDropTarget(entry: entry)
        .fileOpenOnDoubleClick(entry: entry, browser: browser)
        .fileDragArmPress(entry: entry, browser: browser)
        .contextMenu { entryContextMenu(entry) }
    }
}

// MARK: - Columnas (cada columna = lista con el mismo marquee)

struct ColumnsBrowserView: View {
    @EnvironmentObject private var browser: BrowserModel

    var body: some View {
        VStack(spacing: 0) {
            columnsHeader
                .fixedSize(horizontal: false, vertical: true)
            Divider().opacity(0.35)
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(browser.columnPaths.enumerated()), id: \.offset) { index, path in
                        ColumnPane(path: path, columnIndex: index)
                        Divider()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(OrdenTheme.panelFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.06), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onAppear {
            if browser.columnPaths.isEmpty {
                browser.columnPaths = [browser.currentPath]
            }
        }
    }

    private var columnsHeader: some View {
        HStack(spacing: 12) {
            Button {
                browser.toggleSelectAllVisible()
            } label: {
                Image(systemName: browser.allVisibleSelected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(OrdenTheme.accent)
                    .frame(width: 22)
            }
            .buttonStyle(.plain)
            .help("Seleccionar / quitar todos")

            Text("Columnas")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(browser.selectedIDs.count) sel.")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

/// Copia del marquee de `listBrowser`, aplicado a una columna.
private struct ColumnPane: View {
    @EnvironmentObject private var browser: BrowserModel
    let path: String
    let columnIndex: Int

    private let rowHeight: CGFloat = 28

    @State private var entries: [FileEntry] = []
    @State private var marqueeStart: CGPoint?
    @State private var marqueeCurrent: CGPoint?
    @State private var marqueeBase: Set<String> = []
    @State private var marqueeAdditive = false
    @State private var folderDragPaths: [String] = []
    @State private var folderDragStarted = false

    private var sortedEntries: [FileEntry] {
        SortEngine.sort(entries, by: browser.rule)
    }

    private var listContentHeight: CGFloat {
        CGFloat(sortedEntries.count) * rowHeight
    }

    private var spaceName: String { "columnList-\(columnIndex)" }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(sortedEntries) { entry in
                    ColumnRow(entry: entry, columnIndex: columnIndex)
                        .frame(minHeight: rowHeight)
                }
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: 320)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        browser.cancelSelectionFromBackgroundTap(activating: .primary)
                    }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .coordinateSpace(name: spaceName)
            .overlay(alignment: .topLeading) {
                if let rect = marqueeRect {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(OrdenTheme.accent.opacity(0.18))
                        .overlay(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .strokeBorder(OrdenTheme.accent.opacity(0.85), lineWidth: 1)
                        )
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .highPriorityGesture(marqueeGesture)
        }
        .frame(width: 240)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .onTapGesture {
            browser.cancelSelectionFromBackgroundTap(activating: .primary)
        }
        .onAppear(perform: reload)
        .onChange(of: path) { _, _ in reload() }
        .onChange(of: browser.rule) { _, _ in reload() }
        .onChange(of: browser.selectionCancelToken) { _, _ in
            resetMarquee()
        }
    }

    private func reload() {
        entries = (try? DirectoryLoader.load(path: path)) ?? []
    }

    private func resetMarquee() {
        marqueeStart = nil
        marqueeCurrent = nil
        marqueeBase = []
        folderDragPaths = []
        folderDragStarted = false
    }

    private var marqueeRect: CGRect? {
        guard folderDragPaths.isEmpty else { return nil }
        guard let start = marqueeStart, let current = marqueeCurrent else { return nil }
        return CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: max(abs(current.x - start.x), 1),
            height: max(abs(current.y - start.y), 1)
        )
    }

    private var marqueeGesture: some Gesture {
        DragGesture(minimumDistance: PressDragSelectLogic.moveThreshold, coordinateSpace: .named(spaceName))
            .onChanged { value in
                if marqueeStart == nil {
                    let flags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
                    if flags.contains(.command), !browser.hasArmedFileDrag {
                        return
                    }
                    if browser.hasArmedFileDrag {
                        marqueeStart = value.startLocation
                        marqueeCurrent = value.location
                        folderDragPaths = browser.peekArmedFileDrag()
                        folderDragStarted = false
                        return
                    }
                    if browser.fileDragArmingPath != nil { return }
                    if !browser.selectedIDs.isEmpty {
                        marqueeStart = value.startLocation
                        marqueeCurrent = value.location
                        folderDragPaths = browser.selectedEntries.map(\.path)
                        folderDragStarted = false
                        return
                    }
                    marqueeStart = value.startLocation
                    marqueeCurrent = value.location
                    folderDragPaths = []
                    marqueeAdditive = flags.contains(.shift)
                    marqueeBase = marqueeAdditive ? browser.selectedIDs : []
                    if !marqueeAdditive { browser.clearSelection() }
                }
                if !folderDragPaths.isEmpty {
                    let dist = hypot(value.translation.width, value.translation.height)
                    if !folderDragStarted, dist >= PressDragSelectLogic.moveThreshold {
                        folderDragStarted = true
                        _ = browser.startDragWithPaths(folderDragPaths)
                    }
                    return
                }
                marqueeCurrent = value.location
                applyMarquee()
            }
            .onEnded { _ in
                if folderDragPaths.isEmpty { applyMarquee() }
                resetMarquee()
            }
    }

    private func applyMarquee() {
        guard let start = marqueeStart, let current = marqueeCurrent else { return }
        let entries = sortedEntries
        guard !entries.isEmpty else { return }

        let y0 = min(start.y, current.y)
        let y1 = max(start.y, current.y)
        let contentH = listContentHeight

        if y0 >= contentH {
            browser.applyMarqueeSelection(hitIDs: [], base: marqueeBase, additive: marqueeAdditive)
            return
        }

        let first = max(0, Int(floor(y0 / rowHeight)))
        let last = min(entries.count - 1, Int(floor((min(y1, contentH) - 0.001) / rowHeight)))
        guard first <= last else {
            browser.applyMarqueeSelection(hitIDs: [], base: marqueeBase, additive: marqueeAdditive)
            return
        }
        let hits = Set(entries[first...last].map(\.id))
        browser.applyMarqueeSelection(hitIDs: hits, base: marqueeBase, additive: marqueeAdditive)
    }
}

private struct ColumnRow: View {
    @EnvironmentObject private var browser: BrowserModel
    let entry: FileEntry
    let columnIndex: Int

    private var isSelected: Bool {
        browser.selectedIDs.contains(entry.id)
    }

    private var isOpenInNextColumn: Bool {
        let next = columnIndex + 1
        guard next < browser.columnPaths.count else { return false }
        return browser.columnPaths[next] == entry.path
    }

    var body: some View {
        HStack(spacing: 4) {
            SelectionCheckButton(entryID: entry.id)
                .padding(.leading, 6)

            Button {
                handleClick()
            } label: {
                HStack(spacing: 8) {
                    ZStack {
                        FileTypeIcon(category: entry.category, path: entry.path, size: 14)
                        FileDragArmChrome.Overlay(path: entry.path, size: 22)
                    }
                    .frame(width: 22, height: 22)
                    Text(entry.name)
                        .font(.callout)
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                    Spacer(minLength: 0)
                    if entry.isDirectory {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .background(
            (isSelected || isOpenInNextColumn)
                ? OrdenTheme.accent.opacity(0.25)
                : Color.clear
        )
        .fileDragArmHighlight(path: entry.path)
        .reportFileDragArmFrame(path: entry.path)
        .folderDropTarget(entry: entry)
        .fileOpenOnDoubleClick(entry: entry, browser: browser)
        .fileDragArmPress(entry: entry, browser: browser)
        .contextMenu { entryContextMenu(entry) }
    }

    private func handleClick() {
        let flags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let keepingMulti = flags.contains(.command) || flags.contains(.shift) || browser.multiSelectMode
        browser.clickSelect(entry.id)
        // En columnas, clic simple en carpeta también abre; ⌘/⇧/Varios solo seleccionan.
        if !keepingMulti, entry.isDirectory {
            browser.openInColumns(entry, columnIndex: columnIndex)
        }
    }
}

// MARK: - Galería

struct GalleryBrowserView: View {
    @EnvironmentObject private var browser: BrowserModel

    private var focusEntry: FileEntry? {
        browser.selectedEntries.first ?? browser.visibleEntries.first
    }

    var body: some View {
        VStack(spacing: 0) {
            galleryHeader
            Divider().opacity(0.35)

            ZStack {
                OrdenTheme.panelFill
                if let entry = focusEntry {
                    GalleryPreview(entry: entry)
                        .padding(20)
                } else {
                    ContentUnavailableView("Vacío", systemImage: "photo.on.rectangle")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider().opacity(0.35)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(browser.visibleEntries) { entry in
                        GalleryThumb(entry: entry, focused: focusEntry?.id == entry.id)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .frame(height: 118)
            .background(OrdenTheme.panelFill)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.06), lineWidth: 1)
        )
    }

    private var galleryHeader: some View {
        HStack(spacing: 12) {
            Button {
                browser.toggleSelectAllVisible()
            } label: {
                Image(systemName: browser.allVisibleSelected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(OrdenTheme.accent)
                    .frame(width: 22)
            }
            .buttonStyle(.plain)
            .help("Seleccionar / quitar todos")

            Text("Galería")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(browser.selectedIDs.count) sel.")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

private struct GalleryPreview: View {
    @EnvironmentObject private var browser: BrowserModel
    let entry: FileEntry

    var body: some View {
        VStack(spacing: 12) {
            if let image = NSImage(contentsOfFile: entry.path), !entry.isDirectory {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                FileTypeIcon(category: entry.category, path: entry.path, size: 72)
            }
            Text(entry.name)
                .font(.headline)
            if browser.showRowPaths {
                Text(entry.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

private struct GalleryThumb: View {
    @EnvironmentObject private var browser: BrowserModel
    let entry: FileEntry
    let focused: Bool

    private var isSelected: Bool {
        browser.selectedIDs.contains(entry.id)
    }

    var body: some View {
        VStack(spacing: 4) {
            SelectionCheckButton(entryID: entry.id)

            Button {
                browserSelectEntry(browser, entry: entry)
            } label: {
                VStack(spacing: 4) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                            .frame(width: 64, height: 52)
                        if let image = NSImage(contentsOfFile: entry.path), !entry.isDirectory {
                            Image(nsImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 64, height: 52)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        } else {
                            FileTypeIcon(category: entry.category, path: entry.path, size: 22)
                        }
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(
                                (focused || isSelected) ? OrdenTheme.accent : Color.clear,
                                lineWidth: 2
                            )
                    )
                    Text(entry.name)
                        .font(.caption2)
                        .lineLimit(1)
                        .frame(width: 72)
                        .foregroundStyle(.primary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(4)
        .background(
            isSelected ? OrdenTheme.accent.opacity(0.2) : Color.clear,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .contextMenu { entryContextMenu(entry) }
    }
}

// MARK: - Menú contextual compartido

@MainActor
@ViewBuilder
func entryContextMenu(_ entry: FileEntry) -> some View {
    EntryContextMenuButtons(entry: entry)
}

private struct EntryContextMenuButtons: View {
    @EnvironmentObject private var browser: BrowserModel
    let entry: FileEntry

    var body: some View {
        Button("Abrir") {
            browser.selectOnly(entry.id)
            browser.activateEntry(entry)
        }
        OpenWithMenu(entry: entry)
        Button("Obtener información") {
            browser.selectOnly(entry.id)
            browser.showInfo(entry)
        }
        if entry.isDirectory {
            if browser.isFavorite(entry.path) {
                Button("Quitar de Favoritos") { browser.removeFavorite(entry.path) }
            } else {
                Button("Añadir a Favoritos") { browser.addFavorite(entry.path) }
            }
        }
        Button("Renombrar") {
            browser.selectOnly(entry.id)
            browser.promptRename()
        }
        Button("Comprimir") {
            if !browser.selectedIDs.contains(entry.id) {
                browser.selectOnly(entry.id)
            }
            browser.compressSelection()
        }
        if ArchiveOps.isExtractable(entry.path) {
            Button("Descomprimir aquí") {
                browser.selectOnly(entry.id)
                browser.extractArchive(entry, intoSecondary: false)
            }
        }
        Button("A bandeja") {
            if !browser.selectedIDs.contains(entry.id) {
                browser.selectOnly(entry.id)
            }
            browser.addSelectionToShelf()
        }
        Button("Mostrar en Finder") { browser.revealInFinder(entry) }
        Divider()
        if browser.isViewingTrash {
            Button("Sacar de la Papelera") {
                if !browser.selectedIDs.contains(entry.id) {
                    browser.selectOnly(entry.id)
                }
                browser.restoreSelectionFromTrash()
            }
            Button("Eliminar para siempre", role: .destructive) {
                if !browser.selectedIDs.contains(entry.id) {
                    browser.selectOnly(entry.id)
                }
                browser.permanentlyDeleteSelection(confirm: true)
            }
        } else {
            Button("Mover a la Papelera", role: .destructive) {
                if !browser.selectedIDs.contains(entry.id) {
                    browser.selectOnly(entry.id)
                }
                browser.moveSelectionToTrash()
            }
        }
    }
}
