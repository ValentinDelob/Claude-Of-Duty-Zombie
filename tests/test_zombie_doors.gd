extends TestCase
## Portes à zombies (format 8, docs/MAP_OBJECTS.md § 9) : entrée des zombies
## de type fenêtre (d'avant), porte simple ou porte double. Catalogue, JSON
## (format 8 relu, formats d'avant inchangés), contrôle des cartes reçues,
## validateur (largeur, cour, mur plein de chaque côté), découpe du mur (pas
## d'allège), description en maillage, épaisseur de la porte construite
## (10 cm au plus), règles des planches et des zombies qui arrachent.

const FIXTURES := "res://tests/fixtures/maps/"
const OFF := MapGeom.WORLD_OFFSET


static func fixture(id: String) -> EditorMap:
	var texts := {}
	for f in EditorMap.FILES:
		texts[f] = FileAccess.get_file_as_string(FIXTURES + id + "/" + f)
	return EditorMap.from_texts(texts)


static func analyzed(doc: EditorMap) -> MapValidator:
	var v := MapRaster.build(doc).v
	v.analyze()
	return v


static func _errs(v: MapValidator) -> String:
	return "\n".join(v.errors().map(func(m): return String(m.fr)))


## Barricade construite (sans partie) pour la fenêtre `i` de la carte.
func built(doc: EditorMap, i := 0) -> Barricade:
	var def := EditorMapDef.from_map(doc, "perso:" + String(doc.carte.id))
	var layout := MeshMapLayout.new(def, def.layout_data, "")
	var w: BarricadeLayout.Opening = layout.windows()[i]
	var b := Barricade.new()
	b.setup(w)
	host.add_child(b)
	return b


# ------------------------------------------------------------------ catalogue et règles

func test_kinds_rules() -> void:
	assert_eq(MapCatalog.variants("fenetre"), ["fenetre", "porte", "porte_double"])
	assert_eq(MapCatalog.default_variant("fenetre"), "fenetre", "par défaut : la fenêtre d'avant")
	assert_near(MapCatalog.barricade_width("fenetre"), 1.0)
	assert_near(MapCatalog.barricade_width("porte"), 1.0, 0.001, "porte simple : 1 m")
	assert_near(MapCatalog.barricade_width("porte_double"), 2.0, 0.001, "porte double : 2 m")
	assert_near(MapRules.opening_width({"type": "fenetre", "variante": "porte_double"}), 2.0)
	assert_near(MapRules.opening_width({"type": "fenetre"}), 1.0)
	for k in BarricadeRules.KINDS:
		assert_true(MapCatalog.variants("fenetre").has(k), "type %s dans le catalogue" % k)
		assert_near(BarricadeRules.width(k), MapCatalog.barricade_width(k), 0.001, "même largeur jeu / éditeur (%s)" % k)
	# Planches, zombies qui arrachent, file.
	assert_eq(BarricadeRules.planks_for("fenetre"), 6)
	assert_eq(BarricadeRules.planks_for("porte"), 6, "porte simple : 6 planches")
	assert_eq(BarricadeRules.planks_for("porte_double"), 10, "porte double : 5 planches par battant")
	assert_eq(BarricadeRules.tearers("porte"), 1, "porte simple : un seul zombie arrache à la fois")
	assert_eq(BarricadeRules.tearers("porte_double"), 2, "porte double : deux à la fois")
	assert_eq(BarricadeRules.queue_max("porte"), 4, "1 qui arrache + 3 qui attendent")
	assert_eq(BarricadeRules.queue_max("porte_double"), 6, "2 qui arrachent + 4 qui attendent")
	assert_false(BarricadeRules.queue_full(3, "porte"))
	assert_true(BarricadeRules.queue_full(4, "porte"))
	assert_false(BarricadeRules.queue_full(5, "porte_double"))
	assert_true(BarricadeRules.queue_full(6, "porte_double"))
	assert_true(BarricadeRules.queue_full(3), "fenêtre : règle d'avant (3)")
	assert_true(BarricadeRules.full_mask_for("porte_double") < (1 << 16), "masque sur 16 bits")


