import SwiftUI

/// Раздел подборки: открывается как «Фильмы», но с названием подборки сверху.
struct CollectionDetailView: View {
    let collectionID: Int
    let title: String
    var onBack: () -> Void

    @EnvironmentObject var api: APIClient

    @State private var items: [KinopubItem] = []
    @State private var loading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if loading {
                Spacer()
                ProgressView()
                    .scaleEffect(0.8)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else if items.isEmpty {
                Spacer()
                ContentUnavailableView(
                    "Пусто",
                    systemImage: "rectangle.stack",
                    description: Text("В этой подборке пока нет фильмов")
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
                            let sourceID = "coll-\(collectionID)-\(item.id)"
                            ItemLink(item: item, sourceID: sourceID) {
                                PosterCard(item: item, frameID: sourceID)
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { await load() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            CloseCircleButton(action: onBack)

            Text(title)
                .font(.largeTitle.weight(.bold))
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
    }

    private func load() async {
        loading = true
        items = (try? await api.collectionItems(id: collectionID)) ?? []
        loading = false
    }
}
