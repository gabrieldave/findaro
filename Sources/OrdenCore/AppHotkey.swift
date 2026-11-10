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

    /// Comprueba si dos atajos colisionan semánticamente (mismos modificadores y misma tecla o carácter).
    public func conflicts(with other: KeyChord) -> Bool {
        guard self.command == other.command,
              self.option == other.option,
              self.shift == other.shift,
              self.control == other.control else { return false }
        if self.keyCode != 0, other.keyCode != 0, self.keyCode == other.keyCode { return true }
        let a = self.character.lowercased()
        let b = other.character.lowercased()
        if !a.isEmpty, !b.isEmpty, a == b { return true }
        return false
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
        case 49: return L10n.isEnglish ? "Space" : "Espacio"
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
    case windows
    case files
    case dualPane
    case searchAssistant
    case view

    public var titleSpanish: String {
        switch self {
        case .navigation: return "Navegación"
        case .windows: return "Ventanas y pestañas"
        case .files: return "Archivos"
        case .dualPane: return "Doble panel"
        case .searchAssistant: return "Buscar y asistente"
        case .view: return "Vista"
        }
    }

    public var titleEnglish: String {
        switch self {
        case .navigation: return "Navigation"
        case .windows: return "Windows & Tabs"
        case .files: return "Files"
        case .dualPane: return "Dual Pane"
        case .searchAssistant: return "Search & Assistant"
        case .view: return "View"
        }
    }

    public var titleLocalized: String {
        L10n.isEnglish ? titleEnglish : titleSpanish
    }
}

/// Definición de un atajo de teclado de la app (catálogo + override).
public struct AppHotkeyDefinition: Identifiable, Equatable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var titleEnglish: String
    public var detail: String
    public var detailEnglish: String
    public var group: AppHotkeyGroup
    public var defaultChord: KeyChord
    /// Si false, solo se muestra (p. ej. Carbon global).
    public var isEditable: Bool

    public init(
        id: String,
        title: String,
        titleEnglish: String = "",
        detail: String,
        detailEnglish: String = "",
        group: AppHotkeyGroup,
        defaultChord: KeyChord,
        isEditable: Bool = true
    ) {
        self.id = id
        self.title = title
        self.titleEnglish = titleEnglish.isEmpty ? title : titleEnglish
        self.detail = detail
        self.detailEnglish = detailEnglish.isEmpty ? detail : detailEnglish
        self.group = group
        self.defaultChord = defaultChord
        self.isEditable = isEditable
    }

    public var titleLocalized: String {
        L10n.isEnglish ? titleEnglish : title
    }

    public var detailLocalized: String {
        L10n.isEnglish ? detailEnglish : detail
    }
}

