#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != Darwin ]]; then
    echo "[SKIP] bootstrap integration requires macOS (covered by macOS CI)"
    exit 0
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REAL_CHEZMOI="$(command -v chezmoi)" || {
    echo "[FAIL] chezmoi is required for bootstrap integration" >&2
    exit 1
}
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT
mkdir -p "$test_root"/{bin,home,tmp,origin,inventory}
touch "$test_root/gitconfig" "$test_root/commands.log" "$test_root/package-calls"

fail() {
    echo "[FAIL] $1" >&2
    [[ ! -f "$test_root/output" ]] || cat "$test_root/output" >&2
    exit 1
}

# Snapshot the working source, including uncommitted changes, into a local Git
# remote. Neither clone nor update can contact GitHub during this test.
while IFS= read -r path; do
    [[ -f "$REPO_ROOT/$path" ]] || continue
    mkdir -p "$test_root/origin/$(dirname "$path")"
    cp -p "$REPO_ROOT/$path" "$test_root/origin/$path"
done < <(git -C "$REPO_ROOT" ls-files --cached --others --exclude-standard)
git -c init.defaultBranch=main init -q "$test_root/origin"
git -C "$test_root/origin" add .
git -C "$test_root/origin" -c user.name=Test -c user.email=test@example.com \
    -c commit.gpgsign=false commit -qm fixture

# This adapter only supplies isolated paths and replaces the clone URL. All
# init/update/apply operations, template rendering and hook execution are real.
cat >"$test_root/bin/chezmoi" <<'CHEZMOI'
#!/usr/bin/env bash
set -euo pipefail
args=()
for arg in "$@"; do
    [[ "$arg" != richeju/mac-dotfiles ]] || arg="$E2E_ROOT/origin"
    args+=("$arg")
done
exec "$E2E_CHEZMOI" --source "$HOME/.local/share/chezmoi" \
    --destination "$HOME" --config "$HOME/.config/chezmoi/chezmoi.toml" \
    --persistent-state "$E2E_ROOT/chezmoi.boltdb" --cache "$E2E_ROOT/cache" "${args[@]}"
CHEZMOI
cat >"$test_root/bin/brew" <<'BREW'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
    --prefix) echo /opt/homebrew ;;
    'list chezmoi') exit 0 ;;
    'bundle check '* | 'bundle install '*)
        grep -Fq 'cask "vlc"' "$HOME/.Brewfile"
        grep -Fq 'mas "Amazon Kindle", id: 302584613' "$HOME/.Brewfile"
        [[ " $* " == *' --no-upgrade '* ]] || exit 9
        if [[ "$2" == check ]]; then
            [[ -f "$E2E_ROOT/inventory/vlc" && -f "$E2E_ROOT/inventory/kindle" ]]
        else
            echo install >>"$E2E_ROOT/package-calls"
            touch "$E2E_ROOT/inventory/vlc"
            if [[ -f "$E2E_ROOT/app-store-blocked" ]]; then
                echo 'Error: Not signed in to the App Store'
                exit 1
            fi
            touch "$E2E_ROOT/inventory/kindle"
        fi
        ;;
    *) echo "Unexpected brew call: $*" >&2; exit 9 ;;
esac
BREW
cat >"$test_root/bin/mas" <<'MAS'
#!/usr/bin/env bash
[[ "$*" == list ]] || exit 9
[[ ! -f "$E2E_ROOT/inventory/kindle" ]] || echo '302584613 Amazon Kindle (1.0)'
MAS
cat >"$test_root/bin/gh" <<'GH'
#!/usr/bin/env bash
[[ "$*" == 'auth status' ]]
GH
for command in defaults killall launchctl plutil pmset; do
    cat >"$test_root/bin/$command" <<'MOCK'
