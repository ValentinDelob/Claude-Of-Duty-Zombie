extends AutotestScenario
## Couteau (BO1) : fente vers un zombie visé à 2,5 m, 150 dégâts, mort au
## couteau = ferraille fixe d'un kill, pas de fente hors du cône de visée, animation du bras
## gauche. (Le COUTEAU DE CHASSE mural est supprimé : lot C.)

var H := AutotestHelpers


## Place le joueur au quai, regard vers +X, et un zombie immobile devant lui.
func setup_duel(p: Player, dist: float, health: int, side := 0.0) -> Zombie:
	await H.clear_zombies(self)
	var start := MapData.cell_to_world(Vector2i(28, 8), 0.05)
	p.teleport_to(start, -PI * 0.5)
	var z := await H.dummy_zombie(self, start + Vector3(dist, -0.05, side), health)
	p.teleport_to(start, -PI * 0.5)
	H.aim_at(p, z.global_position + Vector3.UP * 1.2)
	if side != 0.0:
		# Regard droit devant (+X) : le zombie est hors du cône.
		H.aim_at(p, start + Vector3(5.0, 1.4, 0.0))
	await seconds(0.9)  # couteau prêt
	return z


func knife(p: Player) -> void:
	p.input.melee = true
	await until(func(): return not p.input.melee, 1.0, "coup de couteau pris en compte")


func run() -> void:
	timeout_sec = 120
	var p: Player = await H.start_solo_game(self, "bunker_k7")
	if p == null:
		return
	var game := Game.instance
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	var pd := game.session.local_data()
	for id in game.doors:
		game.doors[id].srv_open()
	var power: PowerSwitch = game.interact.get_obj("power")
	if power:
		power.srv_use(1)  # lumière pour les captures
	await seconds(2.5)  # captures : les lumières finissent de s'allumer
	at.check(pd.knife == "knife" and p.weapons.knife_id == "knife", "couteau de départ")

	# 1. Fente : zombie visé à 2,5 m, mort d'un coup (150 PV), ferraille d'un kill.
	var z := await setup_duel(p, 2.5, 150)
	var pts := pd.points
	var x0 := p.global_position.x
	await knife(p)
	at.check(p.weapons.lunging and p.is_lunging(), "fente déclenchée")
	await seconds(0.07)  # capture : élan
	await at.screenshot("melee_windup")
	await seconds(0.12)  # capture : coup porté
	await at.screenshot("melee_slash")
	var moved := p.global_position.x - x0
	at.check(moved > 1.0 and moved < 2.2, "le joueur s'est projeté vers le zombie (%.2f m)" % moved)
	await until(func(): return (not is_instance_valid(z) or not z.is_alive()) and pd.points - pts == PointsRules.KILL, 1.0, "zombie tué par la fente")
	at.check(not z.is_alive(), "zombie à 2,5 m tué par la fente")
	at.check(pd.points - pts == PointsRules.KILL, "mort au couteau : montant fixe (%d)" % (pd.points - pts))
	await seconds(0.5)

	# 2. Dégâts du couteau : 150 sur un zombie plus résistant.
	z = await setup_duel(p, 2.5, 1000)
	await knife(p)
	await until(func(): return z.health < 1000, 1.0, "coup de couteau encaissé")
	at.check(z.is_alive() and z.health == 850, "couteau : 150 dégâts (1000 -> %d)" % z.health)
	pts = pd.points
	await seconds(0.5)

	# 3. Pas de fente si le zombie n'est pas visé (35° à côté).
	z = await setup_duel(p, 2.1, 1000, -1.45)
	x0 = p.global_position.x
	await knife(p)
	await seconds(0.1)  # capture
	await at.screenshot("melee_miss")
	await seconds(0.3)  # fenêtre fixe : on vérifie qu'aucune fente ne part
	at.check(not p.weapons.lunging and absf(p.global_position.x - x0) < 0.3, "pas de fente hors du cône (%.2f m)" % (p.global_position.x - x0))
	at.check(z.health == 1000, "zombie non visé intact (%d)" % z.health)
	await seconds(0.5)

	# 4. Coup truqué : origine avancée de 4,2 m (sans fente possible) vers un
	# zombie à 6 m, hors de portée de fente depuis la position serveur.
	z = await setup_duel(p, 6.0, 1000)
	game.combat.srv_melee.rpc_id(1, p.camera.global_position + Vector3(4.2, 0, 0), Vector3(1, 0, 0))
	await seconds(0.2)  # fenêtre fixe : le coup doit rester sans effet
	at.check(z.health == 1000, "coup de couteau à distance refusé (%d)" % z.health)
	await H.clear_zombies(self)

	# 5. BATTE de baseball (arme de base tenue en main) : coup au contact,
	# dégâts de la batte, énergie dépensée (plus que le couteau), animation,
	# deux zombies côte à côte frappés du même coup ; le couteau reste
	# l'attaque séparée.
	pd.weapons = [WeaponDB.new_instance("bat")]
	pd.slot = 0
	game.session.sync_inventory(1)
	await until(func(): return p.weapons.current().get("id", "") == "bat", 2.0, "batte en main")
	await seconds(WeaponController.SWITCH_TIME + 0.2)
	var bat_dmg := int(WeaponDB.stats("bat").damage)
	z = await setup_duel(p, 1.5, 1000)
	var z2 := await H.dummy_zombie(self, z.global_position + Vector3(0.0, 0.0, 0.6), 1000)
	H.aim_at(p, z.global_position + Vector3(0, 1.2, 0.3))
	p.energy.value = PlayerEnergy.MAX
	var e0: float = p.energy.value
	p.input.fire = true
	await until(func(): return p.weapons.view.is_swinging(), 1.0, "coup de batte lancé")
	p.input.fire = false
	at.check(e0 - p.energy.value >= float(WeaponDB.stats("bat").energy) - 0.5, "énergie d'un coup de batte (%.1f)" % (e0 - p.energy.value))
	await seconds(0.12)  # capture : élan
	await at.screenshot("bat_windup")
	await until(func(): return z.health < 1000, 1.5, "coup de batte encaissé")
	await at.screenshot("bat_hit")
	at.check(z.health == 1000 - bat_dmg, "batte : %d dégâts (1000 -> %d)" % [bat_dmg, z.health])
	at.check(z2.health == 1000 - bat_dmg, "batte : le zombie voisin aussi frappé (%d)" % z2.health)
	# Coups enchaînés en maintenant le tir : revers.
	await seconds(0.9)
	p.input.fire = true
	await until(func(): return z.health <= 1000 - bat_dmg * 2, 2.0, "second coup enchaîné")
	p.input.fire = false
	at.check(z.health == 1000 - bat_dmg * 2, "second coup de batte (%d)" % z.health)
	# Le couteau reste l'attaque rapide séparée, batte en main.
	var hp := z.health
	await seconds(0.8)
	await knife(p)
	await until(func(): return z.health < hp, 1.0, "coup de couteau, batte en main")
	at.check(hp - z.health == KnifeDB.damage(KnifeDB.DEFAULT), "couteau batte en main : %d dégâts" % (hp - z.health))
	# Batte ni rechargée ni comptée au HUD : munitions infinies.
	at.check(p.weapons.current().mag == 0 and not p.weapons.is_reloading(), "batte : pas de munitions ni de rechargement")
	await H.clear_zombies(self)
