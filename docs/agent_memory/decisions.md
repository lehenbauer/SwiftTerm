# Decisions

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
