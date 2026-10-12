# Armes — liste originale provisoire

Liste des armes du jeu (GAME_CONCEPT.md § 4.9, § 4.10, § 6), avec leurs
noms français et anglais, leur famille, leur **niveau de base** et leurs
statistiques. Tout est **provisoire** : choisi en l'absence de l'auteur, à
valider ou corriger (voir « Choix à valider » en bas), sauf les armes déjà
**refaites** (fiche validée `docs/weapons/<id>.md`).

- **Refonte en cours (décidée le 2026-10-12)** : chaque arme est refaite, une
  à la fois, d'après une **arme réelle de référence**, avec un **nom affiché
  proche du vrai** (jamais le nom exact ni une marque), un modèle en **cubes
  de 1,25 cm** (« Modèles cubiques ») et, plus tard, des pièces visibles.
  Faites : **M1912** (`m1911`, Colt M1911A1), **MR-40** (`mp40`, MP40),
  **KA-74U** (`ak74u`, AKS-74U), **KA-47** (`ak47`, AK-47 type 3, arme
  nouvelle), **FAMAX F1** (`famas`, FAMAS F1) ; fiches validées le
  2026-10-12 dans `docs/weapons/<id>.md`. Proposée, pas encore validée :
  IZ-43 (`olympia`, fiche et modèle prêts, pas intégrée).
- Jamais le nom exact d'un fabricant ni d'un modèle réel (AK-74u, FAMAS,
  Galil, HK21, AUG, M14, MP40, MP5K, Olympia, SPAS-12, Python, Dragunov,
  L96A1, M16, Commando, CZ75, MPL, PM63, Spectre, G11, RPK, China Lake,
  FN FAL, M1911…) : les armes pas encore refaites ont des mots courants,
  souvent liés à l'univers (hôpital, laboratoire, bricolage, bêtes) ; les
  armes refaites un nom proche du vrai (M1912 pour M1911, MR-40 pour MP40,
  KA-74U pour AKS-74U, KA-47 pour AK-47, FAMAX F1 pour FAMAS F1). Vérifié mot à mot
  par `tests/test_weapons.gd` (`test_original_names`, liste de noms réels
  interdits).
