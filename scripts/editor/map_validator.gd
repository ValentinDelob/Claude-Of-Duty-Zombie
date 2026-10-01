class_name MapValidator
extends RefCounted
## Validateur des cartes de l'éditeur (docs/MAP_AUTHORING.md). MapRaster
## convertit la carte (pièces, ouvertures, objets) en une grille de cases de
## 0,5 m par étage ; ce script la VÉRIFIE (erreurs pointées par leur position
## en mètres, indicateurs d'amusement inspirés de BO1) ; MapLayoutExport en
## tire la description de carte en maillage (format de MeshMapLayout) que le
## jeu construit en 3D (MeshMapGeometry).
##
## Chaque message existe en français et en anglais ({level, fr, en, text,
## floor, cells}) ; `text` suit Settings.language.

## Décalage de la grille dans le monde (m) : x, z >= 0 (NetCodec) et place pour
## les cours derrière les fenêtres du bord.
const ORIGIN := 4.0
const SCALE := 0.5
## Épaisseur des planchers d'étage (m).
const DALLE := 0.3
const DOOR_HEIGHT := 2.5
## Cour des zombies derrière une fenêtre (cases) : profondeur, largeur.
const POCKET_DEPTH := 5
const POCKET_WIDTH := 6
const POCKET_HEIGHT := 2.9
## Apparition derrière une fenêtre, depuis le milieu du mur (m).
const SPAWN_OUT := 1.6
## Pente maximale d'un escalier (degrés ; navmesh des zombies : 42).
const MAX_STAIR_SLOPE := 40.0
const MIN_STAIR_WIDTH := 3
## Leviers de piège : distance maximale à leur zone (m).
const LEVER_RANGE := 10.0
## Départ : les joueurs autour du point de départ (m).
const START_SPREAD := 0.6
## Hauteur sous plafond minimale (m).
const MIN_CEILING := 2.8
## Barricade.SILL_TOP / LINTEL_BOTTOM : allège et linteau des fenêtres.
const SILL := 0.95
const LINTEL := 2.35
## Porte à zombies (format 8) : haut de l'ouverture (traverse du bâti), m
## au-dessus du sol ; pas d'allège (Barricade.DOOR_HEIGHT).
const ZOMBIE_DOOR_TOP := 2.1
## Spawner.MIN_PLAYER_DIST : pas d'apparition plus près d'un joueur (zombies
## qui sortent du sol ; les fenêtres n'ont plus cette distance, comme dans BO1).
const MIN_SPAWN_DIST := 7.0

enum K { VIDE, MUR, TREMIE, ESCALIER, PORTE, DEBRIS, FENETRE, SOL, MARQUEUR }
const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

## Noms des objets (clé de base -> [fr, en]) et type (mural : contre un mur, sol).
const ENTRIES := {
	"depart": ["sol", "Départ des joueurs", "Player start"],
	"apparition": ["sol", "Zombie qui sort du sol", "Ground spawn"],
	"piege": ["sol", "Zone de piège électrique", "Electric trap area"],
	"teleporteur": ["sol", "Téléporteur", "Teleporter"],
	"arrivee": ["sol", "Arrivée du téléporteur", "Teleporter exit"],
	"boite": ["mural", "Emplacement de boîte mystère", "Mystery box location"],
	"boite_depart": ["mural", "Boîte mystère (départ)", "Mystery box (start)"],
	"courant": ["mural", "Interrupteur du courant", "Power switch"],
	"pap": ["mural", "Pack-a-Punch", "Pack-a-Punch"],
	"poste_central": ["mural", "Poste central du téléporteur", "Teleporter mainframe"],
	"levier": ["mural", "Levier de piège", "Trap lever"],
	"grenades": ["mural", "Achat de grenades", "Grenade buy"],
}


class Floor:
	var index := 0
	var sol := 0.0
	## Plafond du dernier étage (m), -1 sinon.
	var plafond := -1.0
	var w := 0
	var h := 0
	var kind := PackedByteArray()
	var key := PackedStringArray()
	## Zone de chaque case praticable ("" sinon).
	var zone := PackedStringArray()
	## Plafond propre à la case (pièce à hauteur réglée), 0 : celui de l'étage.
	@warning_ignore("shadowed_global_identifier")
	var ceil := PackedFloat64Array()
	## Pièce de l'éditeur de chaque case de sol ("" sinon) : textures par pièce.
	var room := PackedStringArray()

	func setup(width: int, height: int) -> void:
		w = width
		h = height
		kind.resize(w * h)
		kind.fill(K.VIDE)
		key.resize(w * h)
		key.fill("vide")
		zone.resize(w * h)
		ceil.resize(w * h)
		room.resize(w * h)

	func room_of(c: Vector2i) -> String:
		return room[c.y * w + c.x] if inside(c) else ""

	func inside(c: Vector2i) -> bool:
		return c.x >= 0 and c.y >= 0 and c.x < w and c.y < h

	func at(c: Vector2i) -> int:
		return kind[c.y * w + c.x] if inside(c) else K.VIDE

	func key_at(c: Vector2i) -> String:
		return key[c.y * w + c.x] if inside(c) else "vide"

	func zone_of(c: Vector2i) -> String:
		return zone[c.y * w + c.x] if inside(c) else ""

	func ceil_at(c: Vector2i) -> float:
		return ceil[c.y * w + c.x] if inside(c) else 0.0

	func put(c: Vector2i, k: int, k_key: String, z := "") -> void:
		if inside(c):
			var i := c.y * w + c.x
			kind[i] = k
			key[i] = k_key
			zone[i] = z


var id := ""
var display_name := ""
var description := ""
var music := "ambience_bunker"
var door_height := DOOR_HEIGHT
var scale := SCALE
## Noms des zones pour le jeu (langue de la partie) : lettre -> nom.
var zone_names: Dictionary = {}
## Noms des zones pour les messages : lettre -> [fr, en].
var zone_label: Dictionary = {}
var floor_mats: Dictionary = {}
var wall_mats: Dictionary = {}
## Plafonds des zones (clé de WorldLook.SURFACES) : lettre -> surface.
var ceil_mats: Dictionary = {}
## Textures propres à une pièce : id de pièce -> {sol, murs, plafond} (clés
## de WorldLook.SURFACES ; absentes : celles de la zone).
var room_surfaces: Dictionary = {}
## Zone (lettre) de chaque pièce de l'éditeur : sol dessiné sous le décor.
var room_zone: Dictionary = {}
var floors: Array[Floor] = []
## Portes : clé de la case (« porte#id ») -> {cost, power, debris, eid}.
var door_info: Dictionary = {}
## Objets muraux : clé -> direction du mur (Vector2i), donnée par l'éditeur.
var wall_hint: Dictionary = {}
## Clé -> identifiant de l'élément de l'éditeur (clic sur un problème).
var eid_of: Dictionary = {}
## Décor bloquant : [{floor, rect (Rect2i, cases), h, mat, eid}].
var decor: Array = []
## Lampes ajoutées : [{floor, center (Vector2, cases)}] ; lampes automatiques ?
## Luminaires : en plus {luminaire, mount, color, energy, range, power,
## flicker, yaw, wall (Vector2i), support (m), boxes, barrier, eid}.
var lamps_extra: Array = []
## Décor posé (prefabs) : [{floor, prefab, center (Vector2, m, repère de
## l'éditeur), rot (degrés), eid}].
var props: Array = []
var lamps_auto := true
## Murs en biais (MapRaster), par étage : [{a, b (m, repère de l'éditeur),
## t (direction), n (normale), half (demi-épaisseur, m), pos, neg (pièce du
## côté +n / -n, "" : dehors), kind ("piece" : côté de pièce, "mur" : mur libre)}].
var oblique_walls: Array = []
## Cases des murs en biais qui ne sont pas aussi celles d'un mur droit, par
## étage ({Vector2i: true}) : le jeu les construit en vrais murs obliques.
var diag_cells: Array = []
## Ouvertures sur un mur en biais : clé de case -> {p (m), t, n, w (m), half, type, eid}.
var diag_open: Dictionary = {}
## Objets muraux contre un mur en biais : clé -> {p (m, sur le trait), wall (vers le mur), eid}.
var diag_items: Dictionary = {}
## Pièces par étage : [{id, poly (m), zone, ceil (m, absolu)}] (sols des murs en biais).
var room_polys: Array = []
## Escaliers tournés ou hors de la grille (MapRaster) : clé de case ->
## {center (m), size (m, contour sur le trait, avant rotation), rot (degrés),
## up (direction de montée, vecteur unitaire), cells, floor, eid}.
var diag_stairs: Dictionary = {}
## Type et réglages de chaque escalier (format 6, MapCatalog.stair_layout_opts) :
## clé de case -> {kind?, turn?, steps?, rail?, closed?} (vide : droit d'avant).
var stair_opts: Dictionary = {}
## Pièges tournés ou hors de la grille : id de l'élément -> {center, size, rot}
## (le jeu électrifie le vrai rectangle, MapLayoutExport).
var diag_traps: Dictionary = {}
## Format 5 : variante d'aspect des éléments qui en ont une autre que celle
## par défaut : id de l'élément -> variante (MapCatalog.VARIANTS).
var variants: Dictionary = {}
## Barrières invisibles (type « bloc_invisible ») : [{floor, center (m),
## size (m, avant rotation), rot (degrés), h (m, 0 : jusqu'au plafond), eid}].
var clips: Array = []

## Messages : {level ("erreur" | "attention" | "info"), fr, en, text, floor, cells}
var messages: Array = []

## Objets trouvés dans la grille.
var blobs: Array = []     # {key, base, kind, floor, cells, rect}
var doors: Array = []     # {id, floor, rect, axis, zones, debris, cost, power, cells, width, eid}
var windows: Array = []   # {floor, rect, inward, zone, pocket (Rect2i), eid}
var stairs: Array = []    # {floor, rect, up, lower, upper, run, width}
var wall_items: Array = []   # {key, base, entry, floor, cells, zone, wall, face (Vector2 cases), center}
var floor_items: Array = []  # {key, base, floor, cells, zone, center, rect}
var start_points: Array = []   # [floor, Vector2 (cases)]
## Graphe des zones : {a, b, kind ("porte", "debris", "ouvert", "escalier"), cost, power, door}
var zone_edges: Array = []
var zones: Array = []   # lettres présentes, triées
## Cases praticables par étage atteintes depuis le départ (portes ouvertes).
var reach: Array = []
## Distance à pied (m) de chaque case praticable à la fenêtre la plus proche.
var window_dist: Array = []
## Liens ouverts entre zones (transitifs) : zone -> [zones]
var open_links: Dictionary = {}
var _stair_at: Array = []   # par étage : {Vector2i: index d'escalier}
var _up_links: Dictionary = {}   # "k:x:y" -> [[k_bas, Vector2i]]
var _obstacles: Array = []   # par étage : {Vector2i: true} emprise des objets pleins
var _analyzed := false


# --------------------------------------------------------------------- objets

static func base_of(key: String) -> String:
	return key.get_slice("#", 0)


## {type, fr, en, atout?, arme?} d'une clé de case (« atout_titan#a1 »...).
static func entry(key: String) -> Dictionary:
	var base := base_of(key)
	if base.begins_with("atout_"):
		var pid := base.substr(6)
		return {"type": "mural", "atout": pid, "fr": "Atout " + PerkDB.display_name(pid), "en": "Perk " + PerkDB.display_name(pid)}
	if base.begins_with("arme_"):
		var wid := base.substr(5)
		var n := KnifeDB.display_name(wid) if KnifeDB.exists(wid) else WeaponDB.display_name(wid)
		return {"type": "mural", "arme": wid, "fr": "Arme au mur " + n, "en": "Wall weapon " + n}
	if ENTRIES.has(base):
		var e: Array = ENTRIES[base]
		return {"type": e[0], "fr": e[1], "en": e[2]}
	return {"type": "", "fr": base, "en": base}


