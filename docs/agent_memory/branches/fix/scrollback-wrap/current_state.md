# Branch state: fix/scrollback-wrap

- V1 `6a37554` is preserved but rejected for B1 background padding; its bottom-row oracle hid the regression and is superseded by the fresh tall non-scrolling oracle.
- Corrected candidate retains bounded physical rows and uses default implicit row attributes only in the private capture parser; explicit erases and live BCE stay unchanged. Old/v1/new padding gate is green/red/green.
- Hydration/private matrix/iOS 26.4/build/full suite (85 XCTest + 914 Swift Testing) pass; ten combined native runs have nine passes and one known-path SIGTRAP. Both isolated repaint runs fail in that baseline path; see [handoff](../../../handoffs/2026-10-18-scrollback-wrap.md).
- OSC 8 target lifetime, native blink test reliability and full-capacity repeat fetching remain open; no physical-device/visual acceptance.
- Not pushed, merged to main or re-pinned; coordinator owns fresh review and downstream qualification.
