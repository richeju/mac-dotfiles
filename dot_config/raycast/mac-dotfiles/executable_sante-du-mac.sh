#!/bin/bash

# @raycast.schemaVersion 1
# @raycast.title Santé du Mac
# @raycast.mode fullOutput
# @raycast.packageName mac-dotfiles
# @raycast.icon 🩺
# @raycast.description Afficher la dernière maintenance, la sauvegarde vérifiée et les alertes du Mac.

set -euo pipefail

# Raycast may start with only the system PATH.
export PATH="/opt/homebrew/bin:/usr/local/bin:${PATH:-/usr/bin:/bin}"
launcher="$HOME/.local/bin/mac-dotfiles.sh"
if [[ ! -x "$launcher" ]]; then
    echo "Le lanceur mac-dotfiles est introuvable. Relance l’installation des dotfiles." >&2
    exit 1
fi
if ! command -v jq >/dev/null; then
    echo "jq est introuvable. Lance brew install jq dans le Terminal." >&2
    exit 1
fi
if ! health="$("$launcher" status --json)"; then
    echo "Impossible de lire le bilan. Lance mac-dotfiles.sh status dans le Terminal pour voir le diagnostic." >&2
    exit 1
fi

if ! jq -ers '
    def severity: {"healthy":"Sain", "warning":"À surveiller", "critical":"Critique"}[.];
    def check_name: {
        "maintenance":"Maintenance", "recovery-snapshot":"Sauvegarde",
        "desired-state":"Configuration", "certification":"Certification",
        "certified-update":"Mise à jour", "compliance":"Conformité"
    }[.] // .;

    select(length == 1) | .[0] |
    select(.schema_version == 1 and (.status | severity) != null and
        (.checks | type == "array" and all(.[];
            (.name | type == "string") and (.status | severity) != null and (.detail | type == "string")))) |
    (.checks | map(select(.name == "maintenance")) | first) as $maintenance |
    (.checks | map(select(.name == "recovery-snapshot")) | first) as $backup |
    "État général · \(.status | severity)",
    "Dernière maintenance · \($maintenance.completed_at // "date inconnue")",
    "Dernière sauvegarde vérifiée · \($backup.verified_at // "aucune vérification enregistrée")",
    (if $backup.path then
        (if $backup.accessible then "Archive accessible" else "Archive inaccessible" end) + " · " + $backup.path
     else empty end),
    (.checks | map(select(.status != "healthy")) | select(length > 0) |
        "", "Alertes", (.[] | "• \(.name | check_name) · \(.detail)"))
' <<<"$health"; then
    echo "Le bilan mac-dotfiles est illisible. Vérifie mac-dotfiles.sh status --json dans le Terminal." >&2
    exit 1
fi
