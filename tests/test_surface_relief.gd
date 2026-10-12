extends TestCase
## Relief des surfaces (SurfaceRelief) : déterministe (même carte, même
## relief ; autre graine, autre relief), jamais sur les endroits de jeu
## (seuils, fenêtres, évacuation, apparitions, escaliers), collisions
## inchangées, creux d'un cube au plus dans les sols, tout sur la grille de
## 5 cm ; découpe des faces exacte ; planches des barricades variées mais
## cubiques et déterministes.

const LEVELS := "res://assets/maps/test_levels/layout.json"


static func _bunker() -> MapDef:
	return load(Game.MAP_SCRIPTS["bunker_k7"]).new()


static func _levels() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(LEVELS))


static func _cells_of(rel: SurfaceRelief) -> Dictionary:
	var out := {}
	for fid in rel._planes:
		var c: Dictionary = rel._planes[fid].cells
		var keys := c.keys()
		keys.sort()
		out[fid] = keys
	return out


func test_seed_is_stable_and_distinct() -> void:
	assert_eq(SurfaceRelief.seed_of("bunker_k7"), SurfaceRelief.seed_of("bunker_k7"))
	assert_true(SurfaceRelief.seed_of("bunker_k7") != SurfaceRelief.seed_of("test_levels"), "graines distinctes")
	# FNV-1a 32 bits : valeur figée (même relief sur toutes les machines et versions).
	assert_eq(SurfaceRelief.seed_of("a"), 0xE40C292C)


func test_grid_map_relief_is_deterministic() -> void:
	var def := _bunker()
	var data := MapData.parse(def.rows)
	var a := MapBuilder.new(data, def).plan_relief()
	var b := MapBuilder.new(data, def).plan_relief()
	assert_true(a.piece_count() > 100, "relief du BUNKER K-7 (%d pièces)" % a.piece_count())
	assert_eq(a.piece_count(), b.piece_count())
	assert_true(_cells_of(a) == _cells_of(b), "mêmes creux d'une construction à l'autre")
	def.id = "autre_graine"
	var c := MapBuilder.new(data, def).plan_relief()
	assert_true(_cells_of(a) != _cells_of(c), "autre graine : autre relief")


func test_grid_map_relief_avoids_gameplay_spots() -> void:
	var def := _bunker()
	var data := MapData.parse(def.rows)
	var rel := MapBuilder.new(data, def).plan_relief()
	var keep := {}
	for sym: String in data.markers:
		if sym == "L":
			continue
		var r := 0 if (sym in MapDef.BLOCKING_PROPS or sym == ",") else 1
		for c: Vector2i in data.markers[sym]:
			for dy in range(-r, r + 1):
				for dx in range(-r, r + 1):
					keep[c + Vector2i(dx, dy)] = sym
	var floor_cells := rel.pit_cells(Vector3i.UP, 0.0)
	assert_true(floor_cells.size() > 200, "creux au sol (%d cubes)" % floor_cells.size())
	var bad := []
	for k: Vector2i in floor_cells:
		var c := Vector2i(floori(k.x * 0.05), floori(k.y * 0.05))
		if keep.has(c) or not data.is_floor(c):
			bad.append([c, keep.get(c, "#")])
	assert_true(bad.is_empty(), "aucun creux près d'une porte, fenêtre, évacuation, station, apparition (%s)" % [bad.slice(0, 5)])
	# Murs : aucun creux ni plinthe devant une fenêtre ou la porte d'évacuation.
	var evac: Vector2i = data.markers["@"][0]
	var west := rel.pit_cells(Vector3i(1, 0, 0), float(evac.x))
	for k: Vector2i in west:
		assert_true(absf(k.x * 0.05 - (evac.y + 0.5)) > 1.4, "pas de creux derrière la porte d'évacuation")


func test_floor_pits_are_one_cube_deep_and_on_the_grid() -> void:
	var def := _bunker()
	var data := MapData.parse(def.rows)
	var rel := MapBuilder.new(data, def).plan_relief()
	var acc := {"low": INF, "high": -INF, "off": 0}
	rel.emit(func(_k: String, _t: String, p: Array, _n: Vector3) -> void:
		for v: Vector3 in p:
			if v.y < 1.0:
				acc.low = minf(acc.low, v.y)
			else:
				acc.high = maxf(acc.high, v.y)
			if not (LayoutCheck.on_grid(v.x) and LayoutCheck.on_grid(v.y) and LayoutCheck.on_grid(v.z)):
				acc.off += 1)
	assert_near(acc.low, -0.05, 0.0005, "creux du sol : 5 cm au plus")
	assert_true(acc.high <= MapBuilder.WALL_HEIGHT + 0.1 + 0.0005, "dalles tombées : 10 cm au plus au-dessus du plafond (%.3f)" % acc.high)
	assert_eq(acc.off, 0, "sommets du relief sur la grille de 5 cm")
	_ok(LayoutCheck.check_def(def), "BUNKER K-7 avec relief")


