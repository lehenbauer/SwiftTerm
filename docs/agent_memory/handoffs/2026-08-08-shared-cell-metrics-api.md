# 2026-08-08: Shared cell metrics API

## Summary

Branch `fix/shared-cell-metrics` extracts `TerminalView`'s existing font-to-cell
calculation into the public static API
`TerminalView.cellMetrics(font:backingScale:lineSpacing:)`. The instance path
delegates to that API with its current font, display scale, and line spacing,
so the renderer and downstream layout code can share one implementation.

The computation is behavior-preserving for `TerminalView`: width still snaps
to the nearest device pixel, height still rounds up, and the existing width and
height clamps are unchanged. `TTFont` is now public so the shared signature is
portable across the existing macOS, iOS, and visionOS conditional builds.

## Tests and validation

- `FontDimensionTests.publicCellMetricsMatchInstanceComputation` checks Menlo,
  Monaco, and Courier New at 11, 12, 13, and 14 points, each at 1x and 2x.
- `swift build`: passed.
- `swift test --no-parallel`: 655 tests in 63 suites passed on real Metal
  hardware.
- `git diff --check`: passed.

## Downstream contract

Downstream clients that need terminal layout metrics should call the public
static API with the same font and backing scale used to construct their
`TerminalView`; do not duplicate the font-advance snapping formula.

## Regression context (why this API exists)

After the cf7764f upstream sync, Karl reported Whisp Mac terminals no longer
filling their windows (~4+ columns of dead right margin). Root cause chain:

- Upstream `87a7888` changed cell-width snapping from
  `ceil(cellWidth*scale)/scale` to `(cellWidth*scale).rounded()/scale`.
  Menlo 12 @2x (7.2246pt advance): old 7.5pt/cell, new 7.0pt/cell. The
  tighter spacing is upstream-intended, not a bug.
- Whisp carried two private duplicates of the OLD ceil formula:
  `NativeTerminalView.swiftTermCellMetrics` (fixed by ai-whisperer `e5fc910d`
  delegating to this API) and a second legacy CoreText copy in
  `MacWindowView.computeCellMetrics` feeding the workspace-window canvas
  (fixed by `edeec636`, using the hosting window's live backing scale).
- Residual margin after the first fix came from stale AppKit
  `frameAutosaveName` point frames baked at 7.5pt-era sizes; the canvas
  fix recomputes from current metrics at restore time.

Verified live via the Fleet Supervisor client witnesses
(`whisp_client_terminal_info`): 80-col panes on two workspaces report
`bounds_w = 560 = 80 x 7.0` exactly. Diagnosis used the `Terminal.inspect()`
API merged in the same sync.
