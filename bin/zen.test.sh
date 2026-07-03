#!/usr/bin/env bash
# Repeatable test for the Zen contract CLI (bin/zen.js) and the shared parser it is built on.
#
# Each case prints a `CASE: <id>` label; the framework's contract links C-033 to these ids via
# `automated → <id>`, and the gate's clause↔test grep resolves the link against THIS file. The
# headline invariant proved here: `zen drift`/`lint` agree with the Stop-gate's verdict, because
# both project the SINGLE shared parser (zen-shared.parseContract). Exit 0 = all pass.

set -u
NODE="${NODE:-node}"                                   # bare node from PATH — portable
HERE="$(cd "$(dirname "$0")" && pwd)"
ZEN="$HERE/zen.js"                                     # the CLI under test
HOOKS="$(cd "$HERE/../hooks" && pwd)"
GATE="$HOOKS/zen-reconcile-gate.js"
SHARED="$HOOKS/zen-shared.js"
REC="$HOOKS/zen-record-run.js"
REFUTE="$HOOKS/zen-record-refute.js"
fails=0
ok()  { echo "ok   - $1"; }
bad() { echo "FAIL - $1"; fails=$((fails+1)); }

# A minimal governed git repo. $1 = optional extra contract clause block appended after C-001.
new_repo() {
  local r; r="$(mktemp -d /tmp/zen-cli-test.XXXXXX)"
  ( cd "$r" && git init -q )
  mkdir -p "$r/.zen" "$r/Tests" "$r/Sources"
  printf 'func testRealOne() {}\n' > "$r/Tests/main.swift"
  printf 'audit.jsonl\nevidence/runs/\n' > "$r/.zen/.gitignore"
  { printf '# Contract Items\n## C-001: real\n- **Verification:** automated → testRealOne\n- **Status:** verified\n'; printf '%s' "${1:-}"; } > "$r/.zen/contract.md"
  ( cd "$r" && git add -A >/dev/null 2>&1 )
  printf '%s' "$r"
}

