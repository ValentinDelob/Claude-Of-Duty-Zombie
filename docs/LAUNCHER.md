# Lanceur et notes de version

Publication, paquets et canaux : `docs/RELEASE.md`.

## Pour le joueur

`ClaudeOfDutyZombie-Launcher.exe` (joint à chaque release stable, et à la
snapshot qui l'a modifié ; les notes de chaque snapshot donnent le lien) :

- **Canal** : l'interrupteur **STABLE / SNAPSHOT** en haut de la liste des
  versions (seul endroit où il se choisit) ; la liste, les notes et la barre du
  bas suivent le canal choisi, et le choix est mémorisé. STABLE (par défaut) :
  versions éprouvées ; SNAPSHOT : chaque nouveauté dès sa sortie.
- **Mise à jour automatique** : à l'ouverture (et au changement de canal), la
  dernière version du canal est téléchargée si elle n'est pas déjà installée.
  Pour les versions en paquets, **seules les parties qui ont changé** sont
  téléchargées (le moteur une seule fois, les voix seulement quand elles
  changent) ; un téléchargement interrompu **reprend** là où il s'était arrêté.
- **Choix de la version** (comme le lanceur de Minecraft) : « Dernière version »
  (suit la plus récente du canal) ou n'importe quelle version publiée du canal ;
  un choix mémorisé par canal. ✓ = version installée ; SUPPRIMER libère sa
  place (et les paquets qu'aucune autre version n'utilise).
- **Notes de version** de la version sélectionnée, dans une bulle à côté de la
  liste (sa pointe montre la version choisie) : titre, nouveautés en quelques
  puces écrites pour les joueurs, captures (clic pour agrandir). L'accueil a
  pour fond une image du jeu (`launcher/assets/background.jpg`, salle du Kino).
- **JOUER** : lance la version choisie (après son téléchargement si besoin) et
  ferme le lanceur.
- Français ou anglais ; hors ligne, seules les versions installées sont proposées.
- **RÉGLAGES** (en haut à droite) : langue, dossier des versions et place prise,
  nettoyage des paquets qu'aucune version n'utilise plus, dossier des journaux,
  à propos. Identité visuelle : `launcher/scripts/look.gd` (thème réutilisable,
  maquettes validées le 30/09/2026, accueil refait le 02/10/2026 ; pas de logo pour l'instant).
- Le lanceur **se met à jour lui-même** et **redémarre** ; si la nouvelle version
  ne démarre pas, l'ancienne est remise automatiquement.

Dossiers (noms historiques gardés : rien n'est perdu d'une version à l'autre) :

| Quoi | Où |
|---|---|
| Versions installées | `%LOCALAPPDATA%\CallOfClaudeZombie\versions\<version>\` (`CallOfClaudeZombie.exe`, et pour les versions en paquets `CallOfClaudeZombie.pck` + `manifest.json`) |
| Paquets vérifiés, partagés | `%LOCALAPPDATA%\CallOfClaudeZombie\store\<sha256>.pck` |
| Moteur (une fois par version de Godot) | `%LOCALAPPDATA%\CallOfClaudeZombie\engines\<godot>\engine.exe` |
| Réglages du lanceur | `%APPDATA%\CallOfClaudeZombieLauncher\launcher.cfg` (langue, canal, version de chaque canal) |
| Journaux | `%APPDATA%\CallOfClaudeZombieLauncher\logs\` (14 jours) ; mises à jour du lanceur : `logs\launcher_update.log` |
| Rapports de plantage | `...\crashes\` (30 jours ; `crash_log.gd`, copie de celui du jeu) |

Les réglages et le dossier de combat du jeu restent communs à toutes les versions.

## Fonctionnement

- Projet Godot séparé : `launcher/` (rendu Compatibilité, ignoré par le projet du
  jeu, exclu de son export). Scripts :
  - `main.gd` : interface et déroulé (versions, canaux, téléchargements, lancement,
    auto-mise à jour) ;
  - `releases.gd` : API GitHub, canaux, ordre des versions, manifeste, notes ;
  - `store.gd` : versions installées, stock de paquets, installation en paquets,
    arguments de lancement, réglages, script d'auto-mise à jour ;
  - `downloader.gd` : téléchargement vérifié avec reprise (`Range`) ;
  - `texts.gd` (français / anglais), `version.gd` (`LAUNCHER_VERSION`),
    `crash_log.gd` (journaux, rapports de plantage).
- Versions : API publique `https://api.github.com/repos/ValentinDelob/Claude-Of-Duty-Zombie/releases`.
  Une *pre-release* (ou un numéro `-snapshot.<n>`) appartient au canal snapshot.
  Une version est jouable avec son `.exe` complet (ancien format, anciennes
  versions et stables) ou son `manifest.json` (versions en paquets, préféré).
- **Version en paquets** : `SHA256SUMS.txt` (somme du manifeste) → `manifest.json`
  vérifié (somme puis contenu : `Releases.parse_manifest`) → fichiers manquants
  (`Store.missing_files`) téléchargés avec reprise et vérifiés un par un →
  installation par copies locales (`Store.install_manifest` : moteur copié sous le
  nom du jeu, core à côté avec le même nom, chargé tout seul par le moteur) →
  lancement avec `-- --packs=<voix fr>,<voix en>` (montées par l'autoload `Packs`).
- Notes : `changelogs/changelogs.json` et `changelogs/img/` du dépôt, lus sur
  `raw.githubusercontent.com` (branche main) et gardés en cache pour le hors
  ligne. Chaque entrée porte son canal ; une stable rassemble les notes des
  snapshots depuis la stable précédente (`tools/promote.sh`).
- **Auto-mise à jour** : la source est la release la plus récente **du canal
  choisi** (`Releases.launcher_release` ; un joueur stable ne reçoit jamais le
  lanceur d'une snapshot), jamais une release sans `SHA256SUMS.txt`.
  - Depuis le lanceur 8 : `SHA256SUMS.txt` → `manifest.json` de cette release
    (somme vérifiée, puis `Releases.parse_manifest`) → entrée `launcher`
    (`docs/RELEASE.md` § 4). Si son `version` est plus grand que
    `LAUNCHER_VERSION` (`Releases.launcher_from_manifest`), le lanceur est
    téléchargé depuis la release qui le porte (souvent plus ancienne : il n'est
    publié que quand il change), avec la somme et la taille du manifeste.
  - Repli (ancien mécanisme, `Releases.launcher_from_assets`) : release sans
    manifeste, ou manifeste sans entrée `launcher` (`v0.2.0-snapshot.165` à
    `167`) : `launcher_version.txt` et `ClaudeOfDutyZombie-Launcher.exe` joints
    à cette release, somme lue dans son `SHA256SUMS.txt`. Un manifeste non
    conforme arrête tout (pas de repli).
  - Les lanceurs 7 et plus anciens ne connaissent que le repli : les stables
    joignent toujours ces fichiers (`tools/promote.sh`), les snapshots
    seulement quand elles publient un nouveau lanceur.
  - Ensuite, comme avant : le nouveau lanceur est téléchargé en `.part` et
    vérifié (taille, SHA-256) AVANT tout remplacement, puis un script `.bat`
    (`Store.update_script`) attend sa fermeture, garde l'ancien en `.bak`, met le
    nouveau en place et le démarre (`--updated`). Le nouveau signale son démarrage
    (`user://launcher_update.ok`) ; sans ce signal en 90 s, il est arrêté, mis de
    côté (`.echec`) et l'ancien est remis puis relancé (`--update-failed`, message
    au joueur). Chaque étape est notée dans `logs/launcher_update.log`.
- Sécurité (détails : `docs/SECURITY.md`, « Ce que le lanceur vérifie ») :
  HTTPS vers les seuls domaines GitHub (redirections revérifiées), réponses
  bornées, numéros de version et noms de fichiers filtrés (fin de texte stricte),
  notes échappées ; chaque release publie `SHA256SUMS.txt` ; manifeste vérifié et
  validé champ par champ, adresses reconstruites par le lanceur (jamais lues dans
  le fichier) ; chaque paquet vérifié (taille, SHA-256) avant d'être rangé ;
  anciennes releases sans sommes : taille vérifiée seulement ; release récente
  sans sommes : refusée.
- Tests (tâche `launcher:tests` de `tools/check.sh`) :
  - `godot --headless --path launcher -s res://tests/test_launcher.gd` : versions,
    canaux, manifestes piégés (entrée `launcher` comprise, manifestes sans elle
    acceptés), décision d'auto-mise à jour (manifeste, canal choisi, numéro plus
    grand seulement, repli sur `launcher_version.txt`), installation
    différentielle (dossier temporaire), réglages, script d'auto-mise à jour,
    journaux et plantages, textes ;
  - `godot --headless --path launcher -s res://tests/test_downloader.gd` :
    téléchargement contre un serveur HTTP **local** (coupure et reprise, serveur
    sans reprise, octets faux, redirections autorisée / interdite) ;
  - la release démarre aussi le lanceur exporté hors écran (`--offline --capture=...`).
- Options : `--capture=<png>`, `--changelogs=<json local>`, `--offline`,
  `--quit-after-update`, `--updated` / `--update-failed` (posées par le script
  d'auto-mise à jour), `--ui-scale=<facteur>` (échelle imposée, avec
  `--resolution` : vérifier le rendu 4K sur un écran 1080p).
- Échelle : les tailles de `look.gd` sont celles d'un écran 1920 × 1080 ; au
  démarrage tout est multiplié par `Look.screen_factor()` (résolution de
  l'écran : 4K × 2, 1440p × 1,35), donc même rendu sur tous les écrans ;
  agrandir la fenêtre donne plus de place, jamais des textes plus gros.

## Écrire les notes d'une nouvelle version

À chaque fonctionnalité livrée, avant `tools/ship.sh` :

1. Créer `changelogs/next/next.json` :
   ```json
   {"title": {"fr": "Titre court", "en": "Short title"},
    "items": [{"fr": "Ce que le joueur découvre.", "en": "What the player discovers."}]}
   ```
   Puces concises, pour les joueurs : nouveautés, cartes, armes, sons, confort de
   jeu, corrections gênantes en jeu ; **jamais** de détails techniques (fichiers,
   tests, outils, refactorisation). Français et anglais écrits nativement.
2. Ajouter à côté les captures (`.jpg` de préférence, 1280 × 720 au plus), triées
   par nom.
3. `tools/commit.sh` (appelé par `tools/ship.sh`) range ces notes sous le numéro
   de la snapshot que le commit va devenir (`tools/changelog_merge.gd`) et
   `tools/release.sh` les place en tête de la page de la release.

Quand le lanceur change, augmenter `LAUNCHER_VERSION` dans `launcher/scripts/version.gd`
(de 1) : `tools/release.sh` refuse de publier un lanceur modifié (sources de
`launcher/` hors `tests/`, ou version de Godot) sous un numéro déjà publié, et
ne republie pas un lanceur inchangé.
