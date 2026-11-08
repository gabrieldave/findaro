import Foundation

/// Combinación de teclas persistible (sin AppKit).
public struct KeyChord: Codable, Equatable, Hashable, Sendable {
    public var keyCode: UInt16
    /// Letra/dígito en minúsculas cuando aplica; vacío en teclas especiales.
    public var character: String
    public var command: Bool
    public var option: Bool
    public var shift: Bool
    public var control: Bool

    public init(
        keyCode: UInt16,
        character: String = "",
        command: Bool = false,
        option: Bool = false,
        shift: Bool = false,
        control: Bool = false
    ) {
        self.keyCode = keyCode
        self.character = character.lowercased()
        self.command = command
        self.option = option
        self.shift = shift
        self.control = control
    }

    public func matches(
        keyCode: UInt16,
        characters: String,
        command: Bool,
        option: Bool,
        shift: Bool,
        control: Bool
    ) -> Bool {
        guard self.command == command,
              self.option == option,
              self.shift == shift,
              self.control == control else { return false }
        if self.keyCode != 0, self.keyCode == keyCode { return true }
        let ch = characters.lowercased()
        guard !self.character.isEmpty, !ch.isEmpty else { return false }
        return self.character == ch
    }

    public var displayLabel: String {
        var parts: [String] = []
        if control { parts.append("⌃") }
        if option { parts.append("⌥") }
        if shift { parts.append("⇧") }
        if command { parts.append("⌘") }
        parts.append(keySymbol)
        return parts.joined()
    }

    private var keySymbol: String {
        switch keyCode {
        case 36: return "↩"
        case 48: return "⇥"
        case 49: return "Espacio"
        case 51: return "⌫"
        case 53: return "Esc"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 99: return "F3"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        case 118: return "F4"
        case 120: return "F2"
        case 122: return "F1"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default:
            if !character.isEmpty { return character.uppercased() }
            return "·"
        }
    }
}

public enum AppHotkeyGroup: String, Codable, Sendable, CaseIterable {
    case navigation
    case files
    case dualPane
    case searchAssistant
    case view

    public var titleSpanish: String {
        switch self {
        case .navigation: return "Navegación"
        case .files: return "Archivos"
        case .dualPane: return "Doble panel"
        case .searchAssistant: return "Buscar y asistente"
        case .view: return "Vista"
        }
    }
}

/// Definición de un atajo de teclado de la app (catálogo + override).
public struct AppHotkeyDefinition: Identifiable, Equatable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var detail: String
    public var group: AppHotkeyGroup
    public var defaultChord: KeyChord
    /// Si false, solo se muestra (p. ej. Carbon global).
    public var isEditable: Bool

    public init(
        id: String,
        title: String,
        detail: String,
        group: AppHotkeyGroup,
        defaultChord: KeyChord,
        isEditable: Bool = true
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.group = group
        self.defaultChord = defaultChord
        self.isEditable = isEditable
    }
}

