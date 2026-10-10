extends TestCase
## Architecture CUBIQUE, lot D (docs/VOXEL_ARCHITECTURE_PLAN.md § 2.3) :
## escaliers de tous les types et options, rampes, colimaçon, garde-corps et
## sols en pente rendus en cubes de 5 cm (faces axiales, sommets sur la
## grille du monde), marches de 3 ou 4 cubes de haut et d'au moins 5 cubes de
## giron, collisions inchangées, avertissement du validateur (marches de
## 25 cm), garde au plafond mesurée sur les marches en cubes.

const Stairs := preload("res://tests/test_stairs.gd")
const TopWall := preload("res://tests/test_stairs_top_wall.gd")

## Monde du jeu = éditeur + 4,25 m (sur la grille de 5 cm).
var off := MapGeom.WORLD_OFFSET


## Entrée « stairs » d'un type, dans le repère du jeu.
func _st(kind: String, opts := {}) -> Dictionary:
	var st := Stairs._spec(kind, opts)
	for k in ["a", "b"]:
		st[k] = [float(st[k][0]) + off, float(st[k][1]), float(st[k][2]) + off]
	return st


## Faces géométriques non axiales, sommets hors de la grille de 5 cm, triangles.
func _cubic(root: Node) -> Vector3i:
	var bad := 0
	var off_grid := 0
	var tris := 0
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		var vs: PackedVector3Array = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		tris += vs.size() / 3
		for i in range(0, vs.size(), 3):
			var n := (vs[i + 1] - vs[i]).cross(vs[i + 2] - vs[i]).normalized()
			if maxf(absf(n.x), maxf(absf(n.y), absf(n.z))) < 0.9999:
				bad += 1
		for v in vs:
			if not (VoxelCheck.on_grid(v.x, 0.05) and VoxelCheck.on_grid(v.y, 0.05) and VoxelCheck.on_grid(v.z, 0.05)):
				off_grid += 1
	return Vector3i(bad, off_grid, tris)


## Toutes les variantes : types, garde-corps, côtés fermés, virage à gauche,
## sortie sur le côté, escaliers tournés.
func _variants() -> Array:
	var out := []
	for kind: String in Stairs.KINDS:
		for opts: Dictionary in [{}, {"rail": true}, {"closed": true}, {"rail": true, "closed": true}]:
			out.append([kind, opts])
		if StairGen.is_shaped(kind):
			out.append([kind, {"turn": -1, "rail": true}])
		if StairGen.SIDE_KINDS.has(kind):
			out.append([kind, {"side": 1, "rail": true}])
			out.append([kind, {"side": -1, "closed": true}])
	return out


func test_every_stair_is_cubes_on_the_5cm_grid() -> void:
	var total := 0
	for v: Array in _variants():
		var st := _st(v[0], v[1])
		var t0 := Time.get_ticks_usec()
		var arch := MeshMapGeometry.build({"stairs": [st]})
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		var r := _cubic(arch)
		var what := "%s %s" % [v[0], v[1]]
		assert_eq(r.x, 0, what + " : faces axiales seulement")
		assert_eq(r.y, 0, what + " : sommets sur la grille de 5 cm")
		assert_true(r.z > 0, what + " : marches visibles")
		if (v[1] as Dictionary).is_empty() or v[1].has("rail") and v[1].size() == 1:
			print("[voxel_archi_stairs] %s : %d triangles, %.1f ms" % [what, r.z, ms])
		total += r.z
		arch.free()
	print("[voxel_archi_stairs] %d variantes : %d triangles" % [_variants().size(), total])


## Escaliers tournés (pas sur les axes) : marches en cubes de 10 cm alignés
## sur la grille du monde, garde-corps en cubes.
func test_rotated_stairs_are_cubes() -> void:
	for kind: String in ["droit", "palier", "quart", "demi_tour", "colimacon", "rampe"]:
		for deg: float in [30.0, 45.0]:
			var up := Vector2(0, -1).rotated(deg_to_rad(deg))
			var L := 7.0 if kind in ["droit", "palier", "rampe"] else 4.5
			var W := 2.0 if kind in ["droit", "palier", "rampe"] else 4.5
			var st := StairGen.spec(Vector2(12.0, 12.0), up, L, W, 0.0, 3.5, kind, {"rail": true})
			st["room"] = "r"
			var arch := MeshMapGeometry.build({"stairs": [st]})
			var r := _cubic(arch)
			assert_eq(r.x, 0, "%s tourné de %d° : faces axiales" % [kind, deg])
			assert_eq(r.y, 0, "%s tourné de %d° : sommets sur 5 cm" % [kind, deg])
			if deg == 30.0:
				print("[voxel_archi_stairs] %s tourné de 30° : %d triangles" % [kind, r.z])
			arch.free()


