# iOS 日程容器（Approach A）— Implementation Plan (Codex)

> **Executor:** Codex CLI. 实现 青岚「日程为中心」的可见性方案：日程列表(容器) + 日程详情
> (JD 内嵌 + 简历旁挂) + JD/简历编辑 sheet + 首页近期 peek/自毁确认卡。**1:1 还原 Figma**
> （Figma 页「18 日程容器 · Approach A」node `599:68`）。Codex 看不到 Figma，本计划内联
> 全部视觉值与契约。

> **GIT 约束（项目硬规则）：** 用户独占本 iOS 仓库的所有 git 操作。**禁止任何 git 命令**。
> ✅ Checkpoint 处停下、打印待提交文件清单 + 建议 message，继续下一任务，不自己提交。

## 构建 / 验证
选可用模拟器：`xcrun simctl list devices available | grep -i iphone`
```
cd <iOS repo root> && xcodegen generate && \
  xcodebuild test -scheme InterviewerApp -destination 'platform=iOS Simulator,name=<iPhone>'
```
TDD：先写/改失败测试 → 最小实现 → 全绿。设计 token 一律用现有 `Fig.*`
（`Sources/DesignSystem/RedesignComponents.swift`：ink#121A24 / muted#6B7686 / blue#3B82F6 /
success#22A06B / amber#F09A24 / danger#E5484D / ctaElevated#F8FAFC / ctaBorder#E6ECF2）。
Source Tag 色：面试=blue / 复盘=success / 日程=amber / 练习=muted。

## 后端契约（已由 Backend 仓库补齐，直接对接，勿造 mock）
- `GET /v1/interview-schedules/{id}` → `ScheduleDetailRead { schedule, position, round, resume|null }`
- `InterviewScheduleRead` 新增可选 `position_title / company / round_name`
- `PositionRead` 新增 `jd_text`（+ seniority/created_at）
- `ResumeRead` 已含 `raw_text + created_at`（iOS 模型此前漏解，需补）
- 既有：`GET /v1/schedules/upcoming`、`PATCH /v1/positions/{id}/jd`、`POST /v1/resumes`、
  `startSchedule/createSession`、`updateSchedule`、`cancelSchedule`

### Task 0 — API/模型对齐（TDD，先做）
`Sources/API/APIModels.swift` + `Sources/API/APIClient.swift`：
- `ResumeRead` 增 `raw_text: String`、`created_at: String`。
- `PositionRead` 增 `jd_text: String`、`seniority: String?`、`created_at: String`。
- `InterviewScheduleRead` 增 `position_title: String?`、`company: String?`、`round_name: String?`。
- 新 `ScheduleDetailRead { schedule: InterviewScheduleRead; position: PositionRead; round: RoundRead; resume: ResumeRead? }`（按需补 `RoundRead`）。
- APIClient 增 `func scheduleDetail(id: String) async throws -> ScheduleDetailRead`（GET /v1/interview-schedules/{id}）、
  `func getCurrentResume() async throws -> ResumeRead`（GET /v1/resumes/me）。
- 测试：解码新字段；scheduleDetail/getCurrentResume 走通（用现有 APIClient 测试夹具）。
✅ Checkpoint — user commits。

---

## Phase 1 — 核心可见面（A3 列表 + A4 详情 + A5 编辑）

### Task 1 — A3 日程列表 `ScheduleListView`（容器，对应 node 599:77）
白底。布局（390 宽，x/间距照抄）：
- 顶部：标题「日程」Bold 30 ink @ (24,56)；副标题「倒计时越近，越靠前」Regular 14 muted @ (24,98)；右上「收起」Semi 13 muted（返回首页）。
- 「近期」分组标签 Semi 13 muted。**日程卡**（白底圆角18、描边 ctaBorder、高104、左20宽350）：
  公司色圆头像52(字=amber/蚂=success/书=…，白色首字Bold19) + 标题「公司 · 轮次名」Semi16 ink + meta「时间 · 形式 · 时长」Regular12.5 muted + 状态点+「待开始/进行中/已结束/已取消」Semi12（待开始=amber）+ 右上倒计时 pill（amber 底@浅、文字 amber，文案「明天/3 天」）+ 右侧 chevron ›。
- 「已结束」分组：condensed 卡（高76、cardElev 底）+「复盘 ›」success 链接。
- 底部 **Voice Bar**（cardElev 圆角28、blue 圆mic）「对青岚说：帮我约下周二的面试…」。
- 数据：`upcomingSchedules()` → 近期；状态映射见上。空态：引导语音创建。点卡 → A4 详情（scheduleDetail(id)）。
- 倒计时由 `scheduled_at` 计算（明天/N 天/今天 HH:mm）。
✅ Checkpoint — user commits。

