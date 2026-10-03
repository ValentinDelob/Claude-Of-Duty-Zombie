class_name MapCatalog
extends RefCounted
## Inventaire de l'éditeur de cartes (façon Minecraft) : catégories et objets
## que l'on peut poser. Les atouts, armes murales, pièges et prix viennent des
## bases de données du jeu (PerkDB, WeaponDB, KnifeDB, ElectricTrap...) :
## ajouter un atout ou une arme au jeu l'ajoute à l'inventaire.
##
## Un objet du catalogue : {id, cat, fr, en, tool, make (modèle de l'objet
## posé), fp (emprise en cases de 0,5 m : [le long du mur, profondeur] ou
## [côté, côté]), color, price}.
## Outils : select, erase, room_rect, room_poly, wall, rect (pilier, escalier,
## zone de piège), poly (objet tracé en polygone : barrière invisible), opening
## (porte, débris, fenêtre...), wall_item (contre un mur), floor_item (au sol,
## dans une pièce).
##
## Décor (PREFABS) et luminaires (LIGHTS) sont décrits ICI seulement : l'éditeur
## (pose, icônes, propriétés), le validateur, l'export en maillage et le jeu
## (MeshMapBuilder, EditorPrefabs) lisent ces tables. Les types et valeurs
## admis dans les fichiers d'une carte sont donnés par allowed_kinds(),
## allowed_surfaces(), room_keys() et zone_keys() (contrôle des cartes
## partagées, docs/MAP_AUTHORING.md §6).

## Sous-onglets des effets (format 10) : [identifiant, nom FR, nom EN].
const EFFECT_SUBS := [
	["flammes", "Flammes", "Flames"],
	["fumees", "Fumées", "Smoke"],
	["etincelles", "Étincelles", "Sparks"],
	["electricite", "Électricité", "Electricity"],
	["eau", "Eau", "Water"],
	["ambiance", "Ambiance", "Atmosphere"],
]
## Catégories de l'inventaire : [identifiant, nom FR, nom EN] et, en option,
## une liste de sous-onglets [[identifiant, FR, EN], ...] (subs_of) : les
## objets de la catégorie ont alors une clé « sub ».
const CATEGORIES := [
	["construction", "Construction", "Building"],
	["ouvertures", "Ouvertures", "Openings"],
	["atouts", "Atouts", "Perks"],
	["armes", "Armes murales", "Wall weapons"],
	["boite", "Boîte mystère", "Mystery box"],
	["machines", "Machines", "Machines"],
	["pieges", "Pièges", "Traps"],
	["joueurs", "Joueurs et apparitions", "Players and spawns"],
	["prefabs", "Décor et obstacles", "Props and obstacles"],
	# Format 10 : prefabs propres à la carte (dossier prefabs/ de la carte, MapPrefabLib).
	["prefabs_carte", "Prefabs de la carte", "Map prefabs"],
	["lumieres", "Luminaires", "Light fixtures"],
	["effets", "Effets", "Effects", EFFECT_SUBS],
]
## Barre rapide par défaut (9 cases). La souris (« select ») n'y est pas : elle
## a sa case fixe à gauche de la barre (MapHotbar).
const DEFAULT_HOTBAR := ["escalier", "piece_rect", "piece_poly", "mur", "porte", "fenetre", "boite", "depart", "arme:m14"]
## Prix BO1 des portes successives (750, puis 1000, puis 1250).
const DOOR_PRICES := [750, 1000, 1250]

## Décor posé au sol (type « prefab » de objets.json), un par identifiant :
##   fp       emprise en cases de 0,5 m [largeur (x), profondeur (y)] à rot = 0
##   h        hauteur (m), pour l'aperçu
##   bloque   « solide » (arrête joueurs, zombies et balles), « barriere »
##            (arrête joueurs et zombies, les balles passent) ou « non »
##            (on marche dessus : aucune collision)
##   model    modèle assets/models/kino/<model>.glb (sinon `build` : objet
##            construit par le jeu, EditorPrefabs) ; scale, remap (matériaux
##            remplacés), copies [[x, z, lacet]] (le modèle répété)
##   boxes    pavés de collision {center, size, yaw} en coordonnées de
##            l'objet (sinon <model>.collision.json) : TOUJOURS des
##            CollisionBox, jamais une collision de modèle Blender
##   support  hauteur du dessus (m) : une lampe de bureau ou des bougies
##            peuvent y être posées
##   mount    format 11 : « mur » (contre un mur, comme une applique : hauteur
##            `y` par défaut, clé « hauteur » de l'objet posé ; origine de
##            l'objet sur la face du mur, +z vers la pièce) ou « plafond »
##            (accroché sous le plafond ; origine au plafond) ; absent : au sol
## Format 11 : décors qui accompagnent les effets (ils étaient construits avec
## l'effet avant, ils sont maintenant posés à part, MapCatalog.EFFECTS.decor).
const RUBBLE_REMAP := {"wall_theater": "concrete", "velvet": "fabric", "ceiling_theater": "concrete_dark"}
const PREFABS := {
	"gravats": {"fr": "Tas de gravats", "en": "Rubble heap", "fp": [6, 6], "h": 1.5, "bloque": "solide",
		"model": "rubble_heap_b", "remap": RUBBLE_REMAP, "color": Color(0.55, 0.52, 0.48)},
	"gros_gravats": {"fr": "Gros éboulement", "en": "Big rubble pile", "fp": [10, 8], "h": 2.3, "bloque": "solide",
		"model": "rubble_heap_a", "remap": RUBBLE_REMAP, "color": Color(0.5, 0.47, 0.44)},
	"eboulis": {"fr": "Mur effondré", "en": "Collapsed wall", "fp": [12, 6], "h": 2.9, "bloque": "solide",
		"model": "rubble_heap_c", "remap": RUBBLE_REMAP, "color": Color(0.45, 0.42, 0.4)},
	"debris_epars": {"fr": "Débris épars (au sol)", "en": "Scattered debris (floor)", "fp": [6, 6], "h": 0.25, "bloque": "non",
		"model": "debris_scatter", "remap": RUBBLE_REMAP, "color": Color(0.6, 0.58, 0.5)},
	"planches": {"fr": "Planches au sol", "en": "Planks on the floor", "fp": [4, 3], "h": 0.4, "bloque": "non",
		"model": "debris_planks", "color": Color(0.55, 0.38, 0.2)},
	"poutre": {"fr": "Poutre tombée", "en": "Fallen beam", "fp": [14, 4], "h": 1.8, "bloque": "solide",
		"model": "debris_beam", "remap": RUBBLE_REMAP, "color": Color(0.42, 0.4, 0.42)},
	"lustre_tombe": {"fr": "Lustre tombé", "en": "Fallen chandelier", "fp": [7, 6], "h": 1.5, "bloque": "barriere",
		"model": "chandelier_fallen", "color": Color(0.85, 0.7, 0.35)},
	"caisses": {"fr": "Pile de caisses", "en": "Stacked crates", "fp": [5, 4], "h": 1.5, "bloque": "solide",
		"model": "stage_crates", "color": Color(0.4, 0.45, 0.4)},
	"tonneaux": {"fr": "Tonneaux", "en": "Drums", "fp": [4, 4], "h": 1.8, "bloque": "barriere",
		"model": "blue_barrel_group", "color": Color(0.2, 0.3, 0.6)},
	"sacs_sable": {"fr": "Sacs de sable", "en": "Sandbags", "fp": [4, 2], "h": 0.9, "bloque": "solide",
		"build": "sacs_sable", "surface": "fabric", "boxes": [{"center": [0, 0.45, 0], "size": [2.0, 0.9, 0.8]}], "support": 0.9, "color": Color(0.6, 0.55, 0.4)},
	"table_renversee": {"fr": "Table renversée", "en": "Overturned table", "fp": [4, 2], "h": 0.9, "bloque": "solide",
		"build": "table_renversee", "surface": "wood", "boxes": [{"center": [0, 0.42, 0.25], "size": [1.6, 0.85, 0.12]}, {"center": [0, 0.3, -0.1], "size": [1.5, 0.6, 0.6]}],
		"color": Color(0.45, 0.28, 0.15)},
	"chaise_renversee": {"fr": "Chaise renversée", "en": "Overturned chair", "fp": [2, 1], "h": 0.5, "bloque": "barriere",
		"build": "chaise_renversee", "surface": "wood", "boxes": [{"center": [0, 0.22, 0], "size": [0.9, 0.45, 0.45]}], "color": Color(0.5, 0.35, 0.2)},
	"chaise": {"fr": "Chaise pliante", "en": "Folding chair", "fp": [1, 1], "h": 0.9, "bloque": "barriere",
		"model": "folding_chair", "surface": "wood", "boxes": [{"center": [0, 0.43, 0], "size": [0.44, 0.87, 0.45]}], "color": Color(0.55, 0.45, 0.3)},
	"bureau": {"fr": "Bureau", "en": "Desk", "fp": [3, 2], "h": 0.8, "bloque": "solide", "model": "desk", "support": 0.78,
		"color": Color(0.35, 0.22, 0.12)},
	"etagere": {"fr": "Étagère", "en": "Shelf", "fp": [3, 1], "h": 1.8, "bloque": "solide", "model": "reel_shelf",
		"color": Color(0.35, 0.36, 0.38)},
	"fauteuils": {"fr": "Rangée de fauteuils de cinéma", "en": "Row of cinema seats", "fp": [5, 2], "h": 1.1, "bloque": "barriere",
		"model": "seat", "copies": [[-0.84, 0, 0], [-0.28, 0, 0], [0.28, 0, 0], [0.84, 0, 0]],
		"surface": "fabric", "boxes": [{"center": [0, 0.5, 0], "size": [2.24, 1.0, 0.6]}], "color": Color(0.5, 0.06, 0.07)},
	"fauteuil_casse": {"fr": "Fauteuil arraché", "en": "Torn-out seat", "fp": [2, 3], "h": 0.7, "bloque": "barriere",
		"model": "seat_broken_b", "surface": "fabric", "boxes": [{"center": [0, 0.32, 0], "size": [0.7, 0.63, 1.2]}], "color": Color(0.45, 0.05, 0.06)},
	"pupitre": {"fr": "Pupitre", "en": "Lectern", "fp": [2, 2], "h": 1.2, "bloque": "solide", "model": "lectern", "color": Color(0.3, 0.18, 0.1)},
	"projecteur_film": {"fr": "Projecteur de cinéma", "en": "Film projector", "fp": [2, 3], "h": 1.9, "bloque": "solide",
		"model": "projector", "color": Color(0.3, 0.32, 0.33)},
	"chariot": {"fr": "Chariot", "en": "Cart", "fp": [3, 2], "h": 1.0, "bloque": "solide", "build": "chariot", "surface": "metal",
		"boxes": [{"center": [0, 0.5, 0], "size": [1.3, 1.0, 0.75]}], "support": 0.85, "color": Color(0.4, 0.42, 0.45)},
	"epave_voiture": {"fr": "Épave de voiture", "en": "Car wreck", "fp": [9, 4], "h": 1.5, "bloque": "solide", "build": "epave_voiture", "surface": "metal",
		"boxes": [{"center": [0, 0.5, 0], "size": [4.3, 1.0, 1.8]}, {"center": [-0.2, 1.2, 0], "size": [2.2, 0.6, 1.6]}], "color": Color(0.35, 0.4, 0.35)},
	# Format 11 : décors des effets (feu, électricité, eau), construits par le jeu.
	"buches": {"fr": "Bûches (feu de bois)", "en": "Logs (wood fire)", "fp": [1, 1], "h": 0.15, "bloque": "non", "build": "buches", "surface": "wood",
		"color": Color(0.4, 0.2, 0.1)},
	"foyer_pierres": {"fr": "Foyer de pierres", "en": "Stone fire pit", "fp": [3, 3], "h": 0.3, "bloque": "barriere", "build": "foyer_pierres", "surface": "stone",
		"boxes": [{"center": [0, 0.5, 0], "size": [1.3, 1.0, 1.3]}], "color": Color(0.45, 0.42, 0.4)},
	"planches_brulees": {"fr": "Planches calcinées", "en": "Charred planks", "fp": [5, 2], "h": 0.1, "bloque": "non", "build": "planches_brulees",
		"surface": "wood", "color": Color(0.2, 0.15, 0.12)},
	"electrodes": {"fr": "Électrodes", "en": "Electrodes", "fp": [3, 1], "h": 1.1, "bloque": "barriere", "build": "electrodes", "surface": "metal",
		"boxes": [{"center": [-0.62, 0.55, 0], "size": [0.2, 1.1, 0.2]}, {"center": [0.62, 0.55, 0], "size": [0.2, 1.1, 0.2]}], "color": Color(0.6, 0.45, 0.3)},
	"bobine_tesla": {"fr": "Bobine Tesla", "en": "Tesla coil", "fp": [1, 1], "h": 1.55, "bloque": "solide", "build": "bobine_tesla", "surface": "metal",
		"boxes": [{"center": [0, 0.78, 0], "size": [0.4, 1.55, 0.4]}], "color": Color(0.7, 0.45, 0.28)},
	"flaque_eau": {"fr": "Flaque d'eau", "en": "Water puddle", "fp": [3, 3], "h": 0.01, "bloque": "non", "build": "flaque_eau", "surface": "tiles",
		"color": Color(0.25, 0.38, 0.5)},
	"petite_flaque": {"fr": "Petite flaque", "en": "Small puddle", "fp": [2, 2], "h": 0.01, "bloque": "non", "build": "petite_flaque", "surface": "tiles",
		"color": Color(0.3, 0.45, 0.6)},
	"torche_murale": {"fr": "Torche murale", "en": "Wall torch", "fp": [1, 1], "h": 0.5, "bloque": "non", "mount": "mur", "y": 1.8, "build": "torche_murale",
		"surface": "wood", "color": Color(0.55, 0.35, 0.18)},
	"tuyau_vapeur": {"fr": "Tuyau à vapeur", "en": "Steam pipe", "fp": [1, 1], "h": 0.2, "bloque": "non", "mount": "mur", "y": 1.2, "build": "tuyau_vapeur",
		"surface": "metal", "color": Color(0.5, 0.5, 0.5)},
	"boitier_electrique": {"fr": "Boîtier électrique ouvert", "en": "Open electrical box", "fp": [1, 1], "h": 0.45, "bloque": "non", "mount": "mur", "y": 1.6,
		"build": "boitier_electrique", "surface": "metal", "color": Color(0.35, 0.4, 0.33)},
	"tuyau_fuite": {"fr": "Tuyau qui fuit", "en": "Leaking pipe", "fp": [2, 1], "h": 0.2, "bloque": "non", "mount": "mur", "y": 2.0, "build": "tuyau_fuite",
		"surface": "metal", "color": Color(0.5, 0.3, 0.18)},
	"cable_suspendu": {"fr": "Câble suspendu", "en": "Hanging cable", "fp": [1, 1], "h": 0.65, "bloque": "non", "mount": "plafond", "build": "cable_suspendu",
		"surface": "metal", "color": Color(0.2, 0.2, 0.22)},
}

