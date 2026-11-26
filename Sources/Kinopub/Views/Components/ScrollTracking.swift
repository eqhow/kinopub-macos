import SwiftUI

/// Отслеживает вертикальный скролл и сообщает, ушёл ли контент за порог.
/// На macOS 15+ использует нативный `onScrollGeometryChange` (надёжно),
/// на 14 — тихо ничего не делает (там работает PreferenceKey-вариант
/// в самих экранах).
struct ScrollThresholdTracker: ViewModifier {
    let threshold: CGFloat
    let onChange: (Bool) -> Void

    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.onScrollGeometryChange(for: CGFloat.self) { geo in
                geo.contentOffset.y
            } action: { _, y in
                onChange(y > threshold)
            }
        } else {
            content
        }
    }
}
