# Assets externes (sons)

Les graphismes du jeu sont 100 % procéduraux. Une partie des sons provient
d'enregistrements **libres de droits** retravaillés pour le jeu ; tout le reste
(musiques, ambiances, annonces des bonus, jingles des atouts, boîte mystère,
Pack-a-Punch, téléporteur, arme merveille, chiens, interface) est synthétisé par
`tools/gen_audio.gd` et `tools/gen_audio_menu.gd`.

## Licence

Toutes les sources ci-dessous sont publiées sur [freesound.org](https://freesound.org)
sous licence **Creative Commons 0 1.0 (CC0, domaine public)** : utilisation,
modification et redistribution libres, y compris commerciales, sans obligation
d'attribution. La licence a été vérifiée sur la page de **chaque** son
(`https://freesound.org/s/<id>/`) avant import. Nous créditons tout de même
les auteurs (écran CRÉDITS du jeu et ce fichier). Aucun son n'est extrait d'un
jeu existant (et en particulier aucun son de Call of Duty).

## Chaîne d'import (reproductible)

```
godot --headless --path . -s res://tools/audio/sfx_import.gd [-- noms...]
```

- télécharge avec `curl` l'aperçu OGG haute qualité de chaque source dans un
  cache hors dépôt (`<temp>/cod_sfx_cache`, option `--cache=`, `--no-fetch`) ;
- décode en mono 44,1 kHz (Godot `AudioStreamOggVorbis` + `mix_audio`),
  découpe (`start`/`end`), coupe les silences, change la hauteur, égalise
  (biquads), compresse, sature légèrement (tirs), ajoute une réverbération
  d'intérieur courte, normalise la crête, écrit un WAV 16 bits mono ;
- les recettes sont dans `tools/audio/sfx_recipes.gd` (préréglages `gun`,
  `gun_heavy`, `explosion`, `mech`, `zombie`, `foley`), le traitement dans
  `tools/audio/sfx_dsp.gd` ;
- `--doc` régénère le tableau ci-dessous, `--analyze=<dossier>` et
  `--segments=<fichiers>` aident à choisir les sources et les découpes.

`tools/gen_audio.gd` ne réécrit **jamais** un son qui a une recette
(`SfxRecipes.RECIPES`, liste d'exclusion vérifiée par `tests/test_audio.gd`).

## À remplacer ensuite (encore procéduraux)

Sons encore synthétisés qui gagneraient à être remplacés par des
enregistrements CC0 (même chaîne : ajouter la source dans `SOURCES`, une
recette dans `RECIPES`, relancer `sfx_import.gd`) :

- armes : `ray_fire` (arme merveille, volontairement synthétique),
  `break_open` / `break_close` (fusil à canons basculants, barillet),
  `impact_concrete` (impacts de balles sur le décor) ;
- joueur : `footstep_1..4`, `dive_land`, `player_hurt_1..2`, `player_down`,
  `revive`, `heartbeat` ;
- grenades : `grenade_pin`, `grenade_throw`, `grenade_bounce`, `monkey_*` ;
- chiens de l'enfer : `dog_bark_*`, `dog_growl_*`, `dog_whine`, `dog_explode` ;
- décor : `door_open`, `lever`, `power_on`, `purchase`, `denied` ;
- sons ajoutés en parallèle (autres chantiers, générés par `gen_audio.gd`) :
  atouts PhD Flopper / Deadshot (jingles, explosion de plongeon), rampants
  (« crawlers ») et death machine, arme « tonnerre » — à passer dans la
  chaîne CC0 une fois intégrés.

## Mixage

- Bus : `Master` (limiteur `AudioEffectHardLimiter`, plafond -0,5 dB),
  `Music`, `SFX`, `UI` (`default_bus_layout.tres`).
- Tirs du joueur local en 2D à -1 dB (crête des fichiers -0,8 dBFS), tirs des
  autres joueurs et zombies en 3D (`unit_size` 6 m, audibles jusqu'à 45 m,
  filtre passe-bas avec la distance).
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
| `m1911_fire.wav` | [Single Pistol Gunshot 3.wav](https://freesound.org/s/385811/) par morganpurkis | mono 44,1 kHz 16 bits, coupé à 0.75 s, égalisation, compression, saturation x1.6, réverbération d'intérieur 0.55 s, normalisé -0.8 dBFS |
| `pistol_fire.wav` | [Single Pistol Gunshot 4.wav](https://freesound.org/s/391328/) par morganpurkis | mono 44,1 kHz 16 bits, hauteur x1.04, coupé à 0.70 s, égalisation, compression, saturation x1.6, réverbération d'intérieur 0.55 s, normalisé -0.8 dBFS |
| `revolver_fire.wav` | [357 Magnum Revolver Gunshot with Tail](https://freesound.org/s/683175/) par Shark_Anthony | mono 44,1 kHz 16 bits, coupé à 1.50 s, égalisation, compression, saturation x1.8, réverbération d'intérieur 0.70 s, normalisé -0.8 dBFS |
| `smg_fire.wav` | [A Glock handgun being shot 3x // punchy hollywood-esque sounding shots w/ airy forest reverb](https://freesound.org/s/855652/) par serøutōnin--deprivəd [0.00-0.60 s] | mono 44,1 kHz 16 bits, hauteur x1.10, coupé à 0.45 s, égalisation, compression, saturation x1.6, réverbération d'intérieur 0.40 s, normalisé -0.8 dBFS |
| `mp40_fire.wav` | [A Glock handgun being shot 3x // punchy hollywood-esque sounding shots w/ airy forest reverb](https://freesound.org/s/855652/) par serøutōnin--deprivəd [1.60-2.20 s] | mono 44,1 kHz 16 bits, hauteur x0.88, coupé à 0.55 s, égalisation, compression, saturation x1.6, réverbération d'intérieur 0.45 s, normalisé -0.8 dBFS |
| `pm63_fire.wav` | [A Glock handgun being shot 3x // punchy hollywood-esque sounding shots w/ airy forest reverb](https://freesound.org/s/855652/) par serøutōnin--deprivəd [3.17-3.80 s] | mono 44,1 kHz 16 bits, hauteur x1.20, coupé à 0.35 s, égalisation, compression, saturation x1.6, réverbération d'intérieur 0.35 s, normalisé -0.8 dBFS |
| `spectre_fire.wav` | [Pistol Shot](https://freesound.org/s/163456/) par LeMudCrab | mono 44,1 kHz 16 bits, hauteur x1.12, coupé à 0.40 s, égalisation, compression, saturation x1.6, réverbération d'intérieur 0.40 s, normalisé -0.8 dBFS |
| `ak74u_fire.wav` | [An AK-47 being shot // has distinctive metallic kalashnikov-esque report](https://freesound.org/s/855841/) par serøutōnin--deprivəd | mono 44,1 kHz 16 bits, hauteur x1.08, coupé à 0.55 s, égalisation, compression, saturation x1.6, réverbération d'intérieur 0.55 s, normalisé -0.8 dBFS |
| `rifle_fire.wav` | [M4A1 Rifle Shot 10](https://freesound.org/s/854231/) par qubodup | mono 44,1 kHz 16 bits, coupé à 0.70 s, égalisation, compression, saturation x1.6, réverbération d'intérieur 0.55 s, normalisé -0.8 dBFS |
| `galil_fire.wav` | [An AK-47 being shot // has distinctive metallic kalashnikov-esque report // punchy sounding](https://freesound.org/s/855842/) par serøutōnin--deprivəd | mono 44,1 kHz 16 bits, coupé à 0.75 s, égalisation, compression, saturation x1.6, réverbération d'intérieur 0.55 s, normalisé -0.8 dBFS |
| `famas_fire.wav` | [M4A1 Rifle Shot 11](https://freesound.org/s/854232/) par qubodup | mono 44,1 kHz 16 bits, hauteur x1.06, coupé à 0.55 s, égalisation, compression, saturation x1.6, réverbération d'intérieur 0.55 s, normalisé -0.8 dBFS |
| `aug_fire.wav` | [M4A1 Shot](https://freesound.org/s/854207/) par qubodup | mono 44,1 kHz 16 bits, hauteur x0.97, coupé à 0.70 s, égalisation, compression, saturation x1.6, réverbération d'intérieur 0.55 s, normalisé -0.8 dBFS |
| `burst_fire.wav` | [M4A1 Rifle Shot 12](https://freesound.org/s/854233/) par qubodup | mono 44,1 kHz 16 bits, hauteur x1.03, coupé à 0.50 s, égalisation, compression, saturation x1.6, réverbération d'intérieur 0.45 s, normalisé -0.8 dBFS |
| `g11_fire.wav` | [M4A1 Rifle Shot 4](https://freesound.org/s/854179/) par qubodup | mono 44,1 kHz 16 bits, hauteur x1.15, coupé à 0.30 s, égalisation, compression, saturation x1.6, réverbération d'intérieur 0.35 s, normalisé -0.8 dBFS |
| `m14_fire.wav` | [An automatic rifle being shot once // metallic and punchy sounding](https://freesound.org/s/855655/) par serøutōnin--deprivəd | mono 44,1 kHz 16 bits, hauteur x0.92, coupé à 0.95 s, égalisation, compression, saturation x1.8, réverbération d'intérieur 0.90 s, normalisé -0.8 dBFS |
| `fnfal_fire.wav` | [An automatic rifle being shot once // punchy sounding](https://freesound.org/s/855654/) par serøutōnin--deprivəd | mono 44,1 kHz 16 bits, hauteur x0.94, coupé à 0.85 s, égalisation, compression, saturation x1.8, réverbération d'intérieur 0.90 s, normalisé -0.8 dBFS |
| `lmg_fire.wav` | [An AK-47 being shot // has distinctive metallic kalashnikov-esque report // punchy sounding w/ distant trailing reverb](https://freesound.org/s/855843/) par serøutōnin--deprivəd | mono 44,1 kHz 16 bits, hauteur x0.93, coupé à 0.75 s, égalisation, compression, saturation x1.8, réverbération d'intérieur 0.90 s, normalisé -0.8 dBFS |
| `hk21_fire.wav` | [AssaultRifle1.wav](https://freesound.org/s/404562/) par SuperPhat | mono 44,1 kHz 16 bits, hauteur x0.88, coupé à 0.80 s, égalisation, compression, saturation x1.8, réverbération d'intérieur 0.90 s, normalisé -0.8 dBFS |
| `shotgun_fire.wav` | [shotgun-one-shot.wav](https://freesound.org/s/668353/) par DeltaCode<br>[Shotgun Shot 03.wav](https://freesound.org/s/473846/) par LilMati | mono 44,1 kHz 16 bits, coupé à 0.72 s, coupé à 1.30 s, 2 couches mixées, égalisation, compression, saturation x1.8, réverbération d'intérieur 0.90 s, normalisé -0.8 dBFS |
| `spas_fire.wav` | [Shotgun Shot sfx](https://freesound.org/s/564480/) par lumikon [0.00-0.80 s] | mono 44,1 kHz 16 bits, coupé à 0.80 s, égalisation, compression, saturation x1.8, réverbération d'intérieur 0.90 s, normalisé -0.8 dBFS |
| `hs10_fire.wav` | [Shotgun Shot](https://freesound.org/s/163455/) par LeMudCrab | mono 44,1 kHz 16 bits, hauteur x1.03, coupé à 0.80 s, égalisation, compression, saturation x1.8, réverbération d'intérieur 0.90 s, normalisé -0.8 dBFS |
| `olympia_fire.wav` | [Shotgun 02.wav](https://freesound.org/s/544676/) par Clueless79 | mono 44,1 kHz 16 bits, coupé à 1.30 s, égalisation, compression, saturation x1.8, réverbération d'intérieur 0.90 s, normalisé -0.8 dBFS |
| `sniper_fire.wav` | [FPS Sniper Shot Alt](https://freesound.org/s/816113/) par qubodup | mono 44,1 kHz 16 bits, coupé à 1.50 s, égalisation, compression, saturation x1.8, réverbération d'intérieur 1.00 s, normalisé -0.8 dBFS |
| `dragunov_fire.wav` | [Sniper Rifle](https://freesound.org/s/514228/) par SuperPhat | mono 44,1 kHz 16 bits, coupé à 1.30 s, égalisation, compression, saturation x1.8, réverbération d'intérieur 0.90 s, normalisé -0.8 dBFS |
| `launcher_fire.wav` | [M203 Grenade Launcher 1.flac](https://freesound.org/s/162402/) par qubodup | mono 44,1 kHz 16 bits, coupé à 0.60 s, égalisation, compression, saturation x1.3, réverbération d'intérieur 0.55 s, normalisé -0.8 dBFS |
| `rocket_fire.wav` | [Rocket Launch](https://freesound.org/s/521377/) par Jarusca | mono 44,1 kHz 16 bits, coupé à 1.40 s, égalisation, compression, saturation x1.3, réverbération d'intérieur 0.90 s, normalisé -0.8 dBFS |
| `explosion.wav` | [Explosion008.wav](https://freesound.org/s/337298/) par klangfabrik<br>[large explosion 1](https://freesound.org/s/482993/) par V-ktor | mono 44,1 kHz 16 bits, coupé à 2.50 s, coupé à 2.80 s, 2 couches mixées, égalisation, compression, saturation x1.4, réverbération d'intérieur 1.20 s, normalisé -0.8 dBFS |
| `frag_explode.wav` | [Grenade Explosion SFX (medium-sized, meaty, realistic)](https://freesound.org/s/609587/) par unfa | mono 44,1 kHz 16 bits, coupé à 3.00 s, égalisation, compression, saturation x1.4, réverbération d'intérieur 1.20 s, normalisé -0.8 dBFS |
| `mag_out.wav` | [Assault Rifle Reload](https://freesound.org/s/815879/) par qubodup [0.00-0.45 s] | mono 44,1 kHz 16 bits, égalisation, compression, réverbération d'intérieur 0.25 s, normalisé -1.5 dBFS |
| `mag_in.wav` | [Assault Rifle Reload](https://freesound.org/s/815879/) par qubodup [0.55-1.00 s] | mono 44,1 kHz 16 bits, égalisation, compression, réverbération d'intérieur 0.25 s, normalisé -1.5 dBFS |
| `slide.wav` | [Assault Rifle Reload](https://freesound.org/s/815879/) par qubodup [1.30-1.87 s] | mono 44,1 kHz 16 bits, égalisation, compression, réverbération d'intérieur 0.25 s, normalisé -1.5 dBFS |
| `bolt.wav` | [Mosin Nagant Bolt Action Cycle](https://freesound.org/s/370345/) par Zott820 [0.05-1.40 s] | mono 44,1 kHz 16 bits, égalisation, compression, réverbération d'intérieur 0.25 s, normalisé -1.5 dBFS |
| `pump.wav` | [Remington 870 12 gauge shotgun pump racking cha chock](https://freesound.org/s/755495/) par TotallyPhilip [0.06-0.60 s] | mono 44,1 kHz 16 bits, égalisation, compression, réverbération d'intérieur 0.25 s, normalisé -1.5 dBFS |
| `shell_in.wav` | [Shotgun Shell Load](https://freesound.org/s/500293/) par Bratish [0.00-0.40 s] | mono 44,1 kHz 16 bits, égalisation, compression, réverbération d'intérieur 0.25 s, normalisé -1.5 dBFS |
| `shell.wav` | [22lr Revolver ejecting bullets from cylinder](https://freesound.org/s/693125/) par serøutōnin--deprivəd [0.00-0.66 s] | mono 44,1 kHz 16 bits, égalisation, compression, réverbération d'intérieur 0.25 s, normalisé -1.5 dBFS |
| `dry_fire.wav` | [9mm Handgun Being Dry Fired](https://freesound.org/s/674568/) par serøutōnin--deprivəd | mono 44,1 kHz 16 bits, égalisation, compression, réverbération d'intérieur 0.25 s, normalisé -1.5 dBFS |
| `weapon_switch.wav` | [A pistol being moved around and handled w/ foley](https://freesound.org/s/725400/) par serøutōnin--deprivəd [4.95-5.36 s] | mono 44,1 kHz 16 bits, égalisation, compression, réverbération d'intérieur 0.25 s, normalisé -1.5 dBFS |
| `knife_swing.wav` | [Small Knife Whoosh.wav](https://freesound.org/s/389690/) par Shamewap | mono 44,1 kHz 16 bits, coupé à 0.50 s, égalisation, compression, réverbération d'intérieur 0.15 s, normalisé -1.5 dBFS |
| `knife_hit.wav` | [body_hit.wav](https://freesound.org/s/276600/) par insanity54 | mono 44,1 kHz 16 bits, coupé à 0.50 s, égalisation, compression, réverbération d'intérieur 0.30 s, normalisé -1.5 dBFS |
| `knife_flesh.wav` | [Flesh Stabs and Slashes 2](https://freesound.org/s/635049/) par sillygrizzlies [3.70-4.32 s] | mono 44,1 kHz 16 bits, égalisation, compression, réverbération d'intérieur 0.30 s, normalisé -1.5 dBFS |
| `bowie_draw.wav` | [UnsheathingSmallKnife.wav](https://freesound.org/s/466216/) par Harrisando | mono 44,1 kHz 16 bits, coupé à 1.00 s, égalisation, compression, réverbération d'intérieur 0.25 s, normalisé -1.5 dBFS |
| `flesh_hit_1.wav` | [VisceralBulletImpacts.wav](https://freesound.org/s/423301/) par u1769092 [0.00-0.30 s] | mono 44,1 kHz 16 bits, égalisation, compression, réverbération d'intérieur 0.30 s, normalisé -1.5 dBFS |
| `flesh_hit_2.wav` | [VisceralBulletImpacts.wav](https://freesound.org/s/423301/) par u1769092 [0.31-0.65 s] | mono 44,1 kHz 16 bits, égalisation, compression, réverbération d'intérieur 0.30 s, normalisé -1.5 dBFS |
| `flesh_hit_3.wav` | [VisceralBulletImpacts.wav](https://freesound.org/s/423301/) par u1769092 [1.39-1.72 s] | mono 44,1 kHz 16 bits, égalisation, compression, réverbération d'intérieur 0.30 s, normalisé -1.5 dBFS |
| `headshot.wav` | [Headshot.wav](https://freesound.org/s/511194/) par Pablobd<br>[VisceralBulletImpacts.wav](https://freesound.org/s/423301/) par u1769092 [0.66-1.33 s] | mono 44,1 kHz 16 bits, coupé à 0.80 s, 2 couches mixées, égalisation, compression, réverbération d'intérieur 0.30 s, normalisé -1.5 dBFS |
| `body_fall.wav` | [BODY FALL - V HVY - DIRT](https://freesound.org/s/504626/) par leonelmail | mono 44,1 kHz 16 bits, égalisation, compression, réverbération d'intérieur 0.30 s, normalisé -1.5 dBFS |
| `emerge.wav` | [Shovelling Dirt.mp3](https://freesound.org/s/415303/) par Yin_Yang_Jake007 [6.95-7.45 s]<br>[Shovel_dirt.wav](https://freesound.org/s/353907/) par dr19 [0.00-0.45 s]<br>[BODY FALL - V HVY - DIRT](https://freesound.org/s/504626/) par leonelmail [0.30-1.20 s] | mono 44,1 kHz 16 bits, 3 couches mixées, égalisation, compression, réverbération d'intérieur 0.30 s, normalisé -1.5 dBFS |
| `barricade_tear_1.wav` | [Tearing pieces of wood](https://freesound.org/s/628398/) par melle_teich [7.10-7.68 s] | mono 44,1 kHz 16 bits, égalisation, compression, réverbération d'intérieur 0.30 s, normalisé -1.5 dBFS |
| `barricade_tear_2.wav` | [Tearing pieces of wood](https://freesound.org/s/628398/) par melle_teich [14.50-15.10 s] | mono 44,1 kHz 16 bits, égalisation, compression, réverbération d'intérieur 0.30 s, normalisé -1.5 dBFS |
| `barricade_tear_3.wav` | [Tearing pieces of wood](https://freesound.org/s/628398/) par melle_teich [18.08-19.00 s] | mono 44,1 kHz 16 bits, égalisation, compression, réverbération d'intérieur 0.30 s, normalisé -1.5 dBFS |
| `barricade_slam_1.wav` | [door wood hits impacts small break through clumsy metal thing dall.wav](https://freesound.org/s/450793/) par kyles [0.33-0.68 s] | mono 44,1 kHz 16 bits, égalisation, compression, réverbération d'intérieur 0.30 s, normalisé -1.5 dBFS |
| `barricade_slam_2.wav` | [door wood hits impacts small break through clumsy metal thing dall.wav](https://freesound.org/s/450793/) par kyles [1.17-1.55 s] | mono 44,1 kHz 16 bits, égalisation, compression, réverbération d'intérieur 0.30 s, normalisé -1.5 dBFS |
| `zombie_groan_1.wav` | [Zombie 1](https://freesound.org/s/163440/) par Under7dude | mono 44,1 kHz 16 bits, hauteur x0.95, égalisation, compression, saturation x1.1, réverbération d'intérieur 0.35 s, normalisé -1.5 dBFS |
| `zombie_groan_2.wav` | [Zombie 2](https://freesound.org/s/163439/) par Under7dude | mono 44,1 kHz 16 bits, hauteur x0.97, égalisation, compression, saturation x1.1, réverbération d'intérieur 0.35 s, normalisé -1.5 dBFS |
| `zombie_groan_3.wav` | [Zombie Growl 5.wav](https://freesound.org/s/555417/) par tonsil5 | mono 44,1 kHz 16 bits, coupé à 2.20 s, égalisation, compression, saturation x1.1, réverbération d'intérieur 0.35 s, normalisé -1.5 dBFS |
| `zombie_groan_4.wav` | [Zombie Growl 2.wav](https://freesound.org/s/555415/) par tonsil5 | mono 44,1 kHz 16 bits, coupé à 2.40 s, égalisation, compression, saturation x1.1, réverbération d'intérieur 0.35 s, normalisé -1.5 dBFS |
| `zombie_groan_5.wav` | [SZ_Zombies_01.wav](https://freesound.org/s/196721/) par PaulMorek | mono 44,1 kHz 16 bits, hauteur x0.94, coupé à 2.80 s, égalisation, compression, saturation x1.1, réverbération d'intérieur 0.35 s, normalisé -1.5 dBFS |
| `zombie_groan_6.wav` | [Zombie Pack(Clean Record)](https://freesound.org/s/393749/) par haratman [3.65-4.60 s] | mono 44,1 kHz 16 bits, hauteur x0.92, égalisation, compression, saturation x1.1, réverbération d'intérieur 0.35 s, normalisé -1.5 dBFS |
| `zombie_groan_7.wav` | [Zombie Pack(Clean Record)](https://freesound.org/s/393749/) par haratman [9.25-10.20 s] | mono 44,1 kHz 16 bits, hauteur x0.90, égalisation, compression, saturation x1.1, réverbération d'intérieur 0.35 s, normalisé -1.5 dBFS |
| `zombie_groan_8.wav` | [zombie_moan.mp3](https://freesound.org/s/346626/) par bigmonmulgrew | mono 44,1 kHz 16 bits, hauteur x0.93, égalisation, compression, saturation x1.1, réverbération d'intérieur 0.35 s, normalisé -1.5 dBFS |
| `zombie_sprint_1.wav` | [Zombie Roar 5](https://freesound.org/s/144005/) par ArriGD | mono 44,1 kHz 16 bits, égalisation, compression, saturation x1.1, réverbération d'intérieur 0.35 s, normalisé -1.5 dBFS |
| `zombie_sprint_2.wav` | [Zombie Roar 3](https://freesound.org/s/143999/) par ArriGD | mono 44,1 kHz 16 bits, égalisation, compression, saturation x1.1, réverbération d'intérieur 0.35 s, normalisé -1.5 dBFS |
| `zombie_sprint_3.wav` | [Zombie Roar 8](https://freesound.org/s/144002/) par ArriGD | mono 44,1 kHz 16 bits, égalisation, compression, saturation x1.1, réverbération d'intérieur 0.35 s, normalisé -1.5 dBFS |
| `zombie_sprint_4.wav` | [Zombie Growl 3.wav](https://freesound.org/s/555414/) par tonsil5 | mono 44,1 kHz 16 bits, hauteur x1.05, coupé à 1.60 s, égalisation, compression, saturation x1.1, réverbération d'intérieur 0.35 s, normalisé -1.5 dBFS |
| `zombie_attack_1.wav` | [Zombie Hit 1.wav](https://freesound.org/s/555420/) par tonsil5<br>[Small Knife Whoosh.wav](https://freesound.org/s/389690/) par Shamewap | mono 44,1 kHz 16 bits, hauteur x0.80, coupé à 0.40 s, 2 couches mixées, égalisation, compression, saturation x1.1, réverbération d'intérieur 0.35 s, normalisé -1.5 dBFS |
| `zombie_attack_2.wav` | [Zombie Hit](https://freesound.org/s/163447/) par Under7dude<br>[Small Knife Whoosh.wav](https://freesound.org/s/389690/) par Shamewap | mono 44,1 kHz 16 bits, hauteur x0.75, coupé à 0.40 s, 2 couches mixées, égalisation, compression, saturation x1.1, réverbération d'intérieur 0.35 s, normalisé -1.5 dBFS |
| `zombie_attack_3.wav` | [Zombie Roar 4](https://freesound.org/s/143998/) par ArriGD<br>[Small Knife Whoosh.wav](https://freesound.org/s/389690/) par Shamewap | mono 44,1 kHz 16 bits, hauteur x0.85, coupé à 0.40 s, 2 couches mixées, égalisation, compression, saturation x1.1, réverbération d'intérieur 0.35 s, normalisé -1.5 dBFS |
| `zombie_attack_4.wav` | [Zombie Pack(Clean Record)](https://freesound.org/s/393749/) par haratman [17.58-18.10 s]<br>[Small Knife Whoosh.wav](https://freesound.org/s/389690/) par Shamewap | mono 44,1 kHz 16 bits, hauteur x0.92, hauteur x0.80, coupé à 0.40 s, 2 couches mixées, égalisation, compression, saturation x1.1, réverbération d'intérieur 0.35 s, normalisé -1.5 dBFS |
| `zombie_death_1.wav` | [Zombie Death 1.wav](https://freesound.org/s/555412/) par tonsil5 | mono 44,1 kHz 16 bits, hauteur x0.95, égalisation, compression, saturation x1.1, réverbération d'intérieur 0.35 s, normalisé -1.5 dBFS |
| `zombie_death_2.wav` | [Zombie Death 2.wav](https://freesound.org/s/555411/) par tonsil5 | mono 44,1 kHz 16 bits, hauteur x0.95, égalisation, compression, saturation x1.1, réverbération d'intérieur 0.35 s, normalisé -1.5 dBFS |
| `zombie_death_3.wav` | [Zombie Pain 2.wav](https://freesound.org/s/555423/) par tonsil5 | mono 44,1 kHz 16 bits, hauteur x0.93, égalisation, compression, saturation x1.1, réverbération d'intérieur 0.35 s, normalisé -1.5 dBFS |
| `zombie_death_4.wav` | [Zombie Pack(Clean Record)](https://freesound.org/s/393749/) par haratman [22.00-23.80 s] | mono 44,1 kHz 16 bits, hauteur x0.92, égalisation, compression, saturation x1.1, réverbération d'intérieur 0.35 s, normalisé -1.5 dBFS |
| `zombie_step_1.wav` | [Walking - Dragging feet - heavy footsteps - eerie - boots](https://freesound.org/s/741627/) par GoatsheadCastle [9.12-9.52 s] | mono 44,1 kHz 16 bits, égalisation, compression, réverbération d'intérieur 0.30 s, normalisé -1.5 dBFS |
| `zombie_step_2.wav` | [Walking - Dragging feet - heavy footsteps - eerie - boots](https://freesound.org/s/741627/) par GoatsheadCastle [9.58-10.00 s] | mono 44,1 kHz 16 bits, égalisation, compression, réverbération d'intérieur 0.30 s, normalisé -1.5 dBFS |
| `zombie_step_3.wav` | [Walking - Dragging feet - heavy footsteps - eerie - boots](https://freesound.org/s/741627/) par GoatsheadCastle [10.64-11.10 s] | mono 44,1 kHz 16 bits, égalisation, compression, réverbération d'intérieur 0.30 s, normalisé -1.5 dBFS |
| `zombie_step_4.wav` | [Walking - Dragging feet - heavy footsteps - eerie - boots](https://freesound.org/s/741627/) par GoatsheadCastle [11.28-11.75 s] | mono 44,1 kHz 16 bits, égalisation, compression, réverbération d'intérieur 0.30 s, normalisé -1.5 dBFS |
