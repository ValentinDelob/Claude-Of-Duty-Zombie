extends MenuScreen
## Options, en onglets (comme les sous-menus d'options de BO1) : JEU (joueur et
## personnage, langue, taille de l'interface de l'éditeur de cartes), COMMANDES
## (sensibilité, touches), GRAPHISMES, SON. Chaque changement est
## appliqué et enregistré immédiatement (Settings.apply() +
## Settings.save_settings()). Le même écran sert au menu principal, au menu
## pause de la partie et à l'éditeur de cartes (hôte : MenuHost ; PauseMenu,
## EditorOptions ; `args.in_game`).
##
## Clavier : ◄ / ► sur les onglets (ou Page préc. / Page suiv. partout)
## changent d'onglet, ▲ / ▼ parcourent la page (qui défile si besoin).
## Textes en français ou en anglais selon Settings.language (Lang.t).

const TABS := ["game", "controls", "graphics", "audio"]
## Libellés des actions réaffectables [fr, en] (ordre : Settings.REBINDABLE).
const ACTION_NAMES := {
	"move_forward": ["AVANCER", "MOVE FORWARD"],
	"move_back": ["RECULER", "MOVE BACK"],
	"move_left": ["GAUCHE", "STRAFE LEFT"],
	"move_right": ["DROITE", "STRAFE RIGHT"],
	"jump": ["SAUTER", "JUMP"],
	"crouch": ["S'ACCROUPIR / S'ALLONGER", "CROUCH / PRONE"],
	"sprint": ["SPRINTER", "SPRINT"],
	"fire": ["TIRER", "FIRE"],
	"aim": ["VISER", "AIM DOWN SIGHT"],
	"reload": ["RECHARGER", "RELOAD"],
	"interact": ["INTERAGIR / ACHETER", "USE / BUY"],
	"melee": ["COUTEAU", "KNIFE"],
	"grenade": ["GRENADE", "GRENADE"],
	"switch_weapon": ["CHANGER D'ARME", "SWITCH WEAPON"],
	"weapon_1": ["ARME 1", "WEAPON 1"],
	"weapon_2": ["ARME 2", "WEAPON 2"],
	"weapon_3": ["ARME 3", "WEAPON 3"],
	"inventory": ["INVENTAIRE", "INVENTORY"],
	"scoreboard": ["TABLEAU DES SCORES", "SCOREBOARD"],
}
const PAGE_SIZE := Vector2(870, 440)

var rows := {}  # clé -> MenuOptionRow (onglet affiché)
var bind_rows := {}  # action -> MenuBindRow (onglet COMMANDES)
var tab_buttons := {}  # onglet -> MenuActionButton
var tab := "game"
var name_edit: LineEdit
var reset_button: Button
var back_button: Button
var scroll: ScrollContainer
var page: VBoxContainer
var in_game := false
var _col: VBoxContainer
var _focusables: Array[Control] = []
## Réaffectation en cours : ligne, case, image du clic qui l'a lancée.
var _capture: MenuBindRow
var _capture_slot := 0
var _capture_frame := -1


static func action_name(action: String) -> String:
	var n: Array = ACTION_NAMES.get(action, [action, action])
	return Lang.t(n[0], n[1])


static func tab_label(t: String) -> String:
	match t:
		"game": return Lang.t("JEU", "GAME")
		"controls": return Lang.t("COMMANDES", "CONTROLS")
		"graphics": return Lang.t("GRAPHISMES", "GRAPHICS")
		"audio": return Lang.t("SON", "AUDIO")
	return t.to_upper()


func enter(args := {}) -> void:
	in_game = args.get("in_game", false)
	tab = args.get("tab", "game")
	if not tab in TABS:
		tab = "game"
	_build()
	var f: String = args.get("focus", "")
	focus_later(rows[f] if rows.has(f) else tab_buttons[tab])


func exit() -> void:
	_end_capture()


func _build() -> void:
	_col = vbox(1)
	_col.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_col.offset_left = 96
	_col.offset_top = 34
	add_child(_col)
	_col.add_child(title("OPTIONS", 46))
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 4)
	_col.add_child(bar)
	for t in TABS:
		var b := button(tab_label(t), func(): _select_tab(t), _tab_hint()) as MenuActionButton
		b.font_size = 24
		b.gui_input.connect(_on_tab_input)
		tab_buttons[t] = b
		bar.add_child(b)
	_col.add_child(text("", 4))
	scroll = ScrollContainer.new()
	scroll.custom_minimum_size = PAGE_SIZE
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	_style_scrollbar(scroll.get_v_scroll_bar())
	_col.add_child(scroll)
	_col.add_child(text("", 4))
	back_button = button(Lang.t("RETOUR", "BACK"), back,
			Lang.t("Les réglages sont enregistrés automatiquement.", "Settings are saved automatically."))
	_col.add_child(back_button)
	_select_tab(tab, false)


