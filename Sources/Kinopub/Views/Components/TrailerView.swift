import AVFoundation
import SwiftUI

/// Фоновый трейлер в шапке: без звука, по кругу. Управляется кнопками
/// поверх кадра, поэтому нативный интерфейс плеера не показываем.
@MainActor
final class TrailerController: ObservableObject {
    let player = AVQueuePlayer()

    @Published var isMuted = true {
        didSet { applyAudio() }
    }

    private var looper: AVPlayerLooper?
    private var currentURL: URL?

    /// Включает/выключает звук. Дополнительно гарантирует ненулевую громкость
    /// и возобновление воспроизведения — иначе звук иногда не появляется,
    /// пока не «пощёлкаешь» кнопку.
    func setMuted(_ muted: Bool) {
        isMuted = muted
        applyAudio()
        if !muted { player.play() }
    }

    private func applyAudio() {
        player.volume = 1
        player.isMuted = isMuted
    }

    func play(_ url: URL) {
        if currentURL == url {
            applyAudio()
            player.play()
            return
        }

        stop()
        currentURL = url

        let template = AVPlayerItem(url: url)
        looper = AVPlayerLooper(player: player, templateItem: template)
        applyAudio()
        player.play()
    }

    func stop() {
        player.pause()
        player.removeAllItems()
        looper = nil
        currentURL = nil
    }
}

/// Слой AVPlayerLayer без контролов: вписывается в шапку как фон.
struct TrailerSurface: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.playerLayer.player = player
        return view
    }

    func updateNSView(_ view: PlayerLayerView, context: Context) {
        if view.playerLayer.player !== player {
            view.playerLayer.player = player
        }
    }
}

final class PlayerLayerView: NSView {
    let playerLayer = AVPlayerLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        playerLayer.videoGravity = .resizeAspectFill
        layer = CALayer()
        layer?.addSublayer(playerLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Не перехватываем события мыши — SwiftUI-кнопки поверх должны работать.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }
}