# Synthetic one-edit transcript so the gate has a turn to classify (code edit ⇒ turn-drift unless
# the contract is the edited file). $1 repo, $2 file edited.
mk_turn() {
  cat > "$1/t.jsonl" <<EOF
{"type":"user","message":{"role":"user","content":"do it"}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Edit","input":{"file_path":"$2"}}]}}
EOF
}
run_gate() { printf '{"stop_hook_active":false,"cwd":"%s","transcript_path":"%s"}' "$1" "$2" | "$NODE" "$GATE"; }

# ── CASE: zen_parse_shared — parseContract returns exact clause objects (the single source the gate,
# context, recorder and CLI all project). Assert id/kind/title/date/source/verified/links on a fixture.
out="$(SHARED="$SHARED" "$NODE" -e '
const {parseContract} = require(process.env.SHARED);
const t = [
  "# Contract Items",
  "## C-001: alpha",
  "- **Date:** 2026-01-01",
  "- **Source:** discovery",
  "- **Verification:** automated → testFoo, testBar | what they cover",
  "- **Status:** verified",
  "## C-002: beta",
  "- **Verification:** manual: by hand",
  "- **Status:** pending verification",
  "### P-001: gamma",
  "- **Date:** 2026-02-02",
  ""
].join("\n");
const cs = parseContract(t);
const a = cs.find(c=>c.id==="C-001"), b = cs.find(c=>c.id==="C-002"), p = cs.find(c=>c.id==="P-001");
const ok = cs.length===3
  && a.kind==="C" && a.title==="alpha" && a.date==="2026-01-01" && a.source==="discovery"
  && a.verified===true && JSON.stringify(a.links.automated)===JSON.stringify(["testFoo","testBar"])
  && b.verified===false && b.links.manual===true && b.links.automated.length===0
  && p.kind==="P" && p.date==="2026-02-02";
process.exit(ok?0:1);
' && echo PASS || echo FAIL)"
[ "$out" = PASS ] && ok zen_parse_shared || bad zen_parse_shared

# ── CASE: zen_next_id — next-id returns max existing + 1 for the kind.
r="$(new_repo "$(printf '## C-002: two\n- **Status:** verified\n## C-005: five\n- **Status:** verified\n')")"
out="$("$NODE" "$ZEN" --root "$r" next-id C)"
[ "$out" = "C-006" ] && ok zen_next_id || { echo "  got [$out]"; bad zen_next_id; }
rm -rf "$r"

# ── CASE: zen_next_id_empty — empty contract ⇒ C-001 (boundary).
r="$(mktemp -d /tmp/zen-cli-empty.XXXXXX)"; ( cd "$r" && git init -q ); mkdir -p "$r/.zen"
printf '# Contract Items\n' > "$r/.zen/contract.md"
out="$("$NODE" "$ZEN" --root "$r" next-id C)"
[ "$out" = "C-001" ] && ok zen_next_id_empty || { echo "  got [$out]"; bad zen_next_id_empty; }
rm -rf "$r"

# ── CASE: zen_list_filters — list --status verified returns ONLY verified clauses (exact count).
r="$(new_repo "$(printf '## C-002: pend\n- **Status:** pending verification\n## C-003: ok\n- **Status:** verified\n')")"
n="$("$NODE" "$ZEN" --root "$r" list --status verified | grep -c '^C-')"
[ "$n" = "2" ] && ok zen_list_filters || { echo "  verified count [$n] (want 2)"; bad zen_list_filters; }
rm -rf "$r"

# ── CASE: zen_show_outputs_clause — show prints the clause body verbatim.
r="$(new_repo)"
"$NODE" "$ZEN" --root "$r" show C-001 | grep -q 'C-001: real' && ok zen_show_outputs_clause || bad zen_show_outputs_clause
rm -rf "$r"

# ── CASE: zen_show_unknown_exits_nonzero — an unknown id exits non-zero (C-027).
r="$(new_repo)"
"$NODE" "$ZEN" --root "$r" show C-999 >/dev/null 2>&1; rc=$?
[ "$rc" -ne 0 ] && ok zen_show_unknown_exits_nonzero || bad zen_show_unknown_exits_nonzero
rm -rf "$r"

# ── CASE: zen_grep_finds — grep surfaces a clause whose body matches the term.
r="$(new_repo "$(printf '## C-002: needle\n- **Description:** a distinctive zqxw marker\n- **Status:** verified\n')")"
"$NODE" "$ZEN" --root "$r" grep zqxw | grep -q 'C-002' && ok zen_grep_finds || bad zen_grep_finds
rm -rf "$r"

# ── CASE: zen_links_resolves — links reports each automated link's resolution; a real test ⇒ RESOLVED.
r="$(new_repo)"
"$NODE" "$ZEN" --root "$r" links C-001 | grep -qi 'testRealOne' \
  && "$NODE" "$ZEN" --root "$r" links C-001 | grep -qi 'resolv' \
  && ok zen_links_resolves || bad zen_links_resolves
rm -rf "$r"

# ── CASE: zen_json_output — list --json emits a parseable JSON array of clauses.
r="$(new_repo)"
"$NODE" "$ZEN" --root "$r" list --json | "$NODE" -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const a=JSON.parse(s);process.exit(Array.isArray(a)&&a[0].id==="C-001"?0:1)})' \
  && ok zen_json_output || bad zen_json_output
rm -rf "$r"

# ── CASE: zen_status_summary — status reports verified/total counts.
r="$(new_repo "$(printf '## C-002: pend\n- **Status:** pending verification\n')")"
"$NODE" "$ZEN" --root "$r" status | grep -q '1/2' && ok zen_status_summary || { "$NODE" "$ZEN" --root "$r" status; bad zen_status_summary; }
rm -rf "$r"

# ── CASE: zen_lint_clean_exit0 — a clean contract (links resolve, no altitude/run drift) ⇒ exit 0.
r="$(new_repo)"
"$NODE" "$ZEN" --root "$r" lint >/dev/null 2>&1 && ok zen_lint_clean_exit0 || bad zen_lint_clean_exit0
rm -rf "$r"

# ── CASE: zen_lint_broken_exit_nonzero — a broken clause↔test link ⇒ lint exits non-zero (verdict in
# the exit code, C-027), and names the offending test.
r="$(new_repo "$(printf '## C-002: ghost\n- **Verification:** automated → testGhostXYZ\n- **Status:** verified\n')")"
out="$("$NODE" "$ZEN" --root "$r" lint 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && echo "$out" | grep -q 'testGhostXYZ' && ok zen_lint_broken_exit_nonzero || { echo "  rc=$rc out=$out"; bad zen_lint_broken_exit_nonzero; }
rm -rf "$r"

