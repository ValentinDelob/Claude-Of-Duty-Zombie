extends AutotestScenario
## [MP] Hôte : joueur à terre puis mort pendant la fenêtre d'évacuation
## (GAME_CONCEPT.md §4.5, §4.6). Le client vote « partir » dans la zone,
## l'hôte aussi ; le client tombe à terre : l'équipe l'attend ; il succombe
## (spectateur) : l'équipe part avec lui. Fin de partie « évacuation réussie »
## chez les deux, et le client rapporte l'arme trouvée qu'il avait en main
## (mise de côté à terre).

const PORT := 17931

var H := AutotestHelpers


func run() -> void:
	timeout_sec = 150
	if not await MpHelpers.host_game(self, PORT):
		return
	var game := Game.instance
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	var door := game.evac
	if door == null:
		at.fail("porte d'évacuation absente")
		return
	var cid := 0
	for pid in game.players:
		if pid != 1:
			cid = pid
	var client: Player = game.players[cid]
	# Arme trouvée pendant la partie, en main du client.
	var cpd := game.session.get_data(cid)
	cpd.weapons.append(GameWeapon.make("mp40", 1, OwnedWeapon.Rarity.RARE, [], "loot:77"))
	game.session.sync_inventory(cid)
	if not await MpHelpers.wait_peer(self, "place", 30.0):
		return
	await until(func(): return door.in_zone(client.srv_origin()), 10.0, "client vu dans la zone")
	await H.clear_zombies(self)
	var dogs := game.rounds.dogs
	dogs.debug_force_next(2)
	game.rounds.paused = false
	game.rounds.debug_jump_to(2)
	if not await until(func(): return dogs.active, 2.0, "vague spéciale lancée"):
		return
	dogs.spawned = dogs.total
	if not await until(func(): return door.is_open, 3.0, "porte ouverte"):
		return
	MpHelpers.signal_peer("ouverte")
	var ok: bool = await until(func(): return int(door.votes.get(cid, 0)) == EvacRules.Vote.LEAVE, 20.0, "vote « partir » du client")
	at.check(ok, "hôte : vote « partir » du client reçu")
	# L'hôte entre dans la zone et vote « partir » ; le client tombe d'abord.
	game.downed.srv_down(cid)
	at.check(cpd.life == PlayerData.Life.DOWNED, "hôte : client à terre")
	var p := game.local_player
	p.bot_controlled = true
	p.teleport_to(door.global_position + door.global_basis.z * 1.6 + door.global_basis.x * 1.0 + Vector3.UP * 0.05)
	await frames(3)
	H.aim_at(p, door.interact_point())
	await until(func(): return game.interact.focused == door, 2.0, "hôte : porte visée")
	p.input.interact_pressed = true
	await until(func(): return int(door.votes.get(1, 0)) == EvacRules.Vote.LEAVE, 2.0, "vote de l'hôte")
	await seconds(1.0)
	at.check(door.is_open and GameState.state != GameState.State.GAME_OVER, "hôte : client à terre dans la zone, l'équipe l'attend")
	MpHelpers.signal_peer("a_terre")
	if not await MpHelpers.wait_peer(self, "vu_a_terre", 20.0):
		return
	# Il succombe : spectateur, il ne vote plus et part avec l'équipe.
	game.downed._bleed_out(cid)
	ok = await until(func(): return GameState.state == GameState.State.GAME_OVER and game.last_result != null, 3.0, "évacuation")
	at.check(ok and game.last_result.evacuated, "hôte : l'équipe s'évacue avec le joueur mort")
	await MpHelpers.finish(self)
