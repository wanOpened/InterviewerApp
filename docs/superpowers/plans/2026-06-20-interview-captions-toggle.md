# 面试舞台「字幕(cc)」开关 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让第二幕·面试舞台底部的 `cc · 字幕` 按钮变成真实的「关闭字幕(closed captions)」开关 —— 点击隐藏/显示实时字幕卡，并让 cc 按钮反映开/关状态。

**Architecture:** 字幕显隐是一个会话级 UI 状态（必须放在 `InterviewSession` 上，因为 `RedesignInterviewRoomScreen` 包在 `TimelineView(.periodic by:1)` 里每秒重建，局部 `@State` 会被冲掉）。`InterviewSession` 新增 `captionsVisible`（默认 true）+ `toggleCaptions()`；`ObserveInterviewStage` 接收 `captionsVisible` 决定是否渲染 `ObserveCaptionCard`，并把 `captionsOn` 传给 `ObserveBottomControls` 让 cc 按钮在「关」时变暗。无后端、无网络、纯客户端状态。

**Tech Stack:** Swift / SwiftUI / XCTest，XcodeGen 工程，`@Observable` 的 `InterviewSession`（视图里用 `@Bindable`）。

## Global Constraints

- 真机命令：构建/测试统一用 `xcodebuild test -scheme InterviewerApp -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:InterviewerAppTests`。
- TDD：先写失败测试，再实现，`make`/`xcodebuild` 必须保持绿。
- 不新增文件（只改既有文件），因此**无需** `xcodegen generate`。
- 新增的视图参数必须带默认值（`captionsVisible: Bool = true` / `captionsOn: Bool = true`），以免破坏 `Sources/DesignSystem/DesignGallery.swift` 里不传该参数的调用点。
- 字幕默认**开**（cc = closed captions，常显）；关闭 = 隐藏 `ObserveCaptionCard` 并把 cc 按钮调暗。
- 不要给 cc 造假功能以外的东西：开关只控制字幕卡显隐这一真实行为。
- 若当前在默认分支（main/master），先 `git switch -c feat/interview-captions-toggle` 再开始；每个 Task 末尾按步骤提交。

---

### Task 1: 会话级字幕显隐状态 + toggleCaptions()

**Files:**
- Modify: `Sources/Session/InterviewSession.swift`（属性区 ~line 33-50；在 `resume()` 方法后追加 `toggleCaptions()`）
- Test: `Tests/InterviewSessionTests.swift`（在 `InterviewSessionTests` 类内追加一个测试）

**Interfaces:**
- Produces:
  - `InterviewSession.captionsVisible: Bool`（`private(set)`，默认 `true`）
  - `InterviewSession.toggleCaptions()` —— 同步方法，翻转 `captionsVisible`

- [ ] **Step 1: 写失败测试**

在 `Tests/InterviewSessionTests.swift` 的 `InterviewSessionTests` 类里，紧跟在 `test_interviewPresentationCandidateCardPromptsMicrophoneWhenDenied` 之后，加入：

```swift
    func test_toggleCaptionsFlipsVisibilityDefaultOn() async {
        // cc = closed captions：默认开（字幕卡常显），点击 cc 在显/隐之间切换。
        let session = InterviewSession(
            config: .default,
            api: FakeAPI(statuses: ["ready"]),
            liveKit: FakeLK(),
            pollInterval: 0
        )
        XCTAssertTrue(session.captionsVisible)

        session.toggleCaptions()
        XCTAssertFalse(session.captionsVisible)

        session.toggleCaptions()
        XCTAssertTrue(session.captionsVisible)
    }
```

- [ ] **Step 2: 跑测试确认失败**

Run: `xcodebuild test -scheme InterviewerApp -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:InterviewerAppTests/InterviewSessionTests/test_toggleCaptionsFlipsVisibilityDefaultOn 2>&1 | tail -20`
Expected: 编译失败，类似 `value of type 'InterviewSession' has no member 'captionsVisible'` / `'toggleCaptions'`。

- [ ] **Step 3: 实现最小代码**

在 `Sources/Session/InterviewSession.swift` 属性区，把 `private(set) var isPaused = false` 那一行改成两行（在其后补一行）：

```swift
    private(set) var isPaused = false
    private(set) var captionsVisible = true
```

在 `resume()` 方法的右花括号之后（`func end() async {` 之前）追加：

```swift
    /// 底部「字幕(cc)」开关：真实控制实时字幕卡的显隐（closed captions），
    /// 纯客户端 UI 状态，不触达后端/LiveKit。
    func toggleCaptions() {
        captionsVisible.toggle()
    }
```

- [ ] **Step 4: 跑测试确认通过**

Run: `xcodebuild test -scheme InterviewerApp -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:InterviewerAppTests/InterviewSessionTests/test_toggleCaptionsFlipsVisibilityDefaultOn 2>&1 | grep -E "Executed|TEST SUCCEEDED|TEST FAILED"`
Expected: `Executed 1 test, with 0 failures` + `** TEST SUCCEEDED **`。

- [ ] **Step 5: 提交**

```bash
git add Sources/Session/InterviewSession.swift Tests/InterviewSessionTests.swift
git commit -m "feat(interview): add session captions-visibility state + toggleCaptions()"
```

---

### Task 2: cc 按钮接线 —— 切换字幕显隐 + cc「关」态变暗

**Files:**
- Modify: `Sources/Views/InterviewView.swift`
  - `ObserveInterviewStage`（struct 头 ~line 508-512；body ~line 546-554）
  - `ObserveBottomControls`（struct 头 ~line 854-856；cc 的 `controlItem` ~line 862-870）
  - `RedesignInterviewRoomScreen` 的两个 `ObserveInterviewStage(...)` 调用点（~line 227-238）