## Emprise d'un objet mural : [largeur le long du mur, profondeur] en cases.
static func footprint(base: String) -> Array:
	var o := {"type": base}
	if base.begins_with("atout_"):
		o = {"type": "atout", "atout": base.substr(6)}
	elif base.begins_with("arme_"):
		o = {"type": "arme", "arme": base.substr(5)}
	elif base == "boite_depart":
		o = {"type": "boite", "depart": true}
	var fp := MapCatalog.footprint(o)
	return [fp.x, fp.y]


# --------------------------------------------------------------------- messages

func _msg(level: String, fr: String, en: String, k := -1, cells: Array = []) -> void:
	messages.append({"level": level, "fr": fr, "en": en, "text": Lang.t(fr, en), "floor": k, "cells": cells})


static func text_of(m: Dictionary) -> String:
	return Lang.t(String(m.get("fr", m.get("text", ""))), String(m.get("en", m.get("text", ""))))


func errors() -> Array:
	return messages.filter(func(m): return m.level == "erreur")


func warnings() -> Array:
	return messages.filter(func(m): return m.level == "attention")


func infos() -> Array:
	return messages.filter(func(m): return m.level == "info")


func ok() -> bool:
	return _analyzed and errors().is_empty()


static func _num(v: float) -> String:
	return ("%.1f" % v).trim_suffix(".0")


## Position d'une case en mètres dans l'éditeur : [fr, en].
func _at(k: int, c: Vector2i) -> Array:
	var x := _num(c.x * scale)
	var y := _num(c.y * scale)
	if floors.size() > 1:
		return ["(x %s m, y %s m, étage %d)" % [x.replace(".", ","), y.replace(".", ","), k], "(x %s m, y %s m, floor %d)" % [x, y, k]]
	return ["(x %s m, y %s m)" % [x.replace(".", ","), y.replace(".", ",")], "(x %s m, y %s m)" % [x, y]]


## Nom d'une zone : [fr, en].
func _zl(z: String) -> Array:
	return zone_label.get(z, [z.to_upper(), z.to_upper()])


func _zf(z: String) -> String:
	return String(_zl(z)[0])


func _ze(z: String) -> String:
	return String(_zl(z)[1])


func m2(n: int) -> float:
	return n * scale * scale


# --------------------------------------------------------------------- analyse

## Hauteurs des étages : 3,1 m au moins entre deux sols, plafond du dernier.
func check_floors() -> void:
	for i in floors.size():
		if i < floors.size() - 1 and floors[i + 1].sol - floors[i].sol < MIN_CEILING + DALLE:
			_msg("erreur", "étage %d : il faut au moins %s m entre deux sols (hauteur sous plafond 2,8 m + dalle)" % [i + 1, _num(MIN_CEILING + DALLE).replace(".", ",")],
				"floor %d: floors must be at least %s m apart (2.8 m ceiling + slab)" % [i + 1, _num(MIN_CEILING + DALLE)])
	if not floors.is_empty():
		var top := floors[-1]
		if top.plafond - top.sol < MIN_CEILING:
			_msg("erreur", "étage %d : plafond trop bas (%s m ; 2,8 m au moins)" % [top.index, _num(top.plafond - top.sol).replace(".", ",")],
				"floor %d: ceiling too low (%s m; at least 2.8 m)" % [top.index, _num(top.plafond - top.sol)])


func analyze() -> void:
	check_floors()
	if floors.is_empty():
		_msg("erreur", "la carte n'a aucun étage", "the map has no floor")
		return
	if not errors().is_empty():
		return
	_find_blobs()
	_marker_zones()
	_stairs()
	_openings()
	_wall_markers()
	_floor_markers()
	_cell_rules()
	if not errors().is_empty():
		_msg("info", "Les vérifications d'accès et les indicateurs d'amusement viendront une fois ces erreurs corrigées.",
			"Access checks and fun indicators will come once these errors are fixed.")
		return
	_zone_graph()
	_connectivity()
	_counts()
	if not errors().is_empty():
		return
	_start_safety()
	_fun()
	_analyzed = true


func _flood(f: Floor, start: Vector2i, same: Callable) -> Array:
	var out := [start]
	var seen := {start: true}
	var i := 0
	while i < out.size():
		var c: Vector2i = out[i]
		i += 1
		for d in DIRS:
			var n := c + d
			if f.inside(n) and not seen.has(n) and same.call(n):
				seen[n] = true
				out.append(n)
	return out


static func _bbox(cells: Array) -> Rect2i:
	var r := Rect2i(cells[0], Vector2i.ONE)
	for c in cells:
		r = r.expand(c).expand(c + Vector2i.ONE)
	return r


func _find_blobs() -> void:
	for f in floors:
		var seen := {}
		for y in f.h:
			for x in f.w:
				var c := Vector2i(x, y)
				var kd := f.at(c)
				if kd in [K.VIDE, K.MUR, K.SOL, K.TREMIE] or seen.has(c):
					continue
				var key := f.key_at(c)
				var cells := _flood(f, c, func(n: Vector2i) -> bool: return f.key_at(n) == key)
				for cc in cells:
					seen[cc] = true
				blobs.append({"key": key, "base": base_of(key), "kind": kd, "floor": f.index, "cells": cells, "rect": _bbox(cells)})


## Zone d'un objet posé sur le sol : celle du sol qui l'entoure.
func _marker_zones() -> void:
	for b in blobs:
		if b.kind != K.MARQUEUR:
			continue
		var f := floors[b.floor]
		var count := {}
		for c in b.cells:
			for d in DIRS:
				var z := f.zone_of(c + d) if f.at(c + d) == K.SOL else ""
				if z != "":
					count[z] = count.get(z, 0) + 1
		if count.is_empty():
			var e := entry(b.key)
			var w := _at(b.floor, b.cells[0])
			_msg("erreur", "%s en %s : posé hors de tout sol de pièce" % [e.fr, w[0]], "%s at %s: placed outside every room floor" % [e.en, w[1]], b.floor, b.cells)
			continue
		var best := ""
		for z in count:
			if best == "" or count[z] > count[best]:
				best = z
		b["zone"] = best
		for c in b.cells:
			f.zone[c.y * f.w + c.x] = best


static func _side(r: Rect2i, d: Vector2i) -> Array:
	var out := []
	if d.x != 0:
		var x := r.position.x - 1 if d.x < 0 else r.end.x
		for y in range(r.position.y, r.end.y):
			out.append(Vector2i(x, y))
	else:
		var y := r.position.y - 1 if d.y < 0 else r.end.y
		for x in range(r.position.x, r.end.x):
			out.append(Vector2i(x, y))
	return out


func _floorlike(f: Floor, c: Vector2i) -> bool:
	var kd := f.at(c)
	return kd == K.SOL or kd == K.MARQUEUR


func _all(cells: Array, pred: Callable) -> bool:
	for c in cells:
		if not pred.call(c):
			return false
	return true


## Case de sol d'une pièce sous un décor posé (MapRaster : case pleine, sans
## zone ; format 7, docs/MAP_OBJECTS.md § 8).
func _under_decor(f: Floor, c: Vector2i) -> bool:
	return f.at(c) == K.MUR and f.key_at(c).begins_with("decor#") and f.room_of(c) != ""


## Côté d'une ouverture : du sol (ou un objet posé au sol), ou le sol d'une
## pièce sous un décor (signalé à part : _decor_in_front).
func _side_floor(f: Floor, c: Vector2i) -> bool:
	return _floorlike(f, c) or _under_decor(f, c)


## Décor posé devant une porte, des débris ou une fenêtre : la carte reste
## valable (le décor est libre) mais le passage est gêné : un avertissement
## (les accès bloqués pour de bon sont des erreurs de _connectivity).
func _decor_in_front(f: Floor, cells: Array, what: Array, w: Array) -> void:
	var hit := cells.filter(func(c): return _under_decor(f, c))
	if hit.is_empty():
		return
	if what[1] == "window":
		_msg("attention", "fenêtre en %s : un décor posé devant gêne l'entrée des zombies (déplacez-le)" % w[0],
			"window at %s: a prop placed in front of it blocks the zombies' way in (move it)" % w[1], f.index, hit)
	else:
		_msg("attention", "%s en %s : un décor posé devant gêne le passage (déplacez-le)" % [what[0], w[0]],
			"%s at %s: a prop placed in front of it blocks the way (move it)" % [what[1], w[1]], f.index, hit)


func _uniform_zone(f: Floor, cells: Array) -> String:
	var z := ""
	for c in cells:
		var zz := String(room_zone.get(f.room_of(c), "")) if _under_decor(f, c) else f.zone_of(c)
		if z == "":
			z = zz
		elif zz != z:
			return "?"
	return z


func _stairs() -> void:
	for f in floors:
		_stair_at.append({})
	for b in blobs:
		if b.kind != K.ESCALIER:
			continue
		if diag_stairs.has(b.key):
			if not _diag_done.has(b.key):
				_diag_done[b.key] = true
				if diag_stairs[b.key].get("shaped", false):
					_shaped_stair(b)
				else:
					_diag_stair(b)
			continue
		var k: int = b.floor
		var r: Rect2i = b.rect
		var w := _at(k, b.cells[0])
		if b.cells.size() != r.get_area():
			_msg("erreur", "escalier en %s : il doit être un rectangle plein" % w[0], "stairs at %s: must be a full rectangle" % w[1], k, b.cells)
			continue
		if k >= floors.size() - 1:
			_msg("erreur", "escalier en %s : il n'y a pas d'étage au-dessus (ajoutez un étage dans l'onglet Étages)" % w[0],
				"stairs at %s: there is no floor above (add a floor in the Floors tab)" % w[1], k, b.cells)
			continue
		var f := floors[k]
		var up := floors[k + 1]
		var cands := []
		for d in DIRS:
			var bottom := _side(r, -d)
			var top := _side(r, d)
			if _all(bottom, func(c): return _floorlike(f, c)) and _all(top, func(c): return _floorlike(up, c)):
				cands.append(d)
		if cands.size() != 1:
			if cands.is_empty():
				_msg("erreur", "escalier en %s : il faut du sol au pied (étage %d) d'un seul petit côté et le plancher d'une pièce en haut (étage %d) du côté opposé" % [w[0], k, k + 1],
					"stairs at %s: needs floor at its foot (floor %d) on one short side and a room floor at the top (floor %d) on the opposite side" % [w[1], k, k + 1], k, b.cells)
			else:
				_msg("erreur", "escalier en %s : sens de montée ambigu (du sol en haut et en bas des deux côtés)" % w[0],
					"stairs at %s: ambiguous direction (floor at the top and bottom on both sides)" % w[1], k, b.cells)
			continue
		var d: Vector2i = cands[0]
		var run := absi(r.size.x) if d.x != 0 else r.size.y
		var width := r.size.y if d.x != 0 else r.size.x
		var rise := up.sol - f.sol
		var slope := _stair_slope(b.key, run * scale, width * scale, rise)
		var min_w := _stair_min_cells(b.key)
		if width < min_w:
			_msg("erreur", "escalier en %s : trop étroit (%s m ; %s m au moins)" % [w[0], _num(width * scale).replace(".", ","), _num(min_w * scale).replace(".", ",")],
				"stairs at %s: too narrow (%s m; at least %s m)" % [w[1], _num(width * scale), _num(min_w * scale)], k, b.cells)
		if slope > MAX_STAIR_SLOPE:
			var need := _stair_need(b.key, width * scale, rise, run * scale)
			_msg("erreur", "escalier en %s : trop raide (%.0f° ; %d° au plus : allongez-le à %s m)" % [w[0], slope, int(MAX_STAIR_SLOPE), _num(need).replace(".", ",")],
				"stairs at %s: too steep (%.0f°; %d° at most: make it %s m long)" % [w[1], slope, int(MAX_STAIR_SLOPE), _num(need)], k, b.cells)
		var covered := []
		for c in b.cells:
			if up.at(c) != K.TREMIE:
				covered.append(c)
		if not covered.is_empty():
			var wc := _at(k + 1, covered[0])
			_msg("erreur", "escalier en %s : l'étage %d le recouvre en %s" % [w[0], k + 1, wc[0]],
				"stairs at %s: floor %d covers it at %s" % [w[1], k + 1, wc[1]], k + 1, covered)
		var lower := _uniform_zone(f, _side(r, -d))
		var upper := _uniform_zone(up, _side(r, d))
		# Pied (sol de l'étage), palier (étage du dessus) et passages du haut
		# (marche -> case du palier) : communs aux escaliers droits et tournés.
		var foot := {}
		for c in _side(r, -d):
			foot[c] = true
		var top := {}
		for c in _side(r, d):
			top[c] = true
		var links := {}
		for c in b.cells:
			if top.has(c + d):
				links[c] = [c + d]
		var st := {"key": b.key, "floor": k, "rect": r, "up": d, "lower": lower, "upper": upper, "run": run, "width": width, "cells": b.cells,
			"foot": foot, "top": top, "links": links}
		_add_stair(st)


