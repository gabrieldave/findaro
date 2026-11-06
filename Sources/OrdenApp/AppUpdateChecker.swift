import AppKit
import Foundation

/// Revisa el feed público (ordena.iareal.net) y ofrece instalar el .dmg más reciente.
/// El repo de GitHub es privado: no sirve para descargas anónimas.
@MainActor
final class AppUpdateChecker: ObservableObject {
    static let shared = AppUpdateChecker()

    static let feedURL = URL(string: "https://ordena.iareal.net/downloads/latest.json")!
    private static let lastCheckKey = "ordena.lastUpdateCheck"
    /// Mientras iteramos builds: cada arranque. Luego volver a 6 h.
    private static let checkInterval: TimeInterval = 0

    @Published var statusMessage: String?
    @Published var isChecking = false
    @Published var isInstalling = false

    struct ReleaseInfo {
        let tag: String
        let version: String
        let dmgURL: URL
        let notesURL: URL
    }

    func checkOnLaunchIfNeeded() {
        let last = UserDefaults.standard.double(forKey: Self.lastCheckKey)
        let now = Date().timeIntervalSince1970
        if Self.checkInterval > 0, last > 0, now - last < Self.checkInterval { return }
        Task { await check(interactive: false) }
    }

    func check(interactive: Bool) async {
        guard !isChecking, !isInstalling else { return }
        isChecking = true
        defer { isChecking = false }

        if interactive {
            statusMessage = "Buscando actualizaciones…"
        }

        do {
            guard let release = try await fetchLatestRelease() else {
                if interactive {
                    await showInfo(
                        title: "No encontré actualización",
                        message: "El servidor no publicó ninguna versión todavía."
                    )
                }
                return
            }
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastCheckKey)

            let current = Self.currentVersion()
            guard Self.isVersion(release.version, newerThan: current) else {
                if interactive {
                    await showInfo(
                        title: "Ya estás al día",
                        message: "Tienes la \(current). No hay nada más nuevo en ordena.iareal.net."
                    )
                }
                statusMessage = "Ya tienes la última versión (\(current))"
                return
            }

            let shouldInstall = await confirmUpdate(from: current, to: release.version)
            if shouldInstall {
                await downloadAndInstall(release: release)
            } else if interactive {
                statusMessage = "Actualización \(release.version) pospuesta"
            }
        } catch {
            if interactive {
                await showInfo(
                    title: "No pude buscar",
                    message: "Revisa la red e inténtalo otra vez.\n\(error.localizedDescription)"
                )
            }
            statusMessage = "No se pudo buscar actualización"
        }
    }

    private func fetchLatestRelease() async throws -> ReleaseInfo? {
        var req = URLRequest(url: Self.feedURL)
        req.setValue("Ordena-UpdateChecker", forHTTPHeaderField: "User-Agent")
        req.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(PublicFeed.self, from: data)
        guard let dmg = URL(string: decoded.dmg_url),
              let notes = URL(string: decoded.notes_url)
        else { return nil }
        let version = decoded.version
        let tag = decoded.tag ?? "v\(version)"
        return ReleaseInfo(tag: tag, version: version, dmgURL: dmg, notesURL: notes)
    }

    private func confirmUpdate(from current: String, to latest: String) async -> Bool {
        await withCheckedContinuation { cont in
            let alert = NSAlert()
            alert.messageText = "Encontré la versión \(latest)"
            alert.informativeText = "Tienes la \(current).\n¿La descargo e instalo ahora?"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Instalar")
            alert.addButton(withTitle: "Después")
            let result = alert.runModal()
            cont.resume(returning: result == .alertFirstButtonReturn)
        }
    }

    private func showInfo(title: String, message: String) async {
        statusMessage = title
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Listo")
            alert.runModal()
            cont.resume()
        }
    }

    private func downloadAndInstall(release: ReleaseInfo) async {
        isInstalling = true
        statusMessage = "Descargando \(release.tag)…"
        defer { isInstalling = false }

        do {
            let (tempURL, _) = try await URLSession.shared.download(from: release.dmgURL)
            let dmg = FileManager.default.temporaryDirectory
                .appendingPathComponent("Ordena-\(release.version).dmg")
            try? FileManager.default.removeItem(at: dmg)
            try FileManager.default.moveItem(at: tempURL, to: dmg)

            statusMessage = "Preparando instalación…"
            // Sale la app y un script instala el .app (el binario en uso no se puede sobrescribir bien).
            try Self.scheduleInstallAndRelaunch(dmgPath: dmg.path)
            NSApp.terminate(nil)
        } catch {
            statusMessage = "Falló la instalación automática"
            let alert = NSAlert()
            alert.messageText = "No se pudo instalar sola"
            alert.informativeText = "Abre el sitio y arrastra el .dmg a Aplicaciones:\n\(release.notesURL.absoluteString)"
            alert.addButton(withTitle: "Abrir en el navegador")
            alert.addButton(withTitle: "Cerrar")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(release.notesURL)
            }
        }
    }

    /// Lanza un script en background: espera a que Ordena cierre, instala y reabre.
    private static func scheduleInstallAndRelaunch(dmgPath: String) throws {
        let script = """
        set -euo pipefail
        sleep 2
        DMG=\(shellEscape(dmgPath))
        MNT=$(mktemp -d /tmp/ordena-update.XXXXXX)
        cleanup() { hdiutil detach "$MNT" -quiet 2>/dev/null || true; rm -rf "$MNT" 2>/dev/null || true; rm -f "$DMG" 2>/dev/null || true; }
        trap cleanup EXIT
        hdiutil attach "$DMG" -nobrowse -quiet -mountpoint "$MNT"
        APP=$(find "$MNT" -maxdepth 2 -name 'Ordena.app' -type d | head -1)
        test -n "$APP"
        ditto "$APP" /Applications/Ordena.app
        open /Applications/Ordena.app
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", script]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    private static func shellEscape(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func currentVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// Comparación semver simple: "0.1.2" > "0.1.1"
    static func isVersion(_ a: String, newerThan b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        let n = max(pa.count, pb.count)
        for i in 0 ..< n {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}

private struct PublicFeed: Decodable {
    let version: String
    let tag: String?
    let dmg_url: String
    let notes_url: String
}
