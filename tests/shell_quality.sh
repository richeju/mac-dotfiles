#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/shell_sources.sh
source "$REPO_ROOT/tests/lib/shell_sources.sh"
MODE="${1:-all}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mac-dotfiles-shell-quality.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

case "$MODE" in
    all | shellcheck | shfmt) ;;
    *)
        echo "Usage: shell_quality.sh [all|shellcheck|shfmt]" >&2
        exit 2
        ;;
esac

if [[ "$MODE" == "all" || "$MODE" == "shellcheck" ]]; then
    command -v shellcheck >/dev/null 2>&1 || {
        echo "shellcheck is required" >&2
        exit 2
    }
fi
if [[ "$MODE" == "all" || "$MODE" == "shfmt" ]]; then
    command -v shfmt >/dev/null 2>&1 || {
        echo "shfmt is required" >&2
        exit 2
    }
fi

check_script() {
    local source="$1" candidate="$1" relative="$2"
    if [[ "$source" == *.tmpl ]] && grep -q '{{' "$source"; then
        candidate="$WORK_DIR/${relative%.tmpl}"
        mkdir -p "$(dirname "$candidate")"
        prepare_shell_source "$source" >"$candidate"
    fi

    if [[ "$MODE" == "all" || "$MODE" == "shellcheck" ]]; then
        shellcheck -x --source-path="$REPO_ROOT" "$candidate"
    fi
    if [[ "$MODE" == "all" || "$MODE" == "shfmt" ]]; then
        shfmt -d -i 4 -ci "$candidate"
    fi
}

list_shell_sources "$REPO_ROOT" | while IFS= read -r -d '' relative; do
    case "$relative" in
        skills/*) continue ;;
    esac
    check_script "$REPO_ROOT/$relative" "$relative"
done

echo "[PASS] shell quality ($MODE)"
