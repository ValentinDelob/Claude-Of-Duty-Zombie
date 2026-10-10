class_name MapLayoutExport
extends RefCounted
## Description de carte en maillage tirée d'une carte de l'éditeur validée
## (MapValidator) : même format que assets/maps/test_levels/layout.json, lu
## par MeshMapLayout (jeu) et construit en cubes par MeshMapGeometry. Salles (sols, plafonds,
## dalles de niveau), blocs (murs, allèges, linteaux, décor), garde-corps,
## escaliers (rampe de collision), zones, marqueurs (objets muraux donnés par
## la face du mur et la direction du mur).

const Kd := MapValidator.K

var md: MapValidator
var S := 0.5
var n_floors := 0
var rooms: Array = []
var blocks: Array = []
var walls: Array = []
var rails: Array = []
var stairs: Array = []
## Murs en biais : [{a, b ([x, z]), y0, y1, thick, mat_n, mat_m, room, openings}]
## (MeshMapGeometry : pavés obliques, collisions en CollisionBox tournées).
var obliques: Array = []
var props: Array = []   # décor posé : [{id, model | build, p, yaw, scale, remap, nocollide}] ; format 14 : « basis »
var blockers: Array = []   # collisions du décor et des luminaires : [{center, size, yaw, barrier, surface}] ; format 14 : « basis »
## Format 14 : emprises au sol des décors inclinés qui bloquent, retirées du
## navmesh des zombies (MeshNav : obstruction projetée) : [{poly [[x, z]...],
## y (bas), h}]. Une pente n'est jamais un passage (prudent).
var nav_blocks: Array = []
## Effets (format 10 ; zone : format 11) : [{fx, p, yaw, ground, room_h,
## intensity, zone [largeur, profondeur, hauteur] (m), color, eid}]
## (MapEffects ; aucune collision). « ground » : distance (m) de l'effet au sol.
var effects: Array = []
var zone_boxes: Array = []   # [niveau, volume, zone, boîte]
## Boîtes de zone des morceaux de sol le long des murs obliques : testées après
## celles des salles de la grille (une boîte englobante déborde un peu du mur).
var filler_boxes: Array = []
var ref_room: Dictionary = {}   # niveau -> id d'une salle (hauteur de sol des murs)
var door_of: Array = []   # par niveau : {Vector2i: porte}


static func build(v: MapValidator) -> Dictionary:
	var ex := MapLayoutExport.new()
	ex.md = v
	return ex._build()


func _r(v: float) -> float:
	return snappedf(v, 0.001)


func wx(px: float) -> float:
	return _r(MapValidator.ORIGIN + px * S)


## Haut du niveau, plafond réel d'une case, haut des murs : MapVertical
## (partagé avec les élévations de l'éditeur).
func top(k: int) -> float:
	return MapVertical.top(md, k)


## Plafond au-dessus d'une case : [hauteur, plafond dessiné (sinon : dessous de dalle)].
func ceil_at(k: int, c: Vector2i) -> Array:
	return MapVertical.ceil_at(md, k, c)


func wall_top(k: int, c: Vector2i) -> float:
	return MapVertical.wall_top(md, k, c)


func _wall_mat(f: MapValidator.Floor, c: Vector2i) -> String:
	var count := {}
	for d in MapValidator.DIRS:
		var z := _side_zone(f, c + d)
		if z != "":
			count[z] = count.get(z, 0) + 1
	var best := ""
	for z in count:
		if best == "" or count[z] > count[best] or (count[z] == count[best] and z < best):
			best = z
	return String(md.wall_mats.get(best, "wall"))


## Rectangles maximaux de cases de même clé ("" : rien). -> [[Rect2i, clé]]
static func merge_rects(w: int, h: int, keys: PackedStringArray) -> Array:
	var used := PackedByteArray()
	used.resize(w * h)
	var out := []
	for y in h:
		for x in w:
			var key := keys[y * w + x]
			if key == "" or used[y * w + x]:
				continue
			var x1 := x
			while x1 + 1 < w and keys[y * w + x1 + 1] == key and not used[y * w + x1 + 1]:
				x1 += 1
			var y1 := y
			var grow := true
			while grow and y1 + 1 < h:
				for xx in range(x, x1 + 1):
					if keys[(y1 + 1) * w + xx] != key or used[(y1 + 1) * w + xx]:
						grow = false
						break
				if grow:
					y1 += 1
			for yy in range(y, y1 + 1):
				for xx in range(x, x1 + 1):
					used[yy * w + xx] = 1
			out.append([Rect2i(x, y, x1 - x + 1, y1 - y + 1), key])
	return out


func _outline(r: Rect2i) -> Array:
	var x0 := wx(r.position.x)
	var x1 := wx(r.end.x)
	var z0 := wx(r.position.y)
	var z1 := wx(r.end.y)
	return [[x0, z0], [x1, z0], [x1, z1], [x0, z1]]


func _build() -> Dictionary:
	S = md.scale
	n_floors = md.floors.size()
	for f in md.floors:
		var dm := {}
		for d in md.doors:
			if d.floor == f.index:
				for c in d.cells:
					dm[c] = d
		door_of.append(dm)
	for f in md.floors:
		_rooms(f)
		_fillers(f)
	for f in md.floors:
		_walls(f)
		_obliques(f)
		_rails(f)
	_decor()
	_props()
	_effects()
	_clips()
	_stairs()
	var markers := _markers()
	_pockets()
	# Zones : boîtes des salles ; niveaux hauts d'abord, puis les plus petites.
	zone_boxes.sort_custom(func(a, b): return a[0] > b[0] if a[0] != b[0] else a[1] < b[1])
	filler_boxes.sort_custom(func(a, b): return a[0] > b[0] if a[0] != b[0] else a[1] < b[1])
	zone_boxes.append_array(filler_boxes)
	var zones := {}
	var zone_order := []
	for zb in zone_boxes:
		zones.get_or_add(zb[2], {"boxes": []}).boxes.append(zb[3])
		zone_order.append({"zone": zb[2], "box": zb[3]})
	var out := {
		"id": md.id,
		"note": "Généré par l'éditeur de cartes (MapLayoutExport) - ne pas modifier à la main.",
		"rooms": rooms, "walls": walls, "blocks": blocks, "rails": rails, "stairs": stairs,
		"props": props, "blockers": blockers,
		"zones": zones, "zone_order": zone_order, "markers": markers, "map_def": _map_def(),
	}
	if not obliques.is_empty():
		out["obliques"] = obliques
	# Format 10 : modèles des prefabs importés posés (pid -> .glb en base64),
	# construits par le jeu (MeshMapBuilder, GLTFDocument).
	if not map_models.is_empty():
		out["map_models"] = map_models
	# Format 15 : textures de la carte utilisées (matériaux « tex-<tid> »),
	# chargées par le jeu (MeshMapBuilder, MapTextureLib.material_of).
	if not md.map_textures.is_empty():
		out["map_textures"] = md.map_textures
	if not effects.is_empty():
		out["effects"] = effects
	if not nav_blocks.is_empty():
		out["nav_blocks"] = nav_blocks
	# Format 20 : filet de sécurité, toute l'architecture sur la grille des
	# cubes de 5 cm (cartes reçues, anciennes valeurs, morceaux calculés).
	snap_layout(out)
	return out


# ------------------------------------------------------------------ grille des cubes (format 20)

## Clés d'architecture d'une description (docs/VOXEL_ARCHITECTURE_PLAN.md
## § 2.1) : chaque nombre de ces entrées est un multiple de 5 cm, sauf les
## blocs de décor (« decor ») et les nombres qui ne sont pas des longueurs
## (salles : seulement contours, sol, plafond, dalles ; escaliers : bouts et
## largeur ; murs en biais : bouts, hauteurs, épaisseur, hauteurs des
## ouvertures — leur milieu et leur largeur se mesurent le long du mur).
const ARCHI_KEYS := ["rooms", "blocks", "walls", "obliques", "rails", "stairs", "slabs"]


