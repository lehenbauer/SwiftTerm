# Decisions

## 2026-06-27

- For the upstream full-width glyph centering merge, resolve `AppleTerminalView.updateCursorPosition` by using the fork's clamped `cursorColumn` everywhere the caret indexes/positions the cursor, while also applying upstream's `charUnderCursor.width` sizing so full-width cells get a full-width caret.
- DEC synchronized output mode 2026 should be treated as a live-buffer core mode in this fork: the core toggles `synchronizedOutputActive`, `displayBuffer` mirrors `buffer`, and display blocking belongs in the view layer. Do not reintroduce a frozen core buffer snapshot when resolving future upstream test conflicts.

## 2026-06-07

- For the June 2026 upstream merge, prefer resolving `Sources/SwiftTerm/SyncDebug.swift` by keeping the local no-op implementation. Upstream's added version describes a host-app opt-in trace, but `enabled` is a `static let false` on an internal enum, so it is not a usable public toggle and adds dead stderr logging machinery.
