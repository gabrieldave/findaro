import SwiftUI
import AppKit
import OrdenCore

/// Ventana nativa de Ayuda y Guía de Findaro.
@MainActor
public enum FindaroHelpWindow {
    private static var helpWindow: NSWindow?

    public static func show() {
        if let existing = helpWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = L10n.s("Ayuda de Findaro", "Findaro Help")
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: FindaroHelpView())
        window.minSize = NSSize(width: 500, height: 400)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        helpWindow = window
    }
}

public struct FindaroHelpView: View {
    @State private var selectedTopic: HelpTopic = .panes

    enum HelpTopic: String, CaseIterable, Identifiable {
        case panes = "Doble Panel"
        case selection = "Selección de Archivos"
        case tabs = "Pestañas"
        case search = "Búsqueda y Filtros"
        case hotkeys = "Atajos de Teclado"
        case assistant = "Asistente IA y Ollama"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .panes: return L10n.s("Doble Panel", "Dual Pane")
            case .selection: return L10n.s("Selección de Archivos", "File Selection")
            case .tabs: return L10n.s("Pestañas", "Tabs")
            case .search: return L10n.s("Búsqueda y Filtros", "Search & Filters")
            case .hotkeys: return L10n.s("Atajos de Teclado", "Keyboard Shortcuts")
            case .assistant: return L10n.s("Asistente IA y Ollama", "AI Assistant & Ollama")
            }
        }

        var icon: String {
            switch self {
            case .panes: return "rectangle.split.2x1"
            case .selection: return "selection.pin.in.out"
            case .tabs: return "square.stack"
            case .search: return "magnifyingglass"
            case .hotkeys: return "command"
            case .assistant: return "sparkles"
            }
        }
    }

    public var body: some View {
        NavigationSplitView {
            List(HelpTopic.allCases, selection: $selectedTopic) { topic in
                NavigationLink(value: topic) {
                    Label(topic.displayName, systemImage: topic.icon)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 160, ideal: 190, max: 240)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    detailContent(for: selectedTopic)
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 560, minHeight: 440)
    }

    @ViewBuilder
    private func detailContent(for topic: HelpTopic) -> some View {
        switch topic {
        case .panes:
            helpSectionHeader(title: L10n.s("Navegación de Doble Panel", "Dual Pane Navigation"), icon: "rectangle.split.2x1")
            Text(L10n.s("Findaro divide la pantalla en panel de Origen y panel de Destino para transferencias inmediatas y sin pérdida de contexto.", "Findaro splits the view into Origin and Destination panes for immediate transfers without losing context."))
            helpCard {
                bullet(L10n.s("Mover al Destino (⌘⇧M): Transfiere la selección del panel activo al secundario.", "Move to Destination (⌘⇧M): Transfers active selection to destination pane."))
                bullet(L10n.s("Copiar al Destino (⌘⌥C): Duplica la selección hacia la carpeta del panel secundario.", "Copy to Destination (⌘⌥C): Duplicates selection into destination folder."))
                bullet(L10n.s("Arrastrar y Soltar: Arrastra cualquier archivo directamente de un panel al otro sin esperas.", "Drag & Drop: Drag files directly from one pane to the other."))
                bullet(L10n.s("Bandeja de Corte y Pega: Agrega archivos con ⌘C / ⌘X y pégalos en cualquier destino con ⌘V. Dos Esc seguidos vacían la bandeja.", "Clipboard Tray: Cut/copy with ⌘C / ⌘X and paste with ⌘V. Double Esc clears the tray."))
            }

        case .selection:
            helpSectionHeader(title: L10n.s("Selección Avanzada macOS", "Advanced macOS Selection"), icon: "selection.pin.in.out")
            Text(L10n.s("Control total de selección combinando ratón y teclado con la ergonomía estándar de macOS.", "Full selection control combining mouse and keyboard with macOS ergonomics."))
            helpCard {
                bullet(L10n.s("Clic simple: Selecciona el elemento y despeja el resto.", "Click: Selects single item and clears rest."))
                bullet(L10n.s("⌘ + Clic: Alterna la selección de un elemento individual sin deseleccionar los demás.", "⌘ + Click: Toggles individual item selection without clearing."))
                bullet(L10n.s("⇧ + Clic / ⇧ + Flechas: Extiende la selección en bloque contiguo desde el ancla.", "⇧ + Click / ⇧ + Arrows: Extends contiguous selection block."))
                bullet(L10n.s("Arrastre de Marquesina: Haz clic y arrastra sobre el fondo vacío para envolver múltiples archivos.", "Marquee Drag: Click and drag on empty background to select multiple items."))
                bullet(L10n.s("Deshacer selección: Escape (⎋) quita la selección. Dos Esc seguidos vacían la bandeja.", "Clear selection: Escape (⎋) deselects. Double Esc clears the tray."))
                bullet(L10n.s("Borrar: ⌫ manda la selección a la Papelera (estilo Windows). ⌘Z la restaura; puedes deshacer varios pasos.", "Delete: ⌫ moves selection to Trash (Windows-style). ⌘Z restores; multi-level undo."))
                bullet(L10n.s("Renombrar: ⌃R (mano izquierda) o F2. Solo editas el nombre; la extensión se conserva. ⌘R actualiza la carpeta.", "Rename: ⌃R (left hand) or F2. Edit the name only; extension is kept. ⌘R refreshes the folder."))
            }

        case .tabs:
            helpSectionHeader(title: L10n.s("Gestión y Reordenamiento de Pestañas", "Tab Management and Reordering"), icon: "square.stack")
            Text(L10n.s("Cada pestaña mantiene su propio historial de navegación, filtros y estado independiente.", "Each tab maintains its independent history, filters, and state."))
            helpCard {
                bullet(L10n.s("Nueva Pestaña (⌘T): Abre una pestaña heredando la ruta actual.", "New Tab (⌘T): Opens a new tab inheriting current path."))
                bullet(L10n.s("Cerrar Pestaña (⌘W): Cierra la pestaña activa.", "Close Tab (⌘W): Closes active tab."))
                bullet(L10n.s("Navegar entre Pestañas: ⌘⇧[ para la anterior y ⌘⇧] para la siguiente.", "Switch Tabs: ⌘⇧[ for previous, ⌘⇧] for next."))
                bullet(L10n.s("Reordenar: Arrastra cualquier pestaña horizontalmente a una nueva posición, o pulsa ⌘⌥← / ⌘⌥→.", "Reorder: Drag any tab horizontally or press ⌘⌥← / ⌘⌥→."))
                bullet(L10n.s("Menú contextual: Clic derecho en una pestaña para reordenarla o cerrarla.", "Context menu: Right-click tab to reorder or close."))
            }

        case .search:
            helpSectionHeader(title: L10n.s("Búsqueda y Filtros", "Search and Filters"), icon: "magnifyingglass")
            Text(L10n.s("Localiza archivos rápidamente sin indexaciones lentas.", "Find files quickly without slow indexing."))
            helpCard {
                bullet(L10n.s("Filtro local (⌘F): Filtra al vuelo los archivos visibles en la carpeta actual.", "Live Filter (⌘F): Instant filter on files in current folder."))
                bullet(L10n.s("Búsqueda en Subcarpetas: Pulsa «Subcarpetas» para buscar recursivamente en todos los niveles inferiores.", "Search in Subfolders: Press «Subfolders» to recursively search subdirectories."))
                bullet(L10n.s("Fijar orden global: Aplica el criterio de ordenación actual como regla predeterminada en todas las carpetas.", "Set Global Sort: Applies current sort order across all folders."))
                bullet(L10n.s("Atajos de fecha y tipo: Filtra instantáneamente por imágenes de hoy, documentos recientes o más pesados.", "Shortcuts by type/date: Filter instantly for today's images, recent docs, or largest files."))
            }
            helpSectionHeader(title: L10n.s("Carpetas inteligentes", "Smart Folders"), icon: "folder.badge.gearshape")
            Text(L10n.s("Búsquedas guardadas en Favoritos. Un clic y ves solo esos archivos; no se mueve ni se copia nada.", "Searches saved in Favorites. One click shows only those files; nothing is moved or copied."))
            helpCard {
                bullet(L10n.s("Crear: en Favoritos pulsa «Nueva carpeta inteligente…» y elige tipo (Imágenes, PDF, ZIP…), cualquier extensión, texto del nombre y fecha (hoy, ayer, 7 o 30 días).", "Create: in Favorites click «New Smart Folder…» and pick type (Images, PDF, ZIP…), any extension, name text and date (today, yesterday, 7 or 30 days)."))
                bullet(L10n.s("Desde una búsqueda: con un filtro, Tipo o «Descargados» activo, pulsa «Guardar en Favoritos».", "From a search: with a filter, Type or «Downloads» active, click «Save to Favorites»."))
                bullet(L10n.s("Subcarpetas: actívalo para buscar también dentro de todas las carpetas de adentro.", "Subfolders: turn it on to also look inside every folder within."))
                bullet(L10n.s("Editar o quitar: clic derecho sobre la carpeta inteligente. Quitarla no borra ningún archivo.", "Edit or remove: right-click the smart folder. Removing it never deletes files."))
            }

        case .hotkeys:
            helpSectionHeader(title: L10n.s("Atajos de Teclado", "Keyboard Shortcuts"), icon: "command")
            Text(L10n.s("Todos los atajos principales pueden personalizarse desde Ajustes con protección contra colisiones.", "All key shortcuts can be customized in Settings with collision detection."))
            helpCard {
                bullet("⌘1 / ⌘2 / ⌘3: " + L10n.s("Navegación de historial y accesos directos.", "History navigation and quick access."))
                bullet("⌘⇧M / ⌘⌥C: " + L10n.s("Acciones directas entre paneles duales.", "Direct actions between dual panes."))
                bullet("⌃⌥A: " + L10n.s("Atajo global de sistema para abrir rápidamente Descargas o tu carpeta preferida.", "Global hotkey to quickly open Downloads or your chosen folder."))
                bullet(L10n.s("Detección de conflictos: Al editar atajos en Ajustes, el sistema te advertirá si una combinación ya está en uso.", "Conflict detection: When customizing hotkeys, Findaro warns if chord is in use."))
            }

        case .assistant:
            helpSectionHeader(title: L10n.s("Asistente IA y Ollama", "AI Assistant & Ollama"), icon: "sparkles")
            Text(L10n.s("Asistente inteligente local para consulta de archivos, espacio y automatizaciones.", "Local smart assistant for file queries, disk space, and actions."))
            helpCard {
                bullet(L10n.s("Atajos de un clic: Filtros predefinidos como «imágenes de hoy» o «más pesados».", "One-click shortcuts: Predefined filters like «today's images» or «largest files»."))
                bullet(L10n.s("Consultas de espacio: Pregunta qué carpetas ocupan más espacio en tu disco.", "Disk space queries: Ask what takes the most space in your active directory."))
                bullet(L10n.s("Soporte Ollama local: Conecta tu modelo Ollama local (ej. qwen3.5) para lenguaje natural.", "Local Ollama support: Connect local model (e.g. qwen3.5) for natural language."))
                bullet(L10n.s("Privacidad absoluta: Tus consultas y datos no salen nunca de tu ordenador.", "Absolute privacy: Your queries and files never leave your computer."))
            }
        }
    }

    private func helpSectionHeader(title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(OrdenTheme.accent)
            Text(title)
                .font(.title2.weight(.bold))
        }
    }

    private func helpCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OrdenTheme.panelFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•")
                .foregroundStyle(OrdenTheme.accent)
            Text(text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
