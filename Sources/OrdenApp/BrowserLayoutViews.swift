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

// MARK: - Iconos

struct IconsBrowserView: View {
    @EnvironmentObject private var browser: BrowserModel

    private let columns = [GridItem(.adaptive(minimum: 96, maximum: 120), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(browser.visibleEntries) { entry in
                    IconsItemCell(entry: entry)
                }
            }
            .padding(16)
        }
        .background(OrdenTheme.panelFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct IconsItemCell: View {
    @EnvironmentObject private var browser: BrowserModel
    let entry: FileEntry

    private var isSelected: Bool {
        browser.selectedIDs.contains(entry.id)
    }

    var body: some View {
        VStack(spacing: 6) {
            FileTypeIcon(category: entry.category, size: 36)
            Text(entry.name)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 96)
        }
        .padding(8)
        .frame(width: 104, height: 100)
        .background(
            isSelected ? OrdenTheme.accent.opacity(0.28) : Color.clear,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            browser.activateEntry(entry)
        }
        .onTapGesture(count: 1) {
            browser.clickSelect(entry.id)
        }
        .contextMenu { entryContextMenu(entry) }
    }
}

// MARK: - Columnas

struct ColumnsBrowserView: View {
    @EnvironmentObject private var browser: BrowserModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(browser.columnPaths.enumerated()), id: \.offset) { index, path in
                    ColumnPane(path: path, columnIndex: index)
                    Divider()
                }
            }
        }
        .background(OrdenTheme.panelFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onAppear {
            if browser.columnPaths.isEmpty {
                browser.columnPaths = [browser.currentPath]
            }
        }
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
        .frame(width: 220)
        .onAppear(perform: reload)
        .onChange(of: path) { _, _ in reload() }
        .onChange(of: browser.rule) { _, _ in reload() }
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
        Button {
            browser.clickSelect(entry.id)
            if entry.isDirectory {
                browser.openInColumns(entry, columnIndex: columnIndex)
            }
        } label: {
            HStack(spacing: 8) {
                FileTypeIcon(category: entry.category, size: 14)
                Text(entry.name)
                    .font(.callout)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if entry.isDirectory {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                (isSelected || isOpenInNextColumn)
                    ? OrdenTheme.accent.opacity(0.25)
                    : Color.clear
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onTapGesture(count: 2) {
            browser.activateEntry(entry)
        }
        .contextMenu { entryContextMenu(entry) }
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
            .frame(height: 100)
            .background(OrdenTheme.panelFill)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.06), lineWidth: 1)
        )
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
        }
        .onTapGesture(count: 2) {
            browser.activateEntry(entry)
        }
        .onTapGesture(count: 1) {
            browser.clickSelect(entry.id)
        }
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
