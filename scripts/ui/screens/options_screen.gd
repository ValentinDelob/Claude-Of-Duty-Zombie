extends MenuScreen
## Options : joueur, commandes, vidéo, audio. Chaque changement est appliqué
## et enregistré immédiatement (Settings.apply() + Settings.save_settings()).

const QUALITY_NAMES := ["BASSE", "MOYENNE", "HAUTE"]

var rows := {}  # clé -> MenuOptionRow
var name_edit: LineEdit
var _col: VBoxContainer


func enter(_args := {}) -> void:
	_col = vbox(1)
	_col.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_col.offset_left = 96
	_col.offset_top = 34
	add_child(_col)
	_col.add_child(title("OPTIONS", 46))

	_section("JOUEUR")
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 0)
	var nl := UiStyle.label("NOM DU JOUEUR", 22, MenuStyle.IDLE, "impact")
	nl.custom_minimum_size = Vector2(MenuOptionRow.VALUE_X, 0)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(16, 0)
	name_row.add_child(pad)
	nl.custom_minimum_size.x -= 16
	name_row.add_child(nl)
	name_edit = MenuStyle.line_edit(Settings.player_name, "Survivant", 16)
	name_edit.custom_minimum_size = Vector2(330, 36)
	name_edit.add_theme_font_size_override("font_size", 20)
	name_edit.text_changed.connect(_on_name_changed)
	name_edit.text_submitted.connect(func(_t): _on_name_changed(name_edit.text, true))
	name_edit.focus_exited.connect(func(): _on_name_changed(name_edit.text, true))
	name_edit.focus_entered.connect(func(): menu.set_hint("Nom affiché aux autres survivants (16 caractères)."))
	name_row.add_child(name_edit)
	_col.add_child(name_row)

	_section("COMMANDES")
	_add("mouse_sensitivity", MenuOptionRow.make_range("SENSIBILITÉ SOURIS", Settings.mouse_sensitivity, 0.05, 1.0, 0.05,
			func(v): return "%.2f" % v), "Vitesse de rotation de la vue à la souris.")
	_add("invert_y", MenuOptionRow.make_toggle("INVERSER L'AXE VERTICAL", Settings.invert_y), "Pousser la souris vers l'avant fait baisser la vue.")

	_section("VIDÉO")
	_add("fov", MenuOptionRow.make_range("CHAMP DE VISION", Settings.fov, 60.0, 110.0, 5.0,
			func(v): return "%d°" % int(v)), "Angle de vue horizontal en jeu.")
	_add("fullscreen", MenuOptionRow.make_toggle("PLEIN ÉCRAN", Settings.fullscreen), "Plein écran ou fenêtre.")
	_add("vsync", MenuOptionRow.make_toggle("SYNCHRO VERTICALE", Settings.vsync), "Supprime les déchirures d'image (peut ajouter un peu de latence).")
	_add("quality", MenuOptionRow.make_choice("QUALITÉ GRAPHIQUE", PackedStringArray(QUALITY_NAMES), int(Settings.quality)),
			"Basse : cartes graphiques modestes. Haute : ombres et effets complets.")
	_add("film_grain", MenuOptionRow.make_range("GRAIN DE FILM", Settings.film_grain, 0.0, 1.0, 0.1,
			func(v): return "DÉSACTIVÉ" if v < 0.05 else "%d %%" % int(round(v * 100.0))),
			"Grain de pellicule en jeu, comme dans Black Ops (0 : image nette).")

	_section("AUDIO")
	var pct := func(v): return "%d %%" % int(round(v * 100.0))
	_add("master_volume", MenuOptionRow.make_range("VOLUME GÉNÉRAL", Settings.master_volume, 0.0, 1.0, 0.05, pct), "Volume de tous les sons.")
	_add("music_volume", MenuOptionRow.make_range("MUSIQUE", Settings.music_volume, 0.0, 1.0, 0.05, pct), "Musiques et ambiances.")
	_add("sfx_volume", MenuOptionRow.make_range("EFFETS SONORES", Settings.sfx_volume, 0.0, 1.0, 0.05, pct), "Armes, zombies, machines.")

	_col.add_child(text("", 4))
	var back_btn := button("RETOUR", back, "Les réglages sont enregistrés automatiquement.")
	_col.add_child(back_btn)
	focus_later(rows.mouse_sensitivity)


func _section(t: String) -> void:
	var l := MenuStyle.section(t)
	l.custom_minimum_size = Vector2(0, 22)
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 16)
	m.add_child(l)
	_col.add_child(m)


func _add(key: String, row: MenuOptionRow, hint: String) -> void:
	rows[key] = row
	_col.add_child(row)
	row.value_changed.connect(func(v): _on_changed(key, v))
	row.focus_entered.connect(func(): menu.set_hint(hint))


func _on_changed(key: String, v: float) -> void:
	match key:
		"invert_y", "fullscreen", "vsync":
			Settings.set(key, v > 0.5)
		"quality":
			Settings.quality = int(v) as Settings.Quality
		_:
			Settings.set(key, v)
	Settings.apply()
	Settings.save_settings()


func _on_name_changed(t: String, final := false) -> void:
	var clean := Net._clean_name(t)
	if final and name_edit.text != clean:
		name_edit.text = clean
	if clean != Settings.player_name:
		Settings.player_name = clean
		Settings.save_settings()


func back() -> void:
	_on_name_changed(name_edit.text, true)
	menu.go_back()
