extends TestCase
## Taille de l'interface de l'éditeur de cartes (EditorUi, Settings.editor_ui_scale) :
## polices, panneaux, marges et styles de l'éditeur suivent le facteur, en
## direct et sans échelle cumulée (retour exact à la valeur d'origine) ; les
## contrôles ajoutés ensuite sont mis à l'échelle ; le plan garde son zoom ;
## Ctrl + / Ctrl - / Ctrl 0 changent le même réglage.

const TMP := "res://tests/_out/test_map_editor_ui"
## Les raccourcis enregistrent le réglage : jamais dans le fichier du joueur.
const TMP_SETTINGS := "user://settings_unittest_ui.cfg"

var _scale0 := 0.8
var _path0 := ""


func before_each() -> void:
	_scale0 = Settings.editor_ui_scale
	_path0 = Settings.path
	Settings.path = TMP_SETTINGS
	Settings.editor_ui_scale = Settings.EDITOR_UI_SCALE_DEFAULT
	EditorMap.root_override = ProjectSettings.globalize_path(TMP + "/maps")


func after_each() -> void:
	Settings.editor_ui_scale = _scale0
	Settings.path = _path0
	if FileAccess.file_exists(TMP_SETTINGS):
		DirAccess.remove_absolute(TMP_SETTINGS)
	EditorMap.root_override = ""


func test_px_and_font_sizes() -> void:
	assert_eq(EditorUi.fs(14, 0.8), 11)
	assert_eq(EditorUi.fs(14, 1.5), 21)
	assert_eq(EditorUi.fs(8, 0.6), EditorUi.MIN_FONT, "jamais sous 6 px")
	assert_near(EditorUi.px(340.0, 0.8), 272.0)
	Settings.editor_ui_scale = 1.2
	assert_near(EditorUi.px(10.0), 12.0, 0.001, "facteur courant par défaut")


func test_scale_control_from_its_original_values() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	var l := UiStyle.label("x", 20)
	l.custom_minimum_size = Vector2(100, 30)
	box.add_child(l)
	var sb := StyleBoxFlat.new()
	sb.set_content_margin_all(10)
	sb.set_border_width_all(4)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", sb)
	box.add_child(p)
	var skip := Control.new()
	skip.custom_minimum_size = Vector2(50, 50)
	skip.set_meta(EditorUi.SKIP, true)
	box.add_child(skip)
	EditorUi.scale_tree(box, 1.5)
	assert_eq(l.custom_minimum_size, Vector2(150, 45))
	assert_eq(l.get_theme_font_size("font_size"), 30)
	assert_eq(box.get_theme_constant("separation"), 15)
	assert_near(sb.get_content_margin(SIDE_LEFT), 15.0)
	assert_eq(sb.get_border_width(SIDE_TOP), 6)
	assert_eq(skip.custom_minimum_size, Vector2(50, 50), "contrôle exclu (SKIP) inchangé")
	# Deuxième changement : depuis la valeur d'origine, pas depuis 150 %.
	EditorUi.scale_tree(box, 0.6)
	assert_eq(l.custom_minimum_size, Vector2(60, 18))
	assert_eq(l.get_theme_font_size("font_size"), 12)
	assert_eq(box.get_theme_constant("separation"), 6)
	EditorUi.scale_tree(box, 1.0)
	assert_eq(l.custom_minimum_size, Vector2(100, 30), "retour exact à 100 %")
	assert_eq(l.get_theme_font_size("font_size"), 20)
	assert_near(sb.get_content_margin(SIDE_LEFT), 10.0)
	# Valeur remise par le code après coup : nouvelle valeur d'origine.
	l.custom_minimum_size = Vector2(40, 0)
	EditorUi.scale_tree(box, 0.5)
	assert_eq(l.custom_minimum_size, Vector2(20, 0))
	box.free()


func test_editor_follows_the_setting_live() -> void:
	var ed: MapEditor = load(MapEditor.SCENE).instantiate()
	host.add_child(ed)
	await wait_frames(3)
	ed.new_map(true)
	ed.add_object({"contour": [[2, 2], [10, 2], [10, 8], [2, 8]]}, 0)
	await wait_frames(3)
	assert_near(ed.ui_scale, 0.8, 0.001, "80 % à l'ouverture")
	assert_eq(ed.theme.default_font_size, 11, "texte de 11 px à 80 %")
	var count_label: Label = ed.object_list._count_label
	assert_eq(count_label.get_theme_font_size("font_size"), EditorUi.fs(12, 0.8), "police propre d'un contrôle (liste des objets)")
	assert_near(ed.panels.custom_minimum_size.x, ed.side_width(MapEditor.PANEL_W))
	var slot0 := ed.hotbar_ui.slots[0]
	var slot_w := slot0.custom_minimum_size.x
	ed.canvas.zoom = 22.0
	var zoom := ed.canvas.zoom
	# 120 % : tout grandit, le plan garde son zoom.
	Settings.editor_ui_scale = 1.2
	await wait_frames(3)
	assert_near(ed.ui_scale, 1.2)
	assert_eq(ed.theme.default_font_size, EditorUi.fs(14, 1.2))
	assert_eq(count_label.get_theme_font_size("font_size"), EditorUi.fs(12, 1.2), "police du contrôle agrandie")
	assert_true(ed.panels.custom_minimum_size.x > EditorUi.px(MapEditor.PANEL_W, 0.8), "panneaux élargis (%d)" % ed.panels.custom_minimum_size.x)
	assert_true(ed.hotbar_ui.slots[0].custom_minimum_size.x >= slot_w, "cases de la barre rapide")
	assert_near(ed.canvas.zoom, zoom, 0.0001, "zoom du plan inchangé")
	assert_near(MapObjectList.row_h(), 31.0, 0.5, "lignes de la liste à 120 %")
	# Contrôles construits ensuite (propriétés refaites) : à l'échelle aussi.
	ed.select(String(ed.doc.pieces[0].id))
	await wait_frames(3)
	var titles := ed.panels._props.find_children("*", "Label", true, false).filter(
		func(x): return (x as Label).has_theme_font_size_override("font_size"))
	assert_true(not titles.is_empty(), "titres des propriétés")
	if not titles.is_empty():
		assert_eq((titles[0] as Label).get_theme_font_size("font_size"), EditorUi.fs(17, 1.2), "titre construit après le changement : 17 px à 120 %")
	# Ctrl - / Ctrl 0 : même réglage, enregistré.
	var e := InputEventKey.new()
	e.keycode = KEY_MINUS
	e.ctrl_pressed = true
	e.pressed = true
	ed._input(e)
	assert_near(Settings.editor_ui_scale, 1.15, 0.001, "Ctrl - : 115 %")
	e.keycode = KEY_0
	e.physical_keycode = KEY_0
	ed._input(e)
	assert_near(Settings.editor_ui_scale, 0.8, 0.001, "Ctrl 0 : défaut")
	await wait_frames(2)
	assert_eq(count_label.get_theme_font_size("font_size"), EditorUi.fs(12, 0.8), "retour à 80 % sans écart")
	assert_near(ed.canvas.zoom, zoom, 0.0001)
	ed.queue_free()
	await wait_frames(1)
