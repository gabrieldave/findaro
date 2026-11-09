import AppKit
import OrdenCore

@MainActor
public enum AppMenuLocalizer {
    public static func applyLocalization() {
        guard let mainMenu = NSApp.mainMenu else { return }
        let isEN = L10n.isEnglish
        localizeMenu(mainMenu, isEnglish: isEN)
    }

    private static func localizeMenu(_ menu: NSMenu, isEnglish: Bool) {
        for item in menu.items {
            let current = item.title
            if let target = translation(for: current, isEnglish: isEnglish) {
                item.title = target
            }
            if let submenu = item.submenu {
                localizeMenu(submenu, isEnglish: isEnglish)
            }
        }
    }

    private static func translation(for current: String, isEnglish: Bool) -> String? {
        let trimmed = current.trimmingCharacters(in: .whitespaces)
        if isEnglish {
            switch trimmed {
            case "Archivo": return "File"
            case "Edición": return "Edit"
            case "Visualización": return "View"
            case "Buscar": return "Search"
            case "Asistente": return "Assistant"
            case "Ir": return "Go"
            case "Archivo+": return "File+"
            case "Ventana": return "Window"
            case "Ayuda": return "Help"
            case "Ajustes…", "Ajustes...", "Preferencias…", "Preferencias...": return "Settings…"
            case "Servicios": return "Services"
            case "Ocultar Findaro": return "Hide Findaro"
            case "Ocultar otras apps", "Ocultar otros": return "Hide Others"
            case "Mostrar todo": return "Show All"
            case "Salir y mantener ventanas", "Salir de Findaro", "Salir": return "Quit Findaro"
            case "Acerca de Findaro": return "About Findaro"
            case "Buscar actualizaciones…": return "Check for Updates…"
            case "Cerrar ventana": return "Close Window"
            case "Cerrar pestaña": return "Close Tab"
            case "Nueva ventana": return "New Window"
            case "Nueva pestaña": return "New Tab"
            case "Pestaña anterior": return "Previous Tab"
            case "Pestaña siguiente": return "Next Tab"
            case "Mover pestaña a la izquierda": return "Move Tab Left"
            case "Mover pestaña a la derecha": return "Move Tab Right"
            case "Nuevo archivo": return "New File"
            case "Nueva carpeta": return "New Folder"
            case "Deshacer movimiento", "Deshacer": return "Undo"
            case "Rehacer": return "Redo"
            case "Cortar a bandeja", "Cortar": return "Cut"
            case "Copiar a bandeja", "Copiar": return "Copy"
            case "Soltar bandeja aquí", "Pegar": return "Paste"
            case "Duplicar": return "Duplicate"
            case "Copiar ruta": return "Copy Path"
            case "Seleccionar todos", "Seleccionar todo": return "Select All"
            case "Quitar selección": return "Deselect All"
            case "Ortografía y gramática": return "Spelling and Grammar"
            case "Sustituciones": return "Substitutions"
            case "Transformaciones": return "Transformations"
            case "Voz": return "Speech"
            case "Iniciar dictado…", "Iniciar dictado": return "Start Dictation…"
            case "Emojis y símbolos": return "Emoji & Symbols"
            case "Mostrar barra de herramientas": return "Show Toolbar"
            case "Ocultar barra de herramientas": return "Hide Toolbar"
            case "Personalizar barra de herramientas…": return "Customize Toolbar…"
            case "Entrar en pantalla completa": return "Enter Full Screen"
            case "Salir de pantalla completa": return "Exit Full Screen"
            case "Minimizar": return "Minimize"
            case "Zoom": return "Zoom"
            case "Traer todo al frente": return "Bring All to Front"
            case "Ayuda de Findaro": return "Findaro Help"
            case "Idioma / Language": return "Language / Idioma"
            case "Automático (Sistema)": return "Automatic (System)"
            default: return nil
            }
        } else {
            switch trimmed {
            case "File": return "Archivo"
            case "Edit": return "Edición"
            case "View": return "Visualización"
            case "Search": return "Buscar"
            case "Assistant": return "Asistente"
            case "Go": return "Ir"
            case "File+": return "Archivo+"
            case "Window": return "Ventana"
            case "Help": return "Ayuda"
            case "Settings…", "Settings...", "Preferences…", "Preferences...": return "Ajustes…"
            case "Services": return "Servicios"
            case "Hide Findaro": return "Ocultar Findaro"
            case "Hide Others": return "Ocultar otras apps"
            case "Show All": return "Mostrar todo"
            case "Quit Findaro", "Quit": return "Salir de Findaro"
            case "About Findaro": return "Acerca de Findaro"
            case "Check for Updates…": return "Buscar actualizaciones…"
            case "Close Window": return "Cerrar ventana"
            case "Close Tab": return "Cerrar pestaña"
            case "New Window": return "Nueva ventana"
            case "New Tab": return "Nueva pestaña"
            case "Previous Tab": return "Pestaña anterior"
            case "Next Tab": return "Pestaña siguiente"
            case "Move Tab Left": return "Mover pestaña a la izquierda"
            case "Move Tab Right": return "Mover pestaña a la derecha"
            case "New File": return "Nuevo archivo"
            case "New Folder": return "Nueva carpeta"
            case "Undo": return "Deshacer"
            case "Redo": return "Rehacer"
            case "Cut": return "Cortar"
            case "Copy": return "Copiar"
            case "Paste": return "Pegar"
            case "Duplicate": return "Duplicar"
            case "Copy Path": return "Copiar ruta"
            case "Select All": return "Seleccionar todo"
            case "Deselect All": return "Quitar selección"
            case "Spelling and Grammar": return "Ortografía y gramática"
            case "Substitutions": return "Sustituciones"
            case "Transformaciones": return "Transformaciones"
            case "Speech": return "Voz"
            case "Start Dictation…": return "Iniciar dictado…"
            case "Emoji & Symbols": return "Emojis y símbolos"
            case "Show Toolbar": return "Mostrar barra de herramientas"
            case "Hide Toolbar": return "Ocultar barra de herramientas"
            case "Customize Toolbar…": return "Personalizar barra de herramientas…"
            case "Enter Full Screen": return "Entrar en pantalla completa"
            case "Exit Full Screen": return "Salir de pantalla completa"
            case "Minimize": return "Minimizar"
            case "Zoom": return "Zoom"
            case "Bring All to Front": return "Traer todo al frente"
            case "Findaro Help": return "Ayuda de Findaro"
            case "Language / Idioma": return "Idioma / Language"
            case "Automatic (System)": return "Automático (Sistema)"
            default: return nil
            }
        }
    }
}
