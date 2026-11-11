import SwiftUI
import AppKit
import OrdenCore
import Combine

/// Controlador reactivo de tema (cambia en caliente sin reiniciar).
@MainActor
final class ThemeController: ObservableObject {
    static let shared = ThemeController()

    @Published private(set) var theme: AppColorTheme
    @Published private(set) var revision: UInt = 0

    private var appearanceObserver: NSObjectProtocol?
    private var prefsObserver: NSObjectProtocol?

    private init() {
        let stored = PreferencesStore.shared.preferences.colorTheme.normalizedForStorage
        theme = stored
        UserDefaults.standard.set(stored.rawValue, forKey: "findaro_color_theme")
        OrdenTheme.sync(from: stored)

        prefsObserver = NotificationCenter.default.addObserver(
            forName: PreferencesStore.preferencesDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reloadFromStore()
            }
        }

        appearanceObserver = DistributedNotificationCenter.default.addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.bump()
            }
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch theme {
        case .systemAuto: return nil
        case .nordicLight: return .light
        case .midnightBlue, .graphitePro, .emeraldSlate: return .dark
        }
    }

    var palette: AppColorPalette {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return AppColorPalette.palette(for: theme.resolved(isDark: isDark))
    }

    func setTheme(_ next: AppColorTheme) {
        let normalized = next.normalizedForStorage
        guard normalized != theme else { return }
        theme = normalized
        UserDefaults.standard.set(normalized.rawValue, forKey: "findaro_color_theme")
        PreferencesStore.shared.update { $0.colorTheme = normalized }
        OrdenTheme.sync(from: normalized)
        bump()
    }

    private func reloadFromStore() {
        let next = PreferencesStore.shared.preferences.colorTheme.normalizedForStorage
        if next != theme {
            theme = next
            UserDefaults.standard.set(next.rawValue, forKey: "findaro_color_theme")
        }
        OrdenTheme.sync(from: theme)
        bump()
    }

    private func bump() {
        OrdenTheme.sync(from: theme)
        revision &+= 1
        objectWillChange.send()
    }
}

/// Findaro visual system — tokens leídos del tema activo.
enum OrdenTheme {
    /// Cache sincronizado desde `ThemeController` (UI / MainActor).
    nonisolated(unsafe) private static var cachedPalette = AppColorPalette.palette(for: .midnightBlue)
    nonisolated(unsafe) private static var cachedTheme: AppColorTheme = .midnightBlue

    @MainActor
    static func sync(from theme: AppColorTheme) {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        cachedTheme = theme
        cachedPalette = AppColorPalette.palette(for: theme.resolved(isDark: isDark))
    }

    static var activeTheme: AppColorTheme { cachedTheme }

    // MARK: - Brand accents

    static var accent: Color { Color(findaroHex: cachedPalette.accent) }
    static var accentHover: Color { Color(findaroHex: cachedPalette.accentHover) }
    static var accentSecondary: Color { Color(findaroHex: cachedPalette.accentAI) }
    static var cyan: Color { Color(findaroHex: cachedPalette.accentAI) }
    static var success: Color { Color(findaroHex: cachedPalette.success) }
    static var warning: Color { Color(findaroHex: cachedPalette.warning) }
    static var danger: Color { Color(findaroHex: cachedPalette.danger) }
    static var selection: Color { Color(findaroHex: cachedPalette.selection) }

    // MARK: - Surfaces

    static var windowFill: Color { Color(findaroHex: cachedPalette.windowFill) }
    static var sidebarFill: Color { Color(findaroHex: cachedPalette.sidebarFill) }
    static var panelFill: Color { Color(findaroHex: cachedPalette.panelFill) }
    static var elevatedFill: Color { Color(findaroHex: cachedPalette.elevatedFill) }
    static var hairline: Color { Color(findaroHex: cachedPalette.hairline) }

    static var textSecondary: Color { Color(findaroHex: cachedPalette.textSecondary) }
    static var textMuted: Color { Color(findaroHex: cachedPalette.textSecondary).opacity(0.85) }

    static var rowSelectionFill: Color {
        if cachedTheme.resolved(isDark: false) == .nordicLight || cachedTheme == .nordicLight {
            return Color(findaroHex: cachedPalette.accent).opacity(0.16)
        }
        return Color(findaroHex: cachedPalette.selection).opacity(0.55)
    }

    static var sidebarActiveFill: Color {
        Color(findaroHex: cachedPalette.accent).opacity(0.22)
    }

    // MARK: - Radii

