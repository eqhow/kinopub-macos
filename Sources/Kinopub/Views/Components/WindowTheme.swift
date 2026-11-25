import AppKit
import SwiftUI

/// Подкрашивает фон окна под текущую тему, убирает заголовок окна
/// и в полноэкранном режиме прячет тулбар/полосу сверху, чтобы видео
/// и контент шли от самого края.
struct WindowTheme: NSViewRepresentable {
    let color: Color?
    /// Плеер перекрывает окно — тогда фон нужен чёрный под видео.
    let blackedOut: Bool

    func makeNSView(context: Context) -> WindowConfigView {
        let view = WindowConfigView()
        view.color = color
        view.blackedOut = blackedOut
        return view
    }

    func updateNSView(_ view: WindowConfigView, context: Context) {
        view.color = color
        view.blackedOut = blackedOut
        view.apply()
    }
}

final class WindowConfigView: NSView {
    var color: Color?
    var blackedOut = false
    private var observers: [NSObjectProtocol] = []

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()

        guard let window else { return }
        for name in [NSWindow.didEnterFullScreenNotification,
                     NSWindow.didExitFullScreenNotification] {
            let token = NotificationCenter.default.addObserver(
                forName: name, object: window, queue: .main
            ) { [weak self] _ in
                // Даём окну обновить styleMask, затем применяем.
                DispatchQueue.main.async { self?.apply() }
            }
            observers.append(token)
        }
        apply()
    }

    func apply() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }

            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.title = ""
            window.styleMask.insert(.fullSizeContentView)
            // Единый компактный тулбар: «светофоры» и кнопка сайдбара
            // не меняют размер при переходе в деталку.
            window.toolbarStyle = .unifiedCompact

            let isFullScreen = window.styleMask.contains(.fullScreen)
            // В полноэкране полоса тулбара — артефакт. В остальных случаях
            // тулбар оставляем видимым (в т.ч. в плеере), чтобы «светофоры»
            // стояли на том же месте, что и на всех экранах.
            window.toolbar?.isVisible = !isFullScreen

            if self.blackedOut {
                // Под видео — чёрный фон, чтобы не было светлой полосы.
                window.backgroundColor = .black
            } else if let color = self.color,
                      let tint = NSColor(color).usingColorSpace(.sRGB),
                      let base = NSColor.windowBackgroundColor.usingColorSpace(.sRGB) {
                window.backgroundColor = base.blended(withFraction: 0.22, of: tint) ?? base
            } else {
                window.backgroundColor = .windowBackgroundColor
            }
        }
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }
}
