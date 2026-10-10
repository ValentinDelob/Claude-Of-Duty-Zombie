# Assets externes (sons)

Les graphismes du jeu sont procéduraux, sauf neuf textures de particules CC0
des effets de carte (§ « Textures des effets de carte » ci-dessous ; les modèles 3D de
`assets/models/` sont produits par nos scripts Blender, voir
`tools/blender/`, aucun modèle téléchargé ; les décors du catalogue
de l'éditeur (`assets/models/props/`) sont
générés par `tools/blender/props/catalog_props.py`, emblèmes et enseignes originaux ; les objets de
carte cubiques (caisse au hasard, levier du courant, téléporteur...), `assets/models/props/voxel/objets/`,
par `tools/blender/voxel_props/objets.py`, dessins (dé, éclair, flèche) originaux ; les modèles du style
cubique, comme `assets/models/zombies/zombie_voxel.glb`, par
`tools/blender/voxel/voxel_lib.py`, couleurs prélevées sur nos propres planches
de référence, voir docs/ART_DIRECTION.md). La plupart des bruitages
proviennent d'enregistrements **libres de droits** retravaillés pour le jeu ;
l'identité sonore originale reste synthétisée par `tools/gen_audio.gd` et
`tools/gen_audio_menu.gd` : musiques et ambiances, début et fin de manche,
caisse au hasard, téléporteur, interface. L'air de la peluche leurre (ancien
singe-tambour, fichiers `monkey_*`) est lui aussi original (procédural,
`tools/audio/synth_stems.gd`) ; seules ses cymbales sont enregistrées.

## Effets visuels

