extends TestCase
## Changer d'arme pendant un rechargement (comme BO1) : le changement est
## accepté, le rechargement est annulé sur-le-champ, le chargeur n'est pas
## rempli et la réserve pas entamée (sauf cartouches déjà poussées au fusil à
## pompe), aucun remplissage différé ne tombe plus tard ; même calcul côté
## serveur (Combat). Touche et molette donnent le même changement.

const SAVED_KEYS := ["bindings", "pad_bindings", "using_pad"]

var _saved := {}


func before_each() -> void:
	# Événements injectés par un test précédent (Input.parse_input_event) et
	# pas encore lus : appliqués maintenant, avant la sauvegarde, et non au
	# milieu de ce test (indépendance de l'ordre des tests).
	Input.flush_buffered_events()
	for k in SAVED_KEYS:
		var v = Settings.get(k)
		_saved[k] = v.duplicate(true) if v is Dictionary else v


func after_each() -> void:
	for k in SAVED_KEYS:
		Settings.set(k, _saved[k])
	Settings.apply_bindings()


## Événements injectés ensemble hors image physique, puis attente de leur
## lecture. Input les met en mémoire tampon et ne les lit qu'au début de
## l'itération suivante du moteur ; après une image lente (machine chargée,
## série complète), le moteur rattrape plusieurs images physiques dans la
## MÊME itération : compter des images physiques juste après
## parse_input_event peut alors se faire sans que l'événement soit lu. Après
## process_frame, toute image physique suivante appartient à une itération
## qui les a déjà lus. Plusieurs événements (cran de molette : appui et
## relâche) sont lus dans la même image, comme ceux du pilote.
func _inject(events: Array) -> void:
	await host.get_tree().process_frame
	for ev in events:
		Input.parse_input_event(ev)
	await host.get_tree().process_frame


## Contrôleur seul (sans joueur ni réseau) tenant `ids`, emplacement 0.
func _wc(ids: Array, mag: int, reserve: int, pap := false) -> WeaponController:
	var wc := WeaponController.new()
	for id in ids:
		wc.weapons.append(WeaponDB.new_instance(id, pap))
	wc.weapons[0].mag = mag
	wc.weapons[0].reserve = reserve
	wc.slot = 0
	return wc


## Rechargement en cours depuis `elapsed` s sur `dur` s (comme _try_reload).
func _reloading(wc: WeaponController, elapsed: float, dur: float) -> void:
	var t := GameClock.now()
	wc._reload_start = t - elapsed
	wc._reload_dur = dur
	wc._reload_end = wc._reload_start + dur
	wc._reload_serial += 1


func test_switch_mid_reload_cancels_without_refill() -> void:
	var wc := _wc(["m1911", "mp40"], 2, 50)
	var dur := float(WeaponDB.stats("m1911").reload)
	_reloading(wc, dur * 0.5, dur)
	var serial := wc._reload_serial
	var t := GameClock.now()
	assert_true(wc.is_reloading())
	assert_true(wc.can_switch(t), "le rechargement n'empêche plus de changer d'arme")
	wc.request_switch(1)
	assert_false(wc.is_reloading(), "rechargement annulé tout de suite")
	assert_true(wc._reload_serial != serial, "sons de rechargement à venir abandonnés")
	assert_eq(int(wc.weapons[0].mag), 2, "chargeur non rempli")
	assert_eq(int(wc.weapons[0].reserve), 50, "réserve intacte")
	# Échéance du rechargement annulé dépassée : aucun remplissage différé.
	wc.update_reload(t + dur * 3.0)
	assert_eq(int(wc.weapons[0].mag), 2, "pas de remplissage différé")
	assert_eq(int(wc.weapons[0].reserve), 50)
	# Changement en attente du serveur : pas de second envoi, pas de tir.
	assert_false(wc.can_switch(t), "demande en cours : pas de seconde demande")
	assert_true(wc.can_switch(t + WeaponController.SWITCH_REQUEST_TIMEOUT + 0.01), "serveur muet : débloqué après le délai")
	# Le serveur applique le changement : la nouvelle arme est en main,
	# chargeur plein, sans rechargement ni remplissage hérité.
	wc.slot = 1
	var mp40: Dictionary = wc.current()
	var mag_before: int = mp40.mag
	var res_before: int = mp40.reserve
	wc.update_reload(t + dur * 3.0)
	assert_eq(String(mp40.id), "mp40", "nouvelle arme active")
	assert_eq(int(mp40.mag), mag_before, "la nouvelle arme ne reçoit pas le rechargement")
	assert_eq(int(mp40.reserve), res_before)
	assert_false(wc.is_reloading())
	wc.free()


