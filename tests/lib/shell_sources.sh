#!/usr/bin/env bash

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
