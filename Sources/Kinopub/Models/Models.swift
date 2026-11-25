import Foundation

// MARK: - Items

struct KinopubItem: Codable, Identifiable, Hashable {
    let id: Int
    let title: String
    let type: String?
    let year: Int?
    let plot: String?
    let posters: Posters?
    let imdbRating: Double?
    let kinopoiskRating: Double?
    let imdb: Int?
    let quality: Int?
    let videos: [VideoFile]?
    let seasons: [Season]?
    let cast: String?
    let director: String?
    let trailer: Trailer?

    var is4K: Bool { quality == 2160 }
    /// Рейтинг только если он реально есть: API часто отдаёт 0,
    /// а «0.0» рядом с постером выглядит ошибкой. Берём IMDb, иначе Кинопоиск,
    /// но обязательно положительное значение.
    var rating: Double? {
        let candidates = [imdbRating, kinopoiskRating].compactMap { $0 }
        return candidates.first(where: { $0 > 0 })
    }
    /// Название на русском — обрезаем транскрипцию/перевод.
    var russianTitle: String {
        guard let slash = title.firstIndex(of: "/") else { return title }
        let before = title[..<slash]
        return before.trimmingCharacters(in: .whitespaces)
    }

    var isSeries: Bool { type == "serial" || !(seasons?.isEmpty ?? true) }

    var bestPoster: URL? {
        [posters?.big, posters?.medium, posters?.small]
            .compactMap { $0 }
            .compactMap(URL.init(string:))
            .first
    }

    var widePoster: URL? {
        [posters?.wide, posters?.big, posters?.medium]
            .compactMap { $0 }
            .compactMap(URL.init(string:))
            .first
    }

    var trailerURL: URL? { trailer?.bestURL }

    struct Trailer: Codable {
        let file: String?
        let url: String?

        var bestURL: URL? {
            // Берём только абсолютные ссылки: в списках API приходит
            // относительный `file` (/trailers/...), который AVPlayer не
            // может загрузить — трейлер молча остаётся чёрным.
            for raw in [url, file].compactMap({ $0 }) {
                if let u = URL(string: raw), u.scheme != nil, u.host != nil {
                    return u
                }
            }
            return nil
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, title, type, year, plot, posters, quality, videos, seasons, cast, director, imdb, trailer
        case imdbRating = "imdb_rating"
        case kinopoiskRating = "kinopoisk_rating"
    }

