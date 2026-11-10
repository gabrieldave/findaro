import Foundation
import CoreGraphics

/// Arrastre inmediato (tras unos px) = marquee.
/// ⌘+clic arma modo naranja sticky; luego el drag mueve archivos (Esc cancela).
public enum PressDragIntent: Equatable, Sendable {
    case marquee
    case fileMove
}

/// Qué hacer al superar el umbral de arrastre.
public enum PressDragStartAction: Equatable, Sendable {
    /// No consumir el gesto (p. ej. ⌘ sin modo naranja).
    case ignore
    /// Arrastre nativo de archivos. `selectOnlyID` si hay que fijar selección al ítem pulsado.
    case beginFileDrag(paths: [String], selectOnlyID: String?)
    /// Marquesina (espacio vacío, ⇧, o gesto de caja/vertical).
    case beginMarquee(additive: Bool)
    /// Archivo no seleccionado: aún no decidimos (marquesina vs mover).
    case pendingUnselectedFile(id: String, path: String)
}

public enum PressDragSelectLogic {
    /// Distancia mínima para reconocer arrastre (no robar clic limpio).
    public static let moveThreshold: CGFloat = 4

    /// El marquee solo “engancha” con un rectángulo intencional.
    public static let marqueeCommitSize: CGFloat = 28

    public static func isMarqueeCommitted(translation: CGSize) -> Bool {
        abs(translation.width) >= marqueeCommitSize
            || abs(translation.height) >= marqueeCommitSize
    }

    /// Altura de fila lista — debe coincidir con el `.frame` de `FileRowButton`.
    public static func listRowHeight(showPaths: Bool) -> CGFloat {
        showPaths ? 64 : 48
    }

    /// Arranque del gesto.
    /// - Seleccionado / armado → mover ya.
    /// - No seleccionado → `pending` (se resuelve en `resolvePendingUnselected`).
    /// - Vacío / ⇧ → marquesina.
    public static func startAction(
        hitID: String?,
        hitPath: String?,
        hitIsSelected: Bool,
        selectedPaths: [String],
        commandHeld: Bool,
        shiftHeld: Bool,
        hasArmedFileDrag: Bool,
        armedPaths: [String],
        isArming: Bool
    ) -> PressDragStartAction {
        if isArming { return .ignore }
        if commandHeld, !hasArmedFileDrag { return .ignore }
        if hasArmedFileDrag {
            return .beginFileDrag(paths: armedPaths, selectOnlyID: nil)
        }
        if let hitID, let hitPath, !hitPath.isEmpty {
            if hitIsSelected {
                let paths = selectedPaths.isEmpty ? [hitPath] : selectedPaths
                return .beginFileDrag(paths: paths, selectOnlyID: nil)
            }
            if shiftHeld {
                return .beginMarquee(additive: true)
            }
            // No comerse la marquesina: decidir en movimiento (vertical/caja vs horizontal).
            return .pendingUnselectedFile(id: hitID, path: hitPath)
        }
        return .beginMarquee(additive: shiftHeld)
    }

    /// Resuelve pending sin delay artificial.
    /// - Caja/vertical ≥ marqueeCommitSize → marquesina (multi-selección con mouse).
    /// - Horizontal dominante ≥ moveThreshold → mover ese archivo (Finder / otro panel).
    public static func resolvePendingUnselected(
        id: String,
        path: String,
        translation: CGSize
    ) -> PressDragStartAction? {
        let dx = abs(translation.width)
        let dy = abs(translation.height)

        if dy >= marqueeCommitSize || (dx >= marqueeCommitSize && dy >= marqueeCommitSize * 0.45) {
            return .beginMarquee(additive: false)
        }
        if dx >= moveThreshold, dx > dy {
            return .beginFileDrag(paths: [path], selectOnlyID: id)
        }
        // Vertical corto: espera a marqueeCommitSize (no lances drag ni marquesina aún).
        return nil
    }
}
