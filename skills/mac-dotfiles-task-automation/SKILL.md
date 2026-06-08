---
name: mac-dotfiles-task-automation
description: Use this skill when the user asks to automate repetitive repository operations for mac-dotfiles, such as bootstrap, update, verification, or scheduled maintenance command chains. It provides a deterministic command workflow and a reusable script for unattended runbooks.
---

# mac-dotfiles task automation

## Quick workflow
1. Validate repository context and required commands.
2. Choose an automation profile (`launcher`, `bootstrap`, `update`, `safe-update`, `verify`, `report`, or `maintenance`).
3. Run the matching command chain directly or via `scripts/repo-automation.sh`.
4. Report executed commands, exit status, and any manual follow-up.

## Automation profiles

### 1) Launcher profile
Use for interactive local operation after installation.

Run:
```bash
mac-dotfiles.sh
```

This provides a numbered menu for:
- verify
- safe update
- update
- report
- doctor
- explain
- maintenance
- diff

Direct commands are also available, such as `mac-dotfiles.sh verify`, `mac-dotfiles.sh safe-update`, `mac-dotfiles.sh report`, and `mac-dotfiles.sh explain`.

### 2) Bootstrap profile
Use for first-time setup on a machine.

Run:
```bash
bash scripts/repo-automation.sh bootstrap --git-name "<NAME>" --git-email "<EMAIL>"
```

This runs:
- `./install.sh --auto --git-name ... --git-email ...`
- `./doctor.sh`

### 3) Update profile
Use for regular synchronization and package reconciliation.

Run:
```bash
bash scripts/repo-automation.sh update
```

This runs:
- `chezmoi update --apply`
- `brew bundle --global --verbose`
- `./doctor.sh`

### 4) Safe update profile
Use when changes should leave an auditable before/after trail.

Run:
```bash
~/.local/bin/mac-dotfiles-safe-update.sh
```

This writes timestamped artifacts under `~/.local/state/mac-dotfiles/safe-updates/`:
- `report-before.md`
- `chezmoi.diff`
- `report-after.md`
- backups of key local files

### 5) Verify profile
Use for quick health validation in local checks or CI-like flows.

Run:
```bash
bash scripts/repo-automation.sh verify
```

This runs:
- `./install.sh --verify` (when checking machine readiness)
- `./doctor.sh`
- `./doctor.sh --explain` when warnings need actionable guidance
- repository tests such as `./tests/doctor_test.sh`, `./tests/install_test.sh`, `./tests/report_test.sh`, and `./tests/safe_update_test.sh` when executable

### 6) Report profile
Use to capture a Markdown snapshot of the machine.

Run:
```bash
~/.local/bin/mac-dotfiles-report.sh > ~/mac-dotfiles-report.md
```

This includes system details, tool versions, Homebrew bundle status, GitHub CLI auth, chezmoi state, maintenance state, doctor output, and recent logs.

### 7) Maintenance profile
Use for periodic cleanup and validation.

Run:
```bash
bash scripts/repo-automation.sh maintenance
```

This runs:
- `~/.local/bin/mac-dotfiles-maintenance.sh` (if available)
- `./doctor.sh`

## Failure handling
- Stop on first failing command.
- Surface stderr from the failed command.
- Provide a short recovery step:
  - install missing dependency,
  - re-run only failed profile,
  - inspect the latest safe-update artifact directory,
  - escalate only when command is macOS-specific and host is not macOS.

## Reference
Load `references/command-matrix.md` when you need the exact profile-to-command mapping and preflight checklist.
