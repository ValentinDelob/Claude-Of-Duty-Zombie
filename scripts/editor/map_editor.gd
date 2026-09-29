class_name MapEditor
extends Control
## ÉDITEUR DE CARTES (docs/MAP_AUTHORING.md) : vue de dessus (MapCanvas),
## inventaire façon Minecraft (barre rapide de 9 cases + inventaire complet,
## MapHotbar / MapInventory), panneaux (MapPanels : propriétés, pièces, zones,
## étages, vérification), fichiers (dossier de cinq JSON, archive .zip),
## annuler / rétablir, sauvegarde automatique, bouton Tester (partie solo sur
## la carte éditée). Lançable depuis le menu principal ou directement :
##   godot --path . res://scenes/editor/map_editor.tscn

const SCENE := "res://scenes/editor/map_editor.tscn"
const AUTOSAVE_EVERY := 60.0
const RECENT_MAX := 8
const PANEL_W := 340.0
## Carte à rouvrir au retour d'une partie lancée par Tester.
static var reopen_dir := ""
static var reopen_example := false

var doc: EditorMap
## Dossier d'enregistrement ("" : jamais enregistrée).
var map_dir := ""
## Ouverte depuis un exemple livré (assets/maps/) : Enregistrer en fait une copie.
var example := false
var dirty := false
var undo_stack: Array = []
var redo_stack: Array = []
var floor_k := 0
var selected := ""
var clipboard: Dictionary = {}
var ghost_below := true
var hotbar: Array = MapCatalog.DEFAULT_HOTBAR.duplicate()
var hot_index := 0
## Éléments posés devenus invalides (dessinés en rouge) : id -> raison.
var invalid: Dictionary = {}
var validator: MapValidator
var validation_stale := true
var _raster: MapRaster
var _raster_dirty := true
var _autosave_t := 0.0
var _validate_t := -1.0

var canvas: MapCanvas
var panels: MapPanels
var hotbar_ui: MapHotbar
var inventory: MapInventory
var status: Label
var cursor_label: Label
var title_label: Label
var floor_label: Label
var check_button: Button
var file_menu: MenuButton
var edit_menu: MenuButton
var _recent_menu: PopupMenu
var _dialog: AcceptDialog
var _file_dialog: FileDialog
var _status_error := false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--check="):
			_cli_check(a.substr(8))
			return
	theme = make_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	if GameState.state != GameState.State.MAIN_MENU:
		GameState.reset_to_menu()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_ui()
	get_tree().root.close_requested.connect(_on_close_requested)
	doc = EditorMap.blank()
	_start.call_deferred()


## Vérification en ligne de commande (sans fenêtre), pour une carte écrite à
## la main ou par un outil :
##   godot --headless --path . res://scenes/editor/map_editor.tscn -- --check=<dossier ou archive .zip>
## Affiche le rapport du validateur ; code de sortie 0 si la carte est jouable.
func _cli_check(path: String) -> void:
	var p := path
	if not (p.is_absolute_path() or p.begins_with("res://") or p.begins_with("user://")):
		p = ProjectSettings.globalize_path("res://").path_join(p)
	var m: EditorMap = EditorMap.import_zip(p) if p.get_extension().to_lower() == "zip" else EditorMap.load_dir(p)
	for e in m.load_errors:
		print("[carte] ", Lang.t(e[0], e[1]))
	var v := MapRaster.build(m).v
	v.analyze()
	print(v.report_text())
	get_tree().quit(0 if v.ok() else 1)


func _start() -> void:
	if reopen_dir != "":
		var d := reopen_dir
		var ex := reopen_example
		reopen_dir = ""
		open_dir(d, ex)
		# Fin de la partie lancée par TESTER (« Partie terminée — ... »).
		if Router.pending_message != "":
			set_status(Router.pending_message)
			Router.pending_message = ""
		return
	var auto := _autosave_dir()
	if EditorMap.is_map_dir(auto):
		new_map(true)
		var meta = JSON.parse_string(FileAccess.get_file_as_string(auto.path_join("meta.json"))) if FileAccess.file_exists(auto.path_join("meta.json")) else {}
		var nm := String(meta.get("name", "")) if meta is Dictionary else ""
		var when := Time.get_datetime_string_from_unix_time(int(meta.get("time", 0)) if meta is Dictionary else 0, true)
		_confirm(Lang.t("Reprendre le travail non enregistré", "Resume unsaved work"),
			Lang.t("Une sauvegarde automatique de « %s » (%s) contient des modifications non enregistrées.\nLa reprendre ?", "An autosave of \"%s\" (%s) has unsaved changes.\nResume it?") % [nm, when],
			func(): _resume_autosave(), func(): _drop_autosave())
		return
	var recent := recent_maps()
	if not recent.is_empty() and EditorMap.is_map_dir(recent[0]):
		open_dir(recent[0])
	else:
		new_map(true)


func _process(delta: float) -> void:
	_autosave_t += delta
	if _autosave_t >= AUTOSAVE_EVERY:
		_autosave_t = 0.0
		autosave()
	if _validate_t > 0.0:
		_validate_t -= delta
		if _validate_t <= 0.0 and panels.is_check_tab():
			validate()


