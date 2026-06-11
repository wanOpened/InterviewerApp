# iOS Dogfooding Client Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

## Deep Space Soundfield v2 Landing - 2026-06-11

Spec: `../Backend/docs/superpowers/specs/2026-06-10-qinglan-deep-space-soundfield-v2-design.md`
Plan: `../Backend/docs/superpowers/plans/2026-06-11-deep-space-v2-ios.md`

- [x] Phase 0: Added `DeepSpaceTheme`, glass cards, accent chips, primary CTA style, and `VoiceBarView`.
- [x] Phase 1: Added `HaloSpec` and Qinglan state halo rendering for idle, connecting, listening, thinking, and speaking.
- [x] Phase 2: Reworked home, schedule layer, schedule detail, preparation derivation, and edit sheet onto the deep-space glass shell.
- [x] Phase 3: Reworked interview room and done screen onto the deep-space shell while preserving `InterviewSession` and LiveKit behavior.
- [x] Phase 4: Added `ReportView` and `ReportViewModel`, wired done and ended-schedule report entry to real `SessionResultRead`.
- [x] Phase 5: Removed the main schedule push flow and remaining local `NavigationStack` use in the settings resume editor.
- [x] Phase 6: Audited `Backend/docs/api/openapi.json`; required endpoints and fields already exist, so Backend code was not changed.
- [x] Phase 7: Updated this implementation note and `docs/design/v2/README.md`.

New files:
- `Sources/DesignSystem/DeepSpaceTheme.swift`
- `Sources/Session/SchedulePreparation.swift`
- `Sources/Views/ReportView.swift`
- `Tests/DeepSpaceThemeTests.swift`
- `Tests/QinglanHaloSpecTests.swift`
- `Tests/SchedulePreparationTests.swift`
- `Tests/ReportViewModelTests.swift`

Verification notes:
- `xcodegen generate` succeeds.
- Full `xcodebuild` verification is tracked in the final execution summary for the v2 plan.

> **GIT CONSTRAINT (project rule):** The user owns ALL git operations — including `git init` for the new iOS repo, `git add`, and `git commit`. **Claude/subagents must NOT run any git command.** Wherever a normal plan would commit, this plan has a **`✅ Checkpoint — user commits`** marker: stop, tell the user what to commit, and wait. Do not proceed past a checkpoint by committing yourself.

**Goal:** Ship a thin native iOS app that runs the AI PM Interviewer's live voice interview on a real device over LAN IP, showing a live chat-style message box of both interviewer + candidate captions.

**Architecture:** SwiftUI app (separate sibling repo `../InterviewerApp`) with focused modules — `APIClient` (thin REST), `LiveKitController` (room/mic/audio/captions), `TranscriptStore` (caption merge), `InterviewSession` (orchestration view-model), and SwiftUI views. Pure-logic modules are unit-tested; the LiveKit/UI shell is verified by real-device dogfooding. A tiny backend change makes LiveKit advertise the Mac's LAN IP.

**Tech Stack:** Swift 5.9+, SwiftUI, LiveKit Swift SDK (`client-sdk-swift`, SPM), XcodeGen (project generation), XCTest. Backend: docker-compose (LiveKit config).

**Spec:** `docs/superpowers/specs/2026-05-25-ios-dogfooding-client-design.md`

**Path conventions:** Backend repo = current dir (`Backend/`). iOS repo = sibling `../InterviewerApp/` (created in Task 3). iOS paths below are relative to the iOS repo root.

---

## File structure (iOS repo `../InterviewerApp/`)

```
InterviewerApp/
├── project.yml                       # XcodeGen project definition
├── Sources/
│   ├── InterviewerAppApp.swift       # @main App entry
│   ├── Config/AppConfig.swift        # base URLs, dev user, seed-round selection
│   ├── API/APIError.swift            # decoded backend error envelope
│   ├── API/APIModels.swift           # Codable request/response DTOs
│   ├── API/APIClient.swift           # thin REST layer (5 calls)
│   ├── Transcript/TranscriptTurn.swift   # one conversation turn
│   ├── Transcript/TranscriptStore.swift  # merge transcription segments → turns
│   ├── LiveKit/LiveKitController.swift   # Room: connect/mic/audio/captions
│   ├── Session/InterviewSession.swift    # orchestration state machine (view-model)
│   └── Views/
│       ├── HomeView.swift
│       ├── SettingsView.swift
│       ├── InterviewView.swift       # composes the three subviews below
│       ├── MessageBoxView.swift
│       ├── StatusBarView.swift
│       ├── MicIndicatorView.swift
│       └── DoneView.swift
├── Resources/Info.plist              # NSMicrophoneUsageDescription, audio bg mode
└── Tests/
    ├── APIClientTests.swift
    ├── TranscriptStoreTests.swift
    └── InterviewSessionTests.swift
```

Responsibilities are isolated: `APIClient`/`TranscriptStore`/models are pure
Foundation (no SwiftUI/LiveKit imports) so they unit-test fast and the agent can
reason about them in isolation. `LiveKitController` is the only file importing
`LiveKit`. `InterviewSession` depends on protocols (`APIClienting`,
`LiveKitControlling`) so it can be tested with fakes.

---

## Task 0: Verify the toolchain

**Files:** none (environment check)

- [ ] **Step 1: Confirm Xcode + tools are present**

Run:
```bash
xcodebuild -version
xcrun simctl list devices available | grep -i iphone | head -3
which xcodegen || echo "MISSING xcodegen"
```
Expected: Xcode 15+, at least one available iPhone simulator, and `xcodegen` on PATH.

- [ ] **Step 2: Install XcodeGen if missing**

Run (only if previous step printed `MISSING xcodegen`):
```bash
brew install xcodegen
```
Expected: `xcodegen` installs and `xcodegen --version` prints a version.

- [ ] **Step 3: Note the Mac's LAN IP (needed in Task 1 and Task 10)**

Run:
```bash
ipconfig getifaddr en0 || ipconfig getifaddr en1
```
Expected: a `192.168.x.x` / `10.x.x.x` address. Record it; call it `<LAN_IP>` below.

(No commit — environment only.)

---

## Task 1: Backend — make LiveKit advertise a configurable node IP

