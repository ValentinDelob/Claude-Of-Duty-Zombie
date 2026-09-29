class_name MapLayoutExport
extends RefCounted
## Description de carte en maillage tirée d'une carte de l'éditeur validée
## (MapValidator) : même format que assets/maps/kino/layout.json, lu par
## MeshMapLayout (jeu) et construit par MeshMapGeometry (ou, pour les cartes
## faites dans Blender, tools/blender/mesh_map.py). Salles (sols, plafonds,
## dalles d'étage), blocs (murs, allèges, linteaux, décor), garde-corps,
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
var zone_boxes: Array = []   # [étage, volume, zone, boîte]
var ref_room: Dictionary = {}   # étage -> id d'une salle (hauteur de sol des murs)
var door_of: Array = []   # par étage : {Vector2i: porte}


static func build(v: MapValidator) -> Dictionary:
	var ex := MapLayoutExport.new()
	ex.md = v
	return ex._build()


func _r(v: float) -> float:
	return snappedf(v, 0.001)


func wx(px: float) -> float:
	return _r(MapValidator.ORIGIN + px * S)


func top(k: int) -> float:
	return md.floors[k + 1].sol - MapValidator.DALLE if k < n_floors - 1 else md.floors[k].plafond


## Plafond au-dessus d'une case : [hauteur, plafond dessiné (sinon : dessous de dalle)].
func ceil_at(k: int, c: Vector2i) -> Array:
	var own := md.floors[k].ceil_at(c)
	if k == n_floors - 1:
		return [own if own > 0.0 else top(k), true]
	var above := md.floors[k + 1].at(c)
	if above == Kd.TREMIE:
		return ceil_at(k + 1, c)
	if above == Kd.VIDE:
		return [own if own > 0.0 else top(k), true]
	return [md.floors[k + 1].sol - MapValidator.DALLE, false]


func wall_top(k: int, c: Vector2i) -> float:
	if k < n_floors - 1:
		var above := md.floors[k + 1].at(c)
		if above == Kd.TREMIE:
			return wall_top(k + 1, c)
		if above != Kd.VIDE:
			return top(k)
	var own := md.floors[k].ceil_at(c)
	return own if own > 0.0 else top(k)


func _wall_mat(f: MapValidator.Floor, c: Vector2i) -> String:
	var count := {}
	for d in MapValidator.DIRS:
		var z := f.zone_of(c + d)
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
	for f in md.floors:
		_walls(f)
		_rails(f)
	_decor()
	_stairs()
	var markers := _markers()
	_pockets()
	# Zones : boîtes des salles ; étages hauts d'abord, puis les plus petites.
	zone_boxes.sort_custom(func(a, b): return a[0] > b[0] if a[0] != b[0] else a[1] < b[1])
	var zones := {}
	var zone_order := []
	for zb in zone_boxes:
		zones.get_or_add(zb[2], {"boxes": []}).boxes.append(zb[3])
		zone_order.append({"zone": zb[2], "box": zb[3]})
	return {
		"id": md.id,
		"note": "Généré par l'éditeur de cartes (MapLayoutExport) - ne pas modifier à la main.",
		"rooms": rooms, "walls": walls, "blocks": blocks, "rails": rails, "stairs": stairs,
		"zones": zones, "zone_order": zone_order, "markers": markers, "map_def": _map_def(),
	}


func _rooms(f: MapValidator.Floor) -> void:
	var k := f.index
	var keys := PackedStringArray()
	keys.resize(f.w * f.h)
	var info := {}
	for y in f.h:
		for x in f.w:
			var c := Vector2i(x, y)
			if not md._walk(f, c):
				continue
			var ce := ceil_at(k, c)
			var key := ""
			if door_of[k].has(c):
				key = "porte%s|%s|%s" % [door_of[k][c].id, ce[0], ce[1]]
			else:
				key = "%s|%s|%s" % [f.zone_of(c), ce[0], ce[1]]
			keys[y * f.w + x] = key
			info[key] = [door_of[k][c].id if door_of[k].has(c) else "", f.zone_of(c), ce]
	var n := 0
	for rk in merge_rects(f.w, f.h, keys):
		var r: Rect2i = rk[0]
		var inf: Array = info[rk[1]]
		n += 1
		var zone: String = inf[1]
		var rid := ("porte%s_%d" % [inf[0], n]) if inf[0] != "" else ("%s%d_%d" % [zone, k, n])
		var room := {"id": rid, "outline": _outline(r), "floor": _r(f.sol), "ceiling": _r(inf[2][0]),
			"floor_mat": "wood" if inf[0] != "" else String(md.floor_mats.get(zone, "concrete")), "ceiling_mat": "ceiling"}
		if not inf[2][1]:
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


