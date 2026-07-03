#!/usr/bin/env bash
# Repeatable test for the Zen Stop-hook gate (zen-reconcile-gate.js).
#
# Each case prints a `CASE: <id>` label. The framework's own contract links to those ids via
# `automated → <id>`; the gate's own clause↔test grep resolves the link against THIS
# file's content. Delete a case ⇒ its link breaks ⇒ the gate flags it. That is the
# system testing itself.
#
# Exit 0 = all cases pass, non-zero = at least one failed.

set -u
NODE="${NODE:-node}" # bare node from PATH — portable (the distributable plugin bundles this file)
HOOK="$(cd "$(dirname "$0")" && pwd)/zen-reconcile-gate.js"
CTX="$(cd "$(dirname "$0")" && pwd)/zen-context.js"
REC="$(cd "$(dirname "$0")" && pwd)/zen-record-run.js"
REFUTE="$(cd "$(dirname "$0")" && pwd)/zen-record-refute.js"
SHARED="$(cd "$(dirname "$0")" && pwd)/zen-shared.js"
fails=0
ok() { echo "ok   - $1"; }
bad() {
	echo "FAIL - $1"
	fails=$((fails + 1))
}

# Build a minimal governed git repo. $1 = optional extra contract clause block.
new_repo() {
	local r
	r="$(mktemp -d /tmp/zen-gate-test.XXXXXX)"
	(cd "$r" && git init -q && git config user.email t@t && git config user.name t)
	mkdir -p "$r/.zen" "$r/Tests" "$r/Sources"
	printf 'func testRealOne() {}\n' >"$r/Tests/main.swift"
	printf 'audit.jsonl\n' >"$r/.zen/.gitignore"
	{
		printf '# Contract Items\n## C-001: real\n- **Verification:** automated → testRealOne\n'
		printf '%s' "${1:-}"
	} >"$r/.zen/contract.md"
	(cd "$r" && git add -A >/dev/null 2>&1) # staged, NOT committed (no HEAD): link / run-evidence / no-baseline cases rely on this
	printf '%s' "$r"
}

# Commit the staged baseline so the working tree is clean. REQUIRED to test turn-drift, which the gate
# now computes from git (C-036): with an uncommitted baseline every file reads as "changed".
commit() { (cd "$1" && git commit -qm base >/dev/null 2>&1); }

# Apply a REAL working-tree change. The gate detects edits from the git working tree (changedPaths),
# not a transcript, so a test drives it by actually touching files. $1 = repo (unused), $2 = path,
# $3 = ignored (kept so existing call sites read the same). The path's extension drives classify().
mk_turn() {
	mkdir -p "$(dirname "$2")"
	printf '\nedit\n' >>"$2"
} # leading \n: the contract built via $() lost its trailing newline, so append on a fresh line

run_hook() { # $1 cwd, $2 ignored (was transcript), $3 stop_hook_active(true/false, default false)
	printf '{"stop_hook_active":%s,"cwd":"%s"}' "${3:-false}" "$1" | "$NODE" "$HOOK"
}

# CASE: gate_blocks_code_only — code edited, contract untouched ⇒ block
r="$(new_repo)"
commit "$r"
mk_turn "$r" "$r/Sources/Foo.swift" Edit
out="$(run_hook "$r")"
echo "$out" | grep -q '"decision":"block"' && ok gate_blocks_code_only || bad gate_blocks_code_only
rm -rf "$r"

# CASE: gate_code_named_like_test_still_blocks — a real CODE file whose name merely contains the
# substring "test"/"spec" (latest.swift, inspector.js) must classify as code, not test, so a code-only
# turn still blocks. The old bare-substring classifier mis-typed these as "test" and let them slip.
r="$(new_repo)"
commit "$r"
mk_turn "$r" "$r/Sources/latest.swift" Edit
out="$(run_hook "$r")"
echo "$out" | grep -q '"decision":"block"' && ok gate_code_named_like_test_still_blocks || bad gate_code_named_like_test_still_blocks
rm -rf "$r"

# CASE: gate_blocks_html_only — a browser project's logic/markup lives in index.html; editing it with no
# contract move must block (E2E run 5: inline index.html classified "other" → turn-drift went blind to
# web source). .htm shares this exact code path (CODE_EXT.has(ext)). C-001.
r="$(new_repo)"
commit "$r"
mk_turn "$r" "$r/index.html" Edit
out="$(run_hook "$r")"
echo "$out" | grep -q '"decision":"block"' && ok gate_blocks_html_only || bad gate_blocks_html_only
rm -rf "$r"

# CASE: gate_blocks_css_only — style is a web capability's surface too; a .css-only edit with no contract
# move blocks. The distinct (non-.html) extension proves the set, not just one branch. C-001.
r="$(new_repo)"
commit "$r"
mk_turn "$r" "$r/style.css" Edit
out="$(run_hook "$r")"
echo "$out" | grep -q '"decision":"block"' && ok gate_blocks_css_only || bad gate_blocks_css_only
rm -rf "$r"

# CASE: gate_unrelated_contract_md_not_the_contract — a file named contract.md OUTSIDE .zen/ (e.g.
# docs/contract.md) must NOT count as "the contract was touched"; only .zen/contract.md does. Editing
# code + such a file must still block (turn-drift), not be silenced by the unrelated contract.md.
r="$(new_repo)"
commit "$r"
mk_turn "$r" "$r/Sources/Foo.swift" Edit
mk_turn "$r" "$r/docs/contract.md" Edit # a contract.md OUTSIDE .zen/ is NOT the governed contract
out="$(run_hook "$r")"
echo "$out" | grep -q '"decision":"block"' && ok gate_unrelated_contract_md_not_the_contract || bad gate_unrelated_contract_md_not_the_contract
rm -rf "$r"

# CASE: gate_silent_when_contract_touched — code + contract edited, no broken links ⇒ silent
r="$(new_repo)"
commit "$r"
mk_turn "$r" "$r/Sources/Foo.swift" Edit
mk_turn "$r" "$r/.zen/contract.md" Edit
out="$(run_hook "$r")"
[ -z "$out" ] && ok gate_silent_when_contract_touched || bad gate_silent_when_contract_touched
rm -rf "$r"

# CASE: gate_passive_ungoverned — no .zen ⇒ silent
p="$(mktemp -d)"
r="$(new_repo)"
mk_turn "$r" "$r/Sources/Foo.swift" Edit
out="$(run_hook "$p" "$r/t.jsonl" false)"
[ -z "$out" ] && ok gate_passive_ungoverned || bad gate_passive_ungoverned
rm -rf "$p" "$r"

# CASE: gate_detects_broken_link — clause claims a test that does not exist ⇒ surfaced
r="$(new_repo "$(printf '## C-002: fake\n- **Verification:** automated → testGhostXYZ\n')")"
mk_turn "$r" "$r/Sources/Foo.swift" Edit
out="$(run_hook "$r" "$r/t.jsonl" false)"
echo "$out" | grep -q 'testGhostXYZ' && ok gate_detects_broken_link || bad gate_detects_broken_link
rm -rf "$r"

# CASE: gate_link_finds_untracked_test — a test written this turn but NOT yet `git add`ed still
# resolves (git grep --untracked), so the normal write-clause-and-test-together flow is not
# false-flagged. testUntrackedXYZ exists on disk but is untracked; it must NOT appear as broken.
r="$(new_repo "$(printf '## C-002: fresh\n- **Verification:** automated → testUntrackedXYZ\n')")"
printf 'func testUntrackedXYZ() {}\n' >"$r/Tests/extra.swift" # written AFTER new_repo's git add ⇒ untracked
mk_turn "$r" "$r/.zen/contract.md" Edit                       # contract-only turn isolates link-check
out="$(run_hook "$r" "$r/t.jsonl" false)"
[ -z "$out" ] && ! echo "$out" | grep -q 'testUntrackedXYZ' && ok gate_link_finds_untracked_test || bad gate_link_finds_untracked_test
rm -rf "$r"

# CASE: gate_link_accepts_path_token — a link written as a PATH (`automated → Checks/deep/real.test.js`)
# must resolve to that file, not be truncated at the first `/` (the demo-caught tokenizer bug: the
# token regex stopped at `/`, so `test/mdtoc.test.js` became `test` and content-matched the wrong
# file — freshness then keyed on README instead of the test; C-048).
r="$(new_repo "$(printf '## C-002: pathlink\n- **Verification:** automated → Checks/deep/real.test.js\n')")"
mkdir -p "$r/Checks/deep" && printf 'assert(1)\n' >"$r/Checks/deep/real.test.js"
mk_turn "$r" "$r/.zen/contract.md" Edit                       # contract-only turn isolates link-check
out="$(run_hook "$r" "$r/t.jsonl" false)"
[ -z "$out" ] && ok gate_link_accepts_path_token || bad gate_link_accepts_path_token "$out"
rm -rf "$r"