func _tab_hint() -> String:
	return Lang.t("◄ / ► : changer d'onglet.", "◄ / ►: switch tab.")


func _style_scrollbar(bar: VScrollBar) -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.03, 0.03, 0.6)
	bg.content_margin_left = 4
	bg.content_margin_right = 4
	bar.add_theme_stylebox_override("scroll", bg)
	var grab := StyleBoxFlat.new()
	grab.bg_color = Color(0.5, 0.08, 0.06)
	bar.add_theme_stylebox_override("grabber", grab)
	var hi := grab.duplicate()
	hi.bg_color = MenuStyle.HOVER
	bar.add_theme_stylebox_override("grabber_highlight", hi)
	bar.add_theme_stylebox_override("grabber_pressed", hi)


# --------------------------------------------------------------------------
# Onglets
# --------------------------------------------------------------------------

func _select_tab(t: String, sound := true) -> void:
	_end_capture()
	if sound and t != tab:
		Audio.play_ui("menu_whoosh", -16.0)
	tab = t
	for k in tab_buttons:
		tab_buttons[k].selected = k == t
	rows.clear()
	bind_rows.clear()
	name_edit = null
	reset_button = null
	if page:
		scroll.remove_child(page)
		page.queue_free()
	page = vbox(1)
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(page)
	scroll.scroll_vertical = 0
	_focusables.clear()
	match t:
		"game": _page_game()
		"controls": _page_controls()
		"graphics": _page_graphics()
		"audio": _page_audio()
	_link_focus()


## Onglet voisin (`dir` = -1 / +1), le focus passe sur son bouton.
func switch_tab(dir: int) -> void:
	var i := posmod(TABS.find(tab) + dir, TABS.size())
	_select_tab(TABS[i])
	tab_buttons[tab].grab_focus()


