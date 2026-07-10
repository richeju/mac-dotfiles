#!/usr/bin/env bash

# Bootstrap script for new macOS setup
# Usage: curl -fsSL https://raw.githubusercontent.com/richeju/mac-dotfiles/main/install.sh | bash

set -euo pipefail

AUTO_MODE="false"
VERIFY_MODE="false"
MINIMAL_MODE="false"
GIT_NAME="${GIT_NAME:-}"
GIT_EMAIL="${GIT_EMAIL:-}"

usage() {
    cat <<'USAGE'
Usage: install.sh [options]

Options:
  --auto                 Run in non-interactive mode
  --minimal              Apply core dotfiles but skip the full Homebrew bundle
  --verify               Check current machine readiness without changing anything
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
        --minimal)
            MINIMAL_MODE="true"
            shift
            ;;
        --verify)
            VERIFY_MODE="true"
            shift
            ;;
        --git-name)
            [[ $# -lt 2 ]] && {
                echo "Missing value for --git-name"
                exit 1
            }
            GIT_NAME="$2"
            shift 2
            ;;
        --git-email)
            [[ $# -lt 2 ]] && {
                echo "Missing value for --git-email"
                exit 1
            }
            GIT_EMAIL="$2"
            shift 2
            ;;
        -h | --help)
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

if [[ "${MINIMAL:-0}" == "1" ]]; then
    MINIMAL_MODE="true"
fi

# Colors for messages
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}✓${NC} $1"; }
log_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
log_error() {
    echo -e "${RED}✗${NC} $1"
    exit 1
}
DOTFILES_APPLIED="false"
VERIFY_WARNINGS=0

require_command() {
    if ! command -v "$1" &>/dev/null; then
        log_error "Required command '$1' is missing"
    fi
}

verify_ok() {
    log_info "$1"
}

verify_warn() {
    log_warning "$1"
    VERIFY_WARNINGS=$((VERIFY_WARNINGS + 1))
}

verify_command() {
    local cmd="$1"
    if command -v "$cmd" &>/dev/null; then
        verify_ok "Command available: $cmd"
    else
        verify_warn "Missing command: $cmd"
    fi
}

