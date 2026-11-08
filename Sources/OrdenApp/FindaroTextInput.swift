import AppKit

/// ¿El foco está en un campo de texto? (chat, omnibox, search, rename…)
enum FindaroTextInput {
    @MainActor
    static var isEditing: Bool {
        guard let fr = NSApp.keyWindow?.firstResponder else { return false }
        if fr is NSTextView || fr is NSTextField { return true }
        let name = NSStringFromClass(type(of: fr))
        return name.contains("FieldEditor")
            || name.contains("TextInput")
            || name.contains("TextField")
            || name.contains("TextView")
    }
}