## Toute l'architecture d'une description arrondie au cube de 5 cm (en place).
## Un contour dont deux sommets voisins se confondent les fusionne ; un
## morceau de sol devenu plat (moins de 3 sommets) disparaît.
static func snap_layout(L: Dictionary) -> void:
	var c := func(v: Variant) -> Variant:
		return MapGeom.cube(float(v)) if (v is float or v is int) else v
	var pts := func(path: Variant) -> Array:
		var out := []
		if not path is Array:
			return out
		for p in path:
			if p is Array and p.size() >= 2:
				var q: Array = p.map(func(x): return c.call(x))
				if out.is_empty() or out[-1] != q:
					out.append(q)
			else:
				out.append(p)
		return out
	var rooms_out := []
	for r in L.get("rooms", []):
		if not r is Dictionary:
			continue
		var ol: Array = pts.call(r.get("outline", []))
		while ol.size() > 3 and ol[0] == ol[-1]:
			ol.pop_back()
		if ol.size() < 3:
			continue
		r["outline"] = ol
		for k in ["floor", "ceiling", "floor_slab", "ceiling_slab"]:
			if r.has(k):
				r[k] = c.call(r[k])
		rooms_out.append(r)
	if L.has("rooms"):
		L["rooms"] = rooms_out
	for b in L.get("blocks", []):
		if b is Dictionary and not b.get("decor", false) and b.get("box") is Array:
			b["box"] = (b.box as Array).map(func(x): return c.call(x))
	for w in L.get("walls", []):
		if not w is Dictionary:
			continue
		w["path"] = pts.call(w.get("path", []))
		for k in ["y0", "y1", "thick"]:
			if w.has(k):
				w[k] = c.call(w[k])
		for o in w.get("openings", []):
			for k in ["t", "w", "y0", "y1"]:
				if o is Dictionary and o.has(k):
					o[k] = c.call(o[k])
	for w in L.get("obliques", []):
		if not w is Dictionary:
			continue
		# Ouvertures d'un mur en biais : leur milieu « t » se compte depuis le
		# bout « a » ; « a » arrondi, « t » est décalé d'autant (l'ouverture
		# reste à sa place sur le mur ; « t » et « w » sont des longueurs le
		# long d'un mur en biais, pas des coordonnées de la grille).
		var shift := 0.0
		if w.get("a") is Array and w.get("b") is Array and (w.a as Array).size() >= 2 and (w.b as Array).size() >= 2:
			var a0 := Vector2(float(w.a[0]), float(w.a[1]))
			var d := Vector2(float(w.b[0]), float(w.b[1])) - a0
			if d.length() > 1e-6:
				shift = (a0 - Vector2(MapGeom.cube(a0.x), MapGeom.cube(a0.y))).dot(d.normalized())
		for k in ["a", "b", "arc"]:
			if w.get(k) is Array:
				w[k] = (w[k] as Array).map(func(x): return c.call(x))
		for o in w.get("openings", []):
			if o is Dictionary and o.has("t"):
				o["t"] = snappedf(float(o.t) + shift, 0.001)
		for k in ["y0", "y1"]:
			if w.has(k):
				w[k] = c.call(w[k])
		if w.has("thick"):
			# Raccord d'angle : jamais plus mince (pas de jour entre deux murs).
			var t := float(w.thick)
			w["thick"] = maxf(MapGeom.CUBE, ceilf(t * MapGeom.CUBES_PER_M - 0.001) / MapGeom.CUBES_PER_M if w.get("joint", false) else MapGeom.cube(t))
		for o in w.get("openings", []):
			for k in ["y0", "y1"]:
				if o is Dictionary and o.has(k):
					o[k] = c.call(o[k])
	for rl in L.get("rails", []):
		if not rl is Dictionary:
			continue
		rl["path"] = pts.call(rl.get("path", []))
		for k in ["y", "h"]:
			if rl.has(k):
				rl[k] = c.call(rl[k])
	for s in L.get("stairs", []):
		if not s is Dictionary:
			continue
		for k in ["a", "b"]:
			if s.get(k) is Array:
				s[k] = (s[k] as Array).map(func(x): return c.call(x))
		if s.has("w"):
			s["w"] = c.call(s.w)
	for sl in L.get("slabs", []):
		if not sl is Dictionary:
			continue
		sl["outline"] = pts.call(sl.get("outline", []))
		for k in ["y", "thick"]:
			if sl.has(k):
				sl[k] = c.call(sl[k])


## Valeurs d'architecture d'une description hors de la grille des cubes de
## 5 cm : ["chemin : valeur", ...] (vide : tout est sur la grille). Mêmes
## clés que snap_layout ; contrôle des tests et de la commande --check.
static func off_grid(L: Dictionary) -> Array:
	var out := []
	var walk := func(self_fn: Callable, v: Variant, path: String) -> void:
		if v is float or v is int:
			if not MapGeom.on_cube(float(v)):
				out.append("%s : %s" % [path, str(v)])
		elif v is Array:
			for i in (v as Array).size():
				self_fn.call(self_fn, v[i], "%s[%d]" % [path, i])
	var fields := {"rooms": ["outline", "floor", "ceiling", "floor_slab", "ceiling_slab"], "blocks": ["box"],
		"walls": ["path", "y0", "y1", "thick"], "obliques": ["a", "b", "arc", "y0", "y1", "thick"],
		"rails": ["path", "y", "h"], "stairs": ["a", "b", "w"], "slabs": ["outline", "y", "thick"]}
	for key in fields:
		var list: Variant = L.get(key, [])
		if not list is Array:
			continue
		for i in (list as Array).size():
			var e: Variant = list[i]
			if not e is Dictionary or e.get("decor", false):
				continue
			for f in fields[key]:
				if e.has(f):
					walk.call(walk, e[f], "/%s[%d]/%s" % [key, i, f])
			for j in (e.get("openings", []) as Array).size():
				# Mur en biais : « t » et « w » se mesurent le long du mur.
				for f in (["y0", "y1"] if key == "obliques" else ["t", "w", "y0", "y1"]):
					if (e.openings[j] as Dictionary).has(f):
						walk.call(walk, e.openings[j][f], "/%s[%d]/openings[%d]/%s" % [key, i, j, f])
	return out


## Surface d'une partie (« sol », « murs », « plafond ») de la pièce de
## l'éditeur `room_id` : celle de la pièce, sinon celle de sa zone, sinon `fallback`.
func surface_of(room_id: String, part: String, zone: String, fallback: String) -> String:
	var own: Dictionary = md.room_surfaces.get(room_id, {})
	if own.has(part):
		return String(own[part])
	var zm: Dictionary = {"sol": md.floor_mats, "murs": md.wall_mats, "plafond": md.ceil_mats}[part]
	return String(zm.get(zone, fallback))


## Plafond d'une pièce sous une pièce (ou un mur) du niveau du dessus : le
## dessous de la dalle `slab_bottom` lui-même (format 20 : plus d'écart de
## 1 cm, tout est sur la grille des cubes de 5 cm). Toujours dessiné, avec la
## texture de plafond de la pièce du bas (même par défaut) : c'est LA face du
## dessous de la dalle ; MeshMapGeometry ne dessine pas la face du dessous
## d'une dalle ou d'un mur là où un plafond est déjà dans son plan (une
## seule face, pas de scintillement).
static func under_slab(slab_bottom: float) -> float:
	return MapGeom.cube(slab_bottom)


## Case de sol d'une pièce, y compris sous le décor posé (prefabs, caisses).
func _floor_cell(f: MapValidator.Floor, c: Vector2i) -> bool:
	if md._walk(f, c):
		return true
	return f.at(c) == Kd.MUR and f.key_at(c).begins_with("decor#") and f.room_of(c) != ""


func _rooms(f: MapValidator.Floor) -> void:
	var k := f.index
	var keys := PackedStringArray()
	keys.resize(f.w * f.h)
	var info := {}
	var dc := _diag(k)
	for y in f.h:
		for x in f.w:
			var c := Vector2i(x, y)
			if not _floor_cell(f, c) or dc.has(c):
				continue
			var ce := ceil_at(k, c)
			var key := ""
			var zone := f.zone_of(c)
			var rid := f.room_of(c)
			if zone == "" and rid != "":
				zone = String(md.room_zone.get(rid, ""))
			if door_of[k].has(c):
				key = "porte%s|%s|%s" % [door_of[k][c].id, ce[0], ce[1]]
				info[key] = [door_of[k][c].id, zone, ce, "wood", "ceiling"]
			else:
				var fm := surface_of(rid, "sol", zone, "concrete")
				var cm := surface_of(rid, "plafond", zone, "ceiling")
				key = "%s|%s|%s|%s|%s" % [zone, ce[0], ce[1], fm, cm]
				info[key] = ["", zone, ce, fm, cm]
			# Plafond masqué (format 17) : son propre plafond, pièce sans plafond.
			if bool(ce[1]) and MapVertical.open_at(md, k, c):
				var ik: Array = info[key]
				key += "|ciel"
				info[key] = ik + [true]
			keys[y * f.w + x] = key
	var n := 0
	for rk in merge_rects(f.w, f.h, keys):
		var r: Rect2i = rk[0]
		var inf: Array = info[rk[1]]
		n += 1
		var zone: String = inf[1]
		var rid := ("porte%s_%d" % [inf[0], n]) if inf[0] != "" else ("%s%d_%d" % [zone, k, n])
		var room := {"id": rid, "outline": _outline(r), "floor": _r(f.sol), "ceiling": _r(inf[2][0]),
			"floor_mat": String(inf[3]), "ceiling_mat": String(inf[4])}
		if not inf[2][1]:
			room["ceiling"] = under_slab(float(inf[2][0]))
		if inf.size() > 5:
			# Ciel ouvert : ni plafond ni collision (MeshMapGeometry) ; « ceiling »
			# reste le plafond virtuel (zones, luminaires accrochés).
			room["no_ceiling"] = true
		if k > 0:
			room["floor_slab"] = MapValidator.DALLE
		rooms.append(room)
		if inf[0] == "":
			if not ref_room.has(k):
				ref_room[k] = rid
			var lo := f.sol - (0.5 if k == 0 else 0.15)
			var b := [wx(r.position.x), _r(lo), wx(r.position.y), wx(r.end.x), _r(inf[2][0]), wx(r.end.y)]
			zone_boxes.append([k, (b[3] - b[0]) * (b[4] - b[1]) * (b[5] - b[2]), zone, b])


## Matériau d'un demi-mur : la moitié (sx, sy) de la case de mur `c` (0 :
## côté ouest / nord, 1 : côté est / sud) prend la texture de la pièce qui la
## touche de ce côté ; un mur mitoyen montre ainsi de chaque côté la texture
## de sa pièce. Sans pièce de ce côté (mur extérieur), celle de la case.
func _half_wall_mat(f: MapValidator.Floor, c: Vector2i, sx: int, sy: int, whole: String) -> String:
	var dx := -1 if sx == 0 else 1
	var dy := -1 if sy == 0 else 1
	for n in [c + Vector2i(dx, 0), c + Vector2i(0, dy), c + Vector2i(dx, dy)]:
		var z := _side_zone(f, n)
		if z != "" and (f.at(n) in [Kd.SOL, Kd.MARQUEUR, Kd.ESCALIER] or _under_decor(f, n)):
			return surface_of(f.room_of(n), "murs", z, "wall")
	return whole


## Case de sol d'une pièce sous un décor posé (prefab, caisse, baril,
## luminaire, barrière invisible) : le raster en fait une case pleine sans
## zone (trajets, validateur) mais, pour l'aspect des murs, c'est toujours le
## sol de sa pièce. L'aspect d'un mur ne dépend que des pièces qui le
## bordent, jamais d'un objet posé contre lui (sinon sa face prenait la
## texture de la pièce d'à côté, ou celle par défaut).
func _under_decor(f: MapValidator.Floor, n: Vector2i) -> bool:
	return f.at(n) == Kd.MUR and f.key_at(n).begins_with("decor#") and f.room_of(n) != ""


## Zone d'une case voisine d'un mur, pour sa texture : la sienne, ou celle de
## la pièce sous un décor posé.
func _side_zone(f: MapValidator.Floor, n: Vector2i) -> String:
	if _under_decor(f, n):
		return String(md.room_zone.get(f.room_of(n), ""))
	return f.zone_of(n)


