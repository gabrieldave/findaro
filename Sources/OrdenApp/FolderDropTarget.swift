import SwiftUI
import UniformTypeIdentifiers
import OrdenCore

/// Drop estable sobre carpetas: hover local (sin republicar en cada frame → no parpadea).
struct FolderDropTargetModifier: ViewModifier {
    @EnvironmentObject private var browser: BrowserModel
    let entry: FileEntry

    @State private var localHover = false
    @State private var clearTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        Group {
            if entry.isDirectory {
                content
                    .onDrop(
                        of: [UTType.fileURL],
                        isTargeted: Binding(
                            get: { localHover },
                            set: { hovering in
                                applyHover(hovering)
                            }
                        )
                    ) { providers in
                        localHover = false
                        clearTask?.cancel()
                        browser.folderDropTargetPath = nil
                        return browser.handleDropIntoFolder(
                            providers: providers,
                            folderPath: entry.path
                        )
                    }
                    // Resaltado siempre presente (solo cambia color) → no rehace layout.
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(localHover ? Color.green.opacity(0.20) : Color.clear)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(
                                localHover ? Color.green : Color.clear,
                                lineWidth: localHover ? 3 : 0
                            )
                            .allowsHitTesting(false)
                    }
            } else {
                content
            }
        }
    }

    private func applyHover(_ hovering: Bool) {
        clearTask?.cancel()
        if hovering {
            localHover = true
            if browser.folderDropTargetPath != entry.path {
                browser.folderDropTargetPath = entry.path
            }
        } else {
            // Histeresis: evita el parpadeo típico de onDrop isTargeted.
            clearTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 120_000_000)
                guard !Task.isCancelled else { return }
                localHover = false
                if browser.folderDropTargetPath == entry.path {
                    browser.folderDropTargetPath = nil
                }
            }
        }
    }
}

extension View {
    func folderDropTarget(entry: FileEntry) -> some View {
        modifier(FolderDropTargetModifier(entry: entry))
    }
}
