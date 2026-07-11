#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MIGRATOR="$REPO_ROOT/dot_local/bin/executable_mac-dotfiles-migrate.sh.tmpl"

fail() {
    echo "[FAIL] $1" >&2
    exit 1
}

setup_env() {
    local root
    root="$(mktemp -d)"
    mkdir -p "$root/home/.config/chezmoi" "$root/source/migrations"
    cp "$REPO_ROOT"/migrations/*.sh "$root/source/migrations/"
    cat >"$root/home/.config/chezmoi/chezmoi.toml" <<'CONFIG'
[data]
name = "Test"
email = "test@example.com"

[data.maintenance]
hour = 4
CONFIG
    echo "$root"
}

run_migrator() {
    local root="$1"
    shift
    HOME="$root/home" CHEZMOI_SOURCE_DIR="$root/source" \
        MAC_DOTFILES_STATE_DIR="$root/home/.local/state/mac-dotfiles" \
        MAC_DOTFILES_CONFIG_FILE="$root/home/.config/chezmoi/chezmoi.toml" \
        PATH="/usr/bin:/bin:/usr/sbin:/sbin" bash "$MIGRATOR" "$@"
}

test_plan_is_read_only_and_json_is_valid() {
    local root output
    root="$(setup_env)"
    output="$(run_migrator "$root" plan --json)"
    printf '%s' "$output" | jq -e '.current == 0 and .desired == 2 and (.pending | length) == 2' >/dev/null ||
        fail "migration plan should emit strict JSON"
    [[ ! -e "$root/home/.local/state/mac-dotfiles/schema-version" ]] || fail "plan must not create migration state"
    ! grep -Fq 'profile =' "$root/home/.config/chezmoi/chezmoi.toml" || fail "plan must not edit config"
}

test_apply_is_ordered_and_idempotent() {
    local root output
    root="$(setup_env)"
    output="$(run_migrator "$root" apply)"
    [[ "$(cat "$root/home/.local/state/mac-dotfiles/schema-version")" == "2" ]] || fail "schema should advance to version 2"
    grep -Fq 'profile = "full"' "$root/home/.config/chezmoi/chezmoi.toml" || fail "migration 1 should initialize profile"
    [[ -d "$root/home/.local/state/mac-dotfiles/transactions" ]] || fail "migration 2 should create state layout"
    [[ "$(grep -c '^=====' "$root/home/.local/state/mac-dotfiles/migrations.log")" -eq 2 ]] || fail "each migration should be logged once"

    output="$(run_migrator "$root" apply)"
    [[ "$output" == *"already up to date"* ]] || fail "second migration apply should be a no-op"
    [[ "$(grep -c '^=====' "$root/home/.local/state/mac-dotfiles/migrations.log")" -eq 2 ]] || fail "migrations must not rerun"
    run_migrator "$root" check || fail "check should pass after migration"
}

test_apply_respects_operation_lock() {
    local root lock status
    root="$(setup_env)"
    lock="$root/home/.local/state/mac-dotfiles/operation.lock"
    mkdir -p "$lock"
    echo "$$" >"$lock/pid"
    set +e
    run_migrator "$root" apply >/dev/null 2>&1
    status=$?
    set -e
    [[ "$status" -eq 1 ]] || fail "migration should refuse a concurrent operation"
}

test_plan_is_read_only_and_json_is_valid
test_apply_is_ordered_and_idempotent
test_apply_respects_operation_lock
echo "[PASS] migration tests completed"
