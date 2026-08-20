# Audit technique

Date : 2026-08-20

Révision inspectée : `00f32b62da1eac20f8a870ed3655a87be0e87b88` (`main`)

## Verdict

Le dépôt est nettement plus mûr qu'un dépôt de dotfiles classique. Le modèle de convergence, les transactions, les migrations, la certification, le last-known-good, le watchdog et la restauration forment un ensemble cohérent et bien testé. La documentation décrit aussi honnêtement les limites du rollback Homebrew et du profil NIST.

Je ne le considérerais toutefois pas encore totalement fiable pour reconstruire indifféremment un Mac Intel ou Apple Silicon. Deux défauts de logique peuvent empêcher l'application de l'état annoncé, et les points d'entrée d'installation restent moins durcis que le reste du projet.

## Ce qui est réussi

- Découpage lisible : chezmoi pour les fichiers, fragments Brewfile pour les profils et scripts dédiés pour les opérations d'état.
- Convergence protégée par verrou, snapshots, validation bloquante et rollback best effort.
- Migrations versionnées, attestation de certification, mise à jour fast-forward et last-known-good.
- Sauvegardes de reprise sur liste blanche, checksums, écriture atomique et restauration transactionnelle.
- CI Linux et macOS, ShellCheck, shfmt, validation plist et attestation JSON.
- Dix-huit groupes de tests passent localement sur la révision auditée.
- Aucun secret évident détecté dans l'arbre courant lors de l'inspection.

## Constats prioritaires

### P1 — Les hooks de préférences sont neutralisés pendant la convergence

`executable_mac-dotfiles-converge.sh.tmpl` exécute :

```bash
MAC_DOTFILES_ORCHESTRATED=1 chezmoi apply --force --no-tty
```

Les hooks suivants quittent alors immédiatement avec un code de succès :

- `run_onchange_configure-dock-darwin.sh.tmpl`
- `run_onchange_configure-finder-and-inputs-darwin.sh`
- `run_onchange_harden-macos-baseline-darwin.sh`

Le convergeur rejoue explicitement Homebrew et recharge le LaunchAgent, mais il ne rejoue pas ces trois ensembles de réglages. Un `run_onchange` exécuté avec succès peut être enregistré comme déjà appliqué par chezmoi : la modification de sa source est alors consommée sans que les `defaults write` ou `pmset` correspondants aient eu lieu.

Conséquences possibles :

- un changement de configuration Dock n'est jamais appliqué ;
- les réglages Finder/clavier/trackpad restent anciens ;
- une évolution du baseline de hardening est annoncée comme convergée mais reste absente de la machine.

Recommandation : extraire ces opérations dans des scripts idempotents appelés à la fois par les hooks chezmoi et par le convergeur, ou ne pas les court-circuiter. Ajouter un test de convergence qui vérifie les appels `defaults`/`pmset`, puis une seconde convergence idempotente.

### P1 — La compatibilité Intel annoncée n'est pas respectée par `.zprofile`

`dot_zprofile` utilise exclusivement le préfixe Apple Silicon :

```bash
eval "$(/opt/homebrew/bin/brew shellenv)"
export PATH="/opt/homebrew/opt/node@24/bin:$PATH"
```

Sur un Mac Intel, Homebrew se trouve normalement sous `/usr/local`. `install.sh` sait détecter les deux préfixes pendant le bootstrap, mais l'application ultérieure de `dot_zprofile` réintroduit les chemins `/opt/homebrew`.

Recommandation : rendre le fichier indépendant de l'architecture, par exemple en cherchant `brew` dans le `PATH`, puis `/opt/homebrew/bin/brew` et `/usr/local/bin/brew`, et calculer le chemin Node avec `brew --prefix node@24`.

### P1 — Les points d'entrée d'installation reposent sur des références mutables

La procédure principale exécute directement `install.sh` depuis `main`, puis le bootstrap Homebrew depuis `HEAD` :

