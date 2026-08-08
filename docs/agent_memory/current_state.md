# Current State

## 2026-08-08

- Merged upstream `cf7764f` (52 commits: BiDi/Arabic, Metal
  BufferPool/atlas/Bundle.module fixes, Hangul IME, DECCOLM gating, parser
  hardening, line-accurate scroll wheel) into `main` as `affe8412`, plus plain
  commit `b2c68bc` translating selections across `prependScrollbackCapture` —
  `handoffs/2026-08-08-upstream-sync-cf7764f.md`.
- Validation: full serial suite green on Metal hardware (654/63 + XCTest);
  `../ai-whisperer` `make mac-client` green via temporary local pin;
  Benchmarks show an accepted upstream-inherent ~3-4% feed cost from BiDi
  bookkeeping (root-cause + ablation in the handoff; see decisions.md).
- All eight merge conflicts resolved combining both sides; every fork surface
  verified surviving (autoResizeGrid, initial geometry, inspect API,
  pending-wrap caret clamp now feeding BiDi caret mapping, line-info caches,
  iOS `UIEditMenuInteraction`, non-monotonic `linesTop`).
- Live exercise: Karl ran `make mac-combined-run` on ai-whisperer branch
  `feature/swiftterm-upstream-cf7764f-adoption` (pin at `b2c68bc`) — typing,
  scroll wheel, selection, and multi-pane mouse-mode TUIs all pass. Pushed
  `main` to origin with Karl's approval the same day; the adoption branch
  re-pins to the GitHub URL for the durable Whisp flip.
- Not yet done: land the adoption branch in ai-whisperer `main`, RenderBench
  GUI baseline, BiDi disabled-mode fast path.

## 2026-07-20 (later)

- Merged `feature/terminal-inspection-pr1` into `main` (`164fb11` tip): public
  `Terminal.inspect()` + view `inspectGeometry`/`inspectInputPolicy`/`inspectAll`
  for client third-witness dumps; Codable snapshots; full `swift test` green in
  worktree before merge. Whisp pin/adoption lands separately.
- Design/reviews: `untracked/DESIGN-terminal-inspection.md`, Fable + sol red-team
  reports under `untracked/`.

## 2026-07-20

- Merged `feature/initial-geometry` into `main` fast-forward (`9a82b23`):
  terminals construct directly at the resolved `TerminalOptions` grid (no
  provisional 80x25), new `TerminalInitialGeometry` + atomic view
  initializer, style-based macOS scroller reservation, wide-grid tab-stop
  and `tabStopWidth` defects fixed — `handoffs/2026-07-20-initial-geometry.md`.
- Validation: `swift build`; `swift test --no-parallel` (517/49 + 43 XCTest,
  Metal hardware); iOS platform xcodebuild; `../ai-whisperer`
  `make mac-client` green against `9a82b23` (pin flipped on its
  `feature/initial-geometry-adoption` branch; Whisp mirror adoption + live
  drill in flight there).
- Pushed `main` to origin at `0b539b7` with Karl's approval the same night;
  fork and origin in sync. The live-exercise validation leg was satisfied by
  the Whisp adoption drill (12/12 mirrors born at model grid, zero
  `feed_grid_mismatch`; `../ai-whisperer` merge `aac1c84d`,
  handoff `2026-07-20-initial-geometry-adoption.md` there). Whisp pins this
  fork at `9a82b23`.

## 2026-07-14

- Merged `fix/mirror-grid-pin` (`a503a72`, pushed to origin during the Whisp
  mirror-grid-pin campaign) into local `main` as `19b194a`. Whisp pins this
  fork at `a503a72` by revision; the merge is lineage reconciliation only and
  does not move the pin.
- The branch adds `autoResizeGrid` (default true) gating both bounds-derived
  grid mutators (`processSizeChange`, `resetFont`) and
  `resize(cols:rows:preservingTerminalModes:)`; campaign record lives in
  `../ai-whisperer/docs/agent_memory/handoffs/2026-07-14-mirror-grid-pin-campaign.md`.
- Validation passed on the merged result: `swift build`;
  `swift test --no-parallel` (496 tests / 47 suites + 43 XCTest cases, 0
  failures, Metal hardware; `MirrorGridPinTests` suite green).
- Pushed to `origin/main` later the same day with Karl's approval
  (`f4f73d8..34c1728`); fork and origin are in sync.

## 2026-07-01

- Merged fork `origin/main` at `faa1f44` into local `main` after the prior upstream sync commit `269c7bb`.
- This was not a new Miguel upstream intake: `upstream/main` remained at `9adb624`, and `git rev-list --count main..upstream/main` was already `0` before the fork merge.
- The only real conflict was in `Sources/SwiftTerm/Apple/AppleTerminalView.swift`, where the upstream-sync side had `GlyphSlotFit` and the fork side had `LineInfoCacheEntry` inserted after `ViewLineInfo`; resolved by keeping both structs.
- The merge preserved the June 27 pending-wrap plus full-width caret behavior and brought in fork work for Apple renderer line-info caching, Metal cursor activity visibility, and viewport-anchored search.
- Validation passed:
  - `git diff --check --cached`
  - `swift test --filter 'LineInfoCacheTests|TerminalViewCursorTests|SearchTests|SynchronizedOutputTests' --no-parallel`
  - `swift test --no-parallel`
- No push was performed.

## 2026-06-27

- Fetched Miguel de Icaza's `main` into `refs/remotes/upstream/main` at `9adb624` and merged it into local `main` as `269c7bb` (`Merge upstream/main into Whisp SwiftTerm`).
- Incoming upstream range from merge base `a3b8c9b` had six commits:
  - `ebc6ca2` force text presentation for default-text emoji-capable symbols.
  - `bb8423d` fix Mac word-mode backward drag selection preserving the seed word.
  - `ab99ba3` center full-width CJK glyphs in CoreGraphics/Metal/caret paths.
  - `9adb624` update synchronized-output test for the no-core-buffer-snapshot contract.
  - Merge commits `6e5dcf2` and `7af5db2`.
- Real conflicts were limited to:
  - `Sources/SwiftTerm/Apple/AppleTerminalView.swift`: combined the fork's pending-wrap cursor-column clamp with upstream full-width caret sizing/text.
  - `Tests/SwiftTermTests/SynchronizedOutputTests.swift`: kept the live-buffer DEC 2026 contract and active-flag assertions; updated stale "frozen buffer" wording.
- Validation passed:
  - `swift test --filter 'SynchronizedOutputTests|SelectionTests|UnicodeTests|BufferTests|TerminalViewCursorTests' --no-parallel`
  - `swift test --no-parallel`
- After the merge, `git rev-list --count main..upstream/main` is `0`. No push was performed.

