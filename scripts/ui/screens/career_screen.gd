extends MenuScreen
## Dossier de combat : statistiques cumulées du joueur (CareerStats).

var rows: Dictionary = {}  # clé -> Label de la valeur


func enter(_args := {}) -> void:
	var col := vbox(6)
	col.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	col.offset_left = 110
	col.offset_top = -250
	add_child(col)
	col.add_child(title(Lang.t("DOSSIER DE COMBAT", "COMBAT RECORD"), 44))
	col.add_child(text(Settings.player_name.to_upper(), 20, UiStyle.DIM))
	col.add_child(text("", 8))
	var stats := CareerStats.load_stats()
	for f in CareerStats.FIELDS:
		var line := HBoxContainer.new()
		line.custom_minimum_size = Vector2(560, 0)
		var name_l := UiStyle.label(Lang.t(f[1], f[2]), 22, UiStyle.BONE)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(name_l)
		var val := UiStyle.label(CareerStats.format_value(f[0], stats[f[0]]), 24, UiStyle.GOLD, "impact")
		line.add_child(val)
		rows[f[0]] = val
		col.add_child(line)
	col.add_child(text("", 10))
	var b := button(Lang.t("RETOUR", "BACK"), back)
	col.add_child(b)
	focus_later(b)


func back() -> void:
	menu.go_back()