## Type d'escalier d'une clé de case (format 6 ; « droit » sans réglage).
func _stair_kind(key: String) -> String:
	return String(stair_opts.get(key, {}).get("kind", StairGen.DEFAULT_KIND))


## Largeur minimale (cases) d'un escalier de ce type (1,5 m : MIN_STAIR_WIDTH).
func _stair_min_cells(key: String) -> int:
	var kind := _stair_kind(key)
	if kind == StairGen.DEFAULT_KIND:
		return MIN_STAIR_WIDTH
	return ceili(float(StairGen.MIN_WIDTH.get(kind, 1.5)) / scale - 0.001)


## Pente la plus forte (degrés) d'un escalier droit de type `kind` (palier :
## volées plus courtes), de longueur `length` et de largeur `width` (m).
func _stair_slope(key: String, length: float, width: float, rise: float) -> float:
	if _stair_kind(key) != "palier":
		return rad_to_deg(atan2(rise, length))
	var st := StairGen.spec(Vector2.ZERO, Vector2(0, 1), length, width, 0.0, rise, "palier")
	return StairGen.max_slope(StairGen.plan(st))


## Longueur (m, au demi-mètre) qui ramène la pente sous MAX_STAIR_SLOPE.
func _stair_need(key: String, width: float, rise: float, from_length: float) -> float:
	if _stair_kind(key) != "palier":
		return ceili(rise / tan(deg_to_rad(MAX_STAIR_SLOPE)) / scale) * scale
	var l := ceilf(from_length / scale) * scale
	for i in 80:
		if _stair_slope(key, l, width, rise) <= MAX_STAIR_SLOPE:
			break
		l += scale
	return l


## Escalier en L, en U ou en colimaçon (MapRaster : diag_stairs « shaped ») :
## sens de montée donné par « monte », sortie là où StairGen la place (sur
## le côté du virage pour le L, à côté du pied pour le U, en face pour le
## colimaçon). Pied : cases de sol de l'étage devant le bord du pied ; palier :
## cases de sol de l'étage du dessus au-delà du bord de sortie.
func _shaped_stair(b: Dictionary) -> void:
	var info: Dictionary = diag_stairs[b.key]
	var k: int = b.floor
	var cells: Array = info.get("cells", b.cells)
	var w := _at(k, cells[0])
	var o: Dictionary = info.get("obj", {})
	var kind := MapCatalog.stair_kind(o)
	var vn := MapCatalog.variant_names("escalier", kind)
	if k >= floors.size() - 1:
		_msg("erreur", "escalier en %s : il n'y a pas d'étage au-dessus (ajoutez un étage dans l'onglet Étages)" % w[0],
			"stairs at %s: there is no floor above (add a floor in the Floors tab)" % w[1], k, cells)
		return
	var f := floors[k]
	var up := floors[k + 1]
	var rise := up.sol - f.sol
	var pl := MapRaster.stair_plan(o, f.sol, up.sol)
	var own := {}
	for c in cells:
		own[c] = true
	var foot := {}
	var top := {}
	var links := {}
	for c in cells:
		for d in DIRS:
			var q: Vector2i = c + d
			if own.has(q):
				continue
			var qc := MapGeom.cell_center(q)
			if _beyond(pl.foot, qc):
				foot[q] = true
			elif _beyond(pl.exit, qc):
				top[q] = true
				if not links.get_or_add(c, []).has(q):
					links[c].append(q)
	var foot_ok := not foot.is_empty() and _all(foot.keys(), func(c): return _floorlike(f, c))
	var top_ok := not top.is_empty() and _all(top.keys(), func(c): return _floorlike(up, c))
	if not (foot_ok and top_ok):
		var where_fr: String = {"quart": "sur le côté où il tourne, au bout", "demi_tour": "du côté du pied, à côté du départ", "colimacon": "du côté opposé au pied"}.get(kind, "")
		var where_en: String = {"quart": "on the side it turns to, at the far end", "demi_tour": "on the foot side, next to the start", "colimacon": "on the side opposite the foot"}.get(kind, "")
		_msg("erreur", "%s en %s : il faut du sol au pied (étage %d) et le plancher d'une pièce à la sortie (étage %d), %s" % [vn[0], w[0], k, k + 1, where_fr],
			"%s at %s: needs floor at its foot (floor %d) and a room floor at its exit (floor %d), %s" % [vn[1], w[1], k, k + 1, where_en], k, cells)
		return
	var walk := StairGen.walk_width(pl)
	if walk < 0.95:
		_msg("erreur", "%s en %s : trop étroit (passage de %s m ; agrandissez-le)" % [vn[0], w[0], _num(walk).replace(".", ",")],
			"%s at %s: too narrow (%s m to walk; make it bigger)" % [vn[1], w[1], _num(walk)], k, cells)
	var slope := StairGen.max_slope(pl)
	if slope > MAX_STAIR_SLOPE:
		_msg("erreur", "%s en %s : trop raide (%.0f° ; %d° au plus : agrandissez-le)" % [vn[0], w[0], slope, int(MAX_STAIR_SLOPE)],
			"%s at %s: too steep (%.0f°; %d° at most: make it bigger)" % [vn[1], w[1], slope, int(MAX_STAIR_SLOPE)], k, cells)
	if kind == "colimacon" and rise < StairGen.SPIRAL_MIN_RISE - 0.001:
		_msg("erreur", "%s en %s : étages trop proches (%s m ; %s m au moins pour passer sous le dernier quart de tour)" % [vn[0], w[0], _num(rise).replace(".", ","), _num(StairGen.SPIRAL_MIN_RISE).replace(".", ",")],
			"%s at %s: floors too close (%s m; at least %s m to walk under the last quarter turn)" % [vn[1], w[1], _num(rise), _num(StairGen.SPIRAL_MIN_RISE)], k, cells)
	var covered := []
	for c in cells:
		if up.at(c) != K.TREMIE:
			covered.append(c)
	if not covered.is_empty():
		var wc := _at(k + 1, covered[0])
		_msg("erreur", "escalier en %s : l'étage %d le recouvre en %s" % [w[0], k + 1, wc[0]],
			"stairs at %s: floor %d covers it at %s" % [w[1], k + 1, wc[1]], k + 1, covered)
	var u: Vector2 = info.up
	_add_stair({"key": b.key, "floor": k, "rect": _bbox(cells), "up": Vector2i(roundi(u.x), roundi(u.y)), "lower": _uniform_zone(f, foot.keys()),
		"upper": _uniform_zone(up, top.keys()), "run": roundi(StairGen.run_length(pl) / scale), "width": roundi(walk / scale), "cells": cells,
		"foot": foot, "top": top, "links": links, "diag": info})


## Centre de case `q` juste au-delà d'un bord d'escalier {m, n, h} (pied ou
## sortie, StairGen.plan) et en face de lui ?
static func _beyond(edge: Dictionary, q: Vector2) -> bool:
	var e: Vector2 = q - (edge.m as Vector2)
	var n: Vector2 = edge.n
	var along := e.dot(n)
	return along > 0.0 and along < 0.8 and absf(e.dot(Vector2(-n.y, n.x))) < float(edge.h) - 0.1


## Escalier retenu : cases, zone du pied, passages vers le palier du dessus.
func _add_stair(st: Dictionary) -> void:
	var k: int = st.floor
	var f := floors[k]
	var si := stairs.size()
	stairs.append(st)
	for c in st.cells:
		_stair_at[k][c] = si
		f.zone[c.y * f.w + c.x] = st.lower
	# Haut de l'escalier : passage vers les cases du palier de l'étage du dessus.
	for c in st.links:
		for t in st.links[c]:
			var key := "%d:%d:%d" % [k + 1, t.x, t.y]
			if not _up_links.has(key):
				_up_links[key] = []
			_up_links[key].append([k, c])


## Escalier TOURNÉ ou hors de la grille (MapRaster : diag_stairs) : mêmes
## règles qu'un escalier droit, dans son propre repère. Pied : cases de sol de
## l'étage qui touchent les premières marches ; palier : cases de sol de
## l'étage du dessus qui touchent les dernières ; largeur utile et pente tirées
## du vrai rectangle (contour sur le trait, marches 0,25 m en retrait).
func _diag_stair(b: Dictionary) -> void:
	var info: Dictionary = diag_stairs[b.key]
	var k: int = b.floor
	var cells: Array = info.get("cells", b.cells)
	var w := _at(k, cells[0])
	if k >= floors.size() - 1:
		_msg("erreur", "escalier en %s : il n'y a pas d'étage au-dessus (ajoutez un étage dans l'onglet Étages)" % w[0],
			"stairs at %s: there is no floor above (add a floor in the Floors tab)" % w[1], k, cells)
		return
	var f := floors[k]
	var up := floors[k + 1]
	var u: Vector2 = info.up
	var lat := Vector2(-u.y, u.x)
	var c0: Vector2 = info.center
	var sz: Vector2 = info.size
	# Longueur le long de la montée, largeur en travers (rectangle avant rotation).
	var along_x := absf(MapGeom.dir_vec("e").rotated(deg_to_rad(float(info.rot))).dot(u)) > 0.7
	var length := sz.x if along_x else sz.y
	var wide := sz.y if along_x else sz.x
	var own := {}
	for c in cells:
		own[c] = true
	var foot := {}
	var top := {}
	var links := {}
	for c in cells:
		for d in DIRS:
			var q: Vector2i = c + d
			if own.has(q):
				continue
			# Hors des marches et dans leur largeur : au-delà d'un petit côté
			# (au pied ou en haut).
			var rel := MapGeom.cell_center(q) - c0
			if absf(rel.dot(lat)) > wide * 0.5 - 0.2:
				continue
			if rel.dot(u) < 0.0:
				foot[q] = true
			else:
				top[q] = true
				if not links.get_or_add(c, []).has(q):
					links[c].append(q)
	var foot_ok := not foot.is_empty() and _all(foot.keys(), func(c): return _floorlike(f, c))
	var top_ok := not top.is_empty() and _all(top.keys(), func(c): return _floorlike(up, c))
	if not (foot_ok and top_ok):
		_msg("erreur", "escalier en %s : il faut du sol au pied (étage %d) d'un seul petit côté et le plancher d'une pièce en haut (étage %d) du côté opposé" % [w[0], k, k + 1],
			"stairs at %s: needs floor at its foot (floor %d) on one short side and a room floor at the top (floor %d) on the opposite side" % [w[1], k, k + 1], k, cells)
		return
	var run := roundi((length - MapGeom.CELL) / scale)
	var width := roundi((wide - MapGeom.CELL) / scale)
	var rise := up.sol - f.sol
	var slope := _stair_slope(b.key, maxf(length - MapGeom.CELL, 0.01), wide - MapGeom.CELL, rise)
	var min_w := _stair_min_cells(b.key)
	if width < min_w:
		_msg("erreur", "escalier en %s : trop étroit (%s m ; %s m au moins)" % [w[0], _num(width * scale).replace(".", ","), _num(min_w * scale).replace(".", ",")],
			"stairs at %s: too narrow (%s m; at least %s m)" % [w[1], _num(width * scale), _num(min_w * scale)], k, cells)
	if slope > MAX_STAIR_SLOPE:
		var need := _stair_need(b.key, wide - MapGeom.CELL, rise, length - MapGeom.CELL) + MapGeom.CELL \
			if _stair_kind(b.key) == "palier" else ceili((rise / tan(deg_to_rad(MAX_STAIR_SLOPE)) + MapGeom.CELL) / scale) * scale
		_msg("erreur", "escalier en %s : trop raide (%.0f° ; %d° au plus : allongez-le à %s m)" % [w[0], slope, int(MAX_STAIR_SLOPE), _num(need).replace(".", ",")],
			"stairs at %s: too steep (%.0f°; %d° at most: make it %s m long)" % [w[1], slope, int(MAX_STAIR_SLOPE), _num(need)], k, cells)
	var covered := []
	for c in cells:
		if up.at(c) != K.TREMIE:
			covered.append(c)
	if not covered.is_empty():
		var wc := _at(k + 1, covered[0])
		_msg("erreur", "escalier en %s : l'étage %d le recouvre en %s" % [w[0], k + 1, wc[0]],
			"stairs at %s: floor %d covers it at %s" % [w[1], k + 1, wc[1]], k + 1, covered)
	_add_stair({"key": b.key, "floor": k, "rect": _bbox(cells), "up": Vector2i(roundi(u.x), roundi(u.y)), "lower": _uniform_zone(f, foot.keys()),
		"upper": _uniform_zone(up, top.keys()), "run": run, "width": width, "cells": cells, "foot": foot, "top": top, "links": links,
		"diag": info})


