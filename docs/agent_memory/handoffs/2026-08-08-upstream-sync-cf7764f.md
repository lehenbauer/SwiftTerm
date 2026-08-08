# 2026-08-08: Upstream sync — merge migueldeicaza/SwiftTerm `cf7764f` (52 commits)

## Summary

Merged `upstream/main` at `cf7764f` into fork `main` (previous tip `2fe8a44`,
merge base `9adb624`). The merge commit is `affe8412`
(`Merge upstream/main into Whisp SwiftTerm (trial)`), followed by plain commit
`b2c68bc` (`Preserve selections when prepending scrollback`). Campaign run by
a Fable coordinator with four Codex (`gpt-5.6-sol`) delegate workers:
intake analysis, trial merge, validation gates, perf root-cause, plus a
selection fixlet and a test-client build. Full delegate reports preserved in
`untracked/upstream-sync-20260807/`.

## What came in (highlights)

- Full BiDi/Arabic/Hebrew support (terminal-wg escapes): new public
  `BidiSupportMode`/`BidiDirection`/`BidiPresentationState`/`BidiHostPolicy`,
  `BufferLine.bidiState` + mutation generation, CoreText/Metal visual
  reordering, identity/content layout caches, `Tools/BidiHarness` and
  `Tools/RenderBench`.
- Metal fixes we wanted: `Bundle.module` packaged-app crash fix (safe
  candidate-probe loader), unbounded BufferPool growth fix (power-of-two
  classes), glyph-atlas overflow recovery (bounded retry/freeze).
- Korean IME (Hangul) transaction series; new `HangulInput.swift`.
- DECCOLM now requires private mode 40 (xterm parity) — default-off helps
  Whisp's pinned grids.
- EL/DCH preserve soft-wrap boundaries; parser hardening (shared VT500 table,
  param caps); TinyAtom thread safety + public payload lifecycle; implicit-link
  regex backtracking fix; sixel crash fix; line-accurate macOS scroll wheel
  with public sensitivity; macOS 26 shared mouse-moved monitor;
  selection-foreground color (new black-on-teal defaults); selection
  translation on in-place scrolls (`dcd9a32`); host-app profile initializers.

## Conflict resolution (8 files, all resolved combining both sides)

Record with per-file detail: `untracked/upstream-sync-20260807/REPORT-trial-merge.md`.
Key compositions:

- `AppleTerminalView.swift`: fork pending-wrap clamp feeds upstream's BiDi
  `logicalToVisualCol` caret mapping (upstream indexed raw `buffer.x`, an OOB
  hazard under pending wrap); initial geometry + `autoResizeGrid` gates kept.
- `MetalTerminalRenderer.swift`: row-cache validity composes fork line-info
  generations + per-line invalidation + upstream `bidiParagraphRevision`;
  cursor activity stays a per-frame draw input, not a cache key. The SwiftPM
  resource loader gained a swift-test sibling-bundle probe (documented inline)
  after upstream's search failed under Swift Testing.
- `iOSTerminalView.swift`: fork `UIEditMenuInteraction` retained alongside the
  full Hangul series and upstream's manual-scroll state machine; fork-public
  scroll delegate hooks preserved as wrappers.
- `Buffer.swift` docs: kept the fork's non-monotonic `linesTop` contract
  (hydration decrements it) over upstream's "monotonic" wording.

## Validation record

- `swift build`, `swift test --no-parallel` (654 tests / 63 suites + XCTest,
  0 failures, real Metal hardware) — on the merge and again on `b2c68bc`.
- `../ai-whisperer` `make mac-client` green against the merge via temporary
  local `file://` pin (restored, hash-verified).
- Benchmarks (`Benchmarks/SwiftTermBenchmarks`, isolated wrapper because the
  target is disabled in `Package.swift`): trial vs main p50 +3.06% /
  +4.37% (noise <=1.63%). Root-cause (REPORT-perf-rootcause.md): the cost is
  upstream-inherent (pure `cf7764f` vs `9adb624`: +3.50%/+3.94%), caused by
  `db31f3a` BiDi paragraph-state bookkeeping on the ASCII LF/wrap/scroll path;
  ablating those 19 sites recovers ~3%. No behavior-preserving guard exists
  (equality-check guard measured as a wash; default mode is `.implicit`, not
  disabled). Cost accepted; see decisions.md.
- Selection fixlet `b2c68bc`: `prependScrollbackCapture` now translates
  registered selections via `selectionsAdjustForInPlaceScroll(top:0, bottom:
  lines.count-1, lines:-inserted)`; 3 new tests in `SelectionScrollTests`.
- Live exercise: TerminalApp smoke (fixlet worker) + Karl's Whisp mac-client
  feel test (client built against `b2c68bc` via local pin).

## Deferred / follow-ups

- RenderBench needs a GUI session; not yet run. Candidate for the live-test
  session or a later baseline.
- BiDi zero-overhead-when-disabled fast path: design a mode-gated skip of
  `bidiState` propagation and offer upstream. Not started.
- Upstream tracks `Tools/BidiHarness/Scripts/__pycache__/*.pyc`; deliberately
  NOT stripped locally (divergence cost > hygiene win). Expect upstream to fix.
- Whisp adoption (push + pin flip in ai-whisperer) is a separate campaign.
