extends TestCase
## Hub du scientifique (docs/HUB_PLAN.md, lot B) : onglets LB / RB et Q / E,
## focus initial, retour B / Échap, menu du hub (Start), invites clavier <->
## manette, taille des menus 80 / 130 % sans débordement à 1280 × 720,
## enregistrement des panneaux, LABO (profil, réserve), réglage TAILLE DES
## MENUS. Sans MainMenu : un hôte d'écrans minimal (FakeHost).

const TMP := "user://settings_hub_unittest.cfg"

var _saved := {}
var _frame: Control
var _host: FakeHost


## Hôte d'écrans minimal : note les écrans demandés.
class FakeHost extends MenuHost:
	var shown: Array = []
	var hint := ""

	func show_screen(screen_name: String, _args := {}, _remember := true) -> void:
		shown.append(screen_name)

	func set_hint(t: String) -> void:
		hint = t


func before_each() -> void:
	Input.flush_buffered_events()
	for k in ["menu_ui_scale", "using_pad", "language"]:
		_saved[k] = Settings.get(k)
	Settings.using_pad = false
	Settings.language = "fr"
	Settings.menu_ui_scale = 1.0


func after_each() -> void:
	if is_instance_valid(_frame):
		_frame.queue_free()
	for k in _saved:
		Settings.set(k, _saved[k])
	HubScreen.register_panel("parts", null)
	HubScreen.last_tab = "lab"
	if FileAccess.file_exists(TMP):
		DirAccess.remove_absolute(TMP)


## Profil de démonstration (niveau 7, échantillons de chiens, 2 armes).
static func demo_profile() -> PlayerProfile:
	var pr := PlayerProfile.new()
	pr.xp = PlayerProfile.xp_for_level(7) + 2140
	pr.add_samples("dog_fang", 7)
	pr.add_samples("dog_fur", 2)
	pr.add_samples("dog_collar", 5)
	var w := OwnedWeapon.create("mp5k", 7, OwnedWeapon.Rarity.EPIC)
	w.parts.append(WeaponPart.create("damage", 6, {"damage": 0.15}))
	w.parts.append(WeaponPart.create("fire_rate", 5, {"fire_rate": 0.1}))
	pr.add_weapon(w)
	pr.add_weapon(OwnedWeapon.create("m16", 6, OwnedWeapon.Rarity.RARE))
	pr.add_part(WeaponPart.create("mag", 7, {"mag": 0.2}))
	return pr


## Hub ouvert dans un cadre de 1280 × 720 (onglet `tab`).
func _open(tab := "lab", pr: PlayerProfile = null) -> HubScreen:
	_frame = Control.new()
	_frame.size = Vector2(1280, 720)
	host.add_child(_frame)
	_host = FakeHost.new()
	_host.size = Vector2(1280, 720)
	_frame.add_child(_host)
	var hub := HubScreen.new()
	hub.menu = _host
	hub.size = Vector2(1280, 720)
	_host.add_child(hub)
	_host.current = hub
	_host.current_name = "hub"
	hub.enter({"tab": tab, "profile": pr if pr else demo_profile()})
	await wait_frames(3)
	return hub