## Matériau d'une case de mur entière : la pièce la plus présente autour.
func _cell_wall_mat(f: MapValidator.Floor, c: Vector2i) -> String:
	var count := {}
	for d in MapValidator.DIRS:
		var n: Vector2i = c + d
		var z := _side_zone(f, n)
		if z != "":
			var m := surface_of(f.room_of(n), "murs", z, "wall")
			count[m] = count.get(m, 0) + 1
	var best := ""
	for m in count:
		if best == "" or count[m] > count[best] or (count[m] == count[best] and m < best):
			best = m
	return best if best != "" else _wall_mat(f, c)


## Retombée au-dessus d'une case de passage libre (sol hors pièce, entre deux
## pièces en vis-à-vis) : le passage est ouvert jusqu'au plafond le plus BAS
## des deux pièces (MapRaster.passage_ceil) ; au-dessus, le mur continue
## jusqu'au plus haut, chaque face avec la texture de murs de sa pièce.
## -> [bas, haut, [matériau côté ouest/nord, côté est/sud], axe (0 : mur
## nord-sud, pièces à l'ouest et à l'est ; 1 : mur est-ouest)], [] sinon.
## Le bas est le plafond du passage (format 20) : ce plafond est la face du
## dessous de la retombée (MeshMapGeometry ne dessine pas la face du dessous
## du bloc dans le plan d'un plafond).
func _passage_lintel(f: MapValidator.Floor, c: Vector2i) -> Array:
	if f.room_of(c) != "" or f.key_at(c) != "zone":
		return []
	var k := f.index
	for axis in 2:
		var d := Vector2i(1, 0) if axis == 0 else Vector2i(0, 1)
		var a := c - d
		var b := c + d
		if f.room_of(a) == "" or f.room_of(b) == "":
			continue
		var low: float = ceil_at(k, c)[0]
		var top := maxf(float(ceil_at(k, a)[0]), float(ceil_at(k, b)[0]))
		# Mur ou sol d'un niveau du dessus au droit du passage : il commence au
		# dessous de la dalle (pas deux murs l'un dans l'autre, z-fighting).
		var j := MapVertical.slab_above(md, k, c)
		if j >= 0:
			top = minf(top, md.floors[j].sol - MapValidator.DALLE)
		if top <= low + 0.005:
			return []
		var mats := [surface_of(f.room_of(a), "murs", f.zone_of(a), "wall"), surface_of(f.room_of(b), "murs", f.zone_of(b), "wall")]
		return [under_slab(low), top, mats, axis]
	return []


## Retombée au-dessus d'un palier dans l'épaisseur d'un mur (arrivée d'un
## escalier entre deux pièces côte à côte d'altitudes différentes,
## MapRaster._landing) : du plafond du palier (le plus bas) au plus haut des
## plafonds de ses voisines praticables (marches, pièce d'arrivée), coupée
## sous la dalle d'un niveau du dessus. Même forme que _passage_lintel.
func _landing_lintel(f: MapValidator.Floor, c: Vector2i) -> Array:
	var k := f.index
	var low: float = ceil_at(k, c)[0]
	var top := low
	var axis := 0
	for d in MapValidator.DIRS:
		var n: Vector2i = c + d
		if f.at(n) in [Kd.SOL, Kd.MARQUEUR, Kd.TREMIE, Kd.ESCALIER]:
			var ce: float = ceil_at(k, n)[0]
			if ce > top:
				top = ce
				axis = 0 if d.x != 0 else 1
	var j := MapVertical.slab_above(md, k, c)
	if j >= 0:
		top = minf(top, md.floors[j].sol - MapValidator.DALLE)
	if top <= low + 0.005:
		return []
	var m := _cell_wall_mat(f, c)
	return [under_slab(low), top, [m, m], axis]


## Murs, allèges et linteaux : blocs fusionnés sur une grille de demi-cases
## (0,25 m) pour que chaque face d'un mur ait la texture de sa pièce.
func _walls(f: MapValidator.Floor) -> void:
	var k := f.index
	var y0 := f.sol - (0.1 if k == 0 else MapValidator.DALLE)
	var w2 := f.w * 2
	var h2 := f.h * 2
	var main := PackedStringArray()
	var upper := PackedStringArray()
	main.resize(w2 * h2)
	upper.resize(w2 * h2)
	var dc := _diag(k)
	for y in f.h:
		for x in f.w:
			var c := Vector2i(x, y)
			var i := y * f.w + x
			if dc.has(c):
				continue   # mur en biais : vrai mur oblique (_obliques)
			var kd := f.at(c)
			var lo := ""   # grille principale : "bas|haut"
			var lintel := []   # retombée d'un passage : [bas, haut, [matériau ouest/nord, est/sud], axe]
			var hi := ""   # grille du haut (linteaux)
			if kd == Kd.MUR:
				# Décor bloquant : ses propres blocs (_decor) ou objets, pas un mur.
				if f.key[i].begins_with("decor#"):
					continue
				lo = "%s|%s" % [y0, wall_top(k, c)]
			elif kd == Kd.FENETRE:
				if md.barricade_kind_of(f.key[i]) != "fenetre":
					# Porte à zombies (format 8) : ouverte du sol (seuil : un
					# bloc à fleur du sol de la pièce) à la traverse de la porte.
					lo = "%s|%s" % [y0, f.sol]
					hi = "%s|%s" % [f.sol + MapValidator.ZOMBIE_DOOR_TOP, wall_top(k, c)]
				else:
					# Allège et linteau autour de l'ouverture (hauteurs de Barricade).
					lo = "%s|%s" % [y0, f.sol + MapValidator.SILL]
					hi = "%s|%s" % [f.sol + MapValidator.LINTEL, wall_top(k, c)]
			elif kd == Kd.PORTE or kd == Kd.DEBRIS:
				var ce: float = ceil_at(k, c)[0]
				if ce > f.sol + md.door_height + 0.05:
					hi = "%s|%s" % [f.sol + md.door_height, ce]
			elif kd == Kd.SOL:
				# Passage libre entre deux pièces de plafonds différents : retombée
				# du plafond le plus bas au plus haut.
				lintel = _passage_lintel(f, c)
				if lintel.is_empty() and (md.landings.get(k, {}) as Dictionary).has(c):
					lintel = _landing_lintel(f, c)
				if not lintel.is_empty():
					hi = "%s|%s" % [lintel[0], lintel[1]]
			if lo == "" and hi == "":
				continue
			var whole := _cell_wall_mat(f, c)
			for sy in 2:
				for sx in 2:
					var mat := _half_wall_mat(f, c, sx, sy, whole)
					if not lintel.is_empty():
						mat = lintel[2][sx if lintel[3] == 0 else sy]
					var j := (y * 2 + sy) * w2 + x * 2 + sx
					if lo != "":
						main[j] = mat + "|" + lo
					if hi != "":
						upper[j] = mat + "|" + hi
	for grid in [main, upper]:
		for rk in merge_rects(w2, h2, grid):
			var r: Rect2i = rk[0]
			var p: PackedStringArray = String(rk[1]).split("|")
			blocks.append({"room": ref_room.get(k, "x"), "box": [wx(r.position.x * 0.5), _r(p[1].to_float()), wx(r.position.y * 0.5),
				wx(r.end.x * 0.5), _r(p[2].to_float()), wx(r.end.y * 0.5)], "mat": p[0]})


# ------------------------------------------------------------------ murs en biais

## Cases des murs en biais du niveau k ({Vector2i: true}).
func _diag(k: int) -> Dictionary:
	return md.diag_cells[k] if k < md.diag_cells.size() else {}


## Point de l'éditeur (m) -> [x, z] du monde.
static func _xz(m: Vector2) -> Array:
	return [snappedf(m.x + MapGeom.WORLD_OFFSET, 0.001), snappedf(m.y + MapGeom.WORLD_OFFSET, 0.001)]


## Plafond d'une case pour une pièce de plafond `own` (m) : comme ceil_at, mais
## avec le plafond de CETTE pièce (un mur mitoyen porte le plus haut des deux).
func _ceil_room(k: int, c: Vector2i, own: float) -> Array:
	return MapVertical.ceil_room(md, k, c, own)


## Salle (sol, plafond) d'un morceau de contour `outline` ([[x, z]...], monde).
func _room_entry(rid: String, outline: Array, f: MapValidator.Floor, ce: Array, fm: String, cm: String, open := false) -> Dictionary:
	var room := {"id": rid, "outline": outline, "floor": _r(f.sol), "ceiling": _r(ce[0]), "floor_mat": fm, "ceiling_mat": cm}
	if not ce[1]:
		room["ceiling"] = under_slab(float(ce[0]))
	if open:
		room["no_ceiling"] = true
	if f.index > 0:
		room["floor_slab"] = MapValidator.DALLE
	return room


