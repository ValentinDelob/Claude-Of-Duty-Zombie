class_name MapDrawing
extends RefCounted
## Carte DESSINÉE (docs/MAP_AUTHORING.md) : une image PNG par étage, où chaque
## case (pixel) est une couleur de la légende (tools/maps/legende.json), plus un
## petit fichier texte de propriétés (carte.txt : nom, étages, noms des zones,
## prix des portes...). Ce script lit le dessin, le VALIDE (erreurs pointées par
## leur position dans le dessin, indicateurs d'amusement inspirés de BO1) ;
## MapDrawingExport en tire la description de carte en maillage
## (assets/maps/<id>/layout.json, format de MeshMapLayout) que
## tools/blender/mesh_map.py construit ensuite en 3D.
##
## Utilisation : MapDrawing.load_file("…/carte.txt") ou, dans les tests,
## MapDrawing.from_images([image_etage0, …], texte_des_propriétés).

const LEGEND_PATH := "res://tools/maps/legende.json"
## Décalage du dessin dans le monde (m) : x, z >= 0 (NetCodec) et place pour
## les cours derrière les fenêtres du bord de l'image.
const ORIGIN := 4.0
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
## Emprise des objets muraux : [largeur le long du mur, profondeur] en cases.
const FOOTPRINT := {
	"boite": [4, 2], "boite_depart": [4, 2], "pap": [3, 2], "poste_central": [2, 2],
	"courant": [1, 1], "levier": [1, 1], "grenades": [1, 1],
}
const PERK_FOOTPRINT := [3, 2]
const WEAPON_FOOTPRINT := [2, 1]
## Départ : les joueurs autour du carré vert (m).
const START_SPREAD := 0.6
# Valeurs du jeu recopiées ici : l'outil tourne sans les autoloads (godot -s),
# donc sans les classes du jeu ; tests/test_map_drawing.gd vérifie qu'elles
# restent égales aux originales.
## Barricade.SILL_TOP / LINTEL_BOTTOM : allège et linteau des fenêtres.
const SILL := 0.95
const LINTEL := 2.35
## Spawner.MIN_PLAYER_DIST : pas d'apparition plus près d'un joueur.
const MIN_SPAWN_DIST := 7.0
## Matériaux utilisables (clés de WorldLook.SURFACES).
const MATERIALS := ["floor", "wall", "ceiling", "concrete", "concrete_dark", "tiles", "wood", "metal", "stone",
	"wall_green", "wall_cell", "wall_lab", "wall_rust", "wall_concrete", "brick", "cobble", "marble", "parquet",
	"carpet_red", "stage_wood", "dark_wood", "wall_lobby", "wall_foyer", "wall_loges", "plaster_theater", "steel"]

enum K { VIDE, MUR, TREMIE, ESCALIER, PORTE, DEBRIS, FENETRE, SOL, MARQUEUR }
const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]


class Floor:
	var index := 0
	var file := ""
	var sol := 0.0
	## Plafond déclaré (dernier étage), -1 sinon.
	var plafond := -1.0
	var w := 0
	var h := 0
	var kind := PackedByteArray()
	var key := PackedStringArray()
	## Zone de chaque case praticable ("" sinon).
	var zone := PackedStringArray()

	func inside(c: Vector2i) -> bool:
		return c.x >= 0 and c.y >= 0 and c.x < w and c.y < h

	func at(c: Vector2i) -> int:
		return kind[c.y * w + c.x] if inside(c) else K.VIDE

	func key_at(c: Vector2i) -> String:
		return key[c.y * w + c.x] if inside(c) else "vide"

	func zone_of(c: Vector2i) -> String:
		return zone[c.y * w + c.x] if inside(c) else ""


var id := ""
var display_name := ""
var description := ""
var music := "ambience_bunker"
var door_height := DOOR_HEIGHT
var scale := 0.5
var zone_names: Dictionary = {}
## "a-b" -> {cost, power, link}
var door_prices: Dictionary = {}
var floor_mats: Dictionary = {}
var wall_mats: Dictionary = {}
var floors: Array[Floor] = []
## Dossier du dessin (images, rapports).
var base_dir := ""

## Messages : {level ("erreur" | "attention" | "info"), text, floor, cells}
var messages: Array = []

## Objets trouvés dans le dessin.
var blobs: Array = []     # {key, kind, floor, cells, rect}
var doors: Array = []     # {id, floor, rect, axis, zones, debris, cost, power, link}
var windows: Array = []   # {floor, rect, inward, zone, pocket (Rect2i)}
var stairs: Array = []    # {floor, rect, up, lower, upper, run, width}
var wall_items: Array = []   # {key, entry, floor, cells, zone, wall, face (Vector2 cases), center}
var floor_items: Array = []  # {key, floor, cells, zone, center, rect}
var start_points: Array = []   # [floor, Vector2 (cases)]
## Graphe des zones : {a, b, kind ("porte", "debris", "ouvert", "escalier"), cost, power, door}
var zone_edges: Array = []
var zones: Array = []   # lettres présentes, triées
## Cellules praticables par étage atteintes depuis le départ (portes ouvertes).
var reach: Array = []
## Distance à pied (m) de chaque case praticable à la fenêtre la plus proche.
var window_dist: Array = []
## Liens ouverts entre zones (transitifs) : zone -> [zones]
var open_links: Dictionary = {}
var _stair_at: Array = []   # par étage : {Vector2i: index d'escalier}
var _up_links: Dictionary = {}   # "k:x:y" -> [[k_bas, Vector2i]]
var _obstacles: Array = []   # par étage : {Vector2i: true} emprise des objets pleins
var _analyzed := false


# --------------------------------------------------------------------- légende

static var _legend: Dictionary = {}
static var _by_key: Dictionary = {}
static var _by_rgb: Dictionary = {}


static func legend() -> Dictionary:
	if _legend.is_empty():
		_legend = JSON.parse_string(FileAccess.get_file_as_string(LEGEND_PATH))
		for e in _legend.couleurs:
			_by_key[String(e.cle)] = e
	return _legend


static func entry(key: String) -> Dictionary:
	legend()
	return _by_key.get(key, {})


