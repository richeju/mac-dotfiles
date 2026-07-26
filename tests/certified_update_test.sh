#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPDATE_SCRIPT="$REPO_ROOT/dot_local/bin/executable_mac-dotfiles-certified-update.sh.tmpl"

fail() {
    echo "[FAIL] $1" >&2
    exit 1
}

setup_env() {
    local root
    root="$(mktemp -d)"
    mkdir -p "$root/bin" "$root/source" "$root/home/.local/state/mac-dotfiles/certifications"
    echo good-commit >"$root/current-commit"
    printf '{"schema_version":1,"kind":"mac-dotfiles-certification","commit":"good-commit","overall":"pass"}\n' \
        >"$root/home/.local/state/mac-dotfiles/certifications/latest.json"

    cat >"$root/bin/git" <<'GIT'
#!/usr/bin/env bash
case "$*" in
  *" rev-parse HEAD") cat "$TEST_ROOT/current-commit" ;;
  *" status --porcelain") [[ ! -f "$TEST_ROOT/dirty" ]] || echo " M local-change" ;;
  *" reset --hard "*)
    [[ ! -f "$TEST_ROOT/source-rollback-fails" ]] || exit 1
    commit="${*: -1}"
    echo "$commit" >"$TEST_ROOT/current-commit"
    echo "reset:$commit" >>"$TEST_ROOT/commands.log"
    ;;
  *) exit 1 ;;
esac
GIT
    cat >"$root/bin/chezmoi" <<'CHEZMOI'
#!/usr/bin/env bash
[[ "$*" == "git pull -- --ff-only" ]] || exit 1
echo pull >>"$TEST_ROOT/commands.log"
[[ ! -f "$TEST_ROOT/pull-fails" ]] || exit 1
[[ ! -f "$TEST_ROOT/next-commit" ]] || cp "$TEST_ROOT/next-commit" "$TEST_ROOT/current-commit"
CHEZMOI
    cat >"$root/bin/certify" <<'CERTIFY'
#!/usr/bin/env bash
echo "certify:$*" >>"$TEST_ROOT/commands.log"
[[ ! -f "$TEST_ROOT/certification-fails" ]] || exit 1
commit="$(cat "$TEST_ROOT/current-commit")"
printf '{"schema_version":1,"kind":"mac-dotfiles-certification","commit":"%s","overall":"pass"}\n' "$commit" \
  >"$MAC_DOTFILES_STATE_DIR/certifications/latest.json"
CERTIFY
    cat >"$root/bin/converge" <<'CONVERGE'
#!/usr/bin/env bash
echo "converge:$*:lock=${MAC_DOTFILES_LOCK_HELD:-0}" >>"$TEST_ROOT/commands.log"
[[ ! -f "$TEST_ROOT/convergence-rollback-fails" ]] || exit 3
[[ ! -f "$TEST_ROOT/convergence-fails" ]]
CONVERGE
    chmod +x "$root/bin/"*
    echo "$root"
}

run_update() {
    local root="$1"
    shift
    HOME="$root/home" TEST_ROOT="$root" CHEZMOI_SOURCE_DIR="$root/source" \
        MAC_DOTFILES_STATE_DIR="$root/home/.local/state/mac-dotfiles" \
        MAC_DOTFILES_CERTIFY_SCRIPT="$root/bin/certify" \
        MAC_DOTFILES_CONVERGE_SCRIPT="$root/bin/converge" \
        MAC_DOTFILES_PATH="$root/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
        PATH="$root/bin:/usr/bin:/bin:/usr/sbin:/sbin" bash "$UPDATE_SCRIPT" "$@"
}