ensure_brew_in_path() {
    if command -v brew &>/dev/null; then
        return 0
    fi

    if [[ "${MAC_DOTFILES_SKIP_BREW_PATH_DETECTION:-0}" == "1" ]]; then
        return 0
    fi

    if [[ -x /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -x /usr/local/bin/brew ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi
}

ensure_zprofile_line() {
    local line="$1"

    if [[ ! -f "$HOME/.zprofile" ]] || ! grep -Fqx "$line" "$HOME/.zprofile"; then
        echo "$line" >>"$HOME/.zprofile"
    fi
}

run_verify() {
    echo "🔎 macOS Bootstrap Verification"
    echo "==============================="

    if [[ "$OSTYPE" == "darwin"* ]]; then
        verify_ok "Running on macOS"
    else
        verify_warn "This repository targets macOS; current OSTYPE is '$OSTYPE'"
    fi

    verify_command curl
    verify_command git

    ensure_brew_in_path
    if command -v brew &>/dev/null; then
        verify_ok "Homebrew installed: $(brew --prefix)"

        if brew list chezmoi &>/dev/null; then
            verify_ok "chezmoi installed via Homebrew"
        else
            verify_warn "chezmoi is not installed via Homebrew"
        fi

        if [[ -f "$HOME/.Brewfile" ]]; then
            verify_ok "Homebrew global Brewfile exists: $HOME/.Brewfile"
            if brew bundle check --global --quiet; then
                verify_ok "Homebrew global Brewfile dependencies are satisfied"
            else
                verify_warn "Homebrew global Brewfile has missing or outdated dependencies"
            fi
        else
            verify_warn "Homebrew global Brewfile is missing: $HOME/.Brewfile"
        fi
    else
        verify_warn "Homebrew is not installed or not in PATH"
    fi

    if command -v chezmoi &>/dev/null; then
        verify_ok "chezmoi available: $(chezmoi --version)"
        if [[ -d "$HOME/.local/share/chezmoi" ]]; then
            verify_ok "chezmoi source directory exists"
        else
            verify_warn "chezmoi source directory is missing"
        fi

        if [[ -z "$(chezmoi diff 2>/dev/null)" ]]; then
            verify_ok "No pending chezmoi changes"
        else
            verify_warn "There are pending chezmoi changes"
        fi
    else
        verify_warn "chezmoi is not installed or not in PATH"
    fi

    if command -v gh &>/dev/null; then
        verify_ok "GitHub CLI available: $(gh --version | head -n 1)"
        if gh auth status &>/dev/null; then
            verify_ok "GitHub CLI authentication is configured"
        else
            verify_warn "GitHub CLI is installed but not authenticated"
        fi
    else
        verify_warn "GitHub CLI is missing"
    fi

    if [[ -x "$HOME/.local/bin/mac-dotfiles-maintenance.sh" ]]; then
        verify_ok "Maintenance script is installed"
    else
        verify_warn "Maintenance script is missing or not executable"
    fi

    if [[ -f "$HOME/Library/LaunchAgents/com.chezmoi.mac-dotfiles.maintenance.plist" ]]; then
        verify_ok "Maintenance LaunchAgent plist exists"
    else
        verify_warn "Maintenance LaunchAgent plist is missing"
    fi

    echo ""
    if [[ "$VERIFY_WARNINGS" -eq 0 ]]; then
        echo -e "${GREEN}✓ Verification completed successfully.${NC}"
        return 0
    fi

    echo -e "${YELLOW}⚠ Verification completed with ${VERIFY_WARNINGS} warning(s).${NC}"
    echo "Run 'chezmoi update --apply' or the normal installer to reconcile this machine."
    return 1
}

if [[ "$VERIFY_MODE" == "true" ]]; then
    run_verify
    exit $?
fi

if [[ "$AUTO_MODE" == "true" ]]; then
    if [[ -z "$GIT_NAME" || -z "$GIT_EMAIL" ]]; then
        echo "In --auto mode, provide --git-name and --git-email (or GIT_NAME/GIT_EMAIL env vars)."
        exit 1
    fi
fi

echo "🚀 macOS Bootstrap Script"
echo "========================="

if [[ "$MINIMAL_MODE" == "true" ]]; then
    export MAC_DOTFILES_MINIMAL=1
    log_info "Minimal mode enabled: full Homebrew bundle will be skipped"
fi

SUDO_KEEPALIVE_PID=""
start_sudo_keepalive() {
    while true; do
        sudo -n true
        sleep 60
        kill -0 "$$" || exit
    done 2>/dev/null &
    SUDO_KEEPALIVE_PID=$!
}

stop_sudo_keepalive() {
    if [[ -n "${SUDO_KEEPALIVE_PID}" ]]; then
        kill "${SUDO_KEEPALIVE_PID}" &>/dev/null || true
    fi
}

ensure_sudo_for_homebrew_install() {
    if sudo -n true 2>/dev/null; then
        start_sudo_keepalive
        trap stop_sudo_keepalive EXIT
        return 0
    fi

    echo ""
    echo -e "${YELLOW}⚠️  Installing Homebrew may require administrator privileges.${NC}"
    echo "You may be prompted for your password by Homebrew or macOS command line tools."
    echo ""

    if sudo -v; then
        start_sudo_keepalive
        trap stop_sudo_keepalive EXIT
        return 0
    fi

    log_error "Failed to obtain sudo privileges. Please make sure you have administrator access."
}

print_install_summary() {
    local warning_count=0

    summary_ok() {
        echo -e "  ${GREEN}✓${NC} $1"
    }

    summary_warn() {
        echo -e "  ${YELLOW}⚠${NC} $1"
        warning_count=$((warning_count + 1))
    }

    echo ""
    echo "📋 Install summary"
    echo "=================="
    echo "Checks:"

    if command -v brew >/dev/null 2>&1; then
        summary_ok "Homebrew available at $(brew --prefix 2>/dev/null || echo unknown)"
    else
        summary_warn "Homebrew is missing or not in PATH"
    fi

    if command -v chezmoi >/dev/null 2>&1; then
        summary_ok "chezmoi available"
    else
        summary_warn "chezmoi is missing or not in PATH"
    fi

    if [[ "$DOTFILES_APPLIED" == "true" ]]; then
        summary_ok "Dotfiles applied"
    else
        summary_warn "Dotfiles were not applied"
    fi

    if [[ -x "$HOME/.local/bin/mac-dotfiles.sh" ]]; then
        summary_ok "Launcher installed: mac-dotfiles.sh"
    else
        summary_warn "Launcher is missing; run 'chezmoi apply' or 'mac-dotfiles.sh repair' after opening a new shell"
    fi

    if [[ -x "$HOME/.local/bin/mac-dotfiles-maintenance.sh" ]]; then
        summary_ok "Maintenance script installed"
    else
        summary_warn "Maintenance script is missing"
    fi

    if [[ "$MINIMAL_MODE" == "true" ]]; then
        summary_ok "Full Homebrew bundle skipped for minimal setup"
    elif command -v brew >/dev/null 2>&1 && [[ -f "$HOME/.Brewfile" ]]; then
        if brew bundle check --global --quiet >/dev/null 2>&1; then
            summary_ok "Homebrew bundle satisfied"
        else
            summary_warn "Homebrew bundle still has missing or outdated items"
        fi
    else
        summary_warn "Homebrew bundle could not be checked"
    fi

    if command -v gh >/dev/null 2>&1; then
        if gh auth status >/dev/null 2>&1; then
            summary_ok "GitHub CLI authenticated"
        else
            summary_warn "GitHub CLI is installed but not authenticated"
        fi
    else
        summary_warn "GitHub CLI is not installed yet"
    fi

    if [[ -f "$HOME/Library/LaunchAgents/com.chezmoi.mac-dotfiles.maintenance.plist" ]]; then
        summary_ok "Maintenance LaunchAgent plist present"
    else
        summary_warn "Maintenance LaunchAgent plist is missing"
    fi

    echo ""
    if [[ "$warning_count" -eq 0 ]]; then
        echo -e "${GREEN}Everything looks squared away.${NC}"
    else
        echo -e "${YELLOW}${warning_count} item(s) may need attention.${NC}"
        echo "Run 'mac-dotfiles.sh repair' after opening a new shell to reconcile the machine."
    fi
}

# Verify macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    log_error "This script is only for macOS"
fi

require_command curl
ensure_brew_in_path

# Install Homebrew
if ! command -v brew &>/dev/null; then
    log_info "Installing Homebrew..."
    ensure_sudo_for_homebrew_install
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    # Add Homebrew to PATH for Apple Silicon
    if [[ $(uname -m) == 'arm64' ]]; then
        # shellcheck disable=SC2016 # We intentionally persist this exact command string into .zprofile.
        BREW_SHELLENV_LINE='eval "$(/opt/homebrew/bin/brew shellenv)"'
        ensure_zprofile_line "$BREW_SHELLENV_LINE"
        eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
else
    ensure_brew_in_path
    log_info "Homebrew already installed"
fi

# Make chezmoi-managed helper scripts available in new shells.
# shellcheck disable=SC2016 # We intentionally persist this exact command string into .zprofile.
ensure_zprofile_line 'export PATH="$HOME/.local/bin:$PATH"'

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
    log_info "Syncing and applying existing dotfiles..."
    chezmoi update --apply --force --no-tty </dev/null
    DOTFILES_APPLIED="true"
else
    log_info "Initializing chezmoi with your dotfiles..."
    if [[ "$AUTO_MODE" == "true" ]]; then
        log_info "Running in auto mode (non-interactive)"
        chezmoi init --apply --promptBool=false --promptInt=false --promptString=false \
            --data "name=$GIT_NAME" --data "email=$GIT_EMAIL" richeju/mac-dotfiles </dev/null
    else
        chezmoi init --apply --promptBool=false --promptInt=false --promptString=false \
            richeju/mac-dotfiles </dev/null
    fi
    DOTFILES_APPLIED="true"
fi

echo ""
echo -e "${GREEN}✨ Setup completed successfully!${NC}"
echo ""
if [[ "$DOTFILES_APPLIED" == "true" ]]; then
    echo "Your dotfiles have been applied with chezmoi."
else
    echo "Chezmoi is installed and ready. Run 'chezmoi update --apply' to sync and apply your dotfiles."
fi
if [[ "$MINIMAL_MODE" == "true" ]]; then
    echo "Minimal setup completed. Run 'mac-dotfiles.sh repair' when ready to install and reconcile all packages."
fi
print_install_summary
echo ""
echo "Useful commands:"
echo "  mac-dotfiles.sh   - Optional local launcher"
echo "  mac-dotfiles.sh repair - Reconcile dotfiles, packages, and health checks"
echo "  chezmoi diff     - See what would change"
echo "  chezmoi apply    - Apply changes"
echo "  chezmoi update   - Pull and apply latest changes"
echo "  chezmoi edit X   - Edit a dotfile"
echo ""
