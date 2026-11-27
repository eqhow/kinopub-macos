import Foundation

@MainActor
final class APIClient: ObservableObject {
    private var baseURL: String { AppConfig.apiBase }
    private unowned let auth: AuthService
    private let decoder = JSONDecoder()

    init(auth: AuthService) { self.auth = auth }

    // MARK: - Public API

    func fetch<T: Codable>(_ path: String, params: [String: String] = [:]) async throws -> T {
        try await request(path: path, params: params) { data in
            let wrapper = try JSONDecoder().decode(KinopubResponse<T>.self, from: data)
            guard let item = wrapper.item else {
                throw APIError.server(wrapper.error ?? "Нет данных")
            }
            return item
        }
    }

    func list<T: Codable>(_ path: String, params: [String: String] = [:]) async throws -> [T] {
        try await request(path: path, params: params) { data in
            let wrapper = try JSONDecoder().decode(KinopubResponse<T>.self, from: data)
            return wrapper.items ?? []
        }
    }

    func hotMovies() async throws -> [KinopubItem] { try await list("/v1/items/hot", params: ["perpage": "47", "type": "movie"]) }
    func hotSeries() async throws -> [KinopubItem] { try await list("/v1/items/hot", params: ["perpage": "47", "type": "serial"]) }
    func popularMovies() async throws -> [KinopubItem] { try await list("/v1/items/popular", params: ["perpage": "47", "type": "movie"]) }
    func popularSeries() async throws -> [KinopubItem] { try await list("/v1/items/popular", params: ["perpage": "47", "type": "serial"]) }
    func freshMovies() async throws -> [KinopubItem] { try await list("/v1/items/fresh", params: ["perpage": "47", "type": "movie"]) }
    func freshSeries() async throws -> [KinopubItem] { try await list("/v1/items/fresh", params: ["perpage": "47", "type": "serial"]) }
    func movies(page: Int = 0) async throws -> [KinopubItem] { try await list("/v1/items", params: ["page": "\(page)", "perpage": "47", "type": "movie"]) }
    func series(page: Int = 0) async throws -> [KinopubItem] { try await list("/v1/items", params: ["page": "\(page)", "perpage": "47", "type": "serial"]) }
    func search(_ query: String) async throws -> [KinopubItem] { try await list("/v1/items/search", params: ["q": query]) }
    func items(actor: String) async throws -> [KinopubItem] { try await list("/v1/items", params: ["actor": actor, "perpage": "47"]) }
    func history() async throws -> [HistoryEntry] {
        try await request(path: "/v1/history", params: ["perpage": "47"]) { data in
            let wrapper = try? JSONDecoder().decode(HistoryResponse.self, from: data)
            return wrapper?.history ?? []
        }
    }
    func watchingMovies() async throws -> [KinopubItem] { try await list("/v1/watching/movies", params: ["perpage": "47"]) }
    func watchingSeries() async throws -> [KinopubItem] { try await list("/v1/watching/serials", params: ["perpage": "47", "subscribed": "1"]) }
    func similar(to id: Int) async throws -> [KinopubItem] { try await list("/v1/items/similar", params: ["id": "\(id)"]) }
    func item(id: Int) async throws -> KinopubItem { try await fetch("/v1/items/\(id)") }

    /// Сообщить серверу прогресс просмотра.
    func markWatch(id: Int, time: Int, video: Int? = nil, season: Int? = nil) async throws {
        var params: [String: String] = ["id": "\(id)", "time": "\(time)"]
        if let video { params["video"] = "\(video)" }
        if let season { params["season"] = "\(season)" }
        let _: String? = try? await request(path: "/v1/watching/marktime", params: params) { data in
            // API возвращает {"status":200,"error":null} при успехе
            guard let wrapper = try? JSONDecoder().decode(KinopubResponse<String>.self, from: data),
                  wrapper.error == nil else {
                throw APIError.server("Ошибка отметки времени")
            }
            return nil
        }
    }

    // MARK: - Filters

    /// Жанры. В API они разделены по типу (movie/music/docu/tvshow);
    /// для фильмов и сериалов используем набор `movie`.
    func genres() async throws -> [Genre] {
        let all: [Genre] = try await list("/v1/genres")
        return all.filter { $0.type == "movie" }
    }

    func countries() async throws -> [Country] { try await list("/v1/countries") }

    /// Каталог с фильтрами: `/v1/items?type=…&genre=…&country=…&year=…`.
    /// `type == nil` — и фильмы, и сериалы (нужно для аниме/мультфильмов).
    func browse(type: String?, genre: Int?, country: Int?, year: Int?) async throws -> [KinopubItem] {
        var params = ["perpage": "47"]
        if let type { params["type"] = type }
        if let genre { params["genre"] = "\(genre)" }
        if let country { params["country"] = "\(country)" }
        if let year { params["year"] = "\(year)" }
        return try await list("/v1/items", params: params)
    }
    func user() async throws -> UserInfo {
        try await request(path: "/v1/user", params: [:]) { data in
            let wrapper = try JSONDecoder().decode(UserResponse.self, from: data)
            guard let user = wrapper.user else {
                throw APIError.server(wrapper.error ?? "Нет профиля")
            }
            return user
        }
    }
    /// Страница подборок Kinopab с числом всего страниц для догрузки.
    func collectionsPage(_ page: Int) async throws -> (items: [KinopubItem], totalPages: Int) {
        try await request(path: "/v1/collections",
                          params: ["perpage": "50", "page": "\(page)"]) { data in
            struct Raw: Codable {
                let items: [KinopubItem]?
                let pagination: Pagination?
                struct Pagination: Codable { let total: Int? }
            }
            let raw = try JSONDecoder().decode(Raw.self, from: data)
            return (raw.items ?? [], max(1, raw.pagination?.total ?? 1))
        }
    }

    /// Поиск подборок по названию.
    func searchCollections(title: String) async throws -> [KinopubItem] {
        try await list("/v1/collections", params: ["title": title, "perpage": "24"])
    }

    /// Элементы подборки (фильмы/сериалы), входящие в коллекцию.
    func collectionItems(id: Int) async throws -> [KinopubItem] {
        try await list("/v1/collections/view", params: ["id": "\(id)"])
    }

    // MARK: - Transport

    private func request<T>(path: String, params: [String: String], decode: (Data) throws -> T) async throws -> T {
        try await auth.ensureValidToken()

        for attempt in 0...1 {
            guard let token = auth.accessToken else { throw AuthService.AuthError.noToken }

            var components = URLComponents(string: "\(baseURL)\(path)")!
            var queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
            queryItems.append(URLQueryItem(name: "rand", value: UUID().uuidString))
            components.queryItems = queryItems

            var req = URLRequest(url: components.url!)
            req.timeoutInterval = 30
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else { throw APIError.badResponse }

            if http.statusCode == 401 {
                if attempt == 0 {
                    try await auth.refresh(force: true)
                    continue
                }
                auth.logout()
                throw AuthService.AuthError.sessionExpired
            }

            guard (200..<300).contains(http.statusCode) else {
                let wrapper = try? decoder.decode(KinopubResponse<KinopubItem>.self, from: data)
                throw APIError.server(wrapper?.error ?? "Ошибка сервера (\(http.statusCode))")
            }

            return try decode(data)
        }

        throw APIError.badResponse
    }

    enum APIError: LocalizedError {
        case badResponse
        case server(String)

        var errorDescription: String? {
            switch self {
            case .badResponse: return "Ошибка сервера"
            case .server(let message): return message
            }
        }
    }
}
