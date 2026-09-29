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
## zone de piège), opening (porte, débris, fenêtre...), wall_item (contre un
## mur), floor_item (au sol, dans une pièce).

const CATEGORIES := [
	["construction", "Construction", "Building"],
	["ouvertures", "Ouvertures", "Openings"],
	["atouts", "Atouts", "Perks"],
	["armes", "Armes murales", "Wall weapons"],
	["boite", "Boîte mystère", "Mystery box"],
	["machines", "Machines", "Machines"],
	["pieges", "Pièges", "Traps"],
	["joueurs", "Joueurs et apparitions", "Players and spawns"],
	["decor", "Décor et lumières", "Props and lights"],
]
## Barre rapide par défaut (9 cases).
const DEFAULT_HOTBAR := ["select", "piece_rect", "piece_poly", "mur", "porte", "fenetre", "boite", "depart", "arme:m14"]
## Prix BO1 des portes successives (750, puis 1000, puis 1250).
const DOOR_PRICES := [750, 1000, 1250]

static var _items: Array = []
static var _by_id: Dictionary = {}


static func items() -> Array:
	if _items.is_empty():
		_build()
	return _items


static func item(id: String) -> Dictionary:
	items()
	return _by_id.get(id, {})


static func in_category(cat: String) -> Array:
	return items().filter(func(it): return it.cat == cat)


static func name_of(it: Dictionary) -> String:
	return Lang.t(String(it.get("fr", "")), String(it.get("en", "")))


static func _add(d: Dictionary) -> void:
	d.merge({"fp": [1, 1], "color": Color(0.7, 0.7, 0.7), "price": 0, "make": {}, "hint_fr": "", "hint_en": ""})
	_items.append(d)
	_by_id[d.id] = d


static func _build() -> void:
	# Construction.
	_add({"id": "select", "cat": "construction", "fr": "Sélection", "en": "Select", "tool": "select", "color": Color(0.9, 0.9, 0.9),
		"hint_fr": "Clic : choisir un élément ; glisser : déplacer ; poignées : redimensionner", "hint_en": "Click: pick an element; drag: move; handles: resize"})
	_add({"id": "gomme", "cat": "construction", "fr": "Gomme", "en": "Eraser", "tool": "erase", "color": Color(0.95, 0.55, 0.6),
		"hint_fr": "Clic : supprimer l'élément sous le curseur", "hint_en": "Click: delete the element under the cursor"})
	_add({"id": "piece_rect", "cat": "construction", "fr": "Pièce rectangle", "en": "Rectangle room", "tool": "room_rect",
		"color": Color(0.55, 0.75, 0.95), "make": {"forme": "rect"},
		"hint_fr": "Glisser d'un coin à l'autre ; les murs suivent le contour", "hint_en": "Drag from corner to corner; walls follow the outline"})
	_add({"id": "piece_poly", "cat": "construction", "fr": "Pièce polygone", "en": "Polygon room", "tool": "room_poly",
		"color": Color(0.55, 0.9, 0.8), "make": {"forme": "poly"},
		"hint_fr": "Clics successifs, double-clic (ou clic sur le premier point) pour fermer", "hint_en": "Click each corner, double-click (or click the first point) to close"})
	_add({"id": "mur", "cat": "construction", "fr": "Mur", "en": "Wall", "tool": "wall", "color": Color(0.35, 0.35, 0.38),
		"make": {"type": "mur", "epaisseur": 0.5}, "hint_fr": "Glisser d'un bout à l'autre", "hint_en": "Drag from one end to the other"})
	_add({"id": "pilier", "cat": "construction", "fr": "Pilier / obstacle", "en": "Pillar / obstacle", "tool": "rect",
		"color": Color(0.45, 0.42, 0.4), "make": {"type": "pilier"}, "hint_fr": "Glisser un rectangle dans une pièce", "hint_en": "Drag a rectangle inside a room"})
	_add({"id": "escalier", "cat": "construction", "fr": "Escalier", "en": "Stairs", "tool": "rect",
		"color": Color(0.8, 0.55, 0.9), "make": {"type": "escalier", "monte": "n"},
		"hint_fr": "Glisser du bas vers le haut de l'escalier (monte vers l'étage du dessus)", "hint_en": "Drag from the bottom to the top of the stairs (goes up one floor)"})
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
		"hint_fr": "Sur un mur extérieur ; les zombies arrivent de dehors", "hint_en": "On an outer wall; zombies come from outside"})
	# Atouts (PerkDB).
	for id in PerkDB.PERKS:
		_add({"id": "atout:" + id, "cat": "atouts", "fr": PerkDB.display_name(id), "en": PerkDB.display_name(id), "tool": "wall_item",
			"color": PerkDB.color(id), "make": {"type": "atout", "atout": id}, "fp": [3, 2], "price": PerkDB.cost(id, false),
			"hint_fr": String(PerkDB.PERKS[id].get("desc", "")), "hint_en": String(PerkDB.PERKS[id].get("desc", ""))})
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
	# Décor et lumières.
	_add({"id": "lampe", "cat": "decor", "fr": "Lampe", "en": "Lamp", "tool": "floor_item", "color": Color(1.0, 0.85, 0.5),
		"make": {"type": "lampe"}, "fp": [1, 1], "hint_fr": "Lampe au plafond (en plus des lampes automatiques)", "hint_en": "Ceiling lamp (in addition to automatic lamps)"})
	_add({"id": "caisse", "cat": "decor", "fr": "Caisse", "en": "Crate", "tool": "floor_item", "color": Color(0.55, 0.38, 0.2),
		"make": {"type": "caisse"}, "fp": [2, 2], "hint_fr": "Obstacle de 1 m de haut", "hint_en": "1 m high obstacle"})
	_add({"id": "baril", "cat": "decor", "fr": "Baril", "en": "Barrel", "tool": "floor_item", "color": Color(0.5, 0.12, 0.08),
		"make": {"type": "baril"}, "fp": [1, 1], "hint_fr": "Petit obstacle", "hint_en": "Small obstacle"})


## Objet du catalogue correspondant à un élément de la carte (icône, nom).
static func item_for(o: Dictionary) -> Dictionary:
	var t := String(o.get("type", ""))
	match t:
		"atout":
			return item("atout:" + String(o.get("atout", "")))
		"arme":
			return item("arme:" + String(o.get("arme", "")))
		"boite":
			return item("boite_depart" if o.get("depart", false) else "boite")
		"porte", "debris", "porte_courant", "passage", "fenetre", "mur", "pilier", "escalier", "piege", "levier", "grenades", "pap", \
				"courant", "teleporteur", "arrivee", "poste_central", "depart", "apparition", "lampe", "caisse", "baril":
			return item(t)
	return {}


## Emprise en cases : [le long du mur, profondeur] (objets muraux) ou [côté, côté].
static func footprint(o: Dictionary) -> Vector2i:
	var it := item_for(o)
	var fp: Array = it.get("fp", [1, 1])
	return Vector2i(int(fp[0]), int(fp[1]))


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