## Sols et plafonds le long des murs en biais : pour chaque pièce, la part de
## ses cases de mur oblique qui est DANS son contour (rangées de cases
## fusionnées, découpées selon le vrai contour puis triangulées par
## MeshMapGeometry) ; le reste de la pièce garde ses rectangles de cases. Le
## sol suit ainsi exactement le trait du mur, sans marches.
func _fillers(f: MapValidator.Floor) -> void:
	var k := f.index
	var dc := _diag(k)
	if dc.is_empty():
		return
	var cells := dc.keys()
	cells.sort_custom(func(a, b): return a.y < b.y or (a.y == b.y and a.x < b.x))
	var half := MapGeom.CELL * 0.5
	for r in md.room_polys[k]:
		var poly: PackedVector2Array = r.poly
		var bb := MapGeom.bbox(poly).grow(MapGeom.CELL)
		var runs := []   # [ligne, x0, x1]
		for c in cells:
			if not bb.has_point(MapGeom.cell_center(c)):
				continue
			if not runs.is_empty() and runs[-1][0] == c.y and runs[-1][2] == c.x - 1:
				runs[-1][2] = c.x
			else:
				runs.append([c.y, c.x, c.x])
		var zone := String(r.zone)
		var fm := surface_of(String(r.id), "sol", zone, "concrete")
		var cm := surface_of(String(r.id), "plafond", zone, "ceiling")
		for run in runs:
			var rect := Rect2(Vector2(run[1], run[0]) * MapGeom.CELL - Vector2(half, half), Vector2((run[2] - run[1] + 1) * MapGeom.CELL, MapGeom.CELL))
			var ce := _ceil_room(k, Vector2i((run[1] + run[2]) / 2, run[0]), float(r.ceil))
			for piece in Geometry2D.intersect_polygons(MapGeom.rect_poly(rect), poly):
				if MapGeom.area(piece) < 1e-4:
					continue
				var outline := []
				for q in piece:
					outline.append(_xz(q))
				rooms.append(_room_entry("biais_%s%d" % [zone, k], outline, f, ce, fm, cm, MapVertical.open_room(md, k, Vector2i((run[1] + run[2]) / 2, run[0]), float(r.ceil), bool(r.get("open", false)))))
				# Zone de ce morceau de sol (testée après les salles de la grille).
				var pb := MapGeom.bbox(piece)
				var lo := f.sol - (0.5 if k == 0 else 0.15)
				var zb := [_r(pb.position.x + MapGeom.WORLD_OFFSET), _r(lo), _r(pb.position.y + MapGeom.WORLD_OFFSET),
					_r(pb.end.x + MapGeom.WORLD_OFFSET), _r(float(ce[0])), _r(pb.end.y + MapGeom.WORLD_OFFSET)]
				filler_boxes.append([k, pb.get_area() * (zb[4] - zb[1]), zone, zb])


## Texture d'un côté de mur en biais : celle des murs de la pièce `rid`.
func _oblique_mat(rid: String) -> String:
	if rid == "":
		return ""
	return surface_of(rid, "murs", String(md.room_zone.get(rid, "")), "wall")


## Murs en biais du niveau : de vrais murs droits obliques (MeshMapGeometry),
## coupés par tronçons de même hauteur (étage du dessus, double hauteur) et
## percés de leurs ouvertures (portes, débris, passages, fenêtres) ; chaque
## face a la texture de la pièce de son côté. Aux angles entre murs en biais,
## un raccord (pavé ajusté à l'angle) ferme la jonction.
func _obliques(f: MapValidator.Floor) -> void:
	var k := f.index
	if k >= md.oblique_walls.size() or md.oblique_walls[k].is_empty():
		return
	var y0 := f.sol - (0.1 if k == 0 else MapValidator.DALLE)
	var dc := _diag(k)
	var ends := {}   # sommet -> {p, list: [{n, half, top, mat}]}
	for w in md.oblique_walls[k]:
		var a: Vector2 = w.a
		var b: Vector2 = w.b
		var t: Vector2 = w.t
		var mat_pos := _oblique_mat(String(w.pos))
		var mat_neg := _oblique_mat(String(w.neg))
		if mat_pos == "":
			mat_pos = mat_neg if mat_neg != "" else String(md.wall_mats.get("a", "wall"))
		if mat_neg == "":
			mat_neg = mat_pos
		var seg_len := a.distance_to(b)
		var nseg := maxi(1, ceili(seg_len / 0.25))
		var runs := []   # [s0, s1, haut]
		for i in nseg:
			var s := (i + 0.5) * seg_len / nseg
			var top_y := wall_top(k, MapGeom.cell_of(a + t * s))
			if not runs.is_empty() and absf(float(runs[-1][2]) - top_y) < 0.001:
				runs[-1][1] = (i + 1) * seg_len / nseg
			else:
				runs.append([i * seg_len / nseg, (i + 1) * seg_len / nseg, top_y])
		var top_max := 0.0
		for run in runs:
			var pa: Vector2 = a + t * float(run[0])
			var pb: Vector2 = a + t * float(run[1])
			top_max = maxf(top_max, float(run[2]))
			var ob := {"room": ref_room.get(k, "x"), "a": _xz(pa), "b": _xz(pb), "y0": _r(y0), "y1": _r(float(run[2])),
				"thick": _r(float(w.half) * 2.0), "mat_n": mat_pos, "mat_m": mat_neg,
				"openings": _oblique_cuts(f, pa, t, float(run[1]) - float(run[0]), y0, float(run[2]))}
			if w.has("arc"):
				# Segment d'un mur courbe : centre de l'arc (MeshMapGeometry : tout
				# l'arc en un escalier de cubes, éclairé comme le vrai arc).
				ob["arc"] = _xz(w.arc)
			obliques.append(ob)
		if String(w.kind) == "pilier":
			continue   # pilier tourné : un pavé plein, sans raccord
		for e in [a, b]:
			# Bouts à 2 cm près (sommets tracés sans grille, murs mitoyens
			# regroupés avec tolérance) : le même sommet.
			var key := "%.3f:%.3f" % [e.x, e.y]
			if not ends.has(key):
				for k2 in ends:
					if Vector2(ends[k2].p).distance_to(e) < 0.02:
						key = k2
						break
			ends.get_or_add(key, {"p": e, "list": []}).list.append({"n": w.n, "half": float(w.half), "top": top_max, "mat": mat_pos, "arc": w.get("arc")})
	# Raccords des angles (sommets entre murs en biais, hors blocs de la grille).
	var keys := ends.keys()
	keys.sort()
	for key in keys:
		var e: Dictionary = ends[key]
		var v: Vector2 = e.p
		if e.list.size() < 2 or not dc.has(MapGeom.cell_of(v)):
			continue
		var pts := PackedVector2Array([v])
		var top_y := 0.0
		for it in e.list:
			pts.append(v + Vector2(it.n) * float(it.half))
			pts.append(v - Vector2(it.n) * float(it.half))
			top_y = maxf(top_y, float(it.top))
		var box := _min_box(pts)
		if box.is_empty() or float(box.w) * float(box.d) < 0.005:
			continue
		var u: Vector2 = box.u
		var c: Vector2 = box.c
		var jn := {"room": ref_room.get(k, "x"), "a": _xz(c - u * float(box.w) * 0.5), "b": _xz(c + u * float(box.w) * 0.5),
			"y0": _r(y0), "y1": _r(top_y), "thick": _r(float(box.d)), "mat_n": String(e.list[0].mat), "mat_m": String(e.list[0].mat),
			"openings": [], "joint": true}
		# Raccord entre deux segments d'un même mur courbe : éclairé comme l'arc.
		var arc: Variant = e.list[0].arc
		if arc != null and e.list.all(func(it): return it.arc != null and Vector2(it.arc).distance_to(arc) < 0.001):
			jn["arc"] = _xz(arc)
		obliques.append(jn)


## Plus petit rectangle orienté qui contient les points (raccord d'angle) :
## {c (centre), u (direction de la longueur), w (longueur), d (épaisseur)}.
static func _min_box(pts: PackedVector2Array) -> Dictionary:
	var hull := Geometry2D.convex_hull(pts)
	var best := {}
	var best_area := INF
	for i in hull.size() - 1:
		var edge := hull[i + 1] - hull[i]
		if edge.length() < 1e-4:
			continue
		var u := edge.normalized()
		var nn := Vector2(-u.y, u.x)
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for p in hull:
			var q := Vector2(p.dot(u), p.dot(nn))
			lo = lo.min(q)
			hi = hi.max(q)
		var sz := hi - lo
		if sz.x * sz.y < best_area:
			best_area = sz.x * sz.y
			var mid := (lo + hi) * 0.5
			best = {"c": u * mid.x + nn * mid.y, "u": u, "w": sz.x, "d": sz.y}
	return best


## Ouvertures d'un tronçon de mur en biais (de `pa`, direction `t`, longueur
## `seg_len`) : [{t (milieu le long du tronçon), w, y0, y1}] (hauteurs absolues).
func _oblique_cuts(f: MapValidator.Floor, pa: Vector2, t: Vector2, seg_len: float, y0: float, top_y: float) -> Array:
	var out := []
	var nrm := Vector2(-t.y, t.x)
	for key in md.diag_open:
		var o: Dictionary = md.diag_open[key]
		if int(o.floor) != f.index:
			continue
		var p: Vector2 = o.p
		if absf((p - pa).dot(nrm)) > MapGeom.JOIN_TOL or absf(Vector2(o.t).dot(t)) < 0.999:
			continue
		var c := (p - pa).dot(t)
		var hw := float(o.w) * 0.5
		if c + hw <= 0.001 or c - hw >= seg_len - 0.001:
			continue
		var oy0 := y0
		var oy1 := top_y
		match String(o.type):
			"fenetre":
				if String(o.get("kind", "fenetre")) in ["porte", "porte_double"]:
					oy0 = f.sol
					oy1 = f.sol + MapValidator.ZOMBIE_DOOR_TOP
				else:
					oy0 = f.sol + MapValidator.SILL
					oy1 = f.sol + MapValidator.LINTEL
			"passage":
				# Passage libre : ouvert jusqu'au plus bas des deux plafonds.
				var ce := INF
				for r in md.room_polys[f.index]:
					if MapGeom.on_boundary(r.poly, p, MapGeom.JOIN_TOL):
						ce = minf(ce, float(r.ceil))
				oy1 = minf(top_y, ce) if ce < INF else top_y
			_:
				if top_y > f.sol + md.door_height + 0.05:
					oy1 = f.sol + md.door_height
		var lo := maxf(c - hw, 0.0)
		var hi := minf(c + hw, seg_len)
		out.append({"t": _r((lo + hi) * 0.5), "w": _r(hi - lo), "y0": _r(oy0), "y1": _r(oy1)})
	return out


## Retrait (m) d'un bloc de décor qui entre dans un mur : ses faces ne sont
## jamais dans le plan d'une face de mur (pas de scintillement, « z-fighting »,
## de l'autre côté d'un mur mitoyen).
const DECOR_WALL_INSET := 0.005


