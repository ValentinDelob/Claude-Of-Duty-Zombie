extends TestCase
## Régression (« je me bloque sur les bords des fenêtres à zombies : la
## hitbox dépasse un peu vers l'intérieur ») : AUCUNE collision d'une entrée
## des zombies (fenêtre, porte, porte double) ne dépasse du nu du mur, côté
## salle comme côté dehors, quels que soient la carte (22 fenêtres de KINO,
## cartes de l'éditeur), l'orientation du mur (nord, est, sud, ouest) et sa
## pente (murs en biais) ; la barrière affleure le nu du mur côté salle (pas
## de renfoncement ni de coin où la capsule accroche), bouche toute la
## découpe et reste assez épaisse pour arrêter le joueur.
## Le mur est mesuré ici par sondage de la description de la carte (blocs,
## murs, murs en biais), indépendamment de BarricadeFit.
## Avant : barrière de fenêtre de 1 m partout, 30 cm de saillie dans les
## salles de KINO (43 cm à la fenêtre des loges), 25 cm sur les murs de
## l'éditeur.

const TZ := preload("res://tests/test_zombie_doors.gd")
const TOL := 0.01
const STEP := 0.005


## Point plein dans la description de carte `data` (murs déjà filtrés) ?
static func solid(data: Dictionary, q: Vector3) -> bool:
	for bl in data.get("blocks", []):
		if bl.get("barrier", false) or bl.get("nocollide", false):
			continue
		var bx: Array = bl.box
		if q.x > float(bx[0]) and q.x < float(bx[3]) and q.y > float(bx[1]) and q.y < float(bx[4]) and q.z > float(bx[2]) and q.z < float(bx[5]):
			return true
	for w in data.get("walls", []):
		var pts: Array = w.path.duplicate()
		if w.get("closed", false):
			pts.append(w.path[0])
		var t := float(w.get("thick", 0.3))
		if q.y < float(w.y0) or q.y > float(w.y1):
			continue
		for si in pts.size() - 1:
			var a := Vector2(pts[si][0], pts[si][1])
			var b := Vector2(pts[si + 1][0], pts[si + 1][1])
			var length := a.distance_to(b)
			if length < 0.001:
				continue
			var d := (b - a) / length
			var rel := Vector2(q.x, q.z) - a
			var along := rel.dot(d)
			if along < -t / 2.0 or along > length + t / 2.0 or absf(rel.dot(Vector2(-d.y, d.x))) > t / 2.0:
				continue
			var cut := false
			for o in w.get("openings", []):
				if int(o.seg) == si and absf(along - float(o.t)) < float(o.w) / 2.0 and q.y > float(o.y0) and q.y < float(o.y1):
					cut = true
			if not cut:
				return true
	for o in data.get("obliques", []):
		var a := Vector2(o.a[0], o.a[1])
		var b := Vector2(o.b[0], o.b[1])
		var d := (b - a).normalized()
		var rel := Vector2(q.x, q.z) - a
		var along := rel.dot(d)
		if along < 0.0 or along > a.distance_to(b) or absf(rel.dot(Vector2(-d.y, d.x))) > float(o.thick) * 0.5:
			continue
		if q.y < float(o.y0) or q.y > float(o.y1):
			continue
		var cut := false
		for c in o.openings:
			cut = cut or (absf(along - float(c.t)) < float(c.w) * 0.5 and q.y > float(c.y0) and q.y < float(c.y1))
		if not cut:
			return true
	return false


## Murs et blocs à moins de 4 m de `p` (sondage rapide sur KINO).
static func near(data: Dictionary, p: Vector3) -> Dictionary:
	var out := {"blocks": [], "walls": [], "obliques": data.get("obliques", [])}
	var p2 := Vector2(p.x, p.z)
	for bl in data.get("blocks", []):
		var bx: Array = bl.box
		if Rect2(Vector2(bx[0], bx[2]), Vector2(float(bx[3]) - float(bx[0]), float(bx[5]) - float(bx[2]))).grow(4.0).has_point(p2):
			out.blocks.append(bl)
	for w in data.get("walls", []):
		var pts: Array = w.path.duplicate()
		if w.get("closed", false):
			pts.append(w.path[0])
		for i in pts.size() - 1:
			if Geometry2D.get_closest_point_to_segment(p2, Vector2(pts[i][0], pts[i][1]), Vector2(pts[i + 1][0], pts[i + 1][1])).distance_to(p2) < 4.0:
				out.walls.append(w)
				break
	return out


