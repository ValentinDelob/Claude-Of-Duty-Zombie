extends AutotestScenario
## @rendu : onglet PARTIE du hub (docs/HUB_PLAN.md lot E, maquette écrans 9
## et 10) et boucle complète hub -> partie -> hub en solo :
##   - SOLO : cartes, aperçu, armes de départ, contrats « sur cette carte »,
##     au clavier (Q, flèches) ; COOP : héberger / rejoindre ; SALON de
##     l'hôte dans l'onglet (joueurs de démonstration : niveau, armes de
##     départ, EN RETOUR…), DÉMARRER grisé avec la raison, CHANGER DE CARTE,
##     changer d'onglet sans quitter le salon ; FR puis EN ;
##   - LANCER LA PARTIE (BUNKER K-7) -> échantillon reçu : message « objectif
##     atteint » une seule fois (ContractWatch) -> évacuation -> écran de fin
##     -> retour au hub, onglet LABO, « dernière partie », tableau des
##     contrats tourné.
## Captures pendant le développement (comparaison avec la maquette), suffixe
## = hauteur de la fenêtre (720, 1080). HUB_SHOT_RES=1920x1080 : fenêtre à
## cette taille.

var PORT := 17978 + MpHelpers.port_offset()
var menu: MainMenu
var hub: HubScreen


## Profil de la maquette (écran 9) : niveau 7, 7 crocs / 2 touffes / 5
## colliers ; Analyse complète (il manque 1 touffe), Urgence au labo (3
## colliers, daté), Dents de lait (prête).
static func demo_profile() -> PlayerProfile:
	var pr := PlayerProfile.new()
	pr.xp = PlayerProfile.xp_for_level(7) + 2140
	pr.add_samples("dog_fang", 7)
	pr.add_samples("dog_fur", 2)
	pr.add_samples("dog_collar", 5)
	var st := pr.contracts
	st.draw_seed = 918273
	st.rotation = 3
	st.done = {"first_sample": 1, "dog_fangs_small": 2, "dog_collars": 1}
	st.active.append({"id": "pack_analysis", "accepted": 1})
	st.active.append({"id": "lab_emergency", "accepted": 2})
	st.active.append({"id": "dog_fangs_small", "accepted": 3})
	st.offers.append({"id": "dog_fur_coat", "since": 2})
	st.offers.append({"id": "dog_collars", "since": 3})
	return pr


func run() -> void:
	timeout_sec = 240
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 5.0, "menu principal")
	menu = tree().current_scene
	var res := OS.get_environment("HUB_SHOT_RES")
	if res != "" and DisplayServer.get_name() != "headless":
		var p := res.split("x")
		if p.size() == 2:
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
			DisplayServer.window_set_size(Vector2i(int(p[0]), int(p[1])))
			await frames(3)
	await until(_settled, 5.0, "menu titre affiché")
	ProfileStore.save_profile(demo_profile())
	HubContractsView.day_override = HubData.parse_day("2026-11-18")
	await press("ui_accept")  # JOUER
	await until(_settled, 3.0, "hub affiché")
	hub = menu.current
	await key(KEY_Q)  # LABO -> PARTIE (en boucle)
	at.check(hub.tab == "play", "Q : onglet PARTIE (%s)" % hub.tab)
	var pp: HubPlayPanel = hub.panels.play
	at.check(pp.view == HubPlayPanel.SOLO and pp.selected == "bunker_k7", "SOLO, BUNKER K-7 choisie")
	at.check(_focused() == pp.launch_button, "focus sur LANCER LA PARTIE")
	await seconds(0.4)
	await shot("solo")
	# Flèche gauche : la ligne de la carte (focus), Échap -> menu, Échap.
	await press("ui_left")
	at.check(_focused() is HubPlayView.MapRow, "flèche gauche : liste des cartes")
	await press("ui_right")
	at.check(_focused() == pp.launch_button, "flèche droite : LANCER")
	await _coop_and_lobby("fr")
	Settings.language = "en"
	await _coop_and_lobby("en")
	Settings.language = "fr"
	await _solo_loop()
	HubContractsView.day_override = -1
	ProfileStore.reset()


