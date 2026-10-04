extends AutotestScenario
## @couvre scripts/game/zombies/zombie.gd scripts/game/zombies/zombie_manager.gd scripts/game/map/mesh_nav.gd scripts/game/dogs/hellhound.gd
## Couloirs étroits (comme BO1 : la horde passe en file, sans boule de
## zombies coincés) : carte d'essai d'un grand hall découpé en baies ; dans
## chaque baie, un goulet (couloir droit de 1,5 / 2 / 2,5 m, coude, porte,
## escalier) entre la horde et le joueur. Mesures par goulet : zombies
## passés, débit (passés/s), arrivée du dernier, plus longue immobilité d'un
## zombie (> 2 s : bloqué), plus long trou sans passage, foule au goulet,
## écart minimal entre deux zombies, torse dans un mur.
## Résultats aussi écrits dans tests/_out/zombie_corridors[_<tag>].txt
## (argument --tag=avant : comparaison avant / après une modification).

const MAP_ID := "couloirs"
const BAY := 10.0
const DEPTH := 30.0
const WALL := 0.5
## Bouche du goulet (y) et sortie d'un couloir droit (y).
const Y_MOUTH := 18.0
const Y_EXIT := 12.0
## Plus long bouchon toléré (s sans qu'aucun zombie passe), et plus longue
## immobilité d'un zombie seul (coincé par le décor, sans voisin).
const STALL := 2.0
## Plus longue attente d'un zombie dans la file (s) : la file avance, personne
## n'y reste oublié (escalier : un seul de front, chacun son tour).
const WAIT_MAX := 5.0
## [nom, forme, largeur (m), nombre, classe de vitesse, type d'entité, débit minimal
## (passés/s), bouchon toléré (s, STALL par défaut ; escalier : un seul de front
## sur les marches, chacun cède le passage au plus avancé, StairLane)]
const CASES := [
	["couloir 1,5 m", "droit", 1.5, 20, RoundRules.RUN, ZombieManager.KIND_ZOMBIE, 6.0],
	["couloir 2 m", "droit", 2.0, 20, RoundRules.RUN, ZombieManager.KIND_ZOMBIE, 9.0],
	["couloir 2,5 m", "droit", 2.5, 20, RoundRules.RUN, ZombieManager.KIND_ZOMBIE, 10.0],
	["coude 1,5 m", "coude", 1.5, 20, RoundRules.RUN, ZombieManager.KIND_ZOMBIE, 5.0],
	["coude 2 m", "coude", 2.0, 20, RoundRules.RUN, ZombieManager.KIND_ZOMBIE, 6.0],
	["porte 1,5 m", "porte", 1.5, 20, RoundRules.RUN, ZombieManager.KIND_ZOMBIE, 8.0],
	["escalier 1,5 m", "escalier", 1.5, 20, RoundRules.RUN, ZombieManager.KIND_ZOMBIE, 1.2, 3.0],
	["couloir 1,5 m, marcheurs", "droit", 1.5, 20, RoundRules.WALK, ZombieManager.KIND_ZOMBIE, 3.0],
	["couloir 1,5 m, chiens", "droit", 1.5, 8, 3, ZombieManager.KIND_DOG, 4.0],
	["fente 0,5 m (porte à côté)", "fente", 0.5, 20, RoundRules.RUN, ZombieManager.KIND_ZOMBIE, 5.0],
]

var H := AutotestHelpers
var game: Game
var nav: MeshNav
var p: Player
var cam: Camera3D
var _lines: PackedStringArray = []
var _probe: PhysicsShapeQueryParameters3D


func run() -> void:
	timeout_sec = 900
	if not await start():
		return
	for i in CASES.size():
		if mine(i):
			await corridor(i, CASES[i])
	game.combat.debug_invulnerable = false
	_write_results()


func _tag() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tag="):
			return a.substr(6)
	return ""