# ------------------------------------------------------------------ interface

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.08, 0.09)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)
	# Barre du haut.
	var top := PanelContainer.new()
	root.add_child(top)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	top.add_child(bar)
	file_menu = MenuButton.new()
	file_menu.text = Lang.t("Fichier", "File")
	file_menu.flat = false
	bar.add_child(file_menu)
	var fm := file_menu.get_popup()
	fm.add_item(Lang.t("Nouvelle carte", "New map") + "   Ctrl+N", 0)
	fm.add_item(Lang.t("Ouvrir…", "Open…") + "   Ctrl+O", 1)
	fm.add_item(Lang.t("Enregistrer", "Save") + "   Ctrl+S", 2)
	fm.add_item(Lang.t("Enregistrer sous…", "Save as…"), 3)
	fm.add_separator()
	fm.add_item(Lang.t("Exporter l'archive .zip…", "Export .zip archive…"), 4)
	fm.add_item(Lang.t("Importer une archive .zip…", "Import .zip archive…"), 5)
	fm.add_separator()
	_recent_menu = PopupMenu.new()
	_recent_menu.name = "Recent"
	fm.add_child(_recent_menu)
	fm.add_submenu_item(Lang.t("Cartes récentes", "Recent maps"), "Recent", 6)
	_recent_menu.index_pressed.connect(func(i): open_dir(recent_maps()[i]))
	fm.add_separator()
	fm.add_item(Lang.t("Retour au menu principal", "Back to main menu"), 7)
	fm.id_pressed.connect(_on_file_menu)
	fm.about_to_popup.connect(_fill_recent)
	edit_menu = MenuButton.new()
	edit_menu.text = Lang.t("Édition", "Edit")
	edit_menu.flat = false
	bar.add_child(edit_menu)
	var em := edit_menu.get_popup()
	em.add_item(Lang.t("Annuler", "Undo") + "   Ctrl+Z", 0)
	em.add_item(Lang.t("Rétablir", "Redo") + "   Ctrl+Y", 1)
	em.add_separator()
	em.add_item(Lang.t("Copier", "Copy") + "   Ctrl+C", 2)
	em.add_item(Lang.t("Coller", "Paste") + "   Ctrl+V", 3)
	em.add_item(Lang.t("Pivoter de 90°", "Rotate 90°") + "   R", 4)
	em.add_item(Lang.t("Supprimer", "Delete") + "   Suppr", 5)
	em.add_separator()
	em.add_item(Lang.t("Inventaire", "Inventory") + "   E / Tab", 6)
	em.add_item(Lang.t("Recadrer la vue", "Frame the view") + "   Origine", 7)
	em.id_pressed.connect(_on_edit_menu)
	bar.add_child(VSeparator.new())
	var prev := Button.new()
	prev.text = "◄"
	prev.tooltip_text = Lang.t("Étage du dessous (Page préc.)", "Floor below (Page Up)")
	prev.pressed.connect(func(): set_floor(floor_k - 1))
	bar.add_child(prev)
	floor_label = Label.new()
	floor_label.custom_minimum_size = Vector2(92, 0)
	floor_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bar.add_child(floor_label)
	var next := Button.new()
	next.text = "►"
	next.tooltip_text = Lang.t("Étage du dessus (Page suiv.)", "Floor above (Page Down)")
	next.pressed.connect(func(): set_floor(floor_k + 1))
	bar.add_child(next)
	bar.add_child(VSeparator.new())
	var test := Button.new()
	test.text = Lang.t("▶  TESTER", "▶  PLAY TEST")
	test.tooltip_text = Lang.t("Enregistre la carte et lance une partie solo dessus", "Saves the map and starts a solo game on it")
	test.add_theme_color_override("font_color", Color(0.5, 1.0, 0.55))
	test.pressed.connect(test_map)
	bar.add_child(test)
	check_button = Button.new()
	check_button.flat = true
	check_button.tooltip_text = Lang.t("Onglet Vérification", "Check tab")
	check_button.pressed.connect(func(): panels.show_tab("check"))
	bar.add_child(check_button)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(sp)
	title_label = Label.new()
	title_label.add_theme_color_override("font_color", UiStyle.BONE)
	bar.add_child(title_label)
	var help := Button.new()
	help.text = " ? "
	help.tooltip_text = Lang.t("Raccourcis", "Shortcuts")
	help.pressed.connect(_show_help)
	bar.add_child(help)
	# Vue + panneaux.
	var mid := HBoxContainer.new()
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 0)
	root.add_child(mid)
	canvas = MapCanvas.new()
	canvas.ed = self
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_child(canvas)
	panels = MapPanels.new()
	panels.ed = self
	panels.custom_minimum_size = Vector2(PANEL_W, 0)
	mid.add_child(panels)
	# Barre d'état.
	var sb := PanelContainer.new()
	root.add_child(sb)
	var sbh := HBoxContainer.new()
	sb.add_child(sbh)
	status = Label.new()
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.clip_text = true
	sbh.add_child(status)
	cursor_label = Label.new()
	cursor_label.add_theme_color_override("font_color", UiStyle.DIM)
	sbh.add_child(cursor_label)
	# Barre rapide (au bas de la vue) et inventaire.
	hotbar_ui = MapHotbar.new()
	hotbar_ui.ed = self
	canvas.add_child(hotbar_ui)
	inventory = MapInventory.new()
	inventory.ed = self
	inventory.visible = false
	canvas.add_child(inventory)
	_dialog = AcceptDialog.new()
	add_child(_dialog)


func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = UiStyle.font("body")
	t.default_font_size = 14
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.13, 0.135, 0.145)
	panel.set_content_margin_all(6)
	panel.border_color = Color(0.22, 0.22, 0.24)
	panel.set_border_width_all(1)
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)
	var popup := panel.duplicate()
	popup.bg_color = Color(0.1, 0.1, 0.11)
	t.set_stylebox("panel", "PopupMenu", popup)
	t.set_stylebox("panel", "PopupPanel", popup)
	t.set_stylebox("panel", "AcceptDialog", popup)
	t.set_stylebox("panel", "ConfirmationDialog", popup)
	for kind in ["Button", "MenuButton", "OptionButton", "CheckBox"]:
		var n := StyleBoxFlat.new()
		n.bg_color = Color(0.2, 0.2, 0.22) if kind != "CheckBox" else Color(0, 0, 0, 0)
		n.set_corner_radius_all(3)
		n.set_content_margin_all(5)
		n.content_margin_left = 9
		n.content_margin_right = 9
		var h := n.duplicate()
		h.bg_color = Color(0.3, 0.26, 0.2)
		var p := n.duplicate()
		p.bg_color = Color(0.45, 0.14, 0.1)
		var d := n.duplicate()
		d.bg_color = Color(0.15, 0.15, 0.16)
		t.set_stylebox("normal", kind, n)
		t.set_stylebox("hover", kind, h)
		t.set_stylebox("pressed", kind, p)
		t.set_stylebox("disabled", kind, d)
		t.set_stylebox("focus", kind, StyleBoxEmpty.new())
		t.set_color("font_color", kind, Color(0.88, 0.86, 0.8))
		t.set_color("font_hover_color", kind, Color(1, 0.95, 0.85))
	var le := StyleBoxFlat.new()
	le.bg_color = Color(0.07, 0.07, 0.08)
	le.set_content_margin_all(5)
	le.border_color = Color(0.3, 0.3, 0.33)
	le.set_border_width_all(1)
	t.set_stylebox("normal", "LineEdit", le)
	var lef := le.duplicate()
	lef.border_color = Color(0.85, 0.6, 0.25)
	t.set_stylebox("focus", "LineEdit", lef)
	t.set_stylebox("panel", "ItemList", le)
	t.set_stylebox("focus", "ItemList", StyleBoxEmpty.new())
	t.set_color("font_color", "Label", Color(0.86, 0.84, 0.78))
	t.set_color("font_color", "ItemList", Color(0.86, 0.84, 0.78))
	var tab := StyleBoxFlat.new()
	tab.bg_color = Color(0.16, 0.16, 0.17)
	tab.set_content_margin_all(6)
	var tabs := tab.duplicate()
	tabs.bg_color = Color(0.3, 0.12, 0.08)
	t.set_stylebox("tab_unselected", "TabContainer", tab)
	t.set_stylebox("tab_hovered", "TabContainer", tab)
	t.set_stylebox("tab_selected", "TabContainer", tabs)
	t.set_stylebox("panel", "TabContainer", panel)
	t.set_font_size("font_size", "TabContainer", 13)
	return t


