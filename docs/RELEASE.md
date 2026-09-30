# Publication, versions et mises à jour légères

> Phase 4 de la refonte (`docs/PROMPT_REFONTE_TESTS_RELEASE.md`). Étude du
> 30/09/2026, Godot 4.7.2. Ce document fixe le schéma retenu ; les choix ont
> été faits en l'absence de l'utilisateur, en prenant chaque fois l'option
> recommandée et réversible (§ 8 : points à valider).

## 1. Constat

| Élément | Taille | Remarque |
|---|---|---|
| Modèle d'export Windows officiel 4.7.2 (`windows_release_x86_64.exe`) | **109,3 Mo** | le moteur seul |
| Lanceur exporté | 109,3 Mo | = le moteur + 33 Ko de lanceur (rendu Compatibilité : ne réduit pas le modèle) |
| Jeu v0.1.132 (`.exe`, PCK intégré) | 168,7 Mo | 109 Mo de moteur + 59 Mo de contenu |
| dont voix (`assets/audio/vox`, fr + en) | 51 Mo de sources | 1 647 fichiers : l'essentiel du PCK |
| `build/` local | 2,5 Go | 17 anciens `.exe` (anciens noms compris) |

Chaque mise à jour re-télécharge donc **168 Mo, dont 65 % de moteur inchangé**
et presque tout le reste en voix inchangées.

Contenu du paquet (`export_presets.cfg`) : pas de `.blend`, `.zip` ni `.md`
(les sources Blender et Python sont sous `tools/`, exclu). Les tests
unitaires y partaient : exclus depuis ce jour (`tests/test_*`,
`tests/parse_all.gd`, `tests/net_smoke.*`) ; `tests/autotest/` reste (scénario
`boot` de vérification du build). `tests/_out/` (314 Mo de captures) et
`build/` étaient importés par Godot à chaque export (352 Mo de textures dans
`.godot/imported`) : `.gdignore` ajouté (créé par `check.sh` / `release.sh`).

## 2. Ce que Godot 4.7 permet (sources § 9)

- **PCK séparé** : un exécutable charge le `.pck` de même nom à côté de lui ;
  `--main-pack <fichier>` charge n'importe quel PCK et passe outre le PCK
  intégré (lu dans `ProjectSettings::_setup`) — **mais seulement avec un
  moteur compilé avec les « path overrides »** : les modèles officiels
  (release) le refusent (vérifié, § 3).
- **`ProjectSettings.load_resource_pack(pack, replace_files, offset)`** : monte
  un PCK supplémentaire ; à faire dans `_init()` du **premier** autoload.
  `project.godot` (autoloads, réglages) n'est lu qu'une fois, au démarrage :
  un pack monté ensuite ne peut pas les changer.
