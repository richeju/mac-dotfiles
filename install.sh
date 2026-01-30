#!/bin/bash

# Script d'installation pour nouveau Mac
# Usage: curl -fsSL https://raw.githubusercontent.com/richeju/mac-dotfiles/main/install.sh | bash

set -e

echo "🚀 Installation des outils de base pour macOS..."

# Couleurs pour les messages
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}✓${NC} $1"; }
log_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1"; exit 1; }

# Vérifier macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    log_error "Ce script est uniquement pour macOS"
fi

# Installer Homebrew
if ! command -v brew &> /dev/null; then
    log_info "Installation de Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    
    # Ajouter Homebrew au PATH pour Apple Silicon
    if [[ $(uname -m) == 'arm64' ]]; then
        echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
        eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
else
    log_info "Homebrew déjà installé"
    log_info "Mise à jour de Homebrew..."
    brew update
fi

# Installer les outils de base
log_info "Installation des outils essentiels..."

brew_packages=(
    git
    wget
    curl
    vim
    zsh
)

for package in "${brew_packages[@]}"; do
    if brew list "$package" &>/dev/null; then
        log_info "$package déjà installé"
    else
        log_info "Installation de $package..."
        brew install "$package"
    fi
done

# Configuration Git
log_info "Configuration de Git..."
if [ -z "$(git config --global user.name)" ]; then
    read -p "Entrez votre nom pour Git: " git_name
    git config --global user.name "$git_name"
fi

if [ -z "$(git config --global user.email)" ]; then
    read -p "Entrez votre email pour Git: " git_email
    git config --global user.email "$git_email"
fi

git config --global init.defaultBranch main
git config --global pull.rebase false
git config --global core.editor vim

log_info "Configuration de base terminée!"

echo ""
echo "${GREEN}✨ Installation terminée avec succès!${NC}"
echo ""
echo "Outils installés:"
for package in "${brew_packages[@]}"; do
    echo "  • $package"
done
echo ""
echo "Configuration Git:"
echo "  • Nom: $(git config --global user.name)"
echo "  • Email: $(git config --global user.email)"
echo ""
