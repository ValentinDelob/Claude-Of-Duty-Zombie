# Direction artistique — référence Black Ops 1 Zombies

Notes d'observation (captures, vidéos de parties et descriptions de Kino der
Toten, Five, Nacht der Untoten, Ascension) servant de cible à la refonte R4.
On s'inspire, on ne copie pas : aucune image ni aucun asset d'Activision n'est
intégré au dépôt (les éventuelles captures de travail vont dans
`docs/reference/`, ignoré par git). Chaque section est tenue par le lot qui la
concerne.

## Étalonnage et post-traitement

### Ce qui caractérise l'image de BO1 Zombies
- **Image désaturée, jamais grise** : les couleurs vives (velours de Kino,
  néons des machines, sang) restent lisibles mais « délavées » ; les murs, le
  béton et les uniformes tirent vers un gris vert-de-gris.
- **Deux températures** : les zones éteintes et les recoins sont froids
  (bleu-vert, surtout dans les noirs), la lumière des ampoules et des lustres
  est chaude (jaune-orangé) — le contraste froid/chaud fait la profondeur.
- **Noirs denses mais lisibles** : les ombres sont profondes, mais on distingue
  toujours la silhouette d'un zombie dans un couloir ; jamais d'aplat noir
  absolu (les noirs sont légèrement relevés et teintés).
- **Bloom marqué sur les sources** : ampoules, lustres, écrans des machines
  d'atouts, écran de cinéma et faisceau du projecteur « bavent » largement ;
  les surfaces ordinaires ne brillent pas.
- **Brume visible dans les faisceaux** : poussière en suspension, halos autour
  des lampes (surtout le projecteur de Kino) ; manches de chiens : brouillard
  épais qui noie les lumières.
- **Grain de film** présent en permanence, fin et animé, plus visible dans les
  tons moyens ; léger vignettage ; de rares franges colorées sur les bords.
- **Interface nette** : le grain et le vignettage ne touchent pas le HUD.

### Mise en œuvre (procédurale)
- `WorldLook.grade_color` / `grade_lut` : table de correspondance 3D (24³)
  calculée au chargement et appliquée par `Environment.adjustment_color_correction`
  (coût nul : incluse dans la passe de tonemap). Étapes : désaturation des
  couleurs vives, virage ombres vert-de-gris / hautes lumières chaudes (sans
  changer la luminance), pied de courbe (noirs plus denses, tons moyens
  intacts), relèvement bleu-vert du noir, léger gain. Surcharge par carte :
  `MapDef.look["grade"]` (KINO : `TheaterLook.GRADE`, plus chaud).
- Bloom : glow en mode « écran », seuil HDR 1,0, niveaux larges (3 à 5).
- Brume volumétrique fine (anisotropie 0,7 : halos vers les lampes) en MEDIUM
  et HIGH ; triplée pendant les manches de chiens (`apply_dog_round_look`).
- `FilmPost` (CanvasLayer 5, sous le HUD) : grain animé à 24 images/s,
  vignettage ovale, aberration chromatique radiale (MEDIUM/HIGH) ; variante LOW
  multiplicative sans lecture de l'écran. Option **OPTIONS > VIDÉO > GRAIN DE
  FILM** (0 à 100 %, 50 % par défaut).
- Contrainte utilisateur : l'éclairage venait d'être relevé (« trop sombre ») —
  l'étalonnage ne ré-assombrit pas : `tests/autotest/visual_look.gd` mesure la
  luminance moyenne de chaque zone (courant rétabli) et échoue sous 0,05.

### Écarts restants
- Les lampes « courant coupé » restent rouges (choix de l'éclairage de la
  carte) là où BO1 garde une lumière faible et neutre.
- Pas de flou de profondeur ni de flou de mouvement (coût, et peu visibles dans
  BO1 hors visée).
- Bloom : un écran de machine d'atout vu à bout portant sature en blanc.

## HUD

### Ce qui caractérise le HUD de BO1 Zombies
- **Compteur de manche** en bas à gauche, gros, rouge sang « peint à la
  main » : bâtons pour les manches 1 à 5 (le 5e barre les quatre autres), puis
  chiffres tracés au pinceau, irréguliers, avec de petites coulures.