- **PCK de patch** (Godot 4.4, PR #97118, #97356) : export des seuls fichiers
  modifiés par rapport à des PCK de base (`--export-patch <préréglage>
  <fichier> --patches <bases>`), suppressions comprises.
- **Encodage delta** (Godot 4.6, PR #112011) : `patch_delta_encoding` (zstd
  `--patch-from`), gain de ≈ 75 % sur scripts et scènes texte, inutile sur les
  données déjà compressées (textures, OGG, QOA) ; la base doit être montée
  avant les patches, décodage à chaque lecture.
- **GitHub Releases** : fichiers ≤ 2 Gio, pas de limite de taille totale ni de
  bande passante ; les téléchargements acceptent `Range` (réponse
  `206 Partial Content` de `release-assets.githubusercontent.com`) : reprise
  possible. L'API sans authentification est limitée à 60 appels / h / IP
  (le lanceur en fait un par démarrage).
- Comparaison : itch.io (butler / wharf) fait du diff par blocs d'un dossier ;
  Steam découpe en « depots » et morceaux adressés par empreinte. Notre
  découpage par paquets adressés par leur SHA-256 reprend l'idée des depots,
  sans service payant ni outil externe.

## 3. Schéma retenu

```
Lanceur ─┬─ engines/4.7.2/engine.exe          (moteur, téléchargé UNE fois par version de Godot)
         ├─ store/<sha256>.pck                (paquets vérifiés, partagés entre versions)
         └─ versions/<tag>/
              ├─ manifest.json
              ├─ ClaudeOfDutyZombie.exe       (copie locale du moteur)
              └─ ClaudeOfDutyZombie.pck       (copie locale du core)
Jeu lancé : versions/<tag>/ClaudeOfDutyZombie.exe -- --packs=store/<vox-fr>.pck
```

**Vérifié le 30/09/2026** : les modèles d'export officiels (release) refusent
`--main-pack` (« compiled without support for path overrides », option
retirée par sécurité). Le moteur charge en revanche tout seul le `.pck` de
même nom posé à côté de lui : chaque version installée a donc sa copie
locale du moteur et du core (copies faites sur le disque, rien n'est
retéléchargé). Essai réel : moteur officiel + `core.pck` (14,4 Mo) +
`vox-fr.pck` (26 Mo) : scénario `vox` réussi (réplique française lue depuis
le paquet des voix) ; sans le paquet des voix, il échoue (contre-épreuve).

- **core** : scripts, scènes, cartes, modèles, sons d'ambiance et d'armes,
  musique (tout sauf les voix) : **14,4 Mo** mesurés. Exporté par un préréglage
  « Core » (PCK seul) qui exclut `assets/audio/vox/*`. Le numéro de build y
  est inscrit comme aujourd'hui (`release.sh` modifie `config/version` le
  temps de l'export : il part dans `project.binary` du paquet).
- **vox-fr**, **vox-en** : les répliques d'une langue (916 répliques, 26 Mo en français),
  construites avec `PCKPacker` (fichiers importés + leurs `.import`, jamais
  les caches `.godot/*cache*`). Le lanceur ne télécharge que la langue
  choisie (et l'autre à la demande). Montées au démarrage par le premier
  autoload du jeu (`--packs=`), les chemins `res://assets/audio/vox/...`
  restent les mêmes (`CharacterDB` charge par chemin).
- **engine** : le modèle d'export officiel, publié comme fichier
  `engine-4.7.2.exe` dans une release ; ne change qu'à une mise à jour de
  Godot. L'ancienne version est gardée tant qu'une version installée en a
  besoin.
- **Adressage par contenu** : chaque paquet est nommé et vérifié par son
  SHA-256. Un paquet identique à celui d'une release précédente n'est pas
  republié : le manifeste pointe vers la release qui l'a déjà.
- **Patches delta de Godot** : pas dans un premier temps (gain faible sur un
  core de 10 Mo, chaîne de patches à gérer) ; possibles plus tard sur `core`.

### Taille d'une mise à jour

| Cas | Aujourd'hui | Nouveau schéma |
|---|---|---|
| Code ou carte modifiés | 168 Mo | **≈ 10 à 14 Mo** (core) |
| Nouvelles répliques | 168 Mo | core + une langue (≈ 25 Mo) |
| Nouvelle version de Godot | 168 Mo | + 109 Mo de moteur, une fois |
| Première installation (une langue) | 168 Mo | ≈ 150 Mo |

## 4. Manifeste (`manifest.json`, joint à chaque release)

```json
{
  "format": 1,
  "version": "v0.2.1-snapshot.180",
  "channel": "snapshot",
  "build": "0.2.1-snapshot.180",
  "engine": {"godot": "4.7.2", "file": "engine-4.7.2.exe", "sha256": "…", "size": 109268480, "release": "v0.2.0"},
  "packs": [
    {"id": "core", "file": "core-1a2b3c4d.pck", "sha256": "…", "size": 12345678, "release": "v0.2.1-snapshot.180", "main": true},
    {"id": "vox-fr", "lang": "fr", "file": "vox-fr-5e6f7a8b.pck", "sha256": "…", "size": 26000000, "release": "v0.2.0"},
    {"id": "vox-en", "lang": "en", "file": "vox-en-9c0d1e2f.pck", "sha256": "…", "size": 25000000, "release": "v0.2.0"}
  ]
}
```

- `release` : la release GitHub où se trouve le fichier (celle-ci ou une plus
  ancienne) ; l'adresse est reconstruite et vérifiée par le lanceur
  (`https://github.com/<dépôt>/releases/download/<release>/<file>`, domaines et
  noms contrôlés comme aujourd'hui : `docs/SECURITY.md`).
- `SHA256SUMS.txt` de la release contient la somme du manifeste ; chaque
  paquet est vérifié après téléchargement (SHA-256) avant d'être rangé dans
  `store/`.
- Reprise d'un téléchargement interrompu : `store/<sha256>.part` + en-tête
  `Range` ; somme fausse = fichier supprimé et retéléchargé entièrement.

## 5. Versions et canaux

| Canal | Tag | Release GitHub | Qui la voit |
|---|---|---|---|
| **snapshot** | `v<M.m.p>-snapshot.<n>` (n = nombre de commits, comme aujourd'hui) | *pre-release* | nouveau lanceur, canal snapshot |
| **stable** | `v<M.m.p>` | release normale, « latest » | tous les lanceurs, anciens compris |

- `tools/ship.sh` publie une **snapshot** (défaut). Première série :
  `v0.2.0-snapshot.<n>` ; après une stable `v0.2.0`, les snapshots deviennent
  `v0.2.1-snapshot.<n>` (version visée par la prochaine stable).
- `tools/promote.sh <snapshot> [<version>]` crée la **stable** sans rien
  reconstruire : même commit, mêmes fichiers (téléchargés de la snapshot puis
  joints à la nouvelle release), manifeste recopié avec `"channel": "stable"`.
  Le jeu promu garde son numéro de build (`0.2.0-snapshot.37`) : hôte et
  clients d'une stable et de sa snapshot sont le même binaire et se
  reconnaissent en multijoueur ; le menu affiche « v0.2.0 (snapshot 37) ».
- Ordre des versions : `v0.2.0` > `v0.1.157` pour les anciens lanceurs
  (comparaison numérique) ; une snapshot `-snapshot.n` passe avant la stable
  de même numéro (règle semver des préversions).
- Notes de version : `changelogs/` indique le canal de chaque entrée.

## 6. Compatibilité

- **Anciens lanceurs** : ils ignorent les *pre-releases* et les tags qui ne
  sont pas « v + nombres » (vérifié dans `launcher/scripts/releases.gd`) : ils
  ne voient jamais les snapshots. Chaque **stable** continue donc de joindre
  l'exécutable complet `ClaudeOfDutyZombie-v<version>.exe` (et les deux noms
  du lanceur, `launcher_version.txt`, `SHA256SUMS.txt`) : un ancien lanceur
  l'installe comme avant et se met à jour tout seul vers le nouveau lanceur
  (numéro de lanceur relevé).
- **Versions déjà installées** (`versions/<tag>/CallOfClaudeZombie.exe` ou
  `ClaudeOfDutyZombie.exe`) : restent jouables, le nouveau lanceur gère les
  deux formes d'installation.
- **Données des joueurs** : dossier `app_userdata/Call of Claude Zombie`
  inchangé (`custom_user_dir_name` du core), réglages du lanceur dans le même
  dossier qu'aujourd'hui.
- **Journaux de plantage** : inchangés ; le lanceur note aussi la commande de
  lancement (moteur, paquets) dans le rapport.

## 7. Vérifications automatiques de la release

- Liste blanche des types de fichiers du paquet (`tools/pack_check.gd`) :
  `.gdc`/`.gd`, `.tscn`/`.scn`, `.tres`/`.res`, fichiers importés
  (`.ctex`, `.oggvorbisstr`, `.sample`, `.mesh`, `.scn`…), `.import`,
  `.json` des cartes, polices, `project.binary`, caches Godot ; tout autre
  type (`.blend`, `.py`, `.md`, `.png` hors import, `.zip`, `.log`…) ou un
  paquet au-delà de la taille maximale fait échouer la release.
- Somme et taille de chaque fichier publié ; le lanceur refuse tout fichier
  dont la somme ne correspond pas (`docs/SECURITY.md`).
- `build/` : seuls le dernier build et les fichiers à publier sont gardés ;
  les anciens `.exe` sont supprimés par `release.sh` (ils restent sur GitHub).

## 8. Choix faits sans validation (à revoir)

1. Découpage core / voix par langue (pas encore par personnage).
2. Moteur fourni par le lanceur (`engine-<godot>.exe`) plutôt que dans chaque version.
3. Pas de patch delta de Godot au début.
4. Numérotation `v0.2.0` / `v0.2.x-snapshot.<n>` ; la première stable sera
   `v0.2.0`.
5. Les stables gardent l'exécutable complet pour les anciens lanceurs.

## 9. Sources

- Godot, *Exporting packs, patches, and mods* — https://docs.godotengine.org/en/latest/tutorials/export/exporting_pcks.html
- Godot, ligne de commande (`--main-pack`, `--export-patch`, `--patches`) — https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html
- `ProjectSettings.xml` 4.7 (`load_resource_pack`) — https://raw.githubusercontent.com/godotengine/godot/4.7-stable/doc/classes/ProjectSettings.xml
- `project_settings.cpp` 4.7 (`--main-pack` avant le PCK intégré) — https://raw.githubusercontent.com/godotengine/godot/4.7-stable/core/config/project_settings.cpp
- PCK de patch : https://github.com/godotengine/godot/pull/97118 , suppressions : https://github.com/godotengine/godot/pull/97356
- Encodage delta : https://github.com/godotengine/godot/pull/112011 , https://godotengine.org/releases/4.6/
- Fusion des caches de classes / UID : https://github.com/godotengine/godot/pull/82084
- Optimiser la taille d'un build : https://docs.godotengine.org/en/latest/engine_details/development/compiling/optimizing_for_size.html
- GitHub, *About releases* — https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases
- itch.io wharf (diff) — https://itch.io/docs/wharf/algorithms/diff.html
