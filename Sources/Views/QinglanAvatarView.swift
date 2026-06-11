import SwiftUI

struct HaloSpec: Equatable {
    let tint: Color
    let baseOpacity: Double
    let showsDashedRing: Bool
    let dashPattern: [CGFloat]
    let solidRingCount: Int
    let showsThinkingDots: Bool
    let usesSpeakingPulse: Bool

    static func `for`(_ state: QinglanState) -> HaloSpec {
        switch state {
        case .connecting:
            return HaloSpec(
                tint: DeepSpaceTheme.auroraCyan,
                baseOpacity: 0.50,
                showsDashedRing: true,
                dashPattern: [6, 12],
                solidRingCount: 0,
                showsThinkingDots: false,
                usesSpeakingPulse: false
            )
        case .listening:
            return HaloSpec(
                tint: DeepSpaceTheme.auroraCyan,
                baseOpacity: 0.50,
                showsDashedRing: false,
                dashPattern: [],
                solidRingCount: 2,
                showsThinkingDots: false,
                usesSpeakingPulse: false
            )
        case .thinking:
            return HaloSpec(
                tint: DeepSpaceTheme.auroraPurple,
                baseOpacity: 0.50,
                showsDashedRing: false,
                dashPattern: [],
                solidRingCount: 0,
                showsThinkingDots: true,
                usesSpeakingPulse: false
            )
        case .speaking:
            return HaloSpec(
                tint: DeepSpaceTheme.auroraCyan,
                baseOpacity: 0.55,
                showsDashedRing: false,
                dashPattern: [],
                solidRingCount: 3,
                showsThinkingDots: false,
                usesSpeakingPulse: true
            )
        case .error:
            return HaloSpec(
                tint: Color.qinglanError,
                baseOpacity: 0.28,
                showsDashedRing: false,
                dashPattern: [],
                solidRingCount: 1,
                showsThinkingDots: false,
                usesSpeakingPulse: false
            )
        case .idle, .attention, .success, .waiting:
            return HaloSpec(
                tint: DeepSpaceTheme.auroraCyan,
                baseOpacity: 0.26,
                showsDashedRing: false,
                dashPattern: [],
                solidRingCount: 0,
                showsThinkingDots: false,
                usesSpeakingPulse: false
            )
        }
    }
}

struct HaloRingSpec: Equatable {
    let diameter: CGFloat
    let opacity: Double
}

struct QinglanAvatarLook: Equatable {
    let bodyColor: Color
    let limbColor: Color
    let showsBlush: Bool

    static let qinglan = QinglanAvatarLook(
        bodyColor: .qinglanBody,
        limbColor: .qinglanBody,
        showsBlush: false
    )

    func glowOpacity(for state: QinglanState) -> Double {
        switch state {
        case .connecting:
            return 0.06
        case .thinking:
            return 0.085
        case .idle, .attention, .waiting:
            return 0.10
        case .listening:
            return 0.13
        case .speaking:
            return 0.16
        case .success:
            return 0.16
        case .error:
            return 0.07
        }
    }
}

struct CompanionStageSpec: Equatable {
    let stageSize: CGSize
    let haloCenter: CGPoint
    let haloRings: [HaloRingSpec]
    let avatarFrame: CGRect
    let usesTransparentStage: Bool
    let includesMouthLoop: Bool
    let includesVoicePulse: Bool

    static let home = CompanionStageSpec(
        stageSize: CGSize(width: 246, height: 238),
        haloCenter: CGPoint(x: 123, y: 112),
        haloRings: [
            HaloRingSpec(diameter: 202, opacity: 0.14),
        ],
        avatarFrame: CGRect(x: 53, y: 32, width: 140, height: 175),
        usesTransparentStage: true,
        includesMouthLoop: false,
        includesVoicePulse: false
    )

    static let resultsSpeaking = CompanionStageSpec(
        stageSize: CGSize(width: 246, height: 226),
        haloCenter: CGPoint(x: 123, y: 104),
        haloRings: [
            HaloRingSpec(diameter: 178, opacity: 0.21),
        ],
        avatarFrame: CGRect(x: 53, y: 26, width: 140, height: 175),
        usesTransparentStage: true,
        includesMouthLoop: true,
        includesVoicePulse: true
    )