static func color_of(key: String) -> Color:
	var e := entry(key)
	return Color8(int(e.rgb[0]), int(e.rgb[1]), int(e.rgb[2])) if not e.is_empty() else Color.MAGENTA


## Clé de légende la plus proche d'une couleur 8 bits, et sa distance.
static func nearest(r: int, g: int, b: int) -> Array:
	legend()
	var packed := (r << 16) | (g << 8) | b
	if _by_rgb.has(packed):
		return _by_rgb[packed]
	var best := ["", INF]
	for e in _legend.couleurs:
		var d := Vector3(r - int(e.rgb[0]), g - int(e.rgb[1]), b - int(e.rgb[2])).length()
		if d < best[1]:
			best = [String(e.cle), d]
	_by_rgb[packed] = best
	return best


static func kind_of_type(t: String) -> int:
	match t:
		"vide": return K.VIDE
		"mur": return K.MUR
		"tremie": return K.TREMIE
		"escalier": return K.ESCALIER
		"porte": return K.PORTE
		"debris": return K.DEBRIS
		"fenetre": return K.FENETRE
		"zone": return K.SOL
	return K.MARQUEUR


# --------------------------------------------------------------------- chargement

## Lit carte.txt et les images d'étage qu'il cite (chemins relatifs à carte.txt).
static func load_file(path: String) -> MapDrawing:
	var md := MapDrawing.new()
	var abs_path := path
	if path.begins_with("res://"):
		abs_path = ProjectSettings.globalize_path(path)
	elif not path.is_absolute_path():
		abs_path = ProjectSettings.globalize_path("res://" + path)
	md.base_dir = abs_path.get_base_dir()
	if not FileAccess.file_exists(abs_path):
		md._msg("erreur", "fichier de propriétés introuvable : %s" % abs_path)
		return md
	md.parse_properties(FileAccess.get_file_as_string(abs_path))
	var images: Array[Image] = []
	for f in md.floors:
		var img := Image.new()
		var p := md.base_dir.path_join(f.file)
		if not FileAccess.file_exists(p) or img.load(p) != OK:
			md._msg("erreur", "étage %d : image illisible ou absente (%s)" % [f.index, p])
			img = null
		images.append(img)
	if md.errors().is_empty():
		md._set_images(images)
		md.analyze()
	return md


## Dessin fourni directement (tests) : une image par étage + texte de carte.txt.
static func from_images(images: Array[Image], properties: String) -> MapDrawing:
	var md := MapDrawing.new()
	md.parse_properties(properties)
	if md.floors.is_empty():
		# Sans ligne « étage » : un seul étage, sol 0, plafond 3,2 m.
		var f := Floor.new()
		f.plafond = 3.2
		md.floors.append(f)
	while md.floors.size() < images.size():
		var f := Floor.new()
		f.index = md.floors.size()
		f.sol = md.floors[-1].sol + 3.5
		f.plafond = f.sol + 3.2
		md.floors.append(f)
	if md.errors().is_empty():
		md._set_images(images)
		md.analyze()
	return md


func _set_images(images: Array[Image]) -> void:
	for i in mini(images.size(), floors.size()):
		var img := images[i]
		if img == null:
			continue
		if img.is_compressed():
			img.decompress()
		var f := floors[i]
		f.w = img.get_width()
		f.h = img.get_height()
		f.kind.resize(f.w * f.h)
		f.key.resize(f.w * f.h)
		f.zone.resize(f.w * f.h)
		f.set_meta("image", img)


# --------------------------------------------------------------------- propriétés

static func _norm(s: String) -> String:
	s = s.strip_edges().to_lower()
	for pair in [["é", "e"], ["è", "e"], ["ê", "e"], ["ë", "e"], ["à", "a"], ["â", "a"], ["î", "i"], ["ï", "i"], ["ô", "o"], ["û", "u"], ["ù", "u"], ["ç", "c"]]:
		s = s.replace(pair[0], pair[1])
	while s.contains("  "):
		s = s.replace("  ", " ")
	return s


static func _num(s: String) -> float:
	return s.strip_edges().replace(",", ".").to_float()