func set_status(text: String, error := false) -> void:
	status.text = text
	_status_error = error
	status.add_theme_color_override("font_color", Color(1, 0.55, 0.45) if error else Color(0.8, 0.8, 0.75))


func show_cursor(m: Vector2) -> void:
	var fr := not Lang.is_en()
	cursor_label.text = "x %s m · y %s m · %s %d" % [MapRules._m(snappedf(m.x, 0.5), fr), MapRules._m(snappedf(m.y, 0.5), fr), Lang.t("étage", "floor"), floor_k]


func _update_title() -> void:
	var where := Lang.t("exemple (copie à l'enregistrement)", "example (copied when saved)") if example else (map_dir if map_dir != "" else Lang.t("non enregistrée", "not saved"))
	title_label.text = "%s%s  —  %s" % [doc.display_name(), " *" if dirty else "", where]
	floor_label.text = Lang.t("Étage %d / %d", "Floor %d / %d") % [floor_k, doc.floor_count() - 1]
	if validation_stale or validator == null:
		check_button.text = Lang.t("Vérification : à faire", "Check: pending")
		check_button.add_theme_color_override("font_color", UiStyle.DIM)
	else:
		var ne := validator.errors().size()
		var nw := validator.warnings().size()
		check_button.text = (Lang.t("✔ jouable (%d avert.)", "✔ playable (%d warn.)") % nw) if ne == 0 else (Lang.t("✖ %d erreur(s)", "✖ %d error(s)") % ne)
		check_button.add_theme_color_override("font_color", Color(0.5, 1.0, 0.55) if ne == 0 else Color(1, 0.4, 0.35))


func _show_help() -> void:
	_info(Lang.t("Raccourcis", "Shortcuts"), Lang.t(
		"Clic gauche : poser / choisir · clic droit : annuler\nGlisser : pièces, murs, piliers, escaliers, pièges\nMaj : aimantation à 0,5 m (sinon 1 m)\nCtrl + molette : zoom · clic milieu ou Espace + glisser : déplacer la vue\nMolette ou 1 à 9 : case de la barre rapide · E ou Tab : inventaire\nR : pivoter · Suppr : supprimer · Ctrl+C / Ctrl+V : copier / coller\nCtrl+Z / Ctrl+Y : annuler / rétablir · Ctrl+S : enregistrer\nPage préc. / suiv. : étage · Origine : recadrer · Entrée : fermer un polygone",
		"Left click: place / pick · right click: cancel\nDrag: rooms, walls, pillars, stairs, traps\nShift: snap to 0.5 m (otherwise 1 m)\nCtrl + wheel: zoom · middle click or Space + drag: pan\nWheel or 1 to 9: hotbar slot · E or Tab: inventory\nR: rotate · Del: delete · Ctrl+C / Ctrl+V: copy / paste\nCtrl+Z / Ctrl+Y: undo / redo · Ctrl+S: save\nPage Up / Down: floor · Home: frame · Enter: close a polygon"))


func _info(title_text: String, text: String) -> void:
	_dialog.title = title_text
	_dialog.dialog_text = text
	_dialog.popup_centered()


func _confirm(title_text: String, text: String, on_ok: Callable, on_cancel := Callable()) -> ConfirmationDialog:
	var d := ConfirmationDialog.new()
	d.title = title_text
	d.dialog_text = text
	d.ok_button_text = Lang.t("Oui", "Yes")
	d.cancel_button_text = Lang.t("Non", "No")
	add_child(d)
	d.confirmed.connect(func():
		d.queue_free()
		on_ok.call())
	d.canceled.connect(func():
		d.queue_free()
		if on_cancel.is_valid():
			on_cancel.call())
	d.popup_centered()
	return d


# ------------------------------------------------------------------ clavier

func _typing() -> bool:
	var f := get_viewport().gui_get_focus_owner()
	return f is LineEdit or f is TextEdit


func _input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var k := event as InputEventKey
	if k.keycode == KEY_SPACE and not _typing():
		canvas.set_space(k.pressed)
		get_viewport().set_input_as_handled()
		return
	if not k.pressed:
		return
	if k.echo and not (k.keycode in [KEY_Z, KEY_Y]):
		return
	if k.ctrl_pressed:
		match k.keycode:
			KEY_S:
				save()
			KEY_Z:
				if k.shift_pressed:
					redo()
				else:
					undo()
			KEY_Y:
				redo()
			KEY_N:
				new_map()
			KEY_O:
				open_dialog()
			KEY_C:
				if _typing():
					return
				copy_selected()
			KEY_V:
				if _typing():
					return
				paste()
			_:
				return
		get_viewport().set_input_as_handled()
		return
	if _typing():
		if k.keycode == KEY_ESCAPE:
			get_viewport().gui_release_focus()
			get_viewport().set_input_as_handled()
		return
	var handled := true
	var pk := k.physical_keycode
	if pk >= KEY_1 and pk <= KEY_9:
		select_slot(pk - KEY_1)
	elif k.keycode >= KEY_KP_1 and k.keycode <= KEY_KP_9:
		select_slot(k.keycode - KEY_KP_1)
	else:
		match k.keycode:
			KEY_E, KEY_TAB:
				toggle_inventory()
			KEY_ESCAPE:
				if inventory.visible:
					toggle_inventory()
				elif not canvas.drag.is_empty() or not canvas.poly_pts.is_empty():
					canvas.cancel()
				else:
					select("")
			KEY_R:
				rotate_selected()
			KEY_DELETE:
				if selected != "":
					delete_element(selected)
			KEY_BACKSPACE:
				if not canvas.poly_pts.is_empty():
					canvas.undo_point()
				elif selected != "":
					delete_element(selected)
			KEY_ENTER, KEY_KP_ENTER:
				canvas.finish_polygon()
			KEY_PAGEUP:
				set_floor(floor_k - 1)
			KEY_PAGEDOWN:
				set_floor(floor_k + 1)
			KEY_HOME:
				canvas.frame_all()
			KEY_EQUAL, KEY_KP_ADD, KEY_PLUS:
				canvas.zoom_by(1.25)
			KEY_MINUS, KEY_KP_SUBTRACT:
				canvas.zoom_by(0.8)
			_:
				handled = false
	if handled:
		get_viewport().set_input_as_handled()


