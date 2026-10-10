extends TestCase
## Style cubique (GAME_CONCEPT.md § 4.19, VoxelCheck) : cubes de 5 cm
## acceptés, rotation de 45° refusée, sommet hors grille, faces obliques,
## ombrage lissé, maillage animé (skinné et en nœuds) vérifié dans le repère
## de ses os, objets posés (quarts de tour), import .glb (MapPrefabLib).

const Prefabs := preload("res://tests/test_map_prefabs.gd")


# ------------------------------------------------------------------ outils

## Scène : une racine et une boîte (BoxMesh) au repère `xf`.
static func _box_scene(size: Vector3, xf := Transform3D.IDENTITY) -> Node3D:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.name = "Boite"
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.transform = xf
	root.add_child(mi)
	return root


## Maillage skinné : une boîte de 10 × 10 × 20 cm sur l'os 0 (repos : tourné
## de `deg` autour de Z et déplacé), une boîte de 10 cm sur l'os 1 (repos :
## identité, décalée de 2 cm hors de la grille de l'os 0). Les sommets sont
## dans le repère du maillage (pose de repos), comme dans un .glb.
static func _skinned(deg: float) -> Node3D:
	var rest0 := Transform3D(Basis(Vector3.BACK, deg_to_rad(deg)), Vector3(0.3, 1.0, 0.0))
	var rest1 := Transform3D(Basis.IDENTITY, Vector3(0.02, 0.0, 0.0))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var idx := PackedInt32Array()
	for part in [[Vector3(0.1, 0.1, 0.2), rest0, 0], [Vector3(0.1, 0.1, 0.1), rest1, 1]]:
		var bm := BoxMesh.new()
		bm.size = part[0]
		var a := bm.get_mesh_arrays()
		var base := pos.size()
		var xf: Transform3D = part[1]
		for v in (a[Mesh.ARRAY_VERTEX] as PackedVector3Array):
			pos.append(xf * v)
			bones.append_array([int(part[2]), 0, 0, 0])
			weights.append_array([1.0, 0.0, 0.0, 0.0])
		for n in (a[Mesh.ARRAY_NORMAL] as PackedVector3Array):
			nrm.append(xf.basis * n)
		for i in (a[Mesh.ARRAY_INDEX] as PackedInt32Array):
			idx.append(base + i)
	arrays[Mesh.ARRAY_VERTEX] = pos
	arrays[Mesh.ARRAY_NORMAL] = nrm
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var skin := Skin.new()
	skin.add_named_bind("bras", rest0.affine_inverse())
	skin.add_named_bind("main", rest1.affine_inverse())
	var root := Node3D.new()
	var sk := Skeleton3D.new()
	sk.add_bone("bras")
	sk.add_bone("main")
	sk.set_bone_rest(0, rest0)
	sk.set_bone_rest(1, rest1)
	root.add_child(sk)
	var mi := MeshInstance3D.new()
	mi.name = "Corps"
	mi.mesh = mesh
	mi.skin = skin
	sk.add_child(mi)
	return root


# ------------------------------------------------------------------ maillages

func test_cubes_on_the_grid_pass() -> void:
	var one := _box_scene(Vector3(0.1, 0.35, 1.2))
	var r := VoxelCheck.check_mesh((one.get_child(0) as MeshInstance3D).mesh)
	one.free()
	assert_true(r.ok, r.fr)
	assert_eq(int(r.faces), 12, "12 triangles")
	assert_eq(int(r.bad_faces), 0)
	# Deux boîtes, l'une déplacée de 15 cm et tournée d'un quart de tour : toujours sur la grille.
	var root := _box_scene(Vector3(0.1, 0.1, 0.1))
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.2, 0.05, 0.1)
	mi.mesh = bm
	mi.transform = Transform3D(Basis(Vector3.UP, PI / 2), Vector3(0.15, 0.025, -0.05))
	root.add_child(mi)
	var r2 := VoxelCheck.check_scene(root)
	assert_true(r2.ok, "quart de tour accepté : %s" % r2.fr)
	assert_true(String(r2.fr).begins_with("Modèle cubique") and String(r2.en).begins_with("Cubic model"), "rapport FR et EN")
	root.free()


func test_rotation_45_refused() -> void:
	var root := _box_scene(Vector3(0.1, 0.1, 0.1), Transform3D(Basis(Vector3.UP, PI / 4), Vector3.ZERO))
	var r := VoxelCheck.check_scene(root)
	assert_false(r.ok, "boîte tournée de 45° refusée")
	assert_eq(int(r.oblique), 8, "les 8 triangles des faces verticales sont obliques")
	assert_true(String(r.fr).contains("oblique") and String(r.en).contains("slanted"), "raison nommée : %s" % r.fr)
	assert_true(String(r.fr).contains("« Boite »"), "premier exemple : la partie fautive")
	root.free()