func _on_tab_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_left", true):
		switch_tab(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right", true):
		switch_tab(1)
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if _capture != null or not is_visible_in_tree():
		return
	if event.is_action_pressed("ui_page_down"):
		switch_tab(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_page_up"):
		switch_tab(-1)
		get_viewport().set_input_as_handled()


## Voisins de focus explicites : onglet actif <-> page <-> RETOUR.
func _link_focus() -> void:
	var tb: Control = tab_buttons[tab]
	var first: Control = _focusables[0] if not _focusables.is_empty() else back_button
	var last: Control = _focusables[-1] if not _focusables.is_empty() else tb
	for k in tab_buttons:
		var b: Control = tab_buttons[k]
		b.focus_neighbor_bottom = b.get_path_to(first)
		b.focus_neighbor_top = b.get_path_to(back_button)
	for i in _focusables.size():
		var c := _focusables[i]
		c.focus_neighbor_top = c.get_path_to(_focusables[i - 1] if i > 0 else tb)
		c.focus_neighbor_bottom = c.get_path_to(_focusables[i + 1] if i < _focusables.size() - 1 else back_button)
	back_button.focus_neighbor_top = back_button.get_path_to(last)
	back_button.focus_neighbor_bottom = back_button.get_path_to(tb)


# --------------------------------------------------------------------------
# Pages
# --------------------------------------------------------------------------

func _page_game() -> void:
	_section(Lang.t("JOUEUR", "PLAYER"))
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 0)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(16, 0)
	name_row.add_child(pad)
	var nl := UiStyle.label(Lang.t("NOM DU JOUEUR", "PLAYER NAME"), 22, MenuStyle.IDLE, "impact")
	nl.custom_minimum_size = Vector2(MenuOptionRow.VALUE_X - 16, 0)
	name_row.add_child(nl)
	name_edit = MenuStyle.line_edit(Settings.player_name, Lang.t("Survivant", "Survivor"), 16)
	name_edit.custom_minimum_size = Vector2(330, 36)
	name_edit.add_theme_font_size_override("font_size", 20)
	name_edit.text_changed.connect(_on_name_changed)
	name_edit.text_submitted.connect(func(_t): _on_name_changed(name_edit.text, true))
	name_edit.focus_exited.connect(func(): _on_name_changed(name_edit.text, true))
	var name_hint := Lang.t("Nom affiché aux autres survivants (16 caractères).", "Name shown to the other survivors (16 characters).")
	if in_game:
		name_hint += Lang.t(" Appliqué à la prochaine partie.", " Applies from the next game.")
	name_edit.focus_entered.connect(func(): menu.set_hint(name_hint))
	name_row.add_child(name_edit)
	page.add_child(name_row)
	_focusables.append(name_edit)
	_add("character", MenuOptionRow.make_choice(Lang.t("PERSONNAGE", "CHARACTER"), character_choices(),
			character_choice_index(Settings.character)), func(): return character_hint(Settings.character))
	_add("language", MenuOptionRow.make_choice("LANGUE / LANGUAGE", PackedStringArray(["FRANÇAIS", "ENGLISH"]),
			maxi(Settings.LANGUAGES.find(Settings.language), 0)),
			Lang.t("Langue de l'interface et des voix des personnages.", "Language of the interface and of the characters' voices."))
	_section(Lang.t("INTERFACE", "INTERFACE"))
	_add("editor_ui_scale", MenuOptionRow.make_range(Lang.t("TAILLE DE L'INTERFACE DE L'ÉDITEUR", "MAP EDITOR UI SIZE"),
			Settings.editor_ui_scale, Settings.EDITOR_UI_SCALE_RANGE.x, Settings.EDITOR_UI_SCALE_RANGE.y,
			Settings.EDITOR_UI_SCALE_STEP, func(v): return "%d %%" % int(round(v * 100.0))),
			Lang.t("Taille des textes et panneaux de l'éditeur de cartes (%d %% par défaut). Dans l'éditeur : Ctrl + / Ctrl - / Ctrl 0."
				% roundi(Settings.EDITOR_UI_SCALE_DEFAULT * 100.0),
				"Size of the map editor's text and panels (%d%% by default). In the editor: Ctrl + / Ctrl - / Ctrl 0."
				% roundi(Settings.EDITOR_UI_SCALE_DEFAULT * 100.0)))


func _page_controls() -> void:
	var pct := func(v): return "%d %%" % int(round(v * 100.0))
	_section(Lang.t("VISÉE", "LOOK"))
	_add("mouse_sensitivity", MenuOptionRow.make_range(Lang.t("SENSIBILITÉ SOURIS", "MOUSE SENSITIVITY"),
			Settings.mouse_sensitivity, 0.05, 1.0, 0.05, func(v): return "%.2f" % v),
			Lang.t("Vitesse de rotation de la vue à la souris.", "How fast the view turns with the mouse."))
	_add("pad_look_sensitivity", MenuOptionRow.make_range(Lang.t("SENSIBILITÉ MANETTE", "CONTROLLER SENSITIVITY"),
			Settings.pad_look_sensitivity, Settings.PAD_SENSITIVITY_RANGE.x, Settings.PAD_SENSITIVITY_RANGE.y, 0.1, pct),
			Lang.t("Vitesse de rotation de la vue au stick droit de la manette.", "How fast the view turns with the controller's right stick."))
	_add("ads_sensitivity", MenuOptionRow.make_range(Lang.t("SENSIBILITÉ EN VISÉE", "AIM SENSITIVITY"),
			Settings.ads_sensitivity, Settings.ADS_SENSITIVITY_RANGE.x, Settings.ADS_SENSITIVITY_RANGE.y, 0.05, pct),
			Lang.t("Vitesse de la vue en visée, par rapport à celle de l'arme (100 % : comme BO1). Souris et manette.",
				"View speed while aiming, relative to the weapon's own (100%: like BO1). Mouse and controller."))
	_add("invert_y", MenuOptionRow.make_toggle(Lang.t("INVERSER L'AXE VERTICAL", "INVERT VERTICAL AXIS"), Settings.invert_y),
			Lang.t("Pousser la souris ou le stick droit vers l'avant fait baisser la vue.",
				"Pushing the mouse or the right stick forward looks down."))
	for r in rows.values():
		r.wheel_nudges = false  # la page défile à la molette
	_section(Lang.t("TOUCHES ET BOUTONS", "KEYS AND BUTTONS"))
	page.add_child(MenuBindRow.make_header())
	for action in Settings.REBINDABLE:
		var br := MenuBindRow.make(action, action_name(action))
		br.action_names = action_name
		br.rebind_requested.connect(_on_rebind_requested)
		br.clear_requested.connect(_on_clear_requested)
		br.focus_entered.connect(func(): menu.set_hint(bind_hint(action, br.shared_note(br.slot))))
		br.slot_changed.connect(func(r: MenuBindRow): menu.set_hint(bind_hint(action, r.shared_note(r.slot))))
		bind_rows[action] = br
		page.add_child(br)
		_focusables.append(br)
	page.add_child(text("", 4))
	reset_button = button(Lang.t("RÉTABLIR LES COMMANDES PAR DÉFAUT", "RESTORE DEFAULT CONTROLS"), reset_keys,
			Lang.t("Toutes les actions reprennent leur touche et leur bouton de manette d'origine.",
				"Every action gets its original key and controller button back."))
	(reset_button as MenuActionButton).font_size = 24
	page.add_child(reset_button)
	_focusables.append(reset_button)


func _page_graphics() -> void:
	var pct := func(v): return "%d %%" % int(round(v * 100.0))
	_section(Lang.t("AFFICHAGE", "DISPLAY"))
	_add("fullscreen", MenuOptionRow.make_toggle(Lang.t("PLEIN ÉCRAN", "FULLSCREEN"), Settings.fullscreen),
			Lang.t("Plein écran ou fenêtre.", "Fullscreen or windowed."))
	_add("vsync", MenuOptionRow.make_toggle(Lang.t("SYNCHRO VERTICALE", "VERTICAL SYNC"), Settings.vsync),
			Lang.t("Supprime les déchirures d'image (peut ajouter un peu de latence).", "Removes screen tearing (may add a little latency)."))
	var fps_names := PackedStringArray()
	for f in Settings.FPS_LIMITS:
		fps_names.append(Lang.t("ILLIMITÉE", "UNLIMITED") if f == 0 else "%d" % f)
	_add("max_fps", MenuOptionRow.make_choice(Lang.t("IMAGES PAR SECONDE (MAX.)", "FRAME RATE LIMIT"), fps_names,
			maxi(Settings.FPS_LIMITS.find(Settings.max_fps), 0)),
			Lang.t("Nombre maximal d'images par seconde (moins de chaleur et de bruit).", "Maximum frames per second (less heat and fan noise)."))
	_add("render_scale", MenuOptionRow.make_range(Lang.t("ÉCHELLE DE RENDU 3D", "3D RENDER SCALE"), Settings.render_scale,
			Settings.RENDER_SCALE_RANGE.x, Settings.RENDER_SCALE_RANGE.y, 0.05, pct),
			Lang.t("Définition de l'image 3D (l'interface reste nette). Moins : plus d'images par seconde.",
				"Resolution of the 3D image (the interface stays sharp). Lower: higher frame rate."))
	_section(Lang.t("IMAGE", "PICTURE"))
	_add("quality", MenuOptionRow.make_choice(Lang.t("QUALITÉ GRAPHIQUE", "GRAPHICS QUALITY"),
			PackedStringArray([Lang.t("BASSE", "LOW"), Lang.t("MOYENNE", "MEDIUM"), Lang.t("HAUTE", "HIGH")]), int(Settings.quality)),
			Lang.t("Basse : cartes graphiques modestes. Haute : ombres et effets complets.",
				"Low: modest graphics cards. High: full shadows and effects."))
	_add("fov", MenuOptionRow.make_range(Lang.t("CHAMP DE VISION", "FIELD OF VIEW"), Settings.fov, 60.0, 110.0, 5.0,
			func(v): return "%d°" % int(v)), Lang.t("Angle de vue horizontal en jeu.", "Horizontal view angle in game."))
	_add("brightness", MenuOptionRow.make_range(Lang.t("LUMINOSITÉ", "BRIGHTNESS"), Settings.brightness,
			Settings.BRIGHTNESS_RANGE.x, Settings.BRIGHTNESS_RANGE.y, 0.05, pct),
			Lang.t("Gamma de l'image en jeu, comme dans Black Ops (100 % : réglage d'origine).",
				"In-game picture gamma, as in Black Ops (100%: original setting)."))
	_add("film_grain", MenuOptionRow.make_range(Lang.t("GRAIN DE FILM", "FILM GRAIN"), Settings.film_grain, 0.0, 1.0, 0.1,
			func(v): return Lang.t("DÉSACTIVÉ", "OFF") if v < 0.05 else "%d %%" % int(round(v * 100.0))),
			Lang.t("Grain de pellicule en jeu, comme dans Black Ops (0 : image nette).", "In-game film grain, as in Black Ops (0: clean picture)."))
	_add("outline", MenuOptionRow.make_toggle(Lang.t("CONTOUR", "OUTLINE"), Settings.outline),
			Lang.t("Trait noir autour des personnages et des marches de cubes." if ScreenOutline.supported()
				else "Indisponible avec ce moteur de rendu (Forward+ nécessaire).",
				"Black line around characters and cube steps." if ScreenOutline.supported()
				else "Unavailable with this renderer (Forward+ required)."))


func _page_audio() -> void:
	var pct := func(v): return "%d %%" % int(round(v * 100.0))
	_section(Lang.t("VOLUME", "VOLUME"))
	_add("master_volume", MenuOptionRow.make_range(Lang.t("VOLUME GÉNÉRAL", "MASTER VOLUME"), Settings.master_volume, 0.0, 1.0, 0.05, pct),
			Lang.t("Volume de tous les sons.", "Volume of every sound."))
	_add("music_volume", MenuOptionRow.make_range(Lang.t("MUSIQUE", "MUSIC"), Settings.music_volume, 0.0, 1.0, 0.05, pct),
			Lang.t("Musiques et ambiances.", "Music and ambience."))
	_add("sfx_volume", MenuOptionRow.make_range(Lang.t("EFFETS SONORES", "SOUND EFFECTS"), Settings.sfx_volume, 0.0, 1.0, 0.05, pct),
			Lang.t("Armes, zombies, machines.", "Weapons, zombies, machines."))
	_add("voice_volume", MenuOptionRow.make_range(Lang.t("VOIX DES PERSONNAGES", "CHARACTER VOICES"), Settings.voice_volume, 0.0, 1.0, 0.05, pct),
			Lang.t("Volume des répliques des personnages (plus fortes que le reste par défaut).",
				"Volume of the characters' lines (louder than everything else by default)."))


func _section(t: String) -> void:
	var l := MenuStyle.section(t)
	l.custom_minimum_size = Vector2(0, 22)
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 16)
	m.add_child(l)
	page.add_child(m)


