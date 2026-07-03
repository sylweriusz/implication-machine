---
name: zen-failure
description: >
  Invoke autonomously the moment something breaks in a IMPLICATION→MACHINE-governed project — a test
  fails, a build errors, or behavior surprises you. Diagnoses root cause, classifies
  it (bug | missing_feature | wrong_assumption | ambiguous_contract | environment_issue),
  and routes it to grow-the-contract or fix-the-code — never fixing the test to hide
  it. Do not wait to be asked; a failure is product evidence. Also callable as /zen-failure.
---

# zen-failure

Failure-as-signal (`zen.md`). The classify step is the arbiter that decides
whether reality disagrees with a *wrong contract* or with a *wrong implementation*.

## Procedure

1. **Diagnose root cause** — not the symptom, not the proximate cause.

2. **Classify** exactly one:
   `bug` | `missing_feature` | `wrong_assumption` | `ambiguous_contract` |
   `environment_issue`.

3. **Route by classification:**
   - **bug** — the contract was sound, the code diverged → fix the code.
   - **missing_feature** — grow the contract (`/zen-contract`) first, then implement.
   - **wrong_assumption** — correct the contract clause; the old assumption was the bug.
   - **ambiguous_contract** — sharpen the clause before touching code; resolve the
     ambiguity first.
   - **environment_issue** — record the dependency / runtime condition as a clause
     when it's part of the project's contract.

4. **Record** what failed, why, and what fixed it — institutional knowledge.

**Never** weaken a verification, suppress the failure, or fix the test to make the
build green. A real failing test is knowledge; a passing mock is not. Green means
verified working.
