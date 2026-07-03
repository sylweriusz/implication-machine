# How IMPLICATION→MACHINE implements the Working Philosophy

This maps `zen-of-creativity-explained.md` (the **why** — the Working Philosophy) to the machinery this
plugin ships (the **how**). The philosophy is read-only and domain-agnostic; it does not change.
This document does — it is the adapter, rewritten when the implementation evolves.

A companion to the user & technical guide (`guide.md`): the guide tells you how to *use*
IMPLICATION→MACHINE; this tells you *why each piece exists* and which principle it realizes.

---

## The two axes — and what IMPLICATION→MACHINE actually covers

The philosophy runs one rule (*nothing is true until reality shows it*) along **two axes**:

- **Correctness** — *does it do what it should?* → Contract (§1) · Verification (§2) · Failure (§3).
- **Authority** — *what is it allowed to do, and what did it do?* → Capability model (§5) · Audit (§6) · No hidden side effects (§11).

**IMPLICATION→MACHINE (this plugin) implements the Correctness axis end-to-end.** The Authority axis is **delegated to
the host (Claude Code) and to tools that already exist** — IMPLICATION→MACHINE deliberately does not rebuild a
capability system or a reference monitor (the philosophy's §6 itself says the trace *already exists*;
the framework's thesis is *less machinery*). The honest split:

| Axis | Realized by |
|---|---|
| **Correctness** (§1–4, §7–10, §12) | IMPLICATION→MACHINE: the contract, the turn-end checklist, the Stop-gate, the `zen-*` skills, run-evidence. |
| **Authority** (§5, §6, §11) | The host's permission model (consent levels, tool mediation) + the session transcript & version-control history as the shared trace. IMPLICATION→MACHINE contributes only the gate's `audit.jsonl` *heartbeat* — proof the gate ran, not a full action audit. |

Claiming IMPLICATION→MACHINE enforces the Authority axis would be the exact false confidence the axiom forbids. It does not. It governs correctness, and leans on the trace that already exists for authority.

---

## Principle-by-principle

| # | Principle | How IMPLICATION→MACHINE realizes it |
|---|---|---|
| **§1** | **Living Contract** | `.zen/contract.md` — one `C-xxx` clause per capability, grown organically (intent, not a plan). **Authoring phase:** `zen-contract` / `zen-failure` grow it from evidence. **Governing phase:** the Stop-gate's *turn-drift* check blocks a code change that didn't move the contract. Clause **altitude** (the gate flags an oversized clause with no `Evidence:` link) keeps it at intent, lab-notebook in `.zen/evidence/`. |
| **§2** | **Real Verification** | The `VERIFIED` checklist box + the `zen-verify` recipe: drive the real thing, the three tiers (deterministic unit → integration with real deps → full-scope), "a mock is never evidence". Made deterministic by **run-evidence**: `zen-record-run` records a real run's exit code + test-file hashes; the gate flags a `verified` clause whose run failed or went stale. The verdict is the **exit code**, never a parsed log. A fresh-context **`zen-refuter` subagent** then tries to *refute* that the test actually proves the clause before `verified` is granted — adversarial verification, so a plausible-but-wrong test cannot self-certify (C-035). |
| **§3** | **Failure as Signal** | The `zen-failure` recipe: diagnose root cause → **classify** (`bug \| missing_feature \| wrong_assumption \| ambiguous_contract \| environment_issue`) → route. The classify step is the promotion gate that decides grow-the-contract vs fix-the-code — and makes §12's "contract wins" a *rebuttable* default. Never fix the test to hide a failure. |
| **§4** | **Incremental Delivery** | The discipline is **per turn**: the turn-end checklist must close before the turn yields. "Match verification to blast radius" is built in — a trivial change **waives** in one line (citing a clause); a behavioral change must reconcile. |
| **§5** | **Capability Model** *(Authority)* | **Delegated to the host.** Claude Code's permission modes are the consent levels (implicit / per-invocation / interactive / blocked). IMPLICATION→MACHINE adds no capability layer — it would be a worse copy of one that exists. |
| **§6** | **Observability / Audit** *(Authority)* | **The trace already exists** — the session transcript + version-control history are the audit record; the host's permission system is the reference monitor. IMPLICATION→MACHINE's own contribution is narrow and honest: a one-line `audit.jsonl` **heartbeat** per gate fire, so a *dead gate* is visible rather than silent. It proves the gate ran; it is not a full per-action audit. |
| **§7** | **Documentation as Working Artifact** | The `DOCS` checklist box: user-facing text must match behavior, and the contract item is written *before* the increment's code (intent before implementation). Honest limit: the gate cannot mechanically tell if docs match behavior — the `DOCS` box is model-judged, upheld by the recipe, not enforced deterministically. |
| **§8** | **Reference Study** | Realized lightly, via `zen-spike`: when correctness is unknown, **learn from the real dependency** before asserting (extract behavior from reality, not guesses). Studying prior art is a practice the recipes encourage, not a mechanism the gate enforces. |
| **§9** | **Version Control as Knowledge Base** | Version control **is** IMPLICATION→MACHINE's deterministic substrate: the clause↔test link check is a `git grep`; "where we left off" after a context reset is read from the last commit; the newly-verified check diffs against the committed contract. History-as-narrative (atomic commits, why-not-just-what) is a practice IMPLICATION→MACHINE relies on but does not itself enforce. |
| **§10** | **Continuous Feedback** | The **shortest possible loop**: the Stop-gate fires at the *end of every turn* — the moment a change is made — and the SessionStart hook re-surfaces contract state on every start/resume/clear. Feedback is immediate and actionable (the checklist names exactly which box is open), not a report read later. |
| **§11** | **No Hidden Side Effects** *(Authority)* | **Delegated to the host.** Tool calls are visible in the Claude Code transcript; IMPLICATION→MACHINE does not add a side-effect monitor. (The completeness guarantee lives on the Authority axis, which IMPLICATION→MACHINE does not own.) |
| **§12** | **Contract-Driven Evolution** | The whole loop: new capability → new clause → new test; changed behavior → updated clause + test (they move together); retired → removed clause. "Contract wins" is the governing-phase default, **rebuttable** by `zen-failure`'s classify when the clause itself was wrong. Stale statuses and broken/​fabricated links are caught deterministically by the gate, so the contract cannot quietly atrophy. And when a change *redefines* a behavior, the **`zen-implications` subagent** sweeps the rest of the contract + recipes + docs for what the change now implicates — a reference gone stale, a clause it contradicts, a duplicate it creates, a gap it opens — catching the *semantic* drift the mechanical gate cannot see (C-037). |

---

## The one-line summary

IMPLICATION→MACHINE turns the **Correctness loop** of the Working Philosophy — Contract → Verification → Failure,
evolved under Contract-Driven Evolution — into a living `.zen/contract.md`, ten canonical recipes,
two adversarial subagents (refute-before-`verified`, and the implications sweep), and a deterministic
Stop-gate, with the **shortest feedback loop** (every turn). For the **Authority
loop**, it does the honest thing the philosophy asks: it does not rebuild what already exists — it
leans on the host's permission model and the existing transcript + version-control trace, adding only
a heartbeat so its own liveness is observable.