    static func compact(size: CGFloat) -> CompanionStageSpec {
        let stage = size * 1.46
        let avatarWidth = size * 0.80
        let avatarHeight = size
        return CompanionStageSpec(
            stageSize: CGSize(width: stage, height: stage),
            haloCenter: CGPoint(x: stage / 2, y: stage / 2),
            haloRings: [
                HaloRingSpec(diameter: stage * 0.72, opacity: 0.12),
            ],
            avatarFrame: CGRect(
                x: (stage - avatarWidth) / 2,
                y: (stage - avatarHeight) / 2,
                width: avatarWidth,
                height: avatarHeight
            ),
            usesTransparentStage: true,
            includesMouthLoop: true,
            includesVoicePulse: true
        )
    }
}

struct CompanionSpeakingAmplitude {
    static let frameDuration: TimeInterval = 0.08

    private static let minimum = 0.18
    private static let maximum = 0.95
    private static let normalizedFrames: [Double] = [0, 0.3, 0.6, 1.0, 0.6, 0.3]

    static func value(at date: Date) -> Double {
        value(at: date.timeIntervalSinceReferenceDate)
    }

    static func value(at time: TimeInterval) -> Double {
        let cycleDuration = frameDuration * Double(normalizedFrames.count)
        let cycleTime = positiveRemainder(time, cycleDuration)
        let rawFrame = cycleTime / frameDuration
        let frameIndex = Int(floor(rawFrame)) % normalizedFrames.count
        let nextFrameIndex = (frameIndex + 1) % normalizedFrames.count
        let progress = rawFrame - floor(rawFrame)
        let easedProgress = progress * progress * (3 - 2 * progress)
        let base = normalizedFrames[frameIndex]
            + (normalizedFrames[nextFrameIndex] - normalizedFrames[frameIndex]) * easedProgress
        let phraseEnvelope = 0.965
            + 0.025 * sin(time * Double.pi * 2 / 1.12)
            + 0.018 * sin(time * Double.pi * 2 / 0.56)
        let amplitude = minimum + (maximum - minimum) * base * phraseEnvelope

        return min(max(amplitude, minimum), maximum)
    }

    private static func positiveRemainder(_ value: TimeInterval, _ divisor: TimeInterval) -> TimeInterval {
        let remainder = value.truncatingRemainder(dividingBy: divisor)
        return remainder >= 0 ? remainder : remainder + divisor
    }
}

struct QinglanCharacterArt: View {
    var state: QinglanState = .idle
    var amplitude: Double = 0

    var body: some View {
        CompanionAvatarArt(companion: .qinglan, state: state, amplitude: amplitude)
    }
}

struct CompanionAvatarArt: View {
    let companion: Companion
    var state: QinglanState = .idle
    var amplitude: Double = 0

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height / 1.25)
            CompanionCharacterView(
                companion: companion,
                state: state,
                amplitude: amplitude,
                size: size
            )
            .frame(width: size, height: size * 1.25)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .aspectRatio(0.8, contentMode: .fit)
    }
}

private struct CompanionCharacterView: View {
    let companion: Companion
    var state: QinglanState = .idle
    var amplitude: Double = 0
    var size: CGFloat = 100

    @State private var breathing = false
    @State private var thinkPulse = false

