# SwiftTerm Agent Guide

This is the canonical repository instruction file for every AI assistant.
`CLAUDE.md` points here; keep substantive guidance in this file rather than
forking policy into vendor-specific files. A more specific `AGENTS.md` takes
precedence within its directory. Do not edit generated dependency checkouts.

## Engineering principles

- Prefer the simplest implementation that completely solves the observed
  problem. Avoid speculative abstractions and unrelated cleanup.
- Establish the root cause before claiming a fix. If a change merely makes a
  symptom disappear, keep investigating until the controlling behavior is
  understood.
- Treat unexecuted code as broken. Validate behavior empirically at the
  cheapest seam capable of catching the plausible regression.
- Work in reversible, verifiable increments. When the model of the system is
  uncertain, reduce the step size and add a focused probe or test.
- Preserve user and concurrent-session changes. Recheck `git branch` and
  `git status` immediately before staging or committing.
- Stop and reassess after repeated failed fixes or a nearby regression. Do not
  stack speculative changes on top of a disproven explanation.
- Report what the evidence establishes. Distinguish source tests, compiled
  artifacts, runtime exercises and physical-device or visual acceptance.

## Standard workflow

1. Read `docs/agent_memory/current_state.md` and the current branch state file,
   if one exists under `docs/agent_memory/branches/<branch>/current_state.md`.
2. Inspect live Git status. Treat pre-existing changes as owned by the user or
   another session unless provenance is known.
3. Grep `docs/agent_memory/decisions.md` only for the subsystem being changed;
   do not read it wholesale.
4. Identify the smallest testable seam and proportional validation before editing.
5. Implement, run focused validation early, then run the broader gates required
   by the change's blast radius.
6. Review the final diff for accidental scope, generated files, weakened
   assertions and stale names or documentation.

## Tests and coverage

Testing is part of implementation, not a cleanup phase.

- Add or update a regression test for each behavior change when a stable,
  deterministic seam exists. A bug fix should fail under the old behavior and
  pass under the new behavior.
- Cover meaningful branches, boundaries, state transitions and failure/recovery
  paths affected by the change. Prefer assertions about behavior over private
  implementation details.
- Use coverage to find unexercised behavior, not as a substitute for strong
  assertions. Do not add tests solely to inflate a percentage.
- Never delete, skip or loosen a test merely to make a change pass unless the
  product contract changed; explain that change in the same diff.
- Run focused tests first. Run the full affected suite before integrating
  cross-cutting work or merging executable changes to `main`.

Validation tiers:

- Documentation or non-executable copy: inspect references and the diff; no
  automated test is required.
- Compiled presentation-only changes: build the affected target and state what
  still needs a human visual check.
- Small behavior changes: focused `SwiftTermTests` plus an exercise of the
  changed path when practical (native fixture, TerminalApp or a consuming app).
- Cross-cutting work or executable changes merged to `main`: `swift build`,
  full `swift test --no-parallel`, and behavior validation proportional to risk.
- Public API, shared Apple-view or renderer changes: also build affected
  downstream targets/platforms against the exact candidate revision.
- Renderer/performance changes: run the relevant `Benchmarks/` comparison.
  Row caches, draw data and invalidation are hot paths; measure before/after.

Useful commands (run from the repository root):

```bash
swift build
swift test --no-parallel --filter <TestCase>
swift test --no-parallel
swift test --no-parallel --enable-code-coverage --filter <TestCase>
git diff --check
```

AppKit tests exercise native state; avoid parallel test execution for those
suites. Metal renderer tests require real Metal hardware. Headless or simulator
passes do not establish Metal rendering or visual/physical-input acceptance.

## Git, branches and worktrees

- Commits are autonomous after proportional verification. Stage explicit files;
  never use `git add -A` in a shared checkout.
- Small, low-risk changes may be committed on `main`. Substantial or risky work
  belongs on a feature branch in its own worktree. Create it from the primary
  checkout with `git worktree add -b <branch> <sibling-path> main`.
- Do not move unrelated dirty changes into a worktree or include them in a
  commit. If work overlaps an unknown edit, inspect and preserve both intents
  or ask for direction when they cannot be reconciled.
- Merging to `main` is autonomous after the applicable integration gates pass.
- Pushing verified work to `origin` is autonomous. Push promptly after
  verification; do not wait to be asked. If the remote has advanced, fetch and
  integrate it, then rerun affected gates on the combined result before pushing.
- Updating downstream dependency pins is autonomous when it is part of the
  task. Publish the exact verified fork revision first, verify it is reachable
  from the remote, then update the downstream manifest and lockfile together
  and run that repository's applicable checks. Follow downstream instructions;
  a local dependency cache is not proof of remote availability.
- Upstream integration is autonomous within the requested task scope. Work in
  an isolated branch, follow the release-selection decisions in
  `docs/agent_memory/decisions.md`, preserve fork behavior and validate the
  combined result before merging and pushing. There is no separate approval
  gate merely because the change is an upstream merge.
- `origin` is `lehenbauer/SwiftTerm`; `upstream` is
  `migueldeicaza/SwiftTerm`. Keep downstream dependencies pinned to exact
  revisions rather than moving branches. Preserve already-qualified revision
  identities instead of rewriting them during publication.
- Publishing releases or distribution artifacts, deployments and destructive
  actions still require user authorization. Authorization already given for
  the task persists; do not ask again for the same action. Ordinary verified
  source commits, merges, pushes and in-scope re-pins use the autonomous rules
  above.
- Never discard user history or unrelated work with `reset --hard`, broad
  checkout, clean or equivalent destructive commands.

Use isolated build output where needed to avoid replacing a running app's
bundle. Before removing a worktree, check that no running app or process relies
on it. Use `git worktree remove <path>` only after preserving needed work and
artifacts. Use reviewed Make targets or `swift package clean` for generated
build cleanup; avoid hand-written recursive or wildcard deletion.

## Session memory

Use `docs/agent_memory/` as durable shared state, never a scratchpad or chat log.
Never store secrets there.

- Put temporary briefs, reports and logs under
  `untracked/agent-work/YYYY-MM-DD-topic/`, not the repository root. Promote
  durable evidence to `docs/agent_memory/handoffs/YYYY-MM-DD-topic/` at closeout.
- `current_state.md` is the bounded snapshot of `main`: update facts in place,
  keep it under roughly 100 lines and link to handoffs for narrative.
- `branches/<branch>/current_state.md` records substantial branch work. Remove
  it after integration once globally relevant facts are promoted.
- `decisions.md` records constraints future agents might accidentally undo.
  Keep entries short, grep by topic and supersede stale decisions in place.
- `handoffs/` holds dated long-form evidence and integration records. Prefer
  one synthesized handoff per task; do not duplicate raw conversation history.
- Memory edits ride the closing code commit. A small memory-only closeout
  commit is appropriate when no code change remains.

## Repository map and conventions

```text
Sources/SwiftTerm/       Terminal engine and Apple platform views/renderers
Sources/SwiftTermFuzz/   Fuzzer entry point
Sources/CaptureOutput/  Output-capture helper
Sources/Termcast/       Terminal session recording
Tests/SwiftTermTests/   Swift package tests
Benchmarks/             Renderer and terminal performance comparisons
TerminalApp/            Sample apps for native exercises
```

Prefer additive public-API changes; downstream applications may expose breaks
that package tests do not. Keep terminal behavior and platform-view behavior
separate where practical, and exercise the actual affected platform bridge.

`make build-fuzzer` requires the separate Swift toolchain named in the Makefile.
`make clone-esctest` fetches the optional esctest suite. Distinguish unavailable
optional fixtures from tests that actually ran.

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
