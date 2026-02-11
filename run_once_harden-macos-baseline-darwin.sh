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

# Apply Finder-related changes.
killall Finder >/dev/null 2>&1 || true

echo "✅ macOS hardening baseline applied!"