    var body: some View {
        ZStack {
            bodyView(for: companion)
            face
            if state == .thinking {
                thinkingDots
            }
        }
        .frame(width: size, height: size * 1.25)
        .scaleEffect(bodyScale, anchor: .bottom)
        .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: breathing)
        .animation(.easeOut(duration: CompanionSpeakingAmplitude.frameDuration), value: amplitude)
        .onAppear {
            breathing = true
            thinkPulse = true
        }
    }

    @ViewBuilder
    private func bodyView(for companion: Companion) -> some View {
        switch companion {
        case .qinglan:
            QinglanBody(size: size, softBackground: companion.softBackground, bodyColor: companion.bodyColor)
        case .mobai:
            MobaiBody(size: size, bodyColor: companion.bodyColor, faceColor: companion.faceColor)
        case .chengcheng:
            ChengchengBody(size: size, bodyColor: companion.bodyColor, softBackground: companion.softBackground)
        case .xingyu:
            XingyuBody(size: size, bodyColor: companion.bodyColor, softBackground: companion.softBackground)
        }
    }

    private var bodyScale: CGFloat {
        let breath: CGFloat = breathing ? 1.03 : 0.99
        if state == .speaking {
            return breath + CGFloat(min(max(amplitude, 0), 1)) * 0.03
        }
        if state == .listening, amplitude > 0.01 {
            return 1.0 + CGFloat(min(amplitude, 1.0)) * 0.06
        }
        if state == .success {
            return breath + 0.01
        }
        if state == .error {
            return 0.98
        }
        return breath
    }

    private var face: some View {
        ZStack {
            eyes
            if showsBlush { blush }
            if companion == .chengcheng { whiskers }
            mouthView.offset(y: size * 0.14)
        }
    }

    private var showsBlush: Bool {
        switch companion {
        case .qinglan:
            return QinglanAvatarLook.qinglan.showsBlush
        case .chengcheng:
            return true
        case .mobai, .xingyu:
            return false
        }
    }

    private var eyes: some View {
        HStack(spacing: size * 0.14) {
            companionEye
            companionEye
        }
        .offset(y: -size * 0.02)
    }

    @ViewBuilder
    private var companionEye: some View {
        switch companion {
        case .mobai:
            Capsule()
                .fill(Color.qinglanInk)
                .frame(width: size * 0.10, height: size * 0.03)
        case .xingyu:
            ZStack {
                Ellipse()
                    .fill(Color.qinglanInk)
                    .frame(width: size * 0.09, height: size * 0.13)
                Circle()
                    .fill(Color.white)
                    .frame(width: size * 0.03, height: size * 0.03)
                    .offset(x: -size * 0.015, y: -size * 0.02)
            }
        default:
            ZStack {
                Circle()
                    .fill(Color.qinglanInk)
                    .frame(width: size * 0.09, height: size * 0.09)
                Circle()
                    .fill(Color.white)
                    .frame(width: size * 0.03, height: size * 0.03)
                    .offset(x: -size * 0.015, y: -size * 0.02)
            }
        }
    }

    private var blush: some View {
        HStack(spacing: size * 0.42) {
            Ellipse()
                .fill(Color(red: 1.0, green: 0.69, blue: 0.71).opacity(0.6))
                .frame(width: size * 0.10, height: size * 0.06)
            Ellipse()
                .fill(Color(red: 1.0, green: 0.69, blue: 0.71).opacity(0.6))
                .frame(width: size * 0.10, height: size * 0.06)
        }
        .offset(y: size * 0.06)
    }

    private var whiskers: some View {
        HStack(spacing: size * 0.40) {
            VStack(alignment: .trailing, spacing: size * 0.015) {
                Capsule().fill(Color.black.opacity(0.5)).frame(width: size * 0.10, height: size * 0.012)
                Capsule().fill(Color.black.opacity(0.4)).frame(width: size * 0.08, height: size * 0.012)
            }
            VStack(alignment: .leading, spacing: size * 0.015) {
                Capsule().fill(Color.black.opacity(0.5)).frame(width: size * 0.10, height: size * 0.012)
                Capsule().fill(Color.black.opacity(0.4)).frame(width: size * 0.08, height: size * 0.012)
            }
        }
        .offset(y: size * 0.10)
    }

    private var mouthOpenness: CGFloat {
        state == .speaking ? CGFloat(min(max(amplitude, 0.05), 1.0)) : 0
    }

    @ViewBuilder
    private var mouthView: some View {
        if mouthOpenness > 0.02 {
            openMouth(openness: mouthOpenness)
        } else {
            restingMouth
        }
    }

    private func openMouth(openness: CGFloat) -> some View {
        let mouthW = size * (0.14 + openness * 0.05)
        let mouthH = size * (0.04 + openness * 0.10)
        return ZStack {
            Rectangle()
                .fill(companion.faceColor)
                .frame(width: size * 0.22, height: size * 0.12)
            Ellipse()
                .fill(Color.qinglanInk)
                .frame(width: mouthW, height: mouthH)
            Ellipse()
                .fill(Color(red: 1.0, green: 0.49, blue: 0.49).opacity(0.85))
                .frame(width: mouthW * 0.55, height: mouthH * 0.55)
                .offset(y: mouthH * 0.18)
            Rectangle()
                .fill(Color.white.opacity(0.7))
                .frame(width: mouthW * 0.7, height: 1.3)
                .offset(y: -mouthH * 0.32)
        }
    }

    @ViewBuilder
    private var restingMouth: some View {
        switch companion {
        case .qinglan:
            SmileArc()
                .stroke(Color.qinglanInk, lineWidth: max(1.4, size * 0.018))
                .frame(width: size * 0.14, height: size * 0.06)
        case .mobai:
            Capsule()
                .fill(Color.qinglanInk)
                .frame(width: size * 0.12, height: size * 0.02)
        case .chengcheng:
            SmileArc()
                .stroke(Color.qinglanInk, lineWidth: max(1.4, size * 0.018))
                .frame(width: size * 0.10, height: size * 0.05)
        case .xingyu:
            Ellipse()
                .fill(Color.qinglanInk)
                .frame(width: size * 0.08, height: size * 0.08)
        }
    }

    private var thinkingDots: some View {
        HStack(spacing: size * 0.06) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(companion.bodyColor)
                    .frame(width: size * 0.08, height: size * 0.08)
                    .opacity(thinkPulse ? 1 : 0.35)
                    .animation(
                        .easeInOut(duration: 0.9)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.2),
                        value: thinkPulse
                    )
            }
        }
        .offset(y: -size * 0.62)
    }
}