func test_double_door_tears_each_leaf() -> void:
	var n := BarricadeRules.planks_for("porte_double")
	var m := BarricadeRules.full_mask_for("porte_double")
	assert_eq(BarricadeRules.count_lane(m, n, 2, 0), 5, "5 planches sur le battant gauche")
	assert_eq(BarricadeRules.count_lane(m, n, 2, 1), 5, "5 sur le droit")
	# Chacun arrache celles de son battant.
	var i0 := BarricadeRules.plank_to_tear_lane(m, n, 2, 0)
	var i1 := BarricadeRules.plank_to_tear_lane(m, n, 2, 1)
	assert_eq(BarricadeRules.lane_of_plank(i0, 2), 0)
	assert_eq(BarricadeRules.lane_of_plank(i1, 2), 1)
	# Battant vide : il aide l'autre ; plus rien : -1.
	var left_only := 0
	for i in n:
		if BarricadeRules.lane_of_plank(i, 2) == 0:
			left_only |= 1 << i
	assert_eq(BarricadeRules.lane_of_plank(BarricadeRules.plank_to_tear_lane(left_only, n, 2, 1), 2), 0, "battant droit vide : il arrache à gauche")
	assert_eq(BarricadeRules.plank_to_tear_lane(0, n, 2, 0), -1)
	# La réparation alterne les battants.
	assert_eq(BarricadeRules.lane_of_plank(BarricadeRules.plank_to_repair(0, n), 2), 0)
	assert_eq(BarricadeRules.lane_of_plank(BarricadeRules.plank_to_repair(1, n), 2), 1)
	assert_eq(BarricadeRules.plank_to_repair(m, n), -1)


## Cadence : simulation image par image des zombies postés (tear_tick) ;
## porte simple : un seul zombie, 6 planches ; porte double : deux zombies
## (un par battant), 10 planches ; la double tombe presque deux fois plus
## vite par planche.
func test_tear_timing_per_kind() -> void:
	var sim := func(kind: String, seed_v: int) -> float:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_v
		var n := BarricadeRules.planks_for(kind)
		var lanes := BarricadeRules.lanes(kind)
		var mask := BarricadeRules.full_mask_for(kind)
		var st := []
		for t in BarricadeRules.tearers(kind):
			st.append([false, 0.0, 0.0])
		var now := 0.0
		var dt := 1.0 / 60.0
		while mask != 0 and now < 120.0:
			now += dt
			for t in st.size():
				var s: Array = st[t]
				var r := BarricadeRules.tear_tick(s[0], s[1], s[2], dt, rng.randf())
				st[t] = [r.x > 0.5, r.y, r.z]
				if r.w > 0.5:
					var i := BarricadeRules.plank_to_tear_lane(mask, n, lanes, t % lanes)
					if i >= 0:
						mask &= ~(1 << i)
		return now
	var single := 0.0
	var double := 0.0
	for k in 5:
		single += sim.call("porte", k + 1) / 5.0
		double += sim.call("porte_double", k + 1) / 5.0
	var per_single := single / 6.0
	var per_double := double / 10.0
	assert_near(per_single, BarricadeRules.TEAR_TIME, 0.35, "porte simple : une planche toutes les 2,5 s (%.2f)" % per_single)
	assert_true(per_double < per_single * 0.62, "porte double : deux à la fois, ~2x plus vite par planche (%.2f contre %.2f s)" % [per_double, per_single])


# ------------------------------------------------------------------ JSON et contrôle