## Luminaires (type « luminaire » de objets.json). Ils passent par le code
## commun des lampes (MapProps.add_lamp : courant, grésillement, RenderQuality).
##   mount     « plafond » (accroché sous le plafond), « mur » (applique,
##             contre un mur) ou « sol » (posé, éventuellement sur un meuble
##             qui a un `support`)
##   fp        emprise en cases (comme les prefabs)
##   drop      plafond : distance (m) de la lumière sous le plafond ;
##   y         mur / sol : hauteur (m) de la lumière
##   couleur, intensite, portee, courant, vacille : valeurs par défaut
##   bloque    (sol) comme les prefabs, avec ses pavés `boxes`
## Réglages d'un luminaire posé : couleur « #rrggbb », intensite (x),
## portee (m), courant (s'allume avec le courant ; sinon toujours allumé),
## vacille (grésille).
const LIGHT_LIMITS := {"intensite": [0.1, 4.0], "portee": [2.0, 20.0]}
const LIGHTS := {
	"ampoule": {"fr": "Ampoule nue", "en": "Bare bulb", "mount": "plafond", "fp": [1, 1], "drop": 0.75,
		"couleur": "#ffd9a0", "intensite": 1.6, "portee": 8.0, "courant": true, "vacille": false, "build": "ampoule", "color": Color(1.0, 0.85, 0.55)},
	"suspension": {"fr": "Suspension", "en": "Pendant lamp", "mount": "plafond", "fp": [1, 1], "drop": 0.7,
		"couleur": "#ffc88a", "intensite": 2.2, "portee": 10.0, "courant": true, "vacille": false, "build": "suspension", "color": Color(0.95, 0.75, 0.4)},
	"neon": {"fr": "Néon", "en": "Fluorescent tube", "mount": "plafond", "fp": [3, 1], "drop": 0.15,
		"couleur": "#dcebff", "intensite": 2.0, "portee": 10.0, "courant": true, "vacille": false, "build": "neon", "color": Color(0.8, 0.9, 1.0)},
	"lustre": {"fr": "Lustre", "en": "Chandelier", "mount": "plafond", "fp": [3, 3], "drop": 1.1,
		"couleur": "#ffd6a0", "intensite": 2.8, "portee": 12.0, "courant": true, "vacille": false, "model": "chandelier", "scale": 0.25,
		"color": Color(1.0, 0.8, 0.45)},
	"applique": {"fr": "Applique murale", "en": "Wall sconce", "mount": "mur", "fp": [1, 1], "y": 2.0,
		"couleur": "#ffc080", "intensite": 1.4, "portee": 7.0, "courant": true, "vacille": false, "model": "sconce", "color": Color(0.9, 0.7, 0.35)},
	"lampe_bureau": {"fr": "Lampe de bureau", "en": "Desk lamp", "mount": "sol", "fp": [1, 1], "y": 0.45,
		"couleur": "#ffe0b0", "intensite": 0.9, "portee": 5.0, "courant": true, "vacille": false, "build": "lampe_bureau", "bloque": "non",
		"color": Color(0.35, 0.55, 0.35)},
	"projecteur": {"fr": "Projecteur de chantier", "en": "Work floodlight", "mount": "sol", "fp": [2, 2], "y": 1.7,
		"couleur": "#fff4e0", "intensite": 3.0, "portee": 14.0, "courant": true, "vacille": false, "build": "projecteur", "bloque": "barriere",
		"boxes": [{"center": [0, 0.85, 0], "size": [0.7, 1.7, 0.7]}], "color": Color(0.95, 0.8, 0.2)},
	"bougies": {"fr": "Bougies", "en": "Candles", "mount": "sol", "fp": [1, 1], "y": 0.25,
		"couleur": "#ff9a40", "intensite": 0.7, "portee": 4.5, "courant": false, "vacille": true, "build": "bougies", "bloque": "non",
		"color": Color(1.0, 0.6, 0.25)},
	"feu": {"fr": "Brasero (feu)", "en": "Fire barrel", "mount": "sol", "fp": [2, 2], "y": 1.15,
		"couleur": "#ff7a2a", "intensite": 2.4, "portee": 9.0, "courant": false, "vacille": true, "build": "feu", "bloque": "solide",
		"boxes": [{"center": [0, 0.45, 0], "size": [0.62, 0.9, 0.62]}], "color": Color(1.0, 0.45, 0.1)},
}

## Effets (format 10, type « effet » de objets.json, docs/MAP_OBJECTS.md §
## 12) : flammes, fumées, étincelles, électricité, eau, ambiance. Format 11 :
## des EFFETS PURS, construits par le jeu (MapEffects) : particules, lumières
## animées, arcs électriques ; AUCUN objet (bûches, torche, tuyau, flaque...
## sont des décors de l'onglet Décor, PREFABS) et AUCUNE collision : ils ne
## gênent ni ne blessent personne et se posent par-dessus n'importe quoi.
##   sub     sous-onglet (EFFECT_SUBS)
##   mount   « sol » (au sol, ou surélevé : `y`), « mur » (contre un mur, à la
##           hauteur `y`, dirigé vers la pièce) ou « plafond » (sous le plafond)
##   zone    ZONE de l'effet (format 11), en mètres : {dimension: [défaut,
##           min, max]}. « l » largeur (axe x de l'effet ; le long du mur pour
##           un effet mural), « p » profondeur (axe z, effets au sol et au
##           plafond), « h » hauteur (volume d'un effet au sol : poussière,
##           brouillard... ; étendue verticale d'un effet mural). Zone par
##           défaut : l'étendue de l'effet d'avant le format 11.
##   vol     VOLUME de l'effet (effect_volume) : TOUT ce qu'il affiche y
##           reste, et c'est la boîte dessinée dans l'éditeur. Hauteur (m)
##           d'un effet au sol sans « h » (de sa hauteur de pose vers le
##           haut) ou au plafond (du plafond vers le bas) ; « sol » : jusqu'au
##           sol (effet au plafond ou mural dont les gouttes ou étincelles
##           tombent par terre) ; « plafond » : jusqu'au plafond (effet au
##           sol : cendres). Sans « vol » : la hauteur « h » de la zone.
##   ancre   effet mural porté par un décor mural : sa hauteur est celle du
##           décor + `ancre` m, bornée comme lui (flamme de torche)
##   appui   effet au sol posé SUR quelque chose (flammes de baril) : le bas
##           de son volume est caché comme le sol (MapEffects)
##   reach   effet mural : distance (m) où il porte dans la pièce (dessin)
##   cap     particules au plus pour cet effet (la densité suit la surface
##           de la zone jusqu'à ce plafond, MapEffects)
##   decor   format 11 : décor (PREFABS) que construisait l'effet avant ; une
##           carte d'un format plus ancien le reçoit à côté de l'effet
##           (split_legacy_effect)
##   y       sol : hauteur par défaut au-dessus du sol ; mur : hauteur (m)
##   couleur teinte par défaut (« #rrggbb ») : seuls ces effets se teintent
## Les effets au sol et au plafond pivotent (R, poignée, angle libre) ; un
## effet mural suit son mur.
## Réglages d'un effet posé (tous facultatifs, jamais écrits à leur valeur
## par défaut, tidy_effect) : intensite (x, quantité de particules et
## lumière), zone, couleur, hauteur (m), rot. « taille » (x, avant le format
## 11) est lue et convertie en zone (zone par défaut × taille).
const EFFECT_LIMITS := {"intensite": [0.25, 2.0], "taille": [0.5, 2.5], "hauteur": [0.0, 30.0]}
## Bornes absolues d'une dimension de zone (m) : celles de chaque effet sont
## dans EFFECTS (clé « zone »). Pas d'une dimension réglée à la main.
const ZONE_LIMITS := [0.1, 40.0]
const ZONE_STEP := 0.05
## Effets au plus par carte (coût des particules, MapEffects.PARTICLE_BUDGET).
const MAX_EFFECTS := CustomMapGuard.MAX_EFFECTS
const EFFECTS := {
	# Flammes.
	"petit_feu": {"sub": "flammes", "fr": "Petit feu", "en": "Small fire", "mount": "sol", "vol": 1.5, "zone": {"l": [0.6, 0.3, 3.0], "p": [0.6, 0.3, 3.0]},
		"cap": 400, "decor": ["buches"], "color": Color(1.0, 0.55, 0.15),
		"hint_fr": "Petites flammes et braises (bûches : onglet Décor)", "hint_en": "Small flames and embers (logs: Props tab)"},
	"brasier": {"sub": "flammes", "fr": "Grand feu", "en": "Bonfire", "mount": "sol", "vol": 2.6, "zone": {"l": [1.2, 0.6, 4.0], "p": [1.2, 0.6, 4.0]},
		"cap": 600, "decor": ["foyer_pierres"], "color": Color(1.0, 0.45, 0.1),
		"hint_fr": "Hautes flammes, braises et fumée (foyer de pierres : onglet Décor)", "hint_en": "Tall flames, embers and smoke (stone fire pit: Props tab)"},
	"baril_feu": {"sub": "flammes", "fr": "Flammes de baril", "en": "Barrel flames", "mount": "sol", "y": 0.9, "vol": 1.3, "appui": true, "zone": {"l": [0.6, 0.3, 1.5], "p": [0.6, 0.3, 1.5]},
		"cap": 300, "color": Color(1.0, 0.5, 0.2),
		"hint_fr": "Flammes à poser sur un baril (0,9 m de haut par défaut)", "hint_en": "Flames to put on a barrel (0.9 m high by default)"},
	"torche": {"sub": "flammes", "fr": "Flamme de torche", "en": "Torch flame", "mount": "mur", "y": 2.25, "ancre": 0.45, "zone": {"l": [0.3, 0.2, 0.6], "h": [0.6, 0.3, 0.8]},
		"reach": 0.5, "cap": 120, "decor": ["torche_murale"], "color": Color(1.0, 0.65, 0.25),
		"hint_fr": "Flamme vive au bout d'une torche (torche murale : onglet Décor)", "hint_en": "Lively flame at the tip of a torch (wall torch: Props tab)"},
	"incendie": {"sub": "flammes", "fr": "Incendie", "en": "Blaze", "mount": "sol", "vol": 3.2, "zone": {"l": [3.0, 1.0, 12.0], "p": [2.0, 1.0, 12.0]},
		"cap": 1200, "decor": ["planches_brulees"], "color": Color(0.95, 0.35, 0.08),
		"hint_fr": "Nappe de feu et épaisse fumée, de la taille de sa zone", "hint_en": "Sheet of fire and thick smoke, as big as its zone"},
	# Fumées.
	"fumee_legere": {"sub": "fumees", "fr": "Fumée légère", "en": "Light smoke", "mount": "sol", "vol": 2.5, "zone": {"l": [2.0, 0.5, 20.0], "p": [2.0, 0.5, 20.0]},
		"cap": 500, "couleur": "#6e6c6a", "color": Color(0.65, 0.65, 0.65),
		"hint_fr": "Volutes grises qui montent lentement", "hint_en": "Grey wisps slowly rising"},
	"fumee_noire": {"sub": "fumees", "fr": "Fumée noire épaisse", "en": "Thick black smoke", "mount": "sol", "vol": 3.5, "zone": {"l": [2.5, 0.5, 20.0], "p": [2.5, 0.5, 20.0]},
		"cap": 600, "color": Color(0.3, 0.3, 0.32),
		"hint_fr": "Colonne de fumée noire, braises au pied", "hint_en": "Column of black smoke, embers at its foot"},
	"vapeur": {"sub": "fumees", "fr": "Jet de vapeur", "en": "Steam jet", "mount": "mur", "y": 1.2, "zone": {"l": [0.6, 0.2, 4.0], "h": [0.6, 0.2, 2.0]},
		"reach": 1.5, "cap": 400, "decor": ["tuyau_vapeur"], "color": Color(0.85, 0.9, 0.95),
		"hint_fr": "Jet de vapeur sous pression sortant du mur (tuyau : onglet Décor)", "hint_en": "Pressurised steam jet out of the wall (pipe: Props tab)"},
	"brouillard": {"sub": "fumees", "fr": "Brouillard au sol", "en": "Ground fog", "mount": "sol",
		"zone": {"l": [4.0, 2.0, 40.0], "p": [4.0, 2.0, 40.0], "h": [0.6, 0.3, 3.0]}, "cap": 700, "couleur": "#8e9aa6", "color": Color(0.6, 0.68, 0.75),
		"hint_fr": "Nappe de brume rampante, sur toute sa zone", "hint_en": "Creeping mist over its whole zone"},
	# Étincelles.
	"pluie_etincelles": {"sub": "etincelles", "fr": "Pluie d'étincelles", "en": "Spark shower", "mount": "plafond", "vol": "sol", "zone": {"l": [1.5, 0.3, 6.0], "p": [1.5, 0.3, 6.0]},
		"cap": 500, "decor": ["cable_suspendu"], "color": Color(1.0, 0.8, 0.3),
		"hint_fr": "Gerbes d'étincelles qui tombent et rebondissent au sol (câble : onglet Décor)", "hint_en": "Showers of sparks falling and bouncing on the floor (cable: Props tab)"},
	"soudure": {"sub": "etincelles", "fr": "Gerbe de soudure", "en": "Welding sparks", "mount": "mur", "y": 1.3, "vol": "sol", "zone": {"l": [1.0, 0.2, 3.0], "h": [0.4, 0.2, 2.0]},
		"reach": 1.6, "cap": 500, "color": Color(0.75, 0.85, 1.0),
		"hint_fr": "Gerbe continue et éclats bleutés, par à-coups", "hint_en": "Steady spray and bluish flashes, in bursts"},
	"court_circuit": {"sub": "etincelles", "fr": "Court-circuit", "en": "Short circuit", "mount": "mur", "y": 1.6, "vol": "sol", "zone": {"l": [0.8, 0.2, 2.0], "h": [0.5, 0.2, 2.0]},
		"reach": 1.2, "cap": 400, "decor": ["boitier_electrique"], "color": Color(0.9, 0.9, 0.5),
		"hint_fr": "Claquements, étincelles et arcs de temps en temps (boîtier : onglet Décor)", "hint_en": "Pops, sparks and arcs now and then (electrical box: Props tab)"},
	# Électricité.
	"arc": {"sub": "electricite", "fr": "Arc électrique", "en": "Electric arc", "mount": "sol", "y": 0.7, "vol": 0.6, "zone": {"l": [1.5, 0.5, 6.0], "p": [0.4, 0.2, 2.0]},
		"cap": 200, "decor": ["electrodes"], "couleur": "#8fb4ff", "color": Color(0.55, 0.7, 1.0),
		"hint_fr": "Arc crépitant d'un bout à l'autre de sa zone (électrodes : onglet Décor)", "hint_en": "Crackling arc from one end of its zone to the other (electrodes: Props tab)"},
	"tesla": {"sub": "electricite", "fr": "Arcs en boule", "en": "Arc burst", "mount": "sol", "y": 0.6, "vol": 1.6, "zone": {"l": [2.4, 0.6, 6.0], "p": [2.4, 0.6, 6.0]},
		"cap": 200, "decor": ["bobine_tesla"], "couleur": "#a6b4ff", "color": Color(0.65, 0.6, 1.0),
		"hint_fr": "Décharges dans toutes les directions jusqu'au bord de sa zone (bobine Tesla : onglet Décor)", "hint_en": "Discharges in every direction up to the edge of its zone (Tesla coil: Props tab)"},
	"cable_nu": {"sub": "electricite", "fr": "Étincelles de câble", "en": "Cable sparks", "mount": "plafond", "vol": "sol", "zone": {"l": [1.0, 0.3, 3.0], "p": [1.0, 0.3, 3.0]},
		"cap": 200, "decor": ["cable_suspendu"], "couleur": "#8fb4ff", "color": Color(0.45, 0.6, 1.0),
		"hint_fr": "Crépitements et étincelles au bout d'un câble pendant (câble : onglet Décor)", "hint_en": "Crackles and sparks at the tip of a hanging cable (cable: Props tab)"},
	# Eau.
	"goutte": {"sub": "eau", "fr": "Goutte-à-goutte", "en": "Dripping water", "mount": "plafond", "vol": "sol", "zone": {"l": [0.5, 0.3, 6.0], "p": [0.5, 0.3, 6.0]},
		"cap": 300, "decor": ["petite_flaque"], "color": Color(0.5, 0.7, 0.95),
		"hint_fr": "Gouttes du plafond et ronds au sol, sur toute sa zone", "hint_en": "Drops from the ceiling and ripples on the floor, over its whole zone"},
	"fuite": {"sub": "eau", "fr": "Filet d'eau", "en": "Water stream", "mount": "mur", "y": 2.0, "vol": "sol", "zone": {"l": [0.3, 0.1, 3.0], "h": [0.4, 0.1, 1.0]},
		"reach": 1.2, "cap": 400, "decor": ["tuyau_fuite", "petite_flaque"], "color": Color(0.4, 0.6, 0.85),
		"hint_fr": "Filet d'eau qui tombe du mur et éclabousse (tuyau, flaque : onglet Décor)", "hint_en": "Stream of water falling from the wall and splashing (pipe, puddle: Props tab)"},
	"flaque": {"sub": "eau", "fr": "Ronds dans l'eau", "en": "Water ripples", "mount": "sol", "vol": 0.15, "zone": {"l": [1.5, 0.5, 10.0], "p": [1.0, 0.5, 10.0]},
		"cap": 200, "decor": ["flaque_eau"], "color": Color(0.3, 0.45, 0.6),
		"hint_fr": "Ronds qui s'étalent sur l'eau (flaque : onglet Décor)", "hint_en": "Rings spreading on the water (puddle: Props tab)"},
	# Ambiance.
	"poussiere": {"sub": "ambiance", "fr": "Poussière en suspension", "en": "Floating dust", "mount": "sol",
		"zone": {"l": [3.0, 1.0, 30.0], "p": [3.0, 1.0, 30.0], "h": [2.0, 0.5, 8.0]}, "cap": 1500, "color": Color(0.85, 0.8, 0.65),
		"hint_fr": "Grains de poussière dans l'air, dans tout le volume de sa zone", "hint_en": "Dust motes in the air, through its whole zone"},
	"braises": {"sub": "ambiance", "fr": "Braises flottantes", "en": "Floating embers", "mount": "sol", "vol": 2.5, "zone": {"l": [2.0, 0.5, 20.0], "p": [2.0, 0.5, 20.0]},
		"cap": 800, "color": Color(1.0, 0.4, 0.1),
		"hint_fr": "Braises qui s'élèvent en tourbillonnant", "hint_en": "Embers swirling upwards"},
	"cendres": {"sub": "ambiance", "fr": "Cendres qui tombent", "en": "Falling ash", "mount": "sol", "vol": "plafond", "zone": {"l": [3.0, 1.0, 30.0], "p": [3.0, 1.0, 30.0]},
		"cap": 1200, "color": Color(0.55, 0.53, 0.5),
		"hint_fr": "Flocons de cendre qui tombent du plafond", "hint_en": "Ash flakes falling from the ceiling"},
	"feux_follets": {"sub": "ambiance", "fr": "Feux follets (115)", "en": "Will-o'-wisps (115)", "mount": "sol",
		"zone": {"l": [1.5, 0.5, 10.0], "p": [1.5, 0.5, 10.0], "h": [1.2, 0.5, 4.0]}, "cap": 400, "couleur": "#3dff6a",
		"color": Color(0.25, 1.0, 0.45), "hint_fr": "Lueurs vertes de l'élément 115 qui dérivent", "hint_en": "Drifting green glows of element 115"},
}

