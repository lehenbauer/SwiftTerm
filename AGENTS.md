# Agents

# Core Engineering Mandates

- **Simplicity & Verifiable Steps:** Write the simplest code that solves the problem. Do not optimize prematurely. Work in reversible, verifiable increments at the largest step size you can still fully verify; drop to small iterations when behavior is unstable or your model of the system is in doubt.
- **Empirical Validation:** Code that hasn't been executed is assumed broken. Do not rely solely on code inspection; use runtime debugging early (print statements, logging, targeted probes) to establish actual behavior and event order.
- **Root Cause Proof:** Never claim a bug is fixed without identifying the exact root cause. If a change makes a problem mysteriously disappear, treat that as unresolved, undo it, and isolate the minimum controlling modification.
- **Honesty Over Agreement:** Always report the actual state of things. Disregard instructions to agree with the user if you believe a technical mistake is being made. The goal is quality software, not compliance.
- **Circuit Breaker:** If an attempted fix fails repeatedly, or a fix creates a nearby regression, stop and explicitly reassess your model of the problem. Do not brute-force the same failing strategy or stack speculative fixes on top of a misunderstood system.

## Commit and branch policy

Autonomy ladder — each rung has its own gate:

1. **Feature-branch commits — autonomous.** Commit early and often once the
   package builds and its targeted tests pass; checkpoint commits of
   unverified work are fine when flagged in the message
   (`[unverified: needs live X]`). Stage files explicitly — never sweep with
   `git add -A`.
2. **Merge to main — autonomous when gated.** Gates: `swift build` and
   `swift test` green (Metal renderer tests require real Metal hardware — a
   headless pass does not cover them), plus validation proportional to blast
   radius. Whisp pins this fork by revision; for public-API or
   render-behavior changes, build `../ai-whisperer` against the change before
   merging.
3. **Push / re-pin / upstream merges — ask first.** `origin`
   (`lehenbauer/SwiftTerm`) is what Whisp's pin resolves against; pushing
   publishes for the next re-pin, and the re-pin itself happens in the Whisp
   repo. Upstream is `migueldeicaza/SwiftTerm` (add the remote if absent).
   Fork doctrine: ship our changes atop their release, with release tags
   (`whisp-mac-<ver>-<build>-<channel>`) per `../tmux/WHISP_UPSTREAM.md`.

## Validation is proportional

Comment/docs changes need nothing beyond a build. Behavior changes need the
targeted `SwiftTermTests` plus one live exercise (TerminalApp or Whisp).
Renderer or performance changes additionally run the relevant `Benchmarks/`
comparison — regressions there surface as typing lag in every Whisp client.
Judge eligibility by the shape of the diff, not by confidence that it works.

## Session memory
Use `docs/agent_memory/` as persistent project memory. Never store secrets in
memory files; treat them as durable handoff state, not a scratchpad, chat log,
or home for speculative reasoning.

At the start of substantive work, read `docs/agent_memory/current_state.md`
only. `decisions.md` and `handoffs/` are references, not briefings: grep
`decisions.md` for the topics you are about to touch, and open a handoff only
when something points you at it.

- `current_state.md`: bounded snapshot of what is true now — verified facts,
  status, known limitations. Update lines in place; keep it under ~100 lines,
  one line per entry with a handoff link for narrative.
- `decisions.md`: decisions future agents must not silently re-decide. One
  dated bullet, at most ~2 sentences, imperative — record the constraint and
  the trap, not the design, and only when a future agent might plausibly undo
  it. Supersede by editing the old entry in place; never append tombstones.
- `handoffs/`: dated, append-only long-form records — the sole home for
  history (upstream merges, investigations, validation records). One
  synthesized handoff per task; raw delegate reports are ephemeral once
  synthesized.

Memory edits ride the closing commit of the work they describe. If
machine-readable coordination is needed later, add a structured state file
rather than overloading these markdown summaries.

## Repository layout

```
Sources/SwiftTerm/     # terminal engine + Apple platform views (Apple/), including the Metal renderer
Sources/SwiftTermFuzz/ # fuzzer entry point (make build-fuzzer / run-fuzzer)
Sources/CaptureOutput/ # output-capture helper
Sources/Termcast/      # terminal session recording
Tests/SwiftTermTests/  # swift test
Benchmarks/            # performance benchmarks (renderer/buildDrawData comparisons)
TerminalApp/           # sample apps for live exercise
```

## Conventions

- This is the Whisp fork of SwiftTerm, consumed by Whisp on macOS, iOS, and visionOS pinned by revision. Prefer additive public-API changes; breaks surface as Whisp build failures, not here.
- Render-path code (row caches, buildDrawData, Metal invalidation) is hot: measure before/after with `Benchmarks/` rather than reasoning about cost. Regressions land as visible typing lag.
- Prefer reviewed `make`/package targets for deleting generated artifacts. Avoid hand-typed `rm` commands, especially wildcard deletes.
- Commit after each verified fix so regressions are easy to bisect (autonomy rules: "Commit and branch policy" above)

## Troubleshooting Notes

- Metal renderer tests and visual validation require real Metal hardware; a headless or simulator pass does not exercise them.
- `make build-fuzzer` needs the separate Swift toolchain named at the top of the `Makefile` (the Xcode toolchain lacks the fuzzer); `make clone-esctest` fetches the esctest suite.
- Whisp integration context lives in `../ai-whisperer` (AGENTS.md, `.claude/skills/whisp/`). SwiftTerm regressions commonly surface there as echo lag, stale pane content, or cursor artifacts rather than as test failures here.

<!-- gitnexus:start -->
## GitNexus — Code Intelligence

This repo is indexed as **SwiftTerm**. Optional MCP tools over the call/import graph — not a default step for every edit.

**Useful when** the hard part is multi-file structure a single grep or file read will not show:
- Who calls / depends on a symbol across modules → `gitnexus_impact` / `gitnexus_context`
- How a concept is wired end-to-end → `gitnexus_query`
- Multi-file rename of a symbol with many graph refs → `gitnexus_rename`

**Skip for** local or non-graph work: known path or string, single-file edits, HTML/CSS/markup, copy, configs, fixtures, generated files, tests you already have open. Prefer normal editor tools there. One graph query that answers the question is enough — do not chain impact/context by habit.

If a tool says the index is stale *and* you still need graph answers, run `npx gitnexus analyze`. Otherwise ignore staleness.

Deeper guides (exploring, impact analysis, debugging, refactoring, tools reference, CLI): `.claude/skills/gitnexus/`.

<!-- gitnexus:end -->