## Faces du mur percé le long de `inn` depuis `p` : (côté dehors, côté
## salle). Fenêtre : dans l'allège ; porte : à côté de l'ouverture.
static func faces(data: Dictionary, b: Barricade) -> Vector2:
	var p := b.global_position
	var inn := b.inward.normalized()
	var side := Vector3(-inn.z, 0, inn.x)
	var q := p + Vector3.UP * (Barricade.SILL_TOP * 0.5)
	if b.is_door():
		q = p + Vector3.UP * 1.0 + side * (b.width * 0.5 + 0.25)
	var lo := 0.0
	var hi := 0.0
	if not solid(data, q):
		return Vector2(NAN, NAN)
	while lo > -2.0 and solid(data, q + inn * (lo - STEP)):
		lo -= STEP
	while hi < 2.0 and solid(data, q + inn * (hi + STEP)):
		hi += STEP
	return Vector2(lo, hi)


## Bords de la découpe du mur (milieu du mur, mi-hauteur de l'ouverture), le
## long de l'axe `side` d'extents : Vector2(bord négatif, bord positif).
static func cut_sides(data: Dictionary, b: Barricade, mid: float) -> Vector2:
	var inn := b.inward.normalized()
	var side := Vector3(-inn.z, 0, inn.x)
	var y := 1.0 if b.is_door() else (Barricade.SILL_TOP + Barricade.LINTEL_BOTTOM) * 0.5
	var q := b.global_position + inn * mid + Vector3.UP * y
	var out := Vector2.ZERO
	for s in [1.0, -1.0]:
		var d := 0.0
		while d < 2.0 and not solid(data, q + side * s * d):
			d += STEP
		if s > 0.0:
			out.y = d
		else:
			out.x = -d
	return out


## Salle de 10 × 6 m, une entrée `kind` au milieu de chacun de ses 4 murs
## (nord, est, sud, ouest : toutes les orientations de la grille).
static func four_walls(kind: String) -> EditorMap:
	var doc := EditorMap.blank("murs_" + kind, "MURS", "WALLS")
	var z := String(doc.add_zone("Salle", "Room").id)
	doc.pieces.append({"id": "p1", "nom": "Salle", "etage": 0, "zone": z, "contour": [[0, 0], [10, 0], [10, 6], [0, 6]]})
	doc.depart = z
	doc.objets.append({"id": "s1", "type": "depart", "etage": 0, "position": [5.0, 3.0]})
	doc.objets.append({"id": "b1", "type": "boite", "etage": 0, "position": [8.5, 6.0], "mur": "s", "depart": true})
	_openings(doc, kind, [Vector2(5, 0), Vector2(10, 3), Vector2(5, 6) if kind != "porte_double" else Vector2(4, 6), Vector2(0, 3)])
	return doc


## Octogone de 16 m, une entrée `kind` au milieu de chacun de ses 4 murs en
## biais (nord-ouest, nord-est, sud-est, sud-ouest).
static func four_obliques(kind: String) -> EditorMap:
	var doc := EditorMap.blank("biais4_" + kind, "BIAIS", "OBLIQUE")
	var z := String(doc.add_zone("Salle", "Room").id)
	doc.pieces.append({"id": "p1", "nom": "Salle", "etage": 0, "zone": z,
		"contour": [[6, 2], [14, 2], [18, 6], [18, 14], [14, 18], [6, 18], [2, 14], [2, 6]]})
	doc.depart = z
	doc.objets.append({"id": "s1", "type": "depart", "etage": 0, "position": [10.0, 10.0]})
	doc.objets.append({"id": "b1", "type": "boite", "etage": 0, "position": [10.0, 18.0], "mur": "s", "depart": true})
	_openings(doc, kind, [Vector2(4, 4), Vector2(16, 4), Vector2(16, 16), Vector2(4, 16)])
	return doc


static func _openings(doc: EditorMap, kind: String, at_list: Array) -> void:
	var n := 0
	for at: Vector2 in at_list:
		n += 1
		var o := {"id": "o%d" % n, "type": "fenetre", "etage": 0, "position": [at.x, at.y]}
		MapCatalog.set_variant(o, kind)
		var res := MapRules.place_opening(doc, 0, "fenetre", at, MapRules.opening_width(o))
		o["position"] = res.position
		doc.ouvertures.append(o)