func _ok(rep: Dictionary, what: String) -> void:
	assert_true(rep.ok, "%s : %s" % [what, rep.get("fr", "")])


## Signature de toutes les collisions sous `root` (formes, tailles, points, place).
static func _collision_sig(root: Node) -> Array:
	var out := []
	for cs: CollisionShape3D in root.find_children("*", "CollisionShape3D", true, false):
		var s := cs.shape
		var d: Variant = null
		if s is BoxShape3D:
			d = (s as BoxShape3D).size
		elif s is ConcavePolygonShape3D:
			d = (s as ConcavePolygonShape3D).get_faces()
		elif s is ConvexPolygonShape3D:
			d = (s as ConvexPolygonShape3D).points
		out.append([String(cs.get_parent().name), s.get_class(), d, cs.global_transform if cs.is_inside_tree() else cs.transform])
	out.sort_custom(func(a, b): return str(a) < str(b))
	return out


func test_relief_never_changes_collisions() -> void:
	var L := _levels()
	SurfaceRelief.enabled = false
	var plain := MeshMapGeometry.build(L)
	SurfaceRelief.enabled = true
	var rel := MeshMapGeometry.build(L)
	assert_true(rel.find_children("*__relief", "MeshInstance3D", true, false).size() > 0, "test_levels : relief construit")
	assert_true(_collision_sig(plain) == _collision_sig(rel), "test_levels : collisions identiques avec et sans relief")
	plain.free()
	rel.free()
	# Carte en grille : collisions de MapBuilder.
	var def := _bunker()
	var data := MapData.parse(def.rows)
	var sigs := []
	for on in [false, true]:
		SurfaceRelief.enabled = on
		var holder := Node3D.new()
		var t0 := Time.get_ticks_usec()
		MapBuilder.new(data, def).build(holder)
		var tris := 0
		for mi: MeshInstance3D in holder.find_children("*", "MeshInstance3D", true, false):
			tris += mi.mesh.get_faces().size()
		print("[relief] BUNKER K-7 %s : construction %.0f ms, %d triangles" % ["avec relief" if on else "sans relief",
			(Time.get_ticks_usec() - t0) / 1000.0, roundi(tris / 3.0)])
		sigs.append(_collision_sig(holder))
		holder.free()
	SurfaceRelief.enabled = true
	assert_true(sigs[0] == sigs[1], "BUNKER K-7 : collisions identiques avec et sans relief")


func test_mesh_map_relief_avoids_stairs_and_markers() -> void:
	var L := _levels()
	var g := MeshMapGeometry.new()
	var root := g._build(L)
	var rel := g._relief
	assert_true(rel != null and rel.piece_count() > 20, "test_levels : relief repéré")
	var cells := rel.pit_cells(Vector3i.UP, 0.0)
	var st: Dictionary = L.stairs[0]
	var sb := Rect2(Vector2(st.a[0], st.a[2]), Vector2.ZERO).expand(Vector2(st.b[0], st.b[2])).grow(float(st.w) * 0.5 + 1.0)
	# Marqueurs au sol (les lampes sont au plafond).
	var pts := []
	var floor_markers: Dictionary = (L.markers as Dictionary).duplicate()
	floor_markers.erase("lamps")
	MeshMapGeometry._marker_points(floor_markers, pts)
	assert_true(pts.size() > 5, "marqueurs relevés (%d)" % pts.size())
	for k: Vector2i in cells:
		var q := (Vector2(k) + Vector2.ONE * 0.5) * 0.05
		assert_false(sb.has_point(q), "pas de creux au pied de l'escalier (%s)" % q)
		for p: Vector2 in pts:
			if absf(p.x - q.x) < 0.95 and absf(p.y - q.y) < 0.95:
				assert_true(false, "creux en %s trop près d'un marqueur %s" % [q, p])
				return
	_ok(LayoutCheck.check(L), "test_levels avec relief")
	root.free()


