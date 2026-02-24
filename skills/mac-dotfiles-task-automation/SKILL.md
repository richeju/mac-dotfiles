---
name: mac-dotfiles-task-automation
description: Use this skill when the user asks to automate repetitive repository operations for mac-dotfiles, such as bootstrap, update, verification, or scheduled maintenance command chains. It provides a deterministic command workflow and a reusable script for unattended runbooks.
---

# mac-dotfiles task automation

## Quick workflow
1. Validate repository context and required commands.
2. Choose an automation profile (`bootstrap`, `update`, `verify`, or `maintenance`).
3. Run the matching command chain directly or via `scripts/repo-automation.sh`.
4. Report executed commands, exit status, and any manual follow-up.

## Automation profiles

### 1) Bootstrap profile
Use for first-time setup on a machine.

Run:
```bash
bash scripts/repo-automation.sh bootstrap --git-name "<NAME>" --git-email "<EMAIL>"
```

This runs:
- `./install.sh --auto --git-name ... --git-email ...`
- `./doctor.sh`

### 2) Update profile
Use for regular synchronization and package reconciliation.

Run:
```bash
bash scripts/repo-automation.sh update
```

This runs:
- `chezmoi update --apply`
- `brew bundle --global --verbose`
- `./doctor.sh`

### 3) Verify profile
Use for quick health validation in local checks or CI-like flows.

Run:
```bash
bash scripts/repo-automation.sh verify
```

This runs:
- `./doctor.sh`
- `./tests/doctor_test.sh` (if executable)

### 4) Maintenance profile
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
  - escalate only when command is macOS-specific and host is not macOS.

## Reference
Load `references/command-matrix.md` when you need the exact profile-to-command mapping and preflight checklist.
