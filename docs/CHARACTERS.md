# Personnages jouables et répliques

Les sept protagonistes de Claude of Duty Zombie : les quatre premiers sur le
modèle de l'équipe de Kino der Toten dans Black Ops 1 (quatre archétypes), plus
Mercer, Berg et Jojo ; des personnages, des noms, des visages, des répliques et
une histoire **originaux**. Aucune réplique
de BO1 n'est reprise ni traduite ; aucun insigne réel, aucun symbole politique.

Une partie compte quatre joueurs au plus, comme dans BO1 ; chacun incarne l'un
des sept personnages (`CharacterDB.IDS` : `callahan`, `orlov`, `arakawa`,
`weissmann`, `mercer`, `berg`, `jojo`, index 0 à 6 ; tenues des mains dans
`ViewHands.STYLES`). Le personnage ne dépend plus de l'emplacement : chaque
joueur le choisit dans OPTIONS > JEU > PERSONNAGE, « auto » par défaut ou l'un
des sept (deux joueurs peuvent prendre le même). En « auto », l'emplacement du
joueur décalé d'une rotation tirée au sort par l'hôte (0 à 6) désigne le premier personnage encore
libre. L'hôte résout la distribution et l'envoie à tous (`Net.cast`). Les répliques existent en **français et en anglais** : la
langue jouée suit le réglage « Langue » du jeu. Elles sont écrites nativement dans
chaque langue (pas de traduction mot à mot).

## Histoire commune (originale)

- **L'Institut Aether** (en anglais *Aether Institute*) : institut de recherche
  secret des années 1940, fictif, sans lien avec un régime réel. Il étudiait
  **l'aethérium** (*aetherium*), un minerai bleu luminescent tombé avec une
  météorite, qui ranime les morts et plie l'espace.
- Le théâtre abandonné (Kino der Toten, notre carte KINO) servait de façade à un
  laboratoire de l'Institut : la cabine de projection cache la machine
  d'amélioration (Pack-a-Punch), la tour de la scène est le **téléporteur** de
  Weissmann, le « poste central » du hall en est l'autre bout.
- Les sept se retrouvent enfermés là par l'Institut, qui s'est servi des quatre
  soldats comme cobayes, y a jeté Berg pour la faire taire et Jojo parce qu'il
  avait voulu lui revendre sa propre ferraille ; Weissmann, lui, sait beaucoup
  plus qu'il ne le dit, et Berg en sait plus que lui.
- Noms en jeu à citer tels quels : armes spéciales CLAUDE-RAY (en anglais
  Claude-Ray), TONNERRE-7 (Thunder-7), SINGE-TAMBOUR (Drum Monkey) ; atouts TITAN
  BREW (santé), RAPID FIZZ (rechargement), TWIN SHOT (cadence), LAZARUS TONIC
  (réanimation), STRIDE SODA (sprint), NOVA FLOP (plongeon explosif), DEADEYE DRAM
  (visée) ; bonus MUNITIONS MAX (Max Ammo), MORT INSTANTANÉE (Insta-Kill), POINTS
  DOUBLES (Double Points), BOMBE NUCLÉAIRE (Nuke), CHARPENTIER (Carpenter),
  LIQUIDATION (Fire Sale), FAUCHEUSE (Death Machine) ; la boîte mystère ; la
  machine d'amélioration (Pack-a-Punch).

## Les sept

### 0. Sergent Jack « Hammer » Callahan (`callahan`)
- Marine des États-Unis, capturé dans le Pacifique puis livré à l'Institut.
- Caractère : grande gueule, bagarreur, fanfaron, courageux jusqu'à l'inconscience,
  sarcastique ; donne des surnoms à tout le monde (Orlov « le Tsar », Arakawa
  « Samouraï », Weissmann « Doc » ou « Frankenstein ») ; parle aux zombies comme à
  des adversaires de bar ; argot de soldat, jamais d'insulte raciste.
