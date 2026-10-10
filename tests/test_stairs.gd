extends TestCase
## Escaliers (docs/MAP_OBJECTS.md § Escaliers) : géométrie de chaque type
## (marches visibles, collision sans fente ni rebord, largeur couverte),
## ancres et couloir des zombies (bornes, écart d'une horde, deux sens),
## format 6 de l'éditeur (types et réglages relus, anciens formats inchangés),
## validateur et contrôle des cartes reçues.

const KINDS := ["droit", "palier", "quart", "demi_tour", "large", "service", "colimacon", "rampe"]
## Baie de chaque type sur la carte d'essai (x de départ de la baie, m).
const BAY := 9.0


# ------------------------------------------------------------------ carte d'essai

static func _room(doc: EditorMap, x0: float, y0: float, x1: float, y1: float, k := 0, zone := "") -> Dictionary:
	var id := doc.new_id("p")
	var z := zone if zone != "" else String(doc.add_zone("Salle " + id, "Room " + id).id)
	var r := {"id": id, "nom": "Salle " + id, "altitude": k * EditorMap.FLOOR_STEP, "zone": z, "contour": [[x0, y0], [x1, y0], [x1, y1], [x0, y1]]}
	doc.pieces.append(r)
	return r


## Grand hall à double hauteur et, dans chaque baie, un escalier d'un type
## qui monte (vers le nord) à une mezzanine de l'étage 1. Sert aux tests
## unitaires et aux scénarios stairs_types / stairs_hordes.
##   {kind: [rect, monte, mezzanine [x0, y0, x1, y1], options]}
static func layout_of() -> Dictionary:
	var out := {}
	for i in KINDS.size():
		var x := 2.0 + BAY * i
		match KINDS[i]:
			"droit":
				out.droit = [[x + 1, 9, x + 3.5, 16], {}, [x, 4, x + 8, 9]]
			"palier":
				out.palier = [[x + 1, 7, x + 3.5, 16], {}, [x, 2, x + 8, 7]]
			"quart":
				out.quart = [[x + 1, 9, x + 5, 16], {}, [x + 5, 6, x + 8.5, 12]]
			"demi_tour":
				out.demi_tour = [[x + 1, 10, x + 5, 16], {}, [x + 3, 16, x + 7, 20]]
			"large":
				out.large = [[x + 0.5, 9, x + 4.5, 16], {}, [x, 4, x + 8, 9]]
			"service":
				out.service = [[x + 1, 9, x + 2.5, 16], {}, [x, 4, x + 8, 9]]
			"colimacon":
				out.colimacon = [[x + 1, 11, x + 5.5, 16.5], {}, [x, 6, x + 8, 11]]
			"rampe":
				out.rampe = [[x + 1, 8, x + 3.5, 16], {}, [x, 3, x + 8, 8]]
	return out


static func stairs_map() -> EditorMap:
	var doc := EditorMap.blank("escaliers", "ESCALIERS", "STAIRS")
	var w := 2.0 + BAY * KINDS.size() + 1.0
	var hall := _room(doc, 0, 0, w, 24)
	hall["plafond"] = 6.7
	doc.depart = String(hall.zone)
	var lay := layout_of()
	for kind: String in KINDS:
		var e: Array = lay[kind]
		var m: Array = e[2]
		_room(doc, m[0], m[1], m[2], m[3], 1, String(hall.zone))
		var o := {"id": doc.new_id("e"), "type": "escalier", "altitude": 0, "rect": e[0], "monte": "n"}
		MapCatalog.set_variant(o, kind)
		o.merge(e[1])
		doc.objets.append(o)
	doc.objets.append({"id": "s1", "type": "depart", "altitude": 0, "position": [6.0, 21.5]})
	doc.objets.append({"id": "b1", "type": "boite", "altitude": 0, "position": [20.75, 24.0], "mur": "s", "depart": true})
	doc.ouvertures.append({"id": "o1", "type": "fenetre", "altitude": 0, "position": [10.25, 24.0]})
	doc.ouvertures.append({"id": "o2", "type": "fenetre", "altitude": 0, "position": [40.25, 24.0]})
	return MapTestKit.add_evac(doc)


static func _check(doc: EditorMap) -> MapValidator:
	var v := MapRaster.build(doc).v
	v.analyze()
	return v


func _errs(v: MapValidator) -> String:
	return "\n".join(v.errors().map(func(m): return String(m.fr)))


