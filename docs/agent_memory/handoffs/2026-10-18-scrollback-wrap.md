# Wrapped scrollback capture retention

Integrated exact candidate `674ad8896e9c7afa80b3fa531dfa46213eecf1b0` into main after final Opus 5.5 ACCEPT and downstream qualification. Base `d45267b` production source is identical to the prior Whisp pin `5e91b9e`. The fork feature branch was published and its exact remote revision verified before downstream builds. This closeout changes documentation only; Whisp keeps the tested candidate pin.

## Original loss and rejected v1

The old `prependScrollbackCapture` used logical newline count both to size a
zero-history scratch viewport and to cap extraction. Wrapped overflow recycled
the earliest physical rows even with destination capacity available.

V1 `6a37554` retained the rows with bounded one-row scratch storage, but final
Opus review rejected its implicit background padding (B1): newly scrolled rows
received active BCE color where tmux and the old parser retain default null
padding. The v1 bottom-row oracle adjustment hid that regression. V1's commit,
original failure receipts and report are preserved; its passing tests are not
acceptance. This record supersedes the earlier v1 handoff's acceptance wording.

## B1 correction

Keep the one-row scratch, history `availableCapacity - 1`, inherited live text
options, and populated extent `yBase + y + 1` bounded by stored rows. A private
flag defaults false and is enabled only on the temporary capture parser. It
selects default attributes for implicit scroll row construction, cache matching
and recycling. Ordinary terminal scrolling and all explicit erases retain BCE.
There is no new public API or option.

Restore a fresh tall oracle starting at row zero, with enough rows for every
input byte plus one and no history. Assert `yBase == 0` and no trimming. Compare
every cell, including null padding: resolved characters, widths, full attributes,
payload presence and wrap flags. The fixed tmux-shaped padding regression is
old-green / v1-red (six issues) / corrected-green with identical test code.
Indexed and RGB padding, explicit colored spaces/EL/ED/ECH/ICH/DCH, capacity-one
recycling, wraps and normal-live BCE controls pass. All original content,
selection, cursor, identity, viewport, reflow and option checks remain.

Capacity intentionally retains the newest physical suffix, including an initial
wrapped continuation. Returned counts are physical rows and may exceed logical
line count. Scratch maxLength/populated-count assertions and the 80,000-character
joined-line test bound storage. Both private captures match the fresh tall
oracle at six widths, including all cell attributes and the original prefix.

## Validation and known native test failure

Focused hydration: 16 Swift Testing functions pass. Selection: 17 XCTest pass;
Mac selection anchor: 35 Swift Testing pass; upstream integration filter:
12 Swift Testing tests in two suites pass. Actual iOS 26.4 simulator:
13 UIKit gesture tests and 16 hydration functions pass. `swift build`,
`git diff --check` and full `swift test --no-parallel` pass (85 XCTest +
914 Swift Testing tests in 81 suites, including all repaint tests).

The ten bounded combined-filter runs were completed without retrying failed
rounds: nine pass, one SIGTRAP 5 in the pre-existing main-queue
`CircularBufferLineList -> visibleBlinkRows -> updateTextBlinkLifecycle` path;
zero SIGSEGV 11, no distinct faults. Root's unchanged `d45267b` baseline has
three such SIGTRAP failures in ten runs. Both isolated repaint attempts (one
initial, one fixed post-classification run) also failed in this same path; these
individual receipts remain failures despite the passing full and combined runs.
No production blink lifecycle fix was attempted. These small samples do not establish
comparative crash rates; the fixture cause and named gate closure are documented below.

Known limits: capture extent assumes sequential text/rendition/charset/OSC 8;
explicit erase compatibility is tested without promising arbitrary cursor-control
reconstruction. The pre-existing OSC 8 target lifetime bug is deferred; payload
presence and rendering are tested, target survival is not fixed. Full-capacity
repeat fetching and host/engine width differences remain separate. No physical
input, human visual or installed-app acceptance is claimed. Downstream compile
qualification completed at closeout below.

## Reviewed fixture gate closure

Opus accepted production `420117d` and identified the repaint fixture race:
the unisolated Swift Testing suite mutates AppKit views/buffers off-main while
`updateTextBlinkLifecycle` dispatches a reader onto main. That reader can use
bounds invalidated by concurrent fixture mutation. The reviewed test-only fix
adds `@MainActor` to `ScrollbackRepaintTests`, without assertion or production
changes, so fixture mutation and the blink reader share main-actor isolation.
This closes the previously red repaint gate; the historical failures above and
the prior reports remain preserved as failures, not retroactively reclassified.

Fixed-count validation after annotation: candidate 5/5 isolated invocations pass
and old `d45267b` plus the identical annotation 5/5 pass (12 tests each). The
root-owned baseline fixture was restored byte-for-byte in `finally` and its
worktree is clean. The single combined filter passes (17 XCTest + 75 Swift
Testing tests in five suites), and the single full `swift test --no-parallel`
passes (85 XCTest + 914 Swift Testing in 81 suites). No gate failed or retried.

Production `Terminal.swift` remains SHA-256
`d781218b3c727a6bd1ac2abe7fe405cad73b7cc6b13e9a77dde2e2939d6dd392`;
UIKit test source is unchanged from `420117d`. Prior private matrix and iOS gates
retain their exact source identity; platform builds were not repeated for this
macOS-only test annotation. No production blink thread-safety repair is claimed.
The coordinator still owns downstream qualification and physical acceptance;
no publication, main merge or re-pin occurred in this worker.

## Coordinator integration and downstream qualification

Final Opus 5.5 closure accepted exact `674ad88`, with production and UIKit hashes unchanged from accepted `420117d`. Whisp all four pins point at that published revision. Isolated WhispMac Debug, generic iOS Simulator Debug, and `make vision-build-check` pass; all three compiled checkouts match the exact candidate revision and Terminal.swift hash above. Full Whisp backend passes 4515 tests (7 skips), support tests 2770 XCTest plus 95 Swift Testing. Those suites exercise unchanged Whisp source trees; actual Xcode builds exercise the changed dependency.

Durable downstream receipts and reviewer closure: `../ai-whisperer/docs/agent_memory/handoffs/2026-10-18-scrollback-wrap/` from the sibling checkout root. Local detailed reports remain under `../ai-whisperer/untracked/agent-work/2026-10-18-scrollback-wrap/`; private capture payloads are not committed. Final diff/scope audit is clean; canonical GitNexus comparison uses the d45267b baseline index and direct caller audit. The index becomes stale after integration; source/test/build receipts remain authoritative.

Following the Whisp `eadabfba` rebuild handoff, Karl reported on 2026-10-18 (local): “yep, scrollback worked all the way to the top”. Physical iPad normal-mode Real Cello access is field accepted for the reported cutoff. This is user-reported installed behavior; no separate binary readback or reconnect-during-fetch acceptance is claimed. Production/external-beta publication remains held; no app relaunch, install, live-pane reset or release was performed during this repair. Branch state is removed after integration; retained worktrees and logs are not deleted.