## Décor bloquant (caisses, barils) : un bloc plein à sa hauteur, à sa vraie
## place (posé au centimètre : pas sur les cases arrondies du validateur).
func _decor() -> void:
	for d in md.decor:
		var sol: float = md.floors[d.floor].sol
		var r: Rect2 = d.box
		if bool(d.get("in_wall", false)):
			r = r.grow(-DECOR_WALL_INSET)
		var a: Array = _xz(r.position)
		var b: Array = _xz(r.end)
		# « decor » : bloc d'un décor posé (règles du décor, pas la grille des
		# cubes de l'architecture : snap_layout le laisse tel quel).
		blocks.append({"room": ref_room.get(d.floor, "x"), "box": [a[0], _r(sol), a[1], b[0], _r(sol + float(d.h)), b[1]], "mat": String(d.mat), "decor": true})


## Point du monde d'un point de l'éditeur (m) au niveau k, `dy` au-dessus du sol.
func _world(k: int, m: Vector2, dy := 0.0) -> Vector3:
	return Vector3(_r(m.x + MapGeom.WORLD_OFFSET), _r(md.floors[k].sol + dy), _r(m.y + MapGeom.WORLD_OFFSET))


static func _v3(v: Vector3) -> Array:
	return [snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001)]


## Pavés de collision d'un objet (coordonnées de l'objet) -> « blockers » du
## monde (CollisionBox) : jamais une collision tirée d'un modèle Blender.
func _blockers_of(boxes: Array, origin: Vector3, yaw: float, barrier: bool, surface: String) -> void:
	var b := Basis(Vector3.UP, yaw)
	for bx in boxes:
		var c: Array = bx.center
		blockers.append({"center": _v3(origin + b * Vector3(c[0], c[1], c[2])), "size": bx.size,
			"yaw": _r(yaw + float(bx.get("yaw", 0.0))), "barrier": barrier, "surface": surface})


## Décor posé (prefabs) : objets du jeu (« props » : modèle ou objet
## construit par EditorPrefabs) et leurs collisions (« blockers »).
func _props() -> void:
	for pr in md.props:
		var d: Dictionary = MapCatalog.prefab_def(String(pr.prefab))
		if d.is_empty():
			continue
		var k: int = pr.floor
		var yaw := -deg_to_rad(float(pr.rot))
		var origin := _world(k, pr.center)
		var block := String(d.bloque)
		var c2: Vector2 = pr.center
		var room_h: float = float(ceil_at(k, Vector2i(floori(c2.x / MapGeom.CELL), floori(c2.y / MapGeom.CELL)))[0]) - float(md.floors[k].sol)
		match String(pr.get("mount", "")):
			"mur":
				# Format 11 : décor mural sur la face du mur, +z vers la pièce, à sa
				# hauteur (toujours sous le plafond de la pièce).
				var wv: Vector2 = pr.wall
				yaw = atan2(-wv.x, -wv.y)
				var wy := clampf(float(pr.y), MapCatalog.WALL_LIGHT_HEIGHT[0], maxf(MapCatalog.WALL_LIGHT_HEIGHT[0], room_h - 0.15))
				if pr.has("obj") and MapScale.is_scaled(pr.obj):
					# Format 14 : décor mural agrandi, tout entier sous le plafond et sur le sol.
					var half := MapScale.dims(pr.obj).z * 0.5
					var lo := maxf(MapCatalog.WALL_LIGHT_HEIGHT[0], half)
					wy = clampf(float(pr.y), lo, maxf(lo, room_h - 0.15 - half))
				origin = _world(k, c2, wy)
			"plafond":
				# Format 11 : accroché sous le plafond de la pièce (origine au plafond) ;
				# format 12 : « descente » sous le plafond.
				origin = _world(k, c2, room_h - float(pr.get("descente", 0.0)))
			_:
				# Format 12 : posé sur un autre décor (hauteur de pose) ; ses
				# collisions (blockers) montent avec lui.
				origin = _world(k, c2, float(pr.get("y", 0.0)))
		if pr.has("obj"):
			# Format 14 : mis à l'échelle ou incliné.
			_prop_xf(pr, d, origin, yaw)
			continue
		if d.has("map"):
			_map_prefab(pr, d, origin, yaw)
			continue
		var copies: Array = d.get("copies", [[0, 0, 0]])
		for i in copies.size():
			var cp: Array = copies[i]
			var p := origin + Basis(Vector3.UP, yaw) * Vector3(cp[0], 0, cp[1])
			var e := {"id": "%s_%d" % [pr.eid, i] if copies.size() > 1 else String(pr.eid), "p": _v3(p), "yaw": _r(yaw + float(cp[2]))}
			if d.has("model"):
				e["model"] = String(d.model)
				if d.has("scale"):
					e["scale"] = float(d.scale)
				if d.has("remap"):
					e["remap"] = d.remap
				# Collisions du modèle (<modèle>.collision.json) seulement s'il
				# bloque et que le catalogue n'en donne pas.
				if block == "non" or d.has("boxes"):
					e["nocollide"] = true
			else:
				e["build"] = String(d.build)
			props.append(e)
		if block != "non" and d.has("boxes"):
			_blockers_of(d.boxes, origin, yaw, block == "barriere", String(d.get("surface", "concrete")))


## Base 3 × 3 -> 9 nombres (colonnes x, y, z), clé « basis » de la description.
static func basis9(b: Basis) -> Array:
	var out := []
	for c in [b.x, b.y, b.z]:
		out.append_array([snappedf(c.x, 0.0001), snappedf(c.y, 0.0001), snappedf(c.z, 0.0001)])
	return out


## Orientation d'un objet de la description : « basis » (`b`, rotation ×
## échelle) quand la base n'est pas un simple lacet uniforme (`plain` faux),
## sinon « yaw » et « scale » comme avant le format 14.
func _put_xf(e: Dictionary, b: Basis, plain: bool, yaw: float, scale: float) -> void:
	if plain:
		e["yaw"] = _r(yaw)
		if absf(scale - 1.0) > 0.0001:
			e["scale"] = snappedf(scale, 0.0001)
	else:
		e["basis"] = basis9(b)


## Format 14 (docs/EDITOR_SCALE_ROTATE.md § 5.2) : décor mis à l'échelle ou
## incliné (MapScale). Base complète = orientation (lacet du mur, du plafond
## ou Rz · Ry · Rx au sol) × échelle dans le repère de l'objet ; au sol,
## l'origine du modèle est décalée pour que son point le plus bas reste à
## sa hauteur de pose. Collisions : ses pavés (catalogue, sinon
## <modèle>.collision.json, sinon ceux du prefab de la carte), mis à
## l'échelle et orientés avec lui (CollisionBox, jamais le modèle) ; incliné
## et bloquant, son emprise au sol projetée est retirée du navmesh.
func _prop_xf(pr: Dictionary, d: Dictionary, origin: Vector3, yaw: float) -> void:
	var o: Dictionary = pr.obj
	var rot := Basis(Vector3.UP, yaw)
	var floor_mount := String(pr.get("mount", "")) == ""
	if floor_mount:
		rot = MapScale.game_basis(o)
		origin += MapScale.floor_offset(o)
	var gs := MapScale.game_scale(o)
	var full := rot * Basis.from_scale(gs)
	var tilted := floor_mount and MapScale.is_tilted(o)
	var plain := not tilted and MapScale.is_uniform(gs)
	var block := String(d.bloque)
	var surface := String(d.get("surface", "concrete"))
	if d.has("map"):
		var pid := String(d.map)
		if d.has("modele"):
			var md2: Dictionary = d.modele
			var e := {"id": String(pr.eid), "p": _v3(origin + full * MapPrefabLib.model_offset(d)), "map_model": pid,
				"sig": String(md2.sha256).left(16), "aabb": md2.aabb}
			_put_xf(e, full * float(md2.echelle), plain, yaw, gs.x * float(md2.echelle))
			props.append(e)
			if md.map_models.has(pid):
				map_models[pid] = md.map_models[pid]
		else:
			var parts: Array = d.get("parties", [])
			for i in parts.size():
				var part: Dictionary = parts[i]
				var cd: Dictionary = MapCatalog.PREFABS.get(String(part.decor), {})
				if cd.is_empty():
					continue
				var pp: Array = part.pos
				var prot := -deg_to_rad(float(part.get("rot", 0)))
				var po := origin + full * Vector3(float(pp[0]), 0.0, float(pp[1]))
				var pb := full * Basis(Vector3.UP, prot)
				_copies(cd, "%s_%d" % [pr.eid, i], po, pb, plain, yaw + prot, gs.x, true)
	else:
		_copies(d, String(pr.eid), origin, full, plain, yaw, gs.x, false)
	if block == "non":
		return
	var boxes: Array = d.get("boxes", []) if (d.has("boxes") or d.has("map")) else MapPrefabLib.catalog_boxes(String(pr.prefab))
	for bx in boxes:
		var sb := MapScale.scaled_box(o, bx)
		var e := {"center": _v3(origin + rot * (sb.center as Vector3)), "size": _v3(sb.size), "barrier": block == "barriere" or bool(bx.get("barrier", false)),
			"surface": surface}
		if tilted:
			e["basis"] = basis9(rot * Basis(Vector3.UP, float(sb.yaw)))
		else:
			e["yaw"] = _r(yaw + float(sb.yaw))
		blockers.append(e)
	if tilted:
		var k: int = pr.floor
		var poly := []
		for q in MapScale.ground_poly(o):
			poly.append([_r(q.x + MapGeom.WORLD_OFFSET), _r(q.y + MapGeom.WORLD_OFFSET)])
		nav_blocks.append({"poly": poly, "y": _r(md.floors[k].sol + MapVertical.decor_z(o)), "h": _r(MapScale.height(o))})


