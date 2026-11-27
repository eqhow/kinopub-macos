import SwiftUI

enum Tab: String, CaseIterable, Identifiable {
    case home = "Главная"
    case collections = "Подборки"
    case movies = "Фильмы"
    case series = "Сериалы"
    case anime = "Аниме"
    case cartoons = "Мультфильмы"
    case search = "Поиск"
    case history = "История"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .collections: return "rectangle.stack.fill"
        case .movies: return "film.fill"
        case .series: return "tv.fill"
        case .anime: return "sparkles"
        case .cartoons: return "theatermasks.fill"
        case .search: return "magnifyingglass"
        case .history: return "clock.fill"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var player: PlayerCoordinator

    @StateObject private var navigation = DetailNavigation()
    @StateObject private var theme = ThemeStore()
    @StateObject private var search = SearchState()

    @State private var tab: Tab = .home
    @State private var user: UserInfo?
    /// Профиль актёра, открытый из поиска/подсказок сайдбара.
    @State private var searchActor: Actor?
    /// Подборка, открытая из подсказок сайдбара.
    @State private var sidebarCollection: OpenedCollection?
    /// Сайдбар сворачивается влево во время кинематографичного запуска.
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    private var activeTint: Color? {
        theme.tint(for: navigation.stack.last?.id)
    }

    var body: some View {
        decoratedSplit
            .onChange(of: player.preparing) { _, preparing in
                withAnimation(.easeInOut(duration: 0.65)) {
                    columnVisibility = preparing ? .detailOnly : .all
                }
            }
            .onChange(of: tab) { _, _ in
                searchActor = nil
                sidebarCollection = nil
                navigation.closeAll()
            }
            .task { await bootstrap() }
    }

    private var decoratedSplit: some View {
        splitView
            .overlay { themeWash }
            .overlay { playerOverlays }
            .animation(.easeInOut(duration: 0.7), value: activeTint)
            .animation(.easeInOut(duration: 0.3), value: player.request)
            .animation(.easeInOut(duration: 0.65), value: player.preparing)
    }

