#!/usr/bin/env bash

# Bootstrap script for new macOS setup
# Usage: curl -fsSL https://raw.githubusercontent.com/richeju/mac-dotfiles/main/install.sh | bash

set -euo pipefail

AUTO_MODE="false"
GIT_NAME="${GIT_NAME:-}"
GIT_EMAIL="${GIT_EMAIL:-}"

usage() {
    cat <<'USAGE'
Usage: install.sh [options]

Options:
  --auto                 Run in non-interactive mode
  --git-name <name>      Git user name (required with --auto if GIT_NAME env not set)
  --git-email <email>    Git user email (required with --auto if GIT_EMAIL env not set)
  -h, --help             Show this help
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --auto)
            AUTO_MODE="true"
            shift
            ;;
        --git-name)
            [[ $# -lt 2 ]] && { echo "Missing value for --git-name"; exit 1; }
            GIT_NAME="$2"
            shift 2
            ;;
        --git-email)
            [[ $# -lt 2 ]] && { echo "Missing value for --git-email"; exit 1; }
            GIT_EMAIL="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac

done

if [[ "${AUTO:-0}" == "1" ]]; then
    AUTO_MODE="true"
fi

if [[ "$AUTO_MODE" == "true" ]]; then
    if [[ -z "$GIT_NAME" || -z "$GIT_EMAIL" ]]; then
        echo "In --auto mode, provide --git-name and --git-email (or GIT_NAME/GIT_EMAIL env vars)."
        exit 1
    fi
fi

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

require_command() {
    if ! command -v "$1" &> /dev/null; then
        log_error "Required command '$1' is missing"
    fi
}

ensure_brew_in_path() {
    if command -v brew &>/dev/null; then
        return 0
    fi

    if [[ -x /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -x /usr/local/bin/brew ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi
}

SUDO_KEEPALIVE_PID=""
start_sudo_keepalive() {
    while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
    SUDO_KEEPALIVE_PID=$!
}

stop_sudo_keepalive() {
    if [[ -n "${SUDO_KEEPALIVE_PID}" ]]; then
        kill "${SUDO_KEEPALIVE_PID}" &>/dev/null || true
    fi
}

# Check if user has sudo access
log_info "Checking sudo access..."
if ! sudo -n true 2>/dev/null; then
    echo ""
    echo "${YELLOW}⚠️  This script requires administrator privileges.${NC}"
    echo "You will be prompted for your password to install system packages."
    echo ""
    if ! sudo -v; then
        log_error "Failed to obtain sudo privileges. Please make sure you have administrator access."
    fi
fi

# Keep sudo alive
start_sudo_keepalive
trap stop_sudo_keepalive EXIT

# Verify macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    log_error "This script is only for macOS"
fi

require_command curl
ensure_brew_in_path

# Install Homebrew
if ! command -v brew &> /dev/null; then
    log_info "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    # Add Homebrew to PATH for Apple Silicon
    if [[ $(uname -m) == 'arm64' ]]; then
        # shellcheck disable=SC2016 # We intentionally persist this exact command string into .zprofile.
        BREW_SHELLENV_LINE='eval "$(/opt/homebrew/bin/brew shellenv)"'
        if [[ ! -f "$HOME/.zprofile" ]] || ! grep -Fqx "$BREW_SHELLENV_LINE" "$HOME/.zprofile"; then
            echo "$BREW_SHELLENV_LINE" >> "$HOME/.zprofile"
        fi
        eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
else
    ensure_brew_in_path
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
    if [[ "$AUTO_MODE" == "true" ]]; then
        log_info "Running in auto mode (non-interactive)"
        chezmoi init --apply --promptBool=false --promptInt=false --promptString=false \
            --data "name=$GIT_NAME" --data "email=$GIT_EMAIL" richeju/mac-dotfiles
    else
        chezmoi init --apply richeju/mac-dotfiles
    fi
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
