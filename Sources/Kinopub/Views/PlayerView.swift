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
        // Полноэкранную кнопку AVKit убираем: он открывает видео отдельным
        // окном, из-за чего пропадают наши оверлеи (название, эпизод, крестик).
        // Фуллскрин делаем через окно приложения — оверлеи остаются видимы.
        view.showsFullScreenToggleButton = false
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
    @EnvironmentObject private var api: APIClient
    @State private var player = AVPlayer()
    @State private var chromeVisible = true
    @State private var hideWork: DispatchWorkItem?
    @State private var markTimer: Timer?
    @State private var sleepBlocker = SleepBlocker()
    @State private var isFullScreen = false

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
            startMarkTimer()
            sleepBlocker.attach(to: player)
            isFullScreen = NSApp.keyWindow?.styleMask.contains(.fullScreen) ?? false
        }
        .onDisappear {
            hideWork?.cancel()
            markTimer?.invalidate()
            sleepBlocker.detach()
            sendFinalMark()
            player.pause()
            player.replaceCurrentItem(with: nil)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
            isFullScreen = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
            isFullScreen = false
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
        HStack(spacing: 10) {
            Spacer(minLength: 0)

            Button(action: toggleFullScreen) {
                playerChromeIcon(isFullScreen
                    ? "arrow.down.right.and.arrow.up.left"
                    : "arrow.up.left.and.arrow.down.right")
            }
            .buttonStyle(.plain)
            .help(isFullScreen ? "Выйти из полноэкранного" : "На весь экран")

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

    private func playerChromeIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 34, height: 34)
            .background(.black.opacity(0.38), in: Circle())
            .overlay {
                Circle().strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
            }
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

    private func toggleFullScreen() {
        (NSApp.keyWindow ?? NSApp.mainWindow)?.toggleFullScreen(nil)
    }

    private func close() {
        player.pause()
        markTimer?.invalidate()
        sendFinalMark()
        // Если смотрели на весь экран — вернуть окно в обычный режим,
        // чтобы после закрытия плеера не остаться в полноэкранном приложении.
        if let window = NSApp.keyWindow, window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
        }
        coordinator.close()
    }

    // MARK: - Watch progress sync

    /// Запускает таймер, отправляющий прогресс каждые 15 секунд.
    private func startMarkTimer() {
        markTimer?.invalidate()
        markTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [self] _ in
            self.sendMark()
        }
    }

    /// Отправляет текущую позицию на сервер.
    private func sendMark() {
        let time = Int(player.currentTime().seconds)
        guard time > 0 else { return }
        let id = request.itemID ?? request.id
        let video = request.video
        let season = request.season
        Task {
            try? await api.markWatch(id: id, time: time, video: video, season: season)
        }
    }

    /// Финальная отметка при закрытии (последняя секунда, с плеера уже остановленного).
    private func sendFinalMark() {
        let time = Int(player.currentTime().seconds)
        guard time > 0 else { return }
        let id = request.itemID ?? request.id
        let video = request.video
        let season = request.season
        Task {
            try? await api.markWatch(id: id, time: time, video: video, season: season)
        }
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
