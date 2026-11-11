import AppKit

/// ¿El foco está en un campo de texto o editor? (chat, omnibox, search, rename…)
/// Ojo: NO usar `NSTextInputClient` a secas — muchos hosts SwiftUI lo implementan
/// y entonces Espacio (Vista rápida) / ⌫ quedaban bloqueados con la lista enfocada.
enum FindaroTextInput {
    @MainActor
    static var isEditing: Bool {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow,
              let fr = window.firstResponder else { return false }

        if fr is NSTextField { return true }
        if fr is NSTextView { return true }

        let name = NSStringFromClass(type(of: fr))
        if isTextControlClassName(name) { return true }

        if let view = fr as? NSView {
            var parent: NSView? = view
            while let p = parent {
                if p is NSTextField || p is NSTextView { return true }
                if isTextControlClassName(NSStringFromClass(type(of: p))) { return true }
                parent = p.superview
            }
        }
        return false
    }

    private static func isTextControlClassName(_ name: String) -> Bool {
        name.contains("FieldEditor")
            || name.contains("NSTextField")
            || name.contains("NSSecureTextField")
            || name.contains("NSTextView")
            || name.contains("SearchField")
            || name.contains("TextEditor")
            || name.contains("SwiftUI.TextEditor")
    }
}