    static let radiusWindow: CGFloat = 14
    static let radiusPanel: CGFloat = 10
    static let radiusControl: CGFloat = 7
    static let radiusChip: CGFloat = 6

    // MARK: - Motion

    static let motionMicro: Double = 0.10
    static let motionStandard: Double = 0.16
    static let motionEmphasis: Double = 0.22
}

// MARK: - Hex helpers

extension Color {
    init(findaroHex hex: String) {
        self.init(nsColor: NSColor(findaroHex: hex))
    }
}

extension NSColor {
    convenience init(findaroHex hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if value.hasPrefix("#") { value.removeFirst() }
        var rgb: UInt64 = 0
        Scanner(string: value).scanHexInt64(&rgb)
        let r = CGFloat((rgb & 0xFF0000) >> 16) / 255
        let g = CGFloat((rgb & 0x00FF00) >> 8) / 255
        let b = CGFloat(rgb & 0x0000FF) / 255
        self.init(calibratedRed: r, green: g, blue: b, alpha: 1)
    }
}

extension View {
    @ViewBuilder
    func ordenGlassCard(cornerRadius: CGFloat = OrdenTheme.radiusWindow) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            self
                .padding(12)
                .glassEffect(.regular.interactive(), in: shape)
        } else {
            self
                .padding(12)
                .background(OrdenTheme.panelFill, in: shape)
                .overlay(shape.strokeBorder(OrdenTheme.hairline, lineWidth: 1))
        }
    }

    func findaroSurface(cornerRadius: CGFloat = OrdenTheme.radiusWindow) -> some View {
        background(OrdenTheme.panelFill, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(OrdenTheme.hairline, lineWidth: 1)
            )
    }

    func findaroPanelChrome(focused: Bool = false, cornerRadius: CGFloat = OrdenTheme.radiusWindow) -> some View {
        background(OrdenTheme.panelFill, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        focused ? OrdenTheme.accent.opacity(0.85) : OrdenTheme.hairline,
                        lineWidth: focused ? 2 : 1
                    )
            )
    }

    /// Aplica preferredColorScheme + fuerza redibujo al cambiar tema.
    func findaroThemed(_ controller: ThemeController = .shared) -> some View {
        self
            .preferredColorScheme(controller.preferredColorScheme)
            .tint(OrdenTheme.accent)
            .id(controller.revision)
    }
}

/// Selector visual de swatches (Ajustes + menú •••).
struct ColorThemeSwatchPicker: View {
    @ObservedObject private var themes = ThemeController.shared

    var body: some View {
        HStack(spacing: 10) {
            ForEach(AppColorTheme.pickerCases, id: \.self) { theme in
                Button {
                    themes.setTheme(theme)
                } label: {
                    ZStack {
                        // Disco = fondo del tema + anillo de acento (predice el look real).
                        Circle()
                            .fill(Color(findaroHex: theme.swatchFillHex))
                            .frame(width: 22, height: 22)
                            .overlay(
                                Circle()
                                    .strokeBorder(
                                        Color(findaroHex: theme.swatchHex),
                                        lineWidth: theme.swatchIsLight ? 2.5 : 3
                                    )
                            )
                            .overlay(
                                Circle()
                                    .strokeBorder(
                                        theme.swatchIsLight ? Color.black.opacity(0.35) : Color.white.opacity(0.22),
                                        lineWidth: 1
                                    )
                            )
                        if themes.theme == theme || (themes.theme == .systemAuto && theme == .midnightBlue) {
                            Circle()
                                .strokeBorder(Color.primary.opacity(0.9), lineWidth: 2)
                                .frame(width: 28, height: 28)
                        }
                    }
                    .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .help(theme.displayName(english: L10n.isEnglish))
                .accessibilityLabel(theme.displayName(english: L10n.isEnglish))
            }
        }
    }
}

struct ColorThemeMenuContent: View {
    @ObservedObject private var themes = ThemeController.shared

    var body: some View {
        ForEach(AppColorTheme.pickerCases, id: \.self) { theme in
            Button {
                themes.setTheme(theme)
            } label: {
                HStack {
                    Circle()
                        .fill(Color(findaroHex: theme.swatchFillHex))
                        .frame(width: 10, height: 10)
                        .overlay(Circle().strokeBorder(Color(findaroHex: theme.swatchHex), lineWidth: 2))
                    Text(theme.displayName(english: L10n.isEnglish))
                    if themes.theme == theme || (themes.theme == .systemAuto && theme == .midnightBlue) {
                        Image(systemName: "checkmark")
                    }
                }
            }
        }
    }
}
