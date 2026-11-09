import Foundation

/// Una fila de Ubicaciones. El path ya está deduplicado por su ruta real.
public struct SidebarLocation: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let path: String
    public let systemImage: String

    public init(id: String, title: String, path: String, systemImage: String) {
        self.id = id
        self.title = title
        self.path = path
        self.systemImage = systemImage
    }
}

public enum SidebarLocations {
    public struct CloudFolder: Equatable, Sendable {
        public var name: String
        public var path: String

        public init(name: String, path: String) {
            self.name = name
            self.path = path
        }
    }

    /// `resolvedPath` es la ruta con symlinks resueltos (`/Volumes/Macintosh HD` → `/`).
    public struct Volume: Equatable, Sendable {
        public var name: String
        public var path: String
        public var resolvedPath: String

        public init(name: String, path: String, resolvedPath: String) {
            self.name = name
            self.path = path
            self.resolvedPath = resolvedPath
        }
    }

    public static func make(
        homePath: String,
        iCloudPath: String?,
        cloudFolders: [CloudFolder],
        volumes: [Volume],
        trashPath: String?
    ) -> [SidebarLocation] {
        var items: [SidebarLocation] = []
        var seen: Set<String> = []

        func push(_ item: SidebarLocation, resolved: String) {
            let key = normalize(resolved)
            guard seen.insert(key).inserted else { return }
            items.append(item)
        }

        if let iCloudPath {
            push(
                SidebarLocation(
                    id: "loc-icloud",
                    title: "iCloud Drive",
                    path: iCloudPath,
                    systemImage: "icloud.fill"
                ),
                resolved: iCloudPath
            )
        }

        let clouds = cloudFolders.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let titledClouds = disambiguate(clouds)
        for cloud in titledClouds {
            push(
                SidebarLocation(
                    id: "loc-cloud-\(cloud.folder.name)",
                    title: cloud.title,
                    path: cloud.folder.path,
                    systemImage: cloud.icon
                ),
                resolved: cloud.folder.path
            )
        }

        let homeName = URL(fileURLWithPath: homePath).lastPathComponent
        push(
            SidebarLocation(
                id: "loc-home",
                title: homeName,
                path: homePath,
                systemImage: "house.fill"
            ),
            resolved: homePath
        )

        push(
            SidebarLocation(
                id: "loc-root",
                title: "Macintosh HD",
                path: "/",
                systemImage: "internaldrive.fill"
            ),
            resolved: "/"
        )

        for volume in volumes.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) {
            let resolved = normalize(volume.resolvedPath)
            if resolved == "/" { continue }
            push(
                SidebarLocation(
                    id: "loc-vol-\(volume.name)",
                    title: volume.name,
                    path: volume.path,
                    systemImage: "externaldrive.fill"
                ),
                resolved: resolved
            )
        }

        if let trashPath {
            push(
                SidebarLocation(
                    id: "loc-trash",
                    title: L10n.s("Papelera", "Trash"),
                    path: trashPath,
                    systemImage: "trash.fill"
                ),
                resolved: trashPath
            )
        }

        return items
    }

    private struct TitledCloud {
        var folder: CloudFolder
        var title: String
        var icon: String
    }

    private static func disambiguate(_ folders: [CloudFolder]) -> [TitledCloud] {
        let tagged = folders.map { folder -> (CloudFolder, String, String, String?) in
            let (base, icon) = serviceTitle(folder.name)
            return (folder, base, icon, accountSuffix(folder.name))
        }
        var counts: [String: Int] = [:]
        for item in tagged {
            counts[item.1, default: 0] += 1
        }
        return tagged.map { folder, base, icon, account in
            let title: String
            if counts[base, default: 0] > 1, let account, !account.isEmpty {
                // Sidebar estrecho: "Drive · usuario" cabe mejor que el correo completo.
                let local = account.split(separator: "@").first.map(String.init) ?? account
                title = "\(shortServiceLabel(base)) · \(local)"
            } else {
                title = base
            }
            return TitledCloud(folder: folder, title: title, icon: icon)
        }
    }

    /// Etiqueta corta al desambiguar varias cuentas del mismo servicio.
    private static func shortServiceLabel(_ base: String) -> String {
        switch base {
        case "Google Drive": return "Drive"
        case "OneDrive": return "OneDrive"
        case "Dropbox": return "Dropbox"
        default: return base
        }
    }

    private static func serviceTitle(_ folderName: String) -> (String, String) {
        let lower = folderName.lowercased()
        if lower.contains("google") {
            return ("Google Drive", "externaldrive.fill.badge.icloud")
        }
        if lower.contains("dropbox") {
            return ("Dropbox", "externaldrive.fill.badge.icloud")
        }
        if lower.contains("onedrive") || lower.contains("one drive") {
            return ("OneDrive", "externaldrive.fill.badge.icloud")
        }
        return (folderName, "externaldrive.fill")
    }

    /// `GoogleDrive-ana@gmail.com` o `GoogleDrive-ana@gmail.com (1)` → el correo.
    static func accountSuffix(_ folderName: String) -> String? {
        let markers = ["GoogleDrive-", "Dropbox-", "OneDrive-"]
        for marker in markers where folderName.hasPrefix(marker) {
            var rest = String(folderName.dropFirst(marker.count))
            if let cut = rest.range(of: " (") {
                rest = String(rest[..<cut.lowerBound])
            }
            let trimmed = rest.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return nil
    }

    private static func normalize(_ path: String) -> String {
        if path == "/" { return "/" }
        return URL(fileURLWithPath: path).standardizedFileURL.path
    }
}
