import SwiftUI

struct DetailView: View {
    let nodeID: UUID
    let route: ItemRoute
    let isTop: Bool
    let onBack: () -> Void

    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var player: PlayerCoordinator
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var navigation: DetailNavigation

    @State private var fullItem: KinopubItem?
    @State private var itemLoaded = false
    @State private var similar: [KinopubItem] = []
    @State private var artwork: MetadataService.Artwork?
    @State private var seasonNumber = 1
    @State private var tint: Color = .accentColor
    @State private var cast: [Actor] = []
    @State private var castLoading = true
    @State private var selectedActor: Actor?
    @StateObject private var trailer = TrailerController()
    @State private var showTrailer = false
    @State private var heroHovering = false
    @State private var kenBurns = false
    /// Полноэкранный режим — в нём у окна нет строки заголовка, поэтому
    /// кнопку «Назад» не надо поднимать (см. `backButtonTopOffset`).
    @State private var isFullScreen = false

    private let heroHeight: CGFloat = 470
    /// Высота строки заголовка окна, на которую корневой ZStack деталки
    /// в оконном режиме опускает содержимое. На полном экране её нет.
    private let windowedTitleBarHeight: CGFloat = 37.5

    private var item: KinopubItem { route.item }
    private var info: KinopubItem { fullItem ?? item }
    private var seasons: [Season] { info.seasons ?? [] }

    private var episodes: [Season.Episode] {
        seasons.first(where: { $0.number == seasonNumber })?.episodes ?? []
    }

    private var primaryURL: URL? {
        if info.isSeries, let episode = episodes.first {
            return episode.files?.first?.bestURL
        }
        return info.videos?.first?.files?.first?.bestURL
    }