## Variantes d'aspect d'un type d'élément (format 5, clé « variante » de
## ouvertures.json / objets.json) : [identifiant, nom FR, nom EN] ; la
## PREMIÈRE est l'aspect par défaut (celui d'avant les variantes). Une
## variante par défaut n'est jamais écrite dans le fichier (une carte sans la
## clé garde exactement son aspect et ses octets). Construites par le jeu :
## Door (portes, débris), WallBuy (armes murales). docs/MAP_OBJECTS.md.
const VARIANTS := {
	"porte": [
		["blindee", "Porte blindée", "Armoured door"],
		["bois", "Porte en bois", "Wooden door"],
		["grille", "Grille en fer", "Iron gate"],
	],
	"debris": [
		["planches", "Planches et gravats", "Planks and rubble"],
		["gravats", "Éboulement de béton", "Concrete cave-in"],
	],
	"arme": [
		["craie", "Craie sur le mur", "Chalk on the wall"],
		["planche", "Craie sur une planche", "Chalk on a board"],
	],
	# Format 6 : types d'escaliers (StairGen.KINDS ; docs/MAP_OBJECTS.md §
	# Escaliers). Contrairement aux autres variantes, le type change la forme
	# des marches, leur collision et le trajet des zombies.
	"escalier": [
		["droit", "Escalier droit", "Straight stairs"],
		["palier", "Droit avec palier", "Straight with landing"],
		["quart", "En L (quart tournant)", "L-shaped (quarter turn)"],
		["demi_tour", "En U (demi-tour)", "U-shaped (switchback)"],
		["large", "Escalier d'honneur (large)", "Grand stairs (wide)"],
		["service", "Escalier de service (étroit)", "Service stairs (narrow)"],
		["colimacon", "En colimaçon", "Spiral stairs"],
		["rampe", "Rampe (sans marches)", "Ramp (no steps)"],
	],
	# Format 8 : entrées des zombies (barricades) : fenêtre (l'aspect d'avant),
	# porte simple ou double à moitié défoncée (docs/MAP_OBJECTS.md § 9).
	# Comme pour les escaliers, le type change plus que l'aspect : largeur,
	# découpe du mur (sans allège), planches et zombies qui arrachent à la fois.
	"fenetre": [
		["fenetre", "Fenêtre", "Window"],
		["porte", "Porte à zombies (simple)", "Zombie door (single)"],
		["porte_double", "Porte à zombies double", "Zombie double door"],
	],
}

## Largeur (m) le long du mur d'une entrée des zombies de type `kind`
## (variante du type « fenetre », format 8) : fenêtre et porte simple 1 m,
## porte double 2 m (deux battants de 1 m).
const BARRICADE_WIDTHS := {"fenetre": 1.0, "porte": 1.0, "porte_double": 2.0}


static func barricade_width(kind: String) -> float:
	return float(BARRICADE_WIDTHS.get(kind, 1.0))


## Type d'entrée des zombies d'une fenêtre posée (« fenetre », « porte »,
## « porte_double ») ; "" pour un autre élément.
static func barricade_kind(o: Dictionary) -> String:
	return variant_of(o) if String(o.get("type", "")) == "fenetre" else ""

## Réglages d'un escalier (format 6, objets.json) ; absents : valeur par
## défaut, jamais écrite (une carte d'avant garde ses octets).
##   sens         « droite » (défaut) ou « gauche » : côté du virage (L, U) ou
##                sens du colimaçon, vu en montant
##   marches      nombre de marches visibles (absent : ≈ 18 cm chacune)
##   garde_corps  garde-corps sur les côtés (absent : oui pour l'escalier
##                d'honneur, non pour les autres)
##   cotes        « ouverts » (défaut) ou « fermes » : limons pleins
const STAIR_STEPS := [3, 60]
const STAIR_TURNS := ["droite", "gauche"]
const STAIR_SIDES := ["ouverts", "fermes"]


## Type d'un escalier posé (variante, StairGen.KINDS).
static func stair_kind(o: Dictionary) -> String:
	return variant_of(o) if String(o.get("type", "")) == "escalier" else ""


## Largeur minimale (m, petit côté du rectangle TRACÉ) d'un escalier de ce
## type : sa largeur de marche (StairGen.MIN_WIDTH) plus le trait (0,25 m de
## chaque côté) ; l'escalier droit garde sa règle d'avant (1,5 m tracé).
static func stair_min_width(kind: String) -> float:
	if kind == StairGen.DEFAULT_KIND or kind == "":
		return 1.5
	return float(StairGen.MIN_WIDTH.get(kind, 1.5)) + MapGeom.WALL_HALF * 2.0


## Garde-corps par défaut d'un type d'escalier.
static func stair_rail_default(kind: String) -> bool:
	return kind == "large"


## Options de la description en maillage (StairGen) d'un escalier posé :
## kind, turn, steps, rail, closed, seulement si elles ne sont pas par défaut.
static func stair_layout_opts(o: Dictionary) -> Dictionary:
	var out := {}
	var kind := stair_kind(o)
	if kind != "" and kind != StairGen.DEFAULT_KIND:
		out["kind"] = kind
	if String(o.get("sens", "droite")) == "gauche":
		out["turn"] = -1
	var n: Variant = o.get("marches")
	if (n is int or n is float) and int(n) >= STAIR_STEPS[0]:
		out["steps"] = clampi(int(n), STAIR_STEPS[0], STAIR_STEPS[1])
	if o.has("garde_corps") and bool(o.garde_corps) != stair_rail_default(kind):
		out["rail"] = bool(o.garde_corps)
	if String(o.get("cotes", "ouverts")) == "fermes":
		out["closed"] = true
	return out


## Réglages par défaut retirés d'un escalier (fichier écrit à la main ou
## réglage remis à sa valeur par défaut) ; valeurs illisibles retirées.
static func tidy_stair(o: Dictionary) -> void:
	if String(o.get("type", "")) != "escalier":
		return
	if not STAIR_TURNS.has(o.get("sens", "droite")) or o.get("sens") == "droite":
		o.erase("sens")
	if not STAIR_SIDES.has(o.get("cotes", "ouverts")) or o.get("cotes") == "ouverts":
		o.erase("cotes")
	if o.has("marches"):
		var n: Variant = o.marches
		if (n is int or n is float) and is_finite(float(n)) and int(n) >= STAIR_STEPS[0]:
			o["marches"] = clampi(int(n), STAIR_STEPS[0], STAIR_STEPS[1])
		else:
			o.erase("marches")
	if o.has("garde_corps") and (not o.garde_corps is bool or o.garde_corps == stair_rail_default(stair_kind(o))):
		o.erase("garde_corps")

## Barrière invisible (type « bloc_invisible ») : hauteur (m) réglable ;
## absente, du sol au plafond de l'étage.
const CLIP_HEIGHT := [0.5, 30.0]
## Pas du champ Hauteur d'une barrière (m).
const CLIP_HEIGHT_STEP := 0.1
## Format 9 : barrière tracée en polygone (clé « sommets », 3 à 64 points) ;
## surface minimale (m²) et côté minimal (m) de son contour.
const CLIP_POINTS := [3, 64]
const CLIP_MIN_AREA := 0.04
const CLIP_MIN_SIDE := 0.05

static var _items: Array = []
static var _by_id: Dictionary = {}


