#!/usr/bin/env bash
# Repeatable test for the mid-turn verification-failure tripwire (zen-post-tool-failure-tripwire.js, C-045).
#
# Each case prints `CASE: <id>`; the framework's contract links to those ids via `automated → <id>`,
# and the Stop-gate's clause↔test grep resolves the link against THIS file. Delete a case ⇒ link breaks.
#
# Exit 0 = all cases pass, non-zero = at least one failed.

set -u
NODE="${NODE:-node}"
HOOK="$(cd "$(dirname "$0")" && pwd)/zen-post-tool-failure-tripwire.js"
fails=0
ok()  { echo "ok   - $1"; }
bad() { echo "FAIL - $1 :: $2"; fails=$((fails+1)); }

# A governed tree: just needs .zen/contract.md at/above cwd (findGovernedRoot). No git needed —
# the tripwire reads stdin + the contract's existence only.
new_governed() {
  local r; r="$(mktemp -d /tmp/zen-trip-test.XXXXXX)"
  mkdir -p "$r/.zen"
  printf 'audit.jsonl\n' > "$r/.zen/.gitignore"
  printf '# Contract\n## C-001: real\n' > "$r/.zen/contract.md"
  printf '%s' "$r"
}
new_ungoverned() { mktemp -d /tmp/zen-trip-bare.XXXXXX; }

# JSON-encode an arbitrary command string safely (handles quotes/spaces).
jstr() { printf '%s' "$1" | "$NODE" -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>process.stdout.write(JSON.stringify(s)))'; }

# $1 cwd, $2 command  -> feed a PostToolUseFailure payload to the hook. Captures stdout in $OUT and the
# hook's EXIT CODE in $RC (the pipeline's exit = node's exit), so a case can assert the hook never blocks.
OUT=""; RC=0
run_fail() {
  OUT="$(printf '{"hook_event_name":"PostToolUseFailure","tool_name":"Bash","cwd":"%s","tool_input":{"command":%s},"error":"Command failed with exit code 1"}' "$1" "$(jstr "$2")" | "$NODE" "$HOOK")"
  RC=$?
}

# CASE: tripwire_nudges_on_verification_failure — a failed `npm test` ⇒ additionalContext nudge that
# routes to zen-failure, AND the hook exits 0 (it must never block — exit 2 is a Claude Code block signal).
r="$(new_governed)"; run_fail "$r" "npm test"
{ [ "$RC" -eq 0 ] && echo "$OUT" | grep -q '"additionalContext"' && echo "$OUT" | grep -q 'zen-failure'; } \
  && ok tripwire_nudges_on_verification_failure || bad tripwire_nudges_on_verification_failure "rc=$RC out=$OUT"
rm -rf "$r"

# CASE: tripwire_nudges_on_compound_env_verification — battle-tested split+env-strip: `cd app && CI=1 npm test`
# still matches the verification step (the v-pi-zen fragment that paid the false-negative cost). Exits 0.
r="$(new_governed)"; run_fail "$r" "cd app && CI=1 npm test"
{ [ "$RC" -eq 0 ] && echo "$OUT" | grep -q '"additionalContext"'; } \
  && ok tripwire_nudges_on_compound_env_verification || bad tripwire_nudges_on_compound_env_verification "rc=$RC out=$OUT"
rm -rf "$r"

# CASE: tripwire_nudges_on_non_npm_runner — the host-agnostic broadening: a failed `eslint .` (not in the
# original v-pi-zen npm-centric set) must also nudge, since the clause scopes to test/build/typecheck/lint.
r="$(new_governed)"; run_fail "$r" "eslint ."
{ [ "$RC" -eq 0 ] && echo "$OUT" | grep -q '"additionalContext"'; } \
  && ok tripwire_nudges_on_non_npm_runner || bad tripwire_nudges_on_non_npm_runner "rc=$RC out=$OUT"
rm -rf "$r"

# CASE: tripwire_silent_on_probe_failure — a failed probe (`grep -q foo bar`, exit 1 = no match) must emit
# NOTHING and still exit 0; only verification failures nudge. (Also guards against a probe that merely
# mentions a runner string — anchored ^ patterns keep `grep -q 'npm test' f` silent.)
r="$(new_governed)"; run_fail "$r" "grep -q 'npm test' bar"
{ [ "$RC" -eq 0 ] && [ -z "$OUT" ]; } \
  && ok tripwire_silent_on_probe_failure || bad tripwire_silent_on_probe_failure "rc=$RC out=$OUT"
rm -rf "$r"

# CASE: tripwire_silent_when_ungoverned — no .zen/contract.md at/above cwd ⇒ passive, no output even for
# a verification failure, exit 0.
r="$(new_ungoverned)"; run_fail "$r" "npm test"
{ [ "$RC" -eq 0 ] && [ -z "$OUT" ]; } \
  && ok tripwire_silent_when_ungoverned || bad tripwire_silent_when_ungoverned "rc=$RC out=$OUT"
rm -rf "$r"

# CASE: tripwire_heartbeats_one_line_per_fire — one governed invocation appends exactly one line to
# .zen/audit.jsonl carrying the {event, fired} record (liveness — a dead hook leaves no line).
r="$(new_governed)"; run_fail "$r" "npm test"
lines="$(wc -l < "$r/.zen/audit.jsonl" 2>/dev/null | tr -d ' ')"
{ [ "$lines" = "1" ] && grep -q '"event":"verification_failure_tripwire"' "$r/.zen/audit.jsonl" && grep -q '"fired":true' "$r/.zen/audit.jsonl"; } \
  && ok tripwire_heartbeats_one_line_per_fire || bad tripwire_heartbeats_one_line_per_fire "lines=$lines"
rm -rf "$r"

# CASE: tripwire_fails_open_on_malformed_input — garbage stdin ⇒ exit 0, no crash, no output.
out="$(printf 'not json at all' | "$NODE" "$HOOK"; echo "rc=$?")"
echo "$out" | grep -q 'rc=0' && [ "$(printf 'not json' | "$NODE" "$HOOK")" = "" ] \
  && ok tripwire_fails_open_on_malformed_input || bad tripwire_fails_open_on_malformed_input "$out"

echo "---"
[ "$fails" -eq 0 ] && echo "ALL PASS" || { echo "$fails FAILED"; exit 1; }
