# Fixed-grid extra-history viewport prototype

## Objective

Support Whisp's phone English keyboard viewport without changing the terminal's
logical rows or sending a remote resize. Isolated feature branch; no main merge.

## Implementation

- UIKit's opt-in `fillsExtraViewportFromHistory` defaults to false and only
  applies with `autoResizeGrid == false` and a viewport taller than the grid.
- Copy additional normal-buffer history into the render snapshot. CG and Metal
  share the snapshot; buffer dimensions, cursor addressing, scroll regions and
  emulator display anchor remain unchanged. Alternate screens do not borrow it.
- Cursor visibility uses the snapshot's presentation origin. Its absolute row
  still drives UIKit caret placement. Mac always leaves the option disabled.

## Verification

- Four range-policy tests pass (history, browsing, short buffers, disabled,
  ordinary-sized and alternate-screen cases).
- Full `swift test --no-parallel`: 150 XCTest plus 2105 Swift Testing pass;
  31 existing environment skips. Receipt: `full-swift.log` below.
- Native UIKit package test passes: opt-out differs from a taller reference,
  opt-in matches it pixel-for-pixel, CUP still addresses the logical live rows,
  and alternate-buffer entry/exit does not borrow unrelated history.
- Package drawHierarchy returned black because the test has no foreground app
  scene. After two failed capture fixtures, reassessed and used the real CG
  draw entry; this alone is not onscreen proof.
- Downstream Whisp's foreground app probe passes 23 checks, including actual
  onscreen CG and Metal comparison against the taller reference and cursor
  updates. Fixture correction uses the app's real font and stored renderer
  preference. Whisp Debug iOS, Mac and Vision builds pass with this local source.
- RenderBench dense_cells baseline/candidate, 10s each, CG and Metal all settle.
  CG baseline/candidate: 70.6/90.7 MB/s, 47.1/44.3 render fps; Metal:
  398.1/415.5 MB/s, 59.9/55.8 render fps. Single runs under other test load are
  smoke comparisons, not evidence of a speedup or energy/latency equivalence.
  The benchmark byte counter overflows on the Metal samples; MB/s and frames
  are reported separately. This change is disabled on that Mac path.

## Evidence and limits

- SwiftTerm receipts: `untracked/agent-work/2026-11-01-keyboard-viewport/`.
- Whisp worktree: `../ai-whisperer-prototype-english-keyboard-resize-20261031`,
  receipts under its same dated keyboard-viewport folder (`native-metrics.log`,
  `native-metrics-images/`, `mac-local.log`, `vision-local.log`).
- Physical phone visual acceptance remains downstream. Simulator Metal
  screenshots do not establish physical-device Metal behavior.
- GitNexus impact returned UNKNOWN for the changed snapshot refresh path;
  checked direct render-owner/CG/Metal consumers in source instead.

## Fixed-grid layout follow-up

Whisp's full keyboard-cycle driver exposed a quiet-program handoff: shrinking
the fixed grid's frame retained the old offset until more output arrived, so
Code keyboard hide failed its live-bottom guard. `processSizeChange` skips its
scroller update for fixed grids. UIKit layout now updates the scroller without
resizing the grid; it preserves manual browsing using the existing scroll owner.
The new native regression fails before the change (offset915 vs1215) and passes
after; both native extra-history tests pass (`follow-old.log`, `follow-fixed.log`).
This follow-up changes only UIKit layout; prior Mac suite/benchmark results apply.
Downstream exact-pin keyboard-cycle qualification is recorded in Whisp's
`RETAINED-GRID-2026-11-01.md` handoff.
