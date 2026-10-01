extends AutotestScenario
## @carte kino
## @couvre tools/blender/kino/make_layout.py
## KINO : chaque zombie qui sort des gravats de la salle (apparitions de la
## zone t) rejoint le joueur sur le poste central, en marchant et en courant.
## Trouvé par le soak : l'apparition (86.18, 0, 56.0) était dans le bord bas du
## grand tas (pavé barrière de 0,2 m flottant au-dessus de la pente) ; le
## zombie, pris dedans, restait coincé entre le tas et le rang de fauteuils.

var H := AutotestHelpers


func run() -> void:
	timeout_sec = 480
	var p: Player = await H.start_solo_game(self, "kino")
	if p == null:
		return
	var game := Game.instance
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	for id in game.doors:
		game.doors[id].srv_open()
	await H.clear_zombies(self)
	p.teleport_to(Vector3(76.245, -0.1, 70.896))
	await seconds(0.5)
	var layout := game.layout as MeshMapLayout
	# Apparitions derrière une fenêtre : passent par la fenêtre (barricades).
	var behind_window := {}
	for w: Dictionary in layout.data.markers.windows:
		for s: Array in w.spawns:
			behind_window[MeshMapLayout.vec(s)] = true
	for zs: Dictionary in layout.data.markers.zombie_spawns:
		if zs.zone != "t" or behind_window.has(MeshMapLayout.vec(zs.p)):
			continue
		var start := MeshMapLayout.vec(zs.p)
		for sp: int in [RoundRules.WALK, RoundRules.SPRINT]:
			var z := game.zombies.get_zombie(game.zombies.spawn(start, sp, 100000))
			await H.emerged(self, [z])
			var t0 := GameClock.now()
			var ok: bool = await until(func(): return z.global_position.distance_to(p.global_position) < 2.5, 45.0, "zombie des gravats %s (vitesse %d) jusqu'au poste central" % [start, sp])
			if ok:
				at.check(true, "zombie des gravats %s (vitesse %d) au poste central en %.1f s" % [start, sp, GameClock.now() - t0])
			await H.clear_zombies(self)
