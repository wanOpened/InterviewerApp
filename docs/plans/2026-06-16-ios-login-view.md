# iOS 手机登录页 LoginView 落地（深空声场风 · 接 /v1/auth/phone）

> **Executor:** Codex CLI。目标：在 `InterviewerApp` 实现**手机号 + 短信验证码**登录页与登录态门控，
> 接后端 `/v1/auth/phone/*` 契约。视觉 **1:1 还原 Figma**（文件 `3Et33QN1QsrRSX98CsUDEs`，page
> `v2 · 深空声场 · 三幕剧`：`L1 手机登录` node `731:198`、`L2 验证码已发送` node `737:211`）。
> Codex 看不到 Figma —— 本文件内联了**全部精确视觉值与契约**，照抄即可。

> **GIT 硬规则：** 本 iOS 仓库 git 归用户。**禁止任何 git 命令（含 add/commit/checkout/restore）**。
> 每个 ✅ Checkpoint 处停下、打印「待提交文件 + 建议 commit message」，由用户提交。

> **依赖：** 后端手机登录模块（Backend 仓库 plan `docs/superpowers/plans/2026-06-16-phone-login-user-module.md`，
> 端点 `/v1/auth/phone/request-code`、`/verify`、`/refresh`、`/logout`、`GET /v1/me`）需先部署。
> 本计划所有单测用注入的 `Transport` 桩，不依赖真后端；真机联调放最后。

## 构建 / 验证
```
cd <iOS repo root> && xcodegen generate && \
  xcodebuild test -scheme InterviewerApp -destination 'platform=iOS Simulator,name=iPhone 16'
```
（destination 用本机已装的模拟器；沿用现有测试目标 `InterviewerAppTests`。）

## 复用现有设计系统（不要重造）
`Sources/DesignSystem/DeepSpaceTheme.swift` 已有全部 token 与 modifier，**直接用**：
- 背景：`.deepSpaceBackground()`（线性渐变 `#05070D→#080D1A→#0E1528` + 左上青光晕/右下紫光晕，**与登录页设计完全一致**）。
- 玻璃：`.glassCard(cornerRadius:strokeOpacity:)`（`glassFill` 白 8% + 描边白 12% + `.ultraThinMaterial`）。
- 主按钮：`PrimaryCTAStyle`（青→蓝渐变 `primaryCTAStart #4FD9C9 → primaryCTAEnd #338FDB` + 青色发光阴影 radius28/y12，height 58，圆角 29，`nearBlackText` 字色，按压缩放）。
- 色：`auroraCyan #6FE7DB`、`practiceText #C7D1E6`、`primaryText`(白0.95)、`secondaryText`(白0.64)、`tertiaryText`(白0.45)、`dangerText #FF8C94`。
- 形象：`QinglanAvatarView(state: .idle, size:)`（`Sources/Views/QinglanAvatarView.swift`，青岚 + 光晕五态）。
- 状态机：`QinglanState`（`Sources/Session/QinglanState.swift`）。

字体：iOS 无 Noto Sans SC，用系统字（中文回落 PingFang SC）。中文统一 `.system(size:weight:)`，数字同理。

---

## 视觉规格（1:1，内联自 Figma node 731:198 / 737:211）

画布基准 390×844（iPhone logical）。**坐标换算成比例/锚定布局，不要写死绝对 y**（跨机型自适应），
但元素内部尺寸、间距比例、颜色、字号照抄。状态栏用系统真实状态栏（**不要**画 9:41，那是 Figma 占位）。

纵向结构（顶→底，建议 `VStack(spacing:0)` + `Spacer()` 配比）：
1. **青岚 hero**：`QinglanAvatarView(state: .idle, size: 140)`，水平居中，视觉中心约屏高 **24–28%**。
2. **品牌字「青岚」**：`.system(size: 30, weight: .bold)`，`primaryText`，字距 `.tracking(4)`，居中。位于 hero 下方约 12pt。
3. **tagline「声音即入口」**：`.system(size: 14)`，`practiceText.opacity(0.7)`，`.tracking(2)`，居中，距品牌字 ~8pt。
4. **登录卡**（`.glassCard(cornerRadius: 22)`，左右各 20pt，内边距 20，`VStack(spacing: 16)`），顶部约屏高 **52%**：
   - **手机号框**（`FieldStyle`：高 54、背景白 8%、描边白 14%、圆角 16）：
     `HStack(spacing:0)`：`Text("+86")`(`.system(15,.medium)`, 白0.9) · 间距12 · 竖分隔 1×20 白0.18 · 间距12 ·
     `TextField("手机号", text:)`（`.keyboardType(.numberPad)`, 文本白0.9, 占位 `tertiaryText`/白0.35, 字号15）。
   - **验证码框**（同 FieldStyle）：
     `HStack`：`TextField("验证码", text:)`(numberPad, 字号15) · `Spacer()` · 竖分隔 1×20 白0.18 ·
     `Button` 右侧 `获取验证码`（`auroraCyan`，`.system(14)`）。倒计时态变 `59s 重发`（`practiceText.opacity(0.4)`，disabled）。
   - **登录按钮**：`Button("登录"){…}.buttonStyle(PrimaryCTAStyle())`。无效（手机号非11位 或 验证码空）时 `.disabled(true)` 且 `.opacity(0.5)`。
