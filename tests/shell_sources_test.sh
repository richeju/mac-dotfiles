#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/shell_sources.sh
source "$REPO_ROOT/tests/lib/shell_sources.sh"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

# Plain scripts must retain their contents, including the final newline.
prepare_shell_source "$REPO_ROOT/tests/lib/shell_sources.sh" >"$work_dir/plain.sh"
cmp "$REPO_ROOT/tests/lib/shell_sources.sh" "$work_dir/plain.sh"

# Validate a real template containing standalone and inline expressions.
prepare_shell_source "$REPO_ROOT/dot_local/bin/executable_mac-dotfiles-configure-dock.sh.tmpl" >"$work_dir/rendered.sh"
if grep -Fq '{{' "$work_dir/rendered.sh"; then
    echo "[FAIL] template expressions remain in prepared shell source" >&2
    exit 1
fi
bash -n "$work_dir/rendered.sh"
echo "[PASS] shell source preparation tests completed"
