# 2026-06-07 Upstream Main Merge Review

Reviewed the 9 commits from Miguel de Icaza's `upstream/main` after local merge base `9446f60`.

Commits:
- `b5ad46c` iOS public `showStandardContextMenu(at:)` wrapper.
- `c356d58` make iOS `TerminalView.deleteBackward()` open.
- `618e43e` merge PR #562.
- `59f3bcc` send Option-composed printable text directly under kitty keyboard protocol.
- `8991462` merge PR #564.
- `d44954c` set iOS `TerminalView.isOpaque = false` to avoid scrollback rendering corruption.
- `b5d6539` merge PR #567.
- `677384e` add missing `SyncDebug.swift`.
- `bf72355` merge PR #554.

Trial merge result:
- Only conflict: add/add in `Sources/SwiftTerm/SyncDebug.swift`.
- Recommended resolution: keep local no-op `SyncDebug.log`.
- Auto-merged upstream code applies cleanly to current local Mac kitty input and iOS terminal view code.

Validation in `/private/tmp/SwiftTerm-upstream-merge-ydpfLn`:
- `swift test --filter KittyOptionComposeTests` passed.
- `swift test --filter SynchronizedOutputTests` passed.
- `swift test --filter SelectionTests/testSelectionTextPreservesAutowrappedLogicalLine` passed.
- `swift test --filter PerformaceTests` passed.
- `swift test --filter KittyKeyboardEncoderTests` passed.
- `swift test --no-parallel` passed: 450 Swift Testing tests plus 43 XCTest tests.
- Plain parallel `swift test` aborted once with signal 6 after missing `timeout-*` fuzzer data-file messages; isolated tests and serial full suite passed.

Applied merge:
- Real merge committed on `whisp/foundation` as `3a1bfaf` (`Merge upstream/main into whisp foundation`).
- Kept local no-op `Sources/SwiftTerm/SyncDebug.swift`; effective committed changes are the two terminal-view files and the new `KittyOptionComposeTests.swift`.
- Post-merge validation passed:
  - `swift test --filter KittyOptionComposeTests`
  - `swift test --filter SynchronizedOutputTests`
  - `swift test --filter KittyKeyboardEncoderTests`
  - `swift test --no-parallel`
