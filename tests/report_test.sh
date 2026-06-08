#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPORT_SCRIPT="$REPO_ROOT/dot_local/bin/executable_mac-dotfiles-report.sh.tmpl"

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
    "$env_dir/home/.local/share/chezmoi" \
    "$env_dir/home/.local/state/mac-dotfiles" \
    "$env_dir/home/Library/LaunchAgents"

  touch "$env_dir/home/Library/LaunchAgents/com.chezmoi.mac-dotfiles.maintenance.plist"
  cat > "$env_dir/home/.local/bin/mac-dotfiles-maintenance.sh" <<'SCRIPT'
#!/usr/bin/env bash
exit 0
SCRIPT
  chmod +x "$env_dir/home/.local/bin/mac-dotfiles-maintenance.sh"

  cat > "$env_dir/home/.local/share/chezmoi/doctor.sh" <<'DOCTOR'
#!/usr/bin/env bash
echo "## mac-dotfiles doctor report"
exit 0
DOCTOR
  chmod +x "$env_dir/home/.local/share/chezmoi/doctor.sh"

  echo "maintenance-ok" > "$env_dir/home/.local/state/mac-dotfiles/maintenance.log"
  echo "launchd-ok" > "$env_dir/home/.local/state/mac-dotfiles/launchd.log"
  echo "$env_dir"
}

write_mocks() {
  local env_dir="$1"

  cat > "$env_dir/bin/sw_vers" <<'SW'
#!/usr/bin/env bash
case "$1" in
  -productVersion) echo "15.5" ;;
  -buildVersion) echo "24F74" ;;
esac
SW

  cat > "$env_dir/bin/uname" <<'UNAME'
#!/usr/bin/env bash
echo "arm64"
UNAME

  cat > "$env_dir/bin/hostname" <<'HOST'
#!/usr/bin/env bash
echo "test-mac"
HOST

  cat > "$env_dir/bin/brew" <<'BREW'
#!/usr/bin/env bash
if [[ "$1" == "--version" ]]; then
  echo "Homebrew 4.6.0"
elif [[ "$1" == "--prefix" ]]; then
  echo "/opt/homebrew"
elif [[ "$1" == "bundle" && "$2" == "check" ]]; then
  echo "The Brewfile's dependencies are satisfied."
elif [[ "$1" == "bundle" && "$2" == "list" && "$3" == "--global" && "$4" == "--formula" ]]; then
  echo "gh"
  echo "node"
elif [[ "$1" == "bundle" && "$2" == "list" && "$3" == "--global" && "$4" == "--cask" ]]; then
  echo "dropbox"
elif [[ "$1" == "outdated" ]]; then
  exit 0
fi
BREW

  cat > "$env_dir/bin/chezmoi" <<'CHEZ'
#!/usr/bin/env bash
if [[ "$1" == "--version" ]]; then
  echo "chezmoi version v2.70.5"
elif [[ "$1" == "diff" ]]; then
  exit 0
fi
CHEZ

  cat > "$env_dir/bin/git" <<'GIT'
#!/usr/bin/env bash
echo "git version 2.50.1"
GIT

  cat > "$env_dir/bin/gh" <<'GH'
#!/usr/bin/env bash
if [[ "$1" == "--version" ]]; then
  echo "gh version 2.93.0"
elif [[ "$1" == "auth" && "$2" == "status" ]]; then
  exit 0
fi
GH

  cat > "$env_dir/bin/node" <<'NODE'
#!/usr/bin/env bash
echo "v26.0.0"
NODE

  cat > "$env_dir/bin/launchctl" <<'LAUNCH'
#!/usr/bin/env bash
exit 0
LAUNCH

  chmod +x "$env_dir/bin/"*
}

test_report_happy_path() {
  local env_dir output
  env_dir="$(setup_env)"
  write_mocks "$env_dir"

  output="$(HOME="$env_dir/home" PATH="$env_dir/bin:/usr/bin:/bin:/usr/sbin:/sbin" bash "$REPORT_SCRIPT")"

  assert_contains "$output" "# mac-dotfiles report" "report should include title"
  assert_contains "$output" "## System" "report should include system section"
  assert_contains "$output" "- Bundle: satisfied" "report should include bundle status"
  assert_contains "$output" "## mac-dotfiles doctor report" "report should include doctor output"
  assert_contains "$output" "maintenance-ok" "report should include maintenance log"
  assert_contains "$output" "launchd-ok" "report should include launchd log"
}

main() {
  test_report_happy_path
  echo "[PASS] report tests completed"
}

main