func test_vertex_off_grid_refused() -> void:
	# 12 cm : 2,4 cubes.
	var root := _box_scene(Vector3(0.12, 0.1, 0.1))
	var r := VoxelCheck.check_scene(root)
	assert_false(r.ok, "12 cm refusé")
	assert_eq(int(r.oblique), 0, "faces bien alignées")
	assert_true(int(r.off_grid) > 0, "sommets hors grille")
	assert_true(String(r.fr).contains("hors de la grille de 5 cm") and String(r.en).contains("off the 5 cm grid"), r.en)
	root.free()
	# Tolérance : 1 mm d'écart (arrondi d'export) accepté, 3 mm refusé.
	var ok := _box_scene(Vector3(0.101, 0.1, 0.1))
	assert_true(VoxelCheck.check_scene(ok).ok, "1 mm toléré")
	ok.free()
	var ko := _box_scene(Vector3(0.106, 0.1, 0.1))
	assert_false(VoxelCheck.check_scene(ko).ok, "6 mm refusé")
	ko.free()
	# Échelle d'un prefab : ×1,2 sort 10 cm de la grille (12 cm), ×1,5 y reste (15 cm).
	var sc := _box_scene(Vector3(0.1, 0.1, 0.1))
	assert_false(VoxelCheck.check_scene(sc, false, 1.2).ok, "×1,2 refusé")
	assert_true(VoxelCheck.check_scene(sc, false, 1.5).ok, "×1,5 accepté")
	sc.free()


func test_oblique_normals_and_smooth_shading_refused() -> void:
	# Prisme : deux pentes.
	var pm := PrismMesh.new()
	pm.size = Vector3(0.1, 0.1, 0.1)
	var r := VoxelCheck.check_mesh(pm)
	assert_false(r.ok, "prisme refusé")
	assert_true(int(r.oblique) > 0, "faces obliques comptées")
	# Sphère : courbe et lissée.
	var sm := SphereMesh.new()
	var rs := VoxelCheck.check_mesh(sm)
	assert_false(rs.ok, "sphère refusée")
	assert_true(int(rs.smooth) > 0, "ombrage lissé compté")
	# Cube de 10 cm aux normales de sommet lissées (moyenne des 3 faces) : refusé.
	var bm := BoxMesh.new()
	bm.size = Vector3(0.1, 0.1, 0.1)
	var a := bm.get_mesh_arrays()
	var n := PackedVector3Array()
	for v in (a[Mesh.ARRAY_VERTEX] as PackedVector3Array):
		n.append(v.sign().normalized())
	a[Mesh.ARRAY_NORMAL] = n
	a[Mesh.ARRAY_TANGENT] = null
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	var rl := VoxelCheck.check_mesh(am)
	assert_false(rl.ok, "cube lissé refusé")
	assert_eq(int(rl.oblique), 0, "géométrie cubique")
	assert_true(String(rl.fr).contains("lissé"), rl.fr)
	# Maillage vide : refusé.
	assert_false(VoxelCheck.check_mesh(ArrayMesh.new()).ok, "aucune face : refusé")


func test_animated_mesh_checked_in_bone_space() -> void:
	# Os tourné de 30° au repos, membre fait de cubes dans le repère de l'os.
	var root := _skinned(30.0)
	var stat := VoxelCheck.check_scene(root, false)
	assert_false(stat.ok, "en global (statique) : le membre tourné est oblique")
	var anim := VoxelCheck.check_scene(root, true)
	assert_true(anim.ok, "animé : chaque partie dans le repère de son os : %s" % anim.fr)
	assert_eq(int(anim.parts), 2, "deux os, deux grilles")
	assert_true(VoxelCheck.has_skeleton(root), "squelette détecté (mode deviné)")
	root.free()
	# Os au repos tourné de 30° mais membre posé à 45° dans le repère de l'os : refusé.
	var bad := _skinned(30.0)
	var mi := bad.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var skin := mi.skin
	skin.set_bind_pose(0, Transform3D(Basis(Vector3.BACK, deg_to_rad(-15.0)), Vector3.ZERO) * skin.get_bind_pose(0))
	var rb := VoxelCheck.check_scene(bad, true)
	assert_false(rb.ok, "membre de travers dans le repère de son os : refusé")
	bad.free()
	# Os de biais (repos tourné de 30°) mais membre aligné sur le modèle : accepté.
	var tilted := _skinned(0.0)
	var mt := tilted.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	mt.skin.set_bind_pose(0, Transform3D(Basis(Vector3.BACK, deg_to_rad(30.0)), Vector3.ZERO) * mt.skin.get_bind_pose(0))
	assert_true(VoxelCheck.check_scene(tilted, true).ok, "cubique au repos dans le repère du modèle : accepté")
	tilted.free()
	# Personnage en nœuds (sans skin) : chaque maillage dans son repère.
	var nodes := _box_scene(Vector3(0.1, 0.2, 0.1), Transform3D(Basis(Vector3.RIGHT, deg_to_rad(37.0)), Vector3(0.013, 0.5, 0)))
	assert_false(VoxelCheck.check_scene(nodes, false).ok, "statique : refusé")
	assert_true(VoxelCheck.check_scene(nodes, true).ok, "animé : accepté")
	nodes.free()


