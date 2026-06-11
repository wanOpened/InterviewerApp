# iOS Voice-Concierge Home — Implementation Plan (Codex)

> **Executor:** Codex CLI (GPT-5.5, xhigh). Implement the **latest** 青岚 home UI:
> a pure-voice, interruptible concierge. Where current iOS code conflicts with
> this plan, **replace it with the new model** — do not keep the old decision-led
> card home or the slot-filling/confirm-button voice panel.

> **GIT CONSTRAINT (hard, project rule — see `IMPLEMENTATION_PLAN.md`):** The user
> owns ALL git operations in this iOS repo. **You (Codex) must NOT run any git
> command** — no `git add`, no `git commit`, no `git init`. Wherever this plan says
> **✅ Checkpoint — user commits**, STOP, print exactly what to commit, and
> continue implementing the next task (do not commit yourself).

## Authoritative design sources (read first)

These live in the **sibling backend repo** `../Backend/` — you have full-disk
read access, read them:

- Spec (product + tech, source of truth for the design): `../Backend/docs/superpowers/specs/2026-06-08-qinglan-voice-concierge-design.md` — read §2.1 (state machine), §2.2 (timing), §2.3 (proactive opening), §2.4 (bottom CTA), §9 (iOS contract), §10 (iOS side).
- Backend contract is **already implemented and live** (do not change the backend). The exact shapes you must match are quoted in this plan (§Contract below). You cannot open Figma; this plan + the spec carry all the concrete visual values.

## Product definition (what we are building)

The home **is** 青岚's animation. White background. No tabs, no card feed, no
popup confirm buttons, no instructional copy.

- **Top ~80%:** the 青岚 avatar in one of five live states, driven by the
  real-time LiveKit session:
  | state | meaning | trigger |
  | --- | --- | --- |
  | `idle` | breathing loop ("alive"); the whole avatar is the tap target | default / after a session ends |
  | `connecting` | tapped, joining room + starting session | tap |
  | `speaking` | 青岚 is talking (incl. the proactive opener) | session ready / tool result / re-ask |
  | `listening` | the user is talking (may interrupt `speaking` at any time) | VAD detects user speech |
  | `thinking` | tool / LLM in progress | tool call running |
  - Tap 青岚 to start; tap again (or silence timeout) → disconnect → `idle`.
  - **Barge-in is a hard requirement:** while `speaking`, if the user starts
    talking → immediately switch to `listening` and 青岚 stops. Server-driven
    (LiveKit `AgentSession`), not a manual turn model.
- **Bottom ~20%:** a single, persistent **contextual CTA card** (the one most
  important next step). Subordinate to 青岚 — light card on white
  (`bg/elevated` + `border/subtle`), not glowing, no copy beyond title/reason/cta.
  A small source-tag dot uses the existing palette: 面试→blue / 练习→neutral /
  复盘→green. It renders **only** `current_context.primary_action` (one thing at a
  time). Everything else is handled by talking to 青岚.

## Contract (already live in `../Backend/`; match exactly)

`POST /v1/home-voice/join` → `HomeVoiceJoinResponse`:
```jsonc
{
  "session_id": "<uuid>",
  "livekit_room": "<string>",
  "livekit_token": "<jwt>",
  "current_context": { /* AgentHomeRead */ }
}
```
There are **no** `server_events` / `client_events` anymore, and **no**
`HomeVoicePendingActionRead`. The client-confirm protocol is gone.

`AgentHomeRead.primary_action` = `AgentHomePrimaryAction`:
```jsonc
{ "type": "<AgentHomeActionType>", "title": "...", "spoken_prompt": "...",
  "reason": "...", "cta": "...", "target": { "<key>": "<uuid>" } }
```
`AgentHomeActionType` ∈ `create_target | add_jd | create_schedule |
start_practice | resume_live_session | review_result | practice_weakness |
wait_scoring | quick_start`.

**Handoff signal (home → interview):** the concierge agent publishes a LiveKit
**data packet**, `topic = "navigate.interview"`, payload `{"session_id":"<uuid>"}`.
The client MUST register a data handler for that topic; on receipt → push
`InterviewView` and join/resume the interview room by `session_id`, then tear down
the home voice session. (Backend source: `../Backend/apps/agent_worker/concierge_agent.py` `_handoff_to_interview`.)

