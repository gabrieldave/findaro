import AppKit
import OrdenCore

/// Findaro about panel bridge; internal type name retained for compatibility.
@MainActor
enum AboutOrdena {
    static func show() {
        AboutWindowController.show()
    }
}