- Tics : « Oorah ! », références au base-ball et au Texas où il a grandi, promet
  des steaks et des bières à la sortie.
- Apparence : casque M1 cabossé sans insigne, chemise kaki aux manches
  retroussées, bandoulière de munitions, cigare éteint, barbe de trois jours,
  cicatrice au menton.

### 1. Mikhaïl « Micha » Orlov (`orlov`)
- Soldat soviétique, vétéran de Stalingrad, envoyé en bataillon disciplinaire
  pour avoir frappé un officier, puis « prêté » à l'Institut.
- Caractère : fataliste, humour très noir, mélancolique, parle de son village,
  de sa mère et de la neige ; récite des bouts de poèmes ; bourru mais loyal ;
  tutoie tout le monde ; considère les zombies comme une corvée de plus.
- Tics : quelques mots de russe (« Davaï ! », « Bojé moï », « Nou ladno »), compte
  les morts à voix haute, compare tout à l'hiver de Stalingrad. Pas de caricature
  d'ivrogne : il réclame du thé noir et du pain.
- Apparence : très grand, barbe épaisse, chapka sans insigne, veste matelassée
  grise usée (cohérente avec ses mitaines de laine en vue FPS), grosses bottes.

### 2. Lieutenant Kenji Arakawa (`arakawa`)
- Officier de l'armée japonaise, capturé par l'Institut lors d'une mission en
  Mandchourie.
- Caractère : stoïque, discipliné, poli même dans le chaos, sens de l'honneur,
  proverbes et images de la nature (le cerisier, la rivière, la montagne), humour
  pince-sans-rire ; respecte ses compagnons même quand ils l'exaspèrent ; se
  méfie profondément de Weissmann.
- Tics : quelques mots de japonais (« Hai ! », « Sou ka », « Ikuzo ! »), salue
  ses adversaires, parle de son sabre et de la voie du guerrier. Jamais de
  caricature d'accent écrite : un français et un anglais corrects et soutenus.
- Apparence : casquette à couvre-nuque, lunettes rondes, veste olive boutonnée
  (mains nues en vue FPS), sabre au côté, visage mince et sévère.

### 3. Docteur Otto Weissmann (`weissmann`)
- Savant de l'Institut Aether, père de l'aethérium appliqué, du téléporteur et
  de la machine d'amélioration ; à moitié fou, il entend des « voix » et parle à
  ses machines.
- Caractère : génie exalté, cruel par distraction, jubile devant la science et la
  destruction, rit tout seul ; tutoie les zombies (« mes enfants », « mes
  sujets ») ; a des secrets sur la carte et les révèle à demi-mot ; méprise
  poliment les trois soldats (« mes cobayes »).
- Tics : quelques mots d'allemand (« Wunderbar ! », « Ja, ja », « Mein Gott »),
  vocabulaire scientifique, commente les résultats comme des expériences.
  Aucune référence à un régime ou à une idéologie réelle.
- Apparence : combinaison de protection en toile jaunâtre et gants de caoutchouc
  noirs (cohérents avec la vue FPS), lunettes de laboratoire relevées sur le
  front, cheveux gris en bataille, sourire inquiétant, sacoche d'outils,
  brassard à l'emblème original de l'Institut (un anneau et un éclair).

