#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SAFE_UPDATE_SCRIPT="$REPO_ROOT/dot_local/bin/executable_mac-dotfiles-safe-update.sh.tmpl"

fail() {
  echo "[FAIL] $1" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local message="$3"
  [[ "$haystack" == *"$needle"* ]] || fail "$message (missing: $needle)"
}

setup_env() {
  local env_dir
  env_dir="$(mktemp -d)"
  mkdir -p \
    "$env_dir/bin" \
    "$env_dir/home/.local/bin" \
    "$env_dir/home/Library/LaunchAgents"

  echo "[user]" > "$env_dir/home/.gitconfig"
  echo 'brew "gh"' > "$env_dir/home/.Brewfile"
  echo "zprofile" > "$env_dir/home/.zprofile"
  echo "plist" > "$env_dir/home/Library/LaunchAgents/com.chezmoi.mac-dotfiles.maintenance.plist"

  cat > "$env_dir/home/.local/bin/mac-dotfiles-report.sh" <<'REPORT'
#!/usr/bin/env bash
echo "# report"
REPORT
  chmod +x "$env_dir/home/.local/bin/mac-dotfiles-report.sh"

  echo "$env_dir"
}

write_mocks() {
  local env_dir="$1"

  cat > "$env_dir/bin/chezmoi" <<CHEZ
#!/usr/bin/env bash
if [[ "\$1" == "diff" ]]; then
  echo "diff-output"
elif [[ "\$1" == "update" && "\$2" == "--apply" ]]; then
  echo "update-called" >> "$env_dir/chezmoi.log"
  exit 0
fi
CHEZ

  chmod +x "$env_dir/bin/chezmoi"
}

test_safe_update_happy_path() {
  local env_dir output run_dir
  env_dir="$(setup_env)"
  write_mocks "$env_dir"

  output="$(HOME="$env_dir/home" PATH="$env_dir/bin:/usr/bin:/bin:/usr/sbin:/sbin" bash "$SAFE_UPDATE_SCRIPT")"
  run_dir="$(echo "$output" | awk -F': ' '/Run directory/ {print $2}')"

  assert_contains "$output" "Safe update completed" "safe update should complete"
  [[ -f "$env_dir/chezmoi.log" ]] || fail "chezmoi update --apply was not called"
  [[ -f "$run_dir/report-before.md" ]] || fail "before report missing"
  [[ -f "$run_dir/report-after.md" ]] || fail "after report missing"
  [[ -f "$run_dir/chezmoi.diff" ]] || fail "chezmoi diff missing"
  assert_contains "$(cat "$run_dir/chezmoi.diff")" "diff-output" "diff output should be saved"
  [[ -f "$run_dir/backups/.gitconfig" ]] || fail "gitconfig backup missing"
  [[ -f "$run_dir/backups/.Brewfile" ]] || fail "Brewfile backup missing"
}

main() {
  test_safe_update_happy_path
  echo "[PASS] safe update tests completed"
}

main
