---
name: zen-converge
description: >
  Invoke autonomously to self-heal a IMPLICATION→MACHINE-governed project: find everything that's out
  of sync across contract, tests, docs, and code, then work the loop until they all
  line up. Audits for gaps, builds a worklist heaviest-drift-first, closes each gap
  with the right procedure (contract / spike / test / doc / verify), re-audits, and
  repeats until the four agree or a remaining gap needs a human decision. Use when a
  project has drifted, after a big change, or before a release. Also /zen-converge.
---

# zen-converge

The self-healing driver (`zen.md`). The method's payoff: it can *see* what's
missing where — in docs, contract, code, or tests — and loop until everything closes.
This skill runs that loop autonomously. It composes the other IMPLICATION→MACHINE skills; it does not
replace them.

## Loop

1. **Audit** (the `zen-check` pass). `zen drift` / `zen lint` enumerate the deterministic
   gaps (broken links, altitude, run-evidence) sharing the gate's parser; the semantic gaps
   below need your reading of the contract (fallback: read `.zen/contract.md`). Enumerate
   every gap:
   - contract clauses with no test / no verification link,
   - clauses marked `pending` that actually have passing tests (stale status),
   - code / public APIs / user-facing features with **no clause**,
   - docs that disagree with the code,
   - unpromoted `P-xxx` deltas,
   - tests with liveness-only assertions (`!isEmpty`) instead of exact outputs,
   - oversized clauses with inlined research and no `Evidence:` link (altitude drift),
   - dead / superseded / resolved clauses, or ripe `P-xxx` deltas — **compaction
     candidates** (the contract grows monotonically; shrinking it is part of converging, C-034).

2. **Worklist.** Order the gaps heaviest-drift-first (untested behavior > stale status
   > missing doc > weak assertion). State the list before acting.

3. **Close each gap** with the matching procedure:
   - missing/wrong clause → `zen-contract`
   - correctness unknown → `zen-spike`
   - missing/weak test → write it (edge cases + exact assertions)
   - stale doc → update it
   - implemented-but-unproven → `zen-verify`
   - altitude drift → move the clause's research log into `.zen/evidence/<ID>.md`,
     leave one `Evidence:` link; the clause keeps only intent + verification.
   - dead / superseded / resolved clause or ripe delta → **compact it** (C-034):
     `zen promote <P>` (ripe) · `zen shelve <P>` (resolved/abandoned) ·
     `zen supersede <id> --by <id>` (replaced) · `zen archive <id>` (obsolete) — each moves
     it to `.zen/archive/` (reversible). Act on clear-cut cases **proactively** and report
     them; surface only genuinely ambiguous retirements for the user to decide.
   - then `zen-reconcile` to confirm the four agree for that item.

4. **Re-audit.** Repeat from step 1.

5. **Terminate** when the audit is clean — every clause verified, every behavior
   claused and tested, docs aligned. 

## Bounds (don't spin)

- A gap that **can't close autonomously** (ambiguous contract, a product decision only
  the user can make, an unavailable real dependency) → **surface it** with the concrete
  question and move on to the next gap. Don't guess to force closure.
- Track progress each pass (gaps closed / remaining). If a full pass closes nothing and
  only blocked-on-human gaps remain, stop and report them — convergence is done as far
  as you can take it.
- Match effort to blast radius: trivial items waive in one line, they don't each need
  a full ceremony.
