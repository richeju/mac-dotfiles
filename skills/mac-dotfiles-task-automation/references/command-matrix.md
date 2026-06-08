# Command matrix

## Preflight checklist
- Run from repository root.
- Ensure `bash`, `git`, and `curl` are present.
- For `update`, `safe-update`, `report`, and `maintenance`, expect `chezmoi` and Homebrew (`brew`) to be installed.

## Profile mappings

### launcher
1. `mac-dotfiles.sh`
2. For non-interactive runs, use direct launcher commands such as `mac-dotfiles.sh verify`, `mac-dotfiles.sh safe-update`, `mac-dotfiles.sh report`, or `mac-dotfiles.sh doctor`

### bootstrap
1. `./install.sh --auto --git-name "<NAME>" --git-email "<EMAIL>"`
2. `./doctor.sh`

### update
1. `chezmoi update --apply`
2. `brew bundle --global --verbose`
3. `./doctor.sh`

### safe-update
1. `~/.local/bin/mac-dotfiles-safe-update.sh`
2. Report the timestamped artifact directory under `~/.local/state/mac-dotfiles/safe-updates/`

### verify
1. `./install.sh --verify`
2. `./doctor.sh`
3. `./tests/install_test.sh` (run only when executable)
4. `./tests/doctor_test.sh` (run only when executable)
5. `./tests/report_test.sh` (run only when executable)
6. `./tests/safe_update_test.sh` (run only when executable)

### report
1. `~/.local/bin/mac-dotfiles-report.sh > ~/mac-dotfiles-report.md`
2. Report the generated Markdown path

### maintenance
1. `~/.local/bin/mac-dotfiles-maintenance.sh` (run only when present and executable)
2. `./doctor.sh`

## Reporting format
After execution, report:
- selected profile,
- commands attempted in order,
- generated report/backup paths,
- first failure (if any),
- final status (`success` or `failed`).
