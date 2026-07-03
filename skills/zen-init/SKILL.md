---
name: zen-init
description: >
  Invoke when a project should follow the IMPLICATION→MACHINE discipline but has no .zen/contract.md
  yet (e.g. the user asks to work this way, or you recognize an ungoverned project
  that needs a contract). Creates .zen/contract.md (no config file — C-019) and seeds it
  from the code that already exists so the contract reflects reality from day one. Also
  callable as /zen-init. (Confirm with the user before scaffolding into their repo.)
---

# zen-init

Brings a project under the IMPLICATION→MACHINE protocol (`zen.md`). After this, the
Stop-hook anti-drift gate is active for the project.

## Procedure

1. **Guard.** If `.zen/contract.md` already exists → stop. The project is already
   governed; suggest `/zen-check` instead. Do not overwrite.

2. **Git check — ask, never auto.** If the project is **not a git repo**
   (`git rev-parse --is-inside-work-tree` fails), the deterministic gate is
   **essentially off**: turn-drift (C-036), clause↔test link verification (C-004),
   and run-evidence (C-024) all need git — version control is IMPLICATION→MACHINE's substrate. Only
   the file-based altitude check runs; without git you get **advisory mode**, not
   enforcement. **Ask the user** whether to `git init`, explaining exactly that ("the
   gate needs git to enforce; without it only the altitude check runs"). **Never run
   `git init` yourself** — initializing a repo is the user's call. If they decline,
   proceed anyway: IMPLICATION→MACHINE still governs in advisory mode (the SessionStart hook will keep
   nudging — C-017).

3. **Scaffold.**
   - `.zen/.gitignore` → one line: `audit.jsonl` (the trace is a local artifact;
     `evidence/` is versioned, not ignored).
   - `.zen/evidence/` → the per-clause lab-notebook directory (`<ID>.md`); create it on
     first use. Clauses stay intent; their research/spike logs live here (C-012).
   - `.zen/contract.md` → header `# Contract Items` and a `## Pending Contract Deltas`
     section. **Do not write placeholder `C-001`/`P-001` headings** — parsers count
     real-looking IDs. Seed only real clauses or leave the body empty.

4. **Seed from reality.** Map what the project *already does* — entry points,
   public APIs, user-facing features, existing tests. Propose one `C-xxx` clause per
   recognized capability, in the clause format (see `zen-contract`: title, date, source,
   description = intent, verification, status). Where a test already covers it, link
   the test and set `Status: verified`; otherwise `pending verification`.

5. **Report.** Show the seeded contract and ask the user to review/correct. The
   contract is theirs; you proposed a starting point, not a verdict.

Keep it organic: seed what you can evidence, not an exhaustive guess. The contract
grows from work, it does not predate it.
