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
## Rotation (degrés) de l'objet tenu (prefabs, luminaires) : R avant de poser.
var place_rot := 0
## Variante de l'objet tenu (portes, débris, armes murales : V avant de
## poser) ; "" : l'aspect par défaut.
var place_variant := ""
## Élément survolé (liste des objets ou carte) : contour lumineux sur la carte.
var hover_id := ""
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
## Onglet déployable « Objets sur la carte » (à gauche de la vue).
var object_list: MapObjectList
var hotbar_ui: MapHotbar
var inventory: MapInventory
## Aperçu 3D en direct (MapPreviewPanel : bouton APERÇU 3D, touche P).
var preview: MapPreviewPanel
var status: Label
var cursor_label: Label
var title_label: Label
var floor_label: Label
var check_button: Button
## Mode d'aimantation (clic ou G : grille 1 m, grille fine, libre).
var snap_button: Button
var file_menu: MenuButton
var edit_menu: MenuButton
var _recent_menu: PopupMenu
var _dialog: AcceptDialog
var _dialog_scroll: ScrollContainer
var _dialog_label: Label
var _file_dialog: FileDialog
var _status_error := false
## Barre du haut (passe à la ligne si elle ne tient pas en largeur).
var top_bar: HFlowContainer
## Écran d'options ouvert par-dessus l'éditeur (bouton ⚙, Fichier > Options).
var options: EditorOptions
## Taille de l'interface appliquée (EditorUi ; -1 : pas encore).
var ui_scale := -1.0
## Contrôles ajoutés depuis, mis à l'échelle en fin d'image.
var _ui_pending: Array = []
var _ui_queued := false
## Position du plan à l'écran avant un changement de taille (_keep_plan_in_place).
var _plan_anchor := Vector2.ZERO
var _plan_pending := false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--check="):
			_cli_check(a.substr(8))
			return
	set_anchors_preset(Control.PRESET_FULL_RECT)
	if GameState.state != GameState.State.MAIN_MENU:
		GameState.reset_to_menu()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	theme = make_theme(EditorUi.factor())
	_build_ui()
	apply_ui_scale()
	get_tree().node_added.connect(_on_node_added)
	resized.connect(_fit_side_panels)
	Settings.editor_ui_scale_changed.connect(func(_v): apply_ui_scale())
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
		var meta: Variant = _read_meta(auto)
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
	# Barre du haut : passe sur deux lignes plutôt que de déborder (grande
	# taille d'interface).
	var top := PanelContainer.new()
	root.add_child(top)
	var bar := HFlowContainer.new()
	bar.name = "TopBar"
	bar.add_theme_constant_override("h_separation", 6)
	bar.add_theme_constant_override("v_separation", 4)
	top.add_child(bar)
	top_bar = bar
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
	fm.add_item(Lang.t("Options (taille de l'interface…)", "Options (interface size…)"), 8)
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
	em.add_item(Lang.t("Aspect suivant", "Next look") + "   V", 8)
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
	snap_button = Button.new()
	snap_button.tooltip_text = Lang.t("Aimantation : G pour changer (grille 1 m, grille fine, libre) ; Maj+G : pas de la grille fine ; Maj maintenu : inverse",
		"Snapping: G to change (1 m grid, fine grid, free); Shift+G: fine grid step; hold Shift: invert")
	snap_button.pressed.connect(func(): canvas.cycle_snap())
	bar.add_child(snap_button)
	# --- Aperçu 3D (MapPreviewPanel) : bouton et touche P.
	var preview_button := Button.new()
	preview_button.text = Lang.t("APERÇU 3D", "3D PREVIEW")
	preview_button.toggle_mode = true
	preview_button.focus_mode = Control.FOCUS_NONE
	preview_button.tooltip_text = Lang.t("Afficher / masquer l'aperçu 3D en direct (P)", "Show / hide the live 3D preview (P)")
	preview_button.toggled.connect(func(on): preview.set_shown(on))
	bar.add_child(preview_button)
	# --- fin aperçu 3D
	var opt := Button.new()
	opt.name = "OptionsButton"
	opt.text = "⚙"
	opt.focus_mode = Control.FOCUS_NONE
	opt.tooltip_text = Lang.t("Options du jeu (taille de l'interface de l'éditeur : Ctrl + / Ctrl - / Ctrl 0)",
		"Game options (map editor UI size: Ctrl + / Ctrl - / Ctrl 0)")
	opt.pressed.connect(open_options)
	bar.add_child(opt)
	# Nom et dossier de la carte, à droite ; coupé s'il est trop long.
	title_label = Label.new()
	title_label.add_theme_color_override("font_color", UiStyle.BONE)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_label.custom_minimum_size = Vector2(140, 0)
	title_label.mouse_filter = Control.MOUSE_FILTER_PASS
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
	object_list = MapObjectList.new()
	object_list.ed = self
	mid.add_child(object_list)
	canvas = MapCanvas.new()
	canvas.ed = self
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_child(canvas)
	panels = MapPanels.new()
	panels.ed = self
	# Largeur à l'échelle, bornée pour laisser la place au plan (side_width).
	panels.set_meta(EditorUi.KEEP_MIN, true)
	panels.custom_minimum_size = Vector2(side_width(PANEL_W), 0)
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
	# Texte du message dans une zone qui défile (aide « ? » à grande taille) ;
	# sa taille est calculée par _info.
	_dialog.get_label().visible = false
	_dialog_scroll = ScrollContainer.new()
	_dialog_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_dialog_scroll.set_meta(EditorUi.SKIP, true)
	_dialog_label = Label.new()
	_dialog_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dialog_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dialog_scroll.add_child(_dialog_label)
	_dialog.add_child(_dialog_scroll)
	add_child(_dialog)
	# --- Aperçu 3D (MapPreviewPanel), flottant au-dessus de la vue.
	preview = MapPreviewPanel.new()
	preview.ed = self
	add_child(preview)
	preview.shown_changed.connect(func(on): preview_button.set_pressed_no_signal(on))
	# --- fin aperçu 3D


