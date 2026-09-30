extends AutotestScenario
## Vue FPS des armes (comme BO1) :
## 1. champ de vision propre à l'arme : rapport des champs appliqué, points
##    apparents (bouche du canon) projetés exactement comme le shader les dessine ;
## 2. mains et avant-bras présents pour chaque arme ;
## 3. rechargement animé selon le mécanisme : le chargeur sort puis revient,
##    la main gauche va le chercher, les canons basculent (Olympia), le
##    barillet sort (Python), la pompe recule (Stakeout) ; tout revient au repos ;
## 4. culasse du pistolet qui recule au tir, pompe au réarmement ;
## 5. captures : hanche, rechargement (3 instants), sprint, changement d'arme.
## Variable d'environnement WV_ONLY (liste d'ids séparés par des virgules) :
## ne passe en revue que ces armes (mise au point).

var H := AutotestHelpers
var game: Game
var p: Player
var pd: PlayerData


func equip(id: String, pap := false) -> bool:
	pd.weapons = [WeaponDB.new_instance(WeaponDB.STARTING_WEAPON), WeaponDB.new_instance(id, pap)]
	pd.slot = 1
	game.combat.cancel_reload(1)
	p.pitch = 0.0
	game.session.sync_inventory(1)
	var ok: bool = await until(func(): return p.weapons.current().get("id", "") == id and p.weapons.current().get("pap", false) == pap, 2.0, "arme %s en main" % id)
	await seconds(WeaponController.SWITCH_TIME + 0.25)
	return ok


func pull_trigger() -> void:
	var before: int = p.weapons.current().get("mag", 0)
	p.input.fire = true
	var t := 0.0
	while p.weapons.current().get("mag", 0) == before and t < 0.5:
		await tree().physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
	p.input.fire = false


## Écart (m) d'un groupe mobile par rapport à son repos (position + rotation).
func group_offset(v: ViewModel, g: String) -> float:
	if not v._groups.has(g):
		return 0.0
	var n: Node3D = v._groups[g]
	return n.position.distance_to(v._group_rest[g]) + n.rotation.length() * 0.05


func left_offset(v: ViewModel) -> float:
	return v.hands.left_pose.origin.length()


