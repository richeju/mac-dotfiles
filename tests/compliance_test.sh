#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPLIANCE_SCRIPT="$REPO_ROOT/dot_local/bin/executable_mac-dotfiles-compliance.sh.tmpl"

fail() {
    echo "[FAIL] $1" >&2
    exit 1
}

setup_env() {
    local root
    root="$(mktemp -d)"
    mkdir -p "$root/bin" "$root/state"

    cat >"$root/bin/fdesetup" <<'MOCK'
#!/usr/bin/env bash
if [[ -f "$TEST_ROOT/noncompliant" ]]; then echo "FileVault is Off."; else echo "FileVault is On."; fi
MOCK
    cat >"$root/bin/firewall" <<'MOCK'
#!/usr/bin/env bash
if [[ "$1" == "--getglobalstate" ]]; then
  if [[ -f "$TEST_ROOT/noncompliant" ]]; then echo "Firewall is disabled. (State = 0)"; else echo "Firewall is enabled. (State = 1)"; fi
elif [[ "$1" == "--getstealthmode" ]]; then
  if [[ -f "$TEST_ROOT/noncompliant" ]]; then echo "Firewall stealth mode is off"; else echo "Firewall stealth mode is on"; fi
fi
MOCK
    cat >"$root/bin/spctl" <<'MOCK'
#!/usr/bin/env bash
echo "assessments enabled"
MOCK
    cat >"$root/bin/csrutil" <<'MOCK'
#!/usr/bin/env bash
echo "System Integrity Protection status: enabled."
MOCK
    cat >"$root/bin/defaults" <<'MOCK'
#!/usr/bin/env bash
case "$*" in
  "read /Library/Preferences/com.apple.SoftwareUpdate CriticalUpdateInstall") echo 1 ;;
  "-currentHost read com.apple.screensaver idleTime")
    if [[ -f "$TEST_ROOT/remediated-timeout" ]]; then echo 900
    elif [[ -f "$TEST_ROOT/noncompliant" ]]; then exit 1
    else echo 600
    fi
    ;;
  "-currentHost write com.apple.screensaver idleTime -int 900") touch "$TEST_ROOT/remediated-timeout" ;;
  "-currentHost delete com.apple.screensaver idleTime") rm -f "$TEST_ROOT/remediated-timeout" ;;
  "read com.apple.screensaver askForPassword") echo 1 ;;
  "read com.apple.screensaver askForPasswordDelay") echo 0 ;;
  "read /Library/Preferences/com.apple.loginwindow autoLoginUser") exit 1 ;;
  "read /Library/Preferences/com.apple.loginwindow GuestEnabled")
    if [[ -f "$TEST_ROOT/noncompliant" ]]; then echo 1; else echo 0; fi
    ;;
  *) exit 1 ;;
esac
MOCK
    cat >"$root/bin/sysadminctl" <<'MOCK'
#!/usr/bin/env bash
case "$*" in
  "-guestAccount status")
    if [[ -f "$TEST_ROOT/remediated-guest" || ! -f "$TEST_ROOT/noncompliant" ]]; then
      echo "Guest account disabled."
    else
      echo "Guest account enabled."
    fi
    ;;
  "-guestAccount off")
    [[ ! -f "$TEST_ROOT/fail-guest-off" ]] || exit 1
    touch "$TEST_ROOT/remediated-guest"
    ;;
  "-guestAccount on") rm -f "$TEST_ROOT/remediated-guest" ;;
  *) exit 1 ;;
esac
MOCK
    cat >"$root/bin/softwareupdate" <<'MOCK'
#!/usr/bin/env bash
echo "No new software available."
MOCK
    cat >"$root/bin/launchctl" <<'MOCK'
#!/usr/bin/env bash
if [[ "$*" == "print system/com.apple.timed" ]]; then exit 0; fi
exit 1
MOCK
    cat >"$root/bin/pgrep" <<'MOCK'
#!/usr/bin/env bash
exit 1
MOCK
    cat >"$root/bin/sw_vers" <<'MOCK'
#!/usr/bin/env bash
echo "26.5.2"
MOCK
    cat >"$root/bin/uname" <<'MOCK'
#!/usr/bin/env bash
echo "Darwin"
MOCK
    chmod +x "$root/bin/"*
    echo "$root"
}

