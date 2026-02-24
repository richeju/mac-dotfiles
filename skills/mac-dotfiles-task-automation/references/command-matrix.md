# Command matrix

## Preflight checklist
- Run from repository root.
- Ensure `bash`, `git`, and `curl` are present.
- For `update` and `maintenance`, expect `chezmoi` and Homebrew (`brew`) to be installed.

## Profile mappings

### bootstrap
1. `./install.sh --auto --git-name "<NAME>" --git-email "<EMAIL>"`
2. `./doctor.sh`

### update
1. `chezmoi update --apply`
2. `brew bundle --global --verbose`
3. `./doctor.sh`

### verify
1. `./doctor.sh`
2. `./tests/doctor_test.sh` (run only when executable)

### maintenance
1. `~/.local/bin/mac-dotfiles-maintenance.sh` (run only when present and executable)
2. `./doctor.sh`

## Reporting format
After execution, report:
- selected profile,
- commands attempted in order,
- first failure (if any),
- final status (`success` or `failed`).
