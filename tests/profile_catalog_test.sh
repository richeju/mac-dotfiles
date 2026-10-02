#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENGINE="$REPO_ROOT/dot_local/bin/executable_mac-dotfiles-converge.sh.tmpl"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
mkdir -p "$work_dir/source" "$work_dir/home"
cp -R "$REPO_ROOT/profiles" "$work_dir/source/"
cp "$REPO_ROOT/dot_Brewfile.tmpl" "$work_dir/source/"
printf '[data]\n' >"$work_dir/config.toml"

fail() {
    echo "[FAIL] $1" >&2
    exit 1
}

run_engine() {
    CHEZMOI_SOURCE_DIR="$work_dir/source" \
        MAC_DOTFILES_CONFIG_FILE="$work_dir/config.toml" bash "$ENGINE" "$@"
}

render_template() {
    chezmoi execute-template --source "$work_dir/source" \
        --destination "$work_dir/home" --config "$work_dir/config.toml" \
        --persistent-state "$work_dir/chezmoi.boltdb" \
        --override-data "$(jq -nc --arg profile "$1" '{profile:$profile}')" <"${2:-$REPO_ROOT/dot_Brewfile.tmpl}"
}

expect_catalog_failure() {
    local filter="$1"
    jq "$filter" "$REPO_ROOT/profiles/catalog.json" >"$work_dir/source/profiles/catalog.json"
    if run_engine profile list >"$work_dir/output" 2>&1; then
        fail "invalid catalog should not list supported profiles"
    fi
    grep -Fq 'Invalid profile catalog' "$work_dir/output" || fail "catalog error should be explicit"
    if command -v chezmoi >/dev/null 2>&1 && render_template minimal >"$work_dir/output" 2>&1; then
        fail "template should also reject the invalid catalog"
    fi
}

names="$(jq -r '.profiles[].name' "$REPO_ROOT/profiles/catalog.json")"
while IFS= read -r profile; do
    run_engine profile show "$profile" >"$work_dir/engine.Brewfile"
    if command -v chezmoi >/dev/null 2>&1; then
        render_template "$profile" >"$work_dir/template.Brewfile"
        cmp "$work_dir/engine.Brewfile" "$work_dir/template.Brewfile" || fail "chezmoi and engine disagree for $profile"
    fi
done <<<"$names"

# Changing the catalog alone must change both consumers, including order and description.
jq '.profiles += [{name:"reading",description:"Reading tools",components:["personal","core"]}]' \
    "$REPO_ROOT/profiles/catalog.json" >"$work_dir/source/profiles/catalog.json"
run_engine profile list | grep -Fq 'Reading tools' || fail "catalog description was not consumed"
run_engine profile show reading >"$work_dir/engine.Brewfile"
grep -Fq 'mas "Amazon Kindle"' "$work_dir/engine.Brewfile" || fail "new profile should include its declared apps"
first_package="$(grep -E '^(brew|cask|mas) ' "$work_dir/engine.Brewfile" | head -n 1)"
[[ "$first_package" == 'brew "mas"'* ]] || fail "component order should follow the catalog"
if command -v chezmoi >/dev/null 2>&1; then
    render_template reading >"$work_dir/template.Brewfile"
    cmp "$work_dir/engine.Brewfile" "$work_dir/template.Brewfile" || fail "catalog-only change should reach both renderers"
    if render_template unknown >"$work_dir/output" 2>&1; then
        fail "template should reject unknown profiles"
    fi
    render_template reading "$REPO_ROOT/run_onchange_install-packages-darwin.sh.tmpl" >"$work_dir/hook-before"
    printf '# Component change\n' >>"$work_dir/source/profiles/personal.Brewfile"
    render_template reading "$REPO_ROOT/run_onchange_install-packages-darwin.sh.tmpl" >"$work_dir/hook-after"
    if cmp -s "$work_dir/hook-before" "$work_dir/hook-after"; then
        fail "a selected component change should update the package hook fingerprint"
    fi
else
    echo "[SKIP] chezmoi template comparison (chezmoi unavailable; required in macOS CI)"
fi

expect_catalog_failure '.profiles += [.profiles[0]]'
expect_catalog_failure '.profiles[0].components = ["../outside"]'
expect_catalog_failure '.profiles[0].components = ["core", "core"]'
expect_catalog_failure '.schema_version = 2'
cp "$REPO_ROOT/profiles/catalog.json" "$work_dir/source/profiles/catalog.json"
rm "$work_dir/source/profiles/core.Brewfile"
if run_engine profile show minimal >"$work_dir/output" 2>&1; then
    fail "missing component should fail rendering"
fi
grep -Fq 'Profile component is missing' "$work_dir/output" || fail "missing component should be explicit"
echo "[PASS] profile catalog tests completed"
