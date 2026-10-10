extends MenuScreen
## Dossier de combat : niveau et progression du profil (PlayerProfile,
## GAME_CONCEPT §4.15 ; en attendant le hub) et statistiques cumulées du
## joueur (CareerStats).

var rows: Dictionary = {}  # clé -> Label de la valeur
## Niveau du profil et progression vers le niveau suivant (tests).
var level_label: Label
var progress_label: Label
var progress_bar: ProgressBar


func enter(_args := {}) -> void:
	var col := vbox(6)
	col.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	col.offset_left = 110
	col.offset_top = -280
	add_child(col)
	col.add_child(title(Lang.t("DOSSIER DE COMBAT", "COMBAT RECORD"), 44))
	col.add_child(text(Settings.player_name.to_upper(), 20, UiStyle.DIM))
	col.add_child(text("", 8))
	# Niveau du profil (§4.15) : XP totale, barre vers le niveau suivant.
	var pr := ProfileStore.load_profile()
	var lvl := pr.level()
	level_label = UiStyle.label(Lang.t("NIVEAU %d", "LEVEL %d") % lvl
			+ (Lang.t(" (MAXIMUM)", " (MAX)") if pr.is_max_level() else ""), 26, UiStyle.GOLD, "impact")
	col.add_child(level_label)
	progress_bar = ProgressBar.new()
	progress_bar.show_percentage = false
	progress_bar.custom_minimum_size = Vector2(560, 10)
	var p := MatchResult.level_progress(pr.xp)
	progress_bar.max_value = maxi(p.y, 1)
	progress_bar.value = p.x if p.y > 0 else 1
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.5)
	var fill := StyleBoxFlat.new()
	fill.bg_color = XpSystem.XP_COLOR
	progress_bar.add_theme_stylebox_override("background", bg)
	progress_bar.add_theme_stylebox_override("fill", fill)
	col.add_child(progress_bar)
	progress_label = text(MatchResult.progress_text(pr.xp), 18, UiStyle.DIM)
	col.add_child(progress_label)
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