# ── CASE: zen_drift_agrees_with_gate — THE seal. Same broken-link repo: `zen drift` flags the SAME
# test the Stop-gate blocks on, because both project the shared parser. And on a clean repo, drift is
# empty exactly when the gate is silent. Disagreement here = the drift this whole CLI exists to kill.
r="$(new_repo "$(printf '## C-002: ghost\n- **Verification:** automated → testGhostABC\n- **Status:** verified\n')")"
mk_turn "$r" "$r/.zen/contract.md"                      # contract-only turn isolates the link check
gate_out="$(run_gate "$r" "$r/t.jsonl")"
cli_out="$("$NODE" "$ZEN" --root "$r" drift 2>&1)"
echo "$gate_out" | grep -q 'testGhostABC' && echo "$cli_out" | grep -q 'testGhostABC' \
  && ok zen_drift_agrees_with_gate || { echo "  gate=[$gate_out] cli=[$cli_out]"; bad zen_drift_agrees_with_gate; }
rm -rf "$r"

# ── CASE: zen_drift_clean_agrees — clean repo: the gate is silent AND `zen lint` exits 0 (the other
# half of agreement — neither reports drift).
r="$(new_repo)"; mk_turn "$r" "$r/.zen/contract.md"
gate_out="$(run_gate "$r" "$r/t.jsonl")"
"$NODE" "$ZEN" --root "$r" lint >/dev/null 2>&1; rc=$?
[ -z "$gate_out" ] && [ "$rc" -eq 0 ] && ok zen_drift_clean_agrees || { echo "  gate=[$gate_out] lint rc=$rc"; bad zen_drift_clean_agrees; }
rm -rf "$r"

# ── CASE: zen_verify_blocks_without_run — verify on an automated clause with NO fresh recorded run
# exits non-zero and DOES NOT write `verified` (it never types the word blind — C-024/C-026).
r="$(new_repo "$(printf '## C-002: claim\n- **Verification:** automated → testRealOne\n- **Status:** pending verification\n')")"
"$NODE" "$ZEN" --root "$r" verify C-002 >/dev/null 2>&1; rc=$?
[ "$rc" -ne 0 ] && grep -A3 'C-002: claim' "$r/.zen/contract.md" | grep -q 'pending verification' \
  && ok zen_verify_blocks_without_run || { echo "  rc=$rc"; grep -A3 'C-002: claim' "$r/.zen/contract.md"; bad zen_verify_blocks_without_run; }
rm -rf "$r"

# ── CASE: zen_verify_blocks_without_refute — record a fresh run but NO refuter pass; verify still exits
# non-zero and does NOT write `verified`. The CLI enforces the SAME refute requirement the Stop-gate does
# (C-041) — it must not be a happy-path that stamps `verified` with the critic skipped.
r="$(new_repo "$(printf '## C-002: claim\n- **Verification:** automated → testRealOne\n- **Status:** pending verification\n')")"
"$NODE" "$REC" --clause C-002 --root "$r" -- true >/dev/null 2>&1
"$NODE" "$ZEN" --root "$r" verify C-002 >/dev/null 2>&1; rc=$?
[ "$rc" -ne 0 ] && grep -A3 'C-002: claim' "$r/.zen/contract.md" | grep -q 'pending verification' \
  && ok zen_verify_blocks_without_refute || { echo "  rc=$rc"; grep -A3 'C-002: claim' "$r/.zen/contract.md"; bad zen_verify_blocks_without_refute; }
rm -rf "$r"

# ── CASE: zen_verify_writes_with_fresh_run — record a real run AND a refuter pass, THEN verify ⇒ exit 0
# and the clause's Status flips to verified (the honest path is the cheap one; both records are the way).
r="$(new_repo "$(printf '## C-002: claim\n- **Verification:** automated → testRealOne\n- **Status:** pending verification\n')")"
"$NODE" "$REC" --clause C-002 --root "$r" -- true >/dev/null 2>&1
"$NODE" "$REFUTE" --clause C-002 --root "$r" --verdict holds >/dev/null 2>&1
"$NODE" "$ZEN" --root "$r" verify C-002 >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && grep -A3 'C-002: claim' "$r/.zen/contract.md" | grep -q '\*\*Status:\*\* verified' \
  && ok zen_verify_writes_with_fresh_run || { echo "  rc=$rc"; grep -A3 'C-002: claim' "$r/.zen/contract.md"; bad zen_verify_writes_with_fresh_run; }
