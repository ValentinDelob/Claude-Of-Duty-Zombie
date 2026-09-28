extends AutotestScenario
## @parts 3 : check.sh lance 3 parties en parallèle (armes réparties).
## Tir droit, arme par arme :
## 1. en visée, le cran (ou l'œilleton) ET le guidon projetés à l'écran sont
##    au centre à ±2 px (armes à lunette : écran de lunette affiché, zoom) ;
## 2. tir en visée sur une plaque à 20 m : impact à ±3 cm du point visé
##    (fusils à pompe : plombs dans le cône de visée) ;
## 3. à la hanche : chaque impact reste dans le cône dessiné par le réticule,
##    et le réticule du HUD a l'écart de la dispersion réelle ;
## 4. traçantes : partent de la bouche du modèle et finissent au point touché.

var H := AutotestHelpers
var game: Game
var p: Player
var pd: PlayerData
var plate_x := 0.0
var _shot: Array = []
var _shot_dir := Vector3.ZERO


func equip(id: String, pap := false) -> bool:
	pd.weapons = [WeaponDB.new_instance(WeaponDB.STARTING_WEAPON), WeaponDB.new_instance(id, pap)]
	pd.slot = 1
	game.combat.cancel_reload(1)
	game.session.sync_inventory(1)
	var ok: bool = await until(func(): return p.weapons.current().get("id", "") == id and p.weapons.current().get("pap", false) == pap, 2.0, "arme %s en main" % id)
	await seconds(WeaponController.SWITCH_TIME + 0.25)
	return ok


## Appui bref sur la détente jusqu'au premier coup prédit.
func pull_trigger() -> void:
	var before: int = p.weapons.current().get("mag", 0)
	_shot = []
	p.input.fire = true
	var t := 0.0
	while p.weapons.current().get("mag", 0) == before and t < 0.6:
		await tree().physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
	p.input.fire = false


func _on_fired() -> void:
	# Premier coup seulement (rafales : les suivants ont du recul).
	if _shot.is_empty():
		_shot = p.weapons.last_impacts.duplicate(true)
		_shot_dir = p.aim_direction()


func center_px() -> Vector2:
	return p.get_viewport().get_visible_rect().size * 0.5


func screen_of(local: Vector3) -> Vector2:
	var v := p.weapons.view
	return p.camera.unproject_position(v.model.to_global(local))


