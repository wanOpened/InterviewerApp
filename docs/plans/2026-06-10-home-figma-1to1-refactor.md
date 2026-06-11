# 首页 1:1 还原 Figma 重构（删右上角日程按钮 + 修 margin + A1/A2 精确化）

> **Executor:** Codex CLI。目标：把 `Sources/Views/HomeView.swift` 的首页改到 **1:1 还原 Figma**
> （文件 `3Et33QN1QsrRSX98CsUDEs`，A1 首页+peek `599:71`、A2 语音创建确认 `599:74`）。Codex 看不到
> Figma，本文件内联了**全部精确视觉值**（px/颜色/字号/圆角/坐标），照抄即可。

> **GIT 硬规则：** 本 iOS 仓库 git 归用户。**禁止任何 git 命令**。✅ Checkpoint 处停下、打印待提交文件 +
> 建议 message，不自己提交。

## 构建 / 验证
```
cd <iOS repo root> && xcodegen generate && \
  xcodebuild test -scheme InterviewerApp -destination 'platform=iOS Simulator,name=<iPhone 15>'
```
设计 token 用现有 `Sources/DesignSystem/RedesignComponents.swift` 的 `Fig.*`：
ink `#121A24` / muted `#6B7686` / blue `#3B82F6` / success `#22A06B` / ctaElevated `#F8FAFC` /
ctaBorder `#E6ECF2`。**两个新灰**（不在 token 里，可加进 Fig 或本文件内联）：grabber 灰 `#CCD4DB`、
分隔线灰 `#D9DEE5`。

## 当前问题（用户反馈 + Claude 核对 Figma 确认）
1. **右上角浮着一个「日程」小字按钮**（`HomeView.swift:235-241`，id `home-schedule-entry-button`）——
   **Figma 里根本没有**，看着别扭。**删除**。
2. margin/纵向布局不合理：日程卡被塞进底部 `height*0.22` 区（y≈664），Figma 里卡在 **66%**（y=560），
   上方有大段留白、卡与 peek 间距~140px。现在卡和 peek 挤在一起。
3. 日程卡圆角 `8`（Figma=**16**）；「去准备」CTA 颜色走 `source.tint`，schedule 类型没映射 → 默认 **muted 灰**，
   Figma 是 **蓝 `#3B82F6`**。
4. A2 确认卡是单行 HStack，Figma 是**竖排三行 + 上方用户原话回显**。

画布基准 390×844（iPhone logical）。下列坐标按此换算成比例/锚定布局，**不要写死绝对 y**（要跨机型自适应），
但**间距比例和元素内部尺寸照抄**。

---

## Task 1 — 删除右上角「日程」按钮 + 重排首页纵向布局
**File:** `Sources/Views/HomeView.swift`（body，约 204-272 行）

- 删掉 `Button("日程", action: tapScheduleEntry) … home-schedule-entry-button`（235-241）。`tapScheduleEntry`
  闭包若无其他调用方则一并清理（日程列表入口改由 peek 上滑/点按 + 语音「查看日程」进入；空态无可见入口=语音优先，
  符合 voice-first；如担心非语音空态无入口，**本次不加**，留作后续 Figma 决策）。
- ZStack 不再用 `.topTrailing`；改为标准层叠（背景白 + 内容 VStack + 底部 peek/确认卡 overlay）。
- **纵向节奏（照 A1 599:71）**：
  - 青岚头像：居中于**上部**，中心约在屏高 **33%**（Figma 头像 top=150 h=255 → 中心 ~277/844）。
    头像视觉宽 ~204–226 都可（保留现有 `QinglanAvatarView` + `avatarSize`，但**不要**再用 `height*0.78` 把头像撑满）。
  - 日程卡：水平 **左右各 20pt**（Figma x=20 w=350），卡**顶部约在屏高 66%**（y=560/844），头像与卡之间留白充足。
  - peek 把手：**钉在底部**，距安全区底 ~12pt（Figma 卡底 832，距帧底 844=12）。卡底与 peek 顶之间有明显间距（Figma~140px）。
  - 建议结构：`VStack(spacing:0){ Spacer(); Avatar; Spacer(minLength: 大); ScheduleCard.padding(.horizontal,20); Spacer() }`
    再用 `.safeAreaInset(edge:.bottom)` 或底部对齐 overlay 放 peek/确认卡，确保 peek 永远贴底、不被卡挤。
- 背景纯白 `Color.white`，`ignoresSafeArea(edges:.bottom)` 保留。
✅ Checkpoint — user commits。

## Task 2 — 日程卡（`HomePrimaryActionCard`）1:1（node 606:82-86）
**File:** `Sources/Views/HomeView.swift:394-435`

