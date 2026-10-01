extends AutotestScenario
## @couvre scripts/game/barricades/* scripts/game/rounds/spawner.gd tests/fixtures/maps/smallest/*
## Carte SMALLEST du joueur (une petite salle, UNE fenêtre ; copie dans
## tests/fixtures/maps/smallest/), jouée comme une carte de l'éditeur
## (« perso:smallest », dossier des cartes de tests/_out) :
## 1. joueur collé à la fenêtre dès la manche 1 : les zombies apparaissent
##    quand même dehors et viennent à la fenêtre (avant : aucun, point
##    d'apparition à moins de 7 m du joueur) ; jamais plus de 3 qui attendent
##    derrière (une place chacun) ; les suivants arrivent quand une place se
##    libère, sans changer le nombre de zombies de la manche ;
## 2. un zombie seul arrache une planche toutes les 2,5 s environ, avec une
##    pause « de folie » entre deux ; trois zombies prennent chacun leur place
##    et arrachent chacun à leur rythme (marcheur, coureur et sprinteur à la
##    même cadence).

const MAP := "smallest"
const FIXTURE := "res://tests/fixtures/maps/smallest"

var H := AutotestHelpers
var game: Game
var w: Barricade
var max_waiting := 0
var max_attached := 0
## Arrachage : instants (s de jeu) de chaque planche tombée.
var rips: Array[float] = []
var _planks := 6
## zid -> [instants des débuts de pause de folie], temps passé en pause.
var frenzy_starts := {}
var frenzy_time := {}
var _was_frenzy := {}
var frenzy_bit_seen := false


## Copie la carte de test dans le dossier des cartes de ce scénario
## (EditorMap.maps_root() : tests/_out/editor_maps_<scénario>, jamais les
## cartes du joueur). Retourne le dossier de la carte, "" en cas d'échec.
static func install_fixture(map_id: String, fixture: String) -> String:
	var dst := EditorMap.map_dir(map_id)
	if dst == "" or not dst.begins_with(ProjectSettings.globalize_path("res://tests/_out")):
		return ""
	DirAccess.make_dir_recursive_absolute(dst)
	for f in DirAccess.get_files_at(fixture):
		if not f.ends_with(".json"):
			continue
		var txt := FileAccess.get_file_as_string(fixture.path_join(f))
		var out := FileAccess.open(dst.path_join(f), FileAccess.WRITE)
		if out == null:
			return ""
		out.store_string(txt)
		out.close()
	return dst if EditorMap.is_map_dir(dst) else ""


