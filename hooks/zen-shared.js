#!/usr/bin/env node
// Shared constants/helpers for the Zen hooks — single source of truth (A5).
// Both zen-reconcile-gate.js and zen-context.js require this so the altitude threshold and the
// git probe cannot drift between the two. require("./zen-shared") resolves relative to the hook's
// own directory regardless of cwd. No project state here — pure constants + a stateless probe.

"use strict";

const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");
const { execFileSync } = require("node:child_process");

function sha256(s) { return crypto.createHash("sha256").update(s).digest("hex"); }

// A clause whose body exceeds this many lines, with no `Evidence:` link, is altitude drift
// (C-012/C-013): its lab-notebook belongs in .zen/evidence/<ID>.md, not in the clause.
const ALTITUDE_LINES = 40;

// Find the governed project ROOT: the nearest ancestor of `startDir` (inclusive) that holds
// .zen/contract.md — exactly how git locates .git (C-021). Returns the root dir, or null if none
// up to the filesystem root. Without this, the hooks treated only the exact cwd as governed, so
// the gate went silently passive in EVERY subdirectory of a governed project (`src/`, `Sources/`…).
function findGovernedRoot(startDir) {
	let dir;
	try { dir = path.resolve(startDir || "."); } catch { return null; }
	for (;;) {
		if (fs.existsSync(path.join(dir, ".zen", "contract.md"))) return dir;
		const parent = path.dirname(dir);
		if (parent === dir) return null; // reached filesystem root, no governed ancestor
		dir = parent;
	}
}

// Is `cwd` inside a usable git work tree? Zen's link-drift check is `git grep` (C-004); the
// SessionStart onboarding nudge keys on this too (C-017). Exit 0 = inside a work tree;
// exit 128 (not a repo) / ENOENT (git missing) → false.
function isGitRepo(cwd) {
	try {
		execFileSync("git", ["rev-parse", "--is-inside-work-tree"], { cwd, stdio: ["ignore", "ignore", "ignore"] });
		return true;
	} catch {
		return false;
	}
}

// Cheap continuity from the trace that already exists (git) — NOT a separate memory store, which
// would be a second source of truth that drifts (the anti-pattern Zen exists to kill). After
// /clear the transcript is empty, so the last commit subject + uncommitted-file count restore
// "where we left off". Fail-safe: returns blanks on any error / no commits / non-git.
function gitSummary(root) {
	const run = (args) => execFileSync("git", args, { cwd: root, stdio: ["ignore", "pipe", "ignore"] }).toString();
	try {
		const subject = run(["log", "-1", "--format=%s"]).trim();
		const uncommitted = run(["status", "--porcelain"]).split("\n").filter(Boolean).length;
		return { subject, uncommitted };
	} catch {
		return { subject: "", uncommitted: 0 };
	}
}

// Files changed in the governed project's working tree, relative to the git root, SCOPED to the
// governed subtree (pathspec `.` under `-C root`, so a sibling project in the same repo cannot cause
// false turn-drift — verified by spike). This is the gate's harness-agnostic edit-detector (C-036),
// replacing transcript parsing: it works on any harness (an edit is an edit regardless of who or what
// made it) and folds in subagent edits for free — git does not care about the author — which subsumes
// the old transcript-folding (supersedes C-014). Renames report the NEW path; staged, unstaged, and
// untracked all count (everything uncommitted-vs-the-tree). THROWS on a non-git project so the caller
// can skip turn-drift the way link-drift is skipped without git (fail open, never fabricate drift).
function changedPaths(root) {
	// `-uall` expands untracked DIRECTORIES to their individual files — without it git collapses a
	// wholly-untracked dir to `?? Sources/`, which classify() reads as "other" (no extension) and a new
	// code file in a fresh dir would silently slip the gate (caught by the test suite, not the spike).
	const out = execFileSync("git", ["-C", root, "status", "--porcelain", "-uall", "--", "."], { stdio: ["ignore", "pipe", "ignore"] }).toString();
	const paths = [];
	for (const line of out.split("\n")) {
		if (!line) continue;
		let p = line.slice(3);                 // drop the 2-char XY status + its trailing space
		const arrow = p.indexOf(" -> ");        // rename/copy "old -> new" → the new path is what exists now
		if (arrow !== -1) p = p.slice(arrow + 4);
		p = p.replace(/^"(.*)"$/, "$1");         // git quotes paths with odd chars; unwrap the common case
		paths.push(p);
	}
	return paths;
}

