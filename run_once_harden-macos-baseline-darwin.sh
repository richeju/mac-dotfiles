#!/usr/bin/env bash

set -euo pipefail

echo "🔒 Applying macOS hardening baseline (NIST-inspired)..."

# Require password immediately after sleep or screen saver.
defaults write com.apple.screensaver askForPassword -int 1
defaults write com.apple.screensaver askForPasswordDelay -int 0

# Keep file extensions visible to reduce spoofing risk.
defaults write NSGlobalDomain AppleShowAllExtensions -bool true

# Show hidden files in Finder for better operator visibility.
defaults write com.apple.finder AppleShowAllFiles -bool true

# Warn before changing a file extension.
defaults write com.apple.finder FXEnableExtensionChangeWarning -bool true

# Keep downloaded files quarantined for Gatekeeper checks.
defaults write com.apple.LaunchServices LSQuarantine -bool true

# Disable automatic execution of "safe" downloaded files.
defaults write com.apple.Safari AutoOpenSafeDownloads -bool false

# Minimize ad/cross-site tracking in Safari.
defaults write com.apple.Safari SendDoNotTrackHTTPHeader -bool true
defaults write com.apple.Safari UniversalSearchEnabled -bool false
defaults write com.apple.Safari SuppressSearchSuggestions -bool true

# Apply AC-only power/network hardening when supported.
if command -v pmset >/dev/null 2>&1; then
  if sudo -n true >/dev/null 2>&1; then
    pmset_caps="$(pmset -g cap 2>/dev/null || true)"

    # Optionally disable Power Nap on AC power (opt-in to avoid intrusive defaults).
    if [[ "${HARDEN_DISABLE_POWERNAP_ON_AC:-0}" == "1" ]]; then
      if grep -q " powernap" <<<"$pmset_caps"; then
        sudo pmset -c powernap 0
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
