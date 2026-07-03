#!/usr/bin/env node
// Zen refute-evidence recorder (C-041) — records a zen-refuter verdict so the Stop-gate can require the
// disinterested-critic pass before a newly-`verified` behavioral clause stands.
//
// The refuter (agents/zen-refuter.md) is reached only by a model-chosen Task spawn, which never fired
// reliably from skill text (the run-3 E2E found it spawned 0/8). Making the RECORD a gate requirement is
// what forces the spawn: the honest path (spawn the critic, record its one-word verdict) is cheaper than
// faking it. This script does NOT run the refuter — it records the verdict you got from the real spawn,
// pinned to the clause's linked test SYMBOL's region hash (C-043), NOT the whole file: a sibling test
// changing in a shared file does not re-stale this refute (no cascade); only an edit to THIS clause's own
// symbol does. (Run-evidence keeps the whole-file hash — a run executes the whole file.) Honest limit, same
// as C-024: the verdict value is caller-supplied; the point is that recording the truth beats faking it and
// staleness is deterministic.
//
// Writes .zen/evidence/refutes/<clause>.json: { clause, verdict, ranAt, headCommit, tests:[{name,file,symbolSha}] }
//
// Usage:
//   node zen-record-refute.js --clause C-041 --verdict holds|trivial|refuted [--root <dir>]
// Exits 0 on holds/trivial (the clause is cleared to stand `verified`), 1 on refuted (a real gap — the
// clause is NOT cleared), 2 on a usage/IO error (so it composes in scripts/CI).

"use strict";

const fs = require("node:fs");
const path = require("node:path");
const { execFileSync } = require("node:child_process");
const { findGovernedRoot, parseClausesForEvidence, sha256, resolveLinkFiles, extractSymbol } = require("./zen-shared");

function fail(msg) { process.stderr.write(`zen-record-refute: ${msg}\n`); process.exit(2); }

function main() {
	const argv = process.argv.slice(2);
	let clause = "", verdict = "", rootArg = "";
	for (let i = 0; i < argv.length; i++) {
		if (argv[i] === "--clause") clause = argv[++i] || "";
		else if (argv[i] === "--verdict") verdict = (argv[++i] || "").toLowerCase();
		else if (argv[i] === "--root") rootArg = argv[++i] || "";
	}
	if (!/^[CP]-\d+$/.test(clause)) fail("need --clause C-xxx");
	if (!["holds", "trivial", "refuted"].includes(verdict)) fail("need --verdict holds|trivial|refuted (the zen-refuter's last-line verdict)");

	const root = rootArg || findGovernedRoot(process.cwd());
	if (!root || !fs.existsSync(path.join(root, ".zen", "contract.md"))) fail("not inside a governed project (.zen/contract.md)");

	const text = fs.readFileSync(path.join(root, ".zen", "contract.md"), "utf8");
	const found = parseClausesForEvidence(text).find((c) => c.id === clause);
	if (!found) fail(`clause ${clause} not found in contract`);

	// Pin freshness to the clause's OWN test SYMBOL, not the whole file (C-043), so a sibling test changing
	// in a shared file does not re-stale this refute (kills the cascade). extractSymbol returns the symbol's
	// region; null (unisolable) ⇒ fall back to the whole-file hash (safe, just no cascade benefit). Same
	// shared resolver as run-evidence (C-033/A5): a filename match wins over a mere content mention.
	const tests = found.tests.map((name) => {
		let file = "", symbolSha = "";
		try {
			file = (resolveLinkFiles(root, name).files[0] || "").trim();
			if (file) {
				const txt = fs.readFileSync(path.join(root, file), "utf8");
				const region = extractSymbol(txt, name);
				symbolSha = sha256(region !== null ? region : txt);
			}
		} catch { /* unlocatable test ⇒ empty file/sha ⇒ the gate will flag it stale */ }
		return { name, file, symbolSha };
	});

	let headCommit = "";
	try { headCommit = execFileSync("git", ["rev-parse", "HEAD"], { cwd: root, encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }).trim(); } catch { /* no commits */ }

	const record = { clause, verdict, ranAt: new Date().toISOString(), headCommit, tests };
	const dir = path.join(root, ".zen", "evidence", "refutes");
	fs.mkdirSync(dir, { recursive: true });
	fs.writeFileSync(path.join(dir, `${clause}.json`), JSON.stringify(record, null, 2) + "\n");

	const cleared = verdict !== "refuted";
	const tail = cleared ? "" : " — NOT cleared (strengthen the test, then re-refute)";
	process.stdout.write(`zen-record-refute: ${clause} ${verdict.toUpperCase()}${tail} · ${tests.length} test(s) · evidence → .zen/evidence/refutes/${clause}.json\n`);
	process.exit(cleared ? 0 : 1);
}

try { main(); } catch (e) { fail(String(e && e.message || e)); }
