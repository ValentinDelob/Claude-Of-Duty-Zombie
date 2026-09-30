extends AutotestScenario
## Sélection de carte (SOLO) au clavier : SOLO ouvre l'écran des cartes
## (BUNKER K-7 / KINO), le dossier suit la carte sélectionnée, Échap revient,
## valider KINO lance la partie sur KINO et mémorise le choix (Settings).

var menu: MainMenu


func run() -> void:
	timeout_sec = 90
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 5.0, "menu principal")
	menu = tree().current_scene
	await until(_settled, 5.0, "sortie du noir d'ouverture du menu")
	at.check(Settings.last_map == "bunker_k7", "carte mémorisée par défaut : %s" % Settings.last_map)
	await press("ui_accept")  # SOLO
	at.check(menu.current_name == "map_select", "SOLO : écran de sélection de carte (%s)" % menu.current_name)
	await until(_settled, 3.0, "écran des cartes affiché")
	var screen := menu.current
	var labels := []
	for b in _buttons():
		labels.append(b.label)
	at.check(labels == ["BUNKER K-7", "KINO", "RETOUR"], "cartes proposées : %s" % ", ".join(labels))
	at.check(_focused_label() == "BUNKER K-7", "focus sur la dernière carte jouée (%s)" % _focused_label())
	at.check(screen.selected == "bunker_k7" and screen._preview.texture != null, "dossier et plan du BUNKER K-7")
	await at.screenshot("bunker")
	await press("ui_down")
	at.check(_focused_label() == "KINO" and screen.selected == "kino", "↓ : KINO sélectionnée (%s)" % screen.selected)
	at.check(screen._name.text == "KINO" and screen._desc.text != "", "dossier de KINO : %s" % screen._desc.text)
	await seconds(0.8)  # pause avant la capture
	await at.screenshot("kino")
	# Échap : retour au menu principal, rien n'est lancé.
	await press("ui_cancel")
	at.check(menu.current_name == "main", "Échap : retour au menu principal")
	await until(_settled, 3.0, "menu principal réaffiché")
	await press("ui_accept")
	at.check(menu.current_name == "map_select", "SOLO de nouveau")
	await until(_settled, 3.0, "écran des cartes réaffiché")
	await press("ui_down")
	await press("ui_accept")  # KINO
	await until(func(): return is_instance_valid(menu) and menu._fade_amount > 0.1, 2.0, "fondu au noir du lancement")
	at.check(tree().current_scene == menu and menu._fade_amount > 0.1, "fondu au noir avant le chargement")
	at.check(Settings.last_map == "kino", "choix mémorisé (Settings.last_map = %s)" % Settings.last_map)
	var cfg := ConfigFile.new()
	at.check(cfg.load(Settings.path) == OK and cfg.get_value("game", "last_map", "") == "kino", "choix enregistré dans %s" % Settings.path)
	var ok: bool = await until(func(): return Game.instance != null and Game.instance.local_player != null, 40.0, "partie lancée")
	if ok:
		at.check(Game.instance.map_def.id == "kino", "partie solo sur KINO")
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