## COOP (héberger / rejoindre), puis SALON de l'hôte avec des joueurs de
## démonstration ; quitte le salon à la fin.
func _coop_and_lobby(lang: String) -> void:
	HubPlayPanel.last_view = HubPlayPanel.SOLO
	menu.show_screen("hub", {"tab": "play"})
	await until(_settled, 3.0, "hub (%s)" % lang)
	hub = menu.current
	var pp: HubPlayPanel = hub.panels.play
	if lang == "en":
		await seconds(0.3)
		await shot("solo_en")
	pp.coop_button.grab_focus()
	await press("ui_accept")
	at.check(pp.view == HubPlayPanel.COOP, "COOP : héberger / rejoindre")
	await seconds(0.3)
	await shot("coop_%s" % lang)
	pp.host_port_edit.text = str(PORT)
	pp.name_edit.text = "Valentin"
	pp.host_button.pressed.emit()
	await frames(3)
	at.check(Net.mode == Net.Mode.HOST and pp.view == HubPlayPanel.LOBBY, "HÉBERGER : salon dans l'onglet")
	# Joueurs de démonstration (maquette écran 10) : registre de l'hôte.
	Net.players[2] = {"name": "Jojo_42", "slot": 1, "lvl": 12, "start": PackedStringArray(["m1911"])}
	Net.players[3] = {"name": "Marie", "slot": 2, "lvl": 3, "start": PackedStringArray(["m1911", "bat"]), "away": true}
	Net.lobby_return.away = {3: true}
	Router.lobby_message = Lang.t("Dernière partie : manche 14, 402 zombies abattus", "Last game: round 14, 402 zombies killed")
	menu.show_screen("hub", {"tab": "play"})
	await until(_settled, 3.0, "salon réaffiché")
	hub = menu.current
	pp = hub.panels.play
	var lobby := pp.lobby
	at.check(lobby != null and lobby.player_rows.size() == 3, "3 joueurs au salon")
	at.check(lobby.start_button.disabled and lobby.start_button.label.contains("MARIE"), "DÉMARRER grisé : %s" % lobby.start_button.label)
	at.check(lobby.player_lines[2].contains(Lang.t("EN RETOUR", "COMING BACK")), "Marie : EN RETOUR… (%s)" % lobby.player_lines[2])
	await seconds(0.4)
	await shot("lobby_%s" % lang)
	# Changer d'onglet : le salon reste ouvert.
	await key(KEY_E)
	at.check(hub.tab == "lab" and Net.mode == Net.Mode.HOST, "E : LABO, toujours hébergé")
	await key(KEY_Q)
	at.check(hub.tab == "play" and pp.view == HubPlayPanel.LOBBY, "Q : retour au salon")
	# CHANGER DE CARTE : liste, Échap ferme.
	lobby.change_button.pressed.emit()
	await frames(3)
	at.check(lobby.picker != null and lobby.picker_rows.has("bunker_k7"), "liste des cartes ouverte")
	await seconds(0.3)
	await shot("lobby_maps_%s" % lang)
	await press("ui_cancel")
	at.check(lobby.picker == null and not hub.hub_menu.is_open(), "Échap : liste fermée")
	Net.lobby_return.away = {}
	Router.lobby_message = ""
	pp.leave_lobby()
	at.check(Net.mode == Net.Mode.NONE and pp.view == HubPlayPanel.COOP, "salon quitté : vue COOP")
	HubPlayPanel.last_view = HubPlayPanel.SOLO


## Boucle solo : LANCER -> message « objectif atteint » -> évacuation -> hub.
func _solo_loop() -> void:
	menu.show_screen("hub", {"tab": "play"})
	await until(_settled, 3.0, "hub")
	hub = menu.current
	var pp: HubPlayPanel = hub.panels.play
	at.check(pp.view == HubPlayPanel.SOLO, "vue SOLO")
	var rotation_before := ProfileStore.load_profile().contracts.rotation
	pp.launch_button.grab_focus()
	await press("ui_accept")
	var ok: bool = await until(func(): return Game.instance != null and Game.instance.local_player != null, 60.0, "partie lancée")
	if not ok:
		return
	var game := Game.instance
	at.check(game.map_def.id == "bunker_k7", "partie solo sur BUNKER K-7")
	game.rounds.paused = true
	game.local_player.bot_controlled = true
	var w := game.contract_watch
	at.check(w != null and w.announced.has("dog_fangs_small"), "contrat déjà prêt au départ : pas de message")
	# Une touffe tombe : Analyse complète couverte (2 + 1 = 3).
	game.loot._cl_loot([], {"dog_fur": 1})  # comme un échantillon reçu du serveur
	await frames(2)
	at.check(w.shown.size() == 1 and w.shown[0].contains("Analyse complète"), "message : %s" % (w.shown[0] if not w.shown.is_empty() else "aucun"))
	at.check(w.current_text().contains("OBJECTIF ATTEINT"), "message affiché : %s" % w.current_text())
	await seconds(1.2)
	await shot("ingame_goal")
	game.loot._cl_loot([], {"dog_fur": 2})
	at.check(w.shown.size() == 1, "une seule fois par contrat")
	# Anglais (même partie : texte du prochain message).
	Settings.language = "en"
	game.loot._cl_loot([], {"dog_fur": 2, "dog_collar": 3})
	at.check(w.shown.size() == 2 and w.shown[1].contains("GOAL REACHED"), "message EN : %s" % (w.shown[1] if w.shown.size() > 1 else "aucun"))
	await seconds(7.5)  # le premier message s'efface, le second s'affiche
	await seconds(1.0)
	await shot("ingame_goal_en")
	Settings.language = "fr"
	# Manche 3 (2 manches survécues : le tableau tourne), puis évacuation.
	game.rounds.debug_jump_to(3)
	await seconds(0.5)
	game.srv_end_match(true)
	ok = await until(func(): return tree().current_scene is MainMenu and (tree().current_scene as MainMenu).current_name == "hub",
			Game.GAME_OVER_DELAY + 15.0, "retour au hub après l'écran de fin")
	if not ok:
		return
	menu = tree().current_scene
	await until(_settled, 4.0, "hub affiché")
	hub = menu.current
	at.check(hub.tab == "lab", "retour sur l'onglet LABO (%s)" % hub.tab)
	at.check(not Router.last_match.is_empty() and Router.last_match.result.evacuated, "dernière partie : évacuation")
	var pr := ProfileStore.load_profile()
	at.check(pr.contracts.rotation == rotation_before + 1, "tableau des contrats tourné (%d -> %d)" % [rotation_before, pr.contracts.rotation])
	at.check(pr.sample_count("dog_fur") == 4 and pr.sample_count("dog_collar") == 8, "échantillons rapportés (touffes %d, colliers %d)" % [pr.sample_count("dog_fur"), pr.sample_count("dog_collar")])
	await seconds(0.4)
	await shot("lab_after_match")


func shot(n: String) -> void:
	await at.screenshot("%s_%d" % [n, DisplayServer.window_get_size().y])


func _settled() -> bool:
	return is_instance_valid(menu) and menu.current != null and menu.current.modulate.a >= 0.999 \
		and menu._fade_amount < 0.001


func _focused() -> Control:
	return at.get_viewport().gui_get_focus_owner()


func press(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	await frames(2)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)
	await frames(3)


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