## Entrée de description d'un type, seule (y de 0 à 3,5).
static func _spec(kind: String, opts := {}) -> Dictionary:
	var e: Array = layout_of()[kind]
	var o := {"type": "escalier", "rect": e[0], "monte": "n"}
	MapCatalog.set_variant(o, kind)
	var st := MapRaster.stair_spec(o, 0.0, 3.5)
	st.merge(opts, true)
	st["room"] = "r"
	return st


# ------------------------------------------------------------------ plan et géométrie

func test_every_kind_has_steps_under_the_step_height() -> void:
	for kind: String in KINDS:
		var pl := StairGen.plan(_spec(kind))
		assert_eq(pl.kind, kind, "type lu")
		for f in pl.flights:
			var rise := absf(float(f.b.y) - float(f.a.y))
			var n := StairGen.flight_steps(pl, rise)
			assert_true(rise / n <= StairGen.STEP_HEIGHT, "%s : marche de %.2f m (≤ %.2f)" % [kind, rise / n, StairGen.STEP_HEIGHT])
		assert_true(StairGen.max_slope(pl) <= MapValidator.MAX_STAIR_SLOPE, "%s : pente %.0f°" % [kind, StairGen.max_slope(pl)])
		var lane: Array = pl.lane
		assert_true(lane.size() >= 4, "%s : couloir d'ancres (%d points)" % [kind, lane.size()])
		assert_near(float(lane[0][0].y), 0.0, 0.001, "%s : ancre d'entrée au sol du bas" % kind)
		assert_near(float(lane[lane.size() - 1][0].y), 3.5, 0.001, "%s : ancre de sortie au sol du haut" % kind)
	var pl := StairGen.plan(_spec("droit", {"steps": 14}))
	assert_eq(StairGen.flight_steps(pl, 3.5), 14, "nombre de marches réglé")
	assert_eq(StairGen.flight_steps(StairGen.plan(_spec("droit", {"steps": 3})), 3.5), 14, "jamais plus de 5 cubes (25 cm) par marche, même réglé à 3")
	assert_eq(StairGen.flight_steps(StairGen.plan(_spec("droit", {"steps": 200})), 3.5), 70, "jamais moins d'un cube par marche")


## Anchors and lane points: inside the stairs, at least a capsule radius from
## every side (rails and the U divider included), whatever the zombie's bias.
func test_lane_stays_a_capsule_away_from_every_side() -> void:
	for kind: String in KINDS:
		for opts: Dictionary in [{}, {"rail": true}, {"turn": -1}]:
			var pl := StairGen.plan(_spec(kind, opts))
			var l := StairLane.from_plan(pl)
			var union: Array = [pl.polys[0]]
			for i in range(1, pl.polys.size()):
				union = Geometry2D.merge_polygons(union[0], pl.polys[i])
			var outline: PackedVector2Array = union[0]
			for i in range(1, l.pts.size() - 1):
				for bias: float in [-1.0, -0.4, 0.0, 0.4, 1.0, 3.0]:
					var p := l.offset_point(i, bias)
					var q := Vector2(p.x, p.z)
					var what := "%s %s point %d écart %.1f" % [kind, opts, i, bias]
					assert_true(Geometry2D.is_point_in_polygon(q, outline) or _edge_dist(q, outline) < 0.02, what + " : sur l'escalier")
					var side := StairGen.AGENT_RADIUS + (StairGen.RAIL_T if (pl.rail or pl.closed) else 0.0)
					if i > 1 and i < l.pts.size() - 2:
						assert_true(_edge_dist(q, outline) >= side - 0.03, what + " : %.2f m du bord (≥ %.2f)" % [_edge_dist(q, outline), side])
					for dv in pl.dividers:
						var cp := Geometry2D.get_closest_point_to_segment(q, dv.a, dv.b)
						assert_true(cp.distance_to(q) >= StairGen.AGENT_RADIUS + StairGen.RAIL_T * 0.5 - 0.03, what + " : loin du noyau du U (%.2f)" % cp.distance_to(q))
					if not (pl.spiral as Dictionary).is_empty():
						var c: Vector2 = pl.spiral.c
						assert_true(q.distance_to(c) >= StairGen.COLUMN_R + StairGen.AGENT_RADIUS - 0.03, what + " : loin du noyau du colimaçon")
			# Ancres : hors des marches, devant le pied et au-delà du haut.
			var e0 := Vector2(l.pts[0].x, l.pts[0].z)
			var e1 := Vector2(l.pts[l.pts.size() - 1].x, l.pts[l.pts.size() - 1].z)
			assert_false(Geometry2D.is_point_in_polygon(e0, outline), "%s : ancre d'entrée devant le pied" % kind)
			assert_false(Geometry2D.is_point_in_polygon(e1, outline), "%s : ancre de sortie sur le palier d'arrivée" % kind)
			assert_true(_edge_dist(e1, outline) >= StairGen.EXIT_GAP - 0.05, "%s : ancre de sortie loin du bord (%.2f m)" % [kind, _edge_dist(e1, outline)])


