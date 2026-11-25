import Foundation

/// Централизованная конфигурация приложения.
///
/// Базовый адрес API по умолчанию — официальный `https://api.kinopub.com`.
/// Его можно переопределить, например на собственный прокси:
/// - переменная окружения `KINOPUB_API_BASE`
/// - ключ UserDefaults `kinopub.apiBase` (домен `com.kinopub.mac`)
enum AppConfig {
    /// Официальный адрес API kino.pub.
    static let defaultAPIBase = "https://api.kinopub.com"

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
}
