import SwiftUI

/// Estándar visual de diálogos Ordena (como Buscar en subcarpetas).
/// Usar sheets con este chrome; no alerts de sistema para flujos de producto.
enum OrdenDialogMetrics {
    static let width: CGFloat = 440
}

struct OrdenDialogShell<Header: View, Content: View, Footer: View>: View {
    @ViewBuilder var header: () -> Header
    @ViewBuilder var content: () -> Content
    @ViewBuilder var footer: () -> Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header()
            Divider().opacity(0.35)
            content()
            Divider().opacity(0.35)
            footer()
        }
        .frame(width: OrdenDialogMetrics.width)
        .background(OrdenTheme.windowFill)
    }
}

struct OrdenDialogHeader: View {
    let systemImage: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(OrdenTheme.accent)
                .symbolRenderingMode(.hierarchical)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.weight(.semibold))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
    }
}

struct OrdenDialogSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
        }
    }
}

struct OrdenDialogHintBox: View {
    struct Row: Identifiable {
        let id = UUID()
        let icon: String
        let tint: Color
        let text: String
    }

    let rows: [Row]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(rows) { row in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: row.icon)
                        .font(.caption)
                        .foregroundStyle(row.tint)
                        .frame(width: 14)
                    Text(row.text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OrdenTheme.panelFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct OrdenDialogFooter: View {
    var shortcutHint: String? = nil
    let cancelTitle: String
    let actionTitle: String
    var actionDisabled: Bool = false
    let onCancel: () -> Void
    let onAction: () -> Void

    var body: some View {
        HStack {
            if let shortcutHint {
                Text(shortcutHint)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button(cancelTitle, action: onCancel)
                .keyboardShortcut(.cancelAction)
            Button(actionTitle, action: onAction)
                .buttonStyle(.borderedProminent)
                .tint(OrdenTheme.accent)
                .keyboardShortcut(.defaultAction)
                .disabled(actionDisabled)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

enum OrdenPathDisplay {
    static func short(_ path: String) -> String {
        path.replacingOccurrences(
            of: FileManager.default.homeDirectoryForCurrentUser.path,
            with: "~"
        )
    }
}