精确值（卡 x=20 w=350 h=92，内部相对卡左/上）：
- 容器：bg `Fig.ctaElevated`(#F8FAFC)、描边 `Fig.ctaBorder`(#E6ECF2) 1pt、**圆角 16**（当前是 8）、高 **92**（当前 minHeight 88）。
- 圆点（606:83）：**9×9**，距卡左 **18**，垂直居中偏上（卡顶下 ~24，中心 588.5）。schedule 状态**蓝色 `Fig.blue`**。
- 标题（606:84）：`action.title`（如「明天 14:00 · 字节终面」）Inter **SemiBold 17** `Fig.ink`，距卡左 **36**，单行。
- 副标题（606:85）：`action.reason`（如「准备进度 5/6，还差一次针对性模拟」）Inter **Regular 13** `Fig.muted`，距卡左 36，
  **1 行**（lineLimit(1)+minimumScaleFactor 0.9）。
- CTA（606:86）：`action.cta`（如「去准备 ›」）Inter **SemiBold 14** **蓝 `Fig.blue`**（不是 tint！），右对齐，
  距卡右 ~14，垂直居中。
- 内部水平 padding：左 18（点）/文本 36；右 ~16。
- **修 tint**：`HomeCTASourceStyle` 给 schedule/create 相关类型映射 `Fig.blue`，或日程卡 CTA 固定蓝。**点与 CTA 同蓝**。
✅ Checkpoint — user commits。

## Task 3 — peek 把手（`HomeSchedulePeekHandle`）1:1（node 606:87-89）
**File:** `Sources/Views/HomeView.swift:355-392`

- 容器：**固定宽 270、高 40**（当前 hug 宽 + h46）、**居中**、bg 白、描边 `Fig.ctaBorder` 1pt、**圆角 20**。
- 抓手条（606:88）：色 **`#CCD4DB`**（不是 ctaBorder）、**30×4**、圆角 2、距容器顶 8。
- 文案（606:89）：`label`（「近期 N 场 · 上滑查看全部」）Inter **SemiBold 12.5** `Fig.muted`、**居中**、距抓手 ~8。
- 保留上滑手势（translation.height < -8 触发）+ id `home-schedule-peek`。
✅ Checkpoint — user commits。

## Task 4 — A2 语音创建确认卡（`ScheduleCreationConfirmationCard`）竖排 1:1（node 599:74）
**File:** `Sources/Views/HomeView.swift:279-353`

Figma 结构（卡 x=28 w=334 h=128，圆角 18）：
- **卡上方**：用户原话回显（607:82）「「{raw_command}」」Inter **Regular 14** `Fig.muted`、**居中**，距卡顶上方 ~38。
  若 `ScheduleCreationConfirmation` 有原话字段则显示；**没有就省略**（不要编造）。
- 容器：bg 白、描边 `Fig.ctaBorder` 1pt、**圆角 18**、阴影 `color: ink.opacity(0.14), radius: 14, y: 10`
  （Figma `0px 10px 28px rgba(15,26,41,0.14)`）、高 **128**、水平 **左右各 28**。
- **竖排三行**（VStack(alignment:.leading)）：
  - 行1：绿圆 **28×28**（`Fig.success` 底，可 0.14 透明圈 + 实心，按现有风格）内含 ✓（Inter Bold 16 `Fig.success`）
    + 「已为你创建」Inter **SemiBold 15** **`Fig.success`**。
  - 行2：`confirmation.summary`（如「周四 20:00 · 字节 · 三面」）Inter **SemiBold 17** `Fig.ink`。
  - 行3：「查看全部」Inter SemiBold 14 **`Fig.blue`** + 分隔条（`#D9DEE5` 1×18）+「撤销」Inter SemiBold 14 `Fig.muted`。
- 底部进度条（607:91）：`Fig.success` 高 **3**、圆角 2、宽从满→0 线性 3s（保留现有自毁 task），左对齐贴卡左内缘。
- 内部 padding：内容距卡左 ~20、各行垂直按 Figma 节奏（行1 顶~19、行2 顶~60、行3 顶~96、进度条~124）。
✅ Checkpoint — user commits。

## 总验收
- 右上角「日程」按钮已删；首页无该浮钮。
- `xcodebuild test` 全绿（保留/更新相关快照或布局测试；现有 home 测试 id `home-schedule-peek`/`home-primary-cta-card` 仍在）。
- 日程卡圆角 16、CTA+点蓝色；peek 270×40 居中、抓手 #CCD4DB；A2 竖排三行 + 进度条（+原话回显如可得）。
- 纵向：头像上部居中、卡在~66%、peek 贴底，三者间距舒展（不再挤）。
- 不新增 tab 栏；不破坏纯语音/无日程态；全程无 git 命令；每 ✅ Checkpoint 打印待提交清单。

## 给验收者（Claude）的对照锚点
Figma 截图：A1 `599:71`、A2 `599:74`。关键数值见上（卡圆角 16/18、peek 270×40、A2 h128 三行、去准备蓝）。