**Files:**
- Modify: `docker-compose.yml` (the `livekit` service `LIVEKIT_CONFIG` block)
- Modify: `.env.example` (document the new var)

**Context:** The dev LiveKit config hardcodes `node_ip: 127.0.0.1` (works for the
Mac-local smoke). A physical iPhone cannot reach `127.0.0.1`. Make `node_ip`
substitutable so it can be set to `<LAN_IP>` for device testing, defaulting to
`127.0.0.1` so the existing smoke is unaffected. docker-compose substitutes
`${VAR:-default}` inside the compose file, including within the YAML block.

- [ ] **Step 1: Edit the `node_ip` line in `docker-compose.yml`**

In the `livekit` service's `LIVEKIT_CONFIG` block, change:
```yaml
        rtc:
          tcp_port: 7881
          udp_port: 7882
          use_external_ip: false
          node_ip: 127.0.0.1
```
to:
```yaml
        rtc:
          tcp_port: 7881
          udp_port: 7882
          use_external_ip: false
          node_ip: ${LIVEKIT_NODE_IP:-127.0.0.1}
```

- [ ] **Step 2: Document the var in `.env.example`**

Append under the LiveKit section of `.env.example`:
```bash
# Set to the Mac's LAN IP (e.g. 192.168.1.23) for real-device testing so
# LiveKit advertises a reachable ICE candidate. Leave unset (defaults to
# 127.0.0.1) for Mac-local smoke tests.
LIVEKIT_NODE_IP=
```

- [ ] **Step 3: Verify default still resolves to 127.0.0.1 (smoke unaffected)**

Run:
```bash
docker compose config | grep -A1 "node_ip" | head -4
```
Expected: the rendered config shows `node_ip: 127.0.0.1` (no env set → default).

- [ ] **Step 4: Verify LAN IP substitution works**

Run (replace with your `<LAN_IP>`):
```bash
LIVEKIT_NODE_IP=<LAN_IP> docker compose config | grep "node_ip"
```
Expected: shows `node_ip: <LAN_IP>`.

- [ ] **✅ Checkpoint — user commits** (`docker-compose.yml`, `.env.example`). Tell the user: "Backend node_ip is now env-configurable; please commit." Wait.

---

## Task 2: Backend — confirm the agent publishes transcriptions

**Files:** none (verification; the agent already enables transcription by default)

**Context:** Live captions rely on the agent publishing the `lk.transcription`
text stream for both its own speech (TTS) and the candidate's STT. `AgentSession`
enables this by default (it is only disabled by explicitly passing
`text_output=False` / `RoomOptions(audio_output=False)`).

- [ ] **Step 1: Confirm we do NOT disable text/transcription output**

Run:
```bash
grep -rn "text_output\|transcription\|audio_output\|RoomOptions\|RoomOutputOptions" apps/agent_worker/ || echo "no overrides — default (transcription ON)"
```
Expected: no line that sets `text_output=False` / disables transcription. (If such a line exists, remove it so transcription stays on.)

- [ ] **Step 2: Record the expectation for Task 10**

No code change. Note for the device dogfooding run (Task 10): the client must
receive `lk.transcription` text streams from BOTH the candidate identity (STT)
and the agent identity (TTS text). If captions for one side are missing, revisit
the agent's `AgentSession.start(...)` output options.

(No commit — verification only.)

---

## Task 3: Scaffold the iOS repo (XcodeGen + LiveKit SPM)

**Files (iOS repo `../InterviewerApp/`):**
- Create: `project.yml`, `Resources/Info.plist`, `Sources/InterviewerAppApp.swift`, `Sources/Config/AppConfig.swift`

- [ ] **Step 1: Create the repo directory and structure**

Run:
```bash
mkdir -p ../InterviewerApp/Sources/{Config,API,Transcript,LiveKit,Session,Views} ../InterviewerApp/Resources ../InterviewerApp/Tests
```

- [ ] **Step 2: Write `../InterviewerApp/project.yml`**

```yaml
name: InterviewerApp
options:
  bundleIdPrefix: com.dogfood.interviewer
  deploymentTarget:
    iOS: "16.0"
packages:
  LiveKit:
    url: https://github.com/livekit/client-sdk-swift
    from: "2.6.0"   # verify latest 2.x; bump if SPM resolution fails
targets:
  InterviewerApp:
    type: application
    platform: iOS
    sources:
      - Sources
    info:
      path: Resources/Info.plist
      properties:
        NSMicrophoneUsageDescription: "用于进行语音模拟面试"
        UIBackgroundModes: [audio]
        UILaunchScreen: {}
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.dogfood.interviewer.app
        GENERATE_INFOPLIST_FILE: NO
        TARGETED_DEVICE_FAMILY: "1"
    dependencies:
      - package: LiveKit
        product: LiveKit
  InterviewerAppTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - Tests
    dependencies:
      - target: InterviewerApp
schemes:
  InterviewerApp:
    build:
      targets:
        InterviewerApp: all
        InterviewerAppTests: [test]
    test:
      targets:
        - InterviewerAppTests
```

- [ ] **Step 3: Write `../InterviewerApp/Resources/Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NSMicrophoneUsageDescription</key>
    <string>用于进行语音模拟面试</string>
    <key>UIBackgroundModes</key>
    <array><string>audio</string></array>
</dict>
</plist>
```

- [ ] **Step 4: Write `../InterviewerApp/Sources/Config/AppConfig.swift`**

```swift
import Foundation

/// Dogfooding configuration. Defaults target a Mac dev host on the LAN.
/// Override at runtime via SettingsView; persisted in UserDefaults.
struct AppConfig: Codable, Equatable {
    /// Mac LAN IP host, e.g. "192.168.1.23". No scheme.
    var host: String
    var apiPort: Int
    var livekitPort: Int
    /// Seed user external id — MUST own a position/round (positions are user-scoped).
    var devUserExternalId: String
    /// Which round to use from the seed position's round list (0-based).
    var seedRoundIndex: Int

    static let `default` = AppConfig(
        host: "10.82.218.71",          // Mac's current LAN IP (DHCP — update if it changes)
        apiPort: 8000,
        livekitPort: 7880,
        devUserExternalId: "apple:mock-pm-candidate-01",
        seedRoundIndex: 0
    )

    var apiBaseURL: URL { URL(string: "http://\(host):\(apiPort)")! }
    var livekitURL: String { "ws://\(host):\(livekitPort)" }

    private static let key = "AppConfig.v1"
    static func load() -> AppConfig {
        guard let data = UserDefaults.standard.data(forKey: key),
              let cfg = try? JSONDecoder().decode(AppConfig.self, from: data)
        else { return .default }
        return cfg
    }
    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: AppConfig.key)
        }
    }
}
```