private struct QinglanBody: View {
    let size: CGFloat
    let softBackground: Color
    let bodyColor: Color
    private let look = QinglanAvatarLook.qinglan

    var body: some View {
        ZStack {
            Ellipse()
                .fill(look.limbColor)
                .frame(width: size * 0.24, height: size * 0.32)
                .rotationEffect(.degrees(20))
                .offset(x: -size * 0.32, y: size * 0.02)
            Ellipse()
                .fill(look.limbColor)
                .frame(width: size * 0.24, height: size * 0.32)
                .rotationEffect(.degrees(-20))
                .offset(x: size * 0.32, y: size * 0.02)
            Ellipse()
                .fill(LinearGradient(
                    colors: [bodyColor.opacity(0.92), bodyColor],
                    startPoint: .top,
                    endPoint: .bottom
                ))
                .frame(width: size * 0.72, height: size * 0.88)
            Ellipse()
                .fill(Color.white.opacity(0.35))
                .frame(width: size * 0.14, height: size * 0.18)
                .offset(x: -size * 0.14, y: -size * 0.24)
            HStack(spacing: size * 0.22) {
                Capsule().fill(look.limbColor).frame(width: size * 0.08, height: size * 0.18)
                Capsule().fill(look.limbColor).frame(width: size * 0.08, height: size * 0.18)
            }
            .offset(y: size * 0.40)
            companionFeet(
                color: look.limbColor,
                size: size,
                offsetY: size * 0.46
            )
        }
    }
}

private struct MobaiBody: View {
    let size: CGFloat
    let bodyColor: Color
    let faceColor: Color

    var body: some View {
        ZStack {
            Capsule()
                .fill(bodyColor)
                .frame(width: size * 0.22, height: size * 0.12)
                .rotationEffect(.degrees(28))
                .offset(x: size * 0.34, y: size * 0.18)
            CompanionTriangleEar(size: size, color: bodyColor)
                .offset(x: -size * 0.22, y: -size * 0.40)
            CompanionTriangleEar(size: size, color: bodyColor)
                .offset(x: size * 0.22, y: -size * 0.40)
            Circle()
                .fill(bodyColor)
                .frame(width: size * 0.78, height: size * 0.78)
            Ellipse()
                .fill(faceColor)
                .frame(width: size * 0.56, height: size * 0.50)
                .offset(y: size * 0.04)
            companionFeet(color: bodyColor, size: size, offsetY: size * 0.40)
        }
    }
}

