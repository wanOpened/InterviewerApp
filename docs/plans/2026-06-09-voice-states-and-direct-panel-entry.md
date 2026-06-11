# iOS 语音反馈状态 + 直达面板入场 — Implementation Plan (Codex)

> **Executor:** Codex CLI (GPT-5.5, xhigh). 两个独立改动，一起做：
> **Track A** = 首页 青岚 语音反馈状态（说话时嘴一直动 / 聆听态 / 思考态）。
> **Track B** = 进入面试直接落到「面板提问页」，删除「进入房间」中间页，后台状态内联到本页提示。
> 硬性要求：**1:1 还原 Figma**（颜色、文案、间距、状态语义）。Codex 看不到 Figma，
> 本计划已把所有具体视觉值内联，照着实现即可。

> **GIT 约束（项目硬规则，见 `IMPLEMENTATION_PLAN.md`）：** 用户独占本 iOS 仓库的
> 所有 git 操作。**Codex 禁止运行任何 git 命令**（不 `git add` / `git commit` /
> `git init`）。凡是计划里写 **✅ Checkpoint — user commits** 的地方：停下，打印
> 「改了哪些文件、建议的 commit message」，然后继续做下一个任务，**不要自己提交**。

## 构建 / 验证命令

先选一个可用模拟器：`xcrun simctl list devices available | grep -i iphone`
```bash
cd <iOS repo root> && xcodegen generate && \
  xcodebuild test -scheme InterviewerApp \
  -destination 'platform=iOS Simulator,name=<iPhone 设备名>' | xcpretty || true
```
TDD：先写/改失败测试 → 最小实现 → 全绿。纯逻辑用单测；LiveKit/SwiftUI 外壳靠真机
体感验证。现有相关测试：`Tests/RedesignComponentsTests.swift`、
`Tests/InterviewSessionTests.swift`、`Tests/HomeVoicePanelModelTests.swift`。

---

# Track A — 首页 青岚 语音反馈状态

## 目标（Figma board「17 青岚 · 语音反馈状态 (Home)」node `574:516`）
首页头像在三态下要有清晰、连续的动效：
- **speaking（青岚在说）：嘴必须持续开合循环**，不能定格。口型走 `合→微→圆→A→圆→微`
  循环，幅度序列 `0 → .3 → .6 → 1.0 → .6 → .3`，**每帧约 80ms**；同时显示声波脉冲
  （voice pulse）。
- **listening（用户在说）：** 收敛的内缩环 + 轻微 inward scale（绿色语义），区别于说话的外扩。
- **thinking（工具/LLM 处理中）：** 三点级联脉冲（紫色语义）。
- 状态切换 **300ms ease-in-out**；口型帧切换 **~80ms**。

## 根因（这是 BUG，不是缺设计）
`Sources/Views/QinglanAvatarView.swift`：
- 首页头像 = `QinglanAvatarView`（line 731）→ `CompanionStageView(spec: .compact(size:))`。
- `.compact`（line 72）`includesMouthLoop: false`、`includesVoicePulse: false`。
- `CompanionStageView.characterAmplitude`（line 618）说话分支：
  `case .speaking: guard spec.includesMouthLoop else { return mouthOpen ? 0.42 : 0.18 }`。
- `mouthOpen` 是 `@State`（line 564），只在 `.onAppear { mouthOpen = true }`（line 600-604）
  **置一次 true，永不回切** → `characterAmplitude` 恒为 `0.42` → `mouthOpenness`
  （line 267-268）恒定 → 嘴张到固定形状后**定格**；`.animation(value: amplitude)` 因
  amplitude 不变而从不触发。`.resultsSpeaking` 同样只置一次 → 同样不循环（只是张得更大）。

## 实现要求
1. **让说话振幅随时间循环。** 在 `CompanionStageView`（或下沉到 `CompanionCharacterView`）
   引入一个连续时间源——`TimelineView(.animation)` 或 ~10–12fps 的定时器——当
   `state == .speaking` 时产出一个**循环合成振幅** `speakingAmplitude ∈ [0.18, 0.95]`，
   按 `合→微→圆→A→圆→微`（`0/.3/.6/1/.6/.3`）的节奏推进，且**带轻微随机/多正弦包络**，
   看起来像说话而非节拍器。把它作为 `amplitude` 传给 `CompanionCharacterView`。
   - `CompanionCharacterView.mouthOpenness`（267）与 `openMouth(openness:)`（280）已能
     按 amplitude 渲染开口——只需要喂入一个会变化的 amplitude 即可。
   - 把 `.animation(.easeOut(duration: 0.12), value: amplitude)`（line 145）改为 **~0.08s（80ms）**
     以匹配口型帧切换节奏。
2. **`.compact` 打开 `includesMouthLoop: true` 与 `includesVoicePulse: true`**（line 89-90），
   让首页拿到完整开口幅度 + 声波脉冲（与 board 574:516 一致）。