func _openings() -> void:
	var pockets := {}   # étage -> {case: fenêtre}
	for b in blobs:
		if not b.kind in [K.PORTE, K.DEBRIS, K.FENETRE]:
			continue
		var k: int = b.floor
		var f := floors[k]
		var r: Rect2i = b.rect
		var w := _at(k, b.cells[0])
		var what: Array = ["porte", "door"] if b.kind == K.PORTE else (["débris", "debris"] if b.kind == K.DEBRIS else ["fenêtre", "window"])
		if diag_open.has(b.key):
			_diag_opening(b, what, pockets)
			continue
		if b.cells.size() != r.get_area():
			_msg("erreur", "%s en %s : doit être un rectangle plein" % [what[0], w[0]], "%s at %s: must be a full rectangle" % [what[1], w[1]], k, b.cells)
			continue
		var found := false
		for axis: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
			var perp := Vector2i(axis.y, axis.x)
			var ends: Array = _side(r, perp) + _side(r, -perp)
			if not _all(ends, func(c): return f.at(c) == K.MUR):
				continue
			var sa := _side(r, -axis)
			var sb := _side(r, axis)
			var thick := r.size.x if axis.x != 0 else r.size.y
			var width := r.size.y if axis.x != 0 else r.size.x
			if b.kind == K.FENETRE:
				var inward := Vector2i.ZERO
				if _all(sa, func(c): return _side_floor(f, c)) and _all(sb, func(c): return f.at(c) == K.VIDE):
					inward = -axis
				elif _all(sb, func(c): return _side_floor(f, c)) and _all(sa, func(c): return f.at(c) == K.VIDE):
					inward = axis
				else:
					continue
				found = true
				var zone := _uniform_zone(f, _side(r, inward))
				_decor_in_front(f, _side(r, inward), what, w)
				# Format 8 : type de l'entrée (fenêtre, porte simple, porte double).
				var bk := barricade_kind_of(b.key)
				var need := roundi(MapCatalog.barricade_width(bk) / scale)
				if thick != 1 or width != need:
					var bn := MapCatalog.variant_names("fenetre", bk)
					_msg("erreur", "%s en %s : elle fait %s m le long d'un mur de 0,5 m" % [String(bn[0]).to_lower(), w[0], _num(need * scale).replace(".", ",")],
						"%s at %s: it is %s m wide in a 0.5 m wall" % [String(bn[1]).to_lower(), w[1], _num(need * scale)], k, b.cells)
					break
				# Cour des zombies derrière la fenêtre : du vide sur 2,5 × 3 m
				# (1 m de plus que l'ouverture de chaque côté : porte double 4 m).
				var out := -inward
				var pocket := []
				var blocked := []
				for dd in range(1, POCKET_DEPTH + 1):
					for ll in range(-2, width + 2):
						var c: Vector2i = r.position + out * dd + perp * ll
						pocket.append(c)
						if f.at(c) != K.VIDE or pockets.get(k, {}).has(c):
							blocked.append(c)
				if not blocked.is_empty():
					var wb := _at(k, blocked[0])
					_msg("erreur", "fenêtre en %s : pas de place dehors pour les zombies (il faut 2,5 m × 3 m de vide derrière ; occupé en %s)" % [w[0], wb[0]],
						"window at %s: no room outside for the zombies (2.5 m × 3 m of empty space needed behind it; blocked at %s)" % [w[1], wb[1]], k, blocked)
					break
				if not pockets.has(k):
					pockets[k] = {}
				for c in pocket:
					pockets[k][c] = true
				windows.append({"floor": k, "rect": r, "inward": inward, "zone": zone, "cells": b.cells, "pocket": _bbox(pocket), "eid": eid_of.get(b.key, ""),
					"kind": bk})
			else:
				if not (_all(sa, func(c): return _side_floor(f, c)) and _all(sb, func(c): return _side_floor(f, c))):
					continue
				found = true
				_decor_in_front(f, sa + sb, what, w)
				var za := _uniform_zone(f, sa)
				var zb := _uniform_zone(f, sb)
				if za == "?" or zb == "?":
					_msg("erreur", "%s en %s : un de ses côtés touche deux zones différentes" % [what[0], w[0]],
						"%s at %s: one of its sides touches two different zones" % [what[1], w[1]], k, b.cells)
				elif za == zb:
					_msg("erreur", "%s en %s : elle relie deux pièces de la même zone « %s » (une porte sépare deux zones : séparez-les dans l'onglet Zones)" % [what[0], w[0], _zf(za)],
						"%s at %s: it links two rooms of the same zone \"%s\" (a door separates two zones: split them in the Zones tab)" % [what[1], w[1], _ze(za)], k, b.cells)
				else:
					var info: Dictionary = door_info.get(b.key, {})
					if width < 2:
						_msg("erreur", "%s en %s : trop étroite (0,5 m ; 1 m au moins, 1,5 m conseillé)" % [what[0], w[0]],
							"%s at %s: too narrow (0.5 m; at least 1 m, 1.5 m advised)" % [what[1], w[1]], k, b.cells)
					elif width < 3:
						_msg("attention", "%s en %s : étroite (%s m ; BO1 : 1,5 à 3 m)" % [what[0], w[0], _num(width * scale).replace(".", ",")],
							"%s at %s: narrow (%s m; BO1: 1.5 to 3 m)" % [what[1], w[1], _num(width * scale)], k, b.cells)
					doors.append({"floor": k, "rect": r, "axis": axis, "zones": [za, zb] if za < zb else [zb, za], "debris": b.kind == K.DEBRIS,
						"cost": int(info.get("cost", 0)), "power": bool(info.get("power", false)), "cells": b.cells, "width": width,
						"eid": String(info.get("eid", ""))})
			break
		if not found:
			if b.kind == K.FENETRE:
				_msg("erreur", "fenêtre en %s : elle doit être dans un mur extérieur, avec le sol d'une pièce d'un côté et du vide (dehors) de l'autre" % w[0],
					"window at %s: it must be in an outer wall, with a room floor on one side and empty space (outside) on the other" % w[1], k, b.cells)
			else:
				_msg("erreur", "%s en %s : elle doit être sur le mur commun de deux pièces collées (mur aux deux bouts, sol de chaque côté)" % [what[0], w[0]],
					"%s at %s: it must be on the shared wall of two touching rooms (wall at both ends, floor on each side)" % [what[1], w[1]], k, b.cells)
	# Identifiants stables : ordre de lecture (étage, ligne, colonne).
	doors.sort_custom(func(a, b): return [a.floor, a.rect.position.y, a.rect.position.x] < [b.floor, b.rect.position.y, b.rect.position.x])
	for i in doors.size():
		doors[i]["id"] = str(i + 1)
		doors[i]["link_id"] = ""


## Type d'entrée des zombies (format 8) de l'ouverture `key` (fenêtre) :
## « fenetre » (par défaut), « porte » ou « porte_double » (variants).
func barricade_kind_of(key: String) -> String:
	var v := String(variants.get(String(eid_of.get(key, "")), ""))
	return v if MapCatalog.BARRICADE_WIDTHS.has(v) else "fenetre"


## Ouvertures déjà traitées sur un mur en biais (une par clé, même si ses
## cases forment plusieurs morceaux).
var _diag_done: Dictionary = {}


## Ouverture sur un mur EN BIAIS (MapRaster : diag_open) : mêmes règles que
## sur un mur droit. Porte, débris : du sol d'une pièce de chaque côté, deux
## zones différentes ; fenêtre : du sol d'un côté, du vide de l'autre et la
## place de la cour des zombies (3 m le long du mur, 2,5 m de profondeur).
## Les côtés sont les cases voisines des cases de l'ouverture, rangées selon
## le côté du trait du mur où tombe leur centre.
func _diag_opening(b: Dictionary, what: Array, pockets: Dictionary) -> void:
	if _diag_done.has(b.key):
		return
	_diag_done[b.key] = true
	var info: Dictionary = diag_open[b.key]
	var k: int = b.floor
	var f := floors[k]
	var cells: Array = info.cells.filter(func(c): return f.key_at(c) == b.key)
	if cells.is_empty():
		cells = b.cells
	var rect := _bbox(cells)
	var w := _at(k, cells[0])
	var p: Vector2 = info.p
	var n: Vector2 = info.n
	var own := {}
	for c in cells:
		own[c] = true
	var pos := {}
	var neg := {}
	for c in cells:
		for d in DIRS:
			var q: Vector2i = c + d
			if own.has(q) or f.at(q) == K.MUR:
				continue
			if (MapGeom.cell_center(q) - p).dot(n) > 0.0:
				pos[q] = true
			else:
				neg[q] = true
	var sa: Array = pos.keys()
	var sb: Array = neg.keys()
	var floor_a := not sa.is_empty() and _all(sa, func(c): return _floorlike(f, c))
	var floor_b := not sb.is_empty() and _all(sb, func(c): return _floorlike(f, c))
	if b.kind == K.FENETRE:
		var inward := Vector2.ZERO
		var inside := []
		if floor_a and not sb.is_empty() and _all(sb, func(c): return f.at(c) == K.VIDE):
			inward = n
			inside = sa
		elif floor_b and not sa.is_empty() and _all(sa, func(c): return f.at(c) == K.VIDE):
			inward = -n
			inside = sb
		else:
			_msg("erreur", "fenêtre en %s : elle doit être dans un mur extérieur, avec le sol d'une pièce d'un côté et du vide (dehors) de l'autre" % w[0],
				"window at %s: it must be in an outer wall, with a room floor on one side and empty space (outside) on the other" % w[1], k, cells)
			return
		# Cour des zombies : les cases dont le centre est dans la cour (hors
		# des cases coupées par le mur) sont du vide.
		var out := -inward
		var bk := barricade_kind_of(b.key)
		var poly := MapGeom.oriented_rect(p + out * MapGeom.WALL_HALF, out, MapRules.pocket_width(MapCatalog.barricade_width(bk)), 2.5)
		var pocket := []
		var blocked := []
		var bb := MapGeom.bbox(poly)
		for j in range(floori(bb.position.y / MapGeom.CELL), ceili(bb.end.y / MapGeom.CELL) + 1):
			for i in range(floori(bb.position.x / MapGeom.CELL), ceili(bb.end.x / MapGeom.CELL) + 1):
				var c := Vector2i(i, j)
				var cc := MapGeom.cell_center(c)
				if not MapGeom.contains(poly, cc) or absf((cc - p).dot(n)) < 0.6:
					continue
				pocket.append(c)
				if f.at(c) != K.VIDE or pockets.get(k, {}).has(c):
					blocked.append(c)
		if not blocked.is_empty():
			var wb := _at(k, blocked[0])
			_msg("erreur", "fenêtre en %s : pas de place dehors pour les zombies (il faut 2,5 m × 3 m de vide derrière ; occupé en %s)" % [w[0], wb[0]],
				"window at %s: no room outside for the zombies (2.5 m × 3 m of empty space needed behind it; blocked at %s)" % [w[1], wb[1]], k, blocked)
			return
		for c in pocket:
			pockets.get_or_add(k, {})[c] = true
		windows.append({"floor": k, "rect": rect, "inward": inward, "zone": _uniform_zone(f, inside), "cells": cells,
			"pocket": _bbox(pocket) if not pocket.is_empty() else rect, "pocket_poly": poly, "inside": inside, "p": p,
			"oblique": true, "eid": eid_of.get(b.key, ""), "kind": bk})
		return
	if not (floor_a and floor_b):
		_msg("erreur", "%s en %s : elle doit être sur le mur commun de deux pièces collées (mur aux deux bouts, sol de chaque côté)" % [what[0], w[0]],
			"%s at %s: it must be on the shared wall of two touching rooms (wall at both ends, floor on each side)" % [what[1], w[1]], k, cells)
		return
	var za := _uniform_zone(f, sa)
	var zb := _uniform_zone(f, sb)
	if za == "?" or zb == "?":
		_msg("erreur", "%s en %s : un de ses côtés touche deux zones différentes" % [what[0], w[0]],
			"%s at %s: one of its sides touches two different zones" % [what[1], w[1]], k, cells)
		return
	if za == zb:
		_msg("erreur", "%s en %s : elle relie deux pièces de la même zone « %s » (une porte sépare deux zones : séparez-les dans l'onglet Zones)" % [what[0], w[0], _zf(za)],
			"%s at %s: it links two rooms of the same zone \"%s\" (a door separates two zones: split them in the Zones tab)" % [what[1], w[1], _ze(za)], k, cells)
		return
	var width := roundi(float(info.w) / scale)
	if width < 2:
		_msg("erreur", "%s en %s : trop étroite (0,5 m ; 1 m au moins, 1,5 m conseillé)" % [what[0], w[0]],
			"%s at %s: too narrow (0.5 m; at least 1 m, 1.5 m advised)" % [what[1], w[1]], k, cells)
	elif width < 3:
		_msg("attention", "%s en %s : étroite (%s m ; BO1 : 1,5 à 3 m)" % [what[0], w[0], _num(width * scale).replace(".", ",")],
			"%s at %s: narrow (%s m; BO1: 1.5 to 3 m)" % [what[1], w[1], _num(width * scale)], k, cells)
	var dinfo: Dictionary = door_info.get(b.key, {})
	doors.append({"floor": k, "rect": rect, "axis": Vector2i.ZERO, "zones": [za, zb] if za < zb else [zb, za], "debris": b.kind == K.DEBRIS,
		"cost": int(dinfo.get("cost", 0)), "power": bool(dinfo.get("power", false)), "cells": cells, "width": width,
		"eid": String(dinfo.get("eid", "")), "oblique": true, "p": p, "t": info.t, "n": n})


