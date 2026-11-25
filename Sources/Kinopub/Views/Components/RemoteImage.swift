import AppKit
import SwiftUI

/// Кэш картинок, чтобы постеры и логотипы не мигали при переходах.
final class ImageCache {
    static let shared = ImageCache()

    private let cache = NSCache<NSURL, NSImage>()

    private init() {
        cache.countLimit = 500
    }

    func image(for url: URL) -> NSImage? {
        cache.object(forKey: url as NSURL)
    }

    func insert(_ image: NSImage, for url: URL) {
        cache.setObject(image, forKey: url as NSURL)
    }
}

/// Картинка с плавным появлением и плейсхолдером на время загрузки.
struct RemoteImage<Placeholder: View>: View {
    let url: URL?
    var contentMode: ContentMode
    var onLoad: (() -> Void)?
    private let placeholder: () -> Placeholder

    @State private var image: NSImage?

    init(
        url: URL?,
        contentMode: ContentMode = .fill,
        onLoad: (() -> Void)? = nil,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.contentMode = contentMode
        self.onLoad = onLoad
        self.placeholder = placeholder
        _image = State(initialValue: url.flatMap { ImageCache.shared.image(for: $0) })
    }

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            } else {
                placeholder()
                    .transition(.opacity)
            }
        }
        .clipped()
        .animation(.easeOut(duration: 0.35), value: image != nil)
        .task(id: url) { await load() }
    }

    private func load() async {
        guard let url else { return }

        if let cached = ImageCache.shared.image(for: url) {
            image = cached
            onLoad?()
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let nsImage = NSImage(data: data) else { return }
            ImageCache.shared.insert(nsImage, for: url)
            image = nsImage
            onLoad?()
        } catch {
            // Оставляем плейсхолдер.
        }
    }
}

/// Мягкий shimmer для пустых постеров.
struct ShimmerPlaceholder: View {
    @State private var phase: CGFloat = -1.2

    var body: some View {
        GeometryReader { proxy in
            LinearGradient(
                colors: [
                    Color.gray.opacity(0.10),
                    Color.gray.opacity(0.22),
                    Color.gray.opacity(0.10),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: proxy.size.width * 2)
            .offset(x: phase * proxy.size.width)
        }
        .clipped()
        .onAppear {
            phase = -1.2
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                phase = 1.2
            }
        }
    }
}