static func _edge_dist(q: Vector2, poly: PackedVector2Array) -> float:
	var best := INF
	for i in poly.size():
		best = minf(best, Geometry2D.get_closest_point_to_segment(q, poly[i], poly[(i + 1) % poly.size()]).distance_to(q))
	return best


## Built collision of every type (MeshMapGeometry, the game's own code), on a
## ground slab with a landing beyond the exit: along the lane and across its
## width, the floor under a zombie never jumps more than a step (no slot at
## the top or the bottom, no lip), and never misses (collision under the
## whole walking width).
func test_built_collision_has_no_slot_or_lip() -> void:
	for kind: String in KINDS:
		for opts: Dictionary in [{}, {"rail": true, "closed": true}]:
			var st := _spec(kind, opts)
			var pl := StairGen.plan(st)
			var root := Node3D.new()
			host.add_child(root)
			var built := MeshMapBuilder.new({"stairs": [st]})
			built.build(root)
			var ground := CollisionBox.make(Vector3(st.a[0], -0.25, st.a[2] - 8.0), Vector3(30, 0.5, 30))
			root.add_child(ground)
			var ex: Dictionary = pl.exit
			var m: Vector2 = ex.m
			var n: Vector2 = ex.n
			var ctr := m + n * 1.5
			var land := CollisionBox.make(Vector3(ctr.x, 3.25, ctr.y), Vector3(3.0, 0.5, float(ex.h) * 2.0), atan2(-n.y, n.x))
			root.add_child(land)
			await wait_frames(3)
			var space := root.get_world_3d().direct_space_state
			var l := StairLane.from_plan(pl)
			var worst := 0.0
			var where := ""
			var misses := 0
			for bias: float in [-1.0, 0.0, 1.0]:
				var prev := NAN
				for i in l.pts.size() - 1:
					var a := l.offset_point(i, bias)
					var b := l.offset_point(i + 1, bias)
					var steps := maxi(1, ceili(a.distance_to(b) / 0.05))
					for j in steps:
						var q := a.lerp(b, float(j) / steps)
						var ray := PhysicsRayQueryParameters3D.create(q + Vector3.UP * 0.9, q + Vector3.DOWN * 1.1, 1)
						var hit := space.intersect_ray(ray)
						if hit.is_empty():
							misses += 1
							continue
						var y: float = hit.position.y
						if not is_nan(prev) and absf(y - prev) > worst:
							worst = absf(y - prev)
							where = "%s (écart %.0f)" % [q, bias]
						prev = y
			assert_true(worst <= StairGen.STEP_HEIGHT, "%s %s : plus grand saut du sol %.2f m en %s" % [kind, opts, worst, where])
			assert_eq(misses, 0, "%s %s : collision sous toute la largeur de marche" % [kind, opts])
			# Tablier du haut : une CollisionBox (objet du projet), à fleur du palier.
			var aprons := root.find_children("StairApron_*", "CollisionBox", true, false)
			assert_eq(aprons.size(), 1, "%s : tablier invisible au haut des marches" % kind)
			if aprons.size() == 1:
				var cb := aprons[0] as CollisionBox
				assert_near(cb.global_position.y + cb.size.y * 0.5, 3.5, 0.001, "%s : tablier à fleur du sol du haut" % kind)
				assert_true(cb.find_children("*", "VisualInstance3D", true, false).is_empty(), "%s : tablier invisible" % kind)
			root.queue_free()
			await wait_frames(1)