# ------------------------------------------------------------------ barre rapide

func current_item() -> Dictionary:
	var id := String(hotbar[hot_index]) if hot_index < hotbar.size() else ""
	var it := MapCatalog.item(id)
	return it if not it.is_empty() else MapCatalog.item("select")


func tool() -> String:
	return String(current_item().get("tool", "select"))


func select_slot(i: int) -> void:
	hot_index = clampi(i, 0, 8)
	canvas.cancel()
	canvas.preview = {}
	canvas.refusal = ""
	var it := current_item()
	set_status("%s — %s" % [MapCatalog.name_of(it), Lang.t(String(it.get("hint_fr", "")), String(it.get("hint_en", "")))])
	hotbar_ui.queue_redraw_slots()
	canvas.queue_redraw()


func cycle_hotbar(d: int) -> void:
	select_slot(posmod(hot_index + d, 9))


func set_hotbar(i: int, item_id: String) -> void:
	if i < 0 or i >= 9:
		return
	while hotbar.size() < 9:
		hotbar.append("")
	hotbar[i] = item_id
	select_slot(i)


func toggle_inventory() -> void:
	inventory.visible = not inventory.visible
	if inventory.visible:
		inventory.open()
	canvas.cancel()


# ------------------------------------------------------------------ carte

func raster() -> MapRaster:
	if _raster_dirty or _raster == null:
		_raster = MapRaster.build(doc)
		_raster_dirty = false
	return _raster


func zone_color(zid: String) -> Color:
	var i := 0
	for z in doc.zones:
		if String(z.id) == zid:
			break
		i += 1
	var c := Color.from_hsv(fmod(0.08 + i * 0.137, 1.0), 0.5, 0.75)
	if zid == doc.depart:
		c = Color(0.95, 0.85, 0.45)
	return Color(c, 0.3)


## Annuler : pile de copies complètes de la carte (illimitée).
func push_undo() -> void:
	push_undo_snapshot(doc.snapshot())


func push_undo_snapshot(s: Dictionary) -> void:
	undo_stack.append(s)
	redo_stack.clear()


## Après une modification : grille, vérification, dessin, panneaux.
func changed(rebuild_panels := true) -> void:
	dirty = true
	_raster_dirty = true
	validation_stale = true
	_validate_t = 1.0
	if doc.find(selected).is_empty():
		selected = ""
	_update_invalid()
	canvas.queue_redraw()
	if rebuild_panels:
		panels.refresh()
	_update_title()


## Modification en direct (glissement) : dessin seulement.
func moved_live() -> void:
	dirty = true
	_raster_dirty = true
	validation_stale = true
	canvas.queue_redraw()


func _update_invalid() -> void:
	invalid.clear()
	for list in [doc.pieces, doc.ouvertures, doc.objets]:
		for e in list:
			var r := MapRules.check_existing(doc, e)
			if not r.ok:
				invalid[String(e.id)] = MapRules.why(r)


func undo() -> void:
	if undo_stack.is_empty():
		set_status(Lang.t("Rien à annuler", "Nothing to undo"))
		return
	canvas.cancel()
	redo_stack.append(doc.snapshot())
	doc.restore(undo_stack.pop_back())
	floor_k = mini(floor_k, doc.floor_count() - 1)
	changed()
	set_status(Lang.t("Annulé (%d étape(s) restante(s))", "Undone (%d step(s) left)") % undo_stack.size())


func redo() -> void:
	if redo_stack.is_empty():
		set_status(Lang.t("Rien à rétablir", "Nothing to redo"))
		return
	canvas.cancel()
	undo_stack.append(doc.snapshot())
	doc.restore(redo_stack.pop_back())
	floor_k = mini(floor_k, doc.floor_count() - 1)
	changed()
	set_status(Lang.t("Rétabli", "Redone"))


func select(eid: String) -> void:
	selected = eid
	var e := doc.find(eid)
	if not e.is_empty() and e.has("etage") and int(e.etage) != floor_k:
		floor_k = int(e.etage)
		_raster_dirty = true
		_update_title()
	if invalid.has(eid):
		set_status(invalid[eid], true)
	panels.refresh()
	canvas.queue_redraw()


## Centre la vue sur un élément et le choisit.
func focus_element(eid: String) -> void:
	select(eid)
	var e := doc.find(eid)
	if e.is_empty():
		return
	var r := MapGeom.bbox(doc.room_poly(e)) if e.has("contour") else MapRules.footprint_rect(e)
	if String(e.get("type", "")) in MapRules.ouvertures_types():
		r = Rect2(MapGeom.v2(e.position), Vector2.ZERO)
	canvas.center_on(r.get_center())


func default_door_price() -> int:
	var n := doc.ouvertures.filter(func(o): return String(o.type) in ["porte", "debris"]).size()
	return MapCatalog.DOOR_PRICES[mini(n, MapCatalog.DOOR_PRICES.size() - 1)]


## Ajoute un élément posé par un outil (pièce, ouverture, objet) à l'étage `k`.
func add_object(o: Dictionary, k: int) -> Dictionary:
	push_undo()
	var e := o.duplicate(true)
	e["etage"] = k
	if e.has("contour"):
		e["id"] = doc.new_id("p")
		var n := doc.pieces.size() + 1
		var named := e.has("nom")
		if not named:
			e["nom"] = Lang.t("Pièce %d", "Room %d") % n
		# Par défaut, une zone par pièce (même nom, en français et en anglais).
		if doc.zone(String(e.get("zone", ""))).is_empty():
			var z := doc.add_zone(String(e.nom) if named else "Pièce %d" % n, String(e.nom) if named else "Room %d" % n)
			e["zone"] = String(z.id)
		doc.pieces.append(e)
	elif String(e.get("type", "")) in MapRules.ouvertures_types():
		e["id"] = doc.new_id("o")
		if String(e.type) in ["porte", "debris"] and not e.has("prix"):
			e["prix"] = default_door_price()
		if String(e.type) == "fenetre":
			e.erase("largeur")
		doc.ouvertures.append(e)
	else:
		var prefix: String = {"atout": "a", "arme": "w", "boite": "b", "depart": "s", "escalier": "e", "pilier": "x", "mur": "m", "piege": "t", "levier": "l"}.get(String(e.get("type", "")), "x")
		e["id"] = doc.new_id(prefix)
		# Un seul départ de la boîte.
		if String(e.type) == "boite" and e.get("depart", false):
			for q in doc.objets:
				if String(q.get("type", "")) == "boite":
					q["depart"] = false
		doc.objets.append(e)
	selected = String(e.id)
	canvas.refusal = ""
	changed()
	set_status(Lang.t("%s posé", "%s placed") % _label(e))
	return e


