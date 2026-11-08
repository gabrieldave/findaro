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
}

/// Barra de pestañas tipo Finder / navegador.
struct BrowserTabBar: View {
    @ObservedObject var session: BrowserWindowSession

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(session.tabs) { tab in
                        tabChip(tab)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            }

            Button {
                session.addTab()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 28, height: 22)
            }
            .buttonStyle(.plain)
            .help("Nueva pestaña (⌘T)")
            .padding(.trailing, 6)
        }
        .background(OrdenTheme.sidebarFill.opacity(0.92))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(OrdenTheme.hairline)
                .frame(height: 1)
        }
    }

    private func tabChip(_ tab: BrowserWindowSession.TabItem) -> some View {
        let selected = tab.id == session.selectedTabID
        return HStack(spacing: 6) {
            Button {
                session.selectTab(tab.id)
            } label: {
                Text(tab.title)
                    .font(.system(size: 11, weight: selected ? .semibold : .medium))
                    .lineLimit(1)
                    .frame(minWidth: 56, maxWidth: 140, alignment: .leading)
            }
            .buttonStyle(.plain)

            if session.canCloseTab {
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
                .help("Cerrar pestaña")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(selected ? OrdenTheme.accent.opacity(0.18) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(selected ? OrdenTheme.accent.opacity(0.45) : Color.clear, lineWidth: 1)
        )
        .foregroundStyle(selected ? Color.primary : OrdenTheme.textSecondary)
        .help(tab.browser.activeWorkingPath)
    }
}
