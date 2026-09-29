# Assets externes (sons)

Les graphismes du jeu sont 100 % procéduraux (les modèles 3D de
`assets/models/` sont produits par nos scripts Blender, voir
`tools/blender/`, aucun modèle téléchargé ; le lettrage des machines
d'atouts utilise la police intégrée de Blender, licence libre ; les objets de la salle
de théâtre, de la scène, des coulisses et de la cabine de projection de KINO V2, `assets/models/kino/`, sont
générés par `tools/blender/props/kino_theater.py`, emblèmes et enseignes originaux). La plupart des bruitages
proviennent d'enregistrements **libres de droits** retravaillés pour le jeu ;
l'identité sonore originale reste synthétisée par `tools/gen_audio.gd` et
`tools/gen_audio_menu.gd` : musiques et ambiances, ritournelles des atouts,
début et fin de manche, annonces des bonus, boîte mystère, Pack-a-Punch,
téléporteur, arme à rayons (CLAUDE-RAY, volontairement synthétique),
interface. L'air du singe-tambour est lui aussi original (procédural,
`tools/audio/synth_stems.gd`) ; seules ses cymbales sont enregistrées.

## Voix des personnages

Les répliques de Callahan, Orlov, Arakawa et Weissmann (textes originaux,
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
  (`--sample 3` pour un échantillon d'écoute ; reprend là où elle s'est arrêtée).

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
  temps (`times`, ex. les cymbales sur les temps de l'air du singe) ou une
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
| `arme_merveille` | `ray_fire`, `thunder_fire` | -10 | ±2 |
| `arme_zap` | `pap_zap_*` (couche Pack-a-Punch) | -19 | ±2 |
| `explosion` | explosions, grenade, nuke, NOVA, chien qui explose | -10 | ±2 |
| `rechargement` | chargeurs, culasses, pompe, canons basculants, goupille, lancer, couteau | -19 | ±2,5 |
| `impact` | impacts de balles (béton, métal, bois), chair, tête, chute | -16 | ±2,5 |
| `zombie` | râles, cris, attaques, morts | -14 | ±2 |
| `zombie_bruitage` | pas traînants, sortie du sol, planches | -18 | ±2,5 |
| `chien` | grognements, aboiements, morsures, mort | -14 | ±2 |
| `joueur` | pas, respiration, douleur, à terre, plongeon | -18 | ±3 |
| `annonce` | annonces des bonus | -12 | ±2 |
| `ritournelle` | ritournelles des atouts, manches, boîte, Pack-a-Punch, singe | -14 | ±2,5 |
| `musique` | menu, manche des chiens, soldes, bonus (intégré) | -20 LUFS-I | ±2 |
| `ambiance` | ambiances des cartes (intégré) | -24 LUFS-I | ±2 |
| `interface` | menus, marqueur de touche | -18 | ±3 |
| `decor` | le reste (portes, levier, téléporteur...) | -15 | ±3,5 |

Écarts voulus et documentés : clé `loud` d'une recette (pas du joueur -6,
pas des zombies -5, FAUCHEUSE -5 car 20 coups/s se chevauchent, respiration
-3, remontage du singe -2,5) et `SfxRecipes.LEVEL_OFFSETS` pour les sons
procéduraux (tics d'interface, lampes en cascade). `sfx_import.gd --level`
(et `gen_audio*.gd` à chaque génération) ne retouche un son procédural que
s'il sort de la moitié de sa tolérance, pour garder son identité.
`tests/test_audio.gd` mesure **tous** les fichiers de `assets/audio/` et
échoue si un son sort de sa catégorie.

## Encore procéduraux (identité originale)

Musiques et ambiances, `round_start`/`round_end`, ritournelles des atouts,
`dog_round_start`/`dog_round_end`/`dog_round_music`, annonces des bonus,
boîte mystère, Pack-a-Punch, téléporteur, courant (`power_on`, `lever`,
`lamp_on`), `ray_fire` (caractère « rayon » synthétique), `heartbeat`,
`revive`, `hitmarker`, `zap` (piège électrique), `dog_bolt`/`dog_spawn`/
`dog_prespawn` (foudre d'apparition), `zombie_fling`, interface. Candidats à
un remplacement futur : `door_open`, `purchase`, `denied`, `zombie_fling`.

## Mixage

- Bus : `Master` (limiteur `AudioEffectHardLimiter`, plafond -0,5 dB),
  `Music`, `SFX`, `UI`, `Voice` (`default_bus_layout.tres`). Un réglage de
  volume par bus dans les options (`Voice` : « VOIX DES PERSONNAGES »,
  `[audio] voice` dans `settings.cfg`).
- Voix des personnages devant le reste, comme dans BO1 : toutes les répliques
  (`VoxSystem`, 2D pour soi, 3D sur les coéquipiers) passent par le bus
  `Voice` (`Audio.track_voice`). Pendant une réplique, l'effet `Duck`
  (`AudioEffectAmplify` piloté par `Audio._process`) baisse `SFX` (zombies,
  armes, machines) de 7 dB et `Music` de 4 dB, attaque 20 ms, retour 300 ms
  (constante de temps) ; l'interface n'est jamais baissée. Baisse pilotée par
  le code plutôt qu'un compresseur en sidechain : profondeur exacte, et
  déclenchée par les seules voix (les tirs ne font jamais pomper). Voix d'un
  coéquipier : baisse complète jusqu'à 10 m, nulle au-delà de 30 m ; voix
  réglées à 0 % : aucune baisse.
- Niveau des voix (fichiers à -19 dBFS sur la parole, `tools/voices`) :
  réplique du joueur local en 2D à +2 dB, coéquipiers en 3D à +6 dB
  (`unit_size` 10 m, audibles jusqu'à 50 m, filtre de distance léger
  9 kHz / -6 dB pour rester intelligibles). Le limiteur du `Master` absorbe
  les crêtes.
- Tirs du joueur local en 2D à -1 dB, tirs des autres joueurs et zombies en
  3D (`unit_size` 6 m, audibles jusqu'à 45 m, filtre passe-bas avec la
  distance).
- Armes Pack-a-Punchées (`WeaponAudio`) : même détonation à peine plus grave
  (x0,95) doublée d'un arc électrique `pap_zap_1..3` à chaque tir, comme
  dans BO1 (plus de simple ralenti à x0,8) ; pas de zap ajouté aux armes
  merveilles.
- Impacts de balles : une seule détection de matière (`Fx.surface_of` /
  `Fx.surface_kind`, méta `surface` des collisions = clé de matériau du décor,
  sinon type d'objet) partagée par l'effet visuel et le son ;
  `Fx.impact` joue `impact_concrete|metal|wood_1..2` à -12 dB (terre =
  béton). Douilles : `shell.wav` au premier rebond.
- Santé basse : battement de cœur et respiration haletante
  (`player_breath_1..2`, un souffle tous les trois battements).
- Chiens de l'enfer : aboiement au bond puis morsure (`dog_bite_1..2`)
  0,22 s plus tard.
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
| `bowie_draw.wav` | [UnsheathingSmallKnife.wav](https://freesound.org/s/466216/) par Harrisando | mono 44,1 kHz 16 bits, coupé à 1.00 s, égalisation, compression, réverbération d'intérieur 0.25 s, intensité -19 LUFS (rechargement) |
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
| `dog_explode.wav` | [Fireball Explosion.wav](https://freesound.org/s/431174/) par Blankened<br>[fire-whoosh.wav](https://freesound.org/s/244926/) par hnhnh [0.00-1.80 s] | mono 44,1 kHz 16 bits, 2 couches mixées, égalisation, compression, saturation x1.4, réverbération d'intérieur 1.20 s, intensité -10 LUFS (explosion) |
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
| `minigun_fire.wav` | [Minigun Fire](https://freesound.org/s/500304/) par Bratish [0.00-0.16 s]<br>[M4A1 Rifle Shot 4](https://freesound.org/s/854179/) par qubodup | mono 44,1 kHz 16 bits, coupé à 0.10 s, 2 couches mixées, égalisation, compression, saturation x1.6, réverbération d'intérieur 0.25 s, intensité -16 LUFS (tir) |
| `thunder_fire.wav` | [Air Canister Short Blasts .wav](https://freesound.org/s/245974/) par Paul368 [0.00-0.90 s]<br>[Explosion From Another Dimension](https://freesound.org/s/814046/) par qubodup<br>[Thunder Clap](https://freesound.org/s/436790/) par roboroo | mono 44,1 kHz 16 bits, coupé à 1.60 s, coupé à 2.60 s, 3 couches mixées, égalisation, compression, saturation x1.4, réverbération d'intérieur 1.20 s, intensité -10 LUFS (arme_merveille) |
| `thunder_charge.wav` | [air_hiss_pressure_loop.wav](https://freesound.org/s/521509/) par typeoo<br>[Assault Rifle Reload](https://freesound.org/s/815879/) par qubodup [1.30-1.87 s] | mono 44,1 kHz 16 bits, coupé à 0.80 s, 2 couches mixées, égalisation, compression, réverbération d'intérieur 0.25 s, intensité -19 LUFS (rechargement) |
| `nova_blast.wav` | [Explosion From Another Dimension](https://freesound.org/s/814046/) par qubodup<br>[Spark Electric SFX 200927_0054.wav](https://freesound.org/s/536793/) par szegvari [0.00-1.30 s] | mono 44,1 kHz 16 bits, coupé à 2.20 s, 2 couches mixées, égalisation, compression, saturation x1.4, réverbération d'intérieur 1.20 s, intensité -10 LUFS (explosion) |
| `pap_zap_1.wav` | [Electric zap.wav](https://freesound.org/s/512471/) par michael_grinnell | mono 44,1 kHz 16 bits, égalisation, compression, réverbération d'intérieur 0.25 s, intensité -19 LUFS (arme_zap) |
| `pap_zap_2.wav` | [zap.mp3](https://freesound.org/s/143565/) par YvesSch | mono 44,1 kHz 16 bits, coupé à 0.30 s, égalisation, compression, réverbération d'intérieur 0.25 s, intensité -19 LUFS (arme_zap) |
| `pap_zap_3.wav` | [ELECTRIC_ZAP_001.wav](https://freesound.org/s/136542/) par JoelAudio | mono 44,1 kHz 16 bits, coupé à 0.28 s, égalisation, compression, réverbération d'intérieur 0.25 s, intensité -19 LUFS (arme_zap) |