func test_old_straight_stairs_build_as_before() -> void:
	# Escalier d'avant (sans type ni réglage) : mêmes nœuds, même collision ;
	# marches en cubes (docs/VOXEL_ARCHITECTURE_PLAN.md § 2.3 : 18 marches de
	# 3 ou 4 cubes, tests/test_voxel_archi_stairs.gd).
	var st := {"room": "r", "a": [10.0, 0.0, 20.0], "b": [10.0, 3.5, 13.0], "w": 2.5, "mat": "wood"}
	var arch := MeshMapGeometry.build({"stairs": [st]})
	var mi := arch.get_node("wood__r__stair") as MeshInstance3D
	assert_true(mi != null, "marches visibles")
	var verts: PackedVector3Array = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var tops := {}
	for v in verts:
		tops[snappedf(v.y, 0.001)] = true
	assert_eq(tops.size(), 19, "18 marches (et le sol)")
	var body := arch.get_node("wood__r__stair__col") as StaticBody3D
	assert_eq(body.get_child_count(), 1, "une rampe pleine")
	var pts: PackedVector3Array = ((body.get_child(0) as CollisionShape3D).shape as ConvexPolygonShape3D).points
	assert_eq(pts.size(), 6, "coin plein : 6 points")
	arch.free()


# ------------------------------------------------------------------ couloir d'ancres

func test_lane_offsets_spread_a_horde_and_stay_clamped() -> void:
	var pl := StairGen.plan(_spec("large"))
	var l := StairLane.from_plan(pl)
	var i := l.pts.size() / 2
	var seen := []
	for id in 10:
		var bias := fposmod(float(id) * 0.6180339, 1.0) * 2.0 - 1.0
		var p := l.offset_point(i, bias)
		var lat := (p - l.pts[i]).length()
		assert_true(lat <= l.half[i] + 0.001, "écart du zombie %d borné (%.2f ≤ %.2f)" % [id, lat, l.half[i]])
		seen.append(snappedf(p.x, 0.05))
	var distinct := {}
	for x in seen:
		distinct[x] = true
	assert_true(distinct.size() >= 8, "une horde de 10 se répartit sur la largeur (%d couloirs distincts)" % distinct.size())
	assert_near(l.offset_point(i, 9.0).distance_to(l.pts[i]), l.half[i], 0.001, "écart hors bornes ramené à la demi-largeur")
	assert_near(l.offset_point(0, 1.0).distance_to(l.pts[0]), l.half[0], 0.001, "écart réduit aux ancres")
	assert_true(l.half[0] < l.half[i], "horde resserrée aux ancres")


func test_lane_both_directions_and_projection() -> void:
	var l := StairLane.from_plan(StairGen.plan(_spec("demi_tour")))
	var S := l.length()
	var up := l.points_between(0.0, S, 0.0, true, true)
	var down := l.points_between(S, 0.0, 0.0, true, true)
	assert_eq(up.size(), l.pts.size(), "montée : tout le couloir, ancres comprises")
	assert_eq(down.size(), l.pts.size(), "descente : tout le couloir")
	for k in up.size():
		assert_true(up[k].is_equal_approx(down[down.size() - 1 - k]), "descente = montée à l'envers (%d)" % k)
	assert_true(up[0].y < up[up.size() - 1].y, "montée : du bas vers le haut")
	# Un zombie au milieu des marches : on repart du point suivant, dans le bon sens.
	var mid := l.pts[l.pts.size() / 2]
	var pr := l.project(mid + Vector3(0.05, 0.0, 0.0))
	assert_near(float(pr[0]), float(l.cum[l.pts.size() / 2]), 0.1, "projection sur le couloir")
	var rest_up := l.points_between(float(pr[0]), S, 0.0, true)
	var rest_down := l.points_between(float(pr[0]), 0.0, 0.0, true)
	assert_true(rest_up[0].y >= mid.y - 0.01 and rest_down[0].y <= mid.y + 0.01, "suite du couloir vers le haut et vers le bas")
	assert_eq(l.end_of(Vector3(0, 0.1, 0)), 0, "bout du bas")
	assert_eq(l.end_of(Vector3(0, 3.4, 0)), 1, "bout du haut")


