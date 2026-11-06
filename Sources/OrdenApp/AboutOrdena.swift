import AppKit

/// Acerca de Ordena: versión + si ya estás al día (o si hay update).
@MainActor
enum AboutOrdena {
    static func show() {
        Task { @MainActor in
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
            let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
            let status = await AppUpdateChecker.shared.aboutStatus(current: version)

            let alert = NSAlert()
            alert.messageText = "Ordena"
            alert.informativeText = """
            Versión \(version)
            Por David DRC
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
