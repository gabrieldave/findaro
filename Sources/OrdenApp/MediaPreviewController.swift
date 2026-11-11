import AppKit
import AVKit
import AVFoundation
import SwiftUI
import OrdenCore

/// Vista previa de vídeo **dentro** de la ventana Findaro.
/// Un NSWindow aparte quedaba off-screen en multi-monitor (LG + TYPEC);
/// el overlay SwiftUI siempre queda delante. No usamos `VideoPlayer` de SwiftUI
/// (abortaba al instanciar metadatos); envolvemos `AVPlayerView`.
@MainActor
final class MediaPreviewController: NSObject {
    static let shared = MediaPreviewController()

    private weak var browser: BrowserModel?

    var isVisible: Bool { browser?.mediaPreviewEntry != nil }
    var isOnScreen: Bool { isVisible }

    func bind(browser: BrowserModel) {
        self.browser = browser
    }

    func show(entry: FileEntry) {
        guard let browser else { return }
        browser.mediaPreviewEntry = entry
    }

    func hide() {
        browser?.mediaPreviewEntry = nil
    }

    func toggle(entry: FileEntry) {
        if isVisible { hide() } else { show(entry: entry) }
    }
}

// MARK: - AVPlayerView bridge (estable; evita crash de SwiftUI.VideoPlayer)

private struct FindaroAVPlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.videoGravity = .resizeAspect
        view.allowsPictureInPicturePlayback = false
        view.player = player
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
        nsView.videoGravity = .resizeAspect
    }

    static func dismantleNSView(_ nsView: AVPlayerView, coordinator: ()) {
        nsView.player?.pause()
        nsView.player = nil
    }
}

// MARK: - Overlay

struct InlineMediaPreviewOverlay: View {
    @EnvironmentObject private var browser: BrowserModel
    @State private var player: AVPlayer?
    /// nil = cargando · true = AVPlayer OK · false = códec no soportado (p. ej. VP9)
    @State private var playable: Bool?
    @State private var unsupportedHint: String = ""

    var body: some View {
        Group {
            if let entry = browser.mediaPreviewEntry {
                overlay(for: entry)
            }
        }
    }

