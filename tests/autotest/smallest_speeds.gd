extends AutotestScenario
## @couvre scripts/game/rounds/* tests/fixtures/maps/smallest/*
## Carte SMALLEST du joueur (une salle, une fenêtre), vraies manches : que des
## marcheurs aux manches 1 à 3, des coureurs à partir de la manche 4 (règle
## demandée par le joueur). Les zombies apparus sont abattus aussitôt pour
## que la fenêtre (3 places) en laisse venir d'autres.

const Win := preload("res://tests/autotest/smallest_window.gd")
const SAMPLES := 6

var H := AutotestHelpers


func run() -> void:
	timeout_sec = 240
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 5.0, "menu principal")
	var dir := Win.install_fixture(Win.MAP, Win.FIXTURE)
	at.check(dir != "", "carte SMALLEST copiée dans le dossier des cartes du test")
	if dir == "":
		return
	var p: Player = await H.start_solo_game(self, EditorMapDef.CUSTOM_PREFIX + Win.MAP)
	if p == null:
		return
	var game := Game.instance
	game.combat.debug_invulnerable = true
	var speeds: Array[int] = []
	var on_spawn := func(z: Zombie): speeds.append(z.speed_class)
	game.zombies.zombie_spawned.connect(on_spawn)
	var by_round := {}
	for r in [1, 2, 3, 4, 6]:
		game.rounds.debug_jump_to(r)
		speeds.clear()
		var ok: bool = await until(func():
			for z: Zombie in game.zombies.alive.duplicate():
				game.zombies.kill(z.id, false, Vector3.FORWARD)
			return speeds.size() >= SAMPLES, 60.0, "%d zombies apparus en manche %d" % [SAMPLES, r])
		if not ok:
			return
		by_round[r] = speeds.duplicate()
		var runners := speeds.filter(func(s): return s != RoundRules.WALK).size()
		print("[smallest] manche %d : vitesses %s" % [r, str(speeds)])
		if r < RoundRules.RUNNERS_FROM_ROUND:
			at.check(runners == 0, "manche %d : que des marcheurs (%d coureur(s) sur %d)" % [r, runners, speeds.size()])
	var late: Array = by_round[4] + by_round[6]
	var late_runners := late.filter(func(s): return s != RoundRules.WALK).size()
	at.check(late_runners > 0, "à partir de la manche 4 : des coureurs (%d sur %d)" % [late_runners, late.size()])
	at.check(by_round[6].filter(func(s): return s == RoundRules.WALK).is_empty(), "manche 6 : plus aucun marcheur (tirage de BO1)")
	game.zombies.zombie_spawned.disconnect(on_spawn)
	await H.clear_zombies(self)
	Router.back_to_menu()
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 10.0, "retour au menu")
	Win.remove_dir(EditorMap.maps_root())
