class_name MapBuilder
extends RefCounted
## Construit la géométrie (rendu + collisions) d'une MapData.
##
## Le rendu est regroupé en un ArrayMesh par matériau ET par tuile de
## CHUNK x CHUNK cellules : peu de draw calls (cible GTX 1050), tout en
## laissant le moteur éliminer les tuiles hors champ — et surtout hors de
## portée des lampes à ombre, dont les 6 faces de cubemap sont redessinées à
## chaque mouvement de zombie. Sols et plafonds ne projettent pas d'ombre
## (rien ne se trouve dessous / dessus) : passes d'ombre plus légères, aucun
## changement visible. Les collisions sont des boîtes fusionnées (rectangles
## gloutons).

const WALL_HEIGHT := 3.2
## Taille des tuiles de rendu (cellules). 16 : ~une salle par tuile.
const CHUNK := 16
const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var data: MapData
var def: MapDef
var wall_height := WALL_HEIGHT
## Matériaux imposés par clé (facultatif) ; sinon WorldLook.surface(clé) :
## seules les textures citées par la carte sont générées.
var materials: Dictionary = {}


func _init(map_data: MapData, map_def: MapDef = null) -> void:
	data = map_data
	def = map_def


func _floor_key(c: Vector2i) -> String:
	if def:
		var zm: Array = def.zone_materials.get(data.zone_at(c), [])
		if zm.size() > 0:
			return zm[0]
	return "floor"


func _wall_key(floor_cell: Vector2i) -> String:
	if def:
		var zm: Array = def.zone_materials.get(data.zone_at(floor_cell), [])
		if zm.size() > 1:
			return zm[1]
	return "wall"


## Troisième matériau de zone (facultatif) : le plafond.
func _ceiling_key(c: Vector2i) -> String:
	if def:
		var zm: Array = def.zone_materials.get(data.zone_at(c), [])
		if zm.size() > 2:
			return zm[2]
	return "ceiling"


func build(parent: Node3D) -> void:
	var geo := Node3D.new()
	geo.name = "Geometry"
	parent.add_child(geo)
	var tools := {}  # "clé matériau@tuile" -> SurfaceTool
	relief = plan_relief()
	_build_floors(tools)
	_build_walls(tools)
	_build_relief(geo, tools)
	for tkey in tools:
		var st: SurfaceTool = tools[tkey]
		st.generate_tangents()
		var key: String = tkey.get_slice("@", 0)
		var mi := MeshInstance3D.new()
		mi.name = "Mesh_%s_%s" % [key, tkey.get_slice("@", 1).get_slice("#", 0)]
		mi.mesh = st.commit()
		mi.material_override = materials[key] if materials.has(key) else SurfaceRelief.material(key)
		if tkey.ends_with("#flat"):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		geo.add_child(mi)
	_build_collisions(parent)


## Relief des surfaces (SurfaceRelief) : creux et saillies, sans ombre, par
## matériau et par tuile de rendu, construits directement (sommets et
## normales en tableaux : des dizaines de milliers de faces). Ajoutés au
## maillage du sol ou du plafond de la même tuile et du même matériau s'il
## existe (sans ombre lui aussi : aucun appel de dessin en plus), sinon un
## maillage à part (« Relief_<clé>_<tuile> »).
func _build_relief(geo: Node3D, tools: Dictionary) -> void:
	var acc := relief.emit_groups(MapData.CELL * CHUNK)
	var keys := acc.keys()
	keys.sort()
	for key: String in keys:
		var tiles: Array = (acc[key] as Dictionary).keys()
		tiles.sort()
		for t: String in tiles:
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			var v: PackedVector3Array = acc[key][t][0]
			arrays[Mesh.ARRAY_VERTEX] = v
			arrays[Mesh.ARRAY_NORMAL] = acc[key][t][1]
			var tk := "%s@%s#flat" % [key, t]
			if tools.has(tk):
				# Mêmes attributs que les faces du SurfaceTool (UV : tangentes).
				var uv := PackedVector2Array()
				uv.resize(v.size())
				arrays[Mesh.ARRAY_TEX_UV] = uv
				var part := ArrayMesh.new()
				part.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
				(tools[tk] as SurfaceTool).append_from(part, 0, Transform3D.IDENTITY)
				continue
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var mi := MeshInstance3D.new()
			mi.name = "Relief_%s_%s" % [key, t]
			mi.mesh = mesh
			mi.material_override = materials[key] if materials.has(key) else SurfaceRelief.material(key)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			geo.add_child(mi)


