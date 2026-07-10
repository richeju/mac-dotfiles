#!/usr/bin/env bash
set -euo pipefail

state_dir="${MAC_DOTFILES_STATE_DIR:-$HOME/.local/state/mac-dotfiles}"
mkdir -p \
    "$state_dir/transactions" \
    "$state_dir/transaction-rollback-backups" \
    "$state_dir/profile-backups"

for legacy_lock in "$state_dir/maintenance.lock" "$state_dir/converge.lock"; do
    [[ -d "$legacy_lock" ]] || continue
    owner=""
    [[ -f "$legacy_lock/pid" ]] && owner="$(cat "$legacy_lock/pid" 2>/dev/null || true)"
    if [[ ! "$owner" =~ ^[0-9]+$ ]] || ! kill -0 "$owner" 2>/dev/null; then
        rm -rf "$legacy_lock"
        echo "Removed stale legacy lock: $legacy_lock"
    fi
done

echo "Initialized transactional state layout"
