import Foundation

/// Modo demo / grabación segura: oculta favoritos y ubicaciones personales.
public enum FindaroDemoMode {
    public static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["FINDARO_DEMO_MODE"] == "1"
            || UserDefaults.standard.bool(forKey: "findaro_demo_mode")
    }

    /// Nombres de favoritos/carpetas permitidos en demo (ES + EN + sistema).
    public static let allowedFavoriteNames: Set<String> = [
        "Downloads", "Descargas",
        "Desktop", "Escritorio",
        "Documents", "Documentos",
        "Estudio Aurora", "Respaldo Estudio",
        "Aurora Studio", "Studio Backup",
        "FINDARO-Demo", "FINDARO-Demo-ES", "FINDARO-Demo-EN",
        "ORIGEN", "DESTINO", "Origin", "Destination"
    ]

    public static func isAllowedFavorite(path: String) -> Bool {
        let name = URL(fileURLWithPath: path).lastPathComponent
        if allowedFavoriteNames.contains(name) { return true }
        // Rutas bajo dataset sintético.
        let lower = path.lowercased()
        return lower.contains("findaro-demo")
            || lower.contains("/tmp/findaro-qa-sandbox")
    }

    /// Particiones APFS internas que nunca deben aparecer en Ubicaciones.
    public static let excludedVolumeNames: Set<String> = [
        "Recovery", "Preboot", "VM", "Update", "Hardware", "xarts", "iSCPreboot"
    ]

    public static func isExcludedVolume(name: String) -> Bool {
        if excludedVolumeNames.contains(name) { return true }
        let lower = name.lowercased()
        return excludedVolumeNames.contains { lower == $0.lowercased() }
            || lower.hasPrefix("recovery")
            || lower.hasPrefix("preboot")
    }
}
