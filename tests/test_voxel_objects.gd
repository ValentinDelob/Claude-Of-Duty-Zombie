extends TestCase
## Objets de carte CUBIQUES (lot 4 de docs/VOXEL_DECOR_PLAN.md, GAME_CONCEPT.md
## § 4.19) : portes payantes (blindée, bois, grille), débris (planches,
## gravats), porte du courant, planches et portes à zombies des barricades,
## caisse au hasard, levier du courant, téléporteur et arrivée, poste
## central (mur, sol), panneau des pièges et second levier, porte
## d'évacuation, caisse et baril de l'éditeur. Chaque modèle passe VoxelCheck
## (cubes de 5 cm) ; les pièces mobiles (levier, couvercle, battant) sont
## cubiques dans leur repère ; collisions, dimensions de jeu et animations
## inchangées.

const OBJ_GLBS := ["boite", "courant", "levier_piege", "teleporteur", "arrivee", "poste_central_mur", "poste_central_sol", "evacuation"]

var _nodes: Array[Node] = []


func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()


func _keep(n: Node) -> Node:
	_nodes.append(n)
	return n


## VoxelCheck statique de tous les maillages de `root` (repère de `root`),
## sauf `moving` ; chaque pièce de `moving` vérifiée dans son propre repère.
func _cubic(root: Node, what: String, moving: Array = []) -> void:
	var tmp := Node3D.new()
	var inv := (root as Node3D).global_transform.affine_inverse() if root is Node3D and (root as Node3D).is_inside_tree() else Transform3D.IDENTITY
	var n := 0
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mi in moving or not mi.visible:
			continue
		var c := MeshInstance3D.new()
		c.mesh = mi.mesh
		c.transform = (inv * mi.global_transform) if mi.is_inside_tree() else _local(mi, root)
		tmp.add_child(c)
		n += 1
	assert_true(n > 0, "%s : maillages trouvés" % what)
	var r := VoxelCheck.check_scene(tmp)
	assert_true(r.ok, "%s : cubique (5 cm) — %s" % [what, r.fr])
	assert_near(float(r.cube), VoxelCheck.CUBE, 0.0001, "%s : grille de 5 cm" % what)
	tmp.free()
	for m: MeshInstance3D in moving:
		var rm := VoxelCheck.check_mesh(m.mesh)
		assert_true(rm.ok, "%s : pièce mobile %s cubique dans son repère — %s" % [what, m.name, rm.fr])


