#!/usr/bin/env node
// IMPLICATION→MACHINE turn-end checklist gate — Stop hook.
// Fires at the end of a turn ONLY in IMPLICATION→MACHINE-governed projects (those with .zen/contract.md).
//
// It does two ungameable things and one model-facing thing:
//   1. Deterministic fact (always, when governed): parse .zen/contract.md for
//      `Verification: automated → <test>` links and check each named test actually
//      exists in the repo (git grep). Broken links = real drift, regardless of intent.
//   2. Turn fact: did this turn edit source code without touching the contract?
//   3. If either shows drift, present the TURN-END CHECKLIST and ask the model to
//      close it (reconcile) or WAIVE citing the C-xxx clause that already covers it.
//
// Observability (so a dead hook is visible, not silent): every fire — including a
// parse error — appends one line to .zen/audit.jsonl. No audit line ⇒ the hook is
// not running. Fails OPEN on any error: a backstop must never wedge a session.
//
// See zen.md for the protocol this enforces.

"use strict";

const fs = require("node:fs");
const path = require("node:path");
const {
	ALTITUDE_LINES,
	findGovernedRoot,
	changedPaths,
	altitudeDrift,
	malformedClauseHeadings,
	brokenLinks,
	runEvidenceDrift,
	newlyVerifiedWithoutEvidence,
	newlyVerifiedWithoutRefute,
	newClauseDuplicates,
	headSha,
} = require("./zen-shared"); // single source of truth (A5, C-021, C-024, C-026, C-033, C-036, C-041, C-042, C-044)

const CODE_EXT = new Set([
	".swift",
	".ts",
	".tsx",
	".js",
	".jsx",
	".mjs",
	".cjs",
	".py",
	".go",
	".rs",
	".c",
	".cc",
	".cpp",
	".cxx",
	".h",
	".hpp",
	".m",
	".mm",
	".java",
	".kt",
	".kts",
	".rb",
	".php",
	".lua",
	".hs",
	".ex",
	".exs",
	".dart",
	".zig",
	".scala",
	".cs",
	".vue",
	".svelte",
	".sql",
	".sh",
	".bash",
	".html",
	".htm",
	".css", // web source — a browser project's logic/markup/style IS its code (C-001, E2E run 5)
]);

function readStdin() {
	try {
		return fs.readFileSync(0, "utf8");
	} catch {
		return "";
	}
}

function audit(zenDir, record) {
	try {
		const line =
			JSON.stringify({ ts: new Date().toISOString(), ...record }) + "\n";
		fs.appendFileSync(path.join(zenDir, "audit.jsonl"), line);
	} catch {
		/* trace is best-effort; never throw from here */
	}
}

// Content hash of the repo-state the gate just judged (djb2). Not crypto: a collision only risks a
// missed suppression (one extra nudge), never a false suppression (a real drift silenced).
function stateSig(head, changed, drifts) {
	const payload = `${head}|${[...changed].sort().join(",")}|${drifts
		.map((d) => (d ? 1 : 0))
		.join("")}`;
	let h = 5381;
	for (let i = 0; i < payload.length; i++)
		h = ((h << 5) + h + payload.charCodeAt(i)) >>> 0;
	return h.toString(16);
}

// Signature of the most recent stop_gate that ended in a block (block or block_suppressed). undefined
// if the last fire passed, or there is no audit yet — so a fresh block is never wrongly suppressed.
function lastBlockedSig(zenDir) {
	try {
		const lines = fs
			.readFileSync(path.join(zenDir, "audit.jsonl"), "utf8")
			.trim()
			.split("\n");
		for (let i = lines.length - 1; i >= 0; i--) {
			if (!lines[i]) continue;
			const rec = JSON.parse(lines[i]);
			if (rec.event !== "stop_gate") continue;
			return typeof rec.decision === "string" && rec.decision.startsWith("block")
				? rec.sig
				: undefined;
		}
	} catch {
		/* no audit yet / unreadable → nothing to dedupe against */
	}
	return undefined;
}