3. **非说话态保持 `restingMouth`**；`state` 切换用 300ms ease-in-out（line 587 已是 0.42s，
   收敛到 0.3s）。
4. **listening：** 维持/强化内缩 inward scale（line 671-676 已有 `.listening` 分支），
   语义色保持绿。若 `HomeVoicePanelModel` 后续能暴露用户麦克风电平，可接入绿色 voice meter；
   当前未接入则保留 inward 收敛即可。
5. **thinking：** 复用现有 `thinkingDots`（line 323），确认三点级联在 `thinkPulse`
   `repeatForever` 下真的在动；如未动，按相同方式用连续时间源驱动。
6. **真实振幅是可选增强**：当前 `HomeVoicePanelModel`/`LiveKitControlling` 未把 agent 音频
   逐帧电平透出到首页模型，因此**合成循环就是与 board 对齐的实现**（board 明确把合成
   fallback 列为可接受方案）。不要为此重构 LiveKit 管线。

## 不要碰
- 不要改 `mobai/chengcheng/xingyu` 的形象；只动 `qinglan` 路径与通用动效驱动。
- 不要改 `HomeVoicePanelModel` 的状态机映射（line 208-259 已正确：agentSpeaking→.speaking、
  localSpeaking→.listening、toolActivity→.thinking）——它是对的，问题只在动画驱动。

## 验收（Track A）
- 首页点头像进入会话，**青岚说话时嘴连续开合**（录屏/真机确认，不定格）。
- 用户开口 → 切 listening（内缩、绿语义）；工具处理 → thinking 三点级联（紫语义）。
- 状态切换平滑（~300ms），无突兀跳变。
- `RedesignComponentsTests` 全绿；模拟器 build 成功。
✅ Checkpoint — user commits（`QinglanAvatarView.swift` 等）。

---

# Track B — 进入面试直接落到「面板提问页」

## 目标（Figma boards：连接态 `583:15` · 已连接 `372:144` · 状态映射注解卡 `592:68`）
进入面试房间时**直接进入「面板提问页」**（= 现有 `InRoomView`，对应 node `372:144`）。
**删除「进入房间」中间页**（现有 `ConnectingRoomView`）。LiveKit 连接 / 面试官加入 /
题单同步 / 麦克风权限 / 失败重连等后台状态，**全部内联到这张面板上提示**，用户不再看到
单独的进入页。同一张面板只做状态切换（300ms），不切页。

## 现状（要改的结构）
`Sources/Views/InterviewView.swift`：
- `RedesignInterviewRoomScreen`（line 102）按 `session.roomPhase` 分支：
  - `case .connecting:` → `ConnectingRoomView`（line 181）= **要删的「进入房间」中间页**
    （"正在进入面试间" + 连接检查清单 `ConnectionCheckRow` + 麦克风权限卡 + "等待面试官
    同步房间状态…" + 取消按钮）。
  - `case .inRoom:` / `.leaving:` → `InRoomView`（line 279）= **面板提问页（目标）**。
- `InRoomView`（279）已优雅降级：participant tiles 默认 `.connecting`，候选人条
  "待开麦 · 需要麦克风权限"，字幕卡 "等待实时字幕…"。`RedesignRoomHeader`（149）的
  `StatusPill`（line 173）已随 `session.connected` 显示 连接中/已连接。

`Sources/Session/InterviewSession.swift`：状态机已就绪——`ConnectionStatus`
（idle/preparingSession/requestingToken/joiningRoom/connected/...）、`RoomPhase`
（connecting/inRoom/leaving）、`canEnterRoom`（line 49 = `phase==.live && connected
&& microphonePermissionGranted`）、`cancelRoomEntry()`（line 278，仅 `.connecting` 时可退）、
`participantStatuses` 由 `applyParticipantAttributes`（394）驱动。**后端契约不改。**

## 实现要求
1. **`RedesignInterviewRoomScreen` 删除 `.connecting → ConnectingRoomView` 分支**：
   `.connecting`、`.inRoom`、`.leaving` **都渲染 `InRoomView`**。`.leaving` 仍叠
   `RedesignLeaveSheet`（line 139-144 逻辑保留）。
2. **删除 `ConnectingRoomView`（181-262）与仅它使用的 `ConnectionCheckRow`（264-277）**
   （先 grep 确认无其它引用，连带删它们的测试断言）。其承载的信息内联到面板：