run_compliance() {
    local root="$1"
    shift
    HOME="$root/home" TEST_ROOT="$root" CHEZMOI_SOURCE_DIR="$REPO_ROOT" \
        MAC_DOTFILES_STATE_DIR="$root/state" MAC_DOTFILES_PLATFORM=Darwin \
        MAC_DOTFILES_FIREWALL_CMD="$root/bin/firewall" \
        MAC_DOTFILES_SYSADMINCTL_CMD="$root/bin/sysadminctl" MAC_DOTFILES_DEFAULTS_CMD="$root/bin/defaults" \
        MAC_DOTFILES_NO_SUDO=1 \
        MAC_DOTFILES_PATH="$root/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
        bash "$COMPLIANCE_SCRIPT" "$@"
}

test_catalog_is_versioned_and_unique() {
    local root output
    root="$(setup_env)"
    output="$(run_compliance "$root" validate-catalog)"
    [[ "$output" == *"16 unique rules"* ]] || fail "catalog should contain the tailored first-pass controls"
}

test_passing_audit_persists_evidence() {
    local root output latest
    root="$(setup_env)"
    output="$(run_compliance "$root" audit --json)"
    jq -e '.schema_version == 1 and .kind == "mac-dotfiles-nist-compliance" and .overall == "pass" and .summary.pass == 16 and (.results | length) == 16' \
        <<<"$output" >/dev/null || fail "passing audit should emit complete JSON evidence"
    latest="$root/state/compliance/latest.json"
    [[ -f "$latest" ]] || fail "latest compliance state should be persisted"
    cmp -s <(printf '%s\n' "$output") "$latest" || fail "printed and persisted attestations should match"
    find "$root/state/compliance/attestations" -type f -name '*.json' | grep -q . ||
        fail "versioned compliance evidence should be retained"
}

test_noncompliance_is_advisory_and_actionable() {
    local root output status plan
    root="$(setup_env)"
    touch "$root/noncompliant"
    set +e
    output="$(run_compliance "$root" audit --json)"
    status=$?
    set -e
    [[ "$status" -eq 1 ]] || fail "non-compliant audit should exit 1"
    jq -e '.overall == "noncompliant" and .summary.fail >= 4 and (.results[] | select(.id == "system_settings_filevault_enforce" and .status == "fail"))' \
        <<<"$output" >/dev/null || fail "failed controls should be explicit"

    set +e
    plan="$(run_compliance "$root" plan --json)"
    status=$?
    set -e
    [[ "$status" -eq 1 ]] || fail "a non-compliant plan should retain audit status"
    jq -e '.actions[] | select(.id == "system_settings_firewall_enable" and .remediation == "manual")' \
        <<<"$plan" >/dev/null || fail "plan should include safe manual guidance"
}

test_non_macos_is_not_applicable() {
    local root output
    root="$(setup_env)"
    output="$(HOME="$root/home" CHEZMOI_SOURCE_DIR="$REPO_ROOT" MAC_DOTFILES_STATE_DIR="$root/state" \
        MAC_DOTFILES_PLATFORM=Linux MAC_DOTFILES_PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin" \
        bash "$COMPLIANCE_SCRIPT" audit --json)"
    jq -e '.overall == "not_applicable" and .summary.not_applicable == 16' <<<"$output" >/dev/null ||
        fail "non-macOS platforms should be explicitly not applicable"
}

test_other_macos_major_is_not_applicable() {
    local root output
    root="$(setup_env)"
    output="$(HOME="$root/home" CHEZMOI_SOURCE_DIR="$REPO_ROOT" MAC_DOTFILES_STATE_DIR="$root/state" \
        MAC_DOTFILES_PLATFORM=Darwin MAC_DOTFILES_OS_VERSION=15.7 \
        MAC_DOTFILES_PATH="$root/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin" \
        bash "$COMPLIANCE_SCRIPT" audit --json)"
    jq -e '.overall == "not_applicable" and .summary.not_applicable == 16' <<<"$output" >/dev/null ||
        fail "a baseline for another macOS major must not claim compliance"
}

test_explain_maps_rule_to_nist_controls() {
    local root output
    root="$(setup_env)"
    output="$(run_compliance "$root" explain os_sip_enable)"
    [[ "$output" == *"CCE-95298-6"* && "$output" == *"SI-7"* && "$output" == *"manual-recovery"* ]] ||
        fail "rule explanation should expose upstream and remediation metadata"
}

