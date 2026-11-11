import SwiftUI
import AppKit
import OrdenCore

/// Raíz por ventana: pestañas + un `BrowserModel` por pestaña (ventanas independientes).
struct BrowserRootView: View {
    @Environment(\.openWindow) private var openWindow
    @StateObject private var session = BrowserWindowSession()
    @State private var hostWindow: NSWindow?

    var body: some View {
        VStack(spacing: 0) {
            BrowserTabBar(session: session)

            ContentView()
                .environmentObject(session.activeBrowser)
                .environmentObject(session)
                .id(session.selectedTabID)
        }
        .focusedValue(\.findaroBrowser, session.activeBrowser)
        .focusedValue(\.findaroSession, session)
        .background(WindowAccessor { window in
            hostWindow = window
            FindaroWindowRegistry.register(session, for: window)
        })
        .frame(
            minWidth: OrdenDisplayMetrics.resolve(windowSize: .zero).windowMinWidth,
            minHeight: OrdenDisplayMetrics.resolve(windowSize: .zero).windowMinHeight
        )
        .tint(OrdenTheme.accent)
        .onAppear {
            OrdenWindowFit.applyToOpenWindows()
            FindaroWindowRegistry.dismissUnregisteredLookalikes(keeping: hostWindow)
            if let pending = OpenFolderBridge.pendingFolderPath {
                OpenFolderBridge.pendingFolderPath = nil
                session.activeBrowser.navigate(to: pending, recordHistory: false)
            }
            if !DefaultFileViewerManager.pendingRevealPaths.isEmpty {
                let pendingPaths = DefaultFileViewerManager.pendingRevealPaths
                DefaultFileViewerManager.pendingRevealPaths = []
                session.revealPaths(pendingPaths)
            }
        }
        .onDisappear {
            FindaroWindowRegistry.unregister(for: hostWindow)
        }
        .onReceive(NotificationCenter.default.publisher(for: .ordenaOpenFolder)) { note in
            guard FindaroWindowRegistry.claimDelivery(for: session) else { return }
            if let path = note.object as? String {
                OpenFolderBridge.pendingFolderPath = nil
                session.activeBrowser.navigate(to: path, recordHistory: true)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .findaroRevealPaths)) { note in
            guard FindaroWindowRegistry.claimDelivery(for: session) else { return }
            if let paths = note.object as? [String] {
                DefaultFileViewerManager.pendingRevealPaths = []
                session.revealPaths(paths)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .findaroOpenNewBrowserWindow)) { _ in
            // Solo una vista debe abrir; si ya hay explorador, reusar.
            if FindaroWindowRegistry.hasVisibleBrowserWindow() { return }
            if !FindaroWindowRegistry.registeredWindows.isEmpty {
                _ = FindaroWindowRegistry.restoreBrowserWindowsOrRequestNew()
                return
            }
            guard FindaroWindowRegistry.claimNewWindowRequest() else { return }
            openWindow(id: "browser")
        }
        .onOpenURL { url in
            OpenFolderBridge.ingest(urls: [url])
        }
    }
}

/// Captura el NSWindow anfitrión para registrar la sesión.
private struct WindowAccessor: NSViewRepresentable {
    var onResolve: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            onResolve(view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            onResolve(nsView.window)
        }
    }
}

private struct FindaroBrowserFocusedKey: FocusedValueKey {
    typealias Value = BrowserModel
}

private struct FindaroSessionFocusedKey: FocusedValueKey {
    typealias Value = BrowserWindowSession
}

extension FocusedValues {
    var findaroBrowser: BrowserModel? {
        get { self[FindaroBrowserFocusedKey.self] }
        set { self[FindaroBrowserFocusedKey.self] = newValue }
    }

    var findaroSession: BrowserWindowSession? {
        get { self[FindaroSessionFocusedKey.self] }
        set { self[FindaroSessionFocusedKey.self] = newValue }
    }
}
