#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_SCRIPT="$REPO_ROOT/install.sh"

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

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local message="$3"
  [[ "$haystack" != *"$needle"* ]] || fail "$message (unexpected: $needle)"
}

assert_exit_code() {
  local actual="$1"
  local expected="$2"
  local message="$3"
  [[ "$actual" -eq "$expected" ]] || fail "$message (expected $expected got $actual)"
}

setup_env() {
  local env_dir
  env_dir="$(mktemp -d)"
  mkdir -p \
    "$env_dir/bin" \
    "$env_dir/home/.local/share/chezmoi" \
    "$env_dir/home/.local/bin" \
    "$env_dir/home/Library/LaunchAgents"
  touch "$env_dir/home/.Brewfile"
  touch "$env_dir/home/Library/LaunchAgents/com.chezmoi.mac-dotfiles.maintenance.plist"
  cat > "$env_dir/home/.local/bin/mac-dotfiles-maintenance.sh" <<'SCRIPT'
#!/usr/bin/env bash
exit 0
SCRIPT
  chmod +x "$env_dir/home/.local/bin/mac-dotfiles-maintenance.sh"
  echo "$env_dir"
}

write_common_mocks() {
  local env_dir="$1"

  cat > "$env_dir/bin/curl" <<'CURL'
#!/usr/bin/env bash
exit 0
CURL

  cat > "$env_dir/bin/git" <<'GIT'
#!/usr/bin/env bash
exit 0
GIT

  cat > "$env_dir/bin/brew" <<'BREW'
#!/usr/bin/env bash
case "$1" in
  --prefix)
    echo "/opt/homebrew"
    ;;
  list)
    [[ "${2:-}" == "chezmoi" ]]
    ;;
  bundle)
    [[ "${2:-}" == "check" ]]
    ;;
esac
exit 0
BREW

  cat > "$env_dir/bin/chezmoi" <<'CHEZ'
#!/usr/bin/env bash
case "$1" in
  --version)
    echo "chezmoi version v2.70.5"
    ;;
  diff)
    ;;
  update)
    if [[ "${2:-}" == "--apply" && "${3:-}" == "--force" && "${4:-}" == "--no-tty" ]]; then
      if IFS= read -r -t 0.1 _stdin_line; then
        echo "chezmoi-update-read-stdin"
        exit 3
      fi
      echo "chezmoi-update-apply-called"
    fi
    ;;
esac
exit 0
CHEZ

  cat > "$env_dir/bin/gh" <<'GH'
#!/usr/bin/env bash
if [[ "$1" == "--version" ]]; then
  echo "gh version 2.93.0"
elif [[ "$1" == "auth" && "$2" == "status" ]]; then
  exit 0
fi
GH

  chmod +x "$env_dir/bin/curl" "$env_dir/bin/git" "$env_dir/bin/brew" "$env_dir/bin/chezmoi" "$env_dir/bin/gh"
}

run_install() {
  local env_dir="$1"
  shift
  set +e
  local output
  output="$(printf 'stdin-sentinel-from-pipe\n' | HOME="$env_dir/home" PATH="$env_dir/bin:/usr/bin:/bin:/usr/sbin:/sbin" OSTYPE=darwin23 MAC_DOTFILES_SKIP_BREW_PATH_DETECTION=1 bash "$INSTALL_SCRIPT" "$@" 2>&1)"
  local status=$?
  set -e
  printf '%s\n__EXIT_STATUS__=%s\n' "$output" "$status"
}

parse_status() {
  local run_output="$1"
  echo "$run_output" | awk -F= '/__EXIT_STATUS__/ {print $2}' | tail -n1
}

strip_status_line() {
  local run_output="$1"
  echo "$run_output" | sed '/__EXIT_STATUS__/d'
}

test_verify_happy_path() {
  local env_dir run_output status output
  env_dir="$(setup_env)"
  write_common_mocks "$env_dir"

  run_output="$(run_install "$env_dir" --verify)"
  status="$(parse_status "$run_output")"
  output="$(strip_status_line "$run_output")"

  assert_exit_code "$status" 0 "install --verify should pass for a fully configured machine"
  assert_contains "$output" "macOS Bootstrap Verification" "verify should print its heading"
  assert_contains "$output" "Verification completed successfully" "verify should report success"
  assert_not_contains "$output" "Checking sudo access" "verify must not request sudo"
}

test_verify_reports_missing_homebrew() {
  local env_dir run_output status output
  env_dir="$(setup_env)"
  write_common_mocks "$env_dir"
  rm -f "$env_dir/bin/brew"

  run_output="$(run_install "$env_dir" --verify)"
  status="$(parse_status "$run_output")"
  output="$(strip_status_line "$run_output")"

  assert_exit_code "$status" 1 "install --verify should warn when Homebrew is missing"
  assert_contains "$output" "Homebrew is not installed or not in PATH" "missing Homebrew should be reported"
  assert_not_contains "$output" "Checking sudo access" "verify must not request sudo when checks fail"
}

test_existing_chezmoi_runs_update_apply() {
  local env_dir run_output status output
  env_dir="$(setup_env)"
  write_common_mocks "$env_dir"

  cat > "$env_dir/bin/sudo" <<'SUDO'
#!/usr/bin/env bash
exit 0
SUDO
  chmod +x "$env_dir/bin/sudo"

  run_output="$(run_install "$env_dir")"
  status="$(parse_status "$run_output")"
  output="$(strip_status_line "$run_output")"

  assert_exit_code "$status" 0 "install should succeed when chezmoi is already initialized"
  assert_contains "$output" "Chezmoi already initialized" "existing chezmoi state should be detected"
  assert_contains "$output" "Syncing and applying existing dotfiles" "install should self-heal existing dotfiles"
  assert_contains "$output" "chezmoi-update-apply-called" "install should run forced non-interactive chezmoi update --apply"
  assert_not_contains "$output" "chezmoi-update-read-stdin" "install should not let chezmoi consume script stdin"
  assert_contains "$output" "Your dotfiles have been applied with chezmoi." "install should report applied state"
  assert_contains "$output" "mac-dotfiles.sh   - Optional local launcher" "install should mention launcher as optional"
  assert_not_contains "$output" "mac-dotfiles\n============" "install should not open the interactive launcher"
}

main() {
  test_verify_happy_path
  test_verify_reports_missing_homebrew
  test_existing_chezmoi_runs_update_apply
  echo "[PASS] install.sh tests completed"
}

main
