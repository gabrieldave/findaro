import AppKit

/// Findaro about panel; internal type name retained for compatibility.
@MainActor
enum AboutOrdena {
    static func show() {
        Task { @MainActor in
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
            let status = await AppUpdateChecker.shared.aboutStatus(current: version)

            let alert = NSAlert()
            alert.messageText = "FINDARO"
            alert.informativeText = """
            Versión \(version)
            Tus archivos, bajo control.
            Encuentra. Organiza. Avanza.
            \(status.line)
            """
            alert.alertStyle = .informational
            if let icon = NSApp.applicationIconImage {
                alert.icon = icon
            }

            switch status {
            case .upToDate:
                alert.addButton(withTitle: "Listo")
                _ = alert.runModal()
            case .updateAvailable(let latest):
                alert.addButton(withTitle: "Instalar \(latest)")
                alert.addButton(withTitle: "Después")
                if alert.runModal() == .alertFirstButtonReturn {
                    await AppUpdateChecker.shared.check(interactive: true)
                }
            case .unreachable:
                alert.addButton(withTitle: "Reintentar")
                alert.addButton(withTitle: "Cerrar")
                if alert.runModal() == .alertFirstButtonReturn {
                    await AppUpdateChecker.shared.check(interactive: true)
                }
            }
        }
    }
}
