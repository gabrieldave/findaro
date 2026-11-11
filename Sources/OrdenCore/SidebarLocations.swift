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
        trashPath: String?,
        demoMode: Bool = FindaroDemoMode.isEnabled
    ) -> [SidebarLocation] {
        var items: [SidebarLocation] = []
        var seen: Set<String> = []

        func push(_ item: SidebarLocation, resolved: String) {
            let key = normalize(resolved)
            guard seen.insert(key).inserted else { return }
            items.append(item)
        }

        if !demoMode, let iCloudPath {
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

        if !demoMode {
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
        }

        // En demo no mostramos el home real del usuario (daveax…).
        if !demoMode {
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
        }

        push(
            SidebarLocation(
                id: "loc-root",
                title: "Macintosh HD",
                path: "/",
                systemImage: "internaldrive.fill"
            ),
            resolved: "/"
        )

        if !demoMode {
            for volume in volumes.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) {
                if FindaroDemoMode.isExcludedVolume(name: volume.name) { continue }
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
        let tagged = folders.map { folder -> (CloudFolder, String, String) in
            let (base, icon) = serviceTitle(folder.name)
            return (folder, base, icon)
        }
        var counts: [String: Int] = [:]
        var seenIndex: [String: Int] = [:]
        for item in tagged {
            counts[item.1, default: 0] += 1
        }
        return tagged.map { folder, base, icon in
            let title: String
            if counts[base, default: 0] > 1 {
                let n = (seenIndex[base] ?? 0) + 1
                seenIndex[base] = n
                title = "\(base) \(n)"
            } else {
                title = base
            }
            return TitledCloud(folder: folder, title: title, icon: icon)
        }
    }

    private static func serviceTitle(_ folderName: String) -> (String, String) {
        let cleaned = sanitizeCloudFolderName(folderName)
        let lower = cleaned.lowercased()
        if lower.contains("icloud") {
            return ("iCloud Drive", "icloud.fill")
        }
        if lower.contains("google") {
            return ("Google Drive", "externaldrive.fill.badge.icloud")
        }
        if lower.contains("dropbox") {
            return ("Dropbox", "externaldrive.fill.badge.icloud")
        }
        if lower.contains("onedrive") || lower.contains("one drive") {
            return ("OneDrive", "externaldrive.fill.badge.icloud")
        }
        // Nunca mostrar el nombre crudo con correo/timestamp.
        return ("Cloud Storage", "externaldrive.fill")
    }

    /// Quita correos, timestamps y basura de nombres CloudStorage.
    public static func sanitizeCloudFolderName(_ folderName: String) -> String {
        var name = folderName
        // `Something (from 9:36 a.m.)` → Something
        if let cut = name.range(of: " (") {
            name = String(name[..<cut.lowerBound])
        }
        // Prefijos típicos de proveedores
        for marker in ["GoogleDrive-", "Dropbox-", "OneDrive-", "iCloudDrive-"] {
            if name.hasPrefix(marker) {
                name = String(name.dropFirst(marker.count))
                break
            }
        }
        // Si quedó un correo, descartarlo — el título lo decide serviceTitle.
        if name.contains("@") {
            if folderName.lowercased().contains("google") { return "Google Drive" }
            if folderName.lowercased().contains("dropbox") { return "Dropbox" }
            if folderName.lowercased().contains("onedrive") { return "OneDrive" }
            if folderName.lowercased().contains("icloud") { return "iCloud Drive" }
            return "Cloud Storage"
        }
        return name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `GoogleDrive-ana@gmail.com` o `GoogleDrive-ana@gmail.com (1)` → el correo (legacy tests / diagnóstico).
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
        (path as NSString).standardizingPath
    }
}