### 4. Sergent-chef d'artillerie Frank « Bulldog » Mercer (`mercer`)
(en anglais *Gunnery Sergeant Frank "Bulldog" Mercer*)
- Marine des États-Unis, la quarantaine passée, vingt ans de service : ancien
  instructeur à Parris Island (c'est lui qui a formé Callahan), puis intendant
  d'un dépôt de ravitaillement dans le Pacifique ; capturé avec son convoi et
  livré à l'Institut.
- Caractère : vieux sous-officier froid, cynique et grognon, humour sec, phrases
  courtes et aboyées ; obsédé par les points, l'argent, les stocks et les prix
  (« tout se paie »), il marchande avec la boîte mystère, râle à chaque achat et
  note chaque point dans son carnet ; dur avec les autres mais les relève
  toujours (« Debout, soldat »). Jamais fanfaron : c'est l'inverse de Callahan,
  qu'il appelle encore « deuxième classe » (*Private*) ; Callahan l'appelle
  « Bulldog », et en fait toujours des cauchemars. Il appelle Orlov « Rayon de
  soleil » (*Sunshine*) et Weissmann « le Professeur », à qui il compte envoyer
  la facture ; il respecte Arakawa du bout des lèvres (« le lieutenant »).
- Tics : vocabulaire d'intendant (registre, inventaire, rendement, remboursement,
  « ça ne se rachète pas »), ordres d'instructeur (pompes, inspection, en rang),
  « Bah. », mâchonne une allumette. Jamais d'insulte visant un groupe réel.
