import SwiftUI

// MARK: - Actor card

struct ActorCard: View {
    let actor: Actor
    @State private var hover = false

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().fill(.quaternary)

                RemoteImage(url: actor.photo, contentMode: .fill) {
                    Text(initials)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 84, height: 84)
            .clipShape(Circle())
            .overlay {
                Circle().strokeBorder(.white.opacity(0.15), lineWidth: 1)
            }
            .shadow(color: .black.opacity(hover ? 0.25 : 0), radius: 10, y: 4)
            .scaleEffect(hover ? 1.04 : 1)
            .animation(.easeOut(duration: 0.18), value: hover)

            Text(actor.name)
                .font(.caption.weight(.medium))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(width: 104)
        }
        .frame(width: 104)
        .onHover { hover = $0 }
        .contentShape(Rectangle())
    }

    private var initials: String {
        actor.name
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()
    }
}

/// Пульсирующий скелетон-заглушка: статичная заливка + мягко дышащий
/// акцентный глоу. Без бегущего градиента и без `blur` (пер-кадровое
/// размытие при анимации даёт мерцание) — поэтому не «моргает».
struct GlowSkeleton: View {
    var cornerRadius: CGFloat = 10
    var tint: Color = .appAccent

    @State private var pulse = false

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(.quaternary.opacity(0.30))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(tint.opacity(pulse ? 0.20 : 0.05))
            }
            .onAppear { startPulse() }
    }

    private func startPulse() {
        pulse = false
        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
            pulse = true
        }
    }
}

struct ActorSkeleton: View {
    var tint: Color = .appAccent

