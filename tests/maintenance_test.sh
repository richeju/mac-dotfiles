#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAINTENANCE_SCRIPT="$REPO_ROOT/dot_local/bin/executable_mac-dotfiles-maintenance.sh.tmpl"

fail() {
    echo "[FAIL] $1" >&2
    exit 1
}

setup_env() {
    local env_dir
    env_dir="$(mktemp -d)"
    mkdir -p "$env_dir/home/.local/bin" "$env_dir/home/.local/share/chezmoi" \
        "$env_dir/home/.local/state/mac-dotfiles"
    cat >"$env_dir/home/.local/bin/mac-dotfiles-brew-maintenance.sh" <<'SCRIPT'
run_brew_maintenance() { echo "brew-maintenance-called"; }
SCRIPT
    cat >"$env_dir/home/.local/bin/mac-dotfiles-certified-update.sh" <<'SCRIPT'
#!/usr/bin/env bash
echo "certified-update-called:$*:lock=${MAC_DOTFILES_LOCK_HELD:-0}"
[[ ! -f "$HOME/certified-update-fails" ]]
SCRIPT
    cat >"$env_dir/home/.local/bin/mac-dotfiles-watchdog.sh" <<'SCRIPT'
#!/usr/bin/env bash
echo "watchdog-called:${MAC_DOTFILES_MAINTENANCE_EXIT_STATUS:-missing}"
SCRIPT
    cat >"$env_dir/home/.local/bin/mac-dotfiles-compliance.sh" <<'SCRIPT'
#!/usr/bin/env bash
echo "compliance-called:$*"
[[ ! -f "$HOME/compliance-errors" ]] || exit 2
[[ ! -f "$HOME/compliance-findings" ]] || exit 1
SCRIPT
    chmod +x "$env_dir/home/.local/bin/mac-dotfiles-certified-update.sh" \
        "$env_dir/home/.local/bin/mac-dotfiles-watchdog.sh" "$env_dir/home/.local/bin/mac-dotfiles-compliance.sh"
    echo "$env_dir"
}

test_launchd_path_finds_managed_tools() {
    local env_dir output
    env_dir="$(setup_env)"
    cat >"$env_dir/home/.local/bin/chezmoi" <<'SCRIPT'
#!/usr/bin/env bash
echo "chezmoi-called"
SCRIPT
    cat >"$env_dir/home/.local/bin/brew" <<'SCRIPT'
#!/usr/bin/env bash
exit 0
SCRIPT
    chmod +x "$env_dir/home/.local/bin/chezmoi" "$env_dir/home/.local/bin/brew"

    output="$(HOME="$env_dir/home" PATH="/usr/bin:/bin:/usr/sbin:/sbin" bash "$MAINTENANCE_SCRIPT")"
    [[ "$output" == *"certified-update-called:run:lock=1"* ]] ||
        fail "maintenance should run the certified updater under its shared lock"
    [[ "$output" == *"brew-maintenance-called"* ]] || fail "maintenance should run Homebrew work"
    [[ "$output" == *"Maintenance completed"* ]] || fail "maintenance should report success after doing work"
    [[ "$output" == *"watchdog-called:0"* ]] || fail "successful maintenance should update watchdog health"
    [[ "$output" == *"Tailored NIST compliance audit passed"* ]] || fail "maintenance should refresh compliance evidence"
    jq -e '.schema_version == 1 and .exit_status == 0' \
        "$env_dir/home/.local/state/mac-dotfiles/maintenance-status.json" >/dev/null ||
        fail "successful maintenance should persist its status"
}

test_compliance_findings_are_advisory() {
    local env_dir output
    env_dir="$(setup_env)"
    touch "$env_dir/home/compliance-findings"
    cat >"$env_dir/home/.local/bin/chezmoi" <<'SCRIPT'
#!/usr/bin/env bash
exit 0
SCRIPT
    cat >"$env_dir/home/.local/bin/brew" <<'SCRIPT'
#!/usr/bin/env bash
exit 0
SCRIPT
    chmod +x "$env_dir/home/.local/bin/chezmoi" "$env_dir/home/.local/bin/brew"
    output="$(HOME="$env_dir/home" PATH="/usr/bin:/bin:/usr/sbin:/sbin" bash "$MAINTENANCE_SCRIPT")"
    [[ "$output" == *"recorded advisory findings"* ]] || fail "NIST findings should be reported"
    [[ "$output" == *"watchdog-called:0"* ]] || fail "audit-only findings must not fail maintenance"
}

test_failed_certified_update_fails_maintenance_after_other_work() {
    local env_dir output status
    env_dir="$(setup_env)"
    touch "$env_dir/home/certified-update-fails"
    cat >"$env_dir/home/.local/bin/chezmoi" <<'SCRIPT'
#!/usr/bin/env bash
exit 0
SCRIPT
    cat >"$env_dir/home/.local/bin/brew" <<'SCRIPT'
#!/usr/bin/env bash
exit 0
SCRIPT
    chmod +x "$env_dir/home/.local/bin/chezmoi" "$env_dir/home/.local/bin/brew"

    set +e
    output="$(HOME="$env_dir/home" PATH="/usr/bin:/bin:/usr/sbin:/sbin" bash "$MAINTENANCE_SCRIPT" 2>&1)"
    status=$?
    set -e
    [[ "$status" -eq 1 ]] || fail "failed certified update should fail maintenance"
    [[ "$output" == *"brew-maintenance-called"* ]] || fail "Homebrew work should continue after update failure"
    [[ "$output" == *"watchdog-called:1"* ]] || fail "update failure should reach the watchdog"
    jq -e '.exit_status == 1' "$env_dir/home/.local/state/mac-dotfiles/maintenance-status.json" >/dev/null ||
        fail "certified update failure should persist a failed maintenance status"
}

