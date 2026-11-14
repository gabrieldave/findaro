import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Intención de una transferencia al soltar archivos.
public enum DropIntent: Equatable, Sendable {
    case move
    case copy
}

/// Reglas puras (sin AppKit) de recepción de Drag & Drop sobre carpetas.
///
/// Objetivo: soltar archivos dentro de la carpeta abierta (o sobre una subcarpeta)
/// transfiere DIRECTAMENTE a ese directorio, nunca a la Bandeja (ClipboardTray).
public enum FolderDropPolicy {
    /// Directorio destino de un drop: la subcarpeta bajo el cursor si la hay;
    /// si no, la carpeta abierta del panel.
    public static func destination(panelDirectory: String, hoveredFolder: String?) -> String {
        if let hoveredFolder, !hoveredFolder.isEmpty {
            return canonical(hoveredFolder)
        }
        return canonical(panelDirectory)
    }

    /// Mover vs copiar.
    /// - ⌥ (Option) siempre copia.
    /// - Si el origen no permite `.move` en su `draggingSourceOperationMask` → copiar.
    /// - Mismo volumen y `.move` permitido → mover.
    /// - Otro volumen: ⌘ fuerza mover; sin ⌘ → copiar (más seguro y coherente con Finder).
    public static func intent(
        optionHeld: Bool,
        commandHeld: Bool,
        sourceAllowsMove: Bool,
        sameVolume: Bool
    ) -> DropIntent {
        if optionHeld { return .copy }
        if !sourceAllowsMove { return .copy }
        if !sameVolume && !commandHeld { return .copy }
        return .move
    }

    /// ¿Los dos paths viven en el mismo dispositivo/volumen?
    public static func sameVolume(_ lhs: String, _ rhs: String) -> Bool {
        guard let a = deviceID(lhs), let b = deviceID(rhs) else { return true }
        return a == b
    }

    /// Normaliza rutas canónicas (sin `..`, sin barras duplicadas, sin barra final).
    public static func canonical(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    /// Filtra orígenes inválidos para un destino:
    /// - duplicados (canónicos),
    /// - el propio destino,
    /// - ancestros del destino (evita meter una carpeta dentro de sí misma),
    /// - elementos cuyo padre ya es el destino (auto-movimiento redundante).
    public static func filteredPaths(_ paths: [String], destination: String) -> [String] {
        let dest = canonical(destination)
        var seen = Set<String>()
        var result: [String] = []
        for raw in paths {
            let path = canonical(raw)
            guard !path.isEmpty, path != "/" else { continue }
            guard path != dest else { continue }
            guard !dest.hasPrefix(path + "/") else { continue }
            guard (path as NSString).deletingLastPathComponent != dest else { continue }
            guard seen.insert(path).inserted else { continue }
            result.append(path)
        }
        return result
    }

    private static func deviceID(_ path: String) -> Int64? {
        #if canImport(Darwin)
        var info = stat()
        guard stat(path, &info) == 0 else { return nil }
        return Int64(info.st_dev)
        #else
        return nil
        #endif
    }
}

/// Estado y toggle de Favoritos sobre la carpeta actual (sin selección).
public enum FavoritesPolicy {
    /// Comparación canónica: `standardizedFileURL` (sin barra final, sin `..`).
    public static func canonical(_ path: String) -> String {
        FolderDropPolicy.canonical(path)
    }

    public static func contains(_ favorites: [String], path: String) -> Bool {
        let target = canonical(path)
        return favorites.contains { canonical($0) == target }
    }

    /// Devuelve la nueva lista y si se añadió (`true`) o se quitó (`false`).
    public static func toggled(_ favorites: [String], path: String) -> (favorites: [String], added: Bool) {
        let target = canonical(path)
        if contains(favorites, path: target) {
            return (favorites.filter { canonical($0) != target }, false)
        }
        return (favorites + [target], true)
    }
}
