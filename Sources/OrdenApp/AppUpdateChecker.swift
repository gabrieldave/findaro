import AppKit
import Foundation
import CryptoKit
import OrdenCore

/// Revisa el feed de distribución y ofrece instalar la versión más reciente.
/// Canal exclusivo por Bundle ID (Findaro ≠ Ordena).
@MainActor
final class AppUpdateChecker: ObservableObject {
    static let shared = AppUpdateChecker()

    static let feedURL = URL(string: "https://ordena.iareal.net/downloads/latest.json")!

    private static let lastCheckKey = "ordena.lastUpdateCheck"
    private static let pendingVersionKey = "findaro.pendingUpdateVersion"
    private static let pendingDMGURLKey = "findaro.pendingUpdateDMGURL"
    private static let pendingSHAKey = "findaro.pendingUpdateSHA"
    private static let pendingLocalDMGKey = "findaro.pendingUpdateLocalDMG"
    private static let pendingExpectedBundleKey = "findaro.pendingExpectedBundle"
    /// Intervalo de producción: 6 horas.
    private static let checkInterval: TimeInterval = 6 * 60 * 60

    @Published var statusMessage: String?
    @Published var isChecking = false
    @Published var isInstalling = false

    private var downloadTask: Task<Void, Never>?
    private var downloadingVersion: String?

    enum AboutStatus {
        case upToDate
        case updateAvailable(String)
        case unreachable(String)

        var line: String {
            switch self {
            case .upToDate:
                return L10n.s("Ya estás al día.", "You're up to date.")
            case .updateAvailable(let latest):
                return L10n.s("Hay una versión nueva: \(latest).", "New version available: \(latest).")
            case .unreachable:
                return L10n.s("No pude comprobar actualizaciones ahora.", "Could not check for updates right now.")
            }
        }
    }

    func aboutStatus(current: String) async -> AboutStatus {
        do {
            let release = try await fetchChannelRelease()
            if UpdateFeed.isVersion(release.version, newerThan: current) {
                return .updateAvailable(release.version)
            }
            return .upToDate
        } catch {
            return .unreachable(error.localizedDescription)
        }
    }

    func checkOnLaunchIfNeeded() {
        Task {
            await resumePendingIfNeeded(installWhenReady: true)
            let last = UserDefaults.standard.double(forKey: Self.lastCheckKey)
            let now = Date().timeIntervalSince1970
            if Self.checkInterval > 0, last > 0, now - last < Self.checkInterval { return }
            await check(interactive: false)
        }
    }

    /// Al salir (⌘Q): instala solo si el DMG local ya está verificado.
    func installPendingOnTerminateIfNeeded() {
        guard !isInstalling else { return }
        guard let local = UserDefaults.standard.string(forKey: Self.pendingLocalDMGKey),
              !local.isEmpty,
              FileManager.default.fileExists(atPath: local),
              let version = UserDefaults.standard.string(forKey: Self.pendingVersionKey),
              UpdateFeed.isVersion(version, newerThan: Self.currentVersion()),
              let expectedBundle = UserDefaults.standard.string(forKey: Self.pendingExpectedBundleKey),
              let sha = UserDefaults.standard.string(forKey: Self.pendingSHAKey)
        else {
            return
        }
        do {
            try Self.scheduleInstallAndRelaunch(
                dmgPath: local,
                installRoot: Self.preferredInstallRoot(),
                expectedBundleID: expectedBundle,
                expectedSHA256: sha
            )
            // No borramos pending aquí: el script limpia el DMG; si falla, el próximo arranque reintenta.
        } catch {
            // Deja pending intacto para el siguiente arranque.
        }
    }