test_no_available_work_fails() {
    local env_dir output status
    env_dir="$(setup_env)"
    set +e
    output="$(HOME="$env_dir/home" MAC_DOTFILES_PATH="/usr/bin:/bin:/usr/sbin:/sbin" AUTO_CHEZMOI_UPDATE=0 bash "$MAINTENANCE_SCRIPT" 2>&1)"
    status=$?
    set -e
    [[ "$status" -eq 1 ]] || fail "maintenance should fail when no task can run"
    [[ "$output" == *"No maintenance task could run"* ]] || fail "maintenance should explain the failure"
    [[ "$output" != *"Maintenance completed"* ]] || fail "maintenance must not report a false success"
    [[ "$output" == *"watchdog-called:1"* ]] || fail "failed maintenance should reach the watchdog"
    jq -e '.schema_version == 1 and .exit_status == 1' \
        "$env_dir/home/.local/state/mac-dotfiles/maintenance-status.json" >/dev/null ||
        fail "failed maintenance should persist its status"
}

test_stale_operation_lock_recovers() {
    local env_dir lock output
    env_dir="$(setup_env)"
    lock="$env_dir/home/.local/state/mac-dotfiles/operation.lock"
    mkdir "$lock"
    echo 2147483647 >"$lock/pid"
    printf '#!/bin/sh\nexit 0\n' >"$env_dir/home/.local/bin/brew"
    chmod +x "$env_dir/home/.local/bin/brew"

    output="$(HOME="$env_dir/home" AUTO_CHEZMOI_UPDATE=0 bash "$MAINTENANCE_SCRIPT" 2>&1)"
    [[ "$output" == *"Recovering abandoned"* && "$output" == *"brew-maintenance-called"* ]] ||
        fail "a dead owner should allow maintenance to recover and run"
    [[ "$output" == *"watchdog-called:0"* && ! -e "$lock" ]] ||
        fail "recovered maintenance must update the watchdog and release the lock"
    jq -e '.exit_status == 0' "${lock%/*}/maintenance-status.json" >/dev/null ||
        fail "a recovered run must persist its result"
}

test_live_and_initializing_locks_are_preserved() {
    local env_dir lock output
    env_dir="$(setup_env)"
    lock="$env_dir/home/.local/state/mac-dotfiles/operation.lock"
    mkdir "$lock"
    output="$(HOME="$env_dir/home" bash "$MAINTENANCE_SCRIPT" 2>&1)"
    [[ "$output" == *"Skipping maintenance"* && ! -f "$lock/pid" ]] ||
        fail "maintenance must allow a live owner to publish its PID"
    echo "$$" >"$lock/pid"
    output="$(HOME="$env_dir/home" bash "$MAINTENANCE_SCRIPT" 2>&1)"
    [[ "$output" == *"Skipping maintenance"* && "$(cat "$lock/pid")" == "$$" ]] ||
        fail "maintenance must leave the live owner's PID intact"
    [[ ! -f "${lock%/*}/maintenance-status.json" ]] ||
        fail "a skipped run must preserve the previous maintenance status"
}

test_reused_pid_does_not_block_recovery() {
    local env_dir lock
    env_dir="$(setup_env)"
    lock="$env_dir/home/.local/state/mac-dotfiles/operation.lock"
    mkdir "$lock"
    echo "$$" >"$lock/pid"
    touch -t 200001010000 "$lock/pid"
    /usr/bin/perl "$REPO_ROOT/dot_local/bin/mac-dotfiles-claim-lock.pl" "$lock" "$$" \
        2>"$env_dir/claim.log" || fail "a PID reused since the lock was written must not block recovery"
    grep -q 'Recovering abandoned' "$env_dir/claim.log" || fail "PID reuse should be reported"
}

test_concurrent_recovery_has_one_owner() {
    local env_dir lock index status
    env_dir="$(setup_env)"
    lock="$env_dir/home/.local/state/mac-dotfiles/operation.lock"
    mkdir "$lock"
    touch -t 200001010000 "$lock"
    for index in 1 2 3 4; do
        (
            status=0
            /usr/bin/perl "$REPO_ROOT/dot_local/bin/mac-dotfiles-claim-lock.pl" "$lock" "$$" \
                2>"$env_dir/$index.log" || status=$?
            echo "$status" >"$env_dir/$index.result"
        ) &
    done
    wait
    [[ "$(grep -lx 0 "$env_dir"/*.result | wc -l | tr -d ' ')" == 1 ]] ||
        fail "exactly one contender should adopt an old lock with a missing PID"
    [[ "$(grep -lx 1 "$env_dir"/*.result | wc -l | tr -d ' ')" == 3 ]] ||
        fail "the other contenders must respect the new owner"
}

test_launchd_path_finds_managed_tools
test_failed_certified_update_fails_maintenance_after_other_work
test_compliance_findings_are_advisory
test_no_available_work_fails
test_stale_operation_lock_recovers
test_live_and_initializing_locks_are_preserved
test_reused_pid_does_not_block_recovery
test_concurrent_recovery_has_one_owner
echo "[PASS] maintenance tests completed"
