extends AutotestScenario
## @couvre scripts/game/barricades/* scripts/game/rounds/spawner.gd scripts/game/zombies/zombie.gd scripts/game/zombies/zombie_anim.gd tests/fixtures/maps/smallest_door/* tests/fixtures/maps/smallest_double_door/*
## Portes à zombies (format 8, docs/MAP_OBJECTS.md § 9) sur deux copies de
## la carte SMALLEST (une salle) : une porte simple, puis une porte double.
## 1. manche 1, joueur collé à la porte : les zombies apparaissent dehors et
##    viennent à la porte ; jamais plus que la file de la porte (simple 4 :
##    1 qui arrache + 3 qui attendent ; double 6 : 2 + 4) ;
## 2. arrachage : porte simple, jamais deux zombies qui arrachent à la fois
##    (un seul arrache toutes les planches) ; porte double, deux à la fois
##    (un par battant), plus vite ; personne n'entre tant qu'il reste une
##    planche ; après la dernière, chacun enjambe le battant cassé et entre ;
## 3. le joueur ne passe pas par la porte ouverte ; il la reconstruit en
##    maintenant [F] (+10 par planche).

const SW := preload("res://tests/autotest/smallest_window.gd")
const MAPS := ["smallest_door", "smallest_double_door"]

var H := AutotestHelpers
var game: Game
var p: Player
var w: Barricade
var max_waiting := 0
var max_pulling := 0
var max_stepping := 0
var escaped := false
## Zombie (id) -> nombre de planches arrachées pendant son geste.
var rippers := {}
var _planks := 0


## Zombies postés à une place où l'on arrache, en plein geste (pas en pause).
func _pulling() -> Array[Zombie]:
	var out: Array[Zombie] = []
	for z: Zombie in game.zombies.alive:
		if z.barricade != w or z.state != Zombie.State.BARRIER or z.tear_frenzy or z.tear_t <= 0.0:
			continue
		for i in w.tear_slots():
			if Barricade._flat_dist(z.global_position, w.slot_point(i)) < 0.55:
				out.append(z)
				break
	return out


func _sample() -> void:
	if game == null or not is_instance_valid(game) or w == null or not is_instance_valid(w):
		return
	max_waiting = maxi(max_waiting, w.waiting_count())
	var pulling := _pulling()
	max_pulling = maxi(max_pulling, pulling.size())
	var stepping := 0
	for z: Zombie in game.zombies.alive:
		if z.barricade == w and z.state == Zombie.State.VAULT:
			stepping += 1
		if w.planks() > 0 and z.state == Zombie.State.BARRIER and z.barricade == w and w.is_inside(z.global_position):
			escaped = true
	max_stepping = maxi(max_stepping, stepping)
	var n := w.planks()
	if n < _planks:
		# Planche tombée : à celui (ou ceux) qui tiraient à cet instant.
		for z in pulling:
			rippers[z.id] = int(rippers.get(z.id, 0)) + 1
	_planks = n


func _reset() -> void:
	max_waiting = 0
	max_pulling = 0
	max_stepping = 0
	escaped = false
	rippers.clear()
	_planks = w.planks()


func run() -> void:
	timeout_sec = 300
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 5.0, "menu principal")
	for map_id in MAPS:
		await _map(map_id)
		if p == null:
			return
		Router.back_to_menu()
		await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 10.0, "retour au menu")
	SW.remove_dir(EditorMap.maps_root())