# CASE: gate_link_unverifiable_when_non_git — a governed project that is NOT a git repo cannot run
# git grep; the link check is then *unverifiable* and must be SKIPPED, not reported as all-broken.
# testRealOne exists on disk; with no git the gate must stay silent (linksVerifiable:false), and the
# audit must record that the links were not verified rather than a false brokenLinks count.
r="$(mktemp -d /tmp/zen-gate-nongit.XXXXXX)" # deliberately NO git init
mkdir -p "$r/.zen" "$r/Tests"
printf 'func testRealOne() {}\n' >"$r/Tests/main.swift"
printf 'audit.jsonl\n' >"$r/.zen/.gitignore"
printf '# Contract Items\n## C-001: real\n- **Verification:** automated → testRealOne\n' >"$r/.zen/contract.md"
mk_turn "$r" "$r/.zen/contract.md" Edit # contract-only turn isolates link-check from turn-drift
out="$(run_hook "$r" "$r/t.jsonl" false)"
[ -z "$out" ] &&
	! echo "$out" | grep -qi 'broken\|testRealOne' &&
	grep -q '"linksVerifiable":false' "$r/.zen/audit.jsonl" &&
	ok gate_link_unverifiable_when_non_git || bad gate_link_unverifiable_when_non_git
rm -rf "$r"

# CASE: gate_checks_all_links_no_cap — a ghost link well past the old 60-name cap is still flagged,
# proving there is no silent cap: every declared link is verified, not just the first 60 in file order.
# 60 distinct real test names (testGen01..60, present on disk) precede a 61st distinct ghost name.
block="$(
	for i in $(seq -w 1 60); do printf '## C-9%s: real-%s\n- **Verification:** automated → testGen%s\n' "$i" "$i" "$i"; done
	printf '## C-999: ghost-past-cap\n- **Verification:** automated → testGhostPastCap\n'
)"
r="$(new_repo "$block")"
for i in $(seq -w 1 60); do printf 'func testGen%s() {}\n' "$i"; done >"$r/Tests/many.swift"
mk_turn "$r" "$r/.zen/contract.md" Edit # contract-only turn isolates link-check
out="$(run_hook "$r" "$r/t.jsonl" false)"
echo "$out" | grep -q 'testGhostPastCap' && ok gate_checks_all_links_no_cap || bad gate_checks_all_links_no_cap
rm -rf "$r"

# CASE: gate_link_tolerates_prose — names may be a comma-list with (parens) and trailing |prose;
# a real test in that form is NOT flagged, a ghost in the list still IS, prose is not a name.
r="$(new_repo "$(printf '## C-002: list\n- **Verification:** automated → testRealOne (does a, b, c) | extra prose\n## C-003: ghost-in-list\n- **Verification:** automated → testRealOne, testGhostABC\n')")"
mk_turn "$r" "$r/.zen/contract.md" Edit
out="$(run_hook "$r" "$r/t.jsonl" false)"
echo "$out" | grep -q 'testGhostABC' &&
	! echo "$out" | grep -qE '• *testRealOne|prose|does a' &&
	ok gate_link_tolerates_prose || bad gate_link_tolerates_prose
rm -rf "$r"

# CASE: gate_link_parses_only_verification_field — a clause whose DESCRIPTION prose contains
# "automated → <x>" must NOT contribute link names; only the **Verification** field does. (C-026's
# real description "claims an `automated → <test>`, or the gate blocks" injected the bogus token "or",
# which git-grep matches inside ".gitignore" — a silent false link.) Here the prose names a ghost that
# exists nowhere; if it leaked into the link set it would be flagged broken. The real Verification link
# (testRealOne) resolves, so a fixed parser stays silent.
r="$(new_repo "$(printf '## C-002: prose\n- **Description:** the clause claims an automated → ghostFromProseXYZ, or the gate blocks.\n- **Verification:** automated → testRealOne\n')")"
mk_turn "$r" "$r/.zen/contract.md" Edit
out="$(run_hook "$r" "$r/t.jsonl" false)"
[ -z "$out" ] && ! echo "$out" | grep -q 'ghostFromProseXYZ' && ok gate_link_parses_only_verification_field || bad gate_link_parses_only_verification_field
rm -rf "$r"

# CASE: gate_keeps_valid_link — an existing test (testRealOne) is NOT flagged as broken
r="$(new_repo)"
mk_turn "$r" "$r/.zen/contract.md" Edit # contract-only turn, no code
out="$(run_hook "$r" "$r/t.jsonl" false)"
[ -z "$out" ] && ok gate_keeps_valid_link || bad gate_keeps_valid_link
rm -rf "$r"

# CASE: gate_writes_audit — every fire appends a heartbeat line to .zen/audit.jsonl
r="$(new_repo)"
mk_turn "$r" "$r/Sources/Foo.swift" Edit
run_hook "$r" "$r/t.jsonl" false >/dev/null
grep -q '"event":"stop_gate"' "$r/.zen/audit.jsonl" && ok gate_writes_audit || bad gate_writes_audit
rm -rf "$r"

# CASE: gate_guard_stop_active — stop_hook_active=true ⇒ no output (no loop)
r="$(new_repo)"
mk_turn "$r" "$r/Sources/Foo.swift" Edit
out="$(run_hook "$r" "$r/t.jsonl" true)"
[ -z "$out" ] && ok gate_guard_stop_active || bad gate_guard_stop_active
rm -rf "$r"

# CASE: gate_fails_open — malformed input must never crash or block: the outer try/catch swallows it
# and exits 0 (a backstop must never wedge a session). No governed root needed — the parse fails first.
out="$(printf 'not json at all' | "$NODE" "$HOOK")"
rc=$?
[ -z "$out" ] && [ $rc -eq 0 ] && ok gate_fails_open || bad gate_fails_open

# Build a >40-line clause body (no Evidence link) to trip the altitude check.
big_clause() { # $1 = optional "evidence" to inject an Evidence line
	printf '## C-002: bloated\n- **Verification:** automated → testRealOne\n'
	[ "${1:-}" = "evidence" ] && printf -- '- **Evidence:** .zen/evidence/C-002.md\n'
	for i in $(seq 1 50); do printf -- '- spike note line %s\n' "$i"; done
}

# CASE: gate_flags_altitude_drift — an oversized clause with no Evidence link is surfaced.
# Use a contract-only turn so this isolates altitude drift from turn-drift.
r="$(new_repo "$(big_clause)")"
mk_turn "$r" "$r/.zen/contract.md" Edit
out="$(run_hook "$r" "$r/t.jsonl" false)"
echo "$out" | grep -qi 'altitude' && echo "$out" | grep -q 'C-002' && ok gate_flags_altitude_drift || bad gate_flags_altitude_drift
rm -rf "$r"

# CASE: gate_altitude_ok_with_evidence — the same oversized clause WITH an Evidence link is silent
# (no false positive on a clause that correctly offloaded its lab-notebook).
r="$(new_repo "$(big_clause evidence)")"
mk_turn "$r" "$r/.zen/contract.md" Edit
out="$(run_hook "$r" "$r/t.jsonl" false)"
[ -z "$out" ] && ok gate_altitude_ok_with_evidence || bad gate_altitude_ok_with_evidence
rm -rf "$r"

# CASE: gate_and_context_share_altitude_threshold — both hooks read ALTITUDE_LINES from the same
# shared module (A5, hooks/zen-shared.js), so one oversized clause (no Evidence link) is flagged by
# BOTH the gate and the SessionStart index. If the threshold ever drifted between them, one would miss.
r="$(new_repo "$(big_clause)")"
mk_turn "$r" "$r/.zen/contract.md" Edit
gate_out="$(run_hook "$r" "$r/t.jsonl" false)"
ctx_out="$(printf '{"cwd":"%s"}' "$r" | "$NODE" "$CTX")"
echo "$gate_out" | grep -qi 'altitude' && echo "$gate_out" | grep -q 'C-002' &&
	echo "$ctx_out" | grep -qi 'altitude' && echo "$ctx_out" | grep -q 'C-002' &&
	ok gate_and_context_share_altitude_threshold || bad gate_and_context_share_altitude_threshold
rm -rf "$r"

# CASE: gate_governed_from_subdir — editing code in a SUBDIRECTORY of a governed project still arms
# the gate; governance is found by walking up to the nearest .zen/contract.md (C-021), not only at
# the exact cwd. Without walk-up the gate was silently passive in every subfolder.
r="$(new_repo)"
commit "$r"
mkdir -p "$r/Sources/deep"
mk_turn "$r" "$r/Sources/deep/Foo.swift" Edit
out="$(run_hook "$r/Sources/deep")"
echo "$out" | grep -q '"decision":"block"' && ok gate_governed_from_subdir || bad gate_governed_from_subdir
rm -rf "$r"

# CASE: gate_sees_subagent_code_edit — edits are read from the git working tree, so a code change
# counts no matter WHO made it (main agent, a subagent in its own context, or an external process).
# This subsumes the old transcript-folding of subagent edits for free (C-014 → C-036): git does not
# care about the author. A code change with the contract untouched still blocks.
r="$(new_repo)"
commit "$r"
mk_turn "$r" "$r/Sources/Foo.swift" Edit # as if written by a subagent / external tool — git sees it
out="$(run_hook "$r")"
echo "$out" | grep -q '"decision":"block"' && ok gate_sees_subagent_code_edit || bad gate_sees_subagent_code_edit
rm -rf "$r"

