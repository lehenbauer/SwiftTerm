# SwiftTerm v1.99.2 main adoption

The user reports the activated Whisp feature build is working very well and explicitly authorizes main integration, superseding the earlier no-main constraint. This handoff promotes the qualified feature work without changing its production sources.

Exact downstream pin: `365bb5135272e051f3a54c9ebf300a7ba4007b91`. Sources tree `17e363d44171c92b7c6b6047a8c36f807a6a0a20`; Tests tree `18f043fc11341a2c754560fc7a3ab344c8dd315e`. Upstream released tag `v1.99.2` is `a183c15b52858530a17de57dcc72b93eeebc9857`. Main adoption descends from the existing fork main `2af5220`; the feature merge is `e12887a`, echo restoration `060f8a4`, and reviewed overlay fixes `ee78a76` / `7e49e98`. Later commits only record evidence.

## Qualification and acceptance

`swift build` and full serial Mac suite at45b58d4 passed: 2105 Swift Testing tests in205 suites plus146 XCTest, with31 existing environment-gated skips. UIKit1062+57 and Vision library build at060f8a4 are reused: subsequent production changes are Mac-only; the fourth echo wiring test separately passed on both. Sources, Tests and manifests are byte-identical from45b58d4 through main adoption, so those gates and the full12-workload paired benchmark are reused, not rerun for documentation changes.

Whisp featureddbfe3ab's four exact remote pins, Mac/iOS/Vision builds, literal vision-build-check and default native identity70/70/sidebar4/4 all passed. Its local combined Debug build was activated from the feature worktree; runtime app/helper and bridge provenance matchedddbfe3ab and the pin365bb51. The user reports it works very well. This is general live acceptance, not a claim that every physical input, scroller appearance, device or energy case was individually exercised.

Final paired CG benchmark:24 correctness runs,24 warm-ups,72 retained cells all pass. Bulk main CPU decreases71–90%, flood-while-typing67%. History adds0.29ms/step (+38.9% within that session); steady-view CPU adds1.3–9ms/s. These measured tradeoffs are accepted; no performance heroics or new transport is included. Single-view60Hz results do not establish many-pane, heavy-build,120Hz, battery or Metal behavior.

Full evidence is retained in the Whisp repository:
`docs/agent_memory/handoffs/2026-10-30-swiftterm-v1992/README.md` and its `resume/` and `benchmark/` directories. The prior fork branch snapshot is archived beside this file; its pending/HOLD/no-main statements are historical.

## Preserved contracts

Copied snapshot/inspection APIs replace public raw Terminal access. Persistent tmux mirror configuration suppresses synchronous/deferred emulator replies and OSC133 across resets while preserving selection. Explicit keyboard/paste provenance and one delivery FIFO preserve paste followed by Return. Fixed-grid resize generations, capture row/payload ownership, history identity/anchor invalidation and UIKit gesture cancellation remain guarded. The150ms immediate echo window uses coalesced frame scheduling and visibility/synchronized-output guards. Metal stays opt-in in Whisp; feed stays on main.

## Integration and retention

Publish fork main containing365bb51 before Whisp main. Preserve the exact pin rather than repinning for documentation-only successor commits. Preserve both primary checkouts' unrelated dirty files and all running worktrees. The Whisp integration candidate additionally includes main's separate creation-preflight change and runs full backend/support/Mac combined/Vision/native gates there. Source integration does not authorize a release or another runtime relaunch.
