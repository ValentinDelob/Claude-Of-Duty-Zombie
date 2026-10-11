# Hub du scientifique, contrats et catalogue d'échanges — plan

Plan de conception du **hub** (écrans entre deux parties, chez le
scientifique), des **contrats** et du **catalogue d'échanges**
(GAME_CONCEPT §2 boucle méta, §4.2, §4.2 ter, §4.9 à §4.16). Rien n'est encore
intégré au jeu : ce document fixe les écrans, le modèle de données, le contenu
d'exemple et les lots d'implémentation.

- Maquettes : **`docs/hub_mockup/index.html`** (ouvrir dans un navigateur,
  aucune dépendance externe ; 1280 × 720, taille réelle du jeu). Une fois
  validée, l'intégration la suit **exactement** (tailles, couleurs, textes).
- Données d'exemple : **`assets/data/hub/contracts.json`** et
  **`assets/data/hub/exchanges.json`** (format §5 et §6, contenu provisoire §7).
- Décisions prises en l'absence de l'auteur : toutes marquées **(provisoire)**
  et reprises dans GAME_CONCEPT §6 bis ; à confirmer ou corriger.

## 1. Décisions principales

| # | Décision (provisoire) | Pourquoi |
|---|---|---|
| D1 | **Hub 2D maintenant** : un écran de menu à onglets. Le hub 3D (laboratoire du scientifique où l'on marche jusqu'au râtelier, au bureau, à la porte) viendra **plus tard** et ouvrira les **mêmes panneaux** | Le plus rapide à livrer et à tester ; jouable à la manette dès le départ ; le 3D demande un décor cubique complet du labo, des animations du scientifique et ne change aucune règle |
| D2 | Le **menu titre** garde JOUER (nouveau, remplace SOLO et MULTIJOUEUR), ÉDITEUR DE CARTES, OPTIONS, CRÉDITS, QUITTER. **JOUER ouvre le hub** ; solo et coop se choisissent dans l'onglet PARTIE du hub | Une seule porte d'entrée ; le joueur prépare son équipement au même endroit quel que soit le mode |
| D3 | Sept onglets à plat : **LABO, ARSENAL, PIÈCES, CONTRATS, ÉCHANGES, DÉPART, PARTIE** ; OPTIONS et DOSSIER DE COMBAT dans le menu du hub (Échap / Start) | Onglets à un seul niveau : LB / RB suffisent, rien n'est caché derrière un sous-menu |
| D4 | En coop, le **salon devient le contenu de l'onglet PARTIE** : le groupe reste connecté pendant que chacun gère son profil dans les autres onglets | Reprend `LobbyReturn` (le groupe revient au salon après une partie) sans nouvel écran ; chacun prépare son départ pendant que l'hôte choisit la carte |
| D5 | La **puissance n'est pas affichée au hub** (§4.13, validé) ; le LABO montre à la place le **meilleur score de l'arsenal** et le score de chaque arme | Au hub on ne part qu'avec des armes de base niveau 1 : la puissance vaudrait toujours 1 à 3, sans intérêt ; la règle validée l'interdit |
| D6 | Les contrats et le catalogue sont des **fichiers JSON** remplis sans coder (`assets/data/hub/`) | Même esprit que les cartes et les répliques (JSON lisibles) ; l'auteur ajoute un contrat en copiant un bloc |
| D7 | **Rotation des contrats par partie jouée**, pas par l'heure : après chaque partie d'au moins une manche survécue, la plus ancienne proposition est remplacée et les cases vides sont remplies | Fonctionne hors ligne, ne dépend pas de l'horloge du PC (pas de triche en avançant la date), testable ; « encore une partie » fait tourner le tableau |
| D8 | Les **contrats datés** utilisent la date réelle (UTC) seulement pour leur fin ; un contrat expiré disparaît du tableau **et des contrats actifs** (les échantillons ne sont jamais touchés) | Règle du concept (§4.2) ; rien n'est consommé avant la clôture, donc rien n'est perdu |
| D9 | XP d'un contrat = **XP de base × (1 + 0,02 × (niveau − 1))**, arrondie à 10 | L'XP par heure double environ du niveau 1 au niveau 50 (XP_RULES §4) : la récompense suit sans exploser |
| D10 | Les **échanges** ne rapportent **pas d'XP**, sont **illimités** et coûtent plus cher qu'un contrat équivalent | L'XP passe par les contrats (objectifs) ; le catalogue sert au farm ciblé d'un objet précis |
| D11 | Récompenses toujours **au niveau du joueur** au moment de la clôture ; **rareté fixée par le contrat** selon sa difficulté ; les pièces ont une **qualité** (ordinaire, soignée, d'exception) | Concept §4.2 ; une pièce n'a pas de rareté (§4.9), la qualité règle ses modificateurs |
| D12 | Contrats et catalogue **locaux** : en coop, chacun ses contrats, son profil, ses récompenses ; l'hôte n'en sait rien | Le profil est local (ARCHITECTURE « Profil du joueur ») ; aucun message réseau nouveau |
| D13 | Un contrat ne se **clôt qu'au hub** ; en partie, un message prévient quand l'objectif est atteint (« évacuez pour le garder ») | §4.2 : le contrat ne force jamais la fin d'une partie ; les échantillons n'entrent au profil qu'à l'évacuation |
| D14 | Actions destructives (retirer une pièce, recycler une arme) : **deux appuis** (« RETIRER » puis « CONFIRMER : LA PIÈCE SERA DÉTRUITE »), comme le recyclage en partie | Cohérent avec la station et l'inventaire existants |
| D15 | Taille d'interface : nouveau réglage **TAILLE DES MENUS** (80 à 130 %, pas de 5 %, défaut 100 %) dans OPTIONS > JEU > INTERFACE, même technique que l'éditeur (`EditorUi`) | Le seul réglage existant ne touche que l'éditeur ; le hub est dense (listes, fiches) |

## 2. Place du hub dans le flux du jeu

```
Lancement ─► Menu titre ─► JOUER ─► (1er démarrage : carte tuto obligatoire, §4.1)
                                └─► HUB (onglet LABO)
HUB ─ PARTIE ─ SOLO : carte ─► LANCER ─► partie ─► écran de fin ─► HUB (LABO)
             └ COOP : HÉBERGER / REJOINDRE ─► salon dans l'onglet PARTIE
                        └─ partie ─► écran de fin ─► HUB, onglet PARTIE (salon, groupe connecté)
HUB ─ Échap / Start ─► menu du hub : REPRENDRE, OPTIONS, DOSSIER DE COMBAT,
                                    ÉCRAN TITRE, QUITTER LE JEU
```

- Retour au hub après une partie : le **rapport de fin** (§4.16) reste l'écran
  de fin actuel du HUD ; au hub, des pastilles « NOUVEAU » marquent les armes
  et pièces ajoutées, et le LABO affiche le résumé de la dernière partie.
- **Rotation des contrats** (§5.3) : faite une fois à la fin de la partie (avec
  `MatchXp.apply`), donc visible dès l'arrivée au hub.
- En coop, ÉCRAN TITRE depuis le hub quitte la session (comme QUITTER au
  salon aujourd'hui), avec confirmation.
- Le tutoriel (§4.1) n'existe pas encore : JOUER ouvre le hub directement
  tant que la carte tuto n'est pas faite ; le contrat tuto (§7) est déjà prévu.

## 3. Écrans

Tous les écrans partagent le **cadre du hub** (maquette, écran 1) :

- **barre du haut** : nom du joueur, **niveau** et **barre d'XP** (XP dans le
  niveau / XP du niveau, niveau maximum signalé) ; onglets ; à droite, rappel
  des touches LB / RB ;
- **zone centrale** : contenu de l'onglet ;
- **barre d'invites** en bas : actions possibles avec la touche du
  périphérique utilisé en dernier (`Settings.action_label`, comme les invites
  du HUD) ; texte d'aide de l'élément choisi (comme `set_hint` des menus) ;
- **fond** : arrière-plan du menu actuel assombri (`MenuBackdrop`), en
  attendant le laboratoire 3D (§3.9).

### 3.1 LABO (accueil)

- Portrait cubique du **scientifique** et sa réplique du moment (texte FR / EN
  ; plus tard voix) : accueil, contrat prêt à remettre, contrat expiré…
- **Profil** : niveau, XP totale, XP jusqu'au niveau suivant, meilleur score
  de l'arsenal, nombre d'armes et de pièces (D5 : pas de puissance).
- **Réserve d'échantillons** : toutes les sortes connues avec icône,
  quantité, ennemi source ; une sorte jamais obtenue reste « ??? » (même
  esprit que le bestiaire, §4.17).
- **Contrats actifs** (3 au plus) : progression `possédés / demandés` par
  échantillon, mention **PRÊT** quand il peut être remis.
- **Dernière partie** : issue, manche, XP gagnée, butin gardé (raccourci vers
  ARSENAL).
- Raccourcis : LANCER UNE PARTIE (onglet PARTIE), VOIR LES CONTRATS.

### 3.2 ARSENAL (armes et versions, fiche d'arme)

- **Liste à gauche**, groupée par arme : chaque arme définie, puis ses
  **versions** (une ligne par exemplaire : niveau, rareté en couleur, score,
  pièces `2/3`, pastille NOUVEAU, cadenas « NIV. n REQUIS » si niveau trop
  haut). Les armes de base sont en tête, marquées **BASE** (non recyclables).
- **Filtres** (Y / Tab : cycle ; clic) : TOUTES, À FEU, CORPS À CORPS,
  UTILISABLES ; **tri** (X / R) : SCORE, NIVEAU, RARETÉ, NOM.
- **Fiche d'arme à droite** : nom, classe, niveau, rareté, **score** (niveau +
  pièces) ; **statistiques effectives** (`GameWeapon.stats`) en barres avec
  la part apportée par les pièces en couleur ; **emplacements de pièces**
  (1 à 4 selon la rareté) : pièce installée (nom, niveau, modificateurs) ou
  emplacement libre.
- **Installer** : choisir un emplacement libre → liste des pièces **montables**
  (règle `OwnedWeapon.can_mount` : niveau de pièce ≤ arme et ≤ joueur) ; les
  autres sont grisées avec la raison. L'aperçu montre les statistiques avant /
  après.
- **Retirer** : sur une pièce installée, deux appuis (D14) : la pièce est
  **détruite** (§4.9).
- **Recycler** : toute arme de l'arsenal sauf les armes de base, deux appuis,
  ne rapporte rien (§4.11). Une arme choisie comme arme de départ ne peut pas
  l'être (les armes de départ sont des armes de base) : sans conflit.

### 3.3 PIÈCES (onglet des pièces)

- Liste de toutes les pièces non installées : nom (d'après le premier
  modificateur), niveau, modificateurs (bonus en vert, malus en rouge),
  pastille NOUVEAU. Tri : NIVEAU, MODIFICATEUR.
- Fiche de la pièce : **armes compatibles** (versions de l'arsenal qui ont un
  emplacement libre et un niveau suffisant) avec l'aperçu de la statistique
  changée ; INSTALLER SUR… ouvre la fiche de l'arme choisie avec la pièce
  pré-sélectionnée.