## Thème de l'éditeur à la taille d'interface `f` (EditorUi) : styles écrits
## à 100 %, puis marges, bordures et arrondis mis à l'échelle, par-dessus le
## thème par défaut de Godot lui aussi à l'échelle (EditorUi.base_theme).
func make_theme(f := 1.0) -> Theme:
	var t := EditorUi.base_theme(f)
	t.default_font = UiStyle.font("body")
	t.default_font_size = EditorUi.fs(EditorUi.BODY_FONT, f)
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
	t.set_font_size("font_size", "TabContainer", EditorUi.fs(13, f))
	t.set_font_size("font_size", "TooltipLabel", EditorUi.fs(13, f))
	for type in ["PanelContainer", "Panel", "PopupMenu", "PopupPanel", "AcceptDialog", "ConfirmationDialog",
			"Button", "MenuButton", "OptionButton", "CheckBox", "LineEdit", "ItemList", "TabContainer"]:
		for n in t.get_stylebox_list(type):
			EditorUi.scale_stylebox(t.get_stylebox(n, type), f)
	return t


# ------------------------------------------------------------------ taille de l'interface

## Applique la taille d'interface du réglage (Settings.editor_ui_scale) à tout
## l'éditeur, en direct : thème, contrôles (EditorUi.scale_tree), dessins de
## la vue, barre rapide, liste des objets, inventaire, aperçu 3D. Le plan garde
## son zoom et ne bouge pas à l'écran : il gagne la place libérée.
func apply_ui_scale() -> void:
	var f := EditorUi.factor()
	var first := ui_scale < 0.0
	if not first and is_equal_approx(f, ui_scale):
		return
	var g0 := canvas.global_position
	ui_scale = f
	if not first:
		theme = make_theme(f)
		if preview != null and preview.window != null:
			preview.window.theme = theme
	EditorUi.scale_tree(self, f)
	_fit_side_panels()
	if hotbar_ui != null:
		hotbar_ui.queue_redraw_slots()
		hotbar_ui.ui_scale_changed()
	if object_list != null:
		object_list.ui_scale_changed()
	if inventory != null:
		inventory.ui_scale_changed()
	if preview != null:
		preview.ui_scale_changed()
	canvas.queue_redraw()
	if first:
		return
	set_status(Lang.t("Taille de l'interface : %d %% (Ctrl + / Ctrl - / Ctrl 0 ; Options, onglet JEU)",
		"Interface size: %d%% (Ctrl + / Ctrl - / Ctrl 0; Options, GAME tab)") % roundi(f * 100.0))
	# Après la mise en page (image suivante) : le plan reste à la même place à
	# l'écran, même après plusieurs changements dans la même image.
	if not _plan_pending:
		_plan_pending = true
		_plan_anchor = g0
		get_tree().process_frame.connect(_keep_plan_in_place, CONNECT_ONE_SHOT)