### Task 2 — A4 日程详情 `ScheduleDetailView`（node 599:80）
返回「‹ 返回日程」。
- **头部卡**（白底圆角18 高128）：公司色头像56 + 「公司 · 轮次名」Semi17 + 「时间 · 组别 · 形式」Regular12.5 muted + 倒计时 pill + 「准备进度 x/y」+ amber 进度条。
- **JD 内嵌区块**（白底卡 高~160）：blue 点 +「岗位要求 · JD」Semi14.5 + 右「编辑」blue → A5(JD)；正文 = `position.jd_text` Regular13 muted（多行）。
- **本场简历 旁挂区块**（cardElev 卡 高80）：blue「简」圆头像 +「本场简历」Semi15 + 状态点+「v{version} · 已就绪」success（若 `resume==nil` → 「未上传 · 去补充」amber）+ 右「编辑 ›」→ A5(简历)。
  「建议更新」判定：`resume.created_at` 距今 > 阈值（如 30 天）显示 amber「建议更新」，否则 success「已就绪」。
- **主操作**：blue 主按钮「开始面试 →」（走既有 `startSchedule(id)`/创建会话进面试）；下方「改期」(muted→ updateSchedule) ｜「取消面试」(danger→ cancelSchedule)。
- 数据：`scheduleDetail(id)` 一次拿全（schedule/position/round/resume）。
✅ Checkpoint — user commits。

### Task 3 — A5 JD/简历 编辑 sheet（node 599:83）
底部 sheet（scrim 42% + 白底顶圆角26，约 634 高）：
- 抓手 + 标题（「编辑岗位 JD」/「编辑简历」）+ 右「完成」blue。
- 文本域（cardElev 圆角14）：JD = `position.jd_text`；简历 = `resume.raw_text`。可编辑。
- Voice Bar：「或对青岚说：把要求改成…」（占位，可后续接语音改写；先做文本编辑）。
- 「保存」blue 按钮：JD → `updatePositionJD(positionId, jdText)`；简历 → `createResume(rawText)`（生成新版本）。保存后回 A4 并刷新。
✅ Checkpoint — user commits。

### Task 4 — 兜底入口（保留 1 个，不要 tab 栏）
首页 `HomeView`/`VoiceConciergeHomeScreen` 加 **1 个低调入口**进入 A3：右上角「日程」小字或顶部「•••」（克制、不抢青岚）。这是非语音用户的 catch-all。**不得新增 tab 栏**。
✅ Checkpoint — user commits。

---

## Phase 2 — 首页可见性（A1 peek + A2 自毁确认卡）— 触碰纯语音首页，务必克制

### Task 5 — A1 近期日程 peek（node 599:71）
首页底部加 **半常驻 peek 把手**（白底圆角20、抓手条 + 「近期 N 场 · 上滑查看全部」Semi12.5 muted，居中）：上滑/点击 → A3。N = upcomingSchedules().count。无近期则隐藏。
首页单 CTA 卡在有最近日程时可呈现为日程化（「明天 14:00 · 字节终面 / 准备进度 x/y / 去准备 ›」）——复用现有 `primary_action` 渲染，不另造。
✅ Checkpoint — user commits。

### Task 6 — A2 语音创建后自毁确认卡（node 599:74）
语音创建日程成功后，首页**自动浮出确认卡**（白底圆角18 + 阴影）：绿 ✓「已为你创建」+「周X HH:mm · 公司 · 轮次」+「查看全部」(blue→A3)｜「撤销」(muted→ cancelSchedule)，底部无字自毁进度条（~3s 后淡出）。
- **触发（client-only，先不依赖新后端事件）**：home voice session 结束/工具完成后刷新 `upcomingSchedules()`，与进入前快照 diff；若出现新日程 → 用其摘要弹确认卡。
- （可选增强，未来）让 concierge 像 navigate-interview 那样发「schedule_created{schedule_id,summary}」LiveKit 数据消息，精确触发——本期**不做**，仅留 TODO。
✅ Checkpoint — user commits。

## 总验收
- A3/A4/A5 全部对接真接口（scheduleDetail/upcoming/updatePositionJD/createResume），**无 mock/假数据**。
- 进入面试沿用既有 startSchedule/会话流程（勿重写面试）。
- `xcodebuild test` 全绿；UI 体感 1:1 于 Figma 599:68 各屏。
- 不新增 tab 栏；首页改动克制、不破坏纯语音交互。
- 全程无 git 命令；每个 ✅ Checkpoint 打印待提交清单。
