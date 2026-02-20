# mac-dotfiles

Automatic installation and configuration script for new macOS setup using [chezmoi](https://www.chezmoi.io/)

## 🚀 Quick Installation

On a new Mac, run one of these in Terminal:

Safer path (recommended):
```bash
curl -fsSL -o /tmp/mac-dotfiles-install.sh https://raw.githubusercontent.com/richeju/mac-dotfiles/main/install.sh
less /tmp/mac-dotfiles-install.sh
bash /tmp/mac-dotfiles-install.sh
```

Fast path:
```bash
curl -fsSL https://raw.githubusercontent.com/richeju/mac-dotfiles/main/install.sh | bash
```

Zero-interaction mode (for full automation):
```bash
curl -fsSL https://raw.githubusercontent.com/richeju/mac-dotfiles/main/install.sh | bash -s -- --auto --git-name "Your Name" --git-email "you@example.com"
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

### macOS Hardening Baseline
Automatically applied once (via chezmoi `run_once_*`) with practical, low-friction hardening defaults:
- Require password immediately after sleep/screensaver lock
- Always show filename extensions
- Show hidden files in Finder
- Keep extension change warning enabled
- Keep downloaded files quarantined (`LSQuarantine`)
- Disable Safari auto-open of downloaded files
- Enable Safari Do Not Track and disable search suggestions

This is a lightweight baseline inspired by common NIST/CIS hardening themes for endpoint visibility, session lock enforcement, and safer handling of downloaded content.

### Automated Maintenance
Daily automatic tasks (via macOS LaunchAgent):
- Homebrew update
- Package upgrades
- Application (cask) upgrades
- Cleanup old versions
- System diagnostics
- Cache statistics
- Scheduled every day at 04:00 + at login


### Fully Automated Installation

If you want a fully unattended setup, use `--auto` with Git identity values:

```bash
bash install.sh --auto --git-name "Your Name" --git-email "you@example.com"
```

You can also use environment variables:

```bash
AUTO=1 GIT_NAME="Your Name" GIT_EMAIL="you@example.com" bash install.sh
```

## 📚 Usage

### Managing Your Dotfiles

#### Edit configuration files
```bash
chezmoi edit ~/.gitconfig
```

#### Apply changes
```bash
chezmoi apply
```

#### See what would change
```bash
chezmoi diff
```

#### Add new dotfiles
```bash
chezmoi add ~/.zshrc
```

#### Run a health check
```bash
./doctor.sh
```

Optional modes:
```bash
./doctor.sh --fix   # attempt safe auto-fixes (brew bundle + chezmoi apply)
./doctor.sh --json  # emit a JSON summary report
./doctor.sh --markdown  # emit a Markdown report (for issue/PR copy-paste)
```

The doctor script validates core dependencies (`git`, `curl`, `brew`, `chezmoi`), checks minimum versions for `git` and `chezmoi`, verifies Homebrew bundle status, confirms whether there are pending chezmoi changes, and detects broken symlinks for key managed files.

When run outside macOS (for example in Linux CI or a dev container), `doctor.sh` reports warnings for the platform and missing macOS tools (`brew`, `chezmoi`) by design.

#### Update from repository
```bash
chezmoi update --apply
```

### Adding Applications

Edit `dot_Brewfile` on GitHub or locally:
```bash
chezmoi edit ~/.Brewfile
```

Then update:
```bash
chezmoi update --apply
```

Applications will be automatically installed!

## 📁 Repository Structure

### Brewfile Strategy

This repository uses two Homebrew manifests for different purposes:

- `Brewfile`: a repo-level list for bootstrap/development references.
- `dot_Brewfile`: the user-level list rendered by chezmoi to `~/.Brewfile`.

The `run_onchange_install-packages-darwin.sh.tmpl` script installs from `~/.Brewfile` using:

```bash
brew bundle --global --verbose
```

- `Brewfile` - Bootstrap/development packages tracked in the repo
- `dot_Brewfile` - Rendered to `~/.Brewfile`, used by `brew bundle --global`
- `dot_gitconfig.tmpl` - Git configuration template
- `install.sh` - Initial installation script
- `doctor.sh` - Health check script for dependencies and dotfile status
- `run_once_configure-dock-darwin.sh` - Dock configuration (runs once)
- `run_once_harden-macos-baseline-darwin.sh` - Applies a one-time macOS hardening baseline
- `run_onchange_install-packages-darwin.sh.tmpl` - Package installer (runs when Brewfile changes)
- `run_onchange_update-and-cleanup-darwin.sh.tmpl` - Maintenance script triggered when template changes
- `dot_local/bin/executable_mac-dotfiles-maintenance.sh.tmpl` - Daily maintenance runner written to `~/.local/bin`
- `dot_Library/LaunchAgents/com.chezmoi.mac-dotfiles.maintenance.plist.tmpl` - LaunchAgent scheduled at 04:00 + run at login
- `run_once_enable-maintenance-launchagent-darwin.sh.tmpl` - Loads/enables the LaunchAgent automatically

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
chezmoi update
```

To update and apply changes:

```bash
chezmoi update --apply
```

## 👏 Contributing

This is a personal dotfiles repository, but feel free to fork it and adapt it to your needs!

## 📝 License

MIT
