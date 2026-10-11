extends AutotestScenario
## Choix de la carte (SOLO) au clavier dans l'onglet PARTIE du hub (lot E) :
## JOUER (hub) -> Q (onglet PARTIE, vue SOLO) : cartes du jeu (BUNKER K-7
## seule depuis le retrait de KINO), aperçu de la carte choisie ; un ancien
## choix mémorisé sur KINO retombe sur BUNKER K-7 ; Échap ouvre le menu du hub
## (rien n'est lancé) ; flèche gauche : la ligne de la carte, Entrée la lance
## et mémorise le choix (Settings).

var menu: MainMenu


func run() -> void:
	timeout_sec = 90
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 5.0, "menu principal")
	menu = tree().current_scene
	await until(_settled, 5.0, "sortie du noir d'ouverture du menu")
	at.check(Settings.last_map == "bunker_k7", "carte mémorisée par défaut : %s" % Settings.last_map)
	# Choix mémorisé sur la carte retirée : l'onglet se place sur BUNKER K-7.
	Settings.last_map = "kino"
	await press("ui_accept")  # JOUER : hub
	await until(_settled, 3.0, "hub affiché")
	await press("ui_page_up")  # onglet PARTIE
	at.check(menu.current_name == "hub" and menu.current.tab == "play", "hub, onglet PARTIE")
	var pp: HubPlayPanel = menu.current.panels.play
	at.check(pp.view == HubPlayPanel.SOLO, "vue SOLO")
	var game_maps := []
	for id in pp.map_rows:
		if not String(id).begins_with(EditorMapDef.CUSTOM_PREFIX):
			game_maps.append(id)
	at.check(game_maps == ["bunker_k7"], "cartes du jeu proposées : %s" % ", ".join(game_maps))
	at.check(pp.selected == "bunker_k7" and pp.map_rows.bunker_k7.selected, "ancien choix KINO : BUNKER K-7 choisie")
	at.check(pp.preview.texture != null and pp.map_title.text == "BUNKER K-7", "aperçu et plan du BUNKER K-7")
	at.check(_focused() == pp.launch_button, "focus sur LANCER LA PARTIE")
	await at.screenshot("bunker")
	# Échap : menu du hub, rien n'est lancé ; Échap le referme.
	await press("ui_cancel")
	at.check(menu.current.hub_menu.is_open() and menu._fade_amount < 0.01, "Échap : menu du hub, rien n'est lancé")
	await press("ui_cancel")
	at.check(not menu.current.hub_menu.is_open(), "Échap : menu fermé")
	await frames(3)
	await press("ui_left")
	at.check(_focused() == pp.map_rows.bunker_k7, "flèche gauche : ligne de BUNKER K-7")
	await press("ui_accept")  # carte déjà choisie : lancement
	await until(func(): return is_instance_valid(menu) and menu._fade_amount > 0.1, 2.0, "fondu au noir du lancement")
	at.check(tree().current_scene == menu and menu._fade_amount > 0.1, "fondu au noir avant le chargement")
	at.check(Settings.last_map == "bunker_k7", "choix mémorisé (Settings.last_map = %s)" % Settings.last_map)
	var cfg := ConfigFile.new()
	at.check(cfg.load(Settings.path) == OK and cfg.get_value("game", "last_map", "") == "bunker_k7", "choix enregistré dans %s" % Settings.path)
	var ok: bool = await until(func(): return Game.instance != null and Game.instance.local_player != null, 40.0, "partie lancée")
	if ok:
		at.check(Game.instance.map_def.id == "bunker_k7", "partie solo sur BUNKER K-7")
		await seconds(1.0)  # rendu posé avant la capture
		await at.screenshot("ingame")


## Écran courant entièrement affiché et plus aucun fondu au noir en cours.
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