# CASE: gate_subagent_doc_edit_is_not_code — a doc-only change (whoever made it) is classified doc,
# not code, so it does NOT trip turn-drift. Git-based detection still respects the kind (C-036).
r="$(new_repo)"
commit "$r"
mk_turn "$r" "$r/.zen/evidence/C-001.md" Edit # a doc (evidence note), not code
out="$(run_hook "$r")"
[ -z "$out" ] && ok gate_subagent_doc_edit_is_not_code || bad gate_subagent_doc_edit_is_not_code
rm -rf "$r"

# CASE: gate_scopes_to_governed_subtree — when the governed root is a SUBDIR of a larger git repo, a
# code change to a SIBLING outside the governed subtree must NOT cause turn-drift. Proves the `-- .`
# pathspec (C-036): without it, `git status` reports the sibling and the gate would falsely block.
# Manual verification on the clause keeps the link check out of it, isolating the scoping behavior.
r="$(mktemp -d /tmp/zen-gate-test.XXXXXX)"
(cd "$r" && git init -q && git config user.email t@t && git config user.name t)
mkdir -p "$r/projA/.zen" "$r/projB/Sources"
printf '# Contract Items\n## C-001: real\n- **Verification:** manual: by hand\n' >"$r/projA/.zen/contract.md"
printf 'audit.jsonl\n' >"$r/projA/.zen/.gitignore"
(cd "$r" && git add -A >/dev/null 2>&1 && git commit -qm base >/dev/null 2>&1)
printf 'func code() {}\n' >"$r/projB/Sources/B.swift" # code change OUTSIDE the governed subtree (projA)
out="$(run_hook "$r/projA")"                          # governed root resolves to projA via walk-up
[ -z "$out" ] && ok gate_scopes_to_governed_subtree || bad gate_scopes_to_governed_subtree
rm -rf "$r"

# CASE: gate_skips_turndrift_when_non_git — a governed project that is NOT a git repo cannot compute
# changedPaths; turn-drift is SKIPPED (fail open), even with a code file present and the contract
# untouched. Proves the git-error branch (C-036): no block, and an `edit_detection_skipped` audit line.
r="$(mktemp -d /tmp/zen-gate-nongit.XXXXXX)" # deliberately NO git init
mkdir -p "$r/.zen" "$r/Sources"
printf '# Contract Items\n## C-001: real\n- **Verification:** manual: by hand\n' >"$r/.zen/contract.md"
printf 'audit.jsonl\n' >"$r/.zen/.gitignore"
printf 'func code() {}\n' >"$r/Sources/Foo.swift" # code present, contract untouched
out="$(run_hook "$r")"
[ -z "$out" ] && grep -q '"event":"edit_detection_skipped"' "$r/.zen/audit.jsonl" &&
	ok gate_skips_turndrift_when_non_git || bad gate_skips_turndrift_when_non_git
rm -rf "$r"

# CASE: changedpaths_parses_rename_and_quoted — changedPaths must unwrap a rename to its NEW path and
# strip git's quoting of a path with a space (git quotes such paths — confirmed by spike). classify()
# keys only on the extension, so a broken unwrap would leave `.swift"` and silently classify the change
# "other" (slip). Drive real git and assert the EXACT returned path forms — the tight check classify can't.
r="$(new_repo)"
commit "$r"
(cd "$r" && git mv Tests/main.swift Tests/renamed.swift) # tracked rename → "R  old -> new"
printf 'x\n' >"$r/Sources/Has Space.swift"               # untracked path with a space → git quotes it
got="$(node -e 'console.log(require(process.argv[2]).changedPaths(process.argv[1]).join("\n"))' "$r" "$SHARED")"
echo "$got" | grep -qx 'Tests/renamed.swift' &&
	echo "$got" | grep -qx 'Sources/Has Space.swift' &&
	! echo "$got" | grep -q ' -> ' &&
	! echo "$got" | grep -q '"' &&
	ok changedpaths_parses_rename_and_quoted || bad changedpaths_parses_rename_and_quoted
rm -rf "$r"

# --- zen-record-run.js + run-evidence gate check (C-024) ---
# A verified clause with a Status line, linking a real test, for recording runs against.
verified_clause() { printf '## C-002: covered\n- **Verification:** automated → testRealOne\n- **Status:** verified\n'; }

# CASE: evidence_recorder_writes_pass — the recorder runs a command and writes a PASS record naming
# the clause's test, with exit 0.
r="$(new_repo "$(verified_clause)")"
"$NODE" "$REC" --clause C-002 --root "$r" -- true >/dev/null 2>&1
ev="$r/.zen/evidence/runs/C-002.json"
[ -f "$ev" ] && grep -q '"exitCode": 0' "$ev" && grep -q 'testRealOne' "$ev" && ok evidence_recorder_writes_pass || bad evidence_recorder_writes_pass
rm -rf "$r"

# CASE: gate_silent_on_fresh_evidence — a verified clause with a fresh PASS record ⇒ no evidence drift.
r="$(new_repo "$(verified_clause)")"
"$NODE" "$REC" --clause C-002 --root "$r" -- true >/dev/null 2>&1
mk_turn "$r" "$r/.zen/contract.md" Edit # contract-only turn isolates from turn-drift
out="$(run_hook "$r" "$r/t.jsonl" false)"
! echo "$out" | grep -qi 'run-evidence' && ok gate_silent_on_fresh_evidence || bad gate_silent_on_fresh_evidence
rm -rf "$r"

# CASE: gate_flags_failed_evidence — a verified clause whose recorded run FAILED ⇒ drift.
r="$(new_repo "$(verified_clause)")"
"$NODE" "$REC" --clause C-002 --root "$r" -- false >/dev/null 2>&1
mk_turn "$r" "$r/.zen/contract.md" Edit
out="$(run_hook "$r" "$r/t.jsonl" false)"
echo "$out" | grep -qi 'run-evidence' && echo "$out" | grep -q 'C-002' && ok gate_flags_failed_evidence || bad gate_flags_failed_evidence
rm -rf "$r"

# CASE: gate_flags_stale_evidence — record a PASS, then CHANGE the test file ⇒ evidence stale ⇒ drift.
r="$(new_repo "$(verified_clause)")"
"$NODE" "$REC" --clause C-002 --root "$r" -- true >/dev/null 2>&1
printf 'func testRealOne() { changed() }\n' >"$r/Tests/main.swift" # test file changed since the run
mk_turn "$r" "$r/.zen/contract.md" Edit
out="$(run_hook "$r" "$r/t.jsonl" false)"
echo "$out" | grep -qi 'stale' && echo "$out" | grep -q 'C-002' && ok gate_flags_stale_evidence || bad gate_flags_stale_evidence
rm -rf "$r"

# CASE: gate_silent_without_evidence — a verified clause with NO recorded run is NOT flagged
# (adoption is gradual; the recorded run is opt-in, not retroactively demanded).
r="$(new_repo "$(verified_clause)")"
mk_turn "$r" "$r/.zen/contract.md" Edit
out="$(run_hook "$r" "$r/t.jsonl" false)"
! echo "$out" | grep -qi 'run-evidence' && ok gate_silent_without_evidence || bad gate_silent_without_evidence
rm -rf "$r"

# CASE: recorder_rerun_reuses_command — `--rerun` re-runs the command recorded last time (no need to
# retype it), so re-verification stays the cheap path (C-024).
r="$(new_repo "$(verified_clause)")"
"$NODE" "$REC" --clause C-002 --root "$r" -- true >/dev/null 2>&1
"$NODE" "$REC" --clause C-002 --root "$r" --rerun >/dev/null 2>&1
ev="$r/.zen/evidence/runs/C-002.json"
[ -f "$ev" ] && grep -q '"command": "true"' "$ev" && grep -q '"exitCode": 0' "$ev" && ok recorder_rerun_reuses_command || bad recorder_rerun_reuses_command
rm -rf "$r"

# CASE: recorder_records_output_tail — the record carries the tail of the real output as a readable
# receipt (C-024); the gate does NOT parse it for pass/fail (C-027), it's for humans.
r="$(new_repo "$(verified_clause)")"
"$NODE" "$REC" --clause C-002 --root "$r" -- echo zentail123 >/dev/null 2>&1
grep -q 'zentail123' "$r/.zen/evidence/runs/C-002.json" && ok recorder_records_output_tail || bad recorder_records_output_tail
rm -rf "$r"

# CASE: recorder_locates_untracked_test — the recorder finds a test file written this turn but not yet
# `git add`ed (uses `git grep --untracked`, matching the gate). Caught live by the P-002 pilot.
r="$(new_repo "$(printf '## C-002: u\n- **Verification:** automated → testUntrackedRec\n- **Status:** verified\n')")"
printf 'func testUntrackedRec() {}\n' >"$r/Tests/extra.swift" # untracked (written after new_repo's git add)
"$NODE" "$REC" --clause C-002 --root "$r" -- true >/dev/null 2>&1
grep -q '"file": "Tests/extra.swift"' "$r/.zen/evidence/runs/C-002.json" && ok recorder_locates_untracked_test || bad recorder_locates_untracked_test
rm -rf "$r"

