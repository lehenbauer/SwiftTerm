# integrate/upstream-v1.99.2 — branch state

Bounded snapshot of the upstream v1.99.2 integration branch. Remove after integration to `main`,
once globally relevant facts are promoted to `current_state.md`/`decisions.md`.

## Identity
- **Parents:**
  - fork `2af5220`: docs after the product pin `674ad88`;
  - upstream tag `v1.99.2` = `a183c15b52858530a17de57dcc72b93eeebc9857`.
  - The merge base with upstream is `464df52` (v1.19.0).
- The merge was resolved in worktree `/Users/karl/src/SwiftTerm-v1.99.2`.
- Source candidate committed as `e12887acb5e28f136ee6fa302b806dfa63c50d4e`. There is no push and no Whisp re-pin until downstream and performance gates pass.
- **Working artifacts** (untracked; promote to `handoffs/2026-10-30-upstream-v1.99.2/` at closeout):
  - worktree `untracked/agent-work/2026-10-30-swiftterm-v1992/`;
  - shared Whisp `../ai-whisperer-feature-swiftterm-v1.99.2/untracked/agent-work/2026-10-30-swiftterm-v1992/`, holding `REPORT-fork.md`, `FORK-API-CONTRACT.md`, `FORK-CONFLICT-PROPOSALS.md` and `COORDINATOR-DECISIONS.md`.

## Architecture adopted from upstream
- `getTerminal()` is removed, and `TerminalView.terminal` is internal. Terminal state sits behind `terminalLock`; views expose copied reads and lock-internal commands. No public `withTerminal` or raw-buffer escape.
- Rendering is snapshot based (`TerminalRenderOwner`, `TerminalSnapshot`, `FrameDriver`), and Kitty graphics storage is upstream's.
- **Upstream's Metal renderer is adopted wholesale. Fork Metal behaviors ported on top:**
  - static cursor-blink policy;
  - a cursor activity window;
  - flushing glyph caches when font smoothing toggles;
  - tearing down the raster font registry on a font change.
- The fork's CG line-info cache is superseded by the snapshot and text builder.

## Fork policies preserved (exercised by tests)
- **Initial geometry:**
  - construct at `TerminalInitialGeometry` with `autoResizeGrid` gating every bounds/queue resize (root also discards pending view sizes on a pin);
  - no provisional 80x25.
- **`resize(cols:rows:preservingTerminalModes:)`:** no soft reset. A changed grid resets each buffer's region and margins to full extent (contract change absorbing Whisp `TerminalGridPin`, `MirrorGridPinTests`); a same-size call preserves them.
- **Tmux mirror (root):**
  - `configureForTmuxMirror` (OSC 133 no-op, reply provenance suppression, D2 selection preservation);
  - `ignoreSemanticPromptsForTmuxMirror()`;
  - `requestFullDisplayRefresh()`;
  - cursor rendering policy.
- **Scrollback prepend and hydration:**
  - `prependScrollbackCapture` keeps wrapped physical rows and capture-only default padding;
  - scratch-parser rows are rehomed to the destination arena;
  - OSC 8 payloads are re-interned once per source code, failing closed;
  - selections translate, and the UIKit momentum anchor holds (`forcePosition`, manual-scroll entry via `isTracking || userScrolling`, post-lock `scrolled`).
- **Mac press anchor:**
  - line-identity, single-use `PressAnchor`, layered on upstream's drag threshold;
  - adjudicated: triple-click extends whole rows, jitter stays a click, orphan drags are ignored, an overwrite clears the selection in ordinary views.
- **CG scrolled-back repaint skip** (root, in `TerminalRenderOwner`):
  - hover and blink are snapshot style with no live-range marks;
  - `Terminal.resize` keeps `updateFullScreen()`.
- **DEC 2026:** live display buffer (`displayBuffer == buffer`); the snapshot freezes while it is active.
- **Selection and inspection:**
  - styled selection runs; block selections give one unstyled run;
  - `cellMetrics` (upstream character-W formula) is the single owner;
  - `Terminal.inspect()` / `inspectAll` gain `bufferGeometry` (yDisp/yBase, trim, region, margins, saved cursor).
