extends AutotestScenario
## @couvre scripts/game/barricades/* scripts/game/map/mesh_map_layout.gd scripts/game/map/mesh_map_geometry.gd scripts/game/map/mesh_map_builder.gd tests/fixtures/maps/smallest/* tests/fixtures/maps/smallest_door/* tests/fixtures/maps/smallest_double_door/* assets/maps/kino/*
## Régression (« je me bloque sur les bords des fenêtres à zombies : la
## hitbox dépasse vers l'intérieur ») : le joueur longe, côté salle, le mur
## percé de CHAQUE entrée des zombies (fenêtres des 22 de KINO ; fenêtre,
## porte simple et porte double des cartes de l'éditeur : mur de la grille,
## hors grille, en biais), dans les deux sens : à 3 cm du mur, collé en
## poussant en diagonale (30° et 60°), en sprint, à reculons.
## Mesures (pas à l'œil) : vitesse le long du mur à chaque pas de physique
## (arrêt net : moins de 60 % de la vitesse prise avant l'ouverture), normales
## de contact (get_slide_collision : accroche = normale qui a une composante
## le long du mur), arrivée au bout ; et un balayage en rayons à 3 cm devant
## le nu du mur (rien ne doit en dépasser devant l'ouverture).
## Puis, fenêtre ouverte, le joueur pousse droit dessus : il ne sort pas.
## Défaut (échec) : ce qui touche une collision de l'entrée elle-même. Ce qui
## vient des murs de la carte autour (joints du maillage de KINO, mur
## perpendiculaire mal découpé) est relevé à part (« NOTE », sans échec) :
## hors de la barricade, voir le rapport du scénario.

const SW := preload("res://tests/autotest/smallest_window.gd")
const TZ := preload("res://tests/test_zombie_doors.gd")
## Écart au mur au départ d'une course (m, entre la capsule et le nu du mur).
const GAP := 0.03
## Arrêt net : vitesse le long du mur tombée sous cette part de la vitesse
## prise avant l'ouverture.
const STALL := 0.6
## Accroche : contact dont la normale (à plat) a au moins cette composante
## le long du mur (un mur plat ne pousse que vers la salle).
const SNAG_SIDE := 0.3

var H := AutotestHelpers
var game: Game
var p: Player
var _space: PhysicsDirectSpaceState3D
## Bilan : [carte, entrée, défaut] des défauts relevés (échec), et des
## gênes dues aux murs de la carte, pas à l'entrée (relevées, sans échec).
var faults: Array = []
var notes: Array = []
var runs := 0


func run() -> void:
	timeout_sec = 600
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 5.0, "menu principal")
	# Cartes de l'éditeur : fixtures (fenêtre sur un mur hors grille, portes)
	# et cartes construites ici (fenêtre sur un mur de la grille, en biais).
	var maps := ["kino"]
	for id in ["smallest", "smallest_door", "smallest_double_door"]:
		if SW.install_fixture(id, "res://tests/fixtures/maps/" + id) != "":
			maps.append(EditorMapDef.CUSTOM_PREFIX + id)
	for doc: EditorMap in [TZ.grid_map("fenetre"), TZ.oblique_map("fenetre"), TZ.oblique_map("porte_double")]:
		var dir := EditorMap.map_dir(doc.id())
		if dir != "" and dir.begins_with(ProjectSettings.globalize_path("res://tests/_out")) and doc.save_dir(dir) == OK:
			maps.append(EditorMapDef.CUSTOM_PREFIX + doc.id())
	at.check(maps.size() == 7, "7 cartes à parcourir (%s)" % ", ".join(maps))
	for map_id in maps:
		await _map(map_id)
		if p == null:
			break
		Router.back_to_menu()
		await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 10.0, "retour au menu")
	SW.remove_dir(EditorMap.maps_root())
	print("[slide] %d courses, %d défaut(s)" % [runs, faults.size()])
	for f in faults:
		print("[slide] DÉFAUT %s / %s : %s" % f)
	for f in notes:
		print("[slide] NOTE (mur de la carte) %s / %s : %s" % f)


