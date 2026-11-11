import AppKit

/// Quita del menú Edición los ítems de sistema que no aplican a un file manager
/// (Writing Tools / Autorrelleno / Dictado / Emoji) y que al abrir submenús
/// sobre la ventana provocan parpadeo del material traslúcido.
@MainActor
enum EditMenuCleaner {
    private static let bannedExact: Set<String> = [
        "Herramientas de escritura",
        "Writing Tools",
        "Autorrelleno",
        "AutoFill",
        "Autofill",
        "Iniciar dictado…",
        "Iniciar dictado...",
        "Iniciar dictado",
        "Start Dictation…",
        "Start Dictation...",
        "Start Dictation",
        "Emojis y símbolos",
        "Emoji & Symbols",
        "Emojis & Symbols",
        "Substitutions",
        "Sustituciones",
        "Transformations",
        "Transformaciones",
        "Speech",
        "Voz",
        "Spelling and Grammar",
        "Ortografía y gramática",
        "Rehacer",
        "Redo",
        "Cortar",
        "Cut",
        "Copiar",
        "Copy",
        "Pegar",
        "Paste",
        "Eliminar",
        "Delete",
        "Paste and Match Style",
        "Pegar con el mismo estilo",
    ]

    private static let bannedPrefixes = [
        "Herramientas de escritura",
        "Writing Tools",
        "Autorrelleno",
        "AutoFill",
        "Autofill",
        "Iniciar dictado",
        "Start Dictation",
    ]

    static func install() {
        strip(from: NSApp.mainMenu)
        // SwiftUI regenera el menú; reaplicar en cuanto esté listo.
        for delay in [0.05, 0.2, 0.6, 1.5] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                strip(from: NSApp.mainMenu)
            }
        }
        NotificationCenter.default.addObserver(
            forName: NSMenu.didAddItemNotification,
            object: nil,
            queue: .main
        ) { _ in
            // Solo mainMenu: evita races de aislamiento con el object del note.
            DispatchQueue.main.async {
                EditMenuCleaner.strip(from: NSApp.mainMenu)
            }
        }
    }

    static func strip(from root: NSMenu?) {
        guard let root else { return }
        stripMenu(root)
        for item in root.items {
            if let sub = item.submenu {
                let title = item.title
                if title == "Edición" || title == "Edit" {
                    stripMenu(sub)
                    collapseExtraSeparators(sub)
                } else {
                    strip(from: sub)
                }
            }
        }
    }

    private static func stripMenu(_ menu: NSMenu) {
        for item in menu.items.reversed() {
            let t = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { continue }
            if bannedExact.contains(t) || bannedPrefixes.contains(where: { t.hasPrefix($0) }) {
                menu.removeItem(item)
            }
        }
    }

    private static func collapseExtraSeparators(_ menu: NSMenu) {
        var prevSep = true
        for item in menu.items.reversed() {
            if item.isSeparatorItem {
                if prevSep {
                    menu.removeItem(item)
                }
                prevSep = true
            } else {
                prevSep = false
            }
        }
        while menu.items.first?.isSeparatorItem == true {
            menu.removeItem(at: 0)
        }
        while menu.items.last?.isSeparatorItem == true {
            menu.removeItem(at: menu.items.count - 1)
        }
    }
}
