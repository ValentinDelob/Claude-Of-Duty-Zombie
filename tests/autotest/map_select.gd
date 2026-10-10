extends AutotestScenario
## Sélection de carte (SOLO) au clavier : JOUER (hub), onglet PARTIE, SOLO ouvre l'écran des cartes
## (BUNKER K-7 seule depuis le retrait de KINO), le dossier suit la carte
## sélectionnée, Échap revient ; un ancien choix mémorisé sur KINO retombe sur
## BUNKER K-7 ; valider lance la partie et mémorise le choix (Settings).

var menu: MainMenu


func run() -> void:
	timeout_sec = 90
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 5.0, "menu principal")
	menu = tree().current_scene
	await until(_settled, 5.0, "sortie du noir d'ouverture du menu")
	at.check(Settings.last_map == "bunker_k7", "carte mémorisée par défaut : %s" % Settings.last_map)
	# Choix mémorisé sur la carte retirée : l'écran se place sur BUNKER K-7.
	Settings.last_map = "kino"
	await press("ui_accept")  # JOUER : hub
	await until(_settled, 3.0, "hub affiché")
	await press("ui_page_up")  # onglet PARTIE
	at.check(menu.current_name == "hub" and menu.current.tab == "play", "hub, onglet PARTIE")
	await press("ui_accept")  # SOLO
	at.check(menu.current_name == "map_select", "SOLO : écran de sélection de carte (%s)" % menu.current_name)
	await until(_settled, 3.0, "écran des cartes affiché")
	var screen := menu.current
	var labels := []
	for b in _buttons():
		labels.append(b.label)
	at.check(labels == ["BUNKER K-7", "RETOUR"], "cartes proposées : %s" % ", ".join(labels))
	at.check(_focused_label() == "BUNKER K-7", "ancien choix KINO : focus sur BUNKER K-7 (%s)" % _focused_label())
	at.check(screen.selected == "bunker_k7" and screen._preview.texture != null, "dossier et plan du BUNKER K-7")
	await at.screenshot("bunker")
	# Échap : retour au hub (onglet PARTIE), rien n'est lancé.
	await press("ui_cancel")
	at.check(menu.current_name == "hub" and menu.current.tab == "play", "Échap : retour au hub, onglet PARTIE")
	await until(_settled, 3.0, "hub réaffiché")
	await press("ui_accept")
	at.check(menu.current_name == "map_select", "SOLO de nouveau")
	await until(_settled, 3.0, "écran des cartes réaffiché")
	await press("ui_accept")  # BUNKER K-7
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


func _buttons() -> Array:
	var out := []
	_collect(menu.current, out)
	return out


func _collect(n: Node, out: Array) -> void:
	if n is MenuActionButton:
		out.append(n)
	for c in n.get_children():
		_collect(c, out)


func _focused_label() -> String:
	var f := at.get_viewport().gui_get_focus_owner()
	if f is MenuActionButton:
		return f.label
	return str(f)
