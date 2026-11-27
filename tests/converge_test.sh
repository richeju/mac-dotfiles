#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENGINE="$REPO_ROOT/dot_local/bin/executable_mac-dotfiles-converge.sh.tmpl"

fail() {
    echo "[FAIL] $1" >&2
    exit 1
}

assert_contains() {
    [[ "$1" == *"$2"* ]] || fail "$3 (missing: $2)"
}

setup_env() {
    local root
    root="$(mktemp -d)"
    mkdir -p "$root/home/.config/chezmoi" "$root/home/.local/state/mac-dotfiles" \
        "$root/home/.local/bin" "$root/source" "$root/bin"
    cp "$REPO_ROOT/dot_Brewfile" "$root/source/"
    cat >"$root/home/.config/chezmoi/chezmoi.toml" <<'CONFIG'
[data]
name = "Test"
email = "test@example.com"
profile = "full"
CONFIG
    echo original >"$root/home/.gitconfig"

    cp "$root/source/dot_Brewfile" "$root/home/.Brewfile"
    write_mocks "$root"
    echo "$root"
}

write_mocks() {
    local root="$1"
    cat >"$root/bin/chezmoi" <<'MOCK'
#!/usr/bin/env bash
case "$1" in
  diff)
    [[ ! -f "$TEST_ROOT/inspect-error" ]] || exit 1
    [[ ! -f "$TEST_ROOT/dirty" ]] || echo "mock dotfile drift"
    ;;
  managed)
    echo "$HOME/.Brewfile"
    echo "$HOME/.gitconfig"
    echo "$HOME/.local/generated-by-apply"
    ;;
  apply)
    echo "chezmoi apply" >>"$TEST_ROOT/commands.log"
    echo changed >"$HOME/.gitconfig"
    mkdir -p "$HOME/.local"
    echo generated >"$HOME/.local/generated-by-apply"
    cp "$CHEZMOI_SOURCE_DIR/dot_Brewfile" "$HOME/.Brewfile"
    rm -f "$TEST_ROOT/dirty"
    [[ ! -f "$TEST_ROOT/chezmoi-fail" ]]
    ;;
esac
MOCK
    cat >"$root/bin/brew" <<'MOCK'
#!/usr/bin/env bash
if [[ "$1" == "bundle" && "$2" == "check" ]]; then
  if [[ -f "$TEST_ROOT/brew-missing" ]]; then
    echo "missing package"
    exit 1
  fi
  exit 0
fi
if [[ "$1" == "bundle" && "$2" == "install" ]]; then
  echo "brew bundle install" >>"$TEST_ROOT/commands.log"
  if [[ -f "$TEST_ROOT/rollback-corrupt" ]]; then
    label="$(awk -F '\t' -v target="$HOME/.gitconfig" '$2 == target {print $1}' "$MAC_DOTFILES_STATE_DIR/transactions/$MAC_DOTFILES_RUN_ID/targets.tsv")"
    rm -f "$MAC_DOTFILES_STATE_DIR/transactions/$MAC_DOTFILES_RUN_ID/backups/$label"
  fi
  [[ ! -f "$TEST_ROOT/brew-fail" ]] || exit 1
  exit 0
fi
if [[ "$1" == "bundle" && "$2" == "cleanup" ]]; then
  exit 0
fi
if [[ "$1" == "list" ]]; then
  stage=before
  [[ ! -f "$TEST_ROOT/commands.log" ]] || stage=after
  kind="$2"
  outputs="$TEST_ROOT/$stage-${kind#--}"
  [[ ! -f "$outputs" ]] || cat "$outputs"
  [[ ! -f "$outputs-fails" ]]
  exit $?
fi
if [[ "$1" == "uninstall" || "$1" == "autoremove" ]]; then
  echo "brew $* (no-autoremove=${HOMEBREW_NO_AUTOREMOVE:-0})" >>"$TEST_ROOT/commands.log"
fi
exit 0
MOCK
    cat >"$root/bin/plutil" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK
    cat >"$root/bin/launchctl" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK
    for helper in \
        mac-dotfiles-configure-dock.sh \
        mac-dotfiles-configure-finder-and-inputs.sh \
        mac-dotfiles-harden-macos-baseline.sh; do
        cat >"$root/home/.local/bin/$helper" <<'MOCK'
#!/usr/bin/env bash
echo "preference-helper:${0##*/}" >>"$TEST_ROOT/commands.log"
MOCK
    done
    chmod +x "$root/bin/"*
    chmod +x "$root/home/.local/bin/"*
}

run_engine() {
    local root="$1"
    shift
    HOME="$root/home" TEST_ROOT="$root" CHEZMOI_SOURCE_DIR="$root/source" \
        MAC_DOTFILES_CONFIG_FILE="$root/home/.config/chezmoi/chezmoi.toml" \
        MAC_DOTFILES_STATE_DIR="$root/home/.local/state/mac-dotfiles" \
        MAC_DOTFILES_RUN_ID="20260101-120000-test" \
        PATH="$root/bin:/usr/bin:/bin:/usr/sbin:/sbin" bash "$ENGINE" "$@"
}

