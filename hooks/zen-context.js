#!/usr/bin/env node
// IMPLICATION→MACHINE contract-awareness — SessionStart hook. Two audiences, two channels (claude-mem's
// hook-io discipline, issue #2292, confirmed by reading their source):
//   • hookSpecificOutput.additionalContext → the MODEL consumes it (silent to the human):
//     a concise progressive-disclosure index of the contract's state.
//   • systemMessage                        → Claude Code SURFACES it to the operator
//     (user-visible): the branded onboarding banner (C-022). Set ZEN_QUIET=1 to silence it.
// Governance is found by walking UP to the nearest .zen/contract.md (C-021), so the hook
// works in subdirectories, not only at the project root. Read-only; enforces nothing.
// Fails OPEN — a startup hook must never wedge a session.
//
// See zen.md and zen-framework-summary.md.

"use strict";

const fs = require("node:fs");
const path = require("node:path");
const { ALTITUDE_LINES, isGitRepo, findGovernedRoot, gitSummary, runEvidenceDrift, parseContract } = require("./zen-shared"); // single source (A5, C-021, C-023, C-024, C-033)

// Plugin mode (C-030): a plugin cannot load `@zen.md` (a plugin-root CLAUDE.md is NOT read by Claude
// Code), so deliver the lean protocol core via this SessionStart hook instead. ON only with the
// `--emit-protocol` flag (the plugin's hooks.json passes it; arg form is shell-agnostic, unlike an
// env prefix) or ZEN_EMIT_PROTOCOL=1; OFF in the dogfood so `@zen.md` is not double-injected.
const EMIT_PROTOCOL = process.argv.includes("--emit-protocol")
	|| !!(process.env.ZEN_EMIT_PROTOCOL && process.env.ZEN_EMIT_PROTOCOL !== "0");
function protocolText() {
	if (!EMIT_PROTOCOL) return "";
	// zen.md sits beside the hook dir, in BOTH the dogfood and the bundled plugin.
	try { return fs.readFileSync(path.join(__dirname, "..", "zen.md"), "utf8"); } catch { return ""; }
}
// Single exit: in plugin mode prepend the protocol to additionalContext (the model channel); always
// preserve the silent-when-empty contract (no plugin mode + nothing to say ⇒ write nothing).
function finish(out) {
	const proto = protocolText();
	if (proto) {
		out.hookSpecificOutput = out.hookSpecificOutput || { hookEventName: "SessionStart" };
		const idx = out.hookSpecificOutput.additionalContext;
		out.hookSpecificOutput.additionalContext = proto + (idx ? "\n\n---\n\n" + idx : "");
	}
	if (Object.keys(out).length) process.stdout.write(JSON.stringify(out));
}

// IMPLICATION→MACHINE wordmark — the visible onboarding banner (C-022): "ZEN" (the codename/heritage)
// in a block shadow font with IMPLICATION → MACHINE stacked beside it in a thin box font, an arrow
// between them. Full-width atop the panel; indigo vertical gradient whose steps track the row count.
const ZEN_MARK = [
	"███████╗███████╗███╗   ██╗    ╻┏┳┓┏━┓╻  ╻┏━╸┏━┓╺┳╸╻┏━┓┏┓╻",
	"╚══███╔╝██╔════╝████╗  ██║    ┃┃┃┃┣━┛┃  ┃┃  ┣━┫ ┃ ┃┃ ┃┃┗┫",
	"  ███╔╝ █████╗  ██╔██╗ ██║    ╹╹ ╹╹  ┗━╸╹┗━╸╹ ╹ ╹ ╹┗━┛╹ ╹",
	" ███╔╝  ██╔══╝  ██║╚██╗██║            ┏┳┓┏━┓┏━╸╻ ╻╻┏┓╻┏━╸",
	"███████╗███████╗██║ ╚████║    ───▶    ┃┃┃┣━┫┃  ┣━┫┃┃┗┫┣╸  ",
	"╚══════╝╚══════╝╚═╝  ╚═══╝            ╹ ╹╹ ╹┗━╸╹ ╹╹╹ ╹┗━╸",
];

