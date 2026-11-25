import SwiftUI

/// Запуск просмотра с сохранённого места для карточек «Продолжить».
@MainActor
enum ResumePlayback {
    static func start(_ entry: HistoryEntry, api: APIClient, player: PlayerCoordinator) {
        // Не запускаем повторно, пока уже идёт подготовка — иначе можно
        // «настучать» по карточке и открыть несколько плееров.
        guard !player.preparing, player.request == nil else { return }
        player.preparing = true
        player.preparingTitle = entry.item.russianTitle
        player.preparingPoster = entry.thumbnail ?? entry.item.bestPoster

        Task {
            // В истории приходит облегчённая карточка — догружаем полную,
            // чтобы найти ссылку на конкретную серию.
            let full = (try? await api.item(id: entry.item.id)) ?? entry.item
            guard let url = resolveURL(full: full, entry: entry) else {
                player.preparing = false
                player.preparingTitle = nil
                return
            }
            let logo = await MetadataService.shared.artwork(for: full)?.logo
            player.open(PlayRequest(
                id: full.id,
                title: full.russianTitle,
                url: url,
                logo: logo,
                subtitle: entry.episodeLabel,
                episodeTitle: entry.media?.title,
                startAt: Double(entry.time ?? 0)
            ))
        }
    }

    private static func resolveURL(full: KinopubItem, entry: HistoryEntry) -> URL? {
        if full.isSeries {
            let snumber = entry.media?.snumber ?? 0
            let number = entry.media?.number ?? 0
            if let season = full.seasons?.first(where: { $0.number == snumber }),
               let episode = season.episodes?.first(where: { $0.number == number }) {
                return episode.files?.first?.bestURL
            }
            return full.seasons?.first?.episodes?.first?.files?.first?.bestURL
        }
        return full.videos?.first?.files?.first?.bestURL
    }
}

/// Тонкий индикатор прогресса просмотра.
struct WatchProgressBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.35))
                Capsule()
                    .fill(.white)
                    .frame(width: geo.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 3)
    }
}

/// Ряд «Продолжить просмотр» на главной: широкие кадры с прогрессом.
struct ContinueWatchingRow: View {
    let entries: [HistoryEntry]

    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var player: PlayerCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Продолжить просмотр").font(.title2.weight(.bold))

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(entries) { entry in
                        Button {
                            ResumePlayback.start(entry, api: api, player: player)
                        } label: {
                            ContinueCard(entry: entry)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

/// Широкая карточка «продолжить»: кадр серии, полоса прогресса, остаток времени.
struct ContinueCard: View {
    let entry: HistoryEntry

    @State private var hover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.gray.opacity(0.12))

                RemoteImage(url: entry.thumbnail) {
                    ShimmerPlaceholder()
                }

                LinearGradient(
                    colors: [.clear, .black.opacity(0.55)],
                    startPoint: .center,
                    endPoint: .bottom
                )
            }
            .frame(width: 320, height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 4) {
                    if let label = entry.episodeLabel {
                        Text(label)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.white)
                    }
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill").font(.caption)
                        Text(remainingText ?? "Продолжить").font(.caption.weight(.semibold))
                    }
                }
                .foregroundColor(.white)
                .padding(.leading, 10)
                .padding(.bottom, 16)
            }
            .overlay(alignment: .bottom) {
                WatchProgressBar(fraction: entry.progress)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(.white.opacity(hover ? 0.25 : 0), lineWidth: 1)
            }
            .overlay {
                if hover {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 42))
                        .foregroundColor(.white)
                        .shadow(radius: 8)
                }
            }
            .shadow(color: .black.opacity(hover ? 0.35 : 0), radius: 12, y: 6)
            .onHover { hover = $0 }
            .animation(.easeOut(duration: 0.18), value: hover)

            Text(entry.item.russianTitle)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .frame(width: 320, alignment: .leading)
        }
        .frame(width: 320)
        .contentShape(Rectangle())
    }

    private var remainingText: String? {
        guard let duration = entry.media?.duration, let time = entry.time else { return nil }
        let remaining = max(0, duration - time)
        let minutes = remaining / 60
        if minutes >= 60 {
            return "\(minutes / 60) ч \(minutes % 60) мин"
        }
        return "\(minutes) мин"
    }
}

/// Постер истории просмотров: обложка с полосой прогресса и подписью серии.
struct HistoryCard: View {
    let entry: HistoryEntry
    let frameID: String

    @State private var hover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.gray.opacity(0.12))

                RemoteImage(url: entry.item.bestPoster) {
                    ShimmerPlaceholder()
                }

                if hover {
                    Color.black.opacity(0.28)
                }
            }
            .frame(width: 160, height: 240)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .frameProbe(frameID)
            .overlay(alignment: .bottom) {
                if entry.progress > 0 {
                    WatchProgressBar(fraction: entry.progress)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 6)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(.white.opacity(hover ? 0.25 : 0), lineWidth: 1)
            }
            .shadow(color: .black.opacity(hover ? 0.35 : 0), radius: 12, y: 6)
            .onHover { hover = $0 }
            .animation(.easeOut(duration: 0.18), value: hover)

            Text(entry.item.russianTitle)
                .font(.caption.weight(.medium))
                .lineLimit(2)
                .frame(width: 160, alignment: .leading)

            HStack(spacing: 4) {
                if let label = entry.episodeLabel {
                    Text(label).font(.caption2).foregroundColor(.secondary)
                } else if let year = entry.item.year {
                    Text(verbatim: String(year)).font(.caption2).foregroundColor(.secondary)
                }
            }
        }
        .frame(width: 160)
        .contentShape(Rectangle())
    }
}

/// Широкая прямоугольная плашка истории — как карточки «Продолжить
/// просмотр» на главной, но тянется по ширине ячейки.
struct HistoryWideCard: View {
    let entry: HistoryEntry

    @State private var hover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.gray.opacity(0.12))

                RemoteImage(url: entry.thumbnail) {
                    ShimmerPlaceholder()
                }

                LinearGradient(
                    colors: [.clear, .black.opacity(0.55)],
                    startPoint: .center,
                    endPoint: .bottom
                )
            }
            .frame(width: 320, height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(alignment: .bottomLeading) {
                if let label = entry.episodeLabel {
                    Text(label)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.leading, 10)
                        .padding(.bottom, 16)
                }
            }
            .overlay(alignment: .bottom) {
                if entry.progress > 0 {
                    WatchProgressBar(fraction: entry.progress)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 6)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(.white.opacity(hover ? 0.25 : 0), lineWidth: 1)
            }
            .shadow(color: .black.opacity(hover ? 0.32 : 0), radius: 12, y: 6)
            .onHover { hover = $0 }
            .animation(.easeOut(duration: 0.18), value: hover)

            Text(entry.item.russianTitle)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .frame(width: 320, alignment: .leading)

            HStack(spacing: 6) {
                if let year = entry.item.year {
                    Text(verbatim: String(year)).font(.caption2).foregroundColor(.secondary)
                }
                if let rating = entry.item.rating {
                    Image(systemName: "star.fill")
                        .font(.system(size: 8))
                        .foregroundColor(.yellow)
                    Text(String(format: "%.1f", rating))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 320, alignment: .leading)
        }
        .frame(width: 320, alignment: .leading)
        .contentShape(Rectangle())
    }
}
