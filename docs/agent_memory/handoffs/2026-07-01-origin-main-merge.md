# 2026-07-01 Origin Main Merge

Merged the Whisp fork's `origin/main` at `faa1f44` into local `main` after local `main` had already incorporated Miguel de Icaza's `upstream/main` at `9adb624`.

Context:
- `upstream/main` was unchanged from the June 27 upstream sync; `git rev-list --count main..upstream/main` was `0` before this work.
- Local `main` was `269c7bb` and was behind `origin/main` by five Whisp fork commits:
  - `47a3079` Apple renderer line-info cache.
  - `85ac8bf` Metal cursor visibility during activity.
  - `8bb4894` viewport-anchored terminal search.
  - `8c7707b` anchored-search reset after manual scroll.
  - `faa1f44` stop anchored search before wrap.

Conflict resolution:
- `Sources/SwiftTerm/Apple/AppleTerminalView.swift`: both sides inserted helper structs after `ViewLineInfo`. Kept the upstream-sync `GlyphSlotFit` struct and the fork `LineInfoCacheEntry` struct.
- No caret math conflict remained in `updateCursorPosition`; the June 27 pending-wrap clamp plus full-width `charUnderCursor.width` behavior was preserved.
- The DEC 2026 synchronized-output live-buffer contract was not conflicted or changed.

Validation:
- `git diff --check --cached` passed.
- `swift test --filter 'LineInfoCacheTests|TerminalViewCursorTests|SearchTests|SynchronizedOutputTests' --no-parallel` passed: 45 Swift Testing tests.
- `swift test --no-parallel` passed: 43 XCTest tests plus 465 Swift Testing tests.

Final state:
- Merge was completed locally.
- No push was performed.