func test_reload_finishes_normally_without_switch() -> void:
	var wc := _wc(["m1911", "mp40"], 2, 50)
	_reloading(wc, 0.1, 1.0)
	wc.update_reload(GameClock.now() + 2.0)
	assert_eq(int(wc.weapons[0].mag), 8, "rechargement mené à terme : chargeur plein")
	assert_eq(int(wc.weapons[0].reserve), 44)
	wc.free()


func test_other_locks_still_block_switch() -> void:
	var wc := _wc(["m1911", "mp40"], 8, 80)
	var t := GameClock.now()
	wc._switch_end = t + 0.3
	assert_false(wc.can_switch(t), "changement d'arme déjà en cours")
	wc._switch_end = -1.0
	wc._drink_end = t + 0.3
	assert_false(wc.can_switch(t), "boisson d'atout")
	wc._drink_end = -1.0
	wc._pickup_end = t + 0.3
	assert_false(wc.can_switch(t), "récupération du couteau")
	wc._pickup_end = -1.0
	assert_true(wc.can_switch(t))
	wc.free()


func test_shotgun_keeps_inserted_shells() -> void:
	var s := WeaponDB.stats("stakeout")
	var w := {"mag": 1, "reserve": 30}
	# 5 cartouches à pousser, de 12 % à 77 % de la durée.
	assert_eq(WeaponController.shells_loaded(s, w, 0.05), 0, "aucune encore poussée")
	assert_eq(WeaponController.shells_loaded(s, w, 0.12 + 0.65 * 0.4), 2, "deux poussées à mi-course")
	assert_eq(WeaponController.shells_loaded(s, w, 1.0), 5, "toutes à la fin")
	assert_eq(WeaponController.shells_loaded(s, {"mag": 1, "reserve": 2}, 1.0), 2, "bornées par la réserve")
	assert_eq(WeaponController.shells_loaded(WeaponDB.stats("m1911"), w, 0.9), 0, "chargeur : tout ou rien")
	var dur := float(s.reload)
	var wc := _wc(["stakeout", "m1911"], 1, 30)
	_reloading(wc, dur * (0.12 + 0.65 * 0.4), dur)
	wc.request_switch(1)
	assert_eq(int(wc.weapons[0].mag), 3, "les 2 cartouches poussées restent")
	assert_eq(int(wc.weapons[0].reserve), 28, "prises dans la réserve")
	wc.update_reload(GameClock.now() + dur * 3.0)
	assert_eq(int(wc.weapons[0].mag), 3, "pas de remplissage différé")
	wc.free()


func test_special_weapons_cancel_cleanly() -> void:
	# Ray Gun, TONNERRE-7, Pack-a-Punch, rechargement accéléré (Speed Cola :
	# durée réduite) : annulation identique, munitions intactes.
	for c in [["ray", false], ["ray", true], ["thunder", false], ["mp40", true], ["hk21", false], ["olympia", false], ["python", false]]:
		assert_true(WeaponDB.WEAPONS.has(c[0]), c[0])
		var wc := _wc([c[0], "m1911"], 1, 20, c[1])
		var dur := float(WeaponDB.stats(c[0], c[1]).reload) * 0.5
		_reloading(wc, dur * 0.6, dur)
		wc.request_switch(1)
		wc.update_reload(GameClock.now() + 10.0)
		assert_eq([int(wc.weapons[0].mag), int(wc.weapons[0].reserve)], [1, 20], "%s : munitions inchangées" % c[0])
		wc.free()


