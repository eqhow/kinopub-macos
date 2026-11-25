import AppKit
import SwiftUI

/// Ловит горизонтальные свайпы на трекпаде (двухпальцевую прокрутку)
/// в пределах своего кадра и превращает их в листание слайдов.
/// Клики не перехватывает: это фоновый слой, а события ловятся монитором.
struct TrackpadSwipeCatcher: NSViewRepresentable {
    /// `+1` — следующий слайд, `-1` — предыдущий.
    let onSwipe: (Int) -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onSwipe = onSwipe
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.onSwipe = onSwipe
    }

    final class CatcherView: NSView {
        var onSwipe: ((Int) -> Void)?
        private var monitor: Any?
        private var accumulated: CGFloat = 0
        private var lockedUntil: Date = .distantPast

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil { install() } else { remove() }
        }

        private func install() {
            remove()
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak self] event in
                guard let self,
                      let window = self.window,
                      event.window === window else { return event }

                let point = self.convert(event.locationInWindow, from: nil)
                guard self.bounds.contains(point) else { return event }

                let dx = event.scrollingDeltaX
                let dy = event.scrollingDeltaY
                // Горизонтальное движение важнее вертикального — иначе это
                // обычная прокрутка страницы.
                guard abs(dx) > abs(dy) else { return event }

                // Один свайп — один шаг: гасим хвост события/инерцию.
                guard Date() >= self.lockedUntil else { return nil }

                self.accumulated += dx
                let threshold: CGFloat = 40
                if self.accumulated <= -threshold {
                    self.accumulated = 0
                    self.lockedUntil = Date().addingTimeInterval(0.9)
                    self.onSwipe?(1)   // свайп влево — вперёд
                    return nil
                } else if self.accumulated >= threshold {
                    self.accumulated = 0
                    self.lockedUntil = Date().addingTimeInterval(0.9)
                    self.onSwipe?(-1)  // свайп вправо — назад
                    return nil
                }
                return nil
            }
        }

        private func remove() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        deinit { remove() }
    }
}