test_candidate_is_certified_before_convergence() {
    local root commands state
    root="$(setup_env)"
    echo candidate-commit >"$root/next-commit"
    run_update "$root" run >/dev/null
    commands="$(cat "$root/commands.log")"
    [[ "$commands" == $'pull\ncertify:--skip-live\nconverge:converge --yes:lock=1' ]] ||
        fail "candidate must be pulled, certified, then converged under the shared lock"
    [[ "$(cat "$root/current-commit")" == candidate-commit ]] || fail "successful candidate should remain checked out"
    state="$root/home/.local/state/mac-dotfiles/certified-update-state.json"
    jq -e '.status == "success" and .candidate_commit == "candidate-commit" and .last_known_good == "candidate-commit"' \
        "$state" >/dev/null || fail "success should promote the candidate to last known good"
}

test_failed_certification_never_applies_candidate() {
    local root status state
    root="$(setup_env)"
    echo rejected-commit >"$root/next-commit"
    touch "$root/certification-fails"
    set +e
    run_update "$root" run >/dev/null 2>&1
    status=$?
    set -e
    [[ "$status" -eq 1 ]] || fail "a rejected candidate should fail"
    ! grep -q '^converge:' "$root/commands.log" || fail "a rejected candidate must never be applied"
    grep -Fqx 'reset:good-commit' "$root/commands.log" || fail "source should return to the previous commit"
    [[ "$(jq -r .commit "$root/home/.local/state/mac-dotfiles/certifications/latest.json")" == good-commit ]] ||
        fail "the previous passing certification should be restored"
    state="$root/home/.local/state/mac-dotfiles/certified-update-state.json"
    jq -e '.status == "rejected" and .candidate_commit == "rejected-commit" and .last_known_good == "good-commit"' \
        "$state" >/dev/null || fail "rejection should preserve candidate and last-known-good evidence"
}

test_failed_convergence_rolls_source_back() {
    local root status state
    root="$(setup_env)"
    echo candidate-commit >"$root/next-commit"
    touch "$root/convergence-fails"
    set +e
    run_update "$root" run >/dev/null 2>&1
    status=$?
    set -e
    [[ "$status" -eq 1 ]] || fail "failed convergence should fail the update"
    grep -q '^converge:' "$root/commands.log" || fail "certified candidate should reach convergence"
    [[ "$(cat "$root/current-commit")" == good-commit ]] || fail "failed convergence should restore source"
    state="$root/home/.local/state/mac-dotfiles/certified-update-state.json"
    jq -e '.status == "rolled_back" and .last_known_good == "good-commit"' "$state" >/dev/null ||
        fail "failed convergence should record a completed rollback"
}

test_local_changes_block_fetch() {
    local root status
    root="$(setup_env)"
    touch "$root/dirty"
    set +e
    run_update "$root" run >/dev/null 2>&1
    status=$?
    set -e
    [[ "$status" -eq 1 ]] || fail "dirty source should block automatic update"
    [[ ! -f "$root/commands.log" ]] || fail "dirty source must not be fetched or applied"
    jq -e '.status == "blocked"' "$root/home/.local/state/mac-dotfiles/certified-update-state.json" >/dev/null ||
        fail "blocked source should be recorded"
}

test_incomplete_rollback_has_distinct_status() {
    local root status
    root="$(setup_env)"
    echo candidate-commit >"$root/next-commit"
    touch "$root/convergence-rollback-fails"
    set +e
    run_update "$root" run >/dev/null 2>&1
    status=$?
    set -e
    [[ "$status" -eq 3 ]] || fail "incomplete transactional rollback should retain exit status 3"
    jq -e '.status == "rollback_failed"' "$root/home/.local/state/mac-dotfiles/certified-update-state.json" >/dev/null ||
        fail "incomplete transactional rollback should be recorded"
}

test_matching_commit_skips_recertification() {
    local root
    root="$(setup_env)"
    run_update "$root" run >/dev/null
    ! grep -q '^certify:' "$root/commands.log" || fail "matching passing candidate should not be recertified"
    grep -q '^converge:' "$root/commands.log" || fail "matching candidate should still reconcile drift"
}

test_candidate_is_certified_before_convergence
test_failed_certification_never_applies_candidate
test_failed_convergence_rolls_source_back
test_local_changes_block_fetch
test_incomplete_rollback_has_distinct_status
test_matching_commit_skips_recertification
echo "[PASS] certified update tests completed"
