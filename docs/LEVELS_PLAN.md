# Plan : niveaux libres (sans étages), plafond masqué et ciel, coordonnées négatives, escalier contre un mur

Demande de l'utilisateur (5 octobre 2026) : supprimer la notion d'étage —
chaque PIÈCE se déplace librement sur l'axe Z (étages de tout niveau et de
toute forme) ; afficher ou non le plafond d'une pièce ; supprimer « Double
hauteur » ; construire en coordonnées négatives ; coller le BOUT HAUT d'un
escalier contre un mur. Les zones restent des groupes de pièces (achat,
textures) et peuvent s'étendre sur plusieurs niveaux.

## Décisions de l'utilisateur (priment sur tout le reste du plan)

1. **Plafond masqué : pas de couvercle invisible.** On voit un **ciel
   personnalisable** : « Sans fond » (noir complet), « Ciel » (jour), « Nuit
   étoilée », avec une **luminosité** réglable. Réglage de la CARTE (clé
   `carte.ciel` = `{type: "noir"|"jour"|"nuit", luminosite: nombre}`, défaut
   noir, jamais écrit à sa valeur par défaut), visible dès qu'une pièce est
   sans plafond (et dans l'aperçu 3D de l'éditeur). Rien n'empêche un joueur
   de sortir par le haut : c'est au concepteur de fermer sa carte (le
   validateur peut AVERTIR d'un décor empilé grimpable sous un ciel ouvert, à
   évaluer, jamais refuser).
2. **Plafond sous une pièce posée au-dessus : le plus bas des deux** (plafond
   réglé de la pièce, coupé par le dessous de la dalle du dessus).
3. **Aucune limite** : l'altitude du sol (axe Z) se règle librement, sans
   bornes de conception ni pas imposé (l'interface aimante, le fichier garde
   la valeur) ; pas de nombre maximal de niveaux ; pas de plafond maximal ;
   coordonnées x, y libres (négatives comprises) et pas d'étendue maximale.
   Seules restent des gardes TECHNIQUES : nombres finis ; refus propre et
   expliqué (jamais un plantage) si une carte demanderait une mémoire
   déraisonnable au validateur (grille par niveau : estimer cases × niveaux
   avant de construire, comme `CustomMapGuard.memory_ok`). Le codage réseau
   des positions (`scripts/game/net_codec.gd`, aujourd'hui x, z en
   `clampi(x*100, 0, 65535)` et y avec `Y_OFFSET` 20) doit être élargi pour
   ne rien brider (ex. 32 bits signés ou flottants) — changement de
   protocole réseau à versionner.
4. **Portes d'une pièce montée/descendue** reliées à une voisine restée en
   place : gardées, signalées par le validateur (« reliez deux niveaux par un
   escalier »), jamais supprimées en silence.

Partout où la suite du plan cite une borne (±256, 12 niveaux, 20 m, −15 à
200, pas de 0,05, `MAX_LEVELS`, `MAX_EXTENT`), elle est REMPLACÉE par la
décision 3 ; partout où elle cite un couvercle de collision, par la décision 1.

## 1. Modèle de données — format 17

| Élément | Clé | Valeur | Défaut |
|---|---|---|---|
| pièce | `altitude` | m, altitude absolue du sol | 0 |
| pièce | `plafond` | m, hauteur sous plafond | 3,2 (`EditorMap.DEFAULT_CEILING`) ; ≥ 2,8 |
| pièce | `sans_plafond` | `true` | absente = plafond affiché |
| ouverture, objet | `altitude` | sol du niveau où il est posé (celui de sa pièce) | 0 |
| escalier | `altitude` / `altitude_haut` | sol du pied / sol d'arrivée (absolus) | `altitude_haut` obligatoire en 17 (déduite pour un fichier écrit à la main : premier niveau au-dessus dont une pièce contient l'arrivée, sinon `altitude` + 3,5) |
| escalier droit | `sortie` | `"gauche"` / `"droite"` vu en montant | absente = en face |
| carte | `ciel` | `{type, luminosite}` | noir |

