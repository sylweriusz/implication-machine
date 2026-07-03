#!/usr/bin/env node
// IMPLICATION→MACHINE mid-turn verification-failure tripwire — PostToolUseFailure hook (C-045).
//
// Fires the MOMENT a Bash tool call fails (Claude Code routes failures to PostToolUseFailure,
// NOT PostToolUse which is success-only). When — and only when — the failed command was a
// VERIFICATION command (a test/build/typecheck/lint run), it injects a short nudge routing the
// model through zen-failure before it changes tests or claims done.
//
// It is a mid-turn ATTENTION nudge, never a correctness proof: it asserts nothing `verified`,
// records no evidence, cannot block (the tool already failed). The deterministic correctness
// substrate (contract drift, link resolution, run exit-code + freshness, refuter) is untouched.
//
// The failure signal is the EVENT FIRING ITSELF — never log-text parsing (the axiom forbids that).
// The only thing read is the structured tool_input.command, matched against a verification allowlist
// so probe failures (grep/rg/test -f/git diff --exit-code returning non-zero) stay silent.
//
// Passive in ungoverned trees, fails OPEN on any error (never wedges a session — C-028), and
// heartbeats one line per fire to .zen/audit.jsonl (liveness, matching the Stop-gate's practice).
//
// See zen.md for the protocol; C-045 in .zen/contract.md for the clause.

"use strict";

const fs = require("node:fs");
const path = require("node:path");
const { findGovernedRoot } = require("./zen-shared");

// --- The segment-split + env-prefix strip + the first block of VERIFICATION_PATTERNS are ported
//     from v-pi-zen/src/shell.ts (the battle-tested fragment that already paid the false-positive
//     cost). The second block broadens the allowlist host-agnostically (claude-zen runs anywhere,
//     not just the Swift+npm project v-pi-zen shipped against): a tripwire that stays silent on a
//     failed jest/vitest/eslint/mvn/gradle/dotnet/rspec run is a real false-negative. Each pattern
//     anchors on the bare (env-stripped) segment so a probe that merely MENTIONS a runner stays silent. ---
const VERIFICATION_PATTERNS = [
	// — ported verbatim from v-pi-zen —
	/^(npm|pnpm|yarn)\s+(test|run\s+(test|build|check|typecheck|lint|e2e))\b/,
	/^npx\s+tsc\b/,
	/^tsc\b/,
	/^swift\s+(test|build)\b/,
	/^scripts\/build-app\.sh\b/,
	/^xcodebuild\b/,
	/^go\s+(test|build)\b/,
	/^cargo\s+(test|build|check)\b/,
	/^pytest\b/,
	/^python\s+-m\s+pytest\b/,
	/^make\s+(test|check|build)\b/,
	// — claude-zen host-agnostic broadening —
	/^(npx\s+)?(jest|vitest|mocha|eslint)\b/,
	/^bun\s+(test|run\s+(test|build|check|lint|typecheck))\b/,
	/^deno\s+(test|check|lint)\b/,
	/^ruff\b/,
	/^(bundle\s+exec\s+)?(rspec|rubocop)\b/,
	/^(phpunit|\.\/vendor\/bin\/phpunit|composer\s+test)\b/,
	/^mvn\s+(test|verify)\b/,
	/^(gradle|\.\/gradlew)\s+(test|check|build)\b/,
	/^dotnet\s+(test|build)\b/,
];

function stripEnvPrefix(segment) {
	// CI=1 npm test → npm test ; FOO="a b" pytest → pytest
	return segment.replace(/^(?:[A-Z_][A-Z0-9_]*=(?:"[^"]*"|'[^']*'|\S+)\s+)+/, "");
}

function splitShellSegments(command) {
	return command
		.replace(/\r\n/g, "\n")
		.replace(/\n+/g, "; ")
		.split(/\s*(?:&&|\|\||;|\|)\s*/) // && ; || | — any segment may be the verification step
		.map((s) => s.trim().replace(/\s+/g, " "))
		.filter(Boolean);
}

// True iff ANY segment of the (possibly compound) command is a verification command.
function isVerificationCommand(command) {
	for (const seg of splitShellSegments(command)) {
		const bare = stripEnvPrefix(seg);
		if (VERIFICATION_PATTERNS.some((p) => p.test(bare))) return true;
	}
	return false;
}

function audit(zenDir, record) {
	try {
		const line = JSON.stringify({ ts: new Date().toISOString(), ...record }) + "\n";
		fs.appendFileSync(path.join(zenDir, "audit.jsonl"), line);
	} catch { /* trace is best-effort; never throw from here */ }
}

function emit(additionalContext) {
	process.stdout.write(JSON.stringify({
		hookSpecificOutput: { hookEventName: "PostToolUseFailure", additionalContext },
	}));
}

function main() {
	let input;
	try { input = JSON.parse(fs.readFileSync(0, "utf8") || "{}"); } catch { return; } // fail open
	if (input.tool_name && input.tool_name !== "Bash") return; // matcher already scopes; double-guard
	const command = input.tool_input && input.tool_input.command;
	if (typeof command !== "string" || !command.trim()) return; // nothing to classify → silent

	const cwd = input.cwd || process.cwd();
	const root = findGovernedRoot(cwd);
	if (!root) return; // ungoverned (no .zen/contract.md at/above cwd) → passive, silent
	const zenDir = path.join(root, ".zen");

	const fired = isVerificationCommand(command);
	audit(zenDir, { event: "verification_failure_tripwire", fired, command: command.slice(0, 200) });
	if (!fired) return; // probe/mutating/unknown failure → silent (the model already sees the error)

	emit(
		"[IMPLICATION→MACHINE] A verification command just failed. Treat it as product evidence, " +
		"not noise: diagnose and classify it via zen-failure (bug | missing_feature | wrong_assumption | " +
		"ambiguous_contract | environment_issue) BEFORE changing the test or claiming done. " +
		"Never weaken a test to reach green."
	);
}

try { main(); } catch { /* fail OPEN: a tripwire must never wedge a session (C-028) */ }
