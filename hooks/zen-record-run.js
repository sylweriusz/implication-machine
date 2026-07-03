#!/usr/bin/env node
// Zen run-evidence recorder (C-024) — makes the honest path the cheap path.
//
// Runs a clause's verification command for real, captures the actual result, and writes a tamper-
// evident-ish record to .zen/evidence/runs/<clause>.json:
//   { clause, command, exitCode, outputSha, ranAt, headCommit, tests:[{name,file,fileSha}] }
//
// The Stop-gate (zen-shared.runEvidenceDrift) then checks, every turn, that a VERIFIED clause's
// recorded run passed AND is still fresh (each test file hashes the same now) — so "verified"
// means "it actually ran green", not just "a test by that name exists". Honest limit: there is no
// external executor, so a determined liar could hand-write this JSON; the point is that recording
// the truth (one command) is easier than faking it, and staleness is caught deterministically. A
// real re-run is the release-gate's job.
//
// Usage:
//   node zen-record-run.js --clause C-083 [--root <dir>] -- <command...>
// Example:
//   node zen-record-run.js --clause C-001 -- bash hooks/zen-reconcile-gate.test.sh
//
// Exits with the command's own exit code (so it composes in scripts/CI).

"use strict";

const fs = require("node:fs");
const path = require("node:path");
const { execFileSync, spawnSync } = require("node:child_process");
const { findGovernedRoot, parseClausesForEvidence, sha256, resolveLinkFiles } = require("./zen-shared");

function fail(msg) { process.stderr.write(`zen-record-run: ${msg}\n`); process.exit(2); }

function main() {
	const argv = process.argv.slice(2);
	const dashdash = argv.indexOf("--");
	const flags = dashdash === -1 ? argv : argv.slice(0, dashdash);
	let cmd = dashdash === -1 ? [] : argv.slice(dashdash + 1);

	let clause = "", rootArg = "", rerun = false;
	for (let i = 0; i < flags.length; i++) {
		if (flags[i] === "--clause") clause = flags[++i] || "";
		else if (flags[i] === "--root") rootArg = flags[++i] || "";
		else if (flags[i] === "--rerun") rerun = true;
	}
	if (!/^[CP]-\d+$/.test(clause)) fail("need --clause C-xxx");

	const root = rootArg || findGovernedRoot(process.cwd());
	if (!root || !fs.existsSync(path.join(root, ".zen", "contract.md"))) fail("not inside a governed project (.zen/contract.md)");

	const evPath = path.join(root, ".zen", "evidence", "runs", `${clause}.json`);

	// --rerun reuses the command recorded last time (zero-friction re-verification): the honest path
	// stays the cheap path. The release re-run is just --rerun over every clause that has evidence.
	if (rerun) {
		if (cmd.length) fail("--rerun reuses the recorded command; don't also pass `-- <command>`");
		let prev;
		try { prev = JSON.parse(fs.readFileSync(evPath, "utf8")); } catch { fail(`no prior run for ${clause} to rerun (record one first: -- <command>)`); }
		cmd = (prev.commandArgv && prev.commandArgv.length) ? prev.commandArgv : (prev.command ? prev.command.split(" ") : []);
		if (!cmd.length) fail(`prior run for ${clause} has no command to reuse`);
	}
	if (!cmd.length) fail("missing `-- <command>` to run (or --rerun to reuse the recorded one)");

	// Find the clause's linked test names from the contract.
	const text = fs.readFileSync(path.join(root, ".zen", "contract.md"), "utf8");
	const found = parseClausesForEvidence(text).find((c) => c.id === clause);
	if (!found) fail(`clause ${clause} not found in contract`);

	// Locate + hash each test file NOW (the gate re-hashes these paths to detect staleness). Use the
	// SHARED resolver (C-033/A5) so the recorder hashes the file the token NAMES — a filename match wins
	// over a file that merely mentions the name (the package.json-first-match trap the E2E found).
	const tests = found.tests.map((name) => {
		let file = "", fileSha = "";
		try {
			file = (resolveLinkFiles(root, name).files[0] || "").trim();
			if (file) fileSha = sha256(fs.readFileSync(path.join(root, file), "utf8"));
		} catch { /* unlocatable test ⇒ empty file/sha ⇒ the gate will flag it stale */ }
		return { name, file, fileSha };
	});

	// Run the real command and capture the real result.
	const res = spawnSync(cmd[0], cmd.slice(1), { cwd: root, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });
	const exitCode = res.status === null ? 1 : res.status; // signal/spawn-fail ⇒ treat as failure
	const output = (res.stdout || "") + (res.stderr || "");
	// Human-readable receipt: the LAST lines (the test framework's pass/fail summary). Bounded so the
	// record stays small (overwritten per clause, never O(rounds)). The gate does NOT parse this for
	// pass/fail — that's the exit code's job (C-027); the tail is for you and me to read.
	const outputTail = output.replace(/\s+$/, "").split("\n").slice(-15).join("\n");
	let headCommit = "";
	try { headCommit = execFileSync("git", ["rev-parse", "HEAD"], { cwd: root, encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }).trim(); } catch { /* no commits */ }

	const record = {
		clause,
		command: cmd.join(" "),
		commandArgv: cmd,
		exitCode,
		outputSha: sha256(output),
		outputTail,
		ranAt: new Date().toISOString(),
		headCommit,
		tests,
	};
	const runsDir = path.join(root, ".zen", "evidence", "runs");
	fs.mkdirSync(runsDir, { recursive: true });
	fs.writeFileSync(evPath, JSON.stringify(record, null, 2) + "\n");

	const verdict = exitCode === 0 ? "PASS" : `FAIL (exit ${exitCode})`;
	process.stdout.write(`zen-record-run: ${clause} ${verdict} · ${tests.length} test(s) · evidence → .zen/evidence/runs/${clause}.json\n`);
	process.exit(exitCode);
}

try { main(); } catch (e) { fail(String(e && e.message || e)); }
