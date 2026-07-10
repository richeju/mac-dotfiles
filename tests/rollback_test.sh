#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROLLBACK_SCRIPT="$REPO_ROOT/dot_local/bin/executable_mac-dotfiles-rollback.sh.tmpl"

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
  local env_dir="$1"
  local run_id="$2"
  local value="$3"
  local backup_dir="$env_dir/home/.local/state/mac-dotfiles/safe-updates/$run_id/backups"

  mkdir -p "$backup_dir" "$env_dir/home/Library/LaunchAgents" "$env_dir/bin"
  echo "$value-gitconfig" > "$backup_dir/.gitconfig"
  echo "$value-brewfile" > "$backup_dir/.Brewfile"
  echo "$value-zprofile" > "$backup_dir/.zprofile"
  echo "$value-plist" > "$backup_dir/Library__LaunchAgents__com.chezmoi.mac-dotfiles.maintenance.plist"
}

write_current_files() {
  local env_dir="$1"
  echo "current-gitconfig" > "$env_dir/home/.gitconfig"
  echo "current-brewfile" > "$env_dir/home/.Brewfile"
  echo "current-zprofile" > "$env_dir/home/.zprofile"
  echo "current-plist" > "$env_dir/home/Library/LaunchAgents/com.chezmoi.mac-dotfiles.maintenance.plist"
}

write_chezmoi_mock() {
  local env_dir="$1"
  cat > "$env_dir/bin/chezmoi" <<'CHEZMOI'
#!/usr/bin/env bash
if [[ "$1" == "diff" ]]; then
  echo "mock-chezmoi-diff"
fi
CHEZMOI
  chmod +x "$env_dir/bin/chezmoi"
}

run_rollback() {
  local env_dir="$1"
  shift
  HOME="$env_dir/home" PATH="$env_dir/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "$ROLLBACK_SCRIPT" "$@"
}

test_dry_run_uses_latest_without_changes() {
  local env_dir output
  env_dir="$(mktemp -d)"
  setup_env "$env_dir" "20260101-120000" "older"
  setup_env "$env_dir" "20260102-120000" "newer"
  write_current_files "$env_dir"
  write_chezmoi_mock "$env_dir"

  output="$(run_rollback "$env_dir" latest --dry-run)"

  assert_contains "$output" "Safe-update run: 20260102-120000" "dry run should select the latest backup"
  assert_contains "$output" "Dry run complete; no files changed" "dry run should report no changes"
  assert_contains "$(cat "$env_dir/home/.gitconfig")" "current-gitconfig" "dry run must not replace current files"
  [[ ! -d "$env_dir/home/.local/state/mac-dotfiles/rollback-backups" ]] || fail "dry run must not create rollback backups"
}

test_restore_specific_run_and_preserve_current_files() {
  local env_dir output rollback_backup
  env_dir="$(mktemp -d)"
  setup_env "$env_dir" "20260101-120000" "selected"
  write_current_files "$env_dir"
  write_chezmoi_mock "$env_dir"

  output="$(run_rollback "$env_dir" "20260101-120000" --yes)"

  assert_contains "$output" "Rollback completed" "rollback should complete"
  assert_contains "$output" "mock-chezmoi-diff" "rollback should show the resulting chezmoi diff"
  assert_contains "$(cat "$env_dir/home/.gitconfig")" "selected-gitconfig" "rollback should restore the selected gitconfig"
  assert_contains "$(cat "$env_dir/home/.Brewfile")" "selected-brewfile" "rollback should restore the selected Brewfile"

  rollback_backup="$(find "$env_dir/home/.local/state/mac-dotfiles/rollback-backups" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
  [[ -n "$rollback_backup" ]] || fail "rollback should preserve current files"
  assert_contains "$(cat "$rollback_backup/.gitconfig")" "current-gitconfig" "rollback backup should contain the previous gitconfig"
}

main() {
  test_dry_run_uses_latest_without_changes
  test_restore_specific_run_and_preserve_current_files
  echo "[PASS] rollback tests completed"
}

main
