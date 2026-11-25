import SwiftUI

struct HomeView: View {
    @EnvironmentObject var api: APIClient
    @State private var continueEntries: [HistoryEntry] = []
    @State private var hotMovies: [KinopubItem] = []
    @State private var hotSeries: [KinopubItem] = []
    @State private var popular: [KinopubItem] = []
    @State private var fresh: [KinopubItem] = []
    @State private var loading = true
    /// Доминирующий цвет текущего слайда — им подсвечивается низ hero и
    /// первая секция, чтобы стык был не резным, а «светящимся».
    @State private var heroGlow: Color = .clear

    var body: some View {
        Group {
            if loading {
                ProgressView()
                    .scaleEffect(1.5)
                    .frame(maxWidth: .infinity, minHeight: 420)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if !hotMovies.isEmpty {
                            HeroSlider(items: Array(hotMovies.prefix(5)), glow: $heroGlow)
                        }

                        VStack(alignment: .leading, spacing: 28) {
                            if !continueEntries.isEmpty {
                                ContinueWatchingRow(entries: continueEntries)
                            }
                            if hotMovies.count > 5 {
                                PosterRow(title: "Горячие фильмы", items: Array(hotMovies.dropFirst(5)))
                            }
                            if !hotSeries.isEmpty {
                                PosterRow(title: "Горячие сериалы", items: hotSeries)
                            }
                            if !popular.isEmpty {
                                PosterRow(title: "Популярное", items: popular)
                            }
                            if !fresh.isEmpty {
                                PosterRow(title: "Новинки", items: fresh)
                            }
                        }
                        .padding(24)
                        // Мягкое цветное свечение снизу hero, перетекающее
                        // в первую секцию: верх прозрачный (совпадает с фоном
                        // под hero), ниже — цветное пятно, затем снова фон.
                        .background(alignment: .top) {
                            heroGlowBackdrop
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .ignoresSafeArea(.container, edges: .top)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .task { await load() }
    }

    /// Цветное свечение под hero: прозрачно в самой верхней точке (стык с
    /// hero, чтобы не было шва), плавно разгорается чуть ниже и гаснет.
    private var heroGlowBackdrop: some View {
        LinearGradient(
            stops: [
                .init(color: heroGlow.opacity(0.0), location: 0.0),
                .init(color: heroGlow.opacity(0.10), location: 0.12),
                .init(color: heroGlow.opacity(0.05), location: 0.30),
                .init(color: heroGlow.opacity(0.0), location: 0.55),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 620)
        .blur(radius: 34)
        .allowsHitTesting(false)
    }

    func load() async {
        loading = true
        do {
            async let hm = api.hotMovies()
            async let hs = api.hotSeries()
            async let pm = api.popularMovies()
            async let fm = api.freshMovies()
            async let hist = api.history()
            let results = try await (hm, hs, pm, fm, hist)
            hotMovies = results.0
            hotSeries = results.1
            popular = results.2
            fresh = results.3
            let allEntries = results.4
            continueEntries = Array(allEntries
                .dedupedByItem()
                .filter { $0.isInProgress }
                .prefix(10))
        } catch {
            // Пустые ряды лучше показывать, чем вечный спиннер.
        }
        loading = false
    }
}

// MARK: - Hero slider

/// Слайдер главной: Ken Burns backdrop, трейлер, автопрокрутка.
struct HeroSlider: View {
    let items: [KinopubItem]
    /// Доминирующий цвет текущего кадра — наружу для фонового свечения.
    @Binding var glow: Color

    @State private var index = 0
    @StateObject private var trailer = TrailerController()
    @State private var showTrailer = false
    @State private var kenBurns = false
    @State private var artwork: MetadataService.Artwork?
    @State private var infoVisible = true
    @State private var progress: CGFloat = 0
    @State private var previous: KinopubItem?
    @State private var previousArtwork: MetadataService.Artwork?
    @State private var reveal: CGFloat = 1
    /// С какой стороны раскрывается новый постер: вперёд — справа,
    /// назад — слева (анимация идёт слева направо).
    @State private var revealAnchor: UnitPoint = .trailing

    @EnvironmentObject private var player: PlayerCoordinator
    @EnvironmentObject private var api: APIClient

    private var current: KinopubItem? {
        guard items.indices.contains(index) else { return items.first }
        return items[index]
    }

    var body: some View {
        baseScene
            .frame(maxWidth: .infinity)
            .frame(height: 440)
            .overlay(alignment: .bottom) { gradientLayer }
            // Низ кадра уходит в прозрачность — под ним ровно фон страницы,
            // поэтому границы не видно. Контент/кнопки ниже маски, не гаснут.
            .mask(bottomRevealMask)
            .overlay(alignment: .bottomLeading) { contentLayer }
            .overlay(alignment: .topTrailing) { trailerControlsLayer }
            .overlay(alignment: .bottomTrailing) { dots }
            .clipped()
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 30)
                    .onEnded { value in
                        guard items.count > 1 else { return }
                        if value.translation.width < -30 { advance() }
                        else if value.translation.width > 30 { retreat() }
                    }
            )
            .onChange(of: index) { _, _ in
                stopTrailer()
            }
            .onAppear {
                kenBurns = true
            }
            // Свайпы на трекпаде (горизонтальная прокрутка) листают слайды.
            .background {
                TrackpadSwipeCatcher { direction in
                    guard items.count > 1 else { return }
                    if direction > 0 { advance() } else { retreat() }
                }
            }
            .task(id: "artwork-\(index)") {
                guard let item = current else { return }
                let art = await MetadataService.shared.artwork(for: item)
                artwork = art
                // Цвет свечения считаем по тому же кадру, что и задник,
                // и плавно перекрашиваем при смене слайда.
                if let url = art?.backdrop ?? item.widePoster,
                   let color = await ArtworkPalette.shared.color(for: url) {
                    withAnimation(.easeInOut(duration: 0.7)) { glow = color }
                }
            }
            // Один цикл на слайд: определяем наличие трейлера, задаём время
            // показа (с трейлером — 30 с, без него — 12 с), запускаем видео
            // и по истечении срока сменяем слайд.
            .task(id: "cycle-\(index)") {
                guard let item = current else { return }
                // В списках API трейлер приходит только относительным путём,
                // поэтому догружаем полную карточку ради абсолютной ссылки.
                let full = try? await api.item(id: item.id)
                guard !Task.isCancelled else { return }
                let trailerURL = full?.trailerURL ?? item.trailerURL
                let duration: Double = trailerURL == nil ? 12 : 30
                startProgress(duration: duration)

                if let trailerURL {
                    // Даём фону появиться, затем запускаем трейлер.
                    try? await Task.sleep(nanoseconds: 4_000_000_000)
                    guard !Task.isCancelled else { return }
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    guard !Task.isCancelled else { return }
                    startTrailer(url: trailerURL)
                    let remaining = max(0.5, duration - 4.3)
                    try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
                } else {
                    try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                }
                guard !Task.isCancelled else { return }
                go(to: (index + 1) % items.count)
            }
    }

    // MARK: - Layers

    private var baseScene: some View {
        ZStack {
            // Старый постер остаётся снизу, пока его полностью не перекроют.
            if let previous {
                backdrop(for: previous, artwork: previousArtwork)
            }

            if let cur = current {
                ZStack {
                    backdrop(for: cur, artwork: artwork)

                    TrailerSurface(player: trailer.player)
                        .opacity(showTrailer ? 1 : 0)
                        .animation(.easeInOut(duration: 0.7), value: showTrailer)
                }
                // Новый постер раскрывается от края: вперёд — справа налево,
                // назад — слева направо.
                .mask(
                    Rectangle().scaleEffect(x: max(0.0001, reveal), anchor: revealAnchor)
                )
            }
        }
    }

    @ViewBuilder
    private func backdrop(for item: KinopubItem, artwork: MetadataService.Artwork?) -> some View {
        RemoteImage(url: artwork?.backdrop ?? item.widePoster) {
            LinearGradient(
                colors: [Color.gray.opacity(0.22), Color.gray.opacity(0.10)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scaleEffect(kenBurns ? 1.06 : 1)
        .animation(.easeInOut(duration: 18).repeatForever(autoreverses: true), value: kenBurns)
    }

    private var gradientLayer: some View {
        LinearGradient(
            colors: [.black.opacity(0.0), .black.opacity(0.35), .black.opacity(0.88)],
            startPoint: .center,
            endPoint: .bottom
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    /// Маска растворения низа кадра в фон страницы.
    private var bottomRevealMask: some View {
        LinearGradient(
            stops: [
                .init(color: .white, location: 0.0),
                .init(color: .white, location: 0.68),
                .init(color: .white.opacity(0.9), location: 0.80),
                .init(color: .clear, location: 0.97),
                .init(color: .clear, location: 1.0),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var contentLayer: some View {
        ZStack(alignment: .bottomLeading) {
            ForEach(items) { item in
                if item.id == current?.id {
                    VStack(alignment: .leading, spacing: 12) {
                        logoOrTitle(for: item)
                        metaRow(for: item)
                        if let plot = item.plot, !plot.isEmpty {
                            Text(plot)
                                .font(.callout)
                                .foregroundColor(.white.opacity(0.75))
                                .lineLimit(2)
                                .frame(maxWidth: 620, alignment: .leading)
                        }
                        HStack(spacing: 12) {
                            Button {
                                playNow(item)
                            } label: {
                                Label("Смотреть", systemImage: "play.fill")
                                    .font(.headline)
                                    .padding(.horizontal, 22)
                                    .padding(.vertical, 11)
                                    .background(.white, in: Capsule())
                                    .foregroundColor(.black)
                            }
                            .buttonStyle(.plain)

                            ItemLink(
                                item: item,
                                sourceID: "hero-\(item.id)",
                                artwork: artwork?.backdrop ?? item.widePoster
                            ) {
                                Label("Подробнее", systemImage: "info.circle")
                                    .font(.headline)
                                    .padding(.horizontal, 22)
                                    .padding(.vertical, 11)
                                    .background(.white.opacity(0.2), in: Capsule())
                                    .foregroundColor(.white)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.top, 6)
                    }
                    .multilineTextAlignment(.leading)
                    .transition(.opacity)
                }
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 32)
        // Низ кнопок выровнен по низу точек-пунктов слайдера справа.
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(infoVisible ? 1 : 0)
    }

    @ViewBuilder
    private var trailerControlsLayer: some View {
        if showTrailer {
            HStack(spacing: 10) {
                Button {
                    trailer.isMuted.toggle()
                } label: {
                    heroIcon(trailer.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                }
                Button(action: openTrailerFullscreen) {
                    heroIcon("arrow.up.left.and.arrow.down.right")
                }
            }
            .buttonStyle(.plain)
            .padding(.trailing, 22)
            .padding(.top, 12)
            .transition(.opacity)
        }
    }

    private var dots: some View {
        HStack(spacing: 7) {
            ForEach(items.indices, id: \.self) { i in
                if i == index {
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.white.opacity(0.30))
                            .frame(width: 26, height: 6)
                        Capsule()
                            .fill(.white)
                            .frame(width: max(0, 26 * progress), height: 6)
                    }
                    .frame(width: 26, height: 6)
                    .contentShape(Rectangle().inset(by: -7))
                    .onTapGesture { go(to: i, forward: true) }
                } else {
                    Capsule()
                        .fill(.white.opacity(0.4))
                        .frame(width: 6, height: 6)
                        .contentShape(Rectangle().inset(by: -7))
                        .onTapGesture { go(to: i, forward: i > index) }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.black.opacity(0.28), in: Capsule())
        .padding(20)
    }

    private func advance() {
        guard items.count > 1 else { return }
        go(to: (index + 1) % items.count, forward: true)
    }

    private func retreat() {
        guard items.count > 1 else { return }
        go(to: (index - 1 + items.count) % items.count, forward: false)
    }

    /// Плавная смена слайда: инфо гаснет, новый постер раскрывается поверх
    /// старого с нужной стороны, затем инфо проявляется заново.
    private func go(to newIndex: Int, forward: Bool = true) {
        guard newIndex != index, items.indices.contains(newIndex) else { return }

        let oldItem = current
        let oldArtwork = artwork

        withAnimation(.easeInOut(duration: 0.30)) { infoVisible = false }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
            // Старый постер держим снизу на всё время раскрытия.
            previous = oldItem
            previousArtwork = oldArtwork

            // Направляем раскрытие: вперёд — от правого края, назад — от левого.
            revealAnchor = forward ? .trailing : .leading

            // Переключаем слайд со скрытой маской…
            reveal = 0
            index = newIndex
            artwork = nil // обложку нового слайда подгрузим заново

            // …и на следующем тике раскрываем его с выбранной стороны.
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.7)) { reveal = 1 }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.72) {
                previous = nil
                previousArtwork = nil
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                withAnimation(.easeInOut(duration: 0.5)) { infoVisible = true }
            }
        }
    }

    /// Индикатор времени до следующей смены слайда.
    private func startProgress(duration: Double = 30) {
        progress = 0
        withAnimation(.linear(duration: duration)) { progress = 1 }
    }

    // MARK: - Content helpers

    @ViewBuilder
    private func logoOrTitle(for item: KinopubItem) -> some View {
        if let logo = artwork?.logo {
            RemoteImage(url: logo, contentMode: .fit) {
                Text(item.russianTitle)
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .shadow(color: .black.opacity(0.5), radius: 10, y: 4)
            }
            .frame(maxWidth: 360, maxHeight: 120, alignment: .leading)
            .shadow(color: .black.opacity(0.5), radius: 10, y: 4)
        } else {
            Text(item.russianTitle)
                .font(.system(size: 36, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(2)
                .shadow(color: .black.opacity(0.5), radius: 10, y: 4)
                .frame(maxWidth: 360, maxHeight: 120, alignment: .leading)
        }
    }

    private func metaRow(for item: KinopubItem) -> some View {
        HStack(spacing: 14) {
            if let year = item.year {
                Text(verbatim: String(year))
            }
            if let rating = item.rating {
                HStack(spacing: 3) {
                    Image(systemName: "star.fill").foregroundColor(.yellow)
                    Text(String(format: "%.1f", rating))
                }
            }
            if item.is4K {
                Text("4K")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 4))
            }
        }
        .font(.subheadline.weight(.medium))
        .foregroundColor(.white.opacity(0.9))
    }

    // MARK: - Direct Play

    private func playNow(_ item: KinopubItem) {
        Task {
            let full = try? await api.item(id: item.id)
            guard !Task.isCancelled else { return }
            let url: URL?
            if full?.isSeries == true, let episode = full?.seasons?.first?.episodes?.first {
                url = episode.files?.first?.bestURL
            } else {
                url = full?.videos?.first?.files?.first?.bestURL
            }
            guard let url else { return }
            await MainActor.run {
                stopTrailer()
                player.open(PlayRequest(
                    id: item.id,
                    title: item.russianTitle,
                    url: url,
                    logo: artwork?.logo,
                    subtitle: item.year.map(String.init) ?? ""
                ))
            }
        }
    }

    // MARK: - Trailer

    private func startTrailer(url: URL) {
        trailer.play(url)
        withAnimation(.easeInOut(duration: 0.7)) {
            showTrailer = true
        }
    }

    private func stopTrailer() {
        withAnimation(.easeInOut(duration: 0.35)) {
            showTrailer = false
        }
        trailer.stop()
    }

    private func openTrailerFullscreen() {
        guard let item = current else { return }
        // Полную карточку уже подгружаем ради абсолютной ссылки.
        Task {
            let full = try? await api.item(id: item.id)
            guard let url = full?.trailerURL ?? item.trailerURL else { return }
            await MainActor.run {
                stopTrailer()
                if let window = NSApp.keyWindow, !window.styleMask.contains(.fullScreen) {
                    window.toggleFullScreen(nil)
                }
                player.open(PlayRequest(id: item.id, title: item.russianTitle, url: url, logo: artwork?.logo, subtitle: "Трейлер"))
            }
        }
    }

    private func heroIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 34, height: 34)
            .background(.black.opacity(0.38), in: Circle())
            .overlay {
                Circle().strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
            }
    }
}

// MARK: - Rows

struct PosterRow: View {
    let title: String
    let items: [KinopubItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title2.weight(.bold))
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(items) { item in
                        let sourceID = "row-\(title)-\(item.id)"
                        ItemLink(item: item, sourceID: sourceID) {
                            PosterCard(item: item, frameID: sourceID)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

struct PosterCard: View {
    let item: KinopubItem
    let frameID: String

    /// Единый размер постера во всём приложении — и в сетках, и в рядах.
    static let width: CGFloat = 160
    static let height: CGFloat = 240

    @State private var hover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            poster
                .frame(width: Self.width, height: Self.height)

            Text(item.russianTitle)
                .font(.caption.weight(.medium))
                .lineLimit(2)
                .frame(width: Self.width, alignment: .leading)

            HStack(spacing: 4) {
                if let year = item.year {
                    Text(verbatim: String(year)).font(.caption2).foregroundColor(.secondary)
                }
                if let rating = item.rating {
                    Text("•").foregroundColor(.secondary)
                    Image(systemName: "star.fill")
                        .font(.system(size: 8))
                        .foregroundColor(.yellow)
                    Text(String(format: "%.1f", rating))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: Self.width, alignment: .leading)
        }
        .frame(width: Self.width, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var poster: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.gray.opacity(0.12))

            RemoteImage(url: item.bestPoster) {
                ShimmerPlaceholder()
            }

            if hover {
                Color.black.opacity(0.28)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .frameProbe(frameID)
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.white.opacity(hover ? 0.25 : 0), lineWidth: 1)
        }
        .shadow(color: .black.opacity(hover ? 0.35 : 0), radius: 12, y: 6)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.18), value: hover)
    }
}

