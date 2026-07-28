#!/usr/bin/env bash
set -euo pipefail

if [[ "${MAC_DOTFILES_CERTIFY_CHILD:-0}" == "1" ]]; then
    echo "[PASS] nested certification test skipped"
    exit 0
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CERTIFIER="$REPO_ROOT/dot_local/bin/executable_mac-dotfiles-certify.sh.tmpl"
output="$(mktemp)"
state_dir="$(mktemp -d)"
trap 'rm -f "$output"; rm -rf "$state_dir"' EXIT

(
    cd "$state_dir"
    CHEZMOI_SOURCE_DIR="$REPO_ROOT" MAC_DOTFILES_STATE_DIR="$state_dir" MAC_DOTFILES_LOCK_HELD=1 \
        bash "$CERTIFIER" --json --skip-live --output "$output" >/dev/null
)
jq -e '.schema_version == 1 and .kind == "mac-dotfiles-certification" and .overall == "pass"' "$output" >/dev/null
jq -e '[.checks[] | select(.status == "fail")] | length == 0' "$output" >/dev/null
jq -e '.checks[] | select(.name == "compliance-catalog" and .status == "pass")' "$output" >/dev/null
cmp -s "$output" "$state_dir/certifications/latest.json"

echo "[PASS] certification tests completed"