func test_key_and_wheel_request_switch() -> void:
	Settings.using_pad = false
	Settings.reset_bindings()
	var tree := host.get_tree()
	var inp := PlayerInput.new()
	var wc := _wc(["m1911", "mp40"], 2, 50)
	var switches := [0]
	var read := func():
		inp.read_devices(1.0 / 60.0)
		if inp.switch_weapon and wc.can_switch(GameClock.now()):
			wc.request_switch(1)
			switches[0] += 1
		inp.clear_edges()
	tree.physics_frame.connect(read)
	# Touche (1 par défaut).
	_reloading(wc, 0.4, 1.6)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_1
	key.pressed = true
	await _inject([key])
	for i in 4:
		await tree.physics_frame
	var up := key.duplicate() as InputEventKey
	up.pressed = false
	await _inject([up])
	assert_eq(switches[0], 1, "touche : changement demandé pendant le rechargement")
	assert_false(wc.is_reloading(), "touche : rechargement annulé")
	assert_eq([int(wc.weapons[0].mag), int(wc.weapons[0].reserve)], [2, 50])
	# Molette haut (cran : appui et relâche dans la même image).
	wc._switch_req_end = -1.0
	_reloading(wc, 0.4, 1.6)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_WHEEL_UP
	ev.pressed = true
	ev.factor = 1.0
	var rel := ev.duplicate() as InputEventMouseButton
	rel.pressed = false
	await _inject([ev, rel])
	for i in 4:
		await tree.physics_frame
	tree.physics_frame.disconnect(read)
	assert_eq(switches[0], 2, "molette : changement demandé pendant le rechargement")
	assert_false(wc.is_reloading(), "molette : rechargement annulé")
	assert_eq([int(wc.weapons[0].mag), int(wc.weapons[0].reserve)], [2, 50])
	wc.free()


func test_server_cancel_matches_client() -> void:
	var s := Session.new()
	host.add_child(s)
	var pd := s.create(1)
	pd.weapons = [WeaponDB.new_instance("stakeout"), WeaponDB.new_instance("m1911")]
	pd.weapons[0].mag = 1
	pd.weapons[0].reserve = 30
	pd.slot = 0
	var syncs := [0]
	s.inventory_changed.connect(func(_pid): syncs[0] += 1)
	var combat := Combat.new()
	combat.session = s
	var dur := float(WeaponDB.stats("stakeout").reload)
	var t := GameClock.now()
	# Couteau / grenade à mi-course : 2 cartouches gardées, inventaire renvoyé.
	combat._reload_end[1] = [0, t + dur * Combat.RELOAD_LENIENCY, t - dur * (0.12 + 0.65 * 0.4), dur]
	combat.cancel_reload(1, true)
	assert_false(combat.is_reloading(1))
	assert_eq([int(pd.weapons[0].mag), int(pd.weapons[0].reserve)], [3, 28], "cartouches poussées gardées (serveur)")
	assert_eq(syncs[0], 1, "inventaire resynchronisé")
	# Changement d'arme (srv_switch) : même calcul, emplacement vérifié.
	combat._reload_end[1] = [0, t + dur, t - dur * 0.05, dur]
	assert_false(combat._keep_loaded_shells(1, combat._reload_end[1]), "aucune cartouche encore poussée")
	assert_false(combat._keep_loaded_shells(1, [1, t + dur, t - dur * 0.5, dur]), "autre emplacement : rien")
	# Annulation par un achat, etc. : rien ne bouge.
	combat.cancel_reload(1)
	assert_eq([int(pd.weapons[0].mag), int(pd.weapons[0].reserve)], [3, 28])
	# Arme à chargeur : jamais de munitions pendant l'annulation.
	pd.slot = 1
	pd.weapons[1].mag = 2
	var res: int = pd.weapons[1].reserve
	assert_false(combat._keep_loaded_shells(1, [1, t + 1.0, t - 1.5, 1.6]))
	assert_eq([int(pd.weapons[1].mag), int(pd.weapons[1].reserve)], [2, res], "M1911 : chargeur inchangé")
	combat.free()
	s.queue_free()


