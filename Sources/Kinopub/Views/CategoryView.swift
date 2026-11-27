import SwiftUI

/// Каталог «Фильмы» / «Сериалы»: поиск по всей библиотеке и фильтры
/// Kinopab (жанр, страна, год) вместо прежних вкладок «Горячее/Популярное».
struct CategoryView: View {
    let type: String?
    let title: String
    /// Если задан — каталог жёстко ограничен одним жанром (аниме/мультфильмы).
    var fixedGenreID: Int? = nil

    @EnvironmentObject var api: APIClient

    @State private var items: [KinopubItem] = []
    @State private var genres: [Genre] = []
    @State private var countries: [Country] = []
    @State private var loading = true

    @State private var query = ""
    @State private var genre: Genre?
    @State private var country: Country?
    @State private var year: Int?

    private var effectiveGenre: Int? { fixedGenreID ?? genre?.id }

    private var filtered: Bool {
        !query.trimmingCharacters(in: .whitespaces).isEmpty || genre != nil || country != nil || year != nil
    }

    /// Ключ для `.task(id:)`: изменение любого фильтра перезапускает загрузку.
    private var loadKey: String {
        "\(query)|\(effectiveGenre ?? 0)|\(country?.id ?? 0)|\(year ?? 0)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.largeTitle.weight(.bold))
                .padding(.horizontal, 24)
                .padding(.top, 18)

            filterBar
                .padding(.horizontal, 24)

            if loading {
                Spacer()
                ProgressView()
                    .scaleEffect(0.8)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else if items.isEmpty {
                Spacer()
                ContentUnavailableView(
                    filtered ? "Ничего не найдено" : "Пусто",
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text(filtered ? "Измените фильтры или запрос" : "Здесь пока нет тайтлов")
                )
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 160, maximum: 160), spacing: 18)],
                        alignment: .leading,
                        spacing: 20
                    ) {
                        ForEach(items) { item in
                            let sourceID = "cat-\(fixedGenreID.map(String.init) ?? type ?? "all")-\(item.id)"
                            ItemLink(item: item, sourceID: sourceID) {
                                PosterCard(item: item, frameID: sourceID)
                            }
                        }
                    }
                    .padding(24)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { await loadFilters() }
        .task(id: loadKey) { await reload() }
    }

    // MARK: - Filter bar

    private var filterBar: some View {
        HStack(spacing: 10) {
            // Поиск по всей библиотеке
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                TextField("Поиск по библиотеке…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.callout)

                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
            .frame(maxWidth: 320)

            if fixedGenreID == nil {
                Menu {
                    Button("Все жанры") { genre = nil }
                    Divider()
                    ForEach(genres) { g in
                        Button(g.title) { genre = g }
                    }
                } label: {
                    filterChip(genre?.title ?? "Жанр", active: genre != nil)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.visible)
                .fixedSize()
            }

            Menu {
                Button("Все страны") { country = nil }
                Divider()
                ForEach(countries) { c in
                    Button(c.title) { country = c }
                }
            } label: {
                filterChip(country?.title ?? "Страна", active: country != nil)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.visible)
            .fixedSize()

            Menu {
                Button("Все годы") { year = nil }
                Divider()
                ForEach(Self.years, id: \.self) { y in
                    Button(String(y)) { year = y }
                }
            } label: {
                filterChip(year.map { String($0) } ?? "Год", active: year != nil)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.visible)
            .fixedSize()

            if filtered {
                Button {
                    query = ""
                    genre = nil
                    country = nil
                    year = nil
                } label: {
                    Label("Сбросить", systemImage: "xmark")
                        .font(.callout)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
    }

    private func filterChip(_ text: String, active: Bool) -> some View {
        HStack(spacing: 5) {
            Text(text).font(.callout).lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.bold))
        }
        .foregroundStyle(active ? AnyShapeStyle(Color.appAccent) : AnyShapeStyle(.primary))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            active ? AnyShapeStyle(Color.appAccent.opacity(0.12)) : AnyShapeStyle(Color.gray.opacity(0.1)),
            in: Capsule()
        )
    }

    // MARK: - Loading

    private func loadFilters() async {
        async let g = api.genres()
        async let c = api.countries()
        genres = (try? await g) ?? []
        countries = (try? await c) ?? []
    }

    private func reload() async {
        // Небольшая задержка «дебаунсит» ввод в поиске.
        try? await Task.sleep(nanoseconds: 250_000_000)
        guard !Task.isCancelled else { return }

        loading = true
        let q = query.trimmingCharacters(in: .whitespaces)
        let result: [KinopubItem]
        if !q.isEmpty {
            result = (try? await api.search(q)) ?? []
        } else {
            result = (try? await api.browse(
                type: type,
                genre: effectiveGenre,
                country: country?.id,
                year: year
            )) ?? []
        }
        guard !Task.isCancelled else { return }
        items = result
        loading = false
    }

    private static let years: [Int] = {
        let current = Calendar.current.component(.year, from: Date())
        return Array(stride(from: current, through: 1950, by: -1))
    }()
}
