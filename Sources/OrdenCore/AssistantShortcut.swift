import Foundation

/// Ventana de fechas relativa (fecha de agregado a la carpeta).
public enum ShortcutDateWindow: Codable, Equatable, Sendable, Hashable {
    case today
    case yesterday
    /// Incluye hoy hacia atrás N días calendario (1 = hoy, 7 = última semana).
    case lastDays(Int)

    public var labelSpanish: String {
        switch self {
        case .today: return "hoy"
        case .yesterday: return "ayer"
        case .lastDays(let n):
            if n <= 1 { return "hoy" }
            if n == 7 { return "hace 1 semana" }
            return "hace \(n) días"
        }
    }

    public var labelEnglish: String {
        switch self {
        case .today: return "today"
        case .yesterday: return "yesterday"
        case .lastDays(let n):
            if n <= 1 { return "today" }
            if n == 7 { return "1 week ago" }
            return "\(n) days ago"
        }
    }

    public var labelLocalized: String {
        L10n.isEnglish ? labelEnglish : labelSpanish
    }

    public func matches(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        switch self {
        case .today:
            return calendar.isDate(date, inSameDayAs: now)
        case .yesterday:
            guard let y = calendar.date(byAdding: .day, value: -1, to: now) else { return false }
            return calendar.isDate(date, inSameDayAs: y)
        case .lastDays(let n):
            let days = max(1, n)
            guard let start = calendar.date(
                byAdding: .day,
                value: -(days - 1),
                to: calendar.startOfDay(for: now)
            ) else { return false }
            return date >= start && date <= now.addingTimeInterval(1)
        }
    }
}

/// Atajo guardado del asistente: tipo(s) + rango de fechas.
public struct AssistantShortcut: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    /// Vacío = cualquier tipo. Varias = p. ej. documentos (pdf+office+texto).
    public var categories: [FileCategory]
    public var dateWindow: ShortcutDateWindow
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        categories: [FileCategory],
        dateWindow: ShortcutDateWindow,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.categories = categories
        self.dateWindow = dateWindow
        self.createdAt = createdAt
    }

    public var displayTitle: String {
        guard L10n.isEnglish else { return title }
        switch title {
        case "Imágenes de hoy": return "Today's images"
        case "Imágenes de hace 1 semana": return "Images from 1 week ago"
        case "Documentos de ayer": return "Yesterday's documents"
        case "Música de hace 3 días": return "Music from 3 days ago"
        default:
            var t = title
            if t.hasPrefix("Imágenes ") {
                t = t.replacingOccurrences(of: "Imágenes de hoy", with: "Today's images")
                     .replacingOccurrences(of: "Imágenes de hace 1 semana", with: "Images from 1 week ago")
                     .replacingOccurrences(of: "Imágenes de hace ", with: "Images from ")
                     .replacingOccurrences(of: " días", with: " days ago")
            } else if t.hasPrefix("Documentos ") {
                t = t.replacingOccurrences(of: "Documentos de ayer", with: "Yesterday's documents")
                     .replacingOccurrences(of: "Documentos de hoy", with: "Today's documents")
                     .replacingOccurrences(of: "Documentos de hace ", with: "Documents from ")
                     .replacingOccurrences(of: " días", with: " days ago")
            } else if t.hasPrefix("Archivos ") {
                t = t.replacingOccurrences(of: "Archivos de hoy", with: "Today's files")
                     .replacingOccurrences(of: "Archivos de ayer", with: "Yesterday's files")
                     .replacingOccurrences(of: "Archivos de hace ", with: "Files from ")
                     .replacingOccurrences(of: " días", with: " days ago")
            }
            return t
        }
    }

    public static let maxCount = 80

    public static var documentCategories: [FileCategory] {
        [.pdf, .word, .excel, .powerpoint, .text]
    }

    public static func factoryDefaults() -> [AssistantShortcut] {
        [
            AssistantShortcut(
                title: "Imágenes de hoy",
                categories: [.image],
                dateWindow: .today
            ),
            AssistantShortcut(
                title: "Imágenes de hace 1 semana",
                categories: [.image],
                dateWindow: .lastDays(7)
            ),
            AssistantShortcut(
                title: "Documentos de ayer",
                categories: documentCategories,
                dateWindow: .yesterday
            ),
            AssistantShortcut(
                title: "Música de hace 3 días",
                categories: [.audio],
                dateWindow: .lastDays(3)
            )
        ]
    }

    public func matches(_ entry: FileEntry, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        if !categories.isEmpty, !categories.contains(entry.category) {
            return false
        }
        let date = entry.dateAdded
        if dateWindow.matches(date, now: now, calendar: calendar) {
            return true
        }
        // Respaldo: creación el mismo día (descargas).
        return dateWindow.matches(entry.dateCreated, now: now, calendar: calendar)
    }
}

extension ShortcutDateWindow {
    enum CodingKeys: String, CodingKey {
        case type, days
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "today": self = .today
        case "yesterday": self = .yesterday
        case "lastDays":
            let days = try c.decodeIfPresent(Int.self, forKey: .days) ?? 7
            self = .lastDays(max(1, days))
        default:
            self = .today
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .today:
            try c.encode("today", forKey: .type)
        case .yesterday:
            try c.encode("yesterday", forKey: .type)
        case .lastDays(let n):
            try c.encode("lastDays", forKey: .type)
            try c.encode(n, forKey: .days)
        }
    }
}