func _write_results() -> void:
	var tag := _tag()
	var path := "res://tests/_out/zombie_corridors%s%s.txt" % ["_" + tag if tag != "" else "", "_p%d" % part() if parts() > 1 else ""]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(_lines) + "\n")


# ------------------------------------------------------------------ carte d'essai

static func _wall(doc: EditorMap, a: Vector2, b: Vector2, thick := WALL) -> void:
	doc.objets.append({"id": doc.new_id("m"), "type": "mur", "etage": 0, "a": [a.x, a.y], "b": [b.x, b.y], "epaisseur": thick})


## Baie `i` : origine x.
static func bay_x(i: int) -> float:
	return BAY * i


## Demi-écart entre les axes des deux murs d'un couloir de largeur libre `w`.
static func _half(w: float) -> float:
	return w * 0.5 + WALL * 0.5


## Bouche du goulet de la baie `i` (au sol).
static func mouth(i: int) -> Vector2:
	var c: Array = CASES[i]
	var x0 := bay_x(i)
	return Vector2(x0 + {"coude": 3.0, "escalier": 5.25, "fente": 4.5}.get(c[1], 5.0), Y_MOUTH)


## Hall à double hauteur, une baie par cas, séparées par des murs.
static func corridors_map() -> EditorMap:
	var doc := EditorMap.blank(MAP_ID, "COULOIRS", "CORRIDORS")
	doc.carte.etages.append({"sol": 3.5, "hauteur": 3.2})
	var w := BAY * CASES.size()
	var zid := String(doc.add_zone("Hall", "Hall").id)
	doc.pieces.append({"id": doc.new_id("p"), "nom": "Hall", "etage": 0, "zone": zid, "double_hauteur": true,
		"contour": [[0, 0], [w, 0], [w, DEPTH], [0, DEPTH]]})
	doc.depart = zid
	for i in range(1, CASES.size()):
		_wall(doc, Vector2(bay_x(i), 7.0), Vector2(bay_x(i), DEPTH))
	for i in CASES.size():
		var c: Array = CASES[i]
		var x0 := bay_x(i)
		var m := mouth(i)
		var o := _half(float(c[2]))
		var cx := m.x
		match c[1]:
			"droit":
				_wall(doc, Vector2(cx - o, Y_EXIT), Vector2(cx - o, Y_MOUTH))
				_wall(doc, Vector2(cx + o, Y_EXIT), Vector2(cx + o, Y_MOUTH))
				_wall(doc, Vector2(x0, Y_MOUTH), Vector2(cx - o, Y_MOUTH))
				_wall(doc, Vector2(cx + o, Y_MOUTH), Vector2(x0 + BAY, Y_MOUTH))
			"fente":
				# Fente d'environ 0,5 m entre deux bouts de cloison minces (hors de
				# la grille : le validateur, qui raisonne par cases de 0,5 m, ne la
				# voit pas), droit vers le joueur : plus large que le tronc, plus
				# étroite que les épaules ; porte de 1,5 m à côté (x0 + 7,75 à
				# x0 + 9,25). Personne ne passe par la fente.
				_wall(doc, Vector2(x0, Y_MOUTH), Vector2(x0 + 4.03, Y_MOUTH))
				_wall(doc, Vector2(x0 + 4.55, Y_MOUTH), Vector2(x0 + 7.5, Y_MOUTH))
				_wall(doc, Vector2(x0 + 9.5, Y_MOUTH), Vector2(x0 + BAY, Y_MOUTH))
			"porte":
				_wall(doc, Vector2(x0, Y_MOUTH), Vector2(cx - o, Y_MOUTH))
				_wall(doc, Vector2(cx + o, Y_MOUTH), Vector2(x0 + BAY, Y_MOUTH))
			"coude":
				var yc := 10.0
				var xe := x0 + 8.0
				_wall(doc, Vector2(cx - o, Y_MOUTH), Vector2(cx - o, yc - o))
				_wall(doc, Vector2(cx - o, yc - o), Vector2(xe, yc - o))
				_wall(doc, Vector2(cx + o, Y_MOUTH), Vector2(cx + o, yc + o))
				_wall(doc, Vector2(cx + o, yc + o), Vector2(xe, yc + o))
				_wall(doc, Vector2(x0, Y_MOUTH), Vector2(cx - o, Y_MOUTH))
				_wall(doc, Vector2(cx + o, Y_MOUTH), Vector2(x0 + BAY, Y_MOUTH))
			"escalier":
				var hw := float(c[2]) * 0.5
				doc.pieces.append({"id": doc.new_id("p"), "nom": "Mezzanine", "etage": 1, "zone": zid,
					"contour": [[x0 + 1, 3], [x0 + 9, 3], [x0 + 9, 9], [x0 + 1, 9]]})
				var st := {"id": doc.new_id("e"), "type": "escalier", "etage": 0, "rect": [cx - hw, 9, cx + hw, 16], "monte": "n"}
				MapCatalog.set_variant(st, "service")
				doc.objets.append(st)
	doc.objets.append({"id": "s1", "type": "depart", "etage": 0, "position": [5.0, 27.0]})
	doc.objets.append({"id": "b1", "type": "boite", "etage": 0, "position": [w - 4.25, DEPTH], "mur": "s", "depart": true})
	doc.ouvertures.append({"id": "o1", "type": "fenetre", "etage": 0, "position": [w - 7.75, DEPTH]})
	return doc


