extends AutotestScenario
## Bonus : apparition au seuil de points (kill suivant), ramassage en marchant
## dessus, effets de chaque bonus dans le vrai jeu (munitions max, mort
## instantanée, points doubles, nuke, charpentier, liquidation), minuteurs du
## HUD, fin de vie au sol (clignotement puis disparition), 4 par manche.

var H := AutotestHelpers
var game: Game
var p: Player
var pd: PlayerData
var pw: PowerupSystem
var box: MysteryBox
## Point de départ (devant la boîte, dos à elle) et direction « devant ».
var origin: Vector3
var fwd: Vector3


func stand() -> void:
	p.teleport_to(origin, atan2(-fwd.x, -fwd.z))
	await seconds(0.25)


func ahead(d: float, side := 0.0) -> Vector3:
	var right := fwd.cross(Vector3.UP)
	return Vector3(origin.x, 0.0, origin.z) + fwd * d + right * side


## Fait tomber `type` devant le joueur, le photographie, puis marche dessus.
func drop_and_grab(type: String, shot := "") -> bool:
	await stand()
	var id := pw.debug_drop(type, ahead(3.0))
	await seconds(0.5)
	var node: PowerupDrop = pw.nodes.get(id)
	at.check(node != null and node.type == type, "%s : bonus au sol chez le client" % type)
	if shot != "" and node:
		H.aim_at(p, node.global_position + Vector3.UP * 0.8)
		await seconds(0.3)
		# Modèle tourné de face (il pivote en continu).
		var to_cam := p.global_position - node.global_position
		node._model.rotation.y = atan2(to_cam.x, to_cam.z) - 0.35
		await at.screenshot(shot)
	at.check(pw._drops.has(id), "%s : pas ramassé à 3 m" % type)
	p.teleport_to(ahead(3.0) + Vector3.UP * 0.05)
	await seconds(0.3)
	var ok := not pw._drops.has(id) and not pw.nodes.has(id)
	at.check(ok, "%s : ramassé en marchant dessus" % type)
	return ok


func refill_pistol() -> void:
	var w: Dictionary = pd.current_weapon()
	w.mag = WeaponDB.stats(w.id, w.pap).mag
	game.session.sync_inventory(1)
	await seconds(0.3)


