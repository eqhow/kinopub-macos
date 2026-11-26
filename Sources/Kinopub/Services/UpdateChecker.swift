import Foundation
import AppKit

/// Проверка обновлений через GitHub Releases.
///
/// При запуске смотрит последний релиз репозитория и, если он новее
/// установленной версии, отдаёт данные для окна обновления.
/// Сеть недоступна/лимит GitHub — молча ничего не показывает.
@MainActor
final class UpdateChecker: ObservableObject {
    struct UpdateInfo: Identifiable {
        let id = UUID()
        /// Версия без ведущей «v», например «0.1.2».
        let version: String
        /// Markdown-описание релиза (то, что написано в GitHub Release).
        let notes: String
        let releaseURL: URL
        let assetURL: URL?
        let assetName: String?
    }

    @Published var available: UpdateInfo?
    @Published var isDownloading = false
    @Published var downloadedFile: URL?
    @Published var error: String?

    private static let repo = "eqhow/kinopub-macos"

    /// Версия текущего приложения из Info.plist.
    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    // MARK: - Проверка

    func check() async {
        // Отладка: KINOPUB_DBG_UPDATE=0.1.2 принудительно показывает окно.
        if let forced = ProcessInfo.processInfo.environment["KINOPUB_DBG_UPDATE"], !forced.isEmpty {
            available = UpdateInfo(
                version: forced,
                notes: """
                ### Что нового
                - Плавное растворение hero-слайдера в фон
                - Акцентные кнопки в карточке тайтла
                - Убран лишний крестик закрытия трейлера

                ### Установка
                1. Скачайте архив.
                2. Распакуйте и замените **Kinopub.app** в «Программах».
                """,
                releaseURL: URL(string: "https://github.com/\(Self.repo)/releases/latest")!,
                assetURL: nil,
                assetName: nil
            )
            return
        }

        guard let url = URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest") else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Kinopub-macOS", forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let release = try? JSONDecoder().decode(Release.self, from: data)
        else { return }

        let latest = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        guard Self.isNewer(latest, than: currentVersion) else { return }

        let zip = release.assets.first { $0.name.lowercased().hasSuffix(".zip") }
        available = UpdateInfo(
            version: latest,
            notes: release.body ?? "",
            releaseURL: URL(string: release.htmlURL)
                ?? URL(string: "https://github.com/\(Self.repo)/releases/latest")!,
            assetURL: zip.flatMap { URL(string: $0.browserDownloadURL) },
            assetName: zip?.name
        )
    }

    // MARK: - Загрузка

    /// Скачивает zip обновления в «Загрузки» и показывает его в Finder.
    /// Автоматической подмены приложения нет намеренно: без подписи
    /// авто-установка небезопасна.
    func download() async {
        guard let info = available else { return }
        guard let assetURL = info.assetURL else {
            NSWorkspace.shared.open(info.releaseURL)
            return
        }

        isDownloading = true
        error = nil
        defer { isDownloading = false }

        guard let (tmp, response) = try? await URLSession.shared.download(from: assetURL),
              let http = response as? HTTPURLResponse, http.statusCode == 200
        else {
            error = "Не удалось скачать обновление"
            return
        }

        let name = info.assetName ?? "Kinopub-\(info.version).zip"
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        let destination = downloads.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: destination)

        do {
            try FileManager.default.moveItem(at: tmp, to: destination)
            downloadedFile = destination
            NSWorkspace.shared.activateFileViewerSelecting([destination])
        } catch {
            self.error = "Не удалось сохранить файл"
        }
    }

    // MARK: - Сравнение версий

    /// true, если `a` новее `b` (посравнивая числовые компоненты).
    static func isNewer(_ a: String, than b: String) -> Bool {
        let lhs = a.split(separator: ".").map { Int($0) ?? 0 }
        let rhs = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(lhs.count, rhs.count) {
            let l = i < lhs.count ? lhs[i] : 0
            let r = i < rhs.count ? rhs[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    // MARK: - DTO

    private struct Release: Decodable {
        let tagName: String
        let body: String?
        let htmlURL: String
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case body
            case htmlURL = "html_url"
            case assets
        }
    }

    private struct Asset: Decodable {
        let name: String
        let browserDownloadURL: String

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }
}