func _label(e: Dictionary) -> String:
	if e.has("contour"):
		return Lang.t("Pièce « %s »", "Room \"%s\"") % e.get("nom", "")
	return MapCatalog.name_of(MapCatalog.item_for(e))


## Éléments rattachés à une pièce (qui bougent et pivotent avec elle).
func attached_to(e: Dictionary) -> Array:
	var out := []
	if not e.has("contour"):
		return out
	var poly := doc.room_poly(e)
	var k := int(e.get("etage", 0))
	for o in doc.objects_on(k):
		var c := MapRules.footprint_rect(o).get_center()
		if String(o.type) == "mur":
			c = (MapGeom.v2(o.a) + MapGeom.v2(o.b)) * 0.5
		if MapGeom.contains(poly, c):
			out.append(String(o.id))
	for o in doc.openings_on(k):
		if MapGeom.on_boundary(poly, MapGeom.v2(o.position), 0.01):
			out.append(String(o.id))
	return out


## Élément sous le point `m` de l'étage courant (ouvertures et objets avant les pièces).
func element_at(m: Vector2) -> Dictionary:
	for o in doc.openings_on(floor_k):
		if MapRules.hit(doc, o, m):
			return o
	var objs := doc.objects_on(floor_k)
	objs.sort_custom(func(a, b): return MapRules.footprint_rect(a).get_area() < MapRules.footprint_rect(b).get_area())
	for o in objs:
		if MapRules.hit(doc, o, m):
			return o
	for p in doc.rooms_on(floor_k):
		if MapRules.hit(doc, p, m):
			return p
	return {}


func delete_element(eid: String) -> void:
	var e := doc.find(eid)
	if e.is_empty():
		return
	push_undo()
	var n := 1
	for a in attached_to(e):
		doc.remove(a)
		n += 1
	doc.remove(eid)
	doc.tidy_zones()
	if selected == eid:
		selected = ""
	changed()
	set_status(Lang.t("%s supprimé", "%s deleted") % _label(e) + (Lang.t(" (avec %d élément(s) de la pièce)", " (with %d element(s) of the room)") % (n - 1) if n > 1 else ""))


## Remplace un élément par sa nouvelle version (même identifiant).
func _replace(e: Dictionary) -> void:
	var list := doc.list_of(String(e.id))
	for i in list.size():
		if String(list[i].id) == String(e.id):
			list[i] = e
			return


static func _shift(o: Dictionary, delta: Vector2) -> Dictionary:
	var e := o.duplicate(true)
	if e.has("contour"):
		var pts := []
		for p in e.contour:
			pts.append(MapGeom.arr(MapGeom.v2(p) + delta))
		e.contour = pts
	for key in ["position", "a", "b"]:
		if e.has(key):
			e[key] = MapGeom.arr(MapGeom.v2(e[key]) + delta)
	if e.has("rect"):
		var r := MapGeom.rect_of(e.rect)
		r.position += delta
		e.rect = MapGeom.rect_arr(r)
	return e


## Déplacement pendant un glissement : essaie `orig` décalé de `delta`
## (depuis la carte `snap0`), l'applique s'il est valide.
func try_move(orig: Dictionary, attached: Array, delta: Vector2, snap0: Dictionary) -> Dictionary:
	var k := int(orig.get("etage", 0))
	var cand := _shift(orig, delta)
	var t := String(orig.get("type", ""))
	var res := {"ok": true}
	if orig.has("contour"):
		res = MapRules.check_room(doc, k, doc.room_poly(cand), String(orig.id))
	elif t in MapRules.ouvertures_types():
		res = MapRules.place_opening(doc, k, t, MapGeom.v2(cand.position), MapRules.opening_width(orig), String(orig.id))
		if res.ok:
			cand.position = res.position
	else:
		match MapCatalog.tool_of(orig):
			"wall_item":
				res = MapRules.place_wall_item(doc, k, orig, MapRules.footprint_rect(cand).get_center(), String(orig.id))
				if res.ok:
					cand.position = res.position
					cand.mur = res.mur
			"floor_item":
				res = MapRules.place_floor_item(doc, k, orig, MapGeom.v2(cand.position), String(orig.id))
				if res.ok:
					cand.position = res.position
			"rect":
				res = MapRules.check_rect(doc, k, t, MapGeom.rect_of(cand.rect), String(orig.id))
			"wall":
				res = MapRules.check_wall(MapGeom.v2(cand.a), MapGeom.v2(cand.b))
	if not res.ok:
		return res
	doc.restore(snap0)
	_replace(cand)
	for aid in attached:
		var a := doc.find(aid)
		if not a.is_empty():
			_replace(_shift(a, delta))
	moved_live()
	return res


## Poignée `h` de l'élément `orig` amenée au point `p`.
func try_handle(orig: Dictionary, h: int, p: Vector2, snap0: Dictionary) -> Dictionary:
	var k := int(orig.get("etage", 0))
	var cand := orig.duplicate(true)
	var res := {"ok": true}
	if orig.has("contour"):
		var poly := doc.room_poly(orig)
		var np := PackedVector2Array()
		if MapGeom.is_axis_rect(poly):
			var r := MapGeom.bbox(poly)
			var x0 := r.position.x
			var y0 := r.position.y
			var x1 := r.end.x
			var y1 := r.end.y
			# Coins 0-3 (haut-gauche, haut-droit, bas-droit, bas-gauche), milieux 4-7 (haut, droite, bas, gauche).
			if h in [0, 3, 7]:
				x0 = p.x
			if h in [1, 2, 5]:
				x1 = p.x
			if h in [0, 1, 4]:
				y0 = p.y
			if h in [2, 3, 6]:
				y1 = p.y
			np = MapGeom.rect_poly(Rect2(Vector2(x0, y0), Vector2.ZERO).expand(Vector2(x1, y1)))
		else:
			np = poly.duplicate()
			np[h] = p
		cand.contour = MapGeom.poly_arr(np)
		res = MapRules.check_room(doc, k, np, String(orig.id))
	elif orig.has("rect"):
		var r := MapGeom.rect_of(orig.rect)
		var corners := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
		var opp: Vector2 = corners[(h + 2) % 4]
		var nr := Rect2(opp, Vector2.ZERO).expand(p)
		cand.rect = MapGeom.rect_arr(nr)
		res = MapRules.check_rect(doc, k, String(orig.type), nr, String(orig.id))
	elif String(orig.get("type", "")) == "mur":
		cand["a" if h == 0 else "b"] = MapGeom.arr(p)
		res = MapRules.check_wall(MapGeom.v2(cand.a), MapGeom.v2(cand.b))
	if not res.ok:
		return res
	doc.restore(snap0)
	_replace(cand)
	moved_live()
	return res


