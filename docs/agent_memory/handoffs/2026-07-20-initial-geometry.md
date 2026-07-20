# 2026-07-20 — Initial terminal geometry (design → red team → Codex implementation → merge)

Terminals were always constructed at 80x25 and then resized to their
requested grid. This campaign makes construction happen directly at the
resolved grid and adds an atomic view-level API for initial geometry plus
resize policy. Branch `feature/initial-geometry`, four commits
(`8c9ed35`, `6654ca6`, `a3d442b` Codex; `9a82b23` coordinator), merged to
`main` fast-forward.

## What shipped

- **Core (`8c9ed35`)**: `Terminal.init` resolves and clamps
  `cols`/`rows`/`tabStopWidth` from `TerminalOptions` before constructing
  either buffer; both buffers are born at the requested grid.
  `setup(isReset:)` became an initializer rather than a resizer: buffer
  resize only on size mismatch (mirroring `Terminal.resize`'s tab-stop
  extension), alt buffer brought to the resolved grid on reset, default
  stops rebuilt on a changed tab width (unchanged width preserves HTS
  stops), and scroll regions/margins reset explicitly on BOTH buffers
  (previously implicit via the unconditional dual resize).
  `Buffer.setupTabStops` clamps stride width ≥ 1 at the sink. Fixes two
  live defects: no default tab stops past column 80 on wide construction,
  and `options.tabStopWidth` silently ignored (it was never read).
- **View API (`6654ca6` + `9a82b23`)**: public
  `TerminalInitialGeometry` — `.grid(cols:rows:)` (authoritative, wins over
  any frame) and `.viewport(points:)` (anticipated bounds in view points;
  SwiftTerm applies chrome/cell math identically to live layout). New
  designated initializer on Mac and iOS views
  `init(frame:font:terminalOptions:initialGeometry:autoResizeGrid:)` —
  `terminalOptions` and `autoResizeGrid` deliberately have NO defaults.
  `LocalProcessTerminalView` passthrough added. macOS scroller reservation
  is now style-based (legacy reserves width, overlay reserves none) so
  birth, first-layout, and font-reset grids agree; `resetFont` uses
  `getEffectiveWidth` for parity. `getTerminal()` reports the resolved grid
  immediately after construction, before layout (documented guarantee).
- **Docs (`a3d442b`)**: docc updates in TerminalOptions/GettingStarted/
  HeadlessUsage/Customization, including points-not-pixels and the
  immediate-dims guarantee.

## Process

Codex authored the design (`untracked/DESIGN-initial-terminal-geometry.md`);
Fable verified every claim against the tree and wrote the plan
(`untracked/PLAN-...md`); a Grok red team refuted the plan adversarially —
14 confirmed findings (probe evidence), of which F1 (same-size `setup()`
dual-buffer reset equivalence), F2 (reset never resized alt), F3/F4
(tab-width policy), F6 (no default on `autoResizeGrid`), F7/F8 (viewport
contract + construction-time scroller reservation mismatch), F15 (stride
clamp) shaped the brief (`untracked/BRIEF-...md` rev 3); a Codex worker
implemented; Fable diff-reviewed, re-ran gates, and added the rev-3 delta
commit. Red-team report: `untracked/REPORT-redteam-initial-geometry.md`;
implementation report: `untracked/REPORT-initial-geometry-implementation.md`.

## Validation

- `swift build` clean; `swift test --no-parallel` 517 Swift Testing tests /
  49 suites + 43 XCTest, 0 failures, Metal hardware (run by worker AND
  re-run by coordinator).
- iOS platform compile: `xcodebuild -scheme SwiftTerm-Package -destination
  'generic/platform=iOS' build` — BUILD SUCCEEDED (macOS toolchain never
  compiles the UIKit view, so this gate is what proves the iOS initializer).
- Whisp consumer gate: `make mac-client` in `../ai-whisperer` green against
  revision `9a82b23` (fetched from GitHub after re-pin on branch
  `feature/initial-geometry-adoption` there). The live mirror exercise is
  deferred to that adoption campaign, which supplies the live-exercise leg
  of validation.

## Known follow-ups

- Whisp adoption (`../ai-whisperer` branch `feature/initial-geometry-adoption`):
  construct mirrors at the pane grid via `.grid` + `autoResizeGrid: false`
  instead of construct-80x25-then-pin; `AppTerminalView` needs a passthrough
  initializer (it defines its own designated inits).
- The old always-resize `setup()` behavior is gone by design; consumers that
  mutate `terminal.options` then call `setup()` get initializer semantics
  (size-guarded resize, tab-width policy) — documented in docc.