func _keep_plan_in_place() -> void:
	_plan_pending = false
	canvas.origin += _plan_anchor - canvas.global_position
	canvas.queue_redraw()


## Part de la largeur de l'éditeur que peut prendre chaque panneau latéral
## (liste des objets, panneaux de droite) : le plan garde au moins 40 %.
const SIDE_MAX := 0.3


## Largeur d'un panneau latéral de `base` pixels à 100 %, à la taille de
## l'interface, bornée par SIDE_MAX (grande taille, petite fenêtre).
func side_width(base: float) -> float:
	var w := EditorUi.px(base)
	return minf(w, roundf(size.x * SIDE_MAX)) if size.x > 0.0 else w


func _fit_side_panels() -> void:
	if panels != null:
		panels.custom_minimum_size = Vector2(side_width(PANEL_W), 0)
	if object_list != null:
		object_list.fit_width(side_width(MapObjectList.WIDTH))


## Ctrl + / Ctrl - (pas de 5 %), Ctrl 0 (taille par défaut) : même réglage
## que dans les options, enregistré tout de suite.
func step_ui_scale(dir: int) -> void:
	var v := Settings.EDITOR_UI_SCALE_DEFAULT if dir == 0 else Settings.editor_ui_scale + dir * Settings.EDITOR_UI_SCALE_STEP
	Settings.editor_ui_scale = v
	Settings.save_settings()
	if is_equal_approx(Settings.editor_ui_scale, ui_scale):
		set_status(Lang.t("Taille de l'interface : %d %% (de %d à %d %%)", "Interface size: %d%% (from %d to %d%%)") % [
			roundi(ui_scale * 100.0), roundi(Settings.EDITOR_UI_SCALE_RANGE.x * 100.0), roundi(Settings.EDITOR_UI_SCALE_RANGE.y * 100.0)])


## Contrôle ajouté à l'éditeur (panneaux reconstruits, fenêtres...) : mis à
## l'échelle en fin d'image, une fois ses tailles écrites par le code.
func _on_node_added(n: Node) -> void:
	if ui_scale < 0.0 or not n is Control:
		return
	_ui_pending.append(n)
	if not _ui_queued:
		_ui_queued = true
		_flush_ui_pending.call_deferred()


func _flush_ui_pending() -> void:
	_ui_queued = false
	var list := _ui_pending
	_ui_pending = []
	for n in list:
		if is_instance_valid(n) and (n as Node).is_inside_tree() and is_ancestor_of(n) and not EditorUi.skipped(n, self):
			EditorUi.scale_control(n, ui_scale)


# ------------------------------------------------------------------ options

## Écran d'options du jeu par-dessus l'éditeur (onglet JEU, sur la taille de
## l'interface) ; RETOUR ou Échap le ferme.
func open_options() -> void:
	if options_open():
		return
	canvas.cancel()
	canvas.set_space(false)
	options = EditorOptions.open_in(self)
	options.closed.connect(func(): options = null)


func options_open() -> bool:
	return options != null and is_instance_valid(options)


func set_status(text: String, error := false) -> void:
	status.text = text
	_status_error = error
	status.add_theme_color_override("font_color", Color(1, 0.55, 0.45) if error else Color(0.8, 0.8, 0.75))


func show_cursor(m: Vector2) -> void:
	var fr := not Lang.is_en()
	var s := canvas.snap(m)
	cursor_label.text = "x %s m · y %s m · %s %d" % [MapRules._m(snappedf(s.x, 0.01), fr), MapRules._m(snappedf(s.y, 0.01), fr), Lang.t("étage", "floor"), floor_k]


## Mode d'aimantation changé (MapCanvas) : bouton de la barre du haut.
func snap_changed() -> void:
	if snap_button != null and canvas != null:
		snap_button.text = Lang.t("Aimantation : %s", "Snapping: %s") % MapSnap.label(canvas.snap_mode, canvas.fine_step)