## `hint` : texte d'aide, ou fonction qui le rend (aide qui suit la valeur).
func _add(key: String, row: MenuOptionRow, hint: Variant) -> void:
	rows[key] = row
	page.add_child(row)
	_focusables.append(row)
	row.value_changed.connect(func(v): _on_changed(key, v))
	row.focus_entered.connect(func(): menu.set_hint(hint.call() if hint is Callable else String(hint)))


## Valeurs du sélecteur de personnage : « automatique » puis les sept.
static func character_choices() -> PackedStringArray:
	var out := PackedStringArray([CharacterDB.short_name(CharacterDB.AUTO)])
	for id in CharacterDB.IDS:
		out.append(CharacterDB.short_name(id))
	return out


static func character_choice_index(choice: String) -> int:
	return CharacterDB.IDS.find(choice) + 1  # « auto » (absent de IDS) : 0


static func character_of_choice_index(i: int) -> String:
	return CharacterDB.IDS[i - 1] if i >= 1 and i <= CharacterDB.IDS.size() else CharacterDB.AUTO


## Aide du sélecteur : nom complet du personnage choisi.
func character_hint(choice: String) -> String:
	var h := Lang.t("Automatique : l'hôte vous attribue un personnage libre au lancement de la partie.",
			"Automatic: the host gives you a free character when the game starts.")
	if choice in CharacterDB.IDS:
		h = Lang.t("Vous incarnez %s.", "You play as %s.") % CharacterDB.display_name(choice)
	if in_game:
		h += Lang.t(" Appliqué à la prochaine partie.", " Applies from the next game.")
	return h