## Construit une fois, sur le fil principal, puis FIGÉ (lecture seule, en
## profondeur) : les fils de travail (aperçu 3D) le lisent sans risque, rien
## ne peut plus le modifier.
static func items() -> Array:
	if _items.is_empty():
		if not ThreadGuard.main_only("MapCatalog._build"):
			return []
		_build()
		_freeze(_items)
		_by_id.make_read_only()
	return _items


static func _freeze(v: Variant) -> void:
	if v is Dictionary:
		for k in v:
			_freeze(v[k])
		(v as Dictionary).make_read_only()
	elif v is Array:
		for x in v:
			_freeze(x)
		(v as Array).make_read_only()


static func item(id: String) -> Dictionary:
	items()
	var it: Dictionary = _by_id.get(id, {})
	return it if not it.is_empty() else _map_items.get(id, {})


## Objets d'une catégorie ; `sub` : seulement ceux de ce sous-onglet.
static func in_category(cat: String, sub := "") -> Array:
	if cat == MAP_CAT:
		return map_items()
	# « hidden » : la souris, case fixe de la barre rapide, hors inventaire.
	return items().filter(func(it): return (it.cat == cat and not it.get("hidden", false)
			and (sub == "" or String(it.get("sub", "")) == sub)))


# ------------------------------------------------------------------ prefabs de la carte (format 10)

## Catégorie de l'inventaire des prefabs de la carte ouverte.
const MAP_CAT := "prefabs_carte"
## Prefabs de la carte ouverte (MapPrefabLib) : pid -> définition au format
## de PREFABS (fr, en, fp, h, bloque, boxes, surface, color, plus « map »,
## « parties » ou « modele »), et leurs objets d'inventaire
## (« prefab:map:<pid> »). Remplacés d'un bloc (jamais modifiés en place) par
## le fil principal, figés en lecture seule : l'aperçu 3D les lit sans risque
## depuis son fil (comme le reste du catalogue).
static var _map_defs: Dictionary = {}
static var _map_items: Dictionary = {}
static var _map_sig := 0


## Prefabs de la carte ouverte (EditorMap.prefabs : pid -> prefab.json lu).
## Appelé par la carte (chargement, modification de sa bibliothèque) ; sans
## effet hors du fil principal ou si rien n'a changé.
static func set_map_prefabs(defs: Dictionary) -> void:
	if ThreadGuard.worker():
		return
	var sig := hash(defs)
	if sig == _map_sig and _map_defs.size() == defs.size():
		return
	_map_sig = sig
	var nd := {}
	var ni := {}
	var block_fr := {"solide": "Bloque joueurs, zombies et balles", "barriere": "Bloque joueurs et zombies (les balles passent)", "non": "Décor : on marche dessus"}
	var block_en := {"solide": "Blocks players, zombies and bullets", "barriere": "Blocks players and zombies (bullets go through)", "non": "Decoration: can be walked over"}
	for pid in defs:
		var d: Dictionary = (defs[pid] as Dictionary).duplicate(true)
		var nom: Dictionary = d.get("nom", {})
		var fr := String(nom.get("fr", nom.get("en", pid)))
		var en := String(nom.get("en", fr))
		var cd := {"fr": fr, "en": en, "fp": d.fp, "h": float(d.h), "bloque": String(d.bloque), "surface": String(d.get("surface", "concrete")),
			"boxes": d.get("boxes", []), "color": MapPrefabLib.color_of(d), "map": String(pid)}
		for k in ["parties", "modele"]:
			if d.has(k):
				cd[k] = d[k]
		_freeze(cd)
		nd[pid] = cd
		var kind_fr := "Modèle importé" if d.has("modele") else "Groupe de %d décors" % (d.get("parties", []) as Array).size()
		var kind_en := "Imported model" if d.has("modele") else "Group of %d props" % (d.get("parties", []) as Array).size()
		var iid := "prefab:" + MapPrefabLib.ref(pid)
		var it := {"id": iid, "cat": MAP_CAT, "fr": fr, "en": en, "tool": "floor_item", "color": cd.color,
			"make": {"type": "prefab", "prefab": MapPrefabLib.ref(pid), "rot": 0}, "fp": d.fp, "rotates": true, "price": 0,
			"hint_fr": "%s · %s · R : pivoter" % [kind_fr, block_fr.get(String(d.bloque), "")],
			"hint_en": "%s · %s · R: rotate" % [kind_en, block_en.get(String(d.bloque), "")], "map": String(pid)}
		_freeze(it)
		ni[iid] = it
	nd.make_read_only()
	ni.make_read_only()
	_map_defs = nd
	_map_items = ni


## Objets d'inventaire des prefabs de la carte, triés par nom.
static func map_items() -> Array:
	var out: Array = _map_items.values()
	out.sort_custom(func(a, b): return name_of(a).naturalnocasecmp_to(name_of(b)) < 0)
	return out


## Définition d'un décor posé (clé « prefab ») : du catalogue, ou un prefab de
## la carte (« map:<pid> ») ; {} s'il est inconnu.
static func prefab_def(id: String) -> Dictionary:
	if id.begins_with(MapPrefabLib.REF):
		return _map_defs.get(id.substr(MapPrefabLib.REF.length()), {})
	return PREFABS.get(id, {})


## Décors qu'un objet posé peut devenir (panneau des propriétés) : ceux du
## catalogue puis les prefabs de la carte.
static func prefab_ids() -> Array:
	var out: Array = PREFABS.keys()
	for it in map_items():
		out.append(String(it.make.prefab))
	return out


static func prefab_name(id: String) -> String:
	var d := prefab_def(id)
	return Lang.t(String(d.get("fr", id)), String(d.get("en", d.get("fr", id))))


## Sous-onglets d'une catégorie ([[identifiant, FR, EN], ...] ; [] : aucun).
static func subs_of(cat: String) -> Array:
	for c in CATEGORIES:
		if String(c[0]) == cat:
			return c[3] if c.size() > 3 else []
	return []


static func name_of(it: Dictionary) -> String:
	return Lang.t(String(it.get("fr", "")), String(it.get("en", "")))


static func _add(d: Dictionary) -> void:
	d.merge({"fp": [1, 1], "color": Color(0.7, 0.7, 0.7), "price": 0, "make": {}, "hint_fr": "", "hint_en": ""})
	_items.append(d)
	_by_id[d.id] = d