## Barricades construites (comme BarricadeSystem) pour toutes les entrées
## d'une description de carte.
func _build_all(layout: MeshMapLayout) -> Array:
	var out := []
	for w: BarricadeLayout.Opening in layout.windows():
		var b := Barricade.new()
		b.setup(w)
		host.add_child(b)
		out.append(b)
	return out


## Toutes les formes de collision de `b` dans le repère de l'entrée
## (le long du mur, hauteur, vers la salle) : [min, max] des coins.
static func extents(b: Barricade) -> Array:
	var inn := b.inward.normalized()
	var side := Vector3(-inn.z, 0, inn.x)
	var out := []
	for cs: CollisionShape3D in b.find_children("*", "CollisionShape3D", true, false):
		var box := cs.shape as BoxShape3D
		var h := box.size * 0.5 if box else Vector3.ONE * 9.0
		var lo := Vector3(INF, INF, INF)
		var hi := -lo
		for sx in [-1, 1]:
			for sy in [-1, 1]:
				for sz in [-1, 1]:
					var c: Vector3 = cs.global_transform * Vector3(h.x * sx, h.y * sy, h.z * sz) - b.global_position
					var l := Vector3(c.dot(side), c.y, c.dot(inn))
					lo = lo.min(l)
					hi = hi.max(l)
		out.append([lo, hi, String(cs.get_parent().name)])
	return out


func _check_map(label: String, data: Dictionary, bars: Array, expect: int) -> void:
	assert_eq(bars.size(), expect, "%s : %d entrée(s)" % [label, expect])
	for b: Barricade in bars:
		var id := "%s, %s %d (%s)" % [label, b.kind, b.window_index, b.global_position.snapped(Vector3.ONE * 0.01)]
		var d := near(data, b.global_position)
		var f := faces(d, b)
		assert_false(is_nan(f.x), "%s : mur percé mesuré" % id)
		if is_nan(f.x):
			continue
		# Découpe mesurée juste derrière le nu côté salle : à KINO, le mur de
		# la poche des zombies est plaqué contre la moitié extérieure du mur.
		var cut := cut_sides(d, b, f.y - 0.05)
		var ext := extents(b)
		assert_true(ext.size() >= 1, "%s : une barrière" % id)
		var zmin := INF
		var zmax := -INF
		for e in ext:
			var lo: Vector3 = e[0]
			var hi: Vector3 = e[1]
			zmin = minf(zmin, lo.z)
			zmax = maxf(zmax, hi.z)
			assert_true(hi.z <= f.y + TOL, "%s : collision %s à %.0f cm DANS LA SALLE au-delà du nu du mur (nu à %.3f m, collision jusqu'à %.3f m)" % [id, e[2], (hi.z - f.y) * 100.0, f.y, hi.z])
			assert_true(lo.z >= f.x - TOL, "%s : collision %s à %.0f cm dehors au-delà du nu du mur" % [id, e[2], (f.x - lo.z) * 100.0])
			assert_true(lo.x >= cut.x - TOL and hi.x <= cut.y + TOL, "%s : collision %s pas plus large que la découpe (%.3f / %.3f m)" % [id, e[2], hi.x - lo.x, cut.y - cut.x])
			assert_true(lo.y <= TOL and hi.y >= minf(b.opening_height, 2.1) - TOL, "%s : du sol au haut de l'ouverture" % id)
		# Affleure le nu du mur côté salle (ni renfoncement ni saillie) et
		# bouche toute la découpe, assez épaisse pour arrêter le joueur.
		assert_near(zmax, f.y, TOL, "%s : barrière au nu du mur côté salle" % id)
		assert_true(zmax - zmin >= 0.3, "%s : barrière de %.2f m, assez épaisse" % [id, zmax - zmin])
		var covered := false
		for e in ext:
			covered = covered or ((e[0] as Vector3).x <= cut.x + TOL and (e[1] as Vector3).x >= cut.y - TOL)
		assert_true(covered, "%s : toute la découpe (%.3f m) fermée" % [id, cut.y - cut.x])
		# Réparation : collé à la barrière, à portée ; dehors, refusé.
		assert_near(b.barrier_face(), f.y, TOL, "%s : face de réparation au nu du mur" % id)
		assert_true(b.in_repair_range(b.global_position + b.inward * (f.y + Player.RADIUS)), "%s : réparable collé au mur" % id)
		assert_false(b.in_repair_range(b.global_position + b.inward * (f.y + Player.RADIUS + Barricade.REPAIR_REACH + 0.05)), "%s : pas au-delà de la portée" % id)
		# Le zombie qui arrache tient à sa place sans toucher la barrière.
		for lane in b.tear_slots():
			var sp := (b.slot_point(lane) - b.global_position).dot(b.inward.normalized())
			assert_true(sp + Zombie.RADIUS <= zmin + 0.001, "%s : place %d devant la barrière (%.2f m)" % [id, lane, sp])
		b.queue_free()