## Objets d'un décor du catalogue (ses « copies ») à l'origine `origin`, de
## base `b` (rotation × échelle), pour _prop_xf. `part` : partie d'un prefab
## groupe (identifiants « <eid>_<partie>_<copie> », jamais de collision propre).
func _copies(cd: Dictionary, base_id: String, origin: Vector3, b: Basis, plain: bool, yaw: float, s: float, part: bool) -> void:
	var copies: Array = cd.get("copies", [[0, 0, 0]])
	for j in copies.size():
		var cp: Array = copies[j]
		var eid := "%s_%d" % [base_id, j] if (part or copies.size() > 1) else base_id
		var e := {"id": eid, "p": _v3(origin + b * Vector3(float(cp[0]), 0.0, float(cp[1])))}
		var ms := float(cd.get("scale", 1.0)) if cd.has("model") else 1.0
		_put_xf(e, b * Basis(Vector3.UP, float(cp[2])) * ms, plain, yaw + float(cp[2]), s * ms)
		if cd.has("model"):
			e["model"] = String(cd.model)
			if cd.has("remap"):
				e["remap"] = cd.remap
			# Collisions : les pavés mis à l'échelle (blockers), jamais le modèle.
			e["nocollide"] = true
		else:
			e["build"] = String(cd.build)
		props.append(e)


## Modèles des prefabs de la carte posés (pid -> base64) : « map_models ».
var map_models: Dictionary = {}


## Prefab de la carte posé (format 10, MapPrefabLib) : groupe -> chaque partie
## comme le décor du catalogue (modèle ou objet construit, à sa place et sa
## rotation dans le prefab, sans collision propre) ; modèle importé -> un objet
## « map_model » (son .glb, décalé pour être centré et posé au sol, à son
## échelle). Collision : les pavés du prefab (CollisionBox), jamais le modèle.
func _map_prefab(pr: Dictionary, d: Dictionary, origin: Vector3, yaw: float) -> void:
	var pid := String(d.map)
	var basis := Basis(Vector3.UP, yaw)
	if d.has("modele"):
		var md2: Dictionary = d.modele
		var e := {"id": String(pr.eid), "p": _v3(origin + basis * MapPrefabLib.model_offset(d)), "yaw": _r(yaw),
			"map_model": pid, "sig": String(md2.sha256).left(16), "aabb": md2.aabb}
		if absf(float(md2.echelle) - 1.0) > 0.0001:
			e["scale"] = float(md2.echelle)
		props.append(e)
		if md.map_models.has(pid):
			map_models[pid] = md.map_models[pid]
	else:
		var parts: Array = d.get("parties", [])
		for i in parts.size():
			var part: Dictionary = parts[i]
			var cd: Dictionary = MapCatalog.PREFABS.get(String(part.decor), {})
			if cd.is_empty():
				continue
			var pp: Array = part.pos
			var pyaw := yaw - deg_to_rad(float(part.get("rot", 0)))
			var po := origin + basis * Vector3(float(pp[0]), 0.0, float(pp[1]))
			var copies: Array = cd.get("copies", [[0, 0, 0]])
			for j in copies.size():
				var cp: Array = copies[j]
				var e := {"id": "%s_%d_%d" % [pr.eid, i, j], "p": _v3(po + Basis(Vector3.UP, pyaw) * Vector3(cp[0], 0, cp[1])), "yaw": _r(pyaw + float(cp[2]))}
				if cd.has("model"):
					e["model"] = String(cd.model)
					if cd.has("scale"):
						e["scale"] = float(cd.scale)
					if cd.has("remap"):
						e["remap"] = cd.remap
					e["nocollide"] = true
				else:
					e["build"] = String(cd.build)
				props.append(e)
	if String(d.bloque) != "non":
		_blockers_of(d.get("boxes", []), origin, yaw, String(d.bloque) == "barriere", String(d.get("surface", "concrete")))
## Effets posés (format 10) : point d'origine dans le monde (au sol, surélevé,
## sur la face d'un mur ou sous le plafond de la pièce), lacet, distance au
## sol (étincelles qui rebondissent, gouttes), réglages bornés. Au plus
## MapCatalog.MAX_EFFECTS (le reste est ignoré).
func _effects() -> void:
	for fx in md.effects:
		if effects.size() >= MapCatalog.MAX_EFFECTS:
			break
		var k: int = fx.floor
		var c: Vector2 = fx.center
		var cell := Vector2i(floori(c.x / MapGeom.CELL), floori(c.y / MapGeom.CELL))
		var room_h: float = float(ceil_at(k, cell)[0]) - float(md.floors[k].sol)
		# Au plafond : descente sous le plafond (format 12) ; mural : toujours
		# sous le plafond de la pièce (les mêmes que l'éditeur, MapVertical).
		var y := MapVertical.effect_ground(String(fx.mount), float(fx.y), float(fx.get("descente", 0.0)), room_h, MapCatalog.effect_anchor(String(fx.effet)))
		var z: Vector3 = fx.zone
		var e := {"fx": String(fx.effet), "p": _v3(_world(k, c, y)), "yaw": _r(float(fx.yaw)), "ground": _r(maxf(0.0, y)),
			"room_h": _r(room_h), "intensity": _r(float(fx.intensity)), "zone": [_r(z.x), _r(z.y), _r(z.z)], "eid": String(fx.eid)}
		if String(fx.color) != "":
			e["color"] = String(fx.color)
		effects.append(e)


## Barrières invisibles : une collision chacune, sur la couche BARRIER
## (joueurs et zombies arrêtés, navmesh cuit autour ; balles et grenades
## passent), du sol jusqu'au plafond du niveau (ou sa hauteur), JAMAIS de
## maillage en jeu. Format 9 : « poly » = les sommets du polygone en x, z
## autour de « center » (CollisionBox en fait un prisme, une forme convexe par
## morceau) ; « size » = son rectangle englobant et la hauteur. « clip » et
## « eid » : l'aperçu 3D peut les montrer (MapPreviewBuilder) ;
## CollisionBox.from_dict les ignore.
func _clips() -> void:
	for cl in md.clips:
		var k: int = cl.floor
		var sol: float = md.floors[k].sol
		var h := float(cl.h)
		if h <= 0.0:
			# Jusqu'au plafond réel de la pièce (au milieu de la barrière), plus
			# le haut du niveau (docs/EDITOR_VIEWS.md § 1.2 : incohérence corrigée).
			var cc: Vector2 = cl.center
			h = maxf(float(ceil_at(k, Vector2i(floori(cc.x / MapGeom.CELL), floori(cc.y / MapGeom.CELL)))[0]) - sol, 2.0)
		var sz: Vector2 = cl.size
		var c: Vector2 = cl.center
		var local := []
		for p: Vector2 in cl.poly:
			local.append([_r(p.x - c.x), _r(p.y - c.y)])
		blockers.append({"center": _v3(_world(k, c, h * 0.5)), "size": [_r(sz.x), _r(h), _r(sz.y)],
			"yaw": 0.0, "poly": local, "barrier": true, "surface": "concrete", "clip": true, "eid": String(cl.eid)})


## Garde-corps : bord d'un plancher de niveau sur un vide (sauf en haut d'escalier).
func _rails(f: MapValidator.Floor) -> void:
	var k := f.index
	if k == 0:
		return
	var skip := {}
	for s in md.stairs:
		if int(s.get("to", -1)) == k:
			# Bord du palier vers les marches (droites ou tournées) : pas de garde-corps.
			for c in s.links:
				for t in s.links[c]:
					var d: Vector2i = c - t
					skip["%d:%d:%d:%d" % [t.x, t.y, d.x, d.y]] = true
	var lines := {}   # "v:x" / "h:z" -> [[début, fin]] (cases)
	for y in f.h:
		for x in f.w:
			var c := Vector2i(x, y)
			if not f.at(c) in [Kd.SOL, Kd.MARQUEUR, Kd.PORTE, Kd.DEBRIS]:
				continue
			for d in MapValidator.DIRS:
				if f.at(c + d) != Kd.TREMIE or skip.has("%d:%d:%d:%d" % [x, y, d.x, d.y]):
					continue
				if d.x != 0:
					lines.get_or_add("v:%d" % (x + (1 if d.x > 0 else 0)), []).append([y, y + 1])
				else:
					lines.get_or_add("h:%d" % (y + (1 if d.y > 0 else 0)), []).append([x, x + 1])
	var keys := lines.keys()
	keys.sort()
	for key in keys:
		var runs: Array = lines[key]
		runs.sort()
		var merged := []
		for r in runs:
			if not merged.is_empty() and r[0] <= merged[-1][1]:
				merged[-1][1] = maxi(merged[-1][1], r[1])
			else:
				merged.append([r[0], r[1]])
		var at := int(String(key).substr(2))
		for m in merged:
			var path := [[wx(at), wx(m[0])], [wx(at), wx(m[1])]] if String(key).begins_with("v") else [[wx(m[0]), wx(at)], [wx(m[1]), wx(at)]]
			rails.append({"room": ref_room.get(k, "x"), "path": path, "y": _r(f.sol), "h": 1.0, "mat": "dark_wood"})


func _stairs() -> void:
	for s in md.stairs:
		var k: int = s.floor
		# Niveau d'arrivée (format 17 : n'importe quel niveau au-dessus du pied).
		var kt: int = int(s.get("to", k + 1))
		# Type et réglages (format 6) : clés de la description seulement s'ils
		# ne sont pas ceux d'avant (une carte d'avant garde sa description).
		var opts: Dictionary = md.stair_opts.get(String(s.get("key", "")), {})
		if s.has("diag") and s.diag.get("shaped", false):
			# En L, en U, en colimaçon : l'emprise de ses cases (MapRaster.stair_spec),
			# sens de montée donné.
			var sp := MapRaster.stair_spec(s.diag.obj, md.floors[k].sol, md.floors[kt].sol)
			var fa: Array = _xz(Vector2(float(sp.a[0]), float(sp.a[2])))
			var fb: Array = _xz(Vector2(float(sp.b[0]), float(sp.b[2])))
			var e := {"room": ref_room.get(k, "x"), "a": [fa[0], _r(md.floors[k].sol), fa[1]],
				"b": [fb[0], _r(md.floors[kt].sol), fb[1]], "w": _r(float(sp.w)), "mat": "wood"}
			e.merge(opts)
			stairs.append(e)
			continue
		if s.has("diag"):
			# Escalier tourné : du milieu du pied au milieu du haut des marches
			# (0,25 m en retrait du contour tracé, comme sur la grille).
			var info: Dictionary = s.diag
			var u: Vector2 = info.up
			var sz: Vector2 = info.size
			var along_x := absf(Vector2(1, 0).rotated(deg_to_rad(float(info.rot))).dot(u)) > 0.7
			var half_run := (sz.x if along_x else sz.y) * 0.5 - MapGeom.WALL_HALF
			var tread := (sz.y if along_x else sz.x) - MapGeom.CELL
			var c: Vector2 = info.center
			var foot: Array = _xz(c - u * half_run)
			var head: Array = _xz(c + u * half_run)
			var ed := {"room": ref_room.get(k, "x"), "a": [foot[0], _r(md.floors[k].sol), foot[1]],
				"b": [head[0], _r(md.floors[kt].sol), head[1]], "w": _r(tread), "mat": "wood"}
			ed.merge(opts)
			stairs.append(ed)
			continue
		var r: Rect2i = s.rect
		var d: Vector2i = s.up
		var mid := Vector2(r.position) + Vector2(r.size) * 0.5
		var a := mid
		var b := mid
		if d.x != 0:
			a.x = r.end.x if d.x < 0 else r.position.x
			b.x = r.position.x if d.x < 0 else r.end.x
		else:
			a.y = r.end.y if d.y < 0 else r.position.y
			b.y = r.position.y if d.y < 0 else r.end.y
		var eg := {"room": ref_room.get(k, "x"), "a": [wx(a.x), _r(md.floors[k].sol), wx(a.y)],
			"b": [wx(b.x), _r(md.floors[kt].sol), wx(b.y)], "w": _r(s.width * S), "mat": "wood"}
		eg.merge(opts)
		stairs.append(eg)