- [ ] **Step 5: Write `../InterviewerApp/Sources/InterviewerAppApp.swift`**

```swift
import SwiftUI

@main
struct InterviewerAppApp: App {
    var body: some Scene {
        WindowGroup {
            HomeView()
        }
    }
}
```

- [ ] **Step 6: Generate the Xcode project and confirm it builds**

Run:
```bash
cd ../InterviewerApp && xcodegen generate && \
xcodebuild -scheme InterviewerApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **` (HomeView doesn't exist yet → this step will fail to compile until Task 9; if so, temporarily replace `HomeView()` with `Text("placeholder")`, build, then restore in Task 9). Prefer: do Step 6's full build only after Task 9; for now just confirm `xcodegen generate` succeeds and the `.xcodeproj` appears.

- [ ] **✅ Checkpoint — user commits**: tell the user to `cd ../InterviewerApp && git init` and commit the scaffold. Wait.

---

## Task 4: API error + models (TDD)

**Files (iOS repo):**
- Create: `Sources/API/APIError.swift`, `Sources/API/APIModels.swift`
- Test: `Tests/APIClientTests.swift` (error decoding portion)

- [ ] **Step 1: Write the failing test for error-envelope decoding**

In `Tests/APIClientTests.swift`:
```swift
import XCTest
@testable import InterviewerApp

final class APIErrorTests: XCTestCase {
    func test_decodesBackendErrorEnvelope() throws {
        let json = """
        {"type":"x","title":"Rate Limited","status":429,
         "error_code":"RATE_LIMITED","error_code_family":"RATE_LIMIT",
         "user_message":"操作过于频繁，请稍后再试。","trace_id":"t-1",
         "retry_after":86400,"details":{}}
        """.data(using: .utf8)!
        let err = try JSONDecoder().decode(APIError.self, from: json)
        XCTAssertEqual(err.errorCode, "RATE_LIMITED")
        XCTAssertEqual(err.userMessage, "操作过于频繁，请稍后再试。")
        XCTAssertEqual(err.retryAfter, 86400)
        XCTAssertEqual(err.traceId, "t-1")
    }
}
```

- [ ] **Step 2: Run it; verify it fails to compile (APIError undefined)**

Run:
```bash
cd ../InterviewerApp && xcodegen generate && \
xcodebuild test -scheme InterviewerApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:InterviewerAppTests/APIErrorTests 2>&1 | tail -8
```
Expected: build failure, `cannot find 'APIError' in scope`.

- [ ] **Step 3: Write `Sources/API/APIError.swift`**

```swift
import Foundation

/// Decoded backend error envelope (see docs/api/CLIENT_INTEGRATION.md §2).
struct APIError: Error, Codable, Equatable {
    let status: Int
    let errorCode: String
    let userMessage: String
    let traceId: String?
    let retryAfter: Int?

    enum CodingKeys: String, CodingKey {
        case status
        case errorCode = "error_code"
        case userMessage = "user_message"
        case traceId = "trace_id"
        case retryAfter = "retry_after"
    }
}

/// Fallback for transport/non-envelope failures.
struct TransportError: Error, Equatable { let message: String }
```

- [ ] **Step 4: Write `Sources/API/APIModels.swift`**

```swift
import Foundation

struct DevUserRequest: Encodable { let external_id: String }
struct DevUserResponse: Decodable { let id: String; let external_id: String }

struct ResumeRead: Decodable { let id: String; let version: Int; let is_current: Bool }
struct ResumeCreateRequest: Encodable { let raw_text: String }

struct PositionRead: Decodable { let id: String; let title: String }
struct RoundRead: Decodable { let id: String; let round_name: String }

struct SessionCreateRequest: Encodable { let position_round_id: String }
struct SessionRead: Decodable {
    let id: String
    let status: String
    let livekit_room: String?
    let failure_reason: String?
    let total_cost_usd: String?   // Decimal serialized as string; display-only
}

struct JoinResponse: Decodable { let livekit_room: String; let livekit_token: String }
```

- [ ] **Step 5: Run the error test; verify it passes**

Run:
```bash
cd ../InterviewerApp && xcodebuild test -scheme InterviewerApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:InterviewerAppTests/APIErrorTests 2>&1 | tail -8
```
Expected: `Test Suite 'APIErrorTests' passed`.

- [ ] **✅ Checkpoint — user commits** (`APIError.swift`, `APIModels.swift`, `APIClientTests.swift`).

---

## Task 5: APIClient (TDD)

**Files (iOS repo):**
- Create: `Sources/API/APIClient.swift`
- Test: `Tests/APIClientTests.swift` (extend)

`APIClient` is constructed with a base URL, a dev user id (sent as `X-User-Id`),
and an injectable transport closure so it can be tested without real HTTP.

- [ ] **Step 1: Write the failing test for request building + envelope routing**

Append to `Tests/APIClientTests.swift`:
```swift
final class APIClientTests: XCTestCase {
    /// Captures the last request and returns a canned response.
    func makeClient(_ status: Int, _ body: Data) -> (APIClient, () -> URLRequest?) {
        var captured: URLRequest?
        let client = APIClient(
            baseURL: URL(string: "http://host:8000")!,
            userExternalId: "u-1"
        ) { request in
            captured = request
            let resp = HTTPURLResponse(url: request.url!, statusCode: status,
                                       httpVersion: nil, headerFields: nil)!
            return (body, resp)
        }
        return (client, { captured })
    }

    func test_createSession_setsHeadersAndBody() async throws {
        let body = #"{"id":"s-1","status":"created","livekit_room":null,"failure_reason":null,"total_cost_usd":null}"#.data(using: .utf8)!
        let (client, lastRequest) = makeClient(201, body)
        let session = try await client.createSession(positionRoundId: "pr-1")
        XCTAssertEqual(session.id, "s-1")
        let req = lastRequest()!
        XCTAssertEqual(req.value(forHTTPHeaderField: "X-User-Id"), "u-1")
        XCTAssertNotNil(req.value(forHTTPHeaderField: "Idempotency-Key"))
        XCTAssertEqual(req.url?.path, "/v1/sessions")
        XCTAssertEqual(req.httpMethod, "POST")
    }

    func test_non2xx_throwsDecodedAPIError() async throws {
        let body = #"{"status":429,"error_code":"RATE_LIMITED","user_message":"慢点","trace_id":"t","retry_after":10,"details":{}}"#.data(using: .utf8)!
        let (client, _) = makeClient(429, body)
        do {
            _ = try await client.createSession(positionRoundId: "pr-1")
            XCTFail("expected throw")
        } catch let e as APIError {
            XCTAssertEqual(e.errorCode, "RATE_LIMITED")
            XCTAssertEqual(e.retryAfter, 10)
        }
    }
}
```

- [ ] **Step 2: Run; verify it fails (APIClient undefined)**

Run:
```bash
cd ../InterviewerApp && xcodegen generate && xcodebuild test -scheme InterviewerApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:InterviewerAppTests/APIClientTests 2>&1 | tail -8
```
Expected: `cannot find 'APIClient' in scope`.

- [ ] **Step 3: Write `Sources/API/APIClient.swift`**

```swift
import Foundation

protocol APIClienting {
    func ensureUser() async throws
    func ensureResume() async throws
    func firstRoundId(seedRoundIndex: Int) async throws -> String
    func createSession(positionRoundId: String) async throws -> SessionRead
    func getSession(id: String) async throws -> SessionRead
    func join(sessionId: String) async throws -> JoinResponse
}

final class APIClient: APIClienting {
    typealias Transport = (URLRequest) async throws -> (Data, HTTPURLResponse)

    private let baseURL: URL
    private let userExternalId: String
    private let transport: Transport

    init(baseURL: URL, userExternalId: String, transport: Transport? = nil) {
        self.baseURL = baseURL
        self.userExternalId = userExternalId
        self.transport = transport ?? { request in
            let (data, resp) = try await URLSession.shared.data(for: request)
            return (data, resp as! HTTPURLResponse)
        }
    }

    // MARK: request plumbing

    private func request(_ method: String, _ path: String,
                         body: Encodable? = nil,
                         extraHeaders: [String: String] = [:]) -> URLRequest {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = method
        req.setValue(userExternalId, forHTTPHeaderField: "X-User-Id")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (k, v) in extraHeaders { req.setValue(v, forHTTPHeaderField: k) }
        if let body { req.httpBody = try? JSONEncoder().encode(AnyEncodable(body)) }
        return req
    }

    private func send<T: Decodable>(_ req: URLRequest, as type: T.Type) async throws -> T {
        let (data, resp) = try await transport(req)
        guard (200..<300).contains(resp.statusCode) else {
            if let apiErr = try? JSONDecoder().decode(APIError.self, from: data) { throw apiErr }
            throw TransportError(message: "HTTP \(resp.statusCode)")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func sendNoContent(_ req: URLRequest) async throws {
        let (data, resp) = try await transport(req)
        guard (200..<300).contains(resp.statusCode) else {
            if let apiErr = try? JSONDecoder().decode(APIError.self, from: data) { throw apiErr }
            throw TransportError(message: "HTTP \(resp.statusCode)")
        }
    }

    // MARK: API surface (see docs/api/CLIENT_INTEGRATION.md §4)

    func ensureUser() async throws {
        let req = request("POST", "/v1/dev/users", body: DevUserRequest(external_id: userExternalId))
        _ = try await send(req, as: DevUserResponse.self)
    }

    func ensureResume() async throws {
        // GET /v1/resumes/me; if 404, create one.
        let getReq = request("GET", "/v1/resumes/me")
        let (data, resp) = try await transport(getReq)
        if resp.statusCode == 200, (try? JSONDecoder().decode(ResumeRead.self, from: data)) != nil {
            return
        }
        let createReq = request("POST", "/v1/resumes",
            body: ResumeCreateRequest(raw_text: "5 年产品经理，专注 AI 与增长方向。"))
        _ = try await send(createReq, as: ResumeRead.self)
    }

    func firstRoundId(seedRoundIndex: Int) async throws -> String {
        let positions = try await send(request("GET", "/v1/positions"), as: [PositionRead].self)
        guard let pos = positions.first else { throw TransportError(message: "no positions for user") }
        let rounds = try await send(request("GET", "/v1/positions/\(pos.id)/rounds"), as: [RoundRead].self)
        guard rounds.indices.contains(seedRoundIndex) else {
            throw TransportError(message: "seed round index out of range")
        }
        return rounds[seedRoundIndex].id
    }

    func createSession(positionRoundId: String) async throws -> SessionRead {
        let req = request("POST", "/v1/sessions",
            body: SessionCreateRequest(position_round_id: positionRoundId),
            extraHeaders: ["Idempotency-Key": UUID().uuidString])
        return try await send(req, as: SessionRead.self)
    }

    func getSession(id: String) async throws -> SessionRead {
        try await send(request("GET", "/v1/sessions/\(id)"), as: SessionRead.self)
    }

    func join(sessionId: String) async throws -> JoinResponse {
        try await send(request("POST", "/v1/sessions/\(sessionId)/join"), as: JoinResponse.self)
    }
}

/// Type-erasing wrapper so `request(body:)` can take any Encodable.
private struct AnyEncodable: Encodable {
    private let encodeFn: (Encoder) throws -> Void
    init(_ wrapped: Encodable) { encodeFn = wrapped.encode }
    func encode(to encoder: Encoder) throws { try encodeFn(encoder) }
}
```

- [ ] **Step 4: Run; verify tests pass**

Run:
```bash
cd ../InterviewerApp && xcodebuild test -scheme InterviewerApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:InterviewerAppTests/APIClientTests 2>&1 | tail -8
```
Expected: `APIClientTests' passed` (both tests).

- [ ] **✅ Checkpoint — user commits** (`APIClient.swift`, updated `APIClientTests.swift`).

---

## Task 6: TranscriptTurn + TranscriptStore (TDD)

**Files (iOS repo):**
- Create: `Sources/Transcript/TranscriptTurn.swift`, `Sources/Transcript/TranscriptStore.swift`
- Test: `Tests/TranscriptStoreTests.swift`

**Behavior:** LiveKit delivers `lk.transcription` segments keyed by `segmentId`,
with `isFinal` and the sender identity. The store keeps one turn per `segmentId`,
updating its text as interim→final arrives, attributing the speaker by comparing
the sender identity to the local (candidate) identity. Turns preserve arrival
order.

- [ ] **Step 1: Write the failing tests**

`Tests/TranscriptStoreTests.swift`:
```swift
import XCTest
@testable import InterviewerApp

final class TranscriptStoreTests: XCTestCase {
    func test_interimThenFinal_updatesSameTurn() {
        let store = TranscriptStore(localIdentity: "cand-1")
        store.ingest(segmentId: "s1", senderIdentity: "cand-1", text: "你好", isFinal: false)
        store.ingest(segmentId: "s1", senderIdentity: "cand-1", text: "你好我是张三", isFinal: true)
        XCTAssertEqual(store.turns.count, 1)
        XCTAssertEqual(store.turns[0].text, "你好我是张三")
        XCTAssertEqual(store.turns[0].speaker, .candidate)
        XCTAssertTrue(store.turns[0].isFinal)
    }

    func test_attributesRemoteAsInterviewer_andPreservesOrder() {
        let store = TranscriptStore(localIdentity: "cand-1")
        store.ingest(segmentId: "a1", senderIdentity: "agent-x", text: "请介绍一下你自己", isFinal: true)
        store.ingest(segmentId: "s2", senderIdentity: "cand-1", text: "好的", isFinal: true)
        XCTAssertEqual(store.turns.map(\.speaker), [.interviewer, .candidate])
        XCTAssertEqual(store.turns.map(\.text), ["请介绍一下你自己", "好的"])
    }
}
```

- [ ] **Step 2: Run; verify it fails (types undefined)**

Run:
```bash
cd ../InterviewerApp && xcodegen generate && xcodebuild test -scheme InterviewerApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:InterviewerAppTests/TranscriptStoreTests 2>&1 | tail -8
```
Expected: `cannot find 'TranscriptStore' in scope`.

- [ ] **Step 3: Write `Sources/Transcript/TranscriptTurn.swift`**

```swift
import Foundation

enum Speaker: Equatable { case candidate, interviewer }

struct TranscriptTurn: Identifiable, Equatable {
    let id: String          // segmentId
    let speaker: Speaker
    var text: String
    var isFinal: Bool
}
```

- [ ] **Step 4: Write `Sources/Transcript/TranscriptStore.swift`**

```swift
import Foundation

/// Merges LiveKit transcription segments into ordered conversation turns.
/// Not thread-safe by itself; the owner marshals calls onto the main actor.
final class TranscriptStore {
    private(set) var turns: [TranscriptTurn] = []
    private var indexBySegment: [String: Int] = [:]
    private let localIdentity: String

    init(localIdentity: String) { self.localIdentity = localIdentity }

    func ingest(segmentId: String, senderIdentity: String, text: String, isFinal: Bool) {
        let speaker: Speaker = (senderIdentity == localIdentity) ? .candidate : .interviewer
        if let idx = indexBySegment[segmentId] {
            turns[idx].text = text
            turns[idx].isFinal = isFinal
        } else {
            indexBySegment[segmentId] = turns.count
            turns.append(TranscriptTurn(id: segmentId, speaker: speaker, text: text, isFinal: isFinal))
        }
    }

    func reset() { turns.removeAll(); indexBySegment.removeAll() }
}
```

- [ ] **Step 5: Run; verify tests pass**

Run:
```bash
cd ../InterviewerApp && xcodebuild test -scheme InterviewerApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:InterviewerAppTests/TranscriptStoreTests 2>&1 | tail -8
```
Expected: `TranscriptStoreTests' passed`.

- [ ] **✅ Checkpoint — user commits** (`TranscriptTurn.swift`, `TranscriptStore.swift`, `TranscriptStoreTests.swift`).

---

## Task 7: LiveKitController (manual-verified)

**Files (iOS repo):**
- Create: `Sources/LiveKit/LiveKitController.swift`

**Note:** This wraps the LiveKit SDK; it's verified by device dogfooding (Task 10),
not unit tests. It conforms to `LiveKitControlling` so `InterviewSession` can be
tested with a fake.

- [ ] **Step 1: Write `Sources/LiveKit/LiveKitController.swift`**

```swift
import Foundation
import LiveKit

protocol LiveKitControlling: AnyObject {
    /// Connect, publish mic (MICROPHONE source), and start receiving captions.
    /// `onSegment` is called for each transcription segment.
    func connect(url: String, token: String,
                 onSegment: @escaping (_ segmentId: String, _ sender: String,
                                       _ text: String, _ isFinal: Bool) -> Void,
                 onState: @escaping (_ connected: Bool) -> Void) async throws
    func disconnect() async
    var localIdentity: String { get }
}

final class LiveKitController: LiveKitControlling {
    private let room = Room()
    private(set) var localIdentity: String = ""

    func connect(url: String, token: String,
                 onSegment: @escaping (String, String, String, Bool) -> Void,
                 onState: @escaping (Bool) -> Void) async throws {
        try await room.connect(url, token)
        localIdentity = room.localParticipant.identity?.stringValue ?? ""
        onState(true)

        // Live captions: agent TTS text + candidate STT both arrive on this topic.
        try await room.registerTextStreamHandler(for: "lk.transcription") { reader, participantIdentity in
            let text = try await reader.readAll()
            let isFinal = reader.info.attributes["lk.transcription_final"] == "true"
            let segmentId = reader.info.attributes["lk.segment_id"] ?? UUID().uuidString
            onSegment(segmentId, participantIdentity.stringValue, text, isFinal)
        }

        // Publish the microphone. setMicrophone publishes with .microphone source,
        // which the agent's RoomIO requires (the source=UNKNOWN gotcha).
        try await room.localParticipant.setMicrophone(enabled: true)
        // Remote (agent) audio plays automatically via LiveKit's AudioManager.
    }

    func disconnect() async {
        await room.disconnect()
    }
}
```

> Implementer note: the LiveKit Swift API surface can shift across 2.x releases.
> If `registerTextStreamHandler(for:)`, `reader.info.attributes`,
> `participantIdentity.stringValue`, or `setMicrophone(enabled:)` don't compile,
> check the installed SDK's symbols (Xcode quick-help / the `LiveKit` module) and
> adjust the call sites — the *shape* (connect → register transcription handler →
> enable mic) stays the same.

- [ ] **Step 2: Confirm it compiles (against the real SDK)**

Run:
```bash
cd ../InterviewerApp && xcodegen generate && xcodebuild -scheme InterviewerApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -6
```
Expected: `** BUILD SUCCEEDED **` (the app entry may still reference `HomeView` — if so, this fully builds after Task 9; at minimum confirm no errors inside `LiveKitController.swift`).

- [ ] **✅ Checkpoint — user commits** (`LiveKitController.swift`).

---

## Task 8: InterviewSession orchestration (TDD for the join state machine)

**Files (iOS repo):**
- Create: `Sources/Session/InterviewSession.swift`
- Test: `Tests/InterviewSessionTests.swift`

**Behavior:** an `@MainActor @Observable` view-model. `start()` runs the join
pipeline (ensureUser → ensureResume → firstRoundId → createSession → poll READY →
join → LiveKit connect), publishing `phase`. The polling loop and phase
transitions are tested with a fake `APIClienting` + fake `LiveKitControlling`.

- [ ] **Step 1: Write the failing test**

`Tests/InterviewSessionTests.swift`:
```swift
import XCTest
@testable import InterviewerApp

@MainActor
final class InterviewSessionTests: XCTestCase {
    final class FakeAPI: APIClienting {
        var statuses: [String]; var joined = false
        init(statuses: [String]) { self.statuses = statuses }
        func ensureUser() async throws {}
        func ensureResume() async throws {}
        func firstRoundId(seedRoundIndex: Int) async throws -> String { "pr-1" }
        func createSession(positionRoundId: String) async throws -> SessionRead {
            SessionRead(id: "s-1", status: "created", livekit_room: nil, failure_reason: nil, total_cost_usd: nil)
        }
        func getSession(id: String) async throws -> SessionRead {
            let s = statuses.isEmpty ? "ready" : statuses.removeFirst()
            return SessionRead(id: "s-1", status: s, livekit_room: nil, failure_reason: nil, total_cost_usd: nil)
        }
        func join(sessionId: String) async throws -> JoinResponse {
            joined = true
            return JoinResponse(livekit_room: "r", livekit_token: "tok")
        }
    }
    final class FakeLK: LiveKitControlling {
        var connected = false
        var localIdentity = "cand-1"
        func connect(url: String, token: String,
                     onSegment: @escaping (String, String, String, Bool) -> Void,
                     onState: @escaping (Bool) -> Void) async throws {
            connected = true; onState(true)
        }
        func disconnect() async { connected = false }
    }

    func test_start_reachesLiveAfterReady() async throws {
        let api = FakeAPI(statuses: ["created", "ready"])
        let lk = FakeLK()
        let session = InterviewSession(config: .default, api: api, liveKit: lk, pollInterval: 0)
        await session.start()
        XCTAssertTrue(api.joined)
        XCTAssertTrue(lk.connected)
        XCTAssertEqual(session.phase, .live)
    }
}
```

- [ ] **Step 2: Run; verify it fails (InterviewSession undefined)**

Run:
```bash
cd ../InterviewerApp && xcodegen generate && xcodebuild test -scheme InterviewerApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:InterviewerAppTests/InterviewSessionTests 2>&1 | tail -8
```
Expected: `cannot find 'InterviewSession' in scope`.

- [ ] **Step 3: Write `Sources/Session/InterviewSession.swift`**

```swift
import Foundation
import Observation

@MainActor
@Observable
final class InterviewSession {
    enum Phase: Equatable { case idle, preparing, live, finishing, done, failed(String) }

    private(set) var phase: Phase = .idle
    private(set) var turns: [TranscriptTurn] = []
    private(set) var connected = false
    private(set) var sessionId: String?
    private(set) var liveStartedAt: Date?   // set when the interview goes live; drives the elapsed timer

    private let config: AppConfig
    private let api: APIClienting
    private let liveKit: LiveKitControlling
    private let pollInterval: TimeInterval
    private var store: TranscriptStore?

    init(config: AppConfig, api: APIClienting, liveKit: LiveKitControlling,
         pollInterval: TimeInterval = 2.0) {
        self.config = config
        self.api = api
        self.liveKit = liveKit
        self.pollInterval = pollInterval
    }

    func start() async {
        do {
            phase = .preparing
            try await api.ensureUser()
            try await api.ensureResume()
            let roundId = try await api.firstRoundId(seedRoundIndex: config.seedRoundIndex)
            let created = try await api.createSession(positionRoundId: roundId)
            sessionId = created.id
            try await waitForReady(created.id)
            let join = try await api.join(sessionId: created.id)

            liveStartedAt = Date()
            let store = TranscriptStore(localIdentity: liveKit.localIdentity)
            self.store = store
            try await liveKit.connect(
                url: config.livekitURL, token: join.livekit_token,
                onSegment: { [weak self] seg, sender, text, isFinal in
                    Task { @MainActor in
                        self?.store?.ingest(segmentId: seg, senderIdentity: sender,
                                            text: text, isFinal: isFinal)
                        self?.turns = self?.store?.turns ?? []
                    }
                },
                onState: { [weak self] up in Task { @MainActor in self?.connected = up } }
            )
            phase = .live
        } catch let e as APIError {
            phase = .failed("\(e.errorCode): \(e.userMessage)")
        } catch {
            phase = .failed("\(error)")
        }
    }

    private func waitForReady(_ id: String, maxAttempts: Int = 30) async throws {
        for _ in 0..<maxAttempts {
            let s = try await api.getSession(id: id)
            if s.status == "ready" { return }
            if ["failed", "failed_partial", "expired", "cancelled"].contains(s.status) {
                throw TransportError(message: "session \(s.status): \(s.failure_reason ?? "")")
            }
            if pollInterval > 0 { try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000)) }
        }
        throw TransportError(message: "session not ready in time")
    }

    func end() async {
        phase = .finishing
        await liveKit.disconnect()
        phase = .done
    }
}
```

- [ ] **Step 4: Run; verify test passes**

Run:
```bash
cd ../InterviewerApp && xcodebuild test -scheme InterviewerApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:InterviewerAppTests/InterviewSessionTests 2>&1 | tail -8
```
Expected: `InterviewSessionTests' passed`.

- [ ] **✅ Checkpoint — user commits** (`InterviewSession.swift`, `InterviewSessionTests.swift`).

---

## Task 9: SwiftUI views (manual-verified)

**Files (iOS repo):**
- Create: `Sources/Views/HomeView.swift`, `SettingsView.swift`, `InterviewView.swift`, `MessageBoxView.swift`, `StatusBarView.swift`, `MicIndicatorView.swift`, `DoneView.swift`

- [ ] **Step 1: Write `Sources/Views/HomeView.swift`**

```swift
import SwiftUI

struct HomeView: View {
    @State private var config = AppConfig.load()
    @State private var session: InterviewSession?
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                Text("AI 模拟面试").font(.largeTitle).bold()
                Text("点击开始一场语音面试").foregroundStyle(.secondary)
                Button("开始面试") {
                    let s = InterviewSession(
                        config: config,
                        api: APIClient(baseURL: config.apiBaseURL, userExternalId: config.devUserExternalId),
                        liveKit: LiveKitController())
                    session = s
                    Task { await s.start() }
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                Spacer()
            }
            .padding()
            .toolbar { ToolbarItem(placement: .topBarTrailing) {
                Button { showSettings = true } label: { Image(systemName: "gear") }
            } }
            .sheet(isPresented: $showSettings) { SettingsView(config: $config) }
            .navigationDestination(item: $session) { s in InterviewView(session: s) }
        }
    }
}

extension InterviewSession: Identifiable { var id: ObjectIdentifier { ObjectIdentifier(self) } }
```

- [ ] **Step 2: Write `Sources/Views/SettingsView.swift`**

```swift
import SwiftUI

struct SettingsView: View {
    @Binding var config: AppConfig
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Mac 主机") {
                    TextField("LAN IP", text: $config.host).keyboardType(.numbersAndPunctuation)
                    Stepper("API 端口: \(config.apiPort)", value: $config.apiPort, in: 1...65535)
                    Stepper("LiveKit 端口: \(config.livekitPort)", value: $config.livekitPort, in: 1...65535)
                }
                Section("面试") {
                    TextField("Dev 用户 external_id", text: $config.devUserExternalId)
                    Stepper("Seed 轮次索引: \(config.seedRoundIndex)", value: $config.seedRoundIndex, in: 0...10)
                }
            }
            .navigationTitle("设置")
            .toolbar { ToolbarItem(placement: .confirmationAction) {
                Button("完成") { config.save(); dismiss() }
            } }
        }
    }
}
```

- [ ] **Step 3: Write `Sources/Views/StatusBarView.swift`, `MicIndicatorView.swift`, `MessageBoxView.swift`**

```swift
import SwiftUI

struct StatusBarView: View {
    let phaseText: String
    let connected: Bool
    let liveStartedAt: Date?     // nil until live; drives the elapsed timer
    var body: some View {
        HStack {
            Circle().fill(connected ? .green : .orange).frame(width: 10, height: 10)
            Text(phaseText).font(.footnote).foregroundStyle(.secondary)
            Spacer()
            if let start = liveStartedAt {
                TimelineView(.periodic(from: start, by: 1)) { ctx in
                    let secs = Int(ctx.date.timeIntervalSince(start))
                    Text(String(format: "%02d:%02d", secs / 60, secs % 60))
                        .font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }.padding(.horizontal)
    }
}

// NOTE (deferred polish): a fine-grained agent "listening / speaking / thinking"
// indicator is NOT in v1 — it needs LiveKit audio-activity wiring. The phase
// text + the live caption updates already signal who's talking. Add it in a
// later pass if dogfooding shows it's needed.

struct MicIndicatorView: View {
    let active: Bool
    var body: some View {
        Label(active ? "麦克风开启" : "麦克风关闭",
              systemImage: active ? "mic.fill" : "mic.slash")
            .font(.footnote).foregroundStyle(active ? .green : .secondary)
    }
}

struct MessageBoxView: View {
    let turns: [TranscriptTurn]
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(turns) { turn in
                        HStack {
                            if turn.speaker == .candidate { Spacer(minLength: 40) }
                            VStack(alignment: turn.speaker == .candidate ? .trailing : .leading) {
                                Text(turn.speaker == .candidate ? "我" : "面试官")
                                    .font(.caption2).foregroundStyle(.secondary)
                                Text(turn.text)
                                    .padding(10)
                                    .background(turn.speaker == .candidate ? Color.blue.opacity(0.15)
                                                                           : Color.gray.opacity(0.15))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .opacity(turn.isFinal ? 1 : 0.6)
                            }
                            if turn.speaker == .interviewer { Spacer(minLength: 40) }
                        }.id(turn.id)
                    }
                }.padding()
            }
            .onChange(of: turns.count) { _, _ in
                if let last = turns.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
        }
    }
}
```

- [ ] **Step 4: Write `Sources/Views/InterviewView.swift`**

```swift
import SwiftUI

struct InterviewView: View {
    @Bindable var session: InterviewSession
    @Environment(\.dismiss) private var dismiss

    private var phaseText: String {
        switch session.phase {
        case .idle: return "空闲"
        case .preparing: return "准备题目中…"
        case .live: return "面试进行中"
        case .finishing: return "结束中…"
        case .done: return "已结束"
        case .failed(let m): return "出错：\(m)"
        }
    }

    var body: some View {
        Group {
            if session.phase == .done {
                VStack {
                    DoneView(sessionId: session.sessionId)
                    Button("返回首页") { dismiss() }
                        .buttonStyle(.bordered).padding()
                }
            } else {
                VStack(spacing: 8) {
                    StatusBarView(phaseText: phaseText, connected: session.connected,
                                  liveStartedAt: session.liveStartedAt)
                    MessageBoxView(turns: session.turns)
                    MicIndicatorView(active: session.connected)
                    Button(role: .destructive) {
                        Task { await session.end() }   // → phase becomes .done, shows DoneView
                    } label: { Text("结束面试").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).controlSize(.large).padding(.horizontal)
                }
            }
        }
        .navigationTitle("面试").navigationBarTitleDisplayMode(.inline)
    }
}
```

- [ ] **Step 5: Write `Sources/Views/DoneView.swift`** (shown after end; minimal)

```swift
import SwiftUI

struct DoneView: View {
    let sessionId: String?
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill").font(.largeTitle).foregroundStyle(.green)
            Text("面试结束").font(.title2).bold()
            if let id = sessionId { Text("session: \(id)").font(.caption).foregroundStyle(.secondary) }
            Text("评分报告稍后接入").font(.footnote).foregroundStyle(.secondary)
        }.padding()
    }
}
```

- [ ] **Step 6: Full build for the simulator**

Run:
```bash
cd ../InterviewerApp && xcodegen generate && xcodebuild -scheme InterviewerApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -6
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Run the full unit-test suite**

Run:
```bash
cd ../InterviewerApp && xcodebuild test -scheme InterviewerApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -10
```
Expected: all suites (`APIErrorTests`, `APIClientTests`, `TranscriptStoreTests`, `InterviewSessionTests`) pass.

- [ ] **✅ Checkpoint — user commits** (all `Views/*.swift`).

---

## Task 10: Real-device dogfooding run (the validation)

**Files:** none (operational validation). This is where the spec's real goal —
evaluating the live interview on a real device — gets exercised.

- [ ] **Step 1: Bring up the backend bound to the LAN IP**

In the Backend repo (record `<LAN_IP>` from Task 0):
```bash
cd <BACKEND_DIR>
LIVEKIT_NODE_IP=<LAN_IP> docker compose up -d --force-recreate livekit
docker compose logs livekit --tail=5 | grep nodeIP   # expect nodeIP: <LAN_IP>
```
Also ensure API + the 3 workers (pregen/scoring/agent) are running (see the voice
smoke instructions), and the agent worker registered.

- [ ] **Step 2: Allow the dev ports through the Mac firewall**

System Settings → Network → Firewall → allow incoming for the docker/uvicorn
processes, or temporarily disable the firewall for the test. Ports: 8000 (API),
7880/7881 (TCP), 7882/udp (LiveKit media). iPhone + Mac on the **same WiFi**.

- [ ] **Step 3: Set the app's host to `<LAN_IP>` and deploy to the device**

Edit `AppConfig.default.host` (or set it via the in-app Settings screen) to
`<LAN_IP>`. Then in Xcode: open `InterviewerApp.xcodeproj`, select your iPhone,
set a Team for signing (Signing & Capabilities), and Run (⌘R). On the device,
trust the developer profile if prompted (Settings → General → VPN & Device Mgmt).

- [ ] **Step 4: Run a full interview and verify**

Tap "开始面试". Verify, in order:
1. Phase goes 准备题目中 → 面试进行中 (session reached READY, joined, connected).
2. You hear the agent's opening line (agent audio plays).
3. Speak an answer; within ~1–2s of pausing, the agent asks a follow-up/next
   question (turn loop fires).
4. The message box shows BOTH sides' text: 面试官 lines and 我 (candidate) lines,
   interim text updating then finalizing.
5. Tap 结束面试 → returns home cleanly.

- [ ] **Step 5: Cross-check the backend recorded the session**

In the Backend repo:
```bash
docker compose exec -T postgres psql -U interviewer -d interviewer -tAc \
 "SELECT id, status FROM sessions ORDER BY created_at DESC LIMIT 1;"
```
Expected: a recent session that progressed to `in_progress`/`ended`/`scored`.

- [ ] **Step 6: Record dogfooding observations**

Note latency (end-of-speech → agent reply), audio quality, caption accuracy and
sync, any turn-taking awkwardness. These observations drive the next round of
"interview process performance" polish (the actual purpose of this app).

- [ ] **✅ Checkpoint — user commits** any config tweaks (e.g., `AppConfig` default host). Done.

---

## Notes for the implementer

- **Captions depend on the agent publishing `lk.transcription`** (Task 2). If the
  message box stays empty while audio works, that's the first thing to check.
- **Rate limit:** session creation is capped 10/user/24h. If 开始面试 fails with a
  429, clear it: `docker compose exec redis redis-cli DEL rl:sessions-create:<devUserExternalId>`.
- **The mic gotcha is already handled** by `setMicrophone(enabled: true)` (it sets
  the `.microphone` source). Do NOT hand-build a generic audio track.
- **LiveKit Swift SDK version drift:** if SPM resolution or symbols fail, bump the
  `from:` version in `project.yml` and adjust `LiveKitController` call sites; keep
  the connect → register-transcription → enable-mic shape.

---

## 2026-06-11 增补执行记录：首页日程入口与主行动卡

- 日程入口：`HomeSchedulePeekModel` 新增 `entryState`，无未来日程或刷新失败时返回 `.empty`，旧 `isVisible`/`label`/`secondaryLabel` 保留为派生属性；首页把手改为常驻渲染，包含 grabber、`chevron.up` 视觉引导、next/empty 两态和 `近期 N 场` 数据标。
- 主行动卡：新增 `HomePrimaryActionPresentation.make(action:nextScheduleID:)`，`nil` 和与下一场日程重复的“去准备”动作不渲染，其它主行动在日程把手上方以深空玻璃卡呈现，点击仍走原 `tapPrimaryAction` 路由。
- 验证记录：`HomeSchedulePeekModelTests`、`HomePrimaryActionRouterTests` 的红绿流程完成；`swiftc -parse` 覆盖本次修改的生产 Swift 文件通过。全量 `xcodegen generate && xcodebuild ... build test` 在当前沙盒被 CoreSimulatorService 与 SwiftPM/Xcode sandbox 限制阻断，需宿主环境代跑。
