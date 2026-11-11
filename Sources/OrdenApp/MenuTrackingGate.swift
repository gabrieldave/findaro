import AppKit
import Foundation

/// Evita redibujar la ventana (FSEvents → reload) mientras un menú de macOS
/// está abierto encima: el material traslúcido parpadea / abre-cierra si el
/// contenido de la ventana cambia bajo el menú.
@MainActor
enum MenuTrackingGate {
    private static var pendingPrimary = false
    private static var pendingSecondary = false
    private static var pollTask: Task<Void, Never>?
    private static var primaryWork: (@MainActor () -> Void)?
    private static var secondaryWork: (@MainActor () -> Void)?

    static var isMenuOpen: Bool {
        if RunLoop.current.currentMode == .eventTracking { return true }
        if NSApp.mainMenu?.highlightedItem != nil { return true }
        for window in NSApp.windows where window.isVisible {
            let name = NSStringFromClass(type(of: window))
            if name.contains("MenuBar") { continue }
            if name.contains("Menu") || name.contains("NSPopup") || name.contains("NSCarbonMenu") {
                return true
            }
        }
        return false
    }

    static func deferPrimaryReload(_ work: @escaping @MainActor () -> Void) {
        if isMenuOpen {
            pendingPrimary = true
            primaryWork = work
            ensurePoll()
            return
        }
        work()
    }

    static func deferSecondaryReload(_ work: @escaping @MainActor () -> Void) {
        if isMenuOpen {
            pendingSecondary = true
            secondaryWork = work
            ensurePoll()
            return
        }
        work()
    }

    private static func ensurePoll() {
        guard pollTask == nil else { return }
        pollTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 80_000_000)
                if isMenuOpen { continue }
                let runP = pendingPrimary
                let runS = pendingSecondary
                let p = primaryWork
                let s = secondaryWork
                pendingPrimary = false
                pendingSecondary = false
                primaryWork = nil
                secondaryWork = nil
                pollTask = nil
                if runP { p?() }
                if runS { s?() }
                break
            }
        }
    }
}