func _p(k: int, v: Vector2, dy := 0.0) -> Array:
	return [wx(v.x), _r(md.floors[k].sol + dy), wx(v.y)]


func _wall_item(it: Dictionary) -> Dictionary:
	if it.has("oblique"):
		# Mur en biais : direction exacte du mur (vecteur unitaire).
		return {"p": _p(it.floor, it.face), "wall": [_r(it.wall.x), 0, _r(it.wall.y)]}
	return {"p": _p(it.floor, it.face), "wall": [it.wall.x, 0, it.wall.y]}


func _markers() -> Dictionary:
	var m := {"player_spawns": [], "zombie_spawns": [], "doors": [], "box": [], "traps": [], "windows": [], "lamps": []}
	# Départ, regard vers le milieu de la zone de départ.
	var mean := Vector2.ZERO
	for p in md.start_points:
		m.player_spawns.append(_p(p[0], p[1], 0.05))
		mean += p[1]
	var cz := Vector2.ZERO
	var nz := 0
	# Carte invalide sans départ (export d'une carte refusée par le
	# validateur) : regard par défaut au lieu d'un index hors bornes.
	if not md.start_points.is_empty():
		mean /= md.start_points.size()
		var f0 := md.floors[md.start_points[0][0]]
		for y in f0.h:
			for x in f0.w:
				if f0.zone_of(Vector2i(x, y)) == "a" and f0.at(Vector2i(x, y)) == Kd.SOL:
					cz += Vector2(x + 0.5, y + 0.5)
					nz += 1
	var look := cz / maxi(nz, 1) - mean
	m["player_yaw"] = _r(atan2(-look.x, -look.y)) if look.length() > 2.0 else PI
	# Fenêtres et apparitions derrière elles.
	for w in md.windows:
		var ww := md._world_window(w)
		var p: Vector3 = ww.p
		var sp: Vector3 = ww.spawn
		var inn: Array = [_r(w.inward.x), 0, _r(w.inward.y)] if w.has("oblique") else [w.inward.x, 0, w.inward.y]
		var bk := String(w.get("kind", "fenetre"))
		var wj := {"p": [_r(p.x), _r(p.y), _r(p.z)], "in": inn, "h": MapValidator.LINTEL, "zone": w.zone}
		var sps: Array = [sp]
		if bk != "fenetre":
			# Porte à zombies (format 8) : type, largeur, hauteur de l'ouverture.
			wj["kind"] = bk
			wj["w"] = MapCatalog.barricade_width(bk)
			wj["h"] = MapValidator.ZOMBIE_DOOR_TOP
			if bk == "porte_double":
				# Une apparition derrière chaque battant.
				var side := Vector3(-ww["in"].z, 0, ww["in"].x)
				sps = [sp - side * Barricade.DOUBLE_SPAWN_SIDE, sp + side * Barricade.DOUBLE_SPAWN_SIDE]
		wj["spawns"] = sps.map(func(q: Vector3): return [_r(q.x), _r(q.y), _r(q.z)])
		m.windows.append(wj)
		for q: Vector3 in sps:
			m.zombie_spawns.append({"p": [_r(q.x), _r(q.y), _r(q.z)], "zone": w.zone})
	for it in md.floor_items:
		if it.base == "apparition":
			m.zombie_spawns.append({"p": _p(it.floor, it.center), "zone": it.zone})
	# Portes.
	for d in md.doors:
		var r: Rect2i = d.rect
		var thick := r.size.x if d.axis.x != 0 else r.size.y
		var dj := {"id": d.id, "p": _p(d.floor, Vector2(r.position) + Vector2(r.size) * 0.5), "yaw": _r(PI / 2.0) if d.axis.x != 0 else 0.0,
			"w": _r(d.width * S), "h": _r(md.door_height), "depth": _r(thick * S + 0.5), "cost": d.cost, "zones": d.zones}
		if d.has("oblique"):
			# Mur en biais : milieu exact sur le trait, porte tournée comme le mur.
			var t: Vector2 = d.t
			dj["p"] = _p(d.floor, Vector2(d.p) / S + Vector2(0.5, 0.5))
			dj["yaw"] = _r(atan2(-t.y, t.x))
			dj["depth"] = _r(MapGeom.WALL_HALF * 2.0 + 0.5)
		if d.debris:
			dj["debris"] = true
		if d.power:
			dj["power"] = true
		# Format 5 : aspect choisi dans l'éditeur (absent : aspect par défaut).
		if md.variants.has(String(d.get("eid", ""))):
			dj["variant"] = String(md.variants[String(d.eid)])
		m.doors.append(dj)
	# Objets muraux (ordre de lecture de la grille).
	var box_key := _box_key()
	for it in md.wall_items:
		var wi := _wall_item(it)
		if String(it.base) in MapCatalog.REMOVED_TYPES:
			# Atouts, armes murales, grenades, Pack-a-Punch : retirés du jeu
			# (EditorMap.strip_removed les retire déjà à la lecture).
			push_warning("[MapLayoutExport] objet retiré du jeu ignoré : %s" % it.key)
			continue
		match it.base:
			"boite", "boite_depart":
				# Caisse au hasard : une seule (_box_key) ; les autres sont ignorées.
				if String(it.key) != box_key:
					push_warning("[MapLayoutExport] caisse au hasard en trop ignorée (une seule par carte) : %s" % it.key)
					continue
				if it.get("floor_box", false):
					# Format 15 : caisse posée au sol (mur fictif derrière elle,
					# MapValidator._floor_box_marker) ; son emprise est retirée
					# du navmesh des zombies.
					wi["floor"] = true
					var poly := []
					for q in MapGeom.rot_rect_poly(it.box_center, Vector2(MysteryBox.BODY_SIZE.x, MysteryBox.BODY_SIZE.z), float(it.rot)):
						poly.append(_xz(q))
					nav_blocks.append({"poly": poly, "y": _r(md.floors[it.floor].sol), "h": MysteryBox.BODY_SIZE.y})
				m.box.append(wi)
			"courant":
				m["power"] = wi
			"evacuation":
				# Format 18 : porte d'évacuation (MeshMapLayout.evac_door).
				m["evac"] = wi
			"station":
				# Format 19 : station de construction (MeshMapLayout.build_station).
				m["station"] = wi
			"poste_central":
				m["_mainframe"] = wi
	# Pièges : zone au sol, un ou deux leviers.
	for it in md.floor_items:
		if it.base != "piege":
			continue
		var r: Rect2i = it.rect
		var sol: float = md.floors[it.floor].sol
		var lv: Array = it.get("levers", [])
		if lv.is_empty():
			# Zone sans levier (carte pas encore vérifiée : aperçu 3D) : pas de
			# piège, jamais d'erreur (une erreur de script dans le fil de
			# l'aperçu peut planter le jeu exporté).
			continue
		var t := {"id": "trap_%d" % (m.traps.size() + 1), "lever": _wall_item(lv[0]),
			"area": [wx(r.position.x), _r(sol), wx(r.position.y), wx(r.end.x), _r(sol + 2.5), wx(r.end.y)],
			"active": 40.0, "cooldown": 60.0}
		var tg: Dictionary = md.diag_traps.get(String(md.eid_of.get(it.key, "")), {})
		if not tg.is_empty():
			# Zone tournée ou hors de la grille : le vrai rectangle (0,25 m en
			# retrait du contour, comme sur la grille), tourné autour de son centre.
			var c: Array = _xz(tg.center)
			var h: Vector2 = (Vector2(tg.size) - Vector2.ONE * MapGeom.CELL).max(Vector2.ONE * MapGeom.CELL) * 0.5
			t["area"] = [_r(c[0] - h.x), _r(sol), _r(c[1] - h.y), _r(c[0] + h.x), _r(sol + 2.5), _r(c[1] + h.y)]
			t["yaw"] = _r(-deg_to_rad(float(tg.rot)))
		if lv.size() > 1:
			t["lever2"] = _wall_item(lv[1])
		m.traps.append(t)
	# Téléporteur.
	var pad: Variant = null
	var exit: Variant = null
	for it in md.floor_items:
		if it.base == "teleporteur":
			pad = it
		elif it.base == "arrivee":
			exit = it
	if pad != null and exit != null:
		var tp := {"pad": _p(pad.floor, pad.center), "exit": _p(exit.floor, exit.center, 0.05), "exit_zone": exit.zone}
		if m.has("_mainframe"):
			tp["mainframe"] = m._mainframe
		m["teleporter"] = tp
	m.erase("_mainframe")
	m.lamps = _lamps() if md.lamps_auto else []
	for l in md.lamps_extra:
		if l.has("luminaire"):
			m.lamps.append(_fixture(l))
		else:
			m.lamps.append(_lamp(int(l.floor), Vector2i(floori(l.center.x), floori(l.center.y))))
	return m


