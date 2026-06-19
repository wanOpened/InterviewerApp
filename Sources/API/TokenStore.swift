import Foundation

protocol TokenProviding {
    var accessToken: String? { get }
}

final class TokenStore: TokenProviding {
    private enum Keys {
        static let accessToken = "auth.accessToken"
        static let refreshToken = "auth.refreshToken"
        static let expiresAt = "auth.expiresAt"
    }

    private let defaults: UserDefaults
    private let now: () -> Date

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
    }

    var accessToken: String? {
        guard let token = defaults.string(forKey: Keys.accessToken), !token.isEmpty else {
            return nil
        }
        guard let expiresAt, expiresAt > now() else {
            return nil
        }
        return token
    }

    var refreshToken: String? {
        defaults.string(forKey: Keys.refreshToken)
    }

    var expiresAt: Date? {
        guard defaults.object(forKey: Keys.expiresAt) != nil else { return nil }
        return Date(timeIntervalSince1970: defaults.double(forKey: Keys.expiresAt))
    }

    var isLoggedIn: Bool {
        accessToken != nil
    }

    func save(access: String, refresh: String, expiresAt: Date) {
        // TODO: 迁 Keychain
        defaults.set(access, forKey: Keys.accessToken)
        defaults.set(refresh, forKey: Keys.refreshToken)
        defaults.set(expiresAt.timeIntervalSince1970, forKey: Keys.expiresAt)
    }

    func clear() {
        defaults.removeObject(forKey: Keys.accessToken)
        defaults.removeObject(forKey: Keys.refreshToken)
        defaults.removeObject(forKey: Keys.expiresAt)
    }
}
