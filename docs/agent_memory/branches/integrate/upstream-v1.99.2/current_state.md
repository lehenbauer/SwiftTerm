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

## Remaining before main / re-pin
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
