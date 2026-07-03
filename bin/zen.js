#!/usr/bin/env node
// `zen` — deterministic CLI over a IMPLICATION→MACHINE-governed project's .zen/contract.md (C-033).
//
// Built on the SINGLE canonical parser, zen-shared.parseContract — the very function the Stop-gate,
// the SessionStart hook and the run-recorder project from — so `zen drift`/`lint` and the gate's
// verdict cannot diverge. The CLI is a pure function of the contract files, computed fresh each call
// (no persisted index). It SHARES the gate's calculation but never replaces it: the gate stays the
// independent enforcer at Stop; `zen verify` enforces the same invariant (a link must resolve AND its
// recorded run be fresh) so the honest path is the cheap one. Verification is exact `git grep`, never
// anything fuzzy (the deterministic boundary it shares with sibling P-001). Errors exit non-zero
// (C-027). "Delete" is never physical rm — only status transitions (C-023; the write ops land next).
//
// Resolves zen-shared relative to this file (bin/ → ../hooks), so it works in BOTH the dogfood config
// dir and the bundled plugin (${CLAUDE_PLUGIN_ROOT}/bin → ${CLAUDE_PLUGIN_ROOT}/hooks) unchanged.

"use strict";

const fs = require("node:fs");
const path = require("node:path");
const {
	findGovernedRoot, parseContract, altitudeDrift, brokenLinks,
	evidenceStatus, runEvidenceDrift, newlyVerifiedWithoutEvidence, refuteStatus,
} = require(path.join(__dirname, "..", "hooks", "zen-shared"));

function die(msg, code = 2) { process.stderr.write(`zen: ${msg}\n`); process.exit(code); }

// A downstream consumer closing the pipe early (`zen list | head`, `zen status | grep -q`) makes
// stdout emit EPIPE. That is the reader's choice, not our error — exit cleanly, never crash.
process.stdout.on("error", (e) => { if (e && e.code === "EPIPE") process.exit(0); throw e; });

// Pull a `--flag value` (or boolean `--flag`) out of an argv array, returning [value, rest].
function takeFlag(args, name, boolean = false) {
	const i = args.indexOf(name);
	if (i === -1) return [boolean ? false : null, args];
	const val = boolean ? true : args[i + 1];
	const rest = args.slice(0, i).concat(args.slice(i + (boolean ? 1 : 2)));
	return [val, rest];
}

function contractPath(root) { return path.join(root, ".zen", "contract.md"); }
function readContract(root) { return fs.readFileSync(contractPath(root), "utf8"); }
function clauses(root) { return parseContract(readContract(root)); }
function findClause(root, id) { return clauses(root).find((c) => c.id === id.toUpperCase()); }

// Short, human status label from the raw status field value.
function statusLabel(c) {
	const s = (c.statusRaw || "").toLowerCase();
	if (c.verified) return "verified";
	if (/pending/.test(s)) return "pending";
	if (/superseded/.test(s)) return "superseded";
	if (/shelved/.test(s)) return "shelved";
	if (/archived/.test(s)) return "archived";
	return s ? s.split(/\s+/)[0] : "—";
}
function verKind(c) {
	if (c.links.automated.length) return "automated";
	if (c.links.manual) return "manual";
	if (c.links.notRequired) return "not_required";
	return "—";
}
function pad(s, n) { s = String(s); return s.length >= n ? s : s + " ".repeat(n - s.length); }

// ── READ ────────────────────────────────────────────────────────────────────────────────────────

function cmdList(root, args) {
	const [statusFilter, a1] = takeFlag(args, "--status");
	const [kindFilter] = takeFlag(a1, "--kind");
	let cs = clauses(root);
	if (kindFilter) cs = cs.filter((c) => c.kind === kindFilter.toUpperCase());
	if (statusFilter) {
		const f = statusFilter.toLowerCase();
		cs = cs.filter((c) => (c.statusRaw || "").toLowerCase().includes(f));
	}
	if (args.includes("--json")) { process.stdout.write(JSON.stringify(cs.map(jsonClause), null, 2) + "\n"); return; }
	for (const c of cs) {
		process.stdout.write(`${pad(c.id, 7)} ${pad(statusLabel(c), 12)} ${pad(verKind(c), 13)} ${c.title}\n`);
	}
}

