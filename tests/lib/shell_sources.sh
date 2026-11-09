#!/usr/bin/env bash

# Emit existing tracked and untracked paths relative to the repository root.
# NUL delimiters preserve spaces, newlines and backslashes without Git quoting.
# Callers use pipefail so a failed Git lookup cannot become a successful check.
list_repository_files() {
    local root="$1" path
    git -C "$root" ls-files --cached --others --exclude-standard -z | while IFS= read -r -d '' path; do
        [[ -e "$root/$path" ]] || continue
        printf '%s\0' "$path"
    done
}

list_shell_sources() {
    local path
    list_repository_files "$1" | while IFS= read -r -d '' path; do
        case "$path" in
            *.sh | *.sh.tmpl) printf '%s\0' "$path" ;;
        esac
    done
}

# Shared preparation for syntax, ShellCheck and formatting checks. This strips
# chezmoi expressions only; it does not replace real template-rendering tests.
prepare_shell_source() {
    local source="$1"
    if [[ "$source" == *.tmpl ]] && grep -q '{{' "$source"; then
        sed -E \
            -e '/^[[:space:]]*\{\{.*\}\}[[:space:]]*$/d' \
            -e 's/\{\{[^}]*\}\}/template_value/g' \
            "$source"
    else
        cat "$source"
    fi
}
