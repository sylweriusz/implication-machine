#!/usr/bin/env bash
# Install the IMPLICATION→MACHINE plugin into Claude Code from this directory.
#
# This directory is a self-contained Claude Code plugin AND a single-plugin marketplace
# (.claude-plugin/marketplace.json). The installer registers it as a local marketplace and
# installs the plugin via the `claude` CLI. Re-runnable.
#
# Usage:  ./install.sh [--scope user|project|local]    (default scope: user)
#         ./install.sh --shim-only [DIR]               (just (re)create the `zen` PATH shim)
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"   # this plugin/marketplace directory

# Put a `zen` shim on PATH pointing at the bundled CLI, so the skills' `zen <cmd>` resolves to a single
# word (they fall back to reading .zen/contract.md directly if it is absent). Non-fatal: with no writable
# PATH dir it prints a hint and returns 0. $1 (optional) forces a target dir (used by the test).
install_zen_shim() {
  local target="$DIR/bin/zen.js" forced="${1:-}" d brewbin=""
  if [ ! -f "$target" ]; then echo "NOTE: no bin/zen.js beside the installer — skipping the zen shim."; return 0; fi
  # Resolve Homebrew's bin dynamically (Apple Silicon vs Intel differ) rather than hardcoding a host
  # path — the distributable must carry none (the build's portability guard enforces this).
  command -v brew >/dev/null 2>&1 && brewbin="$(brew --prefix 2>/dev/null)/bin"
  for d in ${forced:+"$forced"} "$HOME/.local/bin" "/usr/local/bin" ${brewbin:+"$brewbin"}; do
    [ -n "$forced" ] || case ":$PATH:" in *":$d:"*) ;; *) continue ;; esac
    [ -d "$d" ] && [ -w "$d" ] || continue
    if ln -sf "$target" "$d/zen" 2>/dev/null; then chmod +x "$target" 2>/dev/null || true; echo "→ zen CLI shim → $d/zen"; return 0; fi
  done
  echo "NOTE: no writable PATH dir found for a 'zen' shim. To enable the CLI yourself:"
  echo "    ln -sf \"$target\" ~/.local/bin/zen     # (ensure ~/.local/bin is on your PATH)"
  return 0
}

# --shim-only: (re)create the shim and exit — no `claude` CLI required, so this path is testable.
if [ "${1:-}" = "--shim-only" ]; then install_zen_shim "${2:-}"; exit 0; fi

SCOPE="user"
[ "${1:-}" = "--scope" ] && [ -n "${2:-}" ] && SCOPE="$2"

if ! command -v claude >/dev/null 2>&1; then
  echo "The Claude Code CLI ('claude') was not found on your PATH."
  echo "Install Claude Code first, then either re-run this script or, inside Claude Code, run:"
  echo "  /plugin marketplace add \"$DIR\""
  echo "  /plugin install implication-machine@implication-machine-marketplace"
  exit 1
fi

echo "→ Registering marketplace (scope: $SCOPE) from:"
echo "    $DIR"
if claude plugin marketplace list 2>/dev/null | grep -q 'implication-machine-marketplace'; then
  echo "  marketplace 'implication-machine-marketplace' already registered — updating."
  claude plugin marketplace update implication-machine-marketplace || true
else
  claude plugin marketplace add "$DIR" --scope "$SCOPE"
fi

echo "→ Installing implication-machine@implication-machine-marketplace (scope: $SCOPE) ..."
claude plugin install implication-machine@implication-machine-marketplace --scope "$SCOPE"

install_zen_shim

echo
echo "✓ Installed. Restart Claude Code (or start a new session) so the Stop + SessionStart hooks load."
echo "  Verify with:  claude plugin list"
echo
echo "NOTE: if you already run IMPLICATION→MACHINE from a dogfood config (an @zen.md include + its hooks already in"
echo "your settings.json), do NOT also install this plugin — the gate and protocol would fire twice."
