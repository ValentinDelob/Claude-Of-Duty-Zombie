# Hub v2 — maquettes validées (référence à suivre à 100 %)

Maquettes conçues avec Claude Design et validées par l'utilisateur le 2026-10-11
(canvas : https://claude.ai/artifact/3E7xaZUhfc7hPeuT6Yyxk2). Chaque fichier
`*.dc.html` est un écran en **1280 × 720** : tailles, marges, couleurs, polices,
textes et comportements y sont exacts. Le jeu doit les reproduire fidèlement
(mise en page logique 1280 × 720 du projet, `canvas_items`).

## Écrans
| Fichier | Écran |
|---|---|
| `Main.dc.html` | LABO (accueil) : Dr Brown en grand, réplique, boutons CONTRATS (anneaux jaunes pulsés quand un contrat est terminé) et ÉCHANGES (réduits le 2026-10-12, voir « Retouches des maquettes ») |
| `Contrats.dc.html` | LABO › CONTRATS : contrat d'HISTOIRE (chapitres / étapes, à gauche, turquoise) et CONTRATS TEMPORAIRES (à droite, expirent), récompenses en tuiles avec infobulle au survol |
| `Echanges.dc.html` | LABO › ÉCHANGES (catalogue) |
| `Arsenal.dc.html` | ARSENAL : rail horizontal des niveaux, armes d'un même niveau empilées verticalement (◄ ► niveau, ▲ ▼ même niveau), vue d'ensemble, sous-onglet PIÈCES, fiche : statistiques en icônes + valeur de base + modificateur vert / rouge (sans unité) |
| `Inventaire.dc.html` | INVENTAIRE : échantillons groupés par ennemi (rendus 3D), fiche (où le trouver, demandé par) |
| `Codex.dc.html` | CODEX : rendus des ennemis (silhouette noire si inconnu), fiche avec taux de butin par échantillon |
| `Partie.dc.html` | JOUER solo : défi de la semaine, CARTES DU JEU / CARTES PERSONNALISÉES (« POUR LE FUN », aucune progression), aperçu, vagues, ÉQUIPEMENT (rendus), LANCER |
| `PartieCoop.dc.html` | JOUER coop : salon, 4 cartes de joueurs (modèle, couleur, niveau, ping, équipement, PRÊT), carte de l'hôte avec aperçu, LANCER |
| `Recap.dc.html` | Retour de partie : XP qui grimpe, passage de niveau animé, détail de l'XP, butin gardé, contrat prêt |
| `TopBar.dc.html` | Barre du haut : niveau + XP, onglets LABO · ARSENAL · INVENTAIRE · CODEX (LB / RB), bouton JOUER (START en anglais) |
| `Prompts.dc.html` | Barre d'invites du bas |

## Style
Panneaux noirs semi-transparents (≈ rgba(10,11,13,0.62) + flou) sur la **scène 3D du menu**
(couloir avec zombie qui marche, `MenuBackdrop`, assombrie ≈ 35–45 %). Accent jaune `#F5C542`,
turquoise labo / histoire `#4FE3C1`, texte `#F2F0EA`. Rareté : commune `#C9C7BE`, rare `#4D9BFF`,
épique `#B56CFF`, légendaire `#FF9A1F`, unique `#FF4D5E`. Polices : Chakra Petch (titres, libellés),
Barlow (texte), JetBrains Mono (nombres) — toutes sous licence libre OFL. Coins biseautés
(clip-path) sur les boutons principaux. Jamais de carré de couleur à la place d'un objet :
armes, ennemis, échantillons, joueur et scientifique sont des **rendus Blender** de leurs modèles en cubes.

## Images (`img/`)
Correspondance des adresses `/_blob/<id>` des maquettes :
| id | fichier |
|---|---|
| 6081e013ae646f268abd800eabf60108 | img/menu_backdrop.png (capture : en jeu, c'est la scène 3D en direct) |
| bd79da880fce622789c476ca9c7dea95 | img/scientist_hero.png |
| 92057f91395d6002cbc09d7b4e5f0160 | img/map_bunker.png |
| 20876798ce4900f9ed3a5f946a1f1baf | img/mobs/player.png |
| 0e6a75160bd65016d6409296a9fe1d9a | img/mobs/walker.png |
| 3b3679ea74fef2eddafe309e56f0c908 | img/mobs/dog.png |
| 3d39587280b2eeefed09e106a3157733 | img/mobs/brancardier.png |
| 769c7414b88de8c30e62c200fba69dec | img/mobs/nurse.png |
| a9b9e14de6fa9f843806a66820ec7e7f | img/mobs/surgeon.png |
| ed8a57fdd004b309f0c5567595ee180e | img/weapons/m1911.png |
| 9d38742d8c0caee5a322e5a96cf99ef5 | img/weapons/mp40.png |
| fc3abecb0f90953ee10501ac089e2f57 | img/weapons/bat.png |
| 1872714484066f6416ad7bb97500f690 | img/weapons/olympia.png |
| 831a546a3d13826bc14139ab5573dbab | img/weapons/m14.png |
| 31416266c1027096880ffa6893eaaca5 | img/weapons/cz75.png |
| 1b9c912fbd8393fa67af3c56d6269910 | img/weapons/m16.png |
| 8b19808681271fea88592c2d0e4b691a | img/weapons/stakeout.png |
| 3d106fb115dca8c8713b595b21d2f34e | img/weapons/python.png |
| a038df1bbc5fc8e11bb800c3e9e54fcc | img/weapons/spectre.png |
| 246c2d17c27cbe7b3a43427543dbb2c3 | img/weapons/galil.png |
| 5ac1171c8cb205d05475869cc9358d7f | img/samples/dog_fang.png |
| 7541a18d3e89835544629d6617de6912 | img/samples/dog_fur.png |
| f93e9aecad531b09e66d6aa4ccbf4328 | img/samples/dog_collar.png |
| ab3222ad5bf7029146f53c7f07cc1c92 | img/samples/brancard_strap.png |
| 013d704a1375e7c2ac7604ae1e5213eb | img/samples/brancard_bracelet.png |
| f460b73a6a94748bf84eb1e5695a72a6 | img/samples/nurse_vocal_cords.png |
| 58b8fe9a2d9f1d71a563b53b9c1641bf | img/samples/nurse_syringe.png |
| dc44df741b3889e2fa657246e0cf867b | img/samples/nurse_badge.png |
| 044f9f9cb450adf1ca3964ef64e00482 | img/samples/surgeon_scalpel.png |
| 2b5aeca6d61eca6c669a9f0fc63340f2 | img/samples/surgeon_heart.png |

Scripts de rendu : `tools/blender/hub_renders/` (armes, ennemis, joueur),
`tools/blender/samples/` (échantillons), `tools/blender/scientist/` (Dr Brown).

## Écrans en partie (validés le 2026-10-12)
| Fichier | Écran |
|---|---|
| `InventaireJeu.dc.html` | Inventaire de partie (touche I) : EN MAIN (3, touches 1-2-3), SAC À DOS (4), PIÈCES TROUVÉES, fiche avec comparaison à l'arme en main (+ vert / − rouge), recyclage (ferraille), « LA PARTIE CONTINUE » ; fond = la partie, assombrie |
| `Evacuation.dc.html` | Vote d'évacuation : cadre compact à gauche, ÉVACUATION + temps + barre, une ligne par joueur avec son choix en face (CONTINUER jaune, ÉVACUER turquoise, EN ATTENTE gris = pas encore voté, non sélectionnable), deux choix F1 CONTINUER / F2 ÉVACUER (manette : croix gauche / droite), vote depuis n'importe où ; repère « ÉVACUATION · N m » au-dessus de la porte quand on a voté ÉVACUER |
| `Station.dc.html` | Station de construction (validée le 2026-10-12) : en-tête titre + ferraille (sans bandeau « partie continue » ni bande d'état de construction), rail des niveaux comme l'Arsenal (5 colonnes, même niveau empilé, flèches ‹ ›), cartes avec prix en ferraille (rouge si insuffisant) et durée en manches, halo animé de la couleur de rareté derrière l'arme (aucun pour les communes ; rayons tournants en plus pour légendaire), fiche (stats en icônes, pièces, prix, manche où l'arme sera prête, CONSTRUIRE, « Il te restera… » ou raison du refus), bande MUNITIONS (R · RECHARGER), Échap FERMER ; le recyclage n'est plus à la station (inventaire, I) |

## Ajouts sans maquette (dans le style ci-dessus)
- **Fiche complète d'une arme** (2026-10-12, `Hub2WeaponDetails`) : sous les six
  statistiques de l'ARSENAL, de l'inventaire de partie et de la station de
  construction, titre « DÉTAILS ▾ » /
  « MASQUER ▴ » (style des titres de section « PIÈCES · n / m »), puis les autres
  statistiques dans la même grille 2 colonnes, libellé / valeur / modificateur
  des six sans le carré d'icône (tir à la tête, mode de tir, recul, mise en joue,
  réserve, pénétration, plombs, zone ; corps à corps : énergie, coups par
  seconde, fente, cibles ; mobilité) et « Réf. … » (Barlow 13 px) si l'arme a une
  référence réelle. D / clic du stick droit / clic sur le titre ; état retenu
  pour la session ; la fiche défile si elle ne tient pas.
- **Page DÉTAILS du CODEX** (2026-10-12, `Hub2CodexPanel`, contenu
  `CodexDetails`) : A / Entrée ou clic sur la carte déjà choisie,
  « DÉTAILS ▾ » en haut à droite du rendu de la fiche (style des titres
  « DÉTAILS » des fiches d'arme), D / clic du stick droit. Sous le nom, la
  description, Éliminés / XP et le butin glissent vers la gauche en
  s'effaçant (0,08 s, ease-in, 12 px), puis la page arrive de la droite
  (18 px, échelle 0,97 -> 1, opacité 0 -> 1, 0,18 s, ease-out cubique) ;
  retour (A, B / Échap, « RETOUR ▴ ») dans l'autre sens. Invites : A
  DÉTAILS / B RETOUR, puis A B RETOUR. Sections au style des blocs de la
  fiche (liseré du haut, padding 10 20 14, libellé de section Chakra Petch
  12 px 600 0,18em, écart 8) : CE QU'IL TE FAIT, RÉSISTANCE, QUAND IL
  APPARAÎT, CE QU'IL RAPPORTE, BUTIN, POINT FAIBLE, CONSEIL ; ligne :
  libellé Barlow 15 px + précision Barlow 12 px 55 % à gauche, valeur
  Chakra Petch 16 px 700 à droite (dégâts `#FF7A5C`, XP jaune, butin
  turquoise ; échantillons : mêmes lignes à rendu que la fiche). Chiffres
  lus dans les règles du jeu (Combat, DogRules, BrancardRules, NurseRules,
  SurgeonRules, PlayerData, RoundRules, WaveRules, XpRules, PointsRules,
  LootRules), textes du point faible et du conseil dans `codex.json`
  (`weak`, `tip`, sans chiffre). Ennemi inconnu : « DÉTAILS VERROUILLÉS ·
  Rencontre-le pour en savoir plus. ». La page reste ouverte en changeant de
  carte et se referme en quittant l'onglet.

## Retouches des maquettes
- **LABO, entrées CONTRATS / ÉCHANGES** (2026-10-12, `Main.dc.html` mis à
  jour) : trop grandes face aux autres écrans du hub, ramenées à leur
  échelle : padding 14 18 (au lieu de 18 22), écart 14, carré d'icône 40 px
  (dessin 22 px), titre Chakra Petch 20 px 0,08em (au lieu de 24 px 0,1em,
  comme « CONTRATS TEMPORAIRES »), ligne Barlow 14 px, liseré 1 px (jaune
  pour CONTRATS ; les anneaux pulsés gardent leurs 2 px), « 1 TERMINÉ »
  12 px, nombres 13 px, 12 px entre les deux entrées. Structure inchangée
  (Dr Brown, en-tête, réplique, CONTRATS avec anneaux quand un contrat est
  prêt, ÉCHANGES).