func _walls(f: MapValidator.Floor) -> void:
	var k := f.index
	var y0 := f.sol - (0.1 if k == 0 else MapValidator.DALLE)
	var main := PackedStringArray()
	var upper := PackedStringArray()
	main.resize(f.w * f.h)
	upper.resize(f.w * f.h)
	for y in f.h:
		for x in f.w:
			var c := Vector2i(x, y)
			var i := y * f.w + x
			var kd := f.at(c)
			if kd == Kd.MUR:
				# Décor bloquant : ses propres blocs (_decor), pas un mur.
				if f.key[i].begins_with("decor#"):
					continue
				main[i] = "%s|%s|%s" % [_wall_mat(f, c), y0, wall_top(k, c)]
			elif kd == Kd.FENETRE:
				# Allège et linteau autour de l'ouverture (hauteurs de Barricade).
				main[i] = "%s|%s|%s" % [_wall_mat(f, c), y0, f.sol + MapValidator.SILL]
				upper[i] = "%s|%s|%s" % [_wall_mat(f, c), f.sol + MapValidator.LINTEL, wall_top(k, c)]
			elif kd == Kd.PORTE or kd == Kd.DEBRIS:
				var ce: float = ceil_at(k, c)[0]
				if ce > f.sol + md.door_height + 0.05:
					upper[i] = "%s|%s|%s" % [_wall_mat(f, c), f.sol + md.door_height, ce]
	for grid in [main, upper]:
		for rk in merge_rects(f.w, f.h, grid):
			var r: Rect2i = rk[0]
			var p: PackedStringArray = String(rk[1]).split("|")
			blocks.append({"room": ref_room.get(k, "x"), "box": [wx(r.position.x), _r(p[1].to_float()), wx(r.position.y),
				wx(r.end.x), _r(p[2].to_float()), wx(r.end.y)], "mat": p[0]})


## Décor bloquant (caisses, barils) : un bloc plein à sa hauteur.
func _decor() -> void:
	for d in md.decor:
		var r: Rect2i = d.rect
		var sol: float = md.floors[d.floor].sol
		blocks.append({"room": ref_room.get(d.floor, "x"), "box": [wx(r.position.x), _r(sol), wx(r.position.y),
			wx(r.end.x), _r(sol + float(d.h)), wx(r.end.y)], "mat": String(d.mat)})


## Garde-corps : bord d'un plancher d'étage sur un vide (sauf en haut d'escalier).
func _rails(f: MapValidator.Floor) -> void:
	var k := f.index
	if k == 0:
		return
	var skip := {}
	for s in md.stairs:
		if s.floor == k - 1:
			for t in MapValidator._side(s.rect, s.up):
				skip["%d:%d:%d:%d" % [t.x, t.y, -s.up.x, -s.up.y]] = true
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
		var r: Rect2i = s.rect
		var d: Vector2i = s.up
		var k: int = s.floor
		var mid := Vector2(r.position) + Vector2(r.size) * 0.5
		var a := mid
		var b := mid
		if d.x != 0:
			a.x = r.end.x if d.x < 0 else r.position.x
			b.x = r.position.x if d.x < 0 else r.end.x
		else:
			a.y = r.end.y if d.y < 0 else r.position.y
			b.y = r.position.y if d.y < 0 else r.end.y
		stairs.append({"room": ref_room.get(k, "x"), "a": [wx(a.x), _r(md.floors[k].sol), wx(a.y)],
			"b": [wx(b.x), _r(md.floors[k + 1].sol), wx(b.y)], "w": _r(s.width * S), "mat": "wood"})


func _p(k: int, v: Vector2, dy := 0.0) -> Array:
	return [wx(v.x), _r(md.floors[k].sol + dy), wx(v.y)]


func _wall_item(it: Dictionary) -> Dictionary:
	return {"p": _p(it.floor, it.face), "wall": [it.wall.x, 0, it.wall.y]}