func test_format_8_round_trip_and_old_maps() -> void:
	assert_true(EditorMap.FORMAT >= 8, "format 8 et plus (%d)" % EditorMap.FORMAT)
	for id in ["smallest_door", "smallest_double_door"]:
		var doc := fixture(id)
		assert_eq(doc.load_errors, [], "%s lue" % id)
		var o := doc.find("o1")
		assert_eq(MapCatalog.barricade_kind(o), "porte" if id == "smallest_door" else "porte_double")
		var texts := doc.file_texts()
		assert_true(String(texts["carte.json"]).contains("\"format\": %d" % EditorMap.FORMAT), "réécrite au format courant")
		var again := EditorMap.from_texts(texts)
		assert_eq(again.file_texts(), texts, "%s relue à l'identique" % id)
		assert_eq(MapCatalog.barricade_kind(again.find("o1")), MapCatalog.barricade_kind(o))
	# La fenêtre par défaut n'écrit pas de variante ; V revient à la fenêtre.
	var w := {"type": "fenetre", "variante": "porte"}
	assert_true(MapCatalog.set_variant(w, "fenetre"))
	assert_false(w.has("variante"), "fenêtre : pas de clé (carte d'avant inchangée)")
	assert_eq(MapCatalog.next_variant("fenetre", "porte_double"), "fenetre", "V : en boucle")
	# Carte d'avant (format 5, SMALLEST) : lue et décrite exactement comme avant.
	var old := fixture("smallest")
	assert_eq(old.format_read, 5)
	assert_false(old.find("o1").has("variante"))
	var data := EditorMapDef.from_map(old, "perso:smallest").layout_data
	var win: Dictionary = data.markers.windows[0]
	assert_eq(win.keys(), ["p", "in", "h", "zone", "spawns"], "fenêtre d'avant : mêmes clés, dans le même ordre")
	assert_near(float(win.h), MapValidator.LINTEL, 0.001)
	# Variante inconnue écrite à la main : la fenêtre d'avant.
	var hand := old.file_texts()
	hand["ouvertures.json"] = String(hand["ouvertures.json"]).replace("\"id\":\"o1\"", "\"id\":\"o1\",\"variante\":\"porte_triple\"")
	assert_false(EditorMap.from_texts(hand).find("o1").has("variante"), "type inconnu retiré à la lecture")


func test_guard_accepts_doors_and_refuses_bad_values() -> void:
	for id in ["smallest_door", "smallest_double_door"]:
		var texts := fixture(id).file_texts()
		assert_eq(CustomMapGuard.check_texts(texts).reasons, [], "%s acceptée" % id)
		assert_true(bool(CustomMapGuard.check_full(texts).get("ok", false)), "%s jouable" % id)
	var base := fixture("smallest_door").file_texts()
	for bad in ["\"variante\":\"porte_triple\"", "\"variante\":\"bois\"", "\"variante\":2", "\"variante\":\"res://x.tscn\"", "\"variante\":\"porte\",\"largeur\":2"]:
		var t := base.duplicate()
		t["ouvertures.json"] = String(t["ouvertures.json"]).replace("\"variante\":\"porte\"", bad)
		assert_false(CustomMapGuard.check_texts(t).reasons.is_empty(), "refusée : %s" % bad)


# ------------------------------------------------------------------ validateur et export

func test_validator_accepts_both_doors() -> void:
	for id in ["smallest_door", "smallest_double_door"]:
		var v := analyzed(fixture(id))
		assert_eq(_errs(v), "", "%s : aucune erreur" % id)
		assert_eq(v.windows.size(), 1)
		if v.windows.size() == 1:
			assert_eq(String(v.windows[0].kind), "porte" if id == "smallest_door" else "porte_double")
			var r: Rect2i = v.windows[0].rect
			assert_eq(maxi(r.size.x, r.size.y), 2 if id == "smallest_door" else 4, "largeur en cases (0,5 m)")


