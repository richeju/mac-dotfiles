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
        PATH="$root/bin:$PATH" \
        bash "$RECOVERY_SCRIPT" "$@"
}

test_read_only_commands_without_temp_directories() {
    local root output
    root="$(mktemp -d)"
    setup_env "$root"

    output="$(run_recovery "$root" list)"
    [[ "$output" == *"No snapshots found."* ]] || fail "empty snapshot list should succeed"
    run_recovery "$root" help >/dev/null
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
    tar -C "$root/state" -czf "$archive" ../state/schema-version 2>/dev/null
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

test_age_encrypted_round_trip_and_tamper_rejection() {
    local root snapshot identity wrong_identity recipient tampered size offset
    command -v age >/dev/null 2>&1 || return 0
    command -v age-keygen >/dev/null 2>&1 || return 0
    root="$(mktemp -d)"
    setup_env "$root"
    snapshot="$root/portable.tar.gz.age"
    identity="$root/identity.txt"
    wrong_identity="$root/wrong-identity.txt"
    age-keygen --output "$identity" >/dev/null 2>&1
    age-keygen --output "$wrong_identity" >/dev/null 2>&1
    chmod 600 "$identity" "$wrong_identity"
    recipient="$(age-keygen -y "$identity")"
    MAC_DOTFILES_RECOVERY_AGE_RECIPIENT="$recipient" run_recovery "$root" create --encrypt --output "$snapshot" >/dev/null
    MAC_DOTFILES_RECOVERY_AGE_IDENTITY_FILE="$identity" run_recovery "$root" verify "$snapshot" >/dev/null
    if MAC_DOTFILES_RECOVERY_AGE_IDENTITY_FILE="$wrong_identity" run_recovery "$root" verify "$snapshot" >/dev/null 2>&1; then
        fail "encrypted snapshots should reject an incorrect age identity"
    fi

    tampered="$root/tampered.tar.gz.age"
    cp "$snapshot" "$tampered"
    size="$(wc -c <"$tampered" | tr -d ' ')"
    offset=$((size - 1))
    printf '\000' | dd of="$tampered" bs=1 seek="$offset" count=1 conv=notrunc 2>/dev/null
    if cmp -s "$snapshot" "$tampered"; then
        printf '\377' | dd of="$tampered" bs=1 seek="$offset" count=1 conv=notrunc 2>/dev/null
    fi
    if MAC_DOTFILES_RECOVERY_AGE_IDENTITY_FILE="$identity" run_recovery "$root" verify "$tampered" >/dev/null 2>&1; then
        fail "age snapshots should reject ciphertext tampering"
    fi

    chmod 644 "$identity"
    if MAC_DOTFILES_RECOVERY_AGE_IDENTITY_FILE="$identity" run_recovery "$root" verify "$snapshot" >/dev/null 2>&1; then
        fail "group- or world-readable age identity files should be rejected"
    fi
}

test_legacy_openssl_envelope_remains_readable() {
    local root archive snapshot password_file
    command -v openssl >/dev/null 2>&1 || return 0
    root="$(mktemp -d)"
    setup_env "$root"
    archive="$root/portable.tar.gz"
    snapshot="$root/portable.tar.gz.enc"
    password_file="$root/password"
    echo 'recovery-test-password' >"$password_file"
    chmod 600 "$password_file"
    run_recovery "$root" create --output "$archive" >/dev/null
    openssl enc -aes-256-cbc -salt -pbkdf2 -pass "file:$password_file" -in "$archive" -out "$snapshot"
    MAC_DOTFILES_RECOVERY_PASSWORD_FILE="$password_file" run_recovery "$root" verify "$snapshot" >/dev/null
}

test_link_entries_are_rejected() {
    local root snapshot unpack
    root="$(mktemp -d)"
    setup_env "$root"
    snapshot="$root/portable.tar.gz"
    run_recovery "$root" create --output "$snapshot" >/dev/null
    unpack="$root/unpack"
    mkdir -p "$unpack"
    tar -C "$unpack" -xzf "$snapshot"

    rm -f "$unpack/payload/.gitconfig"
    ln -s .Brewfile "$unpack/payload/.gitconfig"
    tar -C "$unpack" -czf "$root/symlink.tar.gz" manifest.json checksums.sha256 files.txt payload inventory
    if run_recovery "$root" verify "$root/symlink.tar.gz" >/dev/null 2>&1; then
        fail "symlink archive entries should be rejected"
    fi

    rm -f "$unpack/payload/.gitconfig"
    ln "$unpack/payload/.Brewfile" "$unpack/payload/.gitconfig"
    tar -C "$unpack" -czf "$root/hardlink.tar.gz" manifest.json checksums.sha256 files.txt payload inventory
    if run_recovery "$root" verify "$root/hardlink.tar.gz" >/dev/null 2>&1; then
        fail "hardlink archive entries should be rejected"
    fi
}

test_read_only_commands_without_temp_directories
test_create_verify_inspect_and_restore
test_corruption_is_rejected
test_unsafe_archive_path_is_rejected
test_outside_allowlist_is_rejected
test_age_encrypted_round_trip_and_tamper_rejection
test_legacy_openssl_envelope_remains_readable
test_link_entries_are_rejected
echo "[PASS] recovery tests completed"
