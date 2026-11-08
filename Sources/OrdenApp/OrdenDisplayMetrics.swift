import AppKit
import SwiftUI

/// Densidad / tipografía según pantalla + tamaño de ventana.
/// Pantallas chicas o 1× (no Retina): letras un poco más grandes y chrome más compacto.
struct OrdenDisplayMetrics: Equatable {
    /// Multiplicador de tipografía (1 = diseño de referencia).
    var textScale: CGFloat
    /// Multiplicador de espaciados / celdas (puede ser < 1 en pantallas estrechas).
    var chromeScale: CGFloat
    var sidebarWidth: CGFloat
    var assistantWidth: CGFloat
    var detailMinWidth: CGFloat
    var windowMinWidth: CGFloat
    var windowMinHeight: CGFloat
    var iconCell: CGFloat
    var iconSpacing: CGFloat
    var contentPadding: CGFloat
    var dynamicTypeSize: DynamicTypeSize
    var isCompact: Bool

    static let reference = OrdenDisplayMetrics(
        textScale: 1,
        chromeScale: 1,
        sidebarWidth: 248,
        assistantWidth: 360,
        detailMinWidth: 360,
        windowMinWidth: 560,
        windowMinHeight: 420,
        iconCell: 118,
        iconSpacing: 14,
        contentPadding: 16,
        dynamicTypeSize: .large,
        isCompact: false
    )

    @MainActor
    static func resolve(windowSize: CGSize, screen: NSScreen? = nil) -> OrdenDisplayMetrics {
        let resolvedScreen = screen ?? NSApp.keyWindow?.screen ?? NSScreen.main
        let visible = resolvedScreen?.visibleFrame.size ?? CGSize(width: 1440, height: 900)
        let backing = resolvedScreen?.backingScaleFactor ?? 2
        let winW = windowSize.width > 1 ? windowSize.width : min(1180, visible.width * 0.9)
        let winH = windowSize.height > 1 ? windowSize.height : min(740, visible.height * 0.9)

        // Pantalla “apretada”: MacBook 13″ @1080p escalado, monitores viejos, etc.
        let smallScreen = visible.width < 1360 || visible.height < 820
        let narrowWindow = winW < 980 || winH < 640
        let lowDPI = backing < 1.5
        let compact = smallScreen || narrowWindow || lowDPI

        // Texto: en pantallas chicas / 1× subir legibilidad; en grandes mantener.
        var text: CGFloat = 1
        if lowDPI { text += 0.12 }
        if smallScreen { text += 0.08 }
        if narrowWindow { text += 0.04 }
        text = min(1.28, max(0.95, text))

        // Chrome: compactar menús para dejar sitio al contenido legible.
        var chrome: CGFloat = 1
        if compact { chrome = 0.88 }
        if visible.width < 1200 { chrome = min(chrome, 0.82) }
        chrome = min(1, max(0.78, chrome))

        // Ancho fijo (nunca colapsa). Un poco más generoso para Favoritos / Drive.
        let sidebar: CGFloat = compact ? round(200 * chrome / 0.88) : 248
        let assistant: CGFloat = compact ? 300 : 360
        let detailMin: CGFloat = compact ? 300 : 360
        let minW = min(visible.width * 0.92, sidebar + detailMin)
        let minH = min(visible.height * 0.85, compact ? 400 : 420)

        let typeSize: DynamicTypeSize
        switch text {
        case ..<1.02: typeSize = .large
        case ..<1.12: typeSize = .xLarge
        case ..<1.2: typeSize = .xxLarge
        default: typeSize = .xxxLarge
        }

        return OrdenDisplayMetrics(
            textScale: text,
            chromeScale: chrome,
            sidebarWidth: max(184, sidebar),
            assistantWidth: assistant,
            detailMinWidth: detailMin,
            windowMinWidth: max(480, minW),
            windowMinHeight: max(360, minH),
            iconCell: round(118 * chrome),
            iconSpacing: round(14 * chrome),
            contentPadding: round(16 * chrome),
            dynamicTypeSize: typeSize,
            isCompact: compact
        )
    }

    /// Tamaño de ventana inicial que cabe entero en la pantalla visible.
    @MainActor
    static func preferredWindowSize(on screen: NSScreen? = nil) -> CGSize {
        let visible = (screen ?? NSScreen.main)?.visibleFrame.size ?? CGSize(width: 1440, height: 900)
        let ideal = CGSize(width: 1180, height: 740)
        let maxW = visible.width * 0.94
        let maxH = visible.height * 0.90
        return CGSize(
            width: min(ideal.width, max(560, maxW)),
            height: min(ideal.height, max(420, maxH))
        )
    }
}

private struct OrdenDisplayMetricsKey: EnvironmentKey {
    static let defaultValue: OrdenDisplayMetrics = .reference
}

extension EnvironmentValues {
    var ordenMetrics: OrdenDisplayMetrics {
        get { self[OrdenDisplayMetricsKey.self] }
        set { self[OrdenDisplayMetricsKey.self] = newValue }
    }
}

extension View {
    /// Tipografía + límites de Dynamic Type según métricas detectadas.
    func ordenAdaptiveTypography(_ metrics: OrdenDisplayMetrics) -> some View {
        self
            .dynamicTypeSize(metrics.dynamicTypeSize)
            .environment(\.ordenMetrics, metrics)
    }
}

enum OrdenWindowFit {
    /// Encaja la ventana principal dentro del `visibleFrame` (evita UI cortada).
    @MainActor
    static func applyToOpenWindows() {
        for window in NSApp.windows where window.styleMask.contains(.titled) {
            fit(window)
        }
    }

    @MainActor
    static func fit(_ window: NSWindow) {
        guard let screen = window.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        var frame = window.frame

        let maxW = visible.width * 0.96
        let maxH = visible.height * 0.94
        if frame.width > maxW { frame.size.width = maxW }
        if frame.height > maxH { frame.size.height = maxH }

        // Si queda fuera, centrar en el área visible.
        if frame.maxX > visible.maxX {
            frame.origin.x = visible.maxX - frame.width
        }
        if frame.minX < visible.minX {
            frame.origin.x = visible.minX
        }
        if frame.maxY > visible.maxY {
            frame.origin.y = visible.maxY - frame.height
        }
        if frame.minY < visible.minY {
            frame.origin.y = visible.minY
        }

        let metrics = OrdenDisplayMetrics.resolve(
            windowSize: frame.size,
            screen: screen
        )
        window.contentMinSize = NSSize(
            width: metrics.windowMinWidth,
            height: metrics.windowMinHeight
        )
        window.setFrame(frame, display: true)
    }
}