## Objet mural contre un mur EN BIAIS (MapRaster : diag_items) : il faut du
## mur plein derrière lui sur toute sa largeur (pas d'ouverture) ; la place
## devant a été vérifiée par la grille (ses cases sont du sol).
func _diag_wall_marker(b: Dictionary, e: Dictionary) -> void:
	var info: Dictionary = diag_items[b.key]
	var k: int = b.floor
	var f := floors[k]
	var w := _at(k, b.cells[0])
	var p: Vector2 = info.p
	var dv: Vector2 = info.wall
	var t := Vector2(-dv.y, dv.x)
	var fp: Array = footprint(b.base)
	var wide := float(fp[0]) * scale
	var bad := []
	var steps := maxi(2, ceili(wide / 0.25))
	for i in steps + 1:
		var q: Vector2 = p + t * (-wide * 0.5 + wide * float(i) / steps) * 0.96
		var c := MapGeom.cell_of(q)
		if f.at(c) != K.MUR and not bad.has(c):
			bad.append(c)
	if not bad.is_empty():
		var wb := _at(k, bad[0])
		_msg("erreur", "%s en %s : pas la place (il faut %s m de mur plein derrière ; gêné en %s)" % [e.fr, w[0], _num(wide).replace(".", ","), wb[0]],
			"%s at %s: not enough room (needs %s m of solid wall behind; blocked at %s)" % [e.en, w[1], _num(wide), wb[1]], k, bad)
		return
	var cx := 0.0
	var cy := 0.0
	for c in b.cells:
		cx += c.x + 0.5
		cy += c.y + 0.5
	var center := Vector2(cx / b.cells.size(), cy / b.cells.size())
	var face_m: Vector2 = p - dv * MapGeom.WALL_HALF
	var face := face_m / scale + Vector2(0.5, 0.5)
	if int(fp[1]) >= 2:
		for c in b.cells:
			_obstacles[k][c] = true
	wall_items.append({"key": b.key, "base": b.base, "entry": e, "floor": k, "cells": b.cells, "zone": b.zone, "wall": dv,
		"face": face, "center": center, "oblique": true})


func _wall_markers() -> void:
	for f in floors:
		_obstacles.append({})
	for b in blobs:
		if b.kind != K.MARQUEUR or not b.has("zone"):
			continue
		var e := entry(b.key)
		if e.type != "mural":
			continue
		if diag_items.has(b.key):
			if not _diag_done.has(b.key):
				_diag_done[b.key] = true
				_diag_wall_marker(b, e)
			continue
		var k: int = b.floor
		var f := floors[k]
		var w := _at(k, b.cells[0])
		var counts := {}
		for d in DIRS:
			var n := 0
			for c in b.cells:
				if f.at(c + d) == K.MUR:
					n += 1
			counts[d] = n
		var best := Vector2i.ZERO
		var tie := false
		if wall_hint.has(b.key):
			best = wall_hint[b.key] if counts.get(wall_hint[b.key], 0) > 0 else Vector2i.ZERO
		else:
			for d in DIRS:
				if counts[d] == 0:
					continue
				if best == Vector2i.ZERO or counts[d] > counts[best]:
					best = d
					tie = false
				elif counts[d] == counts[best]:
					tie = true
		if best == Vector2i.ZERO:
			_msg("erreur", "%s en %s : doit être contre un mur" % [e.fr, w[0]], "%s at %s: must stand against a wall" % [e.en, w[1]], k, b.cells)
			continue
		if tie:
			_msg("erreur", "%s en %s : dans un angle, le mur visé est ambigu — décalez-le le long du mur" % [e.fr, w[0]],
				"%s at %s: in a corner, the target wall is ambiguous — slide it along the wall" % [e.en, w[1]], k, b.cells)
			continue
		# Centre de l'objet et face du mur (en cases).
		var cx := 0.0
		var cy := 0.0
		for c in b.cells:
			cx += c.x + 0.5
			cy += c.y + 0.5
		var center := Vector2(cx / b.cells.size(), cy / b.cells.size())
		var r: Rect2i = b.rect
		var face := center
		var row := 0   # indice (le long de best) de la rangée collée au mur
		if best.x < 0:
			face.x = r.position.x
			row = r.position.x
		elif best.x > 0:
			face.x = r.end.x
			row = r.end.x - 1
		elif best.y < 0:
			face.y = r.position.y
			row = r.position.y
		else:
			face.y = r.end.y
			row = r.end.y - 1
		var fp: Array = footprint(b.base)
		var lat := Vector2i(absi(best.y), absi(best.x))
		var lc := center.x if lat.x != 0 else center.y
		var l0 := floori(lc - fp[0] / 2.0 + 0.01)
		var bad := []
		for l in range(l0, l0 + fp[0]):
			var wall_c := Vector2i(l, row + best.y) if lat.x != 0 else Vector2i(row + best.x, l)
			if f.at(wall_c) != K.MUR:
				bad.append(wall_c)
			for dd in fp[1]:
				var c := Vector2i(l, row - best.y * dd) if lat.x != 0 else Vector2i(row - best.x * dd, l)
				if not (f.at(c) == K.SOL or b.cells.has(c)):
					bad.append(c)
		if not bad.is_empty():
			var wb := _at(k, bad[0])
			_msg("erreur", "%s en %s : pas la place (il faut %s m de mur derrière et %s × %s m de sol libre devant ; gêné en %s)" % [e.fr, w[0], _num(fp[0] * scale).replace(".", ","), _num(fp[0] * scale).replace(".", ","), _num(fp[1] * scale).replace(".", ","), wb[0]],
				"%s at %s: not enough room (needs %s m of wall behind and %s × %s m of free floor in front; blocked at %s)" % [e.en, w[1], _num(fp[0] * scale), _num(fp[0] * scale), _num(fp[1] * scale), wb[1]], k, bad)
			continue
		# Objets pleins (boîte, distributeurs...) : leur emprise gêne le passage.
		if fp[1] >= 2:
			for l in range(l0, l0 + fp[0]):
				for dd in fp[1]:
					_obstacles[k][Vector2i(l, row - best.y * dd) if lat.x != 0 else Vector2i(row - best.x * dd, l)] = true
		wall_items.append({"key": b.key, "base": b.base, "entry": e, "floor": k, "cells": b.cells, "zone": b.zone, "wall": best, "face": face, "center": center})


func _floor_markers() -> void:
	for b in blobs:
		if b.kind != K.MARQUEUR or not b.has("zone"):
			continue
		var e := entry(b.key)
		if e.type != "sol":
			continue
		var cx := 0.0
		var cy := 0.0
		for c in b.cells:
			cx += c.x + 0.5
			cy += c.y + 0.5
		floor_items.append({"key": b.key, "base": b.base, "floor": b.floor, "cells": b.cells, "zone": b.zone,
			"center": Vector2(cx / b.cells.size(), cy / b.cells.size()), "rect": b.rect})
	var starts := floor_items.filter(func(it): return it.base == "depart")
	if starts.is_empty():
		_msg("erreur", "aucun départ des joueurs (inventaire : Joueurs et apparitions > Départ des joueurs, dans la zone de départ)",
			"no player start (inventory: Players and spawns > Player start, in the starting zone)")
		return
	for it in starts:
		if it.zone != "a":
			var w := _at(it.floor, it.cells[0])
			_msg("erreur", "départ des joueurs en %s dans la zone « %s » : il doit être dans la zone de départ « %s » (zone ouverte au début)" % [w[0], _zf(it.zone), _zf("a")],
				"player start at %s in zone \"%s\": it must be in the starting zone \"%s\" (open at the start)" % [w[1], _ze(it.zone), _ze("a")], it.floor, it.cells)
	var pts := []
	if starts.size() == 1:
		var c: Vector2 = starts[0].center
		var o := START_SPREAD / scale
		for v in [Vector2(-o, -o), Vector2(o, -o), Vector2(-o, o), Vector2(o, o)]:
			pts.append([starts[0].floor, c + v])
	else:
		for it in starts:
			pts.append([it.floor, it.center])
	for p in pts:
		var f := floors[p[0]]
		var cell := Vector2i(floori(p[1].x), floori(p[1].y))
		# Le joueur (rayon ~0,4 m) doit tenir : la case et ses voisines sont du sol.
		var clear := true
		for d in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if not _floorlike(f, cell + d):
				clear = false
		if not clear:
			var w := _at(p[0], cell)
			_msg("erreur", "départ des joueurs en %s : trop près d'un mur ou d'un objet (laissez 1 m autour)" % w[0],
				"player start at %s: too close to a wall or an object (leave 1 m around it)" % w[1], p[0], [cell])
			return
	start_points = pts