## Coup par coup : chaque son « shell_in » tombe à l'instant où le compte des
## cartouches gardées augmente (client, serveur, animation : même règle), y
## compris au-delà de SHELL_MAX_STEPS poussées (plusieurs cartouches par son).
func test_shell_sounds_match_count() -> void:
	for c in [["stakeout", false, 1, 30], ["stakeout", false, 5, 30], ["stakeout", true, 0, 60],
			["spas12", true, 2, 120], ["china_lake", false, 0, 20], ["stakeout", false, 1, 2]]:
		var s := WeaponDB.stats(c[0], c[1])
		var w := {"mag": c[2], "reserve": c[3]}
		var need := WeaponController.shells_needed(s, w)
		var sounds: Array = WeaponController.reload_sounds(s, w).filter(func(x): return x[1] == "shell_in")
		var label := "%s%s %d/%d" % [c[0], " PaP" if c[1] else "", c[2], c[3]]
		assert_eq(sounds.size(), mini(need, WeaponController.SHELL_MAX_STEPS), label + " : une poussée par son")
		var prev := 0
		for j in sounds.size():
			var at: float = sounds[j][0]
			var before := WeaponController.shells_loaded(s, w, at - 0.001)
			var after := WeaponController.shells_loaded(s, w, at + 0.001)
			assert_eq(before, prev, "%s : rien de plus juste avant le son %d" % [label, j])
			assert_true(after > before, "%s : le son %d insère (%d -> %d)" % [label, j, before, after])
			prev = after
		assert_eq(WeaponController.shells_loaded(s, w, 0.999), need, label + " : toutes après le dernier son")
	# Avant le premier son : aucune.
	var st := WeaponDB.stats("stakeout")
	var first: float = WeaponController.reload_sounds(st, {"mag": 1, "reserve": 30})[0][0]
	assert_eq(WeaponController.shells_loaded(st, {"mag": 1, "reserve": 30}, first - 0.01), 0, "pas de cartouche avant son premier son")


## Rechargement annulé par le serveur sans changement d'arme (achat de
## munitions, mise à terre, bonus) : la prédiction s'arrête, aucun
## remplissage à l'échéance.
func test_server_cancel_stops_client_prediction() -> void:
	var wc := _wc(["m1911", "mp40"], 2, 50)
	var dur := float(WeaponDB.stats("m1911").reload)
	_reloading(wc, dur * 0.3, dur)
	var serial := wc._reload_serial
	wc.server_cancelled_reload()
	assert_false(wc.is_reloading(), "rechargement arrêté")
	assert_true(wc._reload_serial != serial, "sons à venir abandonnés")
	wc.update_reload(GameClock.now() + dur * 3.0)
	assert_eq([int(wc.weapons[0].mag), int(wc.weapons[0].reserve)], [2, 50], "pas de remplissage local")
	wc.server_cancelled_reload()  # sans rechargement : sans effet
	assert_false(wc.is_reloading())
	wc.free()


## Combat qui note les annulations envoyées au client au lieu de les envoyer.
class NotifyingCombat extends Combat:
	var sent: Array[int] = []

	func _notify_reload_cancelled(pid: int) -> void:
		sent.append(pid)


func test_server_cancel_notifies_client() -> void:
	var s := Session.new()
	host.add_child(s)
	var pd := s.create(1)
	pd.weapons = [WeaponDB.new_instance("mp40")]
	pd.weapons[0].mag = 3
	pd.slot = 0
	var combat := NotifyingCombat.new()
	combat.session = s
	var t := GameClock.now()
	# Annulation décidée par le serveur (achat, mise à terre...) : prévenu.
	combat._reload_end[1] = [0, t + 2.0, t, 2.0]
	combat.cancel_reload(1)
	assert_eq(combat.sent, [1] as Array[int], "achat / mise à terre : client prévenu")
	# Sans rechargement en cours : rien à annuler, aucun message.
	combat.cancel_reload(1)
	assert_eq(combat.sent.size(), 1, "rien à annuler : aucun message")
	# Interruption par le joueur (couteau, grenade) : il l'a déjà arrêtée.
	combat._reload_end[1] = [0, t + 2.0, t, 2.0]
	combat.cancel_reload(1, true)
	assert_eq(combat.sent.size(), 1, "couteau / grenade : pas de message")
	combat.free()
	s.queue_free()
