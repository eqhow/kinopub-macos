import SwiftUI

/// Раздел «Подборки»: сетка всех доступных подборок-«папок».
/// Постеры каждой папки грузятся лениво самой карточкой.
struct CollectionsView: View {
    @EnvironmentObject private var api: APIClient

    @State private var collections: [KinopubItem] = []
    @State private var loading = false
    @State private var openedCollection: OpenedCollection?
    /// Подборки с малым числом фильмов, которые уже «утопили» в низ списка.
    @State private var sunkIDs: Set<Int> = []

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
                content
            }
        }
        .task { await loadCollections() }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Подборки")
                .font(.largeTitle.weight(.bold))
                .padding(.horizontal, 24)
                .padding(.top, 18)

            if loading && collections.isEmpty {
                Spacer()
                ProgressView()
                    .scaleEffect(0.8)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else if collections.isEmpty {
                Spacer()
                ContentUnavailableView(
                    "Подборки",
                    systemImage: "rectangle.stack",
                    description: Text("Подборки пока недоступны")
                )
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 320), spacing: 20, alignment: .top)],
                        alignment: .leading,
                        spacing: 22
                    ) {
                        ForEach(collections) { collection in
                            CollectionCard(
                                collectionID: collection.id,
                                title: collection.russianTitle,
                                onLoaded: { count in
                                    sinkIfTiny(id: collection.id, count: count)
                                },
                                onOpen: {
                                    withAnimation(.easeInOut(duration: 0.22)) {
                                        openedCollection = OpenedCollection(id: collection.id, title: collection.russianTitle)
                                    }
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Загружаем все доступные подборки (постранично). Постеры каждой
    /// подборки тянет сама карточка лениво, чтобы не делать сотни запросов разом.
    private func loadCollections() async {
        guard collections.isEmpty, !loading else { return }
        loading = true
        defer { loading = false }

        var all: [KinopubItem] = []
        var page = 1
        var totalPages = 1
        repeat {
            if Task.isCancelled { return }
            guard let result = try? await api.collectionsPage(page) else { break }
            totalPages = result.totalPages
            if result.items.isEmpty { break }
            all.append(contentsOf: result.items)
            page += 1
        } while page <= totalPages && page <= 30

        collections = all

        if ProcessInfo.processInfo.environment["KINOPUB_DBG_COLLECTION"] != nil,
           let first = all.first {
            openedCollection = OpenedCollection(id: first.id, title: first.russianTitle)
        }
    }

    /// Подборки с малым числом фильмов (меньше полной «папки») не должны
    /// рекомендоваться в начале — уводим их в самый низ списка.
    private func sinkIfTiny(id: Int, count: Int) {
        let tinyThreshold = 5
        guard count < tinyThreshold, !sunkIDs.contains(id) else { return }
        sunkIDs.insert(id)
        guard let index = collections.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(.easeInOut(duration: 0.35)) {
            let item = collections.remove(at: index)
            collections.append(item)
        }
    }
}
