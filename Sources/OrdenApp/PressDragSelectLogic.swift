import Foundation
import AppKit
import OrdenCore

/// Arrastre inmediato (tras unos px) = marquee.
/// ⌘+clic arma mover (`BrowserModel.armFileDrag`); luego el drag mueve archivos.
enum PressDragIntent: Equatable {
    case marquee
    case fileMove
}

@MainActor
enum PressDragSelectLogic {
    /// Distancia mínima para no robar el clic rápido (selección de 1 archivo).
    static let moveThreshold: CGFloat = 4
}