# CASE: gate_link_resolves_by_filename — a link `automated → foo.test.js` resolves because a FILE named
# foo.test.js EXISTS, even though its name appears in no OTHER content (filename-existence, not only
# content-grep). The standalone-test-file case the E2E flagged: without this, a real test never resolves
# until its name is referenced elsewhere (e.g. a package.json script). resolveLinkFiles branch (a).
r="$(new_repo "$(printf '## C-002: fresh\n- **Verification:** automated → foo.test.js\n')")"
printf 'test("ok", () => {});\n' >"$r/foo.test.js" # a real test; its NAME appears in no file's content
mk_turn "$r" "$r/.zen/contract.md" Edit            # contract-only turn isolates the link-check
out="$(run_hook "$r" "$r/t.jsonl" false)"
[ -z "$out" ] && ! echo "$out" | grep -q 'foo.test.js' && ok gate_link_resolves_by_filename || bad gate_link_resolves_by_filename
rm -rf "$r"

# CASE: recorder_hashes_named_test_not_a_mentioner — when the link token is a FILENAME, the recorder
# hashes THAT file, not a different file (package.json) that merely mentions the name in its content.
# The package.json-first-match trap the E2E found: content-grep + split[0] grabbed package.json and the
# C-024 staleness guard then watched the wrong artifact. resolveLinkFiles prefers the filename match.
r="$(new_repo "$(printf '## C-002: u\n- **Verification:** automated → foo.test.js\n- **Status:** verified\n')")"
printf 'test("ok", () => {});\n' >"$r/foo.test.js"                           # the real test (no self-mention)
printf '{"scripts":{"test":"node --test foo.test.js"}}\n' >"$r/package.json" # mentions foo.test.js in CONTENT
"$NODE" "$REC" --clause C-002 --root "$r" -- true >/dev/null 2>&1
grep -q '"file": "foo.test.js"' "$r/.zen/evidence/runs/C-002.json" && ok recorder_hashes_named_test_not_a_mentioner || bad recorder_hashes_named_test_not_a_mentioner
rm -rf "$r"

# CASE: gate_flags_malformed_clause_heading — a heading `## C-002 — title` (em-dash, NO colon) does not
# parse into a clause, yet the contract file was touched. Without this guard turn-drift passes and the
# clause is INVISIBLE (parseContract sees nothing → zero coverage while the gate stays green). The gate
# must flag the malformed id by name. The E2E soundness gap (zen-shared.malformedClauseHeadings, C-039).
r="$(new_repo)"
printf '\n## C-002 — invisible clause\n- **Verification:** automated → whatever\n' >>"$r/.zen/contract.md"
mk_turn "$r" "$r/.zen/contract.md" Edit # contract touched, so turn-drift would otherwise pass it green
out="$(run_hook "$r" "$r/t.jsonl" false)"
echo "$out" | grep -q 'Malformed clause heading' && echo "$out" | grep -q 'C-002' &&
	ok gate_flags_malformed_clause_heading || bad gate_flags_malformed_clause_heading
rm -rf "$r"

# CASE: gate_blocks_newly_verified_without_evidence — a clause flipped to `verified` (automated) SINCE
# the last commit, with no fresh run recorded, blocks (C-026). Make the lie cost a block.
r="$(new_repo)"
(cd "$r" && git -c user.email=t@t -c user.name=t commit -qm base) >/dev/null 2>&1 # HEAD baseline: C-001 (no status)
printf '## C-002: fresh claim\n- **Verification:** automated → testRealOne\n- **Status:** verified\n' >>"$r/.zen/contract.md"
mk_turn "$r" "$r/.zen/contract.md" Edit
out="$(run_hook "$r" "$r/t.jsonl" false)"
echo "$out" | grep -qi 'newly verified' && echo "$out" | grep -q 'C-002' && ok gate_blocks_newly_verified_without_evidence || bad gate_blocks_newly_verified_without_evidence
rm -rf "$r"

# CASE: gate_silent_newly_verified_with_evidence — the same fresh claim, but WITH a recorded pass AND a
# recorded refute pass ⇒ no block. The way through is now two cheap records (run + refuter verdict).
r="$(new_repo)"
(cd "$r" && git -c user.email=t@t -c user.name=t commit -qm base) >/dev/null 2>&1
printf '## C-002: fresh claim\n- **Verification:** automated → testRealOne\n- **Status:** verified\n' >>"$r/.zen/contract.md"
"$NODE" "$REC" --clause C-002 --root "$r" -- true >/dev/null 2>&1
"$NODE" "$REFUTE" --clause C-002 --root "$r" --verdict holds >/dev/null 2>&1
mk_turn "$r" "$r/.zen/contract.md" Edit
out="$(run_hook "$r" "$r/t.jsonl" false)"
! echo "$out" | grep -qi 'newly verified' && ! echo "$out" | grep -qi 'unrefuted' &&
	ok gate_silent_newly_verified_with_evidence || bad gate_silent_newly_verified_with_evidence
rm -rf "$r"

# --- Refute-evidence: the disinterested-critic half of "verified" (C-041) ---

# CASE: refute_recorder_writes_and_clears — the recorder writes a refute record naming the clause's test
# and exits 0 on `holds` (cleared); exit 1 on `refuted` (NOT cleared). The honest path is one command.
r="$(new_repo "$(verified_clause)")"
"$NODE" "$REFUTE" --clause C-002 --root "$r" --verdict holds >/dev/null 2>&1
h=$?
ev="$r/.zen/evidence/refutes/C-002.json"
"$NODE" "$REFUTE" --clause C-002 --root "$r" --verdict refuted >/dev/null 2>&1
rf=$?
[ -f "$ev" ] && grep -q '"verdict": "refuted"' "$ev" && grep -q 'testRealOne' "$ev" && [ "$h" -eq 0 ] && [ "$rf" -eq 1 ] &&
	ok refute_recorder_writes_and_clears || bad refute_recorder_writes_and_clears
rm -rf "$r"

# CASE: gate_blocks_newly_verified_without_refute — a clause flipped to `verified` since HEAD, WITH a
# fresh run recorded but NO refuter pass, still blocks (C-041). A green test is not proof on its own.
r="$(new_repo)"
(cd "$r" && git -c user.email=t@t -c user.name=t commit -qm base) >/dev/null 2>&1
printf '## C-002: fresh claim\n- **Verification:** automated → testRealOne\n- **Status:** verified\n' >>"$r/.zen/contract.md"
"$NODE" "$REC" --clause C-002 --root "$r" -- true >/dev/null 2>&1 # run-evidence satisfied, refute is NOT
mk_turn "$r" "$r/.zen/contract.md" Edit
out="$(run_hook "$r" "$r/t.jsonl" false)"
echo "$out" | grep -q '"decision":"block"' && echo "$out" | grep -qi 'unrefuted' && echo "$out" | grep -q 'C-002' &&
	ok gate_blocks_newly_verified_without_refute || bad gate_blocks_newly_verified_without_refute
rm -rf "$r"

# CASE: gate_silent_newly_verified_with_refute — same fresh claim, run + refute(holds) recorded ⇒ no
# refute drift. The recorded critic verdict is the way through.
r="$(new_repo)"
(cd "$r" && git -c user.email=t@t -c user.name=t commit -qm base) >/dev/null 2>&1
printf '## C-002: fresh claim\n- **Verification:** automated → testRealOne\n- **Status:** verified\n' >>"$r/.zen/contract.md"
"$NODE" "$REC" --clause C-002 --root "$r" -- true >/dev/null 2>&1
"$NODE" "$REFUTE" --clause C-002 --root "$r" --verdict holds >/dev/null 2>&1
mk_turn "$r" "$r/.zen/contract.md" Edit
out="$(run_hook "$r" "$r/t.jsonl" false)"
! echo "$out" | grep -qi 'unrefuted' && ok gate_silent_newly_verified_with_refute || bad gate_silent_newly_verified_with_refute
rm -rf "$r"

# CASE: gate_trivial_verdict_clears — `trivial` (no behavioral surface) is a valid pass, same as holds.
r="$(new_repo)"
(cd "$r" && git -c user.email=t@t -c user.name=t commit -qm base) >/dev/null 2>&1
printf '## C-002: fresh claim\n- **Verification:** automated → testRealOne\n- **Status:** verified\n' >>"$r/.zen/contract.md"
"$NODE" "$REC" --clause C-002 --root "$r" -- true >/dev/null 2>&1
"$NODE" "$REFUTE" --clause C-002 --root "$r" --verdict trivial >/dev/null 2>&1
mk_turn "$r" "$r/.zen/contract.md" Edit
out="$(run_hook "$r" "$r/t.jsonl" false)"
! echo "$out" | grep -qi 'unrefuted' && ok gate_trivial_verdict_clears || bad gate_trivial_verdict_clears
rm -rf "$r"

