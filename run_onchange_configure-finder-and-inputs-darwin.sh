#!/usr/bin/env bash

set -euo pipefail

echo "🛠️ Applying Finder and input comfort defaults..."

# Finder: show status and path bars for quicker navigation.
defaults write com.apple.finder ShowStatusBar -bool true
defaults write com.apple.finder ShowPathbar -bool true

# Finder: prefer list view and keep folders-on-top in list view.
defaults write com.apple.finder FXPreferredViewStyle -string "Nlsv"
defaults write com.apple.finder _FXSortFoldersFirst -bool true

# Save dialogs: expanded by default for easier file operations.
defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true
defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode2 -bool true

# Keyboard: faster key repeat for power users.
defaults write NSGlobalDomain InitialKeyRepeat -int 15
defaults write NSGlobalDomain KeyRepeat -int 2

# Trackpad: tap-to-click for built-in and Bluetooth trackpads.
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true
defaults write com.apple.AppleMultitouchTrackpad Clicking -bool true
defaults -currentHost write NSGlobalDomain com.apple.mouse.tapBehavior -int 1
defaults write NSGlobalDomain com.apple.mouse.tapBehavior -int 1

# Apply relevant changes.
killall Finder >/dev/null 2>&1 || true

echo "✅ Finder and input defaults configured"