### Bottom-CTA tap routing (= same action as the equivalent voice tool)

- **Interview-class** (`resume_live_session` / `start_practice` /
  `practice_weakness` / `quick_start`): start or resume an interview session and
  enter the interview room — the SAME path the `navigate.interview` signal drives.
  Use `target["session_id"]` (resume) or `target["schedule_id"]` /
  `target["position_round_id"]` (start) as available.
- **Conversation-class** (`create_schedule` / `create_target` / `add_jd` /
  `review_result` / `wait_scoring`): tapping just **starts the voice session** and
  lets 青岚 handle it by voice (the proactive opener already references this
  context). **Never deep-link a legacy screen.**

## Avatar reconciliation (match the latest Figma 青岚 · 稳重)

The current `Sources/Views/QinglanAvatarView.swift` is the OLD mascot. Update the
`qinglan` variant (do not touch mobai/chengcheng/xingyu) to the latest design:

- **Limbs are body-colored.** Remove the orange feet:
  `qinglanFoot = Color(red: 0.84, green: 0.49, blue: 0.15)` is rejected — feet AND
  legs/arms must be the **same body blue** as the body (`0x7CC4DE`). Keep arms on
  the body's two sides + short legs + small feet, proportionate (the user
  explicitly rejected orange and the deeper-blue; settle on flat body-colored
  limbs).
- **No blush on 青岚.** `showsBlush` must be false for `.qinglan` (keep the tamed
  highlight; drop the pink cheeks).
- **Soft single-hue breathing glow, not concentric rings.** The home/stage glow
  should read as one soft halo that breathes (opacity progression by state:
  connecting < thinking < idle < listening < speaking), not the 2–3 hard
  `haloRings`. Keep it `accent/glow` single hue (body blue), low opacity, white bg.
- Keep the five-state animation behavior (breathing, mouth loop on speaking,
  listening pulse, thinking dots) — only the *look* (limbs/blush/glow) changes.

## File change map (KEEP / REWORK / REMOVE)

**Before deleting anything: grep for usages, delete/trim the old tests first, then
the implementation, then make the build green.** (Same discipline as the backend.)

- **REWORK `Sources/Views/HomeView.swift`** → the new voiceConcierge layout: white
  bg, big 青岚 five-state avatar (top ~80%, tap to start/stop), single bottom CTA
  card (~20%) bound to `current_context.primary_action`, `navigate.interview` data
  handler → push `InterviewView`. Delete the decision-led card home
  (`AgentHomeFigmaScreen`, `EmphasizedBriefingCard`, `CondensedBriefingCard` /
  "顺手处理" feed, `AgentDecisionCard`, `AgentBottomCommandDock`, `AgentDockTile`,
  `AgentSignalStrip`) and the inline slot-filling panel.
- **REWORK `Sources/Voice/HomeVoicePanelModel.swift`** → pure-voice barge-in
  driver. It currently speaks a **deleted** wire protocol (`confirm_action` /
  `cancel_action` / `stop_session` / `pendingAction` / `HomeVoiceClientWireEvent`) —
  remove all of that. Keep: join via API → LiveKit connect → drive the avatar
  state (`connecting`/`speaking`/`listening`/`thinking`/`idle`) from real session
  events (agent speaking, local VAD/mic activity, tool-in-progress, transcription),
  handle the `navigate.interview` data signal → callback, teardown on tap /
  scenePhase change / silence timeout.
- **REWORK `Sources/Views/QinglanAvatarView.swift`** → avatar reconciliation above.
- **REWORK `Sources/LiveKit/LiveKitController.swift`** → expose: (a) a data-packet
  handler registration for `topic == "navigate.interview"`, and (b)
  speaking/listening state callbacks (agent audio active vs local participant
  speaking) so the model can drive the five states. Validate the LiveKit Swift SDK
  symbols against the installed package (see IMPLEMENTATION_PLAN.md note on SDK
  drift); keep the shape connect → register data/transcription → enable mic.
- **KEEP** `Sources/API/*` (add a `joinHomeVoice()` call returning the response
  above if not present), `Sources/Session/InterviewSession.swift` +
  `Sources/Views/InterviewView.swift` (interview room; ensure `resume(sessionId:)`
  exists for the handoff), `AppConfig`, `SettingsView`, the companion art
  primitives.