static func remove_dir(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for d in DirAccess.get_directories_at(dir):
		remove_dir(dir.path_join(d))
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


func _attached() -> Array[Zombie]:
	var out: Array[Zombie] = []
	for z: Zombie in game.zombies.alive:
		if z.barricade == w and z.state != Zombie.State.VAULT:
			out.append(z)
	return out


## À chaque pas de physique : file derrière la fenêtre, planches, pauses.
func _sample() -> void:
	if game == null or not is_instance_valid(game) or w == null or not is_instance_valid(w):
		return
	max_waiting = maxi(max_waiting, w.waiting_count())
	max_attached = maxi(max_attached, _attached().size())
	var now := GameClock.now()
	var n := w.planks()
	var had_planks := n > 0
	for i in maxi(_planks - n, 0):
		rips.append(now)
	_planks = n
	for z: Zombie in game.zombies.alive:
		if z.barricade != w:
			continue
		var f := z.tear_frenzy and z.state == Zombie.State.BARRIER
		# Début de pause = fin d'un geste d'arrachage ; pas l'attente devant la
		# fenêtre ouverte (plus rien à arracher).
		if f and not _was_frenzy.get(z.id, false) and had_planks:
			if not frenzy_starts.has(z.id):
				frenzy_starts[z.id] = []
			frenzy_starts[z.id].append(now)
		if f:
			frenzy_time[z.id] = frenzy_time.get(z.id, 0.0) + 1.0 / Engine.physics_ticks_per_second
		if z.anim_code() & Zombie.FRENZY_BIT:
			frenzy_bit_seen = true
		_was_frenzy[z.id] = f


func _reset_tear_log() -> void:
	rips.clear()
	_planks = w.planks()
	frenzy_starts.clear()
	frenzy_time.clear()
	_was_frenzy.clear()


func run() -> void:
	timeout_sec = 240
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 5.0, "menu principal")
	var dir := install_fixture(MAP, FIXTURE)
	at.check(dir != "", "carte SMALLEST copiée dans le dossier des cartes du test (%s)" % dir)
	if dir == "":
		return
	var p: Player = await H.start_solo_game(self, EditorMapDef.CUSTOM_PREFIX + MAP)
	if p == null:
		return
	game = Game.instance
	at.check(game.map_def.id == "perso:smallest", "partie sur la carte de l'éditeur (%s)" % game.map_def.id)
	at.check(game.barricades.windows.size() == 1 and game.spawner.points.size() == 1, "une fenêtre, un point d'apparition (%d, %d)" % [game.barricades.windows.size(), game.spawner.points.size()])
	if game.barricades.windows.size() != 1:
		return
	w = game.barricades.windows[0]
	game.combat.debug_invulnerable = true
	tree().physics_frame.connect(_sample)

	# 1. Collé à la fenêtre dès la manche 1.
	var glued := w.global_position + w.inward * 0.6 + Vector3(0, 0.05, 0)
	p.teleport_to(glued, atan2(w.inward.x, w.inward.z))
	var spawn_pt: Vector3 = game.spawner.points[0].pos
	at.check(Barricade._flat_dist(spawn_pt, glued) < Spawner.MIN_PLAYER_DIST, "point d'apparition à %.1f m du joueur (moins de %.0f m)" % [Barricade._flat_dist(spawn_pt, glued), Spawner.MIN_PLAYER_DIST])
	var spawned: Array[Zombie] = []
	var on_spawn := func(z: Zombie): spawned.append(z)
	game.zombies.zombie_spawned.connect(on_spawn)
	var ok: bool = await until(func(): return game.rounds.round_n == 1 and spawned.size() >= 1, 15.0, "un zombie apparaît, joueur collé à la fenêtre")
	at.check(ok, "manche 1 : un zombie apparaît alors que le joueur est collé à la seule fenêtre")
	if not ok:
		return
	var total := game.rounds.total
	ok = await until(func():
		for z in _attached():
			for i in Barricade.SLOT_OFFSETS.size():
				if Barricade._flat_dist(z.global_position, w.slot_point(i)) < 0.5:
					return true
		return false, 10.0, "un zombie à sa place devant la fenêtre")
	at.check(ok, "le zombie vient se poster devant la fenêtre")
	ok = await until(func(): return w.waiting_count() == BarricadeRules.WINDOW_QUEUE_MAX, 20.0, "3 zombies derrière la fenêtre")
	at.check(ok, "3 zombies attendent derrière la fenêtre")
	await seconds(8.0)  # file pleine : aucun 4e ne doit apparaître
	at.check(game.zombies.alive_count() == BarricadeRules.WINDOW_QUEUE_MAX and game.rounds.to_spawn == total - BarricadeRules.WINDOW_QUEUE_MAX,
		"file pleine : pas de 4e zombie, les autres restent à venir (%d en jeu, %d à venir sur %d)" % [game.zombies.alive_count(), game.rounds.to_spawn, total])
	var places := {}
	for z in _attached():
		for i in Barricade.SLOT_OFFSETS.size():
			if Barricade._flat_dist(z.global_position, w.slot_point(i)) < 0.5:
				places[i] = true
	at.check(places.size() == BarricadeRules.WINDOW_QUEUE_MAX, "chacun sa place (milieu, gauche, droite : %s)" % str(places.keys()))
	# Le joueur abat ceux de la fenêtre : les suivants arrivent, jusqu'au
	# dernier zombie de la manche.
	ok = await until(func():
		for z in _attached():
			if z.state == Zombie.State.BARRIER and z.anim_speed < 0.4:
				game.zombies.kill(z.id, false, -w.inward)
		return spawned.size() >= total, 90.0, "tous les zombies de la manche apparus")
	at.check(ok, "les %d zombies de la manche 1 arrivent par la fenêtre, une place libérée à la fois (%d)" % [total, spawned.size()])
	at.check(game.rounds.total == total and spawned.size() == total, "nombre de zombies de la manche inchangé (%d)" % game.rounds.total)
	at.check(max_waiting <= BarricadeRules.WINDOW_QUEUE_MAX and max_attached <= BarricadeRules.WINDOW_QUEUE_MAX, "jamais plus de 3 zombies derrière la fenêtre (max %d)" % max_waiting)
	game.zombies.zombie_spawned.disconnect(on_spawn)

	# 2. Cadence d'arrachage : un zombie seul.
	game.rounds.paused = true
	await H.clear_zombies(self)
	w.srv_set_mask(BarricadeRules.FULL_MASK)
	p.untargetable = true  # pas de coup à travers la fenêtre : il arrache tout
	p.teleport_to(w.global_position + w.inward * 3.0 + Vector3(0, 0.05, 0))
	await seconds(0.3)
	_reset_tear_log()
	var zid := game.zombies.spawn(spawn_pt, RoundRules.WALK, 100000)
	ok = await until(func(): return w.planks() == 0, 25.0, "6 planches arrachées par un zombie seul")
	await frames(3)  # relevé du dernier pas de physique (_sample)
	at.check(ok and rips.size() == 6, "un zombie seul arrache les 6 planches (%d)" % rips.size())
	if rips.size() == 6:
		var lo := INF
		var hi := 0.0
		for i in range(1, 6):
			lo = minf(lo, rips[i] - rips[i - 1])
			hi = maxf(hi, rips[i] - rips[i - 1])
		var mean := (rips[5] - rips[0]) / 5.0
		print("[smallest] planches à %s s" % str(rips.map(func(r): return snappedf(r - rips[0], 0.01))))
		at.check(absf(mean - BarricadeRules.TEAR_TIME) < 0.2, "une planche toutes les %.2f s en moyenne (attendu 2,5 s)" % mean)
		at.check(lo > 2.1 and hi < 2.9, "entre %.2f et %.2f s par planche" % [lo, hi])
		var pauses: Array = frenzy_starts.get(zid, [])
		at.check(pauses.size() >= 5, "pause de folie après chaque planche (%d)" % pauses.size())
		var ft: float = frenzy_time.get(zid, 0.0)
		at.check(ft >= 5 * BarricadeRules.TEAR_PAUSE_MIN - 0.1, "%.1f s de pause de folie entre les planches" % ft)
	at.check(frenzy_bit_seen, "pause de folie dans le code d'animation (vue par les clients)")
	await until(func(): return game.zombies.get_zombie(zid) == null or game.zombies.get_zombie(zid).state != Zombie.State.BARRIER, 5.0, "enjambement")
	await H.clear_zombies(self)

	# 3. Trois zombies : chacun sa place, chacun son rythme.
	w.srv_set_mask(BarricadeRules.FULL_MASK)
	await seconds(0.2)
	_reset_tear_log()
	var trio: Array[int] = []
	for cls in [RoundRules.WALK, RoundRules.RUN, RoundRules.SPRINT]:
		trio.append(game.zombies.spawn(spawn_pt, cls, 100000))
		await seconds(1.0)  # chacun quitte le point d'apparition
	var t3 := GameClock.now()
	ok = await until(func(): return w.planks() == 0, 20.0, "6 planches arrachées par trois zombies")
	var dur := GameClock.now() - t3
	await frames(3)  # relevé du dernier pas de physique (_sample)
	at.check(ok and dur < 9.0, "à trois, la fenêtre tombe plus vite (%.1f s)" % dur)
	var tore := 0
	var pace_ok := true
	for id in trio:
		var starts: Array = frenzy_starts.get(id, [])
		if not starts.is_empty():
			tore += 1
		for i in range(1, starts.size()):
			var gap: float = starts[i] - starts[i - 1]
			pace_ok = pace_ok and gap > 2.1 and gap < 2.9
	at.check(tore == 3, "chacun des trois zombies arrache des planches (%d/3)" % tore)
	at.check(pace_ok, "chacun à 2,5 s environ par planche, coureurs compris")
	at.check(max_attached <= BarricadeRules.WINDOW_QUEUE_MAX, "toujours 3 au plus derrière la fenêtre")
	await H.clear_zombies(self)
	tree().physics_frame.disconnect(_sample)
	p.untargetable = false
	game.rounds.paused = false
	Router.back_to_menu()
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 10.0, "retour au menu")
	remove_dir(EditorMap.maps_root())
