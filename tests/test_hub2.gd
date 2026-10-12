extends TestCase
## Hub v2 (docs/HUB_PLAN.md §9, maquettes docs/hub_v2) : jetons du style
## (couleurs, polices fournies, graisses, espacement des lettres, taille des
## menus, nombres, courbe ease-out), anneaux pulsés, touches et invites selon
## le périphérique, boîte biseautée, barre du haut, et le cadre Hub2Screen :
## onglets LB / RB / Q / E, JOUER (START / P), retours B / Échap (sous-écran,
## onglet, LABO -> menu du hub), fil d'Ariane, cadre masqué du récapitulatif,
## pastilles, écran remplacé à l'exécution, reconstruction à 130 %, anglais,
## menu du hub (Hub2Menu, ÉCRAN TITRE en coop), le hub est LE hub (plus de
## réglage caché). Sans MainMenu : un hôte d'écrans minimal (FakeHost).

const TMP := "user://settings_hub2_unittest.cfg"

var _saved := {}
var _frame: Control
var _host: FakeHost


## Hôte d'écrans minimal : note les écrans demandés.
class FakeHost extends MenuHost:
	var shown: Array = []

	func show_screen(screen_name: String, _args := {}, _remember := true) -> void:
		shown.append(screen_name)


## Écran de test : pastille allumée, retour consommé une fois.
class BadgePanel extends Hub2Panel:
	var eat_back := false

	func badge() -> bool:
		return true

	func back() -> bool:
		if eat_back:
			eat_back = false
			return true
		return false


func before_each() -> void:
	Input.flush_buffered_events()
	for k in ["menu_ui_scale", "using_pad", "language", "player_name"]:
		_saved[k] = Settings.get(k)
	Settings.using_pad = false
	Settings.language = "fr"
	Settings.menu_ui_scale = 1.0
	Settings.player_name = "Valentin"


func after_each() -> void:
	if is_instance_valid(_frame):
		_frame.queue_free()
	for k in _saved:
		Settings.set(k, _saved[k])
	Hub2Screen.register_panel("arsenal", null)
	Hub2Screen.last_screen = "lab"
	if Net.mode != Net.Mode.NONE:
		Net.leave()
	GameState.reset_to_menu()
	if FileAccess.file_exists(TMP):
		DirAccess.remove_absolute(TMP)


func _profile() -> PlayerProfile:
	var pr := PlayerProfile.new()
	pr.xp = PlayerProfile.xp_for_level(23) + 100
	return pr


## Hub v2 ouvert dans un cadre de 1280 × 720 (écran `screen`).
func _open(screen := "lab") -> Hub2Screen:
	_frame = Control.new()
	_frame.size = Vector2(1280, 720)
	host.add_child(_frame)
	_host = FakeHost.new()
	_host.size = Vector2(1280, 720)
	_frame.add_child(_host)
	var hub := Hub2Screen.new()
	hub.menu = _host
	hub.size = Vector2(1280, 720)
	_host.add_child(hub)
	_host.current = hub
	_host.current_name = "hub"
	hub.enter({"screen": screen, "profile": _profile()})
	await wait_frames(3)
	return hub


func _action(hub: Hub2Screen, action: String) -> bool:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	return hub.handle_event(ev)


func _key(hub: Hub2Screen, physical: Key) -> bool:
	var ev := InputEventKey.new()
	ev.physical_keycode = physical
	ev.pressed = true
	return hub.handle_event(ev)


func _pad(hub: Hub2Screen, button: JoyButton) -> bool:
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	ev.pressed = true
	return hub.handle_event(ev)


# --- Style ---------------------------------------------------------------------

