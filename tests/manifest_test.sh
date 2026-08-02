#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
    echo "[FAIL] $1" >&2
    exit 1
}

[[ ! -e "$REPO_ROOT/Brewfile" ]] || fail "the managed template must be the only Brewfile source"
[[ -f "$REPO_ROOT/dot_Brewfile.tmpl" ]] || fail "managed Brewfile template is missing"
grep -Fq 'brew "node@24"' "$REPO_ROOT/profiles/power.Brewfile" || fail "Node LTS must be pinned"
grep -Fq 'cask "balenaetcher"' "$REPO_ROOT/profiles/personal.Brewfile" || fail "personal profile must include the bootable USB writer"
grep -Fq '/opt/homebrew/opt/node@24/bin' "$REPO_ROOT/dot_zprofile" || fail "Node LTS must be added to PATH"
grep -Fq '/opt/homebrew/bin' "$REPO_ROOT/dot_Library/LaunchAgents/com.chezmoi.mac-dotfiles.maintenance.plist.tmpl" || fail "LaunchAgent must include Homebrew in PATH"

echo "[PASS] manifest tests completed"