Aucun fichier : les particules sont des cubes de couleur unie (`VoxelFx`,
`assets/shaders/voxel_particle.gdshader`) et les décalques (trous de balle,
sang, traces d'explosion) des images en pixel art calculées par le jeu
(`Fx`). Les neuf textures du Particle Pack de Kenney (CC0) qu'utilisaient
les effets de carte ont été retirées avec le passage aux particules
cubiques (octobre 2026).

## Voix des personnages

Les répliques de Callahan, Orlov, Arakawa, Weissmann, Mercer, Berg et Jojo (textes originaux,
`assets/voices/*.json`, voir `docs/CHARACTERS.md`) sont des voix de **synthèse**
générées hors ligne par `tools/voices/make_voices.py`, en français et en anglais,
dans `assets/audio/vox/<langue>/<personnage>/` (Ogg Vorbis, 24 kHz) :

- **Chatterbox Multilingual** ([ResembleAI/chatterbox](https://huggingface.co/ResembleAI/chatterbox),
  Resemble AI, licence **MIT**, usage commercial autorisé) : synthèse de chaque
  réplique, même voix dans les deux langues. Les sons produits portent le
  filigrane inaudible « Perth » de Resemble AI.
- **Kokoro-82M** ([hexgrad/Kokoro-82M](https://huggingface.co/hexgrad/Kokoro-82M),
  licence **Apache 2.0**) : une voix de référence synthétique par personnage
  (`am_fenrir`, `bm_george`, `am_michael`, `bm_fable`, réglages dans
  `tools/voices/cast.json`) ; aucune voix de personne réelle n'est clonée.
- Environnement : `tools/tts/` (hors git) avec `uv` (MIT/Apache 2.0), Python 3.11,
  PyTorch (BSD) et les paquets `chatterbox-tts` (MIT) et `kokoro` (Apache 2.0).
  Installation : `tools/tts/bin/uv.exe venv --python 3.11 tools/tts/.venv`, puis
  `uv pip install --index-strategy unsafe-best-match --extra-index-url
  https://download.pytorch.org/whl/cu124 chatterbox-tts kokoro soundfile "setuptools<81"`
  et le modèle spaCy `en_core_web_sm` 3.8.0 (MIT).
- Génération : `tools/tts/.venv/Scripts/python.exe tools/voices/make_voices.py`
  (`--sample 3` pour un échantillon d'écoute ; reprend là où elle s'est arrêtée ;
  `--only callahan --category idle` pour ne faire qu'une catégorie ;
  `--force` pour refaire des fichiers existants). Le moteur de chaque personnage
  est la clé `engine` de `tools/voices/cast.json` (`chatterbox` par défaut).

### Mercer : clonage Qwen3-TTS

La voix de Mercer (FR et EN) vient de deux références choisies à l'écoute,
`tools/voices/refs/mercer_fr.wav` (« Pas assez de fric... Il me faut plus
d'argent, bon sang ! ») et `tools/voices/refs/mercer_en.wav` ("Not enough
cash... I need more money, dammit!"), générées avec **Qwen3-TTS 12Hz 1.7B
VoiceDesign** (voix décrite en texte, aucune personne réelle) et gardées dans git
car elles définissent le personnage. Les deux langues sont deux timbres
différents (une seule est entendue en jeu).

- **Qwen3-TTS 12Hz 1.7B-Base** ([Qwen/Qwen3-TTS-12Hz-1.7B-Base](https://huggingface.co/Qwen/Qwen3-TTS-12Hz-1.7B-Base),
  Alibaba Qwen, licence **Apache 2.0**, usage commercial autorisé ; garder la
  mention de licence) : clonage « ICL » (audio de référence + sa transcription
  exacte) de la référence de la langue, pour chaque réplique ;
  `tools/voices/qwen_clone.py`, appelé par `make_voices.py` pour les personnages
  `"engine": "qwen_clone"` (réglages dans `cast.json`). Mêmes nettoyage,
  niveau (-19 dBFS) et encodage Ogg Vorbis 24 kHz que les autres voix.
- Le modèle Base n'a pas de consigne d'émotion (contrairement à VoiceDesign) :
  il reprend le ton de la référence (agacé, bourru, ce qui colle au personnage)
  et l'adapte à la ponctuation et au texte (exclamations courtes pour les cris,
  phrases sèches pour le reste). Les références de 3 à 4 s suffisent : timbre
  stable d'une réplique à l'autre (mesuré, voir ci-dessous).
- Contrôle qualité automatique de chaque prise, dans le même processus :
  **Whisper large-v3-turbo** (OpenAI, MIT ; outil seulement) transcrit et
  compare au texte, vérifie la langue (français reconnu comme français, p ≥ 0,9) ;
  hauteur médiane (librosa, ISC) à moins de 6 demi-tons de la référence
  (FR ~212 Hz, EN ~237 Hz) ; empreinte de timbre (encodeur de locuteur de
  Qwen3-TTS) proche de la référence. Une prise ratée est refaite avec une autre
  graine (4 essais au plus), la meilleure est gardée ; rapport par fichier dans
  `tools/tts/qa/mercer_<langue>.json` (hors git).
- Grain de la voix : le clone sort souvent plus lisse que la référence. Chaque
  réplique est tirée en plusieurs prises (`"takes"`, 4 pour Mercer) et, parmi
  celles que le contrôle valide, on garde la plus éraillée (rapport
  harmonique/percussif et platitude spectrale les plus proches de la
  référence) ; Ogg Vorbis moins compressé pour Mercer (`"ogg_compression": 0.2`,
  fichiers ~1,5 fois plus gros) pour ne pas lisser le souffle. Essais et mesures :
  `tools/voices/bakeoff/mercer_rasp/README.md`.
- Environnement : `tools/tts/qwen3tts/` (hors git) : venv Python 3.11,
  PyTorch 2.6 cu124, `qwen-tts` (Apache 2.0), `openai-whisper` (MIT, installé
  `--no-deps` avec `tiktoken` et `more-itertools`), `num2words` (LGPL, outil
  seulement) ; sans FlashAttention (attention `sdpa`). Environ 7 Go de mémoire
  GPU avec Whisper, par lots de 8 répliques.
- Génération : `tools/tts/.venv/Scripts/python.exe tools/voices/make_voices.py
  --only mercer` ou directement `tools/tts/qwen3tts/Scripts/python.exe
  tools/voices/qwen_clone.py --only mercer` (`--category`, `--lang`, `--force`,
  `--sample N`, `--qa-only` pour mesurer les fichiers existants).
- `convert_take.py` (Seed-VC) n'a pas de référence `tools/tts/refs/mercer.wav` :
  pour Mercer, lui passer la référence de la langue voulue.

### Berg : clonage Qwen3-TTS

Même moteur et mêmes réglages que Mercer (`cast.json`, `"engine": "qwen_clone"`),
avec ses deux références : `tools/voices/refs/berg_fr.wav` (« Pff... plus
un rond. Quelqu'un veut bien jouer les gentlemen ? ») et
`tools/voices/refs/berg_en.wav` ("Ugh... totally broke. Any gentlemen
wanna help a girl out?", clone interlangue de la référence française), hauteur
de référence ~334 Hz (FR) et ~324 Hz (EN). Le critère de grain garde la prise
la plus proche de SA référence (voix soufflée, lisse), pas la plus éraillée.
Génération : `tools/voices/qwen_clone.py --only berg` (environ 2 h 45 pour
les deux langues) ; rapport dans `tools/tts/qa/berg_<langue>.json`.

### Jojo : clonage Qwen3-TTS

Même moteur et mêmes réglages que Mercer et Berg, avec ses deux références :
`tools/voices/refs/jojo_fr.wav` (« Wesh, écoute-moi bien, sale merde. Tu
touches à mon fric, j'te démonte la gueule, sur la vie de ma mère. ») et
`tools/voices/refs/jojo_en.wav` ("Yo, listen up good, you piece of shit. You
touch my money, I'll smash your face in, swear on my mother.", clone
interlangue de la référence française). La référence française vient de
Qwen3-TTS 1.7B VoiceDesign (brute parisienne d'une centaine de kilos, voix de
basse rauque) dite **grondée à voix basse**, pas criée : une consigne
« furieux, crie » fait monter la hauteur à 300-550 Hz, alors que le clone d'une
référence grave garde le timbre grave même sur une réplique criée. Candidates,
mesures (hauteur médiane, grain) et scripts : `tools/voices/bakeoff/jojo/`
(`scripts/jojo_design.py`, `scripts/jojo_metrics.py`, `scripts/jojo_en_ref.py`).
Hauteur de référence ~116 Hz (FR) et ~112 Hz (EN). Lots plus petits que Mercer
(`"batch": 4`, `"batch_chars": 200`) : sa référence est plus longue (9 s) et les
lots de 8 prises débordaient des 8 Go du GPU. Génération :
`tools/voices/qwen_clone.py --only jojo` (environ 2 h 25 pour les deux langues) ;
rapport dans `tools/tts/qa/jojo_<langue>.json`. Le contrôle compare « j'te » à
« je te » et « wesh » à « ouais » (comme Whisper les écrit). En anglais, la
plupart des prises gardées malgré le contrôle le sont pour la langue détectée
(accent français du clone interlangue, p de 0,5 à 0,9), le texte étant juste.

### Répliques jouées puis converties (Seed-VC)

Pour les répliques qui demandent un vrai jeu d'acteur (cris, peur, rage, souffle,
grognements), on enregistre sa propre voix en jouant la réplique, puis
`tools/voices/convert_take.py` remplace le timbre par celui du personnage en
gardant le jeu (rythme, intonation, souffles) :

- **Seed-VC** ([Plachtaa/seed-vc](https://github.com/Plachtaa/seed-vc), code et
  poids [Plachta/Seed-VC](https://huggingface.co/Plachta/Seed-VC) sous licence
  **GPL-3.0**) : outil hors ligne seulement, rien n'en est livré avec le jeu ; les
  sons produits ne sont pas soumis à la GPL. Modules téléchargés au premier
  lancement : Whisper-small (OpenAI, Apache 2.0), CAM++ (FunASR, Apache 2.0),
  BigVGAN v2 44 kHz (NVIDIA, MIT), RMVPE (MIT).
- Timbre cible : la voix de référence **synthétique** du personnage
  (`tools/tts/refs/<personnage>.wav`, Kokoro) ; aucune voix de personne réelle
  n'est clonée, la voix de l'acteur disparaît.
- Réglages (détaillés dans le script) : modèle 44 kHz conditionné par la hauteur
  de la prise (courbe d'intonation suivie), hauteur moyenne ramenée sur celle du
  personnage, durée inchangée, 40 pas de diffusion. Environ 2,3 Go de mémoire
  GPU et 8 à 12 s de calcul par réplique sur la RTX A2000 (chargement du modèle :
  25 s, plusieurs prises en une commande pour ne le payer qu'une fois).
- Environnement : `tools/tts/seed-vc/` (hors git) : dépôt cloné, venv à part
  (`tools/tts/bin/uv.exe venv --python 3.11 tools/tts/seed-vc/.venv`, puis PyTorch
  2.6 cu124, `transformers==4.46.3`, `librosa==0.10.2`, `descript-audio-codec`,
  `munch`, `einops`, `hydra-core`, `imageio-ffmpeg` pour décoder m4a/mp3) ; poids
  dans `tools/tts/seed-vc/checkpoints/`.
- Conversion (une réplique par fichier, wav/m4a/mp3/ogg/flac) :
  `tools/tts/seed-vc/.venv/Scripts/python.exe tools/voices/convert_take.py
  tools/voices/takes/peur_01.m4a --character callahan` → WAV 44,1 kHz,
  silences coupés, parole à -19 dBFS, dans `tools/voices/takes/out/`
  (`--semitones N` pour monter ou descendre la voix, `--out` pour choisir le
  fichier). Les prises et conversions de `tools/voices/takes/` restent hors git ;
  on copie le résultat retenu dans `assets/audio/vox/<langue>/<personnage>/`.
- Conseils d'enregistrement : pièce calme et peu sonore (rideaux, placard), micro
  ou téléphone à 15-20 cm de la bouche, légèrement de côté pour éviter les
  plosives, sans saturer sur les cris ; une seule prise par fichier, mono,
  0,3 s de silence avant et après ; jouer franchement, l'émotion passe telle quelle
  mais la hauteur moyenne est ramenée sur celle du personnage.

## Licence

Toutes les sources ci-dessous sont publiées sur [freesound.org](https://freesound.org)
sous licence **Creative Commons 0 1.0 (CC0, domaine public)** : utilisation,
modification et redistribution libres, y compris commerciales, sans obligation
d'attribution. La licence a été vérifiée sur la page de **chaque** son
(`https://freesound.org/s/<id>/`, lien `creativecommons.org/publicdomain/zero/1.0`)
avant import. Nous créditons tout de même les auteurs (écran CRÉDITS du jeu et
ce fichier). Aucun son n'est extrait d'un jeu existant (et en particulier
aucun son de Call of Duty).

## Chaîne d'import (reproductible)

```
godot --headless --path . -s res://tools/audio/sfx_import.gd [-- noms...]
godot --headless --path . -s res://tools/audio/sfx_import.gd -- --level      # sons procéduraux
godot --headless --path . -s res://tools/audio/sfx_import.gd -- --loudness   # rapport LUFS
```

- télécharge avec `curl` l'aperçu OGG haute qualité de chaque source dans un
  cache hors dépôt (`<temp>/cod_sfx_cache`, option `--cache=`, `--no-fetch`) ;
- décode en mono 44,1 kHz (Godot `AudioStreamOggVorbis` + `mix_audio`),
  découpe (`start`/`end`), coupe les silences, change la hauteur, égalise
  (biquads), compresse, sature légèrement (tirs), ajoute une réverbération
  d'intérieur courte, écrit un WAV 16 bits mono ;
- couches : plusieurs enregistrements mélangés, répétés sur une grille de
  temps (`times`, ex. les cymbales sur les temps de l'air de la peluche leurre) ou une
  piste procédurale originale (`stem`, `SynthStems`) ;
- les recettes sont dans `tools/audio/sfx_recipes.gd` (préréglages `gun`,
  `gun_heavy`, `explosion`, `mech`, `zombie`, `foley`, `impact`, `dog`,
  `voice`, `zap`), le traitement dans `tools/audio/sfx_dsp.gd` ;
- `--doc` régénère le tableau ci-dessous, `--analyze=<dossier>` et
  `--segments=<fichiers>` aident à choisir les sources et les découpes.

`tools/gen_audio.gd` ne réécrit **jamais** un son qui a une recette
(`SfxRecipes.RECIPES`, liste d'exclusion vérifiée par `tests/test_audio.gd`).

## Intensité perçue (LUFS)

Les sons ne sont plus normalisés en crête mais en **intensité perçue**
(`tools/audio/sfx_loudness.gd`, approximation ITU-R BS.1770 / EBU R128 :
pondération K, blocs de 400 ms ; LUFS-M maximal pour les sons ponctuels,
LUFS intégré avec portes pour les boucles), puis passent dans un limiteur à
anticipation (plafond -0,8 dBFS). Un tir bref et pointu (G11, Spectre) n'est
donc plus 6 à 10 dB sous un tir long (FN FAL) : tous les tirs sont à
-11 LUFS ±1,5.

| Catégorie | Sons | Cible | Tolérance |
|---|---|---|---|
| `tir` | tous les `*_fire` | -11 LUFS-M | ±1,5 LU (écart max 3 LU entre armes) |
| `arme_zap` | `pap_zap_*` (couche des armes améliorées, drapeau `pap` en sommeil) | -19 | ±2 |
| `explosion` | explosions, grenade, chien qui explose | -10 | ±2 |
| `rechargement` | chargeurs, culasses, pompe, canons basculants, goupille, lancer, couteau | -19 | ±2,5 |
| `impact` | impacts de balles (béton, métal, bois), chair, tête, chute | -16 | ±2,5 |
| `zombie` | râles, cris, attaques, morts | -14 | ±2 |
| `zombie_bruitage` | pas traînants, sortie du sol, planches | -18 | ±2,5 |
| `chien` | grognements, aboiements, morsures, mort | -14 | ±2 |
| `joueur` | pas, respiration, douleur, à terre, plongeon | -18 | ±3 |
| `ritournelle` | manches, caisse au hasard, courant, menu, peluche leurre | -14 | ±2,5 |
| `musique` | menu, manche des chiens (intégré) | -20 LUFS-I | ±2 |
| `ambiance` | ambiances des cartes (intégré) | -24 LUFS-I | ±2 |
| `interface` | menus, marqueur de touche | -18 | ±3 |
| `decor` | le reste (portes, levier, téléporteur...) | -15 | ±3,5 |

Écarts voulus et documentés : clé `loud` d'une recette (pas du joueur -6,
pas des zombies -5, respiration -3, remontage de la peluche leurre -2,5) et `SfxRecipes.LEVEL_OFFSETS` pour les sons
procéduraux (tics d'interface, lampes en cascade). `sfx_import.gd --level`
(et `gen_audio*.gd` à chaque génération) ne retouche un son procédural que
s'il sort de la moitié de sa tolérance, pour garder son identité.
`tests/test_audio.gd` mesure **tous** les fichiers de `assets/audio/` et
échoue si un son sort de sa catégorie.

## Encore procéduraux (identité originale)

Musiques et ambiances, `round_start`/`round_end`,
`dog_round_start`/`dog_round_end`/`dog_round_music`,
caisse au hasard (`box_open`, `box_music`), téléporteur, courant (`power_on`, `lever`,
`lamp_on`), `heartbeat`,
`revive`, `hitmarker`, `zap` (piège électrique),
`zombie_fling`, interface. Candidats à
un remplacement futur : `door_open`, `purchase`, `denied`, `zombie_fling`.

## Mixage

- Bus : `Master` (limiteur `AudioEffectHardLimiter`, plafond -0,5 dB),
  `Music`, `SFX`, `UI`, `Voice` (`default_bus_layout.tres`). Un réglage de
  volume par bus dans les options (`Voice` : « VOIX DES PERSONNAGES »,
  `[audio] voice` dans `settings.cfg`).
- Voix des personnages : toutes les répliques (`VoxSystem`, 2D pour soi, 3D sur
  les coéquipiers) passent par le bus `Voice` (`Audio.track_voice`). Elles sont
  simplement mixées plus fort que le reste ; les autres sons ne baissent JAMAIS
  pendant une réplique (une baisse dénature le jeu, choix de l'utilisateur).
- Niveau des voix (fichiers à -19 dBFS sur la parole, `tools/voices`) :
  réplique du joueur local en 2D à +8 dB, coéquipiers en 3D à +10 dB
  (`unit_size` 10 m, audibles jusqu'à 50 m, filtre de distance léger
  9 kHz / -6 dB pour rester intelligibles). Le limiteur du `Master` absorbe
  les crêtes.
- Tirs du joueur local en 2D à -1 dB, tirs des autres joueurs et zombies en
  3D (`unit_size` 6 m, audibles jusqu'à 45 m, filtre passe-bas avec la
  distance).
- Armes améliorées (`WeaponAudio`, drapeau `pap` en sommeil depuis la
  suppression du Pack-a-Punch) : même détonation à peine plus grave (x0,95)
  doublée d'un arc électrique `pap_zap_1..3` à chaque tir.
- Impacts de balles : une seule détection de matière (`Fx.surface_of` /
  `Fx.surface_kind`, méta `surface` des collisions = clé de matériau du décor,
  sinon type d'objet) partagée par l'effet visuel et le son ;
  `Fx.impact` joue `impact_concrete|metal|wood_1..2` à -12 dB (terre =
  béton). Douilles : `shell.wav` au premier rebond.
- Santé basse : battement de cœur et respiration haletante
  (`player_breath_1..2`, un souffle tous les trois battements).
- Chiens (vague « meute ») : aboiements et grognements lointains à l'annonce
  (`DogRound.HOWL_*`), grognement depuis la cachette puis aboiement quand le
  chien jaillit, aboiement au bond puis morsure (`dog_bite_1..2`) 0,22 s plus
  tard ; mort : `dog_whine` et un impact de chair (`flesh_hit_*`).
- Voix des zombies (groupe `zombie`) plafonnées à 7 simultanées, pas traînants
  (groupe `zombie_step`) à 4 et seulement à moins de 14 m ; au-delà, la voix
  la plus lointaine est remplacée par une plus proche (`Audio._group_voice`).
- Rythme (`ZombieVoice`) : marcheurs un râle toutes les 4 à 9,5 s, coureurs
  toutes les 2,2 à 5 s, premier râle étalé après l'apparition, jamais deux
  fois la même variante de suite (8 râles, 4 cris de coureur, 4 attaques,
  4 morts, 4 pas).

## Fichiers importés

| Fichier | Source(s) (freesound.org, CC0 1.0) | Modifications |
|---|---|---|
| `m1911_fire.wav` | [Single Pistol Gunshot 3.wav](https://freesound.org/s/385811/) par morganpurkis | mono 44,1 kHz 16 bits, coupé à 0.75 s, égalisation, compression, saturation x1.6, réverbération d'intérieur 0.55 s, intensité -11 LUFS (tir) |
| `pistol_fire.wav` | [Single Pistol Gunshot 4.wav](https://freesound.org/s/391328/) par morganpurkis | mono 44,1 kHz 16 bits, hauteur x1.04, coupé à 0.70 s, égalisation, compression, saturation x1.6, réverbération d'intérieur 0.55 s, intensité -11 LUFS (tir) |
| `revolver_fire.wav` | [357 Magnum Revolver Gunshot with Tail](https://freesound.org/s/683175/) par Shark_Anthony | mono 44,1 kHz 16 bits, coupé à 1.50 s, égalisation, compression, saturation x1.8, réverbération d'intérieur 0.70 s, intensité -11 LUFS (tir) |
| `smg_fire.wav` | [A Glock handgun being shot 3x // punchy hollywood-esque sounding shots w/ airy forest reverb](https://freesound.org/s/855652/) par serøutōnin--deprivəd [0.00-0.60 s] | mono 44,1 kHz 16 bits, hauteur x1.10, coupé à 0.45 s, égalisation, compression, saturation x1.6, réverbération d'intérieur 0.40 s, intensité -11 LUFS (tir) |
| `mp40_fire.wav` | [A Glock handgun being shot 3x // punchy hollywood-esque sounding shots w/ airy forest reverb](https://freesound.org/s/855652/) par serøutōnin--deprivəd [1.60-2.20 s] | mono 44,1 kHz 16 bits, hauteur x0.88, coupé à 0.55 s, égalisation, compression, saturation x1.6, réverbération d'intérieur 0.45 s, intensité -11 LUFS (tir) |
| `pm63_fire.wav` | [A Glock handgun being shot 3x // punchy hollywood-esque sounding shots w/ airy forest reverb](https://freesound.org/s/855652/) par serøutōnin--deprivəd [3.17-3.80 s] | mono 44,1 kHz 16 bits, hauteur x1.20, coupé à 0.35 s, égalisation, compression, saturation x1.6, réverbération d'intérieur 0.35 s, intensité -11 LUFS (tir) |
| `spectre_fire.wav` | [Pistol Shot](https://freesound.org/s/163456/) par LeMudCrab | mono 44,1 kHz 16 bits, hauteur x1.10, coupé à 0.50 s, égalisation, compression, saturation x3.2, réverbération d'intérieur 0.40 s, intensité -11 LUFS (tir) |
| `ak74u_fire.wav` | [An AK-47 being shot // has distinctive metallic kalashnikov-esque report](https://freesound.org/s/855841/) par serøutōnin--deprivəd | mono 44,1 kHz 16 bits, hauteur x1.08, coupé à 0.55 s, égalisation, compression, saturation x1.6, réverbération d'intérieur 0.55 s, intensité -11 LUFS (tir) |
| `rifle_fire.wav` | [M4A1 Rifle Shot 10](https://freesound.org/s/854231/) par qubodup | mono 44,1 kHz 16 bits, coupé à 0.70 s, égalisation, compression, saturation x1.6, réverbération d'intérieur 0.55 s, intensité -11 LUFS (tir) |
| `galil_fire.wav` | [An AK-47 being shot // has distinctive metallic kalashnikov-esque report // punchy sounding](https://freesound.org/s/855842/) par serøutōnin--deprivəd | mono 44,1 kHz 16 bits, coupé à 0.75 s, égalisation, compression, saturation x1.6, réverbération d'intérieur 0.55 s, intensité -11 LUFS (tir) |
| `famas_fire.wav` | [M4A1 Rifle Shot 11](https://freesound.org/s/854232/) par qubodup | mono 44,1 kHz 16 bits, hauteur x1.06, coupé à 0.55 s, égalisation, compression, saturation x1.6, réverbération d'intérieur 0.55 s, intensité -11 LUFS (tir) |
| `aug_fire.wav` | [M4A1 Shot](https://freesound.org/s/854207/) par qubodup | mono 44,1 kHz 16 bits, hauteur x0.97, coupé à 0.70 s, égalisation, compression, saturation x1.6, réverbération d'intérieur 0.55 s, intensité -11 LUFS (tir) |
| `burst_fire.wav` | [M4A1 Rifle Shot 12](https://freesound.org/s/854233/) par qubodup | mono 44,1 kHz 16 bits, hauteur x1.03, coupé à 0.50 s, égalisation, compression, saturation x1.6, réverbération d'intérieur 0.45 s, intensité -11 LUFS (tir) |
| `g11_fire.wav` | [M4A1 Rifle Shot 4](https://freesound.org/s/854179/) par qubodup<br>[M4A1 Rifle Shot 10](https://freesound.org/s/854231/) par qubodup | mono 44,1 kHz 16 bits, hauteur x1.10, coupé à 0.45 s, hauteur x1.20, coupé à 0.40 s, 2 couches mixées, égalisation, compression, saturation x2.6, réverbération d'intérieur 0.45 s, intensité -11 LUFS (tir) |
| `m14_fire.wav` | [An automatic rifle being shot once // metallic and punchy sounding](https://freesound.org/s/855655/) par serøutōnin--deprivəd | mono 44,1 kHz 16 bits, hauteur x0.92, coupé à 0.95 s, égalisation, compression, saturation x1.8, réverbération d'intérieur 0.90 s, intensité -11 LUFS (tir) |
| `fnfal_fire.wav` | [An automatic rifle being shot once // punchy sounding](https://freesound.org/s/855654/) par serøutōnin--deprivəd | mono 44,1 kHz 16 bits, hauteur x0.94, coupé à 0.85 s, égalisation, compression, saturation x1.8, réverbération d'intérieur 0.90 s, intensité -11 LUFS (tir) |
| `lmg_fire.wav` | [An AK-47 being shot // has distinctive metallic kalashnikov-esque report // punchy sounding w/ distant trailing reverb](https://freesound.org/s/855843/) par serøutōnin--deprivəd | mono 44,1 kHz 16 bits, hauteur x0.93, coupé à 0.75 s, égalisation, compression, saturation x1.8, réverbération d'intérieur 0.90 s, intensité -11 LUFS (tir) |
| `hk21_fire.wav` | [AssaultRifle1.wav](https://freesound.org/s/404562/) par SuperPhat | mono 44,1 kHz 16 bits, hauteur x0.88, coupé à 0.80 s, égalisation, compression, saturation x1.8, réverbération d'intérieur 0.90 s, intensité -11 LUFS (tir) |
| `shotgun_fire.wav` | [shotgun-one-shot.wav](https://freesound.org/s/668353/) par DeltaCode<br>[Shotgun Shot 03.wav](https://freesound.org/s/473846/) par LilMati | mono 44,1 kHz 16 bits, coupé à 0.72 s, coupé à 1.30 s, 2 couches mixées, égalisation, compression, saturation x1.8, réverbération d'intérieur 0.90 s, intensité -11 LUFS (tir) |
| `spas_fire.wav` | [Shotgun Shot sfx](https://freesound.org/s/564480/) par lumikon [0.00-0.80 s] | mono 44,1 kHz 16 bits, coupé à 0.80 s, égalisation, compression, saturation x1.8, réverbération d'intérieur 0.90 s, intensité -11 LUFS (tir) |
| `hs10_fire.wav` | [Shotgun Shot](https://freesound.org/s/163455/) par LeMudCrab | mono 44,1 kHz 16 bits, hauteur x1.03, coupé à 0.80 s, égalisation, compression, saturation x1.8, réverbération d'intérieur 0.90 s, intensité -11 LUFS (tir) |
| `olympia_fire.wav` | [Shotgun 02.wav](https://freesound.org/s/544676/) par Clueless79 | mono 44,1 kHz 16 bits, coupé à 1.30 s, égalisation, compression, saturation x1.8, réverbération d'intérieur 0.90 s, intensité -11 LUFS (tir) |
| `sniper_fire.wav` | [FPS Sniper Shot Alt](https://freesound.org/s/816113/) par qubodup | mono 44,1 kHz 16 bits, coupé à 1.50 s, égalisation, compression, saturation x1.8, réverbération d'intérieur 1.00 s, intensité -11 LUFS (tir) |
| `dragunov_fire.wav` | [Sniper Rifle](https://freesound.org/s/514228/) par SuperPhat | mono 44,1 kHz 16 bits, coupé à 1.30 s, égalisation, compression, saturation x1.8, réverbération d'intérieur 0.90 s, intensité -11 LUFS (tir) |
| `launcher_fire.wav` | [M203 Grenade Launcher 1.flac](https://freesound.org/s/162402/) par qubodup | mono 44,1 kHz 16 bits, coupé à 0.60 s, égalisation, compression, saturation x1.3, réverbération d'intérieur 0.55 s, intensité -11 LUFS (tir) |
| `rocket_fire.wav` | [Rocket Launch](https://freesound.org/s/521377/) par Jarusca | mono 44,1 kHz 16 bits, coupé à 1.40 s, égalisation, compression, saturation x1.3, réverbération d'intérieur 0.90 s, intensité -11 LUFS (tir) |
| `explosion.wav` | [Explosion008.wav](https://freesound.org/s/337298/) par klangfabrik<br>[large explosion 1](https://freesound.org/s/482993/) par V-ktor | mono 44,1 kHz 16 bits, coupé à 2.50 s, coupé à 2.80 s, 2 couches mixées, égalisation, compression, saturation x1.4, réverbération d'intérieur 1.20 s, intensité -10 LUFS (explosion) |
| `frag_explode.wav` | [Grenade Explosion SFX (medium-sized, meaty, realistic)](https://freesound.org/s/609587/) par unfa | mono 44,1 kHz 16 bits, coupé à 3.00 s, égalisation, compression, saturation x1.4, réverbération d'intérieur 1.20 s, intensité -10 LUFS (explosion) |
| `mag_out.wav` | [Assault Rifle Reload](https://freesound.org/s/815879/) par qubodup [0.00-0.45 s] | mono 44,1 kHz 16 bits, égalisation, compression, réverbération d'intérieur 0.25 s, intensité -19 LUFS (rechargement) |
| `mag_in.wav` | [Assault Rifle Reload](https://freesound.org/s/815879/) par qubodup [0.55-1.00 s] | mono 44,1 kHz 16 bits, égalisation, compression, réverbération d'intérieur 0.25 s, intensité -19 LUFS (rechargement) |
| `slide.wav` | [Assault Rifle Reload](https://freesound.org/s/815879/) par qubodup [1.30-1.87 s] | mono 44,1 kHz 16 bits, égalisation, compression, réverbération d'intérieur 0.25 s, intensité -19 LUFS (rechargement) |
| `bolt.wav` | [Mosin Nagant Bolt Action Cycle](https://freesound.org/s/370345/) par Zott820 [0.05-1.40 s] | mono 44,1 kHz 16 bits, égalisation, compression, réverbération d'intérieur 0.25 s, intensité -19 LUFS (rechargement) |
| `pump.wav` | [Remington 870 12 gauge shotgun pump racking cha chock](https://freesound.org/s/755495/) par TotallyPhilip [0.06-0.60 s] | mono 44,1 kHz 16 bits, égalisation, compression, réverbération d'intérieur 0.25 s, intensité -19 LUFS (rechargement) |
| `shell_in.wav` | [Shotgun Shell Load](https://freesound.org/s/500293/) par Bratish [0.00-0.40 s] | mono 44,1 kHz 16 bits, égalisation, compression, réverbération d'intérieur 0.25 s, intensité -19 LUFS (rechargement) |
| `shell.wav` | [22lr Revolver ejecting bullets from cylinder](https://freesound.org/s/693125/) par serøutōnin--deprivəd [0.00-0.66 s] | mono 44,1 kHz 16 bits, égalisation, compression, réverbération d'intérieur 0.25 s, intensité -19 LUFS (rechargement) |
| `dry_fire.wav` | [9mm Handgun Being Dry Fired](https://freesound.org/s/674568/) par serøutōnin--deprivəd | mono 44,1 kHz 16 bits, égalisation, compression, réverbération d'intérieur 0.25 s, intensité -19 LUFS (rechargement) |
| `weapon_switch.wav` | [A pistol being moved around and handled w/ foley](https://freesound.org/s/725400/) par serøutōnin--deprivəd [4.95-5.36 s] | mono 44,1 kHz 16 bits, égalisation, compression, réverbération d'intérieur 0.25 s, intensité -19 LUFS (rechargement) |
| `knife_swing.wav` | [Small Knife Whoosh.wav](https://freesound.org/s/389690/) par Shamewap | mono 44,1 kHz 16 bits, coupé à 0.50 s, égalisation, compression, réverbération d'intérieur 0.15 s, intensité -19 LUFS (rechargement) |
| `knife_hit.wav` | [body_hit.wav](https://freesound.org/s/276600/) par insanity54 | mono 44,1 kHz 16 bits, coupé à 0.50 s, égalisation, compression, réverbération d'intérieur 0.30 s, intensité -16 LUFS (impact) |
| `knife_flesh.wav` | [Flesh Stabs and Slashes 2](https://freesound.org/s/635049/) par sillygrizzlies [3.70-4.32 s] | mono 44,1 kHz 16 bits, égalisation, compression, réverbération d'intérieur 0.30 s, intensité -16 LUFS (impact) |
| `flesh_hit_1.wav` | [VisceralBulletImpacts.wav](https://freesound.org/s/423301/) par u1769092 [0.00-0.30 s] | mono 44,1 kHz 16 bits, égalisation, compression, réverbération d'intérieur 0.30 s, intensité -16 LUFS (impact) |
| `flesh_hit_2.wav` | [VisceralBulletImpacts.wav](https://freesound.org/s/423301/) par u1769092 [0.31-0.65 s] | mono 44,1 kHz 16 bits, égalisation, compression, réverbération d'intérieur 0.30 s, intensité -16 LUFS (impact) |
| `flesh_hit_3.wav` | [VisceralBulletImpacts.wav](https://freesound.org/s/423301/) par u1769092 [1.39-1.72 s] | mono 44,1 kHz 16 bits, égalisation, compression, réverbération d'intérieur 0.30 s, intensité -16 LUFS (impact) |
| `headshot.wav` | [Headshot.wav](https://freesound.org/s/511194/) par Pablobd<br>[VisceralBulletImpacts.wav](https://freesound.org/s/423301/) par u1769092 [0.66-1.33 s] | mono 44,1 kHz 16 bits, coupé à 0.80 s, 2 couches mixées, égalisation, compression, réverbération d'intérieur 0.30 s, intensité -16 LUFS (impact) |
| `body_fall.wav` | [BODY FALL - V HVY - DIRT](https://freesound.org/s/504626/) par leonelmail | mono 44,1 kHz 16 bits, égalisation, compression, réverbération d'intérieur 0.30 s, intensité -16 LUFS (impact) |
| `emerge.wav` | [Shovelling Dirt.mp3](https://freesound.org/s/415303/) par Yin_Yang_Jake007 [6.95-7.45 s]<br>[Shovel_dirt.wav](https://freesound.org/s/353907/) par dr19 [0.00-0.45 s]<br>[BODY FALL - V HVY - DIRT](https://freesound.org/s/504626/) par leonelmail [0.30-1.20 s] | mono 44,1 kHz 16 bits, 3 couches mixées, égalisation, compression, réverbération d'intérieur 0.30 s, intensité -18 LUFS (zombie_bruitage) |
| `barricade_tear_1.wav` | [Tearing pieces of wood](https://freesound.org/s/628398/) par melle_teich [7.10-7.68 s] | mono 44,1 kHz 16 bits, égalisation, compression, réverbération d'intérieur 0.30 s, intensité -18 LUFS (zombie_bruitage) |
| `barricade_tear_2.wav` | [Tearing pieces of wood](https://freesound.org/s/628398/) par melle_teich [14.50-15.10 s] | mono 44,1 kHz 16 bits, égalisation, compression, réverbération d'intérieur 0.30 s, intensité -18 LUFS (zombie_bruitage) |
| `barricade_tear_3.wav` | [Tearing pieces of wood](https://freesound.org/s/628398/) par melle_teich [18.08-19.00 s] | mono 44,1 kHz 16 bits, égalisation, compression, réverbération d'intérieur 0.30 s, intensité -18 LUFS (zombie_bruitage) |
| `barricade_slam_1.wav` | [door wood hits impacts small break through clumsy metal thing dall.wav](https://freesound.org/s/450793/) par kyles [0.33-0.68 s] | mono 44,1 kHz 16 bits, égalisation, compression, réverbération d'intérieur 0.30 s, intensité -18 LUFS (zombie_bruitage) |
| `barricade_slam_2.wav` | [door wood hits impacts small break through clumsy metal thing dall.wav](https://freesound.org/s/450793/) par kyles [1.17-1.55 s] | mono 44,1 kHz 16 bits, égalisation, compression, réverbération d'intérieur 0.30 s, intensité -18 LUFS (zombie_bruitage) |
| `zombie_groan_1.wav` | [Zombie 1](https://freesound.org/s/163440/) par Under7dude | mono 44,1 kHz 16 bits, hauteur x0.95, égalisation, compression, saturation x1.1, réverbération d'intérieur 0.35 s, intensité -14 LUFS (zombie) |
| `zombie_groan_2.wav` | [Zombie 2](https://freesound.org/s/163439/) par Under7dude | mono 44,1 kHz 16 bits, hauteur x0.97, égalisation, compression, saturation x1.1, réverbération d'intérieur 0.35 s, intensité -14 LUFS (zombie) |
| `zombie_groan_3.wav` | [Zombie Growl 5.wav](https://freesound.org/s/555417/) par tonsil5 | mono 44,1 kHz 16 bits, coupé à 2.20 s, égalisation, compression, saturation x1.1, réverbération d'intérieur 0.35 s, intensité -14 LUFS (zombie) |
| `zombie_groan_4.wav` | [Zombie Growl 2.wav](https://freesound.org/s/555415/) par tonsil5 | mono 44,1 kHz 16 bits, coupé à 2.40 s, égalisation, compression, saturation x1.1, réverbération d'intérieur 0.35 s, intensité -14 LUFS (zombie) |
| `zombie_groan_5.wav` | [SZ_Zombies_01.wav](https://freesound.org/s/196721/) par PaulMorek | mono 44,1 kHz 16 bits, hauteur x0.94, coupé à 2.80 s, égalisation, compression, saturation x1.1, réverbération d'intérieur 0.35 s, intensité -14 LUFS (zombie) |
| `zombie_groan_6.wav` | [Zombie Pack(Clean Record)](https://freesound.org/s/393749/) par haratman [3.65-4.60 s] | mono 44,1 kHz 16 bits, hauteur x0.92, égalisation, compression, saturation x1.1, réverbération d'intérieur 0.35 s, intensité -14 LUFS (zombie) |
| `zombie_groan_7.wav` | [Zombie Pack(Clean Record)](https://freesound.org/s/393749/) par haratman [9.25-10.20 s] | mono 44,1 kHz 16 bits, hauteur x0.90, égalisation, compression, saturation x1.1, réverbération d'intérieur 0.35 s, intensité -14 LUFS (zombie) |
| `zombie_groan_8.wav` | [zombie_moan.mp3](https://freesound.org/s/346626/) par bigmonmulgrew | mono 44,1 kHz 16 bits, hauteur x0.93, égalisation, compression, saturation x1.1, réverbération d'intérieur 0.35 s, intensité -14 LUFS (zombie) |
| `zombie_sprint_1.wav` | [Zombie Roar 5](https://freesound.org/s/144005/) par ArriGD | mono 44,1 kHz 16 bits, égalisation, compression, saturation x1.1, réverbération d'intérieur 0.35 s, intensité -14 LUFS (zombie) |
| `zombie_sprint_2.wav` | [Zombie Roar 3](https://freesound.org/s/143999/) par ArriGD | mono 44,1 kHz 16 bits, égalisation, compression, saturation x1.1, réverbération d'intérieur 0.35 s, intensité -14 LUFS (zombie) |
| `zombie_sprint_3.wav` | [Zombie Roar 8](https://freesound.org/s/144002/) par ArriGD | mono 44,1 kHz 16 bits, égalisation, compression, saturation x1.1, réverbération d'intérieur 0.35 s, intensité -14 LUFS (zombie) |
| `zombie_sprint_4.wav` | [Zombie Growl 3.wav](https://freesound.org/s/555414/) par tonsil5 | mono 44,1 kHz 16 bits, hauteur x1.05, coupé à 1.60 s, égalisation, compression, saturation x1.1, réverbération d'intérieur 0.35 s, intensité -14 LUFS (zombie) |
| `zombie_attack_1.wav` | [Zombie Hit 1.wav](https://freesound.org/s/555420/) par tonsil5<br>[Small Knife Whoosh.wav](https://freesound.org/s/389690/) par Shamewap | mono 44,1 kHz 16 bits, hauteur x0.80, coupé à 0.40 s, 2 couches mixées, égalisation, compression, saturation x1.1, réverbération d'intérieur 0.35 s, intensité -14 LUFS (zombie) |
| `zombie_attack_2.wav` | [Zombie Hit](https://freesound.org/s/163447/) par Under7dude<br>[Small Knife Whoosh.wav](https://freesound.org/s/389690/) par Shamewap | mono 44,1 kHz 16 bits, hauteur x0.75, coupé à 0.40 s, 2 couches mixées, égalisation, compression, saturation x1.1, réverbération d'intérieur 0.35 s, intensité -14 LUFS (zombie) |
| `zombie_attack_3.wav` | [Zombie Roar 4](https://freesound.org/s/143998/) par ArriGD<br>[Small Knife Whoosh.wav](https://freesound.org/s/389690/) par Shamewap | mono 44,1 kHz 16 bits, hauteur x0.85, coupé à 0.40 s, 2 couches mixées, égalisation, compression, saturation x1.1, réverbération d'intérieur 0.35 s, intensité -14 LUFS (zombie) |
| `zombie_attack_4.wav` | [Zombie Pack(Clean Record)](https://freesound.org/s/393749/) par haratman [17.58-18.10 s]<br>[Small Knife Whoosh.wav](https://freesound.org/s/389690/) par Shamewap | mono 44,1 kHz 16 bits, hauteur x0.92, hauteur x0.80, coupé à 0.40 s, 2 couches mixées, égalisation, compression, saturation x1.1, réverbération d'intérieur 0.35 s, intensité -14 LUFS (zombie) |
| `zombie_death_1.wav` | [Zombie Death 1.wav](https://freesound.org/s/555412/) par tonsil5 | mono 44,1 kHz 16 bits, hauteur x0.95, égalisation, compression, saturation x1.1, réverbération d'intérieur 0.35 s, intensité -14 LUFS (zombie) |
| `zombie_death_2.wav` | [Zombie Death 2.wav](https://freesound.org/s/555411/) par tonsil5 | mono 44,1 kHz 16 bits, hauteur x0.95, égalisation, compression, saturation x1.1, réverbération d'intérieur 0.35 s, intensité -14 LUFS (zombie) |
| `zombie_death_3.wav` | [Zombie Pain 2.wav](https://freesound.org/s/555423/) par tonsil5 | mono 44,1 kHz 16 bits, hauteur x0.93, égalisation, compression, saturation x1.1, réverbération d'intérieur 0.35 s, intensité -14 LUFS (zombie) |
| `zombie_death_4.wav` | [Zombie Pack(Clean Record)](https://freesound.org/s/393749/) par haratman [22.00-23.80 s] | mono 44,1 kHz 16 bits, hauteur x0.92, égalisation, compression, saturation x1.1, réverbération d'intérieur 0.35 s, intensité -14 LUFS (zombie) |
| `zombie_step_1.wav` | [Walking - Dragging feet - heavy footsteps - eerie - boots](https://freesound.org/s/741627/) par GoatsheadCastle [9.12-9.52 s] | mono 44,1 kHz 16 bits, égalisation, compression, réverbération d'intérieur 0.30 s, intensité -23 LUFS (zombie_bruitage) |
| `zombie_step_2.wav` | [Walking - Dragging feet - heavy footsteps - eerie - boots](https://freesound.org/s/741627/) par GoatsheadCastle [9.58-10.00 s] | mono 44,1 kHz 16 bits, égalisation, compression, réverbération d'intérieur 0.30 s, intensité -23 LUFS (zombie_bruitage) |
| `zombie_step_3.wav` | [Walking - Dragging feet - heavy footsteps - eerie - boots](https://freesound.org/s/741627/) par GoatsheadCastle [10.64-11.10 s] | mono 44,1 kHz 16 bits, égalisation, compression, réverbération d'intérieur 0.30 s, intensité -23 LUFS (zombie_bruitage) |
| `zombie_step_4.wav` | [Walking - Dragging feet - heavy footsteps - eerie - boots](https://freesound.org/s/741627/) par GoatsheadCastle [11.28-11.75 s] | mono 44,1 kHz 16 bits, égalisation, compression, réverbération d'intérieur 0.30 s, intensité -23 LUFS (zombie_bruitage) |
| `break_open.wav` | [Revolver Reload Break 2](https://freesound.org/s/722902/) par tkane0512 [0.05-0.60 s]<br>[Clean Revolver Reload](https://freesound.org/s/177863/) par Dredile [0.26-0.66 s] | mono 44,1 kHz 16 bits, hauteur x0.85, hauteur x0.90, 2 couches mixées, égalisation, compression, réverbération d'intérieur 0.25 s, intensité -19 LUFS (rechargement) |
| `break_close.wav` | [shotgun close.flac](https://freesound.org/s/108794/) par CeebFrack<br>[Revolver Reload Break 2](https://freesound.org/s/722902/) par tkane0512 [2.20-2.58 s] | mono 44,1 kHz 16 bits, hauteur x0.85, 2 couches mixées, égalisation, compression, réverbération d'intérieur 0.25 s, intensité -19 LUFS (rechargement) |
| `impact_concrete_1.wav` | [VSH-38-pop-concrete wall-med.wav](https://freesound.org/s/369138/) par newagesoup<br>[Ricochet 2.wav](https://freesound.org/s/392975/) par morganpurkis | mono 44,1 kHz 16 bits, coupé à 0.45 s, coupé à 0.30 s, 2 couches mixées, égalisation, compression, saturation x1.3, réverbération d'intérieur 0.30 s, intensité -16 LUFS (impact) |
| `impact_concrete_2.wav` | [Hard Impact on Concrete](https://freesound.org/s/683774/) par Elements-Library [4.72-5.30 s]<br>[Concrete Hit](https://freesound.org/s/321477/) par dslrguide | mono 44,1 kHz 16 bits, hauteur x1.10, coupé à 0.40 s, 2 couches mixées, égalisation, compression, saturation x1.3, réverbération d'intérieur 0.30 s, intensité -16 LUFS (impact) |
| `impact_metal_1.wav` | [Foley bullet hit metal 02.wav](https://freesound.org/s/182263/) par martian [0.05-0.60 s]<br>[Ricochet 2.wav](https://freesound.org/s/392975/) par morganpurkis | mono 44,1 kHz 16 bits, coupé à 0.45 s, 2 couches mixées, égalisation, compression, saturation x1.3, réverbération d'intérieur 0.30 s, intensité -16 LUFS (impact) |
| `impact_metal_2.wav` | [Foley bullet hit metal 02.wav](https://freesound.org/s/182263/) par martian [7.22-7.75 s]<br>[Metal Canister Impact Hard](https://freesound.org/s/650573/) par h2p34 [0.00-0.34 s] | mono 44,1 kHz 16 bits, hauteur x1.30, 2 couches mixées, égalisation, compression, saturation x1.3, réverbération d'intérieur 0.30 s, intensité -16 LUFS (impact) |
| `impact_wood_1.wav` | [Wood panel board debris sharp impact hard](https://freesound.org/s/400654/) par LampEight [0.00-0.50 s]<br>[snd_ImpactSmallWood01.wav](https://freesound.org/s/381617/) par dorian.mastin | mono 44,1 kHz 16 bits, coupé à 0.40 s, 2 couches mixées, égalisation, compression, saturation x1.3, réverbération d'intérieur 0.30 s, intensité -16 LUFS (impact) |
| `impact_wood_2.wav` | [Wood panel board debris sharp impact hard](https://freesound.org/s/400654/) par LampEight [7.00-7.60 s]<br>[Single Rock hitting wood 4.wav](https://freesound.org/s/319227/) par worthahep88 | mono 44,1 kHz 16 bits, coupé à 0.35 s, 2 couches mixées, égalisation, compression, saturation x1.3, réverbération d'intérieur 0.30 s, intensité -16 LUFS (impact) |
| `grenade_pin.wav` | [small moving metallic part](https://freesound.org/s/725813/) par F3ather [6.55-6.90 s]<br>[Metallic Clink 3.wav](https://freesound.org/s/682154/) par HenKonen | mono 44,1 kHz 16 bits, coupé à 0.45 s, 2 couches mixées, égalisation, compression, réverbération d'intérieur 0.25 s, intensité -19 LUFS (rechargement) |
| `grenade_throw.wav` | [Throwing / Whip Effect](https://freesound.org/s/346373/) par denao270 | mono 44,1 kHz 16 bits, égalisation, compression, réverbération d'intérieur 0.25 s, intensité -19 LUFS (rechargement) |
| `grenade_bounce.wav` | [Metal Canister Impact Hard](https://freesound.org/s/650573/) par h2p34 [0.43-0.80 s]<br>[Metallic Clink 3.wav](https://freesound.org/s/682154/) par HenKonen | mono 44,1 kHz 16 bits, hauteur x1.25, coupé à 0.35 s, 2 couches mixées, égalisation, compression, réverbération d'intérieur 0.30 s, intensité -16 LUFS (impact) |
| `monkey_wind.wav` | [Wind-up sound](https://freesound.org/s/445966/) par Breviceps | mono 44,1 kHz 16 bits, égalisation, compression, réverbération d'intérieur 0.25 s, intensité -22 LUFS (rechargement) |
| `monkey_bounce.wav` | [CanBounce 2.wav](https://freesound.org/s/92622/) par nigelcoop [0.50-0.95 s] | mono 44,1 kHz 16 bits, hauteur x1.15, égalisation, compression, réverbération d'intérieur 0.30 s, intensité -16 LUFS (impact) |
| `monkey_music.wav` | air original procédural (`SynthStems.monkey_tune`)<br>[cymbal splash hit nearby chinese opera in park.flac](https://freesound.org/s/452400/) par kyles | mono 44,1 kHz 16 bits, coupé à 0.38 s, 2 couches mixées, égalisation, compression, intensité -14 LUFS (ritournelle) |
| `dog_growl_1.wav` | [Dog Growl - Beast / Creature](https://freesound.org/s/404920/) par coldvet [31.70-33.00 s] | mono 44,1 kHz 16 bits, hauteur x0.90, égalisation, compression, saturation x1.5, réverbération d'intérieur 0.35 s, intensité -14 LUFS (chien) |
| `dog_growl_2.wav` | [Dog Growl - Beast / Creature](https://freesound.org/s/404920/) par coldvet [19.80-21.60 s] | mono 44,1 kHz 16 bits, hauteur x0.88, égalisation, compression, saturation x1.5, réverbération d'intérieur 0.35 s, intensité -14 LUFS (chien) |
| `dog_growl_3.wav` | [Dog Growling Snarling Grumbling](https://freesound.org/s/122183/) par qubodup [23.95-25.20 s] | mono 44,1 kHz 16 bits, hauteur x0.80, égalisation, compression, saturation x1.5, réverbération d'intérieur 0.35 s, intensité -14 LUFS (chien) |
| `dog_bark_1.wav` | [Aggressive Barking Dog - 1.wav](https://freesound.org/s/483176/) par SpaceJoe [0.55-1.22 s] | mono 44,1 kHz 16 bits, hauteur x0.82, égalisation, compression, saturation x1.5, réverbération d'intérieur 0.35 s, intensité -14 LUFS (chien) |
| `dog_bark_2.wav` | [Large Dog Aggressive Bark.mp3](https://freesound.org/s/619045/) par mrrap4food [3.58-4.50 s] | mono 44,1 kHz 16 bits, hauteur x0.85, égalisation, compression, saturation x1.5, réverbération d'intérieur 0.35 s, intensité -14 LUFS (chien) |
| `dog_bite_1.wav` | [Dog Teeth Clattering Clicking](https://freesound.org/s/841350/) par qubodup [0.50-0.98 s]<br>[Flesh Stabs and Slashes 2](https://freesound.org/s/635049/) par sillygrizzlies [3.70-4.00 s]<br>[Dog Growling Snarling Grumbling](https://freesound.org/s/122183/) par qubodup [4.39-4.85 s] | mono 44,1 kHz 16 bits, hauteur x0.85, hauteur x0.80, 3 couches mixées, égalisation, compression, saturation x1.2, réverbération d'intérieur 0.35 s, intensité -14 LUFS (chien) |
| `dog_bite_2.wav` | [Dog Teeth Clattering Clicking](https://freesound.org/s/841350/) par qubodup [1.72-2.10 s]<br>[VisceralBulletImpacts.wav](https://freesound.org/s/423301/) par u1769092 [0.31-0.60 s]<br>[Dog Growling Snarling Grumbling](https://freesound.org/s/122183/) par qubodup [5.40-5.84 s] | mono 44,1 kHz 16 bits, hauteur x0.85, hauteur x0.80, 3 couches mixées, égalisation, compression, saturation x1.2, réverbération d'intérieur 0.35 s, intensité -14 LUFS (chien) |
| `dog_whine.wav` | [Dog death cry - video game quality / bad-ish quality](https://freesound.org/s/724927/) par greyfeather | mono 44,1 kHz 16 bits, hauteur x0.82, égalisation, compression, saturation x1.5, réverbération d'intérieur 0.35 s, intensité -14 LUFS (chien) |
| `footstep_1.wav` | [Footsteps boots.wav](https://freesound.org/s/392483/) par gpag1 [0.00-0.25 s] | mono 44,1 kHz 16 bits, égalisation, compression, réverbération d'intérieur 0.30 s, intensité -24 LUFS (joueur) |
| `footstep_2.wav` | [Footsteps boots.wav](https://freesound.org/s/392483/) par gpag1 [0.25-0.52 s] | mono 44,1 kHz 16 bits, égalisation, compression, réverbération d'intérieur 0.30 s, intensité -24 LUFS (joueur) |
| `footstep_3.wav` | [Footsteps boots.wav](https://freesound.org/s/392483/) par gpag1 [1.04-1.29 s] | mono 44,1 kHz 16 bits, égalisation, compression, réverbération d'intérieur 0.30 s, intensité -24 LUFS (joueur) |
| `footstep_4.wav` | [Footsteps boots.wav](https://freesound.org/s/392483/) par gpag1 [1.55-1.80 s] | mono 44,1 kHz 16 bits, égalisation, compression, réverbération d'intérieur 0.30 s, intensité -24 LUFS (joueur) |
| `player_breath_1.wav` | [heavy_breathing_1.wav](https://freesound.org/s/386573/) par ShaneF91 [1.55-2.65 s] | mono 44,1 kHz 16 bits, égalisation, compression, réverbération d'intérieur 0.25 s, intensité -21 LUFS (joueur) |
| `player_breath_2.wav` | [heavy_breathing_1.wav](https://freesound.org/s/386573/) par ShaneF91 [5.55-6.62 s] | mono 44,1 kHz 16 bits, égalisation, compression, réverbération d'intérieur 0.25 s, intensité -21 LUFS (joueur) |
| `player_hurt_1.wav` | [Voice_AdultMale_PainGrunts_09.wav](https://freesound.org/s/547209/) par MrFossy | mono 44,1 kHz 16 bits, égalisation, compression, réverbération d'intérieur 0.25 s, intensité -18 LUFS (joueur) |
| `player_hurt_2.wav` | [Male Grunting In Pain](https://freesound.org/s/464486/) par elynch0901 | mono 44,1 kHz 16 bits, égalisation, compression, réverbération d'intérieur 0.25 s, intensité -18 LUFS (joueur) |
| `player_down.wav` | [Grunt2 - Death Pain.wav](https://freesound.org/s/416838/) par tonsil5<br>[Body fall.wav](https://freesound.org/s/417994/) par DylanTheFish | mono 44,1 kHz 16 bits, 2 couches mixées, égalisation, compression, réverbération d'intérieur 0.80 s, intensité -18 LUFS (joueur) |
| `dive_land.wav` | [Body fall.wav](https://freesound.org/s/417994/) par DylanTheFish<br>[Body Fall Over.wav](https://freesound.org/s/82027/) par raubana | mono 44,1 kHz 16 bits, coupé à 1.00 s, 2 couches mixées, égalisation, compression, réverbération d'intérieur 0.30 s, intensité -18 LUFS (joueur) |
| `pap_zap_1.wav` | [Electric zap.wav](https://freesound.org/s/512471/) par michael_grinnell | mono 44,1 kHz 16 bits, égalisation, compression, réverbération d'intérieur 0.25 s, intensité -19 LUFS (arme_zap) |
| `pap_zap_2.wav` | [zap.mp3](https://freesound.org/s/143565/) par YvesSch | mono 44,1 kHz 16 bits, coupé à 0.30 s, égalisation, compression, réverbération d'intérieur 0.25 s, intensité -19 LUFS (arme_zap) |
| `pap_zap_3.wav` | [ELECTRIC_ZAP_001.wav](https://freesound.org/s/136542/) par JoelAudio | mono 44,1 kHz 16 bits, coupé à 0.28 s, égalisation, compression, réverbération d'intérieur 0.25 s, intensité -19 LUFS (arme_zap) |