func test_tokens_match_mockups() -> void:
	assert_eq(Hub2Style.TEXT.to_html(false), "f2f0ea")
	assert_eq(Hub2Style.YELLOW.to_html(false), "f5c542")
	assert_eq(Hub2Style.TEAL.to_html(false), "4fe3c1")
	assert_eq(Hub2Style.BAD.to_html(false), "ff7a5c")
	assert_eq(Hub2Style.BAD_ALT.to_html(false), "ff6b57")
	assert_eq(Hub2Style.INK.to_html(false), "0b0b0c")
	assert_near(Hub2Style.GLASS.a, 0.62)
	assert_near(Hub2Style.GLASS_STRONG.a, 0.7)
	assert_near(Hub2Style.GLASS.r * 255.0, 10.0, 0.01)
	assert_near(Hub2Style.LINE.a, 0.08)
	assert_eq(Hub2Style.text_a(0.6), Color(Hub2Style.TEXT, 0.6))
	assert_eq(Hub2Style.shade(0.35), Color(8 / 255.0, 9 / 255.0, 11 / 255.0, 0.35))
	var rar := []
	for i in 5:
		rar.append(Hub2Style.rarity_color(i).to_html(false))
	assert_eq(rar, ["c9c7be", "4d9bff", "b56cff", "ff9a1f", "ff4d5e"], "rareté : commune -> unique")
	assert_eq(Hub2Style.rarity_color(99).to_html(false), "ff4d5e", "rareté bornée")


