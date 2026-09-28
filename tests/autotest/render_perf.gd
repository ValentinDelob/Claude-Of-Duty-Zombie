extends AutotestScenario
## @rendu : a besoin du rendu (lancé avec fenêtre hors écran par check.sh).
## Optimisations de rendu (perf: optimize rendering after the visual rework) :
##  - préréglage automatique (QualityProbe) : mini-banc d'essai dans le menu,
##    résultat appliqué et enregistré (fichier de réglages des tests) ;
##  - ombres portées limitées aux zombies les plus proches (ZombieShadows),
##    selon le préréglage ;
##  - vignette de blessure du HUD masquée quand le joueur est en pleine santé ;
##  - corps qui se dissolvent sur leur propre shader (zombie_dissolve), les
##    vivants sur zombie.gdshader sans `discard`.

var H := AutotestHelpers


func run() -> void:
	timeout_sec = 150
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 5.0, "menu")
	await _probe()
	var p: Player = await H.start_solo_game(self, "bunker_k7")
	if p == null:
		return
	var game := Game.instance
	game.combat.debug_invulnerable = true
	game.rounds.paused = true
	await H.clear_zombies(self)

	# Vignette de blessure : rien à l'écran en pleine santé.
	await frames(3)
	at.check(not game.hud._vignette.visible, "vignette de blessure masquée en pleine santé")
	game.combat.debug_invulnerable = false
	game.combat.damage_player(1, 60, p.global_position + Vector3(2, 1, 0))
	game.combat.debug_invulnerable = true
	await frames(3)
	at.check(game.hud._vignette.visible, "vignette de blessure affichée après un coup")

	# 16 zombies immobiles devant le joueur, de 2 à 17 m.
	p.teleport_to(MapData.cell_to_world(Vector2i(35, 31), 0.05))
	H.aim_at(p, MapData.cell_to_world(Vector2i(52, 18), 1.2))
	var ids := []
	for i in 16:
		var pos := p.global_position + (MapData.cell_to_world(Vector2i(52, 18)) - p.global_position).normalized() * (2.0 + i) + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
		var zid: int = game.zombies.spawn(Vector3(pos.x, 0.0, pos.z), 0, 1000000)
		game.zombies.get_zombie(zid).speed_mult = 0.0
		ids.append(zid)
	await seconds(Zombie.EMERGE_TIME + 0.5)
	for q in [Settings.Quality.MEDIUM, Settings.Quality.LOW, Settings.Quality.HIGH, Settings.Quality.MEDIUM]:
		Settings.quality = q
		Settings.changed.emit()
		await frames(ZombieShadows.UPDATE_FRAMES * 2 + 2)
		var preset := RenderQuality.preset(q)
		var n := ZombieShadows.casting(game.zombies.alive)
		var near := 0
		for z: Zombie in game.zombies.alive:
			if z.global_position.distance_to(p.camera.global_position) < float(preset.zombie_shadow_dist) - ZombieShadows.HYSTERESIS:
				near += 1
		at.check(n <= int(preset.zombie_shadows) and n >= mini(near, int(preset.zombie_shadows)),
				"%s : %d zombies sur 16 projettent une ombre (budget %d, %d proches)" % [preset.name, n, preset.zombie_shadows, near])
		# Ce sont les plus proches.
		var far_casting := false
		for z: Zombie in game.zombies.alive:
			if z.mesh.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and z.global_position.distance_to(p.camera.global_position) > float(preset.zombie_shadow_dist) + 0.1:
				far_casting = true
		at.check(not far_casting, "%s : aucune ombre de zombie au-delà de %.0f m" % [preset.name, preset.zombie_shadow_dist])
		await at.screenshot("ombres_" + preset.name)

	# Dissolution : shader dédié pour le corps, les vivants restent sur le shader normal.
	var victim: Zombie = game.zombies.get_zombie(ids[1])
	at.check(victim.mesh.material_override == ZombieModel.material(), "zombie vivant : zombie.gdshader (sans discard)")
	game.zombies.kill(ids[1], false, Vector3.FORWARD)
	await seconds(Zombie.DISSOLVE_DELAY + Zombie.DISSOLVE_TIME * 0.4)
	at.check(victim.mesh.material_override == ZombieModel.dissolve_material(), "corps qui se dissout : zombie_dissolve.gdshader")
	at.check(game.zombies.get_zombie(ids[2]).mesh.material_override == ZombieModel.material(), "les autres zombies gardent le shader normal")
	await at.screenshot("dissolution")


## Mini-banc d'essai du premier lancement, dans le menu.
func _probe() -> void:
	var before := Settings.quality
	var probe: QualityProbe = Settings.start_quality_probe()
	var res: Array = await probe.done
	await frames(2)
	var q: int = res[0]
	at.check(q >= Settings.Quality.LOW and q <= Settings.Quality.HIGH, "préréglage automatique : %s (%s)" % [RenderQuality.preset(q).name, res[1]])
	at.check(Settings.quality == q and Settings.quality_auto == res[1], "préréglage appliqué et mémorisé")
	var cfg := ConfigFile.new()
	at.check(cfg.load(Settings.TEST_PATH) == OK and cfg.get_value("video", "quality_auto", "") == res[1], "détection enregistrée (réglages des tests)")
	# Sur la GTX 1070 de développement, le banc doit reconnaître une carte
	# de classe HIGH (même en présence d'autres jeux, il reste au moins MEDIUM).
	if RenderingServer.get_video_adapter_name().to_lower().contains("gtx 1070"):
		at.check(q >= Settings.Quality.MEDIUM, "GTX 1070 : au moins MEDIUM")
	Settings.quality = before
	Settings.changed.emit()
