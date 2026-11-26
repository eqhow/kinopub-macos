import Foundation
import AVFoundation
import Combine

/// Не даёт дисплею засыпать и включать заставку, пока видео реально
/// воспроизводится. На паузе/остановке сразу отпускает — чтобы мак
/// мог спать, если просмотр поставлен на паузу.
final class SleepBlocker {
    private var activity: NSObjectProtocol?
    private var cancellable: AnyCancellable?

    /// Подписаться на состояние плеера.
    func attach(to player: AVPlayer) {
        detach()
        cancellable = player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self else { return }
                if status == .playing {
                    self.prevent()
                } else {
                    self.allow()
                }
            }
    }

    func detach() {
        cancellable?.cancel()
        cancellable = nil
        allow()
    }

    private func prevent() {
        guard activity == nil else { return }
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.idleDisplaySleepDisabled, .idleSystemSleepDisabled, .userInitiated],
            reason: "Воспроизведение видео в Kinopub"
        )
    }

    private func allow() {
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
    }
}