func _on_changed(key: String, v: float) -> void:
	match key:
		"invert_y", "fullscreen", "vsync", "outline":
			Settings.set(key, v > 0.5)
		"quality":
			Settings.quality = int(v) as Settings.Quality
		"max_fps":
			Settings.max_fps = Settings.FPS_LIMITS[clampi(int(v), 0, Settings.FPS_LIMITS.size() - 1)]
		"language":
			Settings.language = Settings.LANGUAGES[clampi(int(v), 0, Settings.LANGUAGES.size() - 1)]
			# Tout l'écran est réécrit dans la nouvelle langue.
			_rebuild.call_deferred("language")
		"character":
			Settings.character = character_of_choice_index(int(v))
			if menu:
				menu.set_hint(character_hint(Settings.character))
		_:
			Settings.set(key, v)
	Settings.apply()
	Settings.save_settings()


## Reconstruit l'écran (changement de langue), même onglet, focus sur `focus`.
func _rebuild(focus := "") -> void:
	if not is_inside_tree():
		return
	_end_capture()
	remove_child(_col)
	_col.queue_free()
	page = null
	tab_buttons.clear()
	_build()
	focus_later(rows[focus] if rows.has(focus) else tab_buttons[tab])
	if menu:
		menu.set_hint("")


func _on_name_changed(t: String, final := false) -> void:
	if name_edit == null:
		return
	@warning_ignore("static_called_on_instance")
	var clean := Net._clean_name(t)
	if final and name_edit.text != clean:
		name_edit.text = clean
	if clean != Settings.player_name:
		Settings.player_name = clean
		Settings.save_settings()


