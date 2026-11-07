import AppKit
import Foundation
import CryptoKit

/// Revisa el feed de distribución y ofrece instalar la versión más reciente.
/// El repo de GitHub es privado: no sirve para descargas anónimas.
@MainActor
final class AppUpdateChecker: ObservableObject {
    static let shared = AppUpdateChecker()

    static let feedURL = URL(string: "https://ordena.iareal.net/downloads/latest.json")!
    private static let allowedHosts: Set<String> = ["ordena.iareal.net"]
    private static let lastCheckKey = "ordena.lastUpdateCheck"
    private static let pendingVersionKey = "findaro.pendingUpdateVersion"
    private static let pendingDMGKey = "findaro.pendingUpdateDMG"
    /// Intervalo de producción: 6 horas.
    private static let checkInterval: TimeInterval = 6 * 60 * 60

    @Published var statusMessage: String?
    @Published var isChecking = false
    @Published var isInstalling = false

    /// Actualización pospuesta: al salir (⌘Q) se instala sola si el DMG ya está listo.
    private var pendingRelease: ReleaseInfo?
    private var pendingDMGURL: URL?

    struct ReleaseInfo {
        let tag: String
        let version: String
        let dmgURL: URL
        let notesURL: URL
        let sha256: String?
    }

    enum AboutStatus {
        case upToDate
        case updateAvailable(String)
        case unreachable(String)

        var line: String {
            switch self {
            case .upToDate:
                return "Ya estás al día."
            case .updateAvailable(let latest):
                return "Hay una versión nueva: \(latest)."
            case .unreachable:
                return "No pude comprobar actualizaciones ahora."
            }
        }
    }

    func aboutStatus(current: String) async -> AboutStatus {
        do {
            guard let release = try await fetchLatestRelease() else {
                return .unreachable("Sin versión publicada")
            }
            if Self.isVersion(release.version, newerThan: current) {
                return .updateAvailable(release.version)
            }
            return .upToDate
        } catch {
            return .unreachable(error.localizedDescription)
        }
    }

    func checkOnLaunchIfNeeded() {
        // Si quedó un DMG pendiente de una sesión anterior, instalar al arrancar.
        if installPendingOnLaunchIfPossible() { return }

        let last = UserDefaults.standard.double(forKey: Self.lastCheckKey)
        let now = Date().timeIntervalSince1970
        if Self.checkInterval > 0, last > 0, now - last < Self.checkInterval { return }
        Task { await check(interactive: false) }
    }

    /// Al salir de verdad (⌘Q): si pospuso la actualización y el DMG está listo, instala en silencio.
    func installPendingOnTerminateIfNeeded() {
        guard !isInstalling else { return }
        guard let release = pendingRelease, let dmg = pendingDMGURL,
              FileManager.default.fileExists(atPath: dmg.path) else { return }
        do {
            try Self.scheduleInstallAndRelaunch(
                dmgPath: dmg.path,
                installRoot: Self.preferredInstallRoot(),
                reopen: true
            )
            clearPending()
        } catch {
            // Deja el DMG para el próximo arranque.
            UserDefaults.standard.set(release.version, forKey: Self.pendingVersionKey)
            UserDefaults.standard.set(dmg.path, forKey: Self.pendingDMGKey)
        }
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
                clearPending()
                if interactive {
                    await showInfo(
                        title: "Ya estás al día",
                        message: "Tienes la \(current). No hay nada más nuevo en el canal de Findaro."
                    )
                }
                statusMessage = "Ya tienes la última versión (\(current))"
                return
            }

