import Foundation

public enum LicenseGateError: LocalizedError, Sendable {
    case writeNotAllowed(reason: String)

    public var errorDescription: String? {
        switch self {
        case .writeNotAllowed(let reason):
            return reason
        }
    }
}

public final class LicenseGate: @unchecked Sendable {
    private static let lock = NSLock()
    /// Fail-closed: escritura bloqueada hasta que LicenseStore valide trial/token.
    nonisolated(unsafe) private static var _isWriteAllowed: Bool = false
    nonisolated(unsafe) private static var _onWriteBlocked: (@Sendable () -> Void)?

    public static func setWriteAllowed(_ allowed: Bool, onBlocked: (@Sendable () -> Void)? = nil) {
        lock.lock()
        defer { lock.unlock() }
        _isWriteAllowed = allowed
        if let onBlocked {
            _onWriteBlocked = onBlocked
        }
    }

    public static func allowsWrite() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isWriteAllowed
    }

    public static func requireWrite() throws {
        lock.lock()
        let allowed = _isWriteAllowed
        let callback = _onWriteBlocked
        lock.unlock()

        if !allowed {
            callback?()
            throw LicenseGateError.writeNotAllowed(
                reason: "Esta operación requiere una licencia activa o una prueba vigente de Findaro. El modo de solo lectura está activo."
            )
        }
    }
}