# --------------------------------------------------------------------------
# Réaffectation des touches
# --------------------------------------------------------------------------

## Réaffectation en cours ?
func capturing() -> bool:
	return _capture != null


## Aide d'une ligne de commande (noms des boutons de la manette courante).
## `shared` : phrase de la case choisie si sa commande sert aussi à d'autres
## actions (MenuBindRow.shared_note), qui passe alors avant l'aide.
func bind_hint(action: String, shared := "") -> String:
	if shared != "":
		return shared
	var style := Settings.pad_style()
	var a := PadNames.button_label(JOY_BUTTON_A, style)
	var x := PadNames.button_label(JOY_BUTTON_X, style)
	var hint := Lang.t("Entrée, %s ou clic : changer. ◄ / ► : choisir la case (deux touches, deux boutons). Retour arrière ou %s : effacer." % [a, x],
			"Enter, %s or click: change. ◄ / ►: pick a box (two keys, two buttons). Backspace or %s: clear." % [a, x])
	if action == "switch_weapon":
		hint += Lang.t(" La molette change aussi d'arme, sauf un cran affecté à une action.",
				" The mouse wheel also switches weapons, except a notch bound to an action.")
	elif action in Settings.MOVE_ACTIONS:
		hint += Lang.t(" Stick gauche : déplacement progressif.", " Left stick: analog movement.")
	return hint


func _on_rebind_requested(row: MenuBindRow, slot: int) -> void:
	if _capture != null:
		return
	Audio.play_ui(MenuStyle.SND_SELECT, MenuStyle.VOL_SELECT)
	_capture = row
	_capture_slot = slot
	_capture_frame = Engine.get_process_frames()
	row.set_capturing(slot)
	if MenuBindRow.is_pad_slot(slot):
		var start := PadNames.button_label(JOY_BUTTON_START, Settings.pad_style())
		menu.set_hint(Lang.t("%s : appuyez sur un bouton ou une gâchette de la manette (%s ou Échap : annuler)." % [row.label_text, start],
				"%s: press a controller button or trigger (%s or Esc: cancel)." % [row.label_text, start]))
	else:
		var b := PadNames.button_label(JOY_BUTTON_B, Settings.pad_style())
		menu.set_hint(Lang.t("%s : appuyez sur une touche, un bouton de la souris ou tournez la molette (Échap ou %s : annuler)." % [row.label_text, b],
				"%s: press a key or a mouse button, or roll the wheel (Esc or %s: cancel)." % [row.label_text, b]))


func _on_clear_requested(row: MenuBindRow, slot: int) -> void:
	var pad := MenuBindRow.is_pad_slot(slot)
	var i := MenuBindRow.slot_index(slot)
	if Settings.binding(row.action, pad, i) == "":
		Audio.play_ui("ui_error", -14.0)
		return
	Settings.clear_binding(row.action, pad, i)
	Settings.save_settings()
	Audio.play_ui(MenuStyle.SND_BACK, -8.0)
	row.flash()
	menu.set_hint(Lang.t("%s : bouton de manette effacé." % row.label_text, "%s: controller button cleared." % row.label_text) if pad
			else Lang.t("%s : touche effacée." % row.label_text, "%s: key cleared." % row.label_text))


