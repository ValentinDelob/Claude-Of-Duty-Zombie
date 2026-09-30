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
## Matériaux par clé (voir WorldLook.map_materials()).
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
	_build_floors(tools)
	_build_walls(tools)
	for tkey in tools:
		var st: SurfaceTool = tools[tkey]
		st.generate_tangents()
		var key: String = tkey.get_slice("@", 0)
		var mi := MeshInstance3D.new()
		mi.name = "Mesh_%s_%s" % [key, tkey.get_slice("@", 1).get_slice("#", 0)]
		mi.mesh = st.commit()
		mi.material_override = materials.get(key, materials.get("wall"))
		if tkey.ends_with("#flat"):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		geo.add_child(mi)
	_build_collisions(parent)


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


## Sol et plafond : une quad par cellule de sol.
func _build_floors(tools: Dictionary) -> void:
	for cy in data.height:
		for cx in data.width:
			var c := Vector2i(cx, cy)
			if not data.is_floor(c):
				continue
			var x0 := cx * MapData.CELL
			var z0 := cy * MapData.CELL
			var x1 := x0 + MapData.CELL
			var z1 := z0 + MapData.CELL
			var y := wall_height
			_quad(_tool(tools, _floor_key(c), c, true), Vector3(x0, 0, z1), Vector3(x1, 0, z1), Vector3(x1, 0, z0), Vector3(x0, 0, z0), Vector3.UP)
			_quad(_tool(tools, _ceiling_key(c), c, true),Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, y, z1), Vector3(x0, y, z1), Vector3.DOWN)


## Murs : une face verticale pour chaque côté de mur qui touche du sol.
func _build_walls(tools: Dictionary) -> void:
	for cy in data.height:
		for cx in data.width:
			var c := Vector2i(cx, cy)
			if data.is_wall(c):
				for d in DIRS:
					var fc: Vector2i = c + d
					if data.is_floor(fc):
						_face(_tool(tools, _wall_key(fc), c), c, d, 0.0, wall_height)


## Face verticale sur le côté `d` de la cellule `c`, de y0 à y1, tournée vers `d`.
func _face(st: SurfaceTool, c: Vector2i, d: Vector2i, y0: float, y1: float) -> void:
	var x0 := c.x * MapData.CELL
	var z0 := c.y * MapData.CELL
	var x1 := x0 + MapData.CELL
	var z1 := z0 + MapData.CELL
	var n := Vector3(d.x, 0, d.y)
	match d:
		Vector2i(1, 0):
			_quad(st, Vector3(x1, y0, z1), Vector3(x1, y0, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1), n)
		Vector2i(-1, 0):
			_quad(st, Vector3(x0, y0, z0), Vector3(x0, y0, z1), Vector3(x0, y1, z1), Vector3(x0, y1, z0), n)
		Vector2i(0, 1):
			_quad(st, Vector3(x0, y0, z1), Vector3(x1, y0, z1), Vector3(x1, y1, z1), Vector3(x0, y1, z1), n)
		Vector2i(0, -1):
			_quad(st, Vector3(x1, y0, z0), Vector3(x0, y0, z0), Vector3(x0, y1, z0), Vector3(x1, y1, z0), n)


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