test_plan_is_read_only_and_drift_has_stable_codes() {
    local root output status before
    root="$(setup_env)"
    before="$(cat "$root/home/.gitconfig")"
    output="$(run_engine "$root" plan)"
    assert_contains "$output" "already converged" "clean plan should report no changes"
    [[ "$(cat "$root/home/.gitconfig")" == "$before" ]] || fail "plan must not mutate files"
    [[ ! -d "$root/home/.local/state/mac-dotfiles/transactions" ]] || fail "plan must not create transactions"

    output="$(run_engine "$root" plan --json)"
    printf '%s' "$output" | jq -e '.schema_version == 1 and .drift == false and .profile == "full"' >/dev/null ||
        fail "plan --json should emit strict structured JSON"

    touch "$root/dirty"
    set +e
    output="$(run_engine "$root" drift 2>&1)"
    status=$?
    set -e
    [[ "$status" -eq 1 ]] || fail "drift should exit 1 when changes exist"
    assert_contains "$output" "changes are available" "drift should explain detected changes"

    set +e
    output="$(run_engine "$root" drift --json)"
    status=$?
    set -e
    [[ "$status" -eq 1 ]] || fail "JSON drift should preserve drift exit code"
    printf '%s' "$output" | jq -e '.drift == true and .actions.dotfiles == true' >/dev/null ||
        fail "drift --json should remain strict JSON"

    touch "$root/inspect-error"
    set +e
    run_engine "$root" drift >/dev/null 2>&1
    status=$?
    set -e
    [[ "$status" -eq 2 ]] || fail "drift should exit 2 when inspection fails"
}

test_converge_success_records_transaction() {
    local root output status_file
    root="$(setup_env)"
    touch "$root/dirty"
    output="$(run_engine "$root" converge --yes)"
    assert_contains "$output" "Convergence completed" "converge should complete"
    status_file="$root/home/.local/state/mac-dotfiles/transactions/20260101-120000-test/status.env"
    grep -Fqx "status=success" "$status_file" || fail "transaction should be marked success"
    jq -e '.schema_version == 1 and .status == "success"' "${status_file%/*}/state.json" >/dev/null ||
        fail "transaction should expose versioned JSON state"
    grep -Fq "chezmoi apply" "$root/commands.log" || fail "converge should apply dotfiles"
    grep -Fq "brew bundle install" "$root/commands.log" || fail "converge should reconcile packages"
    grep -Fq "preference-helper:mac-dotfiles-configure-dock.sh" "$root/commands.log" ||
        fail "converge should apply Dock preferences"
    grep -Fq "preference-helper:mac-dotfiles-configure-finder-and-inputs.sh" "$root/commands.log" ||
        fail "converge should apply Finder/input preferences"
    grep -Fq "preference-helper:mac-dotfiles-harden-macos-baseline.sh" "$root/commands.log" ||
        fail "converge should apply the hardening baseline"
}

test_failure_restores_files_and_absent_targets() {
    local root status status_file
    root="$(setup_env)"
    touch "$root/dirty" "$root/brew-fail"
    set +e
    run_engine "$root" converge --yes >/dev/null 2>&1
    status=$?
    set -e
    [[ "$status" -eq 1 ]] || fail "failed converge with successful rollback should exit 1"
    [[ "$(cat "$root/home/.gitconfig")" == "original" ]] || fail "rollback should restore changed files"
    [[ ! -e "$root/home/.local/generated-by-apply" ]] || fail "rollback should remove targets absent before"
    status_file="$root/home/.local/state/mac-dotfiles/transactions/20260101-120000-test/status.env"
    grep -Fqx "status=rolled_back" "$status_file" || fail "transaction should record rollback"
}

test_converge_installs_the_same_brewfile_on_an_existing_mac() {
    local root output
    root="$(setup_env)"
    printf '[data]\nprofile = "developer"\n' >"$root/home/.config/chezmoi/chezmoi.toml"
    printf 'brew "go"\n' >"$root/home/.Brewfile"
    output="$(run_engine "$root" plan --json)"
    jq -e '.drift and .actions.brewfile' <<<"$output" >/dev/null || fail "old Brewfile should show drift"
    run_engine "$root" converge --yes >/dev/null
    cmp "$root/home/.Brewfile" "$root/source/dot_Brewfile" || fail "old configurations must receive the same Brewfile"
    ! grep -Eq 'uninstall|autoremove|cleanup' "$root/commands.log" || fail "migration must preserve existing packages"
}

