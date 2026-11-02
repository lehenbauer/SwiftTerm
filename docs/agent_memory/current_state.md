# Current State

Bounded snapshot of main. Detailed evidence lives in `handoffs/`; durable
constraints live in `decisions.md`.

## Branches and pins

- Main adopts released upstream v1.99.2 (`a183c15`) through fork merge e12887a,
  echo repair060f8a4 and overlay repairs ee78a76/7e49e98. Whisp's exact pin is
  `9d5ceadcb491ef93062bea3e0c37933c5dc6f871`, adding UIKit-only extra-history
  presentation and fixed-grid layout anchoring. Mac leaves the feature disabled.
- Phone integration and evidence: `handoffs/2026-11-01-keyboard-viewport.md`.
  The exact published pin is retained; the closing successor changes only docs.
- The user accepted the live Whisp worktree build and explicitly approved main
  integration. Preserve that running worktree; no additional relaunch or release.
- Evidence: `handoffs/2026-10-30-upstream-v1.99.2/README.md`, plus the Whisp
  sibling's `docs/agent_memory/handoffs/2026-10-30-swiftterm-v1992/`.

## Executed qualification

- Latest full Mac swift build/test:2105 Swift Testing +150 XCTest pass,31 existing skips.
- Exact-pin Whisp Mac/iPhone Release/Vision builds pass; native CG/Metal history
  and keyboard-cycle proof plus physical acceptance are in the phone handoff.
- UIKit1062+57 and Vision library build pass at060f8a4; later Mac-only delta
  permits reuse. Fourth echo wiring test separately passes on Mac/UIKit.
- Whisp exact remote pin: Mac/iOS/Vision builds, literal vision-build-check,
  native selection/identity70, paste26, scroll10, cursor11, replay10, file-drop
  and fonts pass. Full backend/support results and reuse are in Whisp's handoff.
- Final CG comparison:24 correctness,24 warm-ups,72 retained timing cells pass.
  Bulk main CPU improves71–90%; history costs+0.29ms/step (+38.9% in that session),
  steady-view CPU+1.3–9ms/s. Accepted tradeoffs, not eliminated regressions.
- General live Whisp use accepted by the user; no exhaustive physical/device,
  many-pane, heavy-build,120Hz,battery or Metal field qualification is claimed.

## Current contracts

- Terminal state is lock-owned and views expose copied reads/atomic commands;
  no public raw Terminal escape. Rendering uses upstream snapshots/frame driver.
- Persistent tmux mirror policy suppresses replay/emulator replies and OSC133,
  preserves selection, and distinguishes actual user input. Paste and following
  keys share an ordered delivery FIFO. Whisp feed remains on main, Metal opt-in.
- Fixed grids reject stale pending view sizes. Capture rows retain physical wrap
  and rehome arena/payload ownership. History repaint tracks buffer identity,
  refresh generation and absolute anchor, avoiding live-output history redraws.
- Native press anchors retain line identity and are consumed once. Cursor/blink
  and appearance policy are copied into snapshots; cellMetrics owns cell snapping.
- Interactive echo retains the150ms window with visibility, clock and DEC2026
  guards; overlay hit-target paint and knob invalidation avoid redundant work.
- UIKit mirror gestures do not inject local scroll input; mode transitions cancel
  gesture ownership synchronously. Repeat timers/observers use isolated teardown.

## History and limitations

- v1.19 adoption: `handoffs/2026-09-29-upstream-v1.19.0-adoption.md`.
- Wrapped capture/iPad acceptance: `handoffs/2026-10-18-scrollback-wrap.md`.
- Mac press anchors: `handoffs/2026-10-14-mac-selection-anchor.md`.
- Upstream environment-gated suites retain skips; Vision library compile does not
  establish an xrOS runtime pass. Native bookkeeping does not prove visual tracking.