            let choice = await confirmUpdate(from: current, to: release.version)
            switch choice {
            case .install:
                await downloadAndInstall(release: release, terminateAfter: true)
            case .later:
                statusMessage = "Actualización \(release.version) pospuesta — se instalará al cerrar Findaro"
                Task { await prefetchForQuitInstall(release: release) }
            case .skip:
                clearPending()
                statusMessage = "Actualización \(release.version) omitida por ahora"
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

    private enum UpdateChoice {
        case install
        case later
        case skip
    }

    private func fetchLatestRelease() async throws -> ReleaseInfo? {
        var req = URLRequest(url: Self.feedURL)
        req.setValue("Findaro-UpdateChecker", forHTTPHeaderField: "User-Agent")
        req.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(PublicFeed.self, from: data)
        guard let dmg = URL(string: decoded.dmg_url),
              let notes = URL(string: decoded.notes_url)
        else { return nil }
        try Self.validateHTTPSHost(dmg)
        try Self.validateHTTPSHost(notes)
        let version = decoded.version
        let tag = decoded.tag ?? "v\(version)"
        return ReleaseInfo(
            tag: tag,
            version: version,
            dmgURL: dmg,
            notesURL: notes,
            sha256: decoded.sha256
        )
    }

    private static func validateHTTPSHost(_ url: URL) throws {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              allowedHosts.contains(host) else {
            throw URLError(.unsupportedURL)
        }
    }

    private func confirmUpdate(from current: String, to latest: String) async -> UpdateChoice {
        await withCheckedContinuation { cont in
            let alert = NSAlert()
            alert.messageText = "Llegó la actualización \(latest)"
            alert.informativeText = """
            Tienes la \(current).

            • Instalar ahora: descarga, cierra la app e instala sola.
            • Después: la deja lista y la instala al salir (⌘Q).
            • Ahora no: pregunta de nuevo más adelante.
            """
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Instalar ahora")
            alert.addButton(withTitle: "Después")
            alert.addButton(withTitle: "Ahora no")
            let result = alert.runModal()
            switch result {
            case .alertFirstButtonReturn:
                cont.resume(returning: .install)
            case .alertSecondButtonReturn:
                cont.resume(returning: .later)
            default:
                cont.resume(returning: .skip)
            }
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

    private func prefetchForQuitInstall(release: ReleaseInfo) async {
        do {
            let dmg = try await downloadVerifiedDMG(release: release)
            pendingRelease = release
            pendingDMGURL = dmg
            UserDefaults.standard.set(release.version, forKey: Self.pendingVersionKey)
            UserDefaults.standard.set(dmg.path, forKey: Self.pendingDMGKey)
            statusMessage = "\(release.version) lista — se instalará al cerrar"
        } catch {
            statusMessage = "No pude preparar la actualización para el cierre"
        }
    }

    private func installPendingOnLaunchIfPossible() -> Bool {
        let version = UserDefaults.standard.string(forKey: Self.pendingVersionKey) ?? ""
        let path = UserDefaults.standard.string(forKey: Self.pendingDMGKey) ?? ""
        guard !version.isEmpty, !path.isEmpty,
              FileManager.default.fileExists(atPath: path),
              Self.isVersion(version, newerThan: Self.currentVersion()) else {
            clearPending()
            return false
        }
        do {
            try Self.scheduleInstallAndRelaunch(
                dmgPath: path,
                installRoot: Self.preferredInstallRoot(),
                reopen: true
            )
            clearPending()
            NSApp.terminate(nil)
            return true
        } catch {
            return false
        }
    }

    private func clearPending() {
        pendingRelease = nil
        pendingDMGURL = nil
        UserDefaults.standard.removeObject(forKey: Self.pendingVersionKey)
        UserDefaults.standard.removeObject(forKey: Self.pendingDMGKey)
    }

    private func downloadAndInstall(release: ReleaseInfo, terminateAfter: Bool) async {
        isInstalling = true
        statusMessage = "Descargando \(release.tag)…"
        defer { isInstalling = false }

        do {
            let dmg = try await downloadVerifiedDMG(release: release)
            let installRoot = Self.preferredInstallRoot()
            statusMessage = "Preparando instalación…"
            try Self.scheduleInstallAndRelaunch(dmgPath: dmg.path, installRoot: installRoot, reopen: true)
            clearPending()
            if terminateAfter {
                NSApp.terminate(nil)
            }
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

    private func downloadVerifiedDMG(release: ReleaseInfo) async throws -> URL {
        let (tempURL, _) = try await URLSession.shared.download(from: release.dmgURL)
        let dmg = FileManager.default.temporaryDirectory
            .appendingPathComponent("Findaro-\(release.version).dmg")
        try? FileManager.default.removeItem(at: dmg)
        try FileManager.default.moveItem(at: tempURL, to: dmg)

        if let expected = release.sha256?.lowercased(), !expected.isEmpty {
            statusMessage = "Verificando integridad…"
            let digest = try Self.sha256File(at: dmg)
            guard digest == expected else {
                try? FileManager.default.removeItem(at: dmg)
                throw URLError(.cannotParseResponse)
            }
        }
        return dmg
    }

    /// Ruta real: `/Applications` si hay permisos / ya instalado ahí; si no, `~/Applications`.
    static func preferredInstallRoot() -> String {
        let bundlePath = Bundle.main.bundleURL.path
        if bundlePath.hasPrefix(NSHomeDirectory() + "/Applications/") {
            return (NSHomeDirectory() as NSString).appendingPathComponent("Applications")
        }
        if FileManager.default.isWritableFile(atPath: "/Applications")
            || FileManager.default.fileExists(atPath: "/Applications/Findaro.app")
            || FileManager.default.fileExists(atPath: "/Applications/Ordena.app") {
            return "/Applications"
        }
        let homeApps = (NSHomeDirectory() as NSString).appendingPathComponent("Applications")
        try? FileManager.default.createDirectory(atPath: homeApps, withIntermediateDirectories: true)
        return homeApps
    }

    /// Staging + backup + swap. Acepta Findaro.app u Ordena.app (migración).
    private static func scheduleInstallAndRelaunch(dmgPath: String, installRoot: String, reopen: Bool) throws {
        let logPath = (NSHomeDirectory() as NSString).appendingPathComponent("Library/Logs/Findaro-update.log")
        let reopenLine = reopen ? "open \"$DEST\"" : "true"
        let script = """
        set -euo pipefail
        exec >> \(shellEscape(logPath)) 2>&1
        echo "==== $(date) update start ===="
        sleep 2
        DMG=\(shellEscape(dmgPath))
        ROOT=\(shellEscape(installRoot))
        MNT=$(mktemp -d /tmp/findaro-update.XXXXXX)
        cleanup() {
          hdiutil detach "$MNT" -quiet 2>/dev/null || true
          rm -rf "$MNT" 2>/dev/null || true
          rm -f "$DMG" 2>/dev/null || true
        }
        trap cleanup EXIT
        hdiutil attach "$DMG" -nobrowse -quiet -mountpoint "$MNT"
        APP=$(find "$MNT" -maxdepth 2 -name 'Findaro.app' -type d | head -1)
        DEST_NAME="Findaro.app"
        if [ -z "$APP" ]; then
          APP=$(find "$MNT" -maxdepth 2 -name 'Ordena.app' -type d | head -1)
          DEST_NAME="Ordena.app"
        fi
        test -n "$APP"
        # Si el usuario aún tiene Ordena y el DMG trae Findaro, instala Findaro y abre esa.
        if [ "$DEST_NAME" = "Findaro.app" ] && [ -d "$ROOT/Ordena.app" ] && [ ! -d "$ROOT/Findaro.app" ]; then
          DEST="$ROOT/Findaro.app"
        else
          DEST="$ROOT/$DEST_NAME"
        fi
        BACKUP="$DEST.bak-$$"
        STAGE="$DEST.staging-$$"
        rm -rf "$STAGE"
        ditto "$APP" "$STAGE"
        if [ -d "$DEST" ]; then
          rm -rf "$BACKUP"
          mv "$DEST" "$BACKUP"
        fi
        mv "$STAGE" "$DEST"
        rm -rf "$BACKUP"
        \(reopenLine)
        echo "==== $(date) update ok dest=$DEST ===="
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", script]
        try process.run()
    }

    private static func sha256File(at url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1_048_576) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func shellEscape(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func currentVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

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
    let sha256: String?
}