## Luminaire posé : lumière (couleur, intensité, portée, courant, vacillement)
## et son objet (« fixture » : EditorPrefabs.fixture), à la hauteur de son
## montage (plafond, mur, sol ou dessus d'un meuble).
func _fixture(l: Dictionary) -> Dictionary:
	var d: Dictionary = MapCatalog.LIGHTS.get(String(l.luminaire), {})
	var k := int(l.floor)
	var c: Vector2 = l.center
	var cell := Vector2i(floori(c.x), floori(c.y))
	var sol: float = md.floors[k].sol
	var fix_y := 0.0   # hauteur de l'objet (m au-dessus du sol)
	var light_y := 0.0
	match String(l.mount):
		"plafond":
			var h: float = float(ceil_at(k, cell)[0]) - sol
			# Format 12 : descente choisie ; l'objet descend avec la lumière
			# au-delà de son `drop` (jamais au-dessus du plafond).
			var drop := float(d.get("drop", 0.4))
			var desc := float(l.get("descente", drop))
			fix_y = h - maxf(0.0, desc - drop)
			light_y = h - desc
		"mur":
			# Hauteur choisie (format 7), toujours sous le plafond de la pièce.
			fix_y = float(l.get("y", d.get("y", 2.0)))
			fix_y = clampf(fix_y, MapCatalog.WALL_LIGHT_HEIGHT[0], maxf(MapCatalog.WALL_LIGHT_HEIGHT[0], float(ceil_at(k, cell)[0]) - sol - 0.15))
			light_y = fix_y
		_:
			fix_y = float(l.get("support", 0.0))
			light_y = fix_y + float(d.get("y", 0.5))
	var at := Vector2(wx(c.x), wx(c.y))
	var pl := Vector3(at.x, sol + light_y, at.y)
	if String(l.mount) == "mur":
		# La lumière devant l'applique (0,2 m du mur), pas dans le mur.
		var wv := Vector2(l.wall)
		pl -= Vector3(wv.x, 0, wv.y) * 0.2
	var col: Color = l.color
	var e := {"p": _v3(pl), "range": _r(float(l.range)), "energy": _r(float(l.energy) * 1.4), "color": col.to_html(false),
		"power": bool(l.power), "flicker": bool(l.flicker), "fixture": String(l.luminaire),
		"fixture_p": _v3(Vector3(at.x, sol + fix_y, at.y)), "yaw": _r(float(l.yaw))}
	var boxes: Array = l.get("boxes", [])
	if not boxes.is_empty() and String(d.get("bloque", "non")) != "non":
		_blockers_of(boxes, Vector3(at.x, sol + fix_y, at.y), float(l.yaw), bool(l.barrier), "metal")
	return e


## Lampes : une grille de 6 m par zone et par niveau, sous le plafond.
func _lamps() -> Array:
	var out := []
	var step := roundi(6.0 / S)
	for f in md.floors:
		var k := f.index
		for z in md.zones:
			var cells := []
			var lo := Vector2i(f.w, f.h)
			var hi := Vector2i(-1, -1)
			for y in f.h:
				for x in f.w:
					var c := Vector2i(x, y)
					if _lamp_zone(f, c) == z:
						cells.append(c)
						lo = Vector2i(mini(lo.x, x), mini(lo.y, y))
						hi = Vector2i(maxi(hi.x, x), maxi(hi.y, y))
			if cells.is_empty():
				continue
			var got := 0
			var nx := maxi(1, roundi(float(hi.x - lo.x + 1) / step))
			var ny := maxi(1, roundi(float(hi.y - lo.y + 1) / step))
			for iy in ny:
				for ix in nx:
					var c := Vector2i(lo.x + int((ix + 0.5) * (hi.x - lo.x + 1) / nx), lo.y + int((iy + 0.5) * (hi.y - lo.y + 1) / ny))
					if _lamp_zone(f, c) != z:
						continue
					out.append(_lamp(k, c))
					got += 1
			if got == 0:
				var mean := Vector2.ZERO
				for c in cells:
					mean += Vector2(c)
				mean /= cells.size()
				cells.sort_custom(func(a, b): return (Vector2(a) - mean).length() < (Vector2(b) - mean).length())
				out.append(_lamp(k, cells[0]))
	return out


## Zone d'une case qui reçoit une lampe automatique ("" : aucune) : sol libre
## ou objet posé, et sol sous une barrière invisible (la lampe est au
## plafond : poser une barrière ne retire ni ne déplace les lampes).
func _lamp_zone(f: MapValidator.Floor, c: Vector2i) -> String:
	# Ciel ouvert (pièce sans plafond) : pas de lampe automatique.
	if MapVertical.open_at(md, f.index, c):
		return ""
	if f.at(c) in [Kd.SOL, Kd.MARQUEUR]:
		return f.zone_of(c)
	if md._under_clip(f, c):
		return String(md.room_zone.get(f.room_of(c), ""))
	return ""


func _lamp(k: int, c: Vector2i) -> Dictionary:
	var ce: float = ceil_at(k, c)[0]
	var h := ce - md.floors[k].sol
	return {"p": _p(k, Vector2(c) + Vector2(0.5, 0.5), h - 0.35), "range": _r(clampf(h * 1.6 + 4.0, 8.0, 13.0)), "energy": 2.2}


## Cours des zombies derrière les fenêtres : sol, plafond bas, trois murs.
func _pockets() -> void:
	for i in md.windows.size():
		var w: Dictionary = md.windows[i]
		var k: int = w.floor
		var sol: float = md.floors[k].sol
		if w.has("oblique"):
			_pocket_oblique(i, w, k, sol)
			continue
		var r: Rect2i = w.pocket
		var x0 := wx(r.position.x)
		var x1 := wx(r.end.x)
		var z0 := wx(r.position.y)
		var z1 := wx(r.end.y)
		var room := {"id": "dehors_%d" % i, "outline": _outline(r), "floor": _r(sol), "ceiling": _r(sol + MapValidator.POCKET_HEIGHT),
			"floor_mat": "cobble", "ceiling_mat": "ceiling"}
		if k > 0:
			room["floor_slab"] = MapValidator.DALLE
		rooms.append(room)
		var inn: Vector2i = w.inward
		var path := []
		if inn == Vector2i(0, 1):
			path = [[x0, z1], [x0, z0], [x1, z0], [x1, z1]]
		elif inn == Vector2i(0, -1):
			path = [[x0, z0], [x0, z1], [x1, z1], [x1, z0]]
		elif inn == Vector2i(1, 0):
			path = [[x1, z0], [x0, z0], [x0, z1], [x1, z1]]
		else:
			path = [[x0, z0], [x1, z0], [x1, z1], [x0, z1]]
		walls.append({"room": "dehors_%d" % i, "path": path, "y0": _r(sol - (0.25 if k == 0 else MapValidator.DALLE)),
			"y1": _r(sol + MapValidator.POCKET_HEIGHT), "thick": 0.3, "mat": "brick", "openings": []})


## Cour d'une fenêtre sur un mur en biais : sol et plafond tournés comme le
## mur (de sa face extérieure à 2,75 m du trait, 3 m de large), trois murs.
func _pocket_oblique(i: int, w: Dictionary, k: int, sol: float) -> void:
	var poly: PackedVector2Array = w.pocket_poly
	var outline := []
	for q in poly:
		outline.append(_xz(q))
	var room := {"id": "dehors_%d" % i, "outline": outline, "floor": _r(sol), "ceiling": _r(sol + MapValidator.POCKET_HEIGHT),
		"floor_mat": "cobble", "ceiling_mat": "ceiling"}
	if k > 0:
		room["floor_slab"] = MapValidator.DALLE
	rooms.append(room)
	# oriented_rect : [face - t, face + t, fond + t, fond - t] ; le côté de la face reste ouvert.
	walls.append({"room": "dehors_%d" % i, "path": [_xz(poly[1]), _xz(poly[2]), _xz(poly[3]), _xz(poly[0])],
		"y0": _r(sol - (0.25 if k == 0 else MapValidator.DALLE)), "y1": _r(sol + MapValidator.POCKET_HEIGHT), "thick": 0.3, "mat": "brick", "openings": []})


## Clé de la seule caisse au hasard exportée : celle marquée « depart »
## (carte d'avant), sinon la première ; "" s'il n'y en a pas. Une carte
## d'avant à plusieurs boîtes reste jouable : les autres sont ignorées.
func _box_key() -> String:
	var first := ""
	for it in md.wall_items:
		if it.base == "boite_depart":
			return String(it.key)
		if it.base == "boite" and first == "":
			first = String(it.key)
	return first


func _map_def() -> Dictionary:
	var doors := {}
	for d in md.doors:
		doors[d.id] = {"cost": d.cost}
	var names := {}
	for z in md.zones:
		names[z] = String(md.zone_names.get(z, "Zone " + z.to_upper()))
	var has_mainframe := md.wall_items.any(func(it): return it.base == "poste_central")
	var out := {
		"display_name": md.display_name if md.display_name != "" else md.id.to_upper(),
		"description": md.description, "music": md.music, "zone_names": names, "doors": doors,
		# Une seule caisse au hasard, fixe : toujours l'emplacement 0.
		"open_links": md.open_links, "box_start": 0,
		"teleporter_link": has_mainframe,
	}
	# Format 17 : ciel de la carte (noir complet par défaut), seulement s'il se
	# voit (une pièce au moins sans plafond) ; sinon le rendu reste celui d'avant.
	if rooms.any(func(r): return r.get("no_ceiling", false)):
		out["sky"] = {"type": String(md.sky.type), "luminosite": float(md.sky.get("luminosite", 1.0))}
	# Format 18 : schéma des vagues spéciales et de boss, seulement s'il n'est
	# pas celui par défaut (EditorMapDef le lit, MapDef.waves).
	if not WaveRules.is_default(md.waves):
		out["waves"] = WaveRules.parse(md.waves)
	return out