test_missing_inventory_stops_convergence() {
    local root kind
    for kind in cask formula; do
        root="$(setup_env)"
        touch "$root/dirty" "$root/before-$kind-fails"
        echo truncated-output >"$root/before-$kind"
        if run_engine "$root" converge --yes >"$root/output" 2>&1; then
            fail "incomplete $kind inventory must fail convergence"
        fi
        [[ ! -f "$root/commands.log" ]] || fail "inventory failure must stop before applying changes"
        jq -e '.status == "snapshot_failed"' "$root/home/.local/state/mac-dotfiles/transactions/20260101-120000-test/state.json" >/dev/null ||
            fail "failed inventory must produce a visible transaction state"
        if run_engine "$root" rollback latest --yes >"$root/output" 2>&1; then
            fail "incomplete inventory must not create a restorable snapshot"
        fi
    done
}

test_package_rollback_uses_complete_inventories() {
    local root status
    root="$(setup_env)"
    touch "$root/dirty" "$root/brew-fail"
    echo preexisting-formula >"$root/before-formula"
    echo preexisting-app >"$root/before-cask"
    printf 'added-formula\npreexisting-formula\n' >"$root/after-formula"
    printf 'added-app\npreexisting-app\n' >"$root/after-cask"
    status=0
    run_engine "$root" converge --yes >/dev/null 2>&1 || status=$?
    [[ "$status" == 1 ]] || fail "expected successful rollback after failed install"
    grep -Fqx 'brew uninstall --formula added-formula (no-autoremove=1)' "$root/commands.log" || fail "expected rollback of newly requested formula"
    grep -Fqx 'brew uninstall --cask added-app (no-autoremove=1)' "$root/commands.log" || fail "expected rollback of newly installed app"
    ! grep -Eq 'uninstall.*preexisting|^brew autoremove' "$root/commands.log" || fail "rollback must only remove newly installed packages"

    root="$(setup_env)"
    touch "$root/dirty" "$root/brew-fail" "$root/after-cask-fails"
    echo added-formula >"$root/after-formula"
    status=0
    run_engine "$root" converge --yes >/dev/null 2>&1 || status=$?
    [[ "$status" == 3 ]] || fail "failed rollback inventory must report incomplete rollback"
    ! grep -Eq 'uninstall|autoremove' "$root/commands.log" || fail "both post-install inventories must succeed before removing any package"
}

test_incomplete_rollback_returns_distinct_status() {
    local root status state
    root="$(setup_env)"
    touch "$root/dirty" "$root/brew-fail" "$root/rollback-corrupt"
    set +e
    run_engine "$root" converge --yes >/dev/null 2>&1
    status=$?
    set -e
    [[ "$status" -eq 3 ]] || fail "incomplete rollback should exit 3"
    state="$root/home/.local/state/mac-dotfiles/transactions/20260101-120000-test/state.json"
    jq -e '.status == "rollback_failed"' "$state" >/dev/null || fail "rollback failure should be recorded"
}

test_live_lock_refuses_second_convergence() {
    local root status lock
    root="$(setup_env)"
    touch "$root/dirty"
    lock="$root/home/.local/state/mac-dotfiles/operation.lock"
    mkdir -p "$lock"
    echo "$$" >"$lock/pid"
    set +e
    run_engine "$root" converge --yes >/dev/null 2>&1
    status=$?
    set -e
    [[ "$status" -eq 1 ]] || fail "concurrent convergence should be refused"
}

test_inherited_lock_is_preserved() {
    local root lock
    root="$(setup_env)"
    touch "$root/dirty"
    lock="$root/home/.local/state/mac-dotfiles/operation.lock"
    mkdir -p "$lock"
    echo "$$" >"$lock/pid"
    MAC_DOTFILES_LOCK_HELD=1 run_engine "$root" converge --yes >/dev/null
    [[ -f "$lock/pid" ]] || fail "nested convergence must preserve its orchestrator's lock"
}

test_manual_transaction_rollback_restores_snapshot() {
    local root
    root="$(setup_env)"
    touch "$root/dirty"
    run_engine "$root" converge --yes >/dev/null
    [[ "$(cat "$root/home/.gitconfig")" == "changed" ]] || fail "fixture should be changed after converge"

    run_engine "$root" rollback latest --yes >/dev/null
    [[ "$(cat "$root/home/.gitconfig")" == "original" ]] || fail "manual transaction rollback should restore snapshot"
    [[ ! -e "$root/home/.local/generated-by-apply" ]] || fail "manual rollback should remove created targets"
    find "$root/home/.local/state/mac-dotfiles/transaction-rollback-backups" -type f -name 'target-*' | grep -q . ||
        fail "manual rollback should preserve the current files first"
}

test_plan_is_read_only_and_drift_has_stable_codes
test_converge_success_records_transaction
test_failure_restores_files_and_absent_targets
test_converge_installs_the_same_brewfile_on_an_existing_mac
test_missing_inventory_stops_convergence
test_package_rollback_uses_complete_inventories
test_incomplete_rollback_returns_distinct_status
test_live_lock_refuses_second_convergence
test_inherited_lock_is_preserved
test_manual_transaction_rollback_restores_snapshot
echo "[PASS] convergence tests completed"
