import Foundation
import CoreGraphics

/// Arrastre inmediato (tras unos px) = marquee o mover archivos.
public enum PressDragIntent: Equatable, Sendable {
    case marquee
    case fileMove
}

/// Qué hacer al superar el umbral de arrastre.
public enum PressDragStartAction: Equatable, Sendable {
    case ignore
    case beginFileDrag(paths: [String], selectOnlyID: String?)
    case beginMarquee(additive: Bool)
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

    public static func listRowHeight(showPaths: Bool) -> CGFloat {
        showPaths ? 64 : 48
    }

    /// Reglas (Tray está abajo → el drag vertical DEBE mover, no marquesina):
    /// - Clic en archivo + mover (cualquier dirección) → arrastrar archivo(s).
    /// - ⇧ + archivo no seleccionado → marquesina aditiva.
    /// - Vacío (debajo/al lado) → marquesina.
    /// - ⌘ sin modo naranja → ignore (lo maneja la fila).
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
        // `isArming` ya no bloquea: el jalón Finder debe ganar siempre.
        if commandHeld, !hasArmedFileDrag { return .ignore }
        if hasArmedFileDrag {
            return .beginFileDrag(paths: armedPaths, selectOnlyID: nil)
        }
        if let hitID, let hitPath, !hitPath.isEmpty {
            if shiftHeld, !hitIsSelected {
                return .beginMarquee(additive: true)
            }
            if hitIsSelected {
                let paths = selectedPaths.isEmpty ? [hitPath] : selectedPaths
                return .beginFileDrag(paths: paths, selectOnlyID: nil)
            }
            // Primer jalón sobre archivo: mover ese archivo (Finder). Marquesina = vacío o ⇧.
            return .beginFileDrag(paths: [hitPath], selectOnlyID: hitID)
        }
        return .beginMarquee(additive: shiftHeld)
    }
}
