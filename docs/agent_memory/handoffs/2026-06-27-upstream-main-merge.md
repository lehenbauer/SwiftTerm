# 2026-06-27 Upstream Main Merge

Merged Miguel de Icaza's `upstream/main` at `9adb624` into local `main` as `269c7bb`.

Incoming commits after merge base `a3b8c9b`:
- `ebc6ca2` Force text presentation for default-text emoji-capable symbols.
- `6e5dcf2` Merge pull request #575.
- `bb8423d` Mac word-mode drag selection preserves the seed word when dragging backwards.
- `7af5db2` Merge pull request #576.
- `ab99ba3` Center full-width CJK glyphs within their cell/caret in CoreGraphics and Metal.
- `9adb624` Fix synchronized-output test after DEC 2026 buffer-snapshot removal.

Conflict resolution:
- `Sources/SwiftTerm/Apple/AppleTerminalView.swift`: both sides edited `updateCursorPosition`. Kept the fork's pending-wrap `cursorColumn` clamp, then used that clamped column to read `charUnderCursor`, position the caret, and apply upstream's full-width `cursorColumnWidth` sizing.
- `Tests/SwiftTermTests/SynchronizedOutputTests.swift`: upstream and local both updated the first DEC 2026 test. Kept upstream's clearer live-buffer contract and flag assertions, preserved the fork's view-layer synchronized-output tests, and renamed a stale "both live and frozen buffers" test/comment to describe the live display buffer.

Assessment:
- The synchronized-output test change helps this fork: it documents and tests the current architecture where mode 2026 toggles `synchronizedOutputActive`, the core buffer remains live, and `AppleTerminalView.updateDisplay` blocks rendering while sync is active.
- The glyph centering changes overlap with the fork's pending-wrap caret fix only at the CoreGraphics caret placement lines; the correct combined behavior is clamped cursor column plus width-aware caret.

Validation:
- `swift test --filter 'SynchronizedOutputTests|SelectionTests|UnicodeTests|BufferTests|TerminalViewCursorTests' --no-parallel` passed.
- `swift test --no-parallel` passed: 43 XCTest tests plus 457 Swift Testing tests.

Final state:
- `git rev-list --count main..upstream/main` returned `0`.
- No push was performed.
