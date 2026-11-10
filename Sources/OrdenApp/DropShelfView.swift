import SwiftUI
import AppKit
import UniformTypeIdentifiers
import OrdenCore

/// Bandeja estilo Dropover: aparcas archivos y los sueltas en otra carpeta.
struct DropShelfView: View {
    @EnvironmentObject private var browser: BrowserModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label(L10n.s("Bandeja", "Tray"), systemImage: "tray.and.arrow.down.fill")
                    .font(.system(.subheadline).weight(.semibold))
                    .foregroundStyle(OrdenTheme.accent)

                if browser.shelf.isEmpty {
                    Text(L10n.s("⌘C copia · ⌘X mueve · o arrastra aquí", "⌘C copy · ⌘X move · or drag here"))
                        .font(.caption)
                        .foregroundStyle(OrdenTheme.textSecondary)
                } else {
                    FindaroStatusPill(
                        title: L10n.s("\(browser.shelf.count) en bandeja", "\(browser.shelf.count) in tray"),
                        kind: .processing
                    )
                    Text(L10n.s("⌘V suelta aquí", "⌘V paste here"))
                        .font(.caption)
                        .foregroundStyle(OrdenTheme.textMuted)
                }

                Spacer()

                Button {
                    browser.addSelectionToShelf(intent: .copy)
                } label: {
                    Label(L10n.s("Copiar", "Copy"), systemImage: "doc.on.doc")
                }
                .controlSize(.small)
                .disabled(browser.selectedIDs.isEmpty)
                .help(L10n.s("Copiar a bandeja · ⌘C", "Copy to tray · ⌘C"))

                Button {
                    browser.addSelectionToShelf(intent: .move)
                } label: {
                    Label(L10n.s("Cortar", "Cut"), systemImage: "scissors")
                }
                .controlSize(.small)
                .disabled(browser.selectedIDs.isEmpty)
                .help(L10n.s("Cortar a bandeja · ⌘X", "Cut to tray · ⌘X"))

                Button {
                    browser.depositShelfHere()
                } label: {
                    Label(L10n.s("Soltar aquí", "Paste here"), systemImage: "arrow.down.doc")
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
                .help(L10n.s("Manda selección/bandeja a una burbuja de Dropover", "Send selection/tray to Dropover bubble"))

                Button(role: .destructive) {
                    browser.clearShelf()
                } label: {
                    Image(systemName: "trash")
                }
                .controlSize(.small)
                .disabled(browser.shelf.isEmpty)
            }

            if browser.shelf.isEmpty {
                RoundedRectangle(cornerRadius: OrdenTheme.radiusPanel, style: .continuous)
                    .strokeBorder(
                        browser.shelfDropTargeted ? OrdenTheme.accent : OrdenTheme.hairline,
                        style: StrokeStyle(lineWidth: browser.shelfDropTargeted ? 1.5 : 1, dash: [6, 4])
                    )
                    .background(
                        (browser.shelfDropTargeted ? OrdenTheme.accent.opacity(0.12) : Color.clear),
                        in: RoundedRectangle(cornerRadius: OrdenTheme.radiusPanel, style: .continuous)
                    )
                    .frame(height: 36)
                    .overlay {
                        Text(L10n.s("Suelta archivos · también a Dropover", "Drop files · also to Dropover"))
                            .font(.caption)
                            .foregroundStyle(OrdenTheme.textSecondary)
                    }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(browser.shelf) { item in
                            shelfChip(item)
                        }
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
        .onDrop(of: [UTType.fileURL], isTargeted: $browser.shelfDropTargeted) { providers in
            browser.importDroppedFiles(providers: providers)
        }
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
