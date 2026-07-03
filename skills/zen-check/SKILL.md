---
name: zen-check
description: >
  Invoke autonomously when you need to know where a IMPLICATION→MACHINE-governed project stands —
  before a release, when picking up work, or whenever drift is suspected. Read-only
  status/drift audit of the contract: clauses pending vs verified, clauses lacking a
  test, stale statuses, unpromoted P-xxx deltas, code with no clause. A status report,
  NOT a test runner. Also callable as /zen-check.
---

# zen-check

The drift mirror (`zen.md`). Reports the gap between contract and reality;
it does **not** run the test suite as a gate (that's `/zen-reconcile`'s job). It may
*read* the last results, but its product is the map.

## Procedure

1. **Read the contract's state.** Run `zen status` / `zen list` / `zen drift` — the
   deterministic CLI shares the gate's parser, so its report matches the gate's verdict.
   (`zen list --json` for machine output; if bare `zen` is not on PATH, use the invocation
   the session-start index emits — `node <plugin>/bin/zen.js <cmd>`; only with no CLI at all
   read `.zen/contract.md` directly.) List every `C-xxx` and `P-xxx` with title, status, and verification link.

2. **Flag drift:**
   - `Status: pending verification` but a passing test exists → **stale status** (mark
     it verified).
   - No `Verification` link / no test → **uncovered clause**.
   - `P-xxx` deltas not yet promoted to `C-xxx`.
   - Code areas / public APIs / user-facing features with **no clause at all** →
     contract gap.
   - Docs that describe behavior the code no longer has, or vice versa.
   - An oversized clause (research logs/sweeps inlined, no `Evidence:` link) →
     **altitude drift** (C-012/C-013); its lab-notebook belongs in `.zen/evidence/<ID>.md`.
   - A `verified` clause whose recorded run is **failed/stale**, or that has **no run
     recorded at all** (`.zen/evidence/runs/<ID>.json`) → **run-evidence gap** (C-024):
     "verified" is asserted but no green run backs it.
   - A newly-`verified` **behavioral** clause with a missing, `refuted`, or stale refute record
     (`.zen/evidence/refutes/<ID>.json`) → **refute-evidence gap** (C-041): a green run is not
     proof on its own; the disinterested critic never cleared it. Re-spawn `zen-refuter` + re-record.
     A test edit re-stales the run (whole-file); it re-stales the refute only if it touches THIS clause's
     own test symbol (C-043) — a sibling's edit to a shared file no longer forces a re-refute. A release
     re-run that re-records the run only re-refutes the clauses whose own symbol actually changed.
   - Dead / superseded / resolved clauses, or ripe `P-xxx` deltas → **compaction
     candidates** (C-034). Surface these **even unasked** — the operator may not know
     compaction exists — and propose the `zen` move: `promote` (ripe delta), `shelve`
     (resolved/abandoned delta), `supersede --by` (replaced), `archive` (obsolete). Each
     MOVES the clause into `.zen/archive/` (reversible, never `rm`), so the live contract
     stops growing monotonically and shrinks back toward the real working set.

3. **Report** as a compact table: clause · status · verification · drift flag. Then a
   short prioritized list of what to reconcile, heaviest drift first.

## Release gate — the real re-run (Phase 3 of C-024)

Per-turn the Stop-gate only checks that *recorded* runs passed and are fresh (it must
stay fast and never execute a suite). **Before a release**, do the real measurement:
re-run each verified clause's actual test command and re-record it, so "verified" is
backed by a green run *now*, not a memory.

```
# <zen> = the IMPLICATION→MACHINE plugin's directory (the dir holding hooks/zen-record-run.js)
node <zen>/hooks/zen-record-run.js --clause C-xxx -- <that clause's real test command>
```

Test commands are project-specific (there is no universal runner), so drive the
project's own harness (`scripts/coverage.sh`, a swift/jest/pytest target, `test.sh`).
After recording, run `/zen-check` again: any remaining run-evidence gap is a clause
claiming `verified` without a green run behind it. This is where "covered" finally
means the coverage tool ran, not a vibe.

Output is evidence for a decision, not the decision. Fixing the drift is
`/zen-contract` + `/zen-reconcile`.
