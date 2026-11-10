import AppKit
import OrdenCore

@MainActor
public enum AppMenuLocalizer {
    public static func applyLocalization() {
        guard let mainMenu = NSApp.mainMenu else { return }
        let isEN = L10n.isEnglish
        localizeMenu(mainMenu, isEnglish: isEN)
        mainMenu.update()
    }

    private static func localizeMenu(_ menu: NSMenu, isEnglish: Bool) {
        if let menuTarget = translation(for: menu.title, isEnglish: isEnglish) {
            menu.title = menuTarget
        }
        for item in menu.items {
            let current = item.title
            if let target = translation(for: current, isEnglish: isEnglish) {
                item.title = target
                item.attributedTitle = nil
                item.submenu?.title = target
            }
            if let submenu = item.submenu {
                if let subTarget = translation(for: submenu.title, isEnglish: isEnglish) {
                    submenu.title = subTarget
                }
                localizeMenu(submenu, isEnglish: isEnglish)
            }
        }
        menu.update()
    }

    private static func translation(for current: String, isEnglish: Bool) -> String? {
        let trimmed = current.trimmingCharacters(in: .whitespaces)
        if isEnglish {
            switch trimmed {
            // Menú principal
            case "Archivo": return "File"
            case "Edición": return "Edit"
            case "Visualización": return "View"
            case "Buscar": return "Search"
            case "Asistente": return "Assistant"
            case "Ir": return "Go"
            case "Archivo+": return "File+"
            case "Ventana": return "Window"
            case "Ayuda": return "Help"

            // Menú de la App (Findaro)
            case "Ajustes…", "Ajustes...", "Preferencias…", "Preferencias...": return "Settings…"
            case "Servicios": return "Services"
            case "Ocultar Findaro": return "Hide Findaro"
            case "Ocultar otras apps", "Ocultar otros": return "Hide Others"
            case "Mostrar todo": return "Show All"
            case "Salir y mantener ventanas", "Salir de Findaro", "Salir": return "Quit Findaro"
            case "Acerca de Findaro": return "About Findaro"
            case "Buscar actualizaciones…": return "Check for Updates…"
            case "Idioma / Language": return "Language / Idioma"
            case "Automático (Sistema)": return "Automatic (System)"

            // Ventana / Pestañas
            case "Cerrar ventana": return "Close Window"
            case "Cerrar pestaña": return "Close Tab"
            case "Nueva ventana": return "New Window"
            case "Nueva pestaña": return "New Tab"
            case "Pestaña anterior": return "Previous Tab"
            case "Pestaña siguiente": return "Next Tab"
            case "Mover pestaña a la izquierda": return "Move Tab Left"
            case "Mover pestaña a la derecha": return "Move Tab Right"

            // Acciones de Archivos
            case "Nuevo archivo": return "New File"
            case "Nueva carpeta": return "New Folder"
            case "Abrir selección": return "Open Selection"
            case "Abrir Terminal aquí": return "Open Terminal Here"
            case "Vista rápida": return "Quick Look"
            case "Renombrar": return "Rename"
            case "Duplicar": return "Duplicate"
            case "Comprimir": return "Compress"
            case "Descomprimir": return "Extract"
            case "Sacar de la Papelera": return "Restore from Trash"
            case "Eliminar para siempre": return "Delete Permanently"
            case "Mover a la Papelera": return "Move to Trash"
            case "Añadir a Favoritos": return "Add to Favorites"
            case "Quitar de Favoritos": return "Remove from Favorites"
            case "Añadir carpeta actual a Favoritos": return "Add Current Folder to Favorites"
            case "Elegir carpeta para Favoritos…": return "Choose Folder for Favorites…"

            // Edición
            case "Deshacer movimiento", "Deshacer": return "Undo"
            case "Rehacer": return "Redo"
            case "Cortar a bandeja", "Cortar": return "Cut"
            case "Copiar a bandeja", "Copiar": return "Copy"
            case "Soltar bandeja aquí", "Pegar": return "Paste"
            case "Copiar ruta": return "Copy Path"
            case "Seleccionar todos", "Seleccionar todo": return "Select All"
            case "Quitar selección", "Quitar selección / bandeja": return "Deselect / Clear Tray"
            case "Modo varios": return "Multi-Select Mode"
            case "Desinstalar Findaro…", "Desinstalar Findaro...": return "Uninstall Findaro…"
            case "Restaurar Finder como explorador": return "Restore Finder as File Viewer"
            case "Abrir Descargas (⌃⌥A)": return "Open Downloads (⌃⌥A)"
            case "Ortografía y gramática": return "Spelling and Grammar"
            case "Sustituciones": return "Substitutions"
            case "Transformaciones": return "Transformations"
            case "Voz": return "Speech"
            case "Iniciar dictado…", "Iniciar dictado": return "Start Dictation…"
            case "Emojis y símbolos": return "Emoji & Symbols"

            // Buscar / Paneles
            case "Buscar en subcarpetas…": return "Search in Subfolders…"
            case "Orden normal / salir filtros (Esc)": return "Normal View / Clear Filters (Esc)"
            case "Un panel": return "Single Pane"
            case "Dos paneles": return "Dual Pane"
            case "Panel Origen": return "Origin Pane"
            case "Panel Destino": return "Destination Pane"
            case "Cambiar de panel (Tab)": return "Toggle Focused Pane (Tab)"
            case "Mover selección → Destino": return "Move Selection → Destination"
            case "Mover selección → Origen": return "Move Selection → Origin"
            case "Intercambiar paneles": return "Swap Panes"

            // Asistente
            case "Mostrar asistente": return "Show Assistant"
            case "Ocultar asistente": return "Hide Assistant"
            case "Configurar Ollama…": return "Configure Ollama…"
            case "Ir al asistente": return "Focus Assistant"
            case "Hablar (mantener ⌃Espacio)": return "Talk (Hold ⌃Space)"

            // Ir
            case "Atrás": return "Back"
            case "Adelante": return "Forward"
            case "Atrás (⌥←)": return "Back (⌥←)"
            case "Adelante (⌥→)": return "Forward (⌥→)"
            case "Arriba": return "Enclosing Folder"
            case "Ir a carpeta…": return "Go to Folder…"
            case "Editar ruta (omnibox)": return "Edit Path (Omnibox)"
            case "Descargas": return "Downloads"
            case "Ocultar archivos ocultos": return "Hide Hidden Files"
            case "Mostrar archivos ocultos": return "Show Hidden Files"
            case "Vista de carpeta": return "Folder View"
            case "Vista plana": return "Flat View"
            case "Escritorio": return "Desktop"
            case "Documentos": return "Documents"

            // Barra de herramientas y Ventana
            case "Mostrar barra de herramientas": return "Show Toolbar"
            case "Ocultar barra de herramientas": return "Hide Toolbar"
            case "Personalizar barra de herramientas…": return "Customize Toolbar…"
            case "Entrar en pantalla completa": return "Enter Full Screen"
            case "Salir de pantalla completa": return "Exit Full Screen"
            case "Minimizar": return "Minimize"
            case "Zoom": return "Zoom"
            case "Traer todo al frente": return "Bring All to Front"
            case "Ayuda de Findaro": return "Findaro Help"
            default: return nil
            }
        } else {
            switch trimmed {
            // Menú principal
            case "File": return "Archivo"
            case "Edit": return "Edición"
            case "View": return "Visualización"
            case "Search": return "Buscar"
            case "Assistant": return "Asistente"
            case "Go": return "Ir"
            case "File+": return "Archivo+"
            case "Window": return "Ventana"
            case "Help": return "Ayuda"

            // Menú de la App
            case "Settings…", "Settings...", "Preferences…", "Preferences...": return "Ajustes…"
            case "Services": return "Servicios"
            case "Hide Findaro": return "Ocultar Findaro"
            case "Hide Others": return "Ocultar otras apps"
            case "Show All": return "Mostrar todo"
            case "Quit Findaro", "Quit": return "Salir de Findaro"
            case "About Findaro": return "Acerca de Findaro"
            case "Check for Updates…": return "Buscar actualizaciones…"
            case "Language / Idioma": return "Idioma / Language"
            case "Automatic (System)": return "Automático (Sistema)"

            // Ventana / Pestañas
            case "Close Window": return "Cerrar ventana"
            case "Close Tab": return "Cerrar pestaña"
            case "New Window": return "Nueva ventana"
            case "New Tab": return "Nueva pestaña"
            case "Previous Tab": return "Pestaña anterior"
            case "Next Tab": return "Pestaña siguiente"
            case "Move Tab Left": return "Mover pestaña a la izquierda"
            case "Move Tab Right": return "Mover pestaña a la derecha"

            // Acciones de Archivos
            case "New File": return "Nuevo archivo"
            case "New Folder": return "Nueva carpeta"
            case "Open Selection": return "Abrir selección"
            case "Open Terminal Here": return "Abrir Terminal aquí"
            case "Quick Look": return "Vista rápida"
            case "Rename": return "Renombrar"
            case "Duplicate": return "Duplicar"
            case "Compress": return "Comprimir"
            case "Extract": return "Descomprimir"
            case "Restore from Trash": return "Sacar de la Papelera"
            case "Delete Permanently": return "Eliminar para siempre"
            case "Move to Trash": return "Mover a la Papelera"
            case "Add to Favorites": return "Añadir a Favoritos"
            case "Remove from Favorites": return "Quitar de Favoritos"
            case "Add Current Folder to Favorites": return "Añadir carpeta actual a Favoritos"
            case "Choose Folder for Favorites…": return "Elegir carpeta para Favoritos…"

            // Edición
            case "Undo": return "Deshacer"
            case "Redo": return "Rehacer"
            case "Cut": return "Cortar"
            case "Copy": return "Copiar"
            case "Paste": return "Pegar"
            case "Copy Path": return "Copiar ruta"
            case "Select All": return "Seleccionar todo"
            case "Deselect All", "Deselect / Clear Tray": return "Quitar selección / bandeja"
            case "Multi-Select Mode": return "Modo varios"
            case "Uninstall Findaro…", "Uninstall Findaro...": return "Desinstalar Findaro…"
            case "Restore Finder as File Viewer": return "Restaurar Finder como explorador"
            case "Open Downloads (⌃⌥A)": return "Abrir Descargas (⌃⌥A)"
            case "Spelling and Grammar": return "Ortografía y gramática"
            case "Substitutions": return "Sustituciones"
            case "Transformations": return "Transformaciones"
            case "Speech": return "Voz"
            case "Start Dictation…": return "Iniciar dictado…"
            case "Emoji & Symbols": return "Emojis y símbolos"

            // Buscar / Paneles
            case "Search in Subfolders…": return "Buscar en subcarpetas…"
            case "Normal View / Clear Filters (Esc)": return "Orden normal / salir filtros (Esc)"
            case "Single Pane": return "Un panel"
            case "Dual Pane": return "Dos paneles"
            case "Origin Pane": return "Panel Origen"
            case "Destination Pane": return "Panel Destino"
            case "Toggle Focused Pane (Tab)": return "Cambiar de panel (Tab)"
            case "Move Selection → Destination": return "Mover selección → Destino"
            case "Move Selection → Origin": return "Mover selección → Origen"
            case "Swap Panes": return "Intercambiar paneles"

            // Asistente
            case "Show Assistant": return "Mostrar asistente"
            case "Hide Assistant": return "Ocultar asistente"
            case "Configure Ollama…": return "Configurar Ollama…"
            case "Focus Assistant": return "Ir al asistente"
            case "Talk (Hold ⌃Space)": return "Hablar (mantener ⌃Espacio)"

            // Ir
            case "Back": return "Atrás"
            case "Forward": return "Adelante"
            case "Back (⌥←)": return "Atrás (⌥←)"
            case "Forward (⌥→)": return "Adelante (⌥→)"
            case "Enclosing Folder": return "Arriba"
            case "Go to Folder…": return "Ir a carpeta…"
            case "Edit Path (Omnibox)": return "Editar ruta (omnibox)"
            case "Downloads": return "Descargas"
            case "Hide Hidden Files": return "Ocultar archivos ocultos"
            case "Show Hidden Files": return "Mostrar archivos ocultos"
            case "Folder View": return "Vista de carpeta"
            case "Flat View": return "Vista plana"
            case "Desktop": return "Escritorio"
            case "Documents": return "Documentos"

            // Barra de herramientas y Ventana
            case "Show Toolbar": return "Mostrar barra de herramientas"
            case "Hide Toolbar": return "Ocultar barra de herramientas"
            case "Customize Toolbar…": return "Personalizar barra de herramientas…"
            case "Enter Full Screen": return "Entrar en pantalla completa"
            case "Exit Full Screen": return "Salir de pantalla completa"
            case "Minimize": return "Minimizar"
            case "Zoom": return "Zoom"
            case "Bring All to Front": return "Traer todo al frente"
            case "Findaro Help": return "Ayuda de Findaro"
            default: return nil
            }
        }
    }
}
