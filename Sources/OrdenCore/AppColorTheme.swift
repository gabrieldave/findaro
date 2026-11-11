import Foundation

/// Temas de color premium intercambiables en caliente (WCAG contraste ≥ 4.5:1 en tipografía).
public enum AppColorTheme: String, Codable, CaseIterable, Sendable, Equatable {
    case systemAuto
    case midnightBlue
    case graphitePro
    case emeraldSlate
    case nordicLight

    public var displayNameES: String {
        switch self {
        case .systemAuto: return "Automático (Mac)"
        case .midnightBlue: return "Azul Noche (Findaro)"
        case .graphitePro: return "Grafito Pro (Space Black)"
        case .emeraldSlate: return "Esmeralda Studio"
        case .nordicLight: return "Nórdico Claro"
        }
    }

    public var displayNameEN: String {
        switch self {
        case .systemAuto: return "System Auto"
        case .midnightBlue: return "Midnight Blue"
        case .graphitePro: return "Graphite Pro"
        case .emeraldSlate: return "Obsidian Emerald"
        case .nordicLight: return "Nordic Light"
        }
    }

    public func displayName(english: Bool) -> String {
        english ? displayNameEN : displayNameES
    }

    /// Swatch hex para el selector (acento primario).
    public var swatchHex: String {
        switch self {
        case .systemAuto: return "#64748B"
        case .midnightBlue: return "#3B82F6"
        case .graphitePro: return "#0A84FF"
        case .emeraldSlate: return "#10B981"
        case .nordicLight: return "#2563EB"
        }
    }

    /// Resuelve el tema concreto (systemAuto → midnight o nordic según apariencia).
    public func resolved(isDark: Bool) -> AppColorTheme {
        switch self {
        case .systemAuto: return isDark ? .midnightBlue : .nordicLight
        default: return self
        }
    }

    public var preferredColorSchemeRaw: String? {
        switch self {
        case .systemAuto: return nil
        case .nordicLight: return "light"
        case .midnightBlue, .graphitePro, .emeraldSlate: return "dark"
        }
    }
}

/// Tokens de color de un tema resuelto (hex sRGB).
public struct AppColorPalette: Equatable, Sendable {
    public var windowFill: String
    public var sidebarFill: String
    public var panelFill: String
    public var elevatedFill: String
    public var hairline: String
    public var textPrimary: String
    public var textSecondary: String
    public var accent: String
    public var accentHover: String
    public var accentAI: String
    public var selection: String
    public var success: String
    public var warning: String
    public var danger: String

    public static func palette(for theme: AppColorTheme) -> AppColorPalette {
        switch theme {
        case .systemAuto:
            // No usar directo: resolver antes con `resolved(isDark:)`.
            return palette(for: .midnightBlue)
        case .midnightBlue:
            return AppColorPalette(
                windowFill: "#0B1220",
                sidebarFill: "#090F1C",
                panelFill: "#131D31",
                elevatedFill: "#1C2A44",
                hairline: "#293B59",
                textPrimary: "#F8FAFC",
                textSecondary: "#AEBBD0",
                accent: "#3B82F6",
                accentHover: "#60A5FA",
                accentAI: "#8B5CF6",
                selection: "#1E3A8A",
                success: "#10B981",
                warning: "#F59E0B",
                danger: "#EF4444"
            )
        case .graphitePro:
            return AppColorPalette(
                windowFill: "#111113",
                sidebarFill: "#0C0C0E",
                panelFill: "#18181B",
                elevatedFill: "#232329",
                hairline: "#2E2E36",
                textPrimary: "#F4F4F5",
                textSecondary: "#A1A1AA",
                accent: "#0A84FF",
                accentHover: "#409CFF",
                accentAI: "#BF5AF2",
                selection: "#1D3557",
                success: "#30D158",
                warning: "#FFD60A",
                danger: "#FF453A"
            )
        case .emeraldSlate:
            return AppColorPalette(
                windowFill: "#0A1211",
                sidebarFill: "#070E0D",
                panelFill: "#111E1C",
                elevatedFill: "#192B28",
                hairline: "#25403B",
                textPrimary: "#ECFDF5",
                textSecondary: "#A7F3D0",
                accent: "#10B981",
                accentHover: "#34D399",
                accentAI: "#22D3EE",
                selection: "#064E3B",
                success: "#34D399",
                warning: "#FBBF24",
                danger: "#F87171"
            )
        case .nordicLight:
            return AppColorPalette(
                windowFill: "#F3F5F9",
                sidebarFill: "#E9EEF5",
                panelFill: "#FFFFFF",
                elevatedFill: "#F8FAFC",
                hairline: "#CBD5E1",
                textPrimary: "#0F172A",
                textSecondary: "#475569",
                accent: "#2563EB",
                accentHover: "#3B82F6",
                accentAI: "#7C3AED",
                selection: "#DBEAFE",
                success: "#059669",
                warning: "#D97706",
                danger: "#DC2626"
            )
        }
    }
}