    static func == (lhs: KinopubItem, rhs: KinopubItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct Posters: Codable {
    let small: String?
    let medium: String?
    let big: String?
    let wide: String?
}

// MARK: - Filters

/// Жанр из `/v1/genres`. Поле `type` различает movie/music/docu/tvshow.
struct Genre: Codable, Identifiable, Hashable {
    let id: Int
    let title: String
    let type: String?
}

/// Страна из `/v1/countries`.
struct Country: Codable, Identifiable, Hashable {
    let id: Int
    let title: String
}

struct VideoFile: Codable {
    let title: String?
    let files: [MediaFile]?

    struct MediaFile: Codable {
        let quality: String?
        let w: Int?
        let h: Int?
        let url: VideoURL?

        var bestURL: URL? {
            [url?.hls4, url?.hls, url?.http]
                .compactMap { $0 }
                .compactMap(URL.init(string:))
                .first
        }
    }

    struct VideoURL: Codable {
        let hls4: String?
        let hls: String?
        let http: String?
    }
}

struct Season: Codable {
    let number: Int
    let title: String?
    let episodes: [Episode]?

    struct Episode: Codable, Identifiable {
        let episodeID: Int?
        let number: Int
        let snumber: Int?
        let title: String?
        let thumbnail: String?
        let duration: Int?
        let watching: WatchingInfo?
        let watched: Int?
        let files: [VideoFile.MediaFile]?

        var id: Int { episodeID ?? number }

        /// Кадр-скрин для карточки серии.
        var thumbnailURL: URL? { thumbnail.flatMap(URL.init(string:)) }

        /// Время остановки в секундах (0 — не начато).
        var watchTime: Int { max(watching?.time ?? 0, 0) }

        /// Доля просмотра серии (0…1).
        var progress: Double {
            if watched == 1 { return 1 }
            guard let duration, duration > 0 else { return 0 }
            return min(max(Double(watchTime) / Double(duration), 0), 1)
        }

        /// Название на русском (обрезаем транскрипцию).
        var russianTitle: String? {
            guard let t = title, !t.isEmpty else { return nil }
            guard let slash = t.firstIndex(of: "/") else { return t }
            return String(t[..<slash]).trimmingCharacters(in: .whitespaces)
        }

        struct WatchingInfo: Codable {
            let status: Int?
            let time: Int?
        }

        enum CodingKeys: String, CodingKey {
            case episodeID = "id"
            case number, snumber, title, thumbnail, duration, watching, watched, files
        }

        static func == (lhs: Episode, rhs: Episode) -> Bool { lhs.id == rhs.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }
}

// MARK: - Responses

struct KinopubResponse<T: Codable>: Codable {
    let status: Int
    let item: T?
    let items: [T]?
    let error: String?
}

// MARK: - History

/// Запись истории просмотров Kinopab. `media` — конкретная серия/файл,
/// на котором остановился пользователь, с её длительностью для прогресса.
struct HistoryEntry: Codable, Identifiable {
    let time: Int?
    let counter: Int?
    let firstSeen: Int?
    let lastSeen: Int?
    let media: HistoryMedia?
    let item: KinopubItem

    var id: Int { item.id }

    private enum CodingKeys: String, CodingKey {
        case time, counter, media, item
        case firstSeen = "first_seen"
        case lastSeen = "last_seen"
    }

    var progress: Double {
        guard let time, let duration = media?.duration, duration > 0 else { return 0 }
        return min(max(Double(time) / Double(duration), 0), 1)
    }

    /// Начато, но не досмотрено.
    var isInProgress: Bool {
        let p = progress
        return p > 0.01 && p < 0.98
    }

    var lastSeenDate: Date {
        Date(timeIntervalSince1970: TimeInterval(lastSeen ?? 0))
    }

    /// Широкий кадр для карточки «Продолжить просмотр».
    var thumbnail: URL? {
        (media?.thumbnail).flatMap(URL.init(string:)) ?? item.widePoster
    }

    /// Подпись серии: «S1 · E8». Только для сериалов — у фильмов
    /// API присылает snumber/number = 0, и «S0 · E1» выглядит ошибкой.
    var episodeLabel: String? {
        guard item.isSeries,
              let number, number > 0 else { return nil }
        if let season = snumber, season > 0 {
            return "S\(season) · E\(number)"
        }
        return "E\(number)"
    }

    private var number: Int? { media?.number }
    private var snumber: Int? { media?.snumber }
}

struct HistoryMedia: Codable {
    let duration: Int?
    let number: Int?
    let snumber: Int?
    let thumbnail: String?
    let title: String?
}

struct HistoryResponse: Codable {
    let status: Int?
    let history: [HistoryEntry]?
}

extension Array where Element == HistoryEntry {
    /// История приходит по одной записи на эпизод/просмотр, поэтому
    /// один и тот же сериал повторяется. Оставляем последнюю серию
    /// каждого тайтла (по `last_seen`), сохраняя порядок «свежие сверху».
    func dedupedByItem() -> [HistoryEntry] {
        var latest: [Int: HistoryEntry] = [:]
        for entry in self {
            let current = latest[entry.item.id]
            if current == nil || (entry.lastSeen ?? 0) > (current?.lastSeen ?? 0) {
                latest[entry.item.id] = entry
            }
        }
        return latest.values.sorted { a, b in (a.lastSeen ?? 0) > (b.lastSeen ?? 0) }
    }
}

struct TokenData: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

struct DeviceCodeData: Codable {
    let code: String
    let userCode: String
    let verificationUri: String?
    let expiresIn: Int
    let interval: Int

    enum CodingKeys: String, CodingKey {
        case code
        case userCode = "user_code"
        case verificationUri = "verification_uri"
        case expiresIn = "expires_in"
        case interval
    }
}

// MARK: - Player

struct PlayRequest: Codable, Hashable, Identifiable {
    let id: Int
    let title: String
    let url: URL
    /// Логотип тайтла для шапки плеера (вместо текстового названия).
    var logo: URL? = nil
    /// Подпись под логотипом (серия/трейлер/год).
    var subtitle: String? = nil
    /// Название конкретной серии, если есть.
    var episodeTitle: String? = nil
    /// С какого времени продолжать просмотр, секунды.
    var startAt: Double? = nil
}

// MARK: - Navigation

struct ItemRoute: Hashable {
    let item: KinopubItem
    let sourceID: String
}

// MARK: - User

struct UserResponse: Codable {
    let status: Int?
    let user: UserInfo?
    let error: String?
}

struct UserInfo: Codable {
    let username: String
    let subscription: Subscription?
    let profile: Profile?

    var displayName: String {
        let name = profile?.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? username : name
    }

    var subscriptionEnd: Date? {
        guard let subscription, subscription.active == true,
              let endTime = subscription.endTime, endTime > 0
        else { return nil }
        return Date(timeIntervalSince1970: endTime)
    }

    var avatarURL: URL? {
        guard var string = profile?.avatar, !string.isEmpty else { return nil }
        if string.hasPrefix("http://") {
            string = string.replacingOccurrences(of: "http://", with: "https://")
        }
        return URL(string: string)
    }

    struct Subscription: Codable {
        let active: Bool?
        let endTime: TimeInterval?
        let days: Double?

        enum CodingKeys: String, CodingKey {
            case active
            case endTime = "end_time"
            case days
        }
    }

    struct Profile: Codable {
        let name: String?
        let avatar: String?
    }
}