- **Transitions de manche** : à la fin d'une manche le compteur passe au blanc
  et pulse lentement (blanc <-> rouge) pendant l'entracte ; au début de la
  suivante l'ancien chiffre s'efface et le nouveau apparaît en blanc puis
  vire au rouge. Manche de chiens : clignotement rouge braise.
- **Atouts** : petites pastilles carrées arrondies, à la couleur de la
  boisson, alignées juste au-dessus du compteur de manche.
- **Points** en bas à droite, au-dessus des munitions : un bandeau par joueur
  à sa couleur (blanc, bleu, jaune, vert), le sien plus grand ; chaque gain
  fait jaillir un « +10 » / « +50 » doré qui s'envole vers la gauche en
  s'éparpillant ; les dépenses apparaissent en rouge.
- **Munitions** : nom de l'arme au-dessus (s'efface quelques secondes après
  le changement d'arme), chargeur en gros chiffres, réserve plus petite ;
  icônes de grenades (et singes) à gauche. Chargeur presque vide en rouge.
- **Invites** au centre bas, texte blanc sans cadre : « Appuyer sur F pour
  acheter M14 [Coût : 500] », « Maintenir F pour ... ».
- **Réticule** : quatre traits fins blancs qui s'écartent avec la dispersion ;
  marqueur de touche en croix.
- **Dégâts** : sang qui envahit les bords (éclaboussures, coulures), voile
  rouge bref à chaque coup, battements de cœur à faible santé.
- **À terre** : vision floue qui respire, délavée, bords rouges pulsés.
- **Fin de partie** : « GAME OVER » en grand, « Vous avez survécu N manches »
  dessous, puis le tableau des scores (points, tués, têtes, réanimations,
  à terre) avec une ligne colorée par joueur.
- **Typographie** : sans empattement, condensée, blanc cassé avec ombre ;
  aucune fioriture, lisible sur le grain.

### Mise en œuvre
- `HudStyle` (`scripts/game/hud/hud_style.gd`) : polices système condensées
  (Bahnschrift étroite, repli Arial Narrow / Impact), couleurs, et pinceau
  procédural `brush_stroke` (largeur variable, bords irréguliers, stries,
  coulures) ; `digit_strokes` décrit les chiffres 0-9 en traits.
- `RoundCounter` : bâtons et chiffres peints, machine d'états INTRO / OUTRO /
  IDLE (`whiteness` = part de blanc), clignotement des manches de chiens.
- `ScorePanel` : bandeaux dégradés à la couleur du joueur, « +N » envolés.
- `Hud.bo1_prompt` : convertit le texte des objets (« [F] Acheter M14 [500] »)
  au format BO1 ; `_prompt` garde le texte brut (tests).
