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
                Label("Bandeja", systemImage: "tray.and.arrow.down.fill")
                    .font(.system(.subheadline).weight(.semibold))
                    .foregroundStyle(OrdenTheme.accent)

                if browser.shelf.isEmpty {
                    Text("⌘C copia · ⌘X mueve · o arrastra aquí")
                        .font(.caption)
                        .foregroundStyle(OrdenTheme.textSecondary)
                } else {
                    FindaroStatusPill(
                        title: "\(browser.shelf.count) en bandeja",
                        kind: .processing
                    )
                    Text("⌘V suelta aquí")
                        .font(.caption)
                        .foregroundStyle(OrdenTheme.textMuted)
                }

                Spacer()

                Button {
                    browser.addSelectionToShelf(intent: .copy)
                } label: {
                    Label("Copiar", systemImage: "doc.on.doc")
                }
                .controlSize(.small)
                .disabled(browser.selectedIDs.isEmpty)
                .help("⌘C")

                Button {
                    browser.addSelectionToShelf(intent: .move)
                } label: {
                    Label("Cortar", systemImage: "scissors")
                }
                .controlSize(.small)
                .disabled(browser.selectedIDs.isEmpty)
                .help("⌘X")

                Button {
                    browser.depositShelfHere()
                } label: {
                    Label("Soltar aquí", systemImage: "arrow.down.doc")
                }
                .buttonStyle(.borderedProminent)
                .tint(OrdenTheme.accent)
                .controlSize(.small)
                .disabled(browser.shelf.isEmpty)
                .help("⌘V — copia o mueve según cada ítem")

                Button {
                    browser.sendOutboundToDropover()
                } label: {
                    Label("Dropover", systemImage: "circle.dashed")
                }
                .controlSize(.small)
                .disabled(browser.outboundPaths.isEmpty)
                .help("Manda selección/bandeja a una burbuja de Dropover")

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
                        Text("Suelta archivos · también a Dropover")
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
            Text(item.intent == .move ? "mover" : "copiar")
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
            .help("Quitar de la bandeja")
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
