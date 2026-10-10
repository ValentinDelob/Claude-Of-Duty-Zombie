extends AutotestScenario
## Actions du serveur qui interrompent l'arme pendant un rechargement (BO1) :
## mise à terre ; et un objet de la caisse au hasard, qui, lui, ne l'interrompt
## pas. Mise à terre : rechargement
## annulé côté serveur ET client (prévenu), rien rempli à l'échéance, client
## et serveur d'accord sur les munitions.

var H := AutotestHelpers
var game: Game
var p: Player
var pd: PlayerData
var wc: WeaponController


## Arme `ids[0]` en main, chargeur `mag0` / réserve `reserve0`.
func equip(ids: Array, mag0: int, reserve0: int) -> bool:
	pd.weapons = []
	for id in ids:
		pd.weapons.append(WeaponDB.new_instance(id))
	pd.weapons[0].mag = mag0
	pd.weapons[0].reserve = reserve0
	pd.slot = 0
	game.combat.cancel_reload(1)
	game.session.sync_inventory(1)
	var ok: bool = await until(func(): return wc.current().get("id", "") == ids[0] and int(wc.current().mag) == mag0, 2.0, "%s en main" % ids[0])
	await seconds(WeaponController.SWITCH_TIME + 0.2)
	return ok


## Lance un rechargement (client puis serveur) ; durée, ou -1 en cas d'échec.
func start_reload() -> float:
	p.input.reload = true
	var ok: bool = await until(func(): return wc.is_reloading() and game.combat.is_reloading(1), 1.0, "rechargement en cours")
	if not ok:
		return -1.0
	await seconds(0.2)
	return game.combat.reload_time(1, pd.current_weapon())


func stopped(label: String) -> void:
	await frames(3)
	at.check(not game.combat.is_reloading(1), "%s : rechargement serveur annulé" % label)
	at.check(not wc.is_reloading(), "%s : rechargement client annulé" % label)


## Munitions [chargeur, réserve] de l'arme `id` (client, serveur).
func ammo_of(id: String) -> Array:
	var c := []
	for w in wc.weapons:
		if w.id == id:
			c = [int(w.mag), int(w.reserve)]
	var s := []
	for w in pd.weapons:
		if w.id == id:
			s = [int(w.mag), int(w.reserve)]
	return [c, s]


## Au-delà de l'échéance du rechargement annulé : l'arme `id` vaut `expect`
## des deux côtés.
func unchanged(label: String, id: String, expect: Array, dur: float) -> void:
	await seconds(dur + 0.3)
	var a := ammo_of(id)
	at.check(a[0] == expect and a[1] == expect, "%s : %s inchangé (client %s, serveur %s)" % [label, id, a[0], a[1]])


func run() -> void:
	timeout_sec = 120
	p = await H.start_solo_game(self, "bunker_k7")
	if p == null:
		return
	game = Game.instance
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	pd = game.session.local_data()
	wc = p.weapons
	for id in game.doors:
		game.doors[id].srv_open()
	var power: Interactable = game.interact.get_obj("power")
	if power:
		(power as PowerSwitch).srv_use(1)
	game.session.add_points(1, 100000)
	await seconds(0.5)

	# 1. Caisse au hasard : l'objet pris va sur l'emplacement de grenade, il
	# n'interrompt pas le rechargement de l'arme.
	var box: MysteryBox = game.interact.get_obj("box")
	at.check(box != null, "caisse présente")
	if box:
		await equip(["m1911"], 5, 80)
		box.force_result = "decoy"
		box.srv_use(1)
		var ok: bool = await until(func(): return box.state == MysteryBox.State.READY, MysteryBox.ROLL_TIME + 3.0, "tirage de la caisse")
		if ok:
			var dur := await start_reload()
			box.srv_use(1)
			await frames(3)
			at.check(pd.throwable == ThrowableRules.Kind.DECOY and pd.grenades == ThrowableRules.SLOT_MAX, "peluches sur l'emplacement de grenade")
			at.check(game.combat.is_reloading(1) and wc.is_reloading(), "rechargement poursuivi")
			await seconds(dur + 0.3)
			var a := ammo_of("m1911")
			at.check(a[0] == a[1] and int(a[0][0]) == int(WeaponDB.stats("m1911").mag), "rechargement terminé des deux côtés (%s)" % str(a))

	# 2. Mise à terre pendant le rechargement (auto-réanimation de test : on
	# reste en partie en solo).
	game.downed.solo_self_revive = true
	await equip(["m1911", "mp40"], 5, 80)
	var d2 := await start_reload()
	game.combat.debug_invulnerable = false
	game.combat.damage_player(1, 500, p.global_position + Vector3(1, 1, 0))
	game.combat.debug_invulnerable = true
	await until(func(): return pd.life == PlayerData.Life.DOWNED, 2.0, "joueur à terre")
	await stopped("mise à terre")
	await unchanged("mise à terre", "m1911", [5, 80], d2)


