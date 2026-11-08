import AppKit

/// ¿El foco está en un campo de texto o editor? (chat, omnibox, search, rename…)
enum FindaroTextInput {
    @MainActor
    static var isEditing: Bool {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow,
              let fr = window.firstResponder else { return false }
        if fr is NSTextView || fr is NSTextField || fr is NSTextInputClient { return true }
        if let view = fr as? NSView {
            if view.isKind(of: NSClassFromString("NSTextView") ?? NSObject.self) { return true }
            if view.isKind(of: NSClassFromString("NSTextField") ?? NSObject.self) { return true }
            var parent = view.superview
            while let p = parent {
                if p is NSTextInputClient || p is NSTextView || p is NSTextField { return true }
                parent = p.superview
            }
        }
        let name = NSStringFromClass(type(of: fr))
        return name.contains("FieldEditor")
            || name.contains("TextInput")
            || name.contains("TextField")
            || name.contains("TextView")
            || name.contains("TextEditor")
            || name.contains("Editor")
            || name.contains("SearchField")
    }
}
