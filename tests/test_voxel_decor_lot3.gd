extends TestCase
## Lot 3 des décors cubiques (docs/VOXEL_DECOR_PLAN.md) : décors des effets
## et luminaires en cubes de 5 cm (tools/blender/voxel_props/effets.py,
## luminaires.py). Le modèle remplace l'ancien objet construit par le jeu
## SANS déplacer ce qu'il porte : décor mural devant la face du mur, décor
## au plafond sous le plafond, flaques d'une seule couche de cubes au sol,
## emprise respectée ; chaque luminaire a des faces émissives (alpha 0) là où
## le jeu pose sa lumière (descente sous le plafond, hauteur, 0,2 m du mur),
## et le jeu le construit avec le matériau « voxel », sans ombre.

const PROPS_DIR := "res://assets/models/props/"
const EFFECT_DECOR := ["buches", "planches_brulees", "electrodes", "bobine_tesla", "flaque_eau", "petite_flaque",
	"torche_murale", "tuyau_vapeur", "boitier_electrique", "tuyau_fuite", "cable_suspendu"]


static func _scene(model: String) -> Node3D:
	var ps := load(PROPS_DIR + model + ".glb") as PackedScene
	return ps.instantiate() as Node3D if ps != null else null


## Transformation d'un nœud dans le repère de `top` (scène hors de l'arbre).
static func _xf_in(n: Node, top: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != top:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


## Boîte englobante des maillages d'une scène, dans son repère.
static func _bounds(scene: Node) -> AABB:
	var box := AABB()
	var first := true
	for mi in scene.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = _xf_in(mi, scene) * (mi as MeshInstance3D).mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


## Faces émissives (alpha 0 dans la couleur de face) d'une scène : boîte de
## chaque triangle, dans le repère de la scène.
static func _glow_faces(scene: Node) -> Array:
	var out := []
	for mi in scene.find_children("*", "MeshInstance3D", true, false):
		var xf := _xf_in(mi, scene)
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			var arr := mesh.surface_get_arrays(s)
			var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			for t in range(0, idx.size(), 3):
				if cols[idx[t]].a >= 0.5:
					continue
				var box := AABB(xf * verts[idx[t]], Vector3.ZERO)
				box = box.expand(xf * verts[idx[t + 1]]).expand(xf * verts[idx[t + 2]])
				out.append(box)
	return out


## Distance d'un point à une boîte (0 dedans).
static func _dist(p: Vector3, b: AABB) -> float:
	return p.distance_to(p.clamp(b.position, b.end))


func test_effect_decor_sits_where_its_effect_is() -> void:
	for pid in EFFECT_DECOR:
		var d: Dictionary = MapCatalog.PREFABS[pid]
		assert_eq(String(d.get("model", "")), "voxel/" + pid, "%s : modèle cubique" % pid)
		var scene := _scene(String(d.model))
		assert_true(scene != null, "%s : modèle chargé" % pid)
		if scene == null:
			continue
		var b := _bounds(scene)
		var fp: Array = d.fp
		var mount := String(d.get("mount", "sol"))
		match mount:
			"mur":
				# Origine sur la face du mur : tout le modèle devant (+z, vers la pièce).
				assert_true(b.position.z >= -0.001 and b.end.z > 0.05, "%s : devant la face du mur (%s)" % [pid, b])
				assert_true(absf(b.position.x) <= float(fp[0]) * 0.25 + 0.001 and b.end.x <= float(fp[0]) * 0.25 + 0.001,
					"%s : dans la largeur de son emprise (%s)" % [pid, b])
			"plafond":
				assert_true(b.end.y <= 0.001, "%s : sous le plafond (%s)" % [pid, b])
				assert_near(-b.position.y, float(d.h), 0.051, "%s : pend de sa hauteur" % pid)
			_:
				assert_true(b.position.y >= -0.001, "%s : posé au sol (%s)" % [pid, b])
				assert_true(b.end.y <= float(d.h) + 0.051, "%s : pas plus haut que sa hauteur (%s)" % [pid, b])
				assert_true(absf(b.position.x) <= float(fp[0]) * 0.25 + 0.001 and b.end.x <= float(fp[0]) * 0.25 + 0.001
					and absf(b.position.z) <= float(fp[1]) * 0.25 + 0.001 and b.end.z <= float(fp[1]) * 0.25 + 0.001,
					"%s : dans son emprise (%s)" % [pid, b])
		if pid in ["flaque_eau", "petite_flaque"]:
			# Plaque d'une couche de cubes au sol, sans ombre.
			assert_near(b.size.y, 0.05, 0.001, "%s : une couche de 5 cm" % pid)
			for mi in scene.find_children("*", "MeshInstance3D", true, false):
				assert_true(String(mi.name).ends_with("__ns"), "%s : sans ombre" % pid)
		scene.free()
	# Les pavés de collision du catalogue enveloppent les décors qui bloquent.
	for pid in ["electrodes", "bobine_tesla"]:
		var scene := _scene("voxel/" + pid)
		var b := _bounds(scene)
		var hull := AABB()
		var boxes: Array = MapCatalog.PREFABS[pid].boxes
		for i in boxes.size():
			var bx: Dictionary = boxes[i]
			var c := Vector3(bx.center[0], bx.center[1], bx.center[2])
			var s := Vector3(bx.size[0], bx.size[1], bx.size[2])
			hull = AABB(c - s * 0.5, s) if i == 0 else hull.merge(AABB(c - s * 0.5, s))
		assert_true(hull.grow(0.051).encloses(b), "%s : modèle dans ses pavés de collision (%s / %s)" % [pid, b, hull])
		scene.free()


func test_light_fixtures_glow_where_the_light_is() -> void:
	var loader := func(m: String) -> PackedScene: return load(PROPS_DIR + m + ".glb") as PackedScene
	for lid in MapCatalog.LIGHTS:
		var d: Dictionary = MapCatalog.LIGHTS[lid]
		assert_eq(String(d.get("model", "")), "voxel/" + lid, "%s : modèle cubique" % lid)
		var fx := EditorPrefabs.fixture(lid, "", loader)
		assert_true(fx != null, "%s : objet du luminaire construit" % lid)
		if fx == null:
			continue
		for mi in fx.find_children("*", "MeshInstance3D", true, false):
			assert_true(String(mi.name).begins_with(MeshMapBuilder.VOXEL_MAT + "__" + lid), "%s : nœud %s" % [lid, mi.name])
		# Point de la lumière dans le repère de l'objet (MapLayoutExport._fixture).
		var light := Vector3.ZERO
		match String(d.mount):
			"plafond":
				light = Vector3(0, -float(d.drop), 0)
			"mur":
				light = Vector3(0, 0, 0.2)
			_:
				light = Vector3(0, float(d.y), 0)
		var faces := _glow_faces(fx)
		assert_true(faces.size() > 0, "%s : parties lumineuses émissives" % lid)
		# Lumière parmi les parties lumineuses (le lustre l'entoure de bougies).
		var best := INF
		var lit := AABB()
		for i in faces.size():
			best = minf(best, _dist(light, faces[i]))
			lit = faces[i] if i == 0 else lit.merge(faces[i])
		if lid == "lustre":
			best = _dist(light, lit)
		assert_true(best <= 0.12,"%s : partie lumineuse à %.2f m de la lumière (%s)" % [lid, best, light])
		var b := _bounds(fx)
		var fp: Array = d.fp
		assert_true(b.position.x >= -float(fp[0]) * 0.25 - 0.051 and b.end.x <= float(fp[0]) * 0.25 + 0.051,
			"%s : largeur dans son emprise (%s)" % [lid, b])
		match String(d.mount):
			"plafond":
				assert_true(b.end.y <= 0.001, "%s : sous le plafond (%s)" % [lid, b])
			"mur":
				assert_true(b.position.z >= -0.001, "%s : devant le mur (%s)" % [lid, b])
			_:
				assert_true(b.position.y >= -0.001, "%s : posé (%s)" % [lid, b])
		if d.has("boxes"):
			var bx: Dictionary = d.boxes[0]
			var c := Vector3(bx.center[0], bx.center[1], bx.center[2])
			var s := Vector3(bx.size[0], bx.size[1], bx.size[2])
			assert_true(AABB(c - s * 0.5, s).grow(0.21).encloses(b), "%s : modèle autour de son pavé de collision (%s)" % [lid, b])
		fx.free()


func test_game_builds_fixtures_with_the_voxel_material_without_shadow() -> void:
	var lamps := []
	var i := 0
	for lid in MapCatalog.LIGHTS:
		lamps.append({"p": [i * 2.0, 2.0, 0.0], "fixture": lid, "fixture_p": [i * 2.0, 2.5, 0.0], "energy": 1.0, "range": 5.0, "color": "ffcc88"})
		i += 1
	var world := Node3D.new()
	host.add_child(world)
	var mb := MeshMapBuilder.new({"markers": {"lamps": lamps}})
	mb._make_root(world, "Props")
	mb._build_lamps()
	var meshes := world.find_children("voxel__*", "MeshInstance3D", true, false)
	assert_eq(meshes.size(), MapCatalog.LIGHTS.size(), "un modèle cubique par luminaire")
	for mi in meshes:
		var m := mi as MeshInstance3D
		var mat := m.material_override
		assert_true(mat is ShaderMaterial and (mat as ShaderMaterial).shader.resource_path.ends_with("voxel_prop.gdshader"), "%s : matériau voxel" % m.name)
		assert_eq(m.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "%s : sans ombre" % m.name)
	world.queue_free()
	await wait_frames(1)