static func _build() -> void:
	# Construction.
	_add({"id": "select", "cat": "construction", "fr": "Souris", "en": "Mouse", "tool": "select", "hidden": true, "color": Color(0.9, 0.9, 0.9),
		"hint_fr": "Clic : choisir un élément ; glisser : déplacer ; poignées : redimensionner", "hint_en": "Click: pick an element; drag: move; handles: resize"})
	_add({"id": "gomme", "cat": "construction", "fr": "Gomme", "en": "Eraser", "tool": "erase", "color": Color(0.95, 0.55, 0.6),
		"hint_fr": "Clic : supprimer l'élément sous le curseur", "hint_en": "Click: delete the element under the cursor"})
	_add({"id": "piece_rect", "cat": "construction", "fr": "Pièce rectangle", "en": "Rectangle room", "tool": "room_rect",
		"color": Color(0.55, 0.75, 0.95), "make": {"forme": "rect"},
		"hint_fr": "Glisser d'un coin à l'autre ; les murs suivent le contour ; R : rectangle tourné de 45°",
		"hint_en": "Drag from corner to corner; walls follow the outline; R: rectangle turned 45°"})
	_add({"id": "piece_poly", "cat": "construction", "fr": "Pièce polygone", "en": "Polygon room", "tool": "room_poly",
		"color": Color(0.55, 0.9, 0.8), "make": {"forme": "poly"},
		"hint_fr": "Clics successifs (côtés à 0, 45 ou 90° ; Alt : angle libre), double-clic (ou clic sur le premier point) pour fermer",
		"hint_en": "Click each corner (sides at 0, 45 or 90°; Alt: free angle), double-click (or click the first point) to close"})
	_add({"id": "mur", "cat": "construction", "fr": "Mur", "en": "Wall", "tool": "wall", "color": Color(0.35, 0.35, 0.38),
		"make": {"type": "mur", "epaisseur": 0.5}, "hint_fr": "Glisser d'un bout à l'autre (0, 45 ou 90° ; Alt : angle libre)",
		"hint_en": "Drag from one end to the other (0, 45 or 90°; Alt: free angle)"})
	# Formes de base (MapShapes) : la pièce posée reste un polygone éditable.
	_add({"id": "piece_cercle", "cat": "construction", "fr": "Cercle / polygone régulier", "en": "Circle / regular polygon", "tool": "room_shape",
		"color": Color(0.6, 0.8, 0.95), "make": {"forme": "cercle"},
		"hint_fr": "Glisser du centre vers le bord ; molette ou + / - : nombre de points (3 à 64) ; clavier : rayon, Tab, points, Entrée",
		"hint_en": "Drag from the centre to the edge; wheel or + / -: number of points (3 to 64); keyboard: radius, Tab, points, Enter"})
	_add({"id": "piece_ellipse", "cat": "construction", "fr": "Ellipse", "en": "Ellipse", "tool": "room_shape",
		"color": Color(0.55, 0.85, 0.95), "make": {"forme": "ellipse"},
		"hint_fr": "Glisser d'un coin à l'autre ; molette ou + / - : nombre de points", "hint_en": "Drag from corner to corner; wheel or + / -: number of points"})
	_add({"id": "piece_triangle", "cat": "construction", "fr": "Pièce triangle", "en": "Triangle room", "tool": "room_shape",
		"color": Color(0.6, 0.9, 0.7), "make": {"forme": "triangle"},
		"hint_fr": "Glisser d'un coin à l'autre (pointe en haut ; glissé vers le haut : pointe en bas)",
		"hint_en": "Drag from corner to corner (tip at the top; dragged upwards: tip at the bottom)"})
	_add({"id": "piece_l", "cat": "construction", "fr": "Pièce en L", "en": "L-shaped room", "tool": "room_shape",
		"color": Color(0.7, 0.8, 0.95), "make": {"forme": "l"},
		"hint_fr": "Glisser d'un coin à l'autre ; épaisseur des branches dans les propriétés",
		"hint_en": "Drag from corner to corner; arm thickness in the properties"})
	_add({"id": "mur_courbe", "cat": "construction", "fr": "Mur courbe", "en": "Curved wall", "tool": "arc", "color": Color(0.42, 0.42, 0.46),
		"make": {"type": "mur_courbe", "epaisseur": 0.5},
		"hint_fr": "Glisser du centre vers le premier bout (arc de 90° dans le sens horaire) ; molette ou + / - : segments ; clavier : rayon, Tab, ouverture",
		"hint_en": "Drag from the centre to the first end (90° clockwise arc); wheel or + / -: segments; keyboard: radius, Tab, opening"})
	_add({"id": "pilier", "cat": "construction", "fr": "Pilier / obstacle", "en": "Pillar / obstacle", "tool": "rect",
		"color": Color(0.45, 0.42, 0.4), "make": {"type": "pilier"}, "hint_fr": "Glisser un rectangle dans une pièce", "hint_en": "Drag a rectangle inside a room"})
	# Deux escaliers dans l'inventaire (flèche ↑ / ↓) : celui qui monte de
	# l'étage courant, celui qui y descend de l'étage du dessous. Un seul objet
	# « escalier » dans la carte : celui qui descend est enregistré comme un
	# escalier de l'étage du dessous qui monte jusqu'ici (« descend » : outil
	# seulement, MapCanvas._creation, MapRules.stair_dir).
	_add({"id": "escalier", "cat": "construction", "fr": "Escalier qui monte", "en": "Stairs going up", "tool": "rect",
		"color": Color(0.8, 0.55, 0.9), "make": {"type": "escalier", "monte": "n"},
		"hint_fr": "Glisser du bas (ici) vers le haut de l'escalier : il monte à l'étage du dessus, son arrivée sur le plancher d'une pièce de cet étage ; V : type (droit, palier, en L, en U, large, service, colimaçon, rampe)",
		"hint_en": "Drag from the bottom (here) to the top of the stairs: they go up to the floor above, arriving on a room floor there; V: type (straight, landing, L, U, wide, service, spiral, ramp)"})
	_add({"id": "escalier_bas", "cat": "construction", "fr": "Escalier qui descend", "en": "Stairs going down", "tool": "rect",
		"color": Color(0.55, 0.7, 0.98), "make": {"type": "escalier", "monte": "n"}, "descend": true,
		"hint_fr": "Glisser du haut (ici) vers le bas de l'escalier : il descend à l'étage du dessous, dans une pièce de cet étage ; V : type",
		"hint_en": "Drag from the top (here) to the bottom of the stairs: they go down to the floor below, into a room there; V: type"})
	# Barrière invisible (« clip » de BO1) : bloque joueurs et zombies, les
	# balles et les grenades passent ; invisible en jeu (CollisionBox).
	# Format 9 : tracée en polygone, posée n'importe où (à cheval sur un mur,
	# dehors, par-dessus un objet).
	_add({"id": "bloc_invisible", "cat": "construction", "fr": "Barrière invisible", "en": "Invisible barrier", "tool": "poly",
		"color": Color(0.35, 0.85, 1.0), "make": {"type": "bloc_invisible"},
		"hint_fr": "Clics successifs (Alt : angle libre), double-clic, clic sur le premier point ou Entrée pour fermer ; n'importe où, même sur un mur ou un objet ; invisible en jeu, bloque joueurs et zombies, les balles passent",
		"hint_en": "Click each corner (Alt: free angle), double-click, click the first point or Enter to close; anywhere, even over a wall or an object; invisible in game, blocks players and zombies, bullets go through"})
	# Ouvertures (sur un mur de pièce).
	_add({"id": "porte", "cat": "ouvertures", "fr": "Porte payante", "en": "Buyable door", "tool": "opening", "color": Color(1.0, 0.67, 0.0),
		"make": {"type": "porte", "largeur": 2.0}, "price": DOOR_PRICES[0],
		"hint_fr": "Sur le mur commun de deux pièces collées", "hint_en": "On the shared wall of two touching rooms"})
	_add({"id": "debris", "cat": "ouvertures", "fr": "Débris à dégager", "en": "Debris", "tool": "opening", "color": Color(0.67, 0.4, 0.15),
		"make": {"type": "debris", "largeur": 2.0}, "price": DOOR_PRICES[0],
		"hint_fr": "Comme une porte : sur le mur commun de deux pièces", "hint_en": "Like a door: on the shared wall of two rooms"})
	_add({"id": "porte_courant", "cat": "ouvertures", "fr": "Porte ouverte par le courant", "en": "Power door", "tool": "opening",
		"color": Color(0.95, 0.9, 0.3), "make": {"type": "porte_courant", "largeur": 2.0},
		"hint_fr": "S'ouvre quand le courant est rétabli", "hint_en": "Opens when the power is turned on"})
	_add({"id": "passage", "cat": "ouvertures", "fr": "Passage libre", "en": "Open passage", "tool": "opening", "color": Color(0.75, 0.85, 0.7),
		"make": {"type": "passage", "largeur": 2.0}, "hint_fr": "Ouverture sans porte entre deux pièces", "hint_en": "Doorless opening between two rooms"})
	_add({"id": "fenetre", "cat": "ouvertures", "fr": "Fenêtre à zombies", "en": "Zombie window", "tool": "opening", "color": Color(0.0, 0.4, 1.0),
		"make": {"type": "fenetre", "largeur": 1.0},
		"hint_fr": "Sur un mur extérieur ; les zombies arrivent de dehors. V : fenêtre, porte simple ou double",
		"hint_en": "On an outer wall; zombies come from outside. V: window, single or double door"})
	# Atouts (PerkDB).
	for id in PerkDB.PERKS:
		_add({"id": "atout:" + id, "cat": "atouts", "fr": PerkDB.display_name(id), "en": PerkDB.display_name(id), "tool": "wall_item",
			"color": PerkDB.color(id), "make": {"type": "atout", "atout": id}, "fp": [3, 2], "price": PerkDB.cost(id, false),
			"hint_fr": String(PerkDB.PERKS[id].desc.fr), "hint_en": String(PerkDB.PERKS[id].desc.en)})
	# Armes murales (WeaponDB, KnifeDB) et grenades.
	for id in WeaponDB.WEAPONS:
		if WeaponDB.wall_cost(id) > 0:
			_add({"id": "arme:" + id, "cat": "armes", "fr": WeaponDB.display_name(id), "en": WeaponDB.display_name(id), "tool": "wall_item",
				"color": Color(0.85, 0.84, 0.78), "make": {"type": "arme", "arme": id}, "fp": [2, 1], "price": WeaponDB.wall_cost(id),
				"hint_fr": "Dessin à la craie au mur", "hint_en": "Chalk outline on the wall"})
	for id in KnifeDB.KNIVES:
		if KnifeDB.wall_cost(id) > 0:
			_add({"id": "arme:" + id, "cat": "armes", "fr": KnifeDB.display_name(id), "en": "BOWIE KNIFE" if id == "bowie" else KnifeDB.display_name(id),
				"tool": "wall_item", "color": Color(0.8, 0.8, 0.85), "make": {"type": "arme", "arme": id}, "fp": [2, 1], "price": KnifeDB.wall_cost(id),
				"hint_fr": "Couteau au mur", "hint_en": "Knife on the wall"})
	_add({"id": "grenades", "cat": "armes", "fr": "Grenades", "en": "Grenades", "tool": "wall_item", "color": Color(0.45, 0.5, 0.3),
		"make": {"type": "grenades"}, "fp": [1, 1], "price": ThrowableRules.FRAG_WALL_COST,
		"hint_fr": "Recharge les grenades", "hint_en": "Refills grenades"})
	# Boîte mystère.
	_add({"id": "boite", "cat": "boite", "fr": "Emplacement de boîte", "en": "Box location", "tool": "wall_item", "color": Color(1.0, 0.9, 0.2),
		"make": {"type": "boite", "depart": false}, "fp": [4, 2], "price": MysteryBox.COST,
		"hint_fr": "Contre un mur ; la boîte se déplace entre ses emplacements", "hint_en": "Against a wall; the box moves between its locations"})
	_add({"id": "boite_depart", "cat": "boite", "fr": "Boîte (départ)", "en": "Box (start)", "tool": "wall_item", "color": Color(0.8, 0.7, 0.1),
		"make": {"type": "boite", "depart": true}, "fp": [4, 2], "price": MysteryBox.COST,
		"hint_fr": "L'emplacement où la boîte commence", "hint_en": "Where the box starts"})
	# Machines.
	_add({"id": "pap", "cat": "machines", "fr": "Pack-a-Punch", "en": "Pack-a-Punch", "tool": "wall_item", "color": Color(0.4, 0.1, 1.0),
		"make": {"type": "pap"}, "fp": [3, 2], "price": PackAPunch.COST, "hint_fr": "Marche avec le courant", "hint_en": "Needs the power"})
	_add({"id": "courant", "cat": "machines", "fr": "Interrupteur du courant", "en": "Power switch", "tool": "wall_item", "color": Color(1.0, 0.2, 0.15),
		"make": {"type": "courant"}, "fp": [1, 1], "hint_fr": "Un seul par carte", "hint_en": "One per map"})
	_add({"id": "teleporteur", "cat": "machines", "fr": "Téléporteur", "en": "Teleporter", "tool": "floor_item", "color": Color(0.0, 1.0, 1.0),
		"make": {"type": "teleporteur"}, "fp": [2, 2], "price": Teleporter.COST, "hint_fr": "Plateforme de départ", "hint_en": "Departure pad"})
	_add({"id": "arrivee", "cat": "machines", "fr": "Arrivée du téléporteur", "en": "Teleporter exit", "tool": "floor_item", "color": Color(0.0, 0.67, 0.67),
		"make": {"type": "arrivee"}, "fp": [2, 2], "hint_fr": "Souvent une salle close (Pack-a-Punch)", "hint_en": "Often a closed room (Pack-a-Punch)"})
	_add({"id": "poste_central", "cat": "machines", "fr": "Poste central", "en": "Mainframe", "tool": "wall_item", "color": Color(0.0, 0.4, 0.4),
		"make": {"type": "poste_central"}, "fp": [2, 2], "hint_fr": "À relier avant chaque voyage (facultatif)", "hint_en": "Link it before each trip (optional)"})
	# Pièges.
	_add({"id": "piege", "cat": "pieges", "fr": "Piège électrique", "en": "Electric trap", "tool": "rect", "color": Color(1.0, 0.33, 0.33),
		"make": {"type": "piege"}, "price": ElectricTrap.COST, "hint_fr": "Glisser la zone au sol ; ajoutez un ou deux leviers à moins de 10 m",
		"hint_en": "Drag the floor area; add one or two levers within 10 m"})
	_add({"id": "levier", "cat": "pieges", "fr": "Levier de piège", "en": "Trap lever", "tool": "wall_item", "color": Color(0.67, 0.0, 0.0),
		"make": {"type": "levier"}, "fp": [1, 1], "hint_fr": "Contre un mur, près de son piège", "hint_en": "Against a wall, near its trap"})
	# Joueurs et apparitions.
	_add({"id": "depart", "cat": "joueurs", "fr": "Départ des joueurs", "en": "Player start", "tool": "floor_item", "color": Color(0.1, 1.0, 0.2),
		"make": {"type": "depart"}, "fp": [1, 1], "hint_fr": "Un point : les 4 joueurs autour ; ou 4 points", "hint_en": "One point: 4 players around it; or 4 points"})
	_add({"id": "apparition", "cat": "joueurs", "fr": "Zombie qui sort du sol", "en": "Ground spawn", "tool": "floor_item", "color": Color(0.5, 0.05, 0.05),
		"make": {"type": "apparition"}, "fp": [1, 1], "hint_fr": "En plus des fenêtres (facultatif)", "hint_en": "In addition to windows (optional)"})
	# Décor et obstacles : caisse et baril (types historiques), puis les prefabs.
	_add({"id": "caisse", "cat": "prefabs", "fr": "Caisse", "en": "Crate", "tool": "floor_item", "color": Color(0.55, 0.38, 0.2),
		"make": {"type": "caisse"}, "fp": [2, 2], "hint_fr": "Obstacle de 1 m de haut", "hint_en": "1 m high obstacle"})
	_add({"id": "baril", "cat": "prefabs", "fr": "Baril", "en": "Barrel", "tool": "floor_item", "color": Color(0.5, 0.12, 0.08),
		"make": {"type": "baril"}, "fp": [1, 1], "hint_fr": "Petit obstacle", "hint_en": "Small obstacle"})
	var block_fr := {"solide": "Bloque joueurs, zombies et balles", "barriere": "Bloque joueurs et zombies (les balles passent)", "non": "Décor : on marche dessus"}
	var block_en := {"solide": "Blocks players, zombies and bullets", "barriere": "Blocks players and zombies (bullets go through)", "non": "Decoration: can be walked over"}
	for pid in PREFABS:
		var d: Dictionary = PREFABS[pid]
		# Format 11 : décor mural (comme une applique) ou accroché au plafond.
		var pm := String(d.get("mount", "sol"))
		if pm == "mur":
			_add({"id": "prefab:" + pid, "cat": "prefabs", "fr": d.fr, "en": d.en, "tool": "wall_item", "color": d.color,
				"make": {"type": "prefab", "prefab": pid}, "fp": d.fp,
				"hint_fr": "Contre un mur, partout et à la hauteur voulue (%s m par défaut) · %s" % [short_num(float(d.y)), block_fr[d.bloque]],
				"hint_en": "Against a wall, anywhere and at any height (%s m by default) · %s" % [short_num(float(d.y)).replace(",", "."), block_en[d.bloque]]})
			continue
		_add({"id": "prefab:" + pid, "cat": "prefabs", "fr": d.fr, "en": d.en, "tool": "floor_item", "color": d.color,
			"make": {"type": "prefab", "prefab": pid, "rot": 0}, "fp": d.fp, "rotates": true,
			"hint_fr": ("Sous le plafond d'une pièce · " if pm == "plafond" else "") + String(block_fr[d.bloque]) + " · R : pivoter",
			"hint_en": ("Under a room ceiling · " if pm == "plafond" else "") + String(block_en[d.bloque]) + " · R: rotate"})
	# Luminaires : la lampe historique, puis les luminaires réglables.
	_add({"id": "lampe", "cat": "lumieres", "fr": "Lampe", "en": "Lamp", "tool": "floor_item", "color": Color(1.0, 0.85, 0.5),
		"make": {"type": "lampe"}, "fp": [1, 1], "hint_fr": "Lampe au plafond (en plus des lampes automatiques)", "hint_en": "Ceiling lamp (in addition to automatic lamps)"})
	var mount_fr := {"plafond": "Au plafond d'une pièce", "mur": "Contre un mur, partout et à la hauteur voulue (2 m par défaut)", "sol": "Au sol, ou sur un meuble (bureau, chariot, sacs de sable)"}
	var mount_en := {"plafond": "On a room ceiling", "mur": "Against a wall, anywhere and at any height (2 m by default)", "sol": "On the floor, or on furniture (desk, cart, sandbags)"}
	for lid in LIGHTS:
		var d: Dictionary = LIGHTS[lid]
		var mount := String(d.mount)
		var mk := {"type": "luminaire", "luminaire": lid, "couleur": d.couleur, "intensite": d.intensite, "portee": d.portee,
			"courant": d.courant, "vacille": d.vacille}
		if mount != "mur":
			mk["rot"] = 0
		_add({"id": "luminaire:" + lid, "cat": "lumieres", "fr": d.fr, "en": d.en, "tool": "wall_item" if mount == "mur" else "floor_item",
			"color": d.color, "make": mk, "fp": d.fp, "rotates": mount != "mur",
			"hint_fr": String(mount_fr[mount]) + " ; couleur, intensité, portée, courant et vacillement dans les propriétés",
			"hint_en": String(mount_en[mount]) + "; colour, intensity, range, power and flicker in the properties"})
	# Effets (format 10), rangés par sous-onglet.
	var fx_fr := {"sol": "Au sol, n'importe où (même sur un objet)", "mur": "Contre un mur, à la hauteur voulue", "plafond": "Sous le plafond d'une pièce"}
	var fx_en := {"sol": "On the floor, anywhere (even over an object)", "mur": "Against a wall, at any height", "plafond": "Under a room ceiling"}
	for s in EFFECT_SUBS:
		for fid in EFFECTS:
			var d: Dictionary = EFFECTS[fid]
			if String(d.sub) != String(s[0]):
				continue
			var mount := String(d.mount)
			var mk := {"type": "effet", "effet": fid}
			# Format 11 : les effets au sol et au plafond pivotent (zone tournée).
			if mount != "mur":
				mk["rot"] = 0
			var z := effect_default_zone(fid)
			var zs := ("%s × %s m" % [short_num(z.x), short_num(z.y)]) if mount != "mur" else ("%s m" % short_num(z.x))
			_add({"id": "effet:" + fid, "cat": "effets", "sub": String(d.sub), "fr": d.fr, "en": d.en, "tool": "wall_item" if mount == "mur" else "floor_item",
				"color": d.color, "make": mk, "fp": effect_cells(fid, z), "rotates": mount != "mur",
				"hint_fr": "%s · %s ; zone de %s, poignées pour l'agrandir ; aucune collision · intensité%s dans les propriétés" % [d.hint_fr, fx_fr[mount], zs, ", couleur" if d.has("couleur") else ""],
				"hint_en": "%s · %s; %s zone, drag its handles to resize; no collision · intensity%s in the properties" % [d.hint_en, fx_en[mount], zs.replace(",", "."), ", colour" if d.has("couleur") else ""]})


## Nombre écrit au plus court, à la française (1,5 ; 3).
static func short_num(v: float) -> String:
	var s := str(snappedf(v, 0.01))
	if s.ends_with(".0"):
		s = s.substr(0, s.length() - 2)
	return s.replace(".", ",")