test_safe_remediation_requires_preview_or_confirmation() {
    local root output status
    root="$(setup_env)"
    touch "$root/noncompliant"

    output="$(run_compliance "$root" remediate --safe --dry-run)"
    [[ "$output" == *"Set the inactivity timeout to 900 seconds"* && "$output" == *"Disable the macOS guest account"* ]] ||
        fail "safe dry-run should preview both curated changes"
    [[ ! -e "$root/remediated-timeout" && ! -e "$root/remediated-guest" ]] ||
        fail "dry-run must not change settings"
    [[ ! -d "$root/state/compliance/remediations" ]] || fail "dry-run must not create a rollback snapshot"

    set +e
    output="$(run_compliance "$root" remediate --safe 2>&1)"
    status=$?
    set -e
    [[ "$status" -eq 2 && "$output" == *"Re-run with --yes"* ]] ||
        fail "non-interactive remediation should require explicit confirmation"
}

test_failed_safe_remediation_restores_previous_settings() {
    local root output status snapshot
    root="$(setup_env)"
    touch "$root/noncompliant" "$root/fail-guest-off"

    set +e
    output="$(run_compliance "$root" remediate --safe --yes 2>&1)"
    status=$?
    set -e
    [[ "$status" -eq 1 && "$output" == *"previous settings were restored"* ]] ||
        fail "a partial remediation should report its automatic rollback"
    [[ ! -e "$root/remediated-timeout" && ! -e "$root/remediated-guest" ]] ||
        fail "a partial remediation must restore all previous settings"
    snapshot="$(find "$root/state/compliance/remediations" -name state.json -type f | head -1)"
    jq -e '.status == "rolled_back_after_failure"' "$snapshot" >/dev/null ||
        fail "failed remediation evidence should record its rollback"
}

test_safe_remediation_is_verified_and_reversible() {
    local root output snapshot
    root="$(setup_env)"
    touch "$root/noncompliant"

    output="$(run_compliance "$root" remediate --safe --yes)"
    [[ "$output" == *"Safe remediation applied and verified"* ]] || fail "safe remediation should report success"
    [[ -e "$root/remediated-timeout" && -e "$root/remediated-guest" ]] ||
        fail "safe remediation should apply both curated settings"
    snapshot="$(find "$root/state/compliance/remediations" -name state.json -type f | head -1)"
    [[ -f "$snapshot" ]] || fail "safe remediation should save rollback evidence"
    jq -e '.status == "success" and .before.screensaver_idle_time.exists == false and .before.guest_account == "enabled"' \
        "$snapshot" >/dev/null || fail "rollback evidence should preserve previous values"
    jq -e '[.results[] | select((.id == "system_settings_screensaver_timeout_enforce" or .id == "system_settings_guest_account_disable") and .status == "pass")] | length == 2' \
        "$root/state/compliance/latest.json" >/dev/null || fail "safe remediation should re-audit selected controls"

    output="$(run_compliance "$root" rollback latest --dry-run)"
    [[ "$output" == *"Inactivity timeout: unset"* && "$output" == *"Guest account: enabled"* ]] ||
        fail "rollback dry-run should preview the saved values"
    [[ -e "$root/remediated-timeout" && -e "$root/remediated-guest" ]] || fail "rollback dry-run must not change settings"

    output="$(run_compliance "$root" rollback latest --yes)"
    [[ "$output" == *"Previous compliance settings restored"* ]] || fail "confirmed rollback should report success"
    [[ ! -e "$root/remediated-timeout" && ! -e "$root/remediated-guest" ]] ||
        fail "rollback should restore the original settings"
    jq -e '.status == "rolled_back"' "$snapshot" >/dev/null || fail "rollback should update snapshot status"
}

test_catalog_is_versioned_and_unique
test_passing_audit_persists_evidence
test_noncompliance_is_advisory_and_actionable
test_non_macos_is_not_applicable
test_other_macos_major_is_not_applicable
test_explain_maps_rule_to_nist_controls
test_safe_remediation_requires_preview_or_confirmation
test_failed_safe_remediation_restores_previous_settings
test_safe_remediation_is_verified_and_reversible
echo "[PASS] compliance tests completed"