## Fichier « clé = valeur », une propriété par ligne, # pour les commentaires.
func parse_properties(text: String) -> void:
	var re_floor := RegEx.create_from_string("^(\\S+\\.png)\\s*[,;]?\\s*sol\\s*(-?[0-9]+(?:[.,][0-9]+)?)\\s*(?:[,;]\\s*plafond\\s*([0-9]+(?:[.,][0-9]+)?))?\\s*$")
	var re_pair := RegEx.create_from_string("^porte ([a-h])\\s*-\\s*([a-h])$")
	var lines := text.split("\n")
	for n in lines.size():
		var line := lines[n]
		var hash_at := line.find("#")
		if hash_at >= 0:
			line = line.substr(0, hash_at)
		line = line.strip_edges()
		if line == "":
			continue
		var eq := line.find("=")
		if eq < 0:
			_msg("erreur", "carte.txt ligne %d : « clé = valeur » attendu (%s)" % [n + 1, line])
			continue
		var raw_key := line.substr(0, eq).strip_edges()
		var k := _norm(raw_key)
		var v := line.substr(eq + 1).strip_edges()
		var nv := _norm(v)
		var where := "carte.txt ligne %d" % (n + 1)
		if k == "id":
			if not RegEx.create_from_string("^[a-z0-9_]+$").search(v):
				_msg("erreur", "%s : l'id doit être en minuscules, chiffres et _ (%s)" % [where, v])
			id = v
		elif k == "nom":
			display_name = v
		elif k == "description":
			description = v
		elif k == "musique":
			music = v
		elif k == "hauteur des portes":
			door_height = _num(v)
		elif k.begins_with("etage "):
			var m := re_floor.search(v)
			if m == null:
				_msg("erreur", "%s : « étage N = image.png, sol 0, plafond 3.2 » attendu (%s)" % [where, v])
				continue
			var f := Floor.new()
			f.index = k.substr(6).to_int()
			f.file = m.get_string(1)
			f.sol = _num(m.get_string(2))
			f.plafond = _num(m.get_string(3)) if m.get_string(3) != "" else -1.0
			if f.index != floors.size():
				_msg("erreur", "%s : les étages se déclarent dans l'ordre 0, 1, 2… (étage %d attendu)" % [where, floors.size()])
				continue
			floors.append(f)
		elif k.begins_with("zone ") and k.length() == 6:
			zone_names[k.substr(5)] = v
		elif re_pair.search(k):
			var m := re_pair.search(k)
			var pair := _pair(m.get_string(1), m.get_string(2))
			var d := {"cost": 0, "power": false, "link": false}
			var ok := false
			for tok in nv.replace(",", " ").split(" ", false):
				if tok.is_valid_int():
					d.cost = tok.to_int()
					ok = true
				elif tok == "courant":
					d.power = true
					ok = true
				elif tok.begins_with("liee"):
					d.link = true
				else:
					ok = false
					break
			if not ok:
				_msg("erreur", "%s : « porte A-B = 750 » (ou « courant », « 1000 liées ») attendu (%s)" % [where, v])
				continue
			door_prices[pair] = d
		elif (k.begins_with("sol ") or k.begins_with("murs ") or k.begins_with("mur ")) and k.length() <= 6:
			var z := k.substr(k.length() - 1)
			if not MATERIALS.has(nv):
				_msg("erreur", "%s : matériau inconnu « %s » (au choix : %s)" % [where, v, ", ".join(MATERIALS)])
				continue
			if k.begins_with("sol "):
				floor_mats[z] = nv
			else:
				wall_mats[z] = nv
		else:
			_msg("erreur", "%s : propriété inconnue « %s » (voir docs/MAP_AUTHORING.md)" % [where, raw_key])
	for i in floors.size():
		if i < floors.size() - 1 and floors[i + 1].sol - floors[i].sol < 2.8 + DALLE:
			_msg("erreur", "étage %d : il faut au moins %.1f m entre deux sols (hauteur sous plafond 2,8 m + dalle)" % [i + 1, 2.8 + DALLE])
	if not floors.is_empty():
		var top := floors[-1]
		if top.plafond < 0:
			_msg("erreur", "étage %d (dernier) : donnez son plafond (« …, plafond 3.2 »)" % top.index)
		elif top.plafond - top.sol < 2.8:
			_msg("erreur", "étage %d : plafond trop bas (%.1f m ; 2,8 m au moins)" % [top.index, top.plafond - top.sol])


static func _pair(a: String, b: String) -> String:
	return "%s-%s" % [a, b] if a < b else "%s-%s" % [b, a]


# --------------------------------------------------------------------- messages

func _msg(level: String, text: String, k := -1, cells: Array = []) -> void:
	messages.append({"level": level, "text": text, "floor": k, "cells": cells})


func errors() -> Array:
	return messages.filter(func(m): return m.level == "erreur")


func warnings() -> Array:
	return messages.filter(func(m): return m.level == "attention")


func infos() -> Array:
	return messages.filter(func(m): return m.level == "info")


func ok() -> bool:
	return _analyzed and errors().is_empty()


func _at(k: int, c: Vector2i) -> String:
	var s := "(x %d, y %d" % [c.x, c.y]
	if floors.size() > 1:
		s += ", étage %d" % k
	return s + ")"


static func _zu(z: String) -> String:
	return z.to_upper()


func m2(n: int) -> float:
	return n * scale * scale


# --------------------------------------------------------------------- analyse

func analyze() -> void:
	scale = float(legend().echelle)
	_classify()
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
		_msg("info", "Les vérifications d'accès et les indicateurs d'amusement viendront une fois ces erreurs corrigées.")
		return
	_zone_graph()
	_connectivity()
	_counts()
	if not errors().is_empty():
		return
	_start_safety()
	_fun()
	_analyzed = true


func _classify() -> void:
	var tol := float(legend().tolerance)
	for f in floors:
		var img: Image = f.get_meta("image", null)
		if img == null:
			continue
		if f.w != floors[0].w or f.h != floors[0].h:
			_msg("erreur", "étage %d : l'image fait %d × %d, celle de l'étage 0 %d × %d (même taille pour tous les étages)" % [f.index, f.w, f.h, floors[0].w, floors[0].h])
			continue
		var unknown := {}   # couleur -> [cases]
		for y in f.h:
			for x in f.w:
				var col := img.get_pixel(x, y)
				var i := y * f.w + x
				var key := "vide"
				if col.a >= 0.5:
					var nr: Array = nearest(roundi(col.r * 255), roundi(col.g * 255), roundi(col.b * 255))
					if nr[1] <= tol:
						key = nr[0]
					else:
						var ck := "%d,%d,%d" % [roundi(col.r * 255), roundi(col.g * 255), roundi(col.b * 255)]
						if not unknown.has(ck):
							unknown[ck] = [nr[0]]
						unknown[ck].append(Vector2i(x, y))
						key = "mur"
				var e := entry(key)
				f.key[i] = key
				f.kind[i] = kind_of_type(String(e.type))
				f.zone[i] = String(e.get("valeur", "")) if e.type == "zone" else ""
		for ck in unknown:
			var cells: Array = unknown[ck].slice(1)
			_msg("erreur", "couleur %s inconnue sur %d case(s), dont %s — la plus proche de la légende : %s (%s). Dessinez au crayon, sans lissage ni transparence partielle." % [ck, cells.size(), _at(f.index, cells[0]), entry(unknown[ck][0]).nom, ", ".join(entry(unknown[ck][0]).rgb.map(func(v): return str(int(v))))], f.index, cells.slice(0, 50))


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
				blobs.append({"key": key, "kind": kd, "floor": f.index, "cells": cells, "rect": _bbox(cells)})


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
			_msg("erreur", "%s en %s : posé hors de tout sol de zone" % [entry(b.key).nom, _at(b.floor, b.cells[0])], b.floor, b.cells)
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


