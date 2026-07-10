#!/usr/bin/env bash

# Output formatters for doctor.sh.
#
# The caller owns CHECK_NAMES, CHECK_STATUS, CHECK_MESSAGE, has_error, and
# FIX_MODE. Keeping rendering separate from health checks makes it easier to
# add output formats without changing the diagnostic workflow.

bool_label() {
    local value="$1"
    local true_label="$2"
    local false_label="$3"
    [[ "$value" -eq 1 ]] && echo "$true_label" || echo "$false_label"
}

json_escape() {
    local value="$1"
    value=${value//\\/\\\\}
    value=${value//\"/\\\"}
    value=${value//$'\n'/\\n}
    printf '%s' "$value"
}

print_json_summary() {
    local overall="ok"
    if [[ "$has_error" -ne 0 ]]; then
        overall="warn"
    fi

    printf '{\n'
    printf '  "overall": "%s",\n' "$overall"
    printf '  "fix_mode": %s,\n' "$(bool_label "$FIX_MODE" true false)"
    printf '  "checks": [\n'

    local i
    for i in "${!CHECK_NAMES[@]}"; do
        printf '    {"name": "%s", "status": "%s", "message": "%s"}' \
            "$(json_escape "${CHECK_NAMES[$i]}")" \
            "$(json_escape "${CHECK_STATUS[$i]}")" \
            "$(json_escape "${CHECK_MESSAGE[$i]}")"

        if [[ "$i" -lt $((${#CHECK_NAMES[@]} - 1)) ]]; then
            printf ','
        fi
        printf '\n'
    done

    printf '  ]\n'
    printf '}\n'
}

print_markdown_summary() {
    local overall="✅ Healthy"
    if [[ "$has_error" -ne 0 ]]; then
        overall="⚠️ Attention needed"
    fi

    echo "## mac-dotfiles doctor report"
    echo
    echo "- Overall: ${overall}"
    echo "- Fix mode: $(bool_label "$FIX_MODE" "enabled" "disabled")"
    echo
    echo "| Check | Status | Message |"
    echo "|---|---|---|"

    local i icon
    for i in "${!CHECK_NAMES[@]}"; do
        case "${CHECK_STATUS[$i]}" in
            ok) icon="✅ ok" ;;
            warn) icon="⚠️ warn" ;;
            *) icon="ℹ️ info" ;;
        esac

        printf '| `%s` | %s | %s |\n' \
            "${CHECK_NAMES[$i]}" \
            "$icon" \
            "${CHECK_MESSAGE[$i]}"
    done
}

print_explanation_for_check() {
    local name="$1"
    local status="$2"
    local message="$3"

    [[ "$status" == "warn" ]] || return 0

    echo "### $name"
    echo
    echo "Status: $message"
    echo

    case "$name" in
        platform)
            cat <<'TEXT'
Meaning:
  These dotfiles are designed for macOS. Some defaults, LaunchAgents, and Homebrew paths may not apply elsewhere.

Try:
  Run this repository on macOS for full validation.
TEXT
            ;;
        command:brew)
            cat <<'TEXT'
Meaning:
  Homebrew is required to install and reconcile packages.

Try:
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  curl -fsSL https://raw.githubusercontent.com/richeju/mac-dotfiles/main/install.sh | bash
TEXT
            ;;
        command:chezmoi)
            cat <<'TEXT'
Meaning:
  chezmoi is required to apply and update these dotfiles.

Try:
  brew install chezmoi
  chezmoi init --apply richeju/mac-dotfiles
TEXT
            ;;
        command:git|command:curl)
            cat <<TEXT
Meaning:
  $name is required by the bootstrap and update workflow.

Try:
  xcode-select --install
  brew bundle --global --verbose
TEXT
            ;;
        version:git|version:chezmoi)
            cat <<'TEXT'
Meaning:
  The installed tool version is older than the supported baseline.

Try:
  brew upgrade git chezmoi
TEXT
            ;;
        brew-bundle)
            cat <<'TEXT'
Meaning:
  Homebrew packages from ~/.Brewfile are missing or outdated.

Try:
  brew bundle --global --verbose

Safer option:
  mac-dotfiles.sh safe-update
TEXT
            ;;
        chezmoi-diff)
            cat <<'TEXT'
Meaning:
  Managed files in your home directory differ from the source state.

Try:
  chezmoi diff
  chezmoi apply

Safer option:
  mac-dotfiles.sh safe-update
TEXT
            ;;
        symlink:*)
            cat <<'TEXT'
Meaning:
  A managed symlink points to a missing target.

Try:
  chezmoi apply

Safer option:
  mac-dotfiles.sh safe-update
TEXT
            ;;
        *)
            cat <<'TEXT'
Meaning:
  This check needs attention.

Try:
  mac-dotfiles.sh report
  mac-dotfiles.sh safe-update
TEXT
            ;;
    esac

    echo
}

print_explanations() {
    echo "## Explanation"
    echo

    local printed=0
    local i
    for i in "${!CHECK_NAMES[@]}"; do
        if [[ "${CHECK_STATUS[$i]}" == "warn" ]]; then
            print_explanation_for_check \
                "${CHECK_NAMES[$i]}" \
                "${CHECK_STATUS[$i]}" \
                "${CHECK_MESSAGE[$i]}"
            printed=1
        fi
    done

    if [[ "$printed" -eq 0 ]]; then
        echo "No warnings to explain."
        echo
    fi
}
