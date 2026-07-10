#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
    echo "[FAIL] $1" >&2
    exit 1
}

[[ ! -e "$REPO_ROOT/Brewfile" ]] || fail "dot_Brewfile must be the only Brewfile source"
grep -Fq 'brew "node@24"' "$REPO_ROOT/dot_Brewfile" || fail "Node LTS must be pinned"
grep -Fq '/opt/homebrew/opt/node@24/bin' "$REPO_ROOT/dot_zprofile" || fail "Node LTS must be added to PATH"
grep -Fq '/opt/homebrew/bin' "$REPO_ROOT/dot_Library/LaunchAgents/com.chezmoi.mac-dotfiles.maintenance.plist.tmpl" || fail "LaunchAgent must include Homebrew in PATH"

echo "[PASS] manifest tests completed"
