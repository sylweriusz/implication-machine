---
name: zen-memory
description: >
  Invoke in a IMPLICATION→MACHINE-governed project when agent-memory may be duplicating the contract —
  periodically, after a big contract change, or when memory has grown. Reconciles
  file-based agent-memory against `.zen/contract.md`: keeps what the contract structurally
  cannot hold (user / feedback / reference), and for project-state memory that a clause
  already covers, migrates any delta into the clause/evidence first, then PROPOSES retiring
  the redundant note. Never auto-deletes — memory is the user's. Also callable as /zen-memory.
---

# zen-memory

The contract↔memory reconcile pass (`zen.md`). In a governed project, project-state
belongs in the contract — verified, drift-checked, named. Agent-memory that restates a clause
is a **second, unverified source of truth** that can drift from the contract (the anti-pattern
IMPLICATION→MACHINE exists to kill). This pass finds that overlap and proposes removing it, without losing
knowledge and without touching what the contract cannot hold.

**The boundary (the rule it enforces):** governed project → project-state lives in the
contract, never duplicated in memory; memory keeps only `user` (who the user is), `feedback`
(how to work — e.g. a push policy, a review preference), and `reference` (external pointers).
You cannot verify a preference against a test, and it must apply in ungoverned dirs too.

## Procedure

1. **Locate both sides.** Memory: the project's memory dir (`<claude-config>/projects/<hash>/
   memory/*.md` + its `MEMORY.md` index). Contract: `.zen/contract.md` + `.zen/evidence/`.
   Not governed (no contract)? → stop; the pass only applies where the contract exists.

2. **Classify each memory entry.**
   - **Keep unconditionally** — `user`, `feedback`, `reference`. These are not capabilities;
     the contract has no shape for them. Do not touch them.
   - **Candidate** — `project`-type notes and spike/finding records. These may duplicate a
     clause or belong in `.zen/evidence/`.

3. **For each candidate, check coverage against the contract** (this is judgment, not a grep —
   read the clause and the memory and decide):
   - **Fully covered** by a clause/evidence → verdict **retire**.
   - **Partially covered** (the memory carries a fact the clause/evidence lacks) → **migrate**
     that delta into the clause or its evidence file (`zen-contract` / append to
     `.zen/evidence/<ID>.md`) FIRST, then verdict **retire**. Knowledge moves before the note dies.
   - **Not covered at all** (genuine project state with no clause) → the memory is doing the
     contract's job badly: **add a clause** (`zen-contract`) so the contract becomes the home,
     then verdict **retire**.

4. **Present, never auto-delete.** Show a table — `memory · verdict · covering clause · delta
   migrated?` — and the keep list with its reason. Memory is the user's; deletion needs their
   go. State plainly what each retirement removes.

5. **On approval, retire cleanly.** Delete the approved memory file(s) AND their line(s) in
   `MEMORY.md` (leave no dangling index entry). Any migration must already be in the
   contract/evidence and committed. Report what moved where and what was removed.

## Rules

- **Propose, don't auto-delete.** This pass never deletes without explicit approval.
- **Don't lose knowledge.** A delta migrates into the contract/evidence before its memory retires.
- **Keep `user`/`feedback`/`reference` always** — the contract structurally cannot hold them.
- **Not a hook.** Memory↔clause matching is semantic; a deterministic hook would either guess
  (and risk silently deleting the user's notes) or add noise. This is a model-judged pass by
  design — the gate's determinism is the wrong tool here.