rm -rf "$r"

# ── CASE: zen_verify_unknown_exits_nonzero — verify on a non-existent clause exits non-zero.
r="$(new_repo)"
"$NODE" "$ZEN" --root "$r" verify C-999 >/dev/null 2>&1; rc=$?
[ "$rc" -ne 0 ] && ok zen_verify_unknown_exits_nonzero || bad zen_verify_unknown_exits_nonzero
rm -rf "$r"

# ── CASE: zen_bad_command_exits_nonzero — an unknown subcommand exits non-zero with usage.
r="$(new_repo)"
"$NODE" "$ZEN" --root "$r" frobnicate >/dev/null 2>&1; rc=$?
[ "$rc" -ne 0 ] && ok zen_bad_command_exits_nonzero || bad zen_bad_command_exits_nonzero
rm -rf "$r"

# ── CASE: zen_ungoverned_exits_nonzero — outside any governed project (no .zen/contract.md) ⇒ non-zero.
p="$(mktemp -d /tmp/zen-cli-ungov.XXXXXX)"
"$NODE" "$ZEN" --root "$p" list >/dev/null 2>&1; rc=$?
[ "$rc" -ne 0 ] && ok zen_ungoverned_exits_nonzero || bad zen_ungoverned_exits_nonzero
rm -rf "$p"

# ── CASE: zen_empty_contract — read ops on a header-only contract don't crash (list ⇒ empty, exit 0).
r="$(mktemp -d /tmp/zen-cli-empty2.XXXXXX)"; ( cd "$r" && git init -q ); mkdir -p "$r/.zen"
printf '# Contract Items\n' > "$r/.zen/contract.md"
out="$("$NODE" "$ZEN" --root "$r" list 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && [ -z "$(echo "$out" | grep '^C-')" ] && ok zen_empty_contract || { echo "  rc=$rc out=[$out]"; bad zen_empty_contract; }
rm -rf "$r"

# ── CASE: zen_handles_closed_pipe — a consumer closing the pipe early must NOT crash the CLI with
# EPIPE (the reader's choice is not our error). `status` writes two separate lines; `grep -q` matches
# the first and closes the pipe, so the second write hits a closed pipe — which must be swallowed.
r="$(new_repo "$(printf '## C-002: pend\n- **Status:** pending verification\n')")"
"$NODE" "$ZEN" --root "$r" status 2>"$r/err.txt" | grep -q 'clauses verified'
! grep -qi 'EPIPE' "$r/err.txt" && ok zen_handles_closed_pipe || { echo "  stderr=[$(cat "$r/err.txt")]"; bad zen_handles_closed_pipe; }
rm -rf "$r"

# ════════════════════ Phase 2 — write ops + status transitions ════════════════════

# ── CASE: zen_add_clause_c — add-clause C with prose from stdin: next-id heading, fields, pending.
r="$(new_repo)"
printf 'a brand new capability' | "$NODE" "$ZEN" --root "$r" add-clause C --title "New thing" --source discovery --date 2026-06-17 >/dev/null 2>&1
grep -q '^## C-002: New thing' "$r/.zen/contract.md" \
  && grep -q 'a brand new capability' "$r/.zen/contract.md" \
  && grep -A5 'C-002: New thing' "$r/.zen/contract.md" | grep -q 'pending verification' \
  && [ "$("$NODE" "$ZEN" --root "$r" next-id C)" = "C-003" ] \
  && ok zen_add_clause_c || { grep -A6 'C-002' "$r/.zen/contract.md"; bad zen_add_clause_c; }
rm -rf "$r"