    @State private var pulse = false

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(.quaternary.opacity(0.35))
                Circle()
                    .fill(tint.opacity(pulse ? 0.20 : 0.05))
            }
            .frame(width: 84, height: 84)
            .clipShape(Circle())
            .overlay {
                Circle().strokeBorder(.white.opacity(0.10), lineWidth: 1)
            }

            Capsule()
                .fill(.quaternary.opacity(0.5))
                .frame(width: 68, height: 8)
        }
        .frame(width: 104)
        .onAppear {
            pulse = false
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

// MARK: - Actor profile

private struct ActorScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ActorProfileView: View {
    let actor: Actor
    let tint: Color
    let currentIMDb: String?
    let onBack: () -> Void
    let onSelectItem: (KinopubItem) -> Void

    @EnvironmentObject private var api: APIClient

    @State private var films: [FilmCredit] = []
    @State private var photos: [URL] = []
    @State private var photosLoading = true
    @State private var loading = true
    @State private var kinopubItems: [KinopubItem] = []
    @State private var kinopubLoading = true
    /// Прокрутили так, что шапка с именем ушла — тогда показываем имя
    /// рядом с кнопкой «Назад».
    @State private var scrolledPastHeader = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            background

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                        .background(
                            GeometryReader { g in
                                Color.clear.preference(
                                    key: ActorScrollOffsetKey.self,
                                    value: g.frame(in: .named("actorScroll")).minY
                                )
                            }
                        )
                    kinopubSection
                    photosSection
                    filmography
                }
                .padding(.horizontal, 32)
                .padding(.top, 56)
                .padding(.bottom, 32)
            }
            .coordinateSpace(name: "actorScroll")
            .onPreferenceChange(ActorScrollOffsetKey.self) { y in
                if #available(macOS 15.0, *) {
                    // На 15+ работает ScrollThresholdTracker.
                } else {
                    scrolledPastHeader = y < -150
                }
            }
            .modifier(ScrollThresholdTracker(threshold: 150) { scrolledPastHeader = $0 })

            backButton
                .padding(.horizontal, 0)
                .padding(.top, 0)
        }
        .task(id: actor.id) { await load() }
        .onExitCommand { onBack() }
    }

    private var background: some View {
        ZStack(alignment: .top) {
            Color(NSColor.windowBackgroundColor)
            LinearGradient(
                colors: [tint.opacity(0.45), tint.opacity(0.12), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 24) {
            ZStack {
                Circle().fill(.quaternary)

                RemoteImage(url: actor.photo, contentMode: .fill) {
                    Text(initials)
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 132, height: 132)
            .clipShape(Circle())
            .overlay {
                Circle().strokeBorder(.white.opacity(0.15), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.35), radius: 18, y: 8)

            VStack(alignment: .leading, spacing: 8) {
                Text(actor.name)
                    .font(.system(size: 34, weight: .bold))
                    .lineLimit(2)

                if actor.imdbID != nil {
                    Text("Актёр")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if !loading, !films.isEmpty {
                    Text("Фильмография · \(films.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !kinopubLoading, !kinopubItems.isEmpty {
                    Text("В Кинопабе · \(kinopubItems.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Photos

    @ViewBuilder
    private var photosSection: some View {
        if photosLoading || !photos.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text("Фото")
                    .font(.title3.weight(.bold))

                if photosLoading {
                    HStack(spacing: 12) {
                        ForEach(0..<4, id: \.self) { _ in
                            GlowSkeleton(cornerRadius: 10, tint: tint)
                                .frame(width: 210, height: 280)
                        }
                    }
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(photos, id: \.self) { url in
                                RemoteImage(url: url, contentMode: .fill) {
                                    Color.gray.opacity(0.15)
                                }
                                .frame(width: 210, height: 280)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    // MARK: - Kinopub catalog

    @ViewBuilder
    private var kinopubSection: some View {
        if kinopubLoading || !kinopubItems.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text("Доступно в Кинопабе")
                    .font(.title3.weight(.bold))

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 16) {
                        if kinopubLoading {
                            ForEach(0..<6, id: \.self) { _ in
                                posterSkeleton
                            }
                        } else {
                            ForEach(kinopubItems) { item in
                                let sourceID = "actor-\(actor.id)-\(item.id)"
                                Button {
                                    onSelectItem(item)
                                } label: {
                                    PosterCard(item: item, frameID: sourceID)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var posterSkeleton: some View {
        VStack(alignment: .leading, spacing: 6) {
            GlowSkeleton(cornerRadius: 10, tint: tint)
                .frame(width: 160, height: 240)

            Capsule()
                .fill(.quaternary.opacity(0.5))
                .frame(width: 120, height: 8)
        }
    }

    @ViewBuilder
    private var filmography: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Где ещё снимался")
                .font(.title3.weight(.bold))

            if loading {
                VStack(spacing: 6) {
                    ForEach(0..<8, id: \.self) { _ in
                        filmSkeleton
                    }
                }
            } else if films.isEmpty {
                Text(actor.entityURI == nil ? "Фильмография недоступна" : "Ничего не найдено")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                LazyVStack(spacing: 6) {
                    ForEach(films) { film in
                        HStack(spacing: 14) {
                            Text(film.year.map { String($0) } ?? "—")
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 44, alignment: .trailing)

                            Text(film.title)
                                .font(.body)
                                .lineLimit(1)

                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }

    private var filmSkeleton: some View {
        HStack(spacing: 14) {
            Capsule()
                .fill(.quaternary.opacity(0.5))
                .frame(width: 36, height: 9)
            Capsule()
                .fill(.quaternary.opacity(0.5))
                .frame(width: 220, height: 9)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 13)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
    }

    private var backButton: some View {
        CloseCircleButton(
            action: onBack,
            label: actor.name,
            labelVisible: scrolledPastHeader
        )
        .padding(.top, 12)
        .padding(.leading, 18)
        // Тот же сдвиг, что и в деталке, для единого положения
        // относительно строки заголовка.
        .offset(y: -37.5)
    }

    private var initials: String {
        actor.name
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()
    }

    private func load() async {
        loading = true
        kinopubLoading = true
        photosLoading = true

        async let filmsTask = PeopleService.shared.filmography(for: actor, excluding: currentIMDb)
        async let kinopubTask = loadKinopub()
        async let photosTask = PeopleService.shared.photos(for: actor)

        photos = await photosTask
        photosLoading = false

        films = await filmsTask
        loading = false

        kinopubItems = await kinopubTask
        kinopubLoading = false
    }

    private func loadKinopub() async -> [KinopubItem] {
        let name = actor.kinopubName ?? actor.name
        return (try? await api.items(actor: name)) ?? []
    }
}