5. **用户协议行**：`HStack(spacing:8)` 居中，距卡 ~26pt：
   - 复选圈：`Circle().stroke(.white.opacity(0.3), lineWidth:1.2).frame(15×15)`，勾选后填 `auroraCyan` + 白勾。
   - 文案：`登录即代表同意《用户协议》与《隐私政策》`，`.system(12)`，`practiceText.opacity(0.5)`；其中
     `《用户协议》`/`《隐私政策》` 用 `auroraCyan.opacity(0.9)`（拼接两段 `Text` 着色）。
6. Home 指示条由系统绘制，**不画**。

**L2「验证码已发送」态 = 同一 LoginView 的状态变体**（非另一个 View）：手机号已填、验证码已填、`获取验证码`→`59s 重发`(倒计时 disabled)、登录键可点（发光由 `PrimaryCTAStyle` 提供）。即下面 `LoginViewModel` 的 `codeSent` 阶段。

无教学/说明文案（遵守 [[no-explanatory-ui-copy]]）：仅字段占位 + 法务同意 + 错误回报。

---

## 后端契约（内联，来源后端 plan）
- `POST /v1/auth/phone/request-code`　body `{"phone": "13812345678"}`　→
  `{"challenge_id": "uuid", "expires_in_seconds": 300, "resend_after_seconds": 60, "dev_code": "123456"|null}`
  （dev/test 环境回 `dev_code`，prod 为 null）。无效手机号 → 400 `INVALID_REQUEST_BODY`；同号频繁 → 429 `AUTH_CODE_RATE_LIMITED`。
- `POST /v1/auth/phone/verify`　body `{"challenge_id","phone","code"}`　→
  `{"token_type":"bearer","access_token","refresh_token","expires_in_seconds":900,
    "user":{"id","phone_masked":"138****5678","profile":{...}}}`
  验证码错 → 401 `AUTH_CODE_INVALID`；过期 → 401 `AUTH_CODE_EXPIRED`。
- `POST /v1/auth/refresh`　body `{"refresh_token"}` → 同 `AuthTokenResponse`（旋转，旧 token 失效 401 `AUTH_SESSION_REVOKED`）。
- `POST /v1/auth/logout`（带 Bearer）→ 204/200。
- `GET /v1/me`（带 Bearer）→ `{"id","phone_masked","profile":{...}}`。
- 错误统一走现有 `APIError` 信封（`error_code` / `user_message`）；UI 用 `user_message` 直接回报。

登录后所有受保护请求改带 `Authorization: Bearer <access_token>`（dev 仍保留 `X-User-Id` 兜底，见 Task 2）。

---

## Task 1 — Auth DTO（APIModels）
**File:** `Sources/API/APIModels.swift`（追加）；测试 `Tests/AuthModelsTests.swift`

- [ ] 先写失败测试 `Tests/AuthModelsTests.swift`：用上面契约的 JSON 字符串解码 `PhoneCodeResponse`（断言 `challengeId`/`expiresInSeconds`/`resendAfterSeconds`/`devCode`）、`AuthTokenResponse`（断言 `accessToken`/`refreshToken`/`user.phoneMasked`/`user.profile.timezone`）。`snake_case` 用 `CodingKeys` 映射（与现有 model 风格一致，如 `external_id`）。
- [ ] 加 `Codable` 结构：`PhoneCodeRequest{phone}`、`PhoneCodeResponse{challengeId, expiresInSeconds, resendAfterSeconds, devCode?}`、`PhoneVerifyRequest{challengeId, phone, code}`、`RefreshTokenRequest{refreshToken}`、`UserProfileRead{displayName?, timezone, preferredCompanion?, targetSummary?, weaknessSummary?, memoryUpdatedAt?}`、`CurrentUserRead{id, phoneMasked?, profile}`、`AuthTokenResponse{tokenType, accessToken, refreshToken, expiresInSeconds, user}`。
- [ ] `xcodebuild test` 该测试通过。
✅ Checkpoint — user commits（`Sources/API/APIModels.swift`, `Tests/AuthModelsTests.swift`；msg: `feat(ios-auth): add phone-login DTOs`）。