    private var splitView: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
        } detail: {
            detailPane
        }
        .environmentObject(navigation)
        .environmentObject(theme)
        .tint(activeTint ?? .appAccent)
        .toolbarBackground(.hidden, for: .windowToolbar)
        .navigationTitle("")
        .background {
            WindowTheme(color: activeTint, blackedOut: player.request != nil)
                .frame(width: 0, height: 0)
        }
    }

    private func bootstrap() async {
        user = try? await api.user()
        let env = ProcessInfo.processInfo.environment
        if let q = env["KINOPUB_DBG_SEARCH"], !q.isEmpty {
            search.query = q
            tab = .search
        } else if let q = env["KINOPUB_DBG_OPEN"], !q.isEmpty,
                  let first = try? await api.search(q).first {
            navigation.open(first, sourceID: "dbg-open-\(first.id)")
        } else if env["KINOPUB_DBG_PLAY"] != nil, let entry = try? await api.history().first {
            ResumePlayback.start(entry, api: api, player: player)
        } else if env["KINOPUB_DBG_SERIES"] != nil,
                  let s = try? await api.hotSeries().first {
            navigation.open(s, sourceID: "dbg-\(s.id)")
        } else if let t = env["KINOPUB_DBG_TAB"],
                  let match = Tab.allCases.first(where: { $0.rawValue.lowercased() == t.lowercased() }) {
            tab = match
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            sidebarSearch

            ZStack(alignment: .top) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach([Tab.home, .collections, .history]) { item in
                            sidebarRow(item)
                        }

                        sidebarGroupTitle("Категории")
                            .padding(.top, 12)
                        ForEach([Tab.movies, .series, .anime, .cartoons]) { item in
                            sidebarRow(item)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }

                if tab != .search, !suggestions.isEmpty || !actorSuggestions.isEmpty || !collectionSuggestions.isEmpty {
                    Group {
                        if suggestions.count + actorSuggestions.count + collectionSuggestions.count <= 5 {
                            suggestionsContent
                        } else {
                            ScrollView { suggestionsContent }
                                .frame(maxHeight: 420)
                        }
                    }
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                    .padding(.horizontal, 8)
                    .transition(.opacity)
                }
            }

            profileFooter
        }
        .navigationSplitViewColumnWidth(min: 210, ideal: 230)
        .task(id: search.query) {
            await fetchSuggestions()
        }
    }

    private var detailPane: some View {
        GeometryReader { geo in
            detailContent
                .onAppear { navigation.detailFrame = geo.frame(in: .global) }
                .onChange(of: geo.frame(in: .global)) { _, frame in
                    navigation.detailFrame = frame
                }
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        ZStack {
            Group {
                screen

                ForEach(Array(navigation.stack.enumerated()), id: \.element.id) { index, node in
                    DetailView(
                        nodeID: node.id,
                        route: node.route,
                        isTop: index == navigation.stack.count - 1,
                        onBack: closeTop
                    )
                    .transition(.asymmetric(insertion: .opacity, removal: .opacity))
                    .zIndex(Double(index + 1))
                }

                if let actor = searchActor {
                    ActorProfileView(
                        actor: actor,
                        tint: .appAccent,
                        currentIMDb: nil,
                        onBack: {
                            withAnimation(.easeInOut(duration: 0.22)) {
                                searchActor = nil
                            }
                        },
                        onSelectItem: { item in
                            withAnimation(.easeInOut(duration: 0.22)) {
                                searchActor = nil
                            }
                            navigation.open(item, sourceID: "search-actor-\(item.id)")
                        }
                    )
                    .transition(.opacity)
                    .zIndex(0.5)
                }

                if let collection = sidebarCollection {
                    CollectionDetailView(collectionID: collection.id, title: collection.title) {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            sidebarCollection = nil
                        }
                    }
                    .background(Color(NSColor.windowBackgroundColor))
                    .transition(.opacity)
                    .zIndex(2)
                }
            }
            // Контент проседает вниз и гаснет, пока идёт запуск.
            .offset(y: player.preparing ? 110 : 0)
            .opacity(player.preparing ? 0 : 1)
        }
    }

    @ViewBuilder
    private var screen: some View {
        switch tab {
        case .home:
            HomeView()
        case .collections:
            CollectionsView()
        case .movies:
            CategoryView(type: "movie", title: "Фильмы")
        case .series:
            CategoryView(type: "serial", title: "Сериалы")
        case .anime:
            CategoryView(type: nil, title: "Аниме", fixedGenreID: 25)
        case .cartoons:
            CategoryView(type: nil, title: "Мультфильмы", fixedGenreID: 23)
        case .search:
            SearchView(search: search) { actor in
                withAnimation(.easeInOut(duration: 0.22)) {
                    searchActor = actor
                }
            }
        case .history:
            HistoryView()
        }
    }

    private func closeTop() {
        withAnimation(.easeInOut(duration: 0.25)) {
            navigation.pop()
        }
    }

    // MARK: - Player overlay

    /// Слой поверх приложения: полноэкранная загрузка плеера
    /// и сам плеер.
    @ViewBuilder
    private var playerOverlays: some View {
        ZStack {
            if player.preparing, player.request == nil {
                LaunchCurtain(poster: player.preparingPoster)
                    .transition(.opacity)
                    .zIndex(30)
            }

            if let request = player.request {
                PlayerWindowView(request: request)
                    .zIndex(20)
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.5), value: player.preparing)
    }

    @ViewBuilder
    private var themeWash: some View {
        if let activeTint {
            ZStack {
                activeTint
                    .opacity(0.32)
                    .blendMode(.color)

                LinearGradient(
                    colors: [activeTint.opacity(0.22), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .blendMode(.softLight)
            }
            .allowsHitTesting(false)
            .ignoresSafeArea()
            .transition(.opacity)
        }
    }

    // MARK: - Sidebar

    private func sidebarGroupTitle(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }

    /// Выбранный пункт меню красится в текущий акцент (цвет открытой
    /// карточки), в тон кнопке «Смотреть». Без открытой карточки — акцент
    /// системы.
    private func sidebarRow(_ item: Tab) -> some View {
        let selected = tab == item
        let color = activeTint ?? .appAccent
        return Button {
            tab = item
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.icon)
                    .font(.body)
                    .frame(width: 20, alignment: .center)
                Text(item.rawValue)
                    .font(.body)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(selected ? color : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var profileFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            HStack(spacing: 10) {
                RemoteImage(url: user?.avatarURL) {
                    Circle().fill(.quaternary)
                }
                .frame(width: 20, height: 20)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(user?.displayName ?? "Профиль")
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)

                    if let end = user?.subscriptionEnd {
                        Text("Оплачен до \(Self.endDateFormatter.string(from: end))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    } else if let user {
                        Text(user.subscription?.active == true ? "Подписка активна" : "Подписка неактивна")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Нет данных")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 4)

                Button {
                    auth.logout()
                } label: {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Выйти")
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
    }

    private var sidebarSearch: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Поиск", text: $search.query)
                .textFieldStyle(.plain)
                .font(.callout)
                .onSubmit {
                    search.submit()
                    suggestions = []
                    actorSuggestions = []
                    tab = .search
                }

            if suggestionsLoading {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
                    .frame(width: 14, height: 14)
            } else if !search.query.isEmpty {
                Button {
                    search.query = ""
                    suggestions = []
                    actorSuggestions = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 8)
        .padding(.top, 8)
    }

    @State private var suggestions: [KinopubItem] = []
    @State private var actorSuggestions: [Actor] = []
    @State private var collectionSuggestions: [KinopubItem] = []
    @State private var suggestionsLoading = false

    private static let endDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMM yyyy"
        return formatter
    }()

    private var suggestionsContent: some View {
        VStack(spacing: 0) {
            if !suggestions.isEmpty {
                dropdownTitle("Фильмы и сериалы")
                ForEach(suggestions) { item in
                    Button {
                        search.query = item.russianTitle
                        suggestions = []
                        actorSuggestions = []
                        navigation.open(item, sourceID: "sugg-\(item.id)")
                    } label: {
                        HStack(spacing: 8) {
                            RemoteImage(url: item.bestPoster) {
                                Color.gray.opacity(0.15)
                            }
                            .frame(width: 30, height: 45)
                            .clipShape(RoundedRectangle(cornerRadius: 4))

                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.russianTitle)
                                    .font(.caption.weight(.medium))
                                    .lineLimit(1)
                                if let year = item.year {
                                    Text(String(year))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            if !actorSuggestions.isEmpty {
                if !suggestions.isEmpty {
                    Divider().padding(.horizontal, 10)
                }
                dropdownTitle("Актёры")
                ForEach(actorSuggestions) { actor in
                    Button {
                        search.query = actor.name
                        suggestions = []
                        actorSuggestions = []
                        searchActor = actor
                    } label: {
                        HStack(spacing: 8) {
                            ZStack {
                                Circle().fill(.quaternary)
                                RemoteImage(url: actor.photo, contentMode: .fill) {
                                    Text(String(actor.name.prefix(1)))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .frame(width: 30, height: 30)
                            .clipShape(Circle())

                            Text(actor.name)
                                .font(.caption.weight(.medium))
                                .lineLimit(1)

                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            if !collectionSuggestions.isEmpty {
                if !suggestions.isEmpty || !actorSuggestions.isEmpty {
                    Divider().padding(.horizontal, 10)
                }
                dropdownTitle("Подборки")
                ForEach(collectionSuggestions) { collection in
                    Button {
                        sidebarCollection = OpenedCollection(id: collection.id, title: collection.russianTitle)
                        suggestions = []
                        actorSuggestions = []
                        collectionSuggestions = []
                    } label: {
                        HStack(spacing: 8) {
                            CollectionFolderBadge(collectionID: collection.id)

                            Text(collection.russianTitle)
                                .font(.caption.weight(.medium))
                                .lineLimit(1)

                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func dropdownTitle(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 2)
    }

    private func fetchSuggestions() async {
        let query = search.query.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            suggestions = []
            actorSuggestions = []
            collectionSuggestions = []
            suggestionsLoading = false
            return
        }
        try? await Task.sleep(nanoseconds: 250_000_000)
        guard !Task.isCancelled, search.query.trimmingCharacters(in: .whitespacesAndNewlines) == query else { return }

        suggestionsLoading = true

        async let filmTask: [KinopubItem] = (try? await api.search(query)) ?? []
        async let actorTask: [Actor] = PeopleService.shared.searchActors(query)
        async let collTask: [KinopubItem] = (try? await api.searchCollections(title: query)) ?? []

        let foundFilms = await filmTask
        let foundActors = await actorTask
        let foundCollections = await collTask

        guard !Task.isCancelled else { return }
        suggestions = Array(foundFilms.prefix(8))
        actorSuggestions = Array(foundActors.prefix(6))
        collectionSuggestions = Array(foundCollections.prefix(6))
        suggestionsLoading = false
    }
}