**Interfaces:**
- Consumes（来自 Task 1）：`session.captionsVisible: Bool`、`session.toggleCaptions()`
- Produces：
  - `ObserveInterviewStage` 新增形参 `var captionsVisible: Bool = true`
  - `ObserveBottomControls` 新增形参 `var captionsOn: Bool = true`

- [ ] **Step 1: 给 `ObserveInterviewStage` 加 `captionsVisible` 形参**

在 `Sources/Views/InterviewView.swift`，把：

```swift
struct ObserveInterviewStage: View {
    let presentation: ObserveInterviewStagePresentation
    let captionsAction: () -> Void
    let leaveAction: () -> Void
    var requestMicrophone: (() -> Void)? = nil
```

改成：

```swift
struct ObserveInterviewStage: View {
    let presentation: ObserveInterviewStagePresentation
    let captionsAction: () -> Void
    let leaveAction: () -> Void
    var requestMicrophone: (() -> Void)? = nil
    var captionsVisible: Bool = true
```

- [ ] **Step 2: body 里按 `captionsVisible` 渲染字幕卡，并把状态传给底部控制**

把 body 里这一段：

```swift
                ObserveCaptionCard(presentation: presentation)
                    .padding(.top, 20)

                Spacer(minLength: 20)

                ObserveBottomControls(
                    captionsAction: captionsAction,
                    leaveAction: leaveAction
                )
```

改成：

```swift
                if captionsVisible {
                    ObserveCaptionCard(presentation: presentation)
                        .padding(.top, 20)
                }

                Spacer(minLength: 20)

                ObserveBottomControls(
                    captionsOn: captionsVisible,
                    captionsAction: captionsAction,
                    leaveAction: leaveAction
                )
```

- [ ] **Step 3: `ObserveBottomControls` 加 `captionsOn` 形参 + cc「关」态变暗**

把：

```swift
private struct ObserveBottomControls: View {
    let captionsAction: () -> Void
    let leaveAction: () -> Void
```

改成：

```swift
private struct ObserveBottomControls: View {
    var captionsOn: Bool = true
    let captionsAction: () -> Void
    let leaveAction: () -> Void
```

再把 cc 的 `controlItem` 块：

```swift
            controlItem(label: "字幕", action: captionsAction) {
                Text("cc")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.75))
                    .frame(width: 56, height: 56)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.16), lineWidth: 1))
            }
```

改成（开 = 原样；关 = 文字/填充/描边整体调暗，读作 inactive）：

```swift
            controlItem(label: "字幕", action: captionsAction) {
                Text("cc")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(captionsOn ? 0.75 : 0.35))
                    .frame(width: 56, height: 56)
                    .background(Color.white.opacity(captionsOn ? 0.08 : 0.04))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(captionsOn ? 0.16 : 0.10), lineWidth: 1))
            }
```

- [ ] **Step 4: 两个调用点接线到真实 session**

在 `RedesignInterviewRoomScreen.body`，把观摩分支：

```swift
                ObserveInterviewStage(
                    presentation: ObserveInterviewStagePresentation(session: session),
                    captionsAction: {},
                    leaveAction: observeLeave
                )
```

改成：

```swift
                ObserveInterviewStage(
                    presentation: ObserveInterviewStagePresentation(session: session),
                    captionsAction: session.toggleCaptions,
                    leaveAction: observeLeave,
                    captionsVisible: session.captionsVisible
                )
```

把正式面试分支：

```swift
                ObserveInterviewStage(
                    presentation: ObserveInterviewStagePresentation(interviewSession: session),
                    captionsAction: {},
                    leaveAction: interviewLeave,
                    requestMicrophone: session.openMicrophoneSettings
                )
```

改成：

```swift
                ObserveInterviewStage(
                    presentation: ObserveInterviewStagePresentation(interviewSession: session),
                    captionsAction: session.toggleCaptions,
                    leaveAction: interviewLeave,
                    requestMicrophone: session.openMicrophoneSettings,
                    captionsVisible: session.captionsVisible
                )
```

- [ ] **Step 5: 全量构建 + 测试，确保绿**

Run: `xcodebuild test -scheme InterviewerApp -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:InterviewerAppTests 2>&1 | grep -E "Executed [0-9]+ tests|TEST SUCCEEDED|TEST FAILED|error:"`
Expected: `Executed 148 tests, with 0 failures`（Task 1 之后总数 +1）+ `** TEST SUCCEEDED **`，无 `error:`。

- [ ] **Step 6: 提交**

```bash
git add Sources/Views/InterviewView.swift
git commit -m "feat(interview): wire cc button to toggle live captions + dim when off"
```

---

## 可选的目检（不强制，不计入 Task）

如需肉眼确认「关」态：可临时在 `Tests/` 写一次性快照测试，用真机安全区把 `ObserveInterviewStage(presentation: <live>, captionsAction: {}, leaveAction: {}, captionsVisible: false)` 渲染成 PNG（hosting 到带 `UIWindowScene` 的 `UIWindow`，`drawHierarchy` 截图到 `/tmp`），确认字幕卡消失、cc 变暗后**删除该一次性文件**。生产代码不保留任何快照测试。

## Self-Review 结论

- Spec 覆盖：cc 真实开关（显隐字幕卡）= Task 1（状态）+ Task 2（接线/视图/暗态）。✓
- 无占位符：所有步骤含完整代码与命令。✓
- 类型一致：`captionsVisible`/`toggleCaptions()`/`captionsOn` 在各 Task 命名一致；新增视图形参均带默认值，DesignGallery 调用点（`ObserveInterviewStage(presentation:captionsAction:leaveAction:)`）保持可编译。✓
