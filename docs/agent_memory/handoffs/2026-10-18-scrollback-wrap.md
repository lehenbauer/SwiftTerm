# Wrapped scrollback capture retention

Branch `fix/scrollback-wrap`, based on docs-current `d45267b` (production
source identical to `5e91b9e`). Integration and downstream builds remain with
the coordinator; this worker did not push, merge to main or change pins.

`Terminal.prependScrollbackCapture` used logical newline count both to size a
zero-history scratch viewport and to cap extraction. Wrapped overflow recycled
the earliest rows before insertion even when destination history had space.
The repair copies live `TerminalOptions`, overrides geometry to one row at the
current columns and history to remaining capacity minus one, then extracts
through `yBase + y + 1` bounded by stored rows. Final blank rows remain real.

Scratch storage is bounded by destination free capacity. Debug assertions check
scratch `maxLength` and populated count; an 80,000-character joined-line test
exercises capacity two. Capacity truncation intentionally retains the newest
physical suffix, including an initial wrapped continuation. Return values count
physical inserted rows and can exceed the number of logical capture lines.
Existing insertion, live-row identities, selection translation and viewport
bookkeeping are unchanged.

Synthetic regressions compare resolved characters, widths, all `Attribute`
fields, payload presence and wrap flags against ordinary feed in a spacious
multi-row terminal. The reference starts at the bottom row so continued rows
receive the normal scroll-time erase background, rather than the background of
preallocated initial viewport blanks. No cell comparison excludes blank cells.
Coverage includes Unicode, charset, SGR, OSC 8 rendering, inherited regional
indicator/tab/EOL options, blank/trailing/exact-width rows, bounded suffixes,
repeated prepends, selection and parked viewport, and reflow after truncation.

Validation: exact old production source fails the final 12 hydration tests with
30 issues; the candidate passes those same tests. Both private captures match
all cells and wraps at six widths and retain the original prefix with ample
capacity. Focused selection (17 XCTest), repaint (12 Swift Testing), Mac press
anchor (35 Swift Testing) and upstream buffer integration gates pass. Full
`swift test --no-parallel`: 85 XCTest + 910 Swift Testing tests pass;
`swift build` and `git diff --check` pass. iOS 26.4 simulator executes 13 UIKit
scrollback gesture tests plus 12 hydration tests successfully, including a new
wrapped-prepend test covering drag, coast and idle through the public view API.

The first combined focused macOS run crashed in the main-queue text-blink
callback (`visibleBlinkRows` reading `CircularBufferLineList`); the isolated
repaint gate and subsequent full suite pass. No unrelated lifecycle repair was
attempted. The iOS 26.5 launch failed at SimLaunchHostService; the installed
26.4 runtime successfully runs the tests. These original failures are retained
in the coordinator's implementation receipts.

Known limits: capture extent assumes sequential text/rendition/charset/OSC 8,
not arbitrary cursor-moving captures. The pre-existing OSC 8 payload lifetime
bug is explicitly deferred: visible text/rendition and payload presence are
covered, hydrated link target survival is not fixed. Capacity-full repeated
zero-insert fetching and host/engine Unicode-width differences remain separate.
Simulator/native state tests do not establish physical-device or human visual
acceptance. Fresh final review and downstream compile gates remain outstanding.
