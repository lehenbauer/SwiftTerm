# 2026-06-15 Upstream Main Review

Reviewed the 13 commits from Miguel de Icaza's `upstream/main` after local `3a1bfaf`.

Commits:
- `05361a4` iOS vowel rewrite tweak.
- `2d8234f` revert of `05361a4`; no net effect.
- `f6429c6` public `Buffer.totalLinesTrimmed` accessor.
- `8ad1701` DECRST 1005/1006/1015/1016 resets mouse encoding without disabling tracking.
- `426b8f8` public `TerminalView.searchMatchSummary(_:options:limit:)`.
- `c6e35fd` `Buffer.resize` iterates `lines.count` rather than `lines.maxLength`.
- `f620c12` `LocalProcess` PTY read backlog backpressure.
- Merge commits `46e168f`, `a7f0e3b`, `34a1c13`, `24a68bc`, `a3b8c9b`.
- `ff59b8a` regression tests for DECRST mouse encoding behavior.

Dry merge:
- No conflicts. Git auto-merged `Sources/SwiftTerm/Terminal.swift`.
- Net incoming files:
  - `Sources/SwiftTerm/Buffer.swift`
  - `Sources/SwiftTerm/LocalProcess.swift`
  - `Sources/SwiftTerm/Terminal.swift`
  - `Sources/SwiftTerm/TerminalViewSearch.swift`
  - `Tests/SwiftTermTests/MouseTrackingTests.swift`

Assessment:
- Recommended to merge. Incoming work complements local fork work; it does not replace local appearance, accessibility, cursor, scrollback hydration, selection, kitty keyboard, or synchronized-output changes.
- Main practical gains: bounded PTY read memory under producer/consumer imbalance, faster and safer large-scrollback resize, mouse tracking compatibility with mosh-style mode reasserts, public search match counters, and an absolute scrollback trim counter useful for host-side viewport anchoring.
- Semantic caution: upstream documents `Buffer.totalLinesTrimmed` as monotonic, but this fork's `Terminal.prependScrollbackCapture` deliberately decrements `normalBuffer.linesTop` when older captured rows are inserted. If merging, adjust docs/consumer expectations so the value is treated as the absolute top-buffer line index in this fork, not always a monotonic trim count.

Validation in disposable worktree:
- `swift test --filter 'MouseTrackingTests|SearchTests|ReflowPortedTests|RetainCycleTests'` passed.
- `swift test --no-parallel` passed: 455 Swift Testing tests plus 43 XCTest tests.

Notes:
- GitNexus index was stale and was refreshed with `npx gitnexus analyze`.
- The disposable dry-merge worktree was removed after validation.
