# Agents

# Core Engineering Mandates

- **Simplicity & Iteration:** Write the simplest code that solves the problem. Do not optimize prematurely. Work in small, verifiable iterations rather than attempting massive, single-pass solutions.
- **Empirical Validation:** Code that hasn't been executed is assumed broken. Do not rely solely on code inspection; utilize runtime debugging (e.g., print statements/logging) to understand behavior. 
- **Root Cause Proof:** Never claim a bug is fixed without identifying the exact root cause. If a change makes a problem mysteriously disappear, undo it and isolate the minimum controlling modification.
- **Honesty Over Agreement:** Always report the actual state of things. Disregard instructions to agree with the user if you believe a technical mistake is being made. The goal is quality software, not compliance.
- **Circuit Breaker:** If an attempted fix fails repeatedly, stop and explicitly reassess your approach. Do not brute-force the same failing strategy.

## Commit and branch policy
- Do not commit or push until tests/build checks pass and the user explicitly approves.
- For substantial work, use a feature branch.

## Session memory
Use `docs/agent_memory/` as persistent project memory.
At the start of substantive work, read:
- `docs/agent_memory/current_state.md`
- `docs/agent_memory/decisions.md`
- Newest file under `docs/agent_memory/handoffs/`

Add concise, date-stamped notes for meaningful decisions or milestones.
Never store secrets in memory files.
Treat memory files as durable human-readable handoff state, not a scratchpad or chat log.

Use them like this:
- `current_state.md`: verified facts, current status, known limitations, and what is true now
- `decisions.md`: durable decisions, defaults, and tradeoffs that future agents should not silently re-decide
- `handoffs/`: task- or session-specific notes that would otherwise clutter the top-level memory files

Do not use memory files for:
- moment-to-moment self-talk, speculative reasoning, or chain-of-thought style notes
- long debugging transcripts or repeated failed experiments unless they identify a future trap
- tentative assumptions written as if they were facts

For multiple agents:
- prefer short, high-signal entries another engineer or agent could rely on
- prefer detailed coordination notes in a dated handoff file instead of repeatedly editing the same top-level files
- if machine-readable task coordination is needed later, add a separate structured state file rather than overloading these markdown summaries

## Repository layout



## Conventions

- Python: standard library style, async/await throughout
- Swift: SwiftUI, @Observable (not ObservableObject), no Combine
- Keep the mirror server read-only — it should never write to terminals
- Prefer reviewed `make` targets or scripts for deleting generated artifacts. Avoid hand-typed `rm` commands, especially wildcard deletes; if cleanup is recurring, add or extend a named target instead.
- Commit after each verified fix so regressions are easy to bisect
- If a large batch of changes is worth preserving before it is fully verified, make a checkpoint commit on the branch before continuing
- Keep unrelated local files out of those commits whenever possible

## Troubleshooting Notes

### iOS Networking and Cloudflare
1. **Direct connections:** iOS App Transport Security (ATS) rejects `ws://` connections to non-local IPs (like Tailscale). Always use `wss://` with a custom `URLSessionWebSocketDelegate` to ignore the self-signed certificate.
2. **Cloudflare WebSocket Upgrades:** Cloudflare natively handles the `Upgrade: websocket` flow when bridging a subrequest to a Durable Object. Performing manual strict validation like `request.headers.get("Upgrade") === "websocket"` inside the DO `fetch` handler will throw a 1101 exception (500 Server Error) because Cloudflare strips or modifies the header.
3. **Connection Timeouts:** Silent WebSocket paths will be dropped by Cloudflare after roughly 60 seconds of idle time. Keep the handheld connection alive with a `{"type":"ping"}` heartbeat every 15 seconds, and make sure the server intercepts and ignores it.

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
