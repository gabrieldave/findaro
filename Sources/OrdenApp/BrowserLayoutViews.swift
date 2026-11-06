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

/// Misma lógica que `FileRowButton.selectRow`: doble clic abre; ⇧ rango; ⌘ / modo varios toggle.
@MainActor
func browserSelectEntry(_ browser: BrowserModel, entry: FileEntry, openOnDoubleClick: Bool = true) {
    if openOnDoubleClick, (NSApp.currentEvent?.clickCount ?? 1) >= 2 {
        browser.selectOnly(entry.id)
        browser.activateEntry(entry)
        return
    }
    browser.clickSelect(entry.id)
}

// MARK: - Iconos

struct IconsBrowserView: View {
    @EnvironmentObject private var browser: BrowserModel

    private let columns = [GridItem(.adaptive(minimum: 110, maximum: 130), spacing: 12)]

    @State private var itemFrames: [String: CGRect] = [:]
    @State private var marqueeStart: CGPoint?
    @State private var marqueeCurrent: CGPoint?
    @State private var marqueeBase: Set<String> = []
    @State private var marqueeAdditive = false

    var body: some View {
        VStack(spacing: 0) {
            iconsHeader
            Divider().opacity(0.35)
            ScrollView {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(browser.visibleEntries) { entry in
                        IconsItemCell(entry: entry)
                            .background(
                                GeometryReader { geo in
                                    Color.clear.preference(
                                        key: IconFrameKey.self,
                                        value: [entry.id: geo.frame(in: .named("iconsGrid"))]
                                    )
                                }
                            )
                    }
                }
                .padding(16)
                .coordinateSpace(name: "iconsGrid")
                .onPreferenceChange(IconFrameKey.self) { itemFrames = $0 }
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
            .onTapGesture {
                browser.cancelSelection()
            }
        }
        .background(OrdenTheme.panelFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.06), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onChange(of: browser.selectionCancelToken) { _, _ in
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

    private var marqueeRect: CGRect? {
        guard let start = marqueeStart, let current = marqueeCurrent else { return nil }
        return CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: max(abs(current.x - start.x), 1),
            height: max(abs(current.y - start.y), 1)
        )
    }

    private var iconsMarqueeGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("iconsGrid"))
            .onChanged { value in
                if marqueeStart == nil {
                    marqueeStart = value.startLocation
                    marqueeCurrent = value.location
                    let flags = NSEvent.modifierFlags
                    marqueeAdditive = flags.contains(.command) || flags.contains(.shift)
                    marqueeBase = marqueeAdditive ? browser.selectedIDs : []
                    if !marqueeAdditive {
                        browser.clearSelection()
                    }
                }
                marqueeCurrent = value.location
                applyIconsMarquee()
            }
            .onEnded { _ in
                applyIconsMarquee()
                resetMarquee()
            }
    }

    private func applyIconsMarquee() {
        guard let rect = marqueeRect else { return }
        let hits = Set(itemFrames.compactMap { id, frame in
            frame.intersects(rect) ? id : nil
        })
        browser.applyMarqueeSelection(hitIDs: hits, base: marqueeBase, additive: marqueeAdditive)
    }

    private func resetMarquee() {
        marqueeStart = nil
        marqueeCurrent = nil
        marqueeBase = []
    }
}

private struct IconFrameKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private struct IconsItemCell: View {
    @EnvironmentObject private var browser: BrowserModel
    let entry: FileEntry

    private var isSelected: Bool {
        browser.selectedIDs.contains(entry.id)
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
                    FileTypeIcon(category: entry.category, size: 36)
                    Text(entry.name)
                        .font(.caption)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 96)
                        .foregroundStyle(.primary)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .frame(width: 118, height: 118)
        .background(
            isSelected ? OrdenTheme.accent.opacity(0.28) : Color.clear,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .contextMenu { entryContextMenu(entry) }
    }
}

// MARK: - Columnas

struct ColumnsBrowserView: View {
    @EnvironmentObject private var browser: BrowserModel

    var body: some View {
        VStack(spacing: 0) {
            columnsHeader
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
            .help("Seleccionar / quitar todos (columna activa)")

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

private struct ColumnPane: View {
    @EnvironmentObject private var browser: BrowserModel
    let path: String
    let columnIndex: Int

    @State private var entries: [FileEntry] = []

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(sortedEntries) { entry in
                    ColumnRow(entry: entry, columnIndex: columnIndex)
                }
            }
        }
        .frame(width: 240)
        .onAppear(perform: reload)
        .onChange(of: path) { _, _ in reload() }
        .onChange(of: browser.rule) { _, _ in reload() }
        .onChange(of: browser.selectionCancelToken) { _, _ in }
    }

    private var sortedEntries: [FileEntry] {
        SortEngine.sort(entries, by: browser.rule)
    }

    private func reload() {
        entries = (try? DirectoryLoader.load(path: path)) ?? []
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
                    FileTypeIcon(category: entry.category, size: 14)
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
                .padding(.vertical, 5)
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
        .contextMenu { entryContextMenu(entry) }
    }

    private func handleClick() {
        if (NSApp.currentEvent?.clickCount ?? 1) >= 2 {
            browser.selectOnly(entry.id)
            browser.activateEntry(entry)
            return
        }
        // ⇧/⌘ / modo varios: solo selección (como Finder)
        let flags = NSEvent.modifierFlags
        if flags.contains(.shift) || flags.contains(.command) || browser.multiSelectMode {
            browser.clickSelect(entry.id)
            return
        }
        browser.clickSelect(entry.id)
        if entry.isDirectory {
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
    let entry: FileEntry

    var body: some View {
        VStack(spacing: 12) {
            if let image = NSImage(contentsOfFile: entry.path), !entry.isDirectory {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                FileTypeIcon(category: entry.category, size: 72)
            }
            Text(entry.name)
                .font(.headline)
            Text(entry.path)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
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
                            FileTypeIcon(category: entry.category, size: 22)
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
        Button("A bandeja") {
            if !browser.selectedIDs.contains(entry.id) {
                browser.selectOnly(entry.id)
            }
            browser.addSelectionToShelf()
        }
        Button("Mostrar en Finder") { browser.revealInFinder(entry) }
        Divider()
        Button("Mover a la Papelera", role: .destructive) {
            if !browser.selectedIDs.contains(entry.id) {
                browser.selectOnly(entry.id)
            }
            browser.moveSelectionToTrash()
        }
    }
}
