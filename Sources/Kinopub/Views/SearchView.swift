import SwiftUI

struct SearchView: View {
    @ObservedObject var search: SearchState

    @EnvironmentObject var api: APIClient
    @State private var results: [KinopubItem] = []
    @State private var loading = false
    @State private var searchedQuery = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("Название фильма или сериала...", text: $search.query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .onSubmit { search.submit() }
                if !search.query.isEmpty {
                    Button {
                        search.query = ""
                        results = []
                        searchedQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            if loading {
                ProgressView().scaleEffect(0.8).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if results.isEmpty {
                ContentUnavailableView(
                    search.query.isEmpty ? "Поиск" : "Ничего не найдено",
                    systemImage: "magnifyingglass",
                    description: Text(search.query.isEmpty ? "Введите название" : "Попробуйте изменить запрос")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(results) { item in
                            let sourceID = "search-\(item.id)"
                            ItemLink(item: item, sourceID: sourceID) {
                                suggestionRow(item)
                            }
                            .buttonStyle(.plain)
                            Divider().padding(.leading, 80)
                        }
                    }
                    .padding(8)
                }
            }
        }
        .task(id: search.query) {
            await liveSearch()
        }
        .onChange(of: search.submitID) { _, _ in
            Task { await performSearch(immediate: true) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Строка с обложкой и годом для додумывания.
    private func suggestionRow(_ item: KinopubItem) -> some View {
        HStack(spacing: 12) {
            RemoteImage(url: item.bestPoster) {
                Color.gray.opacity(0.2)
            }
            .frame(width: 50, height: 75)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.russianTitle)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                if let year = item.year {
                    Text(String(year))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
    }

    /// Живой поиск по мере ввода: небольшая пауза «дебаунсит» набор.
    private func liveSearch() async {
        let query = search.query.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            results = []
            searchedQuery = ""
            loading = false
            return
        }
        try? await Task.sleep(nanoseconds: 300_000_000)
        guard !Task.isCancelled else { return }
        await performSearch()
    }

    private func performSearch(immediate: Bool = false) async {
        let query = search.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            results = []
            searchedQuery = ""
            loading = false
            return
        }
        if immediate { try? await Task.sleep(nanoseconds: 0) }

        // Не мигаем большим спиннером, если результаты уже что-то показывают.
        if results.isEmpty { loading = true }
        do {
            let found = try await api.search(query)
            guard !Task.isCancelled else { return }
            results = found
        } catch {
            guard !Task.isCancelled else { return }
            results = []
        }
        searchedQuery = query
        loading = false
    }
}
