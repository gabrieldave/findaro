import Foundation

/// Información dinámica del hardware de la Mac para diagnóstico y telemetría local.
/// Cero texto fijo de chip: lee directamente de las APIs del kernel de macOS.
public struct HardwareIdentity: Sendable {
    public init() {}

    /// Chip real de la Mac (ej. "Apple M4", "Apple M1 Pro", "Intel Core i7").
    public static var chipModel: String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        guard size > 0 else {
            return fallbackArchitecture()
        }
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0)
        let brand = buffer.withUnsafeBufferPointer { ptr in
            ptr.baseAddress.map { String(cString: $0) } ?? ""
        }.trimmingCharacters(in: .whitespacesAndNewlines)
        return brand.isEmpty ? fallbackArchitecture() : brand
    }

    /// Identificador del modelo de Mac (ej. "Mac16,1", "MacBookPro18,1").
    public static var modelIdentifier: String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return "Mac" }
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &buffer, &size, nil, 0)
        let model = buffer.withUnsafeBufferPointer { ptr in
            ptr.baseAddress.map { String(cString: $0) } ?? ""
        }.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.isEmpty ? "Mac" : model
    }

    /// Versión de macOS (ej. "15.1.0").
    public static var macOSVersionString: String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
    }

    /// Memoria física total en Gigabytes.
    public static var physicalMemoryGigabytes: Int {
        var size = MemoryLayout<UInt64>.size
        var memory: UInt64 = 0
        sysctlbyname("hw.memsize", &memory, &size, nil, 0)
        return Int(memory / (1024 * 1024 * 1024))
    }

    private static func fallbackArchitecture() -> String {
        #if arch(arm64)
        return "Apple Silicon"
        #elseif arch(x86_64)
        return "Intel Core"
        #else
        return "Mac"
        #endif
    }
}