func _map(map_id: String) -> void:
	p = await H.start_solo_game(self, map_id)
	if p == null:
		return
	game = Game.instance
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	p.untargetable = true
	await H.clear_zombies(self)
	await seconds(0.3)
	_space = p.get_world_3d().direct_space_state
	var list: Array = game.barricades.windows
	at.check(list.size() >= 1, "%s : %d entrée(s) des zombies" % [map_id, list.size()])
	var bad0 := faults.size()
	for b: Barricade in list:
		await _barricade(map_id, b)
		if not is_instance_valid(p):
			return
	at.check(faults.size() == bad0, "%s : on longe les %d entrée(s) sans arrêt net ni accroche, rien ne dépasse du mur (%d défaut(s))" % [map_id, list.size(), faults.size() - bad0])


## Distance (le long de `inn`, depuis `b`) du nu du mur côté salle mesurée
## par rayons sur le monde seul (couche 1 : pas la barrière) : sous l'allège
## et au-dessus de l'ouverture (le mur percé lui-même), sinon à côté de
## l'ouverture (la plus proche : un mur perpendiculaire voisin est plus
## loin) ; NAN si introuvable.
func _inner_face(b: Barricade, inn: Vector3, side: Vector3) -> float:
	var own: Array = [[Vector3.ZERO, b.opening_height + 0.12]]
	if not b.is_door():
		own.append([Vector3.ZERO, Barricade.SILL_TOP * 0.5])
	var hits := _face_hits(b, inn, own)
	if hits.is_empty():
		hits = _face_hits(b, inn, [[side * (b.width * 0.5 + 0.3), 1.0], [-side * (b.width * 0.5 + 0.3), 1.0]])
	if hits.is_empty():
		return NAN
	hits.sort()
	return hits[0]


func _face_hits(b: Barricade, inn: Vector3, probes: Array) -> Array[float]:
	var hits: Array[float] = []
	for pr in probes:
		var from: Vector3 = b.global_position + pr[0] + inn * 1.2 + Vector3.UP * float(pr[1])
		var q := PhysicsRayQueryParameters3D.create(from, from - inn * 1.6, 1)
		var r := _space.intersect_ray(q)
		if not r.is_empty() and (r.normal as Vector3).dot(inn) > 0.95:
			hits.append((r.position - b.global_position).dot(inn))
	return hits


## Place libre le long du mur, du milieu de l'ouverture vers `dir` (m) :
## bande où passe la capsule (3 hauteurs, 3 distances au mur), la barrière
## de l'entrée exclue (on cherche les murs et le décor qui bornent la course).
func _free_along(b: Barricade, face: float, inn: Vector3, dir: Vector3) -> float:
	var free := 3.0
	var ex: Array[RID] = []
	for n in b.find_children("*", "CollisionObject3D", true, false):
		ex.append((n as CollisionObject3D).get_rid())
	for d in [GAP + 0.02, Player.RADIUS + GAP, Player.RADIUS * 2.0 + GAP]:
		for h in [0.25, 0.9, 1.6]:
			var from: Vector3 = b.global_position + inn * (face + d) + Vector3.UP * h
			var q := PhysicsRayQueryParameters3D.create(from, from + dir * 3.0, 1 | Barricade.BARRIER_LAYER, ex)
			var r := _space.intersect_ray(q)
			if not r.is_empty():
				free = minf(free, (r.position - from).dot(dir) - Player.RADIUS - 0.05)
	# Sol continu sous la course (balcons, marches).
	var s := 0.0
	while s < free:
		var at_s := b.global_position + inn * (face + Player.RADIUS + GAP) + dir * s
		var q := PhysicsRayQueryParameters3D.create(at_s + Vector3.UP * 0.5, at_s + Vector3.DOWN * 0.3, 1)
		var r := _space.intersect_ray(q)
		if r.is_empty() or absf(r.position.y - b.global_position.y) > 0.1:
			return maxf(s - Player.RADIUS - 0.05, 0.0)
		s += 0.1
	return free


## `own` : la gêne vient d'une collision de l'entrée (défaut) ; sinon d'un
## mur de la carte (note).
func _fault(map_id: String, b: Barricade, what: String, own := true) -> void:
	(faults if own else notes).append([map_id, "%s %d (%s)" % [b.kind, b.window_index, b.global_position.snapped(Vector3.ONE * 0.01)], what])


