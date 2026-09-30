# Current State

Bounded snapshot of what is true now. History and narrative live in
`handoffs/`; constraints in `decisions.md`.

## Branches and pins

- `main` is `2747875` (iOS scrollback momentum/prepend sync, atop the `b9a2d45` styled-selection-runs merge); `origin/main` matched it at last fetch.
- Upstream v1.19.0 adoption is selected and user-authorized (tested source `85cb8ca`, docs-only commits after) on local `integrate/upstream-v1.19.0` (worktree `../SwiftTerm-v119-integration`); merge to `main`, push and Whisp re-pin are pending coordinator live verification — `handoffs/2026-09-29-upstream-v1.19.0-adoption.md`.
- Whisp's committed pin was `2747875` when last checked (ai-whisperer `0a70523b`); no durable v1.19 re-pin has happened. Confirm in `../ai-whisperer` before relying on this.
- A v1.19 re-pin requires Whisp's OSC 133 mirror override (ai-whisperer `77b1d871`, branch `probe/swiftterm-v1.19.0`) — `handoffs/2026-09-29-upstream-v1.19.0.md`.
- Last merged upstream on `main` is `cf7764f` (via `affe8412`); v1.19.0 is `464df52` — `handoffs/2026-08-08-upstream-sync-cf7764f.md`.

## v1.19.0 adoption (`85cb8ca`, pending publication)

- Frozen qualification: `swift build` + `swift test --no-parallel` green on M5 Max Metal (865 tests/80 suites + 85 XCTest); iOS six filtered suites and TerminalApp CG/Metal 43/43 pass; Whisp `77b1d871` builds for macOS/iOS Sim/visionOS Sim — `handoffs/2026-09-29-upstream-v1.19.0.md`.
- No human visual, physical-keyboard or framebuffer acceptance has been done; Metal evidence is draw data/state only.
- Headless ASCII feed p50 is +9.3–10.3% vs `2747875`, mostly OSC 133 semantic row bookkeeping; accepted by the adoption decision, not fixed; diagnostic ablations cannot ship.
- Metal `arabic-line` RenderBench feed ticks drop ~39% from the release merge; that is feed cost (+24% per tick) plus more successful draw builds, not a measured rendering or presented-frame slowdown. Not an adoption priority (Metal disabled in Whisp; CG near baseline).
- Long headless Arabic control: initial merge +35.7% feed time vs main, overlapping pure release; upstream ranges d90963a..1052996 (+12.1%) and 1052996..464df52 (+21.1%) account for material cost, not individually bisected — `handoffs/2026-09-29-upstream-v1.19.0.md`.
- Clear-history on `85cb8ca` keeps absolute row identities, saved cursor, image counts and follow state; captured-history OSC 133 metadata is not imported.
- Next upstream pickup: stable released tag after v1.19.0 only (v1.20.0 is a pre-release); upstream `6ea9082` targets the measured weak-owner cost; do not move Whisp feed off main on v1.19 — `handoffs/2026-09-29-upstream-v1.19.0-adoption.md`.

## Renderer contracts (on `main`)

- Scrolled-back CG ticks repaint only on explicit signals (buffer identity, `fullRefreshGeneration`, anchor, out-of-live marks, overlap) — `handoffs/2026-08-11-scrollback-repaint-skip.md`.
- CG caret visibility is owned solely by `updateCursorPosition()`; DECTCEM delegates route through it — `handoffs/2026-08-11-scrollback-caret-flash.md`.
- Deferred there: partial-rect translation in the overlap case, iOS full-bounds ticks, update-range coordinate normalization.
- `TerminalView.cellMetrics` is the single owner of cell snapping — `handoffs/2026-08-08-shared-cell-metrics-api.md`.
- Upstream BiDi bookkeeping costs ~3–4% feed throughput, accepted; a mode-gated fast path is not done — `handoffs/2026-08-08-upstream-sync-cf7764f.md`.
- Selections translate across `prependScrollbackCapture` (`b2c68bc`) — `handoffs/2026-08-08-upstream-sync-cf7764f.md`.

## Fork API surfaces (on `main`)

- `Terminal.inspect()` and view `inspectGeometry`/`inspectInputPolicy`/`inspectAll` provide Codable third-witness dumps (`164fb11`).
- Terminals construct at the resolved `TerminalOptions` grid via `TerminalInitialGeometry`; no provisional 80x25 — `handoffs/2026-07-20-initial-geometry.md`.
- `autoResizeGrid` (default true) gates bounds-derived grid mutators for Whisp mirrors (`a503a72`); record in `../ai-whisperer/docs/agent_memory/handoffs/2026-07-14-mirror-grid-pin-campaign.md`.
- DEC 2026 synchronized output is a live-buffer core mode; display blocking is view-layer (see `decisions.md`).
- Fork line-info caching, Metal cursor-activity visibility and viewport-anchored search are present since the `2026-07-01` origin merge — `handoffs/2026-07-01-origin-main-merge.md`.

## Known limitations

- Kitty shared-memory tests skip: fixture shm name (53 bytes) exceeds Darwin's limit.
- Default suite counts include no-work cases: 3 optional performance-data tests, 2 esctest cases (suite absent), empty/unavailable fuzzer fixtures.
- Metal renderer tests need real Metal hardware; headless or simulator runs do not cover them.
- The 2026-09-29 campaign records a native RenderBench baseline at main `2747875`; compare identical workloads and distinguish feed ticks from presented frames — `handoffs/2026-09-29-upstream-v1.19.0.md`.
