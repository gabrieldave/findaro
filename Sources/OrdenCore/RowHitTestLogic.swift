import Foundation
import CoreGraphics

/// Hit-test puro para filas de lista (frames en coordenadas de ventana).
/// Evita abrir/seleccionar un vecino cuando quedan frames viejos del LazyVStack.
public enum RowHitTestLogic {
    public struct RowFrame: Equatable, Sendable {
        public var path: String
        public var frame: CGRect
        /// Monotonic token; frames con generation distinta a la vigente se ignoran.
        public var generation: UInt64

        public init(path: String, frame: CGRect, generation: UInt64) {
            self.path = path
            self.frame = frame
            self.generation = generation
        }
    }

    /// Índice de fila a partir de Y en el contenido (misma fórmula que el marquee).
    public static func indexAtY(_ y: CGFloat, rowHeight: CGFloat, count: Int) -> Int? {
        guard count > 0, rowHeight > 0 else { return nil }
        let contentH = CGFloat(count) * rowHeight
        guard y >= 0, y < contentH else { return nil }
        return min(count - 1, max(0, Int(floor(y / rowHeight))))
    }

    /// Elige path bajo el clic. Solo considera frames de `generation`.
    /// Si varios frames contienen el punto, gana el de menor |midY − y| (y luego el más estrecho).
    /// Si no hay contenedor claro, usa cercanía vertical corta; si sigue ambiguo → nil.
    public static func pathAt(
        point: CGPoint,
        frames: [RowFrame],
        generation: UInt64,
        nearTolerance: CGFloat = 14
    ) -> String? {
        let live = frames.filter { $0.generation == generation && $0.frame.width > 2 && $0.frame.height > 2 }
        guard !live.isEmpty else { return nil }

        var inside: [RowFrame] = []
        for row in live where row.frame.insetBy(dx: 0, dy: 1).contains(point) {
            inside.append(row)
        }
        // Varios frames contienen el clic → solape stale (LazyVStack). No adivinar.
        if inside.count > 1 {
            return nil
        }
        if inside.count == 1 {
            return inside[0].path
        }

        var near: [RowFrame] = []
        for row in live {
            guard point.x >= row.frame.minX - 4, point.x <= row.frame.maxX + 4 else { continue }
            let dy = abs(row.frame.midY - point.y)
            guard dy <= max(nearTolerance, row.frame.height * 0.5) else { continue }
            near.append(row)
        }
        if near.count != 1 { return nil }
        return near[0].path
    }
}