private struct ChengchengBody: View {
    let size: CGFloat
    let bodyColor: Color
    let softBackground: Color

    var body: some View {
        ZStack {
            Capsule()
                .fill(bodyColor)
                .frame(width: size * 0.26, height: size * 0.12)
                .rotationEffect(.degrees(-26))
                .offset(x: size * 0.36, y: size * 0.20)
            CompanionTriangleEar(size: size, color: bodyColor)
                .offset(x: -size * 0.22, y: -size * 0.40)
            CompanionTriangleEar(size: size, color: bodyColor)
                .offset(x: size * 0.22, y: -size * 0.40)
            Circle()
                .fill(bodyColor)
                .frame(width: size * 0.80, height: size * 0.80)
            Ellipse()
                .fill(softBackground)
                .frame(width: size * 0.42, height: size * 0.42)
                .offset(y: size * 0.12)
            companionFeet(color: bodyColor, size: size, offsetY: size * 0.42)
        }
    }
}

private struct XingyuBody: View {
    let size: CGFloat
    let bodyColor: Color
    let softBackground: Color

    var body: some View {
        ZStack {
            FourPointStar()
                .fill(softBackground)
                .frame(width: size * 0.08, height: size * 0.08)
                .offset(x: -size * 0.50, y: -size * 0.26)
            FourPointStar()
                .fill(softBackground)
                .frame(width: size * 0.08, height: size * 0.08)
                .offset(x: size * 0.50, y: -size * 0.16)
            FourPointStar()
                .fill(softBackground)
                .frame(width: size * 0.08, height: size * 0.08)
                .offset(x: -size * 0.44, y: size * 0.30)
            FourPointStar()
                .fill(softBackground)
                .frame(width: size * 0.08, height: size * 0.08)
                .offset(x: size * 0.44, y: size * 0.34)
            FourPointStar()
                .fill(LinearGradient(
                    colors: [bodyColor.opacity(0.92), bodyColor],
                    startPoint: .top,
                    endPoint: .bottom
                ))
                .frame(width: size * 0.92, height: size * 0.92)
            Ellipse()
                .fill(softBackground.opacity(0.55))
                .frame(width: size * 0.42, height: size * 0.38)
                .offset(y: size * 0.02)
        }
    }
}

@ViewBuilder
private func companionFeet(color: Color, size: CGFloat, offsetY: CGFloat) -> some View {
    HStack(spacing: size * 0.20) {
        Capsule().fill(color).frame(width: size * 0.14, height: size * 0.10)
        Capsule().fill(color).frame(width: size * 0.14, height: size * 0.10)
    }
    .offset(y: offsetY)
}

private struct CompanionTriangleEar: View {
    let size: CGFloat
    let color: Color

    var body: some View {
        Triangle()
            .fill(color)
            .frame(width: size * 0.22, height: size * 0.22)
            .overlay(
                Triangle()
                    .fill(Color(red: 1.0, green: 0.69, blue: 0.71).opacity(0.7))
                    .frame(width: size * 0.12, height: size * 0.12)
                    .offset(y: size * 0.04)
            )
    }
}

