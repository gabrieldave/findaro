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
        window.title = "Ayuda de Findaro"
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
                    Label(topic.rawValue, systemImage: topic.icon)
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
            helpSectionHeader(title: "Navegación de Doble Panel", icon: "rectangle.split.2x1")
            Text("Findaro divide la pantalla en panel de Origen y panel de Destino para transferencias inmediatas y sin pérdida de contexto.")
            helpCard {
                bullet("Mover al Destino (⌘⇧M): Transfiere la selección del panel activo al secundario.")
                bullet("Copiar al Destino (⌘⌥C): Duplica la selección hacia la carpeta del panel secundario.")
                bullet("Arrastrar y Soltar: Arrastra cualquier archivo directamente de un panel al otro sin esperas.")
                bullet("Bandeja de Corte y Pega: Agrega archivos con ⌘C / ⌘X y pégalos en cualquier destino con ⌘V.")
            }

        case .selection:
            helpSectionHeader(title: "Selección Avanzada macOS", icon: "selection.pin.in.out")
            Text("Control total de selección combinando ratón y teclado con la ergonomía estándar de macOS.")
            helpCard {
                bullet("Clic simple: Selecciona el elemento y despeja el resto.")
                bullet("⌘ + Clic: Alterna la selección de un elemento individual sin deseleccionar los demás.")
                bullet("⇧ + Clic / ⇧ + Flechas: Extiende la selección en bloque contiguo desde el ancla.")
                bullet("Arrastre de Marquesina: Haz clic y arrastra sobre el fondo vacío para envolver múltiples archivos.")
                bullet("Deshacer selección: Pulsa la tecla Escape (⎋) para deseleccionar todo.")
            }

        case .tabs:
            helpSectionHeader(title: "Gestión y Reordenamiento de Pestañas", icon: "square.stack")
            Text("Cada pestaña mantiene su propio historial de navegación, filtros y estado independiente.")
            helpCard {
                bullet("Nueva Pestaña (⌘T): Abre una pestaña heredando la ruta actual.")
                bullet("Cerrar Pestaña (⌘W): Cierra la pestaña activa.")
                bullet("Navegar entre Pestañas: ⌘⇧[ para la anterior y ⌘⇧] para la siguiente.")
                bullet("Reordenar: Arrastra cualquier pestaña horizontalmente a una nueva posición, o pulsa ⌘⌥← / ⌘⌥→.")
                bullet("Menú contextual: Clic derecho en una pestaña para reordenarla o cerrarla.")
            }

        case .search:
            helpSectionHeader(title: "Búsqueda y Filtros", icon: "magnifyingglass")
            Text("Localiza archivos rápidamente sin indexaciones lentas.")
            helpCard {
                bullet("Filtro local (⌘F): Filtra al vuelo los archivos visibles en la carpeta actual.")
                bullet("Búsqueda en Subcarpetas: Pulsa «Subcarpetas» para buscar recursivamente en todos los niveles inferiores.")
                bullet("Fijar orden global: Aplica el criterio de ordenación actual como regla predeterminada en todas las carpetas.")
                bullet("Atajos de fecha y tipo: Filtra instantáneamente por imágenes de hoy, documentos recientes o más pesados.")
            }

        case .hotkeys:
            helpSectionHeader(title: "Atajos de Teclado", icon: "command")
            Text("Todos los atajos principales pueden personalizarse desde Ajustes con protección contra colisiones.")
            helpCard {
                bullet("⌘1 / ⌘2 / ⌘3: Navegación de historial y accesos directos.")
                bullet("⌘⇧M / ⌘⌥C: Acciones directas entre paneles duales.")
                bullet("⌃⌥O: Atajo global de sistema para abrir rápidamente Descargas o tu carpeta preferida.")
                bullet("Detección de conflictos: Al editar atajos en Ajustes, el sistema te advertirá si una combinación ya está en uso.")
            }

        case .assistant:
            helpSectionHeader(title: "Asistente IA y Ollama", icon: "sparkles")
            Text("Asistente inteligente local para consulta de archivos, espacio y automatizaciones.")
            helpCard {
                bullet("Atajos de un clic: Filtros predefinidos como «imágenes de hoy» o «más pesados».")
                bullet("Consultas de espacio: Pregunta qué carpetas ocupan más espacio en tu disco.")
                bullet("Soporte Ollama local: Conecta tu modelo Ollama local (ej. qwen3.5) para lenguaje natural.")
                bullet("Privacidad absoluta: Tus consultas y datos no salen nunca de tu ordenador.")
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
