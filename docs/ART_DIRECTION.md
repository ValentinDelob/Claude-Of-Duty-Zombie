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
