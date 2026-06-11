import Foundation
import XCTest
@testable import InterviewerApp

final class AppConfigTests: XCTestCase {
    func test_defaultHostTargetsCurrentMacLANAddress() {
        XCTAssertEqual(AppConfig.default.host, "192.168.1.9")
    }

    func test_loadMigratesLegacyHostAndPreservesUserSettings() {
        let suiteName = "AppConfigTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let legacy = AppConfig(
            host: "10.82.216.155",
            apiPort: 9000,
            livekitPort: 7999,
            devUserExternalId: "apple:preserved-user",
            seedRoundIndex: 4,
            selectedCompanion: .mobai
        )
        legacy.save(defaults: defaults)

        let loaded = AppConfig.load(defaults: defaults)

        XCTAssertEqual(loaded.host, "192.168.1.9")
        XCTAssertEqual(loaded.apiPort, 9000)
        XCTAssertEqual(loaded.livekitPort, 7999)
        XCTAssertEqual(loaded.devUserExternalId, "apple:preserved-user")
        XCTAssertEqual(loaded.seedRoundIndex, 4)
        XCTAssertEqual(loaded.selectedCompanion, .mobai)
        XCTAssertEqual(AppConfig.load(defaults: defaults), loaded)
    }

    func test_selectedCompanionDefaultsToQinglanAndSurvivesReload() {
        let suiteName = "AppConfigTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(AppConfig.load(defaults: defaults).selectedCompanion, .qinglan)

        var config = AppConfig.default
        config.selectedCompanion = .mobai
        config.save(defaults: defaults)

        XCTAssertEqual(AppConfig.load(defaults: defaults).selectedCompanion, .mobai)
    }

    func test_eachCompanionHasItsOwnDoubaoVoiceIdentifier() {
        let voiceIds = Set(Companion.allCases.map(\.voiceId))

        XCTAssertEqual(voiceIds.count, Companion.allCases.count)
        XCTAssertEqual(Companion.qinglan.voiceId, "saturn_zh_female_nuanxinxuejie_tob")
        XCTAssertEqual(Companion.mobai.voiceId, "saturn_zh_male_chengshuzongcai_tob")
        XCTAssertEqual(Companion.chengcheng.voiceId, "saturn_zh_female_keainvsheng_tob")
        XCTAssertEqual(Companion.xingyu.voiceId, "saturn_zh_male_aojiaojingying_tob")
    }
}
