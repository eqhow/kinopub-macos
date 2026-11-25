import SwiftUI

/// Реестр кадров карточек в координатах окна. Нужен только для стартовой
/// точки перелёта обложки, поэтому хранится вне SwiftUI-состояния.
final class FrameRegistry {
    static let shared = FrameRegistry()

    private var frames: [String: CGRect] = [:]
    private let lock = NSLock()

    private init() {}

    func set(_ frame: CGRect, for id: String) {
        lock.lock()
        frames[id] = frame
        lock.unlock()
    }

    func frame(for id: String) -> CGRect? {
        lock.lock()
        defer { lock.unlock() }
        return frames[id]
    }
}

/// Ссылка на деталку. Карточка не масштабируется при нажатии:
/// её обложка отдельным слоем перелетает в шапку страницы.
struct ItemLink<Content: View>: View {
    let item: KinopubItem
    let sourceID: String
    /// Картинка, которая полетит. Для hero — широкий кадр, для карточек — постер.
    var artwork: URL? = nil
    private let content: () -> Content

    @EnvironmentObject private var navigation: DetailNavigation

    init(
        item: KinopubItem,
        sourceID: String,
        artwork: URL? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.item = item
        self.sourceID = sourceID
        self.artwork = artwork
        self.content = content
    }

    var body: some View {
        Button {
            let start = FrameRegistry.shared.frame(for: sourceID)
                ?? FrameRegistry.shared.frame(for: linkFrameID)
            navigation.open(item, sourceID: sourceID, from: start, artwork: artwork)
        } label: {
            content()
                .frameProbe(linkFrameID)
        }
        .buttonStyle(.plain)
    }

    private var linkFrameID: String { "link-\(sourceID)" }
}

// MARK: - Frame probe

/// Пишет кадр вида в реестр при изменении геометрии. Состояние SwiftUI
/// не трогает, поэтому прокрутка и анимации не перерисовываются лишний раз.
struct FrameProbeModifier: ViewModifier {
    let id: String

    func body(content: Content) -> some View {
        content.background {
            GeometryReader { geo in
                Color.clear
                    .onAppear {
                        FrameRegistry.shared.set(geo.frame(in: .global), for: id)
                    }
                    .onChange(of: geo.frame(in: .global)) { _, frame in
                        FrameRegistry.shared.set(frame, for: id)
                    }
            }
        }
    }
}

extension View {
    func frameProbe(_ id: String) -> some View {
        modifier(FrameProbeModifier(id: id))
    }
}