- **Référence réelle** (demande du 2026-10-12) : une arme refaite d'après un
  modèle existant le dit dans sa fiche complète (DÉTAILS de l'ARSENAL, de
  l'inventaire de partie et de la station de construction), une ligne
  « Réf. Colt M1911A1 » (`WeaponDB.REAL_REFS`, `WeaponDB.real_ref`). Ce n'est
  jamais le nom affiché, qui reste seulement proche du vrai ; une arme entre
  dans la table quand elle est refaite.
- Les **identifiants internes** (clés de `WeaponDB.WEAPONS`, noms des sons
  `*_fire.wav`, arsenals des profils enregistrés, tests) restent ceux de
  l'ancien arsenal : les renommer casserait les profils et les sons pour
  rien, ils ne sont jamais affichés. Seuls les noms affichés changent.
- Les **silhouettes** des armes pas encore refaites sont en cubes de 2,5 cm
  (§ 4.19), inspirées de chaque famille sans copier une arme réelle
  reconnaissable (voir « Modèles »).
- Les **statistiques** de l'ancien arsenal sont gardées telles quelles, sauf
  pour les armes refaites (celles de leur fiche).
- **Niveau de base** (§ 4.7, § 4.9) : niveau minimum auquel l'arme se trouve
  (butin des vagues : seules les armes de niveau de base ≤ manche + 2 sont
  tirées, `LootRules.weapon_pool`) et peut être offerte (contrats, échanges :
  ≤ niveau du joueur, `HubRewards`). Répartis de 1 à 50 selon la puissance
  (dégâts par seconde, zone, mécanisme) : la moitié la plus puissante a un
  niveau moyen plus haut que l'autre (`test_base_levels`). Les dégâts d'un
  exemplaire augmentent ensuite de 10 % par niveau (§ 4.9).

## Table des armes

Cadence en coups par minute (corps à corps : coups par seconde) ; dégâts par
balle (fusils à pompe : × 8 plombs) ; rechargement en secondes.

| Id interne | Nom (FR) | Nom (EN) | Famille | Niv. de base | Dégâts | Cadence | Chargeur / réserve | Recharg. | Particularités |
|---|---|---|---|---|---|---|---|---|---|
| `m1911` | M1912 | M1912 | pistolet | 1 | 30 | 360 | 7 / 70 | 1,7 | **arme de base** (pistolet de départ) ; **refaite** d'après le Colt M1911A1 (fiche `docs/weapons/m1911.md`) : semi-automatique, portée 22 m, recul 2,2° |
| `bat` | BATTE | BAT | corps à corps | 1 | 250 | 1,25 coup/s | — | — | **arme de base** ; énergie 15 par coup ; portée 2,2 m, fente 3 m ; 2 zombies par coup |
| `mp40` | MR-40 | MR-40 | mitraillette | 1 | 90 | 540 | 32 / 192 | 2,4 | **refaite** d'après le MP40 (fiche `docs/weapons/mp40.md`) : recul 0,8°, portée 18 m |
| `olympia` | GARDE-CHASSE | GAMEKEEPER | fusil à pompe | 3 | 60 × 8 | 200 | 2 / 38 | 2,8 | deux canons basculants |
| `stakeout` | BALAI | BROOM | fusil à pompe | 4 | 70 × 8 | 70 | 6 / 54 | 3,0 | pompe, cartouche par cartouche |
| `m14` | MÉTRONOME | METRONOME | fusil d'assaut | 5 | 105 | 380 | 8 / 96 | 1,9 | semi-automatique |
| `mp5k` | MOUCHERON | GNAT | mitraillette | 7 | 70 | 800 | 30 / 120 | 2,1 | poignée avant |
| `cz75` | GUÊPE | WASP | pistolet | 8 | 120 | 500 | 15 / 105 | 1,6 | |
| `pm63` | PUCE | FLEA | mitraillette | 9 | 70 | 1 000 | 20 / 100 | 1,9 | culasse apparente |
| `mpl` | AGRAFEUSE | STAPLER | mitraillette | 11 | 75 | 900 | 24 / 192 | 2,0 | |
| `m16` | TRIPLETTE | TRIPLET | fusil d'assaut | 12 | 110 | 900 | 30 / 120 | 2,2 | rafale de 3 |
| `spas12` | CONCASSEUR | CRUSHER | fusil à pompe | 14 | 70 × 8 | 90 | 8 / 32 | 3,0 | pompe |
| `fnfal` | MASSE | MAUL | fusil d'assaut | 15 | 150 | 400 | 20 / 120 | 2,6 | semi-automatique, pénétration 3 |
| `spectre` | FEU FOLLET | WILL-O'-WISP | mitraillette | 16 | 80 | 950 | 30 / 120 | 2,2 | |
| `ak74u` | KA-74U | KA-74U | mitraillette | 19 | 100 | 700 | 30 / 180 | 2,4 | **refaite** d'après l'AKS-74U (fiche `docs/weapons/ak74u.md`) : pénétration 2, recul 1,3°, portée 28 m |
| `python` | COUPERET | CLEAVER | revolver | 20 | 400 | 180 | 6 / 60 | 3,0 | barillet |
| `g11` | STROBOSCOPE | STROBE | fusil d'assaut | 22 | 110 | 1 800 | 48 / 192 | 2,6 | rafale de 3, lunette courte |
| `ak47` | KA-47 | KA-47 | fusil d'assaut | 23 | 140 | 600 | 30 / 210 | 2,6 | **arme nouvelle**, **refaite** d'après l'AK-47 type 3 (fiche `docs/weapons/ak47.md`) : pénétration 3, recul 1,6°, portée 40 m ; son de la famille (`rifle_fire`) |
| `galil` | BOURRASQUE | GALE | fusil d'assaut | 24 | 110 | 750 | 35 / 315 | 2,8 | |
| `famas` | FAMAX F1 | FAMAX F1 | fusil d'assaut | 26 | 100 | 950 | 25 / 175 | 2,8 | **refaite** d'après le FAMAS F1 (fiche `docs/weapons/famas.md`) : bullpup (chargeur derrière la poignée), recul 1,0°, portée 38 m |
| `l96a1` | LONGUE-VUE | SPYGLASS | précision | 27 | 1 000 | 45 | 5 / 50 | 3,6 | verrou, lunette, pénétration 6 |
| `hs10` | TOURNIQUET | TOURNIQUET | fusil à pompe | 28 | 60 × 8 | 240 | 6 / 36 | 2,8 | semi-automatique |
| `commando` | ÉPERVIER | SPARROWHAWK | fusil d'assaut | 30 | 120 | 800 | 30 / 270 | 2,4 | |
| `aug` | VIGIE | LOOKOUT | fusil d'assaut | 33 | 130 | 700 | 30 / 270 | 2,8 | lunette courte |
| `rpk` | TAMBOUR | DRUMMER | mitrailleuse | 36 | 120 | 700 | 100 / 400 | 4,0 | |
| `china_lake` | TROMBONE | TROMBONE | lance-grenades | 38 | 150 + zone 1 000 (3 m) | 60 | 2 / 20 | 3,2 | pompe, projectile |
| `dragunov` | HIBOU | NIGHT OWL | précision | 40 | 800 | 200 | 10 / 40 | 3,2 | semi-automatique, lunette |
| `hk21` | BÉTONNEUSE | CEMENT MIXER | mitrailleuse | 44 | 130 | 750 | 125 / 500 | 4,5 | |
| `law` | ÉPROUVETTE | TEST TUBE | lance-roquettes | 50 | 800 + zone 1 500 (3,5 m) | 60 | 1 / 20 | 2,8 | projectile |

Hors table (pas une arme tenue) : le **COUTEAU** / KNIFE (`KnifeDB`), attaque
rapide séparée de tous les joueurs (touche de mêlée) : 150 dégâts, un coup
toutes les 0,7 s, 8 d'énergie, portée 1,9 m, fente jusqu'à 3,2 m.

Familles affichées (`WeaponDB.FAMILIES`, FR / EN) : pistolet / pistol,
revolver, mitraillette / SMG, fusil d'assaut / assault rifle, mitrailleuse /
machine gun, fusil à pompe / shotgun, fusil de précision / sniper rifle,
lance-grenades / grenade launcher, lance-roquettes / rocket launcher, corps à
corps / melee.

## Batte de baseball (arme de base)

Arme de départ du personnage (joueur de baseball, § 3, § 4.10) : niveau 1,
commune, donnée à tous (`BaseWeapons`, avec le pistolet de départ ;
sélection par défaut au hub : les deux). Un ancien profil qui avait choisi
le couteau (arme de base provisoire) reçoit la batte.

- **Prend un emplacement d'arme** (§ 4.12) : on la tient, la range, l'échange
  et la construit à la station comme une arme à feu ; le couteau reste
  l'attaque rapide séparée (touche de mêlée), même batte en main.
- **Statistiques** (§ 4.9, corps à corps) : 250 dégâts (couteau : 150 ;
  un coup tue un zombie des manches 1 et 2), **1,25 coup par seconde**
  (`rpm` 75), **15 d'énergie par coup** (couteau : 8 ; § 4.8 bis, § 4.14 :
  plus coûteuse), portée 2,2 m, fente jusqu'à 3 m vers un zombie visé
  (comme le couteau), jusqu'à **2 zombies** frappés dans l'arc du coup. Les
  dégâts suivent le niveau (+10 % par niveau) et les pièces (dégâts,
  cadence) ; épuisé (énergie nulle), les coups sont 50 % plus lents.
