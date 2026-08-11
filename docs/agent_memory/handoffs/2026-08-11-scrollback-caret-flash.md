# 2026-08-11 — Scrollback caret flash fix (CG renderer)

## Symptom

With a pane scrolled back while live output keeps arriving (an AI CLI
redrawing its progress UI), the caret flashed rapidly over historical
content — at any scrollback depth. Whisp default (CoreGraphics) renderer
only; Metal was never affected.

## Root cause

Caret visibility had three co-owners that disagreed while `yDisp != yBase`:

- `MacTerminalView.showCursor` re-added the caret NSView **unconditionally**
  on every DECTCEM show — no scrollback/geometry check, no repositioning —
  so it reappeared at whatever stale frame it last had.
- The next throttled `updateDisplay` tick called `updateCursorPosition()`
  (`AppleTerminalView.swift`), whose below-viewport check
  (`vy >= yDisp + rows`) removed it again ~16 ms later.
- AI CLIs wrap every frame redraw in DECTCEM hide/show, so the pair cycled
  at up to the output coalescing rate (~15 Hz in Whisp) → visible blips.
  iOS `showCursor` had the same unconditional `addSubview`.

The Metal path was immune because `showCursor`/`hideCursor` only queue a
redraw and the renderer clips the cursor to visible rows in-frame — that
became the model for the fix.

## Fix (`9f3afe1`, merged to `main`)

`updateCursorPosition()` is now the sole owner of caret visibility: it
removes the caret when `terminal.cursorHidden` or when the live cursor row
is below the scrolled viewport, and always repositions before showing.
The Mac and iOS `showCursor`/`hideCursor` delegates route through it
instead of touching the view hierarchy. Behavior is geometry-faithful:
when the live cursor row still overlaps a slightly-scrolled viewport the
caret stays visible at the correct translated position (matches Metal).

## Validation

- Two new `TerminalViewCursorTests` (DECTCEM show while scrolled back must
  not re-add; DECTCEM show with overlapping cursor row must reposition from
  a corrupted frame). Both verified to fail against the pre-fix source,
  pass with the fix.
- Full `swift test --no-parallel`: 657 tests / 63 suites + XCTest green on
  Metal hardware (M5 Max).
- `../ai-whisperer` `make mac-client` green via temporary `file://` local
  pin at `9f3afe1`; SPM checkout verified at that revision.
- Live exercise: Karl confirmed the caret no longer flashes when a pane is
  scrolled back while updating (`make mac-combined-run`).

## Origin / credit

Diagnosed from a codex session (Flashing Cursor whispspace, 2026-08-09
rollout). Codex correctly identified `updateCursorPosition()`'s missing
scrollback handling and the `cc5ed6d` full-viewport repaint; its stated
flash trigger (cursor row overlapping the viewport) was the secondary
case — the unconditional `showCursor` re-add was the dominant one.

## Deferred — Half B (perf, not started)

`updateDisplay` still invalidates the full frame whenever
`yDisp != yBase` (upstream `cc5ed6d` stale-row fix), ~15 full CG redraws/s
per scrolled-back pane. Sketch: translate the update range into viewport
space by `yBase - yDisp`, intersect with visible rows, skip invalidation
when disjoint (the common case — trimming adjusts `yDisp` to keep viewport
content stable, `Buffer.swift:499,574`); full-invalidate when the content
anchor shifts (trim clamping `yDisp` at 0 — detect via any change of
public `Buffer.totalLinesTrimmed`; fork's `linesTop` is non-monotonic).
Requires updating `ScrollbackRepaintTests` to assert "no stale rows"
instead of full-frame region, plus a `Benchmarks/` before/after run.