func test_lane_contains_crosses_and_pushes_back() -> void:
	var st := _spec("droit")
	var l := StairLane.from_plan(StairGen.plan(st))
	var a := Vector3(st.a[0], st.a[1], st.a[2])
	var b := Vector3(st.b[0], st.b[1], st.b[2])
	var mid := a.lerp(b, 0.5)
	assert_true(l.contains(mid), "milieu des marches : sur l'escalier")
	assert_false(l.contains(mid + Vector3(3.0, 0, 0)), "à côté : non")
	assert_false(l.contains(mid + Vector3(0, 4.0, 0)), "à l'étage au-dessus : non")
	assert_false(l.contains(a + Vector3(0, 0, 0.05)), "au ras du pied : non (un chemin qui frôle ne compte pas)")
	assert_true(l.crosses(mid + Vector3(-3, 0, 0), mid + Vector3(3, 0, 0)), "ligne droite qui passe sur les marches")
	assert_false(l.crosses(a + Vector3(-3, 0, 3), a + Vector3(3, 0, 3)), "ligne droite devant le pied")
	assert_eq(l.push_back(mid), Vector3.ZERO, "dans le couloir : aucune poussée")
	var off := mid + Vector3(1.2, 0, 0)
	var push := l.push_back(off)
	assert_true(push.x < -0.1, "contre le bord droit : ramené vers l'axe (%s)" % push)
	assert_true(l.push_back(mid + Vector3(-1.2, 0, 0)).x > 0.1, "contre le bord gauche : ramené vers l'axe")


## File à l'ouverture d'un escalier de service (1 m) : la horde arrive en
## haut, deux zombies côte à côte à l'ouverture et un troisième derrière
## (positions relevées sur un blocage de stairs_hordes). L'ancienne règle
## (« plus près de SON point visé de 0,2 m, dans un cône de 45° ») ne faisait
## céder aucun des deux de devant : ils se poussaient l'un contre l'autre et
## personne ne descendait. Avec la mesure commune (StairLane.left_to), de deux
## voisins un seul cède ; le plus avancé ne cède à personne, tous les autres
## cèdent à quelqu'un, et celui qui cède n'avance plus vers lui.
func test_queue_at_a_narrow_stair_mouth_never_deadlocks() -> void:
	var l := StairLane.from_plan(StairGen.plan(_spec("service")))
	var n := l.pts.size()
	var edge := l.pts[n - 2]          # bord de la marche du haut
	var anchor := l.pts[n - 1]        # ancre du haut, sur le palier
	var back := Vector3(anchor.x - edge.x, 0.0, anchor.z - edge.z).normalized()
	var side := Vector3(-back.z, 0.0, back.x)
	var mouth := Vector3(edge.x, anchor.y, edge.z) + back * 0.3
	var exit := l.pts[0]              # en descendant : ancre du bas
	for layout: Array in [
		[mouth - side * 0.3, mouth + side * 0.32, mouth + back * 0.5],
		[mouth - side * 0.3 + back * 0.01, mouth + side * 0.3, mouth + back * 0.45 + side * 0.05],
		[mouth - side * 0.35, mouth + side * 0.25 + back * 0.03, mouth + back * 0.6 - side * 0.3, mouth + back * 0.6 + side * 0.3],
	]:
		var zs: Array = layout
		var left := zs.map(func(p): return l.left_to(p, exit))
		var leaders := 0
		for i in zs.size():
			var a: Vector3 = zs[i]
			var dir := Vector3(edge.x - a.x, 0.0, edge.z - a.z).normalized()
			var gives := []
			for j in zs.size():
				var d: Vector3 = zs[j] - a
				d.y = 0.0
				if i != j and d.length_squared() <= Zombie.YIELD_RANGE2 and Zombie.yields_to(d, dir, left[i], left[j]):
					gives.append(j)
					var bdir := Vector3(edge.x - zs[j].x, 0.0, edge.z - zs[j].z).normalized()
					assert_false(Zombie.yields_to(-d, bdir, left[j], left[i]), "%d et %d ne se cèdent pas l'un à l'autre" % [i, j])
					var w := Zombie.give_way(dir, d.normalized())
					assert_true(w.dot(d.normalized()) < 0.0, "%d cède à %d : il recule, sans avancer vers lui (%s)" % [i, j, w])
			if gives.is_empty():
				leaders += 1
		assert_eq(leaders, 1, "un seul zombie en tête à l'ouverture (%s)" % [left])
	# Mesure commune : plus avancé = moins de couloir à parcourir, et à côté
	# de l'ouverture = plus loin que juste en face.
	assert_true(l.left_to(mouth, exit) < l.left_to(mouth + back * 0.5, exit), "devant : moins de chemin que derrière")
	assert_true(l.left_to(mouth, exit) < l.left_to(mouth + side * 0.4, exit), "en face de l'ouverture : moins de chemin qu'à côté")


# ------------------------------------------------------------------ éditeur : format 6

