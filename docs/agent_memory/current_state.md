# Current State

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

## 2026-06-16

- `main`, `origin/main`, `whisp/foundation`, and `origin/whisp/foundation` are all at `a5254aa` (`Merge upstream main into Whisp SwiftTerm`); a no-op `git push origin main whisp/foundation` confirmed the GitHub fork is current.
- Local branch `agent/update-main-upstream-20260528` is obsolete scratch state, not missing Whisp work: it is not merged by ancestry, but diffing it against current `main` would roll back newer fork files/tests and delete current local project memory.

## 2026-06-07

- `whisp/foundation` at `e71d904` is 55 commits ahead and 9 commits behind Miguel de Icaza's `upstream/main` at `bf72355` after fetching `https://github.com/migueldeicaza/SwiftTerm.git`.
- A temporary trial merge of `upstream/main` into `whisp/foundation` found one conflict only: add/add in `Sources/SwiftTerm/SyncDebug.swift`.
- With the conflict resolved by keeping the local no-op `SyncDebug.log`, the merged result changes only:
  - `Sources/SwiftTerm/Mac/MacTerminalView.swift`
  - `Sources/SwiftTerm/iOS/iOSTerminalView.swift`
  - `Tests/SwiftTermTests/KittyOptionComposeTests.swift`
- Validation in the trial merge passed with `swift test --no-parallel`. A parallel `swift test` run aborted with signal 6 in the Swift Testing harness, but targeted tests and the serial full suite passed.
- Applied the upstream merge on `whisp/foundation` as `3a1bfaf` (`Merge upstream/main into whisp foundation`). The branch is no longer behind `upstream/main`.
- Final validation after the real merge passed:
  - `swift test --filter KittyOptionComposeTests`
  - `swift test --filter SynchronizedOutputTests`
  - `swift test --filter KittyKeyboardEncoderTests`
  - `swift test --no-parallel`

## 2026-06-15

- Fetched Miguel de Icaza's `main` into `refs/remotes/upstream/main` at `a3b8c9b`; `whisp/foundation` at `3a1bfaf` is 56 commits ahead and 13 commits behind.
- A dry merge of `upstream/main` into `whisp/foundation` applied cleanly with no conflicts. Net incoming changes touch only `Buffer.swift`, `LocalProcess.swift`, `Terminal.swift`, `TerminalViewSearch.swift`, and `MouseTrackingTests.swift`.
- Upstream's first two incoming commits (`05361a4`, `2d8234f`) cancel each other out; they have no net merge effect.
- Semantic caution for a future merge: upstream's new `Buffer.totalLinesTrimmed` accessor documents `linesTop` as monotonic, but this fork's `prependScrollbackCapture` decrements `linesTop` when older rows are inserted.
- Dry-merge validation passed:
  - `swift test --filter 'MouseTrackingTests|SearchTests|ReflowPortedTests|RetainCycleTests'`
  - `swift test --no-parallel`
