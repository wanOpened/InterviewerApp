import SwiftUI
import XCTest
@testable import InterviewerApp

final class RedesignComponentsTests: XCTestCase {
    func test_statusPillStyleMapsRoomStatesToLabelsAndDotColors() {
        let expectations: [(RoomStatus, String, Color)] = [
            (.asking, "在提问", DeepSpaceTheme.auroraCyan),
            (.listening, "聆听", Fig.onDarkMuted),
            (.observing, "旁听", Fig.onDarkMuted),
            (.answering, "回答中", DeepSpaceTheme.reviewGreen),
            (.connected, "已连接", DeepSpaceTheme.reviewGreen),
            (.connecting, "连接中", DeepSpaceTheme.auroraCyan),
        ]

        for (state, label, dotColor) in expectations {
            let style = StatusPillStyle(for: state)
            XCTAssertEqual(style.label, label)
            XCTAssertEqual(style.dotColor, dotColor)
        }
    }

    func test_sourceTagKindsMapToLabelsAndTints() {
        let expectations: [(SourceTag.Kind, String, Color)] = [
            (.interview, "面试", DeepSpaceTheme.auroraCyan),
            (.review, "复盘", DeepSpaceTheme.reviewGreen),
            (.schedule, "日程", DeepSpaceTheme.amber),
            (.practice, "练习", DeepSpaceTheme.practiceText),
        ]

        for (kind, label, tint) in expectations {
            XCTAssertEqual(kind.label, label)
            XCTAssertEqual(kind.tint, tint)
        }
    }

    func test_homeCTASourceStyleUsesBlueForScheduleAndCreationActions() {
        let actionTypes = [
            AgentHomeActionType.startPractice.rawValue,
            AgentHomeActionType.createSchedule.rawValue,
            AgentHomeActionType.createTarget.rawValue,
            AgentHomeActionType.addJD.rawValue,
        ]

        for actionType in actionTypes {
            XCTAssertEqual(HomeCTASourceStyle(actionType: actionType).tint, Fig.blue)
        }
    }

    func test_homeFigmaUtilityGrayTokensMatchSpec() {
        XCTAssertEqual(Fig.grabber, Color(red: 0xCC / 255, green: 0xD4 / 255, blue: 0xDB / 255))
        XCTAssertEqual(Fig.divider, Color(red: 0xD9 / 255, green: 0xDE / 255, blue: 0xE5 / 255))
    }

    func test_dimensionRowFlagsScoresBelowThresholdAsWeak() {
        XCTAssertTrue(DimensionRow(label: "衡量指标", score: 58, weakThreshold: 60).isWeak)
        XCTAssertFalse(DimensionRow(label: "取舍判断", score: 60, weakThreshold: 60).isWeak)
    }

    func test_companionStageMetricsMatchNaturalFigmaStage() {
        let home = CompanionStageSpec.home

        XCTAssertEqual(home.stageSize, CGSize(width: 246, height: 238))
        XCTAssertEqual(home.haloCenter, CGPoint(x: 123, y: 112))
        XCTAssertEqual(home.avatarFrame, CGRect(x: 53, y: 32, width: 140, height: 175))
        XCTAssertTrue(home.usesTransparentStage)
        XCTAssertEqual(home.haloRings.map(\.diameter), [202])
    }

    func test_speakingStageKeepsMouthLoopAndVoicePulseSeparateFromHalo() {
        let speaking = CompanionStageSpec.resultsSpeaking

        XCTAssertEqual(speaking.stageSize, CGSize(width: 246, height: 226))
        XCTAssertEqual(speaking.haloCenter, CGPoint(x: 123, y: 104))
        XCTAssertEqual(speaking.avatarFrame, CGRect(x: 53, y: 26, width: 140, height: 175))
        XCTAssertTrue(speaking.includesMouthLoop)
        XCTAssertTrue(speaking.includesVoicePulse)
        XCTAssertEqual(speaking.haloRings.map(\.diameter), [178])
    }

    func test_compactHomeStageEnablesMouthLoopAndVoicePulseForVoiceFeedback() {
        let compact = CompanionStageSpec.compact(size: 120)

        XCTAssertTrue(compact.includesMouthLoop)
        XCTAssertTrue(compact.includesVoicePulse)
    }

