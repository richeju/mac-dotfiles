#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_HOOK="$REPO_ROOT/run_onchange_install-packages-darwin.sh.tmpl"

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

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local message="$3"
    [[ "$haystack" != *"$needle"* ]] || fail "$message (unexpected: $needle)"
}

test_manifest_fingerprint() (
    if ! command -v chezmoi >/dev/null 2>&1; then
        echo "[SKIP] package hook rendering (chezmoi unavailable)"
        return
    fi
    local work_dir expected output
    work_dir="$(mktemp -d)"
    trap 'rm -rf "$work_dir"' EXIT
    mkdir "$work_dir/source" "$work_dir/home"
    printf '[data]\nprofile = "developer"\n' >"$work_dir/config.toml"
    printf 'brew "jq"\n' >"$work_dir/source/dot_Brewfile"
    expected="$(shasum -a 256 "$work_dir/source/dot_Brewfile" | awk '{print $1}')"
    output="$(chezmoi execute-template --source "$work_dir/source" \
        --destination "$work_dir/home" --config "$work_dir/config.toml" \
        --persistent-state "$work_dir/chezmoi.boltdb" <"$PACKAGE_HOOK")"
    assert_contains "$output" "# Manifest SHA-256: $expected" "hook must fingerprint the canonical Brewfile"
)

test_minimal_mode_skips_brew_bundle() {
    local env_dir output
    env_dir="$(mktemp -d)"
    mkdir -p "$env_dir/bin" "$env_dir/home"
    touch "$env_dir/home/.Brewfile"

    cat >"$env_dir/bin/brew" <<'BREW'
#!/usr/bin/env bash
echo "brew-called $*"
BREW
    chmod +x "$env_dir/bin/brew"

    output="$(HOME="$env_dir/home" PATH="$env_dir/bin:/usr/bin:/bin:/usr/sbin:/sbin" MAC_DOTFILES_MINIMAL=1 bash "$PACKAGE_HOOK" 2>&1)"

    assert_contains "$output" "Minimal setup requested" "minimal hook should explain skipped package install"
    assert_not_contains "$output" "brew-called" "minimal hook should not call brew"
}

main() {
    test_manifest_fingerprint
    test_minimal_mode_skips_brew_bundle
    local output
    output="$(MAC_DOTFILES_BOOTSTRAP_PACKAGES=1 bash "$PACKAGE_HOOK")"
    assert_contains "$output" "delegated to bootstrap reconciliation" "bootstrap should own package installation"
    assert_not_contains "$output" "Installing/updating" "hook should not duplicate bootstrap installation"
    output="$(MAC_DOTFILES_BOOTSTRAP_PACKAGES=1 bash "$REPO_ROOT/run_onchange_update-and-cleanup-darwin.sh.tmpl")"
    assert_contains "$output" "Maintenance hook skipped during bootstrap" "bootstrap should not upgrade already installed apps"
    assert_not_contains "$output" "Starting system maintenance" "bootstrap should defer upgrades to maintenance"
    echo "[PASS] package hook tests completed"
}

main