- **Coup** : tir (maintenu : coups enchaînés, coup droit puis revers) ;
  armé en arrière, balayage de droite à gauche, impact aux 42 % du coup,
  accompagnement, retour (`ViewModel.SWING_KEYS`). Pas de munitions (pas de
  compteur), ni rechargement, ni visée (reste sur l'épaule ; en sprint, elle
  garde sa tenue).
- **Sons** procéduraux (`tools/gen_audio.gd`) : `bat_swing` (souffle grave)
  et `bat_hit` (« toc » de bois creux et coup sourd).
- **Serveur** : `Combat.srv_swing` (arme tenue, cadence, origine, cibles,
  dégâts de l'arme de partie) ; coup `MELEE` (ferraille d'une touche ou d'un
  kill).
- **Modèle** : frêne clair, manche entouré de ruban bleu marine et blanc,
  pommeau, tête qui s'élargit en escalier (section en croix puis pleine),
  quelques taches de sang de zombie ; ni barbelé (Lucille), ni marque.

## Modèles cubiques

Script : `tools/blender/weapons/weapons_voxel.py` (voxel_lib, Blender sans
fenêtre) ; cellules et couleurs gardées dans
`tools/blender/weapons/weapons_voxel_cells.json` (suivi par git, `--cache`
pour reconstruire à l'identique) ; sorties dans `assets/models/weapons/voxel/`.

```
sh tools/blender.sh tools/blender/weapons/weapons_voxel.py [ids...] [--cache] [--sheet DOSSIER] [--no-check]
```

**Armes refaites (fines)** : script `tools/blender/weapons/weapons_fine.py`
(cubes de 1,25 cm, une fonction par arme décrite en profil texte, sans
cache) ; `--export` écrit `<id>.glb` et l'entrée `<id>` de
`weapons_voxel.json` (info `cube` = 0,0125), `--sheet DOSSIER` la planche de
validation (profil gauche, trois-quarts, vue du tireur, dessus, profil
droit). `weapons_voxel.py` ne construit plus ces armes (absentes de ses
`BUILDERS` et de son cache ; un id fin passé en argument est refusé) et sa
fusion de `weapons_voxel.json` garde leurs entrées.

```
sh tools/blender.sh tools/blender/weapons/weapons_fine.py [ids...] [--export] [--sheet DOSSIER] [--no-check]
godot --headless --path . --import
```

(Variable `GODOT` : chemin d'un vrai `godot.exe` pour la vérification
`tools/voxel_check.gd` lancée à la fin.)

- **Cubes de 2,5 cm** pour les objets tenus (§ 4.19) : armes pas encore
  refaites, batte, couteau, grenade, peluche leurre, cartouche et grenade
  de 40 mm tenues au rechargement. **Cubes de 1,25 cm** pour les armes
  refaites et les mains et avant-bras de la vue FPS (exception validée le
  2026-10-12 ; `WeaponModels.cube` / `is_fine` lisent l'info `cube`).
  Vérifiés par `voxel_check` (armes : d'un bloc, en statique, pièces
  mobiles comprises sur la même grille, `--pas=1.25` pour les armes fines ;
  objets à pièces indépendantes, mains comprises : pièce par pièce) et par
  `tests/test_weapons.gd` (`test_held_models_are_cubic` : seules des armes
  à feu et les mains peuvent être fines).
- **Repère** : l'arme pointe vers -Z, origine à la détente ; la colonne de
  cubes x = 0 est centrée sur l'axe du canon (décalage d'un demi-cube), pour
  que guidon et cran soient centrés. **Largeurs paires** (armes fines,
  `Item(..., even=True)` de `weapons_fine.py` : MR-40, et la proposition
  IZ-43) : l'axe du canon passe ENTRE les colonnes -1 et 0 (x = 0), pièces
  sans décalage ; canon de 2 × 2 cubes, boîtier rond de 4 × 4, guidon et
  cran de 2 cubes, toujours centrés (`test_even_width_fine_model`).
- **Organes de visée** : guidon = un cube centré, cran = vide d'un cube entre
  deux oreilles posées sur les coins du boîtier, sommets à la même hauteur
  (ligne de mire un cube au-dessus du boîtier) ; lunettes en tube de 3 × 3
  sans les coins (axe au centre). Alignement en visée vérifié à **±1 px**
  (`tests/autotest/weapon_aim.gd` : 0,00 px pour chaque arme).
- **Bouche du canon** (`muzzle`) au centre de la face avant du dernier cube
  du canon (frein, cache-flamme) : la flamme de bouche en part.
- **Pièces mobiles** séparées, chacune un nœud du .glb autour de son pivot :
  chargeur `mag` (colonne avant de la poignée des pistolets, chargeur droit,
  incurvé en escalier, tambour, cuve de la BÉTONNEUSE), glissière / culasse /
  levier d'armement / verrou `slide`, pompe `pump`, canons basculants
  `barrels` (GARDE-CHASSE), barillet `cyl` (COUPERET). Les rechargements
  existants (`ViewModel._reload_anim`) les animent sans changement.
- **Mains et bras FPS** (`hands.glb`, `tools/blender/weapons/hands_fine.py`,
  cubes de 1,25 cm à la taille réelle d'une main, validées le 2026-10-12 :
  `docs/weapons/img/hands_m1911.png`) : ceux du joueur de baseball, palette
  de son modèle vu par les autres : gants de frappe sombres à paume de cuir,
  doigts séparés par deux tons, poignet nu, sous-maillot à manches longues,
  manche courte crème du maillot (équipe fictive, sans logo ni numéro),
  bandage à l'avant-bras gauche (`forearm_l`) ; bracelets, sous-maillot et
  liseré dans la zone d'équipe (matière `team`), teintée à la couleur du
  joueur (`WeaponModels.team_material`) ; poings autour d'une poignée de
  3,75 cm (index le long du flanc, pulpe devant la détente), berceau sous
  un garde-main, main d'appui du pistolet, poings de la batte (manche rond
  de 2,5 cm), mains du lancer ; avant-bras rigide de 24 cubes (0,3 m,
  jamais étiré : posé du poignet vers le coude). `weapons_voxel.py` ne les
  construit plus.
  ```
  sh tools/blender.sh tools/blender/weapons/hands_fine.py --export [--sheet DOSSIER]
  ```
