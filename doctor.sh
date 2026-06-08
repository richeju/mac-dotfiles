#!/usr/bin/env bash

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ok() { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC} $1"; }
info() { echo -e "${BLUE}ℹ${NC} $1"; }
error() { echo -e "${RED}✗${NC} $1"; }

usage() {
    cat <<'USAGE'
Usage: ./doctor.sh [--fix] [--json] [--markdown] [--explain] [--help]

Options:
  --fix    Attempt safe automatic fixes when possible.
  --json   Print a machine-readable JSON summary at the end.
  --markdown  Print a Markdown summary table (useful for issues/PRs).
  --explain  Explain warnings and suggest next commands.
  --help   Show this help.
USAGE
}

FIX_MODE=0
JSON_MODE=0
MARKDOWN_MODE=0
EXPLAIN_MODE=0

while (($#)); do
    case "$1" in
        --fix)
            FIX_MODE=1
            ;;
        --json)
            JSON_MODE=1
            ;;
        --markdown)
            MARKDOWN_MODE=1
            ;;
        --explain)
            EXPLAIN_MODE=1
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            error "Unknown argument: $1"
            usage
            exit 2
            ;;
    esac
    shift
done

# Track status in a simple format for optional JSON output.
CHECK_NAMES=()
CHECK_STATUS=()
CHECK_MESSAGE=()

record_check() {
    local name="$1"
    local status="$2"
    local message="$3"
    CHECK_NAMES+=("$name")
    CHECK_STATUS+=("$status")
    CHECK_MESSAGE+=("$message")
}

has_error=0

version_ge() {
    # Returns 0 when $1 >= $2
    [[ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | tail -n1)" == "$1" ]]
}

check_command() {
    local cmd="$1"
    if command_exists "$cmd"; then
        ok "Command available: $cmd"
        record_check "command:$cmd" "ok" "Command available"
    else
        warn "Missing command: $cmd"
        record_check "command:$cmd" "warn" "Missing command"
        has_error=1
    fi
}

command_exists() {
    local cmd="$1"
    command -v "$cmd" >/dev/null 2>&1
}

check_min_version() {
    local name="$1"
    local current="$2"
    local minimum="$3"

    if version_ge "$current" "$minimum"; then
        ok "$name version $current (minimum $minimum)"
        record_check "version:$name" "ok" "$current >= $minimum"
    else
        warn "$name version $current is below minimum $minimum"
        record_check "version:$name" "warn" "$current < $minimum"
        has_error=1
    fi
}

check_version_if_available() {
    local cmd="$1"
    local name="$2"
    local minimum="$3"
    local extractor="$4"

    if ! command_exists "$cmd"; then
        return
    fi

    local current
    current="$(bash -c "$extractor")"
    check_min_version "$name" "$current" "$minimum"
}

run_autofix_command() {
    local command_text="$1"
    local success_message="$2"
    local fail_message="$3"
    shift 3

    if [[ "$FIX_MODE" -ne 1 ]]; then
        return 1
    fi

    info "Applying fix: $command_text"
    if "$@"; then
        ok "$success_message"
        return 0
    fi

    warn "$fail_message"
    return 1
}

auto_fix_brew_bundle() {
    run_autofix_command \
        "brew bundle --global --verbose" \
        "Auto-fix completed for Homebrew dependencies" \
        "Auto-fix failed for Homebrew dependencies" \
        brew bundle --global --verbose
}

auto_fix_chezmoi() {
    run_autofix_command \
        "chezmoi apply" \
        "Auto-fix completed for pending dotfile changes" \
        "Auto-fix failed for pending dotfile changes" \
        chezmoi apply
}

check_chezmoi_diff() {
    [[ -z "$(chezmoi diff)" ]]
}

run_check_with_optional_fix() {
    local check_key="$1"
    local success_message="$2"
    local warn_message="$3"
    local fix_success_message="$4"
    local fix_function="$5"
    shift 5

    if "$@"; then
        ok "$success_message"
        record_check "$check_key" "ok" "No issue detected"
        return
    fi

    warn "$warn_message"
    if "$fix_function" && "$@"; then
        ok "$fix_success_message"
        record_check "$check_key" "ok" "Fixed via --fix"
    else
        record_check "$check_key" "warn" "Issue detected"
        has_error=1
    fi
}

bool_label() {
    local value="$1"
    local true_label="$2"
    local false_label="$3"
    [[ "$value" -eq 1 ]] && echo "$true_label" || echo "$false_label"
}

check_broken_symlink() {
    local path="$1"
    local label="$2"

    if [[ -L "$path" && ! -e "$path" ]]; then
        warn "Broken symlink detected: $label ($path)"
        record_check "symlink:$label" "warn" "Broken symlink"
        has_error=1
    else
        ok "Symlink check passed: $label"
        record_check "symlink:$label" "ok" "No broken symlink"
    fi
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

echo "🩺 mac-dotfiles doctor"
echo "======================="

if [[ "$FIX_MODE" -eq 1 ]]; then
    info "Fix mode enabled"
fi

if [[ "$OSTYPE" == darwin* ]]; then
    ok "Running on macOS"
    record_check "platform" "ok" "Running on macOS"
else
    warn "This repository targets macOS, current OSTYPE is '$OSTYPE'"
    record_check "platform" "warn" "Expected macOS"
fi

for required_cmd in git curl brew chezmoi; do
    check_command "$required_cmd"
done

check_version_if_available git git 2.30.0 "git --version | awk '{print \$3}'"
check_version_if_available chezmoi chezmoi 2.0.0 "chezmoi --version | sed -E 's/.*v?([0-9]+\\.[0-9]+\\.[0-9]+).*/\\1/'"

if command_exists brew; then
    run_check_with_optional_fix \
        "brew-bundle" \
        "All Homebrew dependencies from ~/.Brewfile are installed" \
        "Some Homebrew dependencies are missing (run: brew bundle --global --verbose)" \
        "Homebrew dependencies fixed successfully" \
        auto_fix_brew_bundle \
        brew bundle check --global --quiet
fi

if command_exists chezmoi; then
    run_check_with_optional_fix \
        "chezmoi-diff" \
        "No pending dotfile changes" \
        "There are pending dotfile changes (run: chezmoi diff / chezmoi apply)" \
        "Pending dotfile changes fixed successfully" \
        auto_fix_chezmoi \
        check_chezmoi_diff
fi

check_broken_symlink "$HOME/.Brewfile" "Homebrew global Brewfile"
check_broken_symlink "$HOME/.gitconfig" "Git config"
check_broken_symlink "$HOME/.local/bin/mac-dotfiles-maintenance.sh" "Maintenance script"

if [[ "$JSON_MODE" -eq 1 ]]; then
    echo
    print_json_summary
fi

if [[ "$MARKDOWN_MODE" -eq 1 ]]; then
    echo
    print_markdown_summary
fi

if [[ "$EXPLAIN_MODE" -eq 1 ]]; then
    echo
    print_explanations
fi

if [[ "$has_error" -eq 0 ]]; then
    echo
    ok "System check completed successfully"
else
    echo
    warn "System check completed with warnings"
    exit 1
fi
