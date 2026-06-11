import XCTest
@testable import InterviewerApp

final class MicrophonePermissionTests: XCTestCase {
    func test_statusLabelsMatchPermissionState() {
        XCTAssertEqual(MicrophonePermissionStatus.allowed.actionLabel, "已允许")
        XCTAssertEqual(MicrophonePermissionStatus.denied.actionLabel, "去允许")
        XCTAssertEqual(MicrophonePermissionStatus.undetermined.actionLabel, "去允许")

        XCTAssertEqual(MicrophonePermissionStatus.allowed.settingsLabel, "已允许")
        XCTAssertEqual(MicrophonePermissionStatus.denied.settingsLabel, "未允许")
        XCTAssertEqual(MicrophonePermissionStatus.undetermined.settingsLabel, "未询问")
    }
}