func _update_title() -> void:
	var where := Lang.t("exemple (copie à l'enregistrement)", "example (copied when saved)") if example else (map_dir if map_dir != "" else Lang.t("non enregistrée", "not saved"))
	title_label.text = "%s%s  —  %s" % [doc.display_name(), " *" if dirty else "", where]
	title_label.tooltip_text = title_label.text
	floor_label.text = Lang.t("Étage %d / %d", "Floor %d / %d") % [floor_k, doc.floor_count() - 1]
	snap_changed()
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
		"Clic gauche : poser / choisir · clic droit : annuler\nGlisser (ou clic puis clic) : pièces, formes, murs, piliers, escaliers, pièges\nG : aimantation grille 1 m, grille fine, libre (sans grille) · Maj+G : pas de la grille fine (0,5 / 0,25 / 0,1 m) · Maj maintenu : inverse le mode\nSans grille : aimants aux sommets et aux côtés des pièces, côtés à 15° près\nMurs et côtés de polygone : à 0, 45 ou 90° sur la grille ; Alt : angle libre (longueur et angle affichés)\nPendant un tracé : taper la longueur, Tab, l'angle (degrés depuis l'est), Entrée (rectangle : largeur, hauteur ; cercle : rayon, points)\nCercle, ellipse : molette ou + / - pendant le tracé : nombre de points (3 à 64) · mur courbe : segments\nPièce rectangle en main : R la tourne de 45°\nPoignée ronde de l'élément choisi : rotation par pas de 15° (Alt : au degré près) ; angle dans les propriétés\nCtrl + molette : zoom · clic milieu ou Espace + glisser : déplacer la vue\nCtrl + « + » / Ctrl + « - » / Ctrl + 0 : taille de l'interface de l'éditeur (aussi dans les options, bouton ⚙)\nMolette ou 1 à 9 : case de la barre rapide · E ou Tab : inventaire\nR : pivoter de 90° (aussi le décor tenu, avant de le poser) · Suppr : supprimer · Ctrl+C / Ctrl+V : copier / coller\nL : liste des objets sur la carte\nCtrl+Z / Ctrl+Y : annuler / rétablir · Ctrl+S : enregistrer\nPage préc. / suiv. : étage · Origine : recadrer · Entrée : fermer un polygone\nP : aperçu 3D · orbite : clic droit glisser, molette, clic milieu · vol libre et vue joueur : touches de déplacement du jeu, Maj, clic droit pour regarder\nClic dans l'aperçu : choisir l'élément · Ctrl + double-clic sur la carte : y placer la caméra de l'aperçu",
		"Left click: place / pick · right click: cancel\nDrag (or click then click): rooms, shapes, walls, pillars, stairs, traps\nG: snapping 1 m grid, fine grid, free (no grid) · Shift+G: fine grid step (0.5 / 0.25 / 0.1 m) · hold Shift: invert the mode\nNo grid: magnets on room corners and sides, sides at 15° steps\nWalls and polygon sides: at 0, 45 or 90° on the grid; Alt: free angle (length and angle shown)\nWhile drawing: type the length, Tab, the angle (degrees from east), Enter (rectangle: width, height; circle: radius, points)\nCircle, ellipse: wheel or + / - while drawing: number of points (3 to 64) · curved wall: segments\nRectangle room held: R turns it 45°\nRound handle of the selected element: rotate in 15° steps (Alt: to the degree); angle in the properties\nCtrl + wheel: zoom · middle click or Space + drag: pan\nCtrl + \"+\" / Ctrl + \"-\" / Ctrl + 0: map editor UI size (also in the options, ⚙ button)\nWheel or 1 to 9: hotbar slot · E or Tab: inventory\nR: rotate 90° (also the held prop, before placing it) · Del: delete · Ctrl+C / Ctrl+V: copy / paste\nL: list of the items on the map\nCtrl+Z / Ctrl+Y: undo / redo · Ctrl+S: save\nPage Up / Down: floor · Home: frame · Enter: close a polygon\nP: 3D preview · orbit: right drag, wheel, middle drag · free flight and player view: game movement keys, Shift, right drag to look\nClick in the preview: pick the element · Ctrl + double-click on the map: move the preview camera there"))