## Règles case par case : pas de sol au bord du vide, trémies fermées,
## passages assez larges.
func _cell_rules() -> void:
	for f in floors:
		var k := f.index
		var no_wall := []
		var bad_tremie := []
		var tremie_void := []
		for y in f.h:
			for x in f.w:
				var c := Vector2i(x, y)
				var kd := f.at(c)
				if kd in [K.SOL, K.MARQUEUR, K.PORTE, K.DEBRIS, K.ESCALIER]:
					for d in DIRS:
						if f.at(c + d) == K.VIDE:
							no_wall.append(c)
							break
				elif kd == K.TREMIE:
					if k == 0 or floors[k - 1].at(c) in [K.VIDE]:
						bad_tremie.append(c)
					else:
						for d in DIRS:
							if f.at(c + d) == K.VIDE:
								tremie_void.append(c)
								break
		for group in _groups(no_wall):
			var w := _at(k, group[0])
			_msg("erreur", "sol au bord du vide sans mur en %s : fermez la pièce (une fenêtre se pose DANS un mur)" % w[0],
				"floor next to empty space without a wall at %s: close the room (a window goes IN a wall)" % w[1], k, group)
		for group in _groups(bad_tremie):
			var w := _at(k, group[0])
			_msg("erreur", "vide d'étage en %s : rien en dessous (un vide s'ouvre sur une pièce de l'étage du dessous)" % w[0],
				"floor opening at %s: nothing below it (an opening looks down on a room of the floor below)" % w[1], k, group)
		for group in _groups(tremie_void):
			var w := _at(k, group[0])
			_msg("erreur", "vide d'étage en %s bordé de vide à l'étage %d : posez une pièce à cet étage autour de l'escalier ou de la double hauteur" % [w[0], k],
				"floor opening at %s bordered by empty space on floor %d: put a room on this floor around the stairs or the double-height room" % [w[1], k], k, group)
		_narrow(f)


## Passages de 1 case (erreur) ou 2 cases (goulot) de large.
func _narrow(f: Floor) -> void:
	var one := []
	var two := []
	var obst: Dictionary = _obstacles[f.index] if f.index < _obstacles.size() else {}
	var free := func(n: Vector2i) -> bool: return _walk(f, n) and not obst.has(n)
	for y in f.h:
		for x in f.w:
			var c := Vector2i(x, y)
			if not f.at(c) in [K.SOL, K.MARQUEUR] or obst.has(c):
				continue
			for axis: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
				var perp := Vector2i(axis.y, axis.x)
				var run := 1
				var n := c + axis
				while free.call(n) and run < 4:
					run += 1
					n += axis
				n = c - axis
				while free.call(n) and run < 4:
					run += 1
					n -= axis
				# Passage (pas une niche) : praticable sur 2 cases devant et derrière.
				if run <= 2 and free.call(c + perp) and free.call(c + perp * 2) and free.call(c - perp) and free.call(c - perp * 2):
					(one if run == 1 else two).append(c)
					break
	for group in _groups(one):
		var w := _at(f.index, group[0])
		_msg("erreur", "passage de 0,5 m en %s : trop étroit pour les zombies et les joueurs (1 m au moins)" % w[0],
			"0.5 m passage at %s: too narrow for zombies and players (at least 1 m)" % w[1], f.index, group)
	for group in _groups(two):
		var w := _at(f.index, group[0])
		_msg("attention", "goulot de 1 m en %s : les zombies y passent à la file ; BO1 : couloirs de 2 à 4 m" % w[0],
			"1 m bottleneck at %s: zombies go through in single file; BO1: 2 to 4 m corridors" % w[1], f.index, group)


func _walk(f: Floor, c: Vector2i) -> bool:
	return f.at(c) in [K.SOL, K.MARQUEUR, K.PORTE, K.DEBRIS, K.ESCALIER]


## Regroupe des cases voisines (8-connexité) ; les plus gros groupes d'abord.
func _groups(cells: Array) -> Array:
	var left := {}
	for c in cells:
		left[c] = true
	var out := []
	while not left.is_empty():
		var s: Vector2i = left.keys()[0]
		left.erase(s)
		var g := [s]
		var i := 0
		while i < g.size():
			var c: Vector2i = g[i]
			i += 1
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					var n := c + Vector2i(dx, dy)
					if left.has(n):
						left.erase(n)
						g.append(n)
		out.append(g)
	out.sort_custom(func(a, b): return a.size() > b.size())
	return out.slice(0, 8)


# --------------------------------------------------------------------- graphe

## Cases voisines praticables : même étage, escaliers par leurs deux bouts.
## `doors_open` : les portes et débris se traversent.
func _neighbors(k: int, c: Vector2i, doors_open: bool) -> Array:
	var f := floors[k]
	var out := []
	var here := f.at(c)
	var st_here: int = _stair_at[k].get(c, -1)
	for d in DIRS:
		var n := c + d
		var kd := f.at(n)
		if not _walk(f, n):
			continue
		if not doors_open and kd in [K.PORTE, K.DEBRIS]:
			continue
		var st_n: int = _stair_at[k].get(n, -1)
		if st_here >= 0 and st_n == st_here:
			out.append([k, n])
		elif st_here >= 0:
			# Du pied de l'escalier vers le sol de l'étage.
			if stairs[st_here].foot.has(n):
				out.append([k, n])
		elif st_n >= 0:
			if stairs[st_n].foot.has(c):
				out.append([k, n])
		elif here != K.ESCALIER:
			out.append([k, n])
	# Haut d'escalier : passage entre la dernière marche et le palier du dessus.
	if st_here >= 0:
		for t in stairs[st_here].links.get(c, []):
			out.append([k + 1, t])
	var key := "%d:%d:%d" % [k, c.x, c.y]
	for l in _up_links.get(key, []):
		out.append(l)
	return out


func _bfs(sources: Array, doors_open: bool, filter := Callable()) -> Dictionary:
	var seen := {}
	var queue := []
	for s in sources:
		var key: String = "%d:%d:%d" % [s[0], s[1].x, s[1].y]
		if not seen.has(key):
			seen[key] = 0
			queue.append(s)
	var i := 0
	while i < queue.size():
		var cur: Array = queue[i]
		i += 1
		var dist: int = seen["%d:%d:%d" % [cur[0], cur[1].x, cur[1].y]]
		for n in _neighbors(cur[0], cur[1], doors_open):
			var key: String = "%d:%d:%d" % [n[0], n[1].x, n[1].y]
			if seen.has(key):
				continue
			if filter.is_valid() and not filter.call(cur, n):
				continue
			seen[key] = dist + 1
			queue.append(n)
	return seen


static func _pair(a: String, b: String) -> String:
	return "%s-%s" % [a, b] if a < b else "%s-%s" % [b, a]


func _zone_graph() -> void:
	var present := {}
	for f in floors:
		for i in f.zone.size():
			if f.zone[i] != "":
				present[f.zone[i]] = true
	zones = present.keys()
	zones.sort()
	var open := {}
	for f in floors:
		for y in f.h:
			for x in f.w:
				var c := Vector2i(x, y)
				if not _floorlike(f, c):
					continue
				for d in [Vector2i(1, 0), Vector2i(0, 1)]:
					var n: Vector2i = c + d
					if _floorlike(f, n) and f.zone_of(n) != f.zone_of(c):
						open[_pair(f.zone_of(c), f.zone_of(n))] = ["ouvert", f.index, c]
	for s in stairs:
		if s.lower != s.upper and s.lower != "?" and s.upper != "?":
			open[_pair(s.lower, s.upper)] = ["escalier", s.floor, s.cells[0]]
	for pair in open:
		var z: PackedStringArray = pair.split("-")
		zone_edges.append({"a": z[0], "b": z[1], "kind": open[pair][0], "cost": 0, "power": false, "door": null})
	for d in doors:
		zone_edges.append({"a": d.zones[0], "b": d.zones[1], "kind": "debris" if d.debris else "porte", "cost": d.cost, "power": d.power, "door": d})
	# Groupes de zones ouvertes l'une sur l'autre sans porte (transitifs).
	for z in zones:
		var group := _open_group(z)
		group.erase(z)
		if not group.is_empty():
			open_links[z] = group


func _open_group(z: String) -> Array:
	var group := [z]
	var i := 0
	while i < group.size():
		for e in zone_edges:
			if e.door != null:
				continue
			for pair in [[e.a, e.b], [e.b, e.a]]:
				if pair[0] == group[i] and not group.has(pair[1]):
					group.append(pair[1])
		i += 1
	return group


func _key(k: int, c: Vector2i) -> String:
	return "%d:%d:%d" % [k, c.x, c.y]


func _connectivity() -> void:
	var sources := []
	for p in start_points:
		sources.append([p[0], Vector2i(floori(p[1].x), floori(p[1].y))])
	var seen := _bfs(sources, true)
	var tp_exit := ""
	for it in floor_items:
		if it.base == "arrivee":
			tp_exit = it.zone
	var lost := {}
	for f in floors:
		var arr := PackedByteArray()
		arr.resize(f.w * f.h)
		for y in f.h:
			for x in f.w:
				var c := Vector2i(x, y)
				if not _walk(f, c):
					continue
				if seen.has(_key(f.index, c)):
					arr[y * f.w + x] = 1
				elif f.zone_of(c) != tp_exit or tp_exit == "":
					lost.get_or_add(f.index, []).append(c)
		reach.append(arr)
	for k in lost:
		for group in _groups(lost[k]):
			var z := floors[k].zone_of(group[0])
			var w := _at(k, group[0])
			var nf := "zone « %s »" % _zf(z) if z != "" else "passage"
			var ne := "zone \"%s\"" % _ze(z) if z != "" else "passage"
			_msg("erreur", "%s inaccessible depuis le départ, même toutes portes ouvertes (en %s) : il manque une porte, un passage ou un escalier" % [nf, w[0]],
				"%s unreachable from the start, even with every door open (at %s): a door, a passage or stairs is missing" % [ne, w[1]], k, group)
	# Une zone d'un seul tenant (sans passer de porte) : sinon ses pièces ne se touchent pas.
	for z in zones:
		var cells := []
		for f in floors:
			for y in f.h:
				for x in f.w:
					var c := Vector2i(x, y)
					if _walk(f, c) and f.zone_of(c) == z:
						cells.append([f.index, c])
		var part := _bfs([cells[0]], false, func(_a, n): return floors[n[0]].zone_of(n[1]) == z)
		var rest := cells.filter(func(kc): return not part.has(_key(kc[0], kc[1])))
		if not rest.is_empty():
			var w0 := _at(cells[0][0], cells[0][1])
			var w1 := _at(rest[0][0], rest[0][1])
			_msg("erreur", "zone « %s » coupée en morceaux sans passage entre eux : %s et %s — ajoutez un passage libre entre ses pièces, ou séparez la zone (onglet Zones)" % [_zf(z), w0[0], w1[0]],
				"zone \"%s\" is split into parts with no passage between them: %s and %s — add an open passage between its rooms, or split the zone (Zones tab)" % [_ze(z), w0[1], w1[1]],
				rest[0][0], rest.map(func(kc): return kc[1]).slice(0, 60))
	# Distance à pied de chaque case à la fenêtre la plus proche.
	var wsrc := []
	for w in windows:
		for c in (w.inside if w.has("oblique") else _side(w.rect, w.inward)):
			wsrc.append([w.floor, c])
	var wd := _bfs(wsrc, true)
	for f in floors:
		var arr := PackedFloat32Array()
		arr.resize(f.w * f.h)
		arr.fill(-1.0)
		for y in f.h:
			for x in f.w:
				var key := _key(f.index, Vector2i(x, y))
				if wd.has(key):
					arr[y * f.w + x] = wd[key] * scale
		window_dist.append(arr)


