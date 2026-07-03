# IMPLICATION→MACHINE — living-contract working protocol

Operationalizes the IMPLICATION→MACHINE philosophy `zen-of-creativity-explained.md` (the *why*); this file is the *how*.
One rule, restated: **nothing is true until reality shows it.** "Done", "correct", "covered"
are claims; no claim counts without evidence you could reconstruct.

The failure mode this prevents: a project grows, and its contract, tests, docs, and code
drift apart until the cost of re-aligning them is huge. The cure is to never let them
diverge in the first place — every turn ends with the four in agreement (the checklist
closed), never with code ahead of its contract, test, and doc.

This file is the lean always-on core — axiom, checklist, closure rule, skills router.
Procedure *detail* lives in the canonical `zen-*` skills (loaded on demand); the enforcement
*mechanism* is the Stop-hook gate, which checks it deterministically. This document
**delegates, it does not restate** — two copies drift (that altitude rule is C-029).

---

## Activation

IMPLICATION→MACHINE governs a project **when it has `.zen/contract.md`**. No `.zen/` → IMPLICATION→MACHINE is passive
(guidance only, no gate). To start governing a project, create `.zen/contract.md`
(`zen-init`). The Stop-hook backstop (below) only fires in governed projects.

This is global guidance; a project's own `CLAUDE.md` may tighten it, never loosen the axiom.

---

## The turn-end checklist (not a fixed order)

A turn that changed behavior does not yield until one checklist is **closed** — every
box green, or explicitly waived:

```
[ ] CONTRACT  a C-xxx clause exists/updated for the change (intent, not implementation)
[ ] TEST      edge cases + correctness, asserting exact outputs, exists and passes
[ ] DOCS      user-facing text matches the behavior
[ ] CODE      implements the clause, nothing more
[ ] VERIFIED  proven against reality (real deps / inputs / outputs — not inferred)
```

**Interleave freely; do not sequence rigidly.** The four *artifacts* — contract, test, docs,
code — are interdependent: each reshapes the others (a spike into the code reveals the real
shape, which rewrites the clause, which changes the test's edge cases, which exposes a doc
gap), and the fifth box, VERIFIED, is the proof that closes them against reality. Forcing an
order fights that. The discipline is not "do them in order"; it is **"don't yield until they
agree."**

When correctness is **unknown** before you can assert — a new API, an unfamiliar
dependency — run a SPIKE first (`zen-spike`): drive the real thing, observe actual
parameters, responses and failure shapes, record them as evidence on the clause. Only
then do you know what to assert; guessed assertions are debt.

Mocks may buy speed while you work; they are **never** evidence for the VERIFIED box.

---

## Closing the checklist: reconcile or waive

Before yielding a turn that touched code, make the closure explicit (`zen-reconcile`):

- **Reconcile** — the boxes are green: clause, test, and doc moved with the code and it
  is verified. Mark the clause `verified`, linking the concrete test.
- **Waive** — a box legitimately needs nothing (a comment typo, a pure rename, no
  behavior change). A waive **must cite the C-xxx clause** that already covers the
  change. If no clause fits, you cannot waive — you must add one. That requirement is the
  point: the waive itself forces contract-awareness; it is not an escape hatch.

Never weaken a test, suppress a failure, or mock around reality to reach green. Green
means *verified working*. Match effort to blast radius — a one-line change closes in one
line and needs no ceremony; a behavioral change that tries to waive is the drift the
gate exists to catch.

---

## What is enforced deterministically (not taken on your word)

You are both the enforcer and the enforced, so any gate you can satisfy by self-report is
weak. The Stop-hook checks these outside your say-so every fire:

- **Clause↔test links resolve** — a clause claiming `automated → <test>` is flagged unless
  that test actually exists in the repo. `verified` is not a word you type; it is a link
  that resolves.
- **Recorded runs passed and are fresh** — `verified` means a recorded run (`zen-record-run`)
  exited 0 and its test file hasn't changed since, not just that a test by that name exists.
  A NEW `verified` claim since the gate last ran must have a fresh run, or the gate blocks —
  so the honest path (one cheap `--rerun`) is cheaper than the lie.
