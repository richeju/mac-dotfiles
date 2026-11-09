#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/shell_sources.sh
source "$REPO_ROOT/tests/lib/shell_sources.sh"

validate_chezmoi_source_names() {
    local path

    list_repository_files "$REPO_ROOT" | while IFS= read -r -d '' path; do
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

    for path in .github/ .gitignore README.md compliance/ doctor.sh install.sh lib/ migrations/ profiles/ skills/ tests/; do
        if ! grep -Fqx "$path" "$REPO_ROOT/.chezmoiignore"; then
            echo "Repository-only path is missing from .chezmoiignore: $path" >&2
            return 1
        fi
    done
}

validate_script() {
    local script="$1"

    if ! prepare_shell_source "$script" | bash -n; then
        echo "Shell syntax validation failed: $script" >&2
        return 1
    fi
}

validate_shell_syntax() {
    local script

    list_shell_sources "$REPO_ROOT" | while IFS= read -r -d '' script; do
        validate_script "$REPO_ROOT/$script"
    done
}

run_test_suites() {
    local test_file

    find "$REPO_ROOT/tests" -maxdepth 1 -type f -name '*_test.sh' -print | sort | while IFS= read -r test_file; do
        bash "$test_file"
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