## Marches : 3 ou 4 cubes de haut (Bresenham, petites en bas), giron d'au
## moins 5 cubes, total = la hauteur ; rampe : un cube par marche.
func test_step_rules_in_whole_cubes() -> void:
	for N in range(6, 141):
		for run_c in [N * 2, N + 40, 400]:
			var H := N * StairGen.CUBE
			var run := float(run_c) * StairGen.CUBE
			var pl := {"y0": 0.0, "y1": H, "steps": 0}
			var n := StairGen.flight_steps(pl, H, run)
			var prev := 0
			var small_done := false
			var ok := true
			for k in n:
				var top := StairGen.rise_at(N, n, k)
				var h := top - prev
				prev = top
				if h > StairGen.MAX_RISE_CUBES or h < 1:
					ok = false
				if run_c / n >= StairGen.MIN_TREAD_CUBES * 1 and run_c >= n * StairGen.MIN_TREAD_CUBES:
					if h < 3 or h > 4:
						ok = false
				# Les petites marches d'abord : jamais une marche plus basse au-dessus d'une plus haute.
				if h < StairGen.rise_at(N, n, 0) and small_done:
					ok = false
				if h > StairGen.rise_at(N, n, 0):
					small_done = true
			assert_eq(prev, N, "H = %d cubes : hauteur totale" % N)
			assert_true(ok, "H = %d cubes, %d cubes de long : %d marches de 3 à 4 cubes (5 au plus)" % [N, run_c, n])
			if run_c >= N * 2:
				assert_true(run_c / n >= StairGen.MIN_TREAD_CUBES, "H = %d cubes : giron %d cubes (≥ 5)" % [N, run_c / n])
	var ramp := {"kind": "rampe", "y0": 0.0, "y1": 1.5, "steps": 0}
	assert_eq(StairGen.flight_steps(ramp, 1.5, 6.0), 30, "rampe : une marche par cube")
	# Marche au cube près, giron entier : pas du tout au long d'une volée de 3,5 m sur 7 m.
	var tops := {}
	for i in 140:
		tops[snappedf(StairGen.step_top(0.0, 3.5, 7.0, 18, (i + 0.5) * 0.05), 0.0001)] = true
	assert_eq(tops.size(), 18, "18 marches distinctes")
	for y: float in tops:
		assert_true(VoxelCheck.on_grid(y, 0.05), "dessus de marche sur 5 cm (%.3f)" % y)


## Paliers (palier, en L, en U) à une hauteur multiple du cube, même pour
## une montée impaire.
func test_landings_on_the_cube() -> void:
	for kind: String in ["palier", "quart", "demi_tour"]:
		var st := Stairs._spec(kind)
		st["b"] = [st.b[0], 3.35, st.b[2]]
		var pl := StairGen.plan(st)
		for l in pl.landings:
			assert_true(VoxelCheck.on_grid(float(l.y), 0.05), "%s : palier à %.3f m" % [kind, float(l.y)])


## Collisions inchangées : rampe pleine (6 points) sous la volée droite, une
## seule forme ; le visuel est en cubes (plus de pavés tournés de 6 faces).
func test_straight_stair_collision_unchanged() -> void:
	var st := {"room": "r", "a": [10.0, 0.0, 20.0], "b": [10.0, 3.5, 13.0], "w": 2.5, "mat": "wood"}
	var arch := MeshMapGeometry.build({"stairs": [st]})
	var body := arch.get_node("wood__r__stair__col") as StaticBody3D
	assert_eq(body.get_child_count(), 1, "une rampe pleine")
	var pts: PackedVector3Array = ((body.get_child(0) as CollisionShape3D).shape as ConvexPolygonShape3D).points
	assert_eq(pts.size(), 6, "coin plein : 6 points")
	var r := _cubic(arch)
	assert_eq(r.x + r.y, 0, "marches en cubes")
	# 18 marches de 3 ou 4 cubes, giron de 7 à 8 cubes : dessus, contremarche,
	# deux flancs par marche, plus le dos : (4 × 18 + 1) quadrilatères.
	assert_eq(r.z, (4 * 18 + 1) * 2, "faces cachées retirées (%d triangles ; avant : 19 × 12 = 228)" % r.z)
	arch.free()


