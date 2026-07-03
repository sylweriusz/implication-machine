---
name: zen-verify
description: >
  Invoke autonomously when a behavior has been implemented and must be PROVEN against
  reality in a IMPLICATION→MACHINE-governed project (the VERIFIED box of the turn-end checklist) — especially for things a
  unit test can't see: GUI apps, services, end-to-end flows. Drives the real artifact
  (run the CLI, hit the real endpoint, drive the GUI via your platform's UI-automation,
  capture and read back screenshots, run E2E scripts), inspects real output, and
  records the evidence on the contract clause. No mock counts here. Also /zen-verify.
---

# zen-verify

The real-verification executor (`zen-of-creativity` §2 — real verification). Verification confirms a known
expectation against reality; if the expectation itself is unknown, run `zen-spike`
first. The only evidence that counts is the real thing — inspected, not inferred.

## Pick the tier and technique for the artifact

- **Pure logic / data transform** → deterministic unit test. Assert **exact** outputs
  (value, count, ordering, error), not liveness.
- **Library / CLI** → run it with real inputs in a bounded environment; inspect real
  stdout/stderr/exit code/files produced.
- **Service / API** → call the real endpoint with real payloads; inspect the actual
  response schema, status, and failure shapes.
- **GUI app** → drive it for real, don't reason about it (the *discipline* is platform-neutral;
  the *tools* are examples — pick your platform's):
  - launch / activate / quit and simulate clicks/keystrokes via your platform's UI-automation —
    e.g. `osascript` (AppleScript / System Events) on macOS, `xdotool`/`ydotool` or AT-SPI on
    Linux, UI Automation (PowerShell) on Windows.
  - capture state to an image — e.g. `screencapture` on macOS, `scrot`/`grim` on Linux, the
    Snipping Tool / PowerShell on Windows — or the app's own export path.
  - **read the screenshot back** (view the image) to confirm what actually rendered —
    a screenshot you don't look at is not evidence.
  - compare against an expected frame/baseline when one exists.
  - reuse the project's own harness if present (an e2e script, frame renderers, comparison
    scripts) before writing new automation.
- **TUI / interactive terminal program** (REPL, ncurses app, a CLI that prompts, or any
  process you must *type into and read back* mid-run) → drive it in a real pseudo-terminal,
  not a one-shot pipe. `tmux` is the portable way: `tmux new-session -d -s s`,
  `tmux send-keys -t s '<input>' C-m` to type, `tmux capture-pane -p -t s` to read back what
  actually rendered. The **pane capture is the evidence** — a screenshot made of text. (A control
  key like `C-c`, or a slash command like `/clear`, is sent by naming it to `send-keys`.) The
  framework's own `e2e-zen-drive` harness is exactly this technique applied to a live Claude Code
  session — reuse or generalize it rather than writing new pane-driving from scratch.
- **Full end-to-end** → assemble the real pipeline as the user would run it; this
  catches what unit and integration tiers miss.

## Rules

- Real dependencies, real inputs, real outputs. A check that can silently pass while
  the real thing is broken is worse than none.
- Dependency genuinely unavailable → the verification **fails and says what's missing**.
  Never skip, degrade, or substitute a weaker check to get green.
- A failing real check is knowledge → route it through `zen-failure`.

## After verifying

Record the evidence on the contract clause: set `Status: verified` and link how it
was proven (`automated → <test>`, or `manual: <screenshot/e2e steps>`). Unverified
behavior is not done.

### Record the run, don't just claim it (C-024)

`Status: verified` must mean the test **actually ran green**, not that a test by that
name exists. For an `automated → <test>` clause, record the real run so the gate can
keep it honest:

```
node <zen>/hooks/zen-record-run.js --clause C-xxx -- <the real test command>
# <zen> = the IMPLICATION→MACHINE plugin's directory (the dir holding hooks/zen-record-run.js)
# e.g.  … --clause C-083 -- bash scripts/coverage.sh
```

This runs the command for real, captures its exit code + an output hash + a hash of
each linked test file, and writes `.zen/evidence/runs/C-xxx.json`. The Stop-gate then
flags that clause if the recorded run **failed** or went **stale** (a test file changed
since it last ran green). Recording the truth is one command — cheaper than faking it.
*Honest limit:* there is no external executor, so this proves diligence, not
incorruptibility; the real re-run is the release gate's job (see `zen-check`).
Re-record later with just `--rerun` (it replays the recorded command). A clause
that *newly* turns `verified` with an `automated` link will be **blocked** until a
fresh run is recorded (C-026) — so record, don't type.

