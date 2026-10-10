extends AutotestScenario
## Arsenal BO1 : chaque arme est équipée, vue à la première personne (capture),
## tirée (validation serveur, rafale de 3 pour M16/G11) et rechargée. Puis les
## mécaniques spéciales : projectiles explosifs (China Lake, LAW, M1911
## amélioré) avec dégâts de zone et dégâts à soi réduits, balles incendiaires,
## vitesse de déplacement selon l'arme.

var H := AutotestHelpers
var game: Game
var p: Player
var pd: PlayerData
var validated := [0]


func equip(id: String, pap := false) -> bool:
	pd.weapons = [WeaponDB.new_instance(WeaponDB.STARTING_WEAPON), WeaponDB.new_instance(id, pap)]
	pd.slot = 1
	game.combat.cancel_reload(1)
	p.pitch = 0.0
	game.session.sync_inventory(1)
	var ok: bool = await until(func(): return p.weapons.current().get("id", "") == id and p.weapons.current().get("pap", false) == pap, 2.0, "arme %s en main" % id)
	await seconds(WeaponController.SWITCH_TIME + 0.25)
	return ok


## Appui bref sur la détente : maintenu jusqu'au premier coup prédit (robuste
## aux images lentes quand la machine est chargée), puis relâché.
func pull_trigger() -> void:
	var before: int = p.weapons.current().get("mag", 0)
	p.input.fire = true
	var t := 0.0
	while p.weapons.current().get("mag", 0) == before and t < 0.5:
		await tree().physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
	p.input.fire = false


func face_wall() -> void:
	# Face à un mur à ~4 m (même poste que weapon_basic).
	p.teleport_to(MapData.cell_to_world(Vector2i(5, 7), 0.05), PI * 0.5)
	p.pitch = 0.0
	await seconds(0.2)


## Toutes les armes alignées de profil devant une caméra dédiée (deux planches).
func lineup() -> void:
	var ids: Array = WeaponDB.WEAPONS.keys()
	var stage := Node3D.new()
	game.world.add_child(stage)
	stage.global_position = Vector3(12.0, 40.0, 12.0)  # loin au-dessus de la carte
	var cam := Camera3D.new()
	stage.add_child(cam)
	cam.position = Vector3(0, 0, 2.2)
	cam.fov = 50.0
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.6, 0.4, 0)
	sun.light_energy = 1.4
	stage.add_child(sun)
	var fill := OmniLight3D.new()
	fill.position = Vector3(0, 0.5, 1.5)
	fill.omni_range = 5.0
	fill.light_energy = 1.2
	stage.add_child(fill)
	cam.make_current()
	for page in 2:
		var models := []
		for i in 15:
			var k: int = page * 15 + i
			if k >= ids.size():
				break
			var m := WeaponModels.build(WeaponDB.stats(ids[k]).model, false)
			stage.add_child(m)
			# Grille 3 x 5, canon vers la gauche, vue de profil (côté droit).
			@warning_ignore("integer_division")
			m.position = Vector3(-1.2 + (i % 3) * 1.2, 0.72 - int(i / 3) * 0.36, 0)
			m.rotation.y = -PI * 0.5
			var lb := Label3D.new()
			lb.text = ids[k]
			lb.pixel_size = 0.0025
			lb.position = m.position + Vector3(0, -0.12, 0.1)
			stage.add_child(lb)
			models.append(m)
			models.append(lb)
		await seconds(0.3)
		await at.screenshot("lineup_%d" % page)
		for m in models:
			m.queue_free()
	stage.queue_free()
	p.camera.make_current()
	await seconds(0.2)