## Règles de pose : sur un mur extérieur, cour libre derrière (4 m pour la
## double), 0,5 m de mur plein de chaque côté, largeur qui tient.
func test_validator_rules_for_doors() -> void:
	var doc := EditorMap.blank("regles_portes", "RÈGLES", "RULES")
	var z := String(doc.add_zone("Salle", "Room").id)
	doc.pieces.append({"id": "p1", "nom": "Salle", "etage": 0, "zone": z, "contour": [[0, 0], [10, 0], [10, 6], [0, 6]]})
	doc.depart = z
	doc.objets.append({"id": "s1", "type": "depart", "etage": 0, "position": [5.0, 3.0]})
	# Mur nord : 10 m ; une porte double au milieu se pose.
	var ok := MapRules.place_opening(doc, 0, "fenetre", Vector2(5.0, 0.0), 2.0)
	assert_true(ok.ok, "porte double posée sur un mur extérieur : %s" % MapRules.why(ok))
	# Trop près d'un angle : recalée pour garder 0,5 m de mur plein.
	var corner := MapRules.place_opening(doc, 0, "fenetre", Vector2(0.4, 0.0), 2.0)
	assert_true(corner.ok)
	if corner.ok:
		assert_true(float(corner.position[0]) - 1.0 >= 0.5 - 0.01, "0,5 m de mur plein au bout (%s)" % str(corner.position))
	# Mur trop court : une salle de 2,5 m de large ne prend pas de double.
	var small := EditorMap.blank("petit", "PETIT", "SMALL")
	var z2 := String(small.add_zone("S", "S").id)
	small.pieces.append({"id": "p1", "nom": "S", "etage": 0, "zone": z2, "contour": [[0, 0], [2.5, 0], [2.5, 4], [0, 4]]})
	assert_false(MapRules.place_opening(small, 0, "fenetre", Vector2(1.25, 0.0), 2.0).ok, "mur de 2,5 m : pas de porte double (3 m)")
	assert_true(MapRules.place_opening(small, 0, "fenetre", Vector2(1.25, 0.0), 1.0).ok, "mais une porte simple tient")
	# Cour : une pièce voisine à 3 m derrière gêne une porte double à son bout.
	var near := EditorMap.blank("cour", "COUR", "YARD")
	var z3 := String(near.add_zone("A", "A").id)
	near.pieces.append({"id": "p1", "nom": "A", "etage": 0, "zone": z3, "contour": [[0, 4], [10, 4], [10, 10], [0, 10]]})
	near.pieces.append({"id": "p2", "nom": "B", "etage": 0, "zone": z3, "contour": [[6.6, 0], [9, 0], [9, 2], [6.6, 2]]})
	assert_true(MapRules.place_opening(near, 0, "fenetre", Vector2(4.0, 4.0), 1.0).ok, "fenêtre : cour de 3 m libre")
	assert_false(MapRules.place_opening(near, 0, "fenetre", Vector2(5.0, 4.0), 2.0).ok, "porte double : cour de 4 m gênée par B")
	# Changer le type d'une fenêtre posée : la double doit tenir à sa place.
	small.ouvertures.append({"id": "o1", "type": "fenetre", "etage": 0, "position": [1.25, 0.0]})
	var o := small.find("o1")
	assert_true(MapRules.apply_variant(small, o, "porte").ok, "fenêtre -> porte simple")
	assert_eq(MapCatalog.barricade_kind(o), "porte")
	assert_false(MapRules.apply_variant(small, o, "porte_double").ok, "refusée : la double ne tient pas")
	assert_eq(MapCatalog.barricade_kind(o), "porte", "rien changé")
	# Validateur : une double dont le fichier dit 1 m de mur... (largeur suivie du
	# type) ; un fichier qui la pose dans un mur trop court est signalé.
	small.ouvertures[0]["variante"] = "porte_double"
	small.objets.append({"id": "s1", "type": "depart", "etage": 0, "position": [1.25, 2.0]})
	small.depart = z2
	var v := analyzed(small)
	assert_true(_errs(v) != "", "porte double dans un mur trop court : erreur")


## Le point `q` est-il dans la maçonnerie (blocs de la grille ou murs en
## biais, ouvertures déduites) ?
static func solid_at(data: Dictionary, q: Vector3) -> bool:
	for b in data.blocks:
		var bx: Array = b.box
		if q.x > float(bx[0]) and q.x < float(bx[3]) and q.y > float(bx[1]) and q.y < float(bx[4]) and q.z > float(bx[2]) and q.z < float(bx[5]):
			return true
	for o in data.get("obliques", []):
		var a := Vector2(o.a[0], o.a[1])
		var b := Vector2(o.b[0], o.b[1])
		var t := (b - a).normalized()
		var p2 := Vector2(q.x, q.z) - a
		var along := p2.dot(t)
		if along < 0.0 or along > a.distance_to(b) or absf(p2.dot(Vector2(-t.y, t.x))) > float(o.thick) * 0.5:
			continue
		if q.y < float(o.y0) or q.y > float(o.y1):
			continue
		var cut := false
		for c in o.openings:
			cut = cut or (absf(along - float(c.t)) < float(c.w) * 0.5 and q.y > float(c.y0) and q.y < float(c.y1))
		if not cut:
			return true
	return false


