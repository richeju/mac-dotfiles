#!/usr/bin/env bash

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ok() { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC} $1"; }
has_error=0

check_command() {
    local cmd="$1"
    if command -v "$cmd" >/dev/null 2>&1; then
        ok "Command available: $cmd"
    else
        warn "Missing command: $cmd"
        has_error=1
    fi
}

echo "🩺 mac-dotfiles doctor"
echo "======================="

if [[ "$OSTYPE" == darwin* ]]; then
    ok "Running on macOS"
else
    warn "This repository targets macOS, current OSTYPE is '$OSTYPE'"
fi

check_command git
check_command curl
check_command brew
check_command chezmoi

if command -v brew >/dev/null 2>&1; then
    if brew bundle check --global --quiet; then
        ok "All Homebrew dependencies from ~/.Brewfile are installed"
    else
        warn "Some Homebrew dependencies are missing (run: brew bundle --global --verbose)"
        has_error=1
    fi
fi

if command -v chezmoi >/dev/null 2>&1; then
    if chezmoi diff --quiet; then
        ok "No pending dotfile changes"
    else
        warn "There are pending dotfile changes (run: chezmoi diff / chezmoi apply)"
        has_error=1
    fi
fi

if [[ "$has_error" -eq 0 ]]; then
    echo
    ok "System check completed successfully"
else
    echo
    warn "System check completed with warnings"
    exit 1
fi