**Policy lives in the command, not in the gate (C-027).** The gate's verdict is the
exit code; it never parses your log or a coverage %. So put the judgement in the
command: tests green → exit 0; **coverage as a floor** → make the coverage command
itself exit non-zero below threshold (then the recorded run enforces it for free — no
fuzzy %-parsing). Coverage catches "code not exercised", not "exercised but not
asserted", so it is a floor, never proof of meaningful tests — that is what exact
assertions and **E2E** (the apex tier above) are for; an E2E run records exactly like
any other (its script's exit code) and its frames are what you show the user.

**Never pipe the runner (C-049).** Run the suite bare (`node --test`), or with
`set -o pipefail` if you must trim output — `node --test 2>&1 | tail -30` exits with
*tail's* 0, so a red suite reads as success to everything keyed on the exit code
(the mid-turn tripwire goes blind; C-045). Trim with the runner's own reporter flags
instead. `zen-record-run` is safe either way — it spawns the runner itself.

### Visual / behavioral evidence (C-025)

For GUI / voice / E2E behavior a unit test can't see, the evidence is the **frames you
read back**: drive the real app, capture a **before** and an **after** frame (your
platform's screenshot tool — e.g. `screencapture`/`scrot`/`grim`), and view both to
confirm what rendered. Save them under `.zen/evidence/runs/` and reference
them from the clause. Optionally record a short screen video as a human-facing artifact
(attach it for the user) — but note an `.mp4` is for the human; the model verifies from
the captured frames, not the video.

**Bounding (don't drown in artifacts):** name frames **per-clause and OVERWRITE** them
(`C-xxx-before.png`, `C-xxx-after.png`) — never timestamp-accumulate, so disk stays
`O(clauses)`, not `O(rounds)`. Keep a **video only as a one-off** handed to the user,
never hoarded in `runs/`. Re-record only when the gate flags that clause stale (or at
the release re-run) — not every round; `runs/` is git-ignored, so none of this bloats
the repo.

### Adversarial pass before `verified` (C-035)

Run-evidence proves a test **ran green** — not that it asserts what matters. A test you
wrote can pass while checking the wrong thing or skipping the edge case that counts. For a
**behavioral** change, close that gap with the one check a tool can't make: **SPAWN the
`zen-refuter` subagent** (`agents/zen-refuter.md`) — do NOT grade your own test inline. A fresh
context that sees **only the diff and the clause's claim**, not your reasoning, and is tuned to
**refute** the result: the unasserted path, the missing edge case, the assertion that only proves
liveness. The agent that wrote the code stops being the one grading it — refuting your own test in
the same context that wrote it shares that context's blind spots, the very author-bias the fresh
spawn exists to remove, so **spawn it, don't simulate it**. (`/code-review` is a
zero-setup fallback, but it reviews the diff for bugs **blind to the clause** — `zen-refuter`
is handed the clause's claim as the rubric, which is the sharper question.)

**Keep it proportionate — the critic renders the escape, not a free-text waive.** Scope by blast
radius, but the no-ceremony judgment is now the refuter's own **`trivial`** verdict (no behavioral
surface): a typo, a pure rename, a one-line change whose correctness a single test obviously can't
fake. When the change IS behavioral and a self-written test could plausibly pass while being wrong,
**spawn the refuter — this is the rule, not a suggestion.** The cheap inline substitute (grading your
own test in-context) is the failure mode the spawn exists to prevent, not a shortcut through it.

**Record the verdict (C-041) — the spawn alone is no longer enough.** After the refuter returns its
last-line verdict, record it so the gate can see the critic ran:

```
node <zen>/hooks/zen-record-refute.js --clause C-xxx --verdict holds|trivial|refuted
```

A clause that *newly* turns `verified` is **blocked** until a fresh `holds`/`trivial` record exists —
the *requirement* that the critic ran is now a deterministic check (mirroring run-evidence C-026,
because wording alone fired the refuter 0/8 across a full E2E run), while the *verdict* stays the
critic's judgment. `refuted` means a real gap: fix the test, then re-refute. Editing THIS clause's own
test symbol re-stales its refute (C-043 pins the refute to the test symbol, so a sibling's edit to a
shared file does not re-refute it) — when your own symbol changed, re-refute.

**A refuter finding is a `zen-failure`, not a TODO list.** Route each through classify
(`bug | missing_feature | wrong_assumption | ambiguous_contract`) — it grows the contract or
fixes the code. Tell the reviewer to flag only gaps that affect correctness or the clause's
stated intent, never style: a reviewer asked for gaps will always find some, and chasing
those is the over-engineering to avoid. Mark the clause `verified` only once the real
findings are resolved.