#!/usr/bin/env bash
printf '%s %s\n' "${0##*/}" "$*" >>"$E2E_ROOT/commands.log"
MOCK
done
for command in sudo curl security osascript systemsetup networksetup; do
    cat >"$test_root/bin/$command" <<'DENY'
#!/usr/bin/env bash
echo "Blocked external operation: ${0##*/} $*" >&2
exit 1
DENY
done
chmod +x "$test_root/bin/"*

run_bootstrap() {
    local expected="$1" actual=0
    env -i HOME="$test_root/home" USER=test LOGNAME=test \
        PATH="$test_root/bin:/usr/bin:/bin:/usr/sbin:/sbin" TMPDIR="$test_root/tmp" \
        XDG_CONFIG_HOME="$test_root/home/.config" XDG_DATA_HOME="$test_root/home/.local/share" \
        XDG_CACHE_HOME="$test_root/cache" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$test_root/gitconfig" \
        E2E_ROOT="$test_root" E2E_CHEZMOI="$REAL_CHEZMOI" \
        MAC_DOTFILES_SKIP_BREW_PATH_DETECTION=1 \
        bash "$REPO_ROOT/install.sh" --auto --git-name 'Test User' --git-email test@example.com \
        >"$test_root/output" 2>&1 </dev/null || actual=$?
    [[ "$actual" -eq "$expected" ]] || fail "bootstrap returned $actual, expected $expected"
}

assert_install_count() {
    [[ "$(wc -l <"$test_root/package-calls" | tr -d ' ')" == "$1" ]] || fail "unexpected number of package installs"
}

run_bootstrap 0
assert_install_count 1
[[ -x "$test_root/home/.local/bin/mac-dotfiles.sh" ]] || fail "real apply did not install the launcher"
grep -Fq 'name = "Test User"' "$test_root/home/.config/chezmoi/chezmoi.toml" || fail "automatic Git identity was not persisted"
[[ -f "$test_root/home/Library/LaunchAgents/com.chezmoi.mac-dotfiles.maintenance.plist" ]] || fail "LaunchAgent was not deployed into ~/Library"
[[ ! -e "$test_root/home/.Library" ]] || fail "LaunchAgent must not create a hidden .Library directory"
[[ "$(cat "$test_root/home/.local/state/mac-dotfiles/schema-version")" == 2 ]] || fail "real migrations did not run"
grep -Fq 'defaults write' "$test_root/commands.log" || fail "preference hooks were not exercised"
grep -Fq 'launchctl bootstrap' "$test_root/commands.log" || fail "LaunchAgent hook was not exercised"
cp "$test_root/home/.Brewfile" "$test_root/manifest-before"
cp "$test_root/commands.log" "$test_root/hooks-before"

run_bootstrap 0
assert_install_count 1
cmp -s "$test_root/hooks-before" "$test_root/commands.log" || fail "unchanged hooks should not rerun"

rm "$test_root/inventory/vlc"
run_bootstrap 0
assert_install_count 2
[[ -f "$test_root/inventory/vlc" ]] || fail "deleted application was not restored"

rm "$test_root/inventory/kindle"
touch "$test_root/app-store-blocked"
run_bootstrap 1
assert_install_count 3
grep -Fq 'Amazon Kindle: App Store sign-in required' "$test_root/output" || fail "App Store failure should be actionable"
grep -Fq 'Install summary' "$test_root/output" || fail "failed installation should still print its summary"

rm "$test_root/app-store-blocked"
run_bootstrap 0
assert_install_count 4
grep -Fq 'Amazon Kindle: installed (Mac App Store)' "$test_root/output" || fail "retry should report successful installation"
cmp -s "$test_root/manifest-before" "$test_root/home/.Brewfile" || fail "repair should preserve the desired manifest"
cmp -s "$test_root/hooks-before" "$test_root/commands.log" || fail "package repair should not rerun unchanged preference hooks"
echo "[PASS] real chezmoi bootstrap integration completed (first install, idempotence, repair, App Store retry)"
