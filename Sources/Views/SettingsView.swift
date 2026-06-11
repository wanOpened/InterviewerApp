import SwiftUI
import UIKit

struct SettingsView: View {
    @Binding var config: AppConfig
    private let microphonePermission: MicrophonePermissionProviding
    @Environment(\.dismiss) private var dismiss
    @State private var showResumeEditor = false
    @State private var microphoneStatus: MicrophonePermissionStatus

    init(
        config: Binding<AppConfig>,
        microphonePermission: MicrophonePermissionProviding = SystemMicrophonePermissionProvider()
    ) {
        self._config = config
        self.microphonePermission = microphonePermission
        self._microphoneStatus = State(initialValue: microphonePermission.status)
    }

    var body: some View {
        ZStack(alignment: .top) {
            SettingsFig.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(spacing: 16) {
                        SettingsSectionCard(title: config.selectedCompanion.displayName) {
                            SettingsStaticRow(title: "音色", value: "清亮")
                            SettingsRowDivider()
                            SettingsActionRow(title: "麦克风", value: microphoneStatus.settingsLabel) {
                                openMicrophoneSettings()
                            }
                        }

                        SettingsSectionCard(title: "本机") {
                            SettingsTextRow(title: "LAN IP", text: $config.host, keyboard: .numbersAndPunctuation)
                            SettingsRowDivider()
                            SettingsNumberRow(title: "API 端口", value: $config.apiPort)
                            SettingsRowDivider()
                            SettingsNumberRow(title: "LiveKit", value: $config.livekitPort)
                            SettingsRowDivider()
                            SettingsNumberRow(title: "Seed 轮次", value: $config.seedRoundIndex, range: 0...10)
                        }

                        SettingsSectionCard(title: "账号") {
                            SettingsTextRow(title: "Dev 用户", text: $config.devUserExternalId, keyboard: .default)
                            SettingsRowDivider()
                            SettingsActionRow(title: "简历", value: "管理") {
                                showResumeEditor = true
                            }
                            SettingsRowDivider()
                            SettingsStaticRow(title: "同步", value: "已开启")
                            SettingsRowDivider()
                            SettingsStaticRow(title: "隐私", value: "本机调试")
                        }

                        Button(action: close) {
                            Text("完成")
                                .settingsFont(16, weight: .bold, color: .white)
                                .frame(maxWidth: .infinity, minHeight: 50)
                                .background(SettingsFig.ink)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 28)
                }
            }
        }
        .presentationDragIndicator(.visible)
        .fullScreenCover(isPresented: $showResumeEditor) {
            ResumeEditorView(config: config)
        }
        .onAppear {
            microphoneStatus = microphonePermission.status
        }
    }

    private var header: some View {
        HStack {
            Text("设置")
                .settingsFont(22, weight: .bold, color: SettingsFig.ink)
            Spacer()
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SettingsFig.ink)
                    .frame(width: 36, height: 36)
                    .background(.white)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(SettingsFig.line, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 10)
    }

    private func close() {
        config.save()
        dismiss()
    }

    private func openMicrophoneSettings() {
        microphonePermission.openSettings()
        microphoneStatus = microphonePermission.status
    }
}

private struct SettingsActionRow: View {
    let title: String
    let value: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title)
                    .settingsFont(15, weight: .regular, color: SettingsFig.muted)
                Spacer(minLength: 12)
                Text(value)
                    .settingsFont(15, weight: .semibold, color: SettingsFig.ink)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SettingsFig.muted)
            }
            .padding(.horizontal, 18)
            .frame(height: 48)
        }
        .buttonStyle(.plain)
    }
}

private struct ResumeEditorView: View {
    let config: AppConfig
    @Environment(\.dismiss) private var dismiss
    @State private var rawText = ""
    @State private var isSubmitting = false
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("简历")
                    .settingsFont(22, weight: .bold, color: SettingsFig.ink)
                Spacer()
                Button("完成") { dismiss() }
                    .font(.system(size: 14, weight: .semibold))
                    .buttonStyle(.plain)
            }

            TextEditor(text: $rawText)
                .font(.system(size: 15))
                .padding(12)
                .frame(maxWidth: .infinity, minHeight: 320)
                .scrollContentBackground(.hidden)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(SettingsFig.line, lineWidth: 1)
                )

            if let message {
                Text(message)
                    .settingsFont(
                        13,
                        weight: .medium,
                        color: message == "简历已更新" ? SettingsFig.ink : .red
                    )
            }

            Button(action: submit) {
                Text(isSubmitting ? "提交中…" : "更新简历")
                    .settingsFont(16, weight: .bold, color: .white)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(SettingsFig.ink)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isSubmitting || rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Spacer()
        }
        .padding(20)
        .background(SettingsFig.background.ignoresSafeArea())
    }

    private func submit() {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isSubmitting = true
        message = nil
        Task {
            do {
                let api = APIClient(
                    baseURL: config.apiBaseURL,
                    userExternalId: config.devUserExternalId
                )
                try await api.ensureUser()
                _ = try await api.createResume(rawText: text)
                message = "简历已更新"
            } catch let error as APIError {
                message = "\(error.errorCode): \(error.userMessage)"
            } catch {
                message = "\(error)"
            }
            isSubmitting = false
        }
    }
}

private struct SettingsSectionCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .settingsFont(13, weight: .bold, color: SettingsFig.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 4)

            content()
        }
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(SettingsFig.line, lineWidth: 1)
        )
    }
}

private struct SettingsRowDivider: View {
    var body: some View {
        Rectangle()
            .fill(SettingsFig.line)
            .frame(height: 1)
            .padding(.leading, 18)
    }
}

private struct SettingsStaticRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .settingsFont(15, weight: .regular, color: SettingsFig.muted)
            Spacer(minLength: 12)
            Text(value)
                .settingsFont(15, weight: .semibold, color: SettingsFig.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 18)
        .frame(height: 48)
    }
}

private struct SettingsTextRow: View {
    let title: String
    @Binding var text: String
    let keyboard: UIKeyboardType

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .settingsFont(15, weight: .regular, color: SettingsFig.muted)
            Spacer(minLength: 12)
            TextField("", text: $text)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(SettingsFig.ink)
                .multilineTextAlignment(.trailing)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .frame(maxWidth: 210)
        }
        .padding(.horizontal, 18)
        .frame(height: 48)
    }
}

private struct SettingsNumberRow: View {
    let title: String
    @Binding var value: Int
    var range: ClosedRange<Int> = 1...65535

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .settingsFont(15, weight: .regular, color: SettingsFig.muted)
            Spacer(minLength: 12)
            HStack(spacing: 10) {
                stepperButton("minus", action: decrement)
                Text("\(value)")
                    .settingsFont(15, weight: .semibold, color: SettingsFig.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(minWidth: 44)
                stepperButton("plus", action: increment)
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 48)
    }

    private func stepperButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(SettingsFig.ink)
                .frame(width: 28, height: 28)
                .background(SettingsFig.soft)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private func decrement() { value = max(range.lowerBound, value - 1) }
    private func increment() { value = min(range.upperBound, value + 1) }
}

private enum SettingsFig {
    static let background = Color(hex: 0xF7F7F5)
    static let ink = Color(hex: 0x1A1D2B)
    static let muted = Color(hex: 0x6B7280)
    static let line = Color(hex: 0xE2E8F0)
    static let soft = Color(hex: 0xF1F5F9)
}

private extension View {
    func settingsFont(_ size: CGFloat, weight: Font.Weight, color: Color) -> some View {
        font(.system(size: size, weight: weight))
            .foregroundStyle(color)
            .tracking(0)
    }
}

private extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
