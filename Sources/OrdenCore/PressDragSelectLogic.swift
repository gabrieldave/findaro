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
    public static let moveThreshold: CGFloat = 3

    /// Marquesina engancha pronto (Finder no espera una caja enorme).
    public static let marqueeCommitSize: CGFloat = 6

    public static func isMarqueeCommitted(translation: CGSize) -> Bool {
        abs(translation.width) >= marqueeCommitSize
            || abs(translation.height) >= marqueeCommitSize
    }

    public static func listRowHeight(showPaths: Bool) -> CGFloat {
        showPaths ? 64 : 48
    }

    /// Modelo Finder:
    /// - `hitOnName` (icono + nombre) → mover archivo(s). SwiftUI puede `.ignore` si AppKit ya arma el drag.
    /// - Fuera del nombre (columnas vacías, debajo de la lista) → marquesina.
    /// - ⇧ → marquesina aditiva (también desde el nombre).
    /// - ⌘ sin modo naranja → ignore (lo resuelve el clic).
    public static func startAction(
        hitOnName: Bool,
        hitID: String?,
        hitPath: String?,
        hitIsSelected: Bool,
        selectedPaths: [String],
        commandHeld: Bool,
        shiftHeld: Bool,
        hasArmedFileDrag: Bool,
        armedPaths: [String],
        isArming: Bool = false
    ) -> PressDragStartAction {
        _ = isArming
        if commandHeld, !hasArmedFileDrag { return .ignore }
        if hasArmedFileDrag {
            return .beginFileDrag(paths: armedPaths, selectOnlyID: nil)
        }
        // ⇧ siempre permite caja aditiva (Finder).
        if shiftHeld {
            return .beginMarquee(additive: true)
        }
        // Solo el chrome del nombre/icono mueve archivos.
        if hitOnName, let hitID, let hitPath, !hitPath.isEmpty {
            if hitIsSelected {
                let paths = selectedPaths.isEmpty ? [hitPath] : selectedPaths
                return .beginFileDrag(paths: paths, selectOnlyID: nil)
            }
            return .beginFileDrag(paths: [hitPath], selectOnlyID: hitID)
        }
        // Vacío / columnas Date·Size / gutter → marquesina.
        return .beginMarquee(additive: false)
    }
}
