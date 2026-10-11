extends AutotestScenario
## @rendu : INVENTAIRE et CODEX du hub v2 EN COURS DE DÉVELOPPEMENT
## (maquettes docs/hub_v2/Inventaire.dc.html et Codex.dc.html) : captures à
## comparer aux maquettes (même contenu : sangle de cuir choisie, Brancardier
## choisi), navigation réelle à la manette et au clavier (croix, flèches),
## fiche inconnue, pastille NOUVEAU, anglais, TAILLE DES MENUS 130 %.
## Captures : tests/_out/shots/hub2_items_look_<nom>_<hauteur>.png.
## Scénario retiré (ou réduit aux vérifications logiques) une fois le hub v2
## livré (captures seulement pour un ajout en cours).

var menu: MainMenu
var hub: Hub2Screen
var _saved_name := ""


## Profil proche des maquettes : niveau 23 ; échantillons de l'inventaire ;
## codex : zombies, meute, Brancardier, Chirurgien rencontrés, Infirmière
## inconnue ; contrats actifs qui demandent des sangles.
static func demo_profile(new_surgeon := false) -> PlayerProfile:
	var pr := PlayerProfile.new()
	pr.xp = PlayerProfile.xp_for_level(23) + int(PlayerProfile.xp_to_next(23) * 0.643)
	for s in [["dog_fang", 12], ["dog_fur", 7], ["dog_collar", 3], ["brancard_strap", 4], ["brancard_bracelet", 2],
			["nurse_vocal_cords", 1]]:
		pr.add_samples(s[0], s[1])
	for k in [["walker", 1500], ["crawler", 236], ["runner", 300], ["sprinter", 100], ["dog", 54], ["brancardier", 7], ["surgeon", 1]]:
		pr.codex.add_kills(k[0], k[1])
		if k[0] != "surgeon" or not new_surgeon:
			pr.codex.mark_seen(k[0])
	var d := HubData.default()
	for c in d.contracts:
		if c.samples.has("brancard_strap") and pr.contracts.active.size() < 3:
			pr.contracts.active.append({"id": c.id, "accepted": 0})
	return pr