static func _local(n: Node3D, top: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != top:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


# ------------------------------------------------------------------ modèles Blender

func test_object_models_are_cubic() -> void:
	for obj in OBJ_GLBS:
		var path: String = VoxelBuild.OBJ_DIR + obj + ".glb"
		assert_true(ResourceLoader.exists(path), "%s présent" % path)
		var ps := load(path) as PackedScene
		if ps == null:
			continue
		var scene := ps.instantiate()
		var rep := VoxelCheck.check_scene(scene, false)
		assert_true(bool(rep.ok), "%s : cubique (5 cm) — %s" % [obj, rep.get("fr", "")])
		assert_eq(scene.find_children("*", "CollisionObject3D", true, false).size(), 0, "%s : aucune collision dans le .glb" % obj)
		for mi in scene.find_children("*", "MeshInstance3D", true, false):
			assert_true(String(mi.name).begins_with("voxel__%s_" % obj), "%s : pièce %s nommée voxel__<objet>_<pièce>__<type>" % [obj, mi.name])
		scene.free()
		var parts := VoxelBuild.parts(obj)
		assert_true(parts.size() >= 2, "%s : pièces lues (%s)" % [obj, parts.keys()])
		for p in parts.values():
			assert_true((p as MeshInstance3D).material_override == VoxelBuild.material(), "%s : matériau « voxel »" % obj)
			p.free()


# ------------------------------------------------------------------ portes et débris

static func _door_marker(variant: String, debris := false, power := false, width := 2.0) -> MapMarker:
	var mk := MapMarker.new()
	mk.id = "v_" + variant
	mk.pos = Vector3.ZERO
	mk.data = {"cost": 1250, "width": width, "height": 2.5, "depth": 0.75, "yaw": 0.0, "zones": ["a", "b"], "debris": debris, "variant": variant, "power": power}
	return mk


func test_doors_and_debris_are_cubic_with_unchanged_collision() -> void:
	for spec in [["blindee", false, false, 2.0], ["bois", false, false, 1.5], ["grille", false, false, 2.0], ["", true, false, 2.0],
			["gravats", true, false, 1.0], ["", false, true, 3.0], ["blindee", false, false, 1.25]]:
		var d := Door.new()
		d.setup_marker(_door_marker(spec[0], spec[1], spec[2], spec[3]))
		host.add_child(_keep(d))
		var what := "porte %s (%.2f m)" % [d.look() if d.look() != "" else "du courant", spec[3]]
		var model := d.get_node_or_null("Slab/Model") as MeshInstance3D
		assert_true(model != null, "%s : modèle cubique sous le battant" % what)
		assert_true(model != null and model.material_override == VoxelBuild.material(), "%s : matériau « voxel »" % what)
		_cubic(d.get_node("Slab"), what)
		# Dans l'ouverture (largeur, hauteur), collision inchangée.
		var aabb := model.get_aabb() if model else AABB()
		assert_true(aabb.size.x <= float(spec[3]) + 0.06 and aabb.size.y <= 2.5 + 0.001, "%s : dans l'ouverture (%s)" % [what, aabb])
		var shape := ((d.get_children().filter(func(n): return n is StaticBody3D)[0] as StaticBody3D).get_child(0) as CollisionShape3D).shape as BoxShape3D
		assert_eq(shape.size, Vector3(spec[3], 2.5, 0.9), "%s : collision inchangée" % what)
	# Aspect déterministe (même tas sur toutes les machines).
	var a := Door.new()
	a.setup_marker(_door_marker("gravats", true))
	var b := Door.new()
	b.setup_marker(_door_marker("gravats", true))
	host.add_child(_keep(a))
	host.add_child(_keep(b))
	var ma := (a.get_node("Slab/Model") as MeshInstance3D).mesh
	var mb := (b.get_node("Slab/Model") as MeshInstance3D).mesh
	assert_eq(ma.surface_get_arrays(0)[Mesh.ARRAY_VERTEX], mb.surface_get_arrays(0)[Mesh.ARRAY_VERTEX], "même éboulement des deux côtés du réseau")
	await wait_frames(1)


## Ouverture : le battant (et son modèle) monte dans le linteau, les débris
## s'enfoncent ; même durée qu'avant.
func test_door_opening_moves_the_cubic_slab() -> void:
	var d := Door.new()
	d.setup_marker(_door_marker("bois"))
	host.add_child(_keep(d))
	d.set_open(true, false)
	assert_near(d._slab.position.y, 2.5 - 0.1, 0.0001, "porte montée dans le linteau")
	assert_false(d._slab.visible, "porte ouverte cachée")
	var g := Door.new()
	g.setup_marker(_door_marker("", true))
	host.add_child(_keep(g))
	g.set_open(true, false)
	assert_near(g._slab.position.y, -(2.5 + 0.3), 0.0001, "débris enfoncés")
	assert_eq(Door.OPEN_TIME, 1.6, "durée d'ouverture inchangée")
	await wait_frames(1)


# ------------------------------------------------------------------ barricades

static func _opening(kind: String) -> BarricadeLayout.Opening:
	var o := BarricadeLayout.Opening.new()
	o.kind = kind
	o.width = MapCatalog.barricade_width(kind)
	o.height = 2.35 if kind == BarricadeRules.WINDOW else 2.1
	o.seed = 777
	return o


func test_barricade_planks_cubic_and_on_the_grid_at_rest() -> void:
	for kind in [BarricadeRules.WINDOW, BarricadeRules.DOOR, BarricadeRules.DOUBLE_DOOR]:
		var b := Barricade.new()
		b.setup(_opening(kind))
		host.add_child(_keep(b))
		var mm := (b.get_node("Planks") as MultiMeshInstance3D).multimesh
		var size := Barricade.DOOR_PLANK_SIZE if b.is_door() else Barricade.PLANK_SIZE
		assert_true(VoxelCheck.check_mesh(mm.mesh).ok, "%s : planche cubique" % kind)
		assert_true(mm.mesh.get_aabb().size.is_equal_approx(size), "%s : planche de %s (%s)" % [kind, size, mm.mesh.get_aabb().size])
		# Au repos : aucune rotation, coins sur la grille (avec la porte, s'il y en a une).
		var root := Node3D.new()
		for i in b.plank_count:
			var xf: Transform3D = b._rest[i]
			assert_true(xf.basis.is_equal_approx(Basis.IDENTITY), "%s : planche %d à plat, sans rotation" % [kind, i])
			var c := MeshInstance3D.new()
			c.mesh = mm.mesh
			c.transform = xf
			root.add_child(c)
		var asm := b.get_node_or_null("DoorAssembly")
		if asm:
			for mi: MeshInstance3D in asm.find_children("*", "MeshInstance3D", true, false):
				var c := MeshInstance3D.new()
				c.mesh = mi.mesh
				c.transform = mi.transform
				root.add_child(c)
		var r := VoxelCheck.check_scene(root)
		assert_true(r.ok, "%s : planches au repos (et porte) sur une même grille de 5 cm — %s" % [kind, r.fr])
		root.free()
		# Deux planches au repos ne se chevauchent pas.
		for i in b.plank_count:
			for j in range(i + 1, b.plank_count):
				var ai := AABB(b._rest[i].origin - size * 0.5, size)
				var aj := AABB(b._rest[j].origin - size * 0.5, size)
				assert_false(ai.grow(-0.001).intersects(aj.grow(-0.001)), "%s : planches %d et %d séparées" % [kind, i, j])
		# Arrachage : la planche tourne pendant l'animation, puis se pose à plat au sol.
		b.set_mask(b.full_mask() & ~1, true)
		b._process(Barricade.TEAR_ANIM * 0.5)
		assert_false(b._plank_xform(0).basis.is_equal_approx(Basis.IDENTITY), "%s : la planche tourne en volant" % kind)
		b._process(Barricade.TEAR_ANIM)
		assert_true(b._plank_xform(0).is_equal_approx(b._fallen[0]), "%s : planche arrachée au sol" % kind)
	await wait_frames(1)


# ------------------------------------------------------------------ machines

func test_mystery_box_is_cubic() -> void:
	var parent := Node3D.new()
	host.add_child(_keep(parent))
	var m := MapMarker.new()
	m.id = "box_0"
	m.wall = Vector3(0, 0, -1)
	var box := MysteryBox.new()
	box.setup_spot(m)
	parent.add_child(box)
	await wait_frames(1)
	_cubic(box._root, "caisse au hasard (fermée)")
	assert_true(box._root.get_node_or_null("Model") != null, "modèle cubique")
	assert_eq(box._open_meshes.size(), 2, "fond et intérieur qui s'allument")
	for mi in box._open_meshes:
		assert_true((mi as MeshInstance3D).material_override.shader == BoxModel.GLOW_SHADER, "%s : lueur à l'ouverture" % mi.name)


func test_power_switch_is_cubic() -> void:
	var root := Node3D.new()
	_keep(root)
	var parts := PowerSwitch.build_model(root)
	var lever: Node3D = parts.lever
	assert_eq(lever.position, Vector3(0, 0, PowerSwitch.LEVER_Z), "pivot du levier")
	assert_near(lever.rotation.x, -0.5, 0.0001, "levier relevé au repos")
	var arm := lever.get_child(0) as MeshInstance3D
	assert_true(arm != null, "bras du levier sous son pivot")
	_cubic(root, "levier du courant", [arm])
	# Levier remis droit : le modèle entier est sur la grille de l'objet.
	lever.rotation.x = 0.0
	_cubic(root, "levier du courant (bras droit)")
	assert_true((parts.beacon as MeshInstance3D).material_override is StandardMaterial3D, "gyrophare lumineux")


func test_trap_panels_are_cubic() -> void:
	var root := Node3D.new()
	_keep(root)
	var mat := StandardMaterial3D.new()
	var lamp := ElectricTrap.build_panel(root, mat)
	assert_eq(lamp.material_override, mat, "voyant au matériau du piège")
	_cubic(root, "panneau du piège")


func test_teleporter_pads_are_cubic() -> void:
	for obj in ["teleporteur", "arrivee"]:
		var root := Node3D.new()
		_keep(root)
		var mat := StandardMaterial3D.new()
		Teleporter.build_pad(root, obj, mat)
		_cubic(root, obj)
		assert_true(root.get_children().any(func(n): return n is MeshInstance3D and n.material_override == mat), "%s : anneau lumineux" % obj)


func test_mainframes_are_cubic() -> void:
	for obj in ["poste_central_mur", "poste_central_sol"]:
		var root := Node3D.new()
		_keep(root)
		var tube := StandardMaterial3D.new()
		var lamp := StandardMaterial3D.new()
		var parts := TeleporterMainframe.build_model(root, obj, tube, lamp)
		_cubic(root, obj)
		assert_eq((parts.voyant as MeshInstance3D).material_override, lamp, "%s : voyant" % obj)
		if parts.has("cable"):
			assert_true(VoxelCheck.check_mesh(parts.cable.mesh).ok, "%s : câble cubique" % obj)
			parts.cable.free()


func test_evac_door_is_cubic() -> void:
	var root := Node3D.new()
	_keep(root)
	var parts := EvacDoor.build_model(root)
	assert_eq((parts.panel as Node3D).position, EvacDoor.PANEL_REST, "battant fermé")
	_cubic(root, "porte d'évacuation (fermée)")
	(parts.panel as Node3D).position.z = -0.05
	_cubic(root, "porte d'évacuation (ouverte)")


func test_editor_crate_and_barrel_are_cubic() -> void:
	for spec in [["caisse", Vector3(1, 1, 1)], ["baril", Vector3(0.5, 0.9, 0.5)], ["caisse", Vector3(1.49, 1.0, 0.99)]]:
		var mi := MeshMapGeometry.decor_model(spec[0], spec[1])
		_keep(mi)
		assert_true(VoxelCheck.check_mesh(mi.mesh).ok, "%s : cubique" % spec[0])
		var size := mi.get_aabb().size
		assert_true(absf(size.x - spec[1].x) <= 0.026 and absf(size.y - spec[1].y) <= 0.026, "%s : taille du bloc (%s)" % [spec[0], size])
	# Dans la carte : collision du bloc gardée, visuel cubique « voxel__ ».
	var layout := {"blocks": [
		{"room": "a", "box": [0.0, 0.0, 0.0, 1.0, 1.0, 1.0], "mat": "crate"},
		{"room": "a", "box": [2.0, 0.0, 0.0, 2.5, 0.9, 0.5], "mat": "barrel"}]}
	var arch := MeshMapGeometry.build(layout)
	_keep(arch)
	var vis := arch.find_children("voxel__*", "MeshInstance3D", true, false)
	assert_eq(vis.size(), 2, "caisse et baril cubiques")
	assert_eq(arch.find_children("crate__*", "MeshInstance3D", true, false).size(), 0, "plus de pavé texturé")
	var crate_col := arch.get_node_or_null("crate__a__block__col") as StaticBody3D
	assert_true(crate_col != null, "collision de la caisse")
	if crate_col:
		var shape := (crate_col.get_child(0) as CollisionShape3D).shape as BoxShape3D
		assert_eq(shape.size, Vector3(1, 1, 1), "collision de la caisse inchangée")
		assert_true((crate_col.get_child(0) as CollisionShape3D).position.is_equal_approx(Vector3(0.5, 0.5, 0.5)), "à sa place")
	assert_true(arch.get_node_or_null("barrel__a__block__col") != null, "collision du baril")
