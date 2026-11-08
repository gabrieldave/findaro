import SwiftUI
import OrdenCore

/// Raíz por ventana: cada ventana tiene su propio `BrowserModel` (varias ventanas independientes).
struct BrowserRootView: View {
    @StateObject private var browser = BrowserModel()

    var body: some View {
        ContentView()
            .environmentObject(browser)
            .focusedValue(\.findaroBrowser, browser)
            .frame(
                minWidth: OrdenDisplayMetrics.resolve(windowSize: .zero).windowMinWidth,
                minHeight: OrdenDisplayMetrics.resolve(windowSize: .zero).windowMinHeight
            )
            .tint(OrdenTheme.accent)
            .onAppear {
                OrdenWindowFit.applyToOpenWindows()
                if let pending = OpenFolderBridge.pendingFolderPath {
                    OpenFolderBridge.pendingFolderPath = nil
                    browser.navigate(to: pending, recordHistory: false)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .ordenaOpenFolder)) { note in
                if let path = note.object as? String {
                    browser.navigate(to: path, recordHistory: true)
                }
            }
            .onOpenURL { url in
                OpenFolderBridge.ingest(urls: [url])
            }
    }
}

private struct FindaroBrowserFocusedKey: FocusedValueKey {
    typealias Value = BrowserModel
}

extension FocusedValues {
    var findaroBrowser: BrowserModel? {
        get { self[FindaroBrowserFocusedKey.self] }
        set { self[FindaroBrowserFocusedKey.self] = newValue }
    }
}