func _uniform_zone(f: Floor, cells: Array) -> String:
	var z := ""
	for c in cells:
		var zz := f.zone_of(c)
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
		var k: int = b.floor
		var r: Rect2i = b.rect
		var where := _at(k, b.cells[0])
		if b.cells.size() != r.get_area():
			_msg("erreur", "escalier en %s : il doit être un rectangle plein" % where, k, b.cells)
			continue
		if k >= floors.size() - 1:
			_msg("erreur", "escalier en %s : il n'y a pas d'étage au-dessus (dessinez-le sur l'étage du BAS)" % where, k, b.cells)
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
			_msg("erreur", "escalier en %s : il faut du sol au pied (étage %d) d'un seul petit côté et du plancher en haut (étage %d) du côté opposé" % [where, k, k + 1] if cands.is_empty() else "escalier en %s : sens de montée ambigu (sol en haut et en bas des deux côtés)" % where, k, b.cells)
			continue
		var d: Vector2i = cands[0]
		var run := absi(r.size.x) if d.x != 0 else r.size.y
		var width := r.size.y if d.x != 0 else r.size.x
		var rise := up.sol - f.sol
		var slope := rad_to_deg(atan2(rise, run * scale))
		if width < MIN_STAIR_WIDTH:
			_msg("erreur", "escalier en %s : trop étroit (%d cases ; %d au moins, soit %.1f m)" % [where, width, MIN_STAIR_WIDTH, MIN_STAIR_WIDTH * scale], k, b.cells)
		if slope > MAX_STAIR_SLOPE:
			_msg("erreur", "escalier en %s : trop raide (%.0f° ; %d° au plus : allongez-le à %d cases)" % [where, slope, int(MAX_STAIR_SLOPE), ceili(rise / tan(deg_to_rad(MAX_STAIR_SLOPE)) / scale)], k, b.cells)
		var covered := []
		for c in b.cells:
			if up.at(c) != K.TREMIE:
				covered.append(c)
		if not covered.is_empty():
			_msg("erreur", "escalier en %s : l'étage %d le recouvre en %s — peignez la trémie (gris foncé) au-dessus de tout l'escalier" % [where, k + 1, _at(k + 1, covered[0])], k + 1, covered)
		var lower := _uniform_zone(f, _side(r, -d))
		var upper := _uniform_zone(up, _side(r, d))
		var st := {"floor": k, "rect": r, "up": d, "lower": lower, "upper": upper, "run": run, "width": width, "cells": b.cells}
		var si := stairs.size()
		stairs.append(st)
		for c in b.cells:
			_stair_at[k][c] = si
			f.zone[c.y * f.w + c.x] = lower
		# Haut de l'escalier : passage vers les cases du palier de l'étage du dessus.
		for t in _side(r, d):
			var key := "%d:%d:%d" % [k + 1, t.x, t.y]
			if not _up_links.has(key):
				_up_links[key] = []
			_up_links[key].append([k, t - d])


func _openings() -> void:
	var pockets := {}   # étage -> {case: fenêtre}
	for b in blobs:
		if not b.kind in [K.PORTE, K.DEBRIS, K.FENETRE]:
			continue
		var k: int = b.floor
		var f := floors[k]
		var r: Rect2i = b.rect
		var where := _at(k, b.cells[0])
		var what := "porte" if b.kind == K.PORTE else ("débris" if b.kind == K.DEBRIS else "fenêtre")
		if b.cells.size() != r.get_area():
			_msg("erreur", "%s en %s : doit être un rectangle plein" % [what, where], k, b.cells)
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
				if _all(sa, func(c): return _floorlike(f, c)) and _all(sb, func(c): return f.at(c) == K.VIDE):
					inward = -axis
				elif _all(sb, func(c): return _floorlike(f, c)) and _all(sa, func(c): return f.at(c) == K.VIDE):
					inward = axis
				else:
					continue
				found = true
				var zone := _uniform_zone(f, _side(r, inward))
				if thick != 1 or width != 2:
					_msg("erreur", "fenêtre en %s : elle fait %d × %d cases ; une fenêtre = 2 cases le long du mur, dans un mur de 1 case" % [where, r.size.x, r.size.y], k, b.cells)
					break
				# Cour des zombies derrière la fenêtre : du vide sur 2,5 × 3 m.
				var out := -inward
				var pocket := []
				var blocked := []
				for dd in range(1, POCKET_DEPTH + 1):
					for ll in range(-2, 4):
						var c: Vector2i = r.position + out * dd + perp * ll
						pocket.append(c)
						if f.at(c) != K.VIDE or pockets.get(k, {}).has(c):
							blocked.append(c)
				if not blocked.is_empty():
					_msg("erreur", "fenêtre en %s : pas de place dehors pour les zombies (il faut 2,5 m × 3 m de vide derrière ; occupé en %s)" % [where, _at(k, blocked[0])], k, blocked)
					break
				if not pockets.has(k):
					pockets[k] = {}
				for c in pocket:
					pockets[k][c] = true
				windows.append({"floor": k, "rect": r, "inward": inward, "zone": zone, "cells": b.cells, "pocket": _bbox(pocket)})
			else:
				if not (_all(sa, func(c): return _floorlike(f, c)) and _all(sb, func(c): return _floorlike(f, c))):
					continue
				found = true
				var za := _uniform_zone(f, sa)
				var zb := _uniform_zone(f, sb)
				if za == "?" or zb == "?":
					_msg("erreur", "%s en %s : un de ses côtés touche deux zones différentes" % [what, where], k, b.cells)
				elif za == zb:
					_msg("erreur", "%s en %s : elle relie deux morceaux de la même zone %s (une porte sépare deux zones de couleurs différentes)" % [what, where, _zu(za)], k, b.cells)
				else:
					var pair := _pair(za, zb)
					var price: Dictionary = door_prices.get(pair, {})
					if price.is_empty():
						_msg("erreur", "%s en %s entre les zones %s et %s : pas de prix — ajoutez « porte %s = 750 » dans carte.txt" % [what, where, _zu(za), _zu(zb), pair.to_upper()], k, b.cells)
					if width < 2:
						_msg("erreur", "%s en %s : trop étroite (%d case ; 2 au moins, 3 conseillées)" % [what, where, width], k, b.cells)
					elif width < 3:
						_msg("attention", "%s en %s : étroite (%.1f m ; BO1 : 1,5 à 3 m)" % [what, where, width * scale], k, b.cells)
					if thick > 2:
						_msg("attention", "%s en %s : mur épais (%d cases)" % [what, where, thick], k, b.cells)
					doors.append({"floor": k, "rect": r, "axis": axis, "zones": [za, zb] if za < zb else [zb, za], "debris": b.kind == K.DEBRIS,
						"cost": int(price.get("cost", 0)), "power": bool(price.get("power", false)), "link": bool(price.get("link", false)), "cells": b.cells, "width": width})
			break
		if not found:
			if b.kind == K.FENETRE:
				_msg("erreur", "fenêtre en %s : elle doit être dans un mur extérieur, avec le sol d'une zone d'un côté et du vide (dehors) de l'autre" % where, k, b.cells)
			else:
				_msg("erreur", "%s en %s : elle doit être posée dans un mur (mur aux deux bouts), avec du sol de chaque côté" % [what, where], k, b.cells)
	# Identifiants stables : ordre de lecture (étage, ligne, colonne).
	doors.sort_custom(func(a, b): return [a.floor, a.rect.position.y, a.rect.position.x] < [b.floor, b.rect.position.y, b.rect.position.x])
	for i in doors.size():
		doors[i]["id"] = str(i + 1)
	# Portes liées : un achat ouvre toutes celles de la même paire de zones.
	var by_pair := {}
	for d in doors:
		if d.link:
			by_pair.get_or_add(_pair(d.zones[0], d.zones[1]), []).append(d)
	for pair in by_pair:
		var list: Array = by_pair[pair]
		for i in list.size():
			list[i]["link_id"] = list[(i + 1) % list.size()].id if list.size() > 1 else ""
	for pair in door_prices:
		if not doors.any(func(d): return _pair(d.zones[0], d.zones[1]) == pair):
			_msg("attention", "carte.txt : « porte %s » ne correspond à aucune porte du dessin" % pair.to_upper())


