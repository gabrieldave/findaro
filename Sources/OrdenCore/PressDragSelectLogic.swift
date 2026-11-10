import Foundation
import CoreGraphics

/// Arrastre inmediato (tras unos px) = marquee.
/// ⌘+clic arma modo naranja sticky; luego el drag mueve archivos (Esc cancela).
public enum PressDragIntent: Equatable, Sendable {
    case marquee
    case fileMove
}

/// Qué hacer al superar el umbral de arrastre (estilo Finder).
public enum PressDragStartAction: Equatable, Sendable {
    /// No consumir el gesto (p. ej. ⌘ sin modo naranja).
    case ignore
    /// Arrastre nativo de archivos. `selectOnlyID` si hay que fijar selección al ítem pulsado.
    case beginFileDrag(paths: [String], selectOnlyID: String?)
    /// Marquesina (espacio vacío o ⇧ desde ítem no seleccionado).
    case beginMarquee(additive: Bool)
}

public enum PressDragSelectLogic {
    /// Distancia mínima para reconocer arrastre (no robar clic limpio).
    /// Mantener bajo: clic suelto = seleccionar; apretar + mover = arrastrar (Finder).
    public static let moveThreshold: CGFloat = 4

    /// El marquee solo “engancha” con un rectángulo intencional.
    /// Evita que un micro-movimiento al hacer clic seleccione la fila de al lado.
    public static let marqueeCommitSize: CGFloat = 28

    public static func isMarqueeCommitted(translation: CGSize) -> Bool {
        abs(translation.width) >= marqueeCommitSize
            || abs(translation.height) >= marqueeCommitSize
    }

    /// Altura de fila lista — debe coincidir con el `.frame` de `FileRowButton`.
    public static func listRowHeight(showPaths: Bool) -> CGFloat {
        showPaths ? 64 : 48
    }

    /// Regla Finder: click+suelta selecciona; click+arrastra sobre un archivo lo mueve.
    /// Marquesina solo desde vacío (o ⇧ sobre no seleccionado). Sin delays extra.
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
            // ⇧ conserva marquesina aditiva; sin modificadores = mover ese archivo (Finder).
            if shiftHeld {
                return .beginMarquee(additive: true)
            }
            return .beginFileDrag(paths: [hitPath], selectOnlyID: hitID)
        }
        return .beginMarquee(additive: shiftHeld)
    }
}