# CASE: gate_blocks_on_refuted_verdict — the critic found a real gap (`refuted`): the clause does NOT
# stand `verified`, the gate blocks until the test is strengthened and re-refuted.
r="$(new_repo)"
(cd "$r" && git -c user.email=t@t -c user.name=t commit -qm base) >/dev/null 2>&1
printf '## C-002: fresh claim\n- **Verification:** automated → testRealOne\n- **Status:** verified\n' >>"$r/.zen/contract.md"
"$NODE" "$REC" --clause C-002 --root "$r" -- true >/dev/null 2>&1
"$NODE" "$REFUTE" --clause C-002 --root "$r" --verdict refuted >/dev/null 2>&1
mk_turn "$r" "$r/.zen/contract.md" Edit
out="$(run_hook "$r" "$r/t.jsonl" false)"
# assert the BLOCK and the DISTINCT reason — `refuted` (the critic found a gap), not merely "missing":
# nothing else in this case is unrefuted, so "found a gap" proves the verdict value drove the block.
echo "$out" | grep -q '"decision":"block"' && echo "$out" | grep -q 'C-002' && echo "$out" | grep -q 'found a gap' &&
	ok gate_blocks_on_refuted_verdict || bad gate_blocks_on_refuted_verdict
rm -rf "$r"

# CASE: gate_refute_goes_stale_on_test_edit — record refute(holds), then CHANGE the test file ⇒ the
# refute is pinned to the old test hash ⇒ stale ⇒ block. Editing a test re-stales the refute (re-refute).
r="$(new_repo)"
(cd "$r" && git -c user.email=t@t -c user.name=t commit -qm base) >/dev/null 2>&1
printf '## C-002: fresh claim\n- **Verification:** automated → testRealOne\n- **Status:** verified\n' >>"$r/.zen/contract.md"
"$NODE" "$REC" --clause C-002 --root "$r" -- true >/dev/null 2>&1
"$NODE" "$REFUTE" --clause C-002 --root "$r" --verdict holds >/dev/null 2>&1
printf 'func testRealOne() { changed() }\n' >"$r/Tests/main.swift" # test changed since the refute
mk_turn "$r" "$r/.zen/contract.md" Edit
out="$(run_hook "$r" "$r/t.jsonl" false)"
# assert the REFUTE-specific stale message, not a bare 'stale' — editing the test also stales the C-024
# run-evidence ('run-evidence stale — …'), so a bare grep would pass via that path even if refute hash-
# pinning broke. `refute stale` is emitted only by the C-041 path → isolates the property under test.
echo "$out" | grep -q '"decision":"block"' && echo "$out" | grep -q 'C-002' && echo "$out" | grep -q 'refute stale' &&
	ok gate_refute_goes_stale_on_test_edit || bad gate_refute_goes_stale_on_test_edit
rm -rf "$r"

# CASE: gate_blocks_unknown_verdict_record — the gate reads the record file, not the recorder, so the
# verdict must be a CONSTRAINED judgment, not any free-text token that clears (C-041: "not a free-text
# waive"). Forge a refute record (bypassing zen-record-refute.js) with an out-of-set verdict on a newly-
# verified clause; the gate must still block, naming the unknown verdict. tests:[] isolates this from
# staleness (the verdict check precedes the hash loop).
r="$(new_repo)"
(cd "$r" && git -c user.email=t@t -c user.name=t commit -qm base) >/dev/null 2>&1
printf '## C-002: fresh claim\n- **Verification:** automated → testRealOne\n- **Status:** verified\n' >>"$r/.zen/contract.md"
"$NODE" "$REC" --clause C-002 --root "$r" -- true >/dev/null 2>&1 # run-evidence satisfied → isolates the refute path
mkdir -p "$r/.zen/evidence/refutes"
printf '{"clause":"C-002","verdict":"lgtm","tests":[]}\n' >"$r/.zen/evidence/refutes/C-002.json"
mk_turn "$r" "$r/.zen/contract.md" Edit
out="$(run_hook "$r" "$r/t.jsonl" false)"
echo "$out" | grep -q '"decision":"block"' && echo "$out" | grep -q 'unknown verdict' && echo "$out" | grep -q 'C-002' &&
	ok gate_blocks_unknown_verdict_record || bad gate_blocks_unknown_verdict_record
rm -rf "$r"

# CASE: gate_grandfathers_preexisting_unrefuted — a clause already `verified` at HEAD with no refute is
# NOT pressured (gradual adoption, no wall on the backlog); only NEW verified claims need a refuter pass.
r="$(new_repo "$(verified_clause)")"
(cd "$r" && git -c user.email=t@t -c user.name=t commit -qm base) >/dev/null 2>&1 # C-002 verified AT HEAD, no refute
printf '\n<!-- a later, unrelated contract edit -->\n' >>"$r/.zen/contract.md"
mk_turn "$r" "$r/.zen/contract.md" Edit
out="$(run_hook "$r" "$r/t.jsonl" false)"
! echo "$out" | grep -qi 'unrefuted' && ok gate_grandfathers_preexisting_unrefuted || bad gate_grandfathers_preexisting_unrefuted
rm -rf "$r"

# --- Grandfather baseline = the last gate-blessed commit (audit-stamped headCommit SHA), not live HEAD (C-042) ---

# CASE: gate_grandfather_baseline_is_last_blessed_not_head — a clause verified AND COMMITTED within a turn
# must NOT grandfather itself. The baseline is the headCommit the gate stamped at its LAST fire (read from
# .zen/audit.jsonl), not live HEAD — else commit-as-you-go silently exempts a new clause (run-4 #1).
r="$(new_repo)"
(cd "$r" && git commit -qm base) >/dev/null 2>&1
BASE=$(cd "$r" && git rev-parse HEAD) # the blessed commit (no C-002)
printf '{"headCommit":"%s","event":"stop_gate","decision":"pass"}\n' "$BASE" >"$r/.zen/audit.jsonl"
printf '## C-002: committed claim\n- **Verification:** automated → testRealOne\n- **Status:** verified\n' >>"$r/.zen/contract.md"
(cd "$r" && git commit -qam c2) >/dev/null 2>&1 # C-002 verified+committed AFTER the blessing ⇒ HEAD now past BASE
out="$(run_hook "$r" "$r/t.jsonl" false)"
echo "$out" | grep -q '"decision":"block"' && echo "$out" | grep -qi 'newly verified' && echo "$out" | grep -q 'C-002' &&
	ok gate_grandfather_baseline_is_last_blessed_not_head || bad gate_grandfather_baseline_is_last_blessed_not_head
rm -rf "$r"

# CASE: gate_grandfathers_clause_committed_before_blessing — the flip side: a verified-no-evidence clause
# committed BEFORE the last blessing stays grandfathered (the real backlog is not walled). HEAD is moved
# PAST the blessing too, so this proves grandfathering via the recorded baseline, not "baseline==HEAD".
r="$(new_repo)"
printf '## C-002: old claim\n- **Verification:** automated → testRealOne\n- **Status:** verified\n' >>"$r/.zen/contract.md"
(cd "$r" && git commit -qam base) >/dev/null 2>&1
BLESS=$(cd "$r" && git rev-parse HEAD) # blessing sha already has C-002 verified
printf '{"headCommit":"%s","event":"stop_gate","decision":"pass"}\n' "$BLESS" >"$r/.zen/audit.jsonl"
printf '\n<!-- later unrelated edit -->\n' >>"$r/.zen/contract.md"
(cd "$r" && git commit -qam later) >/dev/null 2>&1 # HEAD now PAST the blessing (baseline != HEAD)
out="$(run_hook "$r" "$r/t.jsonl" false)"
! echo "$out" | grep -qi 'newly verified' && ! echo "$out" | grep -qi 'unrefuted' &&
	ok gate_grandfathers_clause_committed_before_blessing || bad gate_grandfathers_clause_committed_before_blessing
rm -rf "$r"

# CASE: gate_baseline_falls_back_to_head_without_audit — with NO heartbeat yet (first-ever fire / fresh
# clone — audit.jsonl is gitignored), the baseline falls back to live HEAD: a verified clause already in
# HEAD is grandfathered (the documented one-fire HONEST LIMIT, C-042/C-024 class). Pins the fallback so it
# cannot silently regress into either walling-everything or a permanent hole.
r="$(new_repo)"
printf '## C-002: committed\n- **Verification:** automated → testRealOne\n- **Status:** verified\n' >>"$r/.zen/contract.md"
(cd "$r" && git commit -qam base) >/dev/null 2>&1
rm -f "$r/.zen/audit.jsonl" # no heartbeat ⇒ first-fire fallback
mk_turn "$r" "$r/.zen/contract.md" Edit
out="$(run_hook "$r" "$r/t.jsonl" false)"
! echo "$out" | grep -qi 'newly verified' && ok gate_baseline_falls_back_to_head_without_audit || bad gate_baseline_falls_back_to_head_without_audit
rm -rf "$r"

# --- Refute freshness pins the test SYMBOL, not the whole file — no cascade (C-043) ---

# CASE: refute_recorder_pins_symbol_not_file — the refute record stores the SYMBOL region's hash
# (symbolSha), not a whole-file hash (fileSha), so a sibling edit cannot stale it.
r="$(new_repo "$(printf '## C-002: claim\n- **Verification:** automated → caseAlpha\n- **Status:** verified\n')")"
printf '# CASE: caseAlpha\nassert_alpha\n\n# CASE: caseBeta\nassert_beta\n' >"$r/Tests/cases.sh"
(cd "$r" && git add -A && git commit -qm base) >/dev/null 2>&1
"$NODE" "$REFUTE" --clause C-002 --root "$r" --verdict holds >/dev/null 2>&1
ev="$r/.zen/evidence/refutes/C-002.json"
[ -f "$ev" ] && grep -q 'symbolSha' "$ev" && ! grep -q 'fileSha' "$ev" &&
	ok refute_recorder_pins_symbol_not_file || bad refute_recorder_pins_symbol_not_file
