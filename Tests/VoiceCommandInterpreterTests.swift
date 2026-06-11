import XCTest
@testable import InterviewerApp

final class VoiceCommandInterpreterTests: XCTestCase {
    func test_interviewCommandsRequireExplicitControlIntent() {
        XCTAssertEqual(VoiceCommandInterpreter.interviewCommand(from: "暂停面试"), .pause)
        XCTAssertEqual(VoiceCommandInterpreter.interviewCommand(from: "青岚，先暂停一下"), .pause)
        XCTAssertEqual(VoiceCommandInterpreter.interviewCommand(from: "继续面试"), .resume)
        XCTAssertEqual(VoiceCommandInterpreter.interviewCommand(from: "结束面试"), .end)
        XCTAssertEqual(VoiceCommandInterpreter.interviewCommand(from: "离开房间"), .end)

        XCTAssertNil(VoiceCommandInterpreter.interviewCommand(from: "我以前暂停过一个项目"))
        XCTAssertNil(VoiceCommandInterpreter.interviewCommand(from: "继续刚才说的用户增长案例"))
        XCTAssertNil(VoiceCommandInterpreter.interviewCommand(from: "面试官你好"))
    }
}