function jsonClause(c) {
	return {
		id: c.id, kind: c.kind, title: c.title, date: c.date, source: c.source,
		status: statusLabel(c), verified: c.verified,
		verification: { automated: c.links.automated, manual: c.links.manual, not_required: c.links.notRequired },
		evidence: c.evidence,
	};
}

function cmdShow(root, args) {
	const [json] = takeFlag(args, "--json", true);
	const id = args.find((a) => /^[CP]-\d+$/i.test(a));
	if (!id) die("usage: zen show <C-xxx> [--json]");
	const c = findClause(root, id);
	if (!c) die(`unknown clause ${id.toUpperCase()}`);
	if (json) process.stdout.write(JSON.stringify(jsonClause(c), null, 2) + "\n");
	else process.stdout.write(c.body + "\n");
}

function cmdGrep(root, args) {
	const [json] = takeFlag(args, "--json", true);
	const term = args.find((a) => !a.startsWith("--"));
	if (!term) die("usage: zen grep <term> [--json]");
	const re = new RegExp(term.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"), "i");
	const hits = clauses(root).filter((c) => re.test(c.body));
	if (json) { process.stdout.write(JSON.stringify(hits.map(jsonClause), null, 2) + "\n"); return; }
	for (const c of hits) process.stdout.write(`${pad(c.id, 7)} ${c.title}\n`);
}

// Resolution of one clause's automated links: does each resolve (git grep), and is its run fresh?
function linkReport(root, c) {
	const { broken, verifiable } = brokenLinks(root);
	const ev = evidenceStatus(root, c.id);
	return c.links.automated.map((name) => ({
		name,
		resolves: !verifiable ? "unverifiable" : (broken.includes(name) ? "BROKEN" : "RESOLVED"),
		run: ev.state, // missing | unreadable | failed | stale | fresh
	}));
}

function cmdLinks(root, args) {
	const [json] = takeFlag(args, "--json", true);
	const id = args.find((a) => /^[CP]-\d+$/i.test(a));
	if (!id) die("usage: zen links <C-xxx> [--json]");
	const c = findClause(root, id);
	if (!c) die(`unknown clause ${id.toUpperCase()}`);
	const rep = linkReport(root, c);
	if (json) { process.stdout.write(JSON.stringify({ id: c.id, links: rep }, null, 2) + "\n"); return; }
	if (!rep.length) { process.stdout.write(`${c.id}: no automated links (${verKind(c)})\n`); return; }
	for (const r of rep) process.stdout.write(`${pad(r.name, 40)} ${pad(r.resolves, 13)} run: ${r.run}\n`);
}

function cmdNextId(root, args) {
	const kind = (args.find((a) => /^[CP]$/i.test(a)) || "C").toUpperCase();
	const nums = clauses(root).filter((c) => c.kind === kind).map((c) => parseInt(c.id.split("-")[1], 10)).filter((n) => !isNaN(n));
	const next = (nums.length ? Math.max(...nums) : 0) + 1;
	process.stdout.write(`${kind}-${String(next).padStart(3, "0")}\n`);
}

// ── DRIFT / LINT / STATUS ─────────────────────────────────────────────────────────────────────
// The deterministic facts shared with the gate (minus turn-drift, which is a git working-tree fact
// (C-036), not a fact about the contract file). Same functions the Stop-gate blocks on ⇒ the verdicts agree (C-033).
function collectDrift(root) {
	const links = (() => { try { return brokenLinks(root); } catch { return { broken: [], verifiable: false }; } })();
	const altitude = (() => { try { return altitudeDrift(root); } catch { return []; } })();
	const runs = (() => { try { return runEvidenceDrift(root); } catch { return []; } })();
	const newClaims = (() => { try { return newlyVerifiedWithoutEvidence(root); } catch { return []; } })();
	return { links, altitude, runs, newClaims };
}
function driftLines(d) {
	const out = [];
	if (d.links.verifiable && d.links.broken.length) out.push(`broken links: ${d.links.broken.join(", ")}`);
	if (!d.links.verifiable) out.push("link check unverifiable (not a git repo — `git init` to enable it)");
	if (d.altitude.length) out.push(`altitude drift: ${d.altitude.join(", ")}`);
	if (d.runs.length) out.push(`run-evidence drift: ${d.runs.join("; ")}`);
	if (d.newClaims.length) out.push(`newly verified without a fresh run: ${d.newClaims.join(", ")}`);
	return out;
}
// A blocking-class drift is what the gate would block on. An unverifiable link check is NOT blocking
// (the gate skips it too — no cheap fact ⇒ don't fabricate one).
function hasBlockingDrift(d) {
	return (d.links.verifiable && d.links.broken.length > 0) || d.altitude.length > 0 || d.runs.length > 0 || d.newClaims.length > 0;
}

function cmdDrift(root, args) {
	const d = collectDrift(root);
	if (args.includes("--json")) { process.stdout.write(JSON.stringify(d, null, 2) + "\n"); return; }
	const lines = driftLines(d);
	process.stdout.write(lines.length ? lines.map((l) => `• ${l}`).join("\n") + "\n" : "no drift — links resolve, altitude clean, run-evidence fresh\n");
}

function cmdLint(root, args) {
	const d = collectDrift(root);
	if (args.includes("--json")) {
		process.stdout.write(JSON.stringify({ ...d, ok: !hasBlockingDrift(d) }, null, 2) + "\n");
	} else {
		const lines = driftLines(d).filter((l) => !l.startsWith("link check unverifiable"));
		if (lines.length) process.stderr.write(lines.map((l) => `• ${l}`).join("\n") + "\n");
	}
	process.exit(hasBlockingDrift(d) ? 1 : 0); // verdict in the exit code (C-027)
}

function cmdStatus(root, args) {
	const cs = clauses(root);
	const cClauses = cs.filter((c) => c.kind === "C");
	const verified = cClauses.filter((c) => c.verified).length;
	const manualOnly = cClauses.filter((c) => c.links.manual && c.links.automated.length === 0).length;
	const pDeltas = cs.filter((c) => c.kind === "P").length;
	const d = collectDrift(root);
	if (args.includes("--json")) {
		process.stdout.write(JSON.stringify({ verified, total: cClauses.length, manualOnly, pendingDeltas: pDeltas, drift: driftLines(d) }, null, 2) + "\n");
		return;
	}
	process.stdout.write(`${verified}/${cClauses.length} C-clauses verified · ${manualOnly} manual-only · ${pDeltas} pending deltas\n`);
	const lines = driftLines(d);
	process.stdout.write(lines.length ? lines.map((l) => `• ${l}`).join("\n") + "\n" : "no structural drift\n");
}

// ── VERIFY (the one write this increment) ─────────────────────────────────────────────────────────
// Enforces the SAME invariant the gate does before writing `verified`: an automated link must RESOLVE
// (git grep) and its recorded run must be FRESH (C-024/C-026). It never types the word blind. Manual /
// not_required clauses carry no automated link, so the gate exempts them from run-evidence pressure;
// `zen verify` marks them verified directly (with a note that nothing automated backs them).
function cmdVerify(root, args) {
	const id = (args.find((a) => /^[CP]-\d+$/i.test(a)) || "").toUpperCase();
	if (!id) die("usage: zen verify <C-xxx>");
	const c = findClause(root, id);
	if (!c) die(`unknown clause ${id}`);

	if (c.links.automated.length) {
		const { broken, verifiable } = brokenLinks(root);
		if (!verifiable) die(`${id}: cannot verify — link check is unverifiable (not a git repo). Run \`git init\`.`);
		const stillBroken = c.links.automated.filter((n) => broken.includes(n));
		if (stillBroken.length) die(`${id}: link does not resolve — ${stillBroken.join(", ")} not found in the repo. Write the test or fix the link first.`);
		const ev = evidenceStatus(root, id);
		if (ev.state !== "fresh") {
			const why = ev.state === "missing" ? "no recorded run" : `recorded run ${ev.state}${ev.detail ? ` (${ev.detail})` : ""}`;
			die(`${id}: ${why}. Record a real run before claiming verified (cheaper than faking it):\n      node <zen>/hooks/zen-record-run.js --clause ${id} -- <your test command>`);
		}
		// A green run is not proof on its own (C-041): the disinterested critic must have cleared it too,
		// or the Stop-gate would block this clause the moment it stands `verified`. Enforce the SAME
		// requirement here so the CLI cannot be a happy-path that stamps `verified` with the refute
		// skipped (the exact reward-hack C-041 closes). The verdict is the critic's; that it ran is gated.
		const rf = refuteStatus(root, id);
		if (rf.state !== "fresh") {
			const why = rf.state === "missing" ? "no refuter pass recorded"
				: rf.state === "refuted" ? "the refuter found a gap (refuted) — strengthen the test first"
				: `refute-evidence ${rf.state}${rf.detail ? ` (${rf.detail})` : ""}`;
			die(`${id}: ${why}. Spawn the zen-refuter on this clause + its diff, then record the verdict:\n      use the zen-refuter subagent to refute ${id} against this diff\n      node <zen>/hooks/zen-record-refute.js --clause ${id} --verdict holds|trivial|refuted`);
		}
	} else if (!c.links.manual && !c.links.notRequired) {
		die(`${id}: no verification link. Add \`automated → <test>\`, \`manual: <how>\`, or \`not_required: <why>\` first (zen-contract).`);
	}

	writeStatus(root, c, "verified");
	const how = c.links.automated.length ? "link resolves + run fresh + critic cleared" : verKind(c);
	process.stdout.write(`zen: ${id} → verified (${how})\n`);
}

// Set a clause's Status FIELD line in place (the only mutation this increment makes). Re-parses for a
// fresh line span, replaces the last `**Status**` field line, preserving the `- ` bullet convention.
function writeStatus(root, clause, value) {
	const lines = readContract(root).split("\n");
	const fresh = parseContract(lines.join("\n")).find((c) => c.id === clause.id);
	if (!fresh) die(`clause ${clause.id} vanished before write`);
	let idx = -1;
	for (let i = fresh.lineStart; i < fresh.lineEnd; i++) { if (/\*\*Status\b/i.test(lines[i])) idx = i; }
	const newLine = `- **Status:** ${value}`;
	if (idx >= 0) lines[idx] = newLine;
	else lines.splice(fresh.lineEnd, 0, newLine); // no Status field yet → append at the clause's end
	fs.writeFileSync(contractPath(root), lines.join("\n"));
}

// ── WRITE OPS (C-033 phase 2) ─────────────────────────────────────────────────────────────────
// All contract mutation flows through these few primitives — one read-modify-write each, atomic, and
// re-parsed afterward — so the file the gate reads can never be left half-edited. The prose-edit path
// (a human or model editing Description by hand) stays a normal file edit; both meet the same gate.

function writeContract(root, lines) { fs.writeFileSync(contractPath(root), lines.join("\n")); }
function today() { return new Date().toISOString().slice(0, 10); }
function locate(root, id) {
	const lines = readContract(root).split("\n");
	const c = parseContract(lines.join("\n")).find((x) => x.id === id);
	return { lines, c };
}
function nextIdFor(root, kind) {
	const nums = clauses(root).filter((c) => c.kind === kind).map((c) => parseInt(c.id.split("-")[1], 10)).filter((n) => !isNaN(n));
	return `${kind}-${String((nums.length ? Math.max(...nums) : 0) + 1).padStart(3, "0")}`;
}
// Where to splice a NEW field line in a clause: just before its Status line if it has one, else just
// before the clause's trailing blank line(s). Keeps Verification/Evidence above Status, as in the format.
function fieldInsertIdx(lines, c) {
	for (let i = c.lineStart; i < c.lineEnd; i++) if (/\*\*Status\b/i.test(lines[i])) return i;
	let e = c.lineEnd;
	while (e > c.lineStart + 1 && lines[e - 1] === "") e--;
	return e;
}
function pendingIdx(lines) { return lines.findIndex((l) => /^##\s+Pending Contract Deltas/i.test(l)); }
// Insert a fully-formed clause block (ending with one "") into the C body — before the Pending section,
// or at end of file if there is none.
function insertCBody(lines, block) {
	const pi = pendingIdx(lines);
	if (pi >= 0) lines.splice(pi, 0, ...block);
	else { if (lines.length && lines[lines.length - 1] !== "") lines.push(""); lines.push(...block); }
}
// Insert a P-delta block under the Pending Contract Deltas heading (creating the section if absent).
function insertPending(lines, block) {
	let pi = pendingIdx(lines);
	if (pi < 0) { if (lines.length && lines[lines.length - 1] !== "") lines.push(""); lines.push("## Pending Contract Deltas", ""); pi = lines.length - 2; }
	let ins = pi + 1;
	if (lines[ins] === "") ins++;
	lines.splice(ins, 0, ...block);
}
// Description prose for add-clause: explicit --description, else piped stdin, else $EDITOR.
function resolveDescription(descFlag) {
	if (descFlag) return descFlag;
	if (!process.stdin.isTTY) { try { const s = fs.readFileSync(0, "utf8").trim(); if (s) return s; } catch { /* none */ } }
	const editor = process.env.VISUAL || process.env.EDITOR;
	if (editor) {
		const os = require("node:os"); const cp = require("node:child_process");
		const tmp = path.join(os.tmpdir(), `zen-clause-${process.pid}.md`);
		try {
			fs.writeFileSync(tmp, ""); cp.execFileSync(editor, [tmp], { stdio: "inherit" });
			const s = fs.readFileSync(tmp, "utf8").trim(); fs.unlinkSync(tmp); return s || null;
		} catch { try { fs.unlinkSync(tmp); } catch { /* ignore */ } return null; }
	}
	return null;
}

function cmdAddClause(root, args) {
	const kind = (args.find((a) => /^[CP]$/i.test(a)) || "C").toUpperCase();
	const [title, a1] = takeFlag(args, "--title");
	const [source, a2] = takeFlag(a1, "--source");
	const [verification, a3] = takeFlag(a2, "--verification");
	const [date, a4] = takeFlag(a3, "--date");
	const [descFlag] = takeFlag(a4, "--description");
	const desc = resolveDescription(descFlag);
	if (!desc) die("add-clause: need a Description — pass --description, pipe it on stdin, or set $EDITOR");
	const id = nextIdFor(root, kind);
	const d = date || today();
	const src = source || "discovery";
	const lines = readContract(root).split("\n");
	let block;
	if (kind === "P") {
		block = [`### ${id}: ${title || "untitled"}`, `- **Date:** ${d}`, `- **Source:** ${src}`, `- **Description:** ${desc}`, `- **Proposed verification:** ${verification || "TBD"}`, ""];
		insertPending(lines, block);
	} else {
		block = [`## ${id}: ${title || "untitled"}`, `- **Date:** ${d}`, `- **Source:** ${src}`, `- **Description:** ${desc}`, `- **Verification:** ${verification || "pending — link a test with `zen link`"}`, "- **Status:** pending verification", ""];
		insertCBody(lines, block);
	}
	writeContract(root, lines);
	if (!findClause(root, id)) die(`add-clause: wrote ${id} but it did not parse back — inspect the contract`);
	process.stdout.write(`${id}\n`);
}

function cmdLink(root, args) {
	const [test, a1] = takeFlag(args, "--test");
	const id = (a1.find((a) => /^[CP]-\d+$/i.test(a)) || "").toUpperCase();
	if (!id || !test) die("usage: zen link <C-xxx> --test <name>");
	const { lines, c } = locate(root, id);
	if (!c) die(`unknown clause ${id}`);
	if (c.links.automated.includes(test)) { process.stdout.write(`${id}: already links ${test}\n`); return; }
	const names = c.links.automated.concat(test);
	let vi = -1;
	for (let i = c.lineStart; i < c.lineEnd; i++) if (/\*\*Verification\b/i.test(lines[i])) { vi = i; break; }
	if (vi >= 0) {
		const after = lines[vi].replace(/^.*\*\*Verification:?\*\*\s*/i, "");
		// Preserve REAL verification prose only: an automated line's text after the first `|`, or a
		// manual:/not_required: value kept whole. A placeholder (`pending — link a test …`) carries no
		// verification kind, so it is dropped rather than smeared after the new link as stray prose.
		const hadAuto = /automated\s*(?:→|->)/i.test(after);
		const hadReal = hadAuto || /\bmanual:/i.test(after) || /\bnot_required:/i.test(after);
		const prose = hadAuto ? after.split("|").slice(1).join("|").trim() : (hadReal ? after.trim() : "");
		lines[vi] = `- **Verification:** automated → ${names.join(", ")}${prose ? `  |  ${prose}` : ""}`;
	} else {
		lines.splice(fieldInsertIdx(lines, c), 0, `- **Verification:** automated → ${names.join(", ")}`);
	}
	writeContract(root, lines);
	process.stdout.write(`${id}: linked ${test}\n`);
}

function cmdEvidence(root, args) {
	const id = (args.find((a) => /^[CP]-\d+$/i.test(a)) || "").toUpperCase();
	if (!id) die("usage: zen evidence <C-xxx>");
	const { lines, c } = locate(root, id);
	if (!c) die(`unknown clause ${id}`);
	const evRel = `.zen/evidence/${id}.md`;
	const evAbs = path.join(root, evRel);
	if (!fs.existsSync(evAbs)) {
		fs.mkdirSync(path.dirname(evAbs), { recursive: true });
		fs.writeFileSync(evAbs, `# ${id} — ${c.title} — lab notebook\n\nThe clause states intent; this file holds the research/spike log, sweeps, and design notes that would otherwise bloat the clause (clause altitude, C-012).\n`);
	}
	if (c.evidence) { process.stdout.write(`${id}: already has an Evidence link (${c.evidence})\n`); return; }
	lines.splice(fieldInsertIdx(lines, c), 0, `- **Evidence:** ${evRel}`);
	writeContract(root, lines);
	process.stdout.write(`${id}: evidence → ${evRel}\n`);
}

function cmdSetSource(root, args) {
	const [to, a1] = takeFlag(args, "--to");
	const id = (a1.find((a) => /^[CP]-\d+$/i.test(a)) || "").toUpperCase();
	if (!id || !to) die("usage: zen set-source <C-xxx> --to <source>");
	const { lines, c } = locate(root, id);
	if (!c) die(`unknown clause ${id}`);
	let si = -1;
	for (let i = c.lineStart; i < c.lineEnd; i++) if (/\*\*Source\b/i.test(lines[i])) { si = i; break; }
	if (si >= 0) lines[si] = `- **Source:** ${to}`;
	else {
		let at = c.lineStart + 1;
		for (let i = c.lineStart; i < c.lineEnd; i++) if (/\*\*Date\b/i.test(lines[i])) { at = i + 1; break; }
		lines.splice(at, 0, `- **Source:** ${to}`);
	}
	writeContract(root, lines);
	process.stdout.write(`${id}: source → ${to}\n`);
}

// ── "DELETE" = status transitions that COMPACT the live contract (never physical rm — C-023) ──────
// A retired clause LEAVES contract.md for .zen/archive/contract.md (append-only, versioned — it IS the
// trace), so the monotonically-growing contract can finally shrink while nothing is lost.
function moveToArchive(root, id, reason) {
	const { lines, c } = locate(root, id);
	if (!c) die(`unknown clause ${id}`);
	const block = lines.slice(c.lineStart, c.lineEnd);
	while (block.length && block[block.length - 1] === "") block.pop();
	lines.splice(c.lineStart, c.lineEnd - c.lineStart);
	writeContract(root, lines);
	const archPath = path.join(root, ".zen", "archive", "contract.md");
	fs.mkdirSync(path.dirname(archPath), { recursive: true });
	if (!fs.existsSync(archPath)) fs.writeFileSync(archPath, "# Archived Contract Items\n\nRetired clauses, preserved — never deleted (the audit trace, C-023). Each carries the date it left the live contract.\n");
	fs.appendFileSync(archPath, `\n<!-- archived ${today()}${reason ? `: ${reason}` : ""} -->\n` + block.join("\n") + "\n");
}

function cmdArchive(root, args) {
	const id = (args.find((a) => /^[CP]-\d+$/i.test(a)) || "").toUpperCase();
	if (!id) die("usage: zen archive <C-xxx>");
	moveToArchive(root, id, "");
	process.stdout.write(`${id}: archived → .zen/archive/contract.md\n`);
}
function cmdSupersede(root, args) {
	const [by, a1] = takeFlag(args, "--by");
	const id = (a1.find((a) => /^[CP]-\d+$/i.test(a)) || "").toUpperCase();
	if (!id || !by) die("usage: zen supersede <C-xxx> --by <C-yyy>");
	const byId = by.toUpperCase();
	if (!findClause(root, byId)) die(`supersede: target ${byId} not found in the live contract`);
	if (!findClause(root, id)) die(`unknown clause ${id}`);
	moveToArchive(root, id, `superseded by ${byId}`);
	process.stdout.write(`${id}: superseded by ${byId} → archived\n`);
}
function cmdShelve(root, args) {
	const id = (args.find((a) => /^[CP]-\d+$/i.test(a)) || "").toUpperCase();
	if (!id) die("usage: zen shelve <id>");
	if (!findClause(root, id)) die(`unknown clause ${id}`);
	moveToArchive(root, id, "shelved");
	process.stdout.write(`${id}: shelved → archived\n`);
}

function cmdPromote(root, args) {
	const ids = args.filter((a) => /^[CP]-\d+$/i.test(a)).map((s) => s.toUpperCase());
	const pid = ids.find((x) => x.startsWith("P-"));
	if (!pid) die("usage: zen promote <P-xxx> [C-yyy]");
	const explicitC = ids.find((x) => x.startsWith("C-"));
	const { lines, c } = locate(root, pid);
	if (!c || c.kind !== "P") die(`${pid} is not a pending delta`);
	if (explicitC && findClause(root, explicitC)) die(`promote: ${explicitC} already exists`);
	const targetId = explicitC || nextIdFor(root, "C");
	const block = lines.slice(c.lineStart, c.lineEnd);
	while (block.length && block[block.length - 1] === "") block.pop();
	const newBlock = block.map((l) => {
		if (/^#{2,3}\s+P-\d+:/.test(l)) return l.replace(/^#{2,3}\s+P-\d+:/, `## ${targetId}:`);
		if (/\*\*Proposed verification:?\*\*/i.test(l)) return l.replace(/\*\*Proposed verification:?\*\*/i, "**Verification:**");
		return l;
	});
	if (!newBlock.some((l) => /\*\*Status\b/i.test(l))) newBlock.push("- **Status:** pending verification");
	newBlock.push("");
	lines.splice(c.lineStart, c.lineEnd - c.lineStart); // remove the P delta
	insertCBody(lines, newBlock);                        // insert the new C clause into the C body
	writeContract(root, lines);
	if (!findClause(root, targetId)) die(`promote: wrote ${targetId} but it did not parse back`);
	process.stdout.write(`${pid} → ${targetId} (promoted)\n`);
}

// ── HELP ──────────────────────────────────────────────────────────────────────────────────────
const HELP = `zen — deterministic operations over a IMPLICATION→MACHINE-governed contract (.zen/contract.md)

USAGE
  zen [--root <dir>] <command> [args]

READ
  list [--status S] [--kind C|P] [--json]   list clauses (filter by status substring / kind)
  show <C-xxx> [--json]                      print one clause (raw markdown, or json)
  grep <term> [--json]                       clauses whose body matches <term>
  links <C-xxx> [--json]                     each automated link: resolves? (git grep) · run fresh?
  next-id [C|P]                              next free clause id
  drift [--json]                             report drift (always exit 0) — the gate's deterministic facts
  status [--json]                            summary: verified/total, manual-only, pending deltas, drift

VALIDATE
  lint                                       same checks as the gate; verdict in the exit code (≠0 on drift)

UPDATE
  verify <C-xxx>                             checks the link resolves AND its run is fresh, THEN writes
                                             Status: verified — never the word blind (C-024/C-026)

WRITE
  add-clause [C|P] [--title T] [--source S] [--verification V] [--date D] [--description X]
                                             add a clause (next free id); Description from --description,
                                             piped stdin, or $EDITOR. C → before Pending; P → under it
  link <C-xxx> --test <name>                 add/append an automated → <name> verification link
  evidence <C-xxx>                           create .zen/evidence/<id>.md and add its Evidence link
  set-source <C-xxx> --to <source>           set the Source field

TRANSITION (compaction — move out of the live contract, never delete; C-023)
  archive <C-xxx>                            move the clause to .zen/archive/contract.md
  supersede <C-xxx> --by <C-yyy>             archive <C-xxx>, recording it was replaced by <C-yyy>
  shelve <id>                                archive a parked P-delta / retire a clause
  promote <P-xxx> [C-yyy]                    graduate a pending delta into a C-clause (next free id or C-yyy)

Errors exit non-zero. Verification is exact git grep — never anything fuzzy. The Stop-gate remains the
independent enforcer at turn end; this CLI shares its calculation so the honest path is the cheap one.`;

function main() {
	let argv = process.argv.slice(2);
	const [rootArg, rest] = takeFlag(argv, "--root");
	argv = rest;

	if (!argv.length || argv[0] === "--help" || argv[0] === "-h" || argv[0] === "help") {
		process.stdout.write(HELP + "\n");
		process.exit(0);
	}
	const cmd = argv[0];
	const args = argv.slice(1);

	const root = rootArg || findGovernedRoot(process.cwd());
	if (!root || !fs.existsSync(contractPath(root))) {
		die("not inside a IMPLICATION→MACHINE-governed project (no .zen/contract.md at or above cwd). Run /zen-init to adopt IMPLICATION→MACHINE.");
	}

	switch (cmd) {
		case "list": return cmdList(root, args);
		case "show": return cmdShow(root, args);
		case "grep": return cmdGrep(root, args);
		case "links": return cmdLinks(root, args);
		case "next-id": return cmdNextId(root, args);
		case "drift": return cmdDrift(root, args);
		case "status": return cmdStatus(root, args);
		case "lint": return cmdLint(root, args);
		case "verify": return cmdVerify(root, args);
		case "add-clause": return cmdAddClause(root, args);
		case "link": return cmdLink(root, args);
		case "evidence": return cmdEvidence(root, args);
		case "set-source": return cmdSetSource(root, args);
		case "archive": return cmdArchive(root, args);
		case "supersede": return cmdSupersede(root, args);
		case "shelve": return cmdShelve(root, args);
		case "promote": return cmdPromote(root, args);
		default: die(`unknown command '${cmd}'. Run \`zen --help\`.`);
	}
}

try { main(); } catch (e) { die(String((e && e.message) || e)); }