## Plaque de tir (collision de décor, couche 1) face au joueur à `dist` m.
func build_plate(eye: Vector3, dist: float) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.1, 3.0, 3.0)
	cs.shape = box
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = box.size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.75, 0.72, 0.62)
	mi.material_override = m
	body.add_child(mi)
	# Cible peinte : croix au centre.
	for sz in [Vector3(0.12, 0.02, 0.6), Vector3(0.12, 0.6, 0.02)]:
		var c := MeshInstance3D.new()
		var cb := BoxMesh.new()
		cb.size = sz
		c.mesh = cb
		var cm := StandardMaterial3D.new()
		cm.albedo_color = Color(0.6, 0.05, 0.03)
		c.material_override = cm
		body.add_child(c)
	game.world.add_child(body)
	plate_x = eye.x + dist
	body.global_position = Vector3(plate_x + 0.05, eye.y, eye.z)


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
	p.weapons.fired.connect(_on_fired)
	# Allée dégagée de ~22 m vers +X (rangée 3 de l'arène).
	p.teleport_to(MapData.cell_to_world(Vector2i(2, 3), 0.05), -PI * 0.5)
	p.pitch = 0.0
	await seconds(0.4)
	var eye := p.camera.global_position
	build_plate(eye, 20.0)
	await seconds(0.2)

	# 1 + 2. Visée et tir précis, arme par arme.
	var worst_px := 0.0
	var wi := -1
	for id in WeaponDB.WEAPONS:
		wi += 1
		if not mine(wi):
			continue
		var s := WeaponDB.stats(id)
		if not await equip(id):
			continue
		# Point visé : un peu décalé du centre de la plaque (varie selon l'arme).
		var k := WeaponDB.WEAPONS.keys().find(id)
		var target := Vector3(plate_x, eye.y + 0.3 * sin(k * 1.7), eye.z + 0.4 * cos(k * 2.3))
		H.aim_at(p, target)
		p.input.aim = true
		p.input.sprint = true  # lunette : respiration retenue
		await seconds(float(s.ads_time) + 0.55)
		H.aim_at(p, target)
		await seconds(0.12)
		var scope := WeaponDB.scope_kind(s)
		if scope == "":
			var c := center_px()
			var rear := screen_of(WeaponModels.anchor(s.model, "sight"))
			var front := screen_of(WeaponModels.anchor(s.model, "front"))
			var err := maxf(rear.distance_to(c), front.distance_to(c))
			worst_px = maxf(worst_px, err)
			at.check(err <= 2.0, "%s : ligne de mire au centre (cran %.2f px, guidon %.2f px)" % [id, rear.distance_to(c), front.distance_to(c)])
		else:
			var want_fov: float = s.get("scope_fov", Settings.fov * float(s.ads_zoom))
			at.check(p.weapons.scoped and not p.weapons.view.model.visible and game.hud.scope.visible,
				"%s : écran de lunette (%s) affiché, arme masquée" % [id, scope])
			at.check(absf(p.camera.fov - want_fov) < 0.6, "%s : zoom de la lunette %.1f° (attendu %.1f°)" % [id, p.camera.fov, want_fov])
		await at.screenshot("ads_" + id)
		if s.has("blast_range"):
			p.input.aim = false
			p.input.sprint = false
			continue
		var want_dir := (target - p.camera.global_position).normalized()
		var aim_err := rad_to_deg(p.aim_direction().angle_to(want_dir))
		await pull_trigger()
		await seconds(0.05)
		if _shot.is_empty():
			at.fail("%s : aucun tir" % id)
		elif int(s.pellets) > 1:
			var inside := 0
			for e in _shot:
				var a := rad_to_deg(want_dir.angle_to((e[0] - p.camera.global_position).normalized()))
				if a <= float(s.spread_ads) + 0.3:
					inside += 1
			at.check(inside == _shot.size(), "%s : %d/%d plombs dans le cône de visée (%.1f°)" % [id, inside, _shot.size(), s.spread_ads])
		else:
			var hit: Vector3 = _shot[0][0]
			var miss := hit.distance_to(target)
			at.check(miss <= 0.03, "%s : impact à %.1f cm du point visé à 20 m (visée %.3f°)" % [id, miss * 100.0, aim_err])
		p.input.aim = false
		p.input.sprint = false
		await seconds(0.3)

	print("[weapon_aim] pire écart de la ligne de mire (partie %d) : %.2f px" % [part(), worst_px])
	if not owns(parts() - 1):
		return

	# 3. Hanche : impacts dans le cône du réticule, réticule = dispersion.
	for id in ["m1911", "mp40", "ak74u", "hk21", "stakeout"]:
		var s := WeaponDB.stats(id)
		await equip(id)
		var out := 0
		var n := 0
		for i in 6:
			var target := Vector3(plate_x, eye.y, eye.z)
			H.aim_at(p, target)
			p.weapons.feel.reset()
			await seconds(0.15 if i > 0 else 0.4)
			var spread := p.weapons.spread_deg()
			var px := WeaponDB.spread_to_px(spread, p.camera.fov, game.hud._crosshair.size.y)
			if i == 0:
				at.check(absf(game.hud._crosshair.spread - maxf(px, 3.0)) < 1.5, "%s : réticule à %.1f px pour %.2f° de dispersion (%.1f px attendus)" % [id, game.hud._crosshair.spread, spread, px])
			await pull_trigger()
			await seconds(0.04)
			for e in _shot:
				n += 1
				var a := rad_to_deg(_shot_dir.angle_to((e[0] - p.camera.global_position).normalized()))
				if a > p.weapons.last_spread_deg + 0.05:
					out += 1
			if i == 2:
				await at.screenshot("hip_" + id)
			await seconds(WeaponDB.fire_interval(id) + 0.05)
		at.check(out == 0 and n > 0, "%s : %d/%d impacts à la hanche hors du cône du réticule" % [id, out, n])

	# Le réticule s'ouvre en mouvement et après un tir, puis se referme.
	await equip("mp40")
	H.aim_at(p, Vector3(plate_x, eye.y, eye.z))
	p.weapons.feel.reset()
	await seconds(0.5)
	var still := p.weapons.spread_deg()
	p.input.move = Vector2(0, 1)
	await seconds(0.6)
	var moving := p.weapons.spread_deg()
	p.input.move = Vector2.ZERO
	await seconds(0.8)
	p.input.fire = true
	await seconds(0.35)
	var firing := p.weapons.spread_deg()
	await at.screenshot("hip_bloom")
	p.input.fire = false
	await seconds(0.7)
	var settled := p.weapons.spread_deg()
	at.check(moving > still * 1.3, "réticule ouvert en marchant (%.2f° -> %.2f°)" % [still, moving])
	at.check(firing > still * 1.1 and settled < firing, "réticule ouvert par le tir puis refermé (%.2f° -> %.2f° -> %.2f°)" % [still, firing, settled])

	# 4. Traçante : de la bouche du modèle au point touché.
	await equip("m14")
	p.teleport_to(MapData.cell_to_world(Vector2i(2, 3), 0.05), -PI * 0.5)
	await seconds(0.3)
	H.aim_at(p, Vector3(plate_x, eye.y, eye.z))
	await seconds(0.3)
	var muzzle := p.weapons.view.muzzle_global()
	var fx := game.fx_root
	var ti := fx._tracer_i
	# Ralenti pour la capture : la traînée est visible en vol.
	Engine.time_scale = 0.06
	await pull_trigger()
	var hit_pt: Vector3 = _shot[0][0] if not _shot.is_empty() else Vector3.ZERO
	at.check(fx._tr_from[ti].distance_to(muzzle) < 0.05, "traçante partie de la bouche du canon (%.3f m)" % fx._tr_from[ti].distance_to(muzzle))
	var tr_end: Vector3 = fx._tr_from[ti] + fx._tr_dir[ti] * fx._tr_len[ti]
	at.check(tr_end.distance_to(hit_pt) < 0.01, "traçante qui finit au point touché (%.3f m)" % tr_end.distance_to(hit_pt))
	at.check(fx._tracers[ti].visible, "traçante visible dès l'image du tir")
	await at.screenshot("tracer_m14")
	await seconds(0.004)
	await at.screenshot("tracer_m14_b")
	Engine.time_scale = 1.0
	await seconds(0.5)

	# 5. Recul : le canon monte progressivement (pas de saut à l'image du
	#    tir), puis redescend en partie tout seul.
	for id in ["m1911", "m14", "l96a1"]:
		await equip(id)
		H.aim_at(p, Vector3(plate_x, eye.y, eye.z))
		p.input.aim = true
		await seconds(0.6)
		var p0 := p.pitch
		var at_shot := [0.0]
		var grab := func(): at_shot[0] = p.pitch - p0
		p.weapons.fired.connect(grab)
		await pull_trigger()
		p.weapons.fired.disconnect(grab)
		var kick := deg_to_rad(p.weapons.feel.last_kick_deg)
		var s := WeaponDB.stats(id)
		await seconds(0.1)
		var climbed := p.pitch - p0
		await seconds(0.9)
		var rest := p.pitch - p0
		var want_rest := kick * (1.0 - float(s.recoil_recover))
		at.check(absf(at_shot[0]) < kick * 0.05 and climbed > kick * 0.75 and absf(rest - want_rest) < kick * 0.15,
			"%s : montée progressive %.2f° -> %.2f° en 0,1 s -> %.2f° (reste attendu %.2f°)" % [id, rad_to_deg(at_shot[0]), rad_to_deg(climbed), rad_to_deg(rest), rad_to_deg(want_rest)])
		p.input.aim = false
		await seconds(0.3)
	print("[weapon_aim] pire écart de la ligne de mire : %.2f px" % worst_px)