## Pendant une réaffectation, toutes les entrées reviennent à l'écran : la
## commande suivante du bon périphérique est affectée. Case touche : touche
## ou bouton de souris, Échap ou B / Rond annule. Case manette : bouton,
## gâchette ou stick gauche, Échap ou Start / Options annule (B se réaffecte).
func _input(event: InputEvent) -> void:
	if _capture == null:
		return
	get_viewport().set_input_as_handled()
	Settings.note_input(event)
	# L'appui qui a lancé la saisie n'est pas une réponse.
	if Engine.get_process_frames() == _capture_frame:
		return
	var pad := MenuBindRow.is_pad_slot(_capture_slot)
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).physical_keycode == KEY_ESCAPE or (event as InputEventKey).keycode == KEY_ESCAPE:
			_cancel_capture()
		elif not pad:
			@warning_ignore("static_called_on_instance")
			_finish_capture(Settings.code_from_event(event))
	elif event is InputEventMouseButton and event.pressed:
		if not pad:
			@warning_ignore("static_called_on_instance")
			_finish_capture(Settings.code_from_event(event))
	elif event is InputEventJoypadButton and event.pressed:
		var jb := (event as InputEventJoypadButton).button_index
		if jb == JOY_BUTTON_START or (not pad and jb == JOY_BUTTON_B):
			_cancel_capture()
		elif pad:
			@warning_ignore("static_called_on_instance")
			_finish_capture(Settings.code_from_event(event))
	elif event is InputEventJoypadMotion and pad:
		# Gâchette ou stick gauche bien enfoncés (code « » en deçà).
		@warning_ignore("static_called_on_instance")
		_finish_capture(Settings.code_from_event(event))


func _cancel_capture() -> void:
	Audio.play_ui(MenuStyle.SND_BACK, -6.0)
	var row := _capture
	_end_capture()
	menu.set_hint(Lang.t("Réaffectation annulée.", "Rebinding cancelled."))
	row.grab_focus()


func _finish_capture(code: String) -> void:
	if code == "":
		return
	var row := _capture
	var slot := _capture_slot
	_end_capture()
	# Commande déjà utilisée ailleurs : partagée (rien n'est retiré), les
	# lignes qui l'ont aussi s'éclairent et l'aide le dit.
	var others := Settings.bind(row.action, code, MenuBindRow.slot_index(slot))
	Settings.save_settings()
	Audio.play_ui(MenuStyle.SND_SELECT, MenuStyle.VOL_SELECT)
	row.flash()
	row.grab_focus()
	@warning_ignore("static_called_on_instance")
	var key := Settings.code_label(code, Settings.pad_style())
	var hint := Lang.t("%s : %s." % [row.label_text, key], "%s: %s." % [row.label_text, key])
	if not others.is_empty():
		var names := PackedStringArray()
		for a in others:
			names.append(action_name(a))
			if bind_rows.has(a):
				bind_rows[a].flash()
		var list := ", ".join(names)
		hint = Lang.t("« %s » affectée à %s, et toujours à %s : un même appui déclenche chacune. Pour la retirer, effacez-la sur l'autre ligne." % [key, row.label_text, list],
				"\"%s\" bound to %s, and still to %s: one press triggers each. To remove it, clear it on the other row." % [key, row.label_text, list])
	# Molette haut / bas sur une autre action : ce sens ne change plus d'arme.
	@warning_ignore("static_called_on_instance")
	if row.action != "switch_weapon" and (code == Settings.mouse_code(MOUSE_BUTTON_WHEEL_UP)
			or code == Settings.mouse_code(MOUSE_BUTTON_WHEEL_DOWN)):
		hint += Lang.t(" Ce cran de molette ne change plus d'arme.", " This wheel notch no longer switches weapons.")
	menu.set_hint(hint)


func _end_capture() -> void:
	if _capture != null and is_instance_valid(_capture):
		_capture.set_capturing(-1)
	_capture = null


func reset_keys() -> void:
	_end_capture()
	Settings.reset_bindings()
	Settings.save_settings()
	for r in bind_rows.values():
		r.flash()
	menu.set_hint(Lang.t("Commandes par défaut rétablies (clavier et manette).", "Default controls restored (keyboard and controller)."))


func back() -> void:
	if _capture != null:
		_cancel_capture()
		return
	if name_edit:
		_on_name_changed(name_edit.text, true)
	menu.go_back()