func _wall_markers() -> void:
	for f in floors:
		_obstacles.append({})
	for b in blobs:
		if b.kind != K.MARQUEUR or not b.has("zone"):
			continue
		var e := entry(b.key)
		if e.type != "mural":
			continue
		var k: int = b.floor
		var f := floors[k]
		var where := _at(k, b.cells[0])
		var counts := {}
		for d in DIRS:
			var n := 0
			for c in b.cells:
				if f.at(c + d) == K.MUR:
					n += 1
			counts[d] = n
		var best := Vector2i.ZERO
		var tie := false
		for d in DIRS:
			if counts[d] == 0:
				continue
			if best == Vector2i.ZERO or counts[d] > counts[best]:
				best = d
				tie = false
			elif counts[d] == counts[best]:
				tie = true
		if best == Vector2i.ZERO:
			_msg("erreur", "%s en %s : doit toucher un mur (collez le carré contre le mur)" % [e.nom, where], k, b.cells)
			continue
		if tie:
			_msg("erreur", "%s en %s : dans un angle, le mur visé est ambigu — décalez le carré d'une case le long du mur" % [e.nom, where], k, b.cells)
			continue
		# Centre du carré et face du mur (en cases).
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
		var fp: Array = FOOTPRINT.get(b.key, PERK_FOOTPRINT if e.has("atout") else WEAPON_FOOTPRINT)
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
			_msg("erreur", "%s en %s : pas la place (il faut %d case(s) de mur derrière et %d × %d cases de sol libre devant ; gêné en %s)" % [e.nom, where, fp[0], fp[0], fp[1], _at(k, bad[0])], k, bad)
			continue
		# Objets pleins (boîte, distributeurs...) : leur emprise gêne le passage.
		if fp[1] >= 2:
			for l in range(l0, l0 + fp[0]):
				for dd in fp[1]:
					_obstacles[k][Vector2i(l, row - best.y * dd) if lat.x != 0 else Vector2i(row - best.x * dd, l)] = true
		wall_items.append({"key": b.key, "entry": e, "floor": k, "cells": b.cells, "zone": b.zone, "wall": best, "face": face, "center": center})


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
		floor_items.append({"key": b.key, "floor": b.floor, "cells": b.cells, "zone": b.zone,
			"center": Vector2(cx / b.cells.size(), cy / b.cells.size()), "rect": b.rect})
	var starts := floor_items.filter(func(it): return it.key == "depart")
	if starts.is_empty():
		_msg("erreur", "aucun départ des joueurs (carré vert %s sur le sol de la zone A)" % str(entry("depart").rgb))
		return
	for it in starts:
		if it.zone != "a":
			_msg("erreur", "départ des joueurs en %s dans la zone %s : il doit être dans la zone A (zone ouverte au début)" % [_at(it.floor, it.cells[0]), _zu(it.zone)], it.floor, it.cells)
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
			_msg("erreur", "départ des joueurs en %s : trop près d'un mur ou d'un objet (laissez 1 m autour)" % _at(p[0], cell), p[0], [cell])
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
					if k == 0:
						bad_tremie.append(c)
					elif floors[k - 1].at(c) in [K.VIDE]:
						bad_tremie.append(c)
					else:
						for d in DIRS:
							if f.at(c + d) == K.VIDE:
								tremie_void.append(c)
								break
		for group in _groups(no_wall):
			_msg("erreur", "sol au bord du vide sans mur en %s (%d case(s)) : fermez la pièce par un mur noir (une fenêtre se pose DANS un mur)" % [_at(k, group[0]), group.size()], k, group)
		for group in _groups(bad_tremie):
			_msg("erreur", "trémie en %s : %s" % [_at(k, group[0]), "pas de trémie au rez-de-chaussée (étage 0)" if k == 0 else "rien en dessous (une trémie s'ouvre sur une salle de l'étage %d)" % (k - 1)], k, group)
		for group in _groups(tremie_void):
			_msg("erreur", "trémie en %s bordée de vide à l'étage %d : dessinez le mur de l'étage autour de la double hauteur" % [_at(k, group[0]), k], k, group)
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
		_msg("erreur", "passage de %.1f m en %s : trop étroit pour les zombies et les joueurs (1 m au moins)" % [scale, _at(f.index, group[0])], f.index, group)
	for group in _groups(two):
		_msg("attention", "goulot de %.1f m en %s (%d case(s)) : les zombies y passent à la file ; BO1 : couloirs de 2 à 4 m" % [2 * scale, _at(f.index, group[0]), group.size()], f.index, group)


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
			if d == -stairs[st_here].up and _side(stairs[st_here].rect, -stairs[st_here].up).has(n):
				out.append([k, n])
		elif st_n >= 0:
			if d == stairs[st_n].up and _side(stairs[st_n].rect, -stairs[st_n].up).has(c):
				out.append([k, n])
		elif here != K.ESCALIER:
			out.append([k, n])
	# Haut d'escalier : passage entre la dernière marche et le palier du dessus.
	if st_here >= 0:
		var s: Dictionary = stairs[st_here]
		var t: Vector2i = c + s.up
		if _side(s.rect, s.up).has(t):
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
		if it.key == "arrivee":
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
			_msg("erreur", "%s inaccessible depuis le départ, même toutes portes ouvertes (%d case(s), en %s) : il manque une porte, un passage ou un escalier" % ["zone " + _zu(z) if z != "" else "passage", group.size(), _at(k, group[0])], k, group)
	# Une zone d'un seul tenant (sans passer de porte) : sinon un mur de trop la coupe.
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
			_msg("erreur", "zone %s coupée en morceaux sans passage entre eux : %s et %s — un mur de trop, ou donnez une autre couleur de zone au second morceau" % [_zu(z), _at(cells[0][0], cells[0][1]), _at(rest[0][0], rest[0][1])], rest[0][0], rest.map(func(kc): return kc[1]).slice(0, 60))
	# Distance à pied de chaque case à la fenêtre la plus proche.
	var wsrc := []
	for w in windows:
		for c in _side(w.rect, w.inward):
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
		n[it.key] = n.get(it.key, 0) + 1
	var boxes: int = n.get("boite", 0) + n.get("boite_depart", 0)
	if boxes == 0:
		_msg("erreur", "aucun emplacement de boîte mystère (carré jaune contre un mur)")
	elif boxes < 3:
		_msg("attention", "%d emplacement(s) de boîte seulement : la boîte se déplace entre au moins 3 emplacements (BO1 : 6 à 9 selon la taille)" % boxes)
	if n.get("boite_depart", 0) > 1:
		_msg("erreur", "%d emplacements « boîte (départ) » : un seul" % n.boite_depart)
	for key in ["courant", "pap", "teleporteur", "arrivee", "poste_central"]:
		if n.get(key, 0) > 1:
			var its := (wall_items + floor_items).filter(func(it): return it.key == key)
			_msg("erreur", "%d × %s : un seul par carte" % [n[key], entry(key).nom], its[1].floor, its[1].cells)
	if n.get("courant", 0) == 0:
		_msg("attention", "pas d'interrupteur du courant : le courant sera là dès le départ (BO1 : on le rétablit dans une salle éloignée)")
	if n.get("teleporteur", 0) != n.get("arrivee", 0):
		_msg("erreur", "téléporteur : il faut une plateforme ET une arrivée")
	if n.get("poste_central", 0) > 0 and n.get("teleporteur", 0) == 0:
		_msg("erreur", "poste central sans téléporteur")
	for e in legend().couleurs:
		if e.has("atout") and n.get(e.cle, 0) > 1:
			_msg("erreur", "%d distributeurs %s : un seul par atout" % [n[e.cle], e.nom])
	# Chaque zone a au moins une fenêtre (sauf la salle du téléporteur).
	var tp_exit := ""
	for it in floor_items:
		if it.key == "arrivee":
			tp_exit = it.zone
	for z in zones:
		if windows.any(func(w): return w.zone == z):
			continue
		if z == tp_exit:
			_msg("info", "zone %s (arrivée du téléporteur) sans fenêtre : aucun zombie n'y apparaît" % _zu(z))
		else:
			_msg("erreur", "zone %s sans fenêtre : les zombies n'y apparaîtraient jamais (ajoutez une fenêtre bleue dans un mur extérieur)" % _zu(z))
	# Pièges : chaque zone de piège a un levier proche, chaque levier sa zone.
	var traps := floor_items.filter(func(it): return it.key == "piege")
	var levers := wall_items.filter(func(it): return it.key == "levier")
	for lv in levers:
		var best = null
		for t in traps:
			if t.floor == lv.floor and (t.center - lv.center).length() * scale <= LEVER_RANGE and (best == null or (t.center - lv.center).length() < (best.center - lv.center).length()):
				best = t
		if best == null:
			_msg("erreur", "levier en %s : aucune zone de piège à moins de %d m" % [_at(lv.floor, lv.cells[0]), int(LEVER_RANGE)], lv.floor, lv.cells)
		else:
			best.get_or_add("levers", []).append(lv)
	for t in traps:
		var lvs: Array = t.get("levers", [])
		if lvs.is_empty():
			_msg("erreur", "zone de piège en %s sans levier (levier rouge sombre contre un mur, à moins de %d m)" % [_at(t.floor, t.cells[0]), int(LEVER_RANGE)], t.floor, t.cells)
		elif lvs.size() > 2:
			_msg("erreur", "zone de piège en %s : %d leviers (2 au plus, un à chaque bout)" % [_at(t.floor, t.cells[0]), lvs.size()], t.floor, t.cells)
	for z in zone_names:
		if not zones.has(z):
			_msg("attention", "carte.txt : « zone %s » absente du dessin" % _zu(z))
	for z in zones:
		if not zone_names.has(z):
			_msg("attention", "zone %s sans nom : ajoutez « zone %s = Nom » dans carte.txt (affiché sur les portes)" % [_zu(z), _zu(z)])