func _info(title_text: String, text: String) -> void:
	_dialog.title = title_text
	_dialog_label.text = text
	# Texte replié à une largeur qui tient dans la fenêtre, et qui défile s'il
	# est plus haut qu'elle (toutes les tailles d'interface).
	var vp := get_viewport_rect().size
	var w := minf(EditorUi.px(820.0), vp.x - 80.0)
	var font := _dialog_label.get_theme_font("font")
	var fsz := _dialog_label.get_theme_font_size("font_size")
	var h := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, w, fsz).y
	h += h / maxf(font.get_height(fsz), 1.0) * _dialog_label.get_theme_constant("line_spacing") + 8.0
	_dialog_scroll.custom_minimum_size = Vector2(w + EditorUi.px(14.0), minf(h, vp.y - 160.0))
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
	# Options ouvertes par-dessus : les touches sont à elles.
	if options_open():
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
			# Taille de l'interface (Ctrl + molette reste le zoom du plan).
			KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
				step_ui_scale(1)
			KEY_MINUS, KEY_KP_SUBTRACT:
				step_ui_scale(-1)
			KEY_0, KEY_KP_0:
				step_ui_scale(0)
			_:
				# Ctrl 0 sur un clavier AZERTY (touche « à / 0 »).
				if k.physical_keycode == KEY_0:
					step_ui_scale(0)
				else:
					return
		get_viewport().set_input_as_handled()
		return
	if _typing():
		if k.keycode == KEY_ESCAPE:
			get_viewport().gui_release_focus()
			get_viewport().set_input_as_handled()
		return
	# Aimantation (G), saisie au clavier du tracé, points d'une forme (+ / -).
	if canvas.handle_key(k):
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
			KEY_V:
				cycle_variant()
			KEY_L:
				object_list.toggle()
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
	place_rot = 0
	place_variant = ""
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
	_hit_dirty = true
	_raster_dirty = true
	validation_stale = true
	_validate_t = 1.0
	if doc.find(selected).is_empty():
		selected = ""
	if hover_id != "" and doc.find(hover_id).is_empty():
		hover_id = ""
	_update_invalid()
	canvas.queue_redraw()
	if rebuild_panels:
		panels.refresh()
	object_list.mark_dirty()
	_update_title()


## Modification en direct (glissement) : dessin seulement.
func moved_live() -> void:
	dirty = true
	_hit_dirty = true
	_raster_dirty = true
	validation_stale = true
	canvas.queue_redraw()


func _update_invalid() -> void:
	invalid.clear()
	# Emprises calculées une fois pour toute la carte (rapide avec 2000 objets).
	MapRules.begin_batch(doc)
	for list in [doc.pieces, doc.ouvertures, doc.objets]:
		for e in list:
			var r := MapRules.check_existing(doc, e)
			if not r.ok:
				invalid[String(e.id)] = MapRules.why(r)
	MapRules.end_batch()


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
	object_list.refresh_rows()
	canvas.queue_redraw()


## Survol d'un élément sur la carte : sa ligne est surlignée dans la liste des
## objets (qui saute à la bonne page) et l'élément est entouré sur la carte.
func map_hovered(eid: String) -> void:
	if eid == hover_id:
		return
	hover_id = eid
	object_list.show_hover(eid)
	canvas.queue_redraw()


## Survol d'une ligne de la liste : l'élément est entouré sur la carte, la vue
## ne bouge pas.
func list_hovered(eid: String) -> void:
	if eid == hover_id:
		return
	hover_id = eid
	canvas.queue_redraw()


## Double-clic sur une ligne : vue centrée et zoomée sur l'élément.
func zoom_to_element(eid: String) -> void:
	focus_element(eid)
	var e := doc.find(eid)
	if e.is_empty():
		return
	var r := MapGeom.bbox(doc.room_poly(e)) if e.has("contour") else MapRules.footprint_rect(e)
	var avail := canvas.size * 0.6
	canvas.zoom = clampf(minf(avail.x / maxf(r.size.x, 1.0), avail.y / maxf(r.size.y, 1.0)), MapCanvas.MIN_ZOOM, 60.0)
	canvas.center_on(r.get_center() if not String(e.get("type", "")) in MapRules.ouvertures_types() else MapGeom.v2(e.position))


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
		var prefix: String = {"atout": "a", "arme": "w", "boite": "b", "depart": "s", "escalier": "e", "pilier": "x", "mur": "m", "mur_courbe": "m",
			"piege": "t", "levier": "l", "prefab": "d", "luminaire": "lu", "bloc_invisible": "i"}.get(String(e.get("type", "")), "x")
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
	return MapTransform.attached(doc, e)


## Élément sous le point `m` de l'étage courant (ouvertures et objets avant les pièces).
func element_at(m: Vector2) -> Dictionary:
	for o in doc.openings_on(floor_k):
		if MapRules.hit(doc, o, m):
			return o
	# Le plus petit objet touché d'abord (une lampe sur un bureau). Seuls les
	# objets rangés dans la case de 4 m du point sont essayés (survol fluide
	# avec 2000 objets).
	var best := {}
	var best_area := INF
	for o in _hit_candidates(m):
		if MapRules.hit(doc, o, m):
			var a := MapRules.footprint_rect(o).get_area()
			if a < best_area:
				best_area = a
				best = o
	if not best.is_empty():
		return best
	for p in doc.rooms_on(floor_k):
		if MapRules.hit(doc, p, m):
			return p
	return {}