func test_editor_map_walls_get_relief() -> void:
	# Carte de l'éditeur : murs en blocs de demi-cases, réunis en pans pour
	# le relief (plinthes, cimaises, creux) ; tout sur la grille.
	var data: Dictionary = MapPreviewWorld.compute(EditorMap.load_dir(EditorMap.EXAMPLES.draft_arena)).data
	var g := MeshMapGeometry.new()
	var root := g._build(data)
	var walls := 0
	var pits := 0
	for pc: Dictionary in g._relief._pieces:
		var f: SurfaceRelief.Frame = pc.f
		if f.axis != 1:
			walls += 1
			if pc.pit:
				pits += 1
	assert_true(walls > 50, "DRAFT ARENA : relief des murs (%d pièces)" % walls)
	assert_true(pits > 3, "DRAFT ARENA : creux dans les murs (%d)" % pits)
	root.free()
	_ok(LayoutCheck.check(data), "DRAFT ARENA avec relief")


func test_rect_minus_covers_exactly() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for t in 40:
		var r := Rect2i(rng.randi_range(-30, 30), rng.randi_range(-30, 30), rng.randi_range(5, 40), rng.randi_range(5, 40))
		var holes := []
		var cov := {}
		for k in rng.randi_range(1, 4):
			var h := Rect2i(r.position + Vector2i(rng.randi_range(0, r.size.x - 2), rng.randi_range(0, r.size.y - 2)),
				Vector2i(rng.randi_range(1, 8), rng.randi_range(1, 8))).intersection(r)
			holes.append(h)
			for j in range(h.position.y, h.end.y):
				for i in range(h.position.x, h.end.x):
					cov[Vector2i(i, j)] = true
		var parts := SurfaceRelief.rect_minus(r, holes)
		var seen := {}
		for p: Rect2i in parts:
			for j in range(p.position.y, p.end.y):
				for i in range(p.position.x, p.end.x):
					assert_false(seen.has(Vector2i(i, j)), "rectangles disjoints")
					assert_false(cov.has(Vector2i(i, j)), "rien dans un creux")
					seen[Vector2i(i, j)] = true
		assert_eq(seen.size() + cov.size(), r.get_area(), "toute la face hors des creux")


func test_wall_trims_stop_at_reserved_spots() -> void:
	var rel := SurfaceRelief.new()
	rel.seed = 7
	# Mur de normale +z en z = 0, de x = 0 à 6 m ; réservé de x = 2 à 3 m.
	rel.plan_wall("wall_green", Vector3i(0, 0, 1), 0.0, 0.0, 6.0, 0.0, 3.2, 0.0,
		func(x: float, _z: float) -> bool: return x < 2.0 or x > 3.0)
	var boxes := 0
	for pc: Dictionary in rel._pieces:
		if pc.pit:
			for c: Vector2i in pc.cells:
				assert_true(c.x * 0.05 < 2.0 or c.x * 0.05 >= 3.0, "pas de creux dans la zone réservée")
			continue
		boxes += 1
		var r: Rect2i = pc.rect
		assert_true(r.end.x * 0.05 <= 2.0 + 0.001 or r.position.x * 0.05 >= 3.0 - 0.001,
			"plinthe et cimaise interrompues devant la zone réservée (%s)" % r)
	assert_eq(boxes, 4, "plinthe et cimaise de chaque côté")


func test_menu_backdrop_has_relief() -> void:
	var b := MenuBackdrop.new()
	var rel := b._plan_relief()
	assert_true(rel.piece_count() > 20, "fond du menu : relief (%d pièces)" % rel.piece_count())
	b.free()


func test_barricade_plank_variants() -> void:
	for s in [0, 7, 777, 123456]:
		for i in 10:
			var v := Barricade.plank_variant(s, i)
			assert_true(v >= 0 and v < Barricade.PLANK_VARIANTS, "modèle dans les bornes")
			assert_eq(v, Barricade.plank_variant(s, i), "même modèle à chaque fois")
	var seen := {}
	for i in 10:
		seen[Barricade.plank_variant(777, i)] = true
	assert_true(seen.size() >= 2, "planches variées dans une barricade")
	for door in [false, true]:
		var size := Barricade.DOOR_PLANK_SIZE if door else Barricade.PLANK_SIZE
		for v in Barricade.PLANK_VARIANTS:
			var m := Barricade.plank_mesh(size, v, door)
			assert_true(VoxelCheck.check_mesh(m).ok, "planche %d cubique" % v)
			var bb := m.get_aabb()
			assert_true(absf(bb.size.x - size.x) <= 0.1 + 0.001, "longueur proche de la nominale (%s)" % bb.size)
			assert_true(bb.size.z <= (0.05 if door else 0.1) + 0.001, "épaisseur (%s)" % bb.size)
			# Couche de devant à la place de la planche nominale (dessus : un cube de plus au plus).
			assert_near(bb.end.z, size.z * 0.5, 0.001, "face avant à la place nominale")
			assert_near(bb.position.y, -size.y * 0.5, 0.001, "dessous à la place nominale")
