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
        // Fuerza capa de vídeo (en algunos monitores externos el layer nace vacío).
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
            if let player {
                FindaroAVPlayerView(player: player)
            } else {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private func attachPlayer(for entry: FileEntry) {
        detachPlayer()
        guard entry.category == .video else { return }
        let p = AVPlayer(url: URL(fileURLWithPath: entry.path))
        player = p
        p.play()
    }

    private func detachPlayer() {
        player?.pause()
        player = nil
    }
}
