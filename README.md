# mac-dotfiles

Automatic installation and configuration script for new macOS setup using [chezmoi](https://www.chezmoi.io/)

## 🚀 One-Button Setup

On a new Mac, an already configured Mac, or a machine that needs repair, run:

```bash
curl -fsSL https://raw.githubusercontent.com/richeju/mac-dotfiles/main/install.sh | bash
```

This is the main entrypoint. It installs missing prerequisites, initializes or updates chezmoi, applies managed files non-interactively, repairs missing managed helpers, and then exits.

When Homebrew is already installed, the installer does not request administrator privileges. A password may still be required on a fresh Mac if Homebrew or macOS command line tools need to be installed.

At the end, the installer prints a compact summary of what is ready and what may still need attention, then points to `mac-dotfiles.sh repair` for post-install reconciliation.

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

Minimal mode (core setup now, full apps later):
```bash
curl -fsSL https://raw.githubusercontent.com/richeju/mac-dotfiles/main/install.sh | bash -s -- --minimal
```

Minimal mode installs/applies the core dotfiles flow but skips the full Homebrew bundle during the chezmoi run. Later, run `mac-dotfiles.sh repair` to install and reconcile all packages.

Select a persistent machine profile during bootstrap:
```bash
curl -fsSL https://raw.githubusercontent.com/richeju/mac-dotfiles/main/install.sh | \
  bash -s -- --profile developer
```

Profiles and `--minimal` are intentionally different: `--minimal` skips package installation once, while `--profile minimal` defines the persistent desired package set for that Mac.

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
- Ongoing updates: the managed maintenance scripts run `chezmoi update --apply`, `brew update`, `brew upgrade --formula`, `brew upgrade --cask --greedy`, cleanup, and diagnostics.
- Readiness checks: `install.sh --verify` audits Homebrew, chezmoi, `~/.Brewfile`, package status, GitHub CLI/auth, and maintenance files without changing the machine.

Some macOS apps can still require manual approval or an administrator password during cask upgrades. For example, Dropbox may ask for Privacy & Security approval or sudo access for its system extension. In that case, the maintenance script reports a warning and continues so the rest of the machine stays up to date.

## 📦 What Gets Installed

### Bootstrap Tools
- **Homebrew**: macOS package manager
- **chezmoi**: dotfiles manager
- **Git**, **curl**, and **zsh**: macOS bootstrap tools

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
- **ripgrep**, **yq**, and **zoxide**: search, YAML, and navigation helpers
- **shellcheck** and **shfmt**: shell quality tooling
- **Node.js 24**: pinned LTS JavaScript runtime

## 🧭 Declarative Profiles and Convergence

The active profile is stored per Mac in the chezmoi configuration. Available profiles are:

- `minimal`: bootstrap essentials only
- `personal`: personal applications and power-user CLI tools
- `developer`: personal profile plus Go and Python toolchains
- `gaming`: personal profile plus Discord and GeForce NOW
- `full`: the complete current setup; this is the backward-compatible default

Changing a profile only changes the desired state. It never installs or removes anything immediately:

```bash
mac-dotfiles.sh profile list
mac-dotfiles.sh profile set developer
mac-dotfiles.sh plan
```

Inspect and apply the desired state:

```bash
mac-dotfiles.sh plan                 # read-only; always exits 0 when inspection succeeds
mac-dotfiles.sh plan --json          # strict machine-readable plan
mac-dotfiles.sh drift                # 0=clean, 1=drift, 2=inspection error
mac-dotfiles.sh converge --dry-run   # plan alias
mac-dotfiles.sh converge             # confirmed transactional apply
mac-dotfiles.sh converge --yes       # unattended apply
```

Each convergence creates a versioned transaction under `~/.local/state/mac-dotfiles/transactions/`. It snapshots all managed files and symlinks, the chezmoi configuration, direct Homebrew formulae, and installed casks. Blocking validation checks dotfile convergence, Homebrew dependencies, and the LaunchAgent plist.

If an apply or validation step fails, managed files are restored automatically, files created by the failed apply are removed, newly installed direct formulae/casks are removed on a best-effort basis, and the transaction is marked `rolled_back` or `rollback_failed`. Homebrew cannot restore older package versions or application data, so package rollback is deliberately described as best effort.

Manual transaction rollback first preserves the current files under `~/.local/state/mac-dotfiles/transaction-rollback-backups/`, then restores the selected snapshot. It deliberately leaves Homebrew packages untouched to avoid removing software installed legitimately after an older transaction.

Manual security items such as FileVault, firewall, Time Machine, and macOS updates remain advisory and never trigger a convergence rollback.

Repository evolution is handled by sequential, idempotent scripts under `migrations/`. The current schema version is stored locally in `~/.local/state/mac-dotfiles/schema-version`; convergence applies pending migrations under the same operation lock before changing the desired state.

For a stronger release or machine check, `mac-dotfiles.sh certify` runs the full test suite, formatting and static analysis, profile rendering, migration-catalog validation, transaction fault injection, and live idempotence validation. It writes a versioned JSON attestation to `~/.local/state/mac-dotfiles/certifications/`; use `--skip-live` for CI or a repository-only check.

The proactive watchdog runs after scheduled maintenance and records a versioned health state under `~/.local/state/mac-dotfiles/watchdog/state.json`. It monitors desired-state drift, certification age/result, recovery snapshot age, and maintenance freshness. Native macOS notifications are emitted only when severity changes, when an unresolved alert exceeds its six-hour cooldown, or when the machine returns to healthy.

```bash
mac-dotfiles.sh status                 # latest human-readable health state
mac-dotfiles.sh status --json          # machine-readable state
mac-dotfiles.sh watch run              # evaluate now and notify if needed
mac-dotfiles.sh watch run --no-notify  # evaluate silently
mac-dotfiles.sh watch test warning     # send a sample notification
```

Default freshness thresholds are 7 days for certification, 30 days for recovery snapshots, and 2 days for maintenance. They can be overridden with `MAC_DOTFILES_CERTIFICATION_MAX_AGE_SECONDS`, `MAC_DOTFILES_SNAPSHOT_MAX_AGE_SECONDS`, `MAC_DOTFILES_MAINTENANCE_MAX_AGE_SECONDS`, and `MAC_DOTFILES_WATCHDOG_COOLDOWN_SECONDS`.

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
Applied on install and again whenever the managed baseline changes, with practical, low-friction hardening defaults:
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
- Proactive health evaluation and transition-based native notifications
- Scheduled every day at 04:00

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
- repair/reconcile this Mac
- safe update with backups
- roll back files from a safe-update backup
- inspect and prune update history
- update dotfiles
- generate a machine report
- run doctor
- run maintenance
- show `chezmoi diff`
- inspect or select the active profile
- preview desired-state drift
- run a transactional convergence
- inspect and restore convergence transactions
- inspect/apply repository schema migrations
- generate a reproducible certification attestation
- create, inspect, verify, and transactionally restore disaster-recovery snapshots
- inspect or run the proactive health watchdog

You can also call commands directly:
```bash
mac-dotfiles.sh verify
mac-dotfiles.sh repair
mac-dotfiles.sh safe-update
mac-dotfiles.sh rollback latest --dry-run
mac-dotfiles.sh history
mac-dotfiles.sh report
mac-dotfiles.sh doctor
mac-dotfiles.sh explain
mac-dotfiles.sh profile current
mac-dotfiles.sh plan
mac-dotfiles.sh drift
mac-dotfiles.sh converge
mac-dotfiles.sh transactions
mac-dotfiles.sh tx-rollback latest --yes
mac-dotfiles.sh migrate plan --json
mac-dotfiles.sh migrate apply
mac-dotfiles.sh certify --markdown --output ~/mac-dotfiles-certification.md
mac-dotfiles.sh recovery create --encrypt
mac-dotfiles.sh recovery list
mac-dotfiles.sh recovery inspect /path/to/snapshot.tar.gz.enc
mac-dotfiles.sh recovery restore /path/to/snapshot.tar.gz.enc --dry-run
mac-dotfiles.sh status
mac-dotfiles.sh watch run --no-notify
```

Use `mac-dotfiles.sh repair` after the initial install whenever you want to put the Mac back into the expected state. It fast-forwards the desired-state source, runs a confirmed transactional convergence, applies safe doctor auto-fixes, and writes `~/mac-dotfiles-repair-report.md`.

#### Create and restore a disaster-recovery snapshot

```bash
mac-dotfiles.sh recovery create
mac-dotfiles.sh recovery create --encrypt --output ~/Documents/mac-recovery.tar.gz.enc
mac-dotfiles.sh recovery verify ~/Documents/mac-recovery.tar.gz.enc
mac-dotfiles.sh recovery restore ~/Documents/mac-recovery.tar.gz.enc --dry-run
mac-dotfiles.sh recovery restore ~/Documents/mac-recovery.tar.gz.enc --yes
```

Snapshots use a versioned manifest and SHA-256 checksums. They contain an explicit allowlist of managed configuration, the active schema/profile metadata, and Homebrew inventories. Passwords, tokens, SSH keys, browser data, and application data are excluded. `--encrypt` uses AES-256-CBC with PBKDF2 and asks for a password without storing it.

For non-interactive automation, point `MAC_DOTFILES_RECOVERY_PASSWORD_FILE` to a permission-restricted file; OpenSSL reads the password from that file and its value never appears in the process arguments. Snapshots and rollback artifacts are created with owner-only permissions, snapshot writes are atomic, and verification rejects duplicate/missing checksums, mismatched manifests, unsafe archive paths, symlink payloads, and any restore target outside the documented allowlist.

Restore verifies every checksum before showing its plan. It preserves the current files under `~/.local/state/mac-dotfiles/recovery-rollbacks/`, restores transactionally under the shared operation lock, and rolls back automatically if a file cannot be replaced. Homebrew inventories remain advisory; convergence performs package reconciliation afterward.

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

The doctor script validates core dependencies, versions, Homebrew bundle status, pending chezmoi changes, managed symlinks, FileVault, firewall, Gatekeeper, Time Machine, macOS updates, and scheduled maintenance health. `--json` emits one strict JSON document suitable for `jq` and CI.

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

#### Roll back a safe update
```bash
mac-dotfiles.sh rollback latest --dry-run
mac-dotfiles.sh rollback latest
```

Rollback restores the managed files captured by a safe update. It shows the selected files first, asks for confirmation, and saves the current versions under `~/.local/state/mac-dotfiles/rollback-backups/` before replacing them. Use a timestamp such as `20260710-103000` instead of `latest` to select a specific run, or add `--yes` for non-interactive use.

#### Inspect and prune history
```bash
mac-dotfiles.sh history
mac-dotfiles.sh history --prune --keep 10
```

History lists safe-update runs and rollback backups with their size and file count. Pruning keeps the newest entries of each type, shows a deletion plan, and requires confirmation unless `--yes` is provided.

#### Update from repository
```bash
chezmoi update --apply
```

### Adding Applications

Edit the appropriate fragment under `profiles/` on GitHub or locally. For example:
```bash
$EDITOR ~/.local/share/chezmoi/profiles/personal.Brewfile
```

Then preview and converge:
```bash
mac-dotfiles.sh plan
mac-dotfiles.sh converge
```

The generated `~/.Brewfile` should not be edited directly.

## 📁 Repository Structure

### Brewfile Strategy

This repository uses one canonical Homebrew template: `dot_Brewfile.tmpl`, composed from declarative fragments under `profiles/` and rendered by chezmoi to `~/.Brewfile`.

The `run_onchange_install-packages-darwin.sh.tmpl` script installs from `~/.Brewfile` using:

```bash
brew bundle --global --verbose
```

- `dot_Brewfile.tmpl` - Profile-aware template rendered to `~/.Brewfile`
- `profiles/*.Brewfile` - Composable desired package sets
- `dot_gitconfig.tmpl` - Git configuration template
- `dot_zprofile` - Shell profile that enables Homebrew and `~/.local/bin`
- `install.sh` - Initial installation script
- `doctor.sh` - Health check script for dependencies and dotfile status
- `lib/doctor_output.sh` - JSON, Markdown, and explanation renderers used by the health check
- `tests/test_suite.sh` - Syntax validation and entry point for the complete shell test suite
- `migrations/*.sh` - Ordered, idempotent repository schema migrations
- `dot_local/bin/executable_mac-dotfiles.sh.tmpl` - Compact launcher/menu for common workflows
- `dot_local/bin/executable_mac-dotfiles-converge.sh.tmpl` - Profile, plan, drift, transaction, validation, and rollback engine
- `dot_local/bin/executable_mac-dotfiles-migrate.sh.tmpl` - Versioned schema migration planner and runner
- `dot_local/bin/executable_mac-dotfiles-certify.sh.tmpl` - Versioned repository and live-machine certification attestation
- `dot_local/bin/executable_mac-dotfiles-recovery.sh.tmpl` - Portable, optionally encrypted disaster-recovery snapshots and transactional restore
- `dot_local/bin/executable_mac-dotfiles-watchdog.sh.tmpl` - Proactive health state, cooldown, and native macOS notifications
- `run_onchange_configure-dock-darwin.sh.tmpl` - Dock configuration reapplied when its desired values change
- `run_onchange_configure-finder-and-inputs-darwin.sh` - Finder and input comfort defaults, reapplied when the baseline changes
- `run_onchange_harden-macos-baseline-darwin.sh` - macOS hardening baseline, reapplied when the baseline changes
- `run_onchange_install-packages-darwin.sh.tmpl` - Package installer (runs when Brewfile changes)
- `run_onchange_update-and-cleanup-darwin.sh.tmpl` - Maintenance script triggered when template changes
- `dot_local/bin/executable_mac-dotfiles-maintenance.sh.tmpl` - Daily maintenance runner written to `~/.local/bin`
- `dot_local/bin/executable_mac-dotfiles-brew-maintenance.sh.tmpl` - Shared Homebrew maintenance helper used by scheduled and on-change tasks
- `dot_local/bin/executable_mac-dotfiles-report.sh.tmpl` - Markdown machine report generator written to `~/.local/bin`
- `dot_local/bin/executable_mac-dotfiles-safe-update.sh.tmpl` - Safe update wrapper with before/after reports, backups, and saved diff
- `dot_local/bin/executable_mac-dotfiles-rollback.sh.tmpl` - Confirmed or dry-run restoration from safe-update backups
- `dot_local/bin/executable_mac-dotfiles-history.sh.tmpl` - Backup history listing and retention cleanup
- `dot_Library/LaunchAgents/com.chezmoi.mac-dotfiles.maintenance.plist.tmpl` - LaunchAgent scheduled daily at 04:00
- `run_onchange_enable-maintenance-launchagent-darwin.sh.tmpl` - Validates and reloads the LaunchAgent whenever its definition changes


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
