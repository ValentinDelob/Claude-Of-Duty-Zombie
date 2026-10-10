extends AutotestScenario
## [MP] Hôte : butin personnel des vagues spéciales (GAME_CONCEPT §4.7).
## L'hôte force une vague de chiens et la fait vaincre : chaque joueur a ses
## propres tirages (échantillons et pièce par chien, une arme au sol à sa
## couleur). Le client, debout sur l'arme de l'hôte, essaie de la ramasser :
## refusé ici (l'arme reste, aucun inventaire ne change) ; il ramasse la
## sienne ([F], validé ici) puis y installe une pièce depuis son panneau.

const PORT := 17921

var H := AutotestHelpers


func run() -> void:
	timeout_sec = 150
	if not await MpHelpers.host_game(self, PORT):
		return
	var game := Game.instance
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	await H.clear_zombies(self)
	game.map_def.waves = WaveRules.parse({"speciale": {"premiere": 0, "intervalle": 0}})
	var loot := game.loot
	loot.debug_part_chance = 1.0
	loot.debug_sample_chance = 1.0
	var cid := 0
	for pid in game.players:
		if pid != 1:
			cid = pid
	var cpd := game.session.get_data(cid)
	var hpd := game.session.local_data()
	game.rounds.paused = false

	# 1. Vague de chiens vaincue : butin de chaque joueur.
	if not await H.clear_dog_wave(self, 2):
		return
	await until(func(): return loot.drops.size() == 2, 3.0, "deux armes au sol")
	var host_drop: LootDrop = null
	var client_drop: LootDrop = null
	for d: LootDrop in loot.drops.values():
		if d.owner_pid == 1:
			host_drop = d
		elif d.owner_pid == cid:
			client_drop = d
	at.check(host_drop != null and client_drop != null, "une arme par joueur, chacune à son propriétaire")
	if host_drop == null or client_drop == null:
		return
	at.check(not (loot.samples.get(cid, {}) as Dictionary).is_empty() and not (loot.parts.get(cid, []) as Array).is_empty(),
			"tirages du client faits ici (échantillons, pièce)")
	at.check(host_drop.prompt(cid) == "" and host_drop.prompt(1) != "", "invite de l'arme de l'hôte : l'hôte seulement")
	var client_uid: String = client_drop.weapon.uid
	MpHelpers.signal_peer("drops")

	# 2. Le client sur l'arme de l'hôte : sa demande est refusée.
	if not await MpHelpers.wait_peer(self, "near_host_drop", 30.0):
		return
	var cp: Player = game.players[cid]
	var near: bool = await until(func(): return InteractionSystem.in_reach(cp.srv_origin(), host_drop.srv_point(), host_drop.interact_range), 10.0, "client près de l'arme de l'hôte")
	at.check(near, "l'hôte voit le client sur son arme")
	MpHelpers.signal_peer("host_sees")
	if not await MpHelpers.wait_peer(self, "tried", 30.0):
		return
	at.check(loot.drops.has(host_drop.drop_id), "arme de l'hôte toujours au sol")
	at.check(cpd.bag.is_empty() and hpd.bag.is_empty(), "aucun inventaire changé")
	MpHelpers.signal_peer("checked")

	# 3. Le client ramasse SON arme, puis y installe une pièce.
	if not await MpHelpers.wait_peer(self, "picked", 30.0):
		return
	at.check(cpd.bag.size() == 1 and cpd.bag[0].uid == client_uid, "arme du client dans son inventaire")
	at.check(loot.drops.size() == 1 and loot.drops.has(host_drop.drop_id), "seule l'arme de l'hôte reste")
	if not await MpHelpers.wait_peer(self, "mounted", 30.0):
		return
	at.check(cpd.bag[0].parts.size() == 1, "pièce montée sur l'arme du client (validé ici)")
	game.evac.time_left = 0.1
	await MpHelpers.finish(self)
