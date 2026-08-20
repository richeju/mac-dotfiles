#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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
    local source="$1" candidate="$1" relative="$2" safe_name
    if [[ "$source" == *.tmpl ]] && grep -q '{{' "$source"; then
        safe_name="${relative//\//_}"
        candidate="$WORK_DIR/${safe_name%.tmpl}"
        sed -E \
            -e '/^[[:space:]]*\{\{.*\}\}[[:space:]]*$/d' \
            -e 's/\{\{[^}]*\}\}/template_value/g' \
            "$source" >"$candidate"
    fi

    if [[ "$MODE" == "all" || "$MODE" == "shellcheck" ]]; then
        shellcheck -x --source-path="$REPO_ROOT" "$candidate"
    fi
    if [[ "$MODE" == "all" || "$MODE" == "shfmt" ]]; then
        shfmt -d -i 4 -ci "$candidate"
    fi
}

git -C "$REPO_ROOT" ls-files --cached --others --exclude-standard | while IFS= read -r relative; do
    [[ -e "$REPO_ROOT/$relative" ]] || continue
    case "$relative" in
        skills/*) continue ;;
        *.sh | *.sh.tmpl) check_script "$REPO_ROOT/$relative" "$relative" ;;
    esac
done

echo "[PASS] shell quality ($MODE)"