// THE single canonical contract parser (C-033). The Stop-gate, the SessionStart hook, the run-
// recorder, the `zen` CLI, and the tests all project FROM this one function, so "what is a clause /
// what is verified / what is a link / what is drift" cannot diverge between the human-facing report
// and the gate's verdict (the latent triple-parser drift this closes). Pure function of the text;
// computed fresh — there is no persisted index (parsing is sub-ms even at ~140 KB, and a cache kept
// as a write side-effect would desync on edits arriving via editor/VCS/model — forbidden).
//
// Returns one object per `## C-xxx:` / `### P-xxx:` clause:
//   { id, kind:"C"|"P", title, date, source, statusRaw, verified,
//     links:{ automated:[names], manual:bool, notRequired:bool },
//     evidence:"<path or ''>", bodyLines, lineStart, lineEnd, body }
// Extraction rules are exactly the union of the three prior parsers (see C-004/C-013/C-024).
function parseContract(text) {
	const lines = text.split("\n");
	const heads = [];
	lines.forEach((l, i) => { if (/^#{2,3}\s+[CP]-\d+:/.test(l)) heads.push(i); });
	const out = [];
	for (let k = 0; k < heads.length; k++) {
		const s = heads[k];
		let e = lines.length;
		for (let j = s + 1; j < lines.length; j++) { if (/^#{2,3}\s+/.test(lines[j])) { e = j; break; } }
		const block = lines.slice(s, e);
		const head = lines[s];
		const id = (head.match(/([CP]-\d+)/) || [])[1] || "?";
		const kind = id[0] === "P" ? "P" : "C";
		const title = head.replace(/^#{2,3}\s+[CP]-\d+:\s*/, "").trim();
		const joined = block.join("\n");
		const dm = joined.match(/\*\*Date:\*\*\s*([0-9]{4}-[0-9]{2}-[0-9]{2})/i);
		const date = dm ? dm[1] : "";
		const sm = joined.match(/\*\*Source:\*\*\s*([^\n]+)/i);
		const source = sm ? sm[1].trim() : "";
		// Status: the LAST `**Status**` FIELD line (not prose mentioning "status").
		let statusRaw = "";
		for (const l of block) { if (/\*\*Status\b/i.test(l)) statusRaw = l.replace(/^.*\*\*Status:?\*\*\s*/i, "").trim(); }
		const verified = /\bverified\b/i.test(statusRaw);
		// Verification field → links. Link names come ONLY from the **Verification** field line — not
		// from prose that happens to contain "automated → <test>" (C-026's description does), which
		// would inject bogus tokens like "or" (git-grep matches it inside ".gitignore"). C-004/C-024.
		const automated = [];
		let manual = false, notRequired = false;
		for (const l of block) {
			if (!/\*\*Verification\b/i.test(l)) continue;
			if (/\bmanual:/i.test(l)) manual = true;
			if (/\bnot_required:/i.test(l)) notRequired = true;
			const m = l.match(/automated\s*(?:→|->)\s*([^\n]+)/i);
			if (!m) continue;
			const seg = m[1].split("|")[0].split("(")[0];
			for (const piece of seg.split(",")) {
				// `/` is part of the token: a link written as a path (`test/mdtoc.test.js`) must survive
				// whole — truncating at `/` made it content-match the wrong file (demo-caught, C-048).
				const tok = (piece.trim().replace(/^`|`$/g, "").match(/^[A-Za-z_][\w.\/\-]*/) || [])[0];
				if (tok && tok.length <= 120) automated.push(tok);
			}
		}
		// Evidence: a line carrying BOTH `Evidence:` and an `evidence/<ID>` path (the altitude escape).
		let evidence = "";
		for (const l of block) {
			if (/Evidence:/i.test(l) && /evidence\/[CP]-\d+/i.test(l)) {
				const em = l.match(/([\w./-]*evidence\/[CP]-\d+[\w./-]*)/i);
				evidence = em ? em[1] : l.replace(/^.*Evidence:\s*/i, "").trim();
				break;
			}
		}
		out.push({
			id, kind, title, date, source, statusRaw, verified,
			links: { automated, manual, notRequired },
			evidence, bodyLines: block.length, lineStart: s, lineEnd: e, body: joined,
		});
	}
	return out;
}

// Run-evidence projection (C-024): id, verified, and the linked automated test names. Back-compat
// shape for the recorder and the run-evidence checks below — a thin projection of parseContract.
function parseClausesForEvidence(text) {
	return parseContract(text).map((c) => ({ id: c.id, verified: c.verified, tests: c.links.automated }));
}

// Clause-altitude drift (C-013), shared by the gate and the CLI. A clause whose body exceeds
// ALTITUDE_LINES with no `Evidence:` link has outgrown intent into a research diary. Pure (no git).
function altitudeDrift(root) {
	const text = fs.readFileSync(path.join(root, ".zen", "contract.md"), "utf8");
	const bloated = [];
	for (const c of parseContract(text)) {
		if (c.bodyLines > ALTITUDE_LINES && !c.evidence) bloated.push(`${c.id} (${c.bodyLines} lines)`);
	}
	return bloated;
}

// Broken clause↔test links (C-004), shared by the gate and the CLI — the ungameable deterministic
// fact. Returns { broken:[names], verifiable }. `verifiable:false` ⇒ no git / git error ⇒ the check
// could not run and is SKIPPED (NOT "all broken"): with no cheap deterministic fact, the gate must
// not fabricate one. EXCLUDE .zen/ — else git grep finds the name inside the very clause that
// declares it and every link looks satisfied (a false negative that silently kills the check).
// --untracked covers a test written this turn but not yet `git add`ed. Exit code 0/1/≥2 distinguish
// resolved / genuinely-broken / unverifiable. No silent cap — every declared link is checked.
// A heading that LOOKS like a clause id (`## C-001` / `### P-002`, ANY delimiter) but does NOT parse
// into a clause — almost always the `:` is missing (`## C-001 —` instead of the canonical `## C-001:`).
// The clause is then INVISIBLE to the gate, the CLI, and record-run (parseContract sees nothing), yet
// turn-drift passes because the file was touched — a clause that exists only in prose gives ZERO
// verification coverage while the gate stays green (the E2E soundness gap). This makes it loud.
function malformedClauseHeadings(root) {
	let text;
	try { text = fs.readFileSync(path.join(root, ".zen", "contract.md"), "utf8"); }
	catch { return []; }
	const parsed = new Set(parseContract(text).map((c) => c.id));
	const bad = [];
	for (const line of text.split("\n")) {
		const m = /^#{2,3}\s+([CP]-\d+)\b/.exec(line);                 // a clause-id heading, any delimiter
		if (m && !parsed.has(m[1]) && !bad.includes(m[1])) bad.push(m[1]); // id present but parseContract missed it
	}
	return bad;
}

// Resolve a verification-link token to the work-tree file(s) it designates. A link names a test by
// EITHER (a) a FILE — a path or basename that EXISTS in the tree (e.g. `slug.test.js`) — OR (b) an
// IDENTIFIER — a case/function name that appears as text in a tracked runner/test file (the dogfood
// convention, e.g. `gate_blocks_code_only`). Filename match WINS: it is the artifact the link points
// AT, so record-run hashes the test itself, not some other file that merely mentions its name (the
// package.json-first-match trap). Content match is the fallback. ls-files/grep both exclude .zen/ (so
// a token is never "resolved" by the very clause that declares it) and cover untracked-not-ignored
// files (a test written this turn but not yet `git add`ed). Returns { files, error } — error=true on a
// real git failure (exit ≥2) so the caller marks the result UNVERIFIABLE rather than "broken".
function resolveLinkFiles(root, name) {
	// (a) filename / path existence — cached (tracked) + others (untracked-not-ignored), minus .zen/
	try {
		const listed = execFileSync("git", ["ls-files", "--cached", "--others", "--exclude-standard", "--", ":!.zen/"],
			{ cwd: root, encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }).split("\n").filter(Boolean);
		const byPath = listed.filter((p) => p === name || p.slice(p.lastIndexOf("/") + 1) === name);
		if (byPath.length) return { files: byPath, error: false };
	} catch { /* ls-files failed → fall through to content match */ }
	// (b) content match — the token appears as text in a file outside .zen/
	try {
		const out = execFileSync("git", ["grep", "--untracked", "-lF", "-e", name, "--", ":!.zen/"],
			{ cwd: root, encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] });
		return { files: out.split("\n").filter(Boolean), error: false };
	} catch (e) {
		if (e && e.status === 1) return { files: [], error: false };  // clean no-match ⇒ genuinely unresolved
		return { files: [], error: true };                            // exit ≥2 / spawn error ⇒ unverifiable
	}
}

function brokenLinks(root) {
	const text = fs.readFileSync(path.join(root, ".zen", "contract.md"), "utf8");
	const names = new Set();
	for (const c of parseContract(text)) for (const n of c.links.automated) names.add(n);
	if (!isGitRepo(root)) return { broken: [], verifiable: false };
	const broken = [];
	for (const name of names) {
		const r = resolveLinkFiles(root, name);
		if (r.error) return { broken: [], verifiable: false };  // exit ≥2 / spawn error mid-loop ⇒ unverifiable
		if (r.files.length === 0) broken.push(name);            // neither a file nor referenced in content
	}
	return { broken, verifiable: true };
}

// Run-evidence freshness (C-024). For each VERIFIED clause that HAS a recorded run
// (.zen/evidence/runs/<id>.json), confirm the run passed and is still fresh — every test file it
// recorded must hash to the same value now. A clause with NO evidence is NOT flagged (adoption is
// gradual; "verified" without a recorded run is the pre-existing baseline, surfaced softly by the
// SessionStart index, not blocked). Returns drift strings. The deterministic half of "verified =
// it actually ran green"; the model writes the evidence cheaply via zen-record-run.js, and a real
// re-run is the release-gate's job (no test suite is executed here — the Stop-hook must stay fast).
// State of one clause's recorded run: missing | unreadable | failed | stale | fresh.
// "fresh" = a run was recorded, it passed (exit 0), and every test file it recorded hashes the
// same now. The deterministic verdict is the runner-captured exit code; the gate never parses the
// log's text for pass/fail (that would be a fuzzy parser — see C-027). Policy lives in the command.
function evidenceStatus(root, clauseId) {
	const evPath = path.join(root, ".zen", "evidence", "runs", `${clauseId}.json`);
	if (!fs.existsSync(evPath)) return { state: "missing" };
	let rec;
	try { rec = JSON.parse(fs.readFileSync(evPath, "utf8")); } catch { return { state: "unreadable" }; }
	if (rec.exitCode !== 0) return { state: "failed", detail: `exit ${rec.exitCode}` };
	for (const t of rec.tests || []) {
		let curSha = null;
		try { curSha = sha256(fs.readFileSync(path.join(root, t.file || ""), "utf8")); } catch { /* missing file */ }
		if (curSha !== t.fileSha) return { state: "stale", detail: t.file || t.name };
	}
	return { state: "fresh" };
}

// Run-evidence freshness (C-024): VERIFIED clauses whose recorded run failed or went stale. A clause
// with no recorded run is NOT flagged here (gradual adoption); the newly-verified check below is the
// one that makes a fresh claim cost something.
function runEvidenceDrift(root) {
	if (!fs.existsSync(path.join(root, ".zen", "evidence", "runs"))) return [];
	const text = fs.readFileSync(path.join(root, ".zen", "contract.md"), "utf8");
	const drift = [];
	for (const c of parseClausesForEvidence(text)) {
		if (!c.verified) continue;
		const st = evidenceStatus(root, c.id);
		if (st.state === "unreadable") drift.push(`${c.id} (unreadable run-evidence)`);
		else if (st.state === "failed") drift.push(`${c.id} (recorded run FAILED — ${st.detail})`);
		else if (st.state === "stale") drift.push(`${c.id} (run-evidence stale — ${st.detail} changed since last run)`);
		// "missing" ⇒ gradual, "fresh" ⇒ clean
	}
	return drift;
}

// The grandfather baseline (C-042): the contract as it stood the last time THE GATE ACTUALLY RAN — not
// live HEAD. The newly-verified checks grandfather pre-existing verified clauses so they don't wall the
// backlog, and used `git show HEAD:`. But HEAD moves WITHIN a turn as the agent commits (commit-as-you-go,
// the near-universal workflow), so a clause verified+committed this turn is already in HEAD by Stop-time
// and grandfathers itself out of both gates — a false-green on honest work (E2E run-4 #1). A deterministic
// gate must not depend on the agent NOT committing. The honest baseline is "what the gate last blessed":
// every fire stamps `headCommit` (the exact HEAD sha) into `.zen/audit.jsonl`, so the previous fire's sha
// IS the baseline — read it back, no timestamp matching (exact, no boundary slip). This turn's commits are
// newer than that sha ⇒ not grandfathered ⇒ caught; the backlog (committed before the last fire) stays in
// the baseline ⇒ no wall. No audit yet (first-ever fire, or a fresh clone — audit.jsonl is gitignored) ⇒
// fall back to live HEAD: trust the committed state, since with no prior fire there is no "since when" to
// diff against. That fallback is a one-fire window, and it is the audit TRACE that makes tampering loud —
// deleting the heartbeat to widen the window is exactly the dead-hook signal the trace exists to expose
// (same honest-limit class as C-024). Returns the baseline contract text, or null when even HEAD fails.
// Current HEAD sha, or "" (non-git / no commits). The Stop-gate stamps this into every audit entry so the
// NEXT fire can use it as the grandfather baseline (C-042) — exact, no timestamp matching.
function headSha(root) {
	try { return execFileSync("git", ["rev-parse", "HEAD"], { cwd: root, encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }).trim(); }
	catch { return ""; }
}

function baselineContract(root) {
	let sha = "";
	try {
		const lines = fs.readFileSync(path.join(root, ".zen", "audit.jsonl"), "utf8").trim().split("\n");
		for (let i = lines.length - 1; i >= 0; i--) {
			try { const e = JSON.parse(lines[i]); if (e && e.headCommit) { sha = e.headCommit; break; } } catch { /* skip a bad line */ }
		}
	} catch { /* no heartbeat yet ⇒ first fire ⇒ ref stays HEAD */ }
	const ref = sha || "HEAD";
	try { return execFileSync("git", ["show", `${ref}:./.zen/contract.md`], { cwd: root, encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }); }
	catch {
		if (sha) { // recorded sha unreachable (e.g. history rewrite) — fall back to live HEAD rather than wedge
			try { return execFileSync("git", ["show", "HEAD:./.zen/contract.md"], { cwd: root, encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }); } catch { return null; }
		}
		return null;
	}
}

// Make the lie cost a block (C-026): a clause that became `verified` since the gate last blessed this repo
// (the C-042 baseline, NOT live HEAD — so commit-as-you-go can't grandfather a clause out of the gate) and
// claims an `automated → <test>` must have a FRESH recorded run, or the gate blocks. Only NEW claims are
// pressured — pre-existing verified clauses are grandfathered (no wall). No baseline (non-git / no commits)
// ⇒ returns [] (fail open, never wedge). manual:/not_required: clauses have no `automated` link, never caught.
function newlyVerifiedWithoutEvidence(root) {
	const baseText = baselineContract(root);
	if (baseText === null) return [];
	const wasVerified = new Set(parseClausesForEvidence(baseText).filter((c) => c.verified).map((c) => c.id));
	const now = parseClausesForEvidence(fs.readFileSync(path.join(root, ".zen", "contract.md"), "utf8"));
	const flagged = [];
	for (const c of now) {
		if (!c.verified || !c.tests.length) continue; // only verified clauses claiming an automated test
		if (wasVerified.has(c.id)) continue;          // grandfathered: already verified as of the last blessing
		if (evidenceStatus(root, c.id).state !== "fresh") flagged.push(c.id);
	}
	return flagged;
}

// Extract the region of a test file belonging to test SYMBOL `name` — its definition line through the line
// before the next sibling definition (or EOF). Used to pin refute-evidence freshness to the clause's OWN
// test rather than the whole file (C-043): editing a SIBLING test in a shared file no longer stales this
// clause's refute, killing the O(N) re-refute cascade an E2E run measured (run-4 Finding B — 9 of 12 critic
// spawns were re-refutes of unchanged clauses). Best-effort, language-agnostic by convention — recognizes
// the common test-block openers (`# CASE: <name>`, `def name`, `func name`, `name() {`, `it(`/`test(`). It is
// CONSERVATIVE: anchors on the symbol's DEFINITION (not a mere mention) and runs to the next same-or-lower-
// indent opener, so it errs toward OVER-inclusion (a needless re-refute) never under-inclusion (false-fresh,
// where a weakened test reads `fresh`). Returns null when no definition-opener carries the name ⇒ the caller
// hashes the whole file — the safe fallback. So the worst case is the pre-C-043 cost, never a missed change.
function extractSymbol(text, name) {
	const sym = String(name).split("::").pop().split("#").pop().trim();   // file.py::test_x → test_x
	if (!sym) return null;
	const lines = text.split("\n");
	const wordRe = new RegExp("(^|[^\\w])" + sym.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + "([^\\w]|$)");
	const caseRe = /^\s*#\s*CASE:/;                                            // shell-style test block header
	const codeRe = /^(\s*)(def\s|func\s|function\s|it\s*\(|test\s*\(|describe\s*\()/; // function-style test opener
	// Anchor `start` on the symbol's DEFINITION — a `# CASE:` header or a code opener that NAMES it — not the
	// first mention: a call / `ok <name>` before the def would otherwise anchor on the wrong line and truncate
	// the real body (false-fresh). No definition-opener carries the name ⇒ return null ⇒ caller hashes the
	// whole file (safe over-stale fallback, never false-fresh). NOTE: a bare `name() {` is deliberately NOT an
	// opener — inside a `# CASE:` body a `setup() {` helper at the header's own indent would falsely end the
	// region (the false-fresh hole an adversarial refute found); a file that uses bare `name(){` as its test
	// symbol simply falls back to whole-file hashing (safe).
	let start = -1, isCase = false, indent = "";
	for (let i = 0; i < lines.length; i++) {
		if (!wordRe.test(lines[i])) continue;
		if (caseRe.test(lines[i])) { start = i; isCase = true; break; }
		const m = codeRe.exec(lines[i]);
		if (m) { start = i; indent = m[1]; break; }
	}
	if (start === -1) return null;
	// End the region by CONVENTION: a `# CASE:` block runs to the next `# CASE:` ONLY (flat shell cases are
	// delimited by the header, never by in-body function defs); a code block runs to the next same-or-lower-
	// indent code opener (a DEEPER nested opener does not end it). Conservative — errs toward OVER-inclusion
	// (a needless re-refute), never under-inclusion (false-fresh).
	let end = lines.length;
	for (let i = start + 1; i < lines.length; i++) {
		if (isCase) { if (caseRe.test(lines[i])) { end = i; break; } }
		else { const m = codeRe.exec(lines[i]); if (m && m[1].length <= indent.length) { end = i; break; } }
	}
	return lines.slice(start, end).join("\n");
}

// Refute-evidence (C-041): the disinterested-critic half of "verified". A clause newly flipped to
// `verified` must carry a recorded zen-refuter pass — verdict `holds` (the test proves the clause) or
// `trivial` (no behavioral surface to refute). `refuted` (a real gap the critic found) or missing/stale ⇒
// block. The refuter is reached only by a model-chosen Task spawn, which never fired reliably from skill
// text (the run-3 finding: 0/8); making the RECORD a gate requirement is what forces the spawn — the honest
// path (spawn the critic, record its verdict) is cheaper than the lie. Honest-limit identical to C-024: the
// verdict VALUE is caller-written, but recording the truth beats faking it and staleness is deterministic.
// Freshness pins the clause's linked test SYMBOL's hash, NOT the whole file (C-043) — so a sibling test
// changing in a shared file does not re-stale this refute (no cascade). A record predating C-043 has no
// `symbolSha` ⇒ reads as stale once ⇒ one re-refute to upgrade. State: missing | unreadable | refuted | stale | fresh.
function refuteStatus(root, clauseId) {
	const evPath = path.join(root, ".zen", "evidence", "refutes", `${clauseId}.json`);
	if (!fs.existsSync(evPath)) return { state: "missing" };
	let rec;
	try { rec = JSON.parse(fs.readFileSync(evPath, "utf8")); } catch { return { state: "unreadable" }; }
	if (rec.verdict === "refuted") return { state: "refuted" };
	if (rec.verdict !== "holds" && rec.verdict !== "trivial") return { state: "unreadable", detail: `unknown verdict "${rec.verdict}"` };
	for (const t of rec.tests || []) {
		let curSha = null;
		try {
			const fileText = fs.readFileSync(path.join(root, t.file || ""), "utf8");
			const region = extractSymbol(fileText, t.name); // null ⇒ fall back to whole-file (safe, no cascade benefit)
			curSha = sha256(region !== null ? region : fileText);
		} catch { /* missing file ⇒ curSha stays null ⇒ stale */ }
		if (curSha !== t.symbolSha) return { state: "stale", detail: t.file || t.name };
	}
	return { state: "fresh" };
}

// Refute requirement (C-041): newly-`verified` clauses (since the last gate blessing — the C-042 baseline,
// not live HEAD, so commit-as-you-go can't grandfather a clause out of the gate) claiming an automated test
// whose refute record is missing, refuted, or stale. Only NEW claims are pressured — pre-existing verified
// clauses are grandfathered (gradual adoption, no wall on the backlog). No baseline ⇒ [] (fail open).
// Returns drift strings with the WHY.
function newlyVerifiedWithoutRefute(root) {
	const baseText = baselineContract(root); // last gate-blessed commit, not live HEAD (C-042)
	if (baseText === null) return [];
	const wasVerified = new Set(parseClausesForEvidence(baseText).filter((c) => c.verified).map((c) => c.id));
	const now = parseClausesForEvidence(fs.readFileSync(path.join(root, ".zen", "contract.md"), "utf8"));
	const flagged = [];
	for (const c of now) {
		if (!c.verified || !c.tests.length) continue; // only verified clauses claiming an automated test
		if (wasVerified.has(c.id)) continue;          // grandfathered: already verified at HEAD
		const st = refuteStatus(root, c.id);
		if (st.state === "fresh") continue;
		const why = st.state === "missing" ? "no refute recorded"
			: st.state === "refuted" ? "refuter found a gap — strengthen the test, then re-refute"
			: st.state === "stale" ? `refute stale — ${st.detail} changed since`
			: `unreadable refute${st.detail ? " — " + st.detail : ""}`;
		flagged.push(`${c.id} (${why})`);
	}
	return flagged;
}

// Add-time near-duplicate gate (C-044): a clause ADDED since the gate last blessed this repo (the
// C-042 baseline) whose TITLE shares ≥3 significant tokens with an existing clause/pending it does
// NOT cross-reference is flagged — the C-112↔P-091 trap, where a new clause re-builds (or contradicts)
// something a parked pending already holds or DISPROVED, and the self-report "search before add"
// (zen-contract step 2) was simply skipped. This converts the weakest self-report step into the one
// thing the gate catches — the axiom's "any gate you can satisfy by self-report is weak". Scoped to
// NEW clauses only (baselineContract, C-042) so a long contract's existing pairs are never re-compared
// — tiny false-positive blast radius. The escape is a CROSS-REFERENCE: a new clause whose body NAMES
// the matched id (supersede / relates / promotes) has been reconciled and is not flagged. Resolution
// is semantic (merge? did the pending disprove this? genuinely distinct?), so the gate only SURFACES
// the pair and routes to zen-implications; it never decides direction (§3/§12 — the new clause may be
// the bug). Fails open (no git baseline → [], never wedge, C-028).
// ponytail: the ≥3-significant-token threshold catches multi-word-phrase dupes (the real failure mode,
// e.g. "rolling conversation compaction" shared 3 ways); a bare 2-word near-dupe ("Voice cloning" vs
// "Voice cloning support") still leans on the recipe-level semantic search — raise sensitivity here if
// those start slipping the gate.
const TITLE_STOPWORDS = new Set([
	"that", "this", "when", "into", "from", "with", "have", "will", "your",
	"been", "then", "what", "which", "where", "must", "than", "over", "keeps",
]);
function significantTitleTokens(title) {
	return new Set(
		String(title).toLowerCase().split(/[^a-z0-9]+/).filter((t) => t.length >= 4 && !TITLE_STOPWORDS.has(t))
	);
}
function newClauseDuplicates(root) {
	const baseText = baselineContract(root);
	if (baseText === null) return []; // no baseline (non-git / first fire) ⇒ fail open
	const wasPresent = new Set(parseContract(baseText).map((c) => c.id));
	const now = parseContract(fs.readFileSync(path.join(root, ".zen", "contract.md"), "utf8"));
	const flagged = [];
	for (const c of now) {
		if (wasPresent.has(c.id)) continue;          // only clauses ADDED since the last blessing
		const mine = significantTitleTokens(c.title);
		if (mine.size === 0) continue;
		for (const other of now) {
			if (other.id === c.id) continue;
			if (c.body.includes(other.id)) continue;   // already cross-referenced ⇒ reconciled, not a silent dup
			const theirs = significantTitleTokens(other.title);
			let shared = 0;
			for (const t of mine) if (theirs.has(t)) shared++;
			if (shared >= 3) { flagged.push(`${c.id} ↔ ${other.id}`); break; } // one pair per new clause is enough to surface it
		}
	}
	return flagged;
}

module.exports = { ALTITUDE_LINES, isGitRepo, findGovernedRoot, gitSummary, changedPaths, sha256, parseContract, parseClausesForEvidence, altitudeDrift, malformedClauseHeadings, resolveLinkFiles, brokenLinks, evidenceStatus, runEvidenceDrift, newlyVerifiedWithoutEvidence, refuteStatus, newlyVerifiedWithoutRefute, newClauseDuplicates, headSha, extractSymbol };