- **Budget** : < 1 500 triangles par arme en cubes de 2,5 cm, < 5 000 par
  arme fine en cubes de 1,25 cm, < 6 000 pour l'ensemble des mains
  (contrôlés par `test_weapons`) ; la vue FPS ajoute la découpe en tranches
  de 5 mm de la partie courbée par la joue de visée.
- **Tenue** : le poing droit suit l'inclinaison de la poignée (info
  `grip_angle`, en degrés autour de X, négatif : bas de la poignée vers
  l'arrière) ; main gauche en berceau sous le garde-main, ou poing vertical
  sur une poignée avant / le puits du chargeur (MR-40 : `front_grip`) ;
  pistolets et revolvers (`ViewHands.is_pistol_hold`) : prise à deux mains
  validée le 2026-10-12 (`docs/weapons/img/pistol_grips.png`, image du
  milieu) : mains MINCES et JOINTES (`pistol_grip`, `pistol_support` : dos,
  paume et doigts d'un cube, un doigt par rangée, poignets côte à côte sous
  la poignée), avant-bras DROITS de 3 × 3 cubes (`forearm_pistol`,
  `forearm_pistol_l`) vers le bas et l'arrière (`ViewHands.PISTOL_ARM_R` /
  `_L`, un peu plus raides que sur la planche : la vue FPS en visée a un
  champ de 72°, la planche 61°) ; fusils et mitraillettes gardent leurs
  poings et avant-bras ; gants
  sombres vus de l'œil (talon de la paume et haut de la manchette en cuir
  sombre, cuir clair seulement contre la poignée). Contact vérifié par
  `test_view_model_fit` (sommets à moins de 3,2 cm de l'arme, bracelet
  exclu).

