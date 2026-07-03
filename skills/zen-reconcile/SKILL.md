---
name: zen-reconcile
description: >
  Invoke autonomously when an increment of behavior is finishing in a IMPLICATION→MACHINE-governed
  project, or whenever the IMPLICATION→MACHINE Stop-hook gate fires ("[IMPLICATION→MACHINE] ... reconcile decision"),
  or before claiming anything "done" (closing the turn-end checklist). Verifies contract ∧ tests ∧ docs ∧
  code all agree, fixes any gap, verifies against reality, marks the clause verified —
  or waives with a one-line reason for a no-behavior-change edit. Also /zen-reconcile.
---

# zen-reconcile

The Definition-of-Done check (`zen.md`). "Done" requires all four to agree.

## Procedure

1. **Scope the change.** What did this increment actually modify? (the diff)

2. **Trivial?** No behavior change (comment, rename, formatting)? → **waive**: state
   in one line why no contract/test/doc move is needed. Match effort to blast radius.
   Done.

3. **Otherwise reconcile the four:**
   - **Contract** — a `C-xxx` clause describes this behavior, and its status/text are
     current. Missing or stale → fix via `/zen-contract`.
   - **Tests** — edge cases + correctness, asserting on **exact outputs** (not
     `!isEmpty` liveness), passing. Missing → write them now.
   - **Docs** — user-facing text/help/README matches the new behavior. Missing → update.
   - **Code** — implements the clause, nothing more.

4. **Sweep implications — don't just fix what you touched (C-037).** A change can redefine what
   a behavior *means*, silently turning other clauses, docs, messages, and activation criteria that
   described the OLD meaning into lies — or putting the change in **contradiction** with a load-bearing
   clause. The gate sees neither (every link still resolves; §7's limit). Sweep what this change
   implicates and resolve each **this same turn** (not a future ticket):
   - **Real redefinition → SPAWN the `zen-implications` subagent** (`agents/zen-implications.md`) — do
     NOT confront the change yourself. Hand it the redefined clause; a **fresh context** that did not
     write the change reads the whole contract + recipes + docs and surfaces what the change implicates
     (a stale reference, a contradiction with a load-bearing clause, a near-duplicate, a gap). Confronting
     it **inline** is the trap that defeats the check: the context that just made the change shares its
     blind spots — it catches the obvious ripples and misses the ones that share no word with the change.
     This is the same author-bias `zen-refuter` removes for tests, here for the contract; the independent
     read is the whole point, so spawn it, don't simulate it. Its method is a **full read** of every
     clause, not a grep — the deepest implication shares no term with the change (same behavior, different
     word), which a grep cannot find.
   - **Small change → sweep inline:** `git grep -n` the changed clause id and its key terms; but if the
     behavior is central, read the clause list too — grep only catches shared words.
   - **Direction is not pre-decided.** A *stale reference* → fix it to conform. A *contradiction with a
     load-bearing clause* → do NOT rewrite the old side; **classify it via `zen-failure`** right here
     (§3/§12: "contract wins" is rebuttable — the new change may be the bug, not the old clause).

5. **Verify real.** Run the actual tests/build at the gate. Real deps, real inputs,
   outputs inspected. Never weaken a test or mock around a failure to reach green.

6. **Mark verified.** For a **behavioral** change, record the adversarial-refute verdict FIRST:
   spawn `zen-refuter` (step 4-bis / C-035), then `zen-record-refute.js --clause C-xxx --verdict
   holds|trivial` — the Stop-gate **blocks** a newly-`verified` clause without a fresh `holds`/`trivial`
   record (C-041), the same wall run-evidence puts up. Then `zen verify <C-xxx>` checks the linked test
   resolves AND its recorded run is fresh before it writes `Status: verified`. Fallback if `zen` is
   unavailable: record the run (`zen-record-run.js`) + the refute, then set `Status: verified` and link
   the test by hand.

7. **Report the decision** explicitly: *reconciled* (list what moved with the code)
   or *waived* (the reason). This is what the Stop-hook gate is asking for.