    func test_speakingMouthAmplitudeFollowsEightyMillisecondFigmaLoop() {
        let frames = (0..<7).map { frame in
            CompanionSpeakingAmplitude.value(at: Double(frame) * CompanionSpeakingAmplitude.frameDuration)
        }

        XCTAssertEqual(CompanionSpeakingAmplitude.frameDuration, 0.08, accuracy: 0.001)
        XCTAssertLessThan(frames[0], frames[1])
        XCTAssertLessThan(frames[1], frames[2])
        XCTAssertLessThan(frames[2], frames[3])
        XCTAssertGreaterThan(frames[3], frames[4])
        XCTAssertGreaterThan(frames[4], frames[5])
        XCTAssertEqual(frames[0], frames[6], accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(frames.min() ?? 0, 0.18)
        XCTAssertLessThanOrEqual(frames.max() ?? 1, 0.95)
    }

    func test_inlineRoomConnectionPresentationMatchesFigmaStateTable() {
        let presentation = InterviewPanelPresentation(
            connected: false,
            roomPhase: .connecting,
            phase: .live,
            canEnterRoom: false,
            microphonePermissionGranted: false,
            roomSpeaker: .interviewer,
            participantStatuses: [:],
            liveCaptionText: "",
            questionSetSynced: false
        )

        XCTAssertEqual(presentation.headerStatus, .connecting)
        XCTAssertEqual(presentation.leadTile.statusStyle.label, "连接中")
        XCTAssertEqual(presentation.leadTile.statusStyle.dotColor, DeepSpaceTheme.auroraCyan)
        XCTAssertEqual(presentation.panelistTile.statusStyle.label, "待加入")
        XCTAssertEqual(presentation.panelistTile.statusStyle.dotColor, Fig.amber)
        XCTAssertFalse(presentation.leadTile.isActive)
        XCTAssertEqual(presentation.candidate.statusText, "待开麦 · 开启麦克风")
        XCTAssertEqual(presentation.candidate.statusColor, Fig.amber)
        XCTAssertTrue(presentation.candidate.canRequestMicrophone)
        XCTAssertEqual(presentation.caption.speakerLabel, "主面试官 · 连接中")
        XCTAssertEqual(presentation.caption.dotColor, Fig.amber)
        XCTAssertEqual(presentation.caption.text, "正在接入面试官，正在同步本场题单…")
        XCTAssertEqual(presentation.bottomHint, "")
        XCTAssertFalse(presentation.answerControlEnabled)
    }

    func test_inlineRoomConnectedPresentationMatchesFigmaStateTable() {
        let presentation = InterviewPanelPresentation(
            connected: true,
            roomPhase: .inRoom,
            phase: .live,
            canEnterRoom: true,
            microphonePermissionGranted: true,
            roomSpeaker: .interviewer,
            participantStatuses: [
                .lead: .asking,
                .panelist: .observing,
                .candidate: .listening,
            ],
            liveCaptionText: "请先介绍一个你主导的项目。",
            questionSetSynced: true
        )

        XCTAssertEqual(presentation.headerStatus, .connected)
        XCTAssertEqual(presentation.leadTile.statusStyle.label, "在提问")
        XCTAssertEqual(presentation.panelistTile.statusStyle.label, "旁听")
        XCTAssertEqual(presentation.candidate.statusText, "聆听中 · 麦克风开")
        XCTAssertEqual(presentation.caption.speakerLabel, "主面试官 · 提问中")
        XCTAssertEqual(presentation.caption.text, "请先介绍一个你主导的项目。")
        XCTAssertEqual(presentation.bottomHint, "")
        XCTAssertTrue(presentation.answerControlEnabled)
    }

    func test_qinglanUsesBodyColoredLimbsAndNoBlush() {
        let look = QinglanAvatarLook.qinglan

        XCTAssertEqual(look.bodyColor, Color.qinglanBody)
        XCTAssertEqual(look.limbColor, look.bodyColor)
        XCTAssertFalse(look.showsBlush)
    }

    func test_qinglanGlowOpacityProgressesByVoiceState() {
        let look = QinglanAvatarLook.qinglan

        XCTAssertLessThan(look.glowOpacity(for: .connecting), look.glowOpacity(for: .thinking))
        XCTAssertLessThan(look.glowOpacity(for: .thinking), look.glowOpacity(for: .idle))
        XCTAssertLessThan(look.glowOpacity(for: .idle), look.glowOpacity(for: .listening))
        XCTAssertLessThan(look.glowOpacity(for: .listening), look.glowOpacity(for: .speaking))
    }
}
