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
# GitNexus — Code Intelligence

This project is indexed by GitNexus as **SwiftTerm**. Use the GitNexus MCP tools to understand code, assess impact, and navigate safely.

> If any GitNexus tool warns the index is stale, run `npx gitnexus analyze` in terminal first.

## Always Do

- When exploring unfamiliar code, use `gitnexus_query({query: "concept"})` to find execution flows instead of grepping. It returns process-grouped results ranked by relevance.
- When you need full context on a specific symbol — callers, callees, which execution flows it participates in — use `gitnexus_context({name: "symbolName"})`.
- Before editing a symbol that looks load-bearing (exported API, called from many places, referenced in a hot execution flow), run `gitnexus_impact({target: "symbolName", direction: "upstream"})` and surface HIGH/CRITICAL findings to the user. Skip this for cosmetic/local edits (copy, styling, single-file refactors, layout) where the blast radius is obvious.
- Use `gitnexus_rename` instead of find-and-replace for renames — it understands the call graph and avoids missed references.

## Never Do

- NEVER rename symbols with find-and-replace across the repo — use `gitnexus_rename`.
- NEVER ignore a HIGH or CRITICAL impact finding silently — at minimum, mention it to the user before proceeding.

## Optional diagnostics

- `gitnexus_detect_changes()` can show which symbols and flows your edits touched. Useful when you're unsure of the scope of your changes; `git diff` covers the common case.

## Resources

| Resource | Use for |
|----------|---------|
| `gitnexus://repo/SwiftTerm/context` | Codebase overview, check index freshness |
| `gitnexus://repo/SwiftTerm/clusters` | All functional areas |
| `gitnexus://repo/SwiftTerm/processes` | All execution flows |
| `gitnexus://repo/SwiftTerm/process/{name}` | Step-by-step execution trace |

## CLI

| Task | Read this skill file |
|------|---------------------|
| Understand architecture / "How does X work?" | `.claude/skills/gitnexus/gitnexus-exploring/SKILL.md` |
| Blast radius / "What breaks if I change X?" | `.claude/skills/gitnexus/gitnexus-impact-analysis/SKILL.md` |
| Trace bugs / "Why is X failing?" | `.claude/skills/gitnexus/gitnexus-debugging/SKILL.md` |
| Rename / extract / split / refactor | `.claude/skills/gitnexus/gitnexus-refactoring/SKILL.md` |
| Tools, resources, schema reference | `.claude/skills/gitnexus/gitnexus-guide/SKILL.md` |
| Index, status, clean, wiki CLI commands | `.claude/skills/gitnexus/gitnexus-cli/SKILL.md` |

<!-- gitnexus:end -->