## Index des objets par cases de 4 m (étage -> {case: [objets]}), refait
## après chaque modification (clic, survol : seulement les objets proches).
const HIT_BUCKET := 4.0
var _hit_index: Dictionary = {}
var _hit_dirty := true


func _hit_candidates(m: Vector2) -> Array:
	if _hit_dirty:
		_hit_dirty = false
		_hit_index = {}
		for o in doc.objets:
			var r := MapRules.footprint_rect(o).grow(0.35)
			var grid: Dictionary = _hit_index.get_or_add(int(o.get("etage", 0)), {})
			for j in range(floori(r.position.y / HIT_BUCKET), floori(r.end.y / HIT_BUCKET) + 1):
				for i in range(floori(r.position.x / HIT_BUCKET), floori(r.end.x / HIT_BUCKET) + 1):
					grid.get_or_add(Vector2i(i, j), []).append(o)
	return _hit_index.get(floor_k, {}).get(Vector2i(floori(m.x / HIT_BUCKET), floori(m.y / HIT_BUCKET)), [])


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
	set_status(Lang.t("%s supprimé", "%s deleted") % _label(e) + (Lang.t(" (avec %d élément(s) rattaché(s))", " (with %d attached element(s))") % (n - 1) if n > 1 else ""))


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
		if e.has("forme") and MapShapes.valid(e.forme):
			e.forme = MapShapes.shifted(e.forme, delta)
	for key in ["position", "a", "b", "centre"]:
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
					MapRules.apply_wall(cand, res)
			"floor_item":
				res = MapRules.place_floor_item(doc, k, orig, MapGeom.v2(cand.position), String(orig.id), canvas.mode_now() != "libre")
				if res.ok:
					cand.position = res.position
			"rect":
				res = MapRules.check_rect(doc, k, t, MapGeom.rect_of(cand.rect), String(orig.id), MapGeom.rot_of(cand))
			"wall":
				res = MapRules.check_wall(MapGeom.v2(cand.a), MapGeom.v2(cand.b))
			"arc":
				res = MapRules.check_arc(cand)
	if not res.ok:
		return res
	doc.restore(snap0)
	_replace(cand)
	for aid in attached:
		var a := doc.find(aid)
		if not a.is_empty():
			_replace(_shift(a, delta))
	if t in ["mur", "mur_courbe"]:
		# Objets accrochés au mur libre : raccrochés à sa face (un mur déplacé
		# hors de la grille devient un vrai mur oblique).
		for aid in attached:
			var a := doc.find(aid)
			if a.is_empty():
				continue
			var r := MapRules.place_wall_item(doc, k, a, MapGeom.v2(a.position) - MapGeom.item_wall_dir(a) * 0.3, aid)
			if r.ok:
				a["position"] = r.position
				MapRules.apply_wall(a, r)
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
		if MapGeom.is_axis_rect(poly) and not orig.has("forme"):
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
		# Sommet déplacé à la main : la forme de base d'origine ne se régénère plus.
		cand.erase("forme")
		res = MapRules.check_room(doc, k, np, String(orig.id))
	elif orig.has("rect") and MapGeom.rot_of(orig) != 0:
		# Rectangle tourné : le coin opposé reste en place, dans le repère du rectangle.
		var rot := float(MapGeom.rot_of(orig))
		var corners := MapRaster.rect_poly(orig)
		var opp: Vector2 = corners[(h + 2) % 4]
		var local := (p - opp).rotated(-deg_to_rad(rot))
		var sz := local.abs()
		var c := opp + (local * 0.5).rotated(deg_to_rad(rot))
		var nr := Rect2(c - sz * 0.5, sz)
		cand.rect = MapGeom.rect_arr(nr)
		res = MapRules.check_rect(doc, k, String(orig.type), nr, String(orig.id), int(rot))
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


## Élément tourné de 90° (sens horaire) autour de `c` (MapTransform.rotated).
static func _rot(o: Dictionary, c: Vector2) -> Dictionary:
	return MapTransform.rotated(o, c, 90.0)


