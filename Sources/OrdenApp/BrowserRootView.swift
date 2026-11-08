import SwiftUI
import OrdenCore

/// Raíz por ventana: pestañas + un `BrowserModel` por pestaña (ventanas independientes).
struct BrowserRootView: View {
    @Environment(\.openWindow) private var openWindow
    @StateObject private var session = BrowserWindowSession()

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
        .frame(
            minWidth: OrdenDisplayMetrics.resolve(windowSize: .zero).windowMinWidth,
            minHeight: OrdenDisplayMetrics.resolve(windowSize: .zero).windowMinHeight
        )
        .tint(OrdenTheme.accent)
        .onAppear {
            OrdenWindowFit.applyToOpenWindows()
            if let pending = OpenFolderBridge.pendingFolderPath {
                OpenFolderBridge.pendingFolderPath = nil
                session.activeBrowser.navigate(to: pending, recordHistory: false)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .ordenaOpenFolder)) { note in
            if let path = note.object as? String {
                session.activeBrowser.navigate(to: path, recordHistory: true)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .findaroOpenNewBrowserWindow)) { _ in
            openWindow(id: "browser")
        }
        .onOpenURL { url in
            OpenFolderBridge.ingest(urls: [url])
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