- Apparence : vieux calot de treillis des Marines sans insigne, veste olive en
  toile à chevrons aux manches retroussées, avant-bras tatoués (un bulldog, aucun
  insigne d'unité réelle), cheveux gris en brosse courte, mâchoire lourde, une
  allumette au coin de la bouche, cartouchières à la ceinture, un carnet où il
  tient le compte de ses points.
- Voix : grave, éraillée, agacée, la même en jeu que dans les deux références
  choisies (voir `docs/ASSETS.md`, moteur `qwen_clone`).

### 5. Docteur Ella Berg (`berg`)
(en anglais *Dr Ella Berg*)
- Suédoise, la fin de la vingtaine, chimiste et cryptographe venue de
  Stockholm, neutre. Elle a résolu en une soirée l'énigme chiffrée que l'Institut
  Aether glissait dans une revue savante pour recruter ; Weissmann l'a engagée
  comme assistante. Elle a ensuite cassé le code interne de l'Institut et
  corrigé, en rouge et devant tout le monde, les équations de stabilisation de
  l'aethérium de Weissmann ; vexé, il l'a fait enfermer avec les cobayes. Pour
  qui elle travaille vraiment, elle ne l'a jamais dit : sa sacoche est pleine de
  notes chiffrées, et elle comprend l'aethérium bien mieux qu'elle ne le laisse
  voir.
- Caractère : brillante, rusée, espiègle ; drôle, taquine, charmeuse et un peu
  flirteuse, mais toujours élégante, jamais vulgaire. Elle sourit dans la voix :
  litote malicieuse, piques gentilles contre la manière « gros bras » des
  hommes (« Essayez de suivre, les garçons »). Elle ne marchande pas avec la
  boîte mystère, elle lui fait du charme, et dépense sans compter.
- Relations : Callahan (« cow-boy », *cowboy*) la drague maladroitement et elle
  le mène par le bout du nez ; Mercer (« le Comptable », *the Bookkeeper*) râle
  à chacune de ses dépenses, ce qu'elle trouve « presque romantique » ; avec
  Orlov (« Micha », « mon grand ours », *Misha*, *my big bear*), doux et
  mélancolique, elle est tendre ; Arakawa (« Lieutenant ») respecte son
  intelligence, c'est le seul qui la laisse finir ses phrases ; Weissmann, qu'elle
  appelle « Otto » pour l'agacer, est son rival : il l'a engagée, elle l'a
  surpassé.
- Tics : quelques mots de suédois écrits comme ils se prononcent (FR
  « Hèrrégud », « Tak », « Skol », « Lagom », « Ya », « Oï », « Fika »,
  « Hé dô » ; EN "Herregood", "Tack", "Skoal", "Lahgom", "Yah", "Oy", "Feeka",
  "Hey doh") ; métaphores de science et d'énigme (équation, formule, hypothèse,
  réaction en chaîne) ; « mon chou », « mes chéris », « les garçons »
  (*sweetie*, *darlings*, *boys*) ; jure moins que Mercer, mais lâche de vrais
  coups de gueule quand ça tourne mal (touchée, à terre, à sec, fauchée, boîte
  ou ours), souvent suivis d'un trait d'esprit (« Putain ! À terre ! Et
  j'adorais ce pantalon. ») : « Putain ! », « Fais pas chier ! », « Et
  merde ! », « Bordel ! », en suédois « Fane ! », « Yèvlar ! » ; EN "Fuck!",
  "Shit!", "Dammit!", "Fahn!", "Yevlar!". Aucune référence à un régime ou à une
  politique réelle.
- Apparence : petite et mince, cheveux blond platine relevés en rouleaux
  « victory rolls » des années 1940, rouge à lèvres rouge, veste de terrain
  ajustée bleu canard sombre sur un chemisier crème, pantalon taille haute,
  sacoche de cuir bourrée de notes, petites boucles d'oreilles rondes, un crayon
  derrière l'oreille ; en vue FPS, mains fines à la peau claire, ongles courts
  rouges, poignets de veste bleu canard.
- Voix : claire, soufflée, souriante, la même en jeu que dans les deux
  références choisies (`tools/voices/refs/berg_fr.wav` et `berg_en.wav`,
  moteur `qwen_clone`, voir `docs/ASSETS.md`).

### 6. Georges « Jojo la Magouille » Ferrand (`jojo`)
(en anglais *Georges "Jojo the Hustler" Ferrand*)
- Parisien, la fin de la trentaine, roi de la combine et du marché noir des
  années 1940 : cigarettes, bas, essence, pièces détachées, tout ce qui se
  revend. L'Institut Aether l'a pincé quand il a essayé de lui revendre de la
  ferraille volée… dans ses propres entrepôts. Aucune identité de communauté
  ni d'origine : c'est juste un escroc des rues et une grande gueule de Paris.
- Physique : une brute énorme d'une centaine de kilos, poitrine en tonneau,
  gros ventre, cou de taureau ; il prend toute la place et le fait savoir.
- Caractère : grossier, bruyant, agressif et très drôle, menteur de profession.
  Il triche avec la boîte mystère (il la « secoue », il l'a « graissée »),
  « emprunte » les points des autres et ne rend jamais, s'attribue leurs
  éliminations, fait les poches des cadavres, promet de couvrir puis se planque
  (« Je te couvre ! De loin. »), et jure sur la vie de sa mère que c'était pas
  lui. Il voit chaque objet comme une marchandise à revendre.
- Langue : argot de rue parisien très familier, zéro politesse, jamais de
  vouvoiement de courtoisie, insultes et coups de gueule à tout bout de champ
  (« Nique ta mère ! », « Mange tes morts ! », « Ta gueule ! », « Sale
  merde ! », « Fils de pute ! », « Enculé ! », « Va te faire foutre ! »,
  « Bouffon ! ») et tics de rue (« Wesh », « frère », « sur la vie de ma
  mère », « j'te jure », « ferme-la ») ; il ne dit jamais « zombie » : ce sont
  des « sales merdes », des « pourris », des « macchabées ». EN : même
  registre, *motherfucker*, *eat shit*, *fuck you*, *son of a bitch*, *bro*,
  *swear on my mother*. La vulgarité va toujours avec une blague. Jamais
  d'insulte visant une origine, une communauté, un genre ou une sexualité, ni
  d'insulte sexuelle.
- Relations : il se moque de tout le monde, personnellement, jamais de leur
  origine : Callahan, « le cow-boy en plastique » (*the plastic cowboy*) ;
  Mercer, « le radin », « le comptable » (*the cheapskate*, *bookkeeper*), à qui
  il pique des points ; Weissmann, « le savant fou de mes deux » (*mad
  scientist my ass*), dont il compte revendre les machines en pièces ; Berg,
  « Madame je-sais-tout » (*Miss Know-It-All*) ; Orlov, « le gros nounours qui
  chiale » (*the big crybaby teddy bear*) ; Arakawa, « le prof de politesse »
  (*Mister Manners*).
- Tics : vocabulaire de fourgue (marchandise, camelote, « je te fais un
  prix », « je la revends une fortune », « gratos »), parle de lui à la
  troisième personne (« Jojo fait crédit à personne ! »).
- Apparence : casquette plate en laine, maillot de corps gris-blanc taché sous
  des bretelles, col ouvert, manches roulées, chaîne en or au cou et une dent
  en or, gros ventre, barbe de trois jours, nez cassé, une valise de
  contrebande ; plus grand et bien plus large que les autres (`PlayerModel`,
  échelle 1,1). En vue FPS : grosses mains épaisses (« slim » 1,2), avant-bras
  velus et hâlés, manche de maillot roulée gris-blanc, chevalière en or à
  l'annulaire droit.
- Voix : très grave, rauque, grotesque et agressive, une brute de cent kilos
  (moteur `qwen_clone`, références `tools/voices/refs/jojo_fr.wav` et
  `jojo_en.wav`, voir `docs/ASSETS.md`).

## Règles d'écriture

- Répliques courtes : 3 à 14 mots, 4 secondes à voix haute au plus (les
  répliques de manche et de taquinerie peuvent aller jusqu'à 20 mots).
- Chaque variante dit autre chose : pas de simple reformulation.
- Ton BO1 : humour noir, bravade, folie ; aucune insulte raciste, sexuelle ou
  visant un groupe réel ; aucune apologie d'un régime réel.
- Jurons permis, et même voulus, dans les répliques de colère, de frustration
  ou de douleur (à court de munitions, touché, à terre, fauché, mauvais tirage
  de la boîte, ours, piège ou courant en panne…) : de vrais coups de gueule,
  pas seulement des mots polis (« Putain ! », « Fais pas chier ! », « Putain de
  merde ! », « Bordel de merde ! », « Ta gueule ! » lancé aux zombies ; EN
  "Fuck!", "Shit!", "Goddammit!", "Son of a bitch!"), dans une partie des
  variantes (environ un tiers dans ces catégories). Leur dose et leur style
  dépendent du personnage. Insultes racistes, sexuelles ou visant un groupe
  toujours interdites.
- Texte prêt pour la synthèse vocale : pas d'onomatopées impossibles à lire
  (« Argh » oui, « Hnnngh » non), chiffres en toutes lettres, pas de
  parenthèses ni d'indications de jeu, ponctuation normale.
- Les mots étrangers sont écrits comme ils se prononcent dans la langue de la
  réplique (FR : « Davaï », « Bojé moï » ; EN : « Davai », « Bozhe moi »).
- Ni prix ni montant, ni lieu propre à une carte : les répliques sont jouées sur
  toutes les cartes et les prix peuvent changer. Parler d'argent en général,
  oui (« Encore des points qui s'envolent », « Ce couteau m'a coûté un bras ») ;
  un chiffre précis, non (« neuf cent cinquante points », « Ten points! »). Pas
  de théâtre, de salle de projection, de couloir ni de porte précise : « Une
  porte de plus », « Fouillez le coin » marchent partout.
- Langue parlée, familière et naturelle, comme un soldat qui parle sous le feu,
  pas comme un texte lu : phrases courtes, « on » plutôt que « nous », « ne »
  souvent omis (« j'ai pas », « c'est pas », « personne bouge »), « ça »,
  interjections (« Allez ! », « Bon sang », « Hé ! », « Ouais »), argot de
  soldat (« matos », « flingue », « bouffer », « gratos ») ; éviter les
  tournures écrites (« Rends-la digne de ce prix », « rentabilisez-les »,
  « Méthode réglementaire », « Quel gâchis »). En anglais, même esprit :
  contractions et mots parlés (« Damn », « C'mon », « Yeah! », « Outta my
  way », « Nothin' in there anyway »).

## Situations (catégories de répliques)

Clé de catégorie, déclencheur dans le jeu, nombre de variantes à écrire par
personnage (chaque variante en `fr` et en `en`).

### Éliminations
| Clé | Déclencheur | Variantes |
|---|---|---|
| `kill_headshot` | zombie tué d'une balle dans la tête | 6 |
| `kill_melee` | zombie tué au couteau | 5 |
| `kill_bowie` | zombie tué au couteau de chasse | 2 |
| `kill_explosive` | plusieurs zombies tués par une explosion | 3 |
| `kill_streak` | cinq zombies tués en quelques secondes | 5 |
| `kill_close` | zombie tué à bout portant | 3 |
| `crawler_made` | jambes arrachées : le zombie rampe | 3 |
| `kill_dog` | chien de l'enfer tué | 3 |
| `kill_ray` | zombie tué au CLAUDE-RAY | 3 |
| `kill_thunder` | zombies balayés au TONNERRE-7 | 3 |
| `kill_trap` | zombies grillés par un piège qu'il a activé | 2 |
| `kill_generic` | élimination ordinaire (rarement) | 6 |

### Munitions et armes
| Clé | Déclencheur | Variantes |
|---|---|---|
| `ammo_low` | chargeur presque vide, peu de réserve | 4 |
| `ammo_out` | plus aucune munition pour l'arme en main | 4 |
| `buy_wall` | achat d'une arme au mur | 3 |
| `buy_bowie` | achat du couteau de chasse | 2 |
| `box_good` | la boîte donne un bon fusil ou un pistolet-mitrailleur | 4 |
| `box_bad` | la boîte donne une arme décevante (pistolet, revolver) | 4 |
| `box_shotgun` | la boîte donne un fusil à pompe | 2 |
| `box_sniper` | la boîte donne un fusil de précision | 2 |
| `box_lmg` | la boîte donne une mitrailleuse | 2 |
| `box_launcher` | la boîte donne un lance-grenades ou un lance-roquettes | 2 |
| `box_ray` | la boîte donne le CLAUDE-RAY | 2 |
| `box_thunder` | la boîte donne le TONNERRE-7 | 2 |
| `box_monkey` | la boîte donne des SINGES-TAMBOURS | 2 |
| `box_teddy` | l'ours sort : la boîte s'en va | 4 |
| `box_firesale` | LIQUIDATION : boîtes à 10 points | 2 |
| `pap_upgrade` | arme déposée dans la machine d'amélioration | 3 |
| `pap_wait` | attend devant la machine d'amélioration qui travaille | 2 |
| `pap_take` | arme améliorée récupérée | 3 |
| `no_money` | achat refusé, pas assez de points | 2 |
| `no_power` | essaie une machine sans courant | 2 |
| `buy_ammo` | rachète des munitions au mur | 2 |
| `reload` | recharge (annonce à l'équipe, rarement) | 4 |

### Atouts (2 variantes chacun)
`perk_titan`, `perk_rapid`, `perk_twin`, `perk_lazarus`, `perk_stride`,
`perk_nova`, `perk_deadeye` : après avoir bu l'atout (le goût, l'effet, une
blague sur le nom).

### Bonus (2 variantes chacun)
`pw_max_ammo`, `pw_insta_kill`, `pw_double_points`, `pw_nuke`, `pw_carpenter`,
`pw_fire_sale`, `pw_death_machine` : juste après l'annonce du bonus ramassé.

### À terre et réanimation
| Clé | Déclencheur | Variantes |
|---|---|---|
| `downed` | il tombe à terre | 4 |
| `revive_start` | il commence à réanimer un coéquipier | 4 |
| `revived` | il vient d'être réanimé (remercie à sa façon) | 4 |
| `downed_help` | toujours à terre, appelle à l'aide | 3 |
| `death` | il saigne jusqu'à la mort : derniers mots, cri | 3 |
| `teammate_down` | un coéquipier tombe à terre | 3 |
| `teammate_dead` | un coéquipier meurt (saigne jusqu'à la mort) | 2 |
| `last_alive` | il est le dernier debout | 2 |

### Manches et carte
| Clé | Déclencheur | Variantes |
|---|---|---|
| `game_start` | début de partie | 3 |
| `round_start` | début de manche | 6 |
| `dog_round` | début d'une manche des chiens | 3 |
| `door_open` | il ouvre une porte | 3 |
| `power_on` | le courant est rétabli | 2 |
| `teleporter_link` | il relie le téléporteur au poste central | 2 |
| `teleport_out` | arrivée dans la salle de projection | 2 |
| `teleport_back` | retour au poste central | 2 |
| `trap_on` | il active un piège | 2 |

### Danger et lancers
| Clé | Déclencheur | Variantes |
|---|---|---|
| `low_health` | santé très basse | 4 |
| `surrounded` | encerclé (beaucoup de zombies tout près) | 4 |
| `hurt` | frappé par un zombie ou mordu (cri, juron très court : 1 à 4 mots) | 6 |
| `exert_melee` | donne un coup de couteau (souffle, cri d'effort : 1 à 3 mots) | 4 |
| `oh_shit` | un zombie surgit juste derrière lui | 3 |
| `crawler_near` | un rampant tout près, au ras du sol | 2 |
| `throw_grenade` | lance une grenade | 3 |
| `throw_monkey` | lance un SINGE-TAMBOUR | 2 |

### Calme et taquineries
| Clé | Déclencheur | Variantes |
|---|---|---|
| `idle` | moment de calme (aucun zombie proche depuis un moment) | 10 |
| `resp_box_bad` | un coéquipier tire une arme décevante de la boîte : moquerie | 2 |
| `resp_wonder` | un coéquipier tire une arme spéciale de la boîte : envie | 2 |
| `tease_callahan`, `tease_orlov`, `tease_arakawa`, `tease_weissmann`, `tease_mercer`, `tease_berg`, `tease_jojo` | réflexion sur ce coéquipier, en début de manche s'il est dans la partie (pas de clé pour soi-même) | 2 chacune |

Les taquineries visant les derniers venus ne sont écrites que par ceux qui
sont arrivés après eux (`VoxSystem` ignore une catégorie absente) :
`tease_mercer` existe pour Berg et Jojo (pas pour les quatre premiers),
`tease_berg` pour Jojo seulement, et `tease_jojo` pour personne encore : Jojo
taquine les six autres, mais personne ne le taquine.

Total : 229 répliques par personnage et par langue pour les quatre premiers,
231 pour Mercer, 233 pour Berg, 235 pour Jojo (3 230 fichiers en tout une fois
les voix de Berg et de Jojo générées ; 2 294 sans elles).

Les cris (`hurt`, `exert_melee`, une partie de `death`) restent des mots ou des
exclamations lisibles par la synthèse (« Argh ! », « Aïe, bon sang ! »), propres
à chaque personnage (juron texan, mot russe, souffle retenu, gloussement).

## Fichiers

- Répliques : `assets/voices/<personnage>.json` :
  `{"character": "callahan", "lines": {"kill_headshot": [{"fr": "…", "en": "…"}, …], …}}`
- Voix générées : `assets/audio/vox/<langue>/<personnage>/<catégorie>_<n>.ogg`,
  par `tools/voices/make_voices.py` (Chatterbox Multilingual + voix de référence
  Kokoro ; Mercer, Berg et Jojo : clonage Qwen3-TTS de leurs deux références,
  `tools/voices/qwen_clone.py` ; voir `docs/ASSETS.md`). Un personnage marqué
  `"pending_audio": true` dans `tools/voices/cast.json` (voix pas encore
  générées) est dispensé de la vérification « toutes les voix présentes » de
  `tests/test_vox.gd` (ses fichiers orphelins restent refusés) ; retirer la
  marque quand ses voix sont générées.
- Jeu : `CharacterDB` (personnage de chaque joueur, textes, fichiers),
  `VoxSystem` (nœud `/root/Game/Vox` : le serveur choisit la réplique, chaque
  machine la joue en 3D sur le joueur qui parle, en 2D pour soi), réglage
  « Langue / Language » des options.