## Emprise d'un objet au sol pivoté : sa position est ré-aimantée pour que ses
## cases tombent sur la grille (un prefab 3 × 2 devient 2 × 3).
func _resnap(o: Dictionary) -> void:
	MapTransform.resnap(o)


## R : pivote de 90° l'objet tenu (prefab, luminaire : avant de le poser),
## sinon l'élément choisi (une pièce pivote avec son contenu).
func rotate_selected() -> void:
	var held := current_item()
	if String(held.get("tool", "")) == "room_rect":
		# Pièce rectangle : R bascule entre un rectangle droit et un rectangle
		# tourné de 45° (losange), tracé d'un coin à l'autre.
		place_rot = 45 if place_rot != 45 else 0
		canvas.queue_redraw()
		set_status(Lang.t("Pièce rectangle : tournée de 45° (R pour revenir droite)", "Rectangle room: turned 45° (R to go back straight)") if place_rot == 45
			else Lang.t("Pièce rectangle : droite (R pour la tourner de 45°)", "Rectangle room: straight (R to turn it 45°)"))
		return
	if held.get("rotates", false):
		place_rot = (place_rot + 90) % 360
		canvas._update_preview()
		canvas.queue_redraw()
		set_status(Lang.t("%s : rotation %d°", "%s: rotation %d°") % [MapCatalog.name_of(held), place_rot])
		return
	var e := doc.find(selected)
	if e.is_empty():
		set_status(Lang.t("Choisissez d'abord un élément (outil Sélection)", "Pick an element first (Select tool)"))
		return
	if not MapTransform.can_rotate(e):
		set_status(Lang.t("Cet élément suit son mur : déplacez-le plutôt", "This element follows its wall: move it instead"))
		return
	var before := doc.snapshot()
	var c := MapTransform.pivot(doc, e)
	if e.has("contour") and not e.has("forme"):
		c = MapGeom.bbox(doc.room_poly(e)).get_center()
	# Sur la grille, un quart de tour garde les sommets sur la grille.
	if not e.has("position") and canvas.mode_now() != "libre" and not (e.has("forme") or String(e.get("type", "")) == "mur_courbe"):
		c = Vector2(snappedf(c.x, 0.5), snappedf(c.y, 0.5))
	var attached := attached_to(e)
	var re := _rot(e, c)
	_resnap(re)
	_replace(re)
	for aid in attached:
		var ra := _rot(doc.find(aid), c)
		_resnap(ra)
		_replace(ra)
	var ne := doc.find(selected)
	var res := MapRules.check_existing(doc, ne)
	if not res.ok:
		doc.restore(before)
		_hit_dirty = true
		canvas.show_refusal(res)
		return
	push_undo_snapshot(before)
	changed()
	set_status(Lang.t("Pivoté de 90°", "Rotated 90°"))


## V : variante suivante (aspect) de l'objet tenu (avant de le poser), sinon
## de l'élément choisi (MapCatalog.VARIANTS : portes, débris, armes murales).
func cycle_variant() -> void:
	var held := current_item()
	var make: Dictionary = held.get("make", {})
	var ht := String(make.get("type", ""))
	if MapCatalog.variants(ht).size() > 1 and String(held.get("tool", "")) != "select":
		var cur := place_variant if place_variant != "" else MapCatalog.default_variant(ht)
		place_variant = MapCatalog.next_variant(ht, cur)
		canvas._update_preview()
		canvas.queue_redraw()
		set_status(Lang.t("%s : %s (V : aspect suivant)", "%s: %s (V: next look)") % [MapCatalog.name_of(held), MapCatalog.variant_name(ht, place_variant)])
		return
	var e := doc.find(selected)
	if e.is_empty():
		set_status(Lang.t("Choisissez d'abord une porte, des débris, une arme murale ou un escalier (outil Sélection)",
			"Pick a door, debris, a wall weapon or stairs first (Select tool)"))
		return
	var t := String(e.get("type", ""))
	if MapCatalog.variants(t).size() < 2:
		set_status(Lang.t("Cet élément n'a qu'un seul aspect", "This element has only one look"))
		return
	push_undo()
	MapCatalog.set_variant(e, MapCatalog.next_variant(t, MapCatalog.variant_of(e)))
	MapCatalog.tidy_stair(e)
	changed()
	set_status(Lang.t("Aspect : %s (V : suivant)", "Look: %s (V: next)") % MapCatalog.variant_name(t, MapCatalog.variant_of(e)))


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
	var delta := target - (c if canvas.mode_now() == "libre" else Vector2(snappedf(c.x, 0.5), snappedf(c.y, 0.5)))
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
					MapRules.apply_wall(e, res)
			"floor_item":
				res = MapRules.place_floor_item(doc, floor_k, e, target, "", canvas.mode_now() != "libre")
				if res.ok:
					e.position = res.position
			"rect":
				res = MapRules.check_rect(doc, floor_k, t, MapGeom.rect_of(e.rect), "", MapGeom.rot_of(e), MapCatalog.stair_kind(e))
			"wall":
				res = MapRules.check_wall(MapGeom.v2(e.a), MapGeom.v2(e.b))
			"arc":
				res = MapRules.check_arc(e)
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
	if doc.floor_count() >= MapCatalog.MAX_FLOORS:
		set_status(Lang.t("%d étages au plus" % MapCatalog.MAX_FLOORS, "%d floors at most" % MapCatalog.MAX_FLOORS), true)
		return
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
	_hit_dirty = true
	undo_stack.clear()
	redo_stack.clear()
	selected = ""
	hover_id = ""
	floor_k = 0
	validator = null
	canvas.cancel()
	canvas.highlight = []
	object_list.mark_dirty()
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
	# Fenêtre de Godot (contenu interne) : seule sa taille suit l'interface.
	_file_dialog.set_meta(EditorUi.SKIP, true)
	_file_dialog.size = Vector2i((Vector2(760, 480) * ui_scale).min(get_viewport_rect().size - Vector2(40, 40)))
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