func test_fonts_shipped_and_weights() -> void:
	for fam in [Hub2Style.CHAKRA, Hub2Style.BARLOW, Hub2Style.MONO]:
		for w in [400, 500, 600, 700]:
			var f := Hub2Style.font(fam, w)
			assert_true(f != null, "%s %d chargée" % [fam, w])
			assert_true(f.get_string_size("ARSENAL", HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x > 20.0, "%s %d mesure du texte" % [fam, w])
	assert_eq(Hub2Style.nearest_weight(Hub2Style.CHAKRA, 400), 500, "Chakra Petch 400 -> 500 (seules 500, 600, 700 chargées)")
	assert_eq(Hub2Style.nearest_weight(Hub2Style.MONO, 400), 500, "JetBrains Mono sans graisse -> 500")
	assert_eq(Hub2Style.nearest_weight(Hub2Style.MONO, 700), 700)
	assert_eq(Hub2Style.nearest_weight(Hub2Style.BARLOW, 700), 600)
	assert_true(Hub2Style.font(Hub2Style.CHAKRA, 700) == Hub2Style.font(Hub2Style.CHAKRA, 700), "polices en cache")
	assert_true(Hub2Style.font(Hub2Style.CHAKRA, 700) != Hub2Style.font(Hub2Style.CHAKRA, 500), "une police par graisse")
	# Licences OFL fournies à côté des polices.
	for d in ["chakra_petch", "barlow", "jetbrains_mono"]:
		assert_true(FileAccess.file_exists("res://assets/fonts/%s/OFL.txt" % d), "OFL.txt de %s" % d)


func test_tracking_and_scale() -> void:
	var f := Hub2Style.font(Hub2Style.CHAKRA, 700)
	var plain := Hub2Style.text_width("LABO", f, 16)
	assert_near(Hub2Style.tracking_px(0.08, 16), 1.28)
	assert_near(Hub2Style.text_width("LABO", f, 16, 1.28), plain + 4 * 1.28, 0.01, "letter-spacing après chaque lettre")
	var spaced: FontVariation = Hub2Style.font_spaced(Hub2Style.CHAKRA, 700, 2) as FontVariation
	assert_true(spaced != null and spaced.spacing_glyph == 2, "espacement entier pour un Label")
	var l := Hub2Style.label("ARSENAL", Hub2Style.CHAKRA, 700, 16, Hub2Style.TEXT, 0.08)
	assert_eq(l.get_theme_font_size("font_size"), 16)
	l.free()
	assert_eq(Hub2Style.px(72), 72.0)
	assert_eq(Hub2Style.fs(16), 16)
	Settings.menu_ui_scale = 1.3
	assert_eq(Hub2Style.px(72), roundf(72 * 1.3), "taille des menus 130 %")
	assert_eq(Hub2Style.fs(16), 21)
	assert_eq(Hub2Style.pxv(28, 96), Vector2(36, 125))
	var t := Hub2Text.new()
	t.setup("JOUER", Hub2Style.CHAKRA, 700, 18, Hub2Style.INK, 0.14)
	assert_near(t.text_width(), Hub2Style.text_width("JOUER", Hub2Style.font(Hub2Style.CHAKRA, 700), 23, 0.14 * 23), 0.01,
			"Hub2Text à la taille finale (18 px x 1,3 = 23)")
	assert_true(t.custom_minimum_size.x >= t.text_width(), "taille minimale = texte")
	t.free()


func test_numbers_and_curves() -> void:
	assert_eq(Hub2Style.num(8420), "8" + String.chr(0xA0) + "420")
	assert_eq(Hub2Style.num(13100), "13" + String.chr(0xA0) + "100")
	Settings.language = "en"
	assert_eq(Hub2Style.num(13100), "13,100")
	assert_near(Hub2Style.ease_out(0.0), 0.0)
	assert_near(Hub2Style.ease_out(1.0), 1.0)
	assert_near(Hub2Style.cubic_bezier(0.5, 0.0, 0.0, 1.0, 1.0), 0.5, 0.001, "courbe linéaire")
	var prev := 0.0
	for i in range(1, 11):
		var v := Hub2Style.ease_out(i / 10.0)
		assert_true(v >= prev, "ease-out croissante")
		prev = v
	assert_true(Hub2Style.ease_out(0.5) > 0.5, "ease-out : rapide au début")


func test_pulse_rings_keyframes() -> void:
	var to := Vector2(1.12, 1.35)
	var s0 := Hub2PulseRings.ring_state(0, 0.0, to)
	assert_eq(s0[0], Vector2.ONE, "départ : taille de l'élément")
	assert_near(s0[1], 0.9, 0.001, "départ : opacité 0.9")
	var end := Hub2PulseRings.ring_state(0, 1.799, to)
	assert_near((end[0] as Vector2).x, 1.12, 0.01, "fin : 1.12 en largeur")
	assert_near((end[0] as Vector2).y, 1.35, 0.01, "fin : 1.35 en hauteur")
	assert_near(end[1], 0.0, 0.01, "fin : effacé")
	var r1 := Hub2PulseRings.ring_state(1, 0.6, to)
	assert_eq(r1[0], Vector2.ONE, "deuxième anneau décalé de 0,6 s")
	var r2 := Hub2PulseRings.ring_state(2, 1.2, to)
	assert_eq(r2[0], Vector2.ONE, "troisième anneau décalé de 1,2 s")
	var loop := Hub2PulseRings.ring_state(0, 1.8, to)
	assert_eq(loop[0], Vector2.ONE, "boucle de 1,8 s")


# --- Touches et invites ---------------------------------------------------------

func test_input_names_follow_device() -> void:
	var q := Hub2Input.physical_key_name(KEY_Q)
	var e := Hub2Input.physical_key_name(KEY_E)
	assert_eq(Hub2Input.keycap_text(Hub2Input.keys_of(Hub2Input.TABS), Hub2Input.pads_of(Hub2Input.TABS), false), "%s %s" % [q, e])
	assert_eq(Hub2Input.keycap_text(Hub2Input.keys_of(Hub2Input.TABS), Hub2Input.pads_of(Hub2Input.TABS), true), "LB RB")
	assert_eq(Hub2Input.keycap_text(Hub2Input.keys_of(Hub2Input.PLAY), Hub2Input.pads_of(Hub2Input.PLAY), true), "START")
	assert_eq(Hub2Input.keycap_text(Hub2Input.keys_of(Hub2Input.ACCEPT), Hub2Input.pads_of(Hub2Input.ACCEPT), false), "Entrée")
	assert_eq(Hub2Input.ps_symbol([JOY_BUTTON_A], false), -1, "clavier : texte")
	Settings.using_pad = false
	assert_eq(Hub2Input.tab_hint(-1), q)
	Settings.using_pad = true
	assert_eq(Hub2Input.tab_hint(-1), "LB")
	assert_eq(Hub2Input.tab_hint(1), "RB")
	var start := InputEventJoypadButton.new()
	start.button_index = JOY_BUTTON_START
	start.pressed = true
	assert_true(Hub2Input.is_play(start), "START : JOUER")
	var p := InputEventKey.new()
	p.physical_keycode = KEY_P
	p.pressed = true
	assert_true(Hub2Input.is_play(p), "P : JOUER")
	var ek := InputEventKey.new()
	ek.physical_keycode = KEY_E
	ek.pressed = true
	assert_eq(Hub2Input.tab_step(ek), 1)
	ek.ctrl_pressed = true
	assert_eq(Hub2Input.tab_step(ek), 0, "Ctrl + E : rien")


func test_prompts_bar() -> void:
	var pr := Hub2Prompts.new()
	pr.set_items([[Hub2Input.ACCEPT, "Ouvrir"], [Hub2Input.TABS, "Onglets"], [Hub2Input.PLAY, "Jouer"],
		["custom", "Trier", PackedStringArray(["T"]), [JOY_BUTTON_LEFT_STICK]]])
	Settings.using_pad = true
	assert_eq(Array(pr.describe()), ["A OUVRIR", "LB RB ONGLETS", "START JOUER", "LS TRIER"], "maquette : touches manette, libellés en capitales")
	Settings.using_pad = false
	assert_eq(pr.describe()[0], "Entrée OUVRIR")
	assert_eq(pr.describe()[3], "T TRIER", "action propre : ses touches")
	var f := Hub2Style.font(Hub2Style.BARLOW, 400)
	var cut := Hub2Prompts.ellipsis("Un texte d'aide beaucoup trop long pour la place", f, 15, 80.0)
	assert_true(cut.ends_with("…") and f.get_string_size(cut, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x <= 80.0, "aide coupée : " + cut)
	pr.free()


func test_keycap_size() -> void:
	var k := Hub2Keycap.new()
	k.label = "A"
	assert_eq(k.custom_minimum_size, Vector2(24, 24), "touche d'une lettre : 24 x 24")
	k.label = "LB RB"
	assert_true(k.custom_minimum_size.x > 40.0 and k.custom_minimum_size.x < 50.0, "« LB RB » : ≈ 45 px (%s)" % k.custom_minimum_size)
	k.free()


func test_box_chamfer_and_glass() -> void:
	var b := Hub2Box.new()
	b.size = Vector2(168, 44)
	b.flat(Hub2Style.YELLOW)
	b.chamfer(12)
	var m := b.material as ShaderMaterial
	assert_eq(m.shader, Hub2Box.SHADER_FLAT, "fond plat : pas de lecture de l'écran")
	assert_true(b._has_point(Vector2(84, 22)), "centre")
	assert_false(b._has_point(Vector2(166, 2)), "coin haut-droit coupé")
	assert_false(b._has_point(Vector2(2, 42)), "coin bas-gauche coupé")
	assert_true(b._has_point(Vector2(2, 2)), "coin haut-gauche droit")
	b.glass()
	assert_eq(m.shader, Hub2Box.SHADER_GLASS, "verre : flou")
	assert_near(float(m.get_shader_parameter("blur")), 12.0, 0.01, "blur(12px)")
	assert_eq(m.get_shader_parameter("fill"), Hub2Style.GLASS)
	b.pad(18, 20, 18, 22)
	assert_eq(b.get_theme_constant("margin_left"), 22, "padding CSS : haut, droite, bas, gauche")
	assert_eq(b.get_theme_constant("margin_right"), 20)
	b.free()


# --- Cadre Hub2Screen ----------------------------------------------------------

func test_frame_and_tabs() -> void:
	var hub := await _open()
	assert_eq(hub.current_id, "lab")
	var labels := []
	for t in hub.top_bar.tabs:
		labels.append(t.label)
	assert_eq(labels, ["LABO", "ARSENAL", "INVENTAIRE", "CODEX"], "onglets de la maquette")
	assert_eq(hub.top_bar.play_text.text, "JOUER")
	assert_eq(hub.top_bar.size.y, 72.0, "barre du haut : 72 px")
	assert_eq(hub.prompts.size.y, 48.0, "invites : 48 px")
	assert_eq(hub.prompts.position.y, 672.0, "invites en bas")
	assert_eq(hub.top_bar.level, 23)
	assert_eq(hub.top_bar.player_name, "Valentin")
	assert_true(hub.top_bar.xp_text().contains(" / "), hub.top_bar.xp_text())
	assert_eq(hub.top_bar.level_box.position, Vector2(28, 16), "pavé du niveau (28, 16)")
	assert_eq(hub.top_bar.play_box.position, Vector2(1084, 14), "JOUER à droite (1084, 14)")
	assert_eq(hub.top_bar.play_box.size, Vector2(168, 44))
	# Onglets centrés entre le joueur (28 + 230 + 24) et JOUER (1084 − 24).
	var first: Rect2 = hub.top_bar.tab_rects.lab
	var last: Rect2 = hub.top_bar.tab_rects.codex
	assert_true(first.position.x > 282.0 and last.end.x < 1060.0, "onglets entre le joueur et JOUER")
	assert_near(first.position.x - 282.0, 1060.0 - last.end.x, 30.0, "onglets centrés (LB / RB de part et d'autre)")
	assert_true(hub.panels.lab is Hub2LabPanel and hub.panels.lab.visible)
	assert_false(hub.crumb.visible, "pas de fil d'Ariane sur un onglet")
	assert_eq(hub.veil.spec.stops.size(), 2, "LABO : voile en dégradé")


func test_tab_navigation() -> void:
	var hub := await _open()
	assert_true(_action(hub, "ui_page_down"), "RB / Page suiv. consommé")
	assert_eq(hub.current_id, "arsenal")
	_key(hub, KEY_E)
	assert_eq(hub.current_id, "inventory")
	_key(hub, KEY_E)
	_key(hub, KEY_E)
	assert_eq(hub.current_id, "lab", "E en boucle : LABO")
	_key(hub, KEY_Q)
	assert_eq(hub.current_id, "codex", "Q au premier : le dernier")
	assert_eq(hub.top_bar.current, "codex")
	assert_true(hub.panels.codex.visible and not hub.panels.lab.visible, "seul l'écran affiché est visible")
	assert_near(hub.veil.spec.color.a, 0.35, 0.001, "onglet : voile 0.35")
	hub.top_bar.tab_clicked.emit("arsenal")
	assert_eq(hub.current_id, "arsenal", "clic sur un onglet")


func test_play_and_back() -> void:
	var hub := await _open("arsenal")
	_pad(hub, JOY_BUTTON_START)
	assert_eq(hub.current_id, "play", "START : JOUER")
	assert_true(hub.top_bar.play_active and hub.top_bar.current == "", "JOUER : bouton blanc, aucun onglet souligné")
	assert_eq(hub.top_bar.play_box.fill, Hub2Style.TEXT)
	_key(hub, KEY_P)
	assert_eq(hub.current_id, "arsenal", "P sur JOUER : retour à l'écran d'avant")
	assert_eq(hub.top_bar.play_box.fill, Hub2Style.YELLOW)
	hub.top_bar.play_clicked.emit()
	assert_eq(hub.current_id, "play")
	hub.back()
	assert_eq(hub.current_id, "arsenal", "B sur JOUER : écran d'avant")
	hub.back()
	assert_eq(hub.current_id, "lab", "B sur un onglet : LABO")
	assert_false(hub.hub_menu.is_open())
	hub.back()
	assert_true(hub.hub_menu.is_open(), "B au LABO : menu du hub")
	assert_false(_action(hub, "ui_page_down"), "menu ouvert : pas d'onglet")
	assert_eq(hub.current_id, "lab")
	_pad(hub, JOY_BUTTON_START)
	assert_false(hub.hub_menu.is_open(), "START : menu fermé")
	hub.back()
	hub.back()
	assert_false(hub.hub_menu.is_open(), "B : menu fermé")


func test_sub_screens_and_breadcrumb() -> void:
	var hub := await _open()
	hub.panels.lab.contracts_button.pressed.emit()
	assert_eq(hub.current_id, "contracts", "CONTRATS : sous-écran")
	assert_true(hub.crumb.visible, "fil d'Ariane")
	assert_eq(hub.crumb.parent_label, "LABO")
	assert_eq(hub.crumb.title, "CONTRATS")
	assert_eq(hub.crumb.position, Vector2(28, 92), "fil d'Ariane en (28, 92)")
	assert_eq(hub.top_bar.current, "lab", "onglet LABO allumé")
	assert_near(hub.veil.spec.color.a, 0.45, 0.001, "CONTRATS : voile 0.45")
	var cr: Rect2 = hub.panels.contracts.content_rect()
	assert_near(cr.position.y, 92.0 + hub.crumb_height() + 14.0, 0.5, "contenu sous le fil d'Ariane (gap 14)")
	assert_eq(cr.position.x, 28.0)
	assert_eq(cr.end.y, 660.0, "bas de <main> : 60 px du bord")
	hub.crumb.parent_clicked.emit()
	assert_eq(hub.current_id, "lab", "« ‹ LABO » : retour")
	hub.open("exchanges")
	hub.back()
	assert_eq(hub.current_id, "lab", "B sur ÉCHANGES : LABO")
	hub.open("contracts")
	_key(hub, KEY_E)
	assert_eq(hub.current_id, "arsenal", "E depuis CONTRATS : onglet après LABO")
	assert_eq(hub.panels.arsenal.content_rect().position.y, 96.0, "onglet : <main> à 96 px")


func test_recap_hides_frame() -> void:
	var hub := await _open()
	hub.open("recap")
	assert_false(hub.top_bar.visible, "récapitulatif : pas de barre du haut")
	assert_false(hub.prompts.visible, "récapitulatif : pas d'invites")
	assert_near(hub.veil.spec.color.a, 0.62, 0.001, "voile 0.62")
	assert_eq(hub.panels.recap.content_rect(), Rect2(48, 40, 1280 - 96, 720 - 104))
	hub.back()
	assert_eq(hub.current_id, "lab", "B : LABO")
	assert_true(hub.top_bar.visible and hub.prompts.visible, "cadre revenu")


func test_prompts_help_and_hint() -> void:
	var hub := await _open()
	Settings.using_pad = true
	assert_eq(Array(hub.prompts.describe()), ["A OUVRIR", "LB RB ONGLETS", "START JOUER"], "invites du LABO (maquette)")
	assert_eq(hub.prompts.help, hub.panels.lab.contracts_button.hint, "aide du bouton qui a le focus (CONTRATS)")
	hub.set_hint("")
	assert_eq(hub.prompts.help, hub.panels.lab.help(), "sans focus : aide de l'écran")
	hub.set_hint("Aide du bouton")
	assert_eq(hub.prompts.help, "Aide du bouton", "aide de l'élément qui a le focus")
	hub.set_hint("")
	assert_eq(hub.prompts.help, hub.panels.lab.help(), "retour à l'aide de l'écran")
	hub.open("arsenal")
	assert_eq(Array(hub.prompts.describe()), ["A INSTALLER", "X RECYCLER", "Y FILTRER", "RS DÉTAILS", "B RETOUR"],
			"invites de l'ARSENAL (maquette, plus la fiche complète)")


func test_register_panel_and_badges() -> void:
	Hub2Screen.register_panel("arsenal", BadgePanel)
	var hub := await _open()
	hub.open("arsenal")
	assert_true(hub.panels.arsenal is BadgePanel, "écran remplacé")
	assert_eq(hub.panels.arsenal.screen_id, "arsenal")
	assert_true(hub.panels.arsenal.hub == hub)
	assert_true(hub.top_bar.badges.get("arsenal", false), "pastille de l'onglet")
	assert_false(hub.top_bar.badges.get("codex", false))
	(hub.panels.arsenal as BadgePanel).eat_back = true
	hub.back()
	assert_eq(hub.current_id, "arsenal", "retour consommé par l'écran")
	hub.back()
	assert_eq(hub.current_id, "lab")


func test_scale_130_rebuilds_and_fits() -> void:
	var hub := await _open("contracts")
	var old_bar := hub.top_bar
	Settings.menu_ui_scale = 1.3
	await wait_frames(2)
	assert_true(hub.top_bar != old_bar, "reconstruit à la nouvelle taille")
	assert_eq(hub.current_id, "contracts", "même écran")
	assert_eq(hub.top_bar.size.y, roundf(72 * 1.3))
	var last: Rect2 = hub.top_bar.tab_rects.codex
	assert_true(last.end.x < hub.top_bar.play_box.position.x, "130 % : onglets avant JOUER")
	assert_true(hub.top_bar.tab_rects.lab.position.x > Hub2Style.px(28 + 230), "130 % : onglets après le joueur")


func test_english() -> void:
	Settings.language = "en"
	var hub := await _open()
	var labels := []
	for t in hub.top_bar.tabs:
		labels.append(t.label)
	assert_eq(labels, ["LAB", "ARSENAL", "INVENTORY", "CODEX"])
	assert_eq(hub.top_bar.play_text.text, "START", "bouton START en anglais")
	hub.open("contracts")
	assert_eq(hub.crumb.parent_label, "LAB")
	assert_eq(hub.crumb.title, "CONTRACTS")


func test_hub_menu_screens() -> void:
	var hub := await _open("codex")
	hub.open_screen("options")
	assert_eq(_host.shown, ["options"], "OPTIONS par-dessus le hub")
	assert_eq(Hub2Screen.last_screen, "codex", "écran gardé pour le retour")
	hub.to_title()
	assert_eq(_host.shown, ["options", "main"])


## Le hub v2 est LE hub : MainMenu.SCREENS.hub (JOUER, retour d'une partie,
## salon, erreurs), plus d'ancien hub ni de réglage pour choisir.
func test_hub_is_the_hub() -> void:
	assert_eq(MainMenu.SCREENS.hub, "res://scripts/ui/hub2/hub2_screen.gd")
	assert_false(MainMenu.SCREENS.has("hub2"), "plus d'écran à part")
	assert_false("hub_v2" in Settings, "plus de réglage caché")
	assert_false(ResourceLoader.exists("res://scripts/ui/hub/hub_screen.gd"), "ancien hub retiré")


## Menu du hub (Hub2Menu) : ses cinq boutons, le focus tourne en boucle.
func test_hub_menu_buttons() -> void:
	var hub := await _open()
	hub.open_menu()
	await wait_frames(2)
	var labels := []
	for b in hub.hub_menu.buttons:
		labels.append(Hub2Menu.button_label(b))
	assert_eq(labels, ["REPRENDRE", "OPTIONS", "DOSSIER DE COMBAT", "ÉCRAN TITRE", "QUITTER LE JEU"])
	assert_eq(hub.get_viewport().gui_get_focus_owner(), hub.hub_menu.resume_button, "focus sur REPRENDRE")
	var first: Hub2Button = hub.hub_menu.buttons[0]
	var last: Hub2Button = hub.hub_menu.buttons[-1]
	assert_eq(first.get_node(first.focus_neighbor_top), last, "▲ sur REPRENDRE : QUITTER LE JEU")
	assert_eq(last.get_node(last.focus_neighbor_bottom), first, "▼ sur QUITTER LE JEU : REPRENDRE")
	hub.hub_menu.resume_button.pressed.emit()
	assert_false(hub.hub_menu.is_open(), "REPRENDRE : menu fermé")


## ÉCRAN TITRE en coop (salon ouvert) : deux appuis, le premier demande
## confirmation ; le second quitte la session.
func test_title_screen_needs_confirmation_online() -> void:
	var hub := await _open()
	Net.host(16700 + OS.get_process_id() % 100, 4, "Hote")
	GameState.set_state(GameState.State.LOBBY)
	hub.open_menu()
	hub.hub_menu.title_button.pressed.emit()
	assert_eq(_host.shown, [], "premier appui : confirmation")
	assert_true(hub.hub_menu.is_title_armed())
	assert_eq(Hub2Menu.button_label(hub.hub_menu.title_button), "CONFIRMER : QUITTER LE SALON")
	assert_eq(Net.mode, Net.Mode.HOST)
	hub.hub_menu.title_button.pressed.emit()
	assert_eq(_host.shown, ["main"], "ÉCRAN TITRE")
	assert_eq(Net.mode, Net.Mode.NONE, "session quittée")
	GameState.reset_to_menu()
