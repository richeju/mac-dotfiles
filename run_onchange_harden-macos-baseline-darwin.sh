#!/usr/bin/env bash

set -euo pipefail

echo "🔒 Applying macOS hardening baseline (NIST-inspired)..."

safe_defaults_write() {
  if ! defaults write "$@" >/dev/null 2>&1; then
    echo "⚠️ Skipping unsupported preference: defaults write $*"
  fi
}

# Require password immediately after sleep or screen saver.
safe_defaults_write com.apple.screensaver askForPassword -int 1
safe_defaults_write com.apple.screensaver askForPasswordDelay -int 0

# Keep file extensions visible to reduce spoofing risk.
safe_defaults_write NSGlobalDomain AppleShowAllExtensions -bool true

# Show hidden files in Finder for better operator visibility.
safe_defaults_write com.apple.finder AppleShowAllFiles -bool true

# Warn before changing a file extension.
safe_defaults_write com.apple.finder FXEnableExtensionChangeWarning -bool true

# Keep downloaded files quarantined for Gatekeeper checks.
safe_defaults_write com.apple.LaunchServices LSQuarantine -bool true

# Disable automatic execution of "safe" downloaded files.
safe_defaults_write com.apple.Safari AutoOpenSafeDownloads -bool false

# Minimize ad/cross-site tracking in Safari.
safe_defaults_write com.apple.Safari SendDoNotTrackHTTPHeader -bool true
safe_defaults_write com.apple.Safari UniversalSearchEnabled -bool false
safe_defaults_write com.apple.Safari SuppressSearchSuggestions -bool true

# Apply AC-only power/network hardening when supported.
if command -v pmset >/dev/null 2>&1; then
  if sudo -n true >/dev/null 2>&1; then
    pmset_caps="$(pmset -g cap 2>/dev/null || true)"

    # Disable Power Nap on AC power.
    if grep -q " powernap" <<<"$pmset_caps"; then
      sudo pmset -c powernap 0

      # Optionally disable Power Nap on battery power.
      if [[ "${HARDEN_DISABLE_POWERNAP_ON_BATTERY:-0}" == "1" ]]; then
        sudo pmset -b powernap 0
      fi
    fi

    # Disable wake on network access on AC power.
    if grep -q " womp" <<<"$pmset_caps"; then
      sudo pmset -c womp 0
    fi

    # Disable proximity wake (e.g. nearby devices) on AC power.
    if grep -q " proximitywake" <<<"$pmset_caps"; then
      sudo pmset -c proximitywake 0
    fi
  else
    echo "⚠️ Skipping AC power hardening: sudo credentials are required."
  fi
fi

# Apply Finder-related changes.
killall Finder >/dev/null 2>&1 || true

echo "✅ macOS hardening baseline applied!"
