import Foundation
import AppKit
import OrdenCore

/// Arrastre inmediato (tras unos px) = marquee.
/// ⌘+clic arma modo naranja sticky; luego el drag mueve archivos (Esc cancela).
enum PressDragIntent: Equatable {
    case marquee
    case fileMove
}

@MainActor
enum PressDragSelectLogic {
    /// Distancia mínima para reconocer arrastre (no robar clic limpio).
    static let moveThreshold: CGFloat = 4

    /// El marquee solo “engancha” con un rectángulo intencional.
    /// Evita que un micro-movimiento al hacer clic seleccione la fila de al lado.
    static let marqueeCommitSize: CGFloat = 28

    static func isMarqueeCommitted(translation: CGSize) -> Bool {
        abs(translation.width) >= marqueeCommitSize
            || abs(translation.height) >= marqueeCommitSize
    }

    /// Altura de fila lista — debe coincidir con el `.frame` de `FileRowButton`.
    static func listRowHeight(showPaths: Bool) -> CGFloat {
        showPaths ? 64 : 48
    }
}