rm -rf "$r"

# CASE: refute_fresh_when_sibling_symbol_changes — C-002 links caseAlpha; record a holds refute, then edit
# the SIBLING caseBeta in the same file. C-002's refute must stay FRESH (symbol-scoped) — the cascade-killer.
# Under whole-file hashing this would go stale and force a wasted re-refute.
r="$(new_repo "$(printf '## C-002: claim\n- **Verification:** automated → caseAlpha\n- **Status:** verified\n')")"
printf '# CASE: caseAlpha\nassert_alpha\n\n# CASE: caseBeta\nassert_beta\n' >"$r/Tests/cases.sh"
(cd "$r" && git add -A && git commit -qm base) >/dev/null 2>&1
"$NODE" "$REFUTE" --clause C-002 --root "$r" --verdict holds >/dev/null 2>&1
printf '# CASE: caseAlpha\nassert_alpha\n\n# CASE: caseBeta\nassert_beta_CHANGED\n' >"$r/Tests/cases.sh" # sibling edited
st=$("$NODE" -e 'const s=require(process.argv[2]);console.log(s.refuteStatus(process.argv[1],"C-002").state)' "$r" "$SHARED")
[ "$st" = "fresh" ] && ok refute_fresh_when_sibling_symbol_changes || {
	echo "  state=$st"
	bad refute_fresh_when_sibling_symbol_changes
}
rm -rf "$r"

# CASE: refute_stale_when_own_symbol_changes — editing the clause's OWN linked symbol DOES stale its refute
# (the correctness side of C-043: a real change to what proves the clause must re-trigger the critic).
r="$(new_repo "$(printf '## C-002: claim\n- **Verification:** automated → caseAlpha\n- **Status:** verified\n')")"
printf '# CASE: caseAlpha\nassert_alpha\n\n# CASE: caseBeta\nassert_beta\n' >"$r/Tests/cases.sh"
(cd "$r" && git add -A && git commit -qm base) >/dev/null 2>&1
"$NODE" "$REFUTE" --clause C-002 --root "$r" --verdict holds >/dev/null 2>&1
printf '# CASE: caseAlpha\nassert_alpha_CHANGED\n\n# CASE: caseBeta\nassert_beta\n' >"$r/Tests/cases.sh" # OWN symbol edited
st=$("$NODE" -e 'const s=require(process.argv[2]);console.log(s.refuteStatus(process.argv[1],"C-002").state)' "$r" "$SHARED")
[ "$st" = "stale" ] && ok refute_stale_when_own_symbol_changes || {
	echo "  state=$st"
	bad refute_stale_when_own_symbol_changes
}
rm -rf "$r"

# CASE: refute_stale_when_call_precedes_def — extractSymbol must anchor on the DEFINITION, not the first
# mention: a call (`invoke caseAlpha`) before the `# CASE: caseAlpha` def. An adversarial refute found the
# naive anchor truncated the real body (false-fresh, C-043). Weakening the def body must stale the refute.
r="$(new_repo "$(printf '## C-002: claim\n- **Verification:** automated → caseAlpha\n- **Status:** verified\n')")"
printf 'invoke caseAlpha   # a call BEFORE the def\n\n# CASE: caseAlpha\nassert_real_thing\n\n# CASE: caseBeta\nassert_beta\n' >"$r/Tests/cases.sh"
(cd "$r" && git add -A && git commit -qm base) >/dev/null 2>&1
"$NODE" "$REFUTE" --clause C-002 --root "$r" --verdict holds >/dev/null 2>&1
printf 'invoke caseAlpha   # a call BEFORE the def\n\n# CASE: caseAlpha\nassert_WEAKENED\n\n# CASE: caseBeta\nassert_beta\n' >"$r/Tests/cases.sh"
st=$("$NODE" -e 'const s=require(process.argv[2]);console.log(s.refuteStatus(process.argv[1],"C-002").state)' "$r" "$SHARED")
[ "$st" = "stale" ] && ok refute_stale_when_call_precedes_def || {
	echo "  state=$st"
	bad refute_stale_when_call_precedes_def
}
rm -rf "$r"

# CASE: refute_stale_when_nested_symbol_edited — a nested opener inside the body must NOT truncate the region
# (the indentation-aware end, C-043). A nested `def helper` inside `def caseAlpha`: weakening an assertion
# AFTER the nested block must still stale the refute (else false-fresh, the second hole the refuter found).
r="$(new_repo "$(printf '## C-002: claim\n- **Verification:** automated → caseAlpha\n- **Status:** verified\n')")"
printf 'def caseAlpha():\n    def helper():\n        pass\n    assert_real_thing\n\ndef caseBeta():\n    pass\n' >"$r/Tests/cases.py"
(cd "$r" && git add -A && git commit -qm base) >/dev/null 2>&1
"$NODE" "$REFUTE" --clause C-002 --root "$r" --verdict holds >/dev/null 2>&1
printf 'def caseAlpha():\n    def helper():\n        pass\n    assert_WEAKENED\n\ndef caseBeta():\n    pass\n' >"$r/Tests/cases.py"
st=$("$NODE" -e 'const s=require(process.argv[2]);console.log(s.refuteStatus(process.argv[1],"C-002").state)' "$r" "$SHARED")
[ "$st" = "stale" ] && ok refute_stale_when_nested_symbol_edited || {
	echo "  state=$st"
	bad refute_stale_when_nested_symbol_edited
}
rm -rf "$r"

# CASE: refute_stale_when_inbody_helper_at_case_indent — a no-arg helper `setup() {` at the CASE header's
# own indent (col 0) inside a `# CASE:` body must NOT truncate the region (the 4th false-fresh hole — flat
# shell cases are delimited only by the next `# CASE:`, not by in-body function defs). Weakening the
# assertion AFTER the helper must stale the refute.
r="$(new_repo "$(printf '## C-002: claim\n- **Verification:** automated → caseAlpha\n- **Status:** verified\n')")"
printf '# CASE: caseAlpha\nsetup() {\n  echo hi\n}\nassert_real_thing\n\n# CASE: caseBeta\nassert_beta\n' >"$r/Tests/cases.sh"
(cd "$r" && git add -A && git commit -qm base) >/dev/null 2>&1
"$NODE" "$REFUTE" --clause C-002 --root "$r" --verdict holds >/dev/null 2>&1
printf '# CASE: caseAlpha\nsetup() {\n  echo hi\n}\nassert_WEAKENED\n\n# CASE: caseBeta\nassert_beta\n' >"$r/Tests/cases.sh"
st=$("$NODE" -e 'const s=require(process.argv[2]);console.log(s.refuteStatus(process.argv[1],"C-002").state)' "$r" "$SHARED")
[ "$st" = "stale" ] && ok refute_stale_when_inbody_helper_at_case_indent || {
	echo "  state=$st"
	bad refute_stale_when_inbody_helper_at_case_indent
}
rm -rf "$r"

# CASE: gate_grandfathers_preexisting_verified — a clause already `verified` at HEAD (no evidence) is
# NOT pressured (no wall on the backlog); only NEW claims are (C-026).
r="$(new_repo "$(verified_clause)")"
(cd "$r" && git -c user.email=t@t -c user.name=t commit -qm base) >/dev/null 2>&1 # C-002 verified AT HEAD
printf '\n<!-- a later, unrelated contract edit -->\n' >>"$r/.zen/contract.md"
mk_turn "$r" "$r/.zen/contract.md" Edit
out="$(run_hook "$r" "$r/t.jsonl" false)"
! echo "$out" | grep -qi 'newly verified' && ok gate_grandfathers_preexisting_verified || bad gate_grandfathers_preexisting_verified
rm -rf "$r"

# --- zen-context.js (SessionStart contract-awareness hook) ---

# CASE: context_reports_status — governed project ⇒ injects a contract-state index via additionalContext
r="$(new_repo)"
out="$(printf '{"cwd":"%s"}' "$r" | "$NODE" "$CTX")"
echo "$out" | grep -q 'additionalContext' && echo "$out" | grep -q 'contract state' && ok context_reports_status || bad context_reports_status
rm -rf "$r"

# CASE: context_awaiting_shows_clause_title — the awareness index names an AWAITING clause by its TITLE,
# not just its id, so after /clear the operator knows WHAT a pending clause covers even if it never had a
# dedicated commit (the run-2 continuity name-gap: C-002 titleCase "rode along" in other commits, so its
# name didn't survive). C-015 index now maps unverifiedIds → "C-xxx (title)".
r="$(new_repo "$(printf '## C-002: titleCase capitalization\n- **Verification:** automated → titlecase.test.js\n- **Status:** pending\n')")"
out="$(printf '{"cwd":"%s"}' "$r" | NO_COLOR=1 "$NODE" "$CTX")"
echo "$out" | grep -q 'awaiting verification' && echo "$out" | grep -q 'C-002 (titleCase' &&
	ok context_awaiting_shows_clause_title || bad context_awaiting_shows_clause_title
rm -rf "$r"