## SurfaceTool du matériau `key` pour la tuile contenant la cellule `c`.
## `flat` : sol / plafond (sans ombre portée).
func _tool(tools: Dictionary, key: String, c: Vector2i, flat := false) -> SurfaceTool:
	@warning_ignore("integer_division")
	var tkey := "%s@%d_%d%s" % [key, c.x / CHUNK, c.y / CHUNK, "#flat" if flat else ""]
	if not tools.has(tkey):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		tools[tkey] = st
	return tools[tkey]


## Sol et plafond : une quad par cellule de sol (moins les creux du relief).
func _build_floors(tools: Dictionary) -> void:
	var n := roundi(MapData.CELL / SurfaceRelief.CUBE)
	for cy in data.height:
		for cx in data.width:
			var c := Vector2i(cx, cy)
			if not data.is_floor(c):
				continue
			var r := Rect2i(cx * n, cy * n, n, n)
			for sub: Rect2i in relief.cut(Vector3i.UP, 0.0, r):
				var p := SurfaceRelief.quad_pts(Vector3i.UP, 0.0, sub)
				_quad(_tool(tools, _floor_key(c), c, true), p[0], p[1], p[2], p[3], Vector3.UP)
			for sub: Rect2i in relief.cut(Vector3i.DOWN, wall_height, r):
				var p := SurfaceRelief.quad_pts(Vector3i.DOWN, wall_height, sub)
				_quad(_tool(tools, _ceiling_key(c), c, true), p[0], p[1], p[2], p[3], Vector3.DOWN)


## Murs : une face verticale pour chaque côté de mur qui touche du sol
## (moins les creux du relief).
func _build_walls(tools: Dictionary) -> void:
	for cy in data.height:
		for cx in data.width:
			var c := Vector2i(cx, cy)
			if data.is_wall(c):
				for d in DIRS:
					var fc: Vector2i = c + d
					if data.is_floor(fc):
						var w := _wall_rect(c, d)
						var st := _tool(tools, _wall_key(fc), c)
						for sub: Rect2i in relief.cut(w[0], w[1], w[2]):
							var p := SurfaceRelief.quad_pts(w[0], w[1], sub)
							_quad(st, p[0], p[1], p[2], p[3], Vector3(w[0]))


## Côté `d` de la cellule de mur `c` : [normale (Vector3i), plan (m),
## rectangle (cubes, repère de SurfaceRelief : u le long du mur, v en hauteur)].
func _wall_rect(c: Vector2i, d: Vector2i) -> Array:
	var n := roundi(MapData.CELL / SurfaceRelief.CUBE)
	var h := roundi(wall_height / SurfaceRelief.CUBE)
	var plane := (c.x + (1 if d.x > 0 else 0)) * MapData.CELL if d.x != 0 else (c.y + (1 if d.y > 0 else 0)) * MapData.CELL
	var u := (c.y if d.x != 0 else c.x) * n
	return [Vector3i(d.x, 0, d.y), plane, Rect2i(u, 0, n, h)]


# ------------------------------------------------------------------ relief

## Relief des surfaces de la carte (SurfaceRelief) : graine de la carte,
## zones réservées autour de chaque marqueur (portes, fenêtres, évacuation,
## station, apparitions, caisses, pièges... : sa cellule et ses 8 voisines ;
## lampes : aucune dalle tombée autour), sols, murs et plafonds par matériau.
var relief: SurfaceRelief
## Marqueurs contre un mur ou dans un mur (portes, fenêtres, évacuation,
## station, interrupteur, levier, caisse) : ni creux, ni plinthe, ni cimaise
## sur le mur à moins d'une cellule.
const WALL_MARKERS := "123456789W@=GHX"