// ── ANSI color (truecolor). ONLY the visible systemMessage is colored; additionalContext (the
// model's channel) stays plain. Honors NO_COLOR. visLen() measures VISIBLE width (escapes
// stripped) so colored strings still align under padTo. ──
const COLOR = !process.env.NO_COLOR;
const wrap = (open, s) => COLOR ? `\x1b[${open}m${s}\x1b[0m` : s;
const fg = (r, g, b, s) => wrap(`38;2;${r};${g};${b}`, s);
const bold = (s) => wrap("1", s);
const ital = (s) => wrap("3", s);
// Wordmark gradient — brightest indigo at the top fading to a deeper indigo at the bottom; the number
// of steps tracks the row count, so reshaping the art re-spreads the gradient automatically.
const MARK_TOP = [139, 128, 248], MARK_BOT = [83, 77, 149];
const markShade = (i, n) => MARK_TOP.map((c, k) => Math.round(c + (MARK_BOT[k] - c) * (n <= 1 ? 0 : i / (n - 1))));
const cOk = (s) => fg(120, 230, 140, s);    // green — all-clear
const cWarn = (s) => fg(240, 200, 110, s);  // amber — drift flags
const cCont = (s) => fg(125, 211, 252, s);  // cyan — continuity ("where we left off")
const cMute = (s) => fg(140, 150, 170, s);  // gray — rules, IDs, legend
function visLen(s) { return [...(s || "").replace(/\x1b\[[0-9;]*m/g, "")].length; }

// The wordmark, colored: an indigo top→bottom gradient over the art rows (steps = row count).
// banner() is the wordmark alone now — no badge — leading the visible panel full-width.
const COLORED_MARK = ZEN_MARK.map((row, i) => { const [r, g, b] = markShade(i, ZEN_MARK.length); return fg(r, g, b, row); });
function banner() { return COLORED_MARK.join("\n"); }

// Truncate to n code points with an ellipsis. Operates on PLAIN text — apply color afterward.
function clip(s, n) { const a = [...(s || "")]; return a.length > n ? a.slice(0, n - 1).join("") + "…" : (s || ""); }

// "2026-06-13" → "Jun 13" (compact, human). Empty string if unparseable.
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
function shortDate(iso) {
	const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(iso || "");
	return m ? `${MONTHS[+m[2] - 1] || "?"} ${+m[3]}` : "";
}

// A section rule: "── label ─────…" padded to `width`, in muted gray.
function rule(label, width = 58) {
	const head = `── ${label} `;
	return cMute(head + "─".repeat(Math.max(3, width - [...head].length)));
}

// Left-pad to n VISIBLE code points (so an ID/date column lines up under colored, varied titles).
function padTo(s, n) { return (s || "") + " ".repeat(Math.max(0, n - visLen(s))); }

function main() {
	let input = {};
	try { input = JSON.parse(fs.readFileSync(0, "utf8") || "{}"); } catch { /* no stdin */ }
	const cwd = input.cwd || process.cwd();
	// ZEN_QUIET silences the visible banner (systemMessage); the model still gets additionalContext.
	const quiet = !!(process.env.ZEN_QUIET && process.env.ZEN_QUIET !== "0");
	const root = findGovernedRoot(cwd); // walk up to the nearest governed project (C-021)

	if (!root) {
		// Ungoverned. Offer adoption — but ONLY in a git repo (a real project where IMPLICATION→MACHINE helps);
		// scratch/$HOME/tmp are not git repos, so they stay silent (no context-noise). C-018.
		if (!isGitRepo(cwd)) { finish({}); return; } // plugin mode still emits the protocol here
		const project = path.basename(cwd) || "project";
		const out = {
			hookSpecificOutput: {
				hookEventName: "SessionStart",
				additionalContext: `# [IMPLICATION→MACHINE] ${project} is not governed (no .zen/contract.md). Run /zen-init to adopt the living-contract workflow — contract ∧ tests ∧ docs ∧ code kept in agreement, with a Stop-gate that catches drift.`,
			},
		};
		if (!quiet) {
			const body = [
				`${bold(project)} ${cMute("— not under IMPLICATION→MACHINE yet")}`,
				"",
				"Keep contract ∧ tests ∧ docs ∧ code in agreement;",
				"a Stop-gate catches drift " + cMute("before it ever costs you."),
				"",
				`${cOk("→ run")} ${bold("/zen-init")} ${cOk("to adopt IMPLICATION→MACHINE here")}`,
			].join("\n");
			// Lead with a newline: Claude Code prefixes the first systemMessage line ("…says:"),
			// which would otherwise push the banner to mid-screen.
			out.systemMessage = "\n" + banner() + "\n\n" + body;
		}
		finish(out);
		return;
	}

	const contractPath = path.join(root, ".zen", "contract.md");
	const project = path.basename(root) || "project";
	// Project the SINGLE canonical parser (C-033) — the same one the gate blocks on, so the index the
	// operator reads and the verdict the gate enforces cannot disagree about what a clause/verified is.
	const clauses = parseContract(fs.readFileSync(contractPath, "utf8"));

	let cClauses = 0, cVerified = 0, pDeltas = 0, manualOnly = 0;
	const altitudeIds = [], unverifiedIds = [], pDeltaList = [];
	for (const c of clauses) {
		if (c.kind === "C") cClauses++;
		else if (c.kind === "P") {
			pDeltas++;
			// Date + title so the banner can name the OLDEST delta in plain words, not a bare ID
			// (file order is NOT chronological).
			pDeltaList.push({ id: c.id, date: c.date, title: c.title });
		}
		const isResolved = c.verified || /(PROMOTED|SHELVED|superseded|not[_ ]required|DECIDED|ANSWERED|DONE|retired)/i.test(c.statusRaw);
		if (c.kind === "C" && c.verified) cVerified++;
		if (c.kind === "C" && !isResolved) unverifiedIds.push({ id: c.id, title: c.title });
		// manual-only = the **Verification** field says `manual:` and lists no automated test.
		if (c.links.manual && c.links.automated.length === 0) manualOnly++;
		if (c.bodyLines > ALTITUDE_LINES && !c.evidence) altitudeIds.push(`${c.id} (${c.bodyLines}L)`);
	}

	const oldestDeltas = [...pDeltaList]
		.sort((a, b) => (a.date || "9999").localeCompare(b.date || "9999"))
		.slice(0, 3);
	const nonGit = !isGitRepo(root);
	// Continuity (C-023): /clear empties the transcript, but it must not empty the thread. Restore
	// "where we left off" from git (the existing trace), not a separate memory store that would drift.
	const recent = nonGit ? { subject: "", uncommitted: 0 } : gitSummary(root);
	let staleRuns = []; try { staleRuns = runEvidenceDrift(root); } catch { /* skip */ } // C-024 run-evidence drift

	// ── Channel 1: additionalContext — the MODEL's concise index (progressive disclosure). ──
	const md = [
		`# [IMPLICATION→MACHINE] contract state — ${project}`,
		`${cVerified}/${cClauses} C-clauses verified · ${manualOnly} manual-only · ${pDeltas} pending deltas.`,
	];
	if (recent.subject) md.push(`Where we left off: “${recent.subject}”${recent.uncommitted ? ` · ${recent.uncommitted} uncommitted file(s)` : ""}.`);
	const flags = [];
	if (nonGit) flags.push("⚠ not a git repo → the deterministic gate is essentially OFF: turn-drift, clause↔test link verification, and run-evidence all need git (IMPLICATION→MACHINE's substrate). Only the altitude check runs — `git init` to enable the full gate.");
	if (altitudeIds.length) flags.push(`⚠ altitude drift: ${altitudeIds.join(", ")} — move the lab-notebook to .zen/evidence/<ID>.md, leave one Evidence link.`);
	if (staleRuns.length) flags.push(`⚠ run-evidence drift: ${staleRuns.join("; ")} — re-run & re-record with zen-record-run.js.`);
	if (unverifiedIds.length) flags.push(`awaiting verification: ${unverifiedIds.slice(0, 12).map((u) => `${u.id}${u.title ? ` (${clip(u.title, 28)})` : ""}`).join(", ")}${unverifiedIds.length > 12 ? ` (+${unverifiedIds.length - 12} more)` : ""}.`);
	md.push(flags.length ? flags.join("\n") : "No structural drift (links resolve, altitude clean).");
	if (pDeltaList.length) {
		md.push(`↳ ${pDeltaList.length} pending delta${pDeltaList.length > 1 ? "s" : ""} — oldest: ${oldestDeltas.map((d) => `${d.id}${d.date ? ` (${d.date})` : ""}`).join(", ")}. Promote a ripe one with /zen-contract, or drop it if already resolved; /zen-check lists all.`);
	}
	md.push("→ index only — run /zen-check for the full map · clause bodies in .zen/contract.md · evidence logs in .zen/evidence/");

	const out = { hookSpecificOutput: { hookEventName: "SessionStart", additionalContext: md.join("\n") } };

	// ── Channel 2: systemMessage — the OPERATOR's visible banner, in PLAIN WORDS (C-022), with the
	// ZEN wordmark to the right. Reads top-to-bottom: project · health · where-we-left-off · the
	// oldest parked idea by name · the axiom. De-jargoned so a newcomer can read it. ──
	if (!quiet) {
		const tags = [];
		if (nonGit) tags.push("no git → gate mostly off (only altitude runs)");
		if (altitudeIds.length) tags.push(`${altitudeIds.length} clause(s) too long`);
		if (staleRuns.length) tags.push(`${staleRuns.length} run-evidence stale`);
		if (unverifiedIds.length) tags.push(`${unverifiedIds.length} awaiting proof`);

		// Top block: identity · health · where-we-left-off. The wordmark now leads as a full-width
		// banner above, so this block runs single-column at full width.
		const top = [
			`${bold(project)} ${cMute("· living contract")}`,
			`${bold(`${cVerified} of ${cClauses}`)} capabilities proven ${cMute("·")} ${manualOnly} checked by hand`,
			tags.length ? cWarn(`⚠ ${tags.join(" · ")}`) : `${cOk("✓")} contract, tests & docs agree ${cMute("— no drift")}`,
		];
		if (recent.subject) {
			top.push(`${cMute("↳ last:")} ${cCont(clip(recent.subject, 40))}`);
			if (recent.uncommitted) top.push(cMute(`  + ${recent.uncommitted} uncommitted change${recent.uncommitted > 1 ? "s" : ""}`));
		}
		const sections = [top.join("\n")];

		// Parked ideas — the 3 oldest by name (titles, not bare IDs), aligned, + how to act.
		if (oldestDeltas.length) {
			const rows = oldestDeltas.map((d) =>
				`${cMute("•")} ${padTo(clip(d.title || d.id, 42), 44)} ${cMute(`${d.id}${d.date ? ` · ${shortDate(d.date)}` : ""}`)}`);
			sections.push([
				rule(`${pDeltaList.length} parked idea${pDeltaList.length > 1 ? "s" : ""} · oldest first`),
				...rows,
				cMute("  → /zen-check sees all · /zen-contract promotes one"),
			].join("\n"));
		}

		// How to read this — a newcomer's legend (the teaching channel, C-020/C-022).
		sections.push([
			rule("how to read this"),
			cMute("capability  = a contract clause proven by a test"),
			cMute("parked idea = a P-xxx proposal not yet promoted"),
			cMute("commands: /zen-check · /zen-contract · /zen-verify · /zen-reconcile"),
		].join("\n"));

		sections.push(ital(cMute("“nothing is true until reality shows it”")));

		// Lead with a newline: Claude Code prefixes the first systemMessage line ("…says:"), which
		// would otherwise push the banner to mid-screen. The Serpent wordmark + badge lead the panel.
		out.systemMessage = "\n" + banner() + "\n\n" + sections.join("\n\n");
	}

	finish(out);
}

try { main(); } catch { process.exit(0); } // fail open: a startup hook must never break the session
