# IMPLICATION→MACHINE — user & technical guide

This is the reference documentation for the plugin. For the vision, read the
[README](../README.md); for the *why* behind every mechanism, read the
[Working Philosophy](zen-of-creativity-explained.md);
[zen-implementation-status.md](zen-implementation-status.md) maps each principle of that
philosophy to the exact piece of this plugin that realizes it (and is honest about what
the plugin delegates to the host).

---

## Concepts

**The axiom.** Nothing is true until reality shows it. "Done", "correct", "covered" are
claims; no claim counts without evidence you could reconstruct.

**The four artifacts.** Contract, tests, docs, code. The failure mode this plugin
prevents: a project grows and the four drift apart until re-aligning them is expensive.
The cure is to never let them diverge — every turn that changed behavior ends with the
four in agreement.

**Governed project.** A project is *governed* when it has a `.zen/contract.md` (create
one with `/zen-init`). With no `.zen/`, the protocol still loads as guidance, but the
Stop-gate stays silent.

**The contract** (`.zen/contract.md`). One clause per capability (`## C-xxx`), grown
organically. Each clause states *intent* (not implementation) and links its
verification — that link is what keeps contract↔test from drifting. Pending ideas live
as `P-xxx` under `## Pending Contract Deltas`. Research and spike logs live in
`.zen/evidence/<ID>.md`, referenced from the clause by one `Evidence:` line.

**The turn-end checklist.** A turn that changed behavior does not yield until this is
closed — every box green, or explicitly waived against a clause that covers the change:

```
[ ] CONTRACT  a C-xxx clause exists/updated for the change (intent, not implementation)
[ ] TEST      edge cases + correctness, asserting exact outputs, exists and passes
[ ] DOCS      user-facing text matches the behavior
[ ] CODE      implements the clause, nothing more
[ ] VERIFIED  proven against reality (real deps / inputs / outputs — not inferred)
```

---

## Install

```
/plugin marketplace add sylweriusz/implication-machine
/plugin install implication-machine@implication-machine-marketplace
```

Or from a local clone: `./install.sh [--scope user|project|local]` — registers this
directory as a local marketplace and installs via the `claude` CLI. Re-runnable. It also
drops a `zen` shim on your PATH pointing at the bundled CLI (`./install.sh --shim-only`
recreates just the shim).

**git is effectively required** for the gate to enforce: turn-drift reads the working
tree, the clause↔test link check is `git grep`, and run-evidence diffs against the last
gate-blessed commit — version control is the deterministic substrate. Without git the
gate degrades to advisory (file-based altitude check only); SessionStart nudges you to
`git init`.

## Getting started

1. In a project you want governed: `/zen-init` — creates `.zen/contract.md` and seeds it.
2. Work normally. When a turn changes behavior, close the checklist (the `zen-reconcile`
   skill walks it; the Stop-gate enforces it).
3. `zen status` (or `/zen-check`) any time you want the contract / drift picture.

---

## Architecture

| Part | Where | Role |
|---|---|---|
| **Brain** | `zen.md` | The lean always-on protocol, injected via SessionStart. |
| **Spine** | `hooks/zen-reconcile-gate.js` | Stop-hook gate — the only non-self-report enforcement. |
| **Tripwire** | `hooks/zen-post-tool-failure-tripwire.js` | PostToolUseFailure: catches a verification failing mid-turn, before the gate. |
| **Awareness** | `hooks/zen-context.js` | SessionStart: injects the protocol + a contract-state index for the current project. |
| **Recipes** | `skills/zen-*/` | Ten canonical, refinable procedures. |
| **Critics** | `agents/zen-refuter.md`, `agents/zen-implications.md` | Adversarial subagents: refute a verification; confront a clause against the rest of the contract. |
| **CLI** | `bin/zen.js` | `zen status / lint / verify / grep / add-clause / …` — shares the gate's parser, so its reports match the gate's verdict. |
| **Artifact** | per-project `.zen/contract.md` | The source of truth a project grows. |

