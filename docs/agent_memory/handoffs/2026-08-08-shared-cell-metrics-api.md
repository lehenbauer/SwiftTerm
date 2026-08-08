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