## Task 2 — TokenStore + APIClient Bearer/auth 方法
**Files:** 新 `Sources/API/TokenStore.swift`；改 `Sources/API/APIClient.swift`；测试 `Tests/TokenStoreTests.swift` + 追加 `Tests/APIClientTests.swift`

- [ ] 先写失败测试：
  - `TokenStoreTests`：`save(access,refresh,expiresAt)` 后 `accessToken/refreshToken` 可读、`clear()` 清空、`isLoggedIn` 反映状态（用注入的 `UserDefaults(suiteName:)` 隔离）。
  - `APIClientTests` 追加：`requestPhoneCode(phone:)` 命中 `POST /v1/auth/phone/request-code`、body 含 `phone`、**不**要求登录态；`verifyPhoneCode(...)` 命中 `/verify`、解出 `AuthTokenResponse`；登录后 `request(...)` 带 `Authorization: Bearer <token>`（用 TokenStore 注入一个 token，断言 header）；未登录时仍带 `X-User-Id`（dev 兜底）。
- [ ] `TokenStore`（protocol `TokenProviding{ var accessToken:String? }` + 实现）：dogfood 用 `UserDefaults` 持久化 `access/refresh/expiresAt`；留 `// TODO: 迁 Keychain` 注释。
- [ ] 改 `APIClient`：构造增 `tokenProvider: TokenProviding?`（默认 nil）；`request(...)` 里：若 `tokenProvider?.accessToken` 非空 → 设 `Authorization: Bearer …`（并可省略/保留 `X-User-Id`）；否则维持现有 `X-User-Id`（不破坏现有调用与测试）。加方法 `requestPhoneCode(phone:) -> PhoneCodeResponse`、`verifyPhoneCode(challengeId:phone:code:) -> AuthTokenResponse`、`refresh(refreshToken:) -> AuthTokenResponse`、`logout()`、`me() -> CurrentUserRead`（auth 端点不依赖登录态）。同步进 `APIClienting` 协议（带默认实现避免破坏其它 conformer）。
- [ ] 全测试通过（含**现有** `APIClientTests` 不回归：未注入 token 时仍发 `X-User-Id`）。
✅ Checkpoint — user commits（msg: `feat(ios-auth): TokenStore + bearer + phone auth endpoints`）。

## Task 3 — LoginViewModel（纯逻辑，TDD 核心）
**File:** 新 `Sources/Session/LoginViewModel.swift`；测试 `Tests/LoginViewModelTests.swift`

`@MainActor final class LoginViewModel: ObservableObject`，依赖注入 `APIClienting` 子集（或一个小 `AuthServicing` 协议）+ `TokenStore` + 可注入的「现在时间/计时」以便测倒计时。

- [ ] 先写失败测试：
  - `normalizePhone`：`"138 1234 5678"`/`"+8613812345678"` → `"13812345678"`；`isPhoneValid` 对 11 位 `1[3-9]xxxxxxxxx` 为真、`"12812345678"`/`"1381234567"` 为假。
  - `requestCode()` 成功：调用 client、保存 `challengeId`、`phase == .codeSent`、`resendCountdown == 60`、`canResend == false`。
  - 倒计时：`tick()`（或注入 clock 推进）到 0 → `canResend == true`、按钮文案逻辑回 `获取验证码`。
  - `verify()` 成功：把 `access/refresh` 写入 `TokenStore`、`phase == .loggedIn`、`onLoggedIn` 回调触发。
  - `verify()` 失败（client 抛 `APIError(error_code:"AUTH_CODE_INVALID")`）：`phase == .error`、`errorMessage == user_message`、不写 token。
  - `requestCode()` 限频（429 `AUTH_CODE_RATE_LIMITED`）：`errorMessage` 为后端 `user_message`，phase 退回可重试。
  - 按钮可用性：`isSubmitEnabled == isPhoneValid && code.count>=4 && phase != .verifying`。
- [ ] 实现：`enum Phase { idle, requestingCode, codeSent, verifying, loggedIn, error }`；`@Published phone/code/phase/errorMessage/resendCountdown`；`requestCode()`/`verify()`/`resend()`；倒计时用 `Timer`（生产）但**逻辑走可注入的 `tick()`/clock**以便单测（不要在测试里跑真 timer）。Graceful：任何 `APIError` → 显示 `userMessage`；`TransportError` → 通用「网络异常，请重试」。dev 便利：若 `PhoneCodeResponse.devCode` 非空，可选 `code = devCode`（仅 DEBUG，方便 dogfood，可加 `#if DEBUG`）。
- [ ] 全测试通过。
✅ Checkpoint — user commits（msg: `feat(ios-auth): LoginViewModel phone+code+countdown state machine`）。

