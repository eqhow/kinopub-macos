import AVKit
import SwiftUI

/// SwiftUI `VideoPlayer` на macOS падает в AVKit_SwiftUI,
/// поэтому используем нативный AppKit-плеер.
struct PlayerSurface: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .floating
        view.videoGravity = .resizeAspect
        view.showsFullScreenToggleButton = true
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player {
            view.player = player
        }
    }
}

struct PlayerWindowView: View {
    let request: PlayRequest
    @EnvironmentObject private var coordinator: PlayerCoordinator
    @State private var player = AVPlayer()
    @State private var chromeVisible = true
    @State private var hideWork: DispatchWorkItem?

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            PlayerSurface(player: player)
                .ignoresSafeArea()

            // Логотип по центру, чуть ниже верхней кромки + подпись серии.
            titleBlock
                .opacity(chromeVisible ? 1 : 0)
                .allowsHitTesting(chromeVisible)

            // Верхний ряд: закрыть справа. Появляется по движению мыши.
            controlsRow
                .opacity(chromeVisible ? 1 : 0)
                .allowsHitTesting(chromeVisible)
        }
        .background(MouseActivityCatcher { revealChrome() })
        .onAppear {
            beginPlayback()
            revealChrome()
        }
        .onDisappear {
            hideWork?.cancel()
            player.pause()
            player.replaceCurrentItem(with: nil)
        }
        .onExitCommand {
            close()
        }
    }

    /// Показывает элементы управления и прячет их через паузу бездействия —
    /// как в нативном плеере.
    private func revealChrome() {
        if !chromeVisible {
            withAnimation(.easeInOut(duration: 0.2)) { chromeVisible = true }
        }
        hideWork?.cancel()
        let work = DispatchWorkItem {
            withAnimation(.easeOut(duration: 0.12)) { chromeVisible = false }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: work)
    }

    // MARK: - Top bars

    private var controlsRow: some View {
        HStack {
            Spacer(minLength: 0)

            CloseCircleButton(action: close, icon: "xmark")
                .help("Закрыть")
        }
        .padding(.trailing, 22)
        .padding(.top, 12)
        .background(
            LinearGradient(
                colors: [.black.opacity(0.7), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var titleBlock: some View {
        VStack(spacing: 8) {
            logoOrTitle

            if let meta = metaText {
                Text(meta)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.white.opacity(0.78))
                    .lineLimit(1)
                    .shadow(color: .black.opacity(0.5), radius: 6, y: 2)
            }
        }
        .padding(.top, 58)
        .frame(maxWidth: .infinity)
    }

    /// «S1 · E8» + название серии, если есть.
    private var metaText: String? {
        var parts: [String] = []
        if let subtitle = request.subtitle, !subtitle.isEmpty { parts.append(subtitle) }
        if let episodeTitle = request.episodeTitle, !episodeTitle.isEmpty {
            parts.append(episodeTitle)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var logoOrTitle: some View {
        if let logo = request.logo {
            RemoteImage(url: logo, contentMode: .fit) {
                titleText
            }
            .frame(maxWidth: 250, maxHeight: 66, alignment: .center)
            .shadow(color: .black.opacity(0.55), radius: 8, y: 3)
        } else {
            titleText
        }
    }

    private var titleText: some View {
        Text(request.title)
            .font(.title2.weight(.bold))
            .foregroundColor(.white)
            .lineLimit(1)
            .shadow(color: .black.opacity(0.55), radius: 8, y: 3)
    }

    // MARK: - Playback

    private func beginPlayback() {
        player.replaceCurrentItem(with: AVPlayerItem(url: request.url))
        if let start = request.startAt, start > 1 {
            let time = CMTime(seconds: start, preferredTimescale: 600)
            player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                player.play()
            }
        } else {
            player.play()
        }
    }

    private func close() {
        player.pause()
        coordinator.close()
    }
}

/// Ловит движение мыши в окне плеера (даже поверх нативного AVPlayerView),
/// чтобы показывать элементы управления и прятать их по бездействию.
struct MouseActivityCatcher: NSViewRepresentable {
    var onActivity: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = CatcherView()
        view.onActivity = onActivity
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? CatcherView)?.onActivity = onActivity
    }

    final class CatcherView: NSView {
        var onActivity: (() -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil { install() } else { remove() }
        }

        // Не перехватываем клики — нативные контролы плеера должны работать.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        private func install() {
            remove()
            window?.acceptsMouseMovedEvents = true
            monitor = NSEvent.addLocalMonitorForEvents(
                matching: [.mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
            ) { [weak self] event in
                if event.window === self?.window {
                    self?.onActivity?()
                }
                return event
            }
        }

        private func remove() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}
