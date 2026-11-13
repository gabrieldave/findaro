import Foundation

/// Formateo y escape de rutas POSIX para portapapeles y Terminal.
public enum PathFormatter {
    /// Formatea una lista de rutas como líneas POSIX individuales (una por línea).
    public static func posixLines(for paths: [String]) -> String {
        paths.joined(separator: "\n")
    }

    /// Formatea una lista de rutas escapadas para Terminal/Shell, separadas por espacios.
    public static func shellEscaped(for paths: [String]) -> String {
        paths.map { shellEscape($0) }.joined(separator: " ")
    }

    /// Escapa una ruta individual para uso seguro en shell.
    /// Si contiene espacios, comillas o caracteres especiales, la envuelve en comillas simples y escapa comillas internas.
    public static func shellEscape(_ path: String) -> String {
        guard !path.isEmpty else { return "''" }

        // Caracteres seguros que no requieren escape en zsh/bash
        let safeCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_./~@%:+")
        if path.unicodeScalars.allSatisfy({ safeCharacters.contains($0) }) {
            return path
        }

        // Encomillar con '...' y reemplazar ' por '\''
        let escaped = path.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }
}