func run() -> void:
	timeout_sec = 280
	p = await H.start_solo_game(self)
	if p == null:
		return
	game = Game.instance
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	await H.clear_zombies(self)
	pd = game.session.local_data()
	game.combat.shot_validated.connect(func(_pid): validated[0] += 1)
	await face_wall()

	# 1. Revue de l'arsenal (armes réparties entre les parties).
	var wi := -1
	for id in WeaponDB.WEAPONS:
		wi += 1
		if not mine(wi):
			continue
		var s := WeaponDB.stats(id)
		print("[roster] %s à %.1f s (%d fps)" % [id, GameClock.msec() / 1000.0, Engine.get_frames_per_second()])
		if not await equip(id):
			continue
		at.check(p.weapons.view.model_id == s.model and WeaponModels.spec(s.model).parts.size() > 8, "%s : modèle FPS (%d pièces)" % [id, WeaponModels.spec(s.model).parts.size()])
		await at.screenshot("fps_" + id)
		var before: int = pd.current_weapon().mag
		var v0: int = validated[0]
		await pull_trigger()
		var burst: int = s.get("burst", 1)
		await seconds(0.25 + burst * 60.0 / float(s.rpm))
		var fired: int = before - pd.current_weapon().mag
		at.check(fired == mini(burst, before) and validated[0] - v0 == fired, "%s : %d coup(s) tiré(s) et validé(s) (attendu %d)" % [id, fired, burst])
		# Rechargement (client + serveur).
		await seconds(WeaponDB.fire_interval(id) + 0.05)
		p.input.reload = true
		var rt := game.combat.reload_time(1, pd.current_weapon())
		var full := int(s.mag)
		await until(func(): return pd.current_weapon().mag == full and p.weapons.current().mag == full, rt + 1.5, "%s rechargé" % id)
		at.check(pd.current_weapon().mag == int(s.mag) and p.weapons.current().mag == int(s.mag), "%s : rechargé %d/%d" % [id, pd.current_weapon().mag, pd.current_weapon().reserve])

	# 2. Quelques armes améliorées (camouflage Pack-a-Punch).
	if owns(0):
		for id in ["m1911", "m16", "olympia"]:
			await equip(id, true)
			await at.screenshot("fps_pap_" + id)

	# 2 bis. Planche des silhouettes (modèles « monde », vus de profil, éclairés).
	if owns(1):
		await lineup()

	# 3. Visée : lunette du L96A1.
	if owns(2):
		await equip("l96a1")
		p.input.aim = true
		await seconds(0.5)
		await at.screenshot("ads_l96a1")
		p.input.aim = false
		await seconds(0.3)

	# 4. Explosifs : projectile visible, dégâts de zone à l'arrivée.
	if owns(3):
		for spec in [["china_lake", false, 600], ["law", false, 1200], ["m1911", true, 400]]:
			await face_wall()
			p.yaw = -PI * 0.5  # vers +X : grand espace libre
			await equip(spec[0], spec[1])
			var center := p.global_position + Vector3(9, 0, 0)
			var zs := []
			for k in 3:
				zs.append(await H.dummy_zombie(self, center + Vector3(0, 0, (k - 1) * 0.8), spec[2]))
			H.aim_at(p, zs[1].global_position + Vector3.UP * 0.9)
			await pull_trigger()
			await seconds(0.08)
			var alive_mid := 0
			for z: Zombie in zs:
				if z.is_alive():
					alive_mid += 1
			if spec[0] == "law":
				await at.screenshot("rocket_flight")
			await seconds(0.6)
			var dead := 0
			for z: Zombie in zs:
				if not z.is_alive():
					dead += 1
			at.check(dead == 3, "%s%s : %d/3 zombies tués par l'explosion" % [spec[0], " (amélioré)" if spec[1] else "", dead])
			if spec[0] == "law":
				at.check(alive_mid == 3, "LAW : la roquette met du temps à arriver (%d vivants à 0,08 s)" % alive_mid)
				await at.screenshot("explosion")
			await H.clear_zombies(self)

	# 4 bis. Les explosions tuent aussi les chiens de l'enfer.
	if owns(4):
		await face_wall()
		p.yaw = -PI * 0.5
		await equip("china_lake")
		var zm := game.zombies
		var dog_id := zm.spawn(p.global_position + Vector3(8, 0, 0), 0, 400, ZombieManager.KIND_DOG)
		var dog := zm.get_zombie(dog_id)
		dog.speed_mult = 0.0
		await seconds(2.5)
		H.aim_at(p, dog.global_position + Vector3.UP * 0.4)
		await pull_trigger()
		await seconds(0.8)
		at.check(not dog.is_alive(), "China Lake : chien de l'enfer tué par l'explosion")
		await H.clear_zombies(self)

	# 5. Dégâts à soi réduits (China Lake contre un mur proche).
	if owns(5):
		game.combat.debug_invulnerable = false
		await face_wall()
		p.teleport_to(MapData.cell_to_world(Vector2i(3, 7), 0.05), PI * 0.5)
		await equip("china_lake")
		H.aim_at(p, p.global_position + Vector3(-3.0, 1.0, 0))
		await pull_trigger()
		await seconds(0.5)
		at.check(pd.health < 100 and pd.health > 0 and pd.life == PlayerData.Life.ALIVE, "China Lake à bout portant : dégâts à soi réduits (%d PV)" % pd.health)
		game.combat.debug_invulnerable = true

	# 6. Olympia améliorée : le zombie brûle après le tir.
	if owns(6):
		await face_wall()
		p.yaw = -PI * 0.5
		await equip("olympia", true)
		var zb := await H.dummy_zombie(self, p.global_position + Vector3(4, 0, 0), 5000)
		H.aim_at(p, zb.global_position + Vector3.UP * 0.9)
		await pull_trigger()
		await seconds(0.1)
		var hp_after_shot := zb.health
		await seconds(1.0)
		at.check(zb.health < hp_after_shot, "balles incendiaires : %d -> %d PV" % [hp_after_shot, zb.health])
		await H.clear_zombies(self)

	# 7. Vitesse de déplacement selon l'arme.
	if owns(7):
		await equip("m1911")
		var v_pistol := p.current_max_speed()
		await equip("hk21")
		var v_lmg := p.current_max_speed()
		at.check(v_lmg < v_pistol * 0.9, "mitrailleuse plus lente : %.2f m/s contre %.2f m/s" % [v_lmg, v_pistol])
