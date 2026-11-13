import AppKit
import SwiftUI
import OrdenCore

@MainActor
public final class AboutWindowController: NSWindowController {
    public static let shared = AboutWindowController()

    public static func show() {
        shared.present()
    }

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 490),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.isReleasedWhenClosed = false
        window.title = L10n.s("Acerca de Findaro", "About Findaro")
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        super.init(window: window)
        window.contentView = NSHostingView(rootView: AboutView(controller: self))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func present() {
        guard let window = self.window else { return }
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct AboutView: View {
    weak var controller: AboutWindowController?
    @StateObject private var licenseStore = LicenseStore.shared
    @State private var copiedNotice = false

    private var versionString: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.165"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "157"
        return "\(v) (\(b))"
    }

    private var chipString: String {
        HardwareIdentity.chipModel
    }

    private var macOSString: String {
        HardwareIdentity.macOSVersionString
    }

    private var modelString: String {
        HardwareIdentity.modelIdentifier
    }

    private var memoryString: String {
        "\(HardwareIdentity.physicalMemoryGigabytes) GB"
    }

    private var licenseStatusString: String {
        switch licenseStore.state {
        case .proActive(_, let tier, let seats, _):
            return L10n.s("Licencia de por vida activa (\(tier.capitalized), \(seats) Mac)", "Lifetime License Active (\(tier.capitalized), \(seats) Mac)")
        case .trial(let daysRemaining, _):
            return L10n.s("Prueba gratuita activa (\(daysRemaining) días restantes)", "Free Trial Active (\(daysRemaining) days left)")
        case .trialExpired:
            return L10n.s("Prueba finalizada (modo lectura)", "Trial Expired (Read-only)")
        case .revoked(let message):
            return L10n.s("Licencia revocada: \(message)", "License Revoked: \(message)")
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 80)
                    .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 3)
            } else {
                Image(systemName: "folder.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 64, height: 64)
                    .foregroundStyle(OrdenTheme.accent)
            }

            VStack(spacing: 4) {
                Text("FINDARO")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(L10n.s("Tus archivos, bajo control.", "Your files, under control."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(L10n.s("Versión \(versionString)", "Version \(versionString)"))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }

            VStack(spacing: 8) {
                diagnosticRow(icon: "cpu", label: L10n.s("Procesador", "Processor"), value: chipString)
                diagnosticRow(icon: "laptopcomputer", label: L10n.s("Equipo", "Model"), value: "\(modelString) · \(memoryString)")
                diagnosticRow(icon: "applelogo", label: "macOS", value: macOSString)
                diagnosticRow(icon: "checkmark.seal.fill", label: "Developer ID", value: "David DEL RIO COLIN (YH6W55MP95)", tint: .green)
                diagnosticRow(icon: "key.fill", label: L10n.s("Licencia", "License"), value: licenseStatusString, tint: licenseStore.state.isUsable ? .green : .orange)
            }
            .padding(12)
            .background(OrdenTheme.elevatedFill.opacity(0.55), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(OrdenTheme.hairline, lineWidth: 1)
            )

            HStack(spacing: 10) {
                Button {
                    copyDiagnostics()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: copiedNotice ? "checkmark" : "doc.on.doc")
                            .foregroundStyle(copiedNotice ? Color.green : Color.primary)
                        Text(copiedNotice ? L10n.s("¡Copiado!", "Copied!") : L10n.s("Copiar diagnóstico de soporte", "Copy Support Diagnostics"))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Button(L10n.s("Cerrar", "Close")) {
                    controller?.window?.close()
                }
                .buttonStyle(.borderedProminent)
                .tint(OrdenTheme.accent)
                .controlSize(.regular)
            }
            .padding(.top, 4)
        }
        .padding(24)
        .frame(width: 440)
    }

    private func diagnosticRow(icon: String, label: String, value: String, tint: Color = .secondary) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 18)
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.caption.monospaced())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func copyDiagnostics() {
        let text = """
        Findaro Support Diagnostics
        ---------------------------
        App Version: \(versionString)
        Hardware Chip: \(chipString)
        Model Identifier: \(modelString)
        Physical Memory: \(memoryString)
        macOS Version: \(macOSString)
        Code Signature: Developer ID Application: David DEL RIO COLIN (YH6W55MP95)
        License State: \(licenseStatusString)
        Timestamp: \(ISO8601DateFormatter().string(from: Date()))
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copiedNotice = true
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            copiedNotice = false
        }
    }
}
