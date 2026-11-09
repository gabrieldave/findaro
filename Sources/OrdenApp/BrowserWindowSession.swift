import Foundation
import SwiftUI
import AppKit
import Combine
import OrdenCore

/// Sesión por ventana: varias pestañas, cada una con su propio `BrowserModel`.
@MainActor
final class BrowserWindowSession: ObservableObject {
    struct TabItem: Identifiable {
        let id: UUID
        let browser: BrowserModel

        @MainActor
        init(id: UUID = UUID(), browser: BrowserModel? = nil) {
            self.id = id
            self.browser = browser ?? BrowserModel()
        }

        @MainActor
        var title: String {
            let path = browser.activeWorkingPath
            if path.isEmpty { return "Findaro" }
            let name = (path as NSString).lastPathComponent
            return name.isEmpty ? path : name
        }
    }

    @Published private(set) var tabs: [TabItem]
    @Published var selectedTabID: UUID
    private var browserBags: [UUID: AnyCancellable] = [:]

    var activeBrowser: BrowserModel {
        tabs.first(where: { $0.id == selectedTabID })?.browser
            ?? tabs[0].browser
    }

    var canCloseTab: Bool { tabs.count > 1 }

    init() {
        let first = TabItem()
        self.tabs = [first]
        self.selectedTabID = first.id
        bindBrowserUpdates(for: first)
    }

    private func bindBrowserUpdates(for tab: TabItem) {
        browserBags[tab.id] = tab.browser.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    func selectTab(_ id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        selectedTabID = id
    }

    func addTab(copyingPathFromActive: Bool = true) {
        let path = copyingPathFromActive ? activeBrowser.activeWorkingPath : nil
        let browser = BrowserModel()
        let tab = TabItem(browser: browser)
        tabs.append(tab)
        bindBrowserUpdates(for: tab)
        selectedTabID = tab.id
        if let path, !path.isEmpty {
            browser.navigate(to: path, recordHistory: false)
        }
    }

    func closeTab(_ id: UUID) {
        guard tabs.count > 1,
              let index = tabs.firstIndex(where: { $0.id == id }) else {
            NSApp.keyWindow?.performClose(nil)
            return
        }
        browserBags[id] = nil
        tabs.remove(at: index)
        if selectedTabID == id {
            let next = tabs[min(index, tabs.count - 1)]
            selectedTabID = next.id
        }
    }

    func closeActiveTab() {
        closeTab(selectedTabID)
    }

    func selectNextTab() {
        guard let index = tabs.firstIndex(where: { $0.id == selectedTabID }) else { return }
        let next = tabs[(index + 1) % tabs.count]
        selectedTabID = next.id
    }

    func selectPreviousTab() {
        guard let index = tabs.firstIndex(where: { $0.id == selectedTabID }) else { return }
        let prev = tabs[(index - 1 + tabs.count) % tabs.count]
        selectedTabID = prev.id
    }

    func moveTab(sourceID: UUID, targetID: UUID) {
        guard sourceID != targetID,
              let sourceIndex = tabs.firstIndex(where: { $0.id == sourceID }),
              let targetIndex = tabs.firstIndex(where: { $0.id == targetID }) else { return }
        let item = tabs.remove(at: sourceIndex)
        tabs.insert(item, at: targetIndex)
    }

    func moveTab(fromOffsets source: IndexSet, toOffset destination: Int) {
        tabs.move(fromOffsets: source, toOffset: destination)
    }

    func moveTabLeft(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }), index > 0 else { return }
        tabs.swapAt(index, index - 1)
    }

    func moveTabRight(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }), index < tabs.count - 1 else { return }
        tabs.swapAt(index, index + 1)
    }
}

/// Barra de pestañas tipo Chrome/Safari (siempre visible + botón «+»).
struct BrowserTabBar: View {
    @ObservedObject var session: BrowserWindowSession
    @Environment(\.openWindow) private var openWindow
    @State private var draggingTabID: UUID?

    var body: some View {
        HStack(spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 3) {
                    ForEach(session.tabs) { tab in
                        tabChip(tab)
                    }
                }
                .padding(.leading, 8)
                .padding(.vertical, 5)
            }

            Button {
                session.addTab()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help(L10n.s("Nueva pestaña (⌘T)", "New Tab (⌘T)"))
            .accessibilityLabel(L10n.s("Nueva pestaña", "New Tab"))

            Button {
                openWindow(id: "browser")
            } label: {
                Image(systemName: "macwindow.badge.plus")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help(L10n.s("Nueva ventana (⌘⌥N)", "New Window (⌘⌥N)"))
            .accessibilityLabel(L10n.s("Nueva ventana", "New Window"))
            .padding(.trailing, 8)
        }
        .frame(minHeight: 36)
        .background(OrdenTheme.sidebarFill)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(OrdenTheme.hairline)
                .frame(height: 1)
        }
    }

    private func tabChip(_ tab: BrowserWindowSession.TabItem) -> some View {
        let selected = tab.id == session.selectedTabID
        return HStack(spacing: 6) {
            Image(systemName: "folder.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(selected ? OrdenTheme.accent : OrdenTheme.textSecondary)

            Button {
                session.selectTab(tab.id)
            } label: {
                Text(tab.title)
                    .font(.system(size: 12, weight: selected ? .semibold : .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(minWidth: 64, maxWidth: 160, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button {
                session.closeTab(tab.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(session.canCloseTab || selected ? 0.9 : 0.35)
            .disabled(!session.canCloseTab)
            .help(session.canCloseTab ? L10n.s("Cerrar pestaña", "Close Tab") : L10n.s("Única pestaña · usa Cerrar ventana", "Single tab · use Close Window"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(selected ? OrdenTheme.elevatedFill : OrdenTheme.panelFill.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(
                    selected ? OrdenTheme.accent.opacity(0.55) : OrdenTheme.hairline,
                    lineWidth: selected ? 1.2 : 1
                )
        )
        .foregroundStyle(selected ? Color.primary : OrdenTheme.textSecondary)
        .help(tab.browser.activeWorkingPath)
        .onDrag {
            draggingTabID = tab.id
            return NSItemProvider(object: tab.id.uuidString as NSString)
        }
        .onDrop(of: [.plainText, .text], isTargeted: nil) { providers in
            guard let dragging = draggingTabID, dragging != tab.id else { return false }
            withAnimation(.snappy(duration: 0.2)) {
                session.moveTab(sourceID: dragging, targetID: tab.id)
            }
            draggingTabID = nil
            return true
        }
        .contextMenu {
            Button(L10n.s("Mover pestaña a la izquierda", "Move Tab Left")) {
                withAnimation { session.moveTabLeft(tab.id) }
            }
            .disabled(session.tabs.first?.id == tab.id)

            Button(L10n.s("Mover pestaña a la derecha", "Move Tab Right")) {
                withAnimation { session.moveTabRight(tab.id) }
            }
            .disabled(session.tabs.last?.id == tab.id)

            Divider()

            Button(L10n.s("Nueva pestaña", "New Tab"), action: { session.addTab() })

            if session.canCloseTab {
                Button(L10n.s("Cerrar pestaña", "Close Tab"), action: { session.closeTab(tab.id) })
            }
        }
    }
}
