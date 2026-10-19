# Branch state: fix/scrollback-wrap

- Repairs physical wrapped-row retention in `prependScrollbackCapture` with scratch storage bounded by destination free capacity; based on `d45267b`.
- Exact-source red/green, six-width private corroboration, focused tests, full package tests (85 XCTest + 910 Swift Testing), build and actual iOS 26.4 UIKit/hydration tests pass; see [handoff](../../../handoffs/2026-10-18-scrollback-wrap.md).
- OSC 8 target lifetime and full-capacity repeat fetching remain explicitly deferred; no physical-device/visual acceptance.
- Not pushed, merged to main or re-pinned; coordinator owns final review and downstream integration.