Supprimées : `carte.etages`, `etage` (partout), `double_hauteur`. Les clés
relatives au sol (format 12 : `z`, `hauteur`, `descente`) ne changent pas. Ne
pas appeler la clé `sol` (texture du format 1). `EditorMap.ALT_EQ := 0.005` :
deux altitudes sont le même niveau à 5 mm près. `MIN_STACK := 3.1` (2,8 + dalle
0,3).

Pourquoi une altitude sur chaque élément plutôt qu'un rattachement à la
pièce : conversion 1 pour 1 de `etage` (on garde raster, validateur, export),
pas de référence cassée par MapCarve/fusion/duplication, éléments à cheval
(porte mitoyenne, mur libre, barrière, escalier), éléments autonomes pour
MapOps et le MCP. Déplacer une pièce verticalement déplace son contenu
(`MapTransform.attached`) ; élément orphelin signalé par le validateur.

### Superposition
- Deux pièces qui se recouvrent en plan : `|Δaltitude| ≥ 3,1` (refus à la
  pose `MapRules.check_room`, erreur du validateur sinon) ; même altitude :
  règle actuelle (pas de recouvrement, découpe MapCarve).
- Plafond réel d'une case = min(altitude + plafond, dessous de dalle de la
  première pièce au-dessus de la case). Trémies et vides de pièce haute ne
  sont pas des dalles.