func test_format_6_saves_types_and_options_only_when_not_default() -> void:
	assert_true(EditorMap.FORMAT >= 6, "format 6 : types d'escaliers")
	var doc := stairs_map()
	var o: Dictionary = doc.objets.filter(func(x): return x.type == "escalier" and MapCatalog.stair_kind(x) == "quart")[0]
	o["sens"] = "gauche"
	o["garde_corps"] = true
	o["cotes"] = "fermes"
	var t := doc.file_texts()
	assert_true(String(t["carte.json"]).contains("\"format\": %d" % EditorMap.FORMAT), "enregistrée au format courant")
	var back := EditorMap.from_texts(t)
	assert_eq(back.load_errors, [], "relue sans erreur")
	assert_eq(back.file_texts(), t, "relue puis réécrite à l'identique")
	var ob := back.find(String(o.id))
	assert_eq([MapCatalog.stair_kind(ob), ob.get("sens"), ob.get("garde_corps"), ob.get("cotes")], ["quart", "gauche", true, "fermes"], "type et réglages relus")
	var droit: Dictionary = back.objets.filter(func(x): return x.type == "escalier" and MapCatalog.stair_kind(x) == "droit")[0]
	assert_false(droit.has("variante") or droit.has("sens") or droit.has("marches") or droit.has("garde_corps") or droit.has("cotes"), "escalier droit : aucune clé nouvelle")
	# Valeurs par défaut et illisibles retirées (fichier écrit à la main).
	var hand := t.duplicate()
	hand["objets.json"] = String(t["objets.json"]).replace("\"sens\":\"gauche\"", "\"sens\":\"haut\",\"marches\":22") \
		.replace("\"cotes\":\"fermes\"", "\"cotes\":\"ouverts\"")
	assert_true(String(hand["objets.json"]).contains("\"marches\":22"), "ancien réglage de marches préparé")
	var h := EditorMap.from_texts(hand).find(String(o.id))
	assert_false(h.has("sens"), "sens illisible retiré")
	assert_false(h.has("marches"), "nombre de marches (plus réglable) retiré à la relecture")
	assert_false(MapCatalog.stair_layout_opts(h).has("steps"), "marches toujours automatiques en jeu")
	assert_false(h.has("cotes"), "côtés ouverts (par défaut) non écrits")
	var large := {"type": "escalier", "variante": "large", "garde_corps": true}
	MapCatalog.tidy_stair(large)
	assert_false(large.has("garde_corps"), "escalier d'honneur : garde-corps par défaut non écrit")


func test_old_formats_load_unchanged() -> void:
	# DRAFT ARENA (format 1, un escalier droit) : même description en maillage.
	var dir := "res://tests/fixtures/maps/legacy_draft_arena/"
	var m := EditorMap.load_dir(dir)
	assert_eq(m.format_read, 1, "format 1 lu")
	var lay := MapLayoutExport.build(_check(m))
	assert_eq(lay.stairs.size(), 1, "un escalier")
	assert_eq((lay.stairs[0] as Dictionary).keys(), ["room", "a", "b", "w", "mat"], "escalier d'avant : aucune clé nouvelle dans la description")
	# Carte au format 5 avec un escalier tourné : lue telle quelle, droite.
	var doc := stairs_map()
	doc.objets = doc.objets.filter(func(x): return x.type != "escalier" or MapCatalog.stair_kind(x) == "droit")
	var t := doc.file_texts()
	t = load("res://tests/test_levels_migration.gd").as_format(t, 5)
	var old := EditorMap.from_texts(t)
	assert_eq(old.format_read, 5, "format 5 lu")
	assert_eq(old.load_errors, [], "sans erreur")
	var st: Array = old.objets.filter(func(x): return x.type == "escalier")
	assert_eq(st.size(), 1, "son escalier")
	assert_eq(MapCatalog.stair_kind(st[0]), "droit", "droit (l'escalier d'avant)")


