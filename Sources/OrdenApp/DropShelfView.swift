import SwiftUI
import AppKit
import UniformTypeIdentifiers
import OrdenCore

/// Bandeja estilo Dropover: aparcas archivos y los sueltas en otra carpeta.
struct DropShelfView: View {
    @EnvironmentObject private var browser: BrowserModel

    private var isExpanded: Bool {
        !browser.shelf.isEmpty || browser.shelfDropTargeted
    }

    var body: some View {
        Group {
            if isExpanded {
                expandedBody
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                slimBody
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: OrdenTheme.motionStandard), value: isExpanded)
        .onDrop(of: [UTType.fileURL], isTargeted: $browser.shelfDropTargeted) { providers in
            browser.importDroppedFiles(providers: providers)
        }
    }

    /// Vacía: 28 pt, una línea, sin botones grises ni cajón punteado.
    private var slimBody: some View {
        HStack(spacing: 8) {
            Image(systemName: "tray.and.arrow.down")
                .foregroundStyle(OrdenTheme.accent)
            Text(L10n.s(
                "Bandeja lista · ⌘X corta · ⌘C copia · o suelta archivos aquí",
                "Tray ready · ⌘X cut · ⌘C copy · or drop files here"
            ))
            .font(.caption)
            .foregroundStyle(OrdenTheme.textSecondary)
            .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(OrdenTheme.panelFill.opacity(0.9), in: RoundedRectangle(cornerRadius: OrdenTheme.radiusPanel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: OrdenTheme.radiusPanel, style: .continuous)
                .strokeBorder(OrdenTheme.hairline, lineWidth: 1)
        )
    }

    private var expandedBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label(L10n.s("Bandeja", "Tray"), systemImage: "tray.and.arrow.down.fill")
                    .font(.system(.subheadline).weight(.semibold))
                    .foregroundStyle(OrdenTheme.accent)

                FindaroStatusPill(
                    title: L10n.s("\(browser.shelf.count) en bandeja", "\(browser.shelf.count) in tray"),
                    kind: .processing
                )

                Spacer()

                Button {
                    browser.depositShelfHere()
                } label: {
                    Label(L10n.s("Soltar aquí (⌘V)", "Paste here (⌘V)"), systemImage: "arrow.down.doc")
                }
                .buttonStyle(.borderedProminent)
                .tint(OrdenTheme.accent)
                .controlSize(.small)
                .disabled(browser.shelf.isEmpty)
                .help(L10n.s("⌘V — copia o mueve según cada ítem", "⌘V — copy or move per item intent"))

                Button {
                    browser.sendOutboundToDropover()
                } label: {
                    Label("Dropover", systemImage: "circle.dashed")
                }
                .controlSize(.small)
                .disabled(browser.outboundPaths.isEmpty)

                Button(role: .destructive) {
                    browser.clearShelf()
                } label: {
                    Image(systemName: "trash")
                }
                .controlSize(.small)
                .disabled(browser.shelf.isEmpty)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(browser.shelf) { item in
                        shelfChip(item)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(OrdenTheme.panelFill, in: RoundedRectangle(cornerRadius: OrdenTheme.radiusWindow, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: OrdenTheme.radiusWindow, style: .continuous)
                .strokeBorder(
                    browser.shelfDropTargeted ? OrdenTheme.accent.opacity(0.8) : OrdenTheme.hairline,
                    lineWidth: browser.shelfDropTargeted ? 2 : 1
                )
        )
    }

    private func shelfChip(_ item: FileOps.ShelfItem) -> some View {
        HStack(spacing: 6) {
            Image(systemName: item.intent == .move ? "arrow.right.doc.on.clipboard" : "doc.on.doc")
                .font(.caption2)
                .foregroundStyle(item.intent == .move ? OrdenTheme.warning : OrdenTheme.accent)
            Text(item.name)
                .font(.caption)
                .lineLimit(1)
            Text(item.intent == .move ? L10n.s("mover", "move") : L10n.s("copiar", "copy"))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(item.intent == .move ? OrdenTheme.warning : OrdenTheme.accent)
            Button {
                browser.removeFromShelf(item)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(OrdenTheme.textMuted)
            }
            .buttonStyle(.plain)
            .help(L10n.s("Quitar de la bandeja", "Remove from tray"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(OrdenTheme.elevatedFill, in: RoundedRectangle(cornerRadius: OrdenTheme.radiusChip, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: OrdenTheme.radiusChip, style: .continuous)
                .strokeBorder(
                    (item.intent == .move ? OrdenTheme.warning : OrdenTheme.accent).opacity(0.35),
                    lineWidth: 1
                )
        )
        .help(item.path)
        .onDrag {
            NSItemProvider(contentsOf: URL(fileURLWithPath: item.path)) ?? NSItemProvider()
        }
    }
}
