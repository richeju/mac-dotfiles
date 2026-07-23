#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BREW_MAINTENANCE_SCRIPT="$REPO_ROOT/dot_local/bin/executable_mac-dotfiles-brew-maintenance.sh.tmpl"

fail() {
    echo "[FAIL] $1" >&2
    exit 1
}

test_cask_failure_does_not_fail_formula_maintenance() {
    local root output status
    root="$(mktemp -d)"
    mkdir -p "$root/bin" "$root/cache"
    cat >"$root/bin/brew" <<'SCRIPT'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$BREW_CALLS"
case "$*" in
    "upgrade --cask --greedy") exit 1 ;;
    "--cache") echo "$BREW_CACHE" ;;
esac
SCRIPT
    chmod +x "$root/bin/brew"

    set +e
    output="$(BREW_CALLS="$root/calls" BREW_CACHE="$root/cache" PATH="$root/bin:/usr/bin:/bin" \
        bash "$BREW_MAINTENANCE_SCRIPT" 2>&1)"
    status=$?
    set -e

    [[ "$status" -eq 0 ]] || fail "a cask failure should not fail maintenance"
    grep -Fqx 'upgrade --formula' "$root/calls" || fail "formula upgrades should exclude casks"
    ! grep -Fqx 'upgrade' "$root/calls" || fail "maintenance must not run an unscoped brew upgrade"
    grep -Fqx 'upgrade --cask --greedy' "$root/calls" || fail "casks should run in their guarded phase"
    grep -Fqx 'cleanup -s' "$root/calls" || fail "cleanup should continue after a cask failure"
    grep -Fqx 'doctor' "$root/calls" || fail "diagnostics should continue after a cask failure"
    [[ "$output" == *"Some cask upgrades failed"* ]] || fail "cask failures should remain visible as warnings"
}

test_cask_failure_does_not_fail_formula_maintenance
echo "[PASS] Homebrew maintenance tests completed"