- `hurt_vignette.gdshader` (sang, voile), `downed_blur.gdshader` (flou par
  mipmaps de l'écran, uniquement à terre), `Scoreboard` restylé, fin de
  partie mise en page par `Hud.show_game_over_table`.
- Captures de contrôle : `tests/autotest/visual_look.gd` (`--hud` pour ne
  jouer que la partie HUD).

### Écarts restants
- Le HUD est en pixels (fenêtre de base 1280x720) : en 1080p il paraît plus
  petit que dans BO1 (pas de mise à l'échelle de l'interface).
- Pas d'icônes de réanimation au-dessus des coéquipiers à terre dans le
  monde (hors périmètre du HUD 2D).
## Zombies

### Référence (Kino der Toten, Five, Ascension)
- **Silhouette** : humains maigres, décharnés, épaules tombantes, buste voûté
  vers l'avant, tête projetée en avant ; bras longs et osseux, mains crochues.
  La lecture à 10 m se fait par la silhouette sombre et les deux yeux.
- **Vêtements (Kino)** : uniformes de la Wehrmacht feldgrau (vert-gris terne,
  sali, taché de sang séché brun-rouge), col plus sombre, ceinturon et
  cartouchières de cuir noir, brelages, pantalon gris ardoise rentré dans des
  bottes hautes ; couvre-chefs variés (casque d'acier M35 à bord évasé,
  casquette M43 à visière, casquette d'officier à plateau haut) ou tête nue.
  Tuniques déchirées : manches arrachées, trous laissant voir les côtes.
  D'autres cartes montrent des civils, du personnel, des scientifiques en
  blouse ; on garde quelques variantes de ce type pour la variété.
- **Peau** : gris pâle légèrement verdâtre, marbrée, veines et ecchymoses
  violacées ; orbites creuses et sombres ; lèvres rongées, dents visibles,
  **mâchoire pendante / disloquée** ; plaies ouvertes, entrailles parfois.
- **Yeux** : **jaunes lumineux** à Kino (halo net qui « bave » dans le bloom),
  la marque la plus reconnaissable du mode, visible de loin dans le noir.
- **Sang** : abondant mais sombre (rouge profond presque noir une fois sec),
  surtout bouche/menton/poitrine, mains, autour des plaies.
- **Animations** :
  - marcheur : pas traînant, titubant, souvent une jambe qui traîne ; bras
    tendus en avant ou un bras levé et l'autre ballant, ou bras pendants ;
  - coureur : penché en avant, bras ballants qui battent mollement ;
  - sprinteur : très penché, bras tendus vers la proie ;
  - attaque : coup de griffes à deux bras (bras levés puis frappe plongeante) ;
  - émergence : les mains crèvent le sol d'abord, puis la tête ; le zombie se
    hisse en prenant appui ;
  - fenêtres : agrippe une planche, l'arrache en se jetant en arrière, la jette,
    puis enjambe l'allège ;
  - rampants (jambes arrachées) : se traînent à la force des bras ;
  - morts : chute molle (ragdoll), effondrements variés, tête qui éclate au
    tir à la tête mortel.

### Mise en œuvre (scripts/game/zombies/zombie_model.gd, zombie_anim.gd)
- Maillage procédural à **normales lissées** (RigBuilder : ellipsoïdes et tubes
  de sections elliptiques « loft »), toujours **skinné sur le squelette
  commun** (13 os + mâchoire) et **un seul draw call** ; articulations
  partagées entre deux os (coudes, genoux, épaules, cou) : aucune fissure.
- **6 archétypes** (soldat casqué, soldat en calot, officier, soldat débraillé
  torse nu à bretelles, scientifique en blouse, civil en gilet), 36 looks
  déterministes (variante réseau -> look), couleurs converties sRGB -> linéaire.
- Détails : col, boutons, poches à rabat, pattes d'épaule, ceinturon à boucle,
  cartouchières, brelages, boîtier de masque à gaz ou gourde, jugulaire ;
  côtes à vif dans les déchirures, trous de balles, joue arrachée, crâne
  ouvert, entrailles (rare), moignons prévus pour le démembrement.
- **Shader dédié** (assets/shaders/zombie.gdshader, corps dans
  zombie_body.gdshaderinc) : matière par pièce
  (tissu, peau marbrée veinée, cuir, métal peint écaillé, plaie humide, os),
  bruit calculé sur la position de repos (ne glisse pas pendant l'animation),
  **sang peint par sommet** à bord irrégulier (pas de pastilles géométriques).
- Zombies sur la **couche de rendu 2** : les décalques de sang du sol ne les
  « peignent » plus (bottes rouges auparavant).
- Coût : ~1 800 à 2 700 sommets par look, mesh et Skin partagés (cache),
  looks préparés en arrière-plan (WorkerThreadPool) dès le premier zombie :
  construction d'un zombie < 0,1 ms. A/B dans zombie_look : rendu de 24
  zombies de près à ~96 % des images/s de l'ancien modèle en boîtes.

### Écarts restants avec BO1
- Pas de vrai ragdoll physique (morts procédurales variées).
- Pas de traînée lumineuse des yeux en mouvement ni d'yeux rouges vus « à
  terre » (effet d'écran).
- Détail limité par le low-poly procédural (pas de textures peintes, visages
  simplifiés).

## Armes à la première personne et mains

### Ce qui caractérise BO1
- **Champ de vision de l'arme** : BO1 dessine l'arme avec le `cg_fov` par
  défaut de 65° (horizontal en 4:3, soit ~51° verticalement). L'arme reste
  « loin » de l'œil et peu déformée : pas d'effet grand-angle sur la crosse,
  le bas de l'écran reste dégagé. Le décalage `cg_gun_x/y/z` place l'arme en
  bas à droite, légèrement tournée vers le réticule.
- **Hanche** : on voit le dessus et le flanc gauche de l'arme, la bouche du
  canon vers le centre de l'écran, la crosse sort par le coin inférieur
  droit. Les pistolets sont tenus à deux mains, plus près et plus haut.
- **Visée** : cran et guidon parfaitement centrés ; la carcasse occupe le bas
  de l'écran sans le boucher (armes à lunette : écran de lunette plein).
- **Formes** : pas un seul bloc brut. Canons ronds étagés, cache-flammes à
  lamelles, chambre conique de l'AK74u, garde-mains ronds nervurés (M16),
  bois arrondi (AK74u, M14, Olympia), chargeurs courbes (AK74u, Galil,
  MP5K, Dragunov), tambour nervuré (RPK), glissière aux stries arrière
  (M1911), barillet cannelé (Python), lunettes à objectif évasé.
- **Matériaux** : acier bronzé presque noir aux arêtes usées qui laissent
  voir le métal nu, phosphatation grise sur les armes américaines, noyer
  vernis rougeâtre veiné (M14, Olympia), bakélite, polymère mat, laiton des
  douilles. Contraste fort : reflets nets sur le métal, bois chaud.
- **Mains** : chaque personnage de Kino a ses mains (d'après les fichiers
  de modding : bras de prisonnier américain pour Dempsey, de bagnard de
  Vorkouta pour Nikolaï, de soldat nord-vietnamien pour Takeo, de
  combinaison de protection pour Richtofen). Doigts refermés sur la
  poignée, index sur la détente, pouce par-dessus ; la main gauche
  soutient le garde-main (doigts remontant sur le flanc, pouce le long de
  l'autre) ou tient la poignée avant ; manches visibles jusqu'au bord de
  l'écran.
- **Animations** : sortie (l'arme remonte du bas à droite en pivotant) et
  rangement ; rechargement réaliste (l'arme bascule, la main gauche
  retire le chargeur, en rapporte un neuf, l'enfonce d'un coup sec, arme la
  culasse si le chargeur était vide) ; cartouche par cartouche pour les
  fusils à pompe et le China Lake (coup de pompe final) ; canons basculés de
  l'Olympia ; barillet sorti du Python ; pompe à chaque tir (Stakeout,
  SPAS-12) ; verrou du L96 ; glissière qui recule à chaque tir et reste
  ouverte chargeur vide (pistolets) ; sprint : arme basse, tournée et
  inclinée, grand balancement en huit.

### Mise en œuvre (Call of Claude Zombie)
- `WeaponMesh` : primitives arrondies (profil extrudé chanfreiné, révolution,
  capsule), fusionnées en un maillage par matériau et par pièce mobile,
  construites une fois et mises en cache. Couleur de sommet = donnée
  (arêtes usées, variation par pièce).
- `WeaponModels` : archétypes détaillés, groupes mobiles `mag`, `slide`,
  `pump`, `barrels`, `cyl` et leurs pivots ; ancres de visée inchangées
  (alignement testé à ±2 px par `weapon_aim`).
- `ViewHands` : mains, doigts en phalanges, avant-bras et manches ; quatre
  tenues selon l'emplacement du joueur (manches kaki retroussées et mains
  nues, veste matelassée et mitaines, veste olive, combinaison jaunâtre et
  gants de caoutchouc noir).
- `ViewModel` : champ de vision de l'arme 51,3° à la hanche (72° en visée,
  pour que la carcasse ne bouche pas l'écran), appliqué par
  `weapon.gdshader` (`vm_fov_scale`) ; les effets (flamme, douilles,
  traçantes) partent du point où l'on VOIT la bouche du canon.
- `weapon.gdshader` : usure des arêtes, veinage et vernis du bois, trame des
  manches, liseré de contre-jour et lumière d'appoint de la vue FPS.

### Écarts restants avec BO1
- Pas de textures peintes (gravures, marquages, quadrillage des plaquettes) :
  le détail vient de la géométrie et du bruit procédural.
- Mains stylisées (doigts en capsules), sans rides ni ongles.
- Les animations sont procédurales (courbes) et non capturées : pas de
  léger dépassement ou d'hésitation humaine, et une seule chorégraphie
  « chargeur » partagée par les armes à chargeur.
