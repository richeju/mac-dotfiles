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
    if [[ -f "$TEST_ROOT/noncompliant" ]]; then exit 1; else echo 600; fi
    ;;
  "read com.apple.screensaver askForPassword") echo 1 ;;
  "read com.apple.screensaver askForPasswordDelay") echo 0 ;;
  "read /Library/Preferences/com.apple.loginwindow autoLoginUser") exit 1 ;;
  "read /Library/Preferences/com.apple.loginwindow GuestEnabled")
    if [[ -f "$TEST_ROOT/noncompliant" ]]; then echo 1; else echo 0; fi
    ;;
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

test_catalog_is_versioned_and_unique
test_passing_audit_persists_evidence
test_noncompliance_is_advisory_and_actionable
test_non_macos_is_not_applicable
test_other_macos_major_is_not_applicable
test_explain_maps_rule_to_nist_controls
echo "[PASS] compliance tests completed"
