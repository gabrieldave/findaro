import Foundation
import AppKit
import OrdenCore

/// Intención del gesto: arrastre inmediato = selección; mantener 1s = mover archivos.
enum PressDragIntent: Equatable {
    case undecided
    case marquee
    case fileMove
}

/// Lógica compartida lista / iconos / columnas (estilo Windows: hold-to-drag).
@MainActor
final class PressDragSelectLogic {
    static let holdDuration: TimeInterval = 1.0
    static let moveThreshold: CGFloat = 5

    private(set) var intent: PressDragIntent = .undecided
    private var holdWork: DispatchWorkItem?
    private(set) var armedPaths: [String] = []
    private(set) var fileDragStarted = false

    func reset() {
        holdWork?.cancel()
        holdWork = nil
        intent = .undecided
        armedPaths = []
        fileDragStarted = false
    }

    /// Primer frame del gesto.
    func begin(
        hit: FileEntry?,
        selectedIDs: Set<String>,
        selectedPaths: [String],
        forceMarquee: Bool,
        onArmed: @escaping (_ paths: [String]) -> Void
    ) {
        reset()
        let flags = NSEvent.modifierFlags
        let modifiers = flags.contains(.shift) || flags.contains(.command)

        if forceMarquee || modifiers || hit == nil {
            intent = .marquee
            return
        }

        intent = .undecided
        let hitPath = hit!.path
        let hitID = hit!.id
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.intent == .undecided else { return }
            self.intent = .fileMove
            // Si el ítem no estaba seleccionado, solo ese; si ya había selección que lo incluye, todos.
            if selectedIDs.contains(hitID), !selectedPaths.isEmpty {
                self.armedPaths = selectedPaths
            } else {
                self.armedPaths = [hitPath]
            }
            onArmed(self.armedPaths)
        }
        holdWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.holdDuration, execute: work)
    }

    /// Movimiento: si aún no armó y ya se movió → marquee; si armó → iniciar drag nativo.
    func moved(distance: CGFloat) -> PressDragIntent {
        if intent == .undecided, distance >= Self.moveThreshold {
            holdWork?.cancel()
            holdWork = nil
            intent = .marquee
            armedPaths = []
        }
        return intent
    }

    @discardableResult
    func tryStartFileDrag() -> Bool {
        guard intent == .fileMove, !fileDragStarted, !armedPaths.isEmpty else { return false }
        fileDragStarted = true
        return FolderDragBridge.shared.startDrag(paths: armedPaths)
    }
}
