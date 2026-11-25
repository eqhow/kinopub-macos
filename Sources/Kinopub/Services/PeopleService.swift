import Foundation

struct Actor: Identifiable, Hashable {
    let id: String
    let name: String
    let photo: URL?
    let entityURI: String?
    let imdbID: String?
    /// Имя так, как его пишет Кинопаб в поле cast — по нему ищем каталог.
    let kinopubName: String?
}

struct FilmCredit: Identifiable, Hashable {
    let id: String
    let title: String
    let year: Int?
    let imdbID: String?
}

/// Актёры и фильмография из Wikidata: фото, точный состав по IMDb ID,
/// список работ. Без API-ключей и без привязки к Кинопоиску.
@MainActor
final class PeopleService {
    static let shared = PeopleService()

    private var castCache: [String: [Actor]] = [:]
    private var filmsCache: [String: [FilmCredit]] = [:]

    // MARK: - Public

    func cast(for item: KinopubItem) async -> [Actor] {
        let key = imdbID(for: item.imdb) ?? "item-\(item.id)"
        if let cached = castCache[key] { return cached }

        guard let imdb = imdbID(for: item.imdb) else {
            let fallback = fallbackCast(item.cast)
            castCache[key] = fallback
            return fallback
        }

        let query = """
        SELECT ?actor ?actorLabel ?image ?imdb WHERE {
          ?film wdt:P345 "\(imdb)".
          ?film wdt:P161 ?actor.
          OPTIONAL { ?actor wdt:P18 ?image. }
          OPTIONAL { ?actor wdt:P345 ?imdb. }
          SERVICE wikibase:label { bd:serviceParam wikibase:language "ru,en". }
        }
        LIMIT 40
        """

        var actors: [Actor] = []
        var seen = Set<String>()

        if let rows = try? await sparql(query) {
            for row in rows {
                guard let entity = row["actor"]?.value,
                      let name = row["actorLabel"]?.value,
                      !name.isEmpty,
                      seen.insert(entity).inserted
                else { continue }

                let imdb = row["imdb"]?.value
                actors.append(
                    Actor(
                        id: imdb ?? entity,
                        name: name,
                        photo: row["image"].flatMap { commonsURL($0.value) },
                        entityURI: entity,
                        imdbID: imdb,
                        kinopubName: kinopubName(for: name, in: item.cast)
                    )
                )
            }
        }

        let result = actors.isEmpty ? fallbackCast(item.cast) : ordered(actors, by: item.cast)
        castCache[key] = result
        return result
    }

    func filmography(for actor: Actor, excluding imdb: String?) async -> [FilmCredit] {
        let all = await allFilms(for: actor)
        guard let imdb else { return all }
        return all.filter { $0.imdbID != imdb }
    }

    // MARK: - Filmography

    private func allFilms(for actor: Actor) async -> [FilmCredit] {
        guard let entity = actor.entityURI else { return [] }
        if let cached = filmsCache[entity] { return cached }

        let query = """
        SELECT ?film ?filmLabel (MIN(?date) AS ?firstDate) (SAMPLE(?filmImdb) AS ?filmImdb) WHERE {
          BIND(<\(entity)> AS ?person)
          ?film wdt:P161 ?person.
          OPTIONAL { ?film wdt:P577 ?date. }
          OPTIONAL { ?film wdt:P345 ?filmImdb. }
          SERVICE wikibase:label { bd:serviceParam wikibase:language "ru,en". }
        }
        GROUP BY ?film ?filmLabel
        ORDER BY DESC(?firstDate)
        LIMIT 60
        """

        guard let rows = try? await sparql(query) else { return [] }

        var films: [FilmCredit] = []
        var seen = Set<String>()

        for row in rows {
            guard let uri = row["film"]?.value,
                  let title = row["filmLabel"]?.value.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty,
                  seen.insert(uri).inserted,
                  !isPlaceholder(title)
            else { continue }

            films.append(
                FilmCredit(
                    id: uri,
                    title: title,
                    year: row["firstDate"].flatMap { year(from: $0.value) },
                    imdbID: row["filmImdb"]?.value
                )
            )
        }

        filmsCache[entity] = films
        return films
    }

    // MARK: - Helpers

    func imdbID(for value: Int?) -> String? {
        guard let value else { return nil }
        return String(format: "tt%07d", value)
    }

    private func ordered(_ actors: [Actor], by cast: String?) -> [Actor] {
        guard let cast, !cast.isEmpty else { return actors }

        let names = cast
            .components(separatedBy: ",")
            .map { normalize($0) }
            .filter { !$0.isEmpty }

        return actors.sorted { lhs, rhs in
            let left = names.firstIndex(where: { matches($0, normalize(lhs.name)) }) ?? Int.max
            let right = names.firstIndex(where: { matches($0, normalize(rhs.name)) }) ?? Int.max
            if left == right { return lhs.name < rhs.name }
            return left < right
        }
    }

    private func matches(_ castName: String, _ actorName: String) -> Bool {
        guard !castName.isEmpty, !actorName.isEmpty else { return false }
        if castName == actorName { return true }
        return castName.hasPrefix(actorName) || actorName.hasPrefix(castName)
    }

    private func normalize(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "ru_RU"))
            .replacingOccurrences(of: "ё", with: "е")
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func kinopubName(for actor: String, in cast: String?) -> String? {
        guard let cast else { return nil }
        let target = normalize(actor)
        return cast
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { matches(normalize($0), target) }
    }

    private func fallbackCast(_ cast: String?) -> [Actor] {
        guard let cast else { return [] }
        return cast
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(14)
            .map {
                Actor(
                    id: "name-\($0)",
                    name: $0,
                    photo: nil,
                    entityURI: nil,
                    imdbID: nil,
                    kinopubName: $0
                )
            }
    }

    private func isPlaceholder(_ title: String) -> Bool {
        let lower = title.lowercased()
        return lower.hasPrefix("неизвест")
            || lower.hasPrefix("unknown")
            || lower.hasPrefix("tba")
    }

    private func year(from value: String) -> Int? {
        guard let range = value.range(of: #"\d{4}"#, options: .regularExpression) else { return nil }
        return Int(value[range])
    }

    private func commonsURL(_ value: String) -> URL? {
        guard var components = URLComponents(string: value) else { return nil }
        components.scheme = "https"
        components.queryItems = [URLQueryItem(name: "width", value: "400")]
        return components.url
    }

    // MARK: - SPARQL

    private func sparql(_ query: String) async throws -> [[String: SPARQLValue]] {
        var components = URLComponents(string: "https://query.wikidata.org/sparql")!
        components.queryItems = [
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "query", value: query),
        ]

        guard let url = components.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        request.setValue("application/sparql-results+json", forHTTPHeaderField: "Accept")
        request.setValue("Kinopub-macOS/1.0 (personal app)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(SPARQLResponse.self, from: data)
        return decoded.results.bindings
    }

    private struct SPARQLResponse: Decodable {
        let results: Results

        struct Results: Decodable {
            let bindings: [[String: SPARQLValue]]
        }
    }

    private struct SPARQLValue: Decodable {
        let value: String
    }
}