## Objet du catalogue correspondant à un élément de la carte (icône, nom).
static func item_for(o: Dictionary) -> Dictionary:
	var t := String(o.get("type", ""))
	match t:
		"atout":
			return item("atout:" + String(o.get("atout", "")))
		"prefab":
			return item("prefab:" + String(o.get("prefab", "")))
		"luminaire":
			return item("luminaire:" + String(o.get("luminaire", "")))
		"effet":
			return item("effet:" + String(o.get("effet", "")))
		"arme":
			return item("arme:" + String(o.get("arme", "")))
		"boite":
			return item("boite_depart" if o.get("depart", false) else "boite")
		"porte", "debris", "porte_courant", "passage", "fenetre", "mur", "mur_courbe", "pilier", "escalier", "piege", "levier", "grenades", "pap", \
				"courant", "teleporteur", "arrivee", "poste_central", "depart", "apparition", "lampe", "caisse", "baril", "bloc_invisible":
			return item(t)
	return {}


# ------------------------------------------------------------------ variantes (format 5)

## Identifiants des variantes d'un type (la première : aspect par défaut) ;
## [] si le type n'en a pas.
static func variants(type: String) -> Array:
	var out := []
	for v in VARIANTS.get(type, []):
		out.append(String(v[0]))
	return out


static func has_variants(o: Dictionary) -> bool:
	return VARIANTS.has(String(o.get("type", "")))


static func default_variant(type: String) -> String:
	var l: Array = VARIANTS.get(type, [])
	return String(l[0][0]) if not l.is_empty() else ""


## Variante d'un élément posé : sa clé « variante » si elle est admise pour
## son type, sinon l'aspect par défaut ("" : type sans variantes).
static func variant_of(o: Dictionary) -> String:
	var t := String(o.get("type", ""))
	var v: Variant = o.get("variante")
	if v is String and variants(t).has(v):
		return v
	return default_variant(t)


## Change la variante de `o` ; l'aspect par défaut efface la clé (la carte
## reste identique à une carte d'avant les variantes). Rend false si la
## variante n'existe pas pour ce type.
static func set_variant(o: Dictionary, v: String) -> bool:
	var t := String(o.get("type", ""))
	if not variants(t).has(v):
		return false
	if v == default_variant(t):
		o.erase("variante")
	else:
		o["variante"] = v
	return true


## Variante suivante (touche V) dans l'ordre du catalogue.
static func next_variant(type: String, v: String) -> String:
	var l := variants(type)
	if l.is_empty():
		return ""
	return String(l[(maxi(0, l.find(v)) + 1) % l.size()])


## Nom affiché d'une variante (langue de l'éditeur).
static func variant_name(type: String, v: String) -> String:
	for e in VARIANTS.get(type, []):
		if String(e[0]) == v:
			return Lang.t(String(e[1]), String(e[2]))
	return v


## Noms [FR, EN] d'une variante (messages des règles de pose, dans les deux langues).
static func variant_names(type: String, v: String) -> Array:
	for e in VARIANTS.get(type, []):
		if String(e[0]) == v:
			return [String(e[1]), String(e[2])]
	return [v, v]


## Emprise en cases : [le long du mur, profondeur] (objets muraux) ou [côté, côté].
## Effet (format 11) : les cases qui couvrent sa zone.
static func footprint(o: Dictionary) -> Vector2i:
	if String(o.get("type", "")) == "effet":
		var c := effect_cells(String(o.get("effet", "")), effect_zone(o))
		return Vector2i(int(c[0]), int(c[1]))
	var it := item_for(o)
	var fp: Array = it.get("fp", [1, 1])
	return Vector2i(int(fp[0]), int(fp[1]))


## Taille au sol en cases (x, y) d'un objet au sol, rotation comprise
## (prefab 3 × 2 pivoté de 90° : 2 × 3 ; tourné au degré près : le plus proche
## des deux). Objets historiques : carré fp × fp.
static func floor_size(o: Dictionary) -> Vector2i:
	var it := item_for(o)
	var fp: Array = it.get("fp", [1, 1])
	if String(o.get("type", "")) == "effet":
		fp = effect_cells(String(o.get("effet", "")), effect_zone(o))
	if not it.get("rotates", false):
		return Vector2i(int(fp[0]), int(fp[0]))
	var r := posmod(roundi(float(o.get("rot", 0)) / 90.0) * 90, 360)
	return Vector2i(int(fp[1]), int(fp[0])) if r == 90 or r == 270 else Vector2i(int(fp[0]), int(fp[1]))


## L'objet pivote-t-il avec R (prefabs, luminaires au sol ou au plafond) ?
static func rotates(o: Dictionary) -> bool:
	return bool(item_for(o).get("rotates", false))


## Montage d'un décor du catalogue (format 11) : « sol », « mur » ou « plafond ».
static func prefab_mount(id: String) -> String:
	return String(prefab_def(id).get("mount", "sol"))


## Décor du catalogue posé au sol (les seuls qui entrent dans un prefab groupe).
static func floor_prefab(id: String) -> bool:
	return PREFABS.has(id) and String(PREFABS[id].get("mount", "sol")) == "sol"


## Définition d'un prefab ou d'un luminaire posé ({} sinon).
static func def_of(o: Dictionary) -> Dictionary:
	match String(o.get("type", "")):
		"prefab":
			return prefab_def(String(o.get("prefab", "")))
		"luminaire":
			return LIGHTS.get(String(o.get("luminaire", "")), {})
	return {}


## Collision d'un objet posé : « solide », « barriere » ou « non ».
static func blocking(o: Dictionary) -> String:
	match String(o.get("type", "")):
		"caisse", "baril":
			return "solide"
		"prefab":
			return String(def_of(o).get("bloque", "solide"))
		"luminaire":
			return String(def_of(o).get("bloque", "non"))
	return "non"


## Décor (format 7, docs/MAP_OBJECTS.md § 8) : caisses, barils, prefabs,
## lampes et luminaires. Il se pose librement (contre un mur, à moitié
## dedans, au centimètre, tourné, par-dessus un autre décor) ; les objets de
## jeu (portes, fenêtres, armes murales, atouts, boîte, départs...) gardent
## leurs règles de pose.
## Format 10 : les effets se posent comme le décor (et par-dessus tout,
## MapRules.NO_OVERLAP_CHECK).
const DECOR_TYPES := ["caisse", "baril", "prefab", "luminaire", "lampe", "effet"]


static func is_decor(o: Dictionary) -> bool:
	return String(o.get("type", "")) in DECOR_TYPES


# ------------------------------------------------------------------ effets (format 10)

## Définition d'un effet posé (EFFECTS ; {} si ce n'en est pas un).
static func effect_def(o: Dictionary) -> Dictionary:
	if String(o.get("type", "")) != "effet":
		return {}
	return EFFECTS.get(String(o.get("effet", "")), {})


## Montage d'un effet : « sol », « mur », « plafond » ("" : pas un effet).
static func effect_mount(o: Dictionary) -> String:
	return String(effect_def(o).get("mount", ""))


## L'effet se teinte-t-il (clé « couleur ») ?
static func effect_tints(o: Dictionary) -> bool:
	return effect_def(o).has("couleur")


static func effect_color(o: Dictionary) -> Color:
	var c := String(o.get("couleur", effect_def(o).get("couleur", "#ffffff")))
	return Color.html(c) if Color.html_is_valid(c) else Color.WHITE


## Dimensions de la zone d'un effet, dans l'ordre de la clé « zone » :
## effet mural [l, h] ; au sol ou au plafond [l, p], plus « h » pour un volume.
static func effect_dims(fid: String) -> Array:
	var d: Dictionary = EFFECTS.get(fid, {})
	if d.is_empty():
		return []
	var z: Dictionary = d.get("zone", {})
	if String(d.mount) == "mur":
		return ["l", "h"]
	return ["l", "p", "h"] if z.has("h") else ["l", "p"]


## Bornes [min, max] (m) d'une dimension de la zone d'un effet.
static func effect_zone_bounds(fid: String, key: String) -> Array:
	var z: Dictionary = EFFECTS.get(fid, {}).get("zone", {})
	var s: Array = z.get(key, [1.0, ZONE_LIMITS[0], ZONE_LIMITS[1]])
	return [float(s[1]), float(s[2])]


## Zone par défaut d'un effet : Vector3(largeur, profondeur, hauteur) en m.
## Mural : profondeur = sa portée dans la pièce (« reach », fixe). Effet
## sans volume : hauteur 0.
static func effect_default_zone(fid: String) -> Vector3:
	var d: Dictionary = EFFECTS.get(fid, {})
	var z: Dictionary = d.get("zone", {})
	var out := Vector3(float(z.get("l", [1.0])[0]), float(z.get("p", [1.0])[0]), float(z.get("h", [0.0])[0]))
	if String(d.get("mount", "")) == "mur":
		out.y = float(d.get("reach", 0.5))
	return out


## Effet mural porté par un décor mural (« ancre » : la flamme de torche est
## posée tant de m au-dessus de sa torche) ; 0 : aucun.
static func effect_anchor(fid: String) -> float:
	return float(EFFECTS.get(fid, {}).get("ancre", 0.0))


## Hauteur minimale (m) du volume d'un effet.
const EFFECT_MIN_VOL := 0.1


## VOLUME d'un effet (boîte, m) dans son repère : origine au point posé, y
## vers le haut ; effet mural : x le long du mur, +z du mur vers la pièce.
## SEULE source de vérité : le jeu y contient tout ce que l'effet affiche
## (MapEffects : émission, vitesses, gravité, taille des particules, arcs,
## sol de collision, source des lumières) et l'éditeur la dessine (aperçu 3D,
## élévations, clic). `zone` : effect_zone ; `ground` : distance (m) de
## l'origine au sol ; `room_h` : hauteur sous plafond (m) au point posé.
##   sol      la zone au sol (largeur × profondeur), de la hauteur de pose
##            vers le haut, jamais au-dessus du plafond ;
##   plafond  la zone sous le plafond, du point posé vers le bas ;
##   mur      largeur × hauteur de la zone centrées sur la hauteur, portée
##            (« reach ») vers la pièce ; « sol » : jusqu'au sol.
static func effect_volume(fid: String, zone: Vector3, ground: float, room_h: float) -> AABB:
	var d: Dictionary = EFFECTS.get(fid, {})
	var vol: Variant = d.get("vol", 0.0)
	ground = maxf(0.0, ground)
	var up := maxf(EFFECT_MIN_VOL, room_h - ground) if room_h > 0.0 else INF
	match String(d.get("mount", "sol")):
		"mur":
			var top := minf(zone.z * 0.5, up)
			# Jamais sous le sol (effet mural posé bas).
			var bot := -ground if vol is String and vol == "sol" else maxf(-zone.z * 0.5, -ground)
			bot = minf(bot, top - EFFECT_MIN_VOL)
			return AABB(Vector3(-zone.x * 0.5, bot, 0.0), Vector3(zone.x, top - bot, zone.y))
		"plafond":
			var h := ground if vol is String and vol == "sol" else float(vol)
			h = maxf(EFFECT_MIN_VOL, minf(h, ground)) if ground > 0.0 else maxf(EFFECT_MIN_VOL, h)
			return AABB(Vector3(-zone.x * 0.5, -h, -zone.y * 0.5), Vector3(zone.x, h, zone.y))
	var hh := zone.z
	if hh <= 0.0:
		hh = up if vol is String and vol == "plafond" else float(vol)
	hh = clampf(hh, EFFECT_MIN_VOL, maxf(EFFECT_MIN_VOL, up))
	return AABB(Vector3(-zone.x * 0.5, 0.0, -zone.y * 0.5), Vector3(zone.x, hh, zone.y))


## Zone d'un effet posé (format 11, clé « zone ») : Vector3(largeur,
## profondeur, hauteur) en m, chaque dimension bornée à celles de l'effet ;
## absente ou illisible : la zone par défaut.
static func effect_zone(o: Dictionary) -> Vector3:
	var fid := String(o.get("effet", ""))
	var out := effect_default_zone(fid)
	var v: Variant = o.get("zone")
	var dims := effect_dims(fid)
	if not (v is Array and v.size() == dims.size()):
		return out
	for i in dims.size():
		var x: Variant = v[i]
		if not ((x is float or x is int) and is_finite(float(x))):
			return effect_default_zone(fid)
		var b := effect_zone_bounds(fid, dims[i])
		var f := clampf(float(x), b[0], b[1])
		match String(dims[i]):
			"l":
				out.x = f
			"p":
				out.y = f
			"h":
				out.z = f
	return out


## Règle la zone d'un effet (bornée, arrondie à ZONE_STEP) ; la zone par
## défaut efface la clé (jamais écrite à sa valeur par défaut).
static func set_effect_zone(o: Dictionary, z: Vector3) -> void:
	var fid := String(o.get("effet", ""))
	var dims := effect_dims(fid)
	if dims.is_empty():
		o.erase("zone")
		return
	var def := effect_default_zone(fid)
	var arr := []
	var same := true
	for key in dims:
		var b := effect_zone_bounds(fid, key)
		var raw: float = {"l": z.x, "p": z.y, "h": z.z}[key]
		var f := snap_zone(clampf(raw if is_finite(raw) else b[0], b[0], b[1]))
		f = clampf(f, b[0], b[1])
		var dv: float = {"l": def.x, "p": def.y, "h": def.z}[key]
		if absf(f - dv) > 0.001:
			same = false
		arr.append(f)
	if same:
		o.erase("zone")
	else:
		o["zone"] = arr


## Dimension de zone arrondie au pas ZONE_STEP (division exacte : 0,6 et
## pas 0,6000000000000001).
static func snap_zone(v: float) -> float:
	var inv := roundf(1.0 / ZONE_STEP)
	return roundf(v * inv) / inv


