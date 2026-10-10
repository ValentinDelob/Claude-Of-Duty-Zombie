# Tests — stratégie, niveaux et outils

Ce document décrit comment le projet est vérifié : quels niveaux de tests
existent, comment en écrire un de chaque niveau, quoi lancer et quand.
Historique et mesures de la refonte : `docs/TESTING_PLAN.md`.

## 1. Principes

- **Pyramide** : beaucoup de tests unitaires rapides, moins de scénarios dans
  le vrai jeu, très peu de bout-en-bout (multijoueur, rendu). Un cas limite se
  teste au niveau le plus bas possible ; un scénario couvre le cas nominal
  (« golden path », Sea of Thieves [1]).
- **Invisibles et silencieux** : `--headless` partout où c'est possible ; les
  rares tests avec rendu tournent dans une fenêtre réduite puis déplacée hors
  des écrans (`tools/nofocus.sh`). Peu de jeux à la fois (`JOBS=3`,
  `GUI_JOBS=1` par défaut).
- **Temps de jeu, pas temps réel** : les minuteurs du jeu lisent
  `GameClock.now()` (somme des pas de physique). Les scénarios sans rendu
  tournent avec `--fixed-fps 60` : 1 s de jeu = 60 images simulées aussi vite
  que le processeur le permet (×3 à ×10 plus rapide), et le résultat ne dépend
  plus de la charge de la machine.
- **Attendre un événement, jamais une durée arbitraire** : `until(cond,
  délai_max, "quoi")`. Une attente fixe n'est légitime que pour simuler un
  joueur (viser, tenir une touche) ; en temps simulé elle ne coûte presque rien.
- **Indépendants de l'ordre** : chaque test part d'un état connu (réglages et
  dossier de combat propres au processus, remis à zéro à la fin).
- **Aléatoire rejouable** : chaque scénario tourne avec une graine fixe
  (hash de son nom, imprimée dans le journal : `[autotest] graine N`). Elle
  fixe `seed()` et les `RandomNumberGenerator` du jeu (caisse, apparitions,
  chiens…, graines à leur création par `Autotest._seed_rngs`).
  `--seed=N` (ou `AUTOTEST_SEED=N`) rejoue un échec ou essaie un autre
  tirage. Hors autotest, l'aléatoire du jeu n'est pas touché.
- **Captures d'écran** : uniquement pour un ajout **en cours** (revue humaine) ;
  une fois la fonctionnalité publiée, la capture sort du check. Les
  vérifications logiques restent.

## 2. Niveaux

| Niveau | Où | Lancement | Durée typique |
|---|---|---|---|
| N0 compilation | `tests/parse_all.gd` | tâche `parse:scripts` | ≈ 20 s |
| N1 unitaire | `tests/test_*.gd` (`extends TestCase`) | une seule instance, fichiers impactés seulement | ms à 1 s par test |
| N2 scénario | `tests/autotest/<nom>.gd` (`extends AutotestScenario`) | `--headless --fixed-fps 60`, **en série** : plusieurs scénarios enchaînés dans un même processus (`--autotest=a,b,c`), état global remis à zéro entre deux | 1 à 10 s par scénario |
| N3 bout-en-bout | `## @rendu` (rendu réel), `mp_<nom>_host/_client.gd` (hôte + client), `tools/net_smoke.sh` | rendu : temps réel ; multijoueur : `--fixed-fps 60` (sauf `@temps-reel`) | 15 à 60 s |
| Carte dédiée | `## @carte <id>` | seulement quand la carte change | — |
| Perf | `perf_*`, `long_*`, `## @niveau perf` | `tools/perf.sh`, jamais dans le check | — |
| Soak | `long_soak*` (solo), `mp_soak_*` (`## @niveau long`) | à la main (voir ci-dessous), jamais dans le check | 1 à 2 min par carte |

### Soak (endurance avec invariants)

Un bot joue de nombreuses manches en utilisant tout ce que la carte propose
par le vrai chemin d'interaction (visée, [F], validation du serveur) :
portes et débris, courant, caisse au hasard, grenades, peluches leurres,
téléporteur, pièges, barricades, mise à terre, manche de chiens. En continu : positions finies, points jamais
négatifs, munitions dans leurs bornes, aucune invite sur un objet épuisé,
manche qui finit, « à terre » jamais bloqué, zombie immobile 20 s relevé
(endroit du décor à revoir) et en échec s'il n'est pas retiré par le filet
de BO1 ; à la fin, aucune erreur ni avertissement du moteur (Logger).