## Réglage mémorisé de l'éditeur (_editeur.cfg, section « editeur »).
## Réglages de l'éditeur lus sans décoder d'objet (SafeConfig : un .cfg piégé
## pourrait sinon exécuter du code) ; fichier vide s'il est absent ou refusé.
static func _load_cfg() -> ConfigFile:
	var cf := SafeConfig.load_file(_cfg_path())
	return cf if cf != null else ConfigFile.new()


static func pref(key: String, default: Variant) -> Variant:
	var v: Variant = _load_cfg().get_value("editeur", key, default)
	return v if typeof(v) == typeof(default) else default


static func set_pref(key: String, value: Variant) -> void:
	var cf := _load_cfg()
	cf.set_value("editeur", key, value)
	DirAccess.make_dir_recursive_absolute(EditorMap.maps_root())
	var err := cf.save(_cfg_path())
	if err != OK:
		push_warning("[MapEditor] préférences non enregistrées (%s)" % error_string(err))


static func recent_maps() -> Array:
	var list: Variant = _load_cfg().get_value("editeur", "recentes", [])
	if not list is Array:
		return []
	return (list as Array).filter(func(d): return d is String and EditorMap.is_map_dir(d))


func _add_recent(dir: String) -> void:
	var list := recent_maps()
	list.erase(dir)
	list.push_front(dir)
	var cf := _load_cfg()
	cf.set_value("editeur", "recentes", list.slice(0, RECENT_MAX))
	DirAccess.make_dir_recursive_absolute(EditorMap.maps_root())
	var err := cf.save(_cfg_path())
	if err != OK:
		push_warning("[MapEditor] préférences non enregistrées (%s)" % error_string(err))


func _fill_recent() -> void:
	_recent_menu.clear()
	for d in recent_maps():
		_recent_menu.add_item(String(d).get_file())
	if _recent_menu.item_count == 0:
		_recent_menu.add_item(Lang.t("(aucune)", "(none)"))
		_recent_menu.set_item_disabled(0, true)


## Taille maximale du meta.json de la sauvegarde automatique.
const MAX_META_BYTES := 256 * 1024


## meta.json de la sauvegarde automatique (source, nom, date) : {} s'il est
## absent, illisible ou trop gros (256 Ko au plus).
static func _read_meta(dir: String) -> Variant:
	var txt: Variant = EditorMap.read_text(dir.path_join("meta.json"), MAX_META_BYTES)
	var meta: Variant = JSON.parse_string(txt) if txt != null else null
	return meta if meta is Dictionary else {}


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
	var meta: Variant = _read_meta(dir)
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
		8:
			open_options()


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
		8:
			cycle_variant()


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
	CrashGuard.context("éditeur de cartes : TESTER « %s »" % map_dir.get_file(), true)
	Router.start_solo(EditorMapDef.CUSTOM_PREFIX + map_dir.get_file())
	return true