- **REMOVE** (after verifying usages): `HomeVoiceInlineWorkspace`,
  `HomeVoicePendingActionCard`, `HomeVoicePendingAction`,
  `HomeVoiceClientWireEvent` confirm/cancel events; the on-home full-screen flows
  `ScheduleCreationFlowScreen` + `JDEntryFlowScreen` (schedule/JD creation is now
  voice-driven on the home path — do not launch these from home); the device-STT
  home slot-filling path (`VoiceCommandInterpreter` home command parsing,
  `SpeechCommandRecognizer` for the home — the concierge uses **server** STT via
  LiveKit) IF and only if nothing else depends on them. Delete their tests
  (`HomeVoicePanelModelTests` confirm/cancel cases, `VoiceCommandInterpreterTests`,
  `HomeVoiceTeardownTests` as needed) or rewrite them to the new model.

## Execution rules

- **TDD for pure logic:** the avatar-state mapping (session event → five states,
  incl. barge-in), the CTA routing (`primary_action.type` → interview vs voice),
  and the `navigate.interview` payload decoding are pure and MUST have failing
  tests first → minimal impl → green. The LiveKit/SwiftUI shell is verified by
  build + simulator run.
- **Build/test command** (iPhone simulator; pick an available device from
  `xcrun simctl list devices available | grep -i iphone`):
  ```bash
  cd <iOS repo root> && xcodegen generate && \
  xcodebuild test -scheme InterviewerApp \
    -destination 'platform=iOS Simulator,name=iPhone 16 Pro' 2>&1 | tail -20
  ```
  All suites green before each checkpoint. Do NOT run git.
- **No instructional/teaching copy on screen** (project rule). Minimal interaction
  backed by real functionality.

## Tasks

- **Task 1 — Avatar reconciliation (TDD-lite + build).** Update the `qinglan`
  variant: body-colored limbs (kill orange feet), no blush, soft single glow vs
  rings. Add a snapshot-free unit assertion where feasible (e.g. the foot/limb
  color equals body color); otherwise verify by simulator build + a brief visual
  check. ✅ Checkpoint — user commits (`QinglanAvatarView.swift`).
- **Task 2 — `HomeVoicePanelModel` rework (TDD).** Failing tests for: session
  event → five-state mapping incl. barge-in (speaking + user-speech → listening);
  `navigate.interview` payload decode → `session_id`; teardown resets to idle.
  Remove the dead confirm/cancel wire protocol. ✅ Checkpoint — user commits.
- **Task 3 — `LiveKitController` data + state wiring.** Register the
  `navigate.interview` data handler; surface agent-speaking / local-speaking
  callbacks. Validate SDK symbols. Build green. ✅ Checkpoint — user commits.
- **Task 4 — `HomeView` new layout (TDD for CTA routing).** White bg, big 青岚
  five-state avatar (tap start/stop), single bottom CTA from
  `current_context.primary_action`; failing tests for the routing table
  (interview-class vs conversation-class). Wire `navigate.interview` → push
  `InterviewView` (resume by `session_id`). Delete the old card home + inline
  panel. ✅ Checkpoint — user commits.
- **Task 5 — Remove dead code + flows.** Delete the slot-filling/confirm UI,
  on-home schedule/JD full-screen flows, and any now-unused device-STT home path
  (verify usages first; delete/trim their tests). Full suite green + simulator
  build succeeds. ✅ Checkpoint — user commits.
- **Task 6 — Manual acceptance (simulator/device).** Tap 青岚 → connecting →
  hears the proactive opener (speaking); speak to interrupt (listening); a tool
  runs (thinking); the bottom CTA shows the live `primary_action`; tapping an
  interview-class CTA (or a `navigate.interview` signal) enters the interview room;
  tap again returns to idle. Record latency/feel notes. ✅ Checkpoint — user
  commits any config tweaks.

## Done criteria

- Home is pure-voice 青岚 five-state + single bottom CTA on white; no card feed, no
  confirm buttons, no on-home schedule/JD screens, no teaching copy.
- Avatar matches the latest Figma (body-colored limbs, no blush, soft glow).
- Barge-in works (user can interrupt 青岚 mid-sentence).
- `navigate.interview` enters the interview room; CTA routing matches §Contract.
- iOS unit suite green; simulator build succeeds. **No git commands run by Codex.**