| Modèle | Triangles | Silhouette |
|---|---|---|
| `m1911` M1912 | 788 | **fine** (1,25 cm) : Colt M1911A1, glissière d'acier usé (rouille, éclats), carcasse parkérisée, plaquettes de noyer quadrillées, poignée inclinée, fenêtre d'éjection avec canon de laiton |
| `cz75` GUÊPE | 260 | glissière noire longue, carcasse rayée jaune et noir, chargeur allongé, guidon jaune |
| `python` COUPERET | 336 | carénage de canon plat et haut comme une lame de hachoir, gros barillet cubique |
| `mp40` MR-40 | 2 446 | **fine**, largeurs paires : MP40, boîtier rond bleu-noir de 4 × 4, canon de 2 × 2, arrêtoir d'appui, long puits nervuré, chargeur droit de 32, carcasse en bakélite brun-rouge, crosse dépliée à deux bras |
| `mp5k` MOUCHERON | 486 | bloc carré sans crosse, poignée avant à ruban sarcelle, chargeur en escalier |
| `pm63` PUCE | 278 | minuscule, culasse claire apparente, crosse orange repliée à droite, poignée avant de 10 cm (main à la taille réelle) |
| `mpl` AGRAFEUSE | 472 | agrafeuse géante : bras supérieur sarcelle à charnière arrière |
| `spectre` FEU FOLLET | 476 | manchon ajouré dont le cœur luit en vert |
| `ak74u` KA-74U | 1 392 | **fine** : AKS-74U, booster en cloche, garde-main en lamellé-collé, boîtier embouti à rivets, chargeur courbe orangé-brun, poignée prune, crosse triangulaire repliable |
| `ak47` KA-47 | 1 768 | **fine** : AK-47 type 3, bloc de guidon à oreilles, baguette sous le canon nu, garde-mains en bois verni, boîtier usiné bleu-noir, chargeur d'acier très courbé, crosse fixe en bois |
| `m14` MÉTRONOME | 650 | bois sur toute la longueur, bagues et plaque de couche en laiton |
| `m16` TRIPLETTE | 750 | trois canons superposés à bagues rouge, jaune, bleue, « III » blanc |
| `fnfal` MASSE | 728 | garde-main olive épais, frein massif d'acier, crosse fauve |
| `g11` STROBOSCOPE | 518 | brique gris clair, viseur intégré, bande jaune, gyrophare orange |
| `galil` BOURRASQUE | 748 | ailettes crénelées sur le garde-main en bois clair, crosse en fil, bipied |
| `famas` FAMAX F1 | 2 142 | **fine** : FAMAS F1 bullpup, poignée de transport (ligne de mire haute), manchon lance-grenades, bipied replié, pontet intégral, chargeur droit de 25 derrière la poignée |
| `commando` ÉPERVIER | 632 | fauve et brun, frein en bec qui pique, crosse sur tube |
| `aug` VIGIE | 782 | viseur perché sur une tour, garde-main olive, crosse fauve |
| `rpk` TAMBOUR | 916 | gros tambour peint en caisse claire (rouge, peaux blanches), bois |
| `hk21` BÉTONNEUSE | 1 064 | cuve de bétonnière orange à spirale jaune sous le boîtier, manchon ajouré |
| `olympia` GARDE-CHASSE | 634 | deux canons superposés, longuesse et crosse anglaise en bois |
| `stakeout` BALAI | 372 | court, sans crosse, pompe en bois clair cerclée de ruban paille |
| `spas12` CONCASSEUR | 604 | pare-chaleur ajouré, pompe orange carrée, crosse squelette |
| `hs10` TOURNIQUET | 468 | compact blanc, sangle noire à boucle rouge |
| `l96a1` LONGUE-VUE | 1 232 | lunette en longue-vue de laiton à bagues de cuir, bois sombre, bipied |
| `dragunov` HIBOU | 1 072 | lunette au gros objectif « œil de hibou », crosse pleine brune |
| `china_lake` TROMBONE | 902 | tout en laiton, coulisse de pompe et pavillon de trombone |
| `law` ÉPROUVETTE | 994 | grosse éprouvette de verre graduée, liquide vert, bouchons de liège |
| `bat` BATTE | 476 | voir plus haut |
| `knife` COUTEAU | 110 | lame d'acier à fil clair, garde en croix, manche noir |
| mains (`hands`) | 5 980 | **fines** (1,25 cm, taille réelle) : 15 pièces (dont la prise du pistolet) |
| grenade (`frag`) | 118 | corps olive 3 × 3 × 3, bande sombre, goupille jaune à part |
| peluche (`teddy`) | 464 | ours assis de 27 cm, tête à part, nœud rouge, pièce rapiécée |

Planches de validation : `--sheet <dossier>` (profil gauche, trois-quarts,
vue du tireur, dessus, contour noir ; `_toutes.png` : toutes les armes de
profil à la même échelle).

## Choix à valider (provisoires)

- Les noms (FR / EN) et leur ton (objets du quotidien, laboratoire, bêtes,
  un peu d'humour : AGRAFEUSE, BÉTONNEUSE, ÉPROUVETTE, TROMBONE).
- Les niveaux de base (1 à 50) ; une seule arme de butin au niveau 1
  (MR-40) ; le lance-roquettes au niveau 50.
- Le butin ne tire que des armes de niveau de base ≤ manche + 2.
- La batte : 250 dégâts, 1,25 coup/s, 15 d'énergie, 2 zombies par coup,
  portée 2,2 m, fente 3 m ; tir pour frapper, coups enchaînés en maintenant.
- La sélection de départ par défaut : pistolet + batte (2 emplacements pris).
- Les couleurs des mains FPS : celles du joueur de baseball vu par les
  autres (gants sombres, maillot crème, zone d'équipe à la couleur du joueur).
- Les silhouettes et le budget de 1 500 triangles par arme.