func run() -> void:
	timeout_sec = 300
	p = await H.start_solo_game(self, "bunker_k7")
	if p == null:
		return
	game = Game.instance
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	pd = game.session.local_data()
	pw = game.powerups
	for id in game.doors:
		game.doors[id].srv_open()
	box = game.interact.get_obj("box")
	# La normale de l'emplacement pointe vers le mur : la salle est à l'opposé.
	var n: Vector3 = box.spots[box.location].normal
	fwd = -Vector3(n.x, 0, n.z).normalized()
	origin = box.global_position + fwd * 1.6 + Vector3(0, 0.05, 0)
	await stand()
	at.check(pw != null and pw.random_drops == false, "système de bonus présent (tirage aléatoire coupé en test)")

	# ---------------------------------------------- seuil de points d'équipe
	game.points.team_earned = 1960
	var z := await H.dummy_zombie(self, ahead(5.0), 1)
	H.aim_at(p, z.global_position + Vector3.UP * 0.9)
	await H.shoot(self, p, 0.3)
	at.check(not z.is_alive() and game.points.team_earned > 2000, "kill qui franchit 2000 points (%d)" % game.points.team_earned)
	at.check(pw.drop_count() == 0 and pw.tracker.drop_pending, "pas de bonus sur ce kill, mais bonus dû au suivant")
	at.check(absf(pw.tracker.increment - 2280.0) < 0.1, "incrément x1,14 : %.0f" % pw.tracker.increment)
	await seconds(0.3)
	z = await H.dummy_zombie(self, ahead(4.0, 1.0), 1)
	var zpos := z.global_position
	H.aim_at(p, zpos + Vector3.UP * 0.9)
	await H.shoot(self, p, 0.3)
	await seconds(0.3)
	at.check(pw.drop_count() == 1 and pw.nodes.size() == 1, "le kill suivant fait tomber un bonus")
	var first_id: int = pw._drops.keys()[0] if pw.drop_count() > 0 else -1
	if first_id > 0:
		var dpos: Vector3 = pw._drops[first_id].pos
		at.check(Vector2(dpos.x - zpos.x, dpos.z - zpos.z).length() < 0.5, "bonus sur le cadavre du zombie")
		at.check(pw._drops[first_id].type in PowerupRules.ALL, "type tiré du sac : %s" % pw._drops[first_id].type)
	await seconds(1.0)
	await at.screenshot("kill_drop")
	pw.debug_clear()
	await H.clear_zombies(self)

	# ---------------------------------------------- munitions max
	for w in pd.weapons:
		w.reserve = 0
	game.session.sync_inventory(1)
	await seconds(0.2)
	if await drop_and_grab(PowerupRules.MAX_AMMO, "ground_max_ammo"):
		var full := true
		for w in pd.weapons:
			full = full and w.reserve == WeaponDB.stats(w.id, w.pap).reserve
		at.check(full, "munitions max : réserve pleine (%d)" % pd.current_weapon().reserve)
		at.check(p.weapons.current().reserve == pd.current_weapon().reserve, "munitions max : arme du client synchronisée")
		await seconds(0.4)
		await at.screenshot("announce_max_ammo")

	# ---------------------------------------------- mort instantanée
	await refill_pistol()
	if await drop_and_grab(PowerupRules.INSTA_KILL, "ground_insta_kill"):
		at.check(pw.is_active(PowerupRules.INSTA_KILL) and absf(pw.timers[PowerupRules.INSTA_KILL] - 30.0) < 0.6, "mort instantanée : 30 s")
		await stand()
		var before := pd.points
		z = await H.dummy_zombie(self, ahead(5.0), 50000)
		H.aim_at(p, z.global_position + Vector3.UP * 0.9)
		await H.shoot(self, p, 0.3)
		at.check(not z.is_alive(), "mort instantanée : zombie de 50000 PV tué d'une balle")
		var gained := pd.points - before
		at.check(gained == 50 or gained == 100, "mort instantanée : points de kill normaux (+%d)" % gained)
		await H.clear_zombies(self)

	# ---------------------------------------------- points doubles
	await refill_pistol()
	if await drop_and_grab(PowerupRules.DOUBLE_POINTS, "ground_double_points"):
		at.check(game.points.multiplier == 2, "points doubles : multiplicateur x2")
		await stand()
		await seconds(0.8)
		at.check(game.hud.powerup_hud.shown_icons().size() == 2, "HUD : icônes mort instantanée + points doubles")
		await at.screenshot("hud_icons")
		# Mort instantanée coupée pour tester un coup non mortel.
		pw._cl_timer.rpc(PowerupRules.INSTA_KILL, 0.0)
		var before := pd.points
		z = await H.dummy_zombie(self, ahead(5.0), 50000)
		H.aim_at(p, z.global_position + Vector3.UP * 0.9)
		await H.shoot(self, p, 0.3)
		at.check(pd.points - before == 20, "points doubles : touche à +20 (%d)" % (pd.points - before))
		await H.clear_zombies(self)
		# Ramasser à nouveau remet le minuteur à 30 s ; clignotement à la fin.
		pw.timers[PowerupRules.DOUBLE_POINTS] = 4.0
		await seconds(0.1)
		var blinked := false
		for i in 20:
			if game.hud.powerup_hud.shown_icons().size() == 1 and not PowerupRules.hud_icon_visible(pw.timers[PowerupRules.DOUBLE_POINTS]):
				blinked = true
			await frames(3)
		at.check(blinked, "HUD : l'icône clignote dans les dernières secondes")
		await drop_and_grab(PowerupRules.DOUBLE_POINTS)
		at.check(pw.timers.get(PowerupRules.DOUBLE_POINTS, 0.0) > 29.0, "nouveau ramassage : minuteur remis à 30 s")
		pw.timers[PowerupRules.DOUBLE_POINTS] = 0.3
		await seconds(0.6)
		at.check(not pw.is_active(PowerupRules.DOUBLE_POINTS) and game.points.multiplier == 1, "fin des points doubles : x1")

	# ---------------------------------------------- nuke
	await stand()
	var zs: Array = []
	for k in 6:
		@warning_ignore("integer_division")
		zs.append(await H.dummy_zombie(self, ahead(6.0 + (k % 3) * 1.5, (k / 3) * 2.0 - 1.0), 5000))
	var pts_before := pd.points
	var kills_before := pd.kills
	pw.tracker.drop_pending = true
	if await drop_and_grab(PowerupRules.NUKE, "ground_nuke"):
		H.aim_at(p, ahead(10.0) + Vector3.UP)
		await seconds(0.15)
		await at.screenshot("nuke_flash")
		await seconds(2.2)
		var alive := 0
		for zz: Zombie in zs:
			if is_instance_valid(zz) and zz.is_alive():
				alive += 1
		at.check(alive == 0, "nuke : tous les zombies tués (%d restants)" % alive)
		at.check(pd.points - pts_before == 400, "nuke : +400 points seulement (%d)" % (pd.points - pts_before))
		at.check(pd.kills == kills_before, "nuke : kills non comptés")
		at.check(pw.drop_count() == 0, "nuke : aucun bonus sur les zombies tués")
	pw.tracker.drop_pending = false
	await H.clear_zombies(self)

	# ---------------------------------------------- charpentier
	var carp := [0]
	pw.carpenter_used.connect(func(): carp[0] += 1)
	var before_c := pd.points
	if await drop_and_grab(PowerupRules.CARPENTER, "ground_carpenter"):
		at.check(pd.points - before_c == 200, "charpentier : +200 points (%d)" % (pd.points - before_c))
		at.check(carp[0] == 1, "charpentier : signal carpenter_used émis")

	# ---------------------------------------------- liquidation
	box.moves = 0
	at.check(not pw.is_valid(PowerupRules.FIRE_SALE), "liquidation exclue tant que la boîte n'a pas déménagé")
	box.moves = 1
	at.check(pw.is_valid(PowerupRules.FIRE_SALE), "liquidation possible après un déménagement")
	if await drop_and_grab(PowerupRules.FIRE_SALE, "ground_fire_sale"):
		at.check(box.fire_sale and box.cost() == 10, "liquidation : boîte à 10 points")
		at.check(box.fire_sale_boxes.size() == box.spots.size() - 1, "liquidation : une boîte à chaque emplacement (%d + 1)" % box.fire_sale_boxes.size())
		var all_ten := true
		for b: MysteryBox in box.fire_sale_boxes:
			all_ten = all_ten and b.cost() == 10 and game.interact.get_obj(b.interact_id) == b
		at.check(all_ten, "liquidation : boîtes temporaires à 10 points")
		at.check(pw._fire_sale_music != null and pw._fire_sale_music.playing, "liquidation : musique spéciale")
		p.teleport_to(origin)
		H.aim_at(p, box.global_position + Vector3.UP * 0.8)
		await seconds(0.4)
		at.check(game.hud._prompt.text.contains("[10]"), "invite : %s" % game.hud._prompt.text)
		await at.screenshot("fire_sale_prompt")
		var before_f := pd.points
		p.input.interact_pressed = true
		await seconds(0.3)
		at.check(box.state == MysteryBox.State.ROLLING and before_f - pd.points == 10, "achat de la boîte pour 10 points")
		pw.timers[PowerupRules.FIRE_SALE] = 0.3
		await seconds(0.6)
		at.check(not box.fire_sale and box.cost() == MysteryBox.COST and pw._fire_sale_music == null, "fin de la liquidation : 950 points")
		at.check(box.fire_sale_boxes.is_empty(), "fin de la liquidation : boîtes temporaires retirées")
		await until(func(): return box.state == MysteryBox.State.READY, 6.0, "arme prête")
		p.input.interact_pressed = true
		await seconds(0.3)

	# ---------------------------------------------- FAUCHEUSE (death machine)
	await H.clear_zombies(self)
	var prev_id: String = pd.current_weapon().id
	if await drop_and_grab(PowerupRules.DEATH_MACHINE, "ground_death_machine"):
		var dm := PowerupRules.DEATH_MACHINE_WEAPON
		at.check(pd.current_weapon().get("id", "") == dm and pw.has_death_machine(1), "faucheuse : minigun en main (serveur)")
		await until(func(): return p.weapons.current().get("id", "") == dm and p.weapons.view.model_id == dm, 2.0, "minigun chez le client")
		at.check(p.weapons.current().get("id", "") == dm, "faucheuse : modèle FPS du minigun")
		at.check(absf(pw.death_machine.get(1, 0.0) - 30.0) < 0.8, "faucheuse : 30 s (%.1f)" % pw.death_machine.get(1, 0.0))
		at.check(PowerupRules.DEATH_MACHINE in game.hud.powerup_hud.shown_icons(), "HUD : icône de la faucheuse")
		await stand()
		await seconds(WeaponController.SWITCH_TIME + 0.2)
		await at.screenshot("death_machine_hud")
		# Pas de changement d'arme pendant le bonus.
		p.input.switch_weapon = true
		await seconds(0.3)
		p.input.switch_weapon = false
		at.check(p.weapons.current().get("id", "") == dm, "faucheuse : pas de changement d'arme")
		# Dégâts énormes : un zombie de manche 15 (~2600 PV) fauché en une rafale.
		var dz := await H.dummy_zombie(self, ahead(6.0), RoundRules.zombie_health(15))
		var mag0: int = pd.current_weapon().mag
		# On suit la hitbox réelle : les balles peuvent en faire un rampant.
		p.input.fire = true
		await until(func():
			if dz.is_alive():
				H.aim_at(p, dz.hit_body.global_position)
			return not dz.is_alive(), 4.0, "zombie fauché")
		await seconds(0.1)
		await at.screenshot("death_machine_fire")
		p.input.fire = false
		var fired := mag0 - int(pd.current_weapon().mag)
		at.check(not dz.is_alive() and fired > 0 and fired <= 20, "faucheuse : zombie de manche 15 tué en %d balles" % fired)
		at.check(not game.combat.is_reloading(1) and not p.weapons.is_reloading(), "faucheuse : jamais de rechargement")
		# Arme de bonus : ni boîte, ni armes au mur.
		p.teleport_to(origin)
		H.aim_at(p, box.global_position + Vector3.UP * 0.8)
		await seconds(0.4)
		at.check(not game.hud._prompt.text.contains("Boîte"), "faucheuse : boîte mystère indisponible (%s)" % game.hud._prompt.text)
		await H.clear_zombies(self)
		# Fin du bonus : l'arme d'avant revient.
		pw.death_machine[1] = 0.3
		await seconds(0.7)
		at.check(not pw.has_death_machine(1) and pd.powerup_weapon.is_empty() and pd.current_weapon().id == prev_id, "fin de la faucheuse : %s rendue" % pd.current_weapon().id)
		await until(func(): return p.weapons.current().get("id", "") == prev_id, 2.0, "arme rendue au client")
		at.check(p.weapons.current().get("id", "") == prev_id and not PowerupRules.DEATH_MACHINE in game.hud.powerup_hud.shown_icons(), "fin de la faucheuse chez le client")

	# ---------------------------------------------- fin de vie au sol
	await stand()
	var eid := pw.debug_drop(PowerupRules.MAX_AMMO, ahead(4.0))
	await seconds(0.3)
	pw._drops[eid].age = 22.0
	var enode: PowerupDrop = pw.nodes[eid]
	enode.age = 22.0
	var hidden_seen := false
	var shown_seen := false
	for i in 40:
		if enode.shown:
			shown_seen = true
		else:
			hidden_seen = true
		await frames(2)
	at.check(hidden_seen and shown_seen, "clignotement de fin de vie")
	await until(func(): return not pw._drops.has(eid) and not pw.nodes.has(eid), 6.0, "disparition après 26,5 s")
	at.check(not pw._drops.has(eid), "bonus disparu sans être ramassé")

	# ---------------------------------------------- 4 bonus par manche
	pw.tracker.drops_this_round = PowerupRules.MAX_PER_ROUND
	pw.tracker.drop_pending = true
	await refill_pistol()
	z = await H.dummy_zombie(self, ahead(5.0), 1)
	H.aim_at(p, z.global_position + Vector3.UP * 0.9)
	for i in 5:
		if not z.is_alive():
			break
		await H.shoot(self, p, 0.3)
	at.check(not z.is_alive() and pw.drop_count() == 0, "maximum de 4 bonus par manche (vivant %s, bonus %d)" % [z.is_alive(), pw.drop_count()])
	pw.tracker.new_round()
	# Le corps du zombie précédent ne doit pas arrêter les balles.
	await H.clear_zombies(self)
	await refill_pistol()
	await stand()
	z = await H.dummy_zombie(self, ahead(5.0, 1.0), 1)
	# Ce qui est vérifié ici est le bonus dû, pas la précision : on revise avant
	# chaque tir et on tire jusqu'à la mort (dispersion aléatoire à la hanche ;
	# 5 tirs ratés d'affilée faisaient échouer le test de temps en temps).
	for i in 12:
		if not z.is_alive():
			break
		H.aim_at(p, z.global_position + Vector3.UP * 0.9)
		await H.shoot(self, p, 0.3)
		if i == 5:
			await refill_pistol()
	await until(func(): return pw.drop_count() == 1, 1.0, "bonus dû")
	at.check(pw.drop_count() == 1, "nouvelle manche : le bonus dû tombe (vivant %s, dû %s, bonus de la manche %d)" % [z.is_alive(), pw.tracker.drop_pending, pw.tracker.drops_this_round])
	pw.debug_clear()