func run() -> void:
	timeout_sec = 150
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 5.0, "menu principal")
	menu = tree().current_scene
	await until(_settled, 5.0, "menu titre affiché")
	_saved_name = Settings.player_name
	Settings.player_name = "Valentin"
	Settings.hub_v2 = true
	ProfileStore.save_profile(demo_profile())
	menu.show_screen("hub2", {"screen": "inventory"})
	await until(_settled, 3.0, "hub v2 affiché")
	hub = menu.current
	at.check(hub.current_id == "inventory", "INVENTAIRE (%s)" % hub.current_id)
	var inv: Hub2InventoryPanel = hub.panels.inventory
	# Maquette : la sangle de cuir choisie, invites manette.
	Settings.using_pad = true
	hub.refresh_prompts()
	inv.cards.brancard_strap.grab_focus()
	await seconds(0.6)
	at.check(inv.selected_id == "brancard_strap", "sangle choisie (%s)" % inv.selected_id)
	at.check(Array(hub.prompts.describe()) == ["A VOIR LE CONTRAT", "B RETOUR"], "invites : %s" % ", ".join(hub.prompts.describe()))
	await shot("inventory_mockup")
	# Croix : vers la droite (bracelet), puis vers le bas (infirmière).
	await pad(JOY_BUTTON_DPAD_RIGHT)
	at.check(inv.selected_id == "brancard_bracelet", "croix droite : bracelet (%s)" % inv.selected_id)
	await pad(JOY_BUTTON_DPAD_DOWN)
	at.check(SampleCatalog.kind_of(inv.selected_id) == "nurse", "croix bas : infirmière (%s)" % inv.selected_id)
	await pad(JOY_BUTTON_DPAD_DOWN)
	await seconds(0.3)
	at.check(SampleCatalog.kind_of(inv.selected_id) == "surgeon", "croix bas : chirurgien (%s)" % inv.selected_id)
	await shot("inventory_pad_surgeon")
	# Clavier : flèches, cadre de focus.
	Settings.using_pad = false
	await key(KEY_UP)
	await key(KEY_LEFT)
	await seconds(0.3)
	await shot("inventory_keyboard")
	# CODEX (RB), Brancardier choisi comme la maquette.
	await pad(JOY_BUTTON_RIGHT_SHOULDER)
	at.check(hub.current_id == "codex", "RB : CODEX (%s)" % hub.current_id)
	var cx: Hub2CodexPanel = hub.panels.codex
	Settings.using_pad = true
	hub.refresh_prompts()
	cx.cards.brancardier.grab_focus()
	await seconds(0.6)
	at.check(cx.selected_id == "brancardier", "Brancardier choisi (%s)" % cx.selected_id)
	await shot("codex_mockup")
	await pad(JOY_BUTTON_DPAD_DOWN)
	await seconds(0.3)
	at.check(cx.selected_id == "nurse", "croix bas : l'inconnue, dernière de la ligne (%s)" % cx.selected_id)
	await shot("codex_unknown")
	await pad(JOY_BUTTON_DPAD_LEFT)
	at.check(cx.selected_id == "surgeon", "croix gauche : le Chirurgien (%s)" % cx.selected_id)
	cx.cards.zombies.grab_focus()
	await seconds(0.3)
	await shot("codex_zombies")
	# Pastille NOUVEAU (Chirurgien découvert depuis la dernière visite).
	Settings.using_pad = false
	ProfileStore.save_profile(demo_profile(true))
	menu.show_screen("hub2", {"screen": "lab"})
	await until(_settled, 3.0, "hub v2 rouvert")
	hub = menu.current
	at.check(hub.top_bar.badges.get("codex", false), "pastille de l'onglet CODEX")
	hub.open("codex")
	await seconds(0.5)
	at.check(hub.panels.codex.cards.surgeon.find_child("New", true, false) != null, "NOUVEAU sur le Chirurgien")
	await shot("codex_new")
	# TAILLE DES MENUS 130 %.
	Settings.menu_ui_scale = 1.3
	await frames(4)
	hub = menu.current
	await seconds(0.5)
	_check_inside(hub, "codex 130 %")
	await shot("codex_130")
	hub.open("inventory")
	await seconds(0.5)
	_check_inside(hub, "inventaire 130 %")
	await shot("inventory_130")
	Settings.menu_ui_scale = 1.0
	await frames(3)
	# Anglais.
	Settings.language = "en"
	menu.show_screen("hub2", {"screen": "inventory"})
	await until(_settled, 3.0, "hub v2 en anglais")
	hub = menu.current
	Settings.using_pad = true
	hub.refresh_prompts()
	hub.panels.inventory.cards.brancard_strap.grab_focus()
	await seconds(0.5)
	await shot("inventory_en")
	hub.open("codex")
	hub.panels.codex.cards.brancardier.grab_focus()
	await seconds(0.5)
	await shot("codex_en")
	Settings.using_pad = false
	Settings.language = "fr"
	Settings.hub_v2 = false
	Settings.player_name = _saved_name
	ProfileStore.reset()


func _check_inside(root: Control, what: String) -> void:
	var screen := Rect2(Vector2.ZERO, root.get_viewport_rect().size).grow(1.0)
	var bad := []
	_scan_inside(root, screen, bad)
	at.check(bad.is_empty(), "%s : rien ne sort de l'écran %s" % [what, str(bad.slice(0, 4))])


## Zones qui défilent : leur cadre seulement (le contenu est rogné).
func _scan_inside(n: Node, screen: Rect2, bad: Array) -> void:
	if n is Control:
		var c := n as Control
		if not c.is_visible_in_tree():
			return
		if not (c is Hub2PulseRings) and not screen.encloses(c.get_global_rect()):
			bad.append("%s %s" % [c.name, c.get_global_rect()])
		if c is ScrollContainer:
			return
	for ch in n.get_children():
		_scan_inside(ch, screen, bad)


func shot(n: String) -> void:
	await at.screenshot("%s_%d" % [n, DisplayServer.window_get_size().y])


func _settled() -> bool:
	return is_instance_valid(menu) and menu.current != null and menu.current.modulate.a >= 0.999 \
		and menu._fade_amount < 0.001


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