private struct SmileArc: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.midX, y: rect.maxY * 1.6)
        )
        return path
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct FourPointStar: Shape {
    func path(in rect: CGRect) -> Path {
        let cx = rect.midX
        let cy = rect.midY
        let rx = rect.width / 2
        let ry = rect.height / 2
        let inX = rx * 0.32
        let inY = ry * 0.32
        var path = Path()
        path.move(to: CGPoint(x: cx, y: cy - ry))
        path.addQuadCurve(
            to: CGPoint(x: cx + rx, y: cy),
            control: CGPoint(x: cx + inX, y: cy - inY)
        )
        path.addQuadCurve(
            to: CGPoint(x: cx, y: cy + ry),
            control: CGPoint(x: cx + inX, y: cy + inY)
        )
        path.addQuadCurve(
            to: CGPoint(x: cx - rx, y: cy),
            control: CGPoint(x: cx - inX, y: cy + inY)
        )
        path.addQuadCurve(
            to: CGPoint(x: cx, y: cy - ry),
            control: CGPoint(x: cx - inX, y: cy - inY)
        )
        return path
    }
}

struct CompanionStageView: View {
    let companion: Companion
    let state: QinglanState
    let spec: CompanionStageSpec

    @State private var haloBreathing = false
    @State private var mouthOpen = false
    @State private var voicePulse = false
    @State private var ringRotation = false
    @State private var thinkingPulse = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(spec.haloRings.enumerated()), id: \.offset) { index, ring in
                Circle()
                    .fill(stateTint.opacity(ringOpacity(ring, index: index)))
                    .blur(radius: companion == .qinglan ? 18 : 0)
                    .frame(width: ring.diameter, height: ring.diameter)
                    .scaleEffect(haloScale(index: index))
                    .position(spec.haloCenter)
                    .animation(
                        .easeInOut(duration: haloDuration + Double(index) * 0.14)
                            .repeatForever(autoreverses: true),
                        value: haloBreathing
                    )
            }

            if companion == .qinglan {
                qinglanStateHalo
            }

            stageCharacter
                .frame(width: spec.avatarFrame.width, height: spec.avatarFrame.height)
                .scaleEffect(characterScale)
                .position(x: spec.avatarFrame.midX, y: spec.avatarFrame.midY)
                .animation(.easeInOut(duration: 0.30), value: state)

            if state == .speaking, spec.includesVoicePulse {
                VoicePulseMarks(active: voicePulse, tint: stateTint)
                    .frame(width: 116, height: 32)
                    .position(
                        x: spec.avatarFrame.midX,
                        y: spec.avatarFrame.minY + spec.avatarFrame.height * 0.40
                    )
            }
        }
        .frame(width: spec.stageSize.width, height: spec.stageSize.height)
        .contentShape(Rectangle())
        .onAppear {
            haloBreathing = true
            mouthOpen = true
            voicePulse = true
            ringRotation = true
            thinkingPulse = true
        }
        .accessibilityLabel(accessibilityLabel)
    }

    private var qinglanStateHalo: some View {
        let halo = HaloSpec.for(state)
        let baseDiameter = min(spec.stageSize.width, spec.stageSize.height) * 0.78

        return ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            halo.tint.opacity(halo.baseOpacity),
                            halo.tint.opacity(halo.baseOpacity * 0.22),
                            .clear,
                        ],
                        center: .center,
                        startRadius: baseDiameter * 0.08,
                        endRadius: baseDiameter * 0.50
                    )
                )
                .frame(width: baseDiameter, height: baseDiameter)
                .scaleEffect(haloScale(index: 0))

            if halo.showsDashedRing {
                Circle()
                    .stroke(
                        halo.tint.opacity(0.70),
                        style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: halo.dashPattern)
                    )
                    .frame(width: baseDiameter * 0.94, height: baseDiameter * 0.94)
                    .rotationEffect(.degrees(ringRotation ? 360 : 0))
                    .animation(.linear(duration: 8).repeatForever(autoreverses: false), value: ringRotation)
            }

            ForEach(0..<halo.solidRingCount, id: \.self) { index in
                let opacities = solidRingOpacities(for: halo)
                Circle()
                    .stroke(halo.tint.opacity(opacities[index]), lineWidth: 1)
                    .frame(
                        width: baseDiameter * (0.72 + CGFloat(index) * 0.16),
                        height: baseDiameter * (0.72 + CGFloat(index) * 0.16)
                    )
                    .scaleEffect(haloBreathing ? 1.04 + CGFloat(index) * 0.02 : 0.99)
            }

            if halo.showsThinkingDots {
                thinkingDots(tint: halo.tint, diameter: baseDiameter)
            }
        }
        .position(spec.haloCenter)
        .allowsHitTesting(false)
    }

    private func solidRingOpacities(for halo: HaloSpec) -> [Double] {
        if halo.usesSpeakingPulse {
            return [0.55, 0.32, 0.16]
        }
        return [0.35, 0.22, 0.16]
    }

    private func thinkingDots(tint: Color, diameter: CGFloat) -> some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(tint.opacity(thinkingPulse ? 0.88 : 0.24))
                    .frame(width: 6, height: 6)
                    .animation(
                        .easeInOut(duration: 0.72)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.16),
                        value: thinkingPulse
                    )
            }
        }
        .offset(y: -diameter * 0.43)
    }

    @ViewBuilder
    private var stageCharacter: some View {
        if state == .speaking, spec.includesMouthLoop {
            TimelineView(.animation(minimumInterval: CompanionSpeakingAmplitude.frameDuration)) { timeline in
                CompanionCharacterView(
                    companion: companion,
                    state: state,
                    amplitude: characterAmplitude(at: timeline.date),
                    size: spec.avatarFrame.width
                )
            }
        } else {
            CompanionCharacterView(
                companion: companion,
                state: state,
                amplitude: characterAmplitude,
                size: spec.avatarFrame.width
            )
        }
    }

    private var characterAmplitude: Double {
        switch state {
        case .speaking:
            guard spec.includesMouthLoop else { return mouthOpen ? 0.42 : 0.18 }
            return mouthOpen ? 0.82 : 0.18
        case .listening:
            return haloBreathing ? 0.35 : 0.08
        default:
            return 0
        }
    }

    private func characterAmplitude(at date: Date) -> Double {
        guard state == .speaking, spec.includesMouthLoop else {
            return characterAmplitude
        }
        return CompanionSpeakingAmplitude.value(at: date)
    }

    private var stateTint: Color {
        if companion == .qinglan {
            return HaloSpec.for(state).tint
        }
        switch companion {
        case .qinglan:
            return .qinglanBody
        case .mobai:
            return .mobaiBody
        case .chengcheng:
            return .chengchengBody
        case .xingyu:
            return .xingyuBody
        }
    }

    private var haloDuration: Double {
        switch state {
        case .speaking: return 2.4
        case .thinking: return 3.2
        case .connecting, .waiting, .idle, .attention: return 3.0
        case .success: return 2.6
        case .listening: return 2.2
        case .error: return 1.8
        }
    }

    private func ringOpacity(_ ring: HaloRingSpec, index: Int) -> Double {
        if companion == .qinglan {
            return QinglanAvatarLook.qinglan.glowOpacity(for: state)
        }
        if state == .error { return ring.opacity * 0.68 }
        if state == .success { return ring.opacity * (index == 0 ? 1.18 : 1.04) }
        if state == .thinking { return ring.opacity * (index == 0 ? 1.08 : 0.92) }
        return ring.opacity
    }

    private func haloScale(index: Int) -> CGFloat {
        guard state != .error else { return haloBreathing ? 0.98 : 0.92 }
        let base: CGFloat = index == 0 ? 1.035 : 1.02
        let low: CGFloat = index == 0 ? 0.985 : 0.995
        return haloBreathing ? base : low
    }

    private var characterScale: CGFloat {
        switch state {
        case .listening:
            return haloBreathing ? 1.012 : 0.997
        case .speaking:
            return mouthOpen ? 1.018 : 1.0
        case .connecting:
            return haloBreathing ? 1.006 : 0.998
        case .thinking:
            return 0.995
        case .attention:
            return haloBreathing ? 1.008 : 0.998
        case .success:
            return haloBreathing ? 1.014 : 1.0
        case .waiting:
            return haloBreathing ? 1.006 : 1.0
        case .error:
            return 0.975
        case .idle:
            return 1.0
        }
    }

    private var accessibilityLabel: String {
        switch state {
        case .idle: return "\(companion.displayName)空闲"
        case .connecting: return "\(companion.displayName)连接中"
        case .attention: return "\(companion.displayName)准备回应"
        case .success: return "\(companion.displayName)已完成"
        case .listening: return "\(companion.displayName)正在听"
        case .thinking: return "\(companion.displayName)正在处理"
        case .speaking: return "\(companion.displayName)正在说话"
        case .waiting: return "\(companion.displayName)等待回复"
        case .error: return "\(companion.displayName)遇到错误"
        }
    }
}

