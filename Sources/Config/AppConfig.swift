import Foundation

enum Companion: String, Codable, CaseIterable, Equatable {
    case qinglan
    case mobai
    case chengcheng
    case xingyu

    var displayName: String {
        switch self {
        case .qinglan: return "青岚"
        case .mobai: return "墨白"
        case .chengcheng: return "橙橙"
        case .xingyu: return "星语"
        }
    }

    var assetName: String {
        switch self {
        case .qinglan: return "Qinglan"
        case .mobai: return "Mobai"
        case .chengcheng: return "Chengcheng"
        case .xingyu: return "Xingyu"
        }
    }

    var voicePersona: String {
        switch self {
        case .qinglan: return "温暖陪练"
        case .mobai: return "沉稳追问"
        case .chengcheng: return "活力应援"
        case .xingyu: return "知性启发"
        }
    }

    var voiceId: String {
        switch self {
        case .qinglan: return "saturn_zh_female_nuanxinxuejie_tob"
        case .mobai: return "saturn_zh_male_chengshuzongcai_tob"
        case .chengcheng: return "saturn_zh_female_keainvsheng_tob"
        case .xingyu: return "saturn_zh_male_aojiaojingying_tob"
        }
    }
}

/// Dogfooding configuration. Defaults target a Mac dev host on the LAN.
/// Override at runtime via SettingsView; persisted in UserDefaults.
struct AppConfig: Codable, Equatable {
    var host: String
    var apiPort: Int
    var livekitPort: Int
    var devUserExternalId: String
    var seedRoundIndex: Int
    var selectedCompanion: Companion

    init(
        host: String,
        apiPort: Int,
        livekitPort: Int,
        devUserExternalId: String,
        seedRoundIndex: Int,
        selectedCompanion: Companion = .qinglan
    ) {
        self.host = host
        self.apiPort = apiPort
        self.livekitPort = livekitPort
        self.devUserExternalId = devUserExternalId
        self.seedRoundIndex = seedRoundIndex
        self.selectedCompanion = selectedCompanion
    }

    static let `default` = AppConfig(
        host: "192.168.1.14",  // Current Mac LAN IP for real-device testing.
                             // NOTE: this is a DHCP address and can change — if login/connect
                             // fails, re-check `ipconfig getifaddr en0` and update here (or in Settings).
                             // For the iOS Simulator instead, set host to 127.0.0.1 in Settings.
        apiPort: 8000,
        livekitPort: 7880,
        devUserExternalId: "apple:mock-pm-candidate-01",
        seedRoundIndex: 0,
        selectedCompanion: .qinglan
    )

    var apiBaseURL: URL { URL(string: "http://\(host):\(apiPort)")! }
    var livekitURL: String { "ws://\(host):\(livekitPort)" }

    private static let key = "AppConfig.v1"
    private static let legacyDefaultHosts: Set<String> = ["10.82.216.155", "192.168.1.9"]

    static func load(defaults: UserDefaults = .standard) -> AppConfig {
        guard let data = defaults.data(forKey: key),
              let cfg = try? JSONDecoder().decode(AppConfig.self, from: data)
        else { return .default }
        if legacyDefaultHosts.contains(cfg.host) {
            var migrated = cfg
            migrated.host = Self.default.host
            migrated.save(defaults: defaults)
            return migrated
        }
        return cfg
    }
    func save(defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: AppConfig.key)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case host
        case apiPort
        case livekitPort
        case devUserExternalId
        case seedRoundIndex
        case selectedCompanion
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        host = try values.decode(String.self, forKey: .host)
        apiPort = try values.decode(Int.self, forKey: .apiPort)
        livekitPort = try values.decode(Int.self, forKey: .livekitPort)
        devUserExternalId = try values.decode(String.self, forKey: .devUserExternalId)
        seedRoundIndex = try values.decode(Int.self, forKey: .seedRoundIndex)
        selectedCompanion = try values.decodeIfPresent(Companion.self, forKey: .selectedCompanion) ?? .qinglan
    }
}
