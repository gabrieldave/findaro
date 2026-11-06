import SwiftUI
import OrdenCore

/// Submenú Finder-like: Abrir con… / Siempre con…
struct OpenWithMenu: View {
    @EnvironmentObject private var browser: BrowserModel
    let entry: FileEntry

    var body: some View {
        if !entry.isDirectory {
            let apps = browser.appsForOpening(entry)
            if !apps.isEmpty {
                Menu("Abrir con") {
                    ForEach(apps) { app in
                        Button(app.name) {
                            browser.selectOnly(entry.id)
                            browser.open(entry, withApplicationAt: app.url)
                        }
                    }
                    Divider()
                    Menu("Siempre con…") {
                        ForEach(apps) { app in
                            Button(app.name) {
                                browser.selectOnly(entry.id)
                                browser.setDefaultApplication(app.url, for: entry)
                            }
                        }
                    }
                }
            }
        }
    }
}