func test_validator_accepts_every_kind_and_exports_it() -> void:
	var v := _check(stairs_map())
	assert_true(v.ok(), "carte de tous les escaliers acceptée :\n" + _errs(v))
	assert_eq(v.stairs.size(), KINDS.size(), "un escalier par type")
	var lay := MapLayoutExport.build(v)
	var kinds := {}
	for st in lay.stairs:
		kinds[StairGen.kind_of(st)] = st
	assert_eq(kinds.size(), KINDS.size(), "chaque type dans la description (%s)" % str(kinds.keys()))
	assert_false((kinds.droit as Dictionary).has("kind"), "droit : pas de clé kind")
	assert_eq(String(kinds.quart.kind), "quart", "en L : kind")
	# En L : le coin libre reste du sol (cases hors des marches).
	var lq: Array = layout_of().quart[0]
	var nook := MapGeom.cell_of(Vector2(float(lq[2]) - 0.5, float(lq[3]) - 0.5))
	assert_eq(v.floors[0].at(nook), MapValidator.K.SOL, "en L : le coin libre est du sol")
	# En U : sortie du côté du pied (palier de l'étage 1 au sud des marches).
	for s in v.stairs:
		if String(v.stair_opts.get(String(s.key), {}).get("kind", "")) == "demi_tour":
			var lu: Array = layout_of().demi_tour[0]
			for c in s.top:
				assert_true(MapGeom.cell_center(c).y >= float(lu[3]) - 0.01, "en U : sortie au sud, du côté du pied (%s)" % MapGeom.cell_center(c))


func test_validator_refuses_bad_shapes() -> void:
	var doc := stairs_map()
	var spiral: Dictionary = doc.objets.filter(func(x): return x.type == "escalier" and MapCatalog.stair_kind(x) == "colimacon")[0]
	spiral["rect"] = [float(spiral.rect[0]), float(spiral.rect[1]) + 2.0, float(spiral.rect[2]), float(spiral.rect[3])]
	var e := _errs(_check(doc))
	assert_true(e.contains("colimaçon") or e.contains("Colimaçon") or e.contains("En colimaçon"), "colimaçon trop petit refusé :\n" + e)
	assert_false(MapRules.check_rect(stairs_map(), 0, "escalier", Rect2(3, 9, 1, 7), "", 0, "droit").ok, "droit de 1 m refusé")
	# Arrivée sur le bord de la mezzanine de la baie « droit » (règles des deux étages).
	var sv := MapRules.check_rect(stairs_map(), 0, "escalier", Rect2(7, 9, 1.5, 7), "", 0, "service")
	assert_true(sv.ok, "escalier de service de 1 m (1,5 m tracé) admis (%s)" % sv.get("fr", ""))
	var r := MapRules.check_rect(stairs_map(), 0, "escalier", Rect2(3, 18, 2, 4), "", 0, "large")
	assert_false(r.ok, "escalier d'honneur de 2 m refusé")


func test_guard_accepts_stairs_and_refuses_bad_values() -> void:
	var doc := stairs_map()
	var q: Dictionary = doc.objets.filter(func(x): return x.type == "escalier" and MapCatalog.stair_kind(x) == "quart")[0]
	q["cotes"] = "fermes"
	var texts := doc.file_texts()
	assert_eq(CustomMapGuard.check_texts(texts).reasons, [], "carte aux huit escaliers acceptée")
	var full := CustomMapGuard.check_full(texts)
	assert_true(bool(full.get("ok", false)), "et jouable : %s" % str(full.get("reasons", [])))
	var bad_cases := [
		["\"variante\":\"quart\"", "\"variante\":\"escalator\"", "type inconnu"],
		["\"variante\":\"quart\"", "\"variante\":\"bois\"", "variante d'un autre type"],
		["\"variante\":\"quart\"", "\"variante\":\"quart\",\"sens\":3", "sens qui n'est pas un texte"],
		["\"variante\":\"quart\"", "\"variante\":\"quart\",\"sens\":\"haut\"", "sens inconnu"],
		["\"cotes\":\"fermes\"", "\"cotes\":true", "côtés qui ne sont pas un texte"],
		["\"cotes\":\"fermes\"", "\"cotes\":\"fermes\",\"marches\":1000", "ancien réglage de marches hors bornes"],
		["\"cotes\":\"fermes\"", "\"cotes\":\"res://x\"", "côtés inconnus"],
		["\"variante\":\"quart\"", "\"variante\":\"quart\",\"garde_corps\":\"oui\"", "garde-corps qui n'est pas un booléen"],
	]
	for bc in bad_cases:
		var t := texts.duplicate()
		var src := String(t["objets.json"])
		assert_true(src.contains(bc[0]), "cas %s préparé" % bc[2])
		t["objets.json"] = src.replace(bc[0], bc[1])
		assert_false(CustomMapGuard.check_texts(t).reasons.is_empty(), "refusée : %s" % bc[2])
