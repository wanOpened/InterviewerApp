import SwiftUI

enum Fig {
    static let background = Color(red: 0xF6 / 255, green: 0xF8 / 255, blue: 0xFB / 255)
    static let soft = Color(red: 0xF1 / 255, green: 0xF5 / 255, blue: 0xF9 / 255)
    static let ink = Color(red: 0x12 / 255, green: 0x1A / 255, blue: 0x24 / 255)
    static let muted = Color(red: 0x6B / 255, green: 0x76 / 255, blue: 0x86 / 255)
    static let line = Color(red: 0xE2 / 255, green: 0xE8 / 255, blue: 0xF0 / 255)
    static let blue = Color(red: 0x3B / 255, green: 0x82 / 255, blue: 0xF6 / 255)
    static let pillBlue = Color(red: 0xDB / 255, green: 0xEA / 255, blue: 0xFF / 255)
    static let success = Color(red: 0x22 / 255, green: 0xA0 / 255, blue: 0x6B / 255)
    static let amber = Color(red: 0xF0 / 255, green: 0x9A / 255, blue: 0x24 / 255)
    static let purple = Color(red: 0x7C / 255, green: 0x5C / 255, blue: 0xD6 / 255)
    static let danger = Color(red: 0xE5 / 255, green: 0x48 / 255, blue: 0x4D / 255)
    static let onDarkText = Color.white
    static let onDarkMuted = Color.white.opacity(0.68)
    static let interviewBackground = DeepSpaceTheme.backgroundTop
    static let interviewElevated = Color.white.opacity(0.10)
    static let interviewTile = Color.white.opacity(0.07)
    static let room = DeepSpaceTheme.backgroundBottom
    static let resultsBackground = Color(red: 0xF8 / 255, green: 0xFA / 255, blue: 0xFC / 255)
    static let ctaElevated = Color(red: 0xF8 / 255, green: 0xFA / 255, blue: 0xFC / 255)
    static let ctaBorder = Color(red: 0xE6 / 255, green: 0xEC / 255, blue: 0xF2 / 255)
    static let grabber = Color(red: 0xCC / 255, green: 0xD4 / 255, blue: 0xDB / 255)
    static let divider = Color(red: 0xD9 / 255, green: 0xDE / 255, blue: 0xE5 / 255)
}

enum RoomStatus: CaseIterable, Equatable {
    case asking
    case listening
    case observing
    case answering
    case connected
    case connecting
}

struct StatusPillStyle {
    let label: String
    let dotColor: Color
    let foregroundColor: Color
    let backgroundColor: Color

    init(for state: RoomStatus) {
        switch state {
        case .asking:
            self.init(label: "在提问", dotColor: DeepSpaceTheme.auroraCyan, foregroundColor: DeepSpaceTheme.auroraCyan, backgroundColor: DeepSpaceTheme.auroraCyan.opacity(0.16))
        case .listening:
            self.init(label: "聆听", dotColor: Fig.onDarkMuted, foregroundColor: Fig.onDarkMuted, backgroundColor: Fig.onDarkText.opacity(0.08))
        case .observing:
            self.init(label: "旁听", dotColor: Fig.onDarkMuted, foregroundColor: Fig.onDarkMuted, backgroundColor: Fig.onDarkText.opacity(0.08))
        case .answering:
            self.init(label: "回答中", dotColor: DeepSpaceTheme.reviewGreen, foregroundColor: DeepSpaceTheme.reviewGreen, backgroundColor: DeepSpaceTheme.reviewGreen.opacity(0.14))
        case .connected:
            self.init(label: "已连接", dotColor: DeepSpaceTheme.reviewGreen, foregroundColor: DeepSpaceTheme.reviewGreen, backgroundColor: DeepSpaceTheme.reviewGreen.opacity(0.14))
        case .connecting:
            self.init(label: "连接中", dotColor: DeepSpaceTheme.auroraCyan, foregroundColor: DeepSpaceTheme.auroraCyan, backgroundColor: DeepSpaceTheme.auroraCyan.opacity(0.16))
        }
    }

    init(label: String, dotColor: Color, foregroundColor: Color, backgroundColor: Color) {
        self.label = label
        self.dotColor = dotColor
        self.foregroundColor = foregroundColor
        self.backgroundColor = backgroundColor
    }

    static func amber(label: String) -> StatusPillStyle {
        StatusPillStyle(
            label: label,
            dotColor: Fig.amber,
            foregroundColor: Fig.amber,
            backgroundColor: Fig.amber.opacity(0.14)
        )
    }
}

struct StatusPill: View {
    let style: StatusPillStyle

    init(state: RoomStatus) {
        self.style = StatusPillStyle(for: state)
    }

