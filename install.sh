#!/bin/bash

# Bootstrap script for new macOS setup
# Usage: curl -fsSL https://raw.githubusercontent.com/richeju/mac-dotfiles/main/install.sh | bash

set -e

echo "🚀 macOS Bootstrap Script"
echo "========================="

# Colors for messages
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}✓${NC} $1"; }
log_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1"; exit 1; }

# Verify macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    log_error "This script is only for macOS"
fi

# Install Homebrew
if ! command -v brew &> /dev/null; then
    log_info "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    
    # Add Homebrew to PATH for Apple Silicon
    if [[ $(uname -m) == 'arm64' ]]; then
        echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
        eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
else
    log_info "Homebrew already installed"
fi

# Install chezmoi via Homebrew
log_info "Installing chezmoi..."
if brew list chezmoi &>/dev/null; then
    log_info "chezmoi already installed"
else
    brew install chezmoi
fi

log_info "Bootstrap completed!"

# Initialize chezmoi
echo ""
echo "🏠 Setting up dotfiles with chezmoi..."
echo ""

if [ -d "$HOME/.local/share/chezmoi" ]; then
    log_warning "Chezmoi already initialized"
    log_info "Run 'chezmoi update' to sync your dotfiles"
else
    log_info "Initializing chezmoi with your dotfiles..."
    chezmoi init --apply richeju/mac-dotfiles
fi

echo ""
echo "${GREEN}✨ Setup completed successfully!${NC}"
echo ""
echo "Your dotfiles have been applied with chezmoi."
echo ""
echo "Useful commands:"
echo "  chezmoi diff     - See what would change"
echo "  chezmoi apply    - Apply changes"
echo "  chezmoi update   - Pull and apply latest changes"
echo "  chezmoi edit X   - Edit a dotfile"
echo ""
