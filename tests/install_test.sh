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
    cat >"$env_dir/home/.local/bin/mac-dotfiles-maintenance.sh" <<'SCRIPT'
#!/usr/bin/env bash
exit 0
SCRIPT
    cat >"$env_dir/home/.local/bin/mac-dotfiles.sh" <<'SCRIPT'
#!/usr/bin/env bash
exit 0
SCRIPT
    cat >"$env_dir/home/.local/bin/mac-dotfiles-certified-update.sh" <<'SCRIPT'
#!/usr/bin/env bash
exit 0
SCRIPT
    chmod +x "$env_dir/home/.local/bin/mac-dotfiles-maintenance.sh" "$env_dir/home/.local/bin/mac-dotfiles.sh" \
        "$env_dir/home/.local/bin/mac-dotfiles-certified-update.sh"
    echo "$env_dir"
}

write_common_mocks() {
    local env_dir="$1"

    cat >"$env_dir/bin/curl" <<'CURL'
#!/usr/bin/env bash
exit 0
CURL

    cat >"$env_dir/bin/git" <<'GIT'
#!/usr/bin/env bash
exit 0
GIT

    cat >"$env_dir/bin/brew" <<'BREW'
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

    cat >"$env_dir/bin/chezmoi" <<'CHEZ'
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
  init)
    echo "chezmoi-init-args:$*"
    echo "chezmoi-init-profile:${MAC_DOTFILES_PROFILE:-missing}"
    echo "chezmoi-init-name:${GIT_NAME:-missing}"
    ;;
esac
exit 0
CHEZ

    cat >"$env_dir/bin/gh" <<'GH'
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

    run_output="$(run_install "$env_dir")"
    status="$(parse_status "$run_output")"
    output="$(strip_status_line "$run_output")"

    assert_exit_code "$status" 0 "install should succeed when chezmoi is already initialized"
    assert_not_contains "$output" "administrator privileges" "install should not request sudo when Homebrew is already installed"
    assert_contains "$output" "Chezmoi already initialized" "existing chezmoi state should be detected"
    assert_contains "$output" "Syncing and applying existing dotfiles" "install should self-heal existing dotfiles"
    assert_contains "$output" "chezmoi-update-apply-called" "install should run forced non-interactive chezmoi update --apply"
    assert_not_contains "$output" "chezmoi-update-read-stdin" "install should not let chezmoi consume script stdin"
    assert_contains "$output" "Your dotfiles have been applied with chezmoi." "install should report applied state"
    assert_contains "$output" "Install summary" "install should print a final summary"
    assert_contains "$output" "Homebrew bundle satisfied" "summary should report bundle state"
    assert_contains "$output" "Everything looks squared away" "summary should report all-clear when checks pass"
    assert_contains "$output" "mac-dotfiles.sh   - Optional local launcher" "install should mention launcher as optional"
    assert_contains "$output" "mac-dotfiles.sh repair" "install should suggest the repair command"
    assert_not_contains "$output" "mac-dotfiles\n============" "install should not open the interactive launcher"
}

test_existing_chezmoi_recovers_deleted_tracking_branch() {
    local env_dir run_output status output git_log
    env_dir="$(setup_env)"
    write_common_mocks "$env_dir"
    git_log="$env_dir/git.log"
    cat >"$env_dir/bin/git" <<'GIT'
#!/usr/bin/env bash
echo "$*" >>"$GIT_TEST_LOG"
if [[ "$1" == "-C" ]]; then
  shift 2
fi
case "$1 $2" in
  "rev-parse --is-inside-work-tree") exit 0 ;;
  "fetch origin") exit 0 ;;
  "rev-parse --verify") exit 1 ;;
  "status --porcelain") exit 0 ;;
  "symbolic-ref --quiet") echo origin/main; exit 0 ;;
  "show-ref --verify") exit 0 ;;
  "switch main") exit 0 ;;
  "branch --set-upstream-to=origin/main") exit 0 ;;