## Task 4 — LoginView（SwiftUI，1:1 Figma）
**File:** 新 `Sources/Views/LoginView.swift`；测试 `Tests/LoginViewTests.swift`（可用 ViewModel 驱动的轻量断言/可达性 id）

- [ ] 按上面「视觉规格」实现 `LoginView`，`@StateObject var model: LoginViewModel`。复用 `.deepSpaceBackground()`/`.glassCard()`/`PrimaryCTAStyle`/`QinglanAvatarView`。
- [ ] 字段绑定 `model.phone`/`model.code`；`获取验证码` 按钮 `disabled(!model.isPhoneValid || !model.canResend)`，文案随 `model.resendCountdown` 切 `获取验证码`/`\(n)s 重发`；登录键 `disabled(!model.isSubmitEnabled)`；错误用 `model.errorMessage` 在卡下方以 `dangerText` 一行显示（无则不占位）。
- [ ] 给关键控件加 `.accessibilityIdentifier`：`login-phone-field`、`login-code-field`、`login-get-code`、`login-submit`、`login-agreement`，供测试/UITest 定位。
- [ ] `Tests/LoginViewTests.swift`：用 `LoginViewModel`（注入桩 client）断言交互后状态（如 `requestCode` 后 `phase==.codeSent`、`resendCountdown==60`；verify 成功后 `phase==.loggedIn`）——以 ViewModel 行为为主，避免脆弱快照。
- [ ]（可选）在 `Sources/DesignSystem/DesignGallery.swift` 注册 `login-l1`/`login-l2` 两屏（沿用现有 gallery 机制 + `RuntimeDeviceCanvas`），便于 `-DesignGalleryScreen login-l1` 模拟器 1:1 比对 Figma。
- [ ] `xcodebuild test` 全绿。
✅ Checkpoint — user commits（msg: `feat(ios-auth): deep-space LoginView 1:1`）。

## Task 5 — 登录态门控（root gating）
**Files:** 改 `Sources/InterviewerAppApp.swift`；新 `Sources/Session/AuthGate.swift`（小决策模型）；测试 `Tests/AuthGateTests.swift`

- [ ] 先写失败测试 `AuthGateTests`：`TokenStore` 有未过期 access token → `AuthGate.isLoggedIn == true`；无/过期 → false；`logout()` 后 false。
- [ ] `AuthGate: ObservableObject`（`@Published isLoggedIn`，读 `TokenStore`，提供 `login(AuthTokenResponse)`/`logout()`）。
- [ ] 改 `InterviewerAppApp.body`：保留 `DesignGalleryGate` 分支；否则 `if authGate.isLoggedIn { HomeView() } else { LoginView(model: …) }`。登录成功（`LoginViewModel.onLoggedIn`）→ `authGate.login(...)` → 切 `HomeView`。
- [ ] `APIClient` 构造改为读 `TokenStore`（`tokenProvider`），`baseURL = AppConfig.load().apiBaseURL`；保留 `devUserExternalId` 作未登录兜底（dev）。`SettingsView` 若有「退出登录」可调 `authGate.logout()`（可选）。
- [ ] 全测试绿。
✅ Checkpoint — user commits（msg: `feat(ios-auth): gate app root on login state`）。

## Task 6 — 真机/模拟器联调（需后端已部署 auth）
- [ ] 起后端（含 auth 路由 + migration）；模拟器 `xcodebuild` 跑起 App。dev 环境 `dev_code` 直接可见，验证：输入手机号→获取验证码（卡进入 L2 倒计时）→填码→登录→进入 HomeView；错误码（错码/过期/限频）显示后端 `user_message`。
- [ ] 视觉比对：`-DesignGalleryScreen login-l1`/`login-l2` 模拟器截图 vs Figma 731:198 / 737:211，确认 1:1。
- [ ] 打印「待提交文件 + 建议 message」，停。
✅ Checkpoint — user commits / 真机回归。

---

## 验收口径
- `xcodebuild test -scheme InterviewerApp` 全绿（新增 Auth/TokenStore/LoginViewModel/AuthGate 测试 + 现有测试零回归，尤其 `APIClientTests` 未登录仍发 `X-User-Id`）。
- 视觉 1:1（gallery 比对 731:198 / 737:211）。
- 仅手机号+验证码登录，**无第三方 OAuth**（后端 `auth_sms_provider=fake`，契约无 Apple/微信）。
- 全程 graceful：错误走 `APIError.userMessage`，绝不崩。
- **未自行 git 提交**（按 GIT 硬规则，每 Checkpoint 交回用户）。
