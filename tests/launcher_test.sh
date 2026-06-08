#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAUNCHER_SCRIPT="$REPO_ROOT/dot_local/bin/executable_mac-dotfiles.sh.tmpl"

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
  mkdir -p "$env_dir/home/.local/bin" "$env_dir/home/.local/share/chezmoi" "$env_dir/bin"

  cat > "$env_dir/home/.local/share/chezmoi/install.sh" <<'INSTALL'
#!/usr/bin/env bash
if [[ "$1" == "--verify" ]]; then
  echo "verify-called"
fi
INSTALL

  cat > "$env_dir/home/.local/share/chezmoi/doctor.sh" <<'DOCTOR'
#!/usr/bin/env bash
if [[ "${1:-}" == "--explain" ]]; then
  echo "explain-called"
else
  echo "doctor-called"
fi
DOCTOR

  cat > "$env_dir/home/.local/bin/mac-dotfiles-report.sh" <<'REPORT'
#!/usr/bin/env bash
echo "report-called"
REPORT

  cat > "$env_dir/home/.local/bin/mac-dotfiles-safe-update.sh" <<'SAFE'
#!/usr/bin/env bash
echo "safe-update-called"
SAFE

  cat > "$env_dir/home/.local/bin/mac-dotfiles-maintenance.sh" <<'MAINT'
#!/usr/bin/env bash
echo "maintenance-called"
MAINT

  cat > "$env_dir/bin/chezmoi" <<'CHEZ'
#!/usr/bin/env bash
if [[ "$1" == "update" ]]; then
  echo "update-called"
elif [[ "$1" == "diff" ]]; then
  echo "diff-called"
fi
CHEZ

  chmod +x \
    "$env_dir/home/.local/share/chezmoi/install.sh" \
    "$env_dir/home/.local/share/chezmoi/doctor.sh" \
    "$env_dir/home/.local/bin/mac-dotfiles-report.sh" \
    "$env_dir/home/.local/bin/mac-dotfiles-safe-update.sh" \
    "$env_dir/home/.local/bin/mac-dotfiles-maintenance.sh" \
    "$env_dir/bin/chezmoi"

  echo "$env_dir"
}

run_launcher() {
  local env_dir="$1"
  shift
  HOME="$env_dir/home" PATH="$env_dir/bin:/usr/bin:/bin:/usr/sbin:/sbin" bash "$LAUNCHER_SCRIPT" "$@"
}

test_help() {
  local env_dir output
  env_dir="$(setup_env)"
  output="$(run_launcher "$env_dir" help)"
  assert_contains "$output" "Usage: mac-dotfiles.sh" "help should print usage"
}

test_direct_commands() {
  local env_dir output report_path
  env_dir="$(setup_env)"

  output="$(run_launcher "$env_dir" verify)"
  assert_contains "$output" "verify-called" "verify command should call install --verify"

  output="$(run_launcher "$env_dir" safe-update)"
  assert_contains "$output" "safe-update-called" "safe-update command should call safe update script"

  output="$(run_launcher "$env_dir" update)"
  assert_contains "$output" "update-called" "update command should call chezmoi update"

  output="$(run_launcher "$env_dir" explain)"
  assert_contains "$output" "explain-called" "explain command should call doctor --explain"

  report_path="$env_dir/home/report.md"
  output="$(run_launcher "$env_dir" report "$report_path")"
  assert_contains "$output" "Report written to $report_path" "report command should print destination"
  assert_contains "$(cat "$report_path")" "report-called" "report command should write report content"
}

test_menu_exit() {
  local env_dir output
  env_dir="$(setup_env)"
  output="$(printf '0\n' | HOME="$env_dir/home" PATH="$env_dir/bin:/usr/bin:/bin:/usr/sbin:/sbin" bash "$LAUNCHER_SCRIPT")"
  assert_contains "$output" "mac-dotfiles" "menu should print title"
  assert_contains "$output" "Bye." "menu should exit cleanly"
}

main() {
  test_help
  test_direct_commands
  test_menu_exit
  echo "[PASS] launcher tests completed"
}

main
