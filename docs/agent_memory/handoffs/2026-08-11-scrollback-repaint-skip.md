# 2026-08-11 — Scrolled-back CG repaint skip (Half B)

## What changed (`4cec8f3`, merged to `main`)

While scrolled back (`yDisp != yBase`) the CG renderer used to full-frame
invalidate on every display tick (upstream `cc5ed6d`'s stale-row fix) —
~15 identical full repaints/sec per pane under streaming output.
`updateDisplay`'s scrolled-back branch now skips `setNeedsDisplay`
entirely unless a repaint signal fires (`scrolledBackInvalidationRegion`
in `AppleTerminalView.swift`):

1. Displayed-buffer identity changed — alt-screen exit back to a
   scrolled-back normal buffer leaves alt pixels on screen with only
   live-row marks.
2. `fullRefreshGeneration` changed — palette/`colorsChanged`/BiDi-state;
   `Terminal.resize` now also bumps it (via `updateFullScreen()`) because
   column reflow rewrites history that live-row marks don't describe.
3. Viewport content anchor `linesTop + yDisp` changed — capacity slide
   clamped at the top, scrollback shrink. Recycle compensates
   (`linesTop += 1` / `yDisp -= 1` → stable → skip); prepend compensates
   (`linesTop -= n` / `yDisp += n` → stable → skip).
4. Update range escaped live-screen space (`rowStart < 0 || rowEnd >=
   rows`) — splice ops (ILM/DLM/SU/SD) record absolute indices;
   `updateFullScreen` marks `rowEnd == rows`.
5. Live rows, BiDi-expanded at their absolute (`yBase`-based) positions,
   overlap the visible rows — the original `cc5ed6d` in-place TUI case.

Tracking mirrors (`lastRepaint*` in `MacTerminalView.swift`) update on
pinned ticks too — an alt round-trip or generation bump consumed while
pinned must not read as "unchanged" on the next scrolled tick.

Pre-fix folded in: CG hover-link invalidation paints the viewport row
rect directly (extended one cell down) instead of pushing a
viewport-space row through the live-space update range; Metal keeps
`updateRange` (its `yDisp`-based dirty mapping consumes it correctly).

## Adversarial review record (grok, decorrelated)

Two grok sessions reviewed the design at Karl's request; raw reports in
`untracked/PLAN-scrollback-repaint-skip.md` and
`untracked/REPORT-refute-scrollback-repaint-skip.md` (ephemeral).

- v1 verdict **REFUTED** — three fatals, all confirmed by spot-check and
  fixed: hover marks viewport-space rows (→ pre-fix); alt→normal return
  invisible to all guards (→ guard 1); proposed head-drop counter
  double-counted recycle since `linesTop += 1` already happens there
  (→ anchor is `linesTop + yDisp`, no new counter, no CircularList
  changes).
- v2 verdict **WEAKENED** — closed the fatals; new SEVERE R1:
  `resize(preservingTerminalModes:)` reflow invisible to all guards
  (→ `Terminal.resize` bumps generation); R5 footgun about mirror
  staleness (→ pinned-tick updates; the alt round-trip test proves it).
- Reviewer-confirmed survivors: deep-scroll + live print genuinely skips;
  selection/scrollTo/palette paths have independent invalidation.

## Validation

- `ScrollbackRepaintTests`: 12-case matrix — skip cases
  (deep in-place write, scrolling output, compensated capacity slide,
  prepend) verified to fail against the previous code; repaint cases
  (capacity slide at top, palette, alt round-trip, shrink, ILM,
  preserving resize, hover row rect, original overlap test) all green.
- Full `swift test --no-parallel`: 668 tests / 63 suites + XCTest, Metal
  hardware.
- Benchmarks (isolated wrapper, `Package.swift` hard-disables the
  target): `main-9f3afe1` vs branch p50 within ±1% — noise; nothing was
  added to the feed hot path.
- `../ai-whisperer` `make mac-client` green via temporary `file://` pin
  at `4cec8f3`, checkout hash-verified.
- Live: Karl exercised scrolled-back panes under streaming output —
  works.

## Traps for future work

- Any new "repaint what the user sees" path must bump
  `fullRefreshGeneration`, move the anchor, or `setNeedsDisplay`
  directly — live-row `updateRange` marks alone are skipped while
  scrolled back (that's the point). See decisions.md.
- Update-range coordinates remain a mixed bag (live rows, absolute
  splice indices, and — before the pre-fix — viewport rows). Guard 4 is
  the bandage; a single-space normalization would be the real cleanup
  (upstream-sized project).
- Kitty pure-historical image wipes were already unmarked before this
  change (pre-existing weakness, `KittyGraphics.swift:~1693`); guard 4
  does not make it worse but does not fix it.

## Not done / follow-ups

- Partial-rect translation in the overlap case (deliberately full-frame).
- iOS branch untouched (still full-bounds every tick).
- RenderBench GUI baseline still owed generally.