func start() -> bool:
	var doc := corridors_map()
	var v := MapRaster.build(doc).v
	v.analyze()
	for e in v.errors():
		at.fail("carte d'essai : " + String(e.fr))
	if doc.save_dir(EditorMap.map_dir(MAP_ID)) != OK:
		at.fail("carte d'essai non enregistrée")
		return false
	p = await H.start_solo_game(self, EditorMapDef.CUSTOM_PREFIX + MAP_ID)
	if p == null:
		return false
	game = Game.instance
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	await H.clear_zombies(self)
	nav = game.nav as MeshNav
	_probe = PhysicsShapeQueryParameters3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.12
	_probe.shape = sph
	_probe.collision_mask = 1
	if DisplayServer.get_name() != "headless":
		game.hud.visible = false
		cam = Camera3D.new()
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = 14.0
		cam.far = 60.0
		game.add_child(cam)
	# Carte refusée (une autre est chargée à sa place) : rien à mesurer.
	var ok := nav != null and nav.is_walkable(w3(5.0, 22.0)) and absf(_clear_width(0) - 1.5) < 0.1
	at.check(ok, "carte d'essai « couloirs » chargée (goulet de 1,5 m en place)")
	return ok


## Point du monde d'un point de l'éditeur (x, y), `h` au-dessus du sol.
static func w3(x: float, y: float, h := 0.0) -> Vector3:
	return Vector3(x + MapGeom.WORLD_OFFSET, h, y + MapGeom.WORLD_OFFSET)


## Point de l'éditeur (x, hauteur, y dans z) d'un point du monde.
static func ed(pos: Vector3) -> Vector3:
	return Vector3(pos.x - MapGeom.WORLD_OFFSET, pos.y, pos.z - MapGeom.WORLD_OFFSET)


## Largeur libre mesurée du goulet de la baie `i` : plus long passage libre
## (points sondés tous les 2 cm à 0,5 m du sol, couche du décor) à moins de
## 1,5 m de l'axe du goulet, en travers.
func _clear_width(i: int) -> float:
	var c: Array = CASES[i]
	if c[1] == "escalier":
		return float(c[2])
	var m := mouth(i)
	var z := Y_MOUTH if c[1] in ["porte", "fente"] else Y_MOUTH - 1.0
	var q := PhysicsPointQueryParameters3D.new()
	q.collision_mask = 1
	var space := game.get_world_3d().direct_space_state
	var best := 0.0
	var run := 0.0
	for k in 151:
		q.position = w3(m.x - 1.5 + k * 0.02, z, 0.5)
		if space.intersect_point(q, 1).is_empty():
			run += 0.02
			best = maxf(best, run)
		else:
			run = 0.0
	return best


