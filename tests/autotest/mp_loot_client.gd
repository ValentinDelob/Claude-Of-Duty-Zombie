extends AutotestScenario
## [MP] Client : butin personnel (GAME_CONCEPT §4.7). Voit les deux armes au
## sol (la sienne avec son invite, celle de l'hôte sans), reçoit ses propres
## échantillons et sa pièce, ne peut pas ramasser l'arme de l'hôte (refus du
## serveur, message), ramasse la sienne avec [F] et y installe une pièce
## depuis son panneau d'inventaire.

const PORT := 17921

var H := AutotestHelpers


func run() -> void:
	timeout_sec = 150
	if not await MpHelpers.join_game(self, PORT):
		return
	var game := Game.instance
	var p := game.local_player
	p.bot_controlled = true
	var me := game.multiplayer.get_unique_id()
	var pd := game.session.local_data()
	var loot := game.loot

	if not await MpHelpers.wait_peer(self, "drops", 60.0):
		return
	await until(func(): return loot.drops.size() == 2 and not loot.my_parts.is_empty(), 5.0, "armes et butin reçus")
	var mine: LootDrop = null
	var host_drop: LootDrop = null
	for d: LootDrop in loot.drops.values():
		if d.owner_pid == me:
			mine = d
		else:
			host_drop = d
	at.check(mine != null and host_drop != null, "deux armes au sol, dont la mienne")
	if mine == null or host_drop == null:
		return
	at.check(mine.prompt(me) != "" and host_drop.prompt(me) == "", "invite seulement sur mon arme")
	# Mêmes arcs que l'hôte (départ, arrivée, graine) : même trajectoire.
	var arcs: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MpHelpers.sync_dir().path_join("loot_arcs.json")))
	for d: LootDrop in loot.drops.values():
		var a: Array = arcs.get(str(d.drop_id), ["", ""])
		var same: bool = a[0] != "" and (str_to_var(a[0]) as Vector3).is_equal_approx(d.from) \
				and (str_to_var(a[1]) as Vector3).is_equal_approx(d.global_position)
		at.check(same, "arc de l'arme %d identique à l'hôte" % d.drop_id)
		var ref := LootArc.plan(str_to_var(a[0]), str_to_var(a[1]), d.drop_id) if same else {}
		at.check(same and LootArc.position(ref, 0.3).is_equal_approx(LootArc.position(d.arc, 0.3)), "même position en vol")
	# Mes pièces et échantillons ont jailli ici (objets visibles, à moi seul).
	at.check(not loot.pickups.is_empty(), "objets jaillis reçus (%d)" % loot.pickups.size())
	at.check(not loot.my_samples.is_empty() and loot.counter_shown() != "", "mes échantillons : « %s »" % loot.counter_shown())

	# 1. Debout sur l'arme de l'hôte : demande envoyée quand même -> refus.
	# Du côté du corps d'où elle a jailli (toujours dégagé).
	var to_corpse := host_drop.from - host_drop.global_position
	to_corpse.y = 0.0
	to_corpse = to_corpse.normalized() if to_corpse.length() > 0.05 else Vector3.BACK
	p.teleport_to(host_drop.global_position + to_corpse * 1.3 + Vector3(0, 0.05, 0))
	await seconds(0.5)
	# Visée refaite à chaque essai (la téléportation peut arriver une image après).
	var seen: bool = await until(func():
		H.aim_at(p, host_drop.card_point())
		return loot.looked == host_drop and loot.card_shown(), 4.0, "fiche de l'arme de l'hôte")
	at.check(seen and loot.card.info.get("key", "x") == "" and String(loot.card.info.get("action", "")).contains(Net.player_name(1).to_upper()),
			"fiche de l'arme de l'hôte : « %s », sans touche" % loot.card.info.get("action", "") if loot.card else "")
	p.teleport_to(host_drop.global_position + Vector3(0.6, 0.05, 0))
	MpHelpers.signal_peer("near_host_drop")
	if not await MpHelpers.wait_peer(self, "host_sees", 30.0):
		return
	game.interact.srv_interact.rpc_id(1, host_drop.interact_id)
	var refused := LootSystem.msg_text(LootSystem.MSG_NOT_YOURS, Net.player_name(1))
	var ok: bool = await until(func(): return game.hud._flash.text == refused, 5.0, "refus du serveur")
	at.check(ok, "refus : « %s »" % game.hud._flash.text)
	at.check(loot.drops.has(host_drop.drop_id) and pd.bag.is_empty(), "l'arme de l'hôte reste, mon inventaire est vide")
	MpHelpers.signal_peer("tried")
	if not await MpHelpers.wait_peer(self, "checked", 30.0):
		return

	# 2. Ma propre arme : [F] (renvoyé tant que le serveur, qui juge sur une
	# position en retard, ne l'a pas acceptée).
	var my_id := mine.drop_id
	p.teleport_to(mine.global_position + Vector3(0, 0.05, 1.2))
	await seconds(0.5)
	H.aim_at(p, mine.interact_point())
	await until(func(): return game.interact.focused == mine, 3.0, "mon arme visée")
	# Fiche de mon arme : la mienne (touche), avec ses statistiques.
	ok = await until(func(): return loot.looked == mine and loot.card_shown(), 3.0, "fiche de mon arme")
	at.check(ok and loot.card.info.get("key", "") != "" and (loot.card.info.get("stats", []) as Array).size() == 6,
			"fiche de mon arme : touche et statistiques")
	ok = await until(func():
		if loot.drops.has(my_id) and game.interact.focused == mine:
			p.input.interact_pressed = true
		return not loot.drops.has(my_id) and pd.bag.size() == 1, 10.0, "mon arme ramassée")
	at.check(ok, "mon arme ramassée dans mon inventaire")
	MpHelpers.signal_peer("picked")

	# 3. Pièce installée depuis le panneau d'inventaire.
	var inv := game.hud.inventory
	inv.open()
	inv.press(InventoryPanel.ROW_PARTS, 0)
	inv.press(InventoryPanel.ROW_BAG, 0)
	ok = await until(func(): return pd.bag.size() == 1 and pd.bag[0].parts.size() == 1, 5.0, "pièce montée")
	at.check(ok, "pièce montée sur mon arme")
	inv.close()
	MpHelpers.signal_peer("mounted")
	await MpHelpers.finish(self)
