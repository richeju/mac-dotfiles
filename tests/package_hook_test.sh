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

test_minimal_mode_skips_brew_bundle() {
  local env_dir output
  env_dir="$(mktemp -d)"
  mkdir -p "$env_dir/bin" "$env_dir/home"
  touch "$env_dir/home/.Brewfile"

  cat > "$env_dir/bin/brew" <<'BREW'
#!/usr/bin/env bash
echo "brew-called $*"
BREW
  chmod +x "$env_dir/bin/brew"

  output="$(HOME="$env_dir/home" PATH="$env_dir/bin:/usr/bin:/bin:/usr/sbin:/sbin" MAC_DOTFILES_MINIMAL=1 bash "$PACKAGE_HOOK" 2>&1)"

  assert_contains "$output" "Minimal setup requested" "minimal hook should explain skipped package install"
  assert_not_contains "$output" "brew-called" "minimal hook should not call brew"
}

main() {
  test_minimal_mode_skips_brew_bundle
  echo "[PASS] package hook tests completed"
}

main