func _counts() -> void:
	var n := {}
	for it in wall_items + floor_items:
		n[it.base] = n.get(it.base, 0) + 1
	var boxes: int = n.get("boite", 0) + n.get("boite_depart", 0)
	if boxes == 0:
		_msg("erreur", "aucun emplacement de boîte mystère (inventaire : Boîte mystère, contre un mur)", "no mystery box location (inventory: Mystery box, against a wall)")
	elif boxes < 3:
		_msg("attention", "%d emplacement(s) de boîte seulement : la boîte se déplace entre au moins 3 emplacements (BO1 : 6 à 9 selon la taille)" % boxes,
			"only %d box location(s): the box moves between at least 3 locations (BO1: 6 to 9 depending on size)" % boxes)
	if n.get("boite_depart", 0) > 1:
		_msg("erreur", "%d emplacements « boîte (départ) » : un seul" % n.boite_depart, "%d \"box (start)\" locations: only one" % n.boite_depart)
	for key in ["courant", "pap", "teleporteur", "arrivee", "poste_central"]:
		if n.get(key, 0) > 1:
			var its := (wall_items + floor_items).filter(func(it): return it.base == key)
			var e := entry(key)
			_msg("erreur", "%d × %s : un seul par carte" % [n[key], e.fr], "%d × %s: only one per map" % [n[key], e.en], its[1].floor, its[1].cells)
	if n.get("courant", 0) == 0:
		_msg("attention", "pas d'interrupteur du courant : le courant sera là dès le départ (BO1 : on le rétablit dans une salle éloignée)",
			"no power switch: the power will be on from the start (BO1: you turn it on in a distant room)")
	if n.get("teleporteur", 0) != n.get("arrivee", 0):
		_msg("erreur", "téléporteur : il faut une plateforme ET une arrivée", "teleporter: it needs a pad AND an exit")
	if n.get("poste_central", 0) > 0 and n.get("teleporteur", 0) == 0:
		_msg("erreur", "poste central sans téléporteur", "mainframe without a teleporter")
	for pid in PerkDB.PERKS:
		if n.get("atout_" + pid, 0) > 1:
			_msg("erreur", "%d distributeurs %s : un seul par atout" % [n["atout_" + pid], PerkDB.display_name(pid)],
				"%d %s machines: only one per perk" % [n["atout_" + pid], PerkDB.display_name(pid)])
	# Chaque zone a au moins une fenêtre (sauf la salle du téléporteur).
	var tp_exit := ""
	for it in floor_items:
		if it.base == "arrivee":
			tp_exit = it.zone
	for z in zones:
		if windows.any(func(w): return w.zone == z):
			continue
		if z == tp_exit:
			_msg("info", "zone « %s » (arrivée du téléporteur) sans fenêtre : aucun zombie n'y apparaît" % _zf(z),
				"zone \"%s\" (teleporter exit) has no window: no zombie spawns there" % _ze(z))
		else:
			_msg("erreur", "zone « %s » sans fenêtre : les zombies n'y apparaîtraient jamais (ajoutez une fenêtre dans un mur extérieur)" % _zf(z),
				"zone \"%s\" has no window: zombies would never spawn there (add a window in an outer wall)" % _ze(z))
	# Pièges : chaque zone de piège a un levier proche, chaque levier sa zone.
	var traps := floor_items.filter(func(it): return it.base == "piege")
	var levers := wall_items.filter(func(it): return it.base == "levier")
	for lv in levers:
		var best: Variant = null
		for t in traps:
			if t.floor == lv.floor and (t.center - lv.center).length() * scale <= LEVER_RANGE and (best == null or (t.center - lv.center).length() < (best.center - lv.center).length()):
				best = t
		if best == null:
			var w := _at(lv.floor, lv.cells[0])
			_msg("erreur", "levier en %s : aucune zone de piège à moins de %d m" % [w[0], int(LEVER_RANGE)],
				"lever at %s: no trap area within %d m" % [w[1], int(LEVER_RANGE)], lv.floor, lv.cells)
		else:
			best.get_or_add("levers", []).append(lv)
	for t in traps:
		var lvs: Array = t.get("levers", [])
		var w := _at(t.floor, t.cells[0])
		if lvs.is_empty():
			_msg("erreur", "zone de piège en %s sans levier (Pièges > Levier de piège, contre un mur à moins de %d m)" % [w[0], int(LEVER_RANGE)],
				"trap area at %s has no lever (Traps > Trap lever, against a wall within %d m)" % [w[1], int(LEVER_RANGE)], t.floor, t.cells)
		elif lvs.size() > 2:
			_msg("erreur", "zone de piège en %s : %d leviers (2 au plus, un à chaque bout)" % [w[0], lvs.size()],
				"trap area at %s: %d levers (2 at most, one at each end)" % [w[1], lvs.size()], t.floor, t.cells)


## Départ : aucune fenêtre collée au départ (avertissement). Les apparitions
## derrière une fenêtre n'ont plus de distance minimale aux joueurs (Spawner :
## comme dans BO1, les zombies viennent aussi à la fenêtre où l'on se tient,
## jusqu'à trois qui attendent devant) : un départ près des fenêtres de la
## zone de départ n'est donc plus une erreur. MIN_SPAWN_DIST ne vaut que pour
## les zombies qui sortent du sol (le validateur ne les exige pas : la zone de
## départ a toujours une fenêtre, sinon « zone sans fenêtre »).
func _start_safety() -> void:
	var active: Array = ["a"] + open_links.get("a", [])
	var best := 0.0
	var nearest := INF
	for w in windows:
		var wp := _world_window(w)
		for p in start_points:
			nearest = minf(nearest, _world(p[0], p[1]).distance_to(wp.p))
		if not active.has(w.zone):
			continue
		var closest := INF
		for p in start_points:
			closest = minf(closest, _world(p[0], p[1]).distance_to(wp.spawn))
		best = maxf(best, closest)
	if nearest < 5.0:
		_msg("attention", "départ à %s m d'une fenêtre : les premiers zombies arrivent aussitôt (BO1 : 6 m ou plus)" % _num(nearest).replace(".", ","),
			"start %s m from a window: the first zombies arrive at once (BO1: 6 m or more)" % _num(nearest))
	_msg("info", "Départ : fenêtre la plus proche à %s m, apparition de fenêtre de la zone de départ la plus lointaine à %s m" % [_num(nearest).replace(".", ","), _num(best).replace(".", ",")],
		"Start: nearest window %s m away, farthest window spawn of the starting zone %s m away" % [_num(nearest), _num(best)])


# --------------------------------------------------------------------- amusement

func _fun() -> void:
	# Zones : surface, fenêtres, objets.
	var area := {}
	for f in floors:
		for i in f.zone.size():
			if f.zone[i] != "" and f.kind[i] in [K.SOL, K.MARQUEUR, K.ESCALIER]:
				area[f.zone[i]] = area.get(f.zone[i], 0) + 1
	var pf := []
	var pe := []
	var total := 0
	for z in zones:
		var nw := windows.filter(func(w): return w.zone == z).size()
		pf.append("%s (%d m², %d fenêtre%s)" % [_zf(z), roundi(m2(area.get(z, 0))), nw, "s" if nw > 1 else ""])
		pe.append("%s (%d m², %d window%s)" % [_ze(z), roundi(m2(area.get(z, 0))), nw, "s" if nw > 1 else ""])
		total += area.get(z, 0)
	_msg("info", "Zones : " + " ; ".join(pf), "Zones: " + "; ".join(pe))
	_msg("info", "Surface praticable %d m², %d étage(s), %d porte(s)/débris, %d fenêtres" % [roundi(m2(total)), floors.size(), doors.size(), windows.size()],
		"Walkable area %d m², %d floor(s), %d door(s)/debris, %d windows" % [roundi(m2(total)), floors.size(), doors.size(), windows.size()])
	_fun_loops()
	_fun_doors()
	_fun_items()
	_fun_spawns()


## Boucles (training), impasses et passages obligés.
func _fun_loops() -> void:
	# Cycles du graphe des zones (portes ouvertes) : un arbre couvrant, chaque
	# arête en plus ferme une boucle.
	var parent := {zones[0]: ""}
	var via := {}
	var order := [zones[0]]
	var tree := {}
	var i := 0
	while i < order.size():
		var z: String = order[i]
		i += 1
		for ei in zone_edges.size():
			var e: Dictionary = zone_edges[ei]
			var o := String(e.b) if e.a == z else (String(e.a) if e.b == z else "")
			if o == "" or parent.has(o):
				continue
			parent[o] = z
			via[o] = ei
			tree[ei] = true
			order.append(o)
	var cf := []
	var ce := []
	for ei in zone_edges.size():
		if tree.has(ei):
			continue
		var e: Dictionary = zone_edges[ei]
		var pa := _path_up(parent, e.a)
		var pb := _path_up(parent, e.b)
		while pa.size() > 1 and pb.size() > 1 and pa[-1] == pb[-1] and pa[-2] == pb[-2]:
			pa.pop_back()
			pb.pop_back()
		var ring: Array = pa.duplicate()
		var back := pb.duplicate()
		back.reverse()
		ring.append_array(back.slice(1))
		ring.append(ring[0])
		var cost := int(e.cost)
		for z in pa.slice(0, pa.size() - 1) + pb.slice(0, pb.size() - 1):
			cost += int(zone_edges[via[z]].cost)
		cf.append("%s (%d points de portes)" % [" → ".join(ring.map(func(z): return _zf(z))), cost])
		ce.append("%s (%d door points)" % [" → ".join(ring.map(func(z): return _ze(z))), cost])
	if cf.is_empty():
		_msg("attention", "aucune boucle entre les zones : impossible de tourner d'une salle à l'autre (BO1 Kino : deux grandes boucles hall → loges → scène)",
			"no loop between zones: you cannot run from room to room in a circle (BO1 Kino: two big loops lobby → dressing rooms → stage)")
	else:
		_msg("info", "Boucles entre zones (portes ouvertes) : %d — %s" % [cf.size(), " ; ".join(cf)], "Loops between zones (doors open): %d — %s" % [ce.size(), "; ".join(ce)])
	# Blocs isolés (pilier, îlot de murs, vide entouré de plancher) : on tourne autour.
	var islands := 0
	for f in floors:
		var seen := {}
		for y in f.h:
			for x in f.w:
				var c := Vector2i(x, y)
				if seen.has(c) or _walk(f, c):
					continue
				var comp := _flood(f, c, func(n): return not _walk(f, n))
				var border := false
				for cc in comp:
					seen[cc] = true
					if cc.x == 0 or cc.y == 0 or cc.x == f.w - 1 or cc.y == f.h - 1:
						border = true
				if border:
					continue
				var ring := {}
				for cc in comp:
					for dy in [-1, 0, 1]:
						for dx in [-1, 0, 1]:
							var n: Vector2i = cc + Vector2i(dx, dy)
							if _walk(f, n):
								ring[n] = true
				var loop := ring.size() * scale
				if loop >= 10.0:
					islands += 1
					var doors_on := ring.keys().any(func(n): return f.at(n) in [K.PORTE, K.DEBRIS])
					var w := _at(f.index, comp[0])
					_msg("info", "Boucle de training autour du bloc en %s : tour au plus près ≈ %.0f m%s%s" % [w[0], loop,
						" en passant les portes" if doors_on else "", "" if loop >= 20.0 else " (petit : BO1 ≈ 25-40 m)"],
						"Training loop around the block at %s: tightest lap ≈ %.0f m%s%s" % [w[1], loop,
						" through the doors" if doors_on else "", "" if loop >= 20.0 else " (small: BO1 ≈ 25-40 m)"], f.index, [comp[0]])
	if cf.is_empty() and islands == 0:
		_msg("attention", "aucun endroit pour tourner en rond (« training ») : ajoutez un pilier ou une boucle de salles",
			"nowhere to run in circles (\"training\"): add a pillar or a loop of rooms")
	# Impasses et passages obligés.
	for z in zones:
		var exits := zone_edges.filter(func(e): return e.a == z or e.b == z)
		if exits.size() == 1:
			var o: String = exits[0].b if exits[0].a == z else exits[0].a
			if z == "a":
				_msg("attention", "Impasse : la zone de départ « %s » n'a qu'une sortie (vers « %s ») — le départ doit avoir 2 sorties (BO1)" % [_zf(z), _zf(o)],
					"Dead end: the starting zone \"%s\" has a single exit (to \"%s\") — the start should have 2 exits (BO1)" % [_ze(z), _ze(o)])
			else:
				_msg("info", "Impasse : la zone « %s » n'a qu'une sortie (vers « %s ») : bon coin pour camper, piège pour le training" % [_zf(z), _zf(o)],
					"Dead end: zone \"%s\" has a single exit (to \"%s\"): good for camping, a trap for training" % [_ze(z), _ze(o)])
	for ei in zone_edges.size():
		var e: Dictionary = zone_edges[ei]
		var reached := {String(e.a): true}
		var q := [String(e.a)]
		while not q.is_empty():
			var z: String = q.pop_back()
			for ej in zone_edges.size():
				if ej == ei:
					continue
				var f2: Dictionary = zone_edges[ej]
				for pair in [[f2.a, f2.b], [f2.b, f2.a]]:
					if pair[0] == z and not reached.has(pair[1]):
						reached[pair[1]] = true
						q.append(pair[1])
		if not reached.has(e.b):
			var kf: String = {"porte": "porte", "debris": "débris", "ouvert": "passage", "escalier": "escalier"}[e.kind]
			var ke: String = {"porte": "door", "debris": "debris", "ouvert": "passage", "escalier": "stairs"}[e.kind]
			_msg("info", "Passage obligé (goulot) entre « %s » et « %s » (%s)" % [_zf(e.a), _zf(e.b), kf], "Mandatory passage (choke point) between \"%s\" and \"%s\" (%s)" % [_ze(e.a), _ze(e.b), ke])


