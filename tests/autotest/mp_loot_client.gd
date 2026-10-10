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
	at.check(not loot.my_samples.is_empty() and loot.counter_shown() != "", "mes échantillons : « %s »" % loot.counter_shown())

	# 1. Debout sur l'arme de l'hôte : demande envoyée quand même -> refus.
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