# ── CASE: zen_add_clause_p — add-clause P lands under Pending Contract Deltas as ### with Proposed
# verification and NO Status (the P-delta format).
r="$(new_repo "$(printf '## Pending Contract Deltas\n### P-001: existing\n- **Date:** 2026-06-15\n- **Proposed verification:** TBD\n')")"
printf 'a parked idea' | "$NODE" "$ZEN" --root "$r" add-clause P --title "Maybe X" --date 2026-06-17 >/dev/null 2>&1
grep -q '^### P-002: Maybe X' "$r/.zen/contract.md" \
  && grep -A4 'P-002: Maybe X' "$r/.zen/contract.md" | grep -q 'Proposed verification' \
  && ok zen_add_clause_p || { grep -A6 'P-002' "$r/.zen/contract.md"; bad zen_add_clause_p; }
rm -rf "$r"

# ── CASE: zen_link_adds_test — link adds an automated link to a clause that had none.
r="$(new_repo "$(printf '## C-002: bare\n- **Description:** no link yet\n- **Status:** pending verification\n')")"
"$NODE" "$ZEN" --root "$r" link C-002 --test testRealOne >/dev/null 2>&1
grep -A4 'C-002: bare' "$r/.zen/contract.md" | grep -q 'automated → testRealOne' \
  && "$NODE" "$ZEN" --root "$r" links C-002 | grep -qi 'resolv' \
  && ok zen_link_adds_test || { grep -A4 'C-002: bare' "$r/.zen/contract.md"; bad zen_link_adds_test; }
rm -rf "$r"

# ── CASE: zen_link_replaces_placeholder — linking a clause whose Verification is only the add-clause
# placeholder yields a clean `automated → <name>` line, NOT the placeholder smeared after a `|`.
r="$(new_repo)"
printf 'fresh cap' | "$NODE" "$ZEN" --root "$r" add-clause C --title "Fresh" --date 2026-06-17 >/dev/null 2>&1
"$NODE" "$ZEN" --root "$r" link C-002 --test testRealOne >/dev/null 2>&1
grep -A4 'C-002: Fresh' "$r/.zen/contract.md" | grep -q '\*\*Verification:\*\* automated → testRealOne$' \
  && ok zen_link_replaces_placeholder || { grep -A5 'C-002: Fresh' "$r/.zen/contract.md"; bad zen_link_replaces_placeholder; }
rm -rf "$r"

# ── CASE: zen_link_appends — link appends to an existing automated list (comma-separated).
r="$(new_repo "$(printf '## C-002: has\n- **Verification:** automated → testRealOne\n- **Status:** verified\n')")"
"$NODE" "$ZEN" --root "$r" link C-002 --test testSecond >/dev/null 2>&1
grep -A3 'C-002: has' "$r/.zen/contract.md" | grep -q 'automated → testRealOne, testSecond' \
  && ok zen_link_appends || { grep -A3 'C-002: has' "$r/.zen/contract.md"; bad zen_link_appends; }
rm -rf "$r"

# ── CASE: zen_evidence_creates_file_and_link — evidence creates .zen/evidence/<id>.md AND adds the
# Evidence line to the clause (idempotent: re-running doesn't duplicate).
r="$(new_repo "$(printf '## C-002: big\n- **Verification:** automated → testRealOne\n- **Status:** verified\n')")"
"$NODE" "$ZEN" --root "$r" evidence C-002 >/dev/null 2>&1
"$NODE" "$ZEN" --root "$r" evidence C-002 >/dev/null 2>&1   # second run: must stay idempotent
[ -f "$r/.zen/evidence/C-002.md" ] \
  && [ "$(grep -c 'Evidence:.*evidence/C-002.md' "$r/.zen/contract.md")" = "1" ] \
  && ok zen_evidence_creates_file_and_link || { grep -A4 'C-002: big' "$r/.zen/contract.md"; bad zen_evidence_creates_file_and_link; }
rm -rf "$r"

# ── CASE: zen_set_source — set-source updates the Source field.
r="$(new_repo "$(printf '## C-002: s\n- **Source:** discovery\n- **Status:** verified\n')")"
"$NODE" "$ZEN" --root "$r" set-source C-002 --to failure >/dev/null 2>&1
grep -A2 'C-002: s' "$r/.zen/contract.md" | grep -q '\*\*Source:\*\* failure' \
  && ok zen_set_source || { grep -A2 'C-002: s' "$r/.zen/contract.md"; bad zen_set_source; }
rm -rf "$r"

