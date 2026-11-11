import AppKit
import SwiftUI

/// Densidad / chrome según tamaño de ventana. Tipografía nativa macOS (sin inflación).
struct OrdenDisplayMetrics: Equatable {
    /// Siempre 1.0 — prohibido inflar tipografía (rompe botones en pantallas estrechas).
    var textScale: CGFloat
    /// Multiplicador de espaciados / celdas.
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
    /// Ancho útil del panel de detalle (aprox. ventana − sidebar).
    var detailWidth: CGFloat

    enum DensityBand: Equatable {
        case compactSplit   // detail < 680
        case air13          // win 1100…1360
        case pro14_16       // win 1361…1800
        case wide           // win > 1800
    }

    static let reference = OrdenDisplayMetrics(
        textScale: 1,
        chromeScale: 1,
        sidebarWidth: 220,
        assistantWidth: 360,
        detailMinWidth: 360,
        windowMinWidth: 560,
        windowMinHeight: 420,
        iconCell: 118,
        iconSpacing: 14,
        contentPadding: 16,
        dynamicTypeSize: .large,
        isCompact: false,
        detailWidth: 1100
    )

    @MainActor
    static func resolve(windowSize: CGSize, screen: NSScreen? = nil) -> OrdenDisplayMetrics {
        let resolvedScreen = screen ?? NSApp.keyWindow?.screen ?? NSScreen.main
        let visible = resolvedScreen?.visibleFrame.size ?? CGSize(width: 1440, height: 900)
        let winW = windowSize.width > 1 ? windowSize.width : min(1280, visible.width * 0.94)
        _ = windowSize.height > 1 ? windowSize.height : min(820, visible.height * 0.92)

        // Tipografía nativa: nunca > 1.0 ni Dynamic Type gigante.
        let text: CGFloat = 1.0
        let typeSize: DynamicTypeSize = winW < 1180 ? .medium : .large

        let provisionalSidebar: CGFloat
        if winW <= 1360 { provisionalSidebar = 204 }
        else if winW <= 1800 { provisionalSidebar = 220 }
        else { provisionalSidebar = 236 }

        let detailW = max(320, winW - provisionalSidebar - 16)
        let band: DensityBand
        if detailW < 680 {
            band = .compactSplit
        } else if winW <= 1360 {
            band = .air13
        } else if winW <= 1800 {
            band = .pro14_16
        } else {
            band = .wide
        }

        let chrome: CGFloat
        let sidebar: CGFloat
        let assistant: CGFloat
        let detailMin: CGFloat
        let compact: Bool

        switch band {
        case .compactSplit:
            chrome = 0.86
            sidebar = 190
            assistant = 280
            detailMin = 300
            compact = true
        case .air13:
            chrome = 0.92
            sidebar = 204
            assistant = 300
            detailMin = 320
            compact = true
        case .pro14_16:
            chrome = 1.0
            sidebar = 220
            assistant = 340
            detailMin = 360
            compact = false
        case .wide:
            chrome = 1.0
            sidebar = 236
            assistant = 360
            detailMin = 380
            compact = false
        }

        let minW = min(visible.width * 0.92, sidebar + detailMin)
        let minH = min(visible.height * 0.85, compact ? 420 : 460)

        return OrdenDisplayMetrics(
            textScale: text,
            chromeScale: chrome,
            sidebarWidth: sidebar,
            assistantWidth: assistant,
            detailMinWidth: detailMin,
            windowMinWidth: max(520, minW),
            windowMinHeight: max(380, minH),
            iconCell: round(118 * chrome),
            iconSpacing: round(14 * chrome),
            contentPadding: round(14 * chrome),
            dynamicTypeSize: typeSize,
            isCompact: compact,
            detailWidth: detailW
        )
    }

    /// Tamaño de ventana inicial razonable (captura / uso diario).
    @MainActor
    static func preferredWindowSize(on screen: NSScreen? = nil) -> CGSize {
        let visible = (screen ?? NSScreen.main)?.visibleFrame.size ?? CGSize(width: 1440, height: 900)
        let ideal = CGSize(width: 1280, height: 800)
        let maxW = visible.width * 0.96
        let maxH = visible.height * 0.94
        return CGSize(
            width: min(ideal.width, max(720, maxW)),
            height: min(ideal.height, max(520, maxH))
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
    func ordenAdaptiveTypography(_ metrics: OrdenDisplayMetrics) -> some View {
        self
            .dynamicTypeSize(metrics.dynamicTypeSize)
            .environment(\.ordenMetrics, metrics)
    }
}

enum OrdenWindowFit {
    @MainActor
    static func applyToOpenWindows() {
        for window in NSApp.windows where window.styleMask.contains(.titled) {
            if window is NSPanel || window.isSheet || window.sheetParent != nil { continue }
            let s = window.frame.size
            if s.width < 720, s.height < 780 { continue }
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