    func check(interactive: Bool) async {
        guard !isChecking, !isInstalling else { return }
        isChecking = true
        defer { isChecking = false }

        if interactive {
            statusMessage = L10n.s("Buscando actualizaciones…", "Checking for updates…")
        }

        do {
            let release = try await fetchChannelRelease()
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastCheckKey)

            let current = Self.currentVersion()
            guard UpdateFeed.isVersion(release.version, newerThan: current) else {
                clearPending()
                if interactive {
                    await showInfo(
                        title: L10n.s("Ya estás al día", "You're up to date"),
                        message: L10n.s("Tienes la \(current). No hay nada más nuevo en tu canal.", "You have \(current). You are running the latest version.")
                    )
                }
                statusMessage = L10n.s("Ya tienes la última versión (\(current))", "You have the latest version (\(current))")
                return
            }

            let choice = await confirmUpdate(from: current, to: release.version)
            switch choice {
            case .install:
                await downloadAndInstall(release: release, terminateAfter: true)
            case .later:
                persistPendingMetadata(release)
                statusMessage = L10n.s("Actualización \(release.version) pospuesta", "Update \(release.version) postponed")
                startPrefetchIfNeeded(release: release)
            case .skip:
                clearPending()
                statusMessage = L10n.s("Actualización \(release.version) omitida por ahora", "Update \(release.version) skipped for now")
            }
        } catch {
            if interactive {
                await showInfo(
                    title: L10n.s("No pude buscar", "Could not check for updates"),
                    message: L10n.s("Revisa la red e inténtalo otra vez.\n\(error.localizedDescription)", "Check your connection and try again.\n\(error.localizedDescription)")
                )
            }
            statusMessage = L10n.s("No se pudo buscar actualización", "Could not check for updates")
        }
    }

    private enum UpdateChoice {
        case install
        case later
        case skip
    }

    private func fetchChannelRelease() async throws -> UpdateFeed.ChannelRelease {
        var req = URLRequest(url: Self.feedURL)
        req.setValue("Findaro-UpdateChecker", forHTTPHeaderField: "User-Agent")
        req.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(UpdateFeed.PublicFeed.self, from: data)
        let bundleID = Bundle.main.bundleIdentifier ?? UpdateFeed.findaroBundleID
        let effectiveID = (bundleID == UpdateFeed.ordenaBundleID) ? UpdateFeed.ordenaBundleID : UpdateFeed.findaroBundleID
        return try UpdateFeed.resolve(feed: decoded, installedBundleID: effectiveID)
    }

    private func confirmUpdate(from current: String, to latest: String) async -> UpdateChoice {
        await withCheckedContinuation { cont in
            let alert = NSAlert()
            alert.messageText = L10n.s("Llegó la actualización \(latest)", "Update \(latest) Available")
            alert.informativeText = L10n.s("""
            Tienes la \(current).

            • Instalar ahora: descarga, cierra la app e instala.
            • Después: descarga en segundo plano. Si al salir (⌘Q) ya terminó, instala sola; si no, reintenta al abrir.
            • Ahora no: pregunta más adelante.
            """, """
            You are currently running version \(current).

            • Install Now: downloads update, closes Findaro, and completes install.
            • Later: downloads in background. Automatically installs on quit or next launch.
            • Not Now: ask again later.
            """)
            alert.alertStyle = .informational
            alert.addButton(withTitle: L10n.s("Instalar ahora", "Install Now"))
            alert.addButton(withTitle: L10n.s("Después", "Later"))
            alert.addButton(withTitle: L10n.s("Ahora no", "Not Now"))
            let result = alert.runModal()
            switch result {
            case .alertFirstButtonReturn: cont.resume(returning: .install)
            case .alertSecondButtonReturn: cont.resume(returning: .later)
            default: cont.resume(returning: .skip)
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
            alert.addButton(withTitle: L10n.s("Listo", "OK"))
            alert.runModal()
            cont.resume()
        }
    }

    private func persistPendingMetadata(_ release: UpdateFeed.ChannelRelease) {
        UserDefaults.standard.set(release.version, forKey: Self.pendingVersionKey)
        UserDefaults.standard.set(release.dmgURL.absoluteString, forKey: Self.pendingDMGURLKey)
        UserDefaults.standard.set(release.sha256, forKey: Self.pendingSHAKey)
        UserDefaults.standard.set(release.expectedBundleID, forKey: Self.pendingExpectedBundleKey)
    }

    private func startPrefetchIfNeeded(release: UpdateFeed.ChannelRelease) {
        if downloadingVersion == release.version { return }
        if let local = UserDefaults.standard.string(forKey: Self.pendingLocalDMGKey),
           FileManager.default.fileExists(atPath: local) {
            statusMessage = "\(release.version) ya descargada — se instalará al salir o al abrir"
            return
        }
        downloadingVersion = release.version
        downloadTask?.cancel()
        downloadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let dmg = try await self.downloadVerifiedDMG(release: release)
                guard !Task.isCancelled else { return }
                UserDefaults.standard.set(dmg.path, forKey: Self.pendingLocalDMGKey)
                self.statusMessage = "\(release.version) lista — se instalará al salir (⌘Q) o al abrir de nuevo"
            } catch {
                if !Task.isCancelled {
                    self.statusMessage = "Descarga pospuesta incompleta — se reintentará al abrir"
                }
            }
            if self.downloadingVersion == release.version {
                self.downloadingVersion = nil
            }
        }
    }

    private func resumePendingIfNeeded(installWhenReady: Bool) async {
        guard let version = UserDefaults.standard.string(forKey: Self.pendingVersionKey),
              !version.isEmpty,
              UpdateFeed.isVersion(version, newerThan: Self.currentVersion()) else {
            clearPending()
            return
        }
        let expectedBundle = UserDefaults.standard.string(forKey: Self.pendingExpectedBundleKey)
            ?? (Bundle.main.bundleIdentifier ?? "")
        let sha = UserDefaults.standard.string(forKey: Self.pendingSHAKey) ?? ""

        if let local = UserDefaults.standard.string(forKey: Self.pendingLocalDMGKey),
           FileManager.default.fileExists(atPath: local) {
            if installWhenReady {
                do {
                    try Self.scheduleInstallAndRelaunch(
                        dmgPath: local,
                        installRoot: Self.preferredInstallRoot(),
                        expectedBundleID: expectedBundle,
                        expectedSHA256: sha
                    )
                    NSApp.terminate(nil)
                } catch {
                    statusMessage = "No pude aplicar la actualización pendiente"
                }
            }
            return
        }

        // Descarga incompleta: reintentar con metadatos persistidos.
        guard let urlString = UserDefaults.standard.string(forKey: Self.pendingDMGURLKey),
              let url = URL(string: urlString), !sha.isEmpty else { return }
        let release = UpdateFeed.ChannelRelease(
            version: version,
            tag: "v\(version)",
            dmgURL: url,
            notesURL: URL(string: "https://ordena.iareal.net/")!,
            sha256: sha,
            expectedBundleID: expectedBundle
        )
        statusMessage = "Reanudando descarga de \(version)…"
        startPrefetchIfNeeded(release: release)
        // Esperar un poco a que termine si vamos a instalar en este arranque.
        if installWhenReady {
            for _ in 0 ..< 600 {
                if let local = UserDefaults.standard.string(forKey: Self.pendingLocalDMGKey),
                   FileManager.default.fileExists(atPath: local) {
                    do {
                        try Self.scheduleInstallAndRelaunch(
                            dmgPath: local,
                            installRoot: Self.preferredInstallRoot(),
                            expectedBundleID: expectedBundle,
                            expectedSHA256: sha
                        )
                        NSApp.terminate(nil)
                    } catch {
                        statusMessage = "No pude aplicar la actualización pendiente"
                    }
                    return
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
                if downloadingVersion == nil,
                   UserDefaults.standard.string(forKey: Self.pendingLocalDMGKey) == nil {
                    break
                }
            }
        }
    }

    private func clearPending() {
        downloadTask?.cancel()
        downloadTask = nil
        downloadingVersion = nil
        if let local = UserDefaults.standard.string(forKey: Self.pendingLocalDMGKey) {
            try? FileManager.default.removeItem(atPath: local)
        }
        UserDefaults.standard.removeObject(forKey: Self.pendingVersionKey)
        UserDefaults.standard.removeObject(forKey: Self.pendingDMGURLKey)
        UserDefaults.standard.removeObject(forKey: Self.pendingSHAKey)
        UserDefaults.standard.removeObject(forKey: Self.pendingLocalDMGKey)
        UserDefaults.standard.removeObject(forKey: Self.pendingExpectedBundleKey)
    }

    private func downloadAndInstall(release: UpdateFeed.ChannelRelease, terminateAfter: Bool) async {
        isInstalling = true
        statusMessage = "Descargando \(release.tag)…"
        defer { isInstalling = false }

        do {
            persistPendingMetadata(release)
            let dmg = try await downloadVerifiedDMG(release: release)
            UserDefaults.standard.set(dmg.path, forKey: Self.pendingLocalDMGKey)
            statusMessage = "Preparando instalación…"
            try Self.scheduleInstallAndRelaunch(
                dmgPath: dmg.path,
                installRoot: Self.preferredInstallRoot(),
                expectedBundleID: release.expectedBundleID,
                expectedSHA256: release.sha256
            )
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

    private func downloadVerifiedDMG(release: UpdateFeed.ChannelRelease) async throws -> URL {
        let (tempURL, _) = try await URLSession.shared.download(from: release.dmgURL)
        let dmg = FileManager.default.temporaryDirectory
            .appendingPathComponent("Findaro-\(release.version)-pending.dmg")
        try? FileManager.default.removeItem(at: dmg)
        try FileManager.default.moveItem(at: tempURL, to: dmg)

        statusMessage = "Verificando integridad…"
        let digest = try Self.sha256File(at: dmg)
        guard digest == release.sha256.lowercased() else {
            try? FileManager.default.removeItem(at: dmg)
            throw URLError(.cannotParseResponse)
        }
        return dmg
    }

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

    /// Staging + validación de bundle + backup recuperable + rollback.
    private static func scheduleInstallAndRelaunch(
        dmgPath: String,
        installRoot: String,
        expectedBundleID: String,
        expectedSHA256: String
    ) throws {
        let logPath = (NSHomeDirectory() as NSString).appendingPathComponent("Library/Logs/Findaro-update.log")
        let script = """
        set -euo pipefail
        exec >> \(shellEscape(logPath)) 2>&1
        echo "==== $(date) update start ===="
        sleep 2
        DMG=\(shellEscape(dmgPath))
        ROOT=\(shellEscape(installRoot))
        EXPECT_ID=\(shellEscape(expectedBundleID))
        EXPECT_SHA=\(shellEscape(expectedSHA256.lowercased()))
        MNT=$(mktemp -d /tmp/findaro-update.XXXXXX)
        STAGE=""
        BACKUP=""
        DEST=""

        cleanup_mount() {
          hdiutil detach "$MNT" -quiet 2>/dev/null || true
          rm -rf "$MNT" 2>/dev/null || true
        }

        fail_restore() {
          echo "ERROR: $1"
          if [ -n "${BACKUP:-}" ] && [ -d "$BACKUP" ] && [ -n "${DEST:-}" ]; then
            echo "Rollback: restaurando $BACKUP → $DEST"
            rm -rf "$DEST" 2>/dev/null || true
            mv "$BACKUP" "$DEST" || true
          fi
          if [ -n "${STAGE:-}" ]; then rm -rf "$STAGE" 2>/dev/null || true; fi
          cleanup_mount
          exit 1
        }

        GOT_SHA=$(shasum -a 256 "$DMG" | awk '{print $1}')
        [ "$GOT_SHA" = "$EXPECT_SHA" ] || fail_restore "SHA-256 DMG no coincide"

        hdiutil attach "$DMG" -nobrowse -quiet -mountpoint "$MNT" || fail_restore "No montó el DMG"

        APP=""
        DEST_NAME=""
        if [ "$EXPECT_ID" = "app.findaro.files" ]; then
          APP=$(find "$MNT" -maxdepth 2 -name 'Findaro.app' -type d | head -1)
          DEST_NAME="Findaro.app"
        elif [ "$EXPECT_ID" = "app.ordena.files" ]; then
          APP=$(find "$MNT" -maxdepth 2 -name 'Ordena.app' -type d | head -1)
          DEST_NAME="Ordena.app"
        fi
        [ -n "$APP" ] || fail_restore "No hay .app del canal esperado ($EXPECT_ID) en el DMG"

        PLIST="$APP/Contents/Info.plist"
        GOT_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST" 2>/dev/null || true)
        [ "$GOT_ID" = "$EXPECT_ID" ] || fail_restore "Bundle ID del paquete ($GOT_ID) ≠ esperado ($EXPECT_ID)"

        DEST="$ROOT/$DEST_NAME"
        STAGE="$DEST.staging-$$"
        BACKUP="$DEST.bak-$$"
        rm -rf "$STAGE"
        ditto "$APP" "$STAGE" || fail_restore "ditto a staging falló"

        STAGE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$STAGE/Contents/Info.plist" 2>/dev/null || true)
        [ "$STAGE_ID" = "$EXPECT_ID" ] || fail_restore "Staging Bundle ID inválido"
        [ -x "$STAGE/Contents/MacOS/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$STAGE/Contents/Info.plist")" ] \
          || fail_restore "Ejecutable ausente en staging"

        if [ -d "$DEST" ]; then
          rm -rf "$BACKUP"
          mv "$DEST" "$BACKUP" || fail_restore "No pude respaldar la app actual"
        fi

        if ! mv "$STAGE" "$DEST"; then
          fail_restore "No pude colocar la app nueva"
        fi

        # Confirmar destino final antes de borrar backup.
        FINAL_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$DEST/Contents/Info.plist" 2>/dev/null || true)
        if [ "$FINAL_ID" != "$EXPECT_ID" ]; then
          fail_restore "Destino final con Bundle ID incorrecto"
        fi

        rm -rf "$BACKUP"
        cleanup_mount
        rm -f "$DMG" 2>/dev/null || true
        open "$DEST"
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
}
