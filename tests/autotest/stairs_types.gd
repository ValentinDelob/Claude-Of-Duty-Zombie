extends AutotestScenario
## @couvre scripts/game/map/stair_gen.gd scripts/game/map/stair_lane.gd scripts/game/map/mesh_nav.gd scripts/game/zombies/zombie.gd
## Escaliers de chaque type (carte d'essai de l'éditeur : tests/test_stairs.gd,
## un grand hall et une mezzanine par escalier) : un marcheur, un sprinteur,
## un rampant et un chien de l'enfer montent puis descendent chaque type
## (droit, palier, en L, en U, d'honneur, de service, colimaçon, rampe) par
## ses ancres. Tous arrivent dans le temps imparti, aucun ne reste plus de
## 3 s immobile sur les marches ni ne sort de la largeur permise du couloir.

const Stairs := preload("res://tests/test_stairs.gd")
const MAP_ID := "escaliers"
## Plus longue immobilité tolérée sur les marches (s).
const STALL := 3.0
## Écart toléré au-delà de la demi-largeur du couloir (m) : poussée de la horde.
const DEV := 0.35

var H := AutotestHelpers
var game: Game
var nav: MeshNav
var p: Player


## [nom, classe de vitesse, type d'entité, rampant, nombre, vitesse (m/s)]
func cases() -> Array:
	return [
		["marcheur", RoundRules.WALK, ZombieManager.KIND_ZOMBIE, false, 1, Zombie.SPEEDS[0]],
		["sprinteur", RoundRules.SPRINT, ZombieManager.KIND_ZOMBIE, false, 1, Zombie.SPEEDS[3]],
		["rampant", RoundRules.WALK, ZombieManager.KIND_ZOMBIE, true, 1, ZombieGibs.CRAWL_SPEED],
		["chien", 3, ZombieManager.KIND_DOG, false, 1, DogRules.RUN_SPEED],
	]


func run() -> void:
	timeout_sec = 1500
	if not await start():
		return
	for tg: Array in targets():
		var l: StairLane = tg[1]
		if l == null:
			at.fail("%s : pas de couloir d'ancres" % tg[0])
			continue
		at.check(l.ok, "%s : ancres posées sur le navmesh %s" % [tg[0], l.problem])
		for up: bool in [true, false]:
			for c: Array in cases():
				await walk(l, String(tg[0]), up, c)
	finish()


## Escaliers essayés : [nom, couloir d'ancres].
func targets() -> Array:
	var out := []
	for kind: String in Stairs.KINDS:
		out.append([kind, lane_of(kind)])
	return out


func start() -> bool:
	var dir := EditorMap.map_dir(MAP_ID)
	var doc := Stairs.stairs_map()
	if doc.save_dir(dir) != OK:
		at.fail("carte d'essai non enregistrée dans " + dir)
		return false
	p = await H.start_solo_game(self, EditorMapDef.CUSTOM_PREFIX + MAP_ID)
	if p == null:
		return false
	game = Game.instance
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	await H.clear_zombies(self)
	nav = game.nav as MeshNav
	at.check(nav != null and nav.lanes.size() == Stairs.KINDS.size(), "un couloir d'ancres par escalier (%d)" % (nav.lanes.size() if nav else 0))
	return nav != null and await until(func(): return nav.ensure_anchors(), 5.0, "ancres posées")


func finish() -> void:
	game.combat.debug_invulnerable = false


func lane_of(kind: String) -> StairLane:
	for l in nav.lanes:
		if l.name.ends_with(" " + kind):
			return l
	return null


## Point au sol à `gap` m au-delà d'une ancre (0 : pied, 1 : haut), dans le
## prolongement de l'axe.
func outside(l: StairLane, end: int, gap: float) -> Vector3:
	var i := 0 if end == 0 else l.pts.size() - 1
	var j := 1 if end == 0 else l.pts.size() - 2
	var d := l.pts[i] - l.pts[j]
	d.y = 0.0
	return nav.closest_point(l.pts[i] + d.normalized() * gap)


