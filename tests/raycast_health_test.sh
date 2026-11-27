#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command_script="$repo/dot_config/raycast/mac-dotfiles/executable_sante-du-mac.sh"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/home/.local/bin"
cat >"$fixture/home/.local/bin/mac-dotfiles.sh" <<'MOCK'
#!/usr/bin/env bash
set -eu
[[ "$#" == 2 && "$1" == status && "$2" == --json ]] || exit 23
cat "$HOME/status.json"
[[ ! -e "$HOME/cli-failed" ]]
MOCK
chmod +x "$fixture/home/.local/bin/mac-dotfiles.sh"

cat >"$fixture/healthy.json" <<'JSON'
{
  "schema_version": 1,
  "status": "healthy",
  "updated_at": "2026-11-04T14:00:00Z",
  "checks": [
    {"name":"maintenance","status":"healthy","detail":"maintenance log is recent","completed_at":"2026-11-03T04:05:00Z"},
    {"name":"recovery-snapshot","status":"healthy","detail":"archive is accessible","path":"/Volumes/Backup Mac/test archive.age","verified_at":"2026-11-02T10:15:00Z","accessible":true},
    {"name":"certification","status":"healthy","detail":"latest certification passed"}
  ]
}
JSON

run_command() {
    HOME="$fixture/home" bash "$command_script"
}

expect_text() {
    [[ "$output" == *"$1"* ]] || {
        printf 'Expected %s in Raycast output:\n%s\n' "$1" "$output" >&2
        exit 1
    }
}

cp "$fixture/healthy.json" "$fixture/home/status.json"
output="$(run_command)"
expect_text 'État général · Sain'
expect_text 'Dernière maintenance · 2026-11-03T04:05:00Z'
expect_text 'Dernière sauvegarde vérifiée · 2026-11-02T10:15:00Z'
expect_text 'Archive accessible · /Volumes/Backup Mac/test archive.age'

jq '.status = "warning" | (.checks[] | select(.name == "recovery-snapshot")) +=
    {status:"warning",accessible:false,detail:"archive is unavailable"}' \
    "$fixture/healthy.json" >"$fixture/home/status.json"
output="$(run_command)"
expect_text 'État général · À surveiller'
expect_text 'Archive inaccessible · /Volumes/Backup Mac/test archive.age'

jq '.status = "critical" | (.checks[] | select(.name == "certification")) +=
    {status:"critical",detail:"certification failed for fixture commit"}' \
    "$fixture/healthy.json" >"$fixture/home/status.json"
output="$(run_command)"
expect_text 'État général · Critique'
expect_text 'certification failed for fixture commit'

jq '.status = "warning" | del(.checks[0].completed_at) |
    .checks[1] = {name:"recovery-snapshot",status:"warning",detail:"no verified recovery snapshot recorded"}' \
    "$fixture/healthy.json" >"$fixture/home/status.json"
output="$(run_command)"
expect_text 'Dernière maintenance · date inconnue'
expect_text 'Dernière sauvegarde vérifiée · aucune vérification enregistrée'

# A failed CLI may leave valid-looking JSON on stdout.
touch "$fixture/home/cli-failed"
if run_command >"$fixture/output" 2>&1; then
    echo "[FAIL] Raycast command accepted output from a failed CLI" >&2
    exit 1
fi
rm "$fixture/home/cli-failed"
echo 'malformed JSON' >"$fixture/home/status.json"
if run_command >"$fixture/output" 2>&1; then
    echo "[FAIL] Raycast command accepted invalid JSON" >&2
    exit 1
fi

echo "[PASS] Raycast health command"