public enum AppHotkeyCatalog {
    // keyCodes macOS habituales
    public static let catalog: [AppHotkeyDefinition] = [
        // Navegación
        .init(id: "nav.back", title: "Atrás", titleEnglish: "Back", detail: "Carpeta anterior del historial", detailEnglish: "Previous folder in history", group: .navigation,
              defaultChord: .init(keyCode: 18, character: "1", command: true)),
        .init(id: "nav.forward", title: "Adelante", titleEnglish: "Forward", detail: "Siguiente carpeta del historial", detailEnglish: "Next folder in history", group: .navigation,
              defaultChord: .init(keyCode: 19, character: "2", command: true)),
        .init(id: "nav.backOption", title: "Atrás (⌥)", titleEnglish: "Back (⌥)", detail: "Igual que atrás, con Option", detailEnglish: "Same as back, with Option", group: .navigation,
              defaultChord: .init(keyCode: 123, option: true)),
        .init(id: "nav.forwardOption", title: "Adelante (⌥)", titleEnglish: "Forward (⌥)", detail: "Igual que adelante, con Option", detailEnglish: "Same as forward, with Option", group: .navigation,
              defaultChord: .init(keyCode: 124, option: true)),
        .init(id: "nav.up", title: "Carpeta superior", titleEnglish: "Enclosing Folder", detail: "Sube un nivel", detailEnglish: "Go up one level", group: .navigation,
              defaultChord: .init(keyCode: 126, command: true)),
        .init(id: "nav.goTo", title: "Ir a carpeta…", titleEnglish: "Go to Folder…", detail: "Abrir diálogo de ruta", detailEnglish: "Open path dialog", group: .navigation,
              defaultChord: .init(keyCode: 20, character: "3", command: true)),
        .init(id: "nav.omnibox", title: "Editar ruta", titleEnglish: "Edit Path", detail: "Omnibox de la barra de ruta · Enter confirma", detailEnglish: "Path bar omnibox · Enter confirms", group: .navigation,
              defaultChord: .init(keyCode: 14, character: "e", command: true)),
        .init(id: "nav.downloads", title: "Ir a Descargas", titleEnglish: "Go to Downloads", detail: "Salto rápido a Descargas", detailEnglish: "Quick jump to Downloads", group: .navigation,
              defaultChord: .init(keyCode: 37, character: "l", command: true, shift: true)),
        .init(id: "nav.globalOpen", title: "Abrir Findaro (global)", titleEnglish: "Open Findaro (Global)", detail: "Desde cualquier app → carpeta elegida", detailEnglish: "From any app → chosen folder", group: .navigation,
              defaultChord: .init(keyCode: 31, character: "o", option: true, control: true), isEditable: true),
        .init(id: "help.guide", title: "Ayuda de Findaro", titleEnglish: "Findaro Help", detail: "Abre la guía nativa y atajos de Findaro", detailEnglish: "Open native guide and shortcuts", group: .navigation,
              defaultChord: .init(keyCode: 44, character: "?", command: true, shift: true)),

        // Ventanas y pestañas
        .init(id: "win.newWindow", title: "Nueva ventana", titleEnglish: "New Window", detail: "Abre otro explorador independiente", detailEnglish: "Open another independent window", group: .windows,
              defaultChord: .init(keyCode: 45, character: "n", command: true, option: true)),
        .init(id: "win.newTab", title: "Nueva pestaña", titleEnglish: "New Tab", detail: "Pestaña en la ventana actual", detailEnglish: "Tab in current window", group: .windows,
              defaultChord: .init(keyCode: 17, character: "t", command: true)),
        .init(id: "win.closeTab", title: "Cerrar pestaña", titleEnglish: "Close Tab", detail: "Cierra la pestaña activa (o la ventana si solo hay una)", detailEnglish: "Close active tab (or window if single)", group: .windows,
              defaultChord: .init(keyCode: 13, character: "w", command: true)),
        .init(id: "win.nextTab", title: "Pestaña siguiente", titleEnglish: "Next Tab", detail: "Cicla a la pestaña de la derecha", detailEnglish: "Cycle to tab on the right", group: .windows,
              defaultChord: .init(keyCode: 30, character: "]", command: true, shift: true)),
        .init(id: "win.prevTab", title: "Pestaña anterior", titleEnglish: "Previous Tab", detail: "Cicla a la pestaña de la izquierda", detailEnglish: "Cycle to tab on the left", group: .windows,
              defaultChord: .init(keyCode: 33, character: "[", command: true, shift: true)),
        .init(id: "win.moveTabLeft", title: "Mover pestaña a la izquierda", titleEnglish: "Move Tab Left", detail: "Reordena la pestaña hacia la izquierda", detailEnglish: "Reorder tab to the left", group: .windows,
              defaultChord: .init(keyCode: 123, command: true, option: true)),
        .init(id: "win.moveTabRight", title: "Mover pestaña a la derecha", titleEnglish: "Move Tab Right", detail: "Reordena la pestaña hacia la derecha", detailEnglish: "Reorder tab to the right", group: .windows,
              defaultChord: .init(keyCode: 124, command: true, option: true)),

        // Archivos
        .init(id: "files.undo", title: "Deshacer", titleEnglish: "Undo", detail: "⌘Z: restaura movimiento, copia o Papelera (varios niveles)", detailEnglish: "⌘Z: undo move, copy, or Trash (multi-level)", group: .files,
              defaultChord: .init(keyCode: 6, character: "z", command: true)),
        .init(id: "files.copy", title: "Copiar a bandeja", titleEnglish: "Copy to Tray", detail: "Copia la selección a la bandeja", detailEnglish: "Copy selection to clipboard tray", group: .files,
              defaultChord: .init(keyCode: 8, character: "c", command: true)),
        .init(id: "files.cut", title: "Cortar a bandeja", titleEnglish: "Cut to Tray", detail: "Prepara mover al pegar", detailEnglish: "Prepare move on paste", group: .files,
              defaultChord: .init(keyCode: 7, character: "x", command: true)),
        .init(id: "files.paste", title: "Soltar bandeja", titleEnglish: "Paste from Tray", detail: "Pega/mueve en la carpeta actual", detailEnglish: "Paste/move into current folder", group: .files,
              defaultChord: .init(keyCode: 9, character: "v", command: true)),
        .init(id: "files.duplicate", title: "Duplicar", titleEnglish: "Duplicate", detail: "Copia al lado con otro nombre", detailEnglish: "Copy alongside with new name", group: .files,
              defaultChord: .init(keyCode: 2, character: "d", command: true)),
        .init(id: "files.copyPath", title: "Copiar ruta", titleEnglish: "Copy Path", detail: "Ruta completa al portapapeles", detailEnglish: "Copy full path to clipboard", group: .files,
              defaultChord: .init(keyCode: 8, character: "c", command: true, option: true)),
        .init(id: "files.newFile", title: "Nuevo archivo", titleEnglish: "New File", detail: "Crea un archivo vacío", detailEnglish: "Create an empty file", group: .files,
              defaultChord: .init(keyCode: 45, character: "n", command: true)),
        .init(id: "files.newFolder", title: "Nueva carpeta", titleEnglish: "New Folder", detail: "Crea una carpeta", detailEnglish: "Create a new folder", group: .files,
              defaultChord: .init(keyCode: 45, character: "n", command: true, shift: true)),
        .init(id: "files.terminal", title: "Abrir Terminal aquí", titleEnglish: "Open Terminal Here", detail: "Terminal.app en la carpeta del panel activo", detailEnglish: "Launch Terminal at active folder", group: .files,
              defaultChord: .init(keyCode: 17, character: "t", command: true, option: true)),
        .init(id: "files.open", title: "Abrir selección", titleEnglish: "Open Selection", detail: "Abre el ítem seleccionado", detailEnglish: "Open selected item", group: .files,
              defaultChord: .init(keyCode: 125, command: true)),
        .init(id: "files.quickLook", title: "Vista rápida", titleEnglish: "Quick Look", detail: "Quick Look del archivo", detailEnglish: "Preview file with Quick Look", group: .files,
              defaultChord: .init(keyCode: 49)),
        .init(id: "files.trash", title: "Mover a la Papelera", titleEnglish: "Move to Trash", detail: "⌫ envía la selección a la Papelera (como Windows)", detailEnglish: "⌫ sends selection to Trash (Windows-style)", group: .files,
              defaultChord: .init(keyCode: 51)),
        .init(id: "files.restore", title: "Sacar de la Papelera", titleEnglish: "Restore from Trash", detail: "Restaura la selección fuera del basurero", detailEnglish: "Restore selection out of Trash", group: .files,
              defaultChord: .init(keyCode: 51, command: true, option: true)),
        .init(id: "files.renameF2", title: "Renombrar (F2)", titleEnglish: "Rename (F2)", detail: "Renombra el ítem seleccionado", detailEnglish: "Rename selected item", group: .files,
              defaultChord: .init(keyCode: 120)),
        .init(id: "files.return", title: "Return", titleEnglish: "Return", detail: "Explorer: abrir · Finder: renombrar", detailEnglish: "Explorer: open · Finder: rename", group: .files,
              defaultChord: .init(keyCode: 36)),
        .init(id: "files.selectAll", title: "Seleccionar todos", titleEnglish: "Select All", detail: "Marca todos los visibles", detailEnglish: "Select all visible items", group: .files,
              defaultChord: .init(keyCode: 0, character: "a", command: true)),
        .init(id: "files.cancel", title: "Quitar selección / bandeja", titleEnglish: "Clear Selection / Tray", detail: "Esc: selección · Esc Esc: vaciar bandeja", detailEnglish: "Esc: selection · Esc Esc: clear tray", group: .files,
              defaultChord: .init(keyCode: 53)),
        .init(id: "files.favorite", title: "Añadir a Favoritos", titleEnglish: "Add to Favorites", detail: "Favorito la carpeta actual", detailEnglish: "Bookmark current folder", group: .files,
              defaultChord: .init(keyCode: 17, character: "t", command: true, shift: true)),

        // Dual pane
        .init(id: "dual.toggle", title: "Dos paneles", titleEnglish: "Dual Pane", detail: "Activa/desactiva Origen · Destino", detailEnglish: "Toggle Source · Destination panes", group: .dualPane,
              defaultChord: .init(keyCode: 2, character: "d", command: true, shift: true)),
        .init(id: "dual.focusOrigin", title: "Panel Origen", titleEnglish: "Source Pane", detail: "Enfoca el panel izquierdo", detailEnglish: "Focus left pane", group: .dualPane,
              defaultChord: .init(keyCode: 123, command: true, shift: true)),
        .init(id: "dual.focusDest", title: "Panel Destino", titleEnglish: "Destination Pane", detail: "Enfoca el panel derecho", detailEnglish: "Focus right pane", group: .dualPane,
              defaultChord: .init(keyCode: 124, command: true, shift: true)),
        .init(id: "dual.swapFocus", title: "Cambiar de panel", titleEnglish: "Switch Pane", detail: "Tab entre Origen y Destino", detailEnglish: "Tab between Source and Destination", group: .dualPane,
              defaultChord: .init(keyCode: 48)),
        .init(id: "dual.moveToDest", title: "Mover → Destino", titleEnglish: "Move → Destination", detail: "Mueve la selección al Destino", detailEnglish: "Move selection to Destination", group: .dualPane,
              defaultChord: .init(keyCode: 46, character: "m", command: true, shift: true)),
        .init(id: "dual.moveToOrigin", title: "Mover → Origen", titleEnglish: "Move → Source", detail: "Mueve desde Destino al Origen", detailEnglish: "Move from Destination to Source", group: .dualPane,
              defaultChord: .init(keyCode: 46, character: "m", command: true, option: true, shift: true)),
        .init(id: "dual.swapPanes", title: "Intercambiar paneles", titleEnglish: "Swap Panes", detail: "Origen ↔ Destino (carpetas)", detailEnglish: "Swap Source ↔ Destination folders", group: .dualPane,
              defaultChord: .init(keyCode: 1, character: "s", command: true, shift: true)),

        // Buscar / asistente
        .init(id: "search.deep", title: "Buscar en subcarpetas", titleEnglish: "Search in Subfolders", detail: "Búsqueda recursiva ⌘4", detailEnglish: "Recursive search ⌘4", group: .searchAssistant,
              defaultChord: .init(keyCode: 21, character: "4", command: true)),
        .init(id: "assistant.toggle", title: "Mostrar asistente", titleEnglish: "Toggle Assistant", detail: "Abre/cierra el panel ⌘5", detailEnglish: "Open/close assistant panel ⌘5", group: .searchAssistant,
              defaultChord: .init(keyCode: 23, character: "5", command: true)),
        .init(id: "assistant.focus", title: "Ir al asistente", titleEnglish: "Focus Assistant", detail: "Enfoca el panel ⌘6", detailEnglish: "Focus assistant input ⌘6", group: .searchAssistant,
              defaultChord: .init(keyCode: 22, character: "6", command: true)),
        .init(id: "assistant.voice", title: "Hablar (mantener)", titleEnglish: "Talk (Hold)", detail: "⌃Espacio push-to-talk", detailEnglish: "⌃Space push-to-talk", group: .searchAssistant,
              defaultChord: .init(keyCode: 49, control: true)),

        // Vista
        .init(id: "view.hidden", title: "Mostrar ocultos", titleEnglish: "Show Hidden Files", detail: "Alterna archivos ocultos", detailEnglish: "Toggle hidden files visibility", group: .view,
              defaultChord: .init(keyCode: 47, character: ".", command: true, shift: true)),
        .init(id: "view.multi", title: "Modo varios", titleEnglish: "Multi-Select Mode", detail: "Selección múltiple (naranja)", detailEnglish: "Checkbox multiple selection", group: .view,
              defaultChord: .init(keyCode: 9, character: "v", command: true, shift: true)),
        .init(id: "view.flatten", title: "Vista plana", titleEnglish: "Flat View", detail: "Archivos de subcarpetas en una lista", detailEnglish: "List all subfolder files in one view", group: .view,
              defaultChord: .init(keyCode: 3, character: "f", command: true, shift: true)),
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

    /// Comprueba si una combinación ya está asignada a otra acción del catálogo.
    public static func conflictingDefinition(
        for chord: KeyChord,
        excludingId: String,
        overrides: [String: KeyChord]
    ) -> AppHotkeyDefinition? {
        let resolvedMap = resolved(overrides: overrides)
        for def in catalog where def.id != excludingId {
            if let existingChord = resolvedMap[def.id] {
                if existingChord == chord || existingChord.conflicts(with: chord) {
                    return def
                }
            }
        }
        return nil
    }
}
