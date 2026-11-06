import SwiftUI
import AppKit
import UniformTypeIdentifiers
import OrdenCore

/// Bandeja estilo Dropover: aparcas archivos y los sueltas en otra carpeta.
struct DropShelfView: View {
    @EnvironmentObject private var browser: BrowserModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Bandeja", systemImage: "tray.and.arrow.down.fill")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(OrdenTheme.accent)

                Text(
                    browser.shelf.isEmpty
                        ? "⌘C copia · ⌘X mueve · o arrastra aquí"
                        : "\(browser.shelf.count) en bandeja · ⌘V suelta aquí"
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)

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

                Button(role: .destructive) {
                    browser.clearShelf()
                } label: {
                    Image(systemName: "trash")
                }
                .controlSize(.small)
                .disabled(browser.shelf.isEmpty)
            }

            if browser.shelf.isEmpty {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        browser.shelfDropTargeted ? OrdenTheme.accent : .secondary.opacity(0.35),
                        style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                    )
                    .background(
                        (browser.shelfDropTargeted ? OrdenTheme.accent.opacity(0.12) : Color.clear),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .frame(height: 36)
                    .overlay {
                        Text("Suelta archivos · también a Dropover")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
        .padding(.vertical, 8)
        .background(OrdenTheme.panelFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    browser.shelfDropTargeted ? OrdenTheme.accent.opacity(0.8) : .white.opacity(0.06),
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
            Text(item.name)
                .font(.caption)
                .lineLimit(1)
            Text(item.intent == .move ? "mover" : "copiar")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(item.intent == .move ? .orange : OrdenTheme.accent)
            Button {
                browser.removeFromShelf(item)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            (item.intent == .move ? Color.orange : OrdenTheme.accent).opacity(0.18),
            in: Capsule()
        )
        .help(item.path)
        .onDrag {
            NSItemProvider(contentsOf: URL(fileURLWithPath: item.path)) ?? NSItemProvider()
        }
    }
}