- **A new behavioral claim survived a critic** — a NEW `verified` clause must carry a fresh
  adversarial-refute pass (`zen-refuter`'s `holds`/`trivial`, recorded via `zen-record-refute`);
  a `refuted`/missing/stale record blocks. The verdict is the critic's judgement; that it *ran* is
  the gate's (the lesson of a run where wording alone fired the refuter 0/8 — C-041).
- **The trace already exists** — session transcript + version-control history are the audit record; the
  gate's `.zen/audit.jsonl` heartbeat only proves it ran (no line ⇒ dead hook).

The verdict is always the runner-captured **exit code** — the gate never parses log text or
a coverage % (fuzzy, gameable). Push judgement into the command: tests green → exit 0;
coverage-as-a-floor → make the coverage command itself exit non-zero below threshold (C-027).
Coverage *quality* (real edge cases, exact assertions) is yours to uphold — no tool measures it.

---

## Test & failure discipline (detail: `zen-verify`, `zen-failure`)

- **Edge cases are the point**: empty, boundary, negative, malformed, concurrent,
  locale/encoding, unknown-id, not-found. Enumerate them before coding.
- **Assert exact outputs**, not liveness — the value, ordering, count, error. Asserting only that
  a result is non-empty is coverage theater. Three tiers: deterministic unit, integration with real deps, full-scope.
- **Never pipe the test runner** — `…| tail` exits with tail's 0, a red suite reads green. Run it bare, or `set -o pipefail` (C-049).
- A real failure is **product evidence**: classify it (bug | missing_feature | wrong_assumption |
  ambiguous_contract | environment_issue) and route it — a `bug` fixes the code, the rest grow
  the contract first. Never fix the test to hide a real failure. Full recipe: `zen-failure`.

---

## Contract — `.zen/contract.md`

One clause per capability (`## C-xxx`), grown organically; pending ideas live as `P-xxx`
under `## Pending Contract Deltas`. **Each clause links its verification** — that link is
what keeps contract↔test from drifting. The clause states *intent*, not implementation;
research/spike logs live in `.zen/evidence/<ID>.md` with one `Evidence:` line pointing
at them (clause altitude, C-012 — the gate flags an oversized clause with no Evidence link).
The literal clause format and the add/update recipe are in **`zen-contract`**.

Operations on the contract — read, lint, verify, status — go through the `zen` CLI (`zen help`);
it shares the gate's parser, so its reports match the gate's verdict. The skills route to it,
if bare `zen` is not on PATH, use the CLI invocation the session-start index emits; only with no CLI at all read `.zen/contract.md` directly.

---

## Skills — the canonical procedures

Each procedure has **one** authoritative, refinable recipe — a skill — so its *meaning*
doesn't drift between turns. **Refine, don't reinvent**: when a recipe proves insufficient,
fix the *skill* (a gap in one is a `zen-failure` on the procedure itself). Reach for the
matching skill yourself; the `/zen-*` forms exist for explicit calls.

| When this happens | Skill |
|---|---|
| A new or changed capability is recognized | `zen-contract` |
| A LARGE plan/spec (tens of items) must become contract backlog | `zen-ingest` |
| Correctness of an API/dependency is unknown before you assert | `zen-spike` |
| Behavior is implemented and must be proven against reality | `zen-verify` |
| A turn touching behavior is closing / the Stop-hook gate fires | `zen-reconcile` |
| A test fails or behavior surprises you | `zen-failure` |
| You need the contract / drift status | `zen-check` |
| A whole area has drifted, or you want everything to converge | `zen-converge` |
| A project should adopt IMPLICATION→MACHINE but has no `.zen/` | `zen-init` |
| Agent-memory may be duplicating what the contract already holds | `zen-memory` |

Verification is active, never passive reading: run the CLI, hit the real endpoint, drive
the GUI via your platform's UI-automation, read back screenshots, run E2E scripts.

---

## The Stop-hook backstop

In governed projects, a Stop hook (`hooks/zen-reconcile-gate`) runs at each turn end and
blocks the yield with the checklist on drift — **turn drift** (code edited, `.zen/contract.md`
not), **link drift** (a clause's `automated → <test>` missing), altitude, stale/failed
run-evidence, or a **near-duplicate** new clause shadowing a parked one (C-044). It fires once
per turn, stays silent in ungoverned projects, fails **open**
(never wedges a session), and heartbeats to `.zen/audit.jsonl`.

It is the spine; this document is the brain. A prompt alone drifts over long sessions —
that drift is exactly the cost this protocol exists to avoid.