## Le zombie `z` est-il sorti du goulet de la baie `i` ?
func _passed(i: int, z: Zombie) -> bool:
	var c: Array = CASES[i]
	var pos := ed(z.global_position)
	match c[1]:
		"droit":
			return pos.z < Y_EXIT - 0.2
		"porte", "fente":
			return pos.z < Y_MOUTH - WALL * 0.5 - 0.2
		"coude":
			return pos.x > bay_x(i) + 8.2
		"escalier":
			return pos.y > 3.2
	return false


func corridor(i: int, c: Array) -> void:
	var what := String(c[0])
	var m := mouth(i)
	var x0 := bay_x(i)
	var n: int = c[3]
	# Fente : joueur à moins de Zombie.DIRECT_RANGE de la horde (poursuite en
	# ligne droite, la ligne passe par la fente).
	var goal := w3(x0 + 6.0 if c[1] == "coude" else m.x, 13.0 if c[1] == "fente" else 4.0)
	if c[1] == "escalier":
		goal = w3(m.x, 5.0, 3.5)
	p.teleport_to(nav.closest_point(goal) + Vector3.UP * 0.05)
	await seconds(0.3)
	var zs: Array[Zombie] = []
	for k in n:
		@warning_ignore("integer_division")
		var q := w3(m.x + float(k % 5 - 2) * 1.0, 22.0 + float(k / 5) * 1.1)
		var zid := game.zombies.spawn(nav.closest_point(q), int(c[4]), 100000, int(c[5]))
		zs.append(game.zombies.get_zombie(zid))
	await H.emerged(self, zs)
	if cam:
		cam.make_current()
		cam.look_at_from_position(w3(x0 + BAY * 0.5, 15.5, 30.0), w3(x0 + BAY * 0.5, 15.5), Vector3.FORWARD)
	var mouth3 := w3(m.x, m.y)
	var limit := 40.0 if int(c[4]) != RoundRules.WALK else 70.0
	var t0 := GameClock.now()
	var passed := {}
	var still := {}   # zombie -> [position, depuis]
	var wait_max := 0.0
	var wait_at := ""
	var alone := {}   # immobiles > stall sans voisin : coincés par le décor
	var stall: float = c[7] if c.size() > 7 else STALL
	var last_pass := -1.0
	var worst_gap := 0.0
	var crowd := 0
	var min_gap := INF
	var close_frames := 0
	var in_wall := {}
	var by_slit := 0
	# Captures (avec rendu) : 0,5, 1,5 et 3 s après l'arrivée du premier zombie
	# au goulet.
	var shots := [0.5, 1.5, 3.0]
	var t_mouth := -1.0
	var space := game.get_world_3d().direct_space_state
	while GameClock.now() - t0 < limit and passed.size() < zs.size():
		await frames(1)
		var now := GameClock.now() - t0
		var waiting := 0
		var live: Array[Zombie] = []
		for z in zs:
			if is_instance_valid(z) and z.is_alive():
				live.append(z)
		for z in live:
			var pos := z.global_position
			# Torse dans un mur : sphère au milieu du buste (couche du décor).
			_probe.transform = Transform3D(Basis.IDENTITY, pos + Vector3.UP * 1.15)
			if not space.intersect_shape(_probe, 1).is_empty():
				in_wall[z] = true
			if passed.has(z):
				continue
			if _passed(i, z):
				passed[z] = now
				last_pass = now
				if c[1] == "fente" and absf(ed(pos).x - m.x) < 0.6:
					by_slit += 1
				continue
			if Vector2(pos.x - mouth3.x, pos.z - mouth3.z).length() < 2.5:
				waiting += 1
			var s: Array = still.get(z, [pos, now])
			if Vector2(pos.x - s[0].x, pos.z - s[0].z).length() > 0.3:
				s = [pos, now]
			still[z] = s
			if z.state != Zombie.State.CHASE:
				continue
			var d := now - float(s[1])
			if d > wait_max:
				wait_max = d
				wait_at = "(%.1f, %.1f)" % [ed(pos).x, ed(pos).z]
			if d > stall and not live.any(func(o): return o != z and Vector2(o.global_position.x - pos.x, o.global_position.z - pos.z).length() < 0.7):
				alone[z] = true
		crowd = maxi(crowd, waiting)
		for a in live.size():
			for b in range(a + 1, live.size()):
				var dd := live[a].global_position - live[b].global_position
				if absf(dd.y) > 1.0:
					continue
				var l := Vector2(dd.x, dd.z).length()
				min_gap = minf(min_gap, l)
				if l < 0.3:
					close_frames += 1
		# Bouchon : plus personne ne passe alors que la horde n'est pas passée.
		if last_pass >= 0.0 and passed.size() < zs.size():
			worst_gap = maxf(worst_gap, now - last_pass)
		if waiting > 0 and t_mouth < 0.0:
			t_mouth = now
		if cam and t_mouth >= 0.0 and not shots.is_empty() and now >= t_mouth + float(shots[0]):
			var st := float(shots.pop_front())
			await at.screenshot("%d_%.1fs" % [i, st])
			if st == 1.5:
				# Vue rapprochée en perspective : les corps qui se frôlent au goulet.
				var keep := cam.global_transform
				cam.projection = Camera3D.PROJECTION_PERSPECTIVE
				cam.fov = 55.0
				cam.look_at_from_position(mouth3 + Vector3(2.2, 3.2, 3.4), mouth3 + Vector3(0, 0.7, 0.3))
				await at.screenshot("%d_proche" % i)
				cam.projection = Camera3D.PROJECTION_ORTHOGONAL
				cam.global_transform = keep
	var first := INF
	var last := 0.0
	for z in passed:
		first = minf(first, float(passed[z]))
		last = maxf(last, float(passed[z]))
	var rate := float(passed.size() - 1) / maxf(last - first, 0.001) if passed.size() > 1 else 0.0
	var line := "%s | largeur libre %.2f m | passés %d/%d | débit %.2f/s | premier %.1f s | dernier %.1f s | bouchon max %.1f s | attente max %.1f s %s | coincés seuls > %.0f s : %d | foule au goulet %d | écart min %.2f m | paires < 0,3 m : %d images | torse dans un mur : %d%s" % [
		what, _clear_width(i), passed.size(), zs.size(), rate, first if first < INF else -1.0, last, worst_gap, wait_max, wait_at, stall, alone.size(),
		crowd, min_gap, close_frames, in_wall.size(), " | par la fente : %d" % by_slit if c[1] == "fente" else ""]
	print("[couloirs] " + line)
	_lines.append(line)
	at.check(passed.size() == zs.size(), "%s : %d/%d passés en %.0f s" % [what, passed.size(), zs.size(), limit])
	at.check(rate >= float(c[6]), "%s : débit %.2f/s (au moins %.1f)" % [what, rate, c[6]])
	at.check(worst_gap <= stall, "%s : jamais de bouchon (plus de %.0f s sans qu'un zombie passe ; pire %.1f s)" % [what, stall, worst_gap])
	at.check(alone.is_empty(), "%s : aucun zombie coincé seul plus de %.0f s (%d)" % [what, stall, alone.size()])
	at.check(wait_max <= WAIT_MAX, "%s : aucun zombie n'attend plus de %.0f s dans la file (pire %.1f s en %s)" % [what, WAIT_MAX, wait_max, wait_at])
	at.check(in_wall.is_empty(), "%s : aucun torse dans un mur (%d)" % [what, in_wall.size()])
	at.check(by_slit == 0, "%s : personne par la fente plus étroite que les épaules (%d)" % [what, by_slit])
	await H.clear_zombies(self)