private struct VoicePulseMarks: View {
    let active: Bool
    let tint: Color

    var body: some View {
        ZStack {
            pulseMark(x: 7, height: 11, delay: 0)
            pulseMark(x: 14, height: 16, delay: 0.08)
            pulseMark(x: 96, height: 11, delay: 0.04)
            pulseMark(x: 104, height: 16, delay: 0.12)
        }
    }

    private func pulseMark(x: CGFloat, height: CGFloat, delay: Double) -> some View {
        Capsule(style: .continuous)
            .stroke(tint.opacity(active ? 0.72 : 0.28), lineWidth: 1.6)
            .frame(width: 4, height: active ? height : height * 0.62)
            .position(x: x, y: 16)
            .animation(.easeInOut(duration: 0.38).repeatForever(autoreverses: true).delay(delay), value: active)
    }
}

struct QinglanAvatarView: View {
    let state: QinglanState
    var size: CGFloat = 120

    var body: some View {
        CompanionStageView(
            companion: .qinglan,
            state: state,
            spec: .compact(size: size)
        )
    }
}

private extension Companion {
    var bodyColor: Color {
        switch self {
        case .qinglan:
            return Color(red: 0x7C / 255, green: 0xC4 / 255, blue: 0xDE / 255)
        case .mobai:
            return Color(red: 0x43 / 255, green: 0x4A / 255, blue: 0x5E / 255)
        case .chengcheng:
            return Color(red: 0xF2 / 255, green: 0xA7 / 255, blue: 0x65 / 255)
        case .xingyu:
            return Color(red: 0xA2 / 255, green: 0x8F / 255, blue: 0xD8 / 255)
        }
    }

