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
                Text(L10n.s("Papelera", "Trash"))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                Text(
                    browser.errorMessage == nil
                        ? (browser.entries.isEmpty
                            ? L10n.s("Vacía", "Empty")
                            : (L10n.isEnglish
                                ? "\(browser.entries.count) item(s) · selection → Delete permanently"
                                : "\(browser.entries.count) elemento(s) · selección → Eliminar para siempre"))
                        : L10n.s("Activa Acceso completo al disco para listar aquí", "Enable Full Disk Access to list here")
                )
                .font(.caption)
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(2)
            }

            Spacer(minLength: 8)

            if !browser.selectedIDs.isEmpty && browser.errorMessage == nil {
                HStack(spacing: 4) {
                    Button {
                        browser.restoreSelectionFromTrash()
                    } label: {
                        Label(L10n.s("Restaurar", "Restore"), systemImage: "arrow.uturn.backward.circle.fill")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
                    .foregroundStyle(Color(findaroHex: "#0F766E"))
                    .help(L10n.s("Restaura los archivos seleccionados fuera de la Papelera (atajo ⌥⌘⌫)", "Restores selected files out of Trash (shortcut ⌥⌘⌫)"))

                    Menu {
                        if browser.dualPaneEnabled && !TrashOps.isTrashPath(browser.secondaryPath) {
                            Button {
                                browser.restoreSelectionFromTrash(targetDirectory: browser.secondaryPath)
                            } label: {
                                Label(L10n.s("Sacar al panel destino (\(URL(fileURLWithPath: browser.secondaryPath).lastPathComponent))", "Move to Destination pane (\(URL(fileURLWithPath: browser.secondaryPath).lastPathComponent))"), systemImage: "rectangle.split.2x1")
                            }
                        }
                        Button {
                            let desktop = (FileManager.default.homeDirectoryForCurrentUser.path as NSString).appendingPathComponent("Desktop")
                            browser.restoreSelectionFromTrash(targetDirectory: desktop)
                        } label: {
                            Label(L10n.s("Sacar al Escritorio", "Move to Desktop"), systemImage: "menubar.dock.rectangle")
                        }
                        Button {
                            browser.restoreSelectionFromTrash(targetDirectory: GlobalHotKey.defaultDownloadsPath())
                        } label: {
                            Label(L10n.s("Sacar a Descargas", "Move to Downloads"), systemImage: "arrow.down.circle")
                        }
                        Divider()
                        Button {
                            browser.restoreSelectionFromTrashPromptFolder()
                        } label: {
                            Label(L10n.s("Elegir otra carpeta…", "Choose another folder…"), systemImage: "folder.badge.plus")
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.bold))
                    }
                    .menuStyle(.borderlessButton)
                    .buttonStyle(.bordered)
                    .tint(.white)
                    .help(L10n.s("Elegir dónde restaurar la selección", "Choose where to restore selection"))
                }
            }

            Button {
                browser.permanentlyDeleteSelection(confirm: true)
            } label: {
                Label(L10n.s("Eliminar para siempre", "Delete Permanently"), systemImage: "xmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .foregroundStyle(OrdenTheme.danger)
            .disabled(browser.selectedIDs.isEmpty || browser.errorMessage != nil)
            .help(L10n.s("Borra de verdad lo seleccionado (no se puede recuperar)", "Permanently deletes selected items (cannot be recovered)"))

            Button {
                browser.emptyTrash(confirm: true)
            } label: {
                Label(L10n.s("Vaciar Papelera", "Empty Trash"), systemImage: "trash.slash.fill")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .tint(.white)
            .help(L10n.s("Elimina todo lo de la Papelera", "Deletes everything in Trash"))

            if browser.errorMessage != nil {
                Button {
                    browser.openFullDiskAccessSettings()
                } label: {
                    Label(L10n.s("Dar acceso", "Grant Access"), systemImage: "lock.open.fill")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .help(L10n.s("Ajustes → Privacidad → Acceso completo al disco → Findaro", "Settings → Privacy → Full Disk Access → Findaro"))
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

            Text(L10n.s("Papelera bloqueada", "Trash Access Blocked"))
                .font(.title2.weight(.semibold))

            Text(
                errorText.localizedCaseInsensitiveContains("autoriz")
                    || errorText.localizedCaseInsensitiveContains("permission")
                    || errorText.localizedCaseInsensitiveContains("no tienes")
                    || errorText.localizedCaseInsensitiveContains("couldn't be opened")
                    ? L10n.s(
                        "macOS no deja a Findaro ver la Papelera sin Acceso completo al disco. Actívalo, reinicia Findaro y vuelve a tocar Basurero.",
                        "macOS requires Full Disk Access for Findaro to view Trash contents. Enable it in System Settings, restart Findaro, and reopen Trash."
                    )
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
                    Label(L10n.s("Abrir Acceso completo al disco", "Open Full Disk Access"), systemImage: "lock.open")
                }
                .buttonStyle(.borderedProminent)
                .tint(OrdenTheme.accent)

                Button {
                    browser.emptyTrash(confirm: true)
                } label: {
                    Label(L10n.s("Vaciar Papelera", "Empty Trash"), systemImage: "trash.slash")
                }
                .buttonStyle(.bordered)

                Button {
                    browser.reloadFromUser()
                } label: {
                    Label(L10n.s("Reintentar", "Retry"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .background(OrdenTheme.panelFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