## Clé « zone » lisible pour cet effet (contrôle des cartes reçues) : autant
## de nombres que ses dimensions, chacun dans ses bornes (à 1 cm près).
static func effect_zone_ok(fid: String, v: Variant) -> bool:
	var dims := effect_dims(fid)
	if not (v is Array and v.size() == dims.size()):
		return false
	for i in dims.size():
		var x: Variant = v[i]
		if not ((x is float or x is int) and is_finite(float(x))):
			return false
		var b := effect_zone_bounds(fid, dims[i])
		if float(x) < b[0] - 0.01 or float(x) > b[1] + 0.01:
			return false
	return true


## Cases (0,5 m) qui couvrent une zone d'effet : [largeur, profondeur].
static func effect_cells(fid: String, z: Vector3) -> Array:
	if not EFFECTS.has(fid):
		return [1, 1]
	return [maxi(1, ceili(z.x / MapGeom.CELL - 0.001)), maxi(1, ceili(z.y / MapGeom.CELL - 0.001))]


## Réglage numérique d'un effet (intensite, taille), borné ; absent : 1.
static func effect_value(o: Dictionary, key: String) -> float:
	var v: Variant = o.get(key, 1.0)
	if not (v is float or v is int) or not is_finite(float(v)):
		return 1.0
	var lim: Array = EFFECT_LIMITS[key]
	return clampf(float(v), lim[0], lim[1])


## Hauteur d'un effet (m au-dessus du sol : surélévation d'un effet au sol,
## hauteur d'un effet mural) ; absente : `y` de l'effet. 0 au plafond.
static func effect_height(o: Dictionary) -> float:
	var d := effect_def(o)
	if String(d.get("mount", "")) == "plafond":
		return 0.0
	var def := float(d.get("y", 0.0))
	var hv: Variant = o.get("hauteur", def)
	if not (hv is float or hv is int) or not is_finite(float(hv)):
		return def
	return clampf(float(hv), EFFECT_LIMITS.hauteur[0], EFFECT_LIMITS.hauteur[1])


## Réglages d'un effet remis en ordre (fichier écrit à la main, valeur remise
## par défaut) : valeur illisible ou par défaut retirée, sinon bornée ;
## couleur seulement pour les effets qui se teintent, hauteur jamais au plafond.
## Format 11 : « taille » (d'avant) devient la zone (zone par défaut ×
## taille, si l'effet n'a pas déjà une zone) ; zone illisible retirée, sinon
## bornée ; rotation retirée d'un effet mural (il suit son mur).
## Format 13 : zones par défaut d'avant (format 12 et moins) des effets dont
## la zone par défaut a grandi (le volume les contient désormais tout
## entiers), dans l'ordre de leurs dimensions (effect_dims).
const EFFECT_ZONE_12 := {"torche": [0.3, 0.4], "fumee_legere": [1.0, 1.0], "fumee_noire": [1.5, 1.5], "vapeur": [0.3, 0.3],
	"pluie_etincelles": [0.5, 0.5], "soudure": [0.4, 0.4], "court_circuit": [0.4, 0.5], "cable_nu": [0.5, 0.5], "fuite": [0.3, 0.2]}
## Format 13 : décalage (m) de la « hauteur » des effets dont le dessin a
## bougé par rapport à elle (volume posé à sa hauteur) : flamme de torche
## (0,45 m au-dessus de sa torche), arc (au milieu de son volume, 0,3 m),
## boule de la bobine Tesla (0,8 m).
const EFFECT_SHIFT_13 := {"torche": 0.45, "arc": -0.3, "tesla": -0.8}


## Conversion d'un effet d'une carte au format 12 ou moins (EditorMap._migrate) :
## il reste au même endroit et de la même taille. Sans « zone » : la zone par
## défaut d'avant (EFFECT_ZONE_12), aussi pour « taille » (format 10 et
## moins : zone par défaut d'avant × taille) ; « hauteur » écrite : décalée
## de EFFECT_SHIFT_13 (sans elle, la nouvelle hauteur par défaut dessine
## l'effet au même endroit). Une seule fois : la carte est réécrite au format 13.
static func migrate_effect_13(o: Dictionary) -> void:
	if String(o.get("type", "")) != "effet":
		return
	var fid := String(o.get("effet", ""))
	if not EFFECTS.has(fid):
		return
	if EFFECT_ZONE_12.has(fid) and not o.has("zone"):
		var old: Array = EFFECT_ZONE_12[fid]
		var dims := effect_dims(fid)
		var k := 1.0
		if o.has("taille"):
			var tv: Variant = o.taille
			o.erase("taille")
			if (tv is float or tv is int) and is_finite(float(tv)):
				k = clampf(float(tv), EFFECT_LIMITS.taille[0], EFFECT_LIMITS.taille[1])
		var z := effect_default_zone(fid)
		for i in dims.size():
			match String(dims[i]):
				"l":
					z.x = float(old[i]) * k
				"p":
					z.y = float(old[i]) * k
				"h":
					z.z = float(old[i]) * k
		set_effect_zone(o, z)
	if EFFECT_SHIFT_13.has(fid) and o.has("hauteur"):
		var hv: Variant = o.hauteur
		if (hv is float or hv is int) and is_finite(float(hv)):
			o["hauteur"] = snappedf(clampf(float(hv) + float(EFFECT_SHIFT_13[fid]), EFFECT_LIMITS.hauteur[0], EFFECT_LIMITS.hauteur[1]), 0.01)


static func tidy_effect(o: Dictionary) -> void:
	if String(o.get("type", "")) != "effet":
		return
	var d := effect_def(o)
	if o.has("taille"):
		var tv: Variant = o.taille
		o.erase("taille")
		if not d.is_empty() and not o.has("zone") and (tv is float or tv is int) and is_finite(float(tv)):
			set_effect_zone(o, effect_default_zone(String(o.effet)) * clampf(float(tv), EFFECT_LIMITS.taille[0], EFFECT_LIMITS.taille[1]))
	if o.has("zone"):
		if d.is_empty():
			o.erase("zone")
		else:
			var zv: Variant = o.zone
			var ok: bool = zv is Array and (zv as Array).size() == effect_dims(String(o.effet)).size() \
				and (zv as Array).all(func(x): return (x is float or x is int) and is_finite(float(x)))
			if ok:
				set_effect_zone(o, effect_zone(o))
			else:
				o.erase("zone")
	if o.has("intensite"):
		var v: Variant = o.intensite
		if not (v is float or v is int) or not is_finite(float(v)) or absf(float(v) - 1.0) < 0.005:
			o.erase("intensite")
		else:
			o["intensite"] = snappedf(clampf(float(v), EFFECT_LIMITS.intensite[0], EFFECT_LIMITS.intensite[1]), 0.01)
	if o.has("hauteur"):
		var hv: Variant = o.hauteur
		if d.is_empty() or String(d.mount) == "plafond" or not (hv is float or hv is int) or not is_finite(float(hv)) \
				or absf(float(hv) - float(d.get("y", 0.0))) < 0.005:
			o.erase("hauteur")
		else:
			o["hauteur"] = snappedf(clampf(float(hv), EFFECT_LIMITS.hauteur[0], EFFECT_LIMITS.hauteur[1]), 0.01)
	if o.has("couleur"):
		var c: Variant = o.couleur
		if not d.has("couleur") or not (c is String and Color.html_is_valid(c)) or Color.html(c).is_equal_approx(Color.html(String(d.couleur))):
			o.erase("couleur")
	if o.has("rot") and (d.is_empty() or String(d.mount) == "mur"):
		o.erase("rot")


## Format 11 : décors qu'un effet d'une carte plus ancienne construisait avec
## lui (bûches, torche, tuyau, boîtier, électrodes, flaque...), à poser à côté
## de l'effet devenu pur : même étage, même place (même mur, même hauteur) et
## même rotation ; la flaque d'un filet d'eau là où l'eau tombait. Rien si
## l'effet n'en avait pas, ou si un décor identique est déjà là (`objets` :
## les objets de la carte ; rien n'est posé deux fois). `new_id(préfixe)`
## donne les identifiants.
static func split_legacy_effect(o: Dictionary, objets: Array, new_id: Callable) -> Array:
	var d := effect_def(o)
	if d.is_empty() or not o.get("position") is Array or (o.position as Array).size() != 2:
		return []
	var p := MapGeom.v2(o.position)
	var out := []
	for pid in d.get("decor", []):
		var pd: Dictionary = PREFABS.get(String(pid), {})
		if pd.is_empty():
			continue
		var dec := {"type": "prefab", "prefab": String(pid), "etage": int(o.get("etage", 0))}
		var at := p
		var mount := String(pd.get("mount", "sol"))
		if mount == "mur":
			# Même mur, même hauteur que l'effet (la torche porte la flamme).
			at = p
			dec["mur"] = String(o.get("mur", "n"))
			if o.has("angle"):
				dec["angle"] = o.angle
			var hv: Variant = o.get("hauteur")
			if (hv is float or hv is int) and is_finite(float(hv)):
				dec["hauteur"] = float(hv)
		else:
			if String(d.mount) == "mur":
				# Flaque du filet d'eau : là où l'eau touche le sol (chute depuis la
				# hauteur de l'effet, jet de 1 m/s vers la pièce).
				var dv := MapGeom.item_wall_dir(o)
				var fall := sqrt(2.0 * maxf(0.1, effect_height(o)) / 9.8)
				at = p - dv * (MapGeom.WALL_HALF + 0.15 + 1.05 * fall)
			dec["rot"] = posmod(int(o.get("rot", 0)), 360) if (o.get("rot") is int or o.get("rot") is float) else 0
		at = MapGeom.round_mm(at)
		dec["position"] = MapGeom.arr(at)
		var dup := false
		for q in objets:
			if String(q.get("type", "")) == "prefab" and String(q.get("prefab", "")) == String(pid) and int(q.get("etage", 0)) == int(dec.etage) \
					and q.get("position") is Array and MapGeom.v2(q.position).distance_to(at) < 0.05:
				dup = true
				break
		if dup:
			continue
		dec["id"] = String(new_id.call("d"))
		out.append(dec)
	return out


## Nombre d'effets d'une carte (MAX_EFFECTS au plus).
static func effect_count(doc: EditorMap) -> int:
	var n := 0
	for o in doc.objets:
		if String(o.get("type", "")) == "effet":
			n += 1
	return n


## Format 9 : réglage de la carte « chevauchement_decor » (carte.json, vrai /
## faux ; absent : faux, les règles d'avant). Coché, le décor et les obstacles
## (OVERLAP_TYPES : le décor de DECOR_TYPES et les piliers) peuvent se
## chevaucher entre eux. Les objets de jeu (portes, fenêtres, atouts, armes
## murales, boîte, Pack-a-Punch, interrupteur, leviers, pièges, départs,
## apparitions, téléporteurs, escaliers) gardent leurs règles : ils ne
## chevauchent rien et rien ne les chevauche (la carte reste jouable). La
## barrière invisible, elle, se pose toujours n'importe où (MapRules.check_clip).
const OVERLAP_KEY := "chevauchement_decor"
const OVERLAP_TYPES := ["caisse", "baril", "prefab", "luminaire", "lampe", "pilier"]


static func may_overlap(o: Dictionary) -> bool:
	return String(o.get("type", "")) in OVERLAP_TYPES


## Hauteur d'une applique (format 7, clé « hauteur » d'un luminaire mural :
## m au-dessus du sol, au centre de l'applique ; absente : `y` du luminaire,
## 2 m). Bornée sous le plafond à la construction (MapLayoutExport). Format
## 11 : de même pour un décor mural (torche, tuyau, boîtier : `y` du décor).
const WALL_LIGHT_HEIGHT := [0.2, 30.0]


## Hauteur d'une applique posée (m au-dessus du sol), bornée à WALL_LIGHT_HEIGHT.
static func wall_light_height(o: Dictionary) -> float:
	var def := float(def_of(o).get("y", 2.0))
	var hv: Variant = o.get("hauteur", def)
	if not (hv is float or hv is int) or not is_finite(float(hv)):
		return def
	return clampf(float(hv), WALL_LIGHT_HEIGHT[0], WALL_LIGHT_HEIGHT[1])


## Règle la hauteur d'une applique : la valeur par défaut, une valeur
## illisible ou un luminaire qui n'est pas mural effacent la clé (une carte
## d'avant garde ses octets) ; sinon bornée et arrondie au centimètre.
static func set_wall_light_height(o: Dictionary, h: float) -> void:
	var def := float(def_of(o).get("y", 2.0))
	if light_mount(o) != "mur" or not is_finite(h) or absf(h - def) < 0.005:
		o.erase("hauteur")
		return
	o["hauteur"] = snappedf(clampf(h, WALL_LIGHT_HEIGHT[0], WALL_LIGHT_HEIGHT[1]), 0.01)


## Montage d'un luminaire : plafond, mur, sol ("" : pas un luminaire). La
## lampe historique (« lampe ») est au plafond. Format 11 : aussi le montage
## d'un décor mural ou accroché au plafond (« mur », « plafond » ; "" au sol).
static func light_mount(o: Dictionary) -> String:
	if String(o.get("type", "")) == "lampe":
		return "plafond"
	return String(def_of(o).get("mount", ""))


## Couleur d'un luminaire (« #rrggbb » ; celle du luminaire par défaut si illisible).
static func light_color(o: Dictionary) -> Color:
	var c := String(o.get("couleur", def_of(o).get("couleur", "#ffbf80")))
	return Color.html(c) if Color.html_is_valid(c) else Color(1.0, 0.75, 0.5)


## Type d'emplacement d'un élément : wall_item, floor_item, rect, wall, opening.
static func tool_of(o: Dictionary) -> String:
	return String(item_for(o).get("tool", ""))


## Clé du validateur (MapValidator) d'un objet posé.
static func validator_key(o: Dictionary) -> String:
	match String(o.get("type", "")):
		"atout":
			return "atout_" + String(o.atout)
		"arme":
			return "arme_" + String(o.arme)
		"boite":
			return "boite_depart" if o.get("depart", false) else "boite"
	return String(o.get("type", ""))


## Matériaux proposés (clés de WorldLook.SURFACES).
static func materials() -> Array:
	var out := WorldLook.SURFACES.keys()
	out.sort()
	return out


