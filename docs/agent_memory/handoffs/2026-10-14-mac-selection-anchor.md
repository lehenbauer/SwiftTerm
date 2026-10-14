# Mac selection starts at the original press — 2026-10-14

Status: fixed, verified, integrated and pushed on 2026-10-14. Exact repair
`5e91b9e23267698c6cf14e17864b0a054ae34929` is on public `main`; Whisp
integration `1956ad1bbb8d66e12cc5f757e6bf5258fab7d767` pins it in all four
active manifests/lockfiles. No live app rollout or physical-trackpad acceptance.

## Defect

A native single-click drag on macOS anchored the selection at the first
`mouseDragged` hit instead of the `mouseDown` cell
(`MacTerminalView.mouseDragged` seeded `setSoftStart(hit)` when inactive).
AppKit can deliver the first drag sample several cells from the press, so a
fast drag dropped the leading text, and a single displaced drag event selected
nothing. Diagnosis and the Opus 5.5 plan review are in Whisp's
`docs/plans/mac-selection-press-anchor.md` and
`untracked/agent-work/2026-10-13-mac-selection-anchor/REPORT-plan-review.md`.

## Change

- `Sources/SwiftTerm/Mac/MacTerminalView.swift`: private
  `PendingSelectionPress` (pressed `BufferLine`, its `recycleGeneration`,
  logical column, `terminal.cols`). Set after a `clickCount == 1` press that
  leaves the selection inactive (including Shift without a selection). Cleared
  at the top of `mouseDown`, in the `mouseUp` defer, on application-owned drags,
  in `keyDown`, and in `resignFirstResponder`. Consumed by the first native
  drag: when the line identity still resolves and the column count is the same,
  the drag runs `setSoftStart(press)` → `startSelection()` → `dragExtend(hit)`.
  Otherwise it falls back to the old current-hit seed. Active-selection
  extension and auto-scroll are unchanged.
- `Sources/SwiftTerm/SelectionService.swift`: comment-only. `setSoftStart`
  activates and notifies; it does not reset the mode.
- Output between press and first drag deliberately does not invalidate the
  anchor. Line identity follows scrollback trim and history prepend.

## Evidence

- `Tests/SwiftTermTests/MacSelectionAnchorTests.swift` has 35 tests that drive
  real NSEvents through an offscreen NSWindow and assert the selected text and
  range.
  - Against the original source: 17 fail (displaced forward, reverse,
    single-event, Shift, scrollback, trim, prepend and others).
  - After the fix: 35/35 pass.
  - Mutation check: removing each clearing point, single-use, the column check,
    the generation check or `startSelection()` fails a targeted test.
- `swift test --no-parallel` is green on M5 Max: 900 Swift Testing tests in 81
  suites, plus 85 XCTest. `swift build` is green.
- Native AppKit fixture outside XCTest (Whisp artifact folder
  `untracked/agent-work/2026-10-13-mac-selection-anchor/fork-native-fixture/`):
  a single displaced drag selects the four rows from press to hit. Logs are
  `fork-*.log` there.

## Limits

- No physical-trackpad, live Whisp pane, or Control-click/context-menu
  acceptance. Events are synthesized and sent straight to the handlers.
- The iOS selection path is untouched.
- With `allowMouseReporting`, a linefeed still clears an established selection
  (existing policy), so a streaming pane can still drop a selection after the
  first drag.

## Publication and guide modernization — 2026-10-14

The user explicitly approved publishing the verified repair and integrating
Whisp, and asked to align this fork's `AGENTS.md` with Whisp's general workflow
while omitting Whisp-specific rules. Guide-only commit
`3ebb2074bf81e8b8eb9483039b6d8898d3f55a99` permits verified autonomous source
commits, merges, pushes and in-scope dependency pins/upstream integration.
Testing, exact revision identity, unrelated-work preservation and authorization
for releases/deployments remain. `CLAUDE.md` already points to the canonical
guide; the managed GitNexus block was preserved verbatim.

Both primary branches fast-forwarded without conflicts, and `git push origin
main` plus independent `git ls-remote origin refs/heads/main` confirmed source
publication (SwiftTerm `3ebb207`, Whisp `1956ad1b`). `git diff 5e91b9e
3ebb207 -- Sources Tests` is empty. Whisp's normal `make spm-mirror-refresh`
passed. A fresh `xcodebuild -resolvePackageDependencies` with
`-disablePackageRepositoryCache` and a private `-clonedSourcePackagesDirPath`
fetched the public fork and checked out clean `5e91b9e`; the private bare
repository's origin is GitHub and it has no external object alternates.

Whisp's full support/backend suites, exact-revision Mac/iOS/Vision builds,
70 native wrapper assertions and Opus 5.5 final ACCEPT are recorded in
`../ai-whisperer/docs/agent_memory/handoffs/2026-10-14-mac-selection-anchor/`.
Later changes were documentation only; guide references and `git diff --check`
passed. Primary fork's unrelated untracked workspace/local-pin backup and
Whisp's modified TODO.md were preserved. The running app was not relaunched.