```bash
godot --headless --fixed-fps 60 --log-file tests/_out/logs/soak.log --path . -- --autotest=long_soak,long_soak_draft
AUTOTEST_PORT_OFFSET=5500 sh tools/mp_test.sh soak   # hôte + client, départ et retour refusé
```

### Écrire un test unitaire (N1)

```gdscript
extends TestCase
## Ce que ce fichier vérifie (une phrase).

func test_prix_de_la_caisse() -> void:
	assert_eq(MysteryBox.COST, 950)

func test_session_depense() -> void:
	var s := Session.new()
	host.add_child(s)          # nœud du runner : accès à l'arbre si besoin
	var pd := s.create(1)
	assert_false(s.try_spend(1, 9999), "pas assez de points")
	s.queue_free()
```

- Logique pure d'abord (règles, codecs, parseurs, tables de données).
- Test « actor » (idée de Sea of Thieves) : construire UN nœud du jeu seul,
  l'ajouter sous `host`, appeler `_physics_process(1.0 / 60.0)` à la main pour
  l'avancer, vérifier. Pas de carte, pas de partie.
- Assertions : `assert_true`, `assert_false`, `assert_eq`, `assert_near`.
  Attentes : `wait_frames(n)`, `wait_seconds(s)` (à éviter).
- Lancer un fichier : `godot --headless --path . res://tests/test_runner.tscn -- --files=test_points.gd`.

### Écrire un scénario (N2)

```gdscript
extends AutotestScenario
## Ce que le scénario vérifie (cas nominal).

var H := AutotestHelpers

func run() -> void:
	timeout_sec = 90
	var p := await H.start_solo_game(self, "test_arena")
	if p == null:
		return
	var game := Game.instance
	game.rounds.paused = true
	var pd := game.session.local_data()
	var z := await H.dummy_zombie(self, p.global_position + Vector3(0, 0, -5))
	H.aim_at(p, z.head_position())
	await H.shoot(self, p)
	await until(func(): return pd.points > 500, 5.0, "points de la touche crédités")
	at.check(pd.points >= 510, "au moins +10 pour la touche (%d)" % pd.points)
```

- Petites cartes de test (`test_arena`, `test_levels`) plutôt que les vraies
  cartes, sauf si la carte elle-même est le sujet.
- Mesurer une durée de jeu avec `GameClock.msec()`, jamais
  `Time.get_ticks_msec()` (qui reste réservé aux mesures de coût CPU).
- Un drapeau statique ou un réglage modifié par le scénario doit être remis
  à la fin.
- Lancer seul : `godot --headless --fixed-fps 60 --path . -- --autotest=<nom>`.
- En série, les scénarios partagent le processus : entre deux,
  `Autotest._reset_between()` quitte la session, revient au menu, remet les
  réglages par défaut (`Settings.reset_for_test()`), relâche les touches et
  remet les variables statiques connues. Un scénario qui modifie un nouvel
  état global doit le remettre lui-même ou l'ajouter à `_reset_between()`.
  Un scénario qui échoue en série est rejoué seul : s'il passe seul, le bilan
  le signale (état laissé par un scénario précédent).

### Écrire un test multijoueur (N3)

Deux scénarios, `mp_<nom>_host.gd` et `mp_<nom>_client.gd`, lancés ensemble
par `tools/mp_test.sh <nom>` (sans délai entre les deux), à cadence fixe ×3.

- Démarrage : `MpHelpers.host_game(self, PORT)` / `MpHelpers.join_game(self, PORT)`
  (le client attend que l'hôte écoute, l'hôte que le client soit au salon ;
  connexion abandonnée : le client réessaie, `MpHelpers.JOIN_TRIES`).
- Port : unique parmi tous les tests multijoueur (17801 à 17999), toujours
  `+ MpHelpers.port_offset()` (check.sh décale de 1000 par place).
- **Jamais de délai fixe pour attendre l'autre jeu** : rendez-vous par
  fichiers, `MpHelpers.signal_peer("etape")` d'un côté,
  `await MpHelpers.wait_peer(self, "etape", délai)` de l'autre (dossier
  `tests/_out/mp_sync/<nom>_<décalage>`, vidé par mp_test.sh).
