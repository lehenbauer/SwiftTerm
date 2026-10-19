# Branch state: fix/scrollback-wrap

- V1 `6a37554` is preserved but rejected for B1 background padding; its bottom-row oracle is superseded by the fresh tall non-scrolling oracle. Opus accepted corrected production `420117d`.
- Corrected parser retains bounded physical rows and default implicit padding; explicit erases/live BCE stay unchanged. Old/v1/new padding gate is green/red/green; prior private matrix and iOS gates retain exact accepted source identity.
- Reviewed test-only `@MainActor` on `ScrollbackRepaintTests` closes its off-main fixture/main-queue blink-reader race: five candidate and five old+annotation isolated runs pass; baseline restored clean. Single combined/full suites pass (full: 85 XCTest + 914 Swift Testing); see [handoff](../../../handoffs/2026-10-18-scrollback-wrap.md).
- Historical native failures and all prior reports remain preserved. Production Terminal.swift/UIKit tests unchanged; no production blink repair or physical-device/visual acceptance.
- OSC 8 target lifetime and full-capacity repeat fetching remain deferred. Not pushed, merged to main or re-pinned; coordinator owns downstream qualification.
