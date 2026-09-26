extends MenuScreen
## Sélection de la carte (SOLO), façon Black Ops : liste des cartes à gauche,
## dossier de la carte survolée à droite (plan, nom, description, lieux).
## Valider une carte lance la partie ; le choix est mémorisé (Settings.last_map).

var buttons: Dictionary = {}  # id -> MenuActionButton
var selected := ""
var _preview: TextureRect
var _name: Label
var _desc: Label
var _zones: Label
var _col: VBoxContainer
var _leaving := false


func enter(_args := {}) -> void:
	_col = vbox(2)
	_col.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	_col.offset_left = 96
	_col.offset_top = -230
	add_child(_col)
	_col.add_child(title("SOLO", 48))
	_col.add_child(text("Choisissez votre champ de bataille.", 18, UiStyle.DIM))
	_col.add_child(text("", 12))
	for id in Game.MENU_MAPS:
		var def := MapPreview.map_def(id)
		var b := button(def.display_name, _launch.bind(id), "Lancer une partie solo : %s." % def.display_name)
		b.focus_entered.connect(_show.bind(id))
		_col.add_child(b)
		buttons[id] = b
	_col.add_child(text("", 8))
	_col.add_child(button("RETOUR", back))

	var panel := MenuStyle.panel()
	panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	panel.offset_left = -690
	panel.offset_right = -70
	panel.offset_top = -270
	panel.offset_bottom = 250
	add_child(panel)
	var inner := vbox(8)
	panel.add_child(inner)
	_name = UiStyle.label("", 34, UiStyle.BONE, "impact")
	inner.add_child(_name)
	_preview = TextureRect.new()
	_preview.custom_minimum_size = Vector2(576, 300)
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	inner.add_child(_preview)
	_desc = text("", 18, UiStyle.BONE)
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.custom_minimum_size = Vector2(576, 0)
	inner.add_child(_desc)
	_zones = text("", 15, UiStyle.DIM)
	_zones.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_zones.custom_minimum_size = Vector2(576, 0)
	inner.add_child(_zones)
	var start: String = Settings.last_map if buttons.has(Settings.last_map) else Game.MENU_MAPS[0]
	_show(start)
	focus_later(buttons[start])


## Affiche le dossier de la carte `id`.
func _show(id: String) -> void:
	selected = id
	var def := MapPreview.map_def(id)
	_name.text = def.display_name
	_preview.texture = MapPreview.texture(id)
	_desc.text = def.description
	var names := []
	for z in def.zone_names:
		names.append(def.zone_names[z])
	_zones.text = "LIEUX : " + " · ".join(names)


func _launch(id: String) -> void:
	if _leaving:
		return
	_leaving = true
	for b in buttons.values():
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Settings.last_map = id
	Settings.save_settings()
	menu.launch(func(): Router.start_solo(id))


func back() -> void:
	if not _leaving:
		menu.go_back()
