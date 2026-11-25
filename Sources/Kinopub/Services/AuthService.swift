import Foundation

@MainActor
final class AuthService: ObservableObject {
    @Published private(set) var isAuthenticated = false
    @Published private(set) var isAuthorizing = false
    @Published var authError: String?

    var baseURL: String { AppConfig.apiBase }

    private let clientID = "xbmc"
    private let clientSecret = "cgg3gtifu46urtfp2zp1nqtba0k2ezxh"
    private let storeKey = "kinopub.tokens.v1"
    private let fallbackVerifyURL = URL(string: "https://kino.watch/device")!

    private(set) var accessToken: String?
    private var refreshToken: String?
    private var expiresAt: TimeInterval = 0
    private var pollTask: Task<Void, Never>?

    private struct StoredTokens: Codable {
        var access: String
        var refresh: String
        var expiresAt: TimeInterval
    }

    init() {
        restoreSession()
    }

    // MARK: - Device flow

    struct DeviceAuth {
        let userCode: String
        let verificationURL: URL
    }

    func startDeviceAuth() async throws -> DeviceAuth {
        cancelAuthorization()
        authError = nil

        var req = URLRequest(url: URL(string: "\(baseURL)/oauth2/device")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 30
        req.httpBody = form([
            "grant_type": "device_code",
            "client_id": clientID,
            "client_secret": clientSecret,
        ])

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AuthError.server(serverError(from: data) ?? "Не удалось получить код устройства")
        }

        let device = try JSONDecoder().decode(DeviceCodeData.self, from: data)
        let verifyURL = device.verificationUri.flatMap(URL.init(string:)) ?? fallbackVerifyURL

        isAuthorizing = true
        let code = device.code
        let interval = max(device.interval, 2)
        let expires = max(device.expiresIn, 60)
        pollTask = Task { [weak self] in
            await self?.poll(code: code, interval: interval, expires: expires)
        }

        return DeviceAuth(userCode: device.userCode, verificationURL: verifyURL)
    }

    func cancelAuthorization() {
        pollTask?.cancel()
        pollTask = nil
        isAuthorizing = false
    }

    private func poll(code: String, interval initialInterval: Int, expires: Int) async {
        let deadline = Date().addingTimeInterval(TimeInterval(expires))
        var interval = max(initialInterval, 2)

        while !Task.isCancelled, Date() < deadline {
            do {
                try await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
            } catch {
                return
            }

            var req = URLRequest(url: URL(string: "\(baseURL)/oauth2/device")!)
            req.httpMethod = "POST"
            req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            req.timeoutInterval = 30
            req.httpBody = form([
                "grant_type": "device_token",
                "client_id": clientID,
                "client_secret": clientSecret,
                "code": code,
            ])

            do {
                let (data, response) = try await URLSession.shared.data(for: req)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0

                if status == 200, let token = try? JSONDecoder().decode(TokenData.self, from: data) {
                    finishAuthorization(token)
                    return
                }

                switch serverError(from: data) {
                case "authorization_pending":
                    continue
                case "slow_down":
                    interval += 5
                    continue
                case "expired_token":
                    fail("Код истёк. Нажмите «Войти», чтобы получить новый.")
                    return
                case "access_denied":
                    fail("Вход отклонён на сайте.")
                    return
                default:
                    continue
                }
            } catch is CancellationError {
                return
            } catch {
                // Сетевая ошибка — пробуем дальше до истечения кода.
                continue
            }
        }

        if !Task.isCancelled {
            fail("Время ожидания истекло. Попробуйте снова.")
        }
    }

    private func finishAuthorization(_ token: TokenData) {
        apply(token)
        persistSession()
        isAuthorizing = false
        authError = nil
        isAuthenticated = true
        Task { [weak self] in
            try? await self?.notifyDevice()
        }
    }

    private func fail(_ message: String) {
        isAuthorizing = false
        authError = message
    }

    private func apply(_ token: TokenData) {
        accessToken = token.accessToken
        refreshToken = token.refreshToken
        expiresAt = Date().timeIntervalSince1970 + TimeInterval(token.expiresIn)
    }

    // MARK: - Tokens

    func ensureValidToken() async throws {
        if accessToken != nil, Date().timeIntervalSince1970 < expiresAt - 120 { return }
        try await refresh(force: true)
    }

    func refresh(force: Bool) async throws {
        if !force, accessToken != nil, Date().timeIntervalSince1970 < expiresAt - 120 { return }
        guard let refresh = refreshToken else { throw AuthError.noToken }

        var req = URLRequest(url: URL(string: "\(baseURL)/oauth2/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 30
        req.httpBody = form([
            "grant_type": "refresh_token",
            "client_id": clientID,
            "client_secret": clientSecret,
            "refresh_token": refresh,
        ])

        let (data, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let token = try? JSONDecoder().decode(TokenData.self, from: data) else {
            logout()
            throw AuthError.sessionExpired
        }

        apply(token)
        persistSession()
    }

    func logout() {
        cancelAuthorization()
        accessToken = nil
        refreshToken = nil
        expiresAt = 0
        isAuthenticated = false
        authError = nil
        UserDefaults.standard.removeObject(forKey: storeKey)
    }

    private func persistSession() {
        guard let access = accessToken, let refresh = refreshToken else { return }
        let stored = StoredTokens(access: access, refresh: refresh, expiresAt: expiresAt)
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: storeKey)
        }
    }

    private func restoreSession() {
        guard let data = UserDefaults.standard.data(forKey: storeKey),
              let stored = try? JSONDecoder().decode(StoredTokens.self, from: data) else { return }
        accessToken = stored.access
        refreshToken = stored.refresh
        expiresAt = stored.expiresAt
        isAuthenticated = true
    }

    // MARK: - Helpers

    private func notifyDevice() async throws {
        guard let accessToken else { return }
        var req = URLRequest(url: URL(string: "\(baseURL)/v1/device/notify")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "title": "Kinopub macOS",
            "software": "Kinopub macOS",
            "hardware": "Mac",
        ])
        _ = try await URLSession.shared.data(for: req)
    }

    private func serverError(from data: Data) -> String? {
        struct Payload: Decodable { let error: String? }
        return (try? JSONDecoder().decode(Payload.self, from: data))?.error
    }

    private func form(_ params: [String: String]) -> Data? {
        var components = URLComponents()
        components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.percentEncodedQuery?.data(using: .utf8)
    }

    enum AuthError: LocalizedError {
        case noToken
        case sessionExpired
        case server(String)

        var errorDescription: String? {
            switch self {
            case .noToken: return "Требуется вход в аккаунт"
            case .sessionExpired: return "Сессия истекла, войдите заново"
            case .server(let message): return message
            }
        }
    }
}
