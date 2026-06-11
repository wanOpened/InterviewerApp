import SwiftUI
import XCTest
@testable import InterviewerApp

final class DeepSpaceThemeTests: XCTestCase {
    func test_coreTokensMatchDeepSpaceSpec() {
        XCTAssertEqual(DeepSpaceTheme.auroraCyan, Color(red: 0x6F / 255, green: 0xE7 / 255, blue: 0xDB / 255))
        XCTAssertEqual(DeepSpaceTheme.auroraPurple, Color(red: 0x8B / 255, green: 0x7C / 255, blue: 0xF6 / 255))
        XCTAssertEqual(DeepSpaceTheme.amber, Color(red: 0xFF / 255, green: 0xB4 / 255, blue: 0x5C / 255))
        XCTAssertEqual(DeepSpaceTheme.reviewGreen, Color(red: 0x4A / 255, green: 0xDE / 255, blue: 0x80 / 255))
        XCTAssertEqual(DeepSpaceTheme.dangerText, Color(red: 0xFF / 255, green: 0x8C / 255, blue: 0x94 / 255))
    }

    func test_accentChipUsesSpecHeight() {
        XCTAssertEqual(AccentChip.height, 24)
    }

    func test_voiceBarUsesFiveBarsAndSpecHeights() {
        XCTAssertEqual(VoiceBarView.barCount, 5)
        XCTAssertEqual(VoiceBarView.defaultHeights, [12, 20, 28, 20, 12])
    }
}