# ── CASE: zen_archive_moves_out — archive removes the clause from the LIVE contract (compaction).
r="$(new_repo "$(printf '## C-002: dead\n- **Status:** verified\n')")"
"$NODE" "$ZEN" --root "$r" archive C-002 >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && ! grep -q '^## C-002:' "$r/.zen/contract.md" \
  && "$NODE" "$ZEN" --root "$r" show C-002 >/dev/null 2>&1; sc=$?
[ "$rc" -eq 0 ] && ! grep -q '^## C-002:' "$r/.zen/contract.md" && [ "$sc" -ne 0 ] \
  && ok zen_archive_moves_out || { echo "  rc=$rc sc=$sc"; bad zen_archive_moves_out; }
rm -rf "$r"

# ── CASE: zen_archive_preserves_in_archive — the archived clause is PRESERVED in .zen/archive/
# (never physically rm'd — the audit trace survives, C-023), with a dated marker.
r="$(new_repo "$(printf '## C-002: dead\n- **Status:** verified\n')")"
"$NODE" "$ZEN" --root "$r" archive C-002 >/dev/null 2>&1
[ -f "$r/.zen/archive/contract.md" ] && grep -q '## C-002: dead' "$r/.zen/archive/contract.md" \
  && grep -qi 'archived' "$r/.zen/archive/contract.md" \
  && ok zen_archive_preserves_in_archive || { cat "$r/.zen/archive/contract.md" 2>/dev/null; bad zen_archive_preserves_in_archive; }
rm -rf "$r"

# ── CASE: zen_archive_unknown_exits_nonzero — archiving a non-existent clause exits non-zero.
r="$(new_repo)"
"$NODE" "$ZEN" --root "$r" archive C-999 >/dev/null 2>&1; rc=$?
[ "$rc" -ne 0 ] && ok zen_archive_unknown_exits_nonzero || bad zen_archive_unknown_exits_nonzero
rm -rf "$r"

# ── CASE: zen_supersede_marks_and_moves — supersede archives <id> with a "superseded by <id2>" reason;
# <id2> must exist (here C-001 does).
r="$(new_repo "$(printf '## C-002: old\n- **Status:** verified\n')")"
"$NODE" "$ZEN" --root "$r" supersede C-002 --by C-001 >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && ! grep -q '^## C-002:' "$r/.zen/contract.md" \
  && grep -q 'superseded by C-001' "$r/.zen/archive/contract.md" \
  && ok zen_supersede_marks_and_moves || { echo "  rc=$rc"; cat "$r/.zen/archive/contract.md" 2>/dev/null; bad zen_supersede_marks_and_moves; }
rm -rf "$r"

# ── CASE: zen_supersede_unknown_target — superseding by a non-existent clause exits non-zero and does
# NOT move the clause (no half-done transition).
r="$(new_repo "$(printf '## C-002: old\n- **Status:** verified\n')")"
"$NODE" "$ZEN" --root "$r" supersede C-002 --by C-404 >/dev/null 2>&1; rc=$?
[ "$rc" -ne 0 ] && grep -q '^## C-002:' "$r/.zen/contract.md" \
  && ok zen_supersede_unknown_target || { echo "  rc=$rc"; bad zen_supersede_unknown_target; }
rm -rf "$r"

# ── CASE: zen_shelve_moves_delta — shelve archives a pending P-delta out of the live contract.
r="$(new_repo "$(printf '## Pending Contract Deltas\n### P-001: parked\n- **Date:** 2026-06-15\n- **Proposed verification:** TBD\n')")"
"$NODE" "$ZEN" --root "$r" shelve P-001 >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && ! grep -q '^### P-001:' "$r/.zen/contract.md" \
  && grep -q 'P-001: parked' "$r/.zen/archive/contract.md" && grep -qi 'shelved' "$r/.zen/archive/contract.md" \
  && ok zen_shelve_moves_delta || { echo "  rc=$rc"; cat "$r/.zen/archive/contract.md" 2>/dev/null; bad zen_shelve_moves_delta; }
rm -rf "$r"

