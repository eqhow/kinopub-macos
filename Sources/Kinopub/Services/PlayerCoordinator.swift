import Foundation
import SwiftUI

@MainActor
final class PlayerCoordinator: ObservableObject {
    @Published var request: PlayRequest?
    /// Идёт подготовка к воспроизведению (догрузка карточки, поиск ссылки,
    /// буферизация первых секунд за заставкой).
    @Published var preparing = false
    @Published var preparingTitle: String?
    /// Постер для фона на время подготовки.
    @Published var preparingPoster: URL?

    /// Момент старта заставки — чтобы удержать её минимальное время.
    private var launchStartedAt: Date?
    /// Ограничитель ожидания: если плеер так и не пошёл, всё равно убираем заставку.
    private var fallbackTask: Task<Void, Never>?
    private var readyTask: Task<Void, Never>?

    /// Начать кинематографичный запуск: постер, заставка, сворачивание меню.
    func beginLaunch(title: String, poster: URL?) {
        preparingTitle = title
        preparingPoster = poster
        launchStartedAt = Date()
        withAnimation(.easeInOut(duration: 0.5)) {
            preparing = true
        }
    }

    /// Запрос на воспроизведение готов — монтируем плеер (он ещё скрыт за заставкой).
    func open(_ request: PlayRequest) {
        withAnimation(.easeInOut(duration: 0.3)) {
            self.request = request
        }
        guard preparing else { return }
        // Страховка: если по каким-то причинам плеер не сообщит о готовности,
        // не держим заставку дольше ~10 секунд.
        fallbackTask?.cancel()
        fallbackTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard !Task.isCancelled else { return }
            self?.finishLaunch(animated: true)
        }
    }

    /// Плеер реально начал играть — плавно гасим заставку и показываем видео.
    /// Не раньше минимальной длительности, чтобы переход не мигал.
    func playerReady() {
        guard preparing, readyTask == nil else { return }
        readyTask = Task { @MainActor [weak self] in
            let minimum: TimeInterval = 0.9
            let elapsed = Date().timeIntervalSince(self?.launchStartedAt ?? Date())
            let delay = max(0, minimum - elapsed)
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            self?.finishLaunch(animated: true)
        }
    }

    /// Отменить запуск (например, не нашлась ссылка).
    func cancelLaunch() {
        fallbackTask?.cancel()
        finishLaunch(animated: true)
    }

    private func finishLaunch(animated: Bool) {
        fallbackTask?.cancel()
        readyTask?.cancel()
        fallbackTask = nil
        readyTask = nil
        launchStartedAt = nil
        let apply = {
            self.preparing = false
            self.preparingTitle = nil
            self.preparingPoster = nil
        }
        if animated {
            withAnimation(.easeInOut(duration: 0.6), apply)
        } else {
            apply()
        }
    }

    func close() {
        request = nil
    }
}
