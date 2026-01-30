# mac-dotfiles

Automatic installation and configuration script for new macOS setup using [chezmoi](https://www.chezmoi.io/)

## 🚀 Quick Installation

On a new Mac, run this command in Terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/richeju/mac-dotfiles/main/install.sh | bash
```

## 📦 What Gets Installed

### Essential Tools
- **Homebrew**: macOS package manager
- **chezmoi**: Dotfiles manager
- **Git**: version control system
- **wget**: file downloader
- **curl**: data transfer tool
- **vim**: text editor
- **zsh**: modern shell

### Applications (via Brewfile)
- **VLC**: Media player
- **NVIDIA GeForce NOW**: Cloud gaming platform
- **Discord**: Gaming communication
- **Bitwarden**: Password manager
- **Dropbox**: Cloud storage
- **Raycast**: Productivity launcher

### Additional CLI Tools (Brewfile)
- **jq**: command-line JSON processor
- **tree**: directory structure visualization
- **htop**: interactive process viewer
- **bat**: improved cat with syntax highlighting
- **fzf**: fuzzy finder

## ⚙️ Automatic Configurations

### Git Configuration
Interactive prompts for:
- Your name for Git commits
- Your email for Git commits

Automatic settings:
- Default branch: `main`
- Pull rebase: `false`
- Default editor: `vim`

### Dock Configuration
Automatically configured on first run:
- Icon size: 48px
- Auto-hide enabled
- Instant display (no delay)
- Fast animation (0.5s)
- Recent apps section disabled
- Scale minimize effect
- Minimize to application
- Process indicators enabled

### Automated Maintenance
Daily automatic tasks:
- Homebrew update
- Package upgrades
- Application (cask) upgrades
- Cleanup old versions
- System diagnostics
- Cache statistics

## 📚 Usage

### Managing Your Dotfiles

#### Edit configuration files
```bash
chemzoi edit ~/.gitconfig
```

#### Apply changes
```bash
chemzoi apply
```

#### See what would change
```bash
chemzoi diff
```

#### Add new dotfiles
```bash
chemzoi add ~/.zshrc
```

#### Update from repository
```bash
chemzoi update --apply
```

### Adding Applications

Edit `dot_Brewfile` on GitHub or locally:
```bash
chemzoi edit ~/.Brewfile
```

Then update:
```bash
chemzoi update --apply
```

Applications will be automatically installed!

## 📁 Repository Structure

- `.chezmoi.toml.tmpl` - chezmoi configuration template
- `.chezmoiignore` - Files to ignore
- `Brewfile` - Initial Homebrew packages
- `dot_Brewfile` - User Homebrew packages
- `dot_gitconfig.tmpl` - Git configuration template
- `install.sh` - Initial installation script
- `run_once_configure-dock-darwin.sh` - Dock configuration (runs once)
- `run_onchange_install-packages-darwin.sh.tmpl` - Package installer (runs when Brewfile changes)
- `run_onchange_update-and-cleanup-darwin.sh.tmpl` - Maintenance script (runs daily)

## ℹ️ Notes

- Compatible with **macOS** only (Intel and Apple Silicon)
- Scripts check for existing installations before proceeding
- Already installed tools are skipped
- Interactive Git configuration if not already configured
- Automatic maintenance runs once per day

## 🔐 Security

The scripts are **public** and can be audited before execution. No sensitive information is stored in this repository. The `.chezmoiignore` file protects sensitive files from being tracked.

## 🔄 Updating

To pull the latest changes from this repository:

```bash
chemzoi update
```

To update and apply changes:

```bash
chemzoi update --apply
```

## 👏 Contributing

This is a personal dotfiles repository, but feel free to fork it and adapt it to your needs!

## 📝 License

MIT