```bash
curl -fsSL https://raw.githubusercontent.com/richeju/mac-dotfiles/main/install.sh | bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Le README propose aussi une variante téléchargement puis inspection, ce qui est utile, mais le chemin recommandé n'est ni versionné ni vérifié par checksum. C'est en décalage avec les garanties de certification et de last-known-good appliquées après le bootstrap.

Recommandation : publier un bootstrap associé à un tag ou une release, documenter son SHA-256 et initialiser chezmoi sur le commit certifié correspondant. Garder la commande sur `main` uniquement comme canal explicitement instable.

## Constats secondaires

### P2 — Le chiffrement de reprise n'authentifie pas cryptographiquement l'archive

Les snapshots chiffrés utilisent `openssl enc -aes-256-cbc -pbkdf2`. Les checksums internes détectent la corruption après déchiffrement, mais AES-CBC ne fournit pas à lui seul d'authentification du ciphertext. Le dépôt installe désormais `age`, qui fournit un format plus moderne et authentifié.

Recommandation : introduire un format de snapshot v2 chiffré avec `age` (passphrase ou destinataire), conserver la lecture du v1 pendant une période de migration et ajouter des tests de modification du ciphertext.

### P2 — La chaîne CI peut être davantage verrouillée

Le workflow utilise `actions/checkout@v4` et `actions/upload-artifact@v4` sans SHA complet. Il ne fixe pas non plus explicitement `permissions: contents: read`, de timeout ou de groupe `concurrency`.

Recommandation : épingler les actions par SHA, réduire les permissions, ajouter des timeouts et annuler les exécutions obsolètes d'une même branche.

### P2 — `.chezmoiignore` ne protège pas l'historique Git contre les secrets

Le dépôt ignore les clés, `.env`, `.ssh`, `.aws`, etc. côté chezmoi, mais il ne contient pas de `.gitignore` et la CI n'exécute pas de scanner de secrets. `.chezmoiignore` empêche l'application de fichiers ; il n'empêche pas leur ajout accidentel au dépôt public.

Recommandation : ajouter un `.gitignore` défensif et un scan de secrets en pre-commit et en CI, idéalement sur l'historique lors des changements sensibles.

### P2 — Le nom du profil `full` est ambigu

`full` contient `core + power + personal + gaming`, mais pas `developer`. Le README l'appelle pourtant « complete current setup ». Une machine `full` ne reçoit donc ni Go ni Python, alors que le profil `developer` les reçoit.

Recommandation : soit inclure `developer.Brewfile` dans `full`, soit renommer/décrire le profil comme `personal + gaming` pour éviter une attente erronée.

### P3 — La suite recovery réussit avec beaucoup de bruit sur stderr

La suite complète passe, mais `recovery_test.sh` produit de nombreux `printf: write error: Broken pipe` ainsi qu'un avertissement `tar` attendu par le scénario de traversée de chemin. Ces messages rendent les vrais avertissements plus difficiles à repérer.

Recommandation : éviter les producteurs qui continuent après la fermeture volontaire du pipeline, capturer l'erreur `tar` attendue et ajouter des cas explicites pour les entrées symlink/hardlink avant extraction.

## Ordre de traitement proposé

1. Corriger et tester l'exécution des hooks orchestrés.
2. Rendre `.zprofile` portable Intel/Apple Silicon.
3. Versionner le bootstrap et durcir le workflow GitHub Actions.
4. Migrer les snapshots chiffrés vers `age`.
5. Ajouter la prévention de secrets et clarifier `full`.
6. Nettoyer la sortie de la suite recovery et compléter ses cas adversariaux.

## Vérifications réalisées

- Lecture de l'architecture, du bootstrap, des profils, des hooks, des scripts de convergence/certification/reprise et du workflow CI.
- Exécution de `bash tests/test_suite.sh` : 18 groupes réussis.
- Inspection ciblée de l'arbre courant pour des clés privées, tokens et identifiants usuels : aucun résultat évident.
- `git diff --check` sur cette note avant publication.

Limite : l'audit a été exécuté dans un environnement Linux. Les tests macOS du dépôt existent, mais aucun bootstrap destructif ni test réel de `defaults`, `launchctl`, `pmset` ou Homebrew n'a été lancé sur un Mac pendant cette inspection.
