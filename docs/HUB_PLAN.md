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
- Polices : celles des menus (`UiStyle` : Bahnschrift, Impact, Stencil pour
  les grands titres, Consolas pour les nombres).

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

Seuls échantillons existants : **chiens** — croc (`dog_fang`), touffe de poils
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
| `pack_weapon` | Arme de la meute / Pack Weapon | 10 crocs + 10 touffes + 10 colliers | 5,6 | arme épique précise (pistolet-mitrailleur `mp5k`, nom à renommer) | 8+ |

- Un échange coûte plus de parties qu'un contrat à récompense comparable,
  sans XP : c'est le prix de la certitude.
- La « garniture » du concept (§4.2 ter) est une pièce de dégâts : les
  familles d'emplacements (canon, garniture…) ne sont pas encore dans le jeu
  (💡 §4.9) ; le nom suffit pour l'instant.

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

### Lot D — CONTRATS et ÉCHANGES (dépend de A et B)

- Fichiers : `scripts/ui/hub/contracts_panel.gd`, `contract_card.gd`,
  `reward_popup.gd`, `exchanges_panel.gd`, `samples_column.gd`.
- Tests : `tests/test_hub_contracts.gd` (accepter, abandonner, remettre,
  bouton grisé et raisons, progression partagée, expiration signalée,
  échange en deux appuis, filtre « échangeables »).
- Fini quand : écrans 4 et 5 de la maquette reproduits, FR et EN.

### Lot E — PARTIE et intégration au flux du jeu (dépend de B ; de A pour la rotation)

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

### Lot F — Hub 3D (plus tard)

- Laboratoire cubique (échelle du décor, 5 cm), scientifique cubique,
  objets interactifs qui ouvrent les panneaux de B à D (§3.9).
