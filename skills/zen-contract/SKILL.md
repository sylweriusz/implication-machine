---
name: zen-contract
description: >
  Invoke autonomously, without being asked, the moment a new behavior is recognized
  or an existing one changes in a IMPLICATION→MACHINE-governed project (.zen/contract.md present) —
  intent before code — the contract is the anchor the loop turns around. Records the capability as a C-xxx
  clause (or pending P-xxx) and links its verification. Also callable as /zen-contract.
---

# zen-contract

Intent before code (`zen.md`): capture what a capability *is becoming* before implementing it — the contract is the anchor.

## Procedure

1. **Locate `.zen/contract.md`.** Not governed (no file)? → run `/zen-init` first;
   do not edit a read-only fallback contract.

2. **New or changed?** First **search the existing contract** for a clause already covering
   this capability — `zen grep <term>` / `zen show <id>` to find candidates, `zen next-id C`
   (or `P`) for the next free number (fallback: read `.zen/contract.md` directly). Read the
   match and scan semantically, not just one keyword (the wording may differ: "voice cloning"
   vs "reference-audio synthesis"). **Search the `## Pending Contract Deltas` section too, not only
   the live C-xxx clauses** — a parked `P-xxx` may already hold this idea, *or have recorded why NOT to
   build it* (a "research-first" / "measured & disproven" caveat). Building what a pending disproved is
   the C-112↔P-091 failure this step exists to stop; if the match is such a pending, do not add a
   sibling clause — resolve against its finding (`zen-implications`). A match means this is *Changed*,
   not New — update that clause; never add a near-duplicate. (The Stop-gate backstops this self-report
   search: a new clause that near-duplicates an un-referenced clause/pending is flagged — C-044. At growth scale a
   semantic index may assist this — framework `P-001` — but the model reading the contract is
   the primary tool, and exact-match stays the gate's job, not discovery's.)
   - **New capability, agreed** → add `## C-xxx:` (next free number; the **colon** after the id is required — the parser keys clauses on `## C-xxx:`, so a `—`/space delimiter makes the clause invisible, C-039).
   - **New, not yet agreed / discovered mid-work** → add to `## Pending Contract
     Deltas` as `P-xxx`; promote to `C-xxx` once confirmed.
   - **Changed behavior** → edit the existing clause in place; the clause and its
     test move together.
   - **Replaced, not edited** → if the new capability *supersedes* an old clause rather
     than refining it, add the new `C-xxx` and then `zen supersede <old> --by <new>` to
     retire the old one into `.zen/archive/` (C-034) — proactively, so a stale near-duplicate
     never lingers in the live contract.

3. **Write the clause.** Reuse the `C-xxx` convention (do not invent a new format):

   ```markdown
   ## C-042: <short capability title>
   - **Date:** YYYY-MM-DD
   - **Source:** discovery | failure
   - **Description:** What this capability is / is becoming. Intent, not implementation.
   - **Verification:** automated → <test name>  |  manual: <how>  |  not_required: <reason>
   - **Evidence:** .zen/evidence/C-042.md   ← only when research/logs exist (clause altitude, C-012)
   - **Status:** pending verification | verified
   ```

   - **Description** = what it *is becoming* (intent), not how it's coded.
   - **Source** = `discovery` or `failure` (if it came from `/zen-failure`, reference
     the classification).
   - **Verification** = `automated → <test name>` | `manual: <how>` | `not_required:
     <reason>`. A clause with no verification is incomplete. Multiple tests: list them
     comma-separated, then `|` before any prose (`automated → a, b | what they cover`).
   - **Match the verification to the claim's ALTITUDE.** If the title/description makes a
     **causal or comparative** claim — *keeps / improves / reduces / prevents / makes X reliable* —
     the verification must **measure X** (a with/without or before/after metric), not merely prove the
     mechanism exists. A mechanical test ("the structure splits correctly") does **not** verify "it
     keeps routing reliable" — that needs the failure-rate-vs-turns curve, not a unit assertion. Name
     that measurement here; a causal clause whose only test is mechanical is a painted cake (the
     C-112↔P-091 failure), and `zen-refuter` is now tasked to refute exactly that altitude gap.
   - **Evidence** = `.zen/evidence/<ID>.md` — add this line the moment the clause
     accumulates research/spike logs/sweeps. The clause states *intent*; the lab-notebook
     lives in the evidence file (clause altitude, C-012; `zen.md` → Contract). Keep the clause
     short; if its body is mostly findings, move them out and link. The Stop-gate flags an
     oversized clause with no `Evidence:` link.
   - **Status** = `pending verification` until reality proves it.

4. **Atomic.** One capability per clause. If you're describing two things, write two
   clauses.

Adding the clause is not the end — the loop continues to test-plan (`/zen-spike` if
correctness is unknown), docs, code, then `/zen-reconcile`.