    @ViewBuilder
    private func overlay(for entry: FileEntry) -> some View {
        ZStack {
            Color.black.opacity(0.78)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { MediaPreviewController.shared.hide() }

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text(entry.name)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Button {
                        QuickLookController.shared.navigate(delta: -1)
                    } label: {
                        Image(systemName: "chevron.left.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .buttonStyle(.plain)

                    Button {
                        QuickLookController.shared.navigate(delta: 1)
                    } label: {
                        Image(systemName: "chevron.right.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .buttonStyle(.plain)

                    Button {
                        MediaPreviewController.shared.hide()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)

                mediaBody(for: entry)
                    .frame(maxWidth: 980, maxHeight: 640)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
            }
            .frame(maxWidth: 1040)
        }
        .onAppear { attachPlayer(for: entry) }
        .onChange(of: entry.id) { _, _ in attachPlayer(for: entry) }
        .onDisappear { detachPlayer() }
        .onExitCommand { MediaPreviewController.shared.hide() }
    }

    @ViewBuilder
    private func mediaBody(for entry: FileEntry) -> some View {
        if entry.category == .video {
            switch playable {
            case .none:
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .some(false):
                unsupportedBody(for: entry)
            case .some(true):
                if let player {
                    FindaroAVPlayerView(player: player)
                } else {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        } else if let img = NSImage(contentsOfFile: entry.path) {
            Image(nsImage: img)
                .resizable()
                .scaledToFit()
        } else {
            Image(nsImage: NSWorkspace.shared.icon(forFile: entry.path))
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 160, maxHeight: 160)
        }
    }

    private func unsupportedBody(for entry: FileEntry) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "film.stack")
                .font(.system(size: 42, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))

            Text(L10n.s("Este formato no se puede previsualizar aquí", "This format can’t be previewed here"))
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text(
                unsupportedHint.isEmpty
                    ? L10n.s(
                        "macOS no reproduce este códec en Vista rápida. Ábrelo con tu reproductor (IINA, VLC u otro).",
                        "macOS can’t play this codec in Quick Look. Open it with your player (IINA, VLC, or another)."
                    )
                    : unsupportedHint
            )
            .font(.callout)
            .foregroundStyle(.white.opacity(0.75))
            .multilineTextAlignment(.center)
            .frame(maxWidth: 420)

            Button {
                openWithDefaultApp(path: entry.path)
            } label: {
                Text(L10n.s("Abrir con la app predeterminada", "Open with default app"))
                    .font(.body.weight(.semibold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(OrdenTheme.accent)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(28)
    }

    private func attachPlayer(for entry: FileEntry) {
        detachPlayer()
        playable = nil
        unsupportedHint = ""
        guard entry.category == .video else { return }

        let url = URL(fileURLWithPath: entry.path)
        let asset = AVURLAsset(url: url)
        Task { @MainActor in
            // Si el usuario ya cambió de archivo, no aplicar el resultado viejo.
            guard browser.mediaPreviewEntry?.id == entry.id else { return }
            do {
                let ok = try await asset.load(.isPlayable)
                guard browser.mediaPreviewEntry?.id == entry.id else { return }
                if ok {
                    playable = true
                    let p = AVPlayer(playerItem: AVPlayerItem(asset: asset))
                    player = p
                    p.play()
                } else {
                    playable = false
                    unsupportedHint = await Self.codecHint(for: asset)
                }
            } catch {
                guard browser.mediaPreviewEntry?.id == entry.id else { return }
                playable = false
                unsupportedHint = L10n.s(
                    "No se pudo leer el vídeo. Ábrelo con tu reproductor habitual.",
                    "Couldn’t read the video. Open it with your usual player."
                )
            }
        }
    }

    private func detachPlayer() {
        player?.pause()
        player = nil
        playable = nil
        unsupportedHint = ""
    }

    private func openWithDefaultApp(path: String) {
        let url = URL(fileURLWithPath: path)
        if NSWorkspace.shared.open(url) {
            MediaPreviewController.shared.hide()
        } else {
            browser.statusMessage = L10n.s(
                "No hay app predeterminada para este vídeo",
                "No default app for this video"
            )
        }
    }

    /// Texto corto según códec (VP9, etc.) sin amarrar a una app concreta.
    private static func codecHint(for asset: AVURLAsset) async -> String {
        let fallback = L10n.s(
            "Este códec (p. ej. VP9 de Instagram/TikTok) no lo reproduce macOS aquí. Usa IINA, VLC u otro reproductor.",
            "This codec (e.g. Instagram/TikTok VP9) isn’t playable here by macOS. Use IINA, VLC, or another player."
        )
        do {
            let tracks = try await asset.loadTracks(withMediaType: .video)
            for track in tracks {
                guard let descs = try? await track.load(.formatDescriptions) else { continue }
                for desc in descs {
                    let type = CMFormatDescriptionGetMediaSubType(desc)
                    let fourCC = String(
                        format: "%c%c%c%c",
                        (type >> 24) & 0xff,
                        (type >> 16) & 0xff,
                        (type >> 8) & 0xff,
                        type & 0xff
                    ).lowercased()
                    if fourCC == "vp09" || fourCC.contains("vp9") {
                        return L10n.s(
                            "Este vídeo es VP9 (típico de Instagram/TikTok). macOS no lo previsualiza; ábrelo con IINA, VLC u otro.",
                            "This video is VP9 (common from Instagram/TikTok). macOS can’t preview it — open with IINA, VLC, or another player."
                        )
                    }
                    if fourCC == "av01" {
                        return L10n.s(
                            "Este vídeo es AV1. macOS no lo previsualiza aquí; ábrelo con IINA, VLC u otro.",
                            "This video is AV1. macOS can’t preview it here — open with IINA, VLC, or another player."
                        )
                    }
                }
            }
        } catch {
            return fallback
        }
        return fallback
    }
}