- Fin : `await MpHelpers.finish(self)` des deux côtés (aucun ne quitte, ni ne
  coupe la connexion, pendant que l'autre vérifie encore).
- Une action du client que le serveur valide avec la position qu'il connaît
  (interaction, réparation…) : attendre que l'hôte **voie** le client en place
  (il le signale) ; la marionnette est interpolée en temps réel, donc en
  retard de ≈ 0,3 s de jeu à ×3.
- Les effets de tir passent par un canal non fiable : ne pas compter sur un
  nombre exact de paquets (voir mp_sync : l'hôte tire jusqu'à ce que le
  client en ait vu 5).

### Annotations d'en-tête

| Annotation | Effet |
|---|---|
| `## @rendu` | lancé avec rendu, en temps réel (N3) — seulement si le test lit vraiment l'image (pixels, compteurs de rendu, GPU) ou pour un ajout en cours |
| `## @parts N` | scénario découpé en N parties parallèles (`mine(i)`, `owns(k)`) ; utile seulement en temps réel |
| `## @carte <id>` | dépend uniquement des fichiers de la carte `<id>` : lancé seulement quand elle change |
| `## @couvre <motifs>` | dépendances ajoutées à la main (ex. `scripts/game/throwables/*`) |
| `## @niveau perf` | hors check (`tools/perf.sh`) |
| `## @seul` | jamais en série : un processus pour lui seul (à justifier dans le fichier) |
| `## @temps-reel` | pas d'accélération (`--max-fps 60`) : le test mesure ou limite quelque chose par seconde réelle (débit réseau, transfert cadencé) ; pour un `mp_`, à mettre dans le script hôte, avec la raison précise (aujourd'hui : audio_check, mp_custommap, mp_netload) |

## 3. Le check

```bash
sh tools/check.sh
```

1. Import du projet et du lanceur.
2. **Carte des dépendances** (`tools/test_deps.gd`) : pour chaque tâche, les
   fichiers dont elle dépend (class_name nommées et chemins `res://` cités,
   sur deux niveaux ; les fichiers noyau — autoloads, `game.gd`, `player.gd`,
   `session.gd`, scènes, framework de test, scripts du check — sont des
   dépendances de tous les scénarios). Un fichier qu'aucun scénario n'atteint
   est ajouté à tous (prudence). Détail : `tests/_out/deps/<tâche>.txt`.
3. **Sélection** : une tâche n'est relancée que si l'empreinte de ses
   dépendances a changé depuis son dernier succès (`tests/_out/test_cache.txt`).
   Une tâche en échec est toujours relancée.
4. Scénarios sans rendu regroupés en **séries** équilibrées (≈ 40 s chacune,
   `BATCH_SEC`), puis pool parallèle (les plus longues d'abord) ;
   `SERIES=0` : un processus par scénario.
5. Un échec est **rejoué une fois** ; s'il passe, il est signalé INSTABLE
   (`tests/_out/flaky.txt`, premier journal gardé en `.1.log`) sans bloquer.
6. Bilan : lignes d'échec et chemin du journal de chaque tâche
   (`tests/_out/jobs/`), rapport JUnit `tests/_out/junit.xml`.

| Commande | Usage |
|---|---|
| `sh tools/check.sh` | tâches impactées (avant un commit : `tools/commit.sh`) |
| `sh tools/check.sh --full` | tout (hors cartes dédiées) ; exigé par `tools/release.sh` |
| `sh tools/check.sh --cartes` | force les tests dédiés à une carte (`## @carte <id>`) |
| `sh tools/check.sh --fast` | sans réseau ni multijoueur |
| `sh tools/check.sh --no-retry` | pas de rejeu |
| `SCENARIOS="grenades traps" sh tools/check.sh` | ces scénarios, sans cache |
| `MP="lobby" sh tools/check.sh` | ces tests multijoueur seulement (ni scénario ni test réseau), sans cache |
| `SCENARIOS="boot" MP="lobby" sh tools/check.sh` | les deux listes ensemble |
| `sh tools/perf.sh [scénarios]` | mesures de performance fiables, un jeu à la fois |
| `QUALITY=medium OUTLINE=off sh tools/perf.sh zombie_stress map_tour` | préréglage imposé, contour noir coupé (mesure avant / après) |
| `PERF_ARGS="--only=contour" sh tools/perf.sh perf_costs` | coût A/B de quelques postes seulement (noms contenant ces mots) |
| `godot --headless --fixed-fps 60 --path . -- --autotest=perf_cpu` | coût CPU d'une fin de partie sans rendu (DRAFT ARENA, 24 zombies + 4 chiens, tir, grenades) et micro-mesures des fonctions chaudes (lignes « ancien code » : l'ancienne version, même processus) |
| `sh tools/scenario.sh perf_dog_pack` | meute de 24 chiens cubiques lâchée sur le joueur (TEST ARENA) : img/s moyennes et pire seconde avec rendu, captures de la meute et de morts |
| `bash tools/profile.sh [scénario]` | même scénario dans une COPIE instrumentée du projet : ms par image et µs par appel de chaque `_process` / `_physics_process` et de quelques fonctions chaudes (sources jamais modifiées) |

