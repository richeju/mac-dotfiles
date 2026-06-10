# mac-dotfiles

Automatic installation and configuration script for new macOS setup using [chezmoi](https://www.chezmoi.io/)

## 🚀 One-Button Setup

On a new Mac, an already configured Mac, or a machine that needs repair, run:

```bash
curl -fsSL https://raw.githubusercontent.com/richeju/mac-dotfiles/main/install.sh | bash
```

This is the main entrypoint. It installs missing prerequisites, initializes or updates chezmoi, applies managed files non-interactively, repairs missing managed helpers, and then exits.

Safer audit-first path:
```bash
curl -fsSL -o /tmp/mac-dotfiles-install.sh https://raw.githubusercontent.com/richeju/mac-dotfiles/main/install.sh
less /tmp/mac-dotfiles-install.sh
bash /tmp/mac-dotfiles-install.sh
```

Zero-interaction mode (for full automation):
```bash
curl -fsSL https://raw.githubusercontent.com/richeju/mac-dotfiles/main/install.sh | bash -s -- --auto --git-name "Your Name" --git-email "you@example.com"
```

Verification mode (no changes, no sudo prompt):
```bash
curl -fsSL https://raw.githubusercontent.com/richeju/mac-dotfiles/main/install.sh | bash -s -- --verify
```

After installation, an optional local launcher is available for day-to-day actions:
```bash
mac-dotfiles.sh
```

The installer adds `~/.local/bin` to your shell `PATH` so managed helper commands such as `mac-dotfiles.sh` are available in new terminal sessions.

## ✅ Fresh Install and Updates

This repository is designed for both:

- A fresh macOS install: `install.sh` installs Homebrew and chezmoi, applies the dotfiles, renders `~/.Brewfile`, then installs the required packages with `brew bundle --global --verbose`.
- Existing installs and repairs: rerunning `install.sh` reconciles managed files with `chezmoi update --apply --force --no-tty`, so missing managed helpers are restored without prompts.
- Ongoing updates: the managed maintenance scripts run `chezmoi update --apply`, `brew update`, `brew upgrade`, `brew upgrade --cask --greedy`, cleanup, and diagnostics.
- Readiness checks: `install.sh --verify` audits Homebrew, chezmoi, `~/.Brewfile`, package status, GitHub CLI/auth, and maintenance files without changing the machine.

Some macOS apps can still require manual approval or an administrator password during cask upgrades. For example, Dropbox may ask for Privacy & Security approval or sudo access for its system extension. In that case, the maintenance script reports a warning and continues so the rest of the machine stays up to date.

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
- Automatic pruning of deleted remote branches on fetch: `true`
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

### Finder & Input Comfort Defaults
Automatically configured on first run:
- Finder status bar enabled
- Finder path bar enabled
- Finder default view set to list view
- Keep folders on top in Finder list view
- Expanded save panels by default
- Faster keyboard repeat settings
- Tap-to-click enabled for trackpads

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
- Dotfiles sync (`chezmoi update --apply`)
- Homebrew update
- Package upgrades
- Application (cask) upgrades
- Cleanup old versions
- System diagnostics
- Cache statistics
- Scheduled every day at 04:00 + at login

You can disable the automatic dotfiles sync by setting `AUTO_CHEZMOI_UPDATE=0` before running the maintenance script manually.

If a cask upgrade needs interactive macOS approval, rerun the specific upgrade manually after approving it in System Settings:

```bash
brew upgrade --cask dropbox
```


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

#### Open the launcher
```bash
mac-dotfiles.sh
```

The launcher provides a compact numbered menu for common actions:
- verify machine readiness
- safe update with backups
- update dotfiles
- generate a machine report
- run doctor
- run maintenance
- show `chezmoi diff`

You can also call commands directly:
```bash
mac-dotfiles.sh verify
mac-dotfiles.sh safe-update
mac-dotfiles.sh report
mac-dotfiles.sh doctor
mac-dotfiles.sh explain
```

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
./doctor.sh --explain  # explain warnings and suggest next commands
```

The doctor script validates core dependencies (`git`, `curl`, `brew`, `chezmoi`), checks minimum versions for `git` and `chezmoi`, verifies Homebrew bundle status, confirms whether there are pending chezmoi changes, and detects broken symlinks for key managed files.

When run outside macOS (for example in Linux CI or a dev container), `doctor.sh` reports warnings for the platform and missing macOS tools (`brew`, `chezmoi`) by design.

#### Generate a machine report
```bash
~/.local/bin/mac-dotfiles-report.sh > ~/mac-dotfiles-report.md
```

The report is Markdown and includes macOS details, core tool versions, Homebrew bundle status, Brewfile formulae/casks, pending chezmoi changes, GitHub CLI auth status, maintenance LaunchAgent state, doctor output, and recent maintenance logs.

#### Run a safe update
```bash
~/.local/bin/mac-dotfiles-safe-update.sh
```

The safe update command creates a timestamped directory under `~/.local/state/mac-dotfiles/safe-updates/`, writes a before report, backs up key local files, saves `chezmoi diff`, runs `chezmoi update --apply`, then writes an after report. Use it when you want an auditable before/after trail around dotfile changes.

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
- `dot_zprofile` - Shell profile that enables Homebrew and `~/.local/bin`
- `install.sh` - Initial installation script
- `doctor.sh` - Health check script for dependencies and dotfile status
- `dot_local/bin/executable_mac-dotfiles.sh.tmpl` - Compact launcher/menu for common workflows
- `run_once_configure-dock-darwin.sh` - Dock configuration (runs once)
- `run_once_configure-finder-and-inputs-darwin.sh` - Finder and input comfort defaults (runs once)
- `run_once_harden-macos-baseline-darwin.sh` - Applies a one-time macOS hardening baseline
- `run_onchange_install-packages-darwin.sh.tmpl` - Package installer (runs when Brewfile changes)
- `run_onchange_update-and-cleanup-darwin.sh.tmpl` - Maintenance script triggered when template changes
- `dot_local/bin/executable_mac-dotfiles-maintenance.sh.tmpl` - Daily maintenance runner written to `~/.local/bin`
- `dot_local/bin/executable_mac-dotfiles-brew-maintenance.sh.tmpl` - Shared Homebrew maintenance helper used by scheduled and on-change tasks
- `dot_local/bin/executable_mac-dotfiles-report.sh.tmpl` - Markdown machine report generator written to `~/.local/bin`
- `dot_local/bin/executable_mac-dotfiles-safe-update.sh.tmpl` - Safe update wrapper with before/after reports, backups, and saved diff
- `dot_Library/LaunchAgents/com.chezmoi.mac-dotfiles.maintenance.plist.tmpl` - LaunchAgent scheduled at 04:00 + run at login
- `run_once_enable-maintenance-launchagent-darwin.sh.tmpl` - Loads/enables the LaunchAgent automatically


## 🤖 Codex Skill (Automation)

This repository now includes a reusable Codex skill at:

- `skills/mac-dotfiles-automation/SKILL.md`

Use it when you want consistent automation flows for unattended bootstrap, maintenance, and health checks in this repo.

A helper wrapper is also provided:

```bash
./skills/mac-dotfiles-automation/scripts/auto-bootstrap.sh --git-name "Your Name" --git-email "you@example.com"
```

## ℹ️ Notes

- Compatible with **macOS** only (Intel and Apple Silicon)
- Scripts check for existing installations before proceeding
- Already installed tools are skipped
- Interactive Git configuration if not already configured
- Automatic maintenance runs once per day
- Cask upgrade failures that require manual macOS approval are reported without blocking the rest of maintenance

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