func test_kino_windows_inside_the_wall() -> void:
	var def: MapDef = load("res://scripts/game/map/maps/kino.gd").new()
	var layout := MeshMapLayout.new(def, "res://assets/maps/kino/layout.json", "")
	_check_map("KINO", layout.data, _build_all(layout), 22)
	await wait_frames(1)


func test_editor_entries_inside_the_wall() -> void:
	var maps := {}
	for id in ["smallest", "smallest_door", "smallest_double_door"]:
		maps[id] = [TZ.fixture(id), 1]
	for kind in ["fenetre", "porte", "porte_double"]:
		maps["grille 4 murs " + kind] = [four_walls(kind), 4]
		maps["octogone 4 biais " + kind] = [four_obliques(kind), 4]
	for label in maps:
		var doc: EditorMap = maps[label][0]
		var def := EditorMapDef.from_map(doc, "perso:" + doc.id())
		assert_true(def.is_valid(), "%s : jouable (%s)" % [label, TZ._errs(def.validator)])
		if not def.is_valid():
			continue
		var layout := MeshMapLayout.new(def, def.layout_data, "")
		_check_map(label, def.layout_data, _build_all(layout), int(maps[label][1]))
	await wait_frames(1)


## Cartes grille (BUNKER K-7) : murs de 1 m, barrière de 1 m inchangée.
func test_grid_windows_unchanged() -> void:
	var o := BarricadeLayout.Opening.new()
	o.inward_dir = Vector3(0, 0, 1)
	var b := Barricade.new()
	b.setup(o)
	host.add_child(b)
	assert_near(b.barrier_depth, Barricade.WINDOW_BARRIER_DEPTH, 0.001, "barrière de 1 m")
	assert_near(b.barrier_face(), 0.5, 0.001, "face intérieure à 0,5 m (mur de 1 m)")
	assert_near(b.barrier_width, 1.0, 0.001, "largeur de la cellule")
	b.queue_free()
	await wait_frames(1)


## Fenêtre décalée de 0,25 m de son repère (découpe de x = -0,25 à 0,75 dans
## un mur de 0,5 m) : la barrière couvre TOUTE la découpe, pas 2 × 0,25 m
## centrés sur le repère (jour latéral de 0,5 m où passait un zombie).
func test_offset_opening_fully_closed() -> void:
	var top := Barricade.SILL_TOP
	var lintel := Barricade.LINTEL_BOTTOM
	var data := {"blocks": [
		{"box": [-5.0, 0.0, -0.25, -0.25, 3.0, 0.25]},
		{"box": [0.75, 0.0, -0.25, 5.0, 3.0, 0.25]},
		{"box": [-0.25, 0.0, -0.25, 0.75, top, 0.25]},
		{"box": [-0.25, lintel, -0.25, 0.75, 3.0, 0.25]},
	]}
	var o := BarricadeLayout.Opening.new()
	o.inward_dir = Vector3(0, 0, 1)
	o.pos = Vector3.ZERO
	BarricadeFit.fit(data, [o])
	assert_near(o.cut_width, 1.0, 0.01, "largeur réelle de la découpe")
	assert_near(o.cut_off, 0.25, 0.01, "milieu de la découpe décalé de 0,25 m")
	var b := Barricade.new()
	b.setup(o)
	host.add_child(b)
	var lo := INF
	var hi := -INF
	for cs: CollisionShape3D in b.find_children("*", "CollisionShape3D", true, false):
		var box := cs.shape as BoxShape3D
		if box == null or cs.get_parent().name != "Barrier":
			continue
		var c := cs.global_position
		lo = minf(lo, c.x - box.size.x * 0.5)
		hi = maxf(hi, c.x + box.size.x * 0.5)
	assert_true(lo <= -0.25 + TOL and hi >= 0.75 - TOL, "barrière de %.2f à %.2f m : toute la découpe fermée" % [lo, hi])
	assert_true(lo >= -0.25 - TOL and hi <= 0.75 + TOL, "pas plus large que la découpe")
	b.queue_free()
	await wait_frames(1)
