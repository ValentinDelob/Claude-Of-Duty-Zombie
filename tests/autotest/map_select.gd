extends AutotestScenario
## Choix de la carte (SOLO) au clavier dans l'écran JOUER du hub :
## JOUER (menu titre : LABO) -> P (JOUER, vue SOLO) : cartes du jeu (BUNKER
## K-7 seule depuis le retrait de KINO), aperçu de la carte choisie ; un
## ancien choix mémorisé sur KINO retombe sur BUNKER K-7 ; Échap : retour au
## LABO (rien n'est lancé), Échap au LABO : menu du hub, Échap le referme ;
## P de nouveau : JOUER, focus sur la ligne de la carte, Entrée la lance et
## mémorise le choix (Settings).

var menu: MainMenu


func run() -> void:
	timeout_sec = 90
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 5.0, "menu principal")
	menu = tree().current_scene
	await until(_settled, 5.0, "sortie du noir d'ouverture du menu")
	at.check(Settings.last_map == "bunker_k7", "carte mémorisée par défaut : %s" % Settings.last_map)
	# Choix mémorisé sur la carte retirée : JOUER se place sur BUNKER K-7.
	Settings.last_map = "kino"
	await press("ui_accept")  # JOUER : hub, LABO
	await until(_settled, 3.0, "hub affiché")
	at.check(menu.current_name == "hub" and menu.current.current_id == "lab", "hub, LABO (%s)" % menu.current.current_id)
	await press_key(KEY_P)  # écran JOUER
	at.check(menu.current.current_id == "play", "P : écran JOUER (%s)" % menu.current.current_id)
	var pp: Hub2PlayPanel = menu.current.panels.play
	at.check(pp.view == Hub2PlayPanel.SOLO, "vue SOLO")
	var game_maps := []
	for id in pp.map_buttons:
		if not String(id).begins_with(EditorMapDef.CUSTOM_PREFIX):
			game_maps.append(id)
	at.check(game_maps == ["bunker_k7"], "cartes du jeu proposées : %s" % ", ".join(game_maps))
	at.check(pp.selected == "bunker_k7", "ancien choix KINO : BUNKER K-7 choisie (%s)" % pp.selected)
	at.check(pp.preview.texture != null and pp.preview_title.text.to_upper() == "BUNKER K-7",
			"aperçu du BUNKER K-7 (%s)" % pp.preview_title.text)
	await frames(2)
	at.check(_focused() == pp.map_buttons.bunker_k7, "focus sur la ligne de BUNKER K-7")
	# Échap : retour au LABO, rien n'est lancé ; au LABO, menu du hub.
	await press("ui_cancel")
	at.check(menu.current.current_id == "lab" and menu._fade_amount < 0.01, "Échap : LABO, rien n'est lancé")
	await press("ui_cancel")
	at.check(menu.current.hub_menu.is_open(), "Échap au LABO : menu du hub")
	await press("ui_cancel")
	at.check(not menu.current.hub_menu.is_open(), "Échap : menu fermé")
	await press_key(KEY_P)
	await frames(3)
	at.check(menu.current.current_id == "play" and _focused() == pp.map_buttons.bunker_k7, "P : JOUER, ligne de BUNKER K-7")
	await press("ui_accept")  # carte déjà choisie : lancement
	await until(func(): return is_instance_valid(menu) and menu._fade_amount > 0.1, 2.0, "fondu au noir du lancement")
	at.check(tree().current_scene == menu and menu._fade_amount > 0.1, "fondu au noir avant le chargement")
	at.check(Settings.last_map == "bunker_k7", "choix mémorisé (Settings.last_map = %s)" % Settings.last_map)
	var cfg := ConfigFile.new()
	at.check(cfg.load(Settings.path) == OK and cfg.get_value("game", "last_map", "") == "bunker_k7", "choix enregistré dans %s" % Settings.path)
	var ok: bool = await until(func(): return Game.instance != null and Game.instance.local_player != null, 40.0, "partie lancée")
	if ok:
		at.check(Game.instance.map_def.id == "bunker_k7", "partie solo sur BUNKER K-7")


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


func press_key(key: Key) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	ev.keycode = key
	ev.pressed = true
	Input.parse_input_event(ev)
	await frames(2)
	var up := ev.duplicate() as InputEventKey
	up.pressed = false
	Input.parse_input_event(up)
	await frames(3)
