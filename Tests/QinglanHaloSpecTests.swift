import SwiftUI
import XCTest
@testable import InterviewerApp

final class QinglanHaloSpecTests: XCTestCase {
    func test_haloSpecMapsCoreVoiceStates() {
        XCTAssertEqual(HaloSpec.for(.idle).tint, DeepSpaceTheme.auroraCyan)
        XCTAssertEqual(HaloSpec.for(.idle).baseOpacity, 0.26, accuracy: 0.001)
        XCTAssertFalse(HaloSpec.for(.idle).showsDashedRing)

        XCTAssertEqual(HaloSpec.for(.connecting).baseOpacity, 0.50, accuracy: 0.001)
        XCTAssertTrue(HaloSpec.for(.connecting).showsDashedRing)
        XCTAssertEqual(HaloSpec.for(.connecting).dashPattern, [6, 12])

        XCTAssertEqual(HaloSpec.for(.listening).solidRingCount, 2)
        XCTAssertEqual(HaloSpec.for(.thinking).tint, DeepSpaceTheme.auroraPurple)
        XCTAssertTrue(HaloSpec.for(.thinking).showsThinkingDots)

        XCTAssertEqual(HaloSpec.for(.speaking).solidRingCount, 3)
        XCTAssertTrue(HaloSpec.for(.speaking).usesSpeakingPulse)
    }
}