static func _rot(o: Dictionary, c: Vector2) -> Dictionary:
	var e := o.duplicate(true)
	if e.has("contour"):
		var pts := []
		for p in e.contour:
			pts.append(MapGeom.arr(MapGeom.rot90(MapGeom.v2(p), c)))
		e.contour = pts
	for key in ["position", "a", "b"]:
		if e.has(key):
			e[key] = MapGeom.arr(MapGeom.rot90(MapGeom.v2(e[key]), c))
	if e.has("rect"):
		var r := MapGeom.rect_of(e.rect)
		e.rect = MapGeom.rect_arr(Rect2(MapGeom.rot90(r.position, c), Vector2.ZERO).expand(MapGeom.rot90(r.end, c)))
	for key in ["mur", "monte"]:
		if e.has(key):
			e[key] = MapGeom.dir_rot(String(e[key]))
	return e


## Pivote de 90° l'élément choisi (une pièce pivote avec son contenu).
func rotate_selected() -> void:
	var e := doc.find(selected)
	if e.is_empty():
		set_status(Lang.t("Choisissez d'abord un élément (outil Sélection)", "Pick an element first (Select tool)"))
		return
	var t := String(e.get("type", ""))
	if not (e.has("contour") or e.has("rect") or t == "mur"):
		set_status(Lang.t("Cet élément suit son mur : déplacez-le plutôt", "This element follows its wall: move it instead"))
		return
	var before := doc.snapshot()
	var c := Vector2.ZERO
	if e.has("contour"):
		c = MapGeom.bbox(doc.room_poly(e)).get_center()
	elif e.has("rect"):
		c = MapGeom.rect_of(e.rect).get_center()
	else:
		c = (MapGeom.v2(e.a) + MapGeom.v2(e.b)) * 0.5
	c = Vector2(snappedf(c.x, 0.5), snappedf(c.y, 0.5))
	var attached := attached_to(e)
	_replace(_rot(e, c))
	for aid in attached:
		_replace(_rot(doc.find(aid), c))
	var ne := doc.find(selected)
	var res := MapRules.check_existing(doc, ne)
	if not res.ok:
		doc.restore(before)
		canvas.show_refusal(res)
		return
	push_undo_snapshot(before)
	changed()
	set_status(Lang.t("Pivoté de 90°", "Rotated 90°"))


func copy_selected() -> void:
	var e := doc.find(selected)
	if e.is_empty():
		return
	clipboard = e.duplicate(true)
	set_status(Lang.t("Copié : %s (Ctrl+V pour coller sous le curseur)", "Copied: %s (Ctrl+V to paste under the cursor)") % _label(e))


func paste() -> void:
	if clipboard.is_empty():
		set_status(Lang.t("Rien à coller", "Nothing to paste"))
		return
	var e := clipboard.duplicate(true)
	var c := MapRules.footprint_rect(e).get_center()
	if e.has("contour"):
		c = MapGeom.bbox(MapGeom.poly(e.contour)).get_center()
	elif e.has("position"):
		c = MapGeom.v2(e.position)
	var target := canvas.snap(canvas.mouse_m)
	var delta := target - Vector2(snappedf(c.x, 0.5), snappedf(c.y, 0.5))
	e = _shift(e, delta)
	e.erase("id")
	e["etage"] = floor_k
	var t := String(e.get("type", ""))
	var res := {"ok": true}
	if e.has("contour"):
		e.erase("zone")
		res = MapRules.check_room(doc, floor_k, MapGeom.poly(e.contour))
	elif t in MapRules.ouvertures_types():
		res = MapRules.place_opening(doc, floor_k, t, MapGeom.v2(e.position), MapRules.opening_width(e))
		if res.ok:
			e.position = res.position
	else:
		match MapCatalog.tool_of(e):
			"wall_item":
				res = MapRules.place_wall_item(doc, floor_k, e, target)
				if res.ok:
					e.position = res.position
					e.mur = res.mur
			"floor_item":
				res = MapRules.place_floor_item(doc, floor_k, e, target)
				if res.ok:
					e.position = res.position
			"rect":
				res = MapRules.check_rect(doc, floor_k, t, MapGeom.rect_of(e.rect))
	if not res.ok:
		canvas.show_refusal(res)
		return
	if e.has("contour"):
		e.erase("nom")
	add_object(e, floor_k)


# ------------------------------------------------------------------ zones et étages

func set_room_zone(room_id: String, zid: String) -> void:
	var r := doc.find(room_id)
	if r.is_empty():
		return
	push_undo()
	if zid == "":
		var z := doc.add_zone(String(r.get("nom", "")), String(r.get("nom", "")))
		zid = String(z.id)
	r["zone"] = zid
	doc.tidy_zones()
	changed()


func merge_zones(src: String, dst: String) -> void:
	if src == dst or doc.zone(src).is_empty() or doc.zone(dst).is_empty():
		return
	push_undo()
	for p in doc.rooms_of_zone(src):
		p["zone"] = dst
	if doc.depart == src:
		doc.depart = dst
	doc.tidy_zones()
	changed()
	set_status(Lang.t("Zones fusionnées : « %s »", "Zones merged: \"%s\"") % doc.zone_name(dst))


## Une zone par pièce (la première pièce garde la zone).
func split_zone(zid: String) -> void:
	var rooms := doc.rooms_of_zone(zid)
	if rooms.size() < 2:
		set_status(Lang.t("Cette zone n'a qu'une pièce", "This zone has a single room"))
		return
	push_undo()
	for i in range(1, rooms.size()):
		var z := doc.add_zone(String(rooms[i].get("nom", "")), String(rooms[i].get("nom", "")))
		rooms[i]["zone"] = String(z.id)
	changed()
	set_status(Lang.t("Zone séparée : une zone par pièce", "Zone split: one zone per room"))


