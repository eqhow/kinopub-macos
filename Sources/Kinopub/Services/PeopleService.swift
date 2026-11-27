import Foundation

struct Actor: Identifiable, Hashable {
    let id: String
    let name: String
    let photo: URL?
    let entityURI: String?
    let imdbID: String?
    /// Имя так, как его пишет Кинопаб в поле cast — по нему ищем каталог.
    let kinopubName: String?
    /// Заголовок статьи в английской Википедии — источник галереи фото.
    let wikipediaTitle: String?
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
    private var actorSearchCache: [String: [Actor]] = [:]
    private var photosCache: [String: [URL]] = [:]
    private var wikiTitleCache: [String: String] = [:]

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
        SELECT ?actor ?actorLabel ?image ?imdb ?article WHERE {
          ?film wdt:P345 "\(imdb)".
          ?film wdt:P161 ?actor.
          OPTIONAL { ?actor wdt:P18 ?image. }
          OPTIONAL { ?actor wdt:P345 ?imdb. }
          OPTIONAL {
            ?article schema:about ?actor;
                     schema:isPartOf <https://en.wikipedia.org/>.
          }
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
                        kinopubName: kinopubName(for: name, in: item.cast),
                        wikipediaTitle: row["article"].flatMap { articleTitle($0.value) }
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

    // MARK: - Actor search

    /// Поиск актёров по имени через EntitySearch Викиданных. Возвращает
    /// только людей с актёрскими профессиями, с фото и IMDb ID.
    func searchActors(_ text: String) async -> [Actor] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else { return [] }
        let key = normalize(query)
        if let cached = actorSearchCache[key] { return cached }

        let sparqlQuery = """
        SELECT ?person ?personLabel ?image ?imdb ?article WHERE {
          SERVICE wikibase:mwapi {
            bd:serviceParam wikibase:api "EntitySearch";
                            wikibase:endpoint "www.wikidata.org";
                            mwapi:search "\(sparqlEscape(query))";
                            mwapi:language "ru".
            ?person wikibase:apiOutputItem mwapi:item.
          }
          ?person wdt:P31 wd:Q5.
          ?person wdt:P106 ?occupation.
          VALUES ?occupation { wd:Q33999 wd:Q10800557 wd:Q10798782 wd:Q2405480 }
          OPTIONAL { ?person wdt:P18 ?image. }
          OPTIONAL { ?person wdt:P345 ?imdb. }
          OPTIONAL {
            ?article schema:about ?person;
                     schema:isPartOf <https://en.wikipedia.org/>.
          }
          SERVICE wikibase:label { bd:serviceParam wikibase:language "ru,en". }
        }
        LIMIT 15
        """

        guard let rows = try? await sparql(sparqlQuery) else { return [] }

        var actors: [Actor] = []
        var seen = Set<String>()

        for row in rows {
            guard let entity = row["person"]?.value,
                  let name = row["personLabel"]?.value.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty,
                  !name.hasPrefix("Q"),
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
                    kinopubName: nil,
                    wikipediaTitle: row["article"].flatMap { articleTitle($0.value) }
                )
            )
            if actors.count >= 12 { break }
        }

        actorSearchCache[key] = actors
        return actors
    }

    // MARK: - Photos

    /// Галерея фото актёра из английской Википедии (media-list статьи).
    func photos(for actor: Actor) async -> [URL] {
        let key = actor.entityURI ?? actor.imdbID ?? actor.name
        if let cached = photosCache[key] { return cached }

        var result: [URL] = []

        guard let title = await wikipediaTitle(for: actor),
              let encoded = title.addingPercentEncoding(
                  withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~"))
              ),
              let url = URL(string: "https://en.wikipedia.org/api/rest_v1/page/media-list/\(encoded)")
        else { photosCache[key] = []; return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("Kinopub-macOS/1.0 (personal app)", forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let list = try? JSONDecoder().decode(MediaListResponse.self, from: data)
        else { photosCache[key] = []; return [] }

        let actorKey = title.lowercased() // wikipedia title → "leonardo_dicaprio"
        var seen = Set<String>()

        for item in list.items {
            guard let url = galleryURL(from: item) else { continue }

            guard let itemTitle = item.title else { continue }
            let lowerTitle = itemTitle.lowercased()

            // Только портреты: lead-изображение или файл с именем актёра
            let isLead = item.leadImage == true
            let matchesActor = lowerTitle.contains(actorKey)
            guard isLead || matchesActor else { continue }

            guard seen.insert(url.absoluteString).inserted else { continue }
            result.append(url)
            if result.count >= 6 { break }
        }

        // Скрываем секцию если ≤1 фото
        if result.count <= 1 { result = [] }

        photosCache[key] = result
        return result
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

    private func sparqlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
    }

    private func articleTitle(_ value: String) -> String? {
        guard let url = URL(string: value) else { return nil }
        let name = url.lastPathComponent
        guard !name.isEmpty else { return nil }
        return name.removingPercentEncoding ?? name
    }

    private func wikipediaTitle(for actor: Actor) async -> String? {
        if let title = actor.wikipediaTitle { return title }
        guard let entity = actor.entityURI else { return nil }
        if let cached = wikiTitleCache[entity] { return cached }

        let query = """
        SELECT ?article WHERE {
          <\(entity)> schema:about ?article;
                      schema:isPartOf <https://en.wikipedia.org/>.
        }
        LIMIT 1
        """

        guard let rows = try? await sparql(query),
              let value = rows.first?["article"]?.value,
              let title = articleTitle(value)
        else { return nil }

        wikiTitleCache[entity] = title
        return title
    }

    private func galleryURL(from item: MediaListResponse.Item) -> URL? {
        guard item.type == "image",
              let title = item.title,
              let source = item.srcset?.first?.src
        else { return nil }

        let lower = title.lowercased()
        let banned = [
            "signature", "autograph", "logo", "icon", "map of", "commons-",
            "wikimedia", "question_book", "edit-clear", "ambox", "portal",
            "handprint", "grave", "tomb", "statue", "wax figure", "poster",
            "screenshot", "trailer", "footprint",
            "walks_with", "with_", "and_", "secretary", "press_",
            "premiere", "after_", "party", "award", "red_carpet",
        ]
        if banned.contains(where: { lower.contains($0) }) { return nil }

        var value = source
        if value.hasPrefix("//") { value = "https:" + value }
        guard var components = URLComponents(string: value) else { return nil }
        components.query = nil
        guard let url = components.url else { return nil }

        let ext = url.pathExtension.lowercased()
        guard ["jpg", "jpeg", "png", "webp", "heic"].contains(ext) else { return nil }
        return url
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
                    kinopubName: $0,
                    wikipediaTitle: nil
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

    private struct MediaListResponse: Decodable {
        let items: [Item]

        struct Item: Decodable {
            let title: String?
            let type: String?
            let leadImage: Bool?
            let srcset: [Source]?

            struct Source: Decodable {
                let src: String
            }
        }
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