## Le collider `c` est-il une collision de l'entrée `b` ?
static func _own(b: Barricade, c: Variant) -> bool:
	return c is Node and (c == b or b.is_ancestor_of(c))


func _barricade(map_id: String, b: Barricade) -> void:
	var inn := Vector3(b.inward.x, 0, b.inward.z).normalized()
	var side := Vector3(-inn.z, 0, inn.x)
	var face := _inner_face(b, inn, side)
	if is_nan(face):
		_fault(map_id, b, "nu du mur côté salle introuvable")
		return
	# 1. Collisions de l'entrée au-delà du nu du mur (mesure des formes).
	for cs: CollisionShape3D in b.find_children("*", "CollisionShape3D", true, false):
		var box := cs.shape as BoxShape3D
		if box == null:
			continue
		var hi := -INF
		var h := box.size * 0.5
		for sx in [-1, 1]:
			for sy in [-1, 1]:
				for sz in [-1, 1]:
					hi = maxf(hi, (cs.global_transform * Vector3(h.x * sx, h.y * sy, h.z * sz) - b.global_position).dot(inn))
		print("[slide] %s %s %d : nu du mur à %.3f m, collision %s jusqu'à %.3f m (dépasse de %.3f m)" % [map_id, b.kind, b.window_index, face, cs.get_parent().name, hi, hi - face])
		if hi > face + 0.01:
			_fault(map_id, b, "collision %s : %.0f cm dans la salle au-delà du nu du mur" % [cs.get_parent().name, (hi - face) * 100.0])
	# 2. Balayage physique à 3 cm devant le nu du mur, devant l'ouverture.
	for hgt in [0.2, 1.0, 1.7]:
		for s in [-1.0, 1.0]:
			var from: Vector3 = b.global_position + inn * (face + GAP) + Vector3.UP * hgt - side * s * (b.width * 0.5 + 0.3)
			var q := PhysicsRayQueryParameters3D.create(from, from + side * s * (b.width + 0.6), 1 | Barricade.BARRIER_LAYER)
			var r := _space.intersect_ray(q)
			if not r.is_empty():
				var hp: Vector3 = r.position - b.global_position
				_fault(map_id, b, "obstacle à %d cm devant le mur, %.1f m de haut (%s, à %.2f m du milieu le long du mur, normale %s)" % [roundi(GAP * 100), hgt, (r.collider as Node).name, hp.dot(side), (r.normal as Vector3).snapped(Vector3.ONE * 0.01)], _own(b, r.collider))
				break
	# 3. Courses le long du mur.
	for s in [1.0, -1.0]:
		var back := minf(_free_along(b, face, inn, -side * s), b.width * 0.5 + 1.3)
		var ahead := minf(_free_along(b, face, inn, side * s), b.width * 0.5 + 1.0)
		if back < b.width * 0.5 + 0.7 or ahead < b.width * 0.5 + Player.RADIUS + 0.2:
			print("[slide] %s %s %d sens %+d : pas la place de longer le mur (%.2f / %.2f m)" % [map_id, b.kind, b.window_index, s, back, ahead])
			continue
		for mode in [["à 3 cm", 0.0, false, false], ["diagonale 30°", 30.0, false, false], ["diagonale 60°", 60.0, false, false],
				["sprint", 20.0, true, false], ["à reculons", 30.0, false, true]]:
			await _run(map_id, b, face, inn, side * s, back, ahead, mode)
			if not is_instance_valid(p):
				return
	# 4. Fenêtre ouverte : le joueur pousse droit dessus et ne sort pas.
	var m0 := b.mask
	b.srv_set_mask(0)
	p.teleport_to(b.global_position + inn * (face + 1.0) + Vector3.UP * 0.05, atan2(inn.x, inn.z))
	p.input.move = Vector2(0, 1)
	p.input.sprint = false
	await seconds(1.0)  # durée mesurée : le joueur pousse contre l'ouverture
	p.input.move = Vector2.ZERO
	if not b.is_inside(p.global_position):
		_fault(map_id, b, "entrée ouverte : le joueur sort (%.2f m)" % (p.global_position - b.global_position).dot(inn))
	b.srv_set_mask(m0)