3. **`InRoomView` 内联后台状态（按下面的连接态视觉值 1:1）：**
   - 顶部 `StatusPill`：未连接时 `连接中`（琥珀 `Fig.amber`），连接后 `已连接`（绿）。
     绑定 `session.connected`。
   - 两个 participant tile 的状态药丸：未就绪时 主面试官=`连接中`、评委=`待加入`（琥珀）；
     就绪后 `在提问` / `旁听`。绑定 `participantStatuses[.lead]` / `[.panelist]`。
     连接态下主面试官头像**不要**高亮蓝环 + 均衡器（调暗 active 环、隐藏波形），避免误读为
     "正在说话"。
   - 候选人条：未授权麦克风时显示 `待开麦 · 开启麦克风`（琥珀），**点击内联拉起系统麦克风
     授权**（把原 lobby 的麦克风卡能力迁到这里，调 `session.openMicrophoneSettings()` /
     权限请求）；授权后 `聆听中 · 麦克风开`。绑定 `microphonePermissionGranted` + `roomStatus`。
   - 字幕/题面卡：连接中显示 chip `主面试官 · 连接中`（琥珀点）+ 正文
     `正在接入面试官，正在同步本场题单…`；进入提问后切换为正常 `主面试官 · 提问中` + 题目正文。
     绑定 `roomPhase` + `questionSetSynced`(totalQuestions>0) + `liveCaptionText`。
   - 底部：连接中 hint = `正在连接房间，请稍候 · 稍后即可直接开口`；中间「开口作答」控制键
     在 `!canEnterRoom` 时**置灰禁用**（opacity ~0.4，不可点），就绪后启用。
   - **失败 / 重连：** `session.phase == .failed(msg)` 时，题面卡显示
     `连接异常，正在重试…`，底部「离开」可退出。保留优雅失败语义（filler + 一次重试 →
     优雅退出，**绝不中途崩溃、绝不把内部错误暴露给用户**）。
4. **退出路径：** 连接态下底部「离开」按钮 = 退出入场。`.connecting` 时调
   `session.cancelRoomEntry()`（line 278）然后 `dismiss()`（替代原 lobby 取消按钮）；
   `.inRoom` 时保持现有 `requestLeave()` → `RedesignLeaveSheet` 流程。
5. **过渡：** 连接态 → 提问态是同一张面板的内联状态切换（~300ms ease-in-out），不得跳转/重建页面。
6. **HomeView 入口不变**：`HomeView.swift` 已 `navigationDestination` 直接 push
   `InterviewView`（line 43-54），本来就没有独立的「进入房间」导航页——「进入房间」只是
   `InterviewView` 内部 `ConnectingRoomView` 这个子视图，删它即可。

## 连接态视觉值（1:1，照抄；琥珀统一用 `Fig.amber`）
| 元素 | 连接态文案 | 已连接文案 | 绑定来源 |
| --- | --- | --- | --- |
| 顶部状态药丸 | `连接中`(琥珀) | `已连接`(绿) | `session.connected` |
| 主面试官 tile 药丸 | `连接中`(琥珀) | `在提问` | `participantStatuses[.lead]` |
| 评委·李 tile 药丸 | `待加入`(琥珀) | `旁听` | `participantStatuses[.panelist]` |
| 候选人条 | `待开麦 · 开启麦克风`(琥珀，可点拉起授权) | `聆听中 · 麦克风开` | `microphonePermissionGranted`+`roomStatus` |
| 题面 chip | `主面试官 · 连接中`(琥珀点) | `主面试官 · 提问中` | `roomPhase` |
| 题面正文 | `正在接入面试官，正在同步本场题单…` | 题目正文 | `roomPhase`+`liveCaptionText`+`questionSetSynced` |
| 底部 hint | `正在连接房间，请稍候 · 稍后即可直接开口` | `轮到你直接开口即可 · 随时举手打断` | — |
| 中间「开口作答」键 | 置灰禁用(opacity~0.4) | 可用 | `canEnterRoom` |

面板其余布局（header timer/Q 计数、两个 tile 165×200、候选人条、字幕卡、底部三键
字幕/开口作答/离开）保持 node `372:144` 现有 `InRoomView` 不变。

## 验收（Track B）
- 进入面试**不再出现「进入房间」中间页**；落地即是面板提问页，后台状态内联提示。
- 连接中 → 已连接 全程同一张面板内联切换；麦克风未授权能在候选人条内联拉起授权。
- 失败时面板内提示并可优雅离开，不崩溃、不暴露内部错误。
- `InterviewSessionTests` / `RedesignComponentsTests` 调整后全绿；模拟器 build 成功。
- `grep -rn "ConnectingRoomView\|ConnectionCheckRow" Sources Tests` 无残留引用。
✅ Checkpoint — user commits（`InterviewView.swift`、必要时 `InterviewSession.swift` 及相关测试）。

---

## 总验收
- Track A：首页说话嘴连续动 + listening/thinking 清晰；Track B：直达面板、无进入房间页、状态内联。
- 全量 `xcodebuild test` 通过；真机/模拟器体感符合上面两块 Figma。
- 全程未运行任何 git 命令；每个 ✅ Checkpoint 打印待提交文件清单交用户提交。
