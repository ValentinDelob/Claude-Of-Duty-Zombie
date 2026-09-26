# Reprise du travail — prompt à redonner à Claude

Copier tout le bloc ci-dessous dans une nouvelle session Claude Code ouverte à
la racine du dépôt cloné, puis coller à la suite le cahier des charges
d'origine (sections 45 à 69).

```text
Tu reprends le développement de « Call of Claude Zombie », un FPS coop zombies
low-poly horrifique en Godot 4.7.2 (GDScript, Forward+), dépôt GitHub
git@github.com:ValentinDelob/Claude-Of-Duty-Zombie.git (branche main). Tout le
texte du jeu, les commentaires et les messages de commit sont en FRANÇAIS.

OBJECTIF DE L'UTILISATEUR : faire un CLONE de Call of Duty: Black Ops 1 —
mode Zombies. Chaque décision (gameplay, rythme des manches, économie de
points, prix, armes, atouts, boîte mystère, Pack-a-Punch, téléporteur, pièges,
comportement des zombies, HUD, sons, menus, ambiance) doit viser à reproduire
au plus près l'expérience et les sensations de BO1 Zombies (Kino der Toten,
Five, Ascension...). En cas de doute, fais comme BO1. Seule réserve, issue du
cahier des charges (section 45) : ne pas copier directement le logo Call of
Duty ni les assets graphiques de Black Ops (identité visuelle originale, noms
d'atouts/armes originaux déjà en place).

Le
cahier des charges d'origine (sections 45 à 69 : menu Black Ops, solo,
multijoueur host/join IP, architecture serveur autoritaire, downed, GameState,
lobby, règles Git strictes, perf GTX 1050) est collé à la suite de ce message :
il reste la référence.

## 1. Mise en place sur cette machine
- Installer Godot 4.7.2 standard : `winget install GodotEngine.GodotEngine`.
  Créer un wrapper bash `~/bin/godot` qui lance
  `$LOCALAPPDATA/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.7.2-stable_win64_console.exe "$@"`.
- `git pull`, puis `godot --headless --path . --import` (enregistre les
  class_name ; à refaire après tout nouveau fichier avec class_name).
- Lis README.md, docs/ARCHITECTURE.md et ce fichier (docs/HANDOFF.md).

## 2. Règles de travail (imposées par l'utilisateur, à respecter)
- Chaque fonctionnalité : analyse -> plan -> implémentation -> lancement du
  jeu -> test réel -> logs -> corrections -> commit. Jamais « ça devrait
  marcher ».
- Commit atomique et fonctionnel, messages feat:/fix:/perf:/refactor:/docs:/
  test: + puces en français + ligne finale
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Commits UNIQUEMENT via `sh tools/commit.sh fichier_message.txt` : il lance
  `sh tools/check.sh` (import, compilation de tous les scripts, tests unitaires,
  test réseau, tous les scénarios tests/autotest/*.gd en fenêtres parallèles,
  tests multijoueur hôte/client) et ne committe que si tout passe (~30 min).
  Ne jamais chaîner un commit après un `grep` (le code de retour serait faux).
- Push sur main autorisé pour le moment (demande de l'utilisateur).
- Perf fiable : `sh tools/perf.sh [scénarios]` (1080p, un jeu à la fois) ;
  ~150 fps sur la RTX A2000 de dev ≈ 60 fps sur GTX 1050. En parallèle
  (check.sh), un seuil de perf manqué n'est qu'un avertissement.
- L'utilisateur autorise jusqu'à 5 agents simultanés (worktrees isolés
  `.claude/worktrees/`, ignorés par git). Garde les fichiers cœur de gameplay
  (game.gd, combat.gd, player.gd, hud.gd) pour toi ; donne aux agents des
  périmètres disjoints ; interdis-leur `taskkill /IM Godot…` (ça tue les jeux
  des autres) ; intègre leurs commits par cherry-pick sur main puis refais un
  check complet avant de pousser.
- Scénario isolé : `godot --path . --windowed -- --autotest=<nom>` ; captures
  dans tests/_out/shots/ (regarde-les pour juger le rendu). Test multijoueur :
  `sh tools/mp_test.sh <nom>` (mp_<nom>_host.gd + mp_<nom>_client.gd).

## 3. État actuel (main poussé, commit 2f12381 « perf: optimize rendering »)
Fait et testé : fondations réseau (ENet host/client, solo = OfflineMultiplayerPeer,
même code), GameState, contrôleur FPS, armes (WeaponDB, prédiction client,
validation serveur), zombies (squelette procédural skinné, IA A* AStarGrid2D,
instantanés 15 Hz), dégâts, points, manches, apparitions par zones, carte
BUNKER K-7 (7 zones, shaders procéduraux), portes payantes, achats muraux,
courant, 5 atouts originaux, boîte mystère (CLAUDE-RAY), Pack-a-Punch,
téléporteur, piège électrique, salon multijoueur, connexion par IP avec erreurs
lisibles, synchro joueurs (soldats low-poly animés, noms) et zombies, état À
TERRE + réanimation, gameplay multijoueur (pause, tableau des scores Tab,
spectateur, départ/perte de l'hôte), préchauffage des shaders, menu principal
complet (OPTIONS, CRÉDITS) avec ambiance horreur militaire (fond 3D, logo
original, post-traitement, musique), presets de qualité LOW/MEDIUM/HIGH
(RenderQuality, `--quality=low` en ligne de commande), README.
Graphismes 100 % procéduraux. Sons : armes, impacts, barricades et voix des
zombies = enregistrements CC0 importés par tools/audio/sfx_import.gd (recettes
tools/audio/sfx_recipes.gd, crédits docs/ASSETS.md) ; le reste est synthétisé
par tools/gen_audio.gd (qui ignore les sons importés) et tools/gen_audio_menu.gd.

## 4. Reste à faire (dans cet ordre)
1. Intégrer la branche `perf/zombies-net` (commit 56441a7 « perf: optimize
   zombie system », poussée sur GitHub, testée seule mais PAS encore avec le
   main actuel) : `git cherry-pick 56441a7` sur main, `sh tools/check.sh`,
   `sh tools/perf.sh zombie_stress`, push. Attention : les zombies sont
   désormais en mode « flottant » à y = 0 (cartes plates uniquement) ; toute
   modification de cellules de navigation doit passer par NavGrid.set_blocked.
2. « perf: optimize networking » (pas commencé) : mesurer la bande passante
   (statistiques ENet) pendant un test mp avec 24 zombies et des tirs ;
   instantanés de zombies en delta + rafraîchissement complet périodique ;
   état des joueurs envoyé seulement s'il change (keep-alive) ; regrouper les
   effets de tir ; objectif < 10 Ko/s par client ; documenter dans
   docs/ARCHITECTURE.md.
3. Refaire `sh tools/perf.sh` GPU libre (les mesures ont été faites avec
   d'autres jeux sur le GPU) : menu (boot, seuil 150 fps, était à ~104-146 sous
   charge ; leviers : MENU_3D_SCALE dans main_menu.gd, glow, ombre de la lampe),
   MEDIUM/HIGH de RenderQuality (réévaluer le MSAA 2x de HIGH).
4. tests/autotest/long_endurance.gd (exclu de check.sh, préfixe long_) : le
   bot joue les manches 1 à 5 ; problème NON RÉSOLU : vers le début de la
   manche 3, la coroutine du scénario cesse d'être reprise (ni les minuteurs
   SceneTree ni process_frame ne la relancent), alors que le jeu continue ;
   reproduit même sans tir du bot ; `debug_jump_to(3)` isolé fonctionne.
   Trouver la cause (vérifier aussi qu'il ne s'agit pas d'un vrai blocage du
   jeu), puis vérifier les fuites mémoire sur la durée.
5. « polish: improve visual effects » : finitions (sang, impacts, lumières des
   machines, barricades de fenêtres éventuelles, taille des étiquettes de nom,
   pose « à terre » des coéquipiers, préchauffage par preset de qualité).
6. Mettre à jour README (état d'avancement) et docs/ARCHITECTURE.md.

## 5. Pièges déjà rencontrés (ne pas les refaire)
- Shader spatial : si POSITION est écrit dans une branche, l'écrire dans TOUS
  les cas (sinon les meshes deviennent invisibles).
- Control enfant d'un CanvasLayer : poser les ancrages AVANT add_child (sinon
  taille nulle).
- Couleurs de sommets des personnages : convertir sRGB -> linéaire.
- save_to_wav n'écrit pas de boucle : régler edit/loop_mode=2 dans le .import.
- Pendant les autotests, les réglages sont lus/écrits dans
  user://settings_autotest.cfg (jamais les réglages du joueur).
- Les RPC : requêtes client->serveur en @rpc("any_peer","call_local") +
  rpc_id(1) ; diffusions en @rpc("authority","call_local") ; le serveur ne fait
  jamais confiance au client pour dégâts, points, achats, portes, manches.
- Sortie propre : Audio.stop_all() / Router.quit_game() (sinon ressources
  orphelines signalées à la fermeture).

Commence par la mise en place (§1), vérifie que `sh tools/check.sh` passe sur
main, puis attaque le §4 point par point en respectant les règles du §2.
```