## Départ sûr : au moins une apparition de la zone de départ à 7 m ou plus
## (MIN_SPAWN_DIST), aucune fenêtre collée au départ.
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
	if best < MIN_SPAWN_DIST:
		_msg("erreur", "départ des joueurs à moins de %.0f m de toutes les fenêtres de la zone A (%.1f m au mieux) : le jeu n'y ferait apparaître aucun zombie ; éloignez le départ" % [MIN_SPAWN_DIST, best], start_points[0][0], [Vector2i(start_points[0][1])])
		return
	if nearest < 5.0:
		_msg("attention", "départ à %.1f m d'une fenêtre : les premiers zombies arrivent aussitôt (BO1 : 6 m ou plus)" % nearest)
	_msg("info", "Départ : fenêtre la plus proche à %.1f m, apparition utilisable la plus lointaine à %.1f m" % [nearest, best])


# --------------------------------------------------------------------- amusement

func _fun() -> void:
	# Zones : surface, fenêtres, objets.
	var area := {}
	for f in floors:
		for i in f.zone.size():
			if f.zone[i] != "" and f.kind[i] in [K.SOL, K.MARQUEUR, K.ESCALIER]:
				area[f.zone[i]] = area.get(f.zone[i], 0) + 1
	var parts := []
	var total := 0
	for z in zones:
		var nw := windows.filter(func(w): return w.zone == z).size()
		parts.append("%s %s (%d m², %d fenêtre%s)" % [_zu(z), zone_names.get(z, ""), roundi(m2(area.get(z, 0))), nw, "s" if nw > 1 else ""])
		total += area.get(z, 0)
	_msg("info", "Zones : " + " ; ".join(parts))
	_msg("info", "Surface praticable %d m², emprise %.0f × %.0f m, %d étage(s), %d porte(s)/débris, %d fenêtres" % [roundi(m2(total)), floors[0].w * scale, floors[0].h * scale, floors.size(), doors.size(), windows.size()])
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
	var cycles := []
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
		cycles.append("%s (%d points de portes)" % [" → ".join(ring.map(func(z): return _zu(z))), cost])
	if cycles.is_empty():
		_msg("attention", "aucune boucle entre les zones : impossible de tourner d'une salle à l'autre (BO1 Kino : deux grandes boucles hall → loges → scène)")
	else:
		_msg("info", "Boucles entre zones (portes ouvertes) : %d — %s" % [cycles.size(), " ; ".join(cycles)])
	# Blocs isolés (pilier, îlot de murs, trémie entourée de plancher) : on tourne autour.
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
					_msg("info", "Boucle de training autour du bloc en %s : tour au plus près ≈ %.0f m%s%s" % [_at(f.index, comp[0]), loop,
						" en passant les portes" if doors_on else "", "" if loop >= 20.0 else " (petit : BO1 ≈ 25-40 m)"], f.index, [comp[0]])
	if cycles.is_empty() and islands == 0:
		_msg("attention", "aucun endroit pour tourner en rond (« training ») : ajoutez un pilier ou une boucle de salles")
	# Impasses et passages obligés.
	for z in zones:
		var exits := zone_edges.filter(func(e): return e.a == z or e.b == z)
		if exits.size() == 1:
			var o: String = exits[0].b if exits[0].a == z else exits[0].a
			_msg("attention" if z == "a" else "info", "Impasse : zone %s n'a qu'une sortie (vers %s)%s" % [_zu(z), _zu(o), " — le départ doit avoir 2 sorties (BO1)" if z == "a" else " : bon coin pour camper, piège pour le training"])
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
			_msg("info", "Passage obligé (goulot) entre %s et %s (%s)" % [_zu(e.a), _zu(e.b), {"porte": "porte", "debris": "débris", "ouvert": "passage", "escalier": "escalier"}[e.kind]])