## Carte sur la grille : une salle de 10 × 6 m, une entrée de type `kind` au
## milieu du mur nord (mur droit de la grille : blocs, pas un mur en biais).
static func grid_map(kind: String) -> EditorMap:
	var doc := EditorMap.blank("grille_" + kind, "GRILLE", "GRID")
	var z := String(doc.add_zone("Salle", "Room").id)
	doc.pieces.append({"id": "p1", "nom": "Salle", "etage": 0, "zone": z, "contour": [[0, 0], [10, 0], [10, 6], [0, 6]]})
	doc.depart = z
	doc.objets.append({"id": "s1", "type": "depart", "etage": 0, "position": [5.0, 4.0]})
	doc.objets.append({"id": "b1", "type": "boite", "etage": 0, "position": [5.0, 6.0], "mur": "s", "depart": true})
	var o := {"id": "o1", "type": "fenetre", "etage": 0, "position": [5.0, 0.0]}
	MapCatalog.set_variant(o, kind)
	var res := MapRules.place_opening(doc, 0, "fenetre", Vector2(5.0, 0.0), MapRules.opening_width(o))
	o["position"] = res.position
	doc.ouvertures.append(o)
	return doc


func test_export_cuts_a_doorway_without_sill() -> void:
	var maps := {"smallest_door": fixture("smallest_door"), "smallest_double_door": fixture("smallest_double_door"),
		"grille_porte": grid_map("porte"), "grille_double": grid_map("porte_double"), "grille_fenetre": grid_map("fenetre")}
	for id in maps:
		var doc: EditorMap = maps[id]
		var def := EditorMapDef.from_map(doc, "perso:" + String(id))
		assert_true(def.is_valid(), "%s : jouable (%s)" % [id, _errs(def.validator)])
		if not def.is_valid():
			continue
		var data := def.layout_data
		var win: Dictionary = data.markers.windows[0]
		var kind := MapCatalog.barricade_kind(doc.find("o1"))
		if kind == "fenetre":
			assert_false(win.has("kind"), "fenêtre : description d'avant")
			var wp := Vector3(win.p[0], win.p[1], win.p[2])
			assert_true(solid_at(data, wp + Vector3(0, 0.5, 0)), "fenêtre : allège gardée")
			assert_false(solid_at(data, wp + Vector3(0, 1.5, 0)), "fenêtre : ouverte au milieu")
			continue
		assert_eq(String(win.get("kind", "")), kind, "type dans la description")
		assert_near(float(win.h), MapValidator.ZOMBIE_DOOR_TOP, 0.001, "hauteur de la porte")
		assert_near(float(win.w), MapCatalog.barricade_width(kind), 0.001)
		assert_eq((win.spawns as Array).size(), 1 if kind == "porte" else 2, "une apparition par battant")
		var p := Vector3(win.p[0], win.p[1], win.p[2])
		var inn := Vector3(win["in"][0], 0, win["in"][2])
		var side := Vector3(-inn.z, 0, inn.x)
		var hw := float(win.w) * 0.5 - 0.1
		# Pas d'allège : rien dans l'ouverture, du sol à la traverse, sur toute
		# l'épaisseur du mur ; le mur reste au-dessus, un seuil plein dessous.
		for h in [0.05, 0.5, 1.0, 1.5, 2.0]:
			for dx in [-hw, 0.0, hw]:
				for dz in [-0.2, 0.0, 0.2]:
					assert_false(solid_at(data, p + Vector3(0, h, 0) + side * dx + inn * dz), "%s : ouverture libre à %.2f m (%.1f, %.1f)" % [id, h, dx, dz])
		assert_true(solid_at(data, p + Vector3(0, MapValidator.ZOMBIE_DOOR_TOP + 0.2, 0)), "%s : mur au-dessus de la traverse" % id)
		assert_true(solid_at(data, p + Vector3(0, -0.03, 0)), "%s : seuil plein sous la porte (pas de trou)" % id)
		assert_true(solid_at(data, p + Vector3(0, 1.0, 0) + side * (float(win.w) * 0.5 + 0.25)), "%s : mur plein à côté" % id)


# ------------------------------------------------------------------ porte construite

