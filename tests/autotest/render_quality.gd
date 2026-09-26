extends AutotestScenario
## Préréglages de qualité (RenderQuality) : changement à chaud via
## Settings.changed (comme l'écran OPTIONS), effets réels sur les lampes,
## l'environnement et le viewport, perf et captures par préréglage (salle de
## garde avec des zombies qui bougent : les ombres sont redessinées).

var H := AutotestHelpers


func run() -> void:
	timeout_sec = 120
	var p: Player = await H.start_solo_game(self, "bunker_k7")
	if p == null:
		return
	var game := Game.instance
	game.combat.debug_invulnerable = true
	game.rounds.paused = true
	await H.clear_zombies(self)
	var env: Environment = (game.world.get_node("WorldEnvironment") as WorldEnvironment).environment
	var lamps := tree().get_nodes_in_group(RenderQuality.LAMP_GROUP)
	at.check(lamps.size() == 24, "24 lampes gérées par RenderQuality (%d)" % lamps.size())
	# Quelques zombies au fond de la salle de garde : sur place mais animés
	# (squelettes en mouvement : les ombres des lampes proches sont
	# redessinées), à la même distance pour chaque préréglage.
	for i in 8:
		var zid: int = game.zombies.spawn(MapData.cell_to_world(Vector2i(4 + i, 19), 0.0), i % 4, 150)
		game.zombies.get_zombie(zid).speed_mult = 0.0
	p.teleport_to(MapData.cell_to_world(Vector2i(9, 29), 0.05))
	H.aim_at(p, MapData.cell_to_world(Vector2i(9, 17), 1.2))
	await seconds(Zombie.EMERGE_TIME + 0.3)
	var initial := Settings.quality
	var fps := {}
	for q in [Settings.Quality.LOW, Settings.Quality.HIGH, Settings.Quality.MEDIUM]:
		var preset := RenderQuality.preset(q)
		Settings.quality = q
		Settings.changed.emit()
		await seconds(0.4)
		var shadows := 0
		for l: OmniLight3D in lamps:
			if l.shadow_enabled:
				shadows += 1
		at.check(shadows == [0, 8, 16][q], "%s : %d lampes à ombre" % [preset.name, shadows])
		at.check(env.glow_enabled == preset.glow, "%s : glow %s" % [preset.name, env.glow_enabled])
		at.check(env.ssao_enabled == preset.ssao, "%s : SSAO %s" % [preset.name, env.ssao_enabled])
		at.check(is_equal_approx(at.get_viewport().scaling_3d_scale, preset.scale_3d), "%s : résolution 3D %.2f" % [preset.name, at.get_viewport().scaling_3d_scale])
		at.check(is_equal_approx(ParticlePool.density, preset.particles), "%s : densité de particules" % preset.name)
		at.begin_perf()
		await seconds(1.0)
		fps[q] = at.end_perf("garde " + preset.name)
		await at.screenshot(preset.name)
	at.check_perf(fps[Settings.Quality.LOW], 150.0, "garde LOW")
	at.check_perf(fps[Settings.Quality.MEDIUM], 150.0, "garde MEDIUM")
	Settings.quality = initial
	Settings.changed.emit()