func set_start_zone(zid: String) -> void:
	if doc.zone(zid).is_empty():
		return
	push_undo()
	doc.depart = zid
	changed()


func set_floor(k: int) -> void:
	var nk := clampi(k, 0, doc.floor_count() - 1)
	if nk == floor_k:
		return
	floor_k = nk
	canvas.cancel()
	selected = ""
	_raster_dirty = true
	panels.refresh()
	_update_title()
	canvas.queue_redraw()


func add_floor() -> void:
	push_undo()
	var f: Array = doc.carte.etages
	var top := doc.floor_count() - 1
	f.append({"sol": snappedf(doc.floor_sol(top) + EditorMap.FLOOR_STEP, 0.1), "hauteur": EditorMap.DEFAULT_CEILING})
	changed()
	set_floor(doc.floor_count() - 1)


func remove_top_floor() -> void:
	var top := doc.floor_count() - 1
	if top == 0:
		return
	var used := doc.rooms_on(top).size() + doc.objects_on(top).size() + doc.openings_on(top).size()
	if used > 0:
		set_status(Lang.t("L'étage %d n'est pas vide (%d élément(s))", "Floor %d is not empty (%d element(s))") % [top, used], true)
		return
	push_undo()
	(doc.carte.etages as Array).remove_at(top)
	floor_k = mini(floor_k, doc.floor_count() - 1)
	changed()


# ------------------------------------------------------------------ vérification

func validate() -> MapValidator:
	_validate_t = -1.0
	validator = MapRaster.build(doc).v
	validator.analyze()
	validation_stale = false
	panels.show_validation()
	_update_title()
	return validator


## Clic sur un problème : étage, vue centrée, cases en évidence.
func focus_problem(m: Dictionary) -> void:
	var cells: Array = m.get("cells", [])
	if cells.is_empty():
		return
	var k := int(m.get("floor", -1))
	if k >= 0:
		set_floor(k)
	canvas.highlight = cells
	canvas.highlight_floor = floor_k
	var c := Vector2.ZERO
	for cc in cells:
		c += MapGeom.cell_center(cc)
	canvas.center_on(c / cells.size())


# ------------------------------------------------------------------ fichiers

func _reset(d: EditorMap) -> void:
	doc = d
	undo_stack.clear()
	redo_stack.clear()
	selected = ""
	floor_k = 0
	validator = null
	canvas.cancel()
	canvas.highlight = []
	_raster_dirty = true
	validation_stale = true
	dirty = false
	_update_invalid()
	panels.refresh()
	_update_title()
	canvas.frame_all.call_deferred()


func new_map(force := false) -> void:
	if dirty and not force:
		_confirm(Lang.t("Nouvelle carte", "New map"), Lang.t("Les modifications non enregistrées seront perdues. Continuer ?", "Unsaved changes will be lost. Continue?"), func(): new_map(true))
		return
	map_dir = ""
	example = false
	_reset(EditorMap.blank("nouvelle_carte", Lang.t("NOUVELLE CARTE", "NEW MAP"), Lang.t("NOUVELLE CARTE", "NEW MAP")))
	set_status(Lang.t("Nouvelle carte : prenez « Pièce rectangle » (touche 2) et glissez dans la grille", "New map: take \"Rectangle room\" (key 2) and drag in the grid"))


func open_dir(dir: String, is_example := false) -> void:
	var d := EditorMap.load_dir(dir)
	if not d.load_errors.is_empty():
		_info(Lang.t("Ouverture", "Open"), "\n".join(d.load_errors.map(func(e): return Lang.t(e[0], e[1]))))
	map_dir = "" if is_example else dir
	example = is_example
	_reset(d)
	if not is_example:
		_add_recent(dir)
	set_status(Lang.t("Carte « %s » ouverte", "Map \"%s\" opened") % doc.display_name())


func open_example(ex_id: String) -> void:
	open_dir(EditorMap.EXAMPLES[ex_id], true)


## Enregistre (dans son dossier, sinon dans user://maps/<id>/).
func save() -> bool:
	if map_dir == "" or example:
		var mid := doc.id()
		if example or mid == "nouvelle_carte" or mid == "":
			mid = EditorMap.slug(String(doc.carte.get("nom", {}).get("fr", mid)))
		return save_as(_free_id(mid) if map_dir == "" else mid)
	var err := doc.save_dir(map_dir)
	if err != OK:
		set_status(Lang.t("Échec de l'enregistrement (%s)", "Save failed (%s)") % error_string(err), true)
		return false
	dirty = false
	_drop_autosave()
	_add_recent(map_dir)
	_update_title()
	set_status(Lang.t("Enregistrée dans %s", "Saved to %s") % map_dir)
	return true


func _free_id(base: String) -> String:
	var id := base
	var n := 2
	while EditorMap.is_map_dir(EditorMap.map_dir(id)):
		id = "%s_%d" % [base, n]
		n += 1
	return id


func save_as(map_id: String) -> bool:
	var mid := EditorMap.slug(map_id)
	doc.carte["id"] = mid
	map_dir = EditorMap.map_dir(mid)
	example = false
	return save()


func save_as_dialog() -> void:
	var d := ConfirmationDialog.new()
	d.title = Lang.t("Enregistrer sous", "Save as")
	var box := VBoxContainer.new()
	d.add_child(box)
	var l := Label.new()
	l.text = Lang.t("Nom du dossier (dans %s) :", "Folder name (in %s):") % EditorMap.maps_root()
	box.add_child(l)
	var e := LineEdit.new()
	e.text = doc.id()
	e.custom_minimum_size = Vector2(360, 0)
	box.add_child(e)
	d.ok_button_text = Lang.t("Enregistrer", "Save")
	d.cancel_button_text = Lang.t("Annuler", "Cancel")
	add_child(d)
	d.confirmed.connect(func():
		save_as(e.text)
		d.queue_free())
	d.canceled.connect(d.queue_free)
	d.popup_centered()
	e.grab_focus.call_deferred()