func plan_relief() -> SurfaceRelief:
	var rel := SurfaceRelief.new()
	rel.seed = SurfaceRelief.seed_of(def.id if def else "grid")
	rel.granularity = MapData.CELL
	if not SurfaceRelief.enabled:
		return rel
	var keep := {}
	var keep_wall := {}
	var lamps := {}
	for sym: String in data.markers:
		# Décor posé (caisses, barils, lits, paillasses, générateur) et
		# flaques de sang : leur cellule seulement ; lampes : plafond.
		var r := 0 if (sym in MapDef.BLOCKING_PROPS or sym == ",") else 1
		for c: Vector2i in data.markers[sym]:
			if sym == "L":
				lamps[c] = true
				continue
			for dy in range(-r, r + 1):
				for dx in range(-r, r + 1):
					keep[c + Vector2i(dx, dy)] = true
					# Murs : seulement les objets muraux et les ouvertures.
					if sym in WALL_MARKERS:
						keep_wall[c + Vector2i(dx, dy)] = true
	# Tables par cellule (tests rapides) : matériau du sol et du plafond
	# ("" : pas de sol), zone réservée, lampe.
	var w := data.width
	var h := data.height
	var fkeys := PackedStringArray()
	var ckeys := PackedStringArray()
	var kept := PackedByteArray()
	var lit := PackedByteArray()
	fkeys.resize(w * h)
	ckeys.resize(w * h)
	kept.resize(w * h)
	lit.resize(w * h)
	# Sols et plafonds : une zone par matériau.
	var floor_bb := {}
	var ceil_bb := {}
	for cy in h:
		for cx in w:
			var c := Vector2i(cx, cy)
			kept[cy * w + cx] = (1 if keep.has(c) else 0) | (2 if keep_wall.has(c) else 0)
			lit[cy * w + cx] = 1 if lamps.has(c) else 0
			if not data.is_floor(c):
				continue
			var cr := Rect2(Vector2(c) * MapData.CELL, Vector2.ONE * MapData.CELL)
			var fk := _floor_key(c)
			fkeys[cy * w + cx] = fk
			floor_bb[fk] = (floor_bb[fk] as Rect2).merge(cr) if floor_bb.has(fk) else cr
			var ck := _ceiling_key(c)
			ckeys[cy * w + cx] = ck
			ceil_bb[ck] = (ceil_bb[ck] as Rect2).merge(cr) if ceil_bb.has(ck) else cr
	var at := func(x: float, z: float) -> int:
		var cx := floori(x / MapData.CELL)
		var cz := floori(z / MapData.CELL)
		return cz * w + cx if cx >= 0 and cz >= 0 and cx < w and cz < h else -1
	for fk: String in floor_bb:
		rel.plan_floor(fk, 0.0, floor_bb[fk], func(x: float, z: float) -> bool:
			var i: int = at.call(x, z)
			return i >= 0 and kept[i] == 0 and fkeys[i] == fk)
	for ck: String in ceil_bb:
		rel.plan_ceiling(ck, wall_height, ceil_bb[ck], func(x: float, z: float) -> bool:
			var i: int = at.call(x, z)
			return i >= 0 and ckeys[i] == ck,
			func(x: float, z: float) -> bool:
				var i: int = at.call(x, z)
				return i < 0 or lit[i] == 0, "", MapData.CELL, true)
	# Murs : faces alignées d'un même matériau réunies en pans continus.
	var runs := {}   # [normale, plan, clé] -> [débuts le long du mur (cubes)]
	for cy in data.height:
		for cx in data.width:
			var c := Vector2i(cx, cy)
			if not data.is_wall(c):
				continue
			for d in DIRS:
				if data.is_floor(c + d):
					var wr := _wall_rect(c, d)
					(runs.get_or_add([wr[0], wr[1], _wall_key(c + d)], []) as Array).append((wr[2] as Rect2i).position.x)
	var free := func(x: float, z: float) -> bool:
		var i: int = at.call(x, z)
		return i < 0 or (kept[i] & 2) == 0
	var n := roundi(MapData.CELL / SurfaceRelief.CUBE)
	for k: Array in runs:
		var starts: Array = runs[k]
		starts.sort()
		var a: int = starts[0]
		var prev: int = a
		for i in range(1, starts.size() + 1):
			if i < starts.size() and int(starts[i]) == prev + n:
				prev = starts[i]
				continue
			rel.plan_wall(String(k[2]), k[0], float(k[1]), a * SurfaceRelief.CUBE, (prev + n) * SurfaceRelief.CUBE, 0.0, wall_height, 0.0, free)
			if i < starts.size():
				a = starts[i]
				prev = a
	return rel


## Ajoute une quad (a,b,c,d dans le sens anti-horaire vu depuis la normale).
## Les UV ne servent qu'aux tangentes : les shaders travaillent en coordonnées monde.
func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	var pts := [a, b, c, d]
	var uvs := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	for i in [0, 2, 1, 0, 3, 2]:
		st.set_normal(n)
		st.set_uv(uvs[i])
		st.add_vertex(pts[i])


func _build_collisions(parent: Node3D) -> void:
	var body := StaticBody3D.new()
	body.name = "WorldCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	parent.add_child(body)
	var top := wall_height
	var rects := data.greedy_rects(func(c): return data.is_wall(c))
	for r in rects:
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(r.size.x * MapData.CELL, top + 2.0, r.size.y * MapData.CELL)
		cs.shape = box
		cs.position = Vector3((r.position.x + r.size.x * 0.5) * MapData.CELL, top * 0.5, (r.position.y + r.size.y * 0.5) * MapData.CELL)
		body.add_child(cs)
	# Sol et plafond : deux grandes dalles couvrant toute la carte.
	var size := Vector3(data.width * MapData.CELL, 1.0, data.height * MapData.CELL)
	for y in [-0.5, wall_height + 0.5]:
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		cs.shape = box
		cs.position = Vector3(size.x * 0.5, y, size.z * 0.5)
		body.add_child(cs)
