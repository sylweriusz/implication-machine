---
name: zen-ingest
description: >
  Invoke when a IMPLICATION→MACHINE-governed project must absorb a LARGE plan/spec/design
  document (tens of items) into its contract — the gross-intake case the per-item zen-contract
  path does not scale to. Pours the plan into the contract's P-xxx backlog as the SINGLE sink,
  forbidding the intermediate task/scratch file that fractures bulk intake into three drifting
  documents. Lifts plan lines to capability-grained pendings, confronts each via zen-implications,
  asks the user on real ambiguity, and tracks progress by provenance IN the contract so a big
  plan drains resumably. Also callable as /zen-ingest. (C-046.)
---

# zen-ingest

For the **gross-intake** case: a plan/spec with tens of items that must become contract backlog.
`zen-contract` handles 1–2 pendings from a prompt; this handles 30–100 from a document.

The mechanics already exist (`zen add-clause P`, `zen grep`, the `zen-implications` subagent,
AskUserQuestion). This skill is **not** a batch loop over them — it is the **discipline** that
stops bulk intake from drifting. Read the one rule first.

## The one rule — two documents, never three

The failure this prevents: handed a big plan, the model spawns an **intermediate file** — a
`TODO.md`, `tasks.json`, a scratch tracker — to find its way through, because the plan plus the
growing contract exceed one context. Now there are **three** sources of truth (the plan · the
scratch tracker · the contract), and they diverge. **That three-document sprawl is exactly the
contract↔reality drift zen exists to kill, surfacing at intake.**

> **The input document is the only SOURCE. The contract's `P-xxx` backlog is the only SINK.
> No third document — neither a TODO/task tracker NOR a parallel/"target" contract file.** If you
> feel the urge to make a TODO to "track progress", or to write a second `contract-next.md` to hold
> the target scope — that urge *is* the failure mode. Your tracker AND your target both live in THE
> contract: a `P-xxx` exists ⇒ that item is ingested. Nothing else records progress or target.

(The canonical failure this rule is drawn from — LocalLLama, the testbed: a "target scope" request
produced a parallel `contract-next.md` with a different format and **colliding clause IDs**, then a
master `target-work-plan.md`, then per-task `plans/t0xx-*.md`, then task-keyed evidence — five drifting
documents for what should have been a series of deltas to the one live contract.)

## Step 1 — classify the input BEFORE touching anything

The document you were pointed at is one of three things; misreading it is the root failure. Detect
which (skim it; cited clause-IDs, a "rewrites/target contract" header, or a different clause format
are the tells):

- **(a) New capabilities** — describes behaviour the contract does not yet hold. → the happy path:
  lift to capability altitude and add `P-xxx` deltas (steps 2–5).
- **(b) Execution plan over an EXISTING contract** — items are *tasks* that cite the clauses they
  satisfy ("Contract coverage: C-040…", "satisfies F-003"). The capabilities are ALREADY contracted.
  → ingest is the WRONG tool: do NOT mint `P-xxx` (you would duplicate the contract). Surface to the
  user; the move is *execute/drain* (the amnesty loop over the already-contracted clauses), not ingest.
- **(c) Target-scope / parallel-rewrite contract** — an "alternative-universe" contract: a maturity
  target, a `contract-next.md`, a re-statement of where the product should land (often a different
  format, often **colliding IDs** with the live contract). → THIS is the primary, sharp case: render
  it as **deltas against the LIVE contract** — reconcile format and ID-collision, lift to capability
  altitude, emit the *gap* between live and target as `P-xxx`. The whole point is that a target scope
  becomes deltas to THE contract, so you never keep a second contract + a plan + per-task plans alive.

Only (a) and (c) ingest. (b) routes to drain. When you cannot tell (a)/(b)/(c) → ask the user.

## Procedure — once classified as (a) new-capabilities or (c) target-scope

2. **Locate `.zen/contract.md`** (governed?). Read the input file(s) the user pointed at — directly,
   the whole thing if it fits; if it does not fit, see step 7 (drain in chunks). Do **not** copy
   the input anywhere.

3. **Lift to capability altitude — do NOT map 1 line → 1 pending (C-012 at intake).** The input's
   items are usually *implementation steps* ("add the button", "wire the handler", "write its
   test") — or, for a (c) target contract, fine-grained table rows — of a smaller number of
   **capabilities**. Cluster them into the capability they serve; one `P-xxx` per capability, not per
   line/row. Over-granular intake pollutes the contract at the wrong altitude — the exact thing the
   gate flags later. When unsure whether something is one capability or three → step 5 (ask), never guess.
   - **Preserve enumerated sub-cases when you lift.** If a row spells out *variants* — "nested /
     multipart / whole-set", "GGUF or MLX", a list of failure causes — folding it to one capability
     line silently drops the enumeration (the measured F-004 thinning on the testbed: scan-structure
     and download-scope were summarized into "progress + metadata"). Either keep the enumeration in the
     delta's description, or add an explicit "re-expand at promotion (see provenance)" note — so the
     variants survive into the eventual verified clause instead of being lost to the lift.

4. **For each capability, confront before adding.** `zen grep <term>` the live clauses **and the
   `## Pending Contract Deltas`** for an existing/parked match (semantic, not one keyword). On any
   plausible match, spawn **`zen-implications`** (C-037) to judge: duplicate of a parked pending,
   contradiction with a verified clause (a "measured & disproved" pending is a contradiction, not a
   merge — the C-044 lesson), or a supersede. Resolve against its finding; never blind-add a
   near-duplicate.

5. **Ask the user on real ambiguity — do not dump.** One-clause-or-three? Does this supersede
   `P-xxx`? For a (c) target with a colliding ID, which clause does it really map to? Is this
   in-scope or a tooling/meta note that belongs elsewhere? Use AskUserQuestion. A guessed clause at
   the wrong altitude is debt; a question is cheap.

6. **Add as a pending with provenance — AND carry its acceptance.** `zen add-clause P --title <…>
   --source "ingest (<plan>#<range>)" --description <intent>`. **If the source item already states
   its own acceptance/evidence** — a target contract's "Evidence required" column, a plan task's
   "Evidence:" bullet — carry it into the `P-xxx`'s **Proposed verification**, so the delta arrives
   with its acceptance, not `TBD` (the source already did this thinking; do not discard it). Intake
   is always **proposal** (`P-xxx`) — never a committed `C-xxx` directly; promotion stays a separate,
   human-gated step (`zen promote`), and a delta that says "extends C-xxx" is a *merge-into-existing*
   proposal, resolved at promotion. The **`Source: ingest (<plan>#<range>)` line IS the check-off**:
   re-running this skill `zen grep`s the provenance and skips ranges already ingested, so intake is
   idempotent and resumable with **no side tracker**.

7. **Scale = fresh-context chunks, not a scratch file.** When the input is too big to hold beside
   the growing contract (the root cause of the urge in the one-rule), drain it in chunks via the
   **amnesty loop (P-003)**: each chunk runs in fresh context, processes the next un-ingested plan
   range, and the provenance lines (step 5) carry progress across the wipe. The contract is the
   loop's memory; there is still no third document.

## Done

A reviewed, deduped, **capability-grained** `P-xxx` backlog whose lineage to the source plan is
traceable (provenance) and resumable (idempotent). The plan and the contract are the only two
documents that were touched. Promotion/draining of the backlog is the separate next step
(`zen-contract` to promote, the amnesty loop to drain).