- **Appearance:**
  - themes, `terminalAppearance`, fork `minimumContrast` (L*, applied after upstream's WCAG `minimumContrastRatio`) and `nativeBoldForegroundColor` (nil under DECSCNM) run through `FrameViewState` and `SnapshotRenderContext`;
  - Mac `followsSystemScrollerStyle` (default true).
- **iOS:**
  - edit-menu interaction;
  - accessory Enter and Shift-Tab;
  - hardware printable key repeat (marked text goes to the input method);
  - key-repeat timers invalidated in `isolated deinit`.
- **Narrow API contract (accepted):** `TerminalView` has an `isolated deinit` (iOS: repeat timers; Mac: scroller-preference observer). Subclass `deinit`s must be `isolated`; Whisp `MacMirrorTerminalView` is already updated.
- **Upstream semantics adopted by adjudication:**
  - an opaque host underlay under opaque Metal;
  - Kitty same-id retransmit removes placements;
  - per-row deselection rebuild;
  - the overlay scroller stays hidden until revealed.

## Executed gates (latest candidate snapshot; logs under worktree `untracked/agent-work/2026-10-30-swiftterm-v1992/`)
| Gate | Result |
|---|---|
| `swift test --no-parallel` | exit 0: 2099 Swift Testing tests / 204 suites, 146 XCTest (`full2.log`). 31 upstream environment-gated skips (e.g. `KittyKeyboardAppKitReproductionTests`). |
| iOS 27.2 `xcodebuild test-without-building -scheme SwiftTerm-Package` on simulator `34F53F75-DB5D-4824-9464-73EC875779EA` | exit 0: 1059 Swift Testing tests / 94 suites, 57 XCTest (`ios-test4.log`, `ios-test4.xcresult`); build `ios-build7.log`. Old-red timer evidence: `ios-test1.log`, `ios-test2.log`. |
| visionOS `xcodebuild build -scheme SwiftTerm`, generic simulator | BUILD SUCCEEDED (`vision-build4.log`). No xrOS runtime, so no tests ran. `SwiftTerm-Package` test build fails only in upstream's untouched `termcast` CLI (`TermcastRecorder.swift:214-217`). |
| Root probes | Mirror policy, history prepare, Kitty deferred reply and paste FIFO: Whisp shared dir `root-probes/run.log`, `paste-order-new.log`. |
| Whisp client | Snapshot-5 Mac build reported by the coordinator; see `REPORT-client.md`. |

## Interactive echo window restoration

The first benchmark exposed an omitted fork policy: baseline `feedFinish` rendered
immediately for output within150ms of user input. The snapshot feed path had only
marked dirty, so an already-running display link deferred echo until vsync.
The owner now records user input with a checked timestamp and publishes a coalesced
immediate frame after parsing only inside that window, when visible and outside
DEC2026. Keyboard and core paste paths record without duplicate registration. Both
view feed overloads and checked LocalProcess byte/borrowed feeds use the policy.

- Full Mac:2102 Swift Testing/205 suites plus146 XCTest pass (`echo-full.log`).
- Full iOS:1062 Swift Testing/95 suites plus57 XCTest pass (`echo-ios-test.log`).
- Vision library builds (`echo-vision.log`).
- A subsequent fourth test exercises actual keyboard/paste and byte/text feed
  wiring without a display-link tick. Mac focused4/4 pass (`echo-wiring.log`);
  focused UIKit4/4 and independent mutation proofs also pass (feed wiring and
  hidden-visibility guard mutations each fail the corresponding regression).
- Native diagnostic echo draw-completion median0.299ms/p99 0.376ms,0misses
  (`performance/runs/diag1-diag-echo1-echo-typed.log` in the shared Whisp artifacts).
  This is causal sanity, not final quiet-paired timing or glass latency.
- Input-then-flood diagnostic remains faster than shipping. Bounded Metal
  diagnostic shows no added main hops; it is not Metal product qualification.
  Full final paired qualification is held at the history-scroll regression.

## Held adoption / remaining gates
- **Clean-identity downstream:**
  - publish the exact committed revision;
  - re-pin all four Whisp product/probe pins with the manifest and lockfile together;
  - fresh-resolve Mac/iOS/Vision builds plus native fixtures (mac-scrolling, mac-selection-anchor, mac-file-drop, pane-replay-rendition, mac-cursor);
  - Whisp support (2830 XCTest + 107 Swift Testing) and backend (5238 passed, 23 skipped) already passed; reuse while their inputs remain unchanged.
- **Paired performance:** matched baseline `674ad88` vs candidate runs through the CG/view path with the presentation witness (perf worker), not feed counters; investigate material regressions.
- **Open risks:**
  - The keystroke that *starts* an IME composition is taken by the printable repeat path (unchanged fork behavior; needs a device or real IME check).
  - The Mac observer `deinit` cleanup is verified by compile and suite only.
  - Hosted XCTest `WhispMacClipboardTests` was not run (it launches the app).

## Disposition (2026-10-30, resumed)

SOURCE-QUALIFIED; downstream and performance gates pending. The user accepts
proceeding despite the bounded scrollback CPU tradeoff and wants no further
performance work. No merge to either main, no push from the worker, no pin
advance or activation.

- The overlay scroller fixes from `experiment/scrollbar-frame-coalescing-v1992`
  are cherry-picked unchanged: `ee78a76` (from 49595b0, the overlay hit target
  paints no legacy chrome) and `7e49e98` (from 4d68c80, the knob repaints in the
  display pass only when it moves). Sources tree
  `17e363d44171c92b7c6b6047a8c36f807a6a0a20` is identical to 4d68c80.
  The change is Mac-only: `MacTerminalView.swift` sits under `#if os(macOS)`,
  and so do the tests (`FontResizeColumnsTests.swift`).
- Full Mac: `swift build` and `swift test --no-parallel` exit 0. 2105 Swift
  Testing tests in 205 suites (31 environment-gated skips) plus 146 XCTest.
  Logs: Whisp shared dir `.../resume/fq-full-test.log`.
- iOS (`echo-ios-test.log`) and Vision (`echo-vision.log`) results at 060f8a4
  are reused, because the delta compiles out on those platforms. They were not
  rerun on this tree.
- Timing, from the experimental branch at an identical Sources tree:
  - over-frame stalls are gone in the history workload;
  - main CPU is still +20.2% versus shipping 674ad88 (529 vs 440 ms);
  - accepted by the user, not fixed;
  - no full 12-workload pair was run.
- Still unverified by hand:
  - knob-drag smoothness;
  - overlay reveal and fade;
  - repaint on a runtime switch between legacy and overlay;
  - light/dark knob color.
- Still pending: the coordinator publishes the exact revision, then the
  downstream re-pin and its gates run.

Earlier HOLD record at 060f8a4 (history benchmark +77% main CPU, 21.87ms worst
iteration) and archived receipts:
`/Users/karl/src/ai-whisperer-feature-swiftterm-v1.99.2/docs/agent_memory/handoffs/2026-10-30-swiftterm-v1992/README.md`.
Retain worktrees and artifacts.

## Publication and retention constraints

The coordinator may publish this verified feature branch for exact-revision
Whisp developer pins. Do not merge either repository to main in this task.
Never rewrite or delete `integrate/upstream-v1.99.2` while any Whisp ref pins
one of its commits; a fresh remote clone must retain access to each pinned SHA.
Whisp's Mac release gate still requires fork-main ancestry and is not waived.
Developer qualification is separate from release eligibility and live activation.

## Final source qualification and adoption decision

At 45b58d4 (Sources 17e363d4), the full downstream Mac/iOS/Vision builds and
assigned Mac native fixtures pass. The final CG benchmark passes 24 correctness
runs, 24 warm-ups and 72 retained timing cells, all timing cells compiler-clear.
The coordinator accepts feature-branch developer adoption under the user's
resumed direction; no additional optimization is planned.

Within this session, bulk main CPU falls about 71–90%. History scrolling costs
an extra 0.29 ms/step (+38.9%); steady-view CPU adds 1.3–9.0 ms/s depending on
workload. These costs are accepted for developer qualification, not eliminated.
All 240 history steps draw, with no over-frame history iteration. General
responsiveness, energy and many-pane heavy-build behavior remain unproven.

Evidence and root adjudication are retained in the Whisp sibling's
`untracked/agent-work/2026-10-30-swiftterm-v1992/resume/`:
`REPORT-fork-qualify.md`, `REPORT-client-qualify.md`,
`REPORT-final-performance.md`, and `RESUMPTION-DECISION.md`.
Publication and the four Whisp pins follow this source qualification; ordinary
remote-resolved downstream builds must still pass. These final sections
supersede earlier pending/HOLD descriptions above without erasing their history.

## Downstream completion

Published pin `365bb5135272e051f3a54c9ebf300a7ba4007b91` is adopted in Whisp
feature commit `ddbfe3ab58eb8f26d2afecdd1e11f63ebdc20a9e`. Fresh remote identity,
ordinary Mac/iOS builds, literal vision-build-check, default dependency identity
70/70 and SidebarNativeProbe 4/4 pass. Sources/Tests/manifests match the qualified
45b58d4 candidate. Both implementation worktrees are retained; neither main was
merged, and no app/helper or device was activated. No further source work remains
for this bounded adoption. Manual visual/physical-input and live-use acceptance
remain separate.

Final evidence: Whisp sibling
`docs/agent_memory/handoffs/2026-10-30-swiftterm-v1992/README.md` and
`resume/REPORT-pin-final.md` beneath that directory. The final documentation-only
successor to 365bb51 does not require another downstream pin change; preserve
365bb51's reachability on this branch.