# CASE: context_manual_only_ignores_prose — the SessionStart index counts a clause as "manual-only"
# from its **Verification** FIELD, not prose. A manual clause whose DESCRIPTION mentions "automated →"
# must still be counted (here: exactly 1 manual-only), proving the count isn't fooled by description text.
r="$(new_repo "$(printf '## C-002: m\n- **Description:** the clause mentions automated → fooBar in prose\n- **Verification:** manual: checked by hand\n')")"
out="$(printf '{"cwd":"%s"}' "$r" | "$NODE" "$CTX")"
echo "$out" | grep -q '1 manual-only' && ok context_manual_only_ignores_prose || bad context_manual_only_ignores_prose
rm -rf "$r"

# CASE: context_nudges_when_non_git — a governed project that is NOT a git repo gets an onboarding
# nudge to run `git init` (the gate is essentially off without git — C-036 made turn-drift git-based
# too), the "links resolve" all-clear is suppressed, and the nudge must NOT falsely claim turn-drift is
# still active (the honest degraded-mode message: only the altitude check runs without git).
r="$(mktemp -d /tmp/zen-ctx-nongit.XXXXXX)" # deliberately NO git init
mkdir -p "$r/.zen" "$r/Tests"
printf 'func testRealOne() {}\n' >"$r/Tests/main.swift"
printf '# Contract Items\n## C-001: real\n- **Verification:** automated → testRealOne\n' >"$r/.zen/contract.md"
out="$(printf '{"cwd":"%s"}' "$r" | "$NODE" "$CTX")"
echo "$out" | grep -q 'git init' && ! echo "$out" | grep -q 'links resolve' &&
	! echo "$out" | grep -qiE 'turn-drift \+ altitude|turn-drift.{0,20}active' &&
	ok context_nudges_when_non_git || bad context_nudges_when_non_git
rm -rf "$r"

# CASE: context_no_git_nudge_in_repo — a governed GIT project gets NO git nudge (no false alarm).
r="$(new_repo)"
out="$(printf '{"cwd":"%s"}' "$r" | "$NODE" "$CTX")"
echo "$out" | grep -q 'additionalContext' && ! echo "$out" | grep -q 'git init' &&
	ok context_no_git_nudge_in_repo || bad context_no_git_nudge_in_repo
rm -rf "$r"

# CASE: context_surfaces_oldest_deltas — the index names the 3 OLDEST pending deltas BY DATE (not
# file order) plus a /zen-check pointer. Deltas are listed out of date-order on purpose: P-013 is
# newest but appears among them; the 3 oldest (P-011, P-012, P-010) must be named, P-013 must not.
block="$(printf '## Pending Contract Deltas\n### P-010: a\n- **Date:** 2026-01-03\n### P-011: b\n- **Date:** 2026-01-01\n### P-012: c\n- **Date:** 2026-01-02\n### P-013: d\n- **Date:** 2026-06-15\n')"
r="$(new_repo "$block")"
out="$(printf '{"cwd":"%s"}' "$r" | "$NODE" "$CTX")"
echo "$out" | grep -q 'P-011' && echo "$out" | grep -q 'P-012' && echo "$out" | grep -q 'P-010' &&
	! echo "$out" | grep -q 'oldest:.*P-013\|P-013 (' &&
	echo "$out" | grep -q '/zen-check' &&
	ok context_surfaces_oldest_deltas || bad context_surfaces_oldest_deltas
rm -rf "$r"

# CASE: context_mini_nudge_ungoverned_git — an ungoverned dir that IS a git repo gets a one-line
# /zen-init nudge (a real project where Zen would help), not silence.
r="$(mktemp -d /tmp/zen-ungov-git.XXXXXX)"
(cd "$r" && git init -q)
out="$(printf '{"cwd":"%s"}' "$r" | "$NODE" "$CTX")"
echo "$out" | grep -q '/zen-init' && echo "$out" | grep -qi 'not governed' &&
	ok context_mini_nudge_ungoverned_git || bad context_mini_nudge_ungoverned_git
rm -rf "$r"

# CASE: context_governed_from_subdir — the awareness index works from a SUBDIRECTORY too (C-021):
# walk up to the governed root, report contract state, not the "not governed" nudge.
r="$(new_repo)"
mkdir -p "$r/sub/deeper"
out="$(printf '{"cwd":"%s"}' "$r/sub/deeper" | "$NODE" "$CTX")"
echo "$out" | grep -q 'contract state' && ! echo "$out" | grep -q 'not governed' &&
	ok context_governed_from_subdir || bad context_governed_from_subdir
rm -rf "$r"

# CASE: context_emits_visible_onboarding — a governed project emits a top-level `systemMessage`
# (the channel Claude Code surfaces to the human, C-022) carrying the IMPLICATION→MACHINE wordmark banner. The model
# index (additionalContext) is still present too.
r="$(new_repo)"
out="$(printf '{"cwd":"%s"}' "$r" | "$NODE" "$CTX")"
echo "$out" | grep -q '"systemMessage"' && echo "$out" | grep -q '█████' &&
	echo "$out" | grep -q 'additionalContext' &&
	ok context_emits_visible_onboarding || bad context_emits_visible_onboarding
rm -rf "$r"

# CASE: context_banner_shows_continuity — after /clear the banner restores "where we left off" from
# git (C-023): the last commit subject + an uncommitted-file count, in both channels.
r="$(new_repo)"
(cd "$r" && git -c user.email=t@t -c user.name=t commit -qm "wire up the thing")
printf 'code\n' >"$r/Sources/New.swift" # an uncommitted change
out="$(printf '{"cwd":"%s"}' "$r" | "$NODE" "$CTX")"
echo "$out" | grep -q 'wire up the thing' && echo "$out" | grep -q 'uncommitted' &&
	ok context_banner_shows_continuity || bad context_banner_shows_continuity
rm -rf "$r"

# CASE: context_banner_has_legend — the visible panel carries a newcomer's legend section (C-022),
# teaching what the vocabulary means. NO_COLOR keeps the assertion free of ANSI escapes.
r="$(new_repo)"
out="$(printf '{"cwd":"%s"}' "$r" | NO_COLOR=1 "$NODE" "$CTX")"
echo "$out" | grep -q 'how to read this' && echo "$out" | grep -q 'capability' &&
	ok context_banner_has_legend || bad context_banner_has_legend
rm -rf "$r"

# CASE: context_quiet_silences_banner — ZEN_QUIET=1 drops the visible systemMessage banner but KEEPS
# the model-facing additionalContext index (C-022 toggle).
r="$(new_repo)"
out="$(printf '{"cwd":"%s"}' "$r" | ZEN_QUIET=1 "$NODE" "$CTX")"
echo "$out" | grep -q 'additionalContext' && ! echo "$out" | grep -q '"systemMessage"' &&
	! echo "$out" | grep -q '█████' &&
	ok context_quiet_silences_banner || bad context_quiet_silences_banner
rm -rf "$r"

# CASE: context_silent_ungoverned — ungoverned AND non-git (scratch/home) ⇒ no output (no spam)
p="$(mktemp -d)"
out="$(printf '{"cwd":"%s"}' "$p" | "$NODE" "$CTX")"
[ -z "$out" ] && ok context_silent_ungoverned || bad context_silent_ungoverned
rm -rf "$p"

# CASE: gate_no_stderr_leak_no_baseline — the Stop-gate runs clean: its C-026 baseline read
# (`git show HEAD:` in newlyVerifiedWithoutEvidence) must not leak git's diagnostics to stderr.
# new_repo stages files but does NOT commit, so there is no HEAD ⇒ `git show HEAD:` fails; the check
# fails open (returns []), but its stderr must stay silent (C-028). Capture stderr only (1>/dev/null).
r="$(new_repo)"
mk_turn "$r" "$r/Sources/Foo.swift" Edit
err="$(run_hook "$r" "$r/t.jsonl" false 2>&1 1>/dev/null)"
! echo "$err" | grep -qi 'fatal' && ok gate_no_stderr_leak_no_baseline || bad gate_no_stderr_leak_no_baseline
rm -rf "$r"

# CASE: recorder_no_stderr_leak_no_baseline — the recorder's git calls (`git grep --untracked` to
# locate the test, `git rev-parse HEAD` for the baseline) must also suppress git's stderr (C-028).
# In new_repo (no commits) `git rev-parse HEAD` fails; the recorder still writes a record, silently.
r="$(new_repo "$(verified_clause)")"
err="$("$NODE" "$REC" --clause C-002 --root "$r" -- true 2>&1 1>/dev/null)"
! echo "$err" | grep -qi 'fatal' && ok recorder_no_stderr_leak_no_baseline || bad recorder_no_stderr_leak_no_baseline
rm -rf "$r"

# CASE: context_emits_protocol_in_plugin_mode — with --emit-protocol (the plugin's hooks.json form),
# the SessionStart hook prepends the zen.md protocol core to additionalContext, replacing @zen.md
# (C-030). The contract-state index still rides along beneath it.
r="$(new_repo)"
out="$(printf '{"cwd":"%s"}' "$r" | "$NODE" "$CTX" --emit-protocol)"
echo "$out" | grep -q 'living-contract working protocol' && echo "$out" | grep -q 'contract state' &&
	ok context_emits_protocol_in_plugin_mode || bad context_emits_protocol_in_plugin_mode