func _path_up(parent: Dictionary, z: String) -> Array:
	var out := [z]
	while parent.get(out[-1], "") != "":
		out.append(parent[out[-1]])
	return out


## Coût pour atteindre chaque zone depuis le départ (portes les moins chères).
func zone_costs() -> Dictionary:
	var cost := {"a": 0}
	var changed := true
	while changed:
		changed = false
		for e in zone_edges:
			for pair in [[e.a, e.b], [e.b, e.a]]:
				if cost.has(pair[0]):
					var c: int = cost[pair[0]] + int(e.cost)
					if not cost.has(pair[1]) or c < cost[pair[1]]:
						cost[pair[1]] = c
						changed = true
	return cost


## Courbe d'ouverture : la porte la moins chère d'abord, comme un joueur.
func _fun_doors() -> void:
	var opened := {}
	for z in ["a"] + open_links.get("a", []):
		opened[z] = true
	var bought := {}
	var sf := []
	var se := []
	var total := 0
	var power_doors := doors.filter(func(d): return d.power)
	while true:
		var best: Variant = null
		for d in doors:
			if bought.has(d.id) or d.power:
				continue
			var ia: bool = opened.has(d.zones[0])
			var ib: bool = opened.has(d.zones[1])
			if ia == ib:
				continue
			if best == null or d.cost < best.cost:
				best = d
		if best == null:
			break
		bought[best.id] = true
		total += best.cost
		var nz := String(best.zones[1]) if opened.has(best.zones[0]) else String(best.zones[0])
		var group := _open_group(nz)
		for z in group:
			opened[z] = true
		sf.append("%d (%s, ouvre %s)" % [best.cost, "débris" if best.debris else "porte %s" % best.id, ", ".join(group.map(func(z): return _zf(z)))])
		se.append("%d (%s, opens %s)" % [best.cost, "debris" if best.debris else "door %s" % best.id, ", ".join(group.map(func(z): return _ze(z)))])
	for d in doors:
		if not bought.has(d.id) and not d.power:
			bought[d.id] = true
			total += d.cost
			sf.append("%d (%s %s-%s, ferme une boucle)" % [d.cost, "débris" if d.debris else "porte", _zf(d.zones[0]), _zf(d.zones[1])])
			se.append("%d (%s %s-%s, closes a loop)" % [d.cost, "debris" if d.debris else "door", _ze(d.zones[0]), _ze(d.zones[1])])
	if sf.is_empty():
		_msg("attention", "aucune porte payante : toute la carte est ouverte dès le départ (BO1 : 5 à 10 portes)",
			"no buyable door: the whole map is open from the start (BO1: 5 to 10 doors)")
		return
	_msg("info", "Courbe d'ouverture (moins cher d'abord) : %s ; total pour tout ouvrir %d points" % [" → ".join(sf), total],
		"Opening curve (cheapest first): %s; %d points to open everything" % [" → ".join(se), total])
	if not power_doors.is_empty():
		_msg("info", "%d porte(s) ouverte(s) par le courant" % power_doors.size(), "%d door(s) opened by the power" % power_doors.size())
	var first := doors.filter(func(d): return not d.power and (d.zones[0] == "a" or d.zones[1] == "a" or open_links.get("a", []).has(d.zones[0]) or open_links.get("a", []).has(d.zones[1])))
	first.sort_custom(func(x, y): return x.cost < y.cost)
	if not first.is_empty() and (first[0].cost < 500 or first[0].cost > 1000):
		_msg("attention", "première porte à %d points : BO1 la met à 750-1000 (achetée vers la fin de la manche 1 ou en manche 2)" % first[0].cost,
			"first door at %d points: BO1 puts it at 750-1000 (bought near the end of round 1 or in round 2)" % first[0].cost)
	if opened.size() < zones.size():
		var closed := zones.filter(func(z): return not opened.has(z))
		_msg("info", "zones ouvertes seulement par le courant ou le téléporteur : %s" % ", ".join(closed.map(func(z): return _zf(z))),
			"zones opened only by the power or the teleporter: %s" % ", ".join(closed.map(func(z): return _ze(z))))


func _fun_items() -> void:
	var costs := zone_costs()
	var box_zones := {}
	var bf := []
	var be := []
	for it in wall_items:
		if it.base == "boite" or it.base == "boite_depart":
			box_zones[it.zone] = true
			bf.append("%s%s" % [_zf(it.zone), " (départ)" if it.base == "boite_depart" else ""])
			be.append("%s%s" % [_ze(it.zone), " (start)" if it.base == "boite_depart" else ""])
	if not bf.is_empty():
		_msg("info", "Boîte mystère : %d emplacements, zones %s" % [bf.size(), ", ".join(bf)], "Mystery box: %d locations, zones %s" % [be.size(), ", ".join(be)])
		if box_zones.size() == 1 and bf.size() > 1:
			_msg("attention", "tous les emplacements de boîte sont dans la zone « %s » : répartissez-les (BO1 : un par grande salle)" % _zf(box_zones.keys()[0]),
				"every box location is in zone \"%s\": spread them out (BO1: one per large room)" % _ze(box_zones.keys()[0]))
	var pf := []
	var pe := []
	var has := {}
	for it in wall_items:
		if not it.entry.has("atout"):
			continue
		has[it.entry.atout] = it
		pf.append("%s en « %s » (%d points de portes)" % [PerkDB.display_name(it.entry.atout), _zf(it.zone), costs.get(it.zone, 0)])
		pe.append("%s in \"%s\" (%d door points)" % [PerkDB.display_name(it.entry.atout), _ze(it.zone), costs.get(it.zone, 0)])
	if not pf.is_empty():
		_msg("info", "Atouts : " + " ; ".join(pf), "Perks: " + "; ".join(pe))
	if has.has("titan"):
		var t: Dictionary = has.titan
		var exits := zone_edges.filter(func(e): return e.a == t.zone or e.b == t.zone).size()
		var lvl := "attention" if t.zone == "a" else "info"
		_msg(lvl, "Coin TITAN BREW (rôle du Juggernog) : zone « %s », %d points de portes depuis le départ, %s%s" % [_zf(t.zone), costs.get(t.zone, 0),
				"impasse (bon coin pour camper)" if exits <= 1 else "zone de passage (%d sorties)" % exits, " — BO1 : jamais dans la salle de départ, il se mérite (1 à 3 portes)" if t.zone == "a" else ""],
			"TITAN BREW corner (Juggernog's role): zone \"%s\", %d door points from the start, %s%s" % [_ze(t.zone), costs.get(t.zone, 0),
				"dead end (good for camping)" if exits <= 1 else "through zone (%d exits)" % exits, " — BO1: never in the starting room, you earn it (1 to 3 doors)" if t.zone == "a" else ""])
	else:
		_msg("attention", "pas de TITAN BREW (rôle du Juggernog) : les cartes de BO1 en ont toujours un", "no TITAN BREW (Juggernog's role): BO1 maps always have one")
	if has.has("lazarus") and has.lazarus.zone != "a":
		_msg("info", "LAZARUS TONIC (rôle du Quick Revive) hors de la zone de départ (BO1 : dans la salle de départ)",
			"LAZARUS TONIC (Quick Revive's role) outside the starting zone (BO1: in the starting room)")
	var weapons := wall_items.filter(func(it): return it.entry.has("arme"))
	if not weapons.is_empty():
		_msg("info", "Armes au mur : " + ", ".join(weapons.map(func(it): return "%s (%s)" % [String(it.entry.arme), _zf(it.zone)])),
			"Wall weapons: " + ", ".join(weapons.map(func(it): return "%s (%s)" % [String(it.entry.arme), _ze(it.zone)])))
	if not weapons.any(func(it): return it.zone == "a"):
		_msg("attention", "aucune arme au mur dans la zone de départ (BO1 : M14 ou Olympia à 500 points dès le départ)",
			"no wall weapon in the starting zone (BO1: M14 or Olympia for 500 points from the start)")


func _fun_spawns() -> void:
	var worst := {}
	for f in floors:
		var arr: PackedFloat32Array = window_dist[f.index]
		for i in arr.size():
			var z := f.zone[i]
			if z != "" and arr[i] >= 0.0 and f.kind[i] in [K.SOL, K.MARQUEUR]:
				worst[z] = maxf(worst.get(z, 0.0), arr[i])
	var pf := []
	var pe := []
	for z in zones:
		pf.append("%s %.0f m" % [_zf(z), worst.get(z, 0.0)])
		pe.append("%s %.0f m" % [_ze(z), worst.get(z, 0.0)])
		if worst.get(z, 0.0) > 30.0:
			_msg("attention", "zone « %s » : un point à %.0f m à pied de toute fenêtre (les zombies mettent longtemps à venir ; BO1 : 25 m au plus)" % [_zf(z), worst[z]],
				"zone \"%s\": a spot %.0f m on foot from any window (zombies take a long time to arrive; BO1: 25 m at most)" % [_ze(z), worst[z]])
	_msg("info", "Distance à pied au plus loin d'une fenêtre, par zone : " + ", ".join(pf), "Farthest walking distance from a window, per zone: " + ", ".join(pe))


# --------------------------------------------------------------------- repères

## Position monde (m, sol de l'étage) d'un point de la grille (en cases, bords).
func _world(k: int, p: Vector2) -> Vector3:
	return Vector3(ORIGIN + p.x * scale, floors[k].sol, ORIGIN + p.y * scale)


## Fenêtre : milieu (au sol, au milieu du mur), vers l'intérieur, apparition.
func _world_window(w: Dictionary) -> Dictionary:
	var r: Rect2i = w.rect
	var c := Vector2(r.position) + Vector2(r.size) * 0.5
	if w.has("oblique"):
		# Mur en biais : milieu exact de la fenêtre sur le trait (m -> cases).
		c = Vector2(w.p) / scale + Vector2(0.5, 0.5)
	var p := _world(w.floor, c)
	var inn := Vector3(w.inward.x, 0, w.inward.y)
	return {"p": p, "in": inn, "spawn": p - inn * SPAWN_OUT}


# --------------------------------------------------------------------- rapport

func report_text() -> String:
	var lines := PackedStringArray()
	lines.append(Lang.t("Carte « %s » (%s) : %d erreur(s), %d avertissement(s)", "Map \"%s\" (%s): %d error(s), %d warning(s)") % [display_name if display_name != "" else id, id, errors().size(), warnings().size()])
	for level in ["erreur", "attention", "info"]:
		var list := messages.filter(func(m): return m.level == level)
		if list.is_empty():
			continue
		lines.append("")
		lines.append({"erreur": Lang.t("ERREURS (la carte est refusée) :", "ERRORS (the map is rejected):"),
			"attention": Lang.t("AVERTISSEMENTS :", "WARNINGS:"), "info": Lang.t("INDICATEURS (BO1) :", "INDICATORS (BO1):")}[level])
		for m in list:
			lines.append("  - " + text_of(m))
	return "\n".join(lines) + "\n"