public enum AppHotkeyCatalog {
    // keyCodes macOS habituales
    public static let catalog: [AppHotkeyDefinition] = [
        // Navegación
        .init(id: "nav.back", title: "Atrás", detail: "Carpeta anterior del historial", group: .navigation,
              defaultChord: .init(keyCode: 18, character: "1", command: true)),
        .init(id: "nav.forward", title: "Adelante", detail: "Siguiente carpeta del historial", group: .navigation,
              defaultChord: .init(keyCode: 19, character: "2", command: true)),
        .init(id: "nav.backOption", title: "Atrás (⌥)", detail: "Igual que atrás, con Option", group: .navigation,
              defaultChord: .init(keyCode: 123, option: true)),
        .init(id: "nav.forwardOption", title: "Adelante (⌥)", detail: "Igual que adelante, con Option", group: .navigation,
              defaultChord: .init(keyCode: 124, option: true)),
        .init(id: "nav.up", title: "Carpeta superior", detail: "Sube un nivel", group: .navigation,
              defaultChord: .init(keyCode: 126, command: true)),
        .init(id: "nav.goTo", title: "Ir a carpeta…", detail: "Abrir diálogo de ruta", group: .navigation,
              defaultChord: .init(keyCode: 20, character: "3", command: true)),
        // ⌘E (mano izq.) — antes ⌘L, lejos de la izquierda.
        .init(id: "nav.omnibox", title: "Editar ruta", detail: "Omnibox de la barra de ruta · Enter confirma", group: .navigation,
              defaultChord: .init(keyCode: 14, character: "e", command: true)),
        .init(id: "nav.downloads", title: "Ir a Descargas", detail: "Salto rápido a Descargas", group: .navigation,
              defaultChord: .init(keyCode: 37, character: "l", command: true, shift: true)),
        .init(id: "nav.globalOpen", title: "Abrir Findaro (global)", detail: "Desde cualquier app → carpeta elegida", group: .navigation,
              defaultChord: .init(keyCode: 31, character: "o", option: true, control: true), isEditable: true),

        // Archivos
        .init(id: "files.undo", title: "Deshacer", detail: "Deshace el último movimiento/copia", group: .files,
              defaultChord: .init(keyCode: 6, character: "z", command: true)),
        .init(id: "files.copy", title: "Copiar a bandeja", detail: "Copia la selección a la bandeja", group: .files,
              defaultChord: .init(keyCode: 8, character: "c", command: true)),
        .init(id: "files.cut", title: "Cortar a bandeja", detail: "Prepara mover al pegar", group: .files,
              defaultChord: .init(keyCode: 7, character: "x", command: true)),
        .init(id: "files.paste", title: "Soltar bandeja", detail: "Pega/mueve en la carpeta actual", group: .files,
              defaultChord: .init(keyCode: 9, character: "v", command: true)),
        .init(id: "files.duplicate", title: "Duplicar", detail: "Copia al lado con otro nombre", group: .files,
              defaultChord: .init(keyCode: 2, character: "d", command: true)),
        .init(id: "files.copyPath", title: "Copiar ruta", detail: "Ruta completa al portapapeles", group: .files,
              defaultChord: .init(keyCode: 8, character: "c", command: true, option: true)),
        .init(id: "files.newFile", title: "Nuevo archivo", detail: "Crea un archivo vacío", group: .files,
              defaultChord: .init(keyCode: 45, character: "n", command: true)),
        .init(id: "files.newFolder", title: "Nueva carpeta", detail: "Crea una carpeta", group: .files,
              defaultChord: .init(keyCode: 45, character: "n", command: true, shift: true)),
        .init(id: "files.open", title: "Abrir selección", detail: "Abre el ítem seleccionado", group: .files,
              defaultChord: .init(keyCode: 125, command: true)),
        .init(id: "files.quickLook", title: "Vista rápida", detail: "Quick Look del archivo", group: .files,
              defaultChord: .init(keyCode: 49)),
        .init(id: "files.trash", title: "Mover a la Papelera", detail: "Envía la selección a la Papelera", group: .files,
              defaultChord: .init(keyCode: 51, command: true)),
        .init(id: "files.renameF2", title: "Renombrar (F2)", detail: "Renombra el ítem seleccionado", group: .files,
              defaultChord: .init(keyCode: 120)),
        .init(id: "files.return", title: "Return", detail: "Explorer: abrir · Finder: renombrar", group: .files,
              defaultChord: .init(keyCode: 36)),
        .init(id: "files.selectAll", title: "Seleccionar todos", detail: "Marca todos los visibles", group: .files,
              defaultChord: .init(keyCode: 0, character: "a", command: true)),
        .init(id: "files.cancel", title: "Quitar selección / salir", detail: "Esc: filtros, búsqueda o selección", group: .files,
              defaultChord: .init(keyCode: 53)),
        .init(id: "files.favorite", title: "Añadir a Favoritos", detail: "Favorito la carpeta actual", group: .files,
              defaultChord: .init(keyCode: 17, character: "t", command: true, shift: true)),

        // Dual pane
        .init(id: "dual.toggle", title: "Dos paneles", detail: "Activa/desactiva Origen · Destino", group: .dualPane,
              defaultChord: .init(keyCode: 2, character: "d", command: true, shift: true)),
        .init(id: "dual.focusOrigin", title: "Panel Origen", detail: "Enfoca el panel izquierdo", group: .dualPane,
              defaultChord: .init(keyCode: 123, command: true, shift: true)),
        .init(id: "dual.focusDest", title: "Panel Destino", detail: "Enfoca el panel derecho", group: .dualPane,
              defaultChord: .init(keyCode: 124, command: true, shift: true)),
        .init(id: "dual.swapFocus", title: "Cambiar de panel", detail: "Tab entre Origen y Destino", group: .dualPane,
              defaultChord: .init(keyCode: 48)),
        .init(id: "dual.moveToDest", title: "Mover → Destino", detail: "Mueve la selección al Destino", group: .dualPane,
              defaultChord: .init(keyCode: 46, character: "m", command: true, shift: true)),
        .init(id: "dual.moveToOrigin", title: "Mover → Origen", detail: "Mueve desde Destino al Origen", group: .dualPane,
              defaultChord: .init(keyCode: 46, character: "m", command: true, option: true, shift: true)),

        // Buscar / asistente
        .init(id: "search.deep", title: "Buscar en subcarpetas", detail: "Búsqueda recursiva ⌘4", group: .searchAssistant,
              defaultChord: .init(keyCode: 21, character: "4", command: true)),
        .init(id: "assistant.toggle", title: "Mostrar asistente", detail: "Abre/cierra el panel ⌘5", group: .searchAssistant,
              defaultChord: .init(keyCode: 23, character: "5", command: true)),
        .init(id: "assistant.focus", title: "Ir al asistente", detail: "Enfoca el panel ⌘6", group: .searchAssistant,
              defaultChord: .init(keyCode: 22, character: "6", command: true)),
        .init(id: "assistant.voice", title: "Hablar (mantener)", detail: "⌃Espacio push-to-talk", group: .searchAssistant,
              defaultChord: .init(keyCode: 49, control: true)),

        // Vista
        .init(id: "view.hidden", title: "Mostrar ocultos", detail: "Alterna archivos ocultos", group: .view,
              defaultChord: .init(keyCode: 47, character: ".", command: true, shift: true)),
        .init(id: "view.multi", title: "Modo varios", detail: "Selección múltiple (naranja)", group: .view,
              defaultChord: .init(keyCode: 46, character: "m", command: true, shift: true)),
    ]

    public static func definition(id: String) -> AppHotkeyDefinition? {
        catalog.first { $0.id == id }
    }

    public static func resolvedChord(id: String, overrides: [String: KeyChord]) -> KeyChord? {
        if let custom = overrides[id] { return custom }
        return definition(id: id)?.defaultChord
    }

    public static func resolved(overrides: [String: KeyChord]) -> [String: KeyChord] {
        var map: [String: KeyChord] = [:]
        for def in catalog {
            map[def.id] = overrides[def.id] ?? def.defaultChord
        }
        return map
    }
}
