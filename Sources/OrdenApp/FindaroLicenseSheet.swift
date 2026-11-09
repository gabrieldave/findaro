import SwiftUI
import OrdenCore

public struct FindaroLicenseSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var licenseStore = LicenseStore.shared

    @State private var licenseKeyInput: String = ""
    @State private var activationError: String?

    public init() {}

    private var isRevoked: Bool {
        if case .revoked = licenseStore.state { return true }
        return false
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 12) {
                Image(systemName: isRevoked ? "lock.shield.fill" : "clock.badge.exclamationmark")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(isRevoked ? Color.red : Color.orange)

                Text(isRevoked
                     ? L10n.s("Licencia revocada", "License Revoked")
                     : L10n.s("Período de prueba finalizado", "Free Trial Expired"))
                    .font(.title2.weight(.bold))

                Text(isRevoked
                     ? L10n.s("Esta licencia ha sido revocada o desactivada. Adquiere una nueva licencia para reactivar las operaciones de escritura.", "This license has been revoked or deactivated. Purchase a new license to restore write operations.")
                     : L10n.s("Tu período de prueba de 5 días ha terminado. Las funciones de escritura (mover, copiar, renombrar, borrar, Smart Merge y bandeja) requieren una licencia Pro.", "Your 5-day trial has ended. Write operations (move, copy, rename, delete, Smart Merge and tray) require a Pro license."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            .padding(.top, 28)
            .padding(.bottom, 20)

            Divider()

            // Actions & Activation Form
            VStack(spacing: 20) {
                // CTA de Compra
                VStack(spacing: 8) {
                    Button {
                        if let url = URL(string: "https://findaro.iareal.net/comprar") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "cart.fill")
                            Text(L10n.s("Comprar licencia Pro ($39 USD · 2 Macs)", "Purchase Pro License ($39 USD · 2 Macs)"))
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(Color.accentColor)

                    Text(L10n.s("Pago único de por vida · Sin suscripción · Soporte y actualizaciones", "One-time lifetime payment · No subscription · Updates included"))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                // Separador "o activa una clave"
                HStack {
                    VStack { Divider() }
                    Text(L10n.s("o activa tu clave existente", "or activate existing key"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    VStack { Divider() }
                }

                // Formulario de activación
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        TextField("FINDARO-XXXX-XXXX-XXXX-XXXX", text: $licenseKeyInput)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .textCase(.uppercase)
                            .disabled(licenseStore.isBusy)
                            .onSubmit {
                                performActivation()
                            }

                        Button(L10n.s("Activar", "Activate")) {
                            performActivation()
                        }
                        .buttonStyle(.bordered)
                        .disabled(licenseKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || licenseStore.isBusy)
                    }

                    if licenseStore.isBusy {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text(L10n.s("Verificando con el servidor…", "Verifying with server…"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let err = activationError ?? licenseStore.lastErrorMessage {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(Color.red)
                    }
                }
            }
            .padding(24)

            Divider()

            // Footer
            HStack {
                Text(L10n.s("Modo de solo lectura activo", "Read-only mode active"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button(L10n.s("Continuar en solo lectura", "Continue in Read-Only")) {
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 480)
        .fixedSize(horizontal: true, vertical: true)
    }

    private func performActivation() {
        let key = licenseKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        activationError = nil

        Task {
            do {
                try await licenseStore.activate(key: key)
                dismiss()
            } catch {
                activationError = error.localizedDescription
            }
        }
    }
}