    private var colorSource: URL? {
        artwork?.backdrop ?? info.widePoster
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(NSColor.windowBackgroundColor)
                .ignoresSafeArea()

            backgroundWash

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header

                    VStack(alignment: .leading, spacing: 24) {
                        actions
                        plot
                        credits
                        episodesSection
                        castSection
                        similarSection
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 6)
                    .padding(.bottom, 28)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .scrollContentBackground(.hidden)
            .ignoresSafeArea(.container, edges: .top)

            // Кнопка «Назад» — вне ScrollView, на уровне корневого ZStack,
            // чтобы safe area macOS рассчитывался корректно в окне и на полном
            // экране, без смещения под строку заголовка.
            backButton
                .zIndex(5)

            if let actor = selectedActor {
                ActorProfileView(
                    actor: actor,
                    tint: tint,
                    currentIMDb: PeopleService.shared.imdbID(for: info.imdb),
                    onBack: {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            selectedActor = nil
                        }
                    },
                    onSelectItem: { selected in
                        openFromActor(selected)
                    }
                )
                .transition(.opacity)
                .zIndex(10)
            }
        }
        .tint(tint)
        .animation(.easeInOut(duration: 0.9), value: tint)
        .task(id: item.id) { await load() }
        .task(id: colorSource) { await loadTint() }
        .task(id: info.trailerURL) { await autoPlayTrailer() }
        .onAppear {
            kenBurns = true
            isFullScreen = NSApp.keyWindow?.styleMask.contains(.fullScreen) ?? false
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
            isFullScreen = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
            isFullScreen = false
        }
        .onDisappear {
            trailer.stop()
            theme.remove(nodeID)
        }
        .onChange(of: isTop) { _, top in
            if !top, showTrailer {
                stopTrailer()
            }
        }
        .onExitCommand {
            if selectedActor != nil {
                withAnimation(.easeInOut(duration: 0.22)) {
                    selectedActor = nil
                }
            } else if isTop {
                onBack()
            }
        }
    }

    // MARK: - Background

    private var backgroundWash: some View {
        ZStack(alignment: .top) {
            Color(NSColor.windowBackgroundColor)
            LinearGradient(
                colors: [tint.opacity(0.40), tint.opacity(0.15), tint.opacity(0.05)],
                startPoint: .top,
                endPoint: .bottom
            )
            // Мягкое цветное свечение у верха — hero растворяется в него,
            // а не в плоскую подложку, поэтому стык не режет глаз.
            RadialGradient(
                colors: [tint.opacity(0.14), tint.opacity(0.0)],
                center: .top,
                startRadius: 0,
                endRadius: 560
            )
            .blur(radius: 36)
            .opacity(showTrailer ? 0 : 1)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.35), value: showTrailer)
    }

    // MARK: - Header

    private var header: some View {
        heroBackdrop
            .frame(maxWidth: .infinity)
            .frame(height: heroHeight)
            // Низ кадра растворяется в прозрачность — под ним проступает
            // цветная подложка страницы, поэтому жёсткой кромки нет.
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .white, location: 0.0),
                        .init(color: .white, location: 0.66),
                        .init(color: .clear, location: 0.95),
                        .init(color: .clear, location: 1.0),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(alignment: .bottom) {
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0), location: 0.30),
                        .init(color: .black.opacity(0.28), location: 0.62),
                        .init(color: .black.opacity(0.52), location: 0.82),
                        .init(color: .black.opacity(0.28), location: 0.92),
                        .init(color: .clear, location: 1.0),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)
                .opacity(!showTrailer ? 1 : 0)
                .animation(.easeInOut(duration: 0.35), value: showTrailer)
            }
            .overlay(alignment: .bottomLeading) { heroContent }
            .overlay(alignment: .topTrailing) { trailerControls }
            .clipped()
            .onHover { heroHovering = $0 }
    }

    private var heroBackdrop: some View {
        ZStack {
            RemoteImage(url: artwork?.backdrop ?? info.widePoster) {
                LinearGradient(
                    colors: [Color.gray.opacity(0.25), Color.gray.opacity(0.12)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scaleEffect(kenBurns ? 1.06 : 1)
            .animation(.easeInOut(duration: 18).repeatForever(autoreverses: true), value: kenBurns)

            TrailerSurface(player: trailer.player)
                .opacity(showTrailer ? 1 : 0)
                .animation(.easeInOut(duration: 0.7), value: showTrailer)
        }
        .allowsHitTesting(false)
    }

    private var heroContent: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                logoOrTitle
                metaRow
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private var trailerControls: some View {
        HStack(spacing: 10) {
            Button {
                trailer.setMuted(!trailer.isMuted)
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
        // Показываем только при наведении курсора на трейлер.
        .opacity(showTrailer && heroHovering ? 1 : 0)
        .allowsHitTesting(showTrailer && heroHovering)
        .animation(.easeInOut(duration: 0.2), value: showTrailer)
        .animation(.easeInOut(duration: 0.2), value: heroHovering)
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

    @ViewBuilder
    private var logoOrTitle: some View {
        if let logo = artwork?.logo {
            RemoteImage(url: logo, contentMode: .fit) {
                titleText
            }
            .frame(maxWidth: 380, maxHeight: 130, alignment: .leading)
            .shadow(color: .black.opacity(0.55), radius: 10, y: 4)
        } else {
            titleText
                .frame(maxWidth: 380, maxHeight: 130, alignment: .leading)
        }
    }

    private var titleText: some View {
        Text(item.russianTitle)
            .font(.system(size: 40, weight: .bold))
            .foregroundColor(.white)
            .lineLimit(2)
            .shadow(color: .black.opacity(0.55), radius: 10, y: 4)
    }

    private var metaRow: some View {
        HStack(spacing: 14) {
            if let year = info.year {
                Text(verbatim: String(year))
            }
            if let rating = info.rating {
                HStack(spacing: 3) {
                    Image(systemName: "star.fill").foregroundColor(.yellow)
                    Text(String(format: "%.1f", rating))
                }
            }
            if info.is4K {
                Text("4K")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 4))
            }
            if info.isSeries {
                Text("Сериал")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 4))
            }
        }
        .font(.subheadline.weight(.medium))
        .foregroundColor(.white.opacity(0.9))
    }

    private var backButton: some View {
        CloseCircleButton(action: onBack, label: item.russianTitle)
            .padding(.top, 12)
            .padding(.leading, 18)
            .offset(y: isFullScreen ? 0 : -windowedTitleBarHeight)
    }

    // MARK: - Sections

    private var actions: some View {
        HStack(spacing: 14) {
            PlayButton(action: playPrimary, tint: tint)

            if info.trailerURL != nil {
                SecondaryButton(
                    action: toggleTrailer,
                    label: showTrailer ? "Скрыть трейлер" : "Трейлер",
                    systemImage: showTrailer ? "eye.slash.fill" : "film.fill",
                    tint: tint
                )
            }

            // Пока полная карточка не загрузилась — показываем, что идёт
            // загрузка, а не «видео недоступно» (иначе кажется, что сломано).
            if primaryURL == nil {
                if itemLoaded {
                    Text("Видео пока недоступно")
                        .font(.callout)
                        .foregroundColor(.secondary)
                } else {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Загрузка…")
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var plot: some View {
        if let plot = info.plot, !plot.isEmpty {
            Text(plot)
                .font(.body)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var credits: some View {
        if let director = info.director, !director.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Режиссёр").font(.caption.weight(.semibold)).foregroundColor(.secondary)
                Text(director).font(.body)
            }
        }
    }

    @ViewBuilder
    private var castSection: some View {
        if castLoading || !cast.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text("В ролях").font(.title3.weight(.bold))

                if castLoading {
                    // Единый «луч» загрузки вместо мигающих кругов.
                    ShimmerPlaceholder()
                        .frame(height: 104)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 18) {
                            ForEach(cast) { actor in
                                Button {
                                    withAnimation(.easeOut(duration: 0.28)) {
                                        selectedActor = actor
                                    }
                                } label: {
                                    ActorCard(actor: actor)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var episodesSection: some View {
        if info.isSeries, !seasons.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Серии").font(.title3.weight(.bold))
                    Spacer()
                    Picker("Сезон", selection: $seasonNumber) {
                        ForEach(seasons, id: \.number) { season in
                            Text("Сезон \(season.number)").tag(season.number)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 160)
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 240, maximum: 300), spacing: 14)],
                    alignment: .leading,
                    spacing: 16
                ) {
                    ForEach(episodes) { episode in
                        Button {
                            playEpisode(episode)
                        } label: {
                            episodeCard(episode)
                        }
                        .buttonStyle(.plain)
                        .disabled(episode.files?.first?.bestURL == nil)
                    }
                }
            }
        }
    }

    /// Карточка серии: широкий скрин с номером, названием и прогрессом.
    private func episodeCard(_ episode: Season.Episode) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.gray.opacity(0.12))

                RemoteImage(url: episode.thumbnailURL, contentMode: .fill) {
                    ShimmerPlaceholder()
                }

                LinearGradient(
                    colors: [.clear, .black.opacity(0.6)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                HStack(spacing: 6) {
                    Image(systemName: episode.watched == 1 ? "checkmark.circle.fill" : "play.circle.fill")
                        .font(.caption)
                    Text("Серия \(episode.number)")
                        .font(.caption.weight(.semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(alignment: .bottom) {
                if episode.progress > 0.01 {
                    WatchProgressBar(fraction: episode.progress)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 6)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 1)
            }

            Text(episode.russianTitle ?? "Серия \(episode.number)")
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let duration = episode.duration, duration > 0 {
                Text(Self.durationLabel(duration))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private static func durationLabel(_ seconds: Int) -> String {
        let minutes = seconds / 60
        if minutes >= 60 {
            return "\(minutes / 60) ч \(minutes % 60) мин"
        }
        return "\(minutes) мин"
    }

    @ViewBuilder
    private var similarSection: some View {
        if !similar.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Похожее").font(.title3.weight(.bold))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(similar) { similarItem in
                            let sourceID = "similar-\(route.sourceID)-\(similarItem.id)"
                            ItemLink(item: similarItem, sourceID: sourceID) {
                                PosterCard(item: similarItem, frameID: sourceID)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Navigation from actor

    private func openFromActor(_ selected: KinopubItem) {
        guard let actor = selectedActor else { return }
        let sourceID = "actor-\(actor.id)-\(selected.id)"
        let start = FrameRegistry.shared.frame(for: sourceID)

        withAnimation(.easeInOut(duration: 0.28)) {
            selectedActor = nil
        }

        withAnimation(.easeOut(duration: 0.45)) {
            navigation.open(selected, sourceID: sourceID, from: start)
        }
    }

    // MARK: - Trailer

    private func autoPlayTrailer() async {
        guard info.trailerURL != nil else { return }
        try? await Task.sleep(nanoseconds: 4_000_000_000)
        guard !Task.isCancelled else { return }
        startTrailer()
    }

    private func startTrailer() {
        guard let url = info.trailerURL else { return }
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

    private func toggleTrailer() {
        if showTrailer {
            stopTrailer()
        } else {
            startTrailer()
        }
    }

    private func openTrailerFullscreen() {
        guard let url = info.trailerURL else { return }
        stopTrailer()

        if let window = NSApp.keyWindow, !window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
        }

        player.open(PlayRequest(
            id: info.id,
            title: info.russianTitle,
            url: url,
            logo: artwork?.logo,
            subtitle: "Трейлер"
        ))
    }

    // MARK: - Playback

    private func playPrimary() {
        guard let url = primaryURL else { return }
        stopTrailer()
        let subtitle: String
        let episodeTitle: String?
        if info.isSeries, let episode = episodes.first {
            subtitle = "S\(seasonNumber) · E\(episode.number)"
            episodeTitle = episode.title
        } else if let year = info.year {
            subtitle = String(year)
            episodeTitle = nil
        } else {
            subtitle = ""
            episodeTitle = nil
        }
        player.open(PlayRequest(
            id: info.id,
            title: info.russianTitle,
            url: url,
            logo: artwork?.logo,
            subtitle: subtitle,
            episodeTitle: episodeTitle
        ))
    }

    private func playEpisode(_ episode: Season.Episode) {
        guard let url = episode.files?.first?.bestURL else { return }
        stopTrailer()
        player.open(
            PlayRequest(
                id: episode.id,
                title: info.russianTitle,
                url: url,
                logo: artwork?.logo,
                subtitle: "S\(seasonNumber) · E\(episode.number)",
                episodeTitle: episode.title,
                itemID: info.id,
                season: seasonNumber,
                video: episode.number
            )
        )
    }

    // MARK: - Loading

    private func load() async {
        castLoading = true

        async let artworkTask = MetadataService.shared.artwork(for: item)
        async let similarTask = api.similar(to: item.id)
        async let castTask = PeopleService.shared.cast(for: item)

        artwork = try? await artworkTask
        similar = (try? await similarTask) ?? []
        cast = (try? await castTask) ?? []
        castLoading = false

        do {
            let full = try await api.item(id: item.id)
            fullItem = full
            if let firstSeason = full.seasons?.first?.number {
                seasonNumber = firstSeason
            }
        } catch {
            // Не удалось догрузить полную карточку — остаёмся на данных списка.
        }
        itemLoaded = true
    }

    private func loadTint() async {
        guard let url = colorSource else { return }
        guard let color = await ArtworkPalette.shared.color(for: url) else { return }
        guard url == colorSource else { return }
        tint = color
        theme.set(color, for: nodeID)
    }
}
