import Foundation

/// Recuerda qué teclas (⌘ / ⇧) estaban pulsadas en el instante del CLIC (mouseDown),
/// no en el instante en que SwiftUI reconoce el gesto.
///
/// Motivo: cada fila tiene clic simple + doble clic. SwiftUI puede esperar el intervalo de
/// doble clic (~0,3–0,5 s) antes de disparar el clic simple. Si el usuario suelta ⌘ o ⇧ en
/// ese lapso (lo normal), leer `NSEvent.modifierFlags` en ese momento devolvía "sin teclas"
/// y la selección se reemplazaba por un solo archivo: "⌘/⇧+clic no funciona".
public struct ClickModifierMemory: Sendable, Equatable {
    public struct Modifiers: Sendable, Equatable {
        public var command: Bool
        public var shift: Bool
        public var option: Bool

        public init(command: Bool = false, shift: Bool = false, option: Bool = false) {
            self.command = command
            self.shift = shift
            self.option = option
        }

        public static let none = Modifiers()
    }

    /// Ventana mínima entre mouseDown y el gesto SwiftUI para confiar en lo capturado.
    public static let maxAge: TimeInterval = 1.5

    /// Ventana efectiva: SwiftUI espera el intervalo de doble clic del sistema antes de disparar el
    /// clic simple, y ese intervalo es DISTINTO para mouse y trackpad (Ajustes → Mouse → Velocidad
    /// del doble clic). Con un mouse en velocidad lenta (2–5 s) la ventana fija de 1,5 s caducaba.
    public static func window(doubleClickInterval: TimeInterval) -> TimeInterval {
        max(maxAge, doubleClickInterval + 1.0)
    }

    public private(set) var captured: Modifiers = .none
    public private(set) var capturedAt: TimeInterval = -.infinity

    public init() {}

    public mutating func recordMouseDown(_ modifiers: Modifiers, at time: TimeInterval) {
        captured = modifiers
        capturedAt = time
    }

    /// Teclas efectivas del clic: lo capturado en mouseDown (si es reciente) ∪ lo que siga pulsado.
    public func resolve(now: TimeInterval, current: Modifiers, window: TimeInterval = ClickModifierMemory.maxAge) -> Modifiers {
        guard now - capturedAt >= 0, now - capturedAt <= window else { return current }
        return Modifiers(
            command: captured.command || current.command,
            shift: captured.shift || current.shift,
            option: captured.option || current.option
        )
    }
}
