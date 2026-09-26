# Plan de travail — clone de Black Ops 1 Zombies

Liste de tâches vivante, mise à jour à chaque livraison. Chaque ligne livrée
correspond à un commit poussé et à une release GitHub (`.exe`).

## En cours (agents)

- [ ] Atouts PhD Flopper / Deadshot (noms originaux)
- [ ] Rampants + démembrement ; bonus Death Machine ; Fire Sale multi-boîtes
- [ ] Arme merveille « tonnerre » (équivalent Thundergun de Kino)
- [ ] Carte KINO + sélection de carte (en vérification finale)

## Retours de test de l'utilisateur (26/09/2026) — à corriger

### R1. Corrections rapides (priorité haute)
- [ ] **Planches arrachées trop vite** : aujourd'hui 1,0 s par planche (0,8 s
  pour les coureurs). BO1 : animation d'arrachage d'environ 2 s, un zombie
  seul met une dizaine de secondes à ouvrir une fenêtre de 6 planches.
  Objectif : ~1,9 s par planche (marcheurs), ~1,5 s (coureurs), petite pause
  aléatoire entre deux planches ; scénario barricades mis à jour.
- [ ] **Zombie qui sort du sol et soulève le joueur** : la capsule du zombie est
  solide pour les joueurs pendant l'émergence. Correctif : zombie non solide
  (ni poussé ni poussant) pendant EMERGE, et le Spawner n'utilise plus un point
  d'apparition occupé par un joueur (< 1,5 m). Test : joueur debout sur un
  point d'apparition, sa hauteur ne bouge pas.
- [ ] **Éclairage trop sombre (BUNKER K-7, et vérifier KINO)** : remonter
  l'exposition, la lumière ambiante et la portée des lampes pour obtenir la
  pénombre lisible de BO1 (on voit les zombies et le décor à 15-20 m, les
  zones sombres restent localisées). Captures avant/après dans chaque zone,
  perf maintenue.

### R2. Refonte des armes (priorité haute)
- [ ] **Tir droit** : une seule trajectoire de référence (axe de la caméra =
  réticule), le point d'impact réel sert à TOUT : balle, traceur, impact,
  sang, étincelles. Le traceur part de la bouche du canon et converge vers
  ce point.
- [ ] **Visée (ADS)** : la ligne de mire de chaque modèle (cran arrière,
  guidon, point rouge) doit être EXACTEMENT sur l'axe de la caméra en visée ;
  test automatique par arme (projection écran du guidon au centre à ±1 px),
  dispersion en visée quasi nulle comme BO1.
- [ ] **Lunette des fusils de précision** (L96A1, Dragunov) : écran de lunette
  plein écran (réticule, vignettage noir, zoom x4-x8), balancement, retenir
  la respiration (Maj), le modèle disparaît en visée comme BO1.
- [ ] **Recul façon BO1** : recul visuel de l'arme + remontée progressive de la
  visée qui revient en partie, au lieu d'un saut instantané de la caméra ;
  la dispersion en hanche reste celle de BO1 (réticule dynamique qui s'ouvre).
- [ ] **Effets** : flamme de bouche, fumée, douilles éjectées, lumière de tir,
  impacts selon la surface, trous de balles ; alignés sur la bouche du canon
  et le point d'impact réel ; vus aussi par les coéquipiers.
- [ ] Revue de chaque arme (tir, visée, rechargement, cadence) avec captures.

### R3. Refonte du son (priorité haute)
- [ ] Remplacer les sons procéduraux ratés par des **sons libres de droits**
  (licence CC0 ou équivalente, compatible avec une diffusion gratuite),
  retravaillés (niveau, égalisation, variations) : tirs par famille d'arme,
  rechargements, mécanismes, impacts, couteau, explosions.
- [ ] **Zombies** : grognements, cris, pas traînants, attaques, morts, sons
  d'émergence et d'arrachage de planches ; plusieurs variantes par type,
  espacement réaliste (pas de spam), sons de sprinteurs distincts.
- [ ] Fichier `docs/ASSETS.md` : origine, auteur et licence de chaque son ;
  mention dans les CRÉDITS du jeu.
- [ ] Mixage global (bus, compression légère, spatialisation 3D, occlusion
  simple derrière les murs).

### R4. Refonte visuelle complète vers Black Ops 1 (grande étape)
Étude de référence d'abord (captures de BO1 Zombies : Kino der Toten, Five,
Nacht der Untoten ; HUD, lumière, étalonnage), puis par lots :
- [ ] **Direction artistique et post-traitement** : étalonnage BO1 (tons
  désaturés froids/verts, noirs profonds mais lisibles), grain de film,
  légère aberration, bloom sur les sources lumineuses, brume volumétrique.