    var softBackground: Color {
        switch self {
        case .qinglan:
            return Color(red: 0xB9 / 255, green: 0xE1 / 255, blue: 0xEF / 255)
        case .mobai:
            return Color(red: 0xD9 / 255, green: 0xDD / 255, blue: 0xE7 / 255)
        case .chengcheng:
            return Color(red: 0xFF / 255, green: 0xD5 / 255, blue: 0xA8 / 255)
        case .xingyu:
            return Color(red: 0xD4 / 255, green: 0xC7 / 255, blue: 0xF0 / 255)
        }
    }

    var faceColor: Color {
        switch self {
        case .qinglan:
            return bodyColor
        case .mobai:
            return Color(red: 0xF1 / 255, green: 0xF4 / 255, blue: 0xFA / 255)
        case .chengcheng, .xingyu:
            return softBackground
        }
    }
}

extension Color {
    static let qinglanBody = Color(red: 0x7C / 255, green: 0xC4 / 255, blue: 0xDE / 255)
    static let qinglanBodyStroke = Color(red: 0.34, green: 0.66, blue: 0.77)
    static let qinglanCheek = Color(red: 0.90, green: 0.67, blue: 0.78)
    static let qinglanInk = Color(red: 0.08, green: 0.14, blue: 0.20)
    static let mobaiBody = Color(red: 0.28, green: 0.32, blue: 0.42)
    static let chengchengBody = Color(red: 0.98, green: 0.66, blue: 0.36)
    static let xingyuBody = Color(red: 0.62, green: 0.52, blue: 0.88)
    static let qinglanListen = Color(red: 0.14, green: 0.72, blue: 0.42)
    static let qinglanThink = Color(red: 0.58, green: 0.48, blue: 0.88)
    static let qinglanWait = Color(red: 0.98, green: 0.66, blue: 0.20)
    static let qinglanError = Color(red: 1.0, green: 0.32, blue: 0.46)
}