## Garde-corps de niveau (« rails ») : en cubes, main courante à + 1,0 m,
## collision : le même pavé qu'avant.
func test_level_rails_are_cubes() -> void:
	var L := {"rails": [{"room": "m", "path": [[10.0, 14.0], [16.0, 14.0], [16.0, 20.0]], "y": 3.5, "h": 1.0, "mat": "dark_wood"}]}
	var arch := MeshMapGeometry.build(L)
	var r := _cubic(arch)
	assert_eq(r.x + r.y, 0, "garde-corps en cubes sur la grille")
	var top := -INF
	for v: Vector3 in (arch.get_node("dark_wood__m__rail") as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		top = maxf(top, v.y)
	assert_near(top, 4.5, 0.001, "main courante : dessus à + 1,0 m")
	var body := arch.get_node("dark_wood__m__rail__col") as StaticBody3D
	assert_eq(body.get_child_count(), 2, "un pavé de collision par tronçon")
	print("[voxel_archi_stairs] garde-corps de 12 m : %d triangles" % r.z)
	arch.free()


## Sol en pente (test_levels) : terrasses de 5 cm en cubes ; collision : le
## plan incliné.
func test_slope_floor_terraces() -> void:
	var L := {"rooms": [{"id": "pente", "outline": [[10, 22.15], [22.15, 22.15], [22.15, 32], [10, 32]],
		"slope": [[10, 0.0, 22.15], [22.15, 0.0, 22.15], [10, -1.5, 32]], "ceiling": 5.0, "no_ceiling": true}]}
	var t0 := Time.get_ticks_usec()
	var arch := MeshMapGeometry.build(L)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	var r := _cubic(arch)
	assert_eq(r.x + r.y, 0, "terrasses en cubes sur la grille")
	print("[voxel_archi_stairs] salle en pente : %d triangles, %.0f ms" % [r.z, ms])
	var body := arch.get_node("floor__pente__floor__col") as StaticBody3D
	assert_true(((body.get_child(0) as CollisionShape3D).shape as ConcavePolygonShape3D) != null, "collision : le plan incliné")
	arch.free()


## Validateur : marches de 25 cm (volée trop courte pour sa hauteur) :
## avertissement ; escalier courant : rien.
func test_validator_warns_on_25cm_steps() -> void:
	var doc := Stairs.stairs_map()
	var v := Stairs._check(doc)
	assert_false(v.messages.any(func(m): return String(m.fr).contains("marches de 25 cm")), "escaliers d'essai : marches de 20 cm au plus")
	# Escalier droit de 4 m pour 3,25 m (39° : giron de 25 cm, 16 marches au
	# plus pour 65 cubes, donc des marches de 5 cubes).
	doc.pieces[1]["altitude"] = 3.25
	for o in doc.objets:
		if o.get("type") == "escalier" and MapCatalog.stair_kind(o) == "droit":
			o["rect"] = [o.rect[0], 9, o.rect[2], 13]
	v = Stairs._check(doc)
	var warn: Array = v.messages.filter(func(m): return String(m.fr).contains("marches de 25 cm"))
	assert_eq(warn.size(), 1, "avertissement des marches de 25 cm")
	if warn.size() == 1:
		assert_eq(String(warn[0].level), "attention", "un avertissement, pas une erreur")
		assert_true(String(warn[0].en).contains("25 cm steps"), "texte anglais")


## Garde au plafond : mesurée sur le dessus des marches en cubes (step_y) :
## au plus un cube sous la surface de collision (marches arrondies au cube
## inférieur), au plus une marche au-dessus.
func test_step_y_covers_the_collision_surface() -> void:
	for kind: String in Stairs.KINDS:
		var pl := StairGen.plan(Stairs._spec(kind))
		var bb := Rect2()
		for poly: PackedVector2Array in pl.polys:
			for q in poly:
				bb = Rect2(q, Vector2.ZERO) if bb.size == Vector2.ZERO and bb.position == Vector2.ZERO else bb.expand(q)
		var worst := 0.0
		for j in 40:
			for i in 40:
				var q := bb.position + bb.size * Vector2((i + 0.5) / 40.0, (j + 0.5) / 40.0)
				var ys := StairGen.surface_y(pl, q)
				var yv := StairGen.step_y(pl, q)
				if is_nan(ys) or is_nan(yv):
					continue
				assert_true(yv >= ys - StairGen.CUBE - 0.001, "%s : marche visible au plus un cube sous la collision en %s (%.3f / %.3f)" % [kind, q, yv, ys])
				worst = maxf(worst, yv - ys)
		assert_true(worst <= 0.3, "%s : au plus une marche au-dessus de la collision (%.2f m)" % [kind, worst])