func walk(l: StairLane, kind: String, up: bool, c: Array) -> void:
	var what := "%s %s %s" % [kind, "monte" if up else "descend", c[0]]
	var start_p := outside(l, 0 if up else 1, 1.0)
	var n: int = c[4]
	# Horde : le joueur plus loin, la foule qui l'entoure tient sur le palier.
	var goal := outside(l, 1 if up else 0, 1.0 if n == 1 else 3.0)
	p.teleport_to(goal + Vector3.UP * 0.05)
	await seconds(0.3)
	var zs: Array[Zombie] = []
	var away := start_p - goal
	away.y = 0.0
	var fwd := away.normalized()
	var lat := Vector3(-fwd.z, 0, fwd.x)
	for i in n:
		var q := start_p + lat * (float(i % 5) - 2.0) * 0.6 * (1.0 if n > 1 else 0.0) + fwd * float(i / 5) * 0.9
		var zid := game.zombies.spawn(nav.closest_point(q), int(c[1]), 100000, int(c[2]))
		zs.append(game.zombies.get_zombie(zid))
	await H.emerged(self, zs)
	if c[3]:
		for z in zs:
			ZombieGibs.become_crawler(z)
	var limit := (l.length() + 4.0) / float(c[5]) * 2.2 + 6.0 + float(n) * 1.5
	var t0 := GameClock.now()
	var arrived := {}
	var still := {}   # zombie -> [position, temps]
	var worst_stall := 0.0
	var stall_at := ""
	var worst_dev := 0.0
	var dev_at := ""
	while GameClock.now() - t0 < limit and arrived.size() < zs.size():
		await frames(1)
		var now := GameClock.now()
		for z in zs:
			if not is_instance_valid(z) or arrived.has(z):
				continue
			var pos := z.global_position
			var to := p.global_position - pos
			var flat := Vector2(to.x, to.z).length()
			# Arrivé : au contact du joueur, ou (horde qui l'entoure) descendu des
			# marches sur son sol, tout près de lui.
			var landed := absf(pos.y - p.global_position.y) < 0.3 and flat < 4.0
			if (flat < 2.2 and absf(to.y) < 1.2) or z.state == Zombie.State.ATTACK or landed:
				arrived[z] = now - t0
				continue
			# Immobile sur les marches (loin du joueur : pas dans la file qui l'entoure).
			var s: Array = still.get(z, [pos, now])
			if pos.distance_to(s[0]) > 0.3:
				s = [pos, now]
			still[z] = s
			# Bloqué contre un bord (pas derrière un autre zombie de la file).
			var queued := zs.any(func(o): return o != z and is_instance_valid(o) and o.global_position.distance_to(pos) < 0.9)
			if l.contains(pos) and flat > 3.5 and not queued and now - float(s[1]) > worst_stall:
				worst_stall = now - float(s[1])
				stall_at = "%s" % pos
			# Écart mesuré sur les marches (pas sur les sols du bas et du haut, ni
			# sur le palier de sortie du colimaçon, au niveau du haut).
			if l.contains(pos) and absf(pos.y - goal.y) > 0.3 and absf(pos.y - start_p.y) > 0.3:
				var pr := l.project(pos)
				var seg: int = pr[1]
				var dev := absf(float(pr[2])) - maxf(l.half[seg], l.half[mini(seg + 1, l.half.size() - 1)])
				if dev > worst_dev:
					worst_dev = dev
					dev_at = "%s" % pos
	var slowest := 0.0
	for z in arrived:
		slowest = maxf(slowest, float(arrived[z]))
	at.check(arrived.size() == zs.size(), "%s : %d/%d arrivés en %.1f s (limite %.0f s)%s" % [what, arrived.size(), zs.size(), slowest, limit,
		"" if arrived.size() == zs.size() else " ; restés en " + str(zs.filter(func(z): return is_instance_valid(z) and not arrived.has(z)).map(func(z): return "%s (état %d, chemin %d/%d)" % [z.global_position, z.state, z._path_i, z._path.size()]))])
	at.check(worst_stall <= STALL, "%s : jamais plus de %.0f s immobile sur les marches (pire %.1f s %s)" % [what, STALL, worst_stall, stall_at])
	at.check(worst_dev <= DEV, "%s : dans la largeur du couloir (au plus %.2f m au-delà%s)" % [what, maxf(worst_dev, 0.0), " en " + dev_at if dev_at != "" else ""])
	await H.clear_zombies(self)