esac
exit 0
GIT
    chmod +x "$env_dir/bin/git"

    set +e
    output="$(printf 'stdin-sentinel-from-pipe\n' | HOME="$env_dir/home" GIT_TEST_LOG="$git_log" PATH="$env_dir/bin:/usr/bin:/bin:/usr/sbin:/sbin" OSTYPE=darwin23 MAC_DOTFILES_SKIP_BREW_PATH_DETECTION=1 bash "$INSTALL_SCRIPT" 2>&1)"
    status=$?
    set -e

    assert_exit_code "$status" 0 "install should recover when the tracked source branch was deleted"
    assert_contains "$output" "branch no longer exists on origin; switching to main" "installer should explain deleted-branch recovery"
    assert_contains "$(cat "$git_log")" "switch main" "installer should switch the source to main"
    assert_contains "$output" "chezmoi-update-apply-called" "installer should continue applying after branch recovery"
}

test_install_summary_does_not_treat_outdated_packages_as_missing() {
    local env_dir run_output status output
    env_dir="$(setup_env)"
    write_common_mocks "$env_dir"
    cat >"$env_dir/bin/brew" <<'BREW'
#!/usr/bin/env bash
case "$1" in
  --prefix) echo "/opt/homebrew" ;;
  list) [[ "${2:-}" == "chezmoi" ]] ;;
  bundle)
    [[ " $* " == *" check "* && " $* " == *" --no-upgrade "* ]]
    ;;
esac
BREW
    chmod +x "$env_dir/bin/brew"

    run_output="$(run_install "$env_dir")"
    status="$(parse_status "$run_output")"
    output="$(strip_status_line "$run_output")"

    assert_exit_code "$status" 0 "outdated-only Homebrew state should not fail bootstrap"
    assert_contains "$output" "Homebrew bundle satisfied" "summary should check presence without requiring upgrades"
    assert_not_contains "$output" "missing or outdated items" "summary should leave upgrades to maintenance"
}

test_minimal_mode_skips_bundle_summary() {
    local env_dir run_output status output
    env_dir="$(setup_env)"
    write_common_mocks "$env_dir"

    run_output="$(run_install "$env_dir" --minimal)"
    status="$(parse_status "$run_output")"
    output="$(strip_status_line "$run_output")"

    assert_exit_code "$status" 0 "install --minimal should succeed when prerequisites exist"
    assert_contains "$output" "Minimal mode enabled" "minimal mode should announce itself"
    assert_contains "$output" "Full Homebrew bundle skipped for minimal setup" "summary should mark the full bundle as skipped"
    assert_contains "$output" "Minimal setup completed" "minimal mode should explain the post-install path"
}

test_auto_init_uses_supported_chezmoi_flags_and_profile() {
    local env_dir run_output status output
    env_dir="$(setup_env)"
    write_common_mocks "$env_dir"
    rm -rf "$env_dir/home/.local/share/chezmoi"

    run_output="$(run_install "$env_dir" --auto --git-name "Test User" --git-email test@example.com --profile gaming)"
    status="$(parse_status "$run_output")"
    output="$(strip_status_line "$run_output")"

    assert_exit_code "$status" 0 "fresh auto init should succeed"
    assert_contains "$output" "chezmoi-init-args:init --apply --no-tty richeju/mac-dotfiles" "auto init should use current chezmoi flags"
    assert_not_contains "$output" "--data" "auto init must not use the obsolete --data value syntax"
    assert_contains "$output" "chezmoi-init-profile:gaming" "selected profile should reach the config template"
    assert_contains "$output" "chezmoi-init-name:Test User" "Git identity should reach the config template"
}

test_unknown_profile_is_rejected() {
    local env_dir run_output status output
    env_dir="$(setup_env)"
    write_common_mocks "$env_dir"

    run_output="$(run_install "$env_dir" --profile impossible)"
    status="$(parse_status "$run_output")"
    output="$(strip_status_line "$run_output")"
    assert_exit_code "$status" 1 "unknown profile should fail"
    assert_contains "$output" "Unknown profile: impossible" "unknown profile should be explained"
}

main() {
    test_verify_happy_path
    test_verify_reports_missing_homebrew
    test_existing_chezmoi_runs_update_apply
    test_existing_chezmoi_recovers_deleted_tracking_branch
    test_install_summary_does_not_treat_outdated_packages_as_missing
    test_minimal_mode_skips_bundle_summary
    test_auto_init_uses_supported_chezmoi_flags_and_profile
    test_unknown_profile_is_rejected
    echo "[PASS] install.sh tests completed"
}

main
