#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<'USAGE'
Usage:
  auto-bootstrap.sh --git-name "Your Name" --git-email "you@example.com"

Environment alternatives:
  GIT_NAME="Your Name" GIT_EMAIL="you@example.com" auto-bootstrap.sh
USAGE
  exit 0
fi

GIT_NAME_VALUE="${GIT_NAME:-}"
GIT_EMAIL_VALUE="${GIT_EMAIL:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --git-name)
      GIT_NAME_VALUE="${2:-}"
      shift 2
      ;;
    --git-email)
      GIT_EMAIL_VALUE="${2:-}"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$GIT_NAME_VALUE" || -z "$GIT_EMAIL_VALUE" ]]; then
  echo "Error: --git-name and --git-email are required (or set GIT_NAME / GIT_EMAIL)." >&2
  exit 1
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

cd "$repo_root"
./install.sh --auto --git-name "$GIT_NAME_VALUE" --git-email "$GIT_EMAIL_VALUE"
