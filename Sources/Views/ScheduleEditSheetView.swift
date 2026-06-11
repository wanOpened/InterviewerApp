import Foundation
import Observation
import SwiftUI

enum ScheduleEditKind: String {
    case jd
    case resume

    var title: String {
        switch self {
        case .jd:
            return "编辑岗位 JD"
        case .resume:
            return "编辑简历"
        }
    }
}

@MainActor
@Observable
final class ScheduleEditSheetModel {
    var text = ""
    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var errorMessage: String?

    private let kind: ScheduleEditKind
    private let detail: ScheduleDetailRead
    private let api: APIClienting
    private var didLoad = false

    init(kind: ScheduleEditKind, detail: ScheduleDetailRead, api: APIClienting) {
        self.kind = kind
        self.detail = detail
        self.api = api
    }

    func loadInitialText() async {
        guard !didLoad else { return }
        didLoad = true
        errorMessage = nil

        switch kind {
        case .jd:
            text = detail.position.jd_text
        case .resume:
            if let resume = detail.resume {
                text = resume.raw_text
                return
            }
            isLoading = true
            defer { isLoading = false }
            do {
                text = try await api.getCurrentResume().raw_text
            } catch let e as APIError {
                errorMessage = "\(e.errorCode): \(e.userMessage)"
            } catch {
                errorMessage = "\(error)"
            }
        }
    }

    func save() async -> Bool {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            errorMessage = kind == .jd ? "JD 不能为空" : "简历不能为空"
            return false
        }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            switch kind {
            case .jd:
                _ = try await api.updatePositionJD(positionId: detail.position.id, jdText: cleaned)
            case .resume:
                _ = try await api.createResume(rawText: cleaned)
            }
            return true
        } catch let e as APIError {
            errorMessage = "\(e.errorCode): \(e.userMessage)"
        } catch {
            errorMessage = "\(error)"
        }
        return false
    }
}

struct ScheduleEditSheetView: View {
    @State private var model: ScheduleEditSheetModel
    let kind: ScheduleEditKind
    let dismiss: () -> Void
    let saved: () async -> Void

    init(
        kind: ScheduleEditKind,
        detail: ScheduleDetailRead,
        api: APIClienting,
        dismiss: @escaping () -> Void,
        saved: @escaping () async -> Void
    ) {
        self.kind = kind
        _model = State(initialValue: ScheduleEditSheetModel(kind: kind, detail: detail, api: api))
        self.dismiss = dismiss
        self.saved = saved
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.58)
                .ignoresSafeArea()
                .onTapGesture(perform: dismiss)

            VStack(spacing: 16) {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.30))
                    .frame(width: 38, height: 5)
                    .padding(.top, 12)

                HStack {
                    Text(kind.title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(DeepSpaceTheme.primaryText)
                    Spacer()
                    Button("完成", action: dismiss)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DeepSpaceTheme.auroraCyan)
                        .buttonStyle(.plain)
                }
                .padding(.horizontal, 22)

                editor

                SheetVoiceBar()
                    .padding(.horizontal, 22)

                Button {
                    Task {
                        if await model.save() {
                            await saved()
                        }
                    }
                } label: {
                    Text(model.isSaving ? "保存中" : "保存")
                }
                .buttonStyle(PrimaryCTAStyle())
                .disabled(model.isSaving)
                .padding(.horizontal, 22)

                if let errorMessage = model.errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(DeepSpaceTheme.dangerText)
                        .lineLimit(2)
                        .padding(.horizontal, 22)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 634)
            .background(.ultraThinMaterial)
            .background(DeepSpaceTheme.backgroundBottom.opacity(0.88))
            .overlay(
                UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26)
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
            )
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26))
        }
        .task {
            await model.loadInitialText()
        }
    }

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $model.text)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(DeepSpaceTheme.primaryText)
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(maxWidth: .infinity)
                .frame(height: 356)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(DeepSpaceTheme.auroraCyan.opacity(0.55), lineWidth: 1)
                )

            if model.isLoading {
                Text("正在读取简历")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(DeepSpaceTheme.tertiaryText)
                    .padding(20)
            }
        }
        .padding(.horizontal, 22)
    }
}

private struct SheetVoiceBar: View {
    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [DeepSpaceTheme.auroraCyan, DeepSpaceTheme.auroraCyan.opacity(0.12)],
                        center: .center,
                        startRadius: 2,
                        endRadius: 22
                    )
                )
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: "mic.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.white)
                )

            Text("或对青岚说：把要求改成…")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(DeepSpaceTheme.tertiaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 48)
        .glassCard(cornerRadius: 24)
    }
}