func _action(hub: HubScreen, action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	hub._unhandled_input(ev)


func _key(hub: HubScreen, physical: Key) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = physical
	ev.pressed = true
	hub._unhandled_input(ev)


func _pad(hub: HubScreen, button: JoyButton) -> void:
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	ev.pressed = true
	hub._unhandled_input(ev)


func test_seven_tabs_in_order() -> void:
	var hub := await _open()
	assert_eq(Array(hub.tab_bar.labels), ["LABO", "ARSENAL", "PIÈCES", "CONTRATS", "ÉCHANGES", "DÉPART", "PARTIE"])
	assert_eq(hub.panels.size(), 7, "un panneau par onglet")
	assert_true(hub.panels.lab is HubLabPanel, "LABO : panneau du lot B")
	assert_true(hub.panels.arsenal is HubPlaceholderPanel, "ARSENAL : panneau « à venir »")
	assert_true(hub.panels.play is HubPlayStubPanel, "PARTIE : solo / coop provisoires")
	Settings.language = "en"
	assert_eq(HubScreen.tab_label("loadout"), "LOADOUT")


func test_tabs_with_shoulders_and_keys() -> void:
	var hub := await _open()
	assert_eq(hub.tab, "lab")
	_action(hub, "ui_page_down")  # RB / Page suiv.
	assert_eq(hub.tab, "arsenal", "RB : onglet suivant")
	_key(hub, KEY_E)
	assert_eq(hub.tab, "parts", "E : onglet suivant")
	_key(hub, KEY_Q)
	_action(hub, "ui_page_up")  # LB / Page préc.
	assert_eq(hub.tab, "lab", "Q puis LB : retour au LABO")
	_action(hub, "ui_page_up")
	assert_eq(hub.tab, "play", "LB au premier onglet : le dernier (en boucle)")
	_key(hub, KEY_E)
	assert_eq(hub.tab, "lab", "E au dernier onglet : le premier")
	assert_true(hub.panels.lab.visible and not hub.panels.play.visible, "seul l'onglet affiché est visible")


func test_initial_focus_per_tab() -> void:
	var hub := await _open()
	await wait_frames(2)
	var fo := hub.get_viewport().gui_get_focus_owner()
	assert_eq(fo, hub.panels.lab.contracts_button, "LABO : focus sur VOIR LES CONTRATS")
	hub.select_tab("play")
	await wait_frames(2)
	assert_eq(hub.get_viewport().gui_get_focus_owner(), hub.panels.play.solo_button, "PARTIE : focus sur SOLO")
	hub.select_tab("contracts")
	await wait_frames(2)
	assert_eq(hub.get_viewport().gui_get_focus_owner(), hub.panels.contracts.back_button, "onglet à venir : RETOUR AU LABO")


func test_back_opens_and_closes_hub_menu() -> void:
	var hub := await _open()
	assert_false(hub.hub_menu.is_open())
	hub.back()  # Échap / B au niveau des onglets
	assert_true(hub.hub_menu.is_open(), "retour au niveau des onglets : menu du hub")
	assert_eq(hub.prompts.describe()[1], "Échap Reprendre", "invites du menu")
	_action(hub, "ui_page_down")
	assert_eq(hub.tab, "lab", "pas de changement d'onglet menu ouvert")
	hub.back()
	assert_false(hub.hub_menu.is_open(), "retour : menu fermé")
	_pad(hub, JOY_BUTTON_START)
	assert_true(hub.hub_menu.is_open(), "Start : menu du hub")
	_pad(hub, JOY_BUTTON_START)
	assert_false(hub.hub_menu.is_open(), "Start de nouveau : fermé")
	var labels := []
	for b in hub.hub_menu.buttons:
		labels.append(b.label)
	assert_eq(labels, ["REPRENDRE", "OPTIONS", "DOSSIER DE COMBAT", "ÉCRAN TITRE", "QUITTER LE JEU"])


func test_hub_menu_screens() -> void:
	var hub := await _open("arsenal")
	hub.open_screen("options")
	assert_eq(_host.shown, ["options"], "OPTIONS par-dessus le hub")
	assert_eq(HubScreen.last_tab, "arsenal", "onglet gardé pour le retour")
	hub.open_screen("career")
	hub.to_title()
	assert_eq(_host.shown, ["options", "career", "main"])


func test_play_stub_uses_current_screens() -> void:
	var hub := await _open("play")
	hub.panels.play.solo_button.pressed.emit()
	hub.panels.play.coop_button.pressed.emit()
	assert_eq(_host.shown, ["map_select", "multiplayer"], "SOLO -> sélection de carte, COOP -> MULTIJOUEUR")


func test_prompts_keyboard_and_pad() -> void:
	var hub := await _open()
	var d := hub.prompts.describe()
	var q := HubPrompts.physical_key_name(KEY_Q)
	assert_eq(Array(d), ["Entrée Choisir", "%s E Onglets" % q, "Échap Menu du hub"], "clavier : %s" % str(d))
	Settings.using_pad = true
	d = hub.prompts.describe()
	assert_eq(Array(d), ["A Choisir", "LB RB Onglets", "START Menu du hub"], "manette : %s" % str(d))
	Settings.language = "en"
	Settings.using_pad = false
	hub.refresh_prompts()
	assert_eq(hub.prompts.describe()[0], "Enter Select")


func test_hint_goes_to_prompt_bar() -> void:
	var hub := await _open()
	hub.set_hint("Aide de test")
	assert_eq(hub.prompts.hint, "Aide de test")
	hub.select_tab("arsenal")
	assert_eq(hub.prompts.hint, "", "aide effacée au changement d'onglet")


func test_size_80_and_130_stay_on_screen() -> void:
	for f in [0.8, 1.0, 1.3]:
		Settings.menu_ui_scale = f
		var hub := await _open()
		await wait_frames(2)
		var bad := []
		_scan(hub, Rect2(0, 0, 1280, 720).grow(1.0), hub, bad)
		assert_true(bad.is_empty(), "taille %d %% : rien ne sort de l'écran %s" % [roundi(f * 100.0), str(bad.slice(0, 3))])
		assert_near(hub.top_bar.size.y, HubStyle.px(52) + HubStyle.px(2), 0.5, "barre du haut à l'échelle")
		assert_near(hub.prompts.size.y, HubStyle.px(36), 0.5, "barre d'invites à l'échelle")
		_frame.free()


func _scan(n: Node, screen: Rect2, root: Control, bad: Array) -> void:
	if n is Control:
		var c := n as Control
		if not c.visible:
			return
		var r := Rect2(c.global_position - root.global_position, c.size)
		if not screen.encloses(r):
			bad.append("%s %s" % [c.name, r])
		if c is ScrollContainer:
			return
	for ch in n.get_children():
		_scan(ch, screen, root, bad)


func test_scale_change_rebuilds() -> void:
	var hub := await _open("parts")
	var old_bar := hub.tab_bar
	Settings.menu_ui_scale = 1.2
	await wait_frames(2)
	assert_true(hub.tab_bar != old_bar, "écran reconstruit à la nouvelle taille")
	assert_eq(hub.tab, "parts", "même onglet")
	assert_near(hub.tab_bar.custom_minimum_size.y, roundf(46 * 1.2), 0.5)


func test_register_panel() -> void:
	HubScreen.register_panel("parts", HubPlayStubPanel)
	assert_eq(HubScreen.panel_script("parts"), HubPlayStubPanel)
	var hub := await _open("parts")
	assert_true(hub.panels.parts is HubPlayStubPanel, "panneau enregistré utilisé")
	assert_eq(hub.panels.parts.tab_id, "parts")
	assert_true(hub.panels.parts.hub == hub)
	HubScreen.register_panel("parts", null)
	assert_eq(HubScreen.panel_script("parts"), HubPlaceholderPanel, "retour au panneau provisoire")


func test_lab_reads_profile() -> void:
	var hub := await _open()
	var lab: HubLabPanel = hub.panels.lab
	assert_eq(lab.level_label.text, "NIVEAU 7")
	assert_eq(lab.stats.best_score.text, "18", "meilleur score = 7 + 6 + 5")
	assert_eq(lab.stats.weapons.text, "2")
	assert_eq(lab.stats.parts.text, "1")
	assert_eq(lab.sample_labels.dog_fang.text, "7")
	assert_eq(lab.sample_labels.dog_fur.text, "2")
	assert_eq(lab.sample_labels.dog_collar.text, "5")
	assert_true(lab.progress_label.text.begins_with("2" + String.chr(0xA0) + "140 / "), lab.progress_label.text)
	assert_eq(hub.top_bar.level, 7)
	assert_eq(hub.top_bar.xp_in, 2140)


func test_lab_unknown_samples_hidden() -> void:
	var hub := await _open("lab", PlayerProfile.new())
	var lab: HubLabPanel = hub.panels.lab
	assert_true(lab.sample_labels.is_empty(), "aucune sorte connue : tout en « ??? »")
	assert_eq(lab.stats.best_score.text, "1", "armes de base seules")
	assert_true("volontaire" in lab.line_text, "réplique du premier passage")


func test_lab_last_match() -> void:
	var r := MatchResult.new()
	r.evacuated = true
	r.round_reached = 10
	r.kills = 171
	r.xp = 2312
	r.loot = {"kept": true, "weapons": [["mp5k", 7, 2]], "parts": 1, "samples": {"dog_fang": 2}}
	var keep: Dictionary = Router.last_match
	Router.last_match = {"result": r, "map": "BUNKER K7", "solo": true}
	var hub := await _open()
	var lab: HubLabPanel = hub.panels.lab
	assert_eq(lab.last_box.right_label.text, "BUNKER K7 · SOLO")
	assert_true("ramené" in lab.line_text, "réplique après une évacuation")
	Router.last_match = keep


func test_number_format() -> void:
	assert_eq(HubStyle.num(2140), "2" + String.chr(0xA0) + "140")
	assert_eq(HubStyle.num(999), "999")
	Settings.language = "en"
	assert_eq(HubStyle.num(1234567), "1,234,567")


func test_contracts_view_without_lot_a() -> void:
	var pr := demo_profile()
	if HubContractsView.available(pr):
		return  # lot A en place : couvert par ses tests
	assert_eq(HubContractsView.active(pr), [])
	assert_eq(HubContractsView.done_count(pr), -1)
	assert_eq(HubContractsView.ready_count(pr), 0)
	assert_true(HubContractsView.catalog().has("dog_fangs_small"), "titres lus dans contracts.json")


func test_days_left() -> void:
	var now := Time.get_unix_time_from_datetime_string("2026-11-18T12:00:00")
	assert_eq(HubContractsView.days_left("2026-11-30", now), 12, "maquette : encore 12 j")
	assert_eq(HubContractsView.days_left("", now), -1)
	assert_eq(HubContractsView.days_left("2026-11-01", now), 0)


func test_menu_ui_scale_setting() -> void:
	assert_near(Settings.MENU_UI_SCALE_DEFAULT, 1.0)
	Settings.menu_ui_scale = 3.0
	assert_near(Settings.menu_ui_scale, 1.3, 0.001, "130 % au plus")
	Settings.menu_ui_scale = 0.1
	assert_near(Settings.menu_ui_scale, 0.8, 0.001, "80 % au moins")
	Settings.menu_ui_scale = 1.07
	assert_near(Settings.menu_ui_scale, 1.05, 0.001, "pas de 5 %")
	@warning_ignore("static_called_on_instance")
	assert_near(Settings.clamp_menu_ui_scale(NAN), 1.0)
	Settings.menu_ui_scale = 1.15
	Settings.save_to(TMP)
	var cfg := ConfigFile.new()
	assert_eq(cfg.load(TMP), OK)
	assert_near(float(cfg.get_value("interface", "menu_ui_scale")), 1.15, 0.001, "enregistré")
	Settings.menu_ui_scale = 1.0
	assert_true(Settings.load_from(TMP))
	assert_near(Settings.menu_ui_scale, 1.15, 0.001, "relu")
	assert_near(HubStyle.px(100), 115.0, 0.5)
	assert_eq(HubStyle.fs(16), 18)