rm -rf "$r"

# CASE: context_no_protocol_without_flag — by default (dogfood: @zen.md already loads the protocol) the
# hook does NOT inject zen.md, so it is not double-loaded.
r="$(new_repo)"
out="$(printf '{"cwd":"%s"}' "$r" | "$NODE" "$CTX")"
! echo "$out" | grep -q 'living-contract working protocol' && echo "$out" | grep -q 'contract state' &&
	ok context_no_protocol_without_flag || bad context_no_protocol_without_flag
rm -rf "$r"

# CASE: context_protocol_in_ungoverned_plugin_mode — the protocol is global guidance, so in plugin mode
# it is emitted EVERYWHERE, including an ungoverned non-git scratch dir (which is otherwise silent).
# Without the flag the same dir stays silent (covered by context_silent_ungoverned).
p="$(mktemp -d)"
out="$(printf '{"cwd":"%s"}' "$p" | "$NODE" "$CTX" --emit-protocol)"
echo "$out" | grep -q 'living-contract working protocol' && ok context_protocol_in_ungoverned_plugin_mode || bad context_protocol_in_ungoverned_plugin_mode
rm -rf "$p"

# CASE: protocol_is_stack_agnostic — zen.md (the always-on protocol) must name no OS / test library /
# package manager / build tool / language; the living-contract discipline is stack-neutral (C-032).
# Concrete tools may appear in the zen-* RECIPES as multi-platform examples, never in the protocol.
ZMD="$(cd "$(dirname "$0")/.." && pwd)/zen.md"
DENY='osascript|applescript|screencapture|xdotool|ydotool|\bexpect\(|\bgit\b|\.js\b|\.ts\b|\.py\b|\.rs\b|\.go\b|\.swift\b|\bjest\b|\bvitest\b|\bpytest\b|\brspec\b|\bjunit\b|\bnpm\b|\byarn\b|\bpnpm\b|\bcargo\b|homebrew|\bmacos\b|\bdarwin\b|\bwindows\b|\blinux\b|\bxcode\b'
if grep -nEi "$DENY" "$ZMD" >/dev/null 2>&1; then
	echo "  (stack-specific tokens in zen.md:)"
	grep -nEi "$DENY" "$ZMD"
	bad protocol_is_stack_agnostic
else ok protocol_is_stack_agnostic; fi

# CASE: protocol_stays_lean — zen.md (the always-on protocol, injected every session) must stay a lean
# core: axiom + checklist + reconcile/waive + skills router, with detail delegated to the zen-* skills
# (C-029). A hard line cap makes regrowth a deterministic failure, not a slow rot (it grew to ~230 lines
# / ~4.6k tokens once). Cap is generous over the trimmed size so legitimate edits don't trip it.
ZENMD="$(cd "$(dirname "$0")/.." && pwd)/zen.md"
CAP=165
lines=$(wc -l <"$ZENMD" | tr -d ' ')
[ -f "$ZENMD" ] && [ "$lines" -le "$CAP" ] && ok protocol_stays_lean || {
	echo "  (zen.md is $lines lines, cap $CAP)"
	bad protocol_stays_lean
}

# Base contract carrying the parked pending P-091 (the disproved one) — passed into new_repo as $1.
PARKED_PENDING='### P-091: Rolling conversation compaction for long sessions (tool-use survival)
- **Status:** PLANNED — research first; context size disproved, measure before building.
'

# CASE: gate_blocks_new_clause_near_duplicate — a NEW clause whose title shares ≥3 significant tokens
# with a parked pending it never references (the C-112↔P-091 trap) ⇒ block, routed to zen-implications.
r="$(new_repo "$PARKED_PENDING")"
commit "$r"
printf '## C-112: Rolling conversation compaction keeps small-model routing reliable\n- **Status:** pending verification\n' >>"$r/.zen/contract.md"
out="$(run_hook "$r")"
echo "$out" | grep -q '"decision":"block"' && echo "$out" | grep -qi 'near-duplicate' &&
	echo "$out" | grep -q 'C-112 ↔ P-091' && echo "$out" | grep -q 'zen-implications' &&
	ok gate_blocks_new_clause_near_duplicate || bad gate_blocks_new_clause_near_duplicate
rm -rf "$r"

# CASE: gate_silent_when_new_clause_cross_references — the same near-dup title, but the new clause's body
# NAMES P-091 (reconciled: supersede / relates / promotes) ⇒ not a silent dup ⇒ no near-duplicate drift.
r="$(new_repo "$PARKED_PENDING")"
commit "$r"
printf '## C-112: Rolling conversation compaction keeps small-model routing reliable\n- **Source:** supersedes P-091 after a measured failure-rate curve\n- **Status:** pending verification\n' >>"$r/.zen/contract.md"
out="$(run_hook "$r")"
! echo "$out" | grep -qi 'near-duplicate' && ok gate_silent_when_new_clause_cross_references || bad gate_silent_when_new_clause_cross_references
rm -rf "$r"

# CASE: gate_silent_when_titles_share_two_tokens — a NEW clause sharing only 2 significant title tokens
# with the pending is BELOW the ≥3 threshold ⇒ no false fire (the precision floor).
r="$(new_repo "$PARKED_PENDING")"
commit "$r"
printf '## C-200: Rolling conversation summary at session end\n- **Status:** pending verification\n' >>"$r/.zen/contract.md"
out="$(run_hook "$r")"
! echo "$out" | grep -qi 'near-duplicate' && ok gate_silent_when_titles_share_two_tokens || bad gate_silent_when_titles_share_two_tokens
rm -rf "$r"

# CASE: gate_grandfathers_preexisting_duplicate_pair — two near-dup clauses BOTH present at the last
# blessing (committed, in the baseline) are NOT flagged — only clauses ADDED since the baseline are
# compared. A code-only edit still blocks (turn-drift), but the dup reason must be ABSENT.
r="$(new_repo "$PARKED_PENDING
## C-112: Rolling conversation compaction keeps small-model routing reliable
- **Status:** verified
")"
commit "$r"
mk_turn "$r" "$r/Sources/Foo.swift" Edit
out="$(run_hook "$r")"
echo "$out" | grep -q '"decision":"block"' && ! echo "$out" | grep -qi 'near-duplicate' &&
	ok gate_grandfathers_preexisting_duplicate_pair || bad gate_grandfathers_preexisting_duplicate_pair
rm -rf "$r"

# CASE: gate_dup_fails_open_without_baseline — with NO git baseline (repo has no commit yet, so
# baselineContract returns null), the dup check cannot tell which clauses are NEW, so it fails open:
# a glaring near-dup pair already in the contract is NOT flagged. A backstop must never wedge a session
# for want of a baseline (C-028). Without this, a regression treating "no baseline" as "all clauses new"
# would wrongly block and no other C-044 case would catch it (the gap a zen-refuter pass surfaced).
r="$(new_repo "$PARKED_PENDING
## C-112: Rolling conversation compaction keeps small-model routing reliable
- **Status:** pending verification
")"
# deliberately NO commit ⇒ no HEAD ⇒ baselineContract → null ⇒ newClauseDuplicates → []
mk_turn "$r" "$r/.zen/contract.md" Edit
out="$(run_hook "$r")"
! echo "$out" | grep -qi 'near-duplicate' && ok gate_dup_fails_open_without_baseline || bad gate_dup_fails_open_without_baseline
rm -rf "$r"

# CASE: gate_idempotent_suppresses_repeat — THE loop fix. A code-only turn blocks (first nudge). With
# the repo state UNCHANGED, the next fire must NOT block again: pi re-injects a block as a follow-up
# user message, ending another turn on the identical state — without state-keyed dedupe that is the
# infinite reconcile loop that burned ~3M tokens. Run 1 blocks; run 2 on the same state is silent and
# records decision=block_suppressed.
r="$(new_repo)"
commit "$r"
mk_turn "$r" "$r/Sources/Foo.swift" Edit
out1="$(run_hook "$r")"
out2="$(run_hook "$r")"
if echo "$out1" | grep -q '"decision":"block"' && [ -z "$out2" ] &&
	tail -1 "$r/.zen/audit.jsonl" | grep -q '"decision":"block_suppressed"'; then
	ok gate_idempotent_suppresses_repeat
else
	bad gate_idempotent_suppresses_repeat
fi
rm -rf "$r"

# CASE: gate_reblocks_after_new_edit — the dedupe must not go permanently silent. After a block and a
# suppressed repeat, a genuinely NEW edit changes the state signature and re-arms the gate: it blocks
# again. Proves the guard keys on the state, not a one-shot latch.
r="$(new_repo)"
commit "$r"
mk_turn "$r" "$r/Sources/Foo.swift" Edit
run_hook "$r" >/dev/null # block
run_hook "$r" >/dev/null # suppressed
mk_turn "$r" "$r/Sources/Bar.swift" Edit # NEW edit → new signature
out="$(run_hook "$r")"
echo "$out" | grep -q '"decision":"block"' && ok gate_reblocks_after_new_edit || bad gate_reblocks_after_new_edit
rm -rf "$r"

echo "---"
if [ "$fails" -eq 0 ]; then
	echo "all gate cases passed"
	exit 0
fi
echo "$fails gate case(s) failed"
exit 1