Optimisation sans changement de comportement : garder l'ancienne logique
comme référence dans un test et comparer sur des entrées tirées au hasard
(`tests/test_perf_equivalence.gd`, `tests/test_particle_pool.gd`).

`tools/ship.sh` lance `tools/commit.sh` avec `--full`, puis la release ;
`tools/release.sh` refuse de publier si le dernier check complet réussi ne
porte pas exactement sur le contenu actuel (`tests/_out/last_full_ok`).

## 4. Couverture de code

GDScript n'a pas de couverture native et aucun outil mûr n'existe pour
Godot 4.7 (projets Godot 3 seulement, ou alpha : voir `docs/TESTING_PLAN.md`
§ 2) : le projet a son propre outil, léger.

```bash
sh tools/coverage.sh
```

1. copie du projet et du lanceur dans un dossier temporaire (le cache
   d'import est copié : pas de réimport des assets) — **les sources ne sont
   jamais modifiées** ;
2. `tools/coverage/instrument.gd` ajoute, dans la copie, une ligne
   `CovHits.h(n)` avant chaque instruction d'un corps de fonction (pas avant
   `elif` / `else`, les motifs de `match`, les suites d'expression sur
   plusieurs lignes, le contenu des chaînes `"""…"""`) ;
3. check complet dans la copie (`--full --cartes --no-retry`) ; chaque jeu vide
   ses compteurs en quittant ;
4. `tools/coverage/report.gd` : `tests/_out/coverage/summary.md` (par
   dossier), `files.txt` (par fichier, du moins couvert au plus couvert),
   `missed.txt` (fonctions jamais exécutées).

Durée ≈ 18 min (le code instrumenté est 2 à 3 fois plus lent) : **hors check
par défaut**, à lancer avant une release importante ou pour choisir les tests
à écrire. Dans la copie, quelques tests sensibles au temps échouent (attendu :
lenteur) ; leurs compteurs sont quand même pris.

**Seuils** (`tools/coverage/floors.txt`) : un par dossier, relevés au niveau
atteint par `COV_RATCHET=1 sh tools/coverage.sh` ; ils ne descendent jamais.
Sous un seuil : avertissement ; `COV_STRICT=1` rend le dépassement bloquant.

### Mesure initiale (30/09/2026)

Instructions couvertes **87,6 %** (25 298 / 28 879), fonctions **91,8 %**.
Plus faibles : lanceur 19,9 % (interface `main.gd` et journal des plantages
jamais exécutés), perks 47 % (effet visuel du Nova Flop, aide à la visée
Deadeye), interactions 83 % (fonctions `setup` jamais appelées), éditeur 85 %.

### Zones volontairement non testées

- **Entrées réelles** (`player_input.gd`, souris et manette) : les tests
  pilotent le joueur en bot (`bot_controlled`), le lecteur d'entrées lui-même
  ne se teste qu'à la main.
- **Rendu pur** (aspect des shaders, lumière) : pas de capture comparée
  automatiquement (décision : captures seulement pendant un ajout en cours).
- **Mesures de performance** : niveau perf (`tools/perf.sh`), pas le check.
- **Interface du lanceur** (`launcher/scripts/main.gd`) : à rendre testable
  pendant sa refonte (phase 4), la logique (versions, sommes, stockage,
  journaux) étant testée à part.

## Sources

1. R. Masella, *Automated Testing of Gameplay Features in Sea of Thieves*, GDC 2019 — https://media.gdcvault.com/gdc2019/presentations/Masella_Robert_AutomatedTestingOf.pdf
2. Riot Games, *Automated Testing for League of Legends* — https://www.riotgames.com/en/news/automated-testing-league-legends
3. H. Vocke, *The Practical Test Pyramid* — https://martinfowler.com/articles/practical-test-pyramid.html
4. Google Testing Blog, *Test Sizes* — https://testing.googleblog.com/2010/12/test-sizes.html
5. Microsoft, *Test Impact Analysis* — https://learn.microsoft.com/en-us/azure/devops/pipelines/test/test-impact-analysis
6. Godot, ligne de commande (`--fixed-fps`, `--headless`) — https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html
7. Godot, classe `Engine` (`time_scale`, ticks de physique) — https://docs.godotengine.org/en/stable/classes/class_engine.html