## Tout l'assemblage (bâti, battants, planches) tient dans 10 cm d'épaisseur,
## mesuré sur la géométrie construite ; les planches sont devant le battant.
func test_built_door_is_at_most_10_cm_thick() -> void:
	for id in ["smallest_door", "smallest_double_door"]:
		var b := built(fixture(id))
		await wait_frames(1)
		assert_true(b.is_door(), "%s : porte" % id)
		var asm := b.get_node_or_null("DoorAssembly") as Node3D
		assert_true(asm != null, "%s : bâti et battants construits" % id)
		var zmin := INF
		var zmax := -INF
		var verts := 0
		if asm:
			for mi: MeshInstance3D in asm.find_children("*", "MeshInstance3D", true, false):
				var arr := mi.mesh.surface_get_arrays(0)
				for vtx: Vector3 in arr[Mesh.ARRAY_VERTEX]:
					var lp: Vector3 = b.to_local(mi.to_global(vtx))
					zmin = minf(zmin, lp.z)
					zmax = maxf(zmax, lp.z)
					verts += 1
		assert_true(verts > 100, "%s : modèle détaillé (%d sommets)" % [id, verts])
		# Planches (MultiMesh) : boîte de chaque instance au repos.
		var mmi := b.get_node("Planks") as MultiMeshInstance3D
		var mm := mmi.multimesh
		assert_eq(mm.instance_count, BarricadeRules.planks_for(b.kind))
		var hs: Vector3 = (mm.mesh as BoxMesh).size * 0.5
		for i in mm.instance_count:
			var xf: Transform3D = b._rest[i]  # planche au repos (le MultiMesh ne garde rien sans rendu)
			for sx in [-1, 1]:
				for sy in [-1, 1]:
					for sz in [-1, 1]:
						var c := xf * Vector3(hs.x * sx, hs.y * sy, hs.z * sz)
						zmin = minf(zmin, c.z)
						zmax = maxf(zmax, c.z)
		assert_true(zmax - zmin <= 0.10 + 0.0005, "%s : porte de %.1f cm d'épaisseur (10 cm au plus)" % [id, (zmax - zmin) * 100.0])
		assert_true(zmax <= MapGeom.WALL_HALF + 0.011, "%s : à fleur de la face intérieure du mur (%.3f)" % [id, zmax])
		# Barrière : toute la largeur de l'ouverture, de la hauteur de la porte.
		var shape := (b.get_node("Barrier").get_child(0) as CollisionShape3D).shape as BoxShape3D
		assert_near(shape.size.x, MapCatalog.barricade_width(b.kind), 0.001, "barrière sur toute la largeur")
		assert_near(shape.size.y, Barricade.DOOR_HEIGHT, 0.001)
		b.queue_free()
	await wait_frames(1)


## Battants cassés à mi-hauteur : du bois de battant en bas (à hauteur
## d'allège), aucun au-dessus ; le haut de la porte est vide, on l'enjambe.
func test_door_leaves_broken_at_half_height() -> void:
	for id in ["smallest_door", "smallest_double_door"]:
		var b := built(fixture(id))
		await wait_frames(1)
		var asm := b.get_node_or_null("DoorAssembly") as Node3D
		assert_true(asm != null, "%s : battants construits" % id)
		var ymax := -INF
		var ymin := INF
		if asm:
			for key in ["leaf_a", "leaf_b"]:
				var mi := asm.get_node_or_null("Door_" + key) as MeshInstance3D
				assert_true(mi != null, "%s : bois du battant (%s)" % [id, key])
				if mi == null:
					continue
				for vtx: Vector3 in mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
					var lp: Vector3 = b.to_local(mi.to_global(vtx))
					ymax = maxf(ymax, lp.y)
					ymin = minf(ymin, lp.y)
		assert_true(ymin < 0.1, "%s : le battant part du seuil (%.2f)" % [id, ymin])
		assert_true(ymax > 0.75, "%s : reste de battant à enjamber (%.2f)" % [id, ymax])
		assert_true(ymax < ZombieDoorModel.LEAF_TOP + 0.2, "%s : rien au-dessus de la mi-hauteur (%.2f)" % [id, ymax])
		b.queue_free()
	await wait_frames(1)