func _path_up(parent: Dictionary, z: String) -> Array:
	var out := [z]
	while parent.get(out[-1], "") != "":
		out.append(parent[out[-1]])
	return out


## Coût pour atteindre chaque zone depuis A (portes les moins chères).
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
	var steps := []
	var total := 0
	var power_doors := doors.filter(func(d): return d.power)
	while true:
		var best = null
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
		steps.append("%d (%s, ouvre %s)" % [best.cost, "débris" if best.debris else "porte %s" % best.id, ", ".join(group.map(func(z): return _zu(z)))])
	for d in doors:
		if not bought.has(d.id) and not d.power:
			bought[d.id] = true
			total += d.cost
			steps.append("%d (%s %s-%s, ferme une boucle)" % [d.cost, "débris" if d.debris else "porte", _zu(d.zones[0]), _zu(d.zones[1])])
	if steps.is_empty():
		_msg("attention", "aucune porte payante : toute la carte est ouverte dès le départ (BO1 : 5 à 10 portes)")
		return
	_msg("info", "Courbe d'ouverture (moins cher d'abord) : %s ; total pour tout ouvrir %d points" % [" → ".join(steps), total])
	if not power_doors.is_empty():
		_msg("info", "%d porte(s) ouverte(s) par le courant" % power_doors.size())
	var first := doors.filter(func(d): return not d.power and (d.zones[0] == "a" or d.zones[1] == "a" or open_links.get("a", []).has(d.zones[0]) or open_links.get("a", []).has(d.zones[1])))
	first.sort_custom(func(x, y): return x.cost < y.cost)
	if not first.is_empty() and (first[0].cost < 500 or first[0].cost > 1000):
		_msg("attention", "première porte à %d points : BO1 la met à 750-1000 (achetée vers la fin de la manche 1 ou en manche 2)" % first[0].cost)
	var unlocked := opened.size()
	if unlocked < zones.size():
		var closed := zones.filter(func(z): return not opened.has(z))
		_msg("info", "zones ouvertes seulement par le courant ou le téléporteur : %s" % ", ".join(closed.map(func(z): return _zu(z))))


