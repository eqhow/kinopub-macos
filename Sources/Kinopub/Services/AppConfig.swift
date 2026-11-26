import Foundation

/// Централизованная конфигурация приложения.
///
/// Базовый адрес API по умолчанию — официальный `https://api.service-kp.com`.
/// Его можно переопределить, например на собственный прокси:
/// - переменная окружения `KINOPUB_API_BASE`
/// - ключ UserDefaults `kinopub.apiBase` (домен `com.kinopub.mac`)
enum AppConfig {
    /// Официальный адрес API kino.pub.
    static let defaultAPIBase = "https://api.service-kp.com"

    /// Действующий базовый адрес API с учётом переопределений.
    static var apiBase: String {
        if let env = ProcessInfo.processInfo.environment["KINOPUB_API_BASE"],
           !env.isEmpty {
            return env
        }
        if let stored = UserDefaults.standard.string(forKey: "kinopub.apiBase"),
           !stored.isEmpty {
            return stored
        }
        return defaultAPIBase
    }

    /// Ключ TMDB (v3) — нужен только для русских логотипов.
    /// Можно задать через `KINOPUB_TMDB_KEY` или `defaults write com.kinopub.mac kinopub.tmdbKey "..."`
    static var tmdbAPIKey: String? {
        if let env = ProcessInfo.processInfo.environment["KINOPUB_TMDB_KEY"],
           !env.isEmpty {
            return env
        }
        if let stored = UserDefaults.standard.string(forKey: "kinopub.tmdbKey"),
           !stored.isEmpty {
            return stored
        }
        return nil
    }
}