func _map(map_id: String) -> void:
	var dir := SW.install_fixture(map_id, "res://tests/fixtures/maps/" + map_id)
	at.check(dir != "", "%s copiée dans le dossier des cartes du test" % map_id)
	p = null
	if dir == "":
		return
	p = await H.start_solo_game(self, EditorMapDef.CUSTOM_PREFIX + map_id)
	if p == null:
		return
	game = Game.instance
	var double := map_id == "smallest_double_door"
	var kind := BarricadeRules.DOUBLE_DOOR if double else BarricadeRules.DOOR
	at.check(game.barricades.windows.size() == 1, "%s : une entrée des zombies" % map_id)
	if game.barricades.windows.size() != 1:
		return
	w = game.barricades.windows[0]
	at.check(w.kind == kind and w.is_door(), "%s : porte à zombies de type %s (%s)" % [map_id, kind, w.kind])
	at.check(w.planks() == BarricadeRules.planks_for(kind), "%d planches" % w.planks())
	at.check(game.spawner.points.size() == (2 if double else 1), "apparitions derrière la porte : %d" % game.spawner.points.size())
	game.combat.debug_invulnerable = true
	_reset()
	tree().physics_frame.connect(_sample)

	# 1. Manche 1, joueur collé à la porte : les zombies viennent, file bornée.
	p.teleport_to(w.global_position + w.inward * 0.7 + Vector3(0, 0.05, 0), atan2(w.inward.x, w.inward.z))
	var spawned: Array[Zombie] = []
	var on_spawn := func(z: Zombie): spawned.append(z)
	game.zombies.zombie_spawned.connect(on_spawn)
	var ok: bool = await until(func(): return game.rounds.round_n == 1 and spawned.size() >= 1, 15.0, "un zombie apparaît derrière la porte")
	at.check(ok, "manche 1 : un zombie apparaît derrière la porte, joueur collé à elle")
	var want := mini(w.queue_max(), game.rounds.total)
	ok = await until(func(): return w.waiting_count() >= want, 30.0, "%d zombies à la porte" % want)
	at.check(ok, "%d zombies se postent à la porte (%d)" % [want, w.waiting_count()])
	await seconds(4.0)  # file pleine : aucun de plus ne doit apparaître
	at.check(max_waiting <= w.queue_max(), "jamais plus de %d zombies à la porte (max %d)" % [w.queue_max(), max_waiting])
	game.zombies.zombie_spawned.disconnect(on_spawn)
	game.rounds.paused = true
	await H.clear_zombies(self)

	# 2. Arrachage : file pleine, joueur hors d'atteinte.
	w.srv_set_mask(w.full_mask())
	p.untargetable = true
	p.teleport_to(w.global_position + w.inward * 3.0 + Vector3(0, 0.05, 0))
	await seconds(0.3)
	_reset()
	var crowd: Array[int] = []
	var t0 := GameClock.now()
	for i in w.queue_max():
		var sp: Vector3 = game.spawner.points[i % game.spawner.points.size()].pos
		crowd.append(game.zombies.spawn(sp, [RoundRules.WALK, RoundRules.RUN, RoundRules.SPRINT][i % 3], 100000))
		await seconds(0.8)  # chacun quitte le point d'apparition
	ok = await until(func(): return w.planks() == 0, 40.0, "toutes les planches arrachées")
	var dur := GameClock.now() - t0
	await frames(3)  # relevé du dernier pas de physique (_sample)
	print("[zombie_doors] %s : %d planches en %.1f s, %d arrachent à la fois au plus, arracheurs %s" % [map_id, BarricadeRules.planks_for(kind), dur, max_pulling, str(rippers)])
	at.check(ok, "%s : la horde arrache toutes les planches (%.1f s)" % [map_id, dur])
	if double:
		at.check(max_pulling == 2, "porte double : deux zombies arrachent à la fois (max %d)" % max_pulling)
		at.check(rippers.size() >= 2, "porte double : chacun son battant (%d arracheurs)" % rippers.size())
		at.check(dur < 10 * BarricadeRules.TEAR_TIME * 0.75, "porte double : 10 planches en %.1f s (deux à la fois)" % dur)
	else:
		at.check(max_pulling == 1, "porte simple : jamais deux zombies qui arrachent à la fois (max %d)" % max_pulling)
		at.check(rippers.size() == 1, "porte simple : un seul arracheur (%d)" % rippers.size())
		at.check(dur > 5 * BarricadeRules.TEAR_TIME, "porte simple : 6 planches à 2,5 s chacune (%.1f s)" % dur)
	at.check(max_waiting <= w.queue_max(), "file de la porte respectée (max %d)" % max_waiting)
	at.check(not escaped, "personne n'entre tant qu'il reste une planche")
	# Après la dernière planche : chacun enjambe le battant cassé et entre,
	# puis va vers le joueur (de nouveau ciblable, invulnérable) : l'arrivée
	# se libère pour le suivant.
	p.untargetable = false
	p.teleport_to(w.global_position + w.inward * 3.5 + Vector3(0, 0.05, 0))
	ok = await until(func():
		for id in crowd:
			var z := game.zombies.get_zombie(id)
			if z == null or z.barricade != null or z.state == Zombie.State.VAULT or not w.is_inside(z.global_position):
				return false
		return true, 30.0, "toute la horde entrée")
	if not ok:
		for id in crowd:
			var z := game.zombies.get_zombie(id)
			if z:
				print("[zombie_doors] zombie %d : état %d, fenêtre %s, dedans %s, à %.2f m" % [id, z.state, str(z.barricade != null), str(w.is_inside(z.global_position)),
					(z.global_position - w.global_position).dot(w.inward)])
	print("[zombie_doors] %s : %d enjambent à la fois au plus" % [map_id, max_stepping])
	at.check(ok, "%s : tous les zombies passent la porte et entrent (%d)" % [map_id, crowd.size()])
	at.check(max_stepping >= 1, "enjambement vu")
	await H.clear_zombies(self)
	p.untargetable = false

	# 3. Le joueur ne sort pas par la porte ouverte.
	w.srv_set_mask(0)
	p.teleport_to(w.global_position + w.inward * 1.6 + Vector3(0, 0.05, 0), atan2(w.inward.x, w.inward.z))
	p.input.move = Vector2(0, 1)
	await seconds(1.2)  # durée mesurée : le joueur pousse contre la porte
	p.input.move = Vector2.ZERO
	at.check(w.is_inside(p.global_position), "porte ouverte : le joueur ne peut pas sortir")
	# Réparation : maintien de [F], +10 par planche.
	var pd := game.session.local_data()
	var pts0 := pd.points
	p.teleport_to(w.repair_spot() + Vector3(0, 0.05, 0))
	H.aim_at(p, w.global_position + Vector3.UP * 1.2)
	await seconds(0.2)  # le joueur se pose avant d'appuyer
	p.input.interact = true
	p.input.interact_pressed = true
	ok = await until(func(): return w.planks() == BarricadeRules.planks_for(kind), 12.0, "porte reconstruite")
	p.input.interact = false
	at.check(ok, "maintenir [F] reconstruit la porte planche par planche (%d)" % w.planks())
	await until(func(): return pd.points - pts0 >= 10 * BarricadeRules.planks_for(kind), 2.0, "points des planches")
	at.check(pd.points - pts0 == 10 * BarricadeRules.planks_for(kind), "+10 points par planche reposée (+%d)" % (pd.points - pts0))
	tree().physics_frame.disconnect(_sample)
	game.rounds.paused = false