function classify(p) {
	const lower = p.toLowerCase();
	const base = path.basename(lower);
	if (/(^|\/)\.zen\/contract\.md$/.test(lower)) return "contract"; // the governed contract only — NOT any file named contract.md
	if (
		// Match test files by CONVENTION, not a bare "test"/"spec" substring (which mis-classified
		// real code like latest.swift / inspector.js → "test", letting a code-only change slip the gate).
		/(^|\/)(tests?|specs?|__tests__)\//.test(lower) || // in a test/spec directory
		/\.(tests?|specs?)\./.test(base) || // foo.test.js, foo.spec.ts
		/_(tests?|specs?)\./.test(base) || // foo_test.go, foo_spec.rb
		/^(tests?|specs?)_/.test(base) // test_foo.py, spec_helper.rb
	)
		return "test";
	const ext = path.extname(lower);
	if (ext === ".md" || /(^|\/)docs?\//.test(lower) || base.startsWith("readme"))
		return "doc";
	if (CODE_EXT.has(ext)) return "code";
	return "other";
}

// Edit detection is git-based: zen-shared.changedPaths reads the working tree (C-036), so the gate
// no longer parses a harness-specific transcript. It is harness-agnostic and folds in subagent edits
// for free (git does not care who wrote the file — this subsumes the old transcript-folding, C-014).
// classify() above maps each changed path to a kind.

// The two clause-level deterministic facts the gate blocks on — broken clause↔test links (C-004)
// and clause-altitude drift (C-013) — now live in ./zen-shared.js (brokenLinks, altitudeDrift),
// shared verbatim with the `zen` CLI so the human-facing report and the gate's verdict cannot
// diverge (C-033). The gate calls them; it no longer re-derives the parse or the git probe.

function main() {
	const input = JSON.parse(readStdin() || "{}");
	if (input.stop_hook_active) return; // already nudged this turn — don't loop
	const cwd = input.cwd || process.cwd();
	// Governance is found by walking UP to the nearest .zen/contract.md (C-021) — so the gate stays
	// armed in subdirectories, not only at the project root. `root` is used everywhere below.
	const root = findGovernedRoot(cwd);
	if (!root) return; // ungoverned (no .zen/contract.md at or above cwd) → passive
	const zenDir = path.join(root, ".zen");

	let kinds, links;
	let changed = [];
	try {
		changed = changedPaths(root);
		kinds = new Set(changed.map(classify));
	} catch {
		// non-git (or git error): turn-drift can't be computed deterministically → skip it, exactly as
		// the link check skips without git. Never fabricate drift; never wedge the session (C-036, C-028).
		kinds = new Set();
		audit(zenDir, { event: "edit_detection_skipped", why: "non_git_or_error" });
	}
	try {
		links = brokenLinks(root);
	} catch {
		links = { broken: [], verifiable: false }; // contract unreadable → skip the check, don't wedge
	}
	const broken = links.broken;
	let bloated;
	try {
		bloated = altitudeDrift(root);
	} catch {
		bloated = []; // contract unreadable → skip altitude check, don't wedge
	}
	let staleRuns;
	try {
		staleRuns = runEvidenceDrift(root);
	} catch {
		staleRuns = []; // evidence unreadable → skip the run-evidence check, don't wedge
	}
	let newClaims;
	try {
		newClaims = newlyVerifiedWithoutEvidence(root);
	} catch {
		newClaims = []; // no git baseline / error → skip, don't wedge
	}
	let malformed;
	try {
		malformed = malformedClauseHeadings(root);
	} catch {
		malformed = []; // contract unreadable → skip, don't wedge
	}
	let refuteClaims;
	try {
		refuteClaims = newlyVerifiedWithoutRefute(root);
	} catch {
		refuteClaims = []; // no git baseline / error → skip, don't wedge
	}
	let dupClaims;
	try {
		dupClaims = newClauseDuplicates(root);
	} catch {
		dupClaims = []; // no git baseline / error → skip, don't wedge
	}

	const codeEdited = kinds.has("code");
	const contractEdited = kinds.has("contract");
	const testEdited = kinds.has("test");

	// Drift if: code changed without the contract moving, OR a clause claims a test
	// that does not exist. Touching a test does NOT excuse a stale contract (that was
	// the old gate's blind spot).
	const turnDrift = codeEdited && !contractEdited;
	const linkDrift = links.verifiable && broken.length > 0;
	const altDrift = bloated.length > 0;
	const evidenceDrift = staleRuns.length > 0; // a verified clause whose recorded run failed or went stale (C-024)
	const claimDrift = newClaims.length > 0; // a clause newly claimed `verified` (automated) without a fresh run (C-026)
	const headingDrift = malformed.length > 0; // a clause-id heading that doesn't parse → invisible clause (C-039)
	const refuteDrift = refuteClaims.length > 0; // a clause newly `verified` without a fresh disinterested-critic pass (C-041)
	const dupDrift = dupClaims.length > 0; // a clause newly ADDED that near-duplicates an un-referenced clause/pending (C-044)

	const blocked =
		turnDrift ||
		linkDrift ||
		altDrift ||
		evidenceDrift ||
		claimDrift ||
		headingDrift ||
		refuteDrift ||
		dupDrift;

	// Idempotency guard: nudge a given repo-state at most once. stop_hook_active covers the
	// within-cascade re-fire, but a genuinely new turn that changed NOTHING (pre-existing untracked
	// code keeping turnDrift permanently true — defect B) re-blocks every turn. Key the nudge on the
	// state (HEAD + dirty paths + which drifts fired): if the LAST stop_gate already blocked this exact
	// state, the model saw it and changed nothing, so let it yield. A real edit re-arms the gate.
	const headCommit = headSha(root);
	const sig = stateSig(headCommit, changed, [
		turnDrift,
		linkDrift,
		altDrift,
		evidenceDrift,
		claimDrift,
		headingDrift,
		refuteDrift,
		dupDrift,
	]);
	const repeat = blocked && sig === lastBlockedSig(zenDir);

	audit(zenDir, {
		event: "stop_gate",
		headCommit, // the HEAD this fire blessed — the NEXT fire's grandfather baseline (C-042)
		codeEdited,
		contractEdited,
		testEdited,
		brokenLinks: broken.length,
		linksVerifiable: links.verifiable,
		altitudeDrift: bloated.length,
		runEvidenceDrift: staleRuns.length,
		newVerifiedNoEvidence: newClaims.length,
		malformedHeadings: malformed.length,
		newVerifiedNoRefute: refuteClaims.length,
		newClauseDuplicates: dupClaims.length,
		sig,
		decision: !blocked ? "pass" : repeat ? "block_suppressed" : "block",
	});

	if (!blocked || repeat) return; // closeable on its own, or already nudged this exact state — silent

	const lines = [
		"[IMPLICATION→MACHINE] Turn-end checklist — close it before yielding (reconcile, or waive citing the clause):",
		`  ${contractEdited ? "✓" : "✗"} contract — a C-xxx clause exists/updated for this change`,
		`  ${testEdited ? "✓" : "·"} test — covers it (edge cases + correctness, exact assertions), exists & passes`,
		"  · docs — match the behavior",
		"  · code — implements the clause, nothing more",
		"  · verified against reality",
	];
	if (turnDrift) {
		lines.push("");
		lines.push(
			"This turn edited source code but did not touch .zen/contract.md. Either move the",
		);
		lines.push(
			"matching clause (and its test/doc), or WAIVE in one line citing the C-xxx clause that",
		);
		lines.push(
			"already covers it — if none fits, you must add one (that is the point).",
		);
	}
	if (linkDrift) {
		lines.push("");
		lines.push(
			"Broken verification links — these clauses claim an `automated → <test>` that does NOT",
		);
		lines.push("exist in the repo (stale status / fabricated coverage):");
		for (const n of broken) lines.push(`  • ${n}`);
		lines.push(
			"Fix the link, write the missing test, or correct the clause's status. Run /zen-converge",
		);
		lines.push("to sweep all drift. Do not weaken a test to pass.");
	}
	if (altDrift) {
		lines.push("");
		lines.push(
			"Clause-altitude drift — these clauses outgrew intent into a research diary (over",
		);
		lines.push(
			`${ALTITUDE_LINES} lines) with no \`Evidence:\` link. Move the spike logs / sweeps / running`,
		);
		lines.push(
			"commentary into `.zen/evidence/<ID>.md` and leave one `Evidence:` line on the clause:",
		);
		for (const c of bloated) lines.push(`  • ${c}`);
	}
	if (evidenceDrift) {
		lines.push("");
		lines.push(
			"Run-evidence drift — these `verified` clauses have a recorded run that FAILED or went",
		);
		lines.push(
			"stale (the test file changed since it last ran green). `verified` must mean it actually",
		);
		lines.push(
			"ran green, not just that a test by that name exists — re-run and re-record:",
		);
		for (const c of staleRuns) lines.push(`  • ${c}`);
		lines.push(
			"  node <zen>/hooks/zen-record-run.js --clause <C-xxx> -- <your test command>",
		);
	}
	if (claimDrift) {
		lines.push("");
		lines.push(
			"Newly verified without proof — these clauses became `verified` since the gate last blessed this repo and",
		);
		lines.push(
			"claim an `automated → <test>`, but no fresh run is recorded. Don't just type `verified` —",
		);
		lines.push(
			"record the real run (cheaper than faking it), or drop the status back to pending:",
		);
		for (const c of newClaims) lines.push(`  • ${c}`);
		lines.push(
			"  node <zen>/hooks/zen-record-run.js --clause <C-xxx> -- <your test command>",
		);
	}
	if (refuteDrift) {
		lines.push("");
		lines.push(
			"Unrefuted verification — these clauses became `verified` since the gate last blessed this repo but carry no",
		);
		lines.push(
			"fresh adversarial-critic pass. A passing test is not proof on its own: SPAWN the zen-refuter",
		);
		lines.push(
			"subagent on the clause + its diff (don't grade your own test), then record its last-line",
		);
		lines.push(
			"verdict — `holds`/`trivial` clears it, `refuted` means strengthen the test first:",
		);
		for (const c of refuteClaims) lines.push(`  • ${c}`);
		lines.push(
			"  use the zen-refuter subagent to refute <C-xxx> against this diff",
		);
		lines.push(
			"  node <zen>/hooks/zen-record-refute.js --clause <C-xxx> --verdict holds|trivial|refuted",
		);
	}
	if (dupDrift) {
		lines.push("");
		lines.push(
			"Near-duplicate clause — these NEW clauses share their capability with an existing clause or",
		);
		lines.push(
			"pending they never reference (the C-112↔P-091 trap: re-building, or contradicting, something a",
		);
		lines.push(
			"parked pending already holds or DISPROVED — the add-time search, zen-contract step 2, was skipped):",
		);
		for (const p of dupClaims) lines.push(`  • ${p}`);
		lines.push(
			"SPAWN the zen-implications subagent to resolve each pair — the direction is NOT pre-decided:",
		);
		lines.push(
			"merge the two, supersede one, HONOUR the existing finding (the parked pending may have disproved",
		);
		lines.push(
			"this — then the new clause is the bug), or, if genuinely distinct, cross-reference it and re-run:",
		);
		lines.push(
			"  use the zen-implications subagent to confront <new C-xxx> against the contract",
		);
	}
	if (headingDrift) {
		lines.push("");
		lines.push(
			"Malformed clause heading — these ids appear as a heading but do NOT parse into a clause,",
		);
		lines.push(
			"so the gate, the CLI, and run-evidence are all blind to them (zero coverage while green).",
		);
		lines.push(
			"The grammar needs a COLON right after the id — `## C-001:` not `## C-001 —`. Fix it:",
		);
		for (const id of malformed) lines.push(`  • ${id}`);
	}

	process.stdout.write(
		JSON.stringify({ decision: "block", reason: lines.join("\n") }),
	);
}

try {
	main();
} catch {
	process.exit(0); // fail open: a backstop must never break the session
}
