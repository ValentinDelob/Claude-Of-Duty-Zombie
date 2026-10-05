extends AutotestScenario
## @couvre scripts/editor/map_rules.gd scripts/editor/map_validator.gd scripts/editor/map_raster.gd scripts/game/map/mesh_nav.gd scripts/game/zombies/zombie.gd
## Immeuble de 5 étages de l'éditeur (tests/test_stairs_floors.gd : une cage
## aux volées alternées, du rez-de-chaussée au 5e étage) : le joueur MONTE à
## pied du rez-de-chaussée au dernier étage par les quatre escaliers, puis
## REDESCEND ; un zombie qui court le suit d'un étage à l'autre (du
## rez-de-chaussée au 5e étage, puis du 5e au rez-de-chaussée) par les ancres
## des escaliers.

const Floors := preload("res://tests/test_stairs_floors.gd")
const MAP_ID := "immeuble"
## Repère du jeu = repère de l'éditeur + 4,25 m (MapLayoutExport).
const OFF := 4.25

var H := AutotestHelpers
var game: Game
var nav: MeshNav
var p: Player
var doc: EditorMap


func run() -> void:
	timeout_sec = 400
	doc = Floors.tower_with_stairs()
	var dir := EditorMap.map_dir(MAP_ID)
	if doc.save_dir(dir) != OK:
		at.fail("carte d'essai non enregistrée dans " + dir)
		return
	p = await H.start_solo_game(self, EditorMapDef.CUSTOM_PREFIX + MAP_ID)
	if p == null:
		return
	game = Game.instance
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	await H.clear_zombies(self)
	nav = game.nav as MeshNav
	at.check(nav != null and nav.lanes.size() == Floors.FLOORS - 1, "un couloir d'ancres par escalier (%d)" % (nav.lanes.size() if nav else 0))
	if nav == null or not await until(func(): return nav.ensure_anchors(), 5.0, "ancres posées"):
		return
	for l in nav.lanes:
		at.check(l.ok, "%s : ancres sur le navmesh %s" % [l.name, l.problem])
	await climb()
	await follow(true)
	await follow(false)
	game.combat.debug_invulnerable = false


## Point du monde au-dessus de (x, y) de l'éditeur, au sol de l'étage k.
func world(x: float, y: float, k: int) -> Vector3:
	return Vector3(x + OFF, doc.level_alt(k), y + OFF)


## Chemin à pied du rez-de-chaussée au dernier étage : pied puis haut de
## chaque volée (MapRules.stair_parts : centre de ses cases de départ et
## d'arrivée), [point, étage].
func route_up() -> Array:
	var out := []
	for k in Floors.FLOORS - 1:
		var o := doc.find("e%d" % k)
		var parts := MapRules.stair_parts(o)
		out.append([world_of(parts.foot, k), k])
		out.append([world_of(parts.exit, k + 1), k + 1])
	return out


func world_of(cells: Dictionary, k: int) -> Vector3:
	var c := Vector2.ZERO
	for q in cells:
		c += MapGeom.cell_center(q)
	c /= float(cells.size())
	return world(c.x, c.y, k)


## Le joueur (bot) marche jusqu'à `goal` (cap vers le point, touche avancer).
func walk(goal: Vector3, limit: float) -> bool:
	var t0 := GameClock.now()
	while GameClock.now() - t0 < limit:
		var d := goal - p.global_position
		d.y = 0.0
		if d.length() < 0.35:
			p.input.move = Vector2.ZERO
			return true
		p.yaw = atan2(-d.x, -d.z)
		p.rotation.y = p.yaw
		p.input.move = Vector2(0, 1)
		await frames(1)
	p.input.move = Vector2.ZERO
	return false


## Monte du rez-de-chaussée au 5e étage puis redescend, à pied.
func climb() -> void:
	var up := route_up()
	p.teleport_to(world(12.0, 7.0, 0) + Vector3.UP * 0.05)
	await seconds(0.3)
	for step: Array in up:
		var ok := await walk(step[0], 15.0)
		var k: int = step[1]
		at.check(ok and absf(p.global_position.y - doc.level_alt(k)) < 0.35,
			"montée : étage %d atteint en %s (y %.2f, attendu %.2f)" % [k, step[0], p.global_position.y, doc.level_alt(k)])
	var down := up.duplicate()
	down.reverse()
	for i in down.size():
		# En descendant : du haut (arrivée) au pied de chaque volée.
		var step: Array = down[i]
		var k: int = step[1]
		var ok := await walk(step[0], 15.0)
		at.check(ok and absf(p.global_position.y - doc.level_alt(k)) < 0.35,
			"descente : étage %d atteint en %s (y %.2f, attendu %.2f)" % [k, step[0], p.global_position.y, doc.level_alt(k)])
	at.check(absf(p.global_position.y) < 0.35, "revenu au rez-de-chaussée (y %.2f)" % p.global_position.y)


## Un zombie qui court suit le joueur : `up` : joueur au 5e étage, zombie au
## rez-de-chaussée ; sinon l'inverse.
func follow(up: bool) -> void:
	var top := Floors.FLOORS - 1
	var stand := world(12.0, 7.0, top if up else 0)
	var start := world(12.0, 9.0, 0 if up else top)
	p.teleport_to(stand + Vector3.UP * 0.05)
	await seconds(0.5)
	var z := game.zombies.get_zombie(game.zombies.spawn(nav.closest_point(start), RoundRules.SPRINT, 100000))
	await H.emerged(self, [z])
	var t0 := GameClock.now()
	var floors_seen := {}
	var ok: bool = await until(func():
		if is_instance_valid(z):
			for k in Floors.FLOORS:
				if absf(z.global_position.y - doc.level_alt(k)) < 0.3:
					floors_seen[k] = true
		return is_instance_valid(z) and z.global_position.distance_to(p.global_position) < 2.5, 90.0,
		"zombie %s" % ("monté au 5e étage" if up else "descendu au rez-de-chaussée"))
	at.check(ok, "zombie qui court %s en %.1f s (étages traversés : %s)" % ["monté du rez-de-chaussée au 5e étage" if up else "descendu du 5e étage au rez-de-chaussée",
		GameClock.now() - t0, str(floors_seen.keys())])
	at.check(floors_seen.size() == Floors.FLOORS, "le zombie passe par chaque étage (%s)" % str(floors_seen.keys()))
	await H.clear_zombies(self)