## Places : porte simple = une place où l'on arrache et 3 d'attente ; porte
## double = deux (une par battant) et 4 d'attente ; places écartées les unes
## des autres et des apparitions ; deux passages pour la double.
func test_tear_and_wait_places() -> void:
	for id in ["smallest_door", "smallest_double_door"]:
		var doc := fixture(id)
		var b := built(doc)
		await wait_frames(1)
		var single: bool = id == "smallest_door"
		assert_eq(b.tear_slots(), 1 if single else 2, "%s : zombies qui arrachent à la fois" % id)
		assert_eq(b.slot_count(), 4 if single else 6)
		assert_eq(b.queue_max(), b.slot_count(), "une place par zombie rattaché")
		var pts: Array[Vector3] = []
		for i in b.slot_count():
			pts.append(b.slot_point(i))
		for i in pts.size():
			assert_true((pts[i] - b.global_position).dot(b.inward) < -0.3, "place %d dehors" % i)
			for j in range(i + 1, pts.size()):
				assert_true(Barricade._flat_dist(pts[i], pts[j]) >= 2.0 * Zombie.RADIUS + 0.05, "%s : places %d et %d écartées" % [id, i, j])
		var data := EditorMapDef.from_map(doc, "perso:" + id).layout_data
		for s in data.markers.windows[0].spawns:
			var sp := Vector3(s[0], s[1], s[2])
			for i in range(b.tear_slots(), pts.size()):
				assert_true(Barricade._flat_dist(sp, pts[i]) > Spawner.WINDOW_SPAWN_CLEARANCE, "%s : attente %d hors du point d'apparition" % [id, i])
		if not single:
			assert_true(Barricade._flat_dist(b.inside_point(0), b.inside_point(1)) > 0.8, "deux arrivées, une par battant")
			assert_eq(b.lane_of_slot(0), 0)
			assert_eq(b.lane_of_slot(1), 1)
		assert_near(b.vault_time(), BarricadeRules.VAULT_TIME, 0.001, "on enjambe le battant cassé")
		b.queue_free()
	await wait_frames(1)


## La fenêtre d'avant est construite exactement comme avant (mêmes planches).
func test_window_unchanged() -> void:
	var b := built(fixture("smallest"))
	await wait_frames(1)
	assert_false(b.is_door())
	assert_eq(b.plank_count, 6)
	assert_eq(b.tear_slots(), 3)
	assert_eq(b.slot_count(), 3)
	assert_eq(b.queue_max(), BarricadeRules.WINDOW_QUEUE_MAX)
	assert_true(b.get_node_or_null("DoorAssembly") == null, "pas de porte")
	var mm := (b.get_node("Planks") as MultiMeshInstance3D).multimesh
	assert_eq((mm.mesh as BoxMesh).size, Barricade.PLANK_SIZE)
	assert_near((b._rest[0] as Transform3D).origin.z, Barricade.PLANK_Z + float(Barricade.LAYOUT[0][2]), 0.001, "plan des planches d'avant")
	var shape := (b.get_node("Barrier").get_child(0) as CollisionShape3D).shape as BoxShape3D
	# Barrière : l'épaisseur du mur de 0,5 m (avant : 1 m, 25 cm de saillie
	# de chaque côté ; tests/test_barricade_wall_fit.gd).
	assert_near(shape.size.z, MapGeom.WALL_HALF * 2.0, 0.001, "barrière dans l'épaisseur du mur")
	b.queue_free()
	await wait_frames(1)


# ------------------------------------------------------------------ collisions dans le mur

## Octogone de 16 m, une entrée de type `kind` au milieu du mur en biais
## nord-ouest (mur oblique, hors grille), posée par les règles de l'éditeur.
static func oblique_map(kind: String) -> EditorMap:
	var doc := EditorMap.blank("biais_" + kind, "BIAIS", "OBLIQUE")
	var z := String(doc.add_zone("Salle", "Room").id)
	doc.pieces.append({"id": "p1", "nom": "Salle", "etage": 0, "zone": z,
		"contour": [[6, 2], [14, 2], [18, 6], [18, 14], [14, 18], [6, 18], [2, 14], [2, 6]]})
	doc.depart = z
	doc.objets.append({"id": "s1", "type": "depart", "etage": 0, "position": [10.0, 10.0]})
	doc.objets.append({"id": "b1", "type": "boite", "etage": 0, "position": [10.0, 18.0], "mur": "s", "depart": true})
	var o := {"id": "o1", "type": "fenetre", "etage": 0, "position": [4.0, 4.0]}
	MapCatalog.set_variant(o, kind)
	var res := MapRules.place_opening(doc, 0, "fenetre", Vector2(4.0, 4.0), MapRules.opening_width(o))
	o["position"] = res.position
	doc.ouvertures.append(o)
	return doc


