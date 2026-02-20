#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCTOR_SCRIPT="$REPO_ROOT/doctor.sh"

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

assert_exit_code() {
  local actual="$1"
  local expected="$2"
  local message="$3"
  [[ "$actual" -eq "$expected" ]] || fail "$message (expected $expected got $actual)"
}

run_doctor() {
  local env_dir="$1"
  shift
  set +e
  local output
  output="$(HOME="$env_dir/home" PATH="$env_dir/bin:$PATH" OSTYPE=darwin23 bash "$DOCTOR_SCRIPT" "$@" 2>&1)"
  local status=$?
  set -e
  printf '%s\n__EXIT_STATUS__=%s\n' "$output" "$status"
}

setup_env() {
  local env_dir
  env_dir="$(mktemp -d)"
  mkdir -p "$env_dir/bin" "$env_dir/home/.local/bin"
  touch "$env_dir/home/.Brewfile" "$env_dir/home/.gitconfig" "$env_dir/home/.local/bin/mac-dotfiles-maintenance.sh"
  echo "$env_dir"
}

write_common_mocks() {
  local env_dir="$1"

  cat > "$env_dir/bin/git" <<'GIT'
#!/usr/bin/env bash
if [[ "$1" == "--version" ]]; then
  echo "git version 2.45.1"
  exit 0
fi
exit 0
GIT

  cat > "$env_dir/bin/curl" <<'CURL'
#!/usr/bin/env bash
exit 0
CURL

  cat > "$env_dir/bin/brew" <<'BREW'
#!/usr/bin/env bash
if [[ "$1" == "bundle" && "$2" == "check" ]]; then
  exit 0
fi
if [[ "$1" == "bundle" ]]; then
  exit 0
fi
exit 0
BREW

  cat > "$env_dir/bin/chezmoi" <<'CHEZ'
#!/usr/bin/env bash
if [[ "$1" == "--version" ]]; then
  echo "chezmoi version v2.55.0"
  exit 0
fi
if [[ "$1" == "diff" && "$2" == "--quiet" ]]; then
  exit 0
fi
if [[ "$1" == "apply" ]]; then
  exit 0
fi
exit 0
CHEZ

  chmod +x "$env_dir/bin/git" "$env_dir/bin/curl" "$env_dir/bin/brew" "$env_dir/bin/chezmoi"
}

parse_status() {
  local run_output="$1"
  echo "$run_output" | awk -F= '/__EXIT_STATUS__/ {print $2}' | tail -n1
}

strip_status_line() {
  local run_output="$1"
  echo "$run_output" | sed '/__EXIT_STATUS__/d'
}

test_help() {
  local env_dir
  env_dir="$(setup_env)"
  write_common_mocks "$env_dir"

  local run_output status output
  run_output="$(run_doctor "$env_dir" --help)"
  status="$(parse_status "$run_output")"
  output="$(strip_status_line "$run_output")"

  assert_exit_code "$status" 0 "doctor --help should exit successfully"
  assert_contains "$output" "Usage: ./doctor.sh" "doctor --help should print usage"
}

test_happy_path_json() {
  local env_dir
  env_dir="$(setup_env)"
  write_common_mocks "$env_dir"

  local run_output status output
  run_output="$(run_doctor "$env_dir" --json)"
  status="$(parse_status "$run_output")"
  output="$(strip_status_line "$run_output")"

  assert_exit_code "$status" 0 "doctor --json happy path should exit successfully"
  assert_contains "$output" '"overall": "ok"' "JSON summary should report overall ok"
  assert_contains "$output" '"name": "platform", "status": "ok"' "JSON summary should include platform check"
}

test_fix_mode_runs_autofix() {
  local env_dir
  env_dir="$(setup_env)"
  write_common_mocks "$env_dir"

  cat > "$env_dir/bin/brew" <<BREW
#!/usr/bin/env bash
state_file="$env_dir/brew.state"
if [[ "\$1" == "bundle" && "\$2" == "check" ]]; then
  if [[ -f "\$state_file" ]]; then
    exit 0
  fi
  exit 1
fi
if [[ "\$1" == "bundle" ]]; then
  echo brew-fix-called >> "$env_dir/brew.log"
  touch "\$state_file"
  exit 0
fi
exit 0
BREW

  cat > "$env_dir/bin/chezmoi" <<CHEZ
#!/usr/bin/env bash
state_file="$env_dir/chezmoi.state"
if [[ "\$1" == "--version" ]]; then
  echo "chezmoi version v2.55.0"
  exit 0
fi
if [[ "\$1" == "diff" && "\$2" == "--quiet" ]]; then
  if [[ -f "\$state_file" ]]; then
    exit 0
  fi
  exit 1
fi
if [[ "\$1" == "apply" ]]; then
  echo chezmoi-fix-called >> "$env_dir/chezmoi.log"
  touch "\$state_file"
  exit 0
fi
exit 0
CHEZ

  chmod +x "$env_dir/bin/brew" "$env_dir/bin/chezmoi"

  local run_output status output
  run_output="$(run_doctor "$env_dir" --fix)"
  status="$(parse_status "$run_output")"
  output="$(strip_status_line "$run_output")"

  assert_exit_code "$status" 0 "doctor --fix should return success when auto-fixes resolve all issues"
  assert_contains "$output" "Applying fix: brew bundle --global --verbose" "brew autofix should be attempted"
  assert_contains "$output" "Applying fix: chezmoi apply" "chezmoi autofix should be attempted"
  assert_contains "$output" "Homebrew dependencies fixed successfully" "brew should be reported fixed after --fix"
  assert_contains "$output" "Pending dotfile changes fixed successfully" "chezmoi should be reported fixed after --fix"
  [[ -f "$env_dir/brew.log" ]] || fail "brew autofix command was not invoked"
  [[ -f "$env_dir/chezmoi.log" ]] || fail "chezmoi autofix command was not invoked"
}

test_fix_mode_reports_warning_when_fix_fails() {
  local env_dir
  env_dir="$(setup_env)"
  write_common_mocks "$env_dir"

  cat > "$env_dir/bin/brew" <<'BREW'
#!/usr/bin/env bash
if [[ "$1" == "bundle" && "$2" == "check" ]]; then
  exit 1
fi
if [[ "$1" == "bundle" ]]; then
  exit 1
fi
exit 0
BREW

  chmod +x "$env_dir/bin/brew"

  local run_output status output
  run_output="$(run_doctor "$env_dir" --fix)"
  status="$(parse_status "$run_output")"
  output="$(strip_status_line "$run_output")"

  assert_exit_code "$status" 1 "doctor --fix should return warning when auto-fix fails"
  assert_contains "$output" "Auto-fix failed for Homebrew dependencies" "brew failed autofix should be reported"
}

main() {
  test_help
  test_happy_path_json
  test_fix_mode_runs_autofix
  test_fix_mode_reports_warning_when_fix_fails
  echo "[PASS] doctor.sh tests completed"
}

main