## Une course : de `back` avant le milieu de l'ouverture à `ahead` après,
## direction `dir`, en poussant vers le mur de `mode[1]` degrés.
func _run(map_id: String, b: Barricade, face: float, inn: Vector3, dir: Vector3, back: float, ahead: float, mode: Array) -> void:
	runs += 1
	var ang := deg_to_rad(float(mode[1]))
	var wish := dir * cos(ang) - inn * sin(ang)
	var backwards: bool = mode[3]
	var look := -dir if backwards else dir
	var start := b.global_position + inn * (face + Player.RADIUS + GAP) - dir * back + Vector3.UP * 0.05
	p.teleport_to(start, atan2(-look.x, -look.z))
	p.energy.value = p.energy.max_value
	p.energy.exhausted = false
	var basis := Basis(Vector3.UP, p.yaw)
	p.input.move = Vector2(wish.dot(basis.x), wish.dot(-basis.z))
	p.input.sprint = mode[2]
	var half := b.width * 0.5
	var zone := half + Player.RADIUS + 0.15
	var base_v := 0.0
	var min_v := INF
	var min_at := 0.0
	var min_touch := []
	var min_own := false
	var snags := {}
	var snag_own := false
	var t := 0.0
	var limit := (back + ahead) / 1.5 + 1.0
	var lat := -back
	while t < limit:
		await tree().physics_frame
		if not is_instance_valid(p):
			return
		t += 1.0 / Engine.physics_ticks_per_second
		lat = (p.global_position - b.global_position).dot(dir)
		var v := p.velocity.dot(dir)
		# Contacts de ce pas (les deux premiers pas après la téléportation
		# gardent ceux de l'endroit d'avant) devant l'ouverture : collider,
		# normale, point (le long du mur depuis le milieu, distance au nu du
		# mur, hauteur). Plus loin le long du mur : murs et décor de la
		# salle, hors sujet.
		var touch := []
		for i in p.get_slide_collision_count():
			var c := p.get_slide_collision(i)
			for k in c.get_collision_count():
				var cp := c.get_position(k) - b.global_position
				if t < 0.05 or absf(cp.dot(dir)) > zone:
					continue
				var n := c.get_normal(k)
				var who: String = (c.get_collider(k) as Node).name if c.get_collider(k) is Node else "?"
				var mine := _own(b, c.get_collider(k))
				touch.append([who, n.snapped(Vector3.ONE * 0.01), snappedf(cp.dot(dir), 0.01), snappedf(cp.dot(inn) - face, 0.01), snappedf(cp.y, 0.01)])
				if mine:
					min_own = min_own or v < base_v * STALL
				var nh := Vector3(n.x, 0, n.z)
				if nh.length() < 0.5:
					continue   # sol
				var along := absf(nh.normalized().dot(dir))
				if along >= SNAG_SIDE and (not snags.has(who) or along > float(snags[who][0])):
					snags[who] = [snappedf(along, 0.01), snappedf(cp.dot(dir), 0.01), snappedf(cp.dot(inn) - face, 0.01), snappedf(cp.y, 0.01)]
					snag_own = snag_own or mine
		if lat < -zone and t > 0.1:
			base_v = maxf(base_v, v)
		elif absf(lat) <= zone and base_v > 0.0 and v < min_v:
			min_v = v
			min_at = lat
			min_touch = touch
		if lat >= ahead - 0.05:
			break
	p.input.move = Vector2.ZERO
	p.input.sprint = false
	var label := "%s, sens %s" % [mode[0], "+" if dir.dot(Vector3(-inn.z, 0, inn.x)) > 0 else "-"]
	if base_v <= 0.5:
		_fault(map_id, b, "%s : pas de vitesse avant l'ouverture (%.2f m/s)" % [label, base_v])
	elif min_v < base_v * STALL:
		_fault(map_id, b, "%s : arrêt net devant l'ouverture (%.2f m/s au lieu de %.2f, à %.2f m du milieu ; contacts %s)" % [label, min_v, base_v, min_at, min_touch], min_own)
	if not snags.is_empty():
		_fault(map_id, b, "%s : accroche (normale de contact le long du mur : %s)" % [label, snags], snag_own)
	if lat < ahead - 0.3:
		_fault(map_id, b, "%s : n'arrive pas au bout (%.2f m sur %.2f)" % [label, lat + back, ahead + back])
	await frames(1)