# ── CASE: zen_promote_p_to_c — promote graduates a P-delta into a C-clause (next free C id), removed
# from Pending, heading becomes ## C-xxx, with a Status line.
r="$(new_repo "$(printf '## Pending Contract Deltas\n### P-001: ripe\n- **Date:** 2026-06-15\n- **Description:** ready now\n- **Proposed verification:** TBD\n')")"
"$NODE" "$ZEN" --root "$r" promote P-001 >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && grep -q '^## C-002: ripe' "$r/.zen/contract.md" \
  && ! grep -q '^### P-001:' "$r/.zen/contract.md" \
  && grep -A6 'C-002: ripe' "$r/.zen/contract.md" | grep -qi 'Status' \
  && ok zen_promote_p_to_c || { echo "  rc=$rc"; grep -A6 'C-002: ripe' "$r/.zen/contract.md"; bad zen_promote_p_to_c; }
rm -rf "$r"

# ── CASE: zen_promote_specific_id — promote to an explicitly named C id.
r="$(new_repo "$(printf '## Pending Contract Deltas\n### P-001: pick\n- **Proposed verification:** TBD\n')")"
"$NODE" "$ZEN" --root "$r" promote P-001 C-050 >/dev/null 2>&1
grep -q '^## C-050: pick' "$r/.zen/contract.md" && ! grep -q '^### P-001:' "$r/.zen/contract.md" \
  && ok zen_promote_specific_id || { grep -n 'C-050\|P-001' "$r/.zen/contract.md"; bad zen_promote_specific_id; }
rm -rf "$r"

# ── CASE: zen_writes_keep_contract_parseable — after a full write+transition sequence the contract
# still parses cleanly and lint stays exit 0 (the mutations never corrupt the file).
r="$(new_repo)"
printf 'desc' | "$NODE" "$ZEN" --root "$r" add-clause C --title "T1" --date 2026-06-17 >/dev/null 2>&1
"$NODE" "$ZEN" --root "$r" link C-002 --test testRealOne >/dev/null 2>&1
"$NODE" "$ZEN" --root "$r" lint >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && [ "$("$NODE" "$ZEN" --root "$r" list | grep -c '^C-')" = "2" ] \
  && ok zen_writes_keep_contract_parseable || { echo "  lint rc=$rc"; "$NODE" "$ZEN" --root "$r" list; bad zen_writes_keep_contract_parseable; }
rm -rf "$r"

# ── CASE: zen_installer_shim — install.sh --shim-only puts a `zen` shim (→ bin/zen.js) on a PATH dir.
# Meaningful only in the BUILT layout (install.sh and bin/ are siblings); skipped in the dogfood, where
# install.sh lives under plugin/ and has no sibling bin/ (logged, not a false pass).
INST="$HERE/../install.sh"
if [ -f "$INST" ] && [ -f "$HERE/zen.js" ]; then
  sd="$(mktemp -d /tmp/zen-shim.XXXXXX)"
  bash "$INST" --shim-only "$sd" >/dev/null 2>&1
  [ -L "$sd/zen" ] && "$sd/zen" --help | grep -q 'USAGE' && ok zen_installer_shim || bad zen_installer_shim
  rm -rf "$sd"
else
  echo "skip - zen_installer_shim (not a built tree: install.sh has no sibling bin/)"
fi

# ── CASE: context_emits_cli_invocation — the SessionStart index must tell the model HOW to run the
# CLI (`node <plugin>/bin/zen.js`): a marketplace install never runs install.sh, so no shim is on
# PATH and a bare `zen` fails on a stranger's machine (C-050). Checked in BOTH branches: governed
# (index) and ungoverned-git (adoption nudge).
CTX="$HOOKS/zen-context.js"
r="$(new_repo)"
out="$(printf '{"cwd":"%s"}' "$r" | "$NODE" "$CTX")"
echo "$out" | grep -q 'bin/zen\.js' && ok context_emits_cli_invocation_governed || bad context_emits_cli_invocation_governed
rm -rf "$r"
u="$(mktemp -d /tmp/zen-ctx-ungov.XXXXXX)"; ( cd "$u" && git init -q )
out="$(printf '{"cwd":"%s"}' "$u" | "$NODE" "$CTX")"
echo "$out" | grep -q 'bin/zen\.js' && ok context_emits_cli_invocation_ungoverned || bad context_emits_cli_invocation_ungoverned
rm -rf "$u"

echo "---"
if [ "$fails" -eq 0 ]; then echo "all zen cli cases passed"; exit 0; fi
echo "$fails zen cli case(s) failed"; exit 1
