# Decisions

## 2026-08-11

- While scrolled back, the CG renderer only repaints on explicit signals
  (buffer identity, `fullRefreshGeneration`, `linesTop + yDisp` anchor,
  out-of-live-space marks, viewport overlap) — plain live-row
  `updateRange` marks are deliberately skipped. Any new "repaint what
  the user sees" path must bump the generation (`updateFullScreen`),
  move the anchor, or `setNeedsDisplay` directly; `Terminal.resize`
  must keep its `updateFullScreen()` call (column reflow rewrites
  scrolled-back history) — `4cec8f3`,
  `handoffs/2026-08-11-scrollback-repaint-skip.md`.
- CG hover-link invalidation must not route through `updateRange`: it
  computes a viewport row, and the update range is live-screen space —
  the two disagree while scrolled back. Keep the direct row-rect
  `setNeedsDisplay` (Metal keeps `updateRange`; its `yDisp`-based
  mapping is the one that consumes viewport rows correctly).

- Caret visibility (CG renderer) has exactly one owner:
  `updateCursorPosition()`. The `showCursor`/`hideCursor` delegates must
  never add/remove the caret view directly — an unconditional `addSubview`
  there re-creates the rapid caret flash over scrollback that DECTCEM
  hide/show cycles from AI CLIs trigger (`9f3afe1`,
  `handoffs/2026-08-11-scrollback-caret-flash.md`).

## 2026-08-08

- Cell metrics have exactly one owner: `TerminalView.cellMetrics(font:backingScale:lineSpacing:)`.
  Never duplicate the width/height snapping formula downstream — Whisp carried
  two private copies of the old ceil formula, and upstream `87a7888`'s
  ceil→rounded change silently desynced them (visible as a dead right margin).
- The ~3-4% feed-throughput cost of upstream's BiDi paragraph bookkeeping
  (`db31f3a`) is accepted and upstream-inherent; do not strip `bidiState`
  propagation from the LF/wrap/scroll hot path to recover it — the propagation
  is semantically required in the default `.implicit` mode, and a guard-only
  equality check measured as a wash. Recovery requires a designed mode-gated
  fast path (see 2026-08-08 handoff), ideally offered upstream.
- Upstream tracks generated `Tools/BidiHarness/Scripts/__pycache__/*.pyc`
  files; deliberately not removed in this fork. A local strip commit would
  conflict at every future sync — wait for upstream to clean it.

## 2026-07-20

- Construction never resizes: `Terminal.init` builds buffers at the resolved options grid and `setup(isReset:)` guards buffer resize by size mismatch. Do not reintroduce resize-as-initialization, and keep the guard size-based — `setup()` is public "apply changes" API.
- The initial-geometry view initializer keeps `terminalOptions` and `autoResizeGrid` WITHOUT default values: a default on the former creates overload ambiguity with `init(frame:font:)`, a default on the latter silently turns an authoritative `.grid` into follow-view at first layout.
- `.viewport` is spelled `.viewport(points:)` and takes view points; never accept device pixels or mix backing scale into grid division.
- macOS scroller reservation is style-based (legacy reserves, overlay none), replacing visibility-based reservation that made column math depend on scroll state at measure time. Do not revert to `isHidden`-based reservation.

## 2026-06-27

- For the upstream full-width glyph centering merge, resolve `AppleTerminalView.updateCursorPosition` by using the fork's clamped `cursorColumn` everywhere the caret indexes/positions the cursor, while also applying upstream's `charUnderCursor.width` sizing so full-width cells get a full-width caret.
- DEC synchronized output mode 2026 should be treated as a live-buffer core mode in this fork: the core toggles `synchronizedOutputActive`, `displayBuffer` mirrors `buffer`, and display blocking belongs in the view layer. Do not reintroduce a frozen core buffer snapshot when resolving future upstream test conflicts.

## 2026-06-07

- For the June 2026 upstream merge, prefer resolving `Sources/SwiftTerm/SyncDebug.swift` by keeping the local no-op implementation. Upstream's added version describes a host-app opt-in trace, but `enabled` is a `static let false` on an internal enum, so it is not a usable public toggle and adds dead stderr logging machinery.