func run() -> void:
	timeout_sec = 290
	p = await H.start_solo_game(self)
	if p == null:
		return
	game = Game.instance
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	await H.clear_zombies(self)
	pd = game.session.local_data()
	p.teleport_to(MapData.cell_to_world(Vector2i(5, 7), 0.05), PI * 0.5)
	p.pitch = 0.0
	await seconds(0.3)
	var v := p.weapons.view

	# 1. Champ de vision de l'arme.
	var want_k := tan(deg_to_rad(p.camera.fov) * 0.5) / tan(deg_to_rad(v.view_fov()) * 0.5)
	at.check(absf(ViewModel.fov_k - want_k) < 0.01,
		"champ de vision de l'arme %.1f° (rapport %.2f)" % [ViewModel.VIEW_FOV, ViewModel.fov_k])
	# Projection « shader » de la bouche (champ de l'arme) = projection caméra du point apparent.
	var local: Vector3 = v.model.transform * WeaponModels.anchor(v.model_id, "muzzle")
	var vp := p.get_viewport().get_visible_rect().size
	var th := tan(deg_to_rad(v.view_fov()) * 0.5)
	var ndc := Vector2(local.x / (-local.z * th * vp.x / vp.y), local.y / (-local.z * th))
	var want_px := Vector2((ndc.x * 0.5 + 0.5) * vp.x, (0.5 - ndc.y * 0.5) * vp.y)
	var got_px := p.camera.unproject_position(v.muzzle_global())
	at.check(got_px.distance_to(want_px) < 1.0, "bouche du canon apparente à %.2f px de son dessin" % got_px.distance_to(want_px))

	var only := OS.get_environment("WV_ONLY")
	var ids: Array = WeaponDB.WEAPONS.keys() if only == "" else Array(only.split(","))
	var wi := -1
	for id in ids:
		wi += 1
		if not mine(wi):
			continue
		var s := WeaponDB.stats(id)
		if not await equip(id):
			continue
		v = p.weapons.view
		var hand_meshes := 0
		for c in v.hands.get_children():
			hand_meshes += c.get_child_count()
		at.check(hand_meshes >= 4, "%s : mains et avant-bras (%d maillages)" % [id, hand_meshes])
		await at.screenshot("hip_" + id)
		# Culasse du pistolet au tir.
		var slide_peak := 0.0
		await pull_trigger()
		var t0 := GameClock.msec()
		while GameClock.msec() - t0 < 100:
			slide_peak = maxf(slide_peak, group_offset(v, "slide"))
			await tree().process_frame
		if s.get("class", "") == "pistol":
			at.check(slide_peak > 0.01, "%s : la glissière recule au tir (%.3f m)" % [id, slide_peak])
		if s.get("cycle", "") == "pump":
			var pump_peak := 0.0
			var t1 := GameClock.msec()
			while GameClock.msec() - t1 < WeaponDB.fire_interval(id) * 1000.0:
				pump_peak = maxf(pump_peak, group_offset(v, "pump"))
				await tree().process_frame
			at.check(pump_peak > 0.04, "%s : coup de pompe après le tir (%.3f m)" % [id, pump_peak])
		await seconds(WeaponDB.fire_interval(id) + 0.1)
		# Rechargement : captures à 3 instants, pièces mobiles et main gauche.
		if p.weapons.current().mag >= int(s.mag):
			continue
		p.input.reload = true
		await tree().physics_frame
		await tree().physics_frame
		p.input.reload = false
		var rt := game.combat.reload_time(1, pd.current_weapon())
		var kind := String(s.get("reload_kind", "mag"))
		var peak := {"mag": 0.0, "barrels": 0.0, "cyl": 0.0, "hand": 0.0}
		var shots := [0.3, 0.5, 0.8]
		var start := GameClock.msec()
		var si := 0
		while (GameClock.msec() - start) / 1000.0 < rt + 0.1:
			var el := (GameClock.msec() - start) / 1000.0 / rt
			for g in ["mag", "barrels", "cyl"]:
				peak[g] = maxf(peak[g], group_offset(v, g))
			peak.hand = maxf(peak.hand, left_offset(v))
			if si < shots.size() and el >= shots[si]:
				await at.screenshot("reload_%s_%d" % [id, si])
				si += 1
			await tree().process_frame
		match kind:
			"break":
				at.check(peak.barrels > 0.01, "%s : canons basculés au rechargement" % id)
			"cylinder":
				at.check(peak.cyl > 0.01, "%s : barillet basculé au rechargement" % id)
			"mag", "belt", "bolt":
				if v._groups.has("mag"):
					at.check(peak.mag > 0.1, "%s : chargeur retiré puis remis (%.2f m)" % [id, peak.mag])
		if kind != "rocket":
			at.check(peak.hand > 0.05, "%s : la main gauche quitte le garde-main (%.2f m)" % [id, peak.hand])
		# Fin du rechargement (la machine peut être chargée), puis un temps de pose.
		await until(func(): return not v.is_busy() and not p.weapons.is_reloading(), 3.0, "%s : rechargement terminé" % id)
		await seconds(0.3)
		var rest := group_offset(v, "mag") + group_offset(v, "barrels") + group_offset(v, "cyl") + left_offset(v)
		at.check(rest < 0.005, "%s : pièces revenues au repos après le rechargement (%.3f)" % [id, rest])

	# 5. Sprint et changement d'arme.
	if not owns(parts() - 1):
		return
	for id in ["m1911", "ak74u", "m14"]:
		await equip(id)
		# Vers +X : grand espace libre.
		p.teleport_to(MapData.cell_to_world(Vector2i(2, 3), 0.05), -PI * 0.5)
		await seconds(0.2)
		p.input.move = Vector2(0, 1)
		p.input.sprint = true
		await seconds(0.7)
		await at.screenshot("sprint_" + id)
		p.input.move = Vector2.ZERO
		p.input.sprint = false
		p.teleport_to(MapData.cell_to_world(Vector2i(5, 7), 0.05), PI * 0.5)
		await seconds(0.4)
	pd.weapons = [WeaponDB.new_instance("m1911"), WeaponDB.new_instance("mp40")]
	pd.slot = 1
	game.session.sync_inventory(1)
	await seconds(WeaponController.SWITCH_TIME + 0.3)
	p.input.switch_weapon = true
	await seconds(WeaponController.SWITCH_TIME * 0.3)
	p.input.switch_weapon = false
	await at.screenshot("switch_away")
	await seconds(WeaponController.SWITCH_TIME * 0.4)
	await at.screenshot("switch_draw")
	await seconds(0.5)
	at.check(p.weapons.current().id == "m1911", "changement d'arme vers le M1911")