func _fun_items() -> void:
	var costs := zone_costs()
	var box_zones := {}
	var box_list := []
	for it in wall_items:
		if it.key == "boite" or it.key == "boite_depart":
			box_zones[it.zone] = true
			box_list.append("%s%s" % [_zu(it.zone), " (départ)" if it.key == "boite_depart" else ""])
	if not box_list.is_empty():
		_msg("info", "Boîte mystère : %d emplacements, zones %s" % [box_list.size(), ", ".join(box_list)])
		if box_zones.size() == 1 and box_list.size() > 1:
			_msg("attention", "tous les emplacements de boîte sont dans la zone %s : répartissez-les (BO1 : un par grande salle)" % _zu(box_zones.keys()[0]))
	var perk_parts := []
	var has := {}
	for it in wall_items:
		if not it.entry.has("atout"):
			continue
		has[it.entry.atout] = it
		perk_parts.append("%s en %s (%d points de portes)" % [String(it.entry.nom).get_slice(" (", 0).trim_prefix("Atout "), _zu(it.zone), costs.get(it.zone, 0)])
	if not perk_parts.is_empty():
		_msg("info", "Atouts : " + " ; ".join(perk_parts))
	if has.has("titan"):
		var t: Dictionary = has.titan
		var exits := zone_edges.filter(func(e): return e.a == t.zone or e.b == t.zone).size()
		_msg("attention" if t.zone == "a" else "info", "Coin TITAN BREW (rôle du Juggernog) : zone %s, %d points de portes depuis le départ, %s%s" % [_zu(t.zone), costs.get(t.zone, 0), "impasse (bon coin pour camper)" if exits <= 1 else "zone de passage (%d sorties)" % exits, " — BO1 : jamais dans la salle de départ, il se mérite (1 à 3 portes)" if t.zone == "a" else ""])
	else:
		_msg("attention", "pas de TITAN BREW (rôle du Juggernog) : les cartes de BO1 en ont toujours un")
	if has.has("lazarus") and has.lazarus.zone != "a":
		_msg("info", "LAZARUS TONIC (rôle du Quick Revive) hors de la zone de départ (BO1 : dans la salle de départ)")
	var weapons := wall_items.filter(func(it): return it.entry.has("arme"))
	if not weapons.is_empty():
		_msg("info", "Armes au mur : " + ", ".join(weapons.map(func(it): return "%s (%s)" % [String(it.entry.arme), _zu(it.zone)])))
	if not weapons.any(func(it): return it.zone == "a"):
		_msg("attention", "aucune arme au mur dans la zone de départ (BO1 : M14 ou Olympia à 500 points dès le départ)")


func _fun_spawns() -> void:
	var worst := {}
	for f in floors:
		var arr: PackedFloat32Array = window_dist[f.index]
		for i in arr.size():
			var z := f.zone[i]
			if z != "" and arr[i] >= 0.0 and f.kind[i] in [K.SOL, K.MARQUEUR]:
				worst[z] = maxf(worst.get(z, 0.0), arr[i])
	var parts := []
	for z in zones:
		parts.append("%s %.0f m" % [_zu(z), worst.get(z, 0.0)])
		if worst.get(z, 0.0) > 30.0:
			_msg("attention", "zone %s : un point à %.0f m à pied de toute fenêtre (les zombies mettent longtemps à venir ; BO1 : 25 m au plus)" % [_zu(z), worst[z]])
	_msg("info", "Distance à pied au plus loin d'une fenêtre, par zone : " + ", ".join(parts))


# --------------------------------------------------------------------- repères

## Position monde (m, sol de l'étage) d'un point du dessin (en cases).
func _world(k: int, p: Vector2) -> Vector3:
	return Vector3(ORIGIN + p.x * scale, floors[k].sol, ORIGIN + p.y * scale)


## Fenêtre : milieu (au sol, au milieu du mur), vers l'intérieur, apparition.
func _world_window(w: Dictionary) -> Dictionary:
	var r: Rect2i = w.rect
	var c := Vector2(r.position) + Vector2(r.size) * 0.5
	var p := _world(w.floor, c)
	var inn := Vector3(w.inward.x, 0, w.inward.y)
	return {"p": p, "in": inn, "spawn": p - inn * SPAWN_OUT}


# --------------------------------------------------------------------- rapport

func report_text() -> String:
	var lines := PackedStringArray()
	lines.append("Carte « %s » (%s) : %d erreur(s), %d avertissement(s)" % [display_name if display_name != "" else id, id, errors().size(), warnings().size()])
	for level in ["erreur", "attention", "info"]:
		var list := messages.filter(func(m): return m.level == level)
		if list.is_empty():
			continue
		lines.append("")
		lines.append({"erreur": "ERREURS (la carte est refusée) :", "attention": "AVERTISSEMENTS :", "info": "INDICATEURS (BO1) :"}[level])
		for m in list:
			lines.append("  - " + String(m.text))
	return "\n".join(lines) + "\n"


## Dessin agrandi, problèmes entourés (rouge : erreur, orange : avertissement).
func report_images(zoom := 8) -> Array[Image]:
	var out: Array[Image] = []
	for f in floors:
		var src: Image = f.get_meta("image", null)
		if src == null:
			out.append(null)
			continue
		var img := src.duplicate() as Image
		img.convert(Image.FORMAT_RGBA8)
		img.resize(f.w * zoom, f.h * zoom, Image.INTERPOLATE_NEAREST)
		# Quadrillage léger toutes les 10 cases (5 m) pour se repérer.
		for y in img.get_height():
			for x in img.get_width():
				if (x % (zoom * 10) == 0) or (y % (zoom * 10) == 0):
					img.set_pixel(x, y, img.get_pixel(x, y).lerp(Color(0.2, 0.4, 1.0), 0.35))
		for m in messages:
			if m.floor != f.index or m.cells.is_empty() or m.level == "info":
				continue
			var col := Color(1, 0, 0) if m.level == "erreur" else Color(1, 0.55, 0)
			for c in m.cells:
				_frame(img, Rect2i(c.x * zoom - 2, c.y * zoom - 2, zoom + 4, zoom + 4), col)
		out.append(img)
	return out


static func _frame(img: Image, r: Rect2i, col: Color) -> void:
	for t in 2:
		for x in range(r.position.x, r.end.x):
			for y in [r.position.y + t, r.end.y - 1 - t]:
				if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
					img.set_pixel(x, y, col)
		for y in range(r.position.y, r.end.y):
			for x in [r.position.x + t, r.end.x - 1 - t]:
				if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
					img.set_pixel(x, y, col)


# --------------------------------------------------------------------- tests

## Image d'un dessin écrit en caractères (tests) : un caractère = une case,
## `chars` : caractère -> clé de légende.
static func image_from_ascii(rows: Array, chars: Dictionary) -> Image:
	var w := 0
	for r in rows:
		w = maxi(w, String(r).length())
	var img := Image.create(w, rows.size(), false, Image.FORMAT_RGB8)
	img.fill(color_of("vide"))
	for y in rows.size():
		var r := String(rows[y])
		for x in r.length():
			img.set_pixel(x, y, color_of(chars.get(r[x], "vide")))
	return img
