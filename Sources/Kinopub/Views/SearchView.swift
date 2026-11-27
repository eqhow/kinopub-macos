import SwiftUI

struct SearchView: View {
    @ObservedObject var search: SearchState
    /// Открыть профиль актёра поверх текущего экрана.
    var onSelectActor: (Actor) -> Void = { _ in }

    @EnvironmentObject var api: APIClient
    @State private var films: [KinopubItem] = []
    @State private var actors: [Actor] = []
    @State private var collectionResults: [KinopubItem] = []
    @State private var loading = false
    @State private var searchedQuery = ""
    @State private var openedCollection: OpenedCollection?

    var body: some View {
        Group {
            if let opened = openedCollection {
                CollectionDetailView(collectionID: opened.id, title: opened.title) {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        openedCollection = nil
                    }
                }
                .transition(.opacity)
            } else {
                // Поиск идёт из сайдбара — здесь только результаты.
                content
            }
        }
        .task(id: search.query) {
            await liveSearch()
        }
        .onChange(of: search.submitID) { _, _ in
            Task { await performSearch() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Search bar

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        let query = search.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let few = collectionResults.isEmpty && (films.count + actors.count <= 3)

        if query.isEmpty {
            emptyState
        } else if loading {
            ProgressView()
                .scaleEffect(0.8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if films.isEmpty && actors.isEmpty && collectionResults.isEmpty {
            ContentUnavailableView(
                "Ничего не найдено",
                systemImage: "magnifyingglass",
                description: Text("По запросу «\(query)» ничего нет")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if few {
            // Компактный макет — без ScrollView, чтобы не было пустоты
            VStack(alignment: .leading, spacing: 20) {
                if !films.isEmpty {
                    filmsSection
                }

                if !actors.isEmpty {
                    actorsSection
                }

                if !collectionResults.isEmpty {
                    collectionsSection
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !films.isEmpty {
                        filmsSection
                    }

                    if !actors.isEmpty {
                        actorsSection
                    }

                    if !collectionResults.isEmpty {
                        collectionsSection
                    }
                }
                .padding(24)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    // MARK: - Empty

    private var emptyState: some View {
        ContentUnavailableView(
            "Поиск",
            systemImage: "magnifyingglass",
            description: Text("Введите запрос в поле поиска слева")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var collectionsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Подборки", count: collectionResults.count)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 320), spacing: 20, alignment: .top)],
                alignment: .leading,
                spacing: 22
            ) {
                ForEach(collectionResults) { collection in
                    CollectionCard(
                        collectionID: collection.id,
                        title: collection.russianTitle,
                        onOpen: {
                            withAnimation(.easeInOut(duration: 0.22)) {
                                openedCollection = OpenedCollection(id: collection.id, title: collection.russianTitle)
                            }
                        }
                    )
                }
            }
        }
    }

    private var filmsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Фильмы и сериалы", count: films.count)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 160, maximum: 210), spacing: 18)],
                alignment: .leading,
                spacing: 20
            ) {
                ForEach(films) { item in
                    let sourceID = "search-\(item.id)"
                    ItemLink(item: item, sourceID: sourceID) {
                        PosterCard(item: item, frameID: sourceID)
                    }
                }
            }
        }
    }

    private var actorsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Актёры", count: actors.count)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 104, maximum: 104), spacing: 18)],
                alignment: .leading,
                spacing: 18
            ) {
                ForEach(actors) { actor in
                    Button {
                        onSelectActor(actor)
                    } label: {
                        ActorCard(actor: actor)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func sectionTitle(_ text: String, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(text)
                .font(.title3.weight(.bold))
            Text(String(count))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Loading

    /// Живой поиск по мере ввода: небольшая пауза «дебаунсит» набор.
    private func liveSearch() async {
        let query = search.query.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            films = []
            actors = []
            collectionResults = []
            searchedQuery = ""
            loading = false
            return
        }

        try? await Task.sleep(nanoseconds: 350_000_000)
        guard !Task.isCancelled else { return }
        await performSearch(query)
    }

    private func performSearch(_ rawQuery: String? = nil) async {
        let query = (rawQuery ?? search.query)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            films = []
            actors = []
            collectionResults = []
            searchedQuery = ""
            loading = false
            return
        }

        loading = true

        async let filmTask: [KinopubItem] = (try? await api.search(query)) ?? []
        async let actorTask: [Actor] = PeopleService.shared.searchActors(query)
        async let collTask: [KinopubItem] = (try? await api.searchCollections(title: query)) ?? []

        let foundFilms = await filmTask
        let foundActors = await actorTask
        let foundCollections = await collTask

        guard !Task.isCancelled,
              search.query.trimmingCharacters(in: .whitespacesAndNewlines) == query
        else { return }

        films = foundFilms
        actors = foundActors
        collectionResults = foundCollections
        searchedQuery = query
        loading = false
    }
}

/// Подборка, открытая на просмотр (раздел с её фильмами).
struct OpenedCollection: Identifiable {
    let id: Int
    let title: String
}

/// «Папка» подборки: до 6 постеров в сетке 3×N. На последней ячейке —
/// постер с затемнением и счётчиком `+N` (остаток). Если фильмов мало,
/// карточка просто короче (без пустых серых ячеек).
struct CollectionCard: View {
    let collectionID: Int
    let title: String
    var onLoaded: (Int) -> Void = { _ in }
    var onOpen: () -> Void

    @EnvironmentObject private var api: APIClient
    @State private var posters: [URL] = []
    @State private var remaining = 0
    @State private var loaded = false

    private let spacing: CGFloat = 8
    private let padding: CGFloat = 14
    private let posterAspect: CGFloat = 2.0 / 3.0
    private let maxCells = 6

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 12) {
                grid
                    .padding(padding)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                    )

                Text(title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .task { await load() }
    }

    // MARK: - Grid

    /// Все карточки всегда одного размера — ровно как «скелетон» при загрузке.
    private let totalRows = 2

    private var cellCount: Int { maxCells }

    private var contentRows: [[Int]] {
        stride(from: 0, to: cellCount, by: 3).map { start in
            Array(start..<min(start + 3, cellCount))
        }
    }

    private var grid: some View {
        VStack(spacing: spacing) {
            if !loaded {
                ForEach(0..<totalRows, id: \.self) { _ in skeletonRow }
            } else {
                ForEach(contentRows, id: \.first) { indices in
                    rowView(indices)
                }
            }
        }
    }

    private var skeletonRow: some View {
        HStack(spacing: spacing) {
            ForEach(0..<3, id: \.self) { _ in
                gridCell { SkeletonGlow() }
            }
        }
    }

    private func rowView(_ indices: [Int]) -> some View {
        HStack(spacing: spacing) {
            ForEach(0..<3, id: \.self) { col in
                if col < indices.count {
                    cell(indices[col])
                } else {
                    gridCell { Color.clear }
                }
            }
        }
    }

    @ViewBuilder
    private func cell(_ index: Int) -> some View {
        let isCounter = remaining > 0 && index == cellCount - 1
        gridCell {
            ZStack {
                posterView(index)

                if isCounter {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.black.opacity(0.55))
                    Text("+\(remaining)")
                        .font(.headline.weight(.bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .padding(4)
                }
            }
        }
    }

    /// Единый контейнер ячейки: размер задаётся ровно один раз, поэтому
    /// «скелетон» при загрузке и готовый постер всегда одного размера.
    private func gridCell<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity)
            .aspectRatio(posterAspect, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    @ViewBuilder
    private func posterView(_ index: Int) -> some View {
        if index < posters.count {
            RemoteImage(url: posters[index], contentMode: .fill) {
                Color.gray.opacity(0.12)
            }
        } else {
            Color.gray.opacity(0.12)
        }
    }

    // MARK: - Load

    private func load() async {
        guard !loaded else { return }
        let items = (try? await api.collectionItems(id: collectionID)) ?? []
        let urls = items.compactMap { $0.bestPoster }
        let shown = Array(urls.prefix(maxCells))
        posters = shown
        remaining = max(0, items.count - shown.count)
        withAnimation(.easeInOut(duration: 0.18)) { loaded = true }
        onLoaded(items.count)
    }
}

/// Квадратная «папка» подборки: 4 миниатюры 2×2 как превью,
/// тонкая рамка. Размер задаётся параметром `size`.
struct CollectionFolderBadge: View {
    let collectionID: Int
    var size: CGFloat = 40

    @EnvironmentObject private var api: APIClient
    @State private var posters: [URL] = []
    @State private var loaded = false

    private let cellSpacing: CGFloat = 2
    private let inset: CGFloat = 4

    /// Точный бокс одной миниатюры — квадрат, постеры режутся до него.
    private var cellSide: CGFloat {
        (size - inset * 2 - cellSpacing) / 2
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.gray.opacity(0.08))

            VStack(spacing: cellSpacing) {
                ForEach(0..<2, id: \.self) { row in
                    HStack(spacing: cellSpacing) {
                        ForEach(0..<2, id: \.self) { col in
                            posterCell(row * 2 + col)
                        }
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        }
        .task { await load() }
    }

    @ViewBuilder
    private func posterCell(_ idx: Int) -> some View {
        Group {
            if idx < posters.count {
                RemoteImage(url: posters[idx], contentMode: .fill) {
                    Color.gray.opacity(0.06)
                }
            } else {
                Color.gray.opacity(0.06)
            }
        }
        .frame(width: cellSide, height: cellSide)
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
    }

    private func load() async {
        guard !loaded else { return }
        let items = (try? await api.collectionItems(id: collectionID)) ?? []
        posters = Array(items.compactMap { $0.bestPoster }.prefix(4))
        loaded = true
    }
}

/// Свечение скелетона. Не задаёт собственный размер (его определяет
/// `gridCell`) — просто пульсирующая плашка с мягким глоу.
private struct SkeletonGlow: View {
    @State private var on = false

    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(on ? 0.15 : 0.06))
            .shadow(color: Color.primary.opacity(on ? 0.18 : 0), radius: on ? 6 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                    on = true
                }
            }
    }
}
