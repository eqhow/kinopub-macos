import Foundation

/// Подтягивает логотип и широкий кадр (backdrop) из Cinemeta — публичного
/// каталога Stremio, который отдаёт арт из TMDB/Fanart без API-ключа.
@MainActor
final class MetadataService: ObservableObject {
    static let shared = MetadataService()

    struct Artwork {
        var logo: URL?
        var backdrop: URL?
    }

    private var cache: [Int: Artwork] = [:]

    func artwork(for item: KinopubItem) async -> Artwork? {
        if let cached = cache[item.id] { return cached }
        guard let artwork = await fetch(item) else { return nil }
        cache[item.id] = artwork
        return artwork
    }

    private func fetch(_ item: KinopubItem) async -> Artwork? {
        let type = item.type == "serial" ? "series" : "movie"
        let alternativeType = type == "series" ? "movie" : "series"

        // В API есть IMDb ID — сначала пробуем точное совпадение без поиска.
        if let imdb = item.imdb {
            let id = "tt\(imdb)"
            if let artwork = await resolve(type: type, alternativeType: alternativeType, id: id) {
                return artwork
            }
        }

        for query in searchQueries(for: item) {
            guard let searchURL = searchURL(type: type, query: query),
                  let results: SearchResponse = try? await get(searchURL),
                  let hit = pick(results.metas, year: item.year)
            else { continue }

            // По найденному IMDb-идентификатору тянем логотип из Metahub
            // (там логотипы есть и для аниме/сериалов, чего нет в Cinemeta).
            if hit.id.hasPrefix("tt"),
               let artwork = await resolve(type: type, alternativeType: alternativeType, id: hit.id) {
                return artwork
            }

            if let backdrop = hit.background.flatMap(url(from:)) {
                return Artwork(logo: nil, backdrop: backdrop)
            }
        }

        return nil
    }

    /// Логотип + фон по IMDb-идентификатору из нескольких источников.
    private func resolve(type: String, alternativeType: String, id: String) async -> Artwork? {
        // 1) Metahub — самый надёжный источник прозрачных логотипов.
        let logo = await metahubLogo(id: id)

        // 2) Cinemeta — логотип (если Metahub пуст) и широкий кадр.
        var cinemetaLogo: URL?
        var backdrop: URL?
        for candidate in [type, alternativeType] {
            if let metaURL = metaURL(type: candidate, id: id),
               let response: MetaResponse = try? await get(metaURL),
               let art = artwork(from: response.meta) {
                if cinemetaLogo == nil { cinemetaLogo = art.logo }
                if backdrop == nil { backdrop = art.backdrop }
                if cinemetaLogo != nil && backdrop != nil { break }
            }
        }

        let finalLogo = logo ?? cinemetaLogo
        guard finalLogo != nil || backdrop != nil else { return nil }
        return Artwork(logo: finalLogo, backdrop: backdrop)
    }

    /// Прозрачный логотип из публичного Metahub (Stremio) по IMDb ID.
    private func metahubLogo(id: String) async -> URL? {
        guard id.hasPrefix("tt"),
              let url = URL(string: "https://images.metahub.space/logo/large/\(id)/img"),
              await isAvailable(url)
        else { return nil }
        return url
    }

    /// Проверяет, что по URL реально отдаётся картинка (а не 404).
    private func isAvailable(_ url: URL) async -> Bool {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("Kinopub-macOS/1.0", forHTTPHeaderField: "User-Agent")
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              (http.mimeType ?? "").hasPrefix("image")
        else { return false }
        return true
    }

    private func artwork(from meta: Meta) -> Artwork? {
        let artwork = Artwork(
            logo: meta.logo.flatMap(url(from:)),
            backdrop: meta.background.flatMap(url(from:))
        )
        return artwork.logo != nil || artwork.backdrop != nil ? artwork : nil
    }

    // MARK: - Search

    private func searchQueries(for item: KinopubItem) -> [String] {
        let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = title
            .components(separatedBy: " / ")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard parts.count > 1 else { return [title] }

        // Кино.паб обычно отдаёт «Русское название / Original Title» —
        // сначала ищем по оригиналу, потом по русскому.
        var queries: [String] = []
        if let original = parts.last { queries.append(original) }
        if let localized = parts.first, !queries.contains(localized) { queries.append(localized) }
        return queries
    }

    private func pick(_ hits: [SearchHit], year: Int?) -> SearchHit? {
        guard !hits.isEmpty else { return nil }

        if let year {
            if let exact = hits.first(where: { $0.releaseYear == year }) { return exact }
            if let near = hits.first(where: {
                guard let release = $0.releaseYear else { return false }
                return abs(release - year) <= 1
            }) { return near }
        }

        return hits.first
    }

    // MARK: - Networking

    private func get<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Kinopub-macOS/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func searchURL(type: String, query: String) -> URL? {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=?+/#")
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "https://v3-cinemeta.strem.io/catalog/\(type)/top/search=\(encoded).json")
    }

    private func metaURL(type: String, id: String) -> URL? {
        URL(string: "https://v3-cinemeta.strem.io/meta/\(type)/\(id).json")
    }

    private func url(from string: String) -> URL? {
        guard var components = URLComponents(string: string) else { return nil }
        if components.path.contains("/background/medium/") {
            components.path = components.path.replacingOccurrences(
                of: "/background/medium/",
                with: "/background/large/"
            )
        }
        return components.url
    }

    // MARK: - DTO

    private struct SearchResponse: Decodable {
        let metas: [SearchHit]
    }

    private struct SearchHit: Decodable {
        let id: String
        let releaseInfo: String?
        let background: String?

        var releaseYear: Int? {
            guard let releaseInfo,
                  let range = releaseInfo.range(of: #"\d{4}"#, options: .regularExpression)
            else { return nil }
            return Int(releaseInfo[range])
        }
    }

    private struct MetaResponse: Decodable {
        let meta: Meta
    }

    private struct Meta: Decodable {
        let logo: String?
        let background: String?
    }
}
