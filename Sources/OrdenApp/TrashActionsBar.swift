import SwiftUI
import OrdenCore
import AppKit

/// Barra superior al estar dentro de la Papelera: eliminar para siempre / vaciar.
struct TrashActionsBar: View {
    @EnvironmentObject private var browser: BrowserModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "trash.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 2) {
                Text("Papelera")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                Text(
                    browser.errorMessage == nil
                        ? (browser.entries.isEmpty
                            ? "Vacía"
                            : "\(browser.entries.count) elemento(s) · selección → Eliminar para siempre")
                        : "Activa Acceso completo al disco para listar aquí"
                )
                .font(.caption)
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(2)
            }

            Spacer(minLength: 8)

            if !browser.selectedIDs.isEmpty && browser.errorMessage == nil {
                Menu {
                    if browser.dualPaneEnabled && !TrashOps.isTrashPath(browser.secondaryPath) {
                        Button {
                            browser.restoreSelectionFromTrash(targetDirectory: browser.secondaryPath)
                        } label: {
                            Label("Sacar al panel destino (\(URL(fileURLWithPath: browser.secondaryPath).lastPathComponent))", systemImage: "rectangle.split.2x1")
                        }
                    }
                    Button {
                        let desktop = (FileManager.default.homeDirectoryForCurrentUser.path as NSString).appendingPathComponent("Desktop")
                        browser.restoreSelectionFromTrash(targetDirectory: desktop)
                    } label: {
                        Label("Sacar al Escritorio", systemImage: "menubar.dock.rectangle")
                    }
                    Button {
                        browser.restoreSelectionFromTrash(targetDirectory: GlobalHotKey.defaultDownloadsPath())
                    } label: {
                        Label("Sacar a Descargas", systemImage: "arrow.down.circle")
                    }
                    Divider()
                    Button {
                        browser.restoreSelectionFromTrashPromptFolder()
                    } label: {
                        Label("Elegir otra carpeta…", systemImage: "folder.badge.plus")
                    }
                } label: {
                    Label("Sacar de la Papelera", systemImage: "arrow.uturn.backward.circle.fill")
                        .font(.subheadline.weight(.semibold))
                } primaryAction: {
                    browser.restoreSelectionFromTrash()
                }
                .menuStyle(.borderlessButton)
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(Color(findaroHex: "#1E3A8A"))
                .help("Saca los archivos seleccionados de la Papelera y los restaura")
            }

            Button {
                browser.permanentlyDeleteSelection(confirm: true)
            } label: {
                Label("Eliminar para siempre", systemImage: "xmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .foregroundStyle(OrdenTheme.danger)
            .disabled(browser.selectedIDs.isEmpty || browser.errorMessage != nil)
            .help("Borra de verdad lo seleccionado (no se puede recuperar)")

            Button {
                browser.emptyTrash(confirm: true)
            } label: {
                Label("Vaciar Papelera", systemImage: "trash.slash.fill")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .tint(.white)
            .help("Elimina todo lo de la Papelera")

            if browser.errorMessage != nil {
                Button {
                    browser.openFullDiskAccessSettings()
                } label: {
                    Label("Dar acceso", systemImage: "lock.open.fill")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .help("Ajustes → Privacidad → Acceso completo al disco → Findaro")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [OrdenTheme.danger, OrdenTheme.danger.opacity(0.82)],
                startPoint: .leading,
                endPoint: .trailing
            ),
            in: RoundedRectangle(cornerRadius: OrdenTheme.radiusPanel, style: .continuous)
        )
    }
}

/// Estado vacío / sin permiso al abrir la Papelera.
struct TrashPermissionUnavailable: View {
    @EnvironmentObject private var browser: BrowserModel
    let errorText: String

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "trash.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(OrdenTheme.danger.opacity(0.9))

            Text("Papelera bloqueada")
                .font(.title2.weight(.semibold))

            Text(
                errorText.localizedCaseInsensitiveContains("autoriz")
                    || errorText.localizedCaseInsensitiveContains("permission")
                    || errorText.localizedCaseInsensitiveContains("no tienes")
                    || errorText.localizedCaseInsensitiveContains("couldn't be opened")
                    ? "macOS no deja a Findaro ver la Papelera sin Acceso completo al disco. Actívalo, reinicia Findaro y vuelve a tocar Basurero."
                    : errorText
            )
            .font(.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 420)

            HStack(spacing: 12) {
                Button {
                    browser.openFullDiskAccessSettings()
                } label: {
                    Label("Abrir Acceso completo al disco", systemImage: "lock.open")
                }
                .buttonStyle(.borderedProminent)
                .tint(OrdenTheme.accent)

                Button {
                    browser.emptyTrash(confirm: true)
                } label: {
                    Label("Vaciar Papelera", systemImage: "trash.slash")
                }
                .buttonStyle(.bordered)

                Button {
                    browser.reloadFromUser()
                } label: {
                    Label("Reintentar", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .background(OrdenTheme.panelFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
