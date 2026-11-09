#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAUNCHER_SCRIPT="$REPO_ROOT/dot_local/bin/executable_mac-dotfiles.sh.tmpl"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mac-dotfiles-dispatch-test.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
HOME_DIR="$WORK_DIR/home with spaces"
SOURCE_DIR="$WORK_DIR/source with spaces"
CALLS_FILE="$WORK_DIR/calls"
EXPECTED_FILE="$WORK_DIR/expected"
ARGUMENTS=(--output 'path with spaces' '' '*' 'a"b' 'back\slash' --)
mkdir -p "$HOME_DIR/.local/bin" "$SOURCE_DIR" "$WORK_DIR/bin"

fail() {
    echo "[FAIL] $1" >&2
    exit 1
}

cat >"$WORK_DIR/helper" <<'HELPER'
#!/usr/bin/env bash
name="${0##*/}"
printf '%s\0' "$name" "$@" >>"$CALLS_FILE"
if [[ "$name" == "${FAIL_TOOL:-}" ]]; then
    exit 23
fi
[[ "$name" != "mac-dotfiles-report.sh" ]] || echo "report content"
HELPER
chmod +x "$WORK_DIR/helper"
for name in safe-update certified-update compliance rollback history maintenance converge migrate certify recovery watchdog report; do
    cp "$WORK_DIR/helper" "$HOME_DIR/.local/bin/mac-dotfiles-$name.sh"
done
for name in install doctor; do
    cp "$WORK_DIR/helper" "$SOURCE_DIR/$name.sh"
done
cp "$WORK_DIR/helper" "$WORK_DIR/bin/chezmoi"

run_launcher() {
    HOME="$HOME_DIR" CHEZMOI_SOURCE_DIR="$SOURCE_DIR" \
        PATH="$WORK_DIR/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
        CALLS_FILE="$CALLS_FILE" FAIL_TOOL="${FAIL_TOOL:-}" \
        bash "$LAUNCHER_SCRIPT" "$@"
}

expect_call() {
    : >"$CALLS_FILE"
    printf '%s\0' "$@" >"$EXPECTED_FILE"
}

assert_calls() {
    cmp -s "$EXPECTED_FILE" "$CALLS_FILE" || fail "$1: helper or argument boundaries changed"
}

assert_forwarded() {
    local command="$1" helper="$2"
    shift 2
    expect_call "$helper" "$@" "${ARGUMENTS[@]}"
    run_launcher "$command" "${ARGUMENTS[@]}" >/dev/null
    assert_calls "$command"

    local status=0
    FAIL_TOOL="$helper" run_launcher "$command" "${ARGUMENTS[@]}" >/dev/null 2>&1 || status=$?
    [[ "$status" -eq 23 ]] || fail "$command should preserve the helper exit status"
}

assert_fixed() {
    local command="$1"
    shift
    expect_call "$@"
    run_launcher "$command" "${ARGUMENTS[@]}" >/dev/null
    assert_calls "$command"
}

for name in safe-update certified-update compliance rollback history maintenance migrate certify recovery; do
    assert_forwarded "$name" "mac-dotfiles-$name.sh"
done
for name in profile plan drift converge validate transactions; do
    assert_forwarded "$name" mac-dotfiles-converge.sh "$name"
done
assert_forwarded tx-rollback mac-dotfiles-converge.sh rollback
assert_forwarded status mac-dotfiles-watchdog.sh status
assert_forwarded watch mac-dotfiles-watchdog.sh
assert_forwarded watchdog mac-dotfiles-watchdog.sh
assert_forwarded doctor doctor.sh
assert_fixed verify install.sh --verify
assert_fixed explain doctor.sh --explain
assert_fixed update mac-dotfiles-certified-update.sh run
assert_fixed raw-update chezmoi update --apply
assert_fixed diff chezmoi diff

for command in repair reconcile; do
    expect_call mac-dotfiles-certified-update.sh run
    printf '%s\0' doctor.sh --fix mac-dotfiles-report.sh >>"$EXPECTED_FILE"
    run_launcher "$command" "$WORK_DIR/repair report.md" >/dev/null
    assert_calls "$command"
    [[ "$(cat "$WORK_DIR/repair report.md")" == 'report content' ]] || fail "repair report missing"
done
expect_call mac-dotfiles-report.sh
run_launcher report "$WORK_DIR/report with spaces.md" >/dev/null
assert_calls report
[[ "$(cat "$WORK_DIR/report with spaces.md")" == 'report content' ]] || fail "report missing"

# A failed certified update must not fall through to doctor or reporting.
expect_call mac-dotfiles-certified-update.sh run
status=0
FAIL_TOOL=mac-dotfiles-certified-update.sh run_launcher repair >/dev/null 2>&1 || status=$?
[[ "$status" -eq 23 ]] || fail "repair should stop on a failed update"
assert_calls 'failed repair'

# Menu actions must use the same routes as their CLI equivalents.
for choice in 3 4 5 6 8 9 10 11 12 14 16 17 18 19 20; do
    case "$choice" in
        3) expect_call mac-dotfiles-safe-update.sh ;;
        4) expect_call mac-dotfiles-rollback.sh ;;
        5) expect_call mac-dotfiles-history.sh ;;
        6) expect_call mac-dotfiles-certified-update.sh run ;;
        8) expect_call doctor.sh ;;
        9) expect_call doctor.sh --explain ;;
        10) expect_call mac-dotfiles-maintenance.sh ;;
        11) expect_call chezmoi diff ;;
        12) expect_call mac-dotfiles-converge.sh plan ;;
        14) expect_call mac-dotfiles-converge.sh converge ;;
        16) expect_call mac-dotfiles-migrate.sh plan ;;
        17) expect_call mac-dotfiles-certify.sh ;;
        18) expect_call mac-dotfiles-recovery.sh list ;;
        19) expect_call mac-dotfiles-watchdog.sh status ;;
        20) expect_call mac-dotfiles-compliance.sh audit ;;
    esac
    printf '%s\n\n0\n' "$choice" | run_launcher menu >/dev/null
    assert_calls "menu $choice"
done
expect_call mac-dotfiles-converge.sh profile list
printf '%s\0' mac-dotfiles-converge.sh profile set gaming >>"$EXPECTED_FILE"
printf '15\ngaming\n\n0\n' | run_launcher menu >/dev/null
assert_calls 'profile menu'
expect_call mac-dotfiles-converge.sh drift
printf '13\n\n0\n' | FAIL_TOOL=mac-dotfiles-converge.sh run_launcher menu >/dev/null
assert_calls 'drift menu must remain usable after nonzero status'

for command in help -h --help; do
    : >"$CALLS_FILE"
    run_launcher "$command" >/dev/null
    [[ ! -s "$CALLS_FILE" ]] || fail "help should not execute a helper"
done
: >"$CALLS_FILE"
status=0
run_launcher ../unexpected >/dev/null 2>&1 || status=$?
[[ "$status" -eq 2 && ! -s "$CALLS_FILE" ]] || fail "unknown commands must not execute helpers"
rm "$HOME_DIR/.local/bin/mac-dotfiles-history.sh"
status=0
run_launcher history >/dev/null 2>&1 || status=$?
[[ "$status" -eq 1 ]] || fail "missing helper should return 1"

echo "[PASS] launcher dispatch, argument boundaries, menu parity and exit statuses"
