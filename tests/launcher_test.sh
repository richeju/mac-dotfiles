#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAUNCHER_SCRIPT="$REPO_ROOT/dot_local/bin/executable_mac-dotfiles.sh.tmpl"

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

setup_env() {
    local env_dir
    env_dir="$(mktemp -d)"
    mkdir -p "$env_dir/home/.local/bin" "$env_dir/home/.local/share/chezmoi" "$env_dir/bin"

    cat >"$env_dir/home/.local/share/chezmoi/install.sh" <<'INSTALL'
#!/usr/bin/env bash
if [[ "$1" == "--verify" ]]; then
  echo "verify-called"
fi
INSTALL

    cat >"$env_dir/home/.local/share/chezmoi/doctor.sh" <<'DOCTOR'
#!/usr/bin/env bash
if [[ "${1:-}" == "--explain" ]]; then
  echo "explain-called"
elif [[ "${1:-}" == "--fix" ]]; then
  echo "doctor-fix-called"
else
  echo "doctor-called"
fi
DOCTOR

    cat >"$env_dir/home/.local/bin/mac-dotfiles-report.sh" <<'REPORT'
#!/usr/bin/env bash
echo "report-called"
REPORT

    cat >"$env_dir/home/.local/bin/mac-dotfiles-safe-update.sh" <<'SAFE'
#!/usr/bin/env bash
echo "safe-update-called"
SAFE

    cat >"$env_dir/home/.local/bin/mac-dotfiles-rollback.sh" <<'ROLLBACK'
#!/usr/bin/env bash
printf 'rollback-called'
for arg in "$@"; do
  printf ' %s' "$arg"
done
printf '\n'
ROLLBACK

    cat >"$env_dir/home/.local/bin/mac-dotfiles-history.sh" <<'HISTORY'
#!/usr/bin/env bash
printf 'history-called'
for arg in "$@"; do
  printf ' %s' "$arg"
done
printf '\n'
HISTORY

    cat >"$env_dir/home/.local/bin/mac-dotfiles-maintenance.sh" <<'MAINT'
#!/usr/bin/env bash
echo "maintenance-called"
MAINT

    cat >"$env_dir/home/.local/bin/mac-dotfiles-converge.sh" <<'CONVERGE'
#!/usr/bin/env bash
printf 'converge-engine'
for arg in "$@"; do
  printf ' %s' "$arg"
done
printf '\n'
CONVERGE

    cat >"$env_dir/home/.local/bin/mac-dotfiles-migrate.sh" <<'MIGRATE'
#!/usr/bin/env bash
printf 'migrate-engine %s\n' "$*"
MIGRATE
    cat >"$env_dir/home/.local/bin/mac-dotfiles-certify.sh" <<'CERTIFY'
#!/usr/bin/env bash
printf 'certify-engine %s\n' "$*"
CERTIFY
    cat >"$env_dir/home/.local/bin/mac-dotfiles-recovery.sh" <<'RECOVERY'
#!/usr/bin/env bash
printf 'recovery-engine %s\n' "$*"
RECOVERY

    cat >"$env_dir/bin/chezmoi" <<'CHEZ'
#!/usr/bin/env bash
if [[ "$1" == "update" ]]; then
  printf 'chezmoi'
  for arg in "$@"; do
    printf ' %s' "$arg"
  done
  printf '\n'
elif [[ "$1" == "git" && "$2" == "pull" ]]; then
  printf 'chezmoi git pull -- --ff-only\n'
elif [[ "$1" == "diff" ]]; then
  echo "diff-called"
fi
CHEZ

    cat >"$env_dir/bin/brew" <<'BREW'
#!/usr/bin/env bash
if [[ "$1" == "bundle" ]]; then
  printf 'brew'
  for arg in "$@"; do
    printf ' %s' "$arg"
  done
  printf '\n'
fi
BREW

    chmod +x \
        "$env_dir/home/.local/share/chezmoi/install.sh" \
        "$env_dir/home/.local/share/chezmoi/doctor.sh" \
        "$env_dir/home/.local/bin/mac-dotfiles-report.sh" \
        "$env_dir/home/.local/bin/mac-dotfiles-safe-update.sh" \
        "$env_dir/home/.local/bin/mac-dotfiles-rollback.sh" \
        "$env_dir/home/.local/bin/mac-dotfiles-history.sh" \
        "$env_dir/home/.local/bin/mac-dotfiles-maintenance.sh" \
        "$env_dir/home/.local/bin/mac-dotfiles-converge.sh" \
        "$env_dir/home/.local/bin/mac-dotfiles-migrate.sh" \
        "$env_dir/home/.local/bin/mac-dotfiles-certify.sh" \
        "$env_dir/home/.local/bin/mac-dotfiles-recovery.sh" \
        "$env_dir/bin/chezmoi" \
        "$env_dir/bin/brew"

    echo "$env_dir"
}

