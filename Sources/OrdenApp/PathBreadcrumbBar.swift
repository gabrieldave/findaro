import SwiftUI
import OrdenCore

/// Breadcrumbs clicables + chip para editar ruta (Ir a…).
struct PathBreadcrumbBar: View {
    @EnvironmentObject private var browser: BrowserModel

    var body: some View {
        HStack(spacing: 2) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(Array(browser.pathSegments.enumerated()), id: \.offset) { index, segment in
                        if index > 0 {
                            Image(systemName: "chevron.forward")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        Button {
                            browser.navigate(to: segment.path)
                        } label: {
                            Text(segment.title)
                                .font(.system(.callout, design: .rounded))
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(index == browser.pathSegments.count - 1 ? .primary : .secondary)
                        .help(segment.path)
                    }
                }
            }
            .frame(maxWidth: 360)

            Button {
                browser.promptGoToFolder()
            } label: {
                Image(systemName: "pencil.and.list.clipboard")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderless)
            .help("Ir a carpeta… (⇧⌘G)")
        }
    }
}