func _markers() -> Dictionary:
	var m := {"player_spawns": [], "zombie_spawns": [], "doors": [], "wall_buys": [], "perks": [],
		"grenade_buys": [], "box": [], "traps": [], "windows": [], "lamps": []}
	# Départ, regard vers le milieu de la zone de départ.
	var mean := Vector2.ZERO
	for p in md.start_points:
		m.player_spawns.append(_p(p[0], p[1], 0.05))
		mean += p[1]
	mean /= md.start_points.size()
	var cz := Vector2.ZERO
	var nz := 0
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
		m.windows.append({"p": [_r(p.x), _r(p.y), _r(p.z)], "in": [w.inward.x, 0, w.inward.y], "h": MapValidator.LINTEL,
			"zone": w.zone, "spawns": [[_r(sp.x), _r(sp.y), _r(sp.z)]]})
		m.zombie_spawns.append({"p": [_r(sp.x), _r(sp.y), _r(sp.z)], "zone": w.zone})
	for it in md.floor_items:
		if it.base == "apparition":
			m.zombie_spawns.append({"p": _p(it.floor, it.center), "zone": it.zone})
	# Portes.
	for d in md.doors:
		var r: Rect2i = d.rect
		var thick := r.size.x if d.axis.x != 0 else r.size.y
		var dj := {"id": d.id, "p": _p(d.floor, Vector2(r.position) + Vector2(r.size) * 0.5), "yaw": _r(PI / 2.0) if d.axis.x != 0 else 0.0,
			"w": _r(d.width * S), "h": _r(md.door_height), "depth": _r(thick * S + 0.5), "cost": d.cost, "zones": d.zones}
		if d.debris:
			dj["debris"] = true
		if d.power:
			dj["power"] = true
		m.doors.append(dj)
	# Objets muraux (ordre de lecture de la grille).
	var used_ids := {}
	for it in md.wall_items:
		var e: Dictionary = it.entry
		var wi := _wall_item(it)
		if e.has("arme") or e.has("atout"):
			var base := String(e.get("arme", e.get("atout", "")))
			var n: int = used_ids.get(base, 0) + 1
			used_ids[base] = n
			wi["id"] = base if n == 1 else "%s_%d" % [base, n]
			if e.has("arme"):
				wi["weapon"] = base
				m.wall_buys.append(wi)
			else:
				wi["perk"] = base
				m.perks.append(wi)
			continue
		match it.base:
			"boite", "boite_depart":
				m.box.append(wi)
			"courant":
				m["power"] = wi
			"pap":
				m["pap"] = wi
			"grenades":
				wi["id"] = "grenades_%d" % (m.grenade_buys.size() + 1)
				m.grenade_buys.append(wi)
			"poste_central":
				m["_mainframe"] = wi
	# Pièges : zone au sol, un ou deux leviers.
	for it in md.floor_items:
		if it.base != "piege":
			continue
		var r: Rect2i = it.rect
		var sol: float = md.floors[it.floor].sol
		var lv: Array = it.get("levers", [])
		var t := {"id": "trap_%d" % (m.traps.size() + 1), "lever": _wall_item(lv[0]),
			"area": [wx(r.position.x), _r(sol), wx(r.position.y), wx(r.end.x), _r(sol + 2.5), wx(r.end.y)],
			"active": 40.0, "cooldown": 60.0}
		if lv.size() > 1:
			t["lever2"] = _wall_item(lv[1])
		m.traps.append(t)
	# Téléporteur.
	var pad = null
	var exit = null
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
		m.lamps.append(_lamp(int(l.floor), Vector2i(floori(l.center.x), floori(l.center.y))))
	return m


## Lampes : une grille de 6 m par zone et par étage, sous le plafond.
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
					if f.zone_of(c) == z and f.at(c) in [Kd.SOL, Kd.MARQUEUR]:
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
					if f.zone_of(c) != z or not f.at(c) in [Kd.SOL, Kd.MARQUEUR]:
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


func _map_def() -> Dictionary:
	var doors := {}
	for d in md.doors:
		doors[d.id] = {"cost": d.cost}
	var n_box := 0
	var start := -1
	for it in md.wall_items:
		if it.base == "boite_depart":
			start = n_box
		if it.base == "boite" or it.base == "boite_depart":
			n_box += 1
	var names := {}
	for z in md.zones:
		names[z] = String(md.zone_names.get(z, "Zone " + z.to_upper()))
	var has_mainframe := md.wall_items.any(func(it): return it.base == "poste_central")
	return {
		"display_name": md.display_name if md.display_name != "" else md.id.to_upper(),
		"description": md.description, "music": md.music, "zone_names": names, "doors": doors,
		"open_links": md.open_links, "box_start": maxi(start, 0),
		"box_starts": [] if start >= 0 else range(n_box),
		"teleporter_link": has_mainframe,
	}
