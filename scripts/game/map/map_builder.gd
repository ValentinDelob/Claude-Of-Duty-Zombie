class_name MapBuilder
extends RefCounted
## Construit la géométrie (rendu + collisions) d'une MapData.
##
## Le rendu est regroupé en quelques ArrayMesh (un par matériau) : peu de draw
## calls, ce qui compte pour la cible GTX 1050. Les collisions sont des boîtes
## fusionnées (rectangles gloutons).

const WALL_HEIGHT := 3.2
const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var data: MapData
var wall_height := WALL_HEIGHT
## Matériaux ("floor", "wall", "ceiling"), fournis par l'appelant.
var materials: Dictionary = {}


func _init(map_data: MapData) -> void:
	data = map_data


func build(parent: Node3D) -> void:
	var geo := Node3D.new()
	geo.name = "Geometry"
	parent.add_child(geo)
	_add_mesh(geo, "Floor", _build_floor_mesh(0.0, false), materials.get("floor"))
	_add_mesh(geo, "Ceiling", _build_floor_mesh(wall_height, true), materials.get("ceiling"))
	_add_mesh(geo, "Walls", _build_wall_mesh(), materials.get("wall"))
	_build_collisions(parent)


func _add_mesh(parent: Node3D, n: String, mesh: Mesh, mat: Material) -> void:
	if mesh == null:
		return
	var mi := MeshInstance3D.new()
	mi.name = n
	mi.mesh = mesh
	if mat:
		mi.material_override = mat
	parent.add_child(mi)


## Sol (ou plafond si `down`) : une quad par cellule de sol.
func _build_floor_mesh(y: float, down: bool) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := Vector3.DOWN if down else Vector3.UP
	var count := 0
	for cy in data.height:
		for cx in data.width:
			var c := Vector2i(cx, cy)
			if not data.is_floor(c):
				continue
			var x0 := cx * MapData.CELL
			var z0 := cy * MapData.CELL
			var x1 := x0 + MapData.CELL
			var z1 := z0 + MapData.CELL
			var a := Vector3(x0, y, z0)
			var b := Vector3(x1, y, z0)
			var cc := Vector3(x1, y, z1)
			var d := Vector3(x0, y, z1)
			if down:
				_quad(st, a, b, cc, d, n, 0.5)
			else:
				_quad(st, d, cc, b, a, n, 0.5)
			count += 1
	if count == 0:
		return null
	st.generate_tangents()
	return st.commit()


## Murs : une face verticale pour chaque côté de mur qui touche du sol.
func _build_wall_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := wall_height
	var count := 0
	for cy in data.height:
		for cx in data.width:
			var c := Vector2i(cx, cy)
			if not data.is_wall(c):
				continue
			for d in DIRS:
				if not data.is_floor(c + d):
					continue
				var x0 := cx * MapData.CELL
				var z0 := cy * MapData.CELL
				var x1 := x0 + MapData.CELL
				var z1 := z0 + MapData.CELL
				var n := Vector3(d.x, 0, d.y)
				# Face tournée vers le sol voisin (ordre anti-horaire vu de face).
				match d:
					Vector2i(1, 0):
						_quad(st, Vector3(x1, 0, z1), Vector3(x1, 0, z0), Vector3(x1, h, z0), Vector3(x1, h, z1), n, 0.5, true)
					Vector2i(-1, 0):
						_quad(st, Vector3(x0, 0, z0), Vector3(x0, 0, z1), Vector3(x0, h, z1), Vector3(x0, h, z0), n, 0.5, true)
					Vector2i(0, 1):
						_quad(st, Vector3(x0, 0, z1), Vector3(x1, 0, z1), Vector3(x1, h, z1), Vector3(x0, h, z1), n, 0.5, true)
					Vector2i(0, -1):
						_quad(st, Vector3(x1, 0, z0), Vector3(x0, 0, z0), Vector3(x0, h, z0), Vector3(x1, h, z0), n, 0.5, true)
				count += 1
	if count == 0:
		return null
	st.generate_tangents()
	return st.commit()


## Ajoute une quad (a,b,c,d dans le sens anti-horaire vu depuis la normale).
## UV en coordonnées monde pour un tuilage continu.
func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, uv_scale: float, vertical := false) -> void:
	var pts := [a, b, c, d]
	var uvs := []
	for p in pts:
		if vertical:
			var along: float = p.x + p.z
			uvs.append(Vector2(along, -p.y) * uv_scale)
		else:
			uvs.append(Vector2(p.x, p.z) * uv_scale)
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
	var rects := data.greedy_rects(func(c): return data.is_wall(c))
	for r in rects:
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(r.size.x * MapData.CELL, wall_height + 2.0, r.size.y * MapData.CELL)
		cs.shape = box
		cs.position = Vector3((r.position.x + r.size.x * 0.5) * MapData.CELL, wall_height * 0.5, (r.position.y + r.size.y * 0.5) * MapData.CELL)
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