## Musiques d'ambiance proposées (assets/audio/ambience_*).
static func musics() -> Array:
	var out := []
	for f in DirAccess.get_files_at("res://assets/audio"):
		var base := f.get_basename().get_basename()
		if base.begins_with("ambience_") and not out.has(base):
			out.append(base)
	out.sort()
	if out.is_empty():
		out.append("ambience_bunker")
	return out


# ------------------------------------------------------------------ types admis (contrôle des cartes)

## Coordonnée maximale (m) et nombre d'étages maximal d'une carte.
const MAX_COORD := CustomMapGuard.MAX_COORD  # mêmes limites que le contrôle des cartes reçues
const MAX_FLOORS := CustomMapGuard.MAX_FLOORS


## Types d'éléments admis dans ouvertures.json et objets.json, avec leurs clés
## et les valeurs permises. Sert au contrôle des cartes reçues (archive .zip,
## cartes partagées) : tout type ou toute clé absent de cette table est à
## refuser.
##   {type: {"file": "ouvertures.json" | "objets.json", "required": [clés],
##           "keys": {clé: spec}}}
## spec : {"t": "id"} identifiant (lettres, chiffres, _ ; 32 caractères au
##   plus) ; {"t": "int", "min", "max"} ; {"t": "number", "min", "max"} ;
##   {"t": "bool"} ; {"t": "enum", "values": [...]} ; {"t": "point"} [x, y] en
##   mètres (0 à MAX_COORD) ; {"t": "rect"} [x0, y0, x1, y1] ; {"t": "points",
##   "min", "max"} liste de points [x, y] (format 9) ; {"t": "color"}
##   « #rrggbb » ; {"t": "dims", "min", "max", "lo", "hi"} liste de min à max
##   nombres, chacun de lo à hi (format 11 : zone d'un effet). Les clés communes (id, type, etage) sont dans chaque entrée.
static func allowed_kinds() -> Dictionary:
	var dirs := {"t": "enum", "values": ["n", "e", "s", "o"]}
	# Format 3 : objet mural contre un mur en biais (degrés, sens horaire depuis
	# le nord ; nombre fini, 0 à 360).
	var angle := {"t": "number", "min": 0.0, "max": 360.0}
	# Format 4 : rotation au degré près (degrés entiers, sens horaire vu de
	# dessus) du décor, des luminaires, des piliers, escaliers et pièges.
	var rot := {"t": "int", "min": 0, "max": 359}
	var point := {"t": "point"}
	var price := {"t": "int", "min": 0, "max": 100000}
	var width := {"t": "number", "min": 0.5, "max": 20.0}
	var thick := {"t": "enum", "values": [0.5, 1.5, 2.5]}
	var out := {}
	var add := func(file: String, type: String, keys: Dictionary, req: Array) -> void:
		var k := {"id": {"t": "id"}, "type": {"t": "enum", "values": [type]}, "etage": {"t": "int", "min": 0, "max": MAX_FLOORS - 1}}
		k.merge(keys)
		# Format 5 : variante d'aspect, seulement parmi celles du type.
		if VARIANTS.has(type):
			k["variante"] = {"t": "enum", "values": variants(type)}
		out[type] = {"file": file, "required": ["id", "type"] + req, "keys": k}
	for t in ["porte", "debris"]:
		add.call("ouvertures.json", t, {"position": point, "largeur": width, "prix": price}, ["position"])
	for t in ["porte_courant", "passage"]:
		add.call("ouvertures.json", t, {"position": point, "largeur": width}, ["position"])
	add.call("ouvertures.json", "fenetre", {"position": point, "largeur": {"t": "number", "min": 1.0, "max": 1.0}}, ["position"])
	for t in ["pilier", "piege"]:
		add.call("objets.json", t, {"rect": {"t": "rect"}, "rot": rot}, ["rect"])
	# Format 6 : type (variante), sens du virage, marches, garde-corps, côtés.
	add.call("objets.json", "escalier", {"rect": {"t": "rect"}, "monte": dirs, "rot": rot,
		"sens": {"t": "enum", "values": STAIR_TURNS}, "marches": {"t": "int", "min": STAIR_STEPS[0], "max": STAIR_STEPS[1]},
		"garde_corps": {"t": "bool"}, "cotes": {"t": "enum", "values": STAIR_SIDES}}, ["rect"])
	# Format 5 : barrière invisible (rectangle, rotation, hauteur facultative) ;
	# format 9 : polygone « sommets » (3 à 64 points). L'un des deux est
	# obligatoire (CustomMapGuard._check_object) ; l'éditeur lit un rectangle
	# d'avant comme un polygone de 4 sommets (EditorMap._normalize).
	add.call("objets.json", "bloc_invisible", {"sommets": {"t": "points", "min": CLIP_POINTS[0], "max": CLIP_POINTS[1]},
		"rect": {"t": "rect"}, "rot": rot, "hauteur": {"t": "number", "min": CLIP_HEIGHT[0], "max": CLIP_HEIGHT[1]}}, [])
	add.call("objets.json", "mur", {"a": point, "b": point, "epaisseur": thick}, ["a", "b"])
	# Format 4 : mur courbe (arc de cercle en segments, MapShapes).
	add.call("objets.json", "mur_courbe", {"centre": point, "rayon": {"t": "number", "min": 1.0, "max": MapShapes.MAX_RADIUS},
		"debut": angle, "ouverture": {"t": "number", "min": 5.0, "max": 360.0},
		"segments": {"t": "int", "min": MapShapes.MIN_SEGMENTS, "max": MapShapes.MAX_SEGMENTS}, "epaisseur": thick},
		["centre", "rayon", "ouverture", "segments"])
	add.call("objets.json", "atout", {"atout": {"t": "enum", "values": PerkDB.PERKS.keys()}, "position": point, "mur": dirs, "angle": angle}, ["atout", "position"])
	var arms := []
	for it in in_category("armes"):
		if String(it.id).begins_with("arme:"):
			arms.append(String(it.id).substr(5))
	add.call("objets.json", "arme", {"arme": {"t": "enum", "values": arms}, "position": point, "mur": dirs, "angle": angle}, ["arme", "position"])
	add.call("objets.json", "boite", {"position": point, "mur": dirs, "angle": angle, "depart": {"t": "bool"}}, ["position"])
	for t in ["grenades", "pap", "courant", "poste_central", "levier"]:
		add.call("objets.json", t, {"position": point, "mur": dirs, "angle": angle}, ["position"])
	for t in ["depart", "apparition", "teleporteur", "arrivee", "lampe", "caisse", "baril"]:
		add.call("objets.json", t, {"position": point}, ["position"])
	# Format 10 : « prefab » : un décor du catalogue ou un prefab de la carte
	# (« map:<pid> », qui doit exister dans son dossier prefabs/ :
	# CustomMapGuard.check_texts).
	# Format 11 : décor mural (« mur », « angle », « hauteur » comme une applique).
	# Format 12 : « z » (décor posé au sol, sur un autre), « descente » (décor
	# accroché au plafond).
	var descente := {"t": "number", "min": MapVertical.DESCENTE[0], "max": MapVertical.DESCENTE[1]}
	add.call("objets.json", "prefab", {"prefab": {"t": "prefab", "values": PREFABS.keys()}, "position": point, "rot": rot, "mur": dirs, "angle": angle,
		"hauteur": {"t": "number", "min": WALL_LIGHT_HEIGHT[0], "max": WALL_LIGHT_HEIGHT[1]},
		"z": {"t": "number", "min": MapVertical.DECOR_Z[0], "max": MapVertical.DECOR_Z[1]}, "descente": descente}, ["prefab", "position"])
	add.call("objets.json", "luminaire", {"luminaire": {"t": "enum", "values": LIGHTS.keys()}, "position": point, "rot": rot, "mur": dirs, "angle": angle,
		"couleur": {"t": "color"}, "intensite": {"t": "number", "min": LIGHT_LIMITS.intensite[0], "max": LIGHT_LIMITS.intensite[1]},
		"portee": {"t": "number", "min": LIGHT_LIMITS.portee[0], "max": LIGHT_LIMITS.portee[1]},
		"courant": {"t": "bool"}, "vacille": {"t": "bool"},
		# Format 7 : hauteur d'une applique (m au-dessus du sol) ; format 12 :
		# aussi d'un luminaire au sol (0 : par terre), « descente » au plafond.
		"hauteur": {"t": "number", "min": 0.0, "max": WALL_LIGHT_HEIGHT[1]}, "descente": descente}, ["luminaire", "position"])
	# Format 10 : effets (flammes, fumées...), réglages facultatifs bornés ;
	# format 11 : « zone » (2 ou 3 dimensions en m ; bornes propres à chaque
	# effet : CustomMapGuard._check_object) ; « taille » d'avant encore lue.
	add.call("objets.json", "effet", {"effet": {"t": "enum", "values": EFFECTS.keys()}, "position": point, "rot": rot, "mur": dirs, "angle": angle,
		"couleur": {"t": "color"}, "intensite": {"t": "number", "min": EFFECT_LIMITS.intensite[0], "max": EFFECT_LIMITS.intensite[1]},
		"zone": {"t": "dims", "min": 2, "max": 3, "lo": ZONE_LIMITS[0], "hi": ZONE_LIMITS[1]},
		"taille": {"t": "number", "min": EFFECT_LIMITS.taille[0], "max": EFFECT_LIMITS.taille[1]},
		"hauteur": {"t": "number", "min": EFFECT_LIMITS.hauteur[0], "max": EFFECT_LIMITS.hauteur[1]}, "descente": descente}, ["effet", "position"])
	return out


## Surfaces (textures) admises pour les sols, murs et plafonds des pièces et
## des zones : clés de WorldLook.SURFACES, triées.
static func allowed_surfaces() -> Array:
	return materials()


## Clés admises d'une pièce (pieces.json), même format que allowed_kinds() ;
## en plus : {"t": "text", "max"} texte libre, {"t": "polygon", "min", "max"}
## liste de points, {"t": "shape"} forme de base (MapShapes).
static func room_keys() -> Dictionary:
	var surf := {"t": "enum", "values": allowed_surfaces()}
	# Format 4 : « forme » = forme de base d'origine (MapShapes) : {"t": "shape"}
	# (type parmi MapShapes.TYPES, centre, rayons, points 3 à 64, angle, bras).
	return {"id": {"t": "id"}, "nom": {"t": "text", "max": 64}, "etage": {"t": "int", "min": 0, "max": MAX_FLOORS - 1},
		"zone": {"t": "id"}, "contour": {"t": "polygon", "min": 3, "max": CustomMapGuard.MAX_VERTICES},
		# Plafond : mêmes bornes que le panneau et le validateur (MapVertical.ROOM_CEILING).
		"plafond": {"t": "number", "min": MapVertical.ROOM_CEILING[0], "max": MapVertical.ROOM_CEILING[1]},
		"double_hauteur": {"t": "bool"}, "surface_sol": surf, "surface_murs": surf, "surface_plafond": surf, "forme": {"t": "shape"}}


## Clés admises d'une zone (zones.json) ; {"t": "names", "max"} : {fr, en}.
static func zone_keys() -> Dictionary:
	var surf := {"t": "enum", "values": allowed_surfaces()}
	return {"id": {"t": "id"}, "nom": {"t": "names", "max": 64}, "sol": surf, "murs": surf, "plafond": surf}


# ------------------------------------------------------------------ surfaces (aperçu, noms)

## Aperçu d'une surface : [couleur A, couleur B, motif] de WorldLook.SURFACES.
static func surface_look(key: String) -> Array:
	var s: Array = WorldLook.SURFACES.get(key, WorldLook.SURFACES.wall)
	return [s[1], s[2], int(s[0])]


## Noms affichés des surfaces [FR, EN] (sinon la clé).
const SURFACE_NAMES := {
	"floor": ["Sol brut", "Rough floor"], "wall": ["Plâtre", "Plaster"], "ceiling": ["Plafond sombre", "Dark ceiling"],
	"concrete": ["Béton", "Concrete"], "concrete_dark": ["Béton sombre", "Dark concrete"], "tiles": ["Carrelage", "Tiles"],
	"wood": ["Bois", "Wood"], "metal": ["Métal", "Metal"], "stone": ["Pierre", "Stone"], "wall_green": ["Plâtre vert", "Green plaster"],
	"wall_cell": ["Plâtre de cellule", "Cell plaster"], "wall_lab": ["Carrelage de labo", "Lab tiles"], "wall_rust": ["Tôle rouillée", "Rusty sheet"],
	"wall_concrete": ["Béton de mur", "Wall concrete"], "wall_ritual": ["Pierre rituelle", "Ritual stone"], "crate": ["Bois de caisse", "Crate wood"],
	"barrel": ["Métal peint", "Painted metal"], "steel": ["Acier", "Steel"], "fabric": ["Tissu", "Fabric"], "door": ["Tôle de porte", "Door metal"],
	"carpet_red": ["Moquette rouge", "Red carpet"], "marble": ["Marbre", "Marble"], "stage_wood": ["Plancher de scène", "Stage boards"],
	"parquet": ["Parquet", "Parquet"], "wall_theater": ["Papier peint rouge", "Red wallpaper"], "wall_lobby": ["Papier peint ocre", "Ochre wallpaper"],
	"wall_foyer": ["Papier peint vert", "Green wallpaper"], "wall_loges": ["Plâtre des loges", "Box plaster"], "brick": ["Brique", "Brick"],
	"cobble": ["Pavés", "Cobblestones"], "velvet": ["Velours", "Velvet"], "brass": ["Laiton", "Brass"],
	"plaster_theater": ["Plâtre gris-vert", "Grey-green plaster"], "vault_theater": ["Voûte grise", "Grey vault"],
	"carpet_theater": ["Moquette grise", "Grey carpet"], "ceiling_theater": ["Plafond brun", "Brown ceiling"], "dark_wood": ["Bois sombre", "Dark wood"],
}


static func surface_name(key: String) -> String:
	var n: Array = SURFACE_NAMES.get(key, [key, key])
	return Lang.t(String(n[0]), String(n[1]))
