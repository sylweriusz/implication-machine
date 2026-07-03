---
name: zen-spike
description: >
  Invoke autonomously whenever the correct behavior of an API or dependency is
  unknown and you are about to assert against it in a IMPLICATION→MACHINE-governed project (the spike
  move — before assertions). Drives the REAL API/dependency with real inputs, observes actual
  parameters/responses/failure shapes, and records the findings as contract evidence
  so assertions are grounded in observation, not guesses. Also callable as /zen-spike.
---

# zen-spike

The spike move (`zen.md`): correctness unknown → learn it from
reality before writing assertions. Guessed assertions are debt.

## Procedure

1. **Name the unknown.** What exactly is unclear — the API contract, a parameter's
   shape, response format, error/failure modes, timing, a dependency's real behavior?

2. **Drive the real thing.** Call the real endpoint / exercise the real dependency
   with real inputs. Inspect actual outputs — do not infer them. No mocks here; a
   mock would only encode the assumption you're trying to test.
   - Dependency genuinely unavailable? Say so plainly and stop — do **not** substitute
     a weaker check or guess. An honest "can't verify" beats a fabricated one.

3. **Capture evidence — in `.zen/evidence/<ID>.md`, not in the clause.** Write what
   you observed (params, response schema, edge behavior, failure shapes, sweep
   numbers) into the per-case evidence file `.zen/evidence/<ID>.md` for the clause
   (or its `P-xxx` delta). The clause itself stays at intent altitude and carries one
   `- **Evidence:** .zen/evidence/<ID>.md` line (clause altitude, C-012). A spike
   produces a lab-notebook; the contract is not where it lives — pasting
   it into the clause is the bloat the gate now flags. This observation is the basis for
   the test-plan.

4. **Hand back to the loop.** With behavior observed, the test's edge cases and
   correctness condition are concrete. Proceed to docs → code → `/zen-reconcile`.

The spike's value is discovery: a real result can show you something you didn't
expect, and that is what grows the contract.
