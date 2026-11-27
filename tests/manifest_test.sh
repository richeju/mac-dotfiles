#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
    echo "[FAIL] $1" >&2
    exit 1
}

manifest="$REPO_ROOT/dot_Brewfile"
[[ -f "$manifest" ]] || fail "managed Brewfile is missing"
[[ ! -e "$REPO_ROOT/Brewfile" && ! -e "$manifest.tmpl" ]] || fail "there must be one managed Brewfile"
duplicates="$(awk -F'"' '/^(brew|cask) "/ { print $1 $2 } /^mas "/ { sub(/^.*id:[[:space:]]*/, ""); sub(/[^0-9].*$/, ""); print "mas " $0 }' "$manifest" | sort | uniq -d)"
[[ -z "$duplicates" ]] || fail "duplicate packages: $duplicates"
grep -Fq 'brew "age"' "$manifest" || fail "recovery-kit encryption must be installed"
grep -Fq 'brew "node@24"' "$manifest" || fail "Node LTS must be pinned"
grep -Fq 'cask "balenaetcher"' "$manifest" || fail "the bootable USB writer must be installed"
grep -Fq 'cask "zerotier-one"' "$manifest" || fail "the mesh VPN client must be installed"
grep -Fq '/opt/homebrew/opt/node@24/bin' "$REPO_ROOT/dot_zprofile" || fail "Node LTS must be added to PATH"
grep -Fq '/opt/homebrew/bin' "$REPO_ROOT/Library/LaunchAgents/com.chezmoi.mac-dotfiles.maintenance.plist.tmpl" || fail "LaunchAgent must include Homebrew in PATH"
grep -Fq 'cced90146ea6d3057c03a636b668fef177415eb3' "$REPO_ROOT/install.sh" ||
    fail "Homebrew installer must be pinned to a commit"
grep -Fq '12479a24be3f5307eecac7cde670fad7118640f031229e964f544b1367b52a41' "$REPO_ROOT/install.sh" ||
    fail "Homebrew installer checksum must be pinned"
! grep -Fq 'Homebrew/install/HEAD/install.sh' "$REPO_ROOT/install.sh" || fail "Homebrew installer must not use mutable HEAD"

echo "[PASS] manifest tests completed"
