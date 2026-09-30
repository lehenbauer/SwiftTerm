# Decisions

## 2026-09-29

- Adopt only stable released upstream SwiftTerm tags into the fork (GitHub pre-releases such as v1.20.0 are not eligible); do not pull unreleased upstream `main` work (e.g. Ghostty-derived IO/SIMD, `6ea9082`) into a release integration to chase throughput — `handoffs/2026-09-29-upstream-v1.19.0-adoption.md`.
- Never re-pin Whisp to a v1.19-based SwiftTerm without Whisp's OSC 133 mirror override (ai-whisperer `77b1d871` or equivalent) in the same change; without it, built-in OSC 133 A/N/L handling makes tmux mirrors diverge from tmux's grid.
- Do not read RenderBench feed ticks/s as rendering latency or presented frames: the v1.19 Metal `arabic-line` ~39% tick drop is feed cost plus more successful draw builds, and the 2026-08-08 3–4% BiDi acceptance does not cover it.
- Keep v1.19 `clearScrollback` preserving absolute row identities, the screen-relative saved cursor, image counts and output-follow state (including the global follow flag when cleared under the alternate screen), and never import OSC 133 marks, groups or cell tags from captured history.
- v1.19.0 adoption accepts its +9.3–10.3% headless ASCII feed cost as measured; do not re-open the hold or record the cost as fixed until a released upstream change (e.g. `6ea9082`) is measured with `Benchmarks/` — `handoffs/2026-09-29-upstream-v1.19.0-adoption.md`.
- Do not move Whisp's `feed` off the main thread on v1.19: its "background feed" comments lack upstream's terminal locks (`222400c`), callback marshalling (`282a7bd`) and snapshot CG rendering (`59b3017`).
- Do not drop `owningBuffer` assignment in `Buffer.onLineAttached` to recover feed cost: it measured −2.6%/−4.1% p50 but is required for OSC 133 cross-buffer behavior.

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