- [ ] **HUD fidèle** : compteur de manche rouge à la craie (bâtons 1-5 puis
  chiffres), points des joueurs, munitions et armes, icônes d'atouts, grenades,
  invites, écran de fin de partie et transitions de manche comme BO1.
- [x] **Zombies** : silhouettes humaines crédibles (uniformes allemands
  déchirés, peau, yeux jaunes lumineux), variété, animations (marche traînante,
  course, sprint, attaque, arrachage de planches, émergence, rampants).
- [x] **Modèles d'armes** à la première personne plus détaillés et fidèles,
  mains/gants, animations de rechargement.
- [ ] **Décors et matériaux** : textures plus riches (béton, bois, métal,
  papier peint), accessoires, éclairage de chaque zone ; machines d'atouts,
  boîte mystère, Pack-a-Punch, téléporteur au style BO1.
- [ ] **Menu principal** et écran de chargement au style BO1.
- [ ] Mesures de perf à chaque lot (cible GTX 1050 à 60 fps).

### R5. KINO V2 : reproduction à l'identique de Kino der Toten
Après R4. La V1 (livrée) reprend la structure et les sensations ; la V2 vise
la reproduction fidèle de la carte réelle à partir d'images de référence
(plans vus de dessus, captures, vidéos de parcours) :
- [ ] Réunir les références (plan complet, chaque salle sous plusieurs angles)
  dans un dossier local non publié `docs/reference/kino/` (ignoré par git :
  images sous droits, servant UNIQUEMENT de modèle).
- [ ] Relever les dimensions et l'agencement exacts : hall et son escalier,
  foyer à l'étage et balcon, loges, allée, salle de théâtre (fauteuils,
  scène, fosse), salle des machines, cabine de projection, emplacements exacts
  des fenêtres, portes et prix, atouts, achats muraux, boîtes, pièges,
  téléporteur.
- [ ] **Étages réels** : escaliers, balcon et foyer en hauteur. Nécessite de
  sortir les zombies du mode « flottant » y = 0 (navigation multi-niveaux) :
  chantier technique préalable.
- [ ] Reconstruire la géométrie, l'éclairage et l'ambiance salle par salle, en
  comparant côte à côte avec les références (captures au même point de vue).
- [ ] Textures et modèles recréés (procéduraux ou libres de droits) : on
  s'inspire des images, on ne copie pas les textures ni les modèles d'Activision
  (réserve du cahier des charges).

## Autres tâches restantes
- [ ] Passe de performance GPU libre (`sh tools/perf.sh`, dont `kino_tour`).
- [ ] Poignée de main réseau : refuser un client dont la version de build diffère.
- [ ] Mettre à jour README (état d'avancement) et docs/ARCHITECTURE.md.

## Fait (releases)
- v0.1.36 : build .exe + releases GitHub ; zombies optimisés.
- v0.1.38 : formules de manches et règles d'atouts de BO1.
- v0.1.41 : bonus (power-ups) ; dossier de combat.
- v0.1.45 : fenêtres barricadées ; manches de chiens ; délais d'autotest.
- v0.1.54 : arsenal BO1 ; réseau optimisé ; fente au couteau, Bowie,
  plongeon ; grenades et singe.
