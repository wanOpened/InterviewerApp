import SwiftUI

private enum LoginField: Hashable {
    case phone
    case code
}

struct LoginView: View {
    @StateObject private var model: LoginViewModel
    @State private var agreementAccepted = false
    @FocusState private var focusedField: LoginField?

    init(model: LoginViewModel) {
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                Spacer()
                    .frame(height: max(96, proxy.size.height * 0.16))

                QinglanAvatarView(state: .idle, size: 140)
                    .frame(maxWidth: .infinity)

                Spacer()
                    .frame(height: max(48, proxy.size.height * 0.07))

                loginCard
                    .padding(.horizontal, 20)

                if let errorMessage = model.errorMessage, !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(DeepSpaceTheme.dangerText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.horizontal, 24)
                        .padding(.top, 10)
                }

                agreementRow
                    .padding(.top, model.errorMessage == nil ? 26 : 18)

                Spacer(minLength: 18)
            }
            .frame(width: proxy.size.width)
            .frame(minHeight: proxy.size.height)
        }
        // Tap anywhere outside the fields/buttons to dismiss the keyboard. Sits
        // behind the content, so taps on text fields and buttons still reach them;
        // only empty space falls through here.
        .background(
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { focusedField = nil }
        )
        .deepSpaceBackground()
        .toolbar {
            // numberPad has no return/Done key, so without this the keyboard can
            // never be dismissed (and would keep covering the agreement row).
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") { focusedField = nil }
                    .foregroundStyle(DeepSpaceTheme.auroraCyan)
            }
        }
    }

    private var loginCard: some View {
        VStack(spacing: 16) {
            phoneField
            codeField
            Button {
                Task { await model.verify() }
            } label: {
                Text("登录")
            }
            .buttonStyle(PrimaryCTAStyle())
            .disabled(!model.isSubmitEnabled)
            .opacity(model.isSubmitEnabled ? 1 : 0.5)
            .accessibilityIdentifier("login-submit")
        }
        .padding(20)
        .glassCard(cornerRadius: 22)
    }

    private var phoneField: some View {
        HStack(spacing: 12) {
            Text("+86")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.9))

            fieldDivider

            LoginTextField(placeholder: "手机号", text: $model.phone, focus: $focusedField, field: .phone)
                .keyboardType(.numberPad)
                .textContentType(.telephoneNumber)
                .accessibilityIdentifier("login-phone-field")
        }
        .loginFieldStyle()
    }

    private var codeField: some View {
        HStack(spacing: 12) {
            LoginTextField(placeholder: "验证码", text: $model.code, focus: $focusedField, field: .code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .accessibilityIdentifier("login-code-field")

            fieldDivider

            Button {
                Task { await model.requestCode() }
            } label: {
                Text(model.codeButtonTitle)
                    .font(.system(size: 14))
                    .foregroundStyle(
                        model.isPhoneValid && model.canResend
                        ? DeepSpaceTheme.auroraCyan
                        : DeepSpaceTheme.practiceText.opacity(0.4)
                    )
                    .frame(minWidth: 76, alignment: .trailing)
            }
            .disabled(!model.isPhoneValid || !model.canResend)
            .accessibilityIdentifier("login-get-code")
        }
        .loginFieldStyle()
    }

    private var fieldDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.18))
            .frame(width: 1, height: 20)
    }

    private var agreementRow: some View {
        Button {
            agreementAccepted.toggle()
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.3), lineWidth: 1.2)
                        .background {
                            Circle()
                                .fill(agreementAccepted ? DeepSpaceTheme.auroraCyan : Color.clear)
                        }
                        .frame(width: 15, height: 15)

                    if agreementAccepted {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Color.white)
                    }
                }

                (
                    Text("登录即代表同意")
                        .foregroundColor(DeepSpaceTheme.practiceText.opacity(0.5))
                    + Text("《用户协议》")
                        .foregroundColor(DeepSpaceTheme.auroraCyan.opacity(0.9))
                    + Text("与")
                        .foregroundColor(DeepSpaceTheme.practiceText.opacity(0.5))
                    + Text("《隐私政策》")
                        .foregroundColor(DeepSpaceTheme.auroraCyan.opacity(0.9))
                )
                .font(.system(size: 12))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("login-agreement")
    }
}

private struct LoginTextField: View {
    let placeholder: String
    @Binding var text: String
    let focus: FocusState<LoginField?>.Binding
    let field: LoginField

    var body: some View {
        ZStack(alignment: .leading) {
            if text.isEmpty {
                Text(placeholder)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.white.opacity(0.35))
                    .allowsHitTesting(false)
            }

            // Fill the full 54pt row height so the entire field is tappable for
            // focus and cursor placement — not just the ~20pt text baseline.
            TextField("", text: $text)
                .font(.system(size: 15))
                .foregroundStyle(Color.white.opacity(0.9))
                .tint(DeepSpaceTheme.auroraCyan)
                .focused(focus, equals: field)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct LoginFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 16)
            .frame(height: 54)
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
    }
}

private extension View {
    func loginFieldStyle() -> some View {
        modifier(LoginFieldStyle())
    }
}
