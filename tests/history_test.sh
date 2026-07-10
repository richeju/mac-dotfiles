#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HISTORY_SCRIPT="$REPO_ROOT/dot_local/bin/executable_mac-dotfiles-history.sh.tmpl"

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

create_safe_update() {
    local env_dir="$1"
    local run_id="$2"
    local backup_dir="$env_dir/home/.local/state/mac-dotfiles/safe-updates/$run_id/backups"
    mkdir -p "$backup_dir"
    echo "$run_id" >"$backup_dir/.gitconfig"
}

create_rollback() {
    local env_dir="$1"
    local rollback_id="$2"
    local rollback_dir="$env_dir/home/.local/state/mac-dotfiles/rollback-backups/$rollback_id"
    mkdir -p "$rollback_dir"
    echo "$rollback_id" >"$rollback_dir/.gitconfig"
}

run_history() {
    local env_dir="$1"
    shift
    HOME="$env_dir/home" PATH="/usr/bin:/bin:/usr/sbin:/sbin" bash "$HISTORY_SCRIPT" "$@"
}

test_history_lists_latest_entries() {
    local env_dir output newest
    env_dir="$(mktemp -d)"
    create_safe_update "$env_dir" "20260101-120000"
    create_safe_update "$env_dir" "20260102-120000"
    create_rollback "$env_dir" "20260103-120000-from-20260102-120000"
    newest="$env_dir/home/.local/state/mac-dotfiles/safe-updates/20260102-120000"
    echo before >"$newest/report-before.md"
    echo after >"$newest/report-after.md"

    output="$(run_history "$env_dir")"

    assert_contains "$output" "Safe-update history" "history should include safe updates"
    assert_contains "$output" "20260102-120000" "history should include the newest run"
    assert_contains "$output" "yes      latest" "newest complete run should be marked latest"
    assert_contains "$output" "Rollback backups" "history should include rollback backups"
    assert_contains "$output" "20260103-120000-from-20260102-120000" "history should include rollback ID"
}

test_prune_keeps_newest_entries() {
    local env_dir output state_dir
    env_dir="$(mktemp -d)"
    state_dir="$env_dir/home/.local/state/mac-dotfiles"
    create_safe_update "$env_dir" "20260101-120000"
    create_safe_update "$env_dir" "20260102-120000"
    create_safe_update "$env_dir" "20260103-120000"
    create_rollback "$env_dir" "20260101-130000-from-20260101-120000"
    create_rollback "$env_dir" "20260103-130000-from-20260103-120000"

    output="$(run_history "$env_dir" --prune --keep 1 --yes)"

    assert_contains "$output" "Prune plan: 2 safe-update run(s), 1 rollback backup(s)" "prune should report its deletion plan"
    [[ -d "$state_dir/safe-updates/20260103-120000" ]] || fail "newest safe update should be kept"
    [[ ! -e "$state_dir/safe-updates/20260102-120000" ]] || fail "older safe update should be removed"
    [[ -d "$state_dir/rollback-backups/20260103-130000-from-20260103-120000" ]] || fail "newest rollback should be kept"
    [[ ! -e "$state_dir/rollback-backups/20260101-130000-from-20260101-120000" ]] || fail "older rollback should be removed"
}

main() {
    test_history_lists_latest_entries
    test_prune_keeps_newest_entries
    echo "[PASS] history tests completed"
}

main
