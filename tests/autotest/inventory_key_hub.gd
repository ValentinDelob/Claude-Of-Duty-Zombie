extends AutotestScenario
## Inventaire de partie après le vrai chemin du hub, entrées comme les envoie
## l'OS (InputEventKey physique + keycode, bouton de manette) :
## menu titre JOUER (Entrée) -> hub (LABO) -> START (écran JOUER) -> LANCER
## (Entrée sur le bouton) -> partie ; arme au sol ramassée ([F]) : message
## avec la touche d'inventaire ; [I] ouvre le panneau, l'arme de l'inventaire
## choisie deux fois s'équipe (place libre en main, devient l'arme tenue),
## [I] referme ; croix haut ouvre, et referme MÊME quand une case de
## l'inventaire a le focus (avant : « ui_up » avalé par la navigation du
## focus, le focus remontait d'une rangée) ; [I] referme la station ; touche
## réaffectée (OPTIONS) : la nouvelle ouvre, l'ancienne plus, invites à jour.

var menu: MainMenu


func run() -> void:
	timeout_sec = 120
	ProfileStore.reset()
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 5.0, "menu principal")
	menu = tree().current_scene
	await until(_settled, 6.0, "menu titre affiché")
	await key(KEY_ENTER)
	if not await until(func(): return menu.current is Hub2Screen and _settled(), 5.0, "JOUER : le hub"):
		return
	var hub: Hub2Screen = menu.current
	await pad(JOY_BUTTON_START)
	if not await until(func(): return hub.current_id == "play" and hub.panels.get("play") != null, 3.0, "START : écran JOUER"):
		return
	var pp = hub.panels.get("play")
	if not await until(func(): return pp.launch_button != null and pp.selected != "", 3.0, "LANCER prêt"):
		return
	pp.launch_button.grab_focus()
	await frames(2)
	await key(KEY_ENTER)
	if not await until(func(): return Game.instance != null and Game.instance.local_player != null, 20.0, "LANCER : partie"):
		return
	var game := Game.instance
	if not await until(func(): return GameState.state == GameState.State.PLAYING, 10.0, "en jeu"):
		return
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	at.check(not is_instance_valid(menu), "menu (et hub) libérés pendant la partie")
	at.check(at.get_viewport().gui_get_focus_owner() == null, "aucun contrôle n'a le focus en partie")
	var pd := game.session.local_data()
	var p := game.local_player
	var inv := game.hud.inventory

	# 1. Arme au sol ramassée ([F] : sans souris capturée, la lecture des
	# commandes du joueur passe par le bot) : dans l'inventaire, message avec
	# la touche d'inventaire.
	var hands0 := pd.weapons.size()
	at.check(hands0 < 3, "une place libre en main (%d armes)" % hands0)
	var did := game.loot.srv_drop(1, GameWeapon.make("mp40", 1, OwnedWeapon.Rarity.COMMON, [], "loot:1"))
	await frames(3)
	var d: LootDrop = game.loot.drops.get(did)
	AutotestHelpers.aim_at(p, d.interact_point())
	if not await until(func(): return game.interact.focused == d, 2.0, "arme visée"):
		return
	p.bot_controlled = true
	p.input.interact_pressed = true
	if not await until(func(): return game.loot.drops.is_empty(), 2.0, "arme ramassée"):
		return
	p.bot_controlled = false
	at.check(pd.bag.size() == 1 and pd.bag[0].uid == "loot:1", "arme dans l'inventaire")
	at.check(game.hud._flash.text.contains(Settings.action_label("inventory")) and Settings.action_label("inventory") == "I",
			"message avec la touche : « %s »" % game.hud._flash.text)

	# 2. [I] ouvre ; l'arme choisie deux fois s'équipe et devient l'arme tenue.
	await key(KEY_I)
	at.check(inv.visible, "[I] : inventaire ouvert")
	at.check(" ".join(inv.prompts.describe()).contains("I FERMER"), "invites du panneau : %s" % [inv.prompts.describe()])
	inv.press(InventoryPanel.ROW_BAG, 0)
	inv.press(InventoryPanel.ROW_BAG, 0)
	await until(func(): return pd.weapons.size() == hands0 + 1 and pd.slot == hands0, 2.0, "arme équipée et tenue")
	at.check(pd.bag.is_empty() and pd.weapons[hands0].uid == "loot:1", "arme ramassée équipée (en main %d)" % pd.weapons.size())
	at.check(pd.slot == hands0, "arme ramassée tenue (emplacement %d)" % pd.slot)
	await key(KEY_I)
	at.check(not inv.visible, "[I] : inventaire fermé")

	# 3. Manette : croix haut ouvre ; focus sur une case de l'inventaire, croix
	# haut referme quand même.
	await pad(JOY_BUTTON_DPAD_UP)
	at.check(inv.visible, "croix haut : inventaire ouvert")
	inv.bag_buttons[1].grab_focus()
	await frames(2)
	await pad(JOY_BUTTON_DPAD_UP)
	at.check(not inv.visible, "croix haut (focus sur l'inventaire) : fermé")
	await pad(JOY_BUTTON_DPAD_UP)
	at.check(inv.visible, "croix haut : rouvert")
	# X : recyclage de l'arme montrée, premier appui = confirmation demandée.
	var hands_n := pd.weapons.size()
	await pad(JOY_BUTTON_X)
	at.check(inv._recycle_armed and inv.recycle_label.text == Lang.t("Confirmer le recyclage", "Confirm recycling"),
			"X : confirmation du recyclage (%s)" % inv.recycle_label.text)
	at.check(pd.weapons.size() == hands_n, "X une fois : rien de recyclé")
	# Tab (PIÈCES au clavier) tenu : pas de tableau des scores par-dessus.
	var tab := InputEventKey.new()
	tab.physical_keycode = KEY_TAB
	tab.keycode = KEY_TAB
	tab.pressed = true
	Input.parse_input_event(tab)
	await frames(3)
	at.check(not game.hud.scoreboard.visible, "Tab tenu : pas de tableau des scores sous l'inventaire")
	var tab_up := tab.duplicate() as InputEventKey
	tab_up.pressed = false
	Input.parse_input_event(tab_up)
	await frames(2)
	await pad(JOY_BUTTON_B)
	at.check(not inv.visible, "B : fermé")

	# 4. Station de construction ouverte, focus sur un de ses boutons : [I] la ferme.
	if game.hud.station_panel and game.station:
		game.hud.station_panel.open(game.station)
		await frames(2)
		var f := at.get_viewport().gui_get_focus_owner()
		await pad(JOY_BUTTON_DPAD_UP)
		at.check(not game.hud.station_panel.visible, "croix haut : station fermée (focus %s)" % [f])
		at.check(not inv.visible, "…sans ouvrir l'inventaire")

	# 5. Réaffectation (OPTIONS) : K remplace I.
	Settings.bind("inventory", Settings.key_code(KEY_K))
	await key(KEY_I)
	at.check(not inv.visible, "touche réaffectée : I n'ouvre plus")
	await key(KEY_K)
	at.check(inv.visible, "touche réaffectée : K ouvre")
	at.check(" ".join(inv.prompts.describe()).contains("K FERMER"), "invite à jour : %s" % [inv.prompts.describe()])
	at.check(LootSystem.msg_text(LootSystem.MSG_PICKED, "MP40").contains("K"), "message de ramassage à jour")
	await key(KEY_K)
	at.check(not inv.visible, "K : fermé")
	Settings.reset_bindings()
	ProfileStore.reset()


func _settled() -> bool:
	return is_instance_valid(menu) and menu.current != null and menu.current.modulate.a >= 0.999 \
		and menu._fade_amount < 0.001


## Touche comme l'OS l'envoie (physique et keycode).
func key(physical: int) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = physical as Key
	ev.keycode = physical as Key
	ev.pressed = true
	Input.parse_input_event(ev)
	await frames(2)
	var up := ev.duplicate() as InputEventKey
	up.pressed = false
	Input.parse_input_event(up)
	await frames(3)


func pad(button: int) -> void:
	var ev := InputEventJoypadButton.new()
	ev.device = 0
	ev.button_index = button as JoyButton
	ev.pressed = true
	Input.parse_input_event(ev)
	await frames(2)
	var up := ev.duplicate() as InputEventJoypadButton
	up.pressed = false
	Input.parse_input_event(up)
	await frames(3)