func test_character_grid_is_2_5_cm() -> void:
	# Pavé de 7,5 cm : 3 cubes de personnage (2,5 cm), pas un multiple du
	# cube de décor (5 cm).
	var root := _box_scene(Vector3(0.075, 0.1, 0.025))
	var stat := VoxelCheck.check_scene(root, false)
	assert_false(stat.ok, "statique : grille de 5 cm, refusé")
	assert_near(float(stat.cube), 0.05, 0.0001, "pas statique")
	assert_true(String(stat.fr).contains("5 cm"), stat.fr)
	var anim := VoxelCheck.check_scene(root, true)
	assert_true(anim.ok, "animé : grille de 2,5 cm : %s" % anim.fr)
	assert_true(String(anim.fr).contains("2,5 cm") and String(anim.en).contains("2.5 cm"), anim.en)
	# Pas forcé.
	assert_true(VoxelCheck.check_scene(root, false, 1.0, VoxelCheck.CUBE_CHAR).ok, "statique forcé à 2,5 cm : accepté")
	assert_false(VoxelCheck.check_scene(root, true, 1.0, VoxelCheck.CUBE).ok, "animé forcé à 5 cm : refusé")
	root.free()
	# Sommet à 1,25 cm de la grille : hors de la grille de 2,5 cm aussi.
	var half := _box_scene(Vector3(0.0625, 0.1, 0.1))
	assert_false(VoxelCheck.check_scene(half, true).ok, "6,25 cm : refusé en animé")
	half.free()
	assert_true(VoxelCheck.on_grid(0.075, VoxelCheck.CUBE_CHAR) and not VoxelCheck.on_grid(0.075))


func test_glb_and_import_report() -> void:
	var good := Prefabs.box_glb(Vector3(1, 2, 3))
	var r := VoxelCheck.check_glb_bytes(good)
	assert_true(r.ok, ".glb cubique : %s" % r.fr)
	assert_false(bool(r.animated), "pas de squelette : statique")
	assert_true(MapPrefabLib.voxel_report(good).ok, "import : accepté")
	assert_false(MapPrefabLib.voxel_report(good, 1.01).ok, "import à ×1,01 : refusé")
	var bad := Prefabs.box_glb(Vector3(0.52, 1, 0.5))
	var rb := MapPrefabLib.voxel_report(bad)
	assert_false(rb.ok, "52 cm : refusé")
	var why := VoxelCheck.refusal(rb)
	assert_true(String(why[0]).contains("style cubique") and String(why[1]).contains("cubic style"), "message FR / EN : %s" % why[1])
	assert_false(VoxelCheck.check_glb_bytes(PackedByteArray([1, 2, 3])).ok, "illisible : refusé")


# ------------------------------------------------------------------ objets posés

func test_placement_quarter_turns() -> void:
	assert_eq(VoxelCheck.placement_issue({"type": "prefab", "rot": 0}), [])
	assert_eq(VoxelCheck.placement_issue({"type": "prefab", "rot": 270}), [])
	assert_eq(VoxelCheck.placement_issue({"type": "prefab", "rot": -90}), [])
	var r45 := VoxelCheck.placement_issue({"type": "prefab", "rot": 45})
	assert_eq(r45.size(), 2, "45° : refusé")
	assert_true(String(r45[0]).contains("quarts de tour") and String(r45[1]).contains("quarter turns"), str(r45))
	assert_eq(VoxelCheck.placement_issue({"type": "prefab", "rot": 0, "incl": [15, 0]}).size(), 2, "incliné : refusé")
	assert_eq(VoxelCheck.placement_issue({"type": "prefab", "rot": 0, "echelle": [1.5, 1, 1]}, Vector3(1, 1, 1)), [], "1,5 m : sur la grille")
	assert_eq(VoxelCheck.placement_issue({"type": "prefab", "rot": 0, "echelle": [1.33, 1, 1]}, Vector3(1, 1, 1)).size(), 2, "1,33 m : hors grille")
	assert_true(VoxelCheck.on_grid(0.35) and not VoxelCheck.on_grid(0.33))
