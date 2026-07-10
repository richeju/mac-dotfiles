#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

validate_chezmoi_source_names() {
    local path

    git -C "$REPO_ROOT" ls-files | while IFS= read -r path; do
        case "$path" in
            */run_*)
                echo "Reserved chezmoi run_ prefix outside repository root: $path" >&2
                return 1
                ;;
        esac
    done
}

validate_repo_files_are_ignored() {
    local path

    for path in .github/ Brewfile README.md doctor.sh install.sh lib/ skills/ tests/; do
        if ! grep -Fqx "$path" "$REPO_ROOT/.chezmoiignore"; then
            echo "Repository-only path is missing from .chezmoiignore: $path" >&2
            return 1
        fi
    done
}

validate_script() {
    local script="$1"

    if [[ "$script" == *.tmpl ]] && grep -q '{{' "$script"; then
        if ! sed -E \
            -e '/^[[:space:]]*\{\{.*\}\}[[:space:]]*$/d' \
            -e 's/\{\{[^}]*\}\}/template_value/g' \
            "$script" | bash -n; then
            echo "Shell syntax validation failed: $script" >&2
            return 1
        fi
        return
    fi

    bash -n "$script"
}

validate_shell_syntax() {
    local script

    git -C "$REPO_ROOT" ls-files | while IFS= read -r script; do
        case "$script" in
            *.sh|*.sh.tmpl)
                validate_script "$REPO_ROOT/$script"
                ;;
        esac
    done
}

run_test_suites() {
    local test_file

    git -C "$REPO_ROOT" ls-files 'tests/*_test.sh' | sort | while IFS= read -r test_file; do
        bash "$REPO_ROOT/$test_file"
    done
}

echo "==> Validating chezmoi source names"
validate_chezmoi_source_names
validate_repo_files_are_ignored

echo "==> Validating shell syntax"
validate_shell_syntax

echo "==> Running test suites"
run_test_suites

echo "[PASS] All checks completed"
