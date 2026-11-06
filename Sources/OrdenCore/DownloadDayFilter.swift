import Foundation

/// Criterio del «modo Descargados»: actividad de hoy en la carpeta actual.
/// Usa fecha de agregado a la carpeta (lo que ve Finder) y, de respaldo, creación.
public enum DownloadDayFilter: Sendable {
    /// ¿Este ítem aparece como actividad de hoy en esta carpeta?
    public static func isActivityToday(_ entry: FileEntry, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        if calendar.isDate(entry.dateAdded, inSameDayAs: now) {
            return true
        }
        // Algunos navegadores dejan creation ≈ momento de descarga
        if calendar.isDate(entry.dateCreated, inSameDayAs: now) {
            return true
        }
        return false
    }

    /// Orden exclusivo del modo: lo más reciente arriba.
    public static func sortNewestFirst(_ entries: [FileEntry]) -> [FileEntry] {
        entries.sorted { lhs, rhs in
            if lhs.dateAdded != rhs.dateAdded {
                return lhs.dateAdded > rhs.dateAdded
            }
            return lhs.dateCreated > rhs.dateCreated
        }
    }
}
