import XCTest
@testable import InterviewerApp

final class TranscriptStoreTests: XCTestCase {
    func test_interimThenFinal_updatesSameTurn() {
        let store = TranscriptStore(localIdentity: "cand-1")
        store.ingest(segmentId: "s1", senderIdentity: "cand-1", text: "你好", isFinal: false)
        store.ingest(segmentId: "s1", senderIdentity: "cand-1", text: "你好我是张三", isFinal: true)
        XCTAssertEqual(store.turns.count, 1)
        XCTAssertEqual(store.turns[0].text, "你好我是张三")
        XCTAssertEqual(store.turns[0].speaker, .candidate)
        XCTAssertTrue(store.turns[0].isFinal)
    }

    func test_attributesRemoteAsInterviewer_andPreservesOrder() {
        let store = TranscriptStore(localIdentity: "cand-1")
        store.ingest(segmentId: "a1", senderIdentity: "agent-x", text: "请介绍一下你自己", isFinal: true)
        store.ingest(segmentId: "s2", senderIdentity: "cand-1", text: "好的", isFinal: true)
        XCTAssertEqual(store.turns.map(\.speaker), [.interviewer, .candidate])
        XCTAssertEqual(store.turns.map(\.text), ["请介绍一下你自己", "好的"])
    }
}