func open_dialog() -> void:
	var d := ConfirmationDialog.new()
	d.title = Lang.t("Ouvrir une carte", "Open a map")
	var box := VBoxContainer.new()
	d.add_child(box)
	var list := ItemList.new()
	list.custom_minimum_size = Vector2(460, 300)
	box.add_child(list)
	var entries := []
	for ex in EditorMap.EXAMPLES:
		entries.append([EditorMap.EXAMPLES[ex], true])
		list.add_item(Lang.t("Exemple : %s", "Example: %s") % ex.to_upper())
	for m in EditorMap.list_maps():
		entries.append([m.dir, false])
		list.add_item("%s   (%s)" % [m.name, m.id])
	var hint := Label.new()
	hint.text = Lang.t("Dossier des cartes : %s", "Maps folder: %s") % ProjectSettings.globalize_path(EditorMap.maps_root())
	hint.add_theme_color_override("font_color", UiStyle.DIM)
	box.add_child(hint)
	d.ok_button_text = Lang.t("Ouvrir", "Open")
	d.cancel_button_text = Lang.t("Annuler", "Cancel")
	add_child(d)
	var go := func():
		var sel := list.get_selected_items()
		if not sel.is_empty():
			var en: Array = entries[sel[0]]
			open_dir(String(en[0]), bool(en[1]))
		d.queue_free()
	d.confirmed.connect(go)
	list.item_activated.connect(func(_i): go.call())
	d.canceled.connect(d.queue_free)
	d.popup_centered()


func _zip_dialog(save_mode: bool) -> void:
	if _file_dialog != null:
		_file_dialog.queue_free()
	_file_dialog = FileDialog.new()
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE if save_mode else FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.filters = PackedStringArray(["*.zip ; " + Lang.t("Archive de carte", "Map archive")])
	_file_dialog.title = Lang.t("Exporter l'archive", "Export the archive") if save_mode else Lang.t("Importer une archive", "Import an archive")
	_file_dialog.current_file = doc.id() + ".zip"
	_file_dialog.current_dir = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	_file_dialog.size = Vector2i(760, 480)
	add_child(_file_dialog)
	_file_dialog.file_selected.connect(func(path):
		if save_mode:
			export_zip(path)
		else:
			import_zip(path))
	_file_dialog.popup_centered()


func export_zip(path: String) -> bool:
	var err := doc.export_zip(path)
	if err != OK:
		set_status(Lang.t("Échec de l'export (%s)", "Export failed (%s)") % error_string(err), true)
		return false
	set_status(Lang.t("Archive exportée : %s", "Archive exported: %s") % path)
	return true


func import_zip(path: String) -> bool:
	var d := EditorMap.import_zip(path)
	if not d.load_errors.is_empty() and d.pieces.is_empty():
		_info(Lang.t("Import", "Import"), "\n".join(d.load_errors.map(func(e): return Lang.t(e[0], e[1]))))
		return false
	map_dir = ""
	example = false
	_reset(d)
	dirty = true
	_update_title()
	set_status(Lang.t("Archive importée : enregistrez-la (Ctrl+S) pour la garder", "Archive imported: save it (Ctrl+S) to keep it"))
	return true


# ------------------------------------------------------------------ récents, sauvegarde auto

static func _cfg_path() -> String:
	return EditorMap.maps_root().path_join("_editeur.cfg")


static func recent_maps() -> Array:
	var cf := ConfigFile.new()
	if cf.load(_cfg_path()) != OK:
		return []
	return (cf.get_value("editeur", "recentes", []) as Array).filter(func(d): return EditorMap.is_map_dir(String(d)))


func _add_recent(dir: String) -> void:
	var list := recent_maps()
	list.erase(dir)
	list.push_front(dir)
	var cf := ConfigFile.new()
	cf.load(_cfg_path())
	cf.set_value("editeur", "recentes", list.slice(0, RECENT_MAX))
	DirAccess.make_dir_recursive_absolute(EditorMap.maps_root())
	cf.save(_cfg_path())


func _fill_recent() -> void:
	_recent_menu.clear()
	for d in recent_maps():
		_recent_menu.add_item(String(d).get_file())
	if _recent_menu.item_count == 0:
		_recent_menu.add_item(Lang.t("(aucune)", "(none)"))
		_recent_menu.set_item_disabled(0, true)


static func _autosave_dir() -> String:
	return EditorMap.maps_root().path_join("_autosave")


## Sauvegarde automatique (toutes les 60 s et à la fermeture) si la carte a changé.
func autosave() -> void:
	if not dirty:
		return
	var dir := _autosave_dir()
	if doc.save_dir(dir) != OK:
		return
	var f := FileAccess.open(dir.path_join("meta.json"), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"source": map_dir, "example": example, "name": doc.display_name(), "time": int(Time.get_unix_time_from_system())}))
		f.close()


func _resume_autosave() -> void:
	var dir := _autosave_dir()
	var meta = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("meta.json"))) if FileAccess.file_exists(dir.path_join("meta.json")) else {}
	var d := EditorMap.load_dir(dir)
	_reset(d)
	if meta is Dictionary:
		map_dir = String(meta.get("source", ""))
		example = bool(meta.get("example", false))
	dirty = true
	_update_title()
	set_status(Lang.t("Travail non enregistré repris", "Unsaved work resumed"))


func _drop_autosave() -> void:
	var dir := _autosave_dir()
	if DirAccess.dir_exists_absolute(dir):
		for f in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute(dir.path_join(f))
		DirAccess.remove_absolute(dir)


func _on_close_requested() -> void:
	autosave()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		autosave()


# ------------------------------------------------------------------ menus

func _on_file_menu(id: int) -> void:
	match id:
		0:
			new_map()
		1:
			open_dialog()
		2:
			save()
		3:
			save_as_dialog()
		4:
			_zip_dialog(true)
		5:
			_zip_dialog(false)
		7:
			quit_to_menu()


func _on_edit_menu(id: int) -> void:
	match id:
		0:
			undo()
		1:
			redo()
		2:
			copy_selected()
		3:
			paste()
		4:
			rotate_selected()
		5:
			if selected != "":
				delete_element(selected)
		6:
			toggle_inventory()
		7:
			canvas.frame_all()


func quit_to_menu() -> void:
	autosave()
	get_tree().change_scene_to_file(Router.MENU_SCENE)


## TESTER : vérifie, enregistre, puis lance une partie solo sur la carte ; la
## fin de partie ramène dans l'éditeur, sur la même carte.
func test_map() -> bool:
	validate()
	panels.show_tab("check")
	if not validator.ok():
		_info(Lang.t("Tester", "Play test"), Lang.t("La carte n'est pas jouable : %d erreur(s). Corrigez-les (onglet Vérification, clic sur une erreur pour la voir).",
			"The map is not playable: %d error(s). Fix them (Check tab, click an error to see it).") % validator.errors().size())
		return false
	if not save():
		return false
	reopen_dir = map_dir
	reopen_example = false
	Router.return_scene = SCENE
	Router.start_solo(EditorMapDef.CUSTOM_PREFIX + map_dir.get_file())
	return true
