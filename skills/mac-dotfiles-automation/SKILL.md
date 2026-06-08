---
name: mac-dotfiles-automation
description: Use this skill when you need to automate setup, updates, maintenance, or health checks for this mac-dotfiles repository on macOS. It provides a minimal workflow for unattended install, recurring maintenance, and verification commands.
---

# mac-dotfiles automation

## When to use
Use this skill when the user asks to:
- automate initial setup of a new Mac,
- run unattended package/dotfiles updates,
- schedule or verify maintenance,
- run repository health checks,
- explain diagnostic warnings,
- use the compact `mac-dotfiles.sh` launcher,
- generate a machine report,
- run a safe update with before/after artifacts.

## Workflow
1. **Validate platform and tools**
   - Prefer macOS for full functionality.
   - Check required commands: `git`, `curl`, `bash`.

2. **Automated bootstrap**
   - For unattended install, run `install.sh --auto --git-name ... --git-email ...`.
   - For a no-change readiness audit, run `install.sh --verify`.
   - Use `scripts/auto-bootstrap.sh` for a ready-to-run wrapper.

3. **Apply dotfiles and packages**
   - For interactive local use, prefer the compact launcher: `mac-dotfiles.sh`.
   - Apply latest state with `chezmoi update --apply`.
   - Ensure packages are reconciled with `brew bundle --global --verbose`.
   - For an auditable update, prefer `~/.local/bin/mac-dotfiles-safe-update.sh` when available.

4. **Run maintenance and validation**
   - Run `~/.local/bin/mac-dotfiles-maintenance.sh` when available.
   - Generate a Markdown machine report with `~/.local/bin/mac-dotfiles-report.sh` when available.
   - Run `./doctor.sh` (or `./doctor.sh --json` in CI-like flows).
   - Use `./doctor.sh --explain` or `mac-dotfiles.sh explain` when warnings need actionable guidance.

5. **Troubleshoot quickly**
   - If Homebrew is missing, re-run bootstrap script.
   - If chezmoi is missing, install via Homebrew then `chezmoi init --apply`.
   - If LaunchAgent is not loaded, run the repo `run_once_enable-maintenance-launchagent-darwin.sh.tmpl` logic through chezmoi apply.

## Outputs to provide
- Commands executed
- Whether bootstrap succeeded
- Whether doctor checks passed
- Where reports/backups were written, if generated
- Next manual step only if a hard blocker exists (e.g., macOS-only setting on Linux)
