# mac-dotfiles

Automatic installation and configuration script for new macOS setup

## 🚀 Quick Installation

On a new Mac, run this command in Terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/richeju/mac-dotfiles/main/install.sh | bash
```

## 📦 What Gets Installed

### Essential Tools
- **Homebrew**: macOS package manager
- **Git**: version control system
- **wget**: file downloader
- **curl**: data transfer tool
- **vim**: text editor
- **zsh**: modern shell

### Git Configuration
The script will prompt you for:
- Your name for Git commits
- Your email for Git commits

Automatic configuration:
- Default branch: `main`
- Pull rebase: `false`
- Default editor: `vim`

## 📝 Manual Usage

If you prefer to download and run the script locally:

```bash
# Clone the repository
git clone https://github.com/richeju/mac-dotfiles.git
cd mac-dotfiles

# Make the script executable
chmod +x install.sh

# Run it
./install.sh
```

## ℹ️ Notes

- Compatible with **macOS** only (Intel and Apple Silicon)
- The script checks if Homebrew is already installed before installing it
- Already installed tools are skipped
- Interactive Git configuration if not already configured

## 🔐 Security

The script is **public** and can be audited before execution. No sensitive information is stored in this repository.


## 📦 Additional Packages

After the initial setup, chezmoi will install additional tools from the Brewfile:

- **jq**: command-line JSON processor
- **tree**: directory structure visualization
- **htop**: interactive process viewer
- **bat**: improved cat with syntax highlighting
- **fzf**: fuzzy finder

## 🔧 Managing Your Dotfiles with chezmoi

Once installed, you can manage your dotfiles with chezmoi:

### Edit configuration files
```bash
chezmoi edit ~/.gitconfig
```

### Apply changes
```bash
chezmoi apply
```

### See what would change
```bash
chezmoi diff
```

### Add new dotfiles
```bash
chezmoi add ~/.zshrc
```

### Update from the repository
```bash
chezmoi update
```