run_launcher() {
    local env_dir="$1"
    shift
    HOME="$env_dir/home" PATH="$env_dir/bin:/usr/bin:/bin:/usr/sbin:/sbin" bash "$LAUNCHER_SCRIPT" "$@"
}

test_help() {
    local env_dir output
    env_dir="$(setup_env)"
    output="$(run_launcher "$env_dir" help)"
    assert_contains "$output" "Usage: mac-dotfiles.sh" "help should print usage"
}

test_direct_commands() {
    local env_dir output report_path
    env_dir="$(setup_env)"

    output="$(run_launcher "$env_dir" verify)"
    assert_contains "$output" "verify-called" "verify command should call install --verify"

    output="$(run_launcher "$env_dir" safe-update)"
    assert_contains "$output" "safe-update-called" "safe-update command should call safe update script"

    output="$(run_launcher "$env_dir" rollback latest --dry-run)"
    assert_contains "$output" "rollback-called latest --dry-run" "rollback command should forward its arguments"

    output="$(run_launcher "$env_dir" history --prune --keep 10 --yes)"
    assert_contains "$output" "history-called --prune --keep 10 --yes" "history command should forward its arguments"

    output="$(run_launcher "$env_dir" update)"
    assert_contains "$output" "chezmoi update --apply" "update command should call chezmoi update"

    report_path="$env_dir/home/repair-report.md"
    output="$(run_launcher "$env_dir" repair "$report_path")"
    assert_contains "$output" "chezmoi git pull -- --ff-only" "repair should update the desired-state source"
    assert_contains "$output" "converge-engine converge --yes" "repair should use transactional convergence"
    assert_contains "$output" "doctor-fix-called" "repair should run doctor --fix"
    assert_contains "$output" "Report written to $report_path" "repair should write a report"
    assert_contains "$(cat "$report_path")" "report-called" "repair report should contain report output"

    output="$(run_launcher "$env_dir" explain)"
    assert_contains "$output" "explain-called" "explain command should call doctor --explain"

    report_path="$env_dir/home/report.md"
    output="$(run_launcher "$env_dir" report "$report_path")"
    assert_contains "$output" "Report written to $report_path" "report command should print destination"
    assert_contains "$(cat "$report_path")" "report-called" "report command should write report content"

    output="$(run_launcher "$env_dir" profile set developer)"
    assert_contains "$output" "converge-engine profile set developer" "profile command should route to convergence engine"

    output="$(run_launcher "$env_dir" plan --profile gaming)"
    assert_contains "$output" "converge-engine plan --profile gaming" "plan should forward options"

    output="$(run_launcher "$env_dir" converge --yes)"
    assert_contains "$output" "converge-engine converge --yes" "converge should forward confirmation"

    output="$(run_launcher "$env_dir" tx-rollback latest --yes)"
    assert_contains "$output" "converge-engine rollback latest --yes" "transaction rollback should route correctly"

    output="$(run_launcher "$env_dir" migrate plan --json)"
    assert_contains "$output" "migrate-engine plan --json" "migration command should forward arguments"

    output="$(run_launcher "$env_dir" certify --json --skip-live)"
    assert_contains "$output" "certify-engine --json --skip-live" "certify command should forward arguments"

    output="$(run_launcher "$env_dir" recovery restore backup.tar.gz --dry-run)"
    assert_contains "$output" "recovery-engine restore backup.tar.gz --dry-run" "recovery command should forward arguments"
}

test_menu_exit() {
    local env_dir output
    env_dir="$(setup_env)"
    output="$(printf '0\n' | HOME="$env_dir/home" PATH="$env_dir/bin:/usr/bin:/bin:/usr/sbin:/sbin" bash "$LAUNCHER_SCRIPT")"
    assert_contains "$output" "mac-dotfiles" "menu should print title"
    assert_contains "$output" "Bye." "menu should exit cleanly"
}

main() {
    test_help
    test_direct_commands
    test_menu_exit
    echo "[PASS] launcher tests completed"
}

main
