#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  repo-automation.sh bootstrap --git-name "NAME" --git-email "EMAIL"
  repo-automation.sh update
  repo-automation.sh verify
  repo-automation.sh maintenance
USAGE
}

require_cmd() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "Missing required command: $cmd" >&2
    exit 1
  }
}

run_if_executable() {
  local path="$1"
  if [[ -x "$path" ]]; then
    "$path"
  else
    echo "Skipping non-executable path: $path"
  fi
}

profile="${1:-}"
if [[ -z "$profile" ]]; then
  usage
  exit 1
fi
shift || true

require_cmd bash
require_cmd git
require_cmd curl

case "$profile" in
  bootstrap)
    git_name=""
    git_email=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --git-name)
          git_name="${2:-}"
          shift 2
          ;;
        --git-email)
          git_email="${2:-}"
          shift 2
          ;;
        *)
          echo "Unknown bootstrap option: $1" >&2
          usage
          exit 1
          ;;
      esac
    done

    if [[ -z "$git_name" || -z "$git_email" ]]; then
      echo "bootstrap requires --git-name and --git-email" >&2
      usage
      exit 1
    fi

    ./install.sh --auto --git-name "$git_name" --git-email "$git_email"
    ./doctor.sh
    ;;

  update)
    require_cmd chezmoi
    require_cmd brew
    chezmoi update --apply
    brew bundle --global --verbose
    ./doctor.sh
    ;;

  verify)
    ./doctor.sh
    run_if_executable ./tests/doctor_test.sh
    ;;

  maintenance)
    run_if_executable "$HOME/.local/bin/mac-dotfiles-maintenance.sh"
    ./doctor.sh
    ;;

  *)
    echo "Unknown profile: $profile" >&2
    usage
    exit 1
    ;;
esac
