extends AutotestScenario
## Garde-fous du serveur dans le vrai jeu (docs/SECURITY.md) : un client qui
## ment dans ses RPC ne peut ni poser une explosion hors de la trajectoire de
## son tir, ni tirer avec une origine NaN, ni déclencher des plongeons
## explosifs à volonté, ni faire charger une réplique hors du dossier des voix.

var game: Game
var p: Player
var H := AutotestHelpers


func run() -> void:
	timeout_sec = 60
	p = await H.start_solo_game(self)
	if p == null:
		return
	game = Game.instance
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	await H.clear_zombies(self)
	var origin := MapData.cell_to_world(Vector2i(4, 7), 0.05)
	p.teleport_to(origin, -PI * 0.5)
	await seconds(0.3)
	var pd := game.session.local_data()
	pd.slot = WeaponDB.give(pd, "law")
	game.session.sync_inventory(1)
	await seconds(0.3)
	var eye := p.camera.global_position

	# 1. Explosion revendiquée DERRIÈRE le tireur (visée vers +x) : refusée.
	var behind := await H.dummy_zombie(self, origin + Vector3(-8, 0, 0), 5000)
	var hp_behind := behind.health
	game.combat.srv_fire.rpc_id(1, pd.slot, eye, Vector3(1, 0, 0), PackedVector3Array(),
		[[behind.id, 0, 8.0, behind.global_position + Vector3.UP * 0.9]])
	await seconds(1.0)  # rien ne doit arriver : on laisse le temps à une explosion éventuelle
	at.check(behind.health == hp_behind, "explosion hors de la trajectoire refusée (PV %d -> %d)" % [hp_behind, behind.health])

	# 2. Contrôle : la même roquette devant le tireur explose normalement.
	var front := await H.dummy_zombie(self, origin + Vector3(8, 0, 0), 5000)
	var hp_front := front.health
	await seconds(0.5)
	pd.current_weapon().mag = 1  # M72 LAW : une roquette par chargeur
	game.combat.srv_fire.rpc_id(1, pd.slot, eye, Vector3(1, 0, 0), PackedVector3Array(),
		[[front.id, 0, 8.0, front.global_position + Vector3.UP * 0.9]])
	await until(func(): return is_instance_valid(front) and front.health < hp_front, 3.0, "dégâts de la roquette")
	at.check(front.health < hp_front, "roquette sur la trajectoire : dégâts (PV %d -> %d)" % [hp_front, front.health])
	await H.clear_zombies(self)

	# 3. Origine NaN : tir refusé, aucune munition consommée.
	await seconds(0.6)
	pd.current_weapon().mag = 1
	var mag: int = pd.current_weapon().mag
	var rejected := []
	game.combat.shot_rejected.connect(func(_pid, reason): rejected.append(reason))
	game.combat.srv_fire.rpc_id(1, pd.slot, Vector3(NAN, 0, 0), Vector3(1, 0, 0), PackedVector3Array(), [])
	game.combat.srv_fire.rpc_id(1, pd.slot, eye, Vector3(INF, 0, 0), PackedVector3Array(), [])
	await until(func(): return rejected.size() >= 2, 2.0, "refus des deux tirs NaN / infini")
	at.check(pd.current_weapon().mag == mag and rejected.size() == 2, "tirs NaN / infini refusés (%s)" % [rejected])

	# 4. Fins de plongeon envoyées en rafale : une seule acceptée.
	var landings := []
	game.combat.player_dived_landed.connect(func(pid, _pos, _h): landings.append(pid))
	for i in 6:
		game.combat.srv_dive_landed.rpc_id(1, p.global_position, 12.0)
	await seconds(0.2)  # on compte TOUS les plongeons acceptés : fenêtre fixe
	at.check(landings.size() == 1, "plongeons en rafale : %d accepté(s) sur 6" % landings.size())

	# 5. Réplique au nom-chemin (hôte malveillant) : ignorée.
	var said := []
	game.vox.said.connect(func(_pid, cat, _v): said.append(cat))
	game.vox._cl_say(1, "../../../../evil", 0)
	game.vox._cl_say(1, "reload", 0)
	at.check(said == ["reload"], "réplique hors du dossier des voix ignorée (%s)" % [said])

	# 6. Inondations bornées (docs/REFACTORING_PLAN.md § 3) : fins
	#    d'interaction, dégoupillages et faux lancers en rafale ; chaque faux
	#    lancer renvoyait un message d'annulation au client.
	for i in 40:
		game.interact.srv_release.rpc_id(1, "inconnu_%d" % i)
	at.check(not game.interact._release_limit.allow(1), "fins d'interaction en rafale : limiteur engagé")
	for i in 40:
		game.throwables.srv_cook.rpc_id(1, 99)
	at.check(not game.throwables._cook_limit.allow(1), "dégoupillages en rafale : limiteur engagé")
	var grenades := pd.grenades
	game.throwables.srv_cook.rpc_id(1, ThrowableRules.Kind.FRAG)
	at.check(pd.grenades == grenades and not game.throwables.is_cooking(1), "dégoupillage refusé pendant l'inondation")
	for i in 40:
		game.throwables.srv_throw.rpc_id(1, eye, Vector3(1, 0, 0), 1000 + i)
	at.check(not game.throwables._cancel_limit.allow(1), "faux lancers en rafale : annulations bornées")
	# Un peu plus d'une seconde réelle après : un vrai lancer passe de nouveau.
	var real0 := Time.get_ticks_msec()
	await until(func(): return Time.get_ticks_msec() - real0 > 1200, 5.0, "remplissage des limiteurs")
	var items := game.throwables.items.size()
	game.throwables.srv_cook.rpc_id(1, ThrowableRules.Kind.FRAG)
	game.throwables.srv_throw.rpc_id(1, eye, Vector3(1, 0, 0), 2000)
	at.check(pd.grenades == grenades - 1 and game.throwables.items.size() == items + 1,
		"vrai lancer accepté après l'inondation (%d -> %d grenades)" % [grenades, pd.grenades])

	# 7. Lancer annoncé depuis sous le sol (à moins de 4 m du joueur) : l'objet
	#    part des yeux du joueur, jamais de l'autre côté du décor.
	pd.grenades = 2
	game.throwables.srv_cook.rpc_id(1, ThrowableRules.Kind.FRAG)
	game.throwables.srv_throw.rpc_id(1, p.global_position + Vector3(0, -2.5, 0), Vector3(1, 0, 0), 2001)
	var newest: Throwable = null
	for tid in game.throwables.items:
		if newest == null or int(tid) > newest.tid:
			newest = game.throwables.items[tid]
	at.check(newest != null and newest.position.y > p.global_position.y + 0.5,
		"origine sous le sol refusée : départ des yeux (y %.2f, joueur %.2f)" % [newest.position.y if newest else 0.0, p.global_position.y])