- Pièce haute qui traverse un niveau j (altitude < sol_j et altitude +
  plafond ≥ sol_j + 2,1) : au niveau j, intérieur = vide (TREMIE
  « vide#<id> »), contour = mur ; une pièce de j posée dessus (Δ ≥ 3,1) est
  une mezzanine (bord au-dessus du vide = plancher avec garde-corps).
  Généralise l'ancienne double hauteur à tous les niveaux traversés.
- Cour de fenêtre (`POCKET_*`) qui couperait le volume d'une pièce d'un
  autre niveau : erreur.
- Porte, débris, passage : entre pièces de même altitude ; sinon erreur.

### Escaliers
- Montée = `altitude_haut − altitude`, pente ≤ 40° ; pied : sol libre d'une
  pièce à `altitude` ; arrivée : sol libre d'une pièce à `altitude_haut` ; un
  escalier peut sauter des niveaux ; trémie sur chaque niveau j avec
  altitude < sol_j ≤ altitude_haut ; un plancher intermédiaire au-dessus des
  marches = erreur ; dégagement : plafond réel ≥ surface des marches + 2,1 m.

### Coordonnées négatives
- Le raster construit sur une copie décalée d'un multiple de 0,5 m
  (`MapValidator.shift` = max(0, ceil(−min/0,5))·0,5 par axe) : mêmes cases,
  export inchangé, monde ≥ 0 ; décalage nul pour une carte ≥ 0 (aucune
  régression). Les consommateurs côté éditeur (canvas `_draw_cells`, murs
  obliques, surlignage, textes de position, `MapVertical`, élévations, aperçu
  3D et gizmo : `OFF = WORLD_OFFSET + v.shift`) retirent le décalage. Aides
  `MapValidator.to_grid`, `cell_ed`, `MapTransform.shifted`. NetCodec élargi
  (décision 3).

## 2. Migration (format ≤ 16 → 17), en DERNIER dans `EditorMap._migrate`
Condition : `from < 17` ou présence de `etages` / `etage` / `double_hauteur`.
1. `sols[k] = etages[k].sol` (absent : k·3,5), `hauteurs[k]` (absent 3,2).
2. Pièce d'étage k : `altitude = sols[k]` ; sans `plafond` : `plafond =
   hauteurs[k]` (écrit seulement si ≠ 3,2) ; `double_hauteur` avec un étage
   k+1 : `plafond = sols[k+1] + hauteurs[k+1] − sols[k]` ; au dernier étage :
   clé retirée. Mezzanines, piliers et murs libres d'une double hauteur : rien
   à faire. Pièce ENTIÈREMENT recouverte par des pièces de k+1 : plafond porté
   à max(propre, sols[k+1] − 0,3 − sols[k]) pour garder l'aspect.
3. Ouvertures, objets : `altitude = sols[etage]` ; escaliers : `altitude_haut
   = sols[k+1]` (sinon sols[k] + 3,5, erreur conservée).
4. Retirer `carte.etages`, `etage`, `double_hauteur`.
Cartes reçues : `CustomMapGuard.check_texts` contrôle avant la migration →
deux schémas (≤ 16 figé : `etage`, `etages`, `double_hauteur` ; 17 : nouvelles
clés, sans bornes de conception, `etage`/`etages` refusés). Carte livrée
`assets/maps/draft_arena` réécrite en 17 ; l'originale copiée dans
`tests/fixtures/maps/legacy_draft_arena/` pour les tests de migration.

## 3. Moteur interne
- **Façade `EditorMap`** : `levels()` (altitudes distinctes des pièces,
  triées, + `view_levels` vides de l'éditeur jamais enregistrées),
  `level_alt(k)`, `level_index(alt)`, `alt_of(e)`, `level_of(e)` ;
  `rooms_on(k)`, `openings_on(k)`, `objects_on(k)` filtrent par altitude ;
  `floor_count`/`floor_sol` alias transitoires ; `floor_height` disparaît.
  Écritures `e["etage"] = k` → `e["altitude"] = doc.level_alt(k)` ; lectures →
  `doc.level_of(e)`. Mise en cache de `levels()` (boucles chaudes). Test
  statique `tests/test_levels_no_legacy.gd` : plus de `"etage"` dans scripts/
  hors migration et garde.
- **MapRaster** : niveaux = altitudes distinctes des pièces et éléments ;
  `Floor.sol` = altitude ; copie décalée si négatifs ; `_floor(k)` : (a) toute
  pièce plus basse qui traverse k y pose vide + murs + ses obstacles ; (b)
  pièces du niveau ; (c) trémies des escaliers qui traversent k ; plafond des
  cases des marches posé au niveau du pied ; `_vertical_overlaps()` (paires Δ
  < 3,1, préfiltre par boîtes) ; `v.stair_to[key]` = niveau d'arrivée.
- **MapVertical** : `slab_above(v, k, c)`, `ceil_at = min(own, slab)`,
  `wall_top` (mur jusqu'à la dalle si l'écart ≤ `WALL_CLOSE` 3,0 m), plus de
  récursion par trémies ; `level_at(doc, p, za)`, `nearest_level` ; aimants
  sur altitudes des niveaux, hauts de pièces, dessous de dalle.
- **MapValidator** : `check_floors` → `_vertical_overlaps` ; escaliers via
  `stair_to` ; `_stair_covered` sur tous les niveaux intermédiaires ;
  `_stair_headroom` ; `_neighbors` via `st.to` ; règles des vides adaptées
  (clé « tremie_mi#id » pour les trémies intermédiaires) ; nouveaux contrôles
  (cour de fenêtre, ouverture entre deux altitudes, orphelin) ; messages
  « niveau 3,5 m » au lieu de « étage 1 ».
- **MapRules** : `check_room` refuse un recouvrement vertical < 3,1 ;
  `check_stair` avec `kt = level_index(altitude_haut)` ; `_stair_floor_base`
  lit pièces hautes et escaliers traversants ; escalier qui descend : pied =
  premier niveau dessous dont une pièce contient le pied.
- **MapCarve** : seulement à même altitude ; refus si trop proche
  verticalement d'une autre pièce.
- **Export** (`MapLayoutExport`) : `_stairs` avec `floors[kt].sol` ; linteaux
  et murs via `slab_above` ; murs mitoyens entre niveaux empilés sans
  recouvrement (test de propriété : aucun bloc de mur ne recoupe un autre).
  **Jeu** (MeshMapGeometry, MeshMapBuilder, MeshNav, StairLane) : déjà en 3D
  libre, rien à changer hors plafond masqué/ciel et NetCodec.
- **Plafond masqué** : export `no_ceiling` sur les cases dont le plafond est le
  sien quand la pièce est `sans_plafond` (sous une pièce au-dessus, le dessous
  de dalle reste dessiné) ; murs jusqu'au `plafond` réglé ; pas de lampes
  automatiques sous ciel ouvert ; luminaires/effets/décor accrochés au
  plafond : construits au plafond virtuel + AVERTISSEMENT « accroché à un
  plafond masqué : il flotte à X m » ; élévations : plafond en pointillés ;
  **ciel** de la carte (décision 1) dans le jeu et l'aperçu 3D
  (environnement : noir / ciel de jour / nuit étoilée, luminosité).

## 4. Escalier dont le bout haut touche un mur
Constat : les cases d'arrivée sont sur le trait du petit côté du haut ; si la
pièce d'arrivée a un mur sur ce trait, refus. Règle :
1. Clé `sortie` (droit, large, service, rampe, palier, sur la grille ou
   tourné) : `StairGen.plan` reçoit `side = ±1` ; palier plat en haut à
   `altitude_haut`, largeur W, profondeur D = clamp(snap(W, 0,5), 1,0, 1,5) ;
   volée sur L − D ; bord de sortie latéral ; ancre et tablier suivent ;
   garde-corps côté opposé et au bout si `rail`/`closed`.
2. Cases de sortie = au-delà du bord latéral, au niveau d'arrivée : plancher
   libre d'une pièce à `altitude_haut`. Le bout du haut n'a plus d'exigence.
3. Sortie possible : plafond réel ≥ altitude_haut + 2,1 sur palier et sortie,
   dégagement des marches, rien de bloquant, passage ≥ 0,95 m
   (`StairGen.walk_width`), pente de la volée raccourcie ≤ 40°.
4. Un escalier avec `sortie` passe par le chemin « en forme » (`shaped`).
5. Choix automatique à la pose : si `sortie` absente et l'arrivée en face est
   un mur/obstacle, essayer droite puis gauche ; statut « Arrivée sur le côté
   droit : le haut des marches touche un mur » ; sinon refus détaillé. Le
   validateur lit `sortie`, ne choisit jamais.
6. L, U, colimaçon : inchangés (`tidy_stair` retire `sortie`).
7. Propriétés : « Sortie en haut : en face / à gauche / à droite » et
   « Arrivée : altitude ».

## 5. Interface (sans sélecteur d'étage)
- `view_alt` (float) ; `floor_k` calculé ; barre « ◄ [Niveau 3,5 m ▾] ► »
  (menu des niveaux du plus haut au plus bas avec nombre de pièces,
  « Autre altitude… ») ; Page préc./suiv. = niveau voisin.
- Plan : édition du niveau de la vue ; fantôme du niveau dessous ; vides des
  pièces hautes hachurés ; option pièces du dessus en pointillés ; Alt+clic =
  pièce empilée suivante (va à son niveau) ; clic dans une élévation idem.
- Propriétés de pièce : « Altitude du sol » (déplace la pièce et son contenu,
  une étape d'annulation, refus nommé), « Hauteur sous plafond » (note si
  coupée), case « Afficher le plafond ». « Double hauteur » disparaît.
- Onglet « Niveaux » (remplace Étages) : liste (altitude, pièces, zones) ;
  Voir, Déplacer le niveau de … m, Dupliquer au-dessus, Nouveau niveau vide à
  … m, Supprimer ; fantôme / pointillés. Réglage du **ciel** de la carte
  (onglet de la carte ou des niveaux).
- Déplacement vertical : `MapGroup.move/place_copies` avec `dalt: float` ;
  `MapTransform.attached` filtre par altitude et emporte les escaliers (pied :
  altitude += Δ ; arrivée : altitude_haut += Δ) ; élévations : glisser une
  pièce verticalement avec aimants (pas 0,25).
- Raccourcis : Page préc./suiv. ; Maj+Page = monter/descendre la sélection au
  niveau voisin ; Alt+clic. Textes FR/EN (`Lang.t`).

## 6. MCP et collaboration
- `MapSummary.summarize` groupé par niveau (`niveaux: [{altitude, pieces…}]`),
  pièces avec `altitude`, `plafond`, `plafond_reel_min`, `sans_plafond` ;
  escaliers `{altitude, altitude_haut, sortie, de, vers}` ; entrée ancienne
  (`etage`) encore lue pour les références existantes.
- Outils : `editor_get_map` et `editor_screenshot` : `floor` → `altitude` ;
  `editor_plan_corridor` : même altitude ; `editor_get_element` : `z_monde =
  altitude + z` ; `editor_apply` : `etage` refusé avec message clair.
- Consignes MCP (`scripts/mcp/mcp_docs.gd`) réécrites (altitude, pièces hautes,
  mezzanines, `sans_plafond`, ciel, escaliers, `sortie`).
- MapOps/collab : normaliser `altitude` (nombre fini) ; présence `floor` →
  `alt` ; `PROTO` incrémenté.

## 7. Étapes
Avant tout : références d'export du code actuel dans
`tests/fixtures/levels/*_layout_f16.json` (draft_arena, cartes de
`tests/fixtures/maps`, cartes de `test_stairs_floors`,
`test_ceiling_under_floor`, `test_map_carve`) : filet de non-régression des
étapes 1a/1b (différences de la migration listées et tolérées).

| Vague | Étape | Contenu | Mode |
|---|---|---|---|
| 1 | **1a** | format 17, migration, façade, garde (deux schémas), raster niveaux = altitudes AVEC restriction temporaire (niveaux à ≥ 3,1 m, arrivée = niveau suivant), pièce haute = plafond, MapOps/collab/PROTO, MapSummary lit `altitude`, interface minimale (barre des niveaux, propriété Altitude, plafond libre, double hauteur retirée, onglet listant les niveaux) | seule |
| 2 | **1b** | niveaux libres (recouvrement par paires, traversées, slab_above, escaliers vers tout niveau, check_room/check_stair, cour, ouvertures entre altitudes, orphelins) | parallèle |
| 2 | **2** | plafond masqué + ciel de la carte | parallèle |
| 2 | **3** | coordonnées négatives + NetCodec élargi + retrait des bornes | parallèle |
| 3 | **4** | escalier contre un mur | parallèle |
| 3 | **5** | interface des niveaux complète | parallèle |
| 3 | **6** | MCP et collaboration | parallèle |
| 4 | **7** | docs (MAP_AUTHORING, EDITOR_VIEWS, MAP_OBJECTS, MCP, MAP_COLLAB), retrait des alias, check complet, essai à la main | seule |

Tests par étape (détail) : 1a `test_levels_migration.gd` (f1, f16, sans
format, double hauteur, mezzanine, escaliers, objets, idempotence, relecture),
export identique aux références, `test_levels_no_legacy.gd`, adaptation des
tests qui écrivent `carte.etages`/`etage` ; 1b `test_levels_free.gd`
(demi-niveau + rampe, pièce haute de 9 m et deux mezzanines, refus Δ 3,0,
escalier 0 → 7 avec plancher intermédiaire, dégagement, plafond coupé, murs
sans recoupement) + autotest `levels_play.gd` (zombies sur demi-niveau et
escalier qui saute un niveau) ; 2 `test_map_no_ceiling.gd` + capture `@rendu`
du ciel (jour, nuit, noir) ; 3 `test_map_negative.gd` (invariance par
translation : mêmes messages, export identique, monde ≥ 0) + NetCodec ;
4 `test_stairs_top_wall.gd` ; 5 `test_map_levels_ui.gd` ; 6 tests MCP/collab.
