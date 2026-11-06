import SwiftUI
import AppKit
import OrdenCore

/// Feedback visual del hold 1s → listo para arrastrar/mover.
enum FileDragArmChrome {
    static let holdDuration: TimeInterval = 1.0
    /// Mientras armas, un temblor mayor cancela el hold (no el marquee del padre).
    static let maxWiggle: CGFloat = 14

    /// Anillo de carga mientras mantienes pulsado + badge cuando ya está armado.
    struct Overlay: View {
        @EnvironmentObject private var browser: BrowserModel
        let path: String
        var size: CGFloat = 28

        private var isArming: Bool {
            browser.isFileDragArming(path: path)
        }

        private var isArmed: Bool {
            browser.isFileDragArmed(path: path)
        }

        var body: some View {
            ZStack {
                if isArming {
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 3)
                        .frame(width: size, height: size)
                    Circle()
                        .trim(from: 0, to: max(0.06, browser.fileDragArmProgress))
                        .stroke(Color.orange, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: size, height: size)
                }

                if isArmed {
                    Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                        .font(.system(size: size * 0.42, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(Color.orange, in: Circle())
                        .shadow(color: .orange.opacity(0.55), radius: 6, y: 1)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .allowsHitTesting(false)
        }
    }

    /// Borde/fondo de fila o celda cuando está armando o armada.
    struct Highlight: ViewModifier {
        @EnvironmentObject private var browser: BrowserModel
        let path: String

        private var isArming: Bool { browser.isFileDragArming(path: path) }
        private var isArmed: Bool { browser.isFileDragArmed(path: path) }
        private var armedCount: Int { browser.fileDragArmedPaths.count }
        private var armingCount: Int { browser.fileDragArmingPaths.count }

        func body(content: Content) -> some View {
            content
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            isArmed ? Color.orange : (isArming ? Color.orange.opacity(0.7) : .clear),
                            lineWidth: isArmed ? 2.5 : (isArming ? 2 : 0)
                        )
                }
                .overlay(alignment: .trailing) {
                    if isArmed {
                        Label(
                            armedCount > 1 ? "Listo · \(armedCount)" : "Listo · arrastra",
                            systemImage: "hand.draw.fill"
                        )
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .foregroundStyle(.white)
                            .background(Color.orange, in: Capsule())
                            .padding(.trailing, 40)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    } else if isArming {
                        Text(armingCount > 1 ? "Mantén… (\(armingCount))" : "Mantén…")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .foregroundStyle(.orange)
                            .background(Color.orange.opacity(0.15), in: Capsule())
                            .padding(.trailing, 40)
                    }
                }
                .animation(.spring(response: 0.28, dampingFraction: 0.8), value: isArmed)
                .animation(.easeOut(duration: 0.12), value: isArming)
        }
    }

    /// Banner grande arriba del explorador.
    struct ReadyBanner: View {
        @EnvironmentObject private var browser: BrowserModel

        var body: some View {
            if browser.hasArmedFileDrag {
                HStack(spacing: 10) {
                    Image(systemName: "hand.draw.fill")
                        .font(.title3.weight(.bold))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(
                            browser.fileDragArmedPaths.count == 1
                                ? "Listo para mover"
                                : "\(browser.fileDragArmedPaths.count) listos para mover"
                        )
                        .font(.subheadline.weight(.bold))
                        Text(
                            browser.fileDragArmedPaths.count == 1
                                ? "Sin soltar, arrastra a otra carpeta"
                                : "Sin soltar, arrástralos juntos a una carpeta"
                        )
                            .font(.caption)
                            .opacity(0.9)
                    }
                    Spacer(minLength: 0)
                    Button("Cancelar") {
                        browser.clearArmedFileDrag()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.white)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.orange.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: .orange.opacity(0.35), radius: 10, y: 2)
                .padding(.horizontal, 16)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
}

/// Hold sobre la fila: progreso 0→1 y arma el drag sin pelearse del todo con el marquee.
private struct FileDragArmPressModifier: ViewModifier {
    @EnvironmentObject private var browser: BrowserModel
    let entry: FileEntry

    @State private var pressOrigin: CGPoint?
    @State private var armedThisPress = false

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { value in
                    if pressOrigin == nil {
                        pressOrigin = value.startLocation
                        armedThisPress = false
                        // Gesto de la fila: dueño del armado (carpetas y archivos).
                        browser.beginArmingFileDrag(for: entry)
                    }

                    let dist = hypot(value.translation.width, value.translation.height)
                    // Más tolerancia en carpetas: el icono/nombre tiembla más al hacer hold.
                    let limit = entry.isDirectory
                        ? FileDragArmChrome.maxWiggle * 1.6
                        : FileDragArmChrome.maxWiggle
                    if dist > limit, !browser.hasArmedFileDrag {
                        // Temblor grande antes de armar → cancela hold (el padre hará marquee).
                        browser.endArmingPress(for: entry)
                        pressOrigin = nil
                        return
                    }
                    if browser.hasArmedFileDrag {
                        armedThisPress = true
                    }
                }
                .onEnded { _ in
                    // Si aún no armó, suelta = clic normal (solo selección).
                    if !browser.hasArmedFileDrag {
                        browser.endArmingPress(for: entry)
                    } else {
                        // Ya armado: limpia anillo pero deja el estado "listo" unos segundos.
                        browser.endArmingPress(for: entry)
                    }
                    pressOrigin = nil
                    armedThisPress = false
                }
        )
    }
}

extension View {
    func fileDragArmHighlight(path: String) -> some View {
        modifier(FileDragArmChrome.Highlight(path: path))
    }

    func fileDragArmPress(entry: FileEntry, browser: BrowserModel) -> some View {
        modifier(FileDragArmPressModifier(entry: entry))
            .environmentObject(browser)
    }
}
