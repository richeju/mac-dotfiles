#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RECOVERY_SCRIPT="$REPO_ROOT/dot_local/bin/executable_mac-dotfiles-recovery.sh.tmpl"

fail() {
    echo "[FAIL] $1" >&2
    exit 1
}

setup_env() {
    local root="$1"
    mkdir -p "$root/home/.config/chezmoi" "$root/home/Library/LaunchAgents" "$root/bin" "$root/state"
    echo "original-git" >"$root/home/.gitconfig"
    echo "original-brew" >"$root/home/.Brewfile"
    echo "original-zprofile" >"$root/home/.zprofile"
    echo 'profile = "developer"' >"$root/home/.config/chezmoi/chezmoi.toml"
    echo "original-plist" >"$root/home/Library/LaunchAgents/com.chezmoi.mac-dotfiles.maintenance.plist"
    echo 2 >"$root/state/schema-version"
    cat >"$root/bin/brew" <<'MOCK'
#!/usr/bin/env bash
[[ "$1" == "leaves" ]] && { echo jq; exit; }
[[ "$1 $2" == "list --cask" ]] && echo raycast
MOCK
    cat >"$root/bin/chezmoi" <<'MOCK'
#!/usr/bin/env bash
[[ "$1" == "data" ]] && echo '{"profile":"developer"}'
MOCK
    chmod +x "$root/bin/brew" "$root/bin/chezmoi"
}

run_recovery() {
    local root="$1"
    shift
    HOME="$root/home" MAC_DOTFILES_STATE_DIR="$root/state" \
        MAC_DOTFILES_SNAPSHOT_DIR="$root/snapshots" \
        PATH="$root/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
        bash "$RECOVERY_SCRIPT" "$@"
}

test_create_verify_inspect_and_restore() {
    local root snapshot output
    root="$(mktemp -d)"
    setup_env "$root"
    snapshot="$root/portable.tar.gz"
    run_recovery "$root" create --output "$snapshot" >/dev/null
    [[ -f "$snapshot" ]] || fail "snapshot should be created"

    output="$(run_recovery "$root" verify "$snapshot")"
    [[ "$output" == *"verified"* ]] || fail "snapshot should verify"
    output="$(run_recovery "$root" inspect "$snapshot")"
    [[ "$output" == *'"secrets_included": false'* ]] || fail "manifest should assert secret exclusion"
    [[ "$output" == *".gitconfig"* ]] || fail "inspect should list restorable files"

    echo "changed-git" >"$root/home/.gitconfig"
    run_recovery "$root" restore "$snapshot" --dry-run >/dev/null
    [[ "$(cat "$root/home/.gitconfig")" == "changed-git" ]] || fail "dry-run must not restore"
    run_recovery "$root" restore "$snapshot" --yes >/dev/null
    [[ "$(cat "$root/home/.gitconfig")" == "original-git" ]] || fail "restore should recover configuration"
    find "$root/state/recovery-rollbacks" -type f -path '*/current/.gitconfig' | grep -q . ||
        fail "restore should preserve the previous state"
}

test_corruption_is_rejected() {
    local root snapshot unpack
    root="$(mktemp -d)"
    setup_env "$root"
    snapshot="$root/portable.tar.gz"
    run_recovery "$root" create --output "$snapshot" >/dev/null
    unpack="$root/unpack"
    mkdir -p "$unpack"
    tar -C "$unpack" -xzf "$snapshot"
    echo tampered >"$unpack/payload/.gitconfig"
    tar -C "$unpack" -czf "$root/corrupt.tar.gz" manifest.json checksums.sha256 files.txt payload inventory
    if run_recovery "$root" verify "$root/corrupt.tar.gz" >/dev/null 2>&1; then
        fail "checksum corruption should be rejected"
    fi
}

test_unsafe_archive_path_is_rejected() {
    local root archive
    root="$(mktemp -d)"
    setup_env "$root"
    archive="$root/unsafe.tar.gz"
    tar -C "$root/state" -czf "$archive" ../state/schema-version
    if run_recovery "$root" verify "$archive" >/dev/null 2>&1; then
        fail "archive path traversal should be rejected"
    fi
}

test_outside_allowlist_is_rejected() {
    local root snapshot unpack checksum
    root="$(mktemp -d)"
    setup_env "$root"
    snapshot="$root/portable.tar.gz"
    run_recovery "$root" create --output "$snapshot" >/dev/null
    unpack="$root/unpack"
    mkdir -p "$unpack/payload/.ssh"
    tar -C "$unpack" -xzf "$snapshot"
    cp "$unpack/payload/.gitconfig" "$unpack/payload/.ssh/id_rsa"
    echo '.ssh/id_rsa' >>"$unpack/files.txt"
    checksum="$(shasum -a 256 "$unpack/payload/.ssh/id_rsa" | awk '{print $1}')"
    printf '%s  payload/.ssh/id_rsa\n' "$checksum" >>"$unpack/checksums.sha256"
    jq '.file_count += 1' "$unpack/manifest.json" >"$unpack/manifest.new"
    mv "$unpack/manifest.new" "$unpack/manifest.json"
    tar -C "$unpack" -czf "$root/outside-allowlist.tar.gz" manifest.json checksums.sha256 files.txt payload inventory
    if run_recovery "$root" verify "$root/outside-allowlist.tar.gz" >/dev/null 2>&1; then
        fail "checksum-valid targets outside the recovery allowlist should be rejected"
    fi
}

test_encrypted_round_trip() {
    local root snapshot password_file wrong_password_file
    command -v openssl >/dev/null 2>&1 || return 0
    root="$(mktemp -d)"
    setup_env "$root"
    snapshot="$root/portable.tar.gz.enc"
    password_file="$root/password"
    wrong_password_file="$root/wrong-password"
    echo 'recovery-test-password' >"$password_file"
    echo 'wrong-recovery-test-password' >"$wrong_password_file"
    chmod 600 "$password_file" "$wrong_password_file"
    MAC_DOTFILES_RECOVERY_PASSWORD_FILE="$password_file" run_recovery "$root" create --encrypt --output "$snapshot" >/dev/null
    MAC_DOTFILES_RECOVERY_PASSWORD_FILE="$password_file" run_recovery "$root" verify "$snapshot" >/dev/null
    if MAC_DOTFILES_RECOVERY_PASSWORD_FILE="$wrong_password_file" run_recovery "$root" verify "$snapshot" >/dev/null 2>&1; then
        fail "encrypted snapshots should reject an incorrect password"
    fi
}

test_create_verify_inspect_and_restore
test_corruption_is_rejected
test_unsafe_archive_path_is_rejected
test_outside_allowlist_is_rejected
test_encrypted_round_trip
echo "[PASS] recovery tests completed"
