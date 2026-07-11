#!/usr/bin/env bash
set -euo pipefail

config="${MAC_DOTFILES_CONFIG_FILE:-$HOME/.config/chezmoi/chezmoi.toml}"
[[ -f "$config" ]] || exit 0
grep -Eq '^[[:space:]]*profile[[:space:]]*=' "$config" && exit 0

temp="$(mktemp "${TMPDIR:-/tmp}/mac-dotfiles-migration.XXXXXX")"
awk '
    BEGIN { in_data=0; inserted=0 }
    /^\[data\]$/ { print; in_data=1; next }
    /^\[/ && in_data && !inserted {
        print "profile = \"full\""
        inserted=1
        in_data=0
    }
    { print }
    END {
        if (in_data && !inserted) print "profile = \"full\""
    }
' "$config" >"$temp"
chmod 600 "$temp"
mv "$temp" "$config"
echo "Initialized persistent profile to 'full'"