The hooks fail **open** — a backstop must never wedge a session — and heartbeat to
`.zen/audit.jsonl` so a dead hook is visible rather than silent.

## The Stop-gate — what is checked deterministically

At each turn end the gate blocks the yield when it detects drift. Every check is
outside the model's say-so:

- **Turn drift** — code changed but `.zen/contract.md` did not (the contract is the anchor).
- **Link drift** — a clause claims `automated → <test>` but no such test exists in the repo.
- **Altitude drift** — a clause has absorbed its lab-notebook instead of linking evidence.
- **Run-evidence drift** — a `verified` clause's recorded test run (`zen-record-run`)
  failed, is missing, or went stale (its test file changed since the run).
- **Refute-evidence drift** — a NEW `verified` clause lacks a fresh adversarial-refute
  record (`zen-record-refute`), or the record says `refuted`.
- **Near-duplicate** — a newly added clause shadows a parked pending (routes to the
  `zen-implications` subagent).

The verdict is always the runner-captured **exit code** — the gate never parses log text
or a coverage % (fuzzy, gameable). Push judgement into the command: tests green →
exit 0; coverage-as-a-floor → make the coverage command itself exit non-zero below
threshold. The gate fires once per turn, stays silent in ungoverned projects, and fails
open.

## The ten skills

One authoritative, refinable recipe per procedure — so *how we do X* doesn't drift
between turns. Each is also callable as `/zen-<name>`.

| When this happens | Skill |
|---|---|
| A new or changed capability is recognized | `zen-contract` |
| A LARGE plan/spec (tens of items) must become contract backlog | `zen-ingest` |
| Correctness of an API/dependency is unknown before you assert | `zen-spike` |
| Behavior is implemented and must be proven against reality | `zen-verify` |
| A turn touching behavior is closing / the Stop-gate fires | `zen-reconcile` |
| A test fails or behavior surprises you | `zen-failure` |
| You need the contract / drift status | `zen-check` |
| A whole area has drifted, or you want everything to converge | `zen-converge` |
| A project should adopt the protocol but has no `.zen/` | `zen-init` |
| Agent-memory may be duplicating what the contract already holds | `zen-memory` |

## Verification tiers (`zen-verify`)

1. **Deterministic unit** — smallest thing proving a unit of behavior; no external deps.
2. **Integration** — real deps, real data flow, real side effects in a bounded env.
3. **Full-scope** — the assembled thing driven as the user would (CLI, real endpoint,
   GUI via UI-automation, TUI via tmux).

Assert **exact outputs** — value, ordering, count, error — never mere liveness. Mocks may
buy speed while you work; they are never evidence for the VERIFIED box.

## Failure discipline (`zen-failure`)

A real failure is product evidence: classify it (`bug | missing_feature |
wrong_assumption | ambiguous_contract | environment_issue`) and route it — a `bug` fixes
the code, the rest grow the contract first. Never fix the test to hide a real failure.

---

## Develop / test

The bundled test suites run on bare `node`:

```
bash hooks/zen-reconcile-gate.test.sh
bash hooks/zen-post-tool-failure-tripwire.test.sh
bash bin/zen.test.sh
```

This repository is the **distributable**, assembled from a single source (the
maintainer's dogfood config) — it is never hand-edited as a second copy. The build
enforces: no host-absolute path in the output, the bundled test suites pass, and
`claude plugin validate` if the CLI is present. Contributions are welcome as issues/PRs
here; the maintainer folds accepted changes back through the source.

## Further reading

- [Working Philosophy](zen-of-creativity-explained.md) — the twelve principles, two axes
  (correctness / authority), one shared trace.
- [zen-implementation-status.md](zen-implementation-status.md) — principle → mechanism map.
- [The Plumb Line and the Painted Cake](zen-1972-lore.md) — the same discipline as a
  1972 seminar handout. Read it slowly.

## License

MIT.