    init(style: StatusPillStyle) {
        self.style = style
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(style.dotColor)
                .frame(width: 6, height: 6)
            Text(style.label)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(style.foregroundColor)
        }
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(style.backgroundColor)
        .clipShape(Capsule(style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct SourceTag: View {
    enum Kind: CaseIterable, Equatable {
        case interview
        case review
        case schedule
        case practice

        var label: String {
            switch self {
            case .interview: return "面试"
            case .review: return "复盘"
            case .schedule: return "日程"
            case .practice: return "练习"
            }
        }

        var tint: Color {
            switch self {
            case .interview: return DeepSpaceTheme.auroraCyan
            case .review: return DeepSpaceTheme.reviewGreen
            case .schedule: return DeepSpaceTheme.amber
            case .practice: return DeepSpaceTheme.practiceText
            }
        }
    }

    let kind: Kind

    var body: some View {
        Text(kind.label)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(kind.tint)
            .padding(.horizontal, 9)
            .frame(height: 23)
            .background(kind.tint.opacity(0.12))
            .clipShape(Capsule(style: .continuous))
    }
}

struct ParticipantTile: View {
    enum Role: Equatable {
        case lead
        case panelist
        case candidate
    }

    enum State: Equatable {
        case active
        case listening
    }

    let name: String
    let role: Role
    let state: State
    var subtitle: String?
    var statusOverride: RoomStatus?
    var statusStyleOverride: StatusPillStyle?

    private var status: RoomStatus {
        if let statusOverride { return statusOverride }
        switch (role, state) {
        case (.lead, .active), (.panelist, .active):
            return .asking
        case (.candidate, .active):
            return .answering
        case (.panelist, .listening):
            return .observing
        case (.lead, .listening), (.candidate, .listening):
            return .listening
        }
    }

    private var roleLabel: String {
        switch role {
        case .lead: return "资深产品 · 主问"
        case .panelist: return "技术评委"
        case .candidate: return "候选人"
        }
    }

    private var avatarColor: Color {
        switch role {
        case .lead: return DeepSpaceTheme.auroraCyan
        case .panelist: return DeepSpaceTheme.auroraPurple
        case .candidate: return DeepSpaceTheme.reviewGreen
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Spacer()
                if let statusStyleOverride {
                    StatusPill(style: statusStyleOverride)
                } else {
                    StatusPill(state: status)
                }
            }

            ZStack {
                Circle()
                    .fill(avatarColor.opacity(0.16))
                    .frame(width: 74, height: 74)
                Circle()
                    .stroke(state == .active ? avatarColor : Fig.onDarkMuted.opacity(0.24), lineWidth: 2)
                    .frame(width: 62, height: 62)
                Image(systemName: role == .candidate ? "person.fill" : "person.crop.circle.fill")
                    .font(.system(size: 38, weight: .regular))
                    .foregroundStyle(avatarColor.opacity(state == .active ? 0.92 : 0.48))
            }

            VStack(spacing: 3) {
                Text(name)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Fig.onDarkText)
                Text(subtitle ?? roleLabel)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Fig.onDarkMuted)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(state == .active ? Fig.interviewElevated : Fig.interviewTile)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(state == .active ? DeepSpaceTheme.auroraCyan.opacity(0.74) : Fig.onDarkText.opacity(0.10), lineWidth: 1)
        )
    }
}

struct ControlButton: View {
    enum Kind: Equatable {
        case ghost
        case accent
        case danger
    }

    let kind: Kind
    let icon: String
    let label: String
    let action: () -> Void
    var isEnabled = true

    private var tint: Color {
        switch kind {
        case .ghost: return Fig.onDarkText
        case .accent: return DeepSpaceTheme.auroraCyan
        case .danger: return DeepSpaceTheme.dangerText
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .bold))
                    .frame(width: 52, height: 52)
                    .background(kind == .accent ? tint : tint.opacity(0.12))
                    .foregroundStyle(kind == .accent ? DeepSpaceTheme.nearBlackText : tint)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(tint.opacity(kind == .accent ? 0 : 0.42), lineWidth: 1))
                    .shadow(color: tint.opacity(kind == .accent ? 0.28 : 0), radius: 12, y: 5)

                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
    }
}

struct DimensionRow: View {
    let label: String
    let score: Int
    var weakThreshold = 60
    var showWeakFlag = true

    var isWeak: Bool {
        score < weakThreshold
    }

    private var tint: Color {
        if isWeak { return Fig.danger }
        if score < 75 { return Fig.amber }
        return Fig.success
    }

    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 7) {
                Text(label)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Fig.ink)
                if isWeak && showWeakFlag {
                    Text("重点补")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Fig.danger)
                        .padding(.horizontal, 6)
                        .frame(height: 18)
                        .background(Fig.danger.opacity(0.10))
                        .clipShape(Capsule(style: .continuous))
                }
                Spacer()
                Text("\(score)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(tint)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(Fig.line.opacity(0.72))
                    Capsule(style: .continuous)
                        .fill(tint)
                        .frame(width: proxy.size.width * CGFloat(max(0, min(score, 100))) / 100)
                }
            }
            .frame(height: 5)
        }
    }
}