## Faces du mur autour d'une entrée, mesurées sur la maçonnerie exportée à
## côté de l'ouverture : (face côté cour, face côté salle), en m le long de
## `inn` depuis `p`.
static func wall_faces(data: Dictionary, p: Vector3, inn: Vector3, side: Vector3, w: float) -> Vector2:
	var q := p + Vector3(0, 1.0, 0) + side * (w * 0.5 + 0.25)
	var lo := 0.0
	var hi := 0.0
	while lo > -2.0 and solid_at(data, q + inn * (lo - 0.005)):
		lo -= 0.005
	while hi < 2.0 and solid_at(data, q + inn * (hi + 0.005)):
		hi += 0.005
	return Vector2(lo, hi)


## Régression (« la hitbox de la porte des zombies dépasse du mur et bloque
## le joueur ») : toute collision d'une porte à zombies, simple ou double, sur
## un mur de la grille, hors grille ou en biais, reste dans l'épaisseur du
## mur ; elle ferme quand même toute l'ouverture (largeur, hauteur) et le
## zombie tient à sa place devant les planches sans la toucher.
func test_door_collisions_stay_inside_the_wall() -> void:
	var maps := {"smallest_door": fixture("smallest_door"), "smallest_double_door": fixture("smallest_double_door"),
		"grille_porte": grid_map("porte"), "grille_double": grid_map("porte_double"),
		"biais_porte": oblique_map("porte"), "biais_double": oblique_map("porte_double")}
	const TOL := 0.01
	for id in maps:
		var doc: EditorMap = maps[id]
		var def := EditorMapDef.from_map(doc, "perso:" + String(id))
		assert_true(def.is_valid(), "%s : jouable (%s)" % [id, _errs(def.validator)])
		if not def.is_valid():
			continue
		var b := built(doc)
		await wait_frames(1)
		assert_true(b.is_door(), "%s : porte" % id)
		var p := b.global_position
		var inn := b.inward.normalized()
		var side := Vector3(-inn.z, 0, inn.x)
		var faces := wall_faces(def.layout_data, p, inn, side, b.width)
		assert_near(faces.y - faces.x, MapGeom.WALL_HALF * 2.0, 0.02, "%s : mur de 0,5 m mesuré (%s)" % [id, faces])
		var shapes := b.find_children("*", "CollisionShape3D", true, false)
		assert_true(shapes.size() >= 1, "%s : une barrière" % id)
		var dmin := INF
		var dmax := -INF
		for cs: CollisionShape3D in shapes:
			var box := cs.shape as BoxShape3D
			assert_true(box != null, "%s : barrière en pavé" % id)
			if box == null:
				continue
			var h := box.size * 0.5
			# Repère de la porte : (le long du mur, hauteur, vers la salle).
			var lo := Vector3(INF, INF, INF)
			var hi := -lo
			for sx in [-1, 1]:
				for sy in [-1, 1]:
					for sz in [-1, 1]:
						var c: Vector3 = cs.global_transform * Vector3(h.x * sx, h.y * sy, h.z * sz) - p
						var l := Vector3(c.dot(side), c.y, c.dot(inn))
						lo = lo.min(l)
						hi = hi.max(l)
			dmin = minf(dmin, lo.z)
			dmax = maxf(dmax, hi.z)
			assert_true(lo.z >= faces.x - TOL, "%s : collision à %.2f m dans la cour, face du mur à %.2f m" % [id, -lo.z, -faces.x])
			assert_true(hi.z <= faces.y + TOL, "%s : collision à %.2f m dans la salle, face du mur à %.2f m" % [id, hi.z, faces.y])
			assert_true(lo.x >= -b.width * 0.5 - TOL and hi.x <= b.width * 0.5 + TOL, "%s : pas plus large que l'ouverture" % id)
			assert_true(lo.x <= -b.width * 0.5 + TOL and hi.x >= b.width * 0.5 - TOL, "%s : toute la largeur de l'ouverture fermée" % id)
			assert_true(lo.y <= TOL and hi.y >= Barricade.DOOR_HEIGHT - TOL, "%s : du sol au haut de la porte" % id)
		assert_true(dmax - dmin >= 0.3, "%s : barrière assez épaisse pour arrêter les joueurs (%.2f m)" % [id, dmax - dmin])
		# Le zombie qui arrache tient à sa place sans toucher la barrière.
		for lane in b.tear_slots():
			var sp := b.slot_point(lane) - p
			assert_true(sp.dot(inn) + Zombie.RADIUS < dmin, "%s : place %d devant la barrière (%.2f m)" % [id, lane, sp.dot(inn)])
		b.queue_free()
	await wait_frames(1)