- Pas de vente ni de destruction d'une pièce non installée pour l'instant
  (rien ne le demande ; onglet illimité, §4.9).

### 3.4 CONTRATS

- **En haut à gauche, contrats actifs** (3 cases ; case vide « LIBRE ») :
  titre, demande du scientifique, progression par échantillon, récompense
  (XP calculée au niveau actuel, arme ou pièce « au niveau n », rareté ou
  qualité), date de fin s'il est daté (« encore 3 j ») ; bouton **REMETTRE**
  (actif quand tout est là) et **ABANDONNER** (deux appuis, le contrat
  disparaît, rien n'est consommé).
- **Dessous, propositions du scientifique** (5 cases) : même fiche, bouton
  **ACCEPTER** (grisé avec « 3 CONTRATS ACTIFS AU MAXIMUM ») ; mention
  « nouvelles propositions après votre prochaine partie » quand des cases
  sont vides.
- Quand deux contrats actifs demandent la même sorte d'échantillon, la
  progression le signale (« partagé avec : … ») : remettre l'un peut faire
  reculer l'autre.
- **Colonne de droite** : réserve d'échantillons (comme au LABO).
- Remise : écran de récompense (XP gagnée, niveau avant / après, objet
  obtenu, réplique de remerciement) puis l'objet est dans l'ARSENAL ou les
  PIÈCES (pastille NOUVEAU).

### 3.5 ÉCHANGES (catalogue permanent)

- Liste des échanges débloqués (niveau requis atteint) ; ceux d'un niveau
  supérieur sont visibles, grisés, « NIV. n REQUIS » (donne un objectif).
- Chaque ligne : objet précis obtenu (nom, statistiques exactes, rareté ou
  modificateurs ; « au niveau n » = niveau du joueur), coût en échantillons
  avec `possédés / demandés` en couleur, bouton **ÉCHANGER** (deux appuis :
  « CONFIRMER : 5 CROCS + 3 TOUFFES »).
- Filtre « ÉCHANGEABLES MAINTENANT ».
- Colonne de droite : réserve d'échantillons.

### 3.6 DÉPART (armes de départ)

- Trois cases (§4.10) : au moins une, au plus trois armes de base distinctes
  (`PlayerProfile.set_starting_weapons`). Les armes de base disponibles sont
  listées avec leurs statistiques ; A ajoute / retire, une case non choisie
  reste vide au départ.
- Rappel : « Les armes de votre arsenal se construisent pendant la partie, à
  la station de construction, contre de la ferraille. » avec la liste des
  armes que le joueur pourra construire (utilisables à son niveau).

### 3.7 PARTIE (lancer une partie)

- **SOLO** : liste des cartes (cartes du jeu puis cartes perso, comme l'écran
  de sélection actuel `map_screen.gd`) avec aperçu, schéma des vagues
  spéciales et de boss, échantillons qu'on peut y trouver ; **LANCER**.
- **COOP** : HÉBERGER (nom, port), REJOINDRE (adresse IP), puis le **salon**
  dans le même onglet : joueurs (couleur, nom, niveau), carte (choisie par
  l'hôte), DÉMARRER (hôte), QUITTER LE SALON ; message « Retour au salon de :
  … » repris tel quel (`LobbyReturn`).
- Rappel en bas : armes de départ choisies (lien vers DÉPART) et contrats
  actifs (rappel des échantillons visés).
- **DÉFI DE LA SEMAINE** (GAME_CONCEPT §4.18, provisoire, sans maquette :
  même style que les lignes de cartes) : une ligne au-dessus des CARTES DU
  JEU (« S41 · BUNKER K-7 », temps restant ou « réussi ») ; choisie, l'aperçu
  montre la carte, les modificateurs, l'objectif, le meilleur résultat, le
  temps restant et la récompense (REÇUE une fois donnée) ; VOUS PARTEZ AVEC
  montre les armes de base imposées (sans MODIFIER) et CONTRATS ACTIFS
  laisse la place aux RÈGLES DU DÉFI ; bouton LANCER LE DÉFI. En coop, le
  défi est la première ligne de CHANGER DE CARTE (hôte) et s'affiche en tête
  de la carte du salon pour tout le groupe.
- **CARTES PERSONNALISÉES** (décision du 2026-10-11, GAME_CONCEPT §4.20) :
  les cartes de l'éditeur sont **pour le fun**, aucune progression (ni XP,
  ni butin, ni contrat, ni codex, ni défi) ; rangées à part, étiquette POUR
  LE FUN et la règle en une phrase (hub v2, §9.5).

### 3.8 Options et dossier de combat

- **OPTIONS** : l'écran d'options actuel, ouvert par-dessus le hub
  (`show_screen("options")`), plus le réglage TAILLE DES MENUS (D15).
- **DOSSIER DE COMBAT** : l'écran actuel (`career_screen.gd`) ; la partie
  « niveau du profil » y reste en double du hub (rien à retirer).

### 3.9 Hub 3D plus tard (emplacement prévu)

- Chaque onglet est un **panneau indépendant** (`HubPanel`) qui ne connaît que
  le profil et le menu hôte : le hub 2D les range dans des onglets ; le futur
  hub 3D (laboratoire cubique) les ouvrira en **surimpression** quand le
  joueur interagit avec un objet : râtelier → ARSENAL, établi → PIÈCES,
  scientifique → CONTRATS / ÉCHANGES, casier → DÉPART, porte → PARTIE.
- Le fond du hub passe par un seul point (`HubScreen.backdrop`) : remplacer
  `MenuBackdrop` par la scène du labo ne touche pas aux panneaux.

### 3.10 CODEX (bestiaire, GAME_CONCEPT §4.17) ✅

- Huitième onglet, **avant PARTIE** (`HubCodexPanel`, `codex_panel.gd`) :
  une fiche par type d'ennemi en grille de 4 colonnes (défile à 130 %).
- Fiche **connue** : nom, famille et manche d'apparition, description drôle
  (FR / EN, sans nombre exact), éliminations, XP de base (lue dans
  `XpRules`, jamais recopiée), échantillons. Fiche **inconnue** : pointillés
  gris, « ??? » et seulement « Peut apparaître dès la manche n ».
- Données : `assets/data/hub/codex.json` (format « hub_codex », `CodexData`) :
  id = type d'ennemi de `XpRules`, nom, texte, manche, sortes d'échantillons
  (`LootRules.SAMPLES`), `xp_ref` (type de référence pour un ennemi prévu,
  pas encore au barème), `planned`. Fiches actuelles : marcheur, rampant,
  coureur, sprinteur, meute errante, Brancardier, Infirmière hurlante
  (manche 15) ; prévue : Le Chirurgien.
- **Rencontre** (locale, chacun la sienne en coop) : un coup porté à
  l'ennemi, un coup reçu de lui (`Combat.damage_player` avec `source`) ou
  son élimination. Le serveur la note dans le relevé d'XP du joueur
  (`XpRules` « met », sans XP) ; le profil la reçoit **une fois par partie**
  avec l'XP (`MatchXp.apply` → `CodexState.record_ledger`), comme les
  éliminations par type.
- Profil : section facultative `"codex": {"enemies": {type: éliminations},
  "seen": [type…]}` (`CodexState`), sans changement de version : absente
  (profil plus ancien) = codex vide.
- Pastille NOUVEAU : fiche découverte depuis la dernière visite ; l'onglet
  porte leur nombre ; vues à l'affichage de l'onglet, enregistrées en le
  quittant.

## 4. Navigation, tailles, langues

### 4.1 Commandes

| Action | Clavier / souris | Manette |
|---|---|---|
| Onglet précédent / suivant | Page préc. / Page suiv., Q / E (A / E en AZERTY), clic | LB / RB |
| Se déplacer | Flèches, souris | Croix, stick gauche |
| Valider (accepter, installer, choisir) | Entrée, Espace, clic | A (Croix) |
| Retour (fermer une fiche ou une liste ; au niveau des onglets : menu du hub) | Échap, clic droit | B (Rond) |
| Action secondaire (retirer, recycler, abandonner) | Suppr ou R | X (Carré) |
| Filtre / tri | Tab | Y (Triangle) |
| Menu du hub | Échap (au niveau des onglets) | Start |
| Défiler une liste longue | Molette | Stick droit |

- Les touches du hub sont fixes (comme celles des menus aujourd'hui) ;
  `ui_page_up` / `ui_page_down` existent déjà avec LB / RB
  (`Settings._register_inputs`).
- **Focus** : chaque onglet donne le focus à son premier élément utile
  (premier contrat prêt, arme choisie la dernière fois…) ; voisins de focus
  explicites entre liste et fiche, comme l'écran d'options.
- La souris peut tout faire sans clavier ; la manette tout faire sans souris.
- Invites en bas : recalculées sur `Settings.input_device_changed` (noms Xbox
  ou PlayStation par `PadNames`).

### 4.2 Tailles

- Mise en page conçue à **1280 × 720** logiques (mode d'étirement
  `canvas_items` du projet : la même mise en page à toute résolution).
- Texte courant **16 px**, petit texte **13 px minimum**, titres d'onglet
  **20 px**, lignes de liste **40 px** de haut (cible souris et lisibilité à
  la manette sur un téléviseur).
- Réglage TAILLE DES MENUS (D15) : un facteur sur le hub et les menus, même
  technique que `EditorUi` (valeurs écrites « à 100 % », polices rendues à la
  taille finale, jamais une image agrandie) ; à 130 % les listes défilent,
  rien ne sort de l'écran.

### 4.3 Langues

- Tout texte en **français et en anglais** (`Lang.t(fr, en)` pour l'interface ;
  champs `{"fr", "en"}` dans les fichiers de données). Une entrée de données
  sans l'une des deux langues est refusée au chargement (§5.5).
- Les nombres suivent la langue (espace fine en français : « 2 270 XP »).
- Les noms des échantillons viennent de `LootRules.SAMPLES` (FR / EN).

### 4.4 Style visuel

- **Pas cubique, mais en harmonie** (§4.19) : panneaux à bords droits,
  **contour noir de 2 px** (comme le rendu du jeu), coins « en escalier » d'un
  pixel, ombre portée pleine décalée (pas de flou), icônes en **pixel art**
  (un pixel = un cube : armes, échantillons, portrait).
- Palette tirée de `DECOR_PALETTE` (`tools/blender/voxel/voxel_lib.py`) :
  fond `case_black` / `metal_dark`, panneaux `case_grey`, texte `paper` /
  `plaster`, accent **`hazard_yellow`** (focus, sélection), **`medic_red`**
  (titres, danger, comme le sang des menus actuels), `tile_green` /
  `enamel_green` (le labo, bonus), `rust` (bordures secondaires).
- Couleurs de rareté : celles du jeu (`GameWeapon.RARITY_COLORS`).
- Polices : celles des menus (`UiStyle` : Bahnschrift, Impact pour les grands
  titres — l'ancien pochoir « Stencil » est retiré —, Consolas pour les nombres).

## 5. Modèle de données des contrats

### 5.1 Fichier `assets/data/hub/contracts.json`

```json
{
  "format": "hub_contracts",
  "version": 1,
  "rules": {
    "offers": 5,
    "active_max": 3,
    "replace_per_match": 1,
    "min_rounds_for_rotation": 1,
    "xp_level_factor": 0.02
  },
  "contracts": [
    {
      "id": "dog_fangs_small",
      "title": {"fr": "Dents de lait", "en": "Milk Teeth"},
      "text": {"fr": "Réplique du scientifique…", "en": "Scientist line…"},
      "thanks": {"fr": "Réplique à la remise…", "en": "Line on delivery…"},
      "samples": {"dog_fang": 4},
      "xp": 1200,
      "reward": {"kind": "part", "quality": "fine"},
      "min_level": 1,
      "max_level": 50,
      "starts": "2026-11-01",
      "ends": "2026-11-30",
      "repeatable": true,
      "weight": 1.0,
      "after": ["first_sample"],
      "tutorial": false
    }
  ]
}
```

| Champ | Obligatoire | Sens |
|---|---|---|
| `id` | oui | identifiant unique (`[a-z0-9_]`, 64 caractères au plus) ; ne jamais le changer une fois publié (le profil le garde) |
| `title` | oui | titre court `{fr, en}` |
| `text` | oui | demande du scientifique `{fr, en}` (2 ou 3 phrases, ton du personnage) |
| `thanks` | non | réplique à la remise `{fr, en}` (sinon une réplique générique) |
| `samples` | oui | échantillons demandés `{sorte: quantité}` (sortes de `LootRules.SAMPLES`, quantités 1 à 999) |
| `xp` | oui | XP de base (au niveau 1) ; donnée : `xp × (1 + xp_level_factor × (niveau − 1))`, arrondie à 10 (D9) |
| `reward` | oui | `{"kind": "weapon", "weapon": "any" ou identifiant d'arme, "rarity": "common"…"unique"}` ou `{"kind": "part", "quality": "standard" / "fine" / "superior"}` ou `{"kind": "none"}` |
| `min_level`, `max_level` | non | niveaux du joueur pour qu'il soit proposé (défaut 1 et 50) |
| `starts`, `ends` | non | dates UTC `AAAA-MM-JJ` : proposé à partir de `starts` à 0 h, **supprimé** après le dernier jour `ends` (24 h UTC) ; sans `ends` : contrat permanent |
| `repeatable` | non | peut revenir après avoir été rempli (défaut vrai) |
| `weight` | non | poids du tirage (défaut 1 ; 0 : jamais tiré, sauf tuto) |
| `after` | non | contrats à avoir remplis au moins une fois avant (chaîne d'histoire) |
| `tutorial` | non | proposé en premier tant qu'il n'est pas rempli, jamais tiré ensuite |

**Récompense** (D11), toujours au **niveau du joueur au moment de la
remise** :

- arme : `"any"` = tirage parmi les armes du butin (`LootRules`, hors armes de
  base, niveau de base ≤ niveau du joueur), sinon l'arme nommée ; rareté
  fixée ; aucune pièce ;
- pièce : modificateurs tirés selon la **qualité** (provisoire) :

  | Qualité | FR / EN | Modificateurs |
  |---|---|---|
  | `standard` | ordinaire / standard | tirage du butin (`LootRules.roll_part`), niveau fixé au niveau du joueur |
  | `fine` | soignée / fine | deux modificateurs, tous deux en bonus, 10 à 25 % |
  | `superior` | d'exception / superior | deux modificateurs en bonus, 18 à 25 % |

### 5.2 Règles d'un contrat

- **Accepter** : proposition → actif, si moins de `active_max` actifs. La case
  de proposition reste vide jusqu'à la prochaine rotation.
- **Progression** : calculée, jamais enregistrée : pour chaque sorte,
  `min(possédés, demandés)`. Les échantillons restent en commun (§4.2).
- **Remettre** : actif et `PlayerProfile.has_samples(samples)` → consomme
  **exactement** les quantités demandées (`consume_samples`, tout ou rien),
  ajoute l'XP (`add_xp`), crée l'objet (arsenal ou onglet des pièces), compte
  la remise (`done[id] += 1`), libère la case. Une seule écriture du profil.
- **Abandonner** : actif → supprimé (ni proposition, ni pénalité, rien de
  consommé). Il pourra revenir par le tirage s'il est répétable.
- **Expiration** : à l'ouverture du hub et à chaque rotation, tout contrat
  (proposé ou actif) dont la date `ends` est passée est supprimé ; le LABO le
  signale une fois (« Contrat expiré : … »).
- **Contrat disparu du fichier** (renommé, supprimé par l'auteur) : retiré du
  profil au chargement avec un avertissement dans le journal.

### 5.3 Rotation (D7)

Fonction pure `ContractRules.rotate(état, catalogue, niveau, aujourd'hui,
après_partie)` :

1. **Purge** : propositions et actifs inconnus ou expirés retirés.
2. **Après une partie** (au moins `min_rounds_for_rotation` manche survécue,
   quelle que soit l'issue) : la ou les `replace_per_match` **plus anciennes
   propositions** (rotation d'arrivée la plus petite) sont retirées.
3. **Remplissage** jusqu'à `offers` propositions :
   - d'abord un contrat `tutorial` éligible jamais rempli ;
   - puis tirage **pondéré sans remise** parmi les contrats **éligibles** :
     niveau dans `[min_level, max_level]`, date dans `[starts, ends]`,
     contrats de `after` remplis, pas déjà proposé ni actif (**aucun
     doublon**), pas `repeatable: false` déjà rempli, et pas une des
     propositions retirées à l'étape 2 (elles reviendront plus tard) ;
   - s'il n'y a pas assez de contrats éligibles, le tableau reste incomplet.
4. Compteur `rotation` + 1. Le tirage utilise un générateur **initialisé par
   `seed + rotation`** (graine tirée à la création du profil) : recharger le
   jeu ne change pas le tirage.

Appels : à l'ouverture du hub (`après_partie` faux : purge seulement, et
remplissage la toute première fois — voir lot A) et à la fin de chaque partie, une fois, en même temps que
`MatchXp.apply` (`après_partie` vrai). Un joueur qui quitte avant la fin de la
première manche ne fait pas tourner le tableau (pas de « relance » gratuite).

### 5.4 Sauvegarde dans le profil

`ProfileStore` passe en **version 2** (migration : profil v1 → sections
vides, tableau rempli à la première ouverture du hub) :

```json
"contracts": {
  "seed": 918273,
  "rotation": 12,
  "offers": [{"id": "dog_fur_coat", "since": 11}, …],
  "active": [{"id": "dog_fangs_small", "accepted": 9}, …],
  "done": {"first_sample": 1, "dog_fangs_small": 2},
  "expired_unseen": ["lab_emergency"]
},
"exchanges": {"done": {"fang_trim": 3}},
"seen": {"weapons": ["w12"], "parts": ["p40"]}
```

- `done` sert aux conditions `after`, aux contrats non répétables et au
  dossier de combat (nombre de contrats remplis).
- `seen` : exemplaires déjà vus au hub (pastilles NOUVEAU).
- `expired_unseen` : contrats **actifs** supprimés par leur date de fin, pas
  encore signalés au LABO (`ContractState.take_expired`, puis enregistrer) ;
  une proposition jamais acceptée disparaît sans message.
- Relecture tolérante comme le reste du profil (entrées illisibles écartées
  et comptées, copie `.invalid-<date>` gardée).

### 5.5 Chargement et validation des fichiers

`HubData` (pur, chargé une fois) lit les deux fichiers et **écarte chaque
entrée invalide avec un avertissement** dans le journal : identifiant
manquant ou en double, texte sans `fr` ou `en`, sorte d'échantillon inconnue,
quantité hors 1 à 999, arme inconnue ou arme de base, rareté ou qualité
inconnue, date illisible, `after` vers un contrat inconnu, `min_level >
max_level`. Un test vérifie que les fichiers livrés se chargent **sans aucun
avertissement**. Les fichiers sont ajoutés aux exports (`include_filter` :
`assets/data/*`).

### 5.6 Coop (D12)

- Rien ne passe par le réseau : chaque joueur a ses contrats, son tableau et
  son catalogue. L'hôte ignore tout des contrats.
- Pendant la partie, chaque client surveille ses contrats actifs
  (`ContractWatch`) à chaque échantillon reçu (`LootSystem._cl_loot`) :
  quand `profil + partie` couvre un contrat, message unique « CONTRAT « … » :
  OBJECTIF ATTEINT — évacuez pour garder vos échantillons ». La partie
  continue (§4.2).
- 💡 Plus tard : voir au salon les échantillons que visent les coéquipiers.

### 5.7 Contrats d'histoire et contrats temporaires (hub v2, 💡 provisoire)

GAME_CONCEPT §4.2 quater ; écran LABO › CONTRATS (`docs/hub_v2/Contrats.dc.html`).

**Histoire** — fichier `assets/data/hub/story.json` (`StoryData`, validé
comme les contrats : chaque entrée invalide est écartée avec un
avertissement ; `tests/test_story.gd` vérifie le fichier livré) :

```json
{"format": "hub_story", "version": 1, "rules": {"xp_level_factor": 0.02},
 "chapters": [{"id": "ch2_night_shift", "title": {"fr": "Le service de nuit", "en": "The Night Shift"},
   "steps": [{"id": "ch2_straps", "short": {"fr": "Sangles", "en": "Straps"},
     "title": {"fr": "Sangles en série", "en": "Strapped In Series"},
     "text": {…}, "lab": {…}, "ready": {…}, "thanks": {…},
     "samples": {"brancard_strap": 3}, "xp": 1650,
     "reward": {"kind": "weapon", "weapon": "any", "rarity": "rare"}, "min_level": 6}]}]}
```

| Champ d'une étape | Obligatoire | Sens |
|---|---|---|
| `id` | oui | unique dans tout le fichier, jamais changé une fois publié |
| `short` | oui | libellé de la frise du chapitre (14 caractères au plus) |
| `title`, `text` | oui | titre et demande de Dr Brown `{fr, en}` |
| `lab`, `ready`, `thanks` | non | répliques de Dr Brown : au LABO pendant l'étape, au LABO quand elle est prête, à la remise |
| `samples`, `xp`, `reward` | oui | comme un contrat (§5.1) ; récompense au niveau du joueur |
| `min_level` | non | niveau du joueur pour la remettre (défaut 1) |

Chapitre : `id`, `title`, `steps` (1 à 8 étapes). Règles (`StoryRules`) :
l'étape en cours est la **première du fichier non remise** (le profil ne
garde que les étapes remises : `"story": {"done": [...]}`, `StoryState`,
**profil version 4** ; un profil v1 à v3 se lit sans perte, histoire au
début) ; remise = niveau atteint et échantillons en réserve -> consommation
exacte, objet (créé AVANT l'XP), XP, étape notée, étape suivante débloquée ;
pas d'acceptation, pas d'abandon, pas d'expiration. L'objet est tiré avec
une graine du profil : l'**aperçu** montré dans la tuile (arme exacte,
statistiques) est l'objet remis (`StoryRules.preview_item`,
`ContractRules.preview_item` pour les contrats temporaires).

**Contrats temporaires** — le tableau §5.3 ; règle `lifetime_days` de
`contracts.json` (livrée : 7 ; défaut 0 = sans limite propre) : une
proposition reçoit à son arrivée un dernier jour `until` (aujourd'hui +
lifetime_days − 1), gardé quand elle est acceptée ; la fin effective est la
plus proche de `until` et de `ends` (`ContractRules.deadline`) ; passée,
la purge la retire (un contrat actif est signalé au LABO). Entrées sans
`until` (profils plus anciens) : pas de limite propre.

## 6. Modèle de données du catalogue d'échanges

Fichier `assets/data/hub/exchanges.json` :

```json
{
  "format": "hub_exchanges",
  "version": 1,
  "exchanges": [
    {
      "id": "fang_trim",
      "title": {"fr": "Garniture à crocs", "en": "Fang Trim"},
      "text": {"fr": "…", "en": "…"},
      "samples": {"dog_fang": 5, "dog_fur": 3},
      "reward": {"kind": "part", "mods": {"damage": 0.15}},
      "min_level": 1,
      "starts": null,
      "ends": null,
      "limit": 0
    }
  ]
}
```

| Champ | Obligatoire | Sens |
|---|---|---|
| `id`, `title`, `samples`, `min_level` | comme les contrats | |
| `text` | non | description courte `{fr, en}` |
| `reward` | oui | `{"kind": "part", "mods": {stat: valeur}}` (pièce **précise** : modificateurs exacts, noms de `GameWeapon.MODS`, ±0,01 à 0,5) ou `{"kind": "weapon", "weapon": identifiant, "rarity": …}` (arme précise) ; toujours au niveau du joueur |
| `starts`, `ends` | non | échange temporaire (sinon permanent) |
| `limit` | non | nombre d'échanges par profil (0 = illimité, défaut) |

Règle : `ExchangeRules.trade(profil, id)` → niveau suffisant, dans les dates,
limite non atteinte, `has_samples` → consomme exactement, crée l'objet, compte
`exchanges.done[id]`. Pas d'XP (D10).

## 7. Contenu d'exemple (provisoire)

Échantillons des **chiens** (ceux du Brancardier : §7.2 bis) — croc (`dog_fang`), touffe de poils
(`dog_fur`), collier (`dog_collar`), chacun **20 %** par chien tué et par
joueur (§4.7).

**Partie de référence** (XP_RULES §4) : évacuation à la manche 10 en solo,
2 vagues de chiens (6 + 6 chiens), **≈ 2,4 échantillons de chaque sorte**,
≈ 15 min, ≈ 2 270 XP. Les parties nécessaires ci-dessous sont simulées
(tirages à 20 %, en partant de zéro, moyenne de 4 000 essais).

**Règle d'équilibre** (provisoire) :

- **XP** ≈ **25 %** de l'XP des parties de référence nécessaires
  (≈ 570 XP par partie), ramenée au niveau 1 par le facteur D9 au niveau
  typique du contrat ; +25 % pour un contrat daté ;
- **rareté de l'arme / qualité de la pièce** selon les parties nécessaires :
  moins de 1,5 → commune / ordinaire ; 1,5 à 3 → rare / soignée ; 3 à 5 →
  épique / d'exception ; plus de 5 → légendaire. **Unique** : jamais par un
  contrat ordinaire (reste la chance pure du butin), réservée à de rares
  contrats datés.

### 7.1 Contrats (8)

| Id | Titre FR / EN | Demande | Parties (solo) | XP de base | Récompense | Niveau | Autre |
|---|---|---|---|---|---|---|---|
| `first_sample` | Premier prélèvement / First Sample | 1 croc | 1,1 | 150 | arme commune | 1+ | tuto, non répétable |
| `dog_fangs_small` | Dents de lait / Milk Teeth | 4 crocs | 2,1 | 1 200 | pièce soignée | 1+ | |
| `dog_fur_coat` | Échantillons de pelage / Coat Samples | 6 touffes | 2,9 | 1 650 | arme rare | 2+ | |
| `dog_collars` | Colliers de la meute / Pack Collars | 5 colliers | 2,6 | 1 450 | pièce soignée | 2+ | |
| `pack_analysis` | Analyse complète / Full Analysis | 3 crocs, 3 touffes, 3 colliers | 2,2 | 1 250 | arme rare | 3+ | après `first_sample` |
| `jaw_series` | Mâchoires en série / Jaw Series | 10 crocs | 4,4 | 2 300 | arme épique | 5+ | |
| `great_harvest` | La grande collecte / The Great Harvest | 12 crocs, 12 touffes, 12 colliers | 6,6 | 3 300 | arme légendaire | 10+ | après `pack_analysis` |
| `lab_emergency` | Urgence au labo / Lab Emergency | 8 colliers | 3,8 | 2 700 | pièce d'exception | 3+ | **daté** (exemple : 1er au 30 novembre 2026), non répétable |

- À la manche 15 (3 vagues, 20 chiens), les mêmes contrats demandent environ
  1,5 fois moins de parties ; c'est voulu : aller plus loin rapporte plus.
- Effet sur la progression : un contrat toutes les 2 à 3 parties ajoute
  ≈ 20 à 25 % d'XP ; le niveau 50 passerait de ≈ 123 h à ≈ 100 h. À
  re-mesurer quand les contrats seront en jeu (`XpCalibration` pourra
  ajouter les contrats) ; baisser `xp` ou le pourcentage si besoin.

### 7.2 Échanges (5)

| Id | Titre FR / EN | Coût | Parties (solo) | Objet (au niveau du joueur) | Niveau |
|---|---|---|---|---|---|
| `fang_trim` | Garniture à crocs / Fang Trim | 5 crocs + 3 touffes | 2,7 | pièce : dégâts +15 % | 1+ |
| `fur_padding` | Bourre de poils / Fur Padding | 6 touffes | 3,0 | pièce : recul +20 % (moins de recul) | 1+ |
| `collar_strap` | Bride de collier / Collar Strap | 4 colliers + 2 touffes | 2,2 | pièce : chargeur +20 % | 2+ |
| `sharpened_fangs` | Crocs affûtés / Sharpened Fangs | 8 crocs + 4 colliers | 3,8 | pièce : dégâts +12 %, cadence +10 % | 5+ |
| `pack_weapon` | Arme de la meute / Pack Weapon | 10 crocs + 10 touffes + 10 colliers | 5,6 | arme épique précise (mitraillette MOUCHERON, identifiant `mp5k`) | 8+ |

- Un échange coûte plus de parties qu'un contrat à récompense comparable,
  sans XP : c'est le prix de la certitude.
- La « garniture » du concept (§4.2 ter) est une pièce de dégâts : les
  familles d'emplacements (canon, garniture…) ne sont pas encore dans le jeu
  (💡 §4.9) ; le nom suffit pour l'instant.

### 7.2 bis Brancardier : contrats (3) et échanges (2)

Échantillons du Brancardier (GAME_CONCEPT §4.4) : **sangle de cuir**
(`brancard_strap`) et **bracelet d'identification** (`brancard_bracelet`),
20 % chacun sur **chaque zombie de sa vague** (le Brancardier et ses
5 zombies d'escorte par joueur) : à un joueur, 6 tirages par vague, comme la
première meute. Icônes du hub : `strap` (sangle à boucle), `bracelet`
(bande blanche à étiquette bleue) ; groupe « BRANCARDIER » de la réserve.

**Rotation** (format de carte 21) : sur une carte aux deux types, la partie
de référence (évacuation à la manche 10) a **une** vague de chaque type
(meute à la 5, Brancardier à la 10) : ≈ 1,2 échantillon de chaque sorte de
chaque type par partie. Les contrats des chiens (§7.1, calculés avec deux
meutes) demandent donc ≈ 2 fois plus de parties qu'annoncé tant que la
carte fait tourner deux types (à revoir avec l'auteur : GAME_CONCEPT §7).

Parties estimées (≈ 1,2 de chaque sorte par partie de référence, comme
§7.1, non simulées) ; mêmes règles d'équilibre que les chiens ; niveau
minimal 5 et plus (le Brancardier arrive à la manche 10, quand le joueur
s'évacue vers la manche 10, XP_RULES §4) :

| Id | Titre FR / EN | Demande | Parties (solo) | XP de base | Récompense | Niveau | Autre |
|---|---|---|---|---|---|---|---|
| `orderly_straps` | Sangles de contention / Restraint Straps | 3 sangles | ≈ 2,9 | 1 650 | arme rare | 5+ | |
| `patient_records` | Dossiers des patients / Patient Records | 4 bracelets | ≈ 3,7 | 2 100 | pièce d'exception | 5+ | |
| `field_stretcher` | Brancard de campagne / Field Stretcher | 3 sangles, 3 bracelets | ≈ 3,4 | 1 950 | arme épique | 6+ | après `orderly_straps` |

| Id | Titre FR / EN | Coût | Parties (solo) | Objet (au niveau du joueur) | Niveau |
|---|---|---|---|---|---|
| `leather_sling` | Bretelle de cuir / Leather Sling | 4 sangles | ≈ 3,7 | pièce : rechargement +20 % | 5+ |
| `tagged_sights` | Mire étiquetée / Tagged Sights | 3 bracelets + 2 sangles | ≈ 3,2 | pièce : précision +20 %, dégâts +5 % | 6+ |

### 7.2 quater Le Chirurgien : contrats (3) et échanges (2)

Échantillons du Chirurgien (premier boss, GAME_CONCEPT §4.4) : **scalpel**
(`surgeon_scalpel`) et **cœur mutant** (`surgeon_heart`), 20 % chacun sur
chaque zombie de sa vague (6 d'escorte par joueur, 2 patients par joueur à
chacune de ses deux opérations) et **à coup sûr** sur le boss : seul, ≈ 3 de
chaque par vague de boss. Icônes du hub : `scalpel` (lame et manche en
diagonale), `heart` (cœur rouge) ; groupe « LE CHIRURGIEN (BOSS) » de la
réserve. Fiche du codex jouable (manche 15, XP de son barème).

Il arrive à la manche 15 (défaut), quand le joueur s'évacue vers la manche
15, à partir du niveau 10 (XP_RULES §4) : niveau minimal 10 et plus. Partie
de référence : évacuation à la manche 15 (6 621 XP) ; XP d'un contrat ≈ 25 %
de l'XP des parties nécessaires (comme §7.1) :

| Id | Titre FR / EN | Demande | Parties (solo) | XP de base | Récompense | Niveau | Autre |
|---|---|---|---|---|---|---|---|
| `surgical_instruments` | Instruments de chirurgie / Surgical Instruments | 6 scalpels | ≈ 2 | 3 300 | arme rare | 10+ | |
| `mutant_hearts` | Cœurs mutants / Mutant Hearts | 10 cœurs | ≈ 3,3 | 5 500 | pièce d'exception | 10+ | |
| `full_autopsy` | Autopsie complète / Full Autopsy | 12 scalpels, 12 cœurs | ≈ 4 | 6 600 | arme épique | 12+ | après `surgical_instruments` |

| Id | Titre FR / EN | Coût | Parties (solo) | Objet (au niveau du joueur) | Niveau |
|---|---|---|---|---|---|
| `scalpel_edge` | Fil du scalpel / Scalpel Edge | 8 scalpels | ≈ 2,7 | pièce : dégâts +22 % | 10+ |
| `pacemaker` | Stimulateur cardiaque / Pacemaker | 6 cœurs + 4 scalpels | ≈ 2 | pièce : cadence +20 %, rechargement +10 % | 11+ |

### 7.2 ter Infirmière hurlante : contrats (3) et échanges (2)

Échantillons de l'Infirmière hurlante (GAME_CONCEPT §4.4) : **cordes
vocales** (`nurse_vocal_cords`), **seringue cassée** (`nurse_syringe`) et
**badge nominatif** (`nurse_badge`), 20 % chacun sur **chaque zombie de sa
vague** (l'Infirmière et ses 6 zombies d'escorte par joueur) : à un joueur,
7 tirages par vague, ≈ 1,4 de chaque sorte. Icônes du hub : `cords` (cordes
vocales dans la gorge), `syringe` (seringue au liquide vert), `badge` (carte
blanche à bande bleue et photo) ; groupe « INFIRMIÈRE HURLANTE » de la
réserve.

**Rotation** (trois types) : l'Infirmière arrive à la manche 15 (3e vague
spéciale) ; la partie de référence des niveaux 10 à 24 (évacuation à la
manche 15, XP_RULES §4) a **une** vague de l'Infirmière : ≈ 1,4 échantillon
de chaque sorte par partie. Niveau minimal **10** et plus (un joueur plus
bas s'évacue avant elle). Parties estimées (non simulées) ; XP ≈ 25 % de
l'XP des parties nécessaires (≈ 5 200 XP par partie de référence, XP_RULES §4).
⚠️ Depuis le Chirurgien (boss à la manche 15, §7.2 quater), la 15 est une
vague de boss : l'Infirmière arrive à la **manche 20** (puis 40) ; la partie
de référence des niveaux 10 à 24 (évacuation à la 15) ne la croise plus, ses
contrats demandent donc des parties plus longues (évacuation à la 20) : à
recalculer avec l'auteur (estimations ci-dessous d'avant le boss) :

| Id | Titre FR / EN | Demande | Parties (solo) | XP de base | Récompense | Niveau | Autre |
|---|---|---|---|---|---|---|---|
| `night_shift` | Garde de nuit / Night Shift | 3 cordes vocales | ≈ 2,1 | 2 700 | arme rare | 10+ | |
| `used_syringes` | Seringues usagées / Used Syringes | 3 seringues | ≈ 2,1 | 2 700 | pièce d'exception | 10+ | |
| `staff_register` | Registre du personnel / Staff Register | 4 badges, 3 cordes vocales | ≈ 3,2 | 4 100 | arme épique | 11+ | après `night_shift` |

| Id | Titre FR / EN | Coût | Parties (solo) | Objet (au niveau du joueur) | Niveau |
|---|---|---|---|---|---|
| `taut_cords` | Cordes tendues / Taut Cords | 4 cordes vocales | ≈ 2,9 | pièce : recul +20 % | 10+ |
| `night_kit` | Trousse de garde / Night Kit | 4 seringues + 2 badges | ≈ 2,9 | pièce : rechargement +12 %, cadence +8 % | 11+ |

### 7.3 Coop

En coop, **chaque joueur tire les échantillons de chaque chien** (§4.7) et il
y a plus de chiens : à 4 joueurs, un joueur reçoit ≈ 4 fois plus
d'échantillons par partie qu'en solo, donc remplit ses contrats ≈ 4 fois plus
vite (et le bonus d'XP des contrats avec). **Question ouverte** (GAME_CONCEPT
§7) : réduire la chance par joueur en coop, ou l'accepter comme bonus de la
coop. Rien n'est changé au butin dans ce plan.

## 8. Lots d'implémentation

Ordre proposé : **A et B en parallèle**, puis **C et D en parallèle**, puis
**E**. F est pour plus tard.

### Lot A — Données et règles des contrats et du catalogue (sans interface) ✅

**Fait** (branche `hub-a`). Choix faits pendant l'implémentation
(provisoires) :

- **Remplissage du tableau** : seulement après une partie d'au moins
  `min_rounds_for_rotation` manche survécue, et la toute première fois
  (profil neuf ou venu de la v1 : `rotation == 0`). L'ouverture du hub ne fait
  ensuite que la purge (`ContractRules.rotate(…, false)`) : une proposition
  acceptée laisse bien sa case vide jusqu'à la partie suivante.
- **Manches survécues** (`MatchContracts.rounds_survived`) : le plus grand du
  relevé d'XP du joueur (`rounds`) et de la manche atteinte − 1 (un joueur
  mort dont l'équipe a tenu compte aussi). Quitter une partie en cours
  (`Game.keep_match_xp`) fait tourner le tableau si une manche a été
  survécue, comme une partie finie ; une seule rotation par partie.
- **Niveau de la récompense** : celui du joueur **avant** l'XP du contrat
  (celui affiché sur la fiche au moment de la remise).
- **Expiration signalée** : contrats actifs seulement (`expired_unseen`, voir
  §5.4).
- **Nouveautés (`seen`)** : à la migration v1 → v2, tout l'existant est marqué
  vu ; les exemplaires recyclés ou détruits sont oubliés à l'enregistrement.
- **Pièce « fine » / « superior »** : deux modificateurs distincts de
  `LootRules.PART_MODS`, identifiant `part_<premier modificateur>` (comme le
  butin) ; pièce d'un échange : `part_<premier modificateur du fichier>`.
- **Arme nommée** d'un niveau de base supérieur au joueur : créée au niveau
  de base (gardée pour plus tard, comme le butin).
- API pour les lots D et E : `HubData.default()`, `HubData.today()`,
  `ContractRules.rotate / accept / abandon / deliver / progress / covered /
  shared_with / days_left / xp_for / refusal_text / goals_met /
  goal_message`, `ExchangeRules.listed / refusal / trade / count /
  refusal_text`, `HubRewards.describe`, `PlayerProfile.is_new_weapon /
  is_new_part / mark_weapon_seen / mark_part_seen`,
  `ContractState.take_expired`. Les fonctions modifient le profil en
  mémoire : l'écran enregistre ensuite une fois (`ProfileStore.save_profile`).

- Fichiers : `assets/data/hub/contracts.json`, `exchanges.json` (déjà écrits,
  §7) ; `scripts/game/hub/hub_data.gd` (`HubData` : chargement, validation
  §5.5) ; `contract_rules.gd` (`ContractRules` : éligibilité, rotation,
  accepter, abandonner, remettre, expiration, progression) ;
  `exchange_rules.gd` (`ExchangeRules`) ; `hub_rewards.gd` (`HubRewards` :
  arme au niveau du joueur, pièce par qualité, XP D9) ;
  `scripts/game/profile/contract_state.gd` (état sérialisable du profil,
  §5.4) ; `PlayerProfile` (sections `contracts`, `exchanges`, `seen`) ;
  `ProfileStore` version 2 et migration ; rotation à la fin de la partie
  (`MatchContracts.after_match`, appelé à côté de `MatchXp.apply`) ;
  `export_presets.cfg` (`assets/data/*`).
- Tests : `tests/test_hub_data.gd` (fichiers livrés sans avertissement,
  chaque refus de §5.5), `tests/test_contracts.gd` (rotation sans doublon,
  graine stable, tuto en premier, `after`, non répétable, expiration des
  proposés et des actifs, remplacement de la plus ancienne, partie trop
  courte, consommation exacte 200 − 50 = 150, refus sans les échantillons,
  3 actifs au plus, XP D9, récompense au niveau du joueur), 
  `tests/test_exchanges.gd`, `tests/test_profile.gd` (v1 → v2, aller-retour).
- Fini quand : tous les tests passent ; un profil v1 existant se charge sans
  perte ; ARCHITECTURE « Profil du joueur » décrit les nouvelles classes.

### Lot B — Cadre du hub et navigation

- Fichiers : `scripts/ui/hub/hub_screen.gd` (`HubScreen`, `MenuScreen` à
  onglets, entrée `MainMenu.SCREENS.hub`), `hub_panel.gd` (base des
  panneaux), `hub_style.gd` (palette §4.4, panneaux à contour noir, `px()` /
  `fs()` pour la taille), `hub_tab_bar.gd`, `hub_prompts.gd` (barre
  d'invites), `hub_menu.gd` (Échap / Start), panneau `lab_panel.gd`
  (LABO) ; `main_screen.gd` (JOUER → hub) ; `Settings.menu_ui_scale` et sa
  ligne d'options.
- Tests : `tests/test_hub_screen.gd` (onglets LB / RB, focus initial, retour
  B / Échap, menu du hub, invites clavier ↔ manette, taille 80 / 130 % sans
  débordement à 1280 × 720) ; scénario autotest `hub_nav` (captures pendant le
  développement seulement, retirées ensuite).
- Fini quand : on entre au hub par JOUER, on parcourt les 7 onglets (vides
  sauf LABO) au clavier, à la souris et à la manette ; rendu conforme à la
  maquette (écran 1).
- **Fait** (branche `hub-b`). Choix pris pendant le lot (provisoires) :
  - onglets sans panneau : panneau « À VENIR » (ce que l'onglet contiendra,
    RETOUR AU LABO) ; **PARTIE provisoire** jusqu'au lot E : SOLO (écran de
    sélection de carte actuel) et COOP (écran MULTIJOUEUR actuel, puis
    héberger / rejoindre / salon) ; Échap depuis ces écrans revient au hub,
    même onglet. La fin d'une partie revient encore au menu titre (solo) ou
    au salon (coop) : le retour au hub est le travail du lot E ;
  - le menu du hub n'a pas de maquette : voile, panneau à en-tête rouge,
    boutons de la maquette ;
  - sous le hub, le menu titre masque son post-traitement (bombé, vignette,
    grain, parasites), sa surimpression de caméra et son voile : sinon les
    tailles et les couleurs de la maquette sont déformées ; le fond 3D
    reste visible à 7 % sous le fond quadrillé ;
  - nombres : espace insécable ordinaire (l'espace fine manque aux polices
    des menus) ;
  - TAILLE DES MENUS : ne touche que le hub (les anciens écrans de menu,
    positionnés au pixel près, restent à 100 % ; ils seront remplacés par
    les panneaux) ; le hub se reconstruit au changement ;
  - LABO : contrats lus par `HubContractsView` (section `contracts` du
    profil, lot A ; titres dans `contracts.json`) ; tant que le lot A n'est
    pas fusionné, « Les contrats du scientifique arrivent bientôt » ;
    « Contrats remplis » : « – » ; pastille de l'onglet CONTRATS = contrats
    prêts. Une sorte d'échantillon est « connue » dès qu'un échantillon de
    son groupe est en réserve ou demandé ; deux lignes « ??? » annoncent les
    ennemis à venir. DERNIÈRE PARTIE : `Router.last_match` (depuis le
    lancement du jeu, non enregistré) ; « 1 nouvelle proposition » de la
    maquette viendra avec le lot D.

### Lot C — ARSENAL, PIÈCES, DÉPART (dépend de B)

- Fichiers : `scripts/ui/hub/arsenal_panel.gd`, `weapon_sheet.gd` (fiche),
  `part_picker.gd`, `parts_panel.gd`, `loadout_panel.gd` ; utilise les
  règles existantes (`OwnedWeapon.can_mount`, `PlayerProfile.mount_part`,
  `unmount_part`, `remove_weapon`, `set_starting_weapons`, `GameWeapon.stats`).
- Tests : `tests/test_hub_arsenal.gd` (filtres, tri, montage refusé avec
  raison, retrait = pièce détruite, recyclage refusé sur arme de base, deux
  appuis, 1 à 3 armes de départ, pastilles NOUVEAU).
- Fini quand : écrans 2, 3 et 6 de la maquette reproduits ; le profil
  enregistré reflète chaque action.
- **Fait** (branche `hub-c`, écrans 2, 3, 4 et 8 de la maquette). Fichiers en
  plus : `hub_gear.gd` (`HubGear` : filtres, tris, versions, noms et textes
  des pièces, statistiques de la fiche, raison d'un refus de montage, pur),
  `hub_pick_row.gd` (ligne choisissable), `hub_slot.gd` (emplacement),
  `hub_chip.gd` (puces et barre de filtres) ; scénario `hub_gear` (@rendu,
  captures pendant le développement). Choix pris pendant le lot
  (provisoires) :
  - **noms des armes** : les noms originaux du jeu (`HubGear.weapon_name`
    -> `WeaponDB.display_name` : MOUCHERON, MÉTRONOME…, docs/WEAPONS.md),
    pas les noms fictifs de la maquette (FRELON…) ni les identifiants
    internes (`mp5k`, gardés dans le profil et `assets/data/hub/*.json`) ;
    famille (`HubGear.CLASS_NAMES`, mots de `WeaponDB.FAMILIES`) et icône
    par famille (`HubGear.CLASS_ART`) ; armes de base : la PÉTOIRE et la
    **BATTE** de baseball (§4.10) ; le couteau n'est plus une arme de base
    (attaque de mêlée séparée en partie) : un profil qui partait avec lui
    part avec la batte (`BaseWeapons.migrate`) ;
  - **nom d'une pièce** d'après son modificateur principal (celui de son
    identifiant `part_<modificateur>`, sinon le plus grand bonus) : dégâts
    Renfort, cadence Ressort, rechargement Guide, recul Amortisseur,
    précision Mire, chargeur Rallonge, réserve Cartouchière (les noms
    d'échange de la maquette, « Garniture à crocs », « Bride de collier »,
    ne sont pas gardés par le profil) ;
  - **statistiques de la fiche** : barres comparées à des valeurs fixes
    (dégâts 300, cadence 1 200 /min, chargeur 100, réserve 500 ;
    rechargement vide à 5 s, recul à 6° par coup) ; précision affichée
    0 à 100 = 100 − 12 × dispersion à la hanche ; recul en mots (faible < 1°,
    moyen < 2,5°, fort) — dans l'aperçu d'une pièce, la valeur en degrés
    quand le mot ne change pas ; écart des pièces écrit pour dégâts,
    précision, chargeur, réserve ; arme de corps à corps : dégâts, coups par
    seconde, énergie par coup ;
  - **retirer** : Entrée / A sur une pièce installée (ou RETIRER LA PIÈCE,
    ou Suppr) arme le bouton « CONFIRMER : LA PIÈCE SERA DÉTRUITE » ;
    **recycler** : « CONFIRMER : L'ARME SERA DÉTRUITE » ; Échap ou un
    déplacement du focus annule ;
  - **NOUVEAU** : une arme ou une pièce est marquée vue quand elle est
    affichée ; la pastille reste jusqu'à la fin de la visite de l'onglet ;
    l'écriture se fait avec l'action suivante ou en quittant l'onglet
    (`hidden`, appelé aussi par `HubScreen.exit`) ; pas de pastille
    d'onglet (maquette) ;
  - **numéro de version** : ordre d'arrivée dans l'arsenal (stable quel que
    soit le tri) ;
  - **taille des menus 130 %** : puces de filtre, ligne niveau / rareté /
    emplacements de la fiche et boutons INSTALLER / RETIRER passent à la
    ligne s'il manque de place ; modificateurs des emplacements à la ligne ;
  - **DÉPART** : le bouton du bas suit l'élément choisi (RETIRER DE
    L'EMPLACEMENT n, AJOUTER AU DÉPART…) ; CONSTRUCTIBLES : armes à feu de
    l'arsenal utilisables triées par prix, puis les verrouillées.

### Lot D — CONTRATS et ÉCHANGES (dépend de A et B)

- Fichiers : `scripts/ui/hub/contracts_panel.gd`, `contract_card.gd`,
  `reward_popup.gd`, `exchanges_panel.gd`, `samples_column.gd`.
- Tests : `tests/test_hub_contracts.gd` (accepter, abandonner, remettre,
  bouton grisé et raisons, progression partagée, expiration signalée,
  échange en deux appuis, filtre « échangeables »).
- Fini quand : écrans 4 et 5 de la maquette reproduits, FR et EN.
- **Fait** (branche `hub-d` : écrans 5, 6, 7, 11 et l'encart contrats du 1).
  Choix pris pendant le lot (provisoires) :
  - ouverture du hub : purge et premier remplissage
    (`HubContractsView.open_hub`), contrats actifs expirés lus une fois
    (`take_expired`) et signalés au LABO (ligne EXPIRÉ et réplique du
    scientifique) pendant la visite ; une écriture du profil seulement si
    quelque chose a changé ;
  - « nouvelle proposition » = arrivée au dernier remplissage du tableau
    (`since == rotation`) : pastille NOUVEAU sur la carte (absente de la
    maquette) et ligne du LABO ; la pastille de l'onglet CONTRATS reste le
    nombre de contrats prêts (maquette), ÉCHANGES n'en a pas ;
  - jours restants : jours pleins après aujourd'hui (« ENCORE 12 J » le 18
    pour le 30), « DERNIER JOUR » le dernier ;
  - « Partagé avec : … » seulement sur un contrat PRÊT (là où remettre peut
    faire reculer l'autre, comme la maquette) ; la RÉSERVE dit la
    conséquence (« il en restera 3, assez pour … », en rouge un contrat à qui
    la remise ou l'échange **crée** un manque) ;
  - REMETTRE grisé dit ce qui manque (« IL MANQUE 1 TOUFFE » ; plusieurs
    sortes : « IL MANQUE 5 ÉCHANTILLONS ») ; ACCEPTER grisé : raison en tête
    de l'aide, la demande du scientifique ensuite ; les textes des boutons
    rétrécissent pour tenir dans la carte (`HubFitButton`) ;
  - demande du scientifique : texte complet des données, 3 lignes au plus
    (2 si trois sortes), « … » ensuite ; italique synthétique ;
  - échange : même fenêtre que la remise (« ÉCHANGE CONCLU », sans XP), nom
    de l'objet = titre de l'échange ; une pièce de contrat porte le nom
    commun à tout le hub (`HubGear.part_name`, noms du lot C : Renfort,
    Ressort, Guide, Amortisseur, Mire, Rallonge, Cartouchière), en
    capitales dans la fenêtre ;
  - aide de la fenêtre : « L'objet est rangé avec la pastille NOUVEAU. »
    (la maquette y mettait une note de conception) ; une case active vide
    affiche « LIBRE ».

### Lot E — PARTIE et intégration au flux du jeu (dépend de B ; de A pour la rotation) ✅

- Fichiers : `scripts/ui/hub/play_panel.gd` (solo : cartes ; coop :
  héberger / rejoindre / salon, reprend `map_screen.gd`, `host_screen.gd`,
  `join_screen.gd`, `lobby_screen.gd`) ; `Router` / `MainMenu` (retour au hub
  après une partie solo, à l'onglet PARTIE en coop) ;
  `scripts/game/hub/contract_watch.gd` (message en partie, D13) ; appel de la
  rotation en fin de partie.
- Tests : `tests/test_lobby_return.gd` (retour à l'onglet PARTIE),
  scénarios `hub_solo` (hub → carte → partie → évacuation → hub, tableau
  tourné) et `contract_watch` ; `sh tools/mp_test.sh rematch` toujours vert.
- Fini quand : une boucle complète hub → partie → hub marche en solo et en
  coop, écran 7 de la maquette reproduit.
- **Fait** (branche `hub-e` : écrans 9 et 10). Fichiers :
  `scripts/ui/hub/play_panel.gd` (`HubPlayPanel` : vues SOLO, COOP, SALON),
  `play_lobby.gd` (`HubPlayLobby`, reprend l'ancien écran du salon),
  `play_view.gd` (`HubPlayView` : cartes, faits d'une carte, lignes
  communes) ; `scripts/game/hub/contract_watch.gd` (`ContractWatch`) ;
  `Router.hub_tab` ; `Net` (fiche de salon). Retirés : écrans
  MULTIJOUEUR, HÉBERGER, REJOINDRE, CONNEXION, SALON, choix de carte solo
  (`map_screen.gd`) et le panneau provisoire `HubPlayStubPanel` ; la
  rotation des contrats était déjà appelée en fin de partie (lot A). Tests :
  `tests/test_hub_play.gd`, scénario `hub_play` (boucle hub → partie →
  message → évacuation → hub, à la place de `hub_solo` et
  `contract_watch`), scénarios `map_select`, `menu_navigation`, `hub_nav`
  et tests multijoueur `lobby`, `join`, `rematch`, `custommap` adaptés.
  Choix pris pendant le lot (provisoires) :
  - **COOP avant connexion** (pas de maquette) : même cadre que l'écran 9 ;
    à gauche SOLO / COOP puis nom du joueur, HÉBERGER (port, joueurs
    maximum), REJOINDRE (adresse IP, port), ligne d'état (votre adresse IP,
    « Connexion à … » avec ANNULER, erreur) ; à droite les règles de la coop,
    VOUS PARTEZ AVEC et VOS CONTRATS ACTIFS (comme l'écran 10). Les erreurs
    de connexion et la fin de session s'affichent **sur place** (plus de
    fenêtre de message), sauf hors du hub (message, puis onglet PARTIE) ;
  - **salon** : chaque ligne montre aussi les **armes de départ** du joueur
    (petite ligne sous le nom ; absent de la maquette) ; niveau et armes
    viennent du profil de chacun (`Net.players[pid].lvl / start`, non
    vérifiés par l'hôte, affichage seulement) ; couleurs des joueurs : celles
    du jeu (`ScorePanel.slot_color`), pas celles de la maquette ; état :
    AU SALON, EN RETOUR… (`LobbyReturn`), CARTE n %, ATTENTE CARTE, CARTE
    REFUSÉE (carte perso) ; pas de bouton PRÊT (la maquette n'en a pas :
    l'état AU SALON en tient lieu, l'hôte lance) ; « VOUS » sur sa propre
    ligne chez l'invité ; places libres jusqu'à 4 lignes ;
  - DÉMARRER grisé porte la raison dans son texte (maquette) ; la ligne
    d'état sous le résumé ne garde que les autres messages (carte refusée,
    joueur parti, lancement) ; QUITTER LE SALON et, en coop, ÉCRAN TITRE du
    menu du hub demandent un deuxième appui ;
  - **CHANGER DE CARTE** (hôte) : fenêtre au-dessus de l'onglet, cartes du
    jeu puis cartes perso ; la carte du salon est gardée d'une partie à
    l'autre (plus réannoncée au retour) ;
  - pastille de l'onglet PARTIE : nombre de changements du salon (joueur
    arrivé ou parti, carte changée) pendant que l'onglet est caché ;
  - **SOLO** : la ligne d'une carte se choisit au focus (clavier, manette)
    ou au clic ; Entrée / A / second clic sur la carte choisie la lance ;
    aperçu : vrai plan de la carte (`MapPreview`) au lieu du dessin de la
    maquette ; « sur cette carte » / « pas sur cette carte » selon les
    échantillons qui manquent ; porte d'évacuation « derrière une porte »
    quand sa zone n'est pas celle du départ ;
  - **retour au hub** : solo (fin de partie ou QUITTER du menu pause) :
    onglet LABO ; multijoueur : onglet PARTIE (salon si le groupe est encore
    connecté) ; partie lancée par TESTER : retour à l'éditeur comme avant ;
  - **« objectif atteint »** : message sobre sous le compteur d'échantillons
    (deux lignes, menthe puis gris, 7 s, file d'attente, petit son), une
    fois par contrat et par partie ; jamais pour un contrat déjà prêt au
    départ (rien à évacuer pour lui).

### Lot F — Hub 3D (plus tard)

- Laboratoire cubique (échelle du décor, 5 cm), scientifique cubique,
  objets interactifs qui ouvrent les panneaux de B à D (§3.9).

## 9. Hub v2 (refonte validée le 2026-10-11) — cadre et règles pour les écrans

Maquettes **à suivre à 100 %** : `docs/hub_v2/` (README.md + un `*.dc.html`
par écran, 1280 × 720 ; tailles, couleurs, polices, espacements et textes
sont dans les styles en ligne). Le scientifique s'appelle **Dr Brown**. Le hub
v2 vit dans `scripts/ui/hub2/` à côté de l'ancien hub (`scripts/ui/hub/`,
toujours celui du jeu) jusqu'à la bascule.

**Ouvrir le hub v2 (provisoire)** : réglage caché `hub_v2=true` dans la
section `[interface]` de `settings.cfg` (`Settings.hub_v2`), ou argument
`--hub2` ; JOUER au menu titre ouvre alors `MainMenu.SCREENS.hub2`.
Captures de comparaison avec les maquettes :
`sh tools/scenario.sh hub2_look` (fenêtre hors écran ;
`HUB_SHOT_RES=1920x1080` pour du 1080p) -> `tests/_out/shots/hub2_look_*.png`
(`lab_mockup` : même contenu que `Main.dc.html`).

### 9.1 Architecture

| Classe | Fichier | Rôle |
|---|---|---|
| `Hub2Screen` | `hub2_screen.gd` | Écran de menu (MenuScreen) : cadre, navigation, profil, menu du hub |
| `Hub2Panel` | `hub2_panel.gd` | Base d'un écran (une maquette) : API ci-dessous |
| `Hub2Style` | `hub2_style.gd` | Jetons des maquettes : couleurs, polices, letter-spacing, px / fs, nombres, ease-out |
| `Hub2Text` | `hub2_text.gd` | Texte d'une ligne à letter-spacing exact (sous-pixel) |
| `Hub2Box` | `hub2_box.gd` | Panneau : fond rgba, liseré par côté, biseaux (clip-path), verre flouté (backdrop-filter) ; MarginContainer (padding) |
| `Hub2Button` | `hub2_button.gd` | BaseButton à contenu libre (un `box` Hub2Box), cadre de focus jaune à la manette / au clavier, `hint` |
| `Hub2Keycap` | `hub2_keycap.gd` | Touche `<kbd>` (texte ou symbole PlayStation) |
| `Hub2PulseRings` | `hub2_pulse_rings.gd` | Anneaux jaunes pulsés (@keyframes hubPulse) |
| `Hub2TopBar` | `hub2_top_bar.gd` | Barre du haut (TopBar.dc.html) |
| `Hub2Prompts` | `hub2_prompts.gd` | Barre d'invites (Prompts.dc.html) |
| `Hub2Breadcrumb` | `hub2_breadcrumb.gd` | Fil d'Ariane « ‹ LABO / CONTRATS » |
| `Hub2Veil` | `hub2_veil.gd` | Voile sur le fond 3D (plein ou dégradé) |
| `Hub2Input` | `hub2_input.gd` | Invites standard -> touches / boutons, noms selon le périphérique, reconnaissance des événements |
| écrans | `screens/hub2_*_panel.gd` | LABO, CONTRATS, ÉCHANGES, ARSENAL, INVENTAIRE, CODEX, JOUER, récapitulatif (provisoires) |

Shaders : `assets/shaders/hub2_box.gdshader` (plat),
`hub2_glass.gdshader` (verre : mipmaps de l'écran + 16 échantillons
gaussiens, écart type du CSS converti en pixels de l'écran),
`hub2_backdrop.gdshader` (étalonnage du fond 3D sous l'interface).

Empilement de `Hub2Screen` (de bas en haut) : fond 3D en direct
(`MenuBackdrop` du MainMenu, voile de gauche du menu titre gardé :
`backdrop_shade`) -> `grade` (étalonnage de menu_post sous l'interface :
l'image de fond des maquettes est le menu titre post-traité) -> `veil` (voile
de l'écran) -> copie de l'écran (BackBufferCopy : le verre floute le fond
tel qu'affiché) -> `pages` (écrans) -> `crumb` -> `top_bar` -> `prompts` ->
`hub_menu`.

Navigation (HUB_PLAN §4.1) : onglets LABO · ARSENAL · INVENTAIRE · CODEX
en boucle (LB / RB, Page préc. / suiv., Q / E, clic) ; JOUER : START, P ou
clic (de nouveau : retour à l'écran d'avant) ; B / Échap / clic droit :
fiche de l'écran, sinon sous-écran -> parent, onglet -> LABO, JOUER ->
écran d'avant, LABO -> menu du hub ; « ‹ LABO » se clique.

### 9.2 Ajouter (remplir) un écran

1. Écrire le contenu dans le fichier de l'écran
   (`scripts/ui/hub2/screens/hub2_<écran>_panel.gd`, `extends Hub2Panel`),
   retirer `add_placeholder(...)`. Un nouvel écran : une ligne dans
   `Hub2Screen.SCREENS` (script, onglet allumé, `parent` pour un sous-écran,
   titre FR / EN).
2. API du panneau (toutes facultatives) :
   - `build()` : construire (une fois ; tout le hub est reconstruit si la
     TAILLE DES MENUS change) ; `refresh()` : profil changé ;
     `shown()` / `hidden()` ;
   - `first_focus()` ; `prompts()` : `[[Hub2Input.ACCEPT, texte], …]` ou
     `[[id, texte, touches, boutons]]` pour une action propre (clic ->
     `on_prompt(id)`) ; `help()` : aide à gauche des invites ;
   - `back()` : vrai si consommé (fiche ouverte…) ; sinon le hub remonte ;
     `handle_input(event)` : reçu AVANT la navigation du hub ;
   - `badge()` : pastille jaune de l'onglet ; `veil()` : voile du fond
     (`{"color": Hub2Style.shade(0.35)}` ou `{"stops": [[0.35, c0], [0.7, c1]]}`) ;
     `shows_top_bar()` / `shows_prompts()` ;
   - placement : `content_rect()` / `content_margins()` / `add_main(c)` =
     le `<main>` de la maquette (28, 96 ou sous le fil d'Ariane, bas 60) ;
   - côté hub : `hub.open(id)`, `hub.back()`, `hub.profile`,
     `hub.save_profile()`, `hub.reload_profile()`, `hub.set_hint(t)`,
     `hub.refresh_prompts()`, `hub.refresh_badges()`, `hub.menu`.
3. Traduire le CSS : toute valeur passe par `Hub2Style.px()` / `fs()` ;
   couleurs par les jetons (`TEXT`, `text_a(α)`, `YELLOW`, `TEAL`, `BAD`,
   `GLASS`, `LINE`, `white_a(α)`, `shade(α)`, `rarity_color(r)`) ;
   un libellé en capitales espacées = `Hub2Text.setup(texte, CHAKRA, 700, 16,
   couleur, 0.08)` (taille et letter-spacing de la maquette, texte déjà en
   majuscules) ; un paragraphe = `Hub2Style.label(...)` ; un panneau
   `rgba(10,11,13,.62) + blur(12px) + 1px rgba(255,255,255,.08)` =
   `Hub2Box.glass()` ; un `clip-path` biseauté = `Hub2Box.chamfer(n)` ;
   un bouton = `Hub2Button` (fond = `button.box`) ; `.hub-ring` =
   `Hub2PulseRings` enfant du bouton (`scale_to` de la maquette).
   Graisses : celles chargées par les maquettes (Chakra Petch 500 / 600 /
   700, Barlow 400 / 500 / 600, JetBrains Mono 500 / 700) ; un nombre sans
   graisse s'affiche en JetBrains Mono 500, comme dans le navigateur.
4. Toute chaîne visible : `Lang.t(fr, en)` (FR et EN).
5. Tests : `tests/test_hub2.gd` (cadre) ; les écrans ajoutent leurs tests
   unitaires et, pendant leur développement, des captures dans
   `tests/autotest/hub2_look.gd` (ou leur propre scénario `@rendu`).
   Pas de fonction statique qui crée sa propre classe dans un script de
   Control (ressources encore utilisées à la sortie).

### 9.3 Écarts connus avec les maquettes (cadre)

- **Fond** : scène 3D en direct (zombie qui marche, caméra qui dérive), pas
  l'image figée ; l'image des maquettes est le menu titre post-traité : même
  étalonnage, grain et vignette reproduits sous l'interface, sans la
  surimpression « caméra » (CAM-07, REC, coins) ni le texte d'aide capturés
  dans l'image.
- **Verre** : la copie de l'écran est faite une fois, après le voile : un
  verre ne floute pas un autre verre ni le contenu des écrans dessiné avant
  lui (`Hub2Style.blur_barrier()` au besoin).
- **Mesures de texte** : avances des glyphes de Godot (onglets à ±1,3 px des
  positions mesurées dans Chrome sur la maquette).
- **Menu du hub** (REPRENDRE, OPTIONS…) : pas de maquette v2, celui de
  l'ancien hub (`HubMenu`) est réutilisé tel quel.
- **Focus** : les maquettes ne le dessinent pas ; `Hub2Button` montre un
  cadre jaune de 2 px (manette, clavier), jamais à la souris.
- **JOUER au clavier** : P (la maquette ne montre que START).

### 9.4 LABO, CONTRATS, ÉCHANGES (écrans faits)

Fichiers : `screens/hub2_lab_panel.gd`, `hub2_contracts_panel.gd`,
`hub2_exchanges_panel.gd`, plus `hub2_lab_kit.gd` (`Hub2LabKit` : mots et
couleurs des échantillons, fiches des tuiles, délais, réplique de Dr Brown
selon la situation, contrats prêts histoire + temporaires),
`hub2_reward_tile.gd` / `hub2_reward_tooltip.gd` (tuile 72 × 72 et son
infobulle, survol ou focus), `hub2_reward_popup.gd` (fenêtre de remise).
Règles : `StoryRules` / `StoryData` (§5.7), `ContractRules`,
`ExchangeRules`, `HubRewards`. Tests : `tests/test_story.gd`,
`tests/test_hub2_labo.gd` ; captures pendant le développement :
`tests/autotest/hub2_labo_look.gd` (`*_mockup` : contenu des maquettes,
puis données réelles, anglais, 130 %).

Commandes : CONTRATS — A / Entrée / clic : REMETTRE l'étape (anneaux
quand elle est prête), remettre un contrat temporaire prêt (l'article a le
focus), ACCEPTER une proposition ; X / Suppr / R / clic sur l'invite :
ABANDONNER le contrat temporaire choisi en deux appuis (l'article passe en
rouge, « ABANDONNER ? »), B : annuler ; tuiles focusables (infobulle).
ÉCHANGES — A : ÉCHANGER en deux appuis (« CONFIRMER », coût dans l'aide),
Y / Tab / clic : POSSIBLES MAINTENANT ↔ TOUS. Fenêtre de remise : VOIR DANS
L'ARSENAL (ouvre l'ARSENAL et appelle `show_item(uid)` si l'écran l'a), FERMER
(B, clic à côté) ; les onglets et JOUER sont bloqués derrière elle.

Écarts avec les maquettes :
- **Fenêtre de remise** : pas de maquette ; composée avec les jetons v2
  (verre, Dr Brown en buste `scientist_bust`, tuiles, XP, étape débloquée).
- **CONTRATS sans contrat prêt** : la maquette ne montre que l'état prêt ;
  sans contrat prêt, pas d'anneaux ni de « TERMINÉ », le nombre de contrats
  en cours à la place (JetBrains Mono 14, jaune) ; le bouton reste jaune.
- **Étape non prête** : REMETTRE grisé (fond blanc 8 %, texte 40 %, comme
  ÉCHANGER impossible), étiquette EN COURS (turquoise) ou NIV. n REQUIS
  (rouge) à la place de TERMINÉ ; frise : étape en cours non prête en blanc.
  Histoire finie : « HISTOIRE TERMINÉE ».
- **Contrat temporaire prêt** (absent de la maquette) : liseré jaune 60 % et
  étiquette TERMINÉ en tête des échantillons.
- **Filtre des échanges** : la maquette allume POSSIBLES MAINTENANT en
  montrant aussi des échanges impossibles ; ici le filtre allumé est celui
  appliqué (TOUS par défaut).
- **Fiche d'échange** : toute la fiche est le bouton (focus, clic) ; elle
  s'allume (jaune) au focus et au survol. Qualité affichée d'une pièce
  exacte (provisoire) : deux bonus d'au moins 10 % = D'EXCEPTION, un = SOIGNÉE.
- **Infobulle de l'XP** : « Niveau a → b » et « Progression » pour
  l'histoire, le niveau seul pour les contrats temporaires (comme la
  maquette).
- **Aperçu d'arme** : statistiques réelles de l'arme qui sera remise (pas
  celles de la maquette) ; score = `OwnedWeapon.score()`.
- **Ombre portée de Dr Brown** : mipmap floue du rendu (pas un vrai flou
  gaussien de 30 px).
- **130 %** : rien ne sort de l'écran : colonne du LABO relevée sous la
  barre du haut, Dr Brown borné en hauteur, histoire limitée à 47 % de la
  largeur, contenu des colonnes défilant (molette, focus suivi, sans barre
  visible).

### 9.5 JOUER et récapitulatif (hub v2) ✅

**JOUER** (`screens/hub2_play_panel.gd`, maquettes `Partie.dc.html` et
`PartieCoop.dc.html`) : vue SOLO, vue COOP sans salon, salon
(`hub2_lobby_view.gd`) ; données sans interface dans `hub2_play_data.gd`
(pastilles des vagues : rotation de `WaveRules`, carte du défi, lignes de
cartes, fiches du salon), cases d'armes et règles du choix des armes de départ
dans `hub2_equipment.gd` (règles de l'ancien onglet DÉPART), fenêtre (armes de
départ, CHANGER DE CARTE) `hub2_modal.gd`, images (`object-fit`, ombre
portée, couche teintée) `hub2_render.gd`, petits éléments `hub2_ui.gd`.

- Aperçu d'une carte du jeu : vue en jeu pré-rendue
  `assets/ui/hub/maps/<carte>.png` (1280 × 720, départ du joueur tourné vers
  la porte la plus proche, interface et mains masquées), régénérée par
  `sh tools/map_shots.sh` (scénario `map_shots`, hors check) ; carte perso :
  son plan (`MapPreview`, pixels nets).
- Noms des cartes du jeu en casse de titre (« BUNKER K-7 » -> « Bunker K-7 »,
  `Hub2PlayData.map_title`) ; sous-titre « 1 à 4 joueurs » ; carte perso
  « par <nom du joueur> » (faite sur ce PC) ; record = meilleure manche sur
  la carte (`CareerStats.map_best`, section `best_round_map` du dossier de
  combat, cartes perso comprises).
- Défi de la semaine : la carte turquoise biseautée se choisit comme une
  carte (aperçu de sa carte, armes imposées : « IMPOSÉ PAR LE DÉFI » au lieu
  de X · MODIFIER) ; en coop, première ligne de CHANGER DE CARTE.
- X · MODIFIER (X au clavier comme à la manette) : fenêtre ARMES DE DÉPART
  (trois cases, une ligne par arme de base, AU DÉPART) ; Échap / B : fermer.
- Salon : PRÊT = revenu au salon après la partie précédente (`LobbyReturn`)
  et, si l'hôte a choisi une carte perso, carte reçue et vérifiée
  (`MapShare`) ; pas de bouton PRÊT à part (la maquette n'en montre pas).
  Ping : mesuré par l'hôte (aller-retour ENet de chaque invité, toutes les
  2 s au salon), écrit dans le registre des joueurs (champ facultatif
  « ping », diffusé s'il bouge de 5 ms ou plus) : aucun nouveau RPC,
  protocole inchangé (tests/autotest/mp_hub2_lobby_*). Niveau et armes de
  départ : fiche de salon existante. Joueur : `player_neutral` +
  `player_team_mask` × `HudStyle.player_color(place)`. B / Échap : QUITTER
  LE SALON (deux appuis) ; Y / Tab : CHANGER DE CARTE (hôte) ; HÉBERGER
  ouvre un salon de 4 (maquette) ; REJOINDRE accepte « IP » ou « IP:port ».

**Récapitulatif** (`screens/hub2_recap_panel.gd`, `Recap.dc.html` ; données
`hub2_recap_model.gd`) : ouvert par MainMenu au retour d'une partie
(`Router.last_match` pas encore vu : clé `recap_seen`), en solo comme en coop
(CONTINUER : LABO, ou JOUER si le salon est encore ouvert ; « je suis revenu
au salon » part dès le récapitulatif). L'écran de fin en partie ne montre
plus le rapport d'XP ni le butin quand le hub v2 est actif.

- Animation (temps `t` depuis l'affichage, `apply_time(t)` pose tout,
  testable) : XP 0,7 s + 3,8 s ease-out cubique ; à chaque passage de
  niveau (`Hub2RecapModel.level_ups`, plusieurs possibles) : pavé (lvlPop,
  cubic-bezier(.2, 1.6, .4, 1) par segment), anneaux jaune puis turquoise
  (+0,18 s, ×3,2 en 1,1 s), éclair doré radial (0,9 s), « NIVEAU N ! »
  (lvlText 2,2 s : opacité, montée, échelle, espacement 0,6 -> 0,22 em ->
  normal), barre turquoise repartie de 0 ; lignes (rowIn 0,4 s, décalées de
  0,15 s ; armes 0,3 + 0,15 s ; échantillons 0,8 + 0,1 s) ; DÉBLOQUÉ quand
  le passage est fait et l'XP à 75 %. A / Entrée pendant l'animation : fin
  immédiate ; ensuite CONTINUER. ↻ REJOUER L'ANIMATION.
- Détail de l'XP (relevé `XpRules`) : Zombies éliminés (ennemis communs),
  Vagues spéciales et boss (ennemis des vagues + vagues vaincues), Manches
  survécues, Évacuation réussie, Défi de la semaine (récompense) ; lignes à
  0 omises.
- DÉBLOQUÉ : « Armes de niveau N utilisables » (équiper, construire) puis
  « K nouveaux échanges au labo » (échanges dont le niveau requis vient
  d'être atteint) ou, sans échange, « pièces de niveau N au butin ».
- Butin : armes (rendus, rareté, NEUF pour un nouvel exemplaire, AMÉLIORÉE
  pour une version de l'arsenal mise à jour), échantillons ×n, pièces dans
  le titre ; sans évacuation BUTIN PERDU, cartes estompées PERDU et « PERDU :
  3 armes, 9 échantillons » ; défi ou carte perso : BUTIN NON GARDÉ.
- Sons (procéduraux, `tools/gen_audio_menu.gd`) : `ui_xp_tick` (catégorie
  interface, joué à hauteur montante pendant que l'XP grimpe), `level_up`
  (catégorie ritournelle) ; aucune baisse des autres sons.

Écarts et choix provisoires :
- Lueur du « NIVEAU N ! » (text-shadow 24 px) : tache floue sous le texte ;
  lueur de la barre (box-shadow) : dégradé après le bout de la barre.
- Les nombres de la maquette (8 420 / 13 100) suivent le barème réel du jeu
  (`PlayerProfile.xp_to_next`).
- Défaite : titre « LA HORDE L'EMPORTE » en `BAD` (#FF7A5C) à la place
  d'ÉVACUÉ (pas de maquette de défaite).
- Vue COOP sans salon et fenêtres (armes de départ, CHANGER DE CARTE) : pas
  de maquette, style des panneaux du hub v2.
- TAILLE DES MENUS 130 % : la colonne XP du récapitulatif prend au plus 48 %
  de la largeur, les textes trop longs sont coupés ; les cartes perso
  défilent dans leur liste.
- Captures de développement : `sh tools/scenario.sh hub2_play_look`
  (`tests/_out/shots/hub2_play_look_*.png`) ; parcours complet :
  `hub2_recap_flow` (partie -> récapitulatif, carte perso sans progression).
