#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WATCHDOG_SCRIPT="$REPO_ROOT/dot_local/bin/executable_mac-dotfiles-watchdog.sh.tmpl"

fail() {
    echo "[FAIL] $1" >&2
    exit 1
}

setup_env() {
    local root="$1" now="$2"
    mkdir -p "$root/home/.local/bin" "$root/state/certifications" "$root/state/recovery-snapshots" "$root/source" "$root/bin"
    cat >"$root/home/.local/bin/mac-dotfiles-converge.sh" <<'ENGINE'
#!/usr/bin/env bash
if [[ -f "$WATCHDOG_TEST_ROOT/drift" || "$(umask)" != "0022" ]]; then
  echo '{"drift":true}'
else
  echo '{"drift":false}'
fi
ENGINE
    cat >"$root/bin/git" <<'GIT'
#!/usr/bin/env bash
echo "${WATCHDOG_TEST_CURRENT_COMMIT:-test-commit}"
GIT
    cat >"$root/bin/osascript" <<'OSASCRIPT'
#!/usr/bin/env bash
echo "$*" >>"$WATCHDOG_TEST_ROOT/notifications.log"
cat >/dev/null
OSASCRIPT
    cat >"$root/bin/stat" <<'STAT'
#!/usr/bin/env bash
if [[ "$1" == "-f" ]]; then
  echo "gnu-stat-probe-output"
  exit 1
fi
if [[ "$1" == "-c" ]]; then
  echo "$MAC_DOTFILES_WATCHDOG_NOW"
fi
STAT
    chmod +x "$root/home/.local/bin/mac-dotfiles-converge.sh" "$root/bin/git" "$root/bin/osascript" "$root/bin/stat"
    echo '{"schema_version":1,"kind":"mac-dotfiles-certification","commit":"test-commit","overall":"pass"}' >"$root/state/certifications/latest.json"
    echo snapshot >"$root/state/recovery-snapshots/mac-dotfiles-test.tar.gz"
    echo '===== 2026-01-01 00:00:00 :: mac-dotfiles maintenance =====' >"$root/state/maintenance.log"
    echo '✅ Maintenance completed' >>"$root/state/maintenance.log"
    echo '{"schema_version":1,"exit_status":0}' >"$root/state/maintenance-status.json"
    : >"$root/notifications.log"
}

run_watchdog() {
    local root="$1" now="$2"
    shift 2
    HOME="$root/home" WATCHDOG_TEST_ROOT="$root" MAC_DOTFILES_STATE_DIR="$root/state" \
        MAC_DOTFILES_PATH="$root/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
        CHEZMOI_SOURCE_DIR="$root/source" \
        MAC_DOTFILES_CONVERGE_SCRIPT="$root/home/.local/bin/mac-dotfiles-converge.sh" \
        MAC_DOTFILES_WATCHDOG_NOW="$now" MAC_DOTFILES_WATCHDOG_COOLDOWN_SECONDS=60 \
        bash "$WATCHDOG_SCRIPT" "$@"
}

test_stale_certification_commit_warns() {
    local root now
    root="$(mktemp -d)"
    now="$(date '+%s')"
    setup_env "$root" "$now"
    jq '.commit = "old-commit"' "$root/state/certifications/latest.json" >"$root/certification.json"
    mv "$root/certification.json" "$root/state/certifications/latest.json"

    run_watchdog "$root" "$now" run --no-notify >/dev/null
    [[ "$(jq -r '.status' "$root/state/watchdog/state.json")" == "warning" ]] ||
        fail "a certification for another commit should warn"
    jq -e '.checks[] | select(.name == "certification" and .detail == "certification does not match current commit")' \
        "$root/state/watchdog/state.json" >/dev/null || fail "commit mismatch should be explicit"
}

test_persisted_maintenance_failure_survives_manual_run() {
    local root now
    root="$(mktemp -d)"
    now="$(date '+%s')"
    setup_env "$root" "$now"
    echo '{"schema_version":1,"exit_status":1}' >"$root/state/maintenance-status.json"

    run_watchdog "$root" "$now" run --no-notify >/dev/null 2>&1 || true
    [[ "$(jq -r '.status' "$root/state/watchdog/state.json")" == "critical" ]] ||
        fail "a persisted maintenance failure should remain critical"
    jq -e '.checks[] | select(.name == "maintenance" and .detail == "maintenance exited with status 1")' \
        "$root/state/watchdog/state.json" >/dev/null || fail "persisted maintenance failure should be explicit"
}

test_transitions_and_cooldown() {
    local root now state notifications
    root="$(mktemp -d)"
    now="$(date '+%s')"
    setup_env "$root" "$now"

    run_watchdog "$root" "$now" run --json >/dev/null
    state="$(run_watchdog "$root" "$now" status --json)"
    [[ "$(jq -r '.status' <<<"$state")" == "healthy" ]] || fail "healthy fixture should report healthy"
    [[ ! -s "$root/notifications.log" ]] || fail "initial healthy state should remain silent"

    touch "$root/drift"
    run_watchdog "$root" "$now" run --json >/dev/null 2>&1 || true
    [[ "$(jq -r '.status' "$root/state/watchdog/state.json")" == "critical" ]] || fail "drift should be critical"
    notifications="$(wc -l <"$root/notifications.log" | tr -d ' ')"
    [[ "$notifications" -eq 1 ]] || fail "transition to critical should notify once"

    run_watchdog "$root" "$((now + 30))" run --json >/dev/null 2>&1 || true
    [[ "$(wc -l <"$root/notifications.log" | tr -d ' ')" -eq 1 ]] || fail "cooldown should suppress duplicate alerts"
    run_watchdog "$root" "$((now + 61))" run --json >/dev/null 2>&1 || true
    [[ "$(wc -l <"$root/notifications.log" | tr -d ' ')" -eq 2 ]] || fail "expired cooldown should repeat unresolved alerts"

    rm "$root/drift"
    run_watchdog "$root" "$((now + 62))" run --json >/dev/null
    [[ "$(wc -l <"$root/notifications.log" | tr -d ' ')" -eq 3 ]] || fail "recovery to healthy should notify"
}

test_manual_notification() {
    local root now
    root="$(mktemp -d)"
    now="$(date '+%s')"
    setup_env "$root" "$now"
    run_watchdog "$root" "$now" test warning >/dev/null
    grep -Fq 'mac-dotfiles — warning' "$root/notifications.log" || fail "test command should send the requested notification"
}

test_transitions_and_cooldown
test_stale_certification_commit_warns
test_persisted_maintenance_failure_survives_manual_run
test_manual_notification
echo "[PASS] watchdog tests completed"
