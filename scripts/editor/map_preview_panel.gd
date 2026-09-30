class_name MapPreviewPanel
extends Control
## Fenêtre d'APERÇU 3D de l'éditeur de cartes (docs/MAP_AUTHORING.md, §2 ter) :
## panneau flottant au-dessus de la vue 2D (bouton APERÇU 3D ou touche P),
## déplaçable par sa barre de titre, redimensionnable par son coin, agrandi à
## tout l'éditeur (⛶) ou détaché dans une vraie fenêtre (⧉, que l'on peut
## mettre sur un deuxième écran). Il montre la carte telle qu'elle sera en jeu
## (MapPreviewWorld), mise à jour toute seule après chaque modification.
##
## Caméras (MapPreviewCamera) : orbite, vol libre, vue joueur ; « Centrer »
## sur la sélection ; « Suivre la 2D » ; Ctrl + double-clic sur la carte 2D :
## la caméra va à cet endroit ; un repère sur la vue 2D montre où elle est et
## où elle regarde. Clic dans l'aperçu : choisit l'élément dans l'éditeur.
##
## Performances : rien n'est construit ni rendu quand l'aperçu est masqué, ni
## (option) quand l'éditeur n'a pas le focus ; résolution de rendu réglable
## (100 à 35 %, en plus de celle de RenderQuality) ; au repos, 24 images/s au
## plus (le rendu suit la souris dès que la caméra bouge).
## Position, taille et réglages mémorisés (_editeur.cfg, clé « apercu »).

signal shown_changed(on: bool)

const MIN_SIZE := Vector2(340, 240)
const DEFAULT_SIZE := Vector2(560, 380)
const IDLE_FPS := 24.0
const SCALES := [1.0, 0.75, 0.5, 0.35]
const PREF_KEY := "apercu"
const OFF := MapGeom.WORLD_OFFSET
const COL_CAM := Color(1.0, 0.55, 0.15)
## Options du menu Affichage (identifiants).
enum Opt { POWER, FULL, CEIL, FLOORS_ALL, FLOORS_UP_TO, FLOORS_ONLY, SCALE_0 = 10, PAUSE = 20 }

var ed: MapEditor
var world: MapPreviewWorld
var shown := false
var maximized := false
var detached := false
var follow := false
var render_scale := 0.75
## Rendu en pause quand ni l'éditeur ni la fenêtre détachée n'ont le focus.
var pause_unfocused := true
## Images demandées au rendu (tests : aucune quand l'aperçu est masqué).
var renders := 0
var window: Window

var frame: PanelContainer
var content: VBoxContainer
var view: PreviewView
var title_label: Label
var info: Label
var hint: Label
var cam_mode: OptionButton
var follow_box: CheckBox
var display_menu: MenuButton
var grip: Control
var _free_rect := Rect2()
var _drag := ""
var _drag_from := Vector2.ZERO
var _rect0 := Rect2()
var _render_t := 0.0
var _save_t := -1.0
var _hover_m := Vector2(INF, INF)
var _hover_2d := ""
var _mouse_in_view := false
var _rmb := false
var _mmb := false
var _lmb_at := Vector2(-1, -1)
var _capture_at := Vector2.ZERO
var _last_status := ""


## Vue : le rendu du SubViewport, qui reçoit souris et touches (aussi dans
## la fenêtre détachée).
class PreviewView extends TextureRect:
	var panel: MapPreviewPanel

	func _gui_input(event: InputEvent) -> void:
		panel._view_input(event)

	func _input(event: InputEvent) -> void:
		panel._view_key(event)


func _ready() -> void:
	name = "Preview3D"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	world = MapPreviewWorld.new()
	world.name = "PreviewWorld"
	add_child(world)
	_build_ui()
	visible = false
	_load_prefs.call_deferred()


# ------------------------------------------------------------------ interface

func _build_ui() -> void:
	frame = PanelContainer.new()
	frame.name = "Frame"
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.1, 0.11, 0.97)
	sb.border_color = Color(0.85, 0.5, 0.2, 0.8)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(3)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 6
	frame.add_theme_stylebox_override("panel", sb)
	add_child(frame)
	var outer := VBoxContainer.new()
	outer.name = "Outer"
	outer.add_theme_constant_override("separation", 2)
	frame.add_child(outer)
	# Barre de titre (glisser : déplacer).
	var bar := HBoxContainer.new()
	bar.name = "TitleBar"
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	bar.mouse_default_cursor_shape = Control.CURSOR_MOVE
	bar.gui_input.connect(_title_input)
	outer.add_child(bar)
	title_label = Label.new()
	title_label.text = Lang.t("APERÇU 3D", "3D PREVIEW")
	title_label.add_theme_color_override("font_color", Color(1.0, 0.72, 0.4))
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.clip_text = true
	bar.add_child(title_label)
	bar.add_child(_small_button("⛶", Lang.t("Agrandir à tout l'éditeur / réduire", "Fill the whole editor / restore"), func(): set_maximized(not maximized)))
	bar.add_child(_small_button("⧉", Lang.t("Détacher dans une fenêtre séparée (deuxième écran)", "Detach into a separate window (second screen)"), func(): set_detached(true)))
	bar.add_child(_small_button("✕", Lang.t("Masquer l'aperçu (P)", "Hide the preview (P)"), func(): set_shown(false)))
	content = VBoxContainer.new()
	content.name = "Content"
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 2)
	outer.add_child(content)
	# Barre d'outils.
	var tools := HBoxContainer.new()
	tools.name = "Tools"
	tools.add_theme_constant_override("separation", 4)
	content.add_child(tools)
	cam_mode = OptionButton.new()
	cam_mode.add_item(Lang.t("Orbite", "Orbit"), MapPreviewCamera.Mode.ORBIT)
	cam_mode.add_item(Lang.t("Vol libre", "Free flight"), MapPreviewCamera.Mode.FLY)
	cam_mode.add_item(Lang.t("Joueur", "Player"), MapPreviewCamera.Mode.WALK)
	cam_mode.tooltip_text = Lang.t("Caméra : orbite autour d'un point, vol libre, ou vue joueur à hauteur d'yeux (avec les collisions)",
		"Camera: orbit around a point, free flight, or player view at eye height (with collisions)")
	cam_mode.item_selected.connect(func(i): set_camera_mode(cam_mode.get_item_id(i)))
	cam_mode.focus_mode = Control.FOCUS_NONE
	tools.add_child(cam_mode)
	var center := Button.new()
	center.text = Lang.t("⌖ Sélection", "⌖ Selection")
	center.tooltip_text = Lang.t("Centrer la caméra sur l'élément choisi", "Center the camera on the selected element")
	center.focus_mode = Control.FOCUS_NONE
	center.pressed.connect(center_on_selection)
	tools.add_child(center)
	var whole := Button.new()
	whole.text = Lang.t("Carte", "Map")
	whole.tooltip_text = Lang.t("Recadrer sur toute la carte", "Frame the whole map")
	whole.focus_mode = Control.FOCUS_NONE
	whole.pressed.connect(func(): world.frame_map())
	tools.add_child(whole)
	follow_box = CheckBox.new()
	follow_box.text = Lang.t("Suivre la 2D", "Follow 2D")
	follow_box.tooltip_text = Lang.t("La caméra vise ce que montre la vue 2D", "The camera aims at what the 2D view shows")
	follow_box.focus_mode = Control.FOCUS_NONE
	follow_box.toggled.connect(func(on): set_follow(on))
	tools.add_child(follow_box)
	display_menu = MenuButton.new()
	display_menu.text = Lang.t("Affichage ▾", "Display ▾")
	display_menu.flat = false
	display_menu.focus_mode = Control.FOCUS_NONE
	tools.add_child(display_menu)
	var pm := display_menu.get_popup()
	pm.add_check_item(Lang.t("Courant rétabli (luminaires liés au courant)", "Power on (power-linked lights)"), Opt.POWER)
	pm.add_check_item(Lang.t("Éclairage plein (tout voir)", "Full lighting (see everything)"), Opt.FULL)
	pm.add_check_item(Lang.t("Masquer les plafonds (vue en coupe)", "Hide ceilings (cutaway view)"), Opt.CEIL)
	pm.add_separator(Lang.t("Étages", "Floors"))
	pm.add_radio_check_item(Lang.t("Tous les étages", "All floors"), Opt.FLOORS_ALL)
	pm.add_radio_check_item(Lang.t("Jusqu'à l'étage affiché en 2D", "Up to the floor shown in 2D"), Opt.FLOORS_UP_TO)
	pm.add_radio_check_item(Lang.t("Seulement l'étage affiché en 2D", "Only the floor shown in 2D"), Opt.FLOORS_ONLY)
	pm.add_separator(Lang.t("Résolution du rendu", "Render resolution"))
	for i in SCALES.size():
		pm.add_radio_check_item("%d %%" % roundi(SCALES[i] * 100.0), Opt.SCALE_0 + i)
	pm.add_separator()
	pm.add_check_item(Lang.t("Pause quand l'éditeur n'a pas le focus", "Pause when the editor is not focused"), Opt.PAUSE)
	pm.hide_on_checkable_item_selection = false
	pm.id_pressed.connect(_on_display)
	# Vue.
	view = PreviewView.new()
	view.name = "View"
	view.panel = self
	view.texture = world.viewport.get_texture()
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_SCALE
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view.mouse_filter = Control.MOUSE_FILTER_STOP
	view.focus_mode = Control.FOCUS_CLICK
	view.mouse_entered.connect(func(): _mouse_in_view = true)
	view.mouse_exited.connect(func(): _mouse_in_view = false)
	content.add_child(view)
	info = Label.new()
	info.name = "Info"
	info.position = Vector2(6, 4)
	info.add_theme_color_override("font_color", Color(1, 0.95, 0.85))
	info.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	info.add_theme_constant_override("outline_size", 4)
	info.add_theme_font_size_override("font_size", 12)
	view.add_child(info)
	hint = Label.new()
	hint.name = "Hint"
	hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint.position = Vector2(6, -20)
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	hint.add_theme_constant_override("outline_size", 4)
	hint.add_theme_font_size_override("font_size", 11)
	view.add_child(hint)
	# Coin de redimensionnement.
	grip = Control.new()
	grip.name = "Grip"
	grip.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	grip.offset_left = -16
	grip.offset_top = -16
	grip.mouse_filter = Control.MOUSE_FILTER_STOP
	grip.mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
	grip.gui_input.connect(_grip_input)
	grip.draw.connect(func():
		var g := grip.size.x
		for i in 3:
			var o := g * (0.25 + i * 0.25)
			grip.draw_line(Vector2(g, o), Vector2(o, g), Color(1, 0.7, 0.4, 0.8), 1.5))
	add_child(grip)
	_refresh_menu()
	_refresh_hint()


func _small_button(txt: String, tip: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = txt
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(26, 0)
	b.pressed.connect(cb)
	return b


func _refresh_menu() -> void:
	var pm := display_menu.get_popup()
	pm.set_item_checked(pm.get_item_index(Opt.POWER), world.power_on)
	pm.set_item_checked(pm.get_item_index(Opt.FULL), world.full_light)
	pm.set_item_checked(pm.get_item_index(Opt.CEIL), world.hide_ceilings)
	pm.set_item_checked(pm.get_item_index(Opt.FLOORS_ALL), world.floors_mode == MapPreviewWorld.Floors.ALL)
	pm.set_item_checked(pm.get_item_index(Opt.FLOORS_UP_TO), world.floors_mode == MapPreviewWorld.Floors.UP_TO)
	pm.set_item_checked(pm.get_item_index(Opt.FLOORS_ONLY), world.floors_mode == MapPreviewWorld.Floors.ONLY)
	for i in SCALES.size():
		pm.set_item_checked(pm.get_item_index(Opt.SCALE_0 + i), is_equal_approx(SCALES[i], render_scale))
	pm.set_item_checked(pm.get_item_index(Opt.PAUSE), pause_unfocused)
	cam_mode.select(cam_mode.get_item_index(world.rig.mode))
	follow_box.set_pressed_no_signal(follow)


func _on_display(id: int) -> void:
	match id:
		Opt.POWER:
			set_option("power", not world.power_on)
		Opt.FULL:
			set_option("full", not world.full_light)
		Opt.CEIL:
			set_option("ceil", not world.hide_ceilings)
		Opt.FLOORS_ALL, Opt.FLOORS_UP_TO, Opt.FLOORS_ONLY:
			set_option("floors", id - Opt.FLOORS_ALL)
		Opt.PAUSE:
			pause_unfocused = not pause_unfocused
		_:
			if id >= Opt.SCALE_0 and id < Opt.SCALE_0 + SCALES.size():
				set_render_scale(SCALES[id - Opt.SCALE_0])
	_refresh_menu()
	_save_soon()


## Option d'affichage : « power » (courant), « full » (éclairage plein),
## « ceil » (plafonds masqués), « floors » (MapPreviewWorld.Floors).
func set_option(key: String, value: Variant) -> void:
	world.set_options({key: value})
	_refresh_menu()
	_save_soon()
	_request_render()


func set_render_scale(s: float) -> void:
	render_scale = clampf(s, 0.25, 1.0)
	_refresh_menu()
	_save_soon()


func set_camera_mode(m: int) -> void:
	world.rig.set_mode(m as MapPreviewCamera.Mode, world.ground_below)
	_refresh_menu()
	_refresh_hint()
	_save_soon()


func set_follow(on: bool) -> void:
	follow = on
	_refresh_menu()
	_save_soon()


func _refresh_hint() -> void:
	match world.rig.mode:
		MapPreviewCamera.Mode.ORBIT:
			hint.text = Lang.t("Clic droit glisser : tourner · molette : zoom · clic milieu : déplacer · clic : choisir",
				"Right drag: orbit · wheel: zoom · middle drag: pan · click: pick")
		MapPreviewCamera.Mode.FLY:
			hint.text = Lang.t("Déplacement du jeu (ZQSD / WASD) · Maj : vite · clic droit : regarder · Espace / Ctrl : monter / descendre",
				"Game movement keys (WASD) · Shift: fast · right drag: look · Space / Ctrl: up / down")
		MapPreviewCamera.Mode.WALK:
			hint.text = Lang.t("Vue joueur (1,6 m) : ZQSD / WASD · Maj : courir · Espace : sauter · clic droit : regarder",
				"Player view (1.6 m): WASD · Shift: run · Space: jump · right drag: look")


# ------------------------------------------------------------------ affichage

func toggle() -> void:
	set_shown(not shown)


func set_shown(on: bool) -> void:
	if on == shown:
		return
	shown = on
	if detached:
		if window != null:
			window.visible = on
	else:
		visible = on
	if on:
		_clamp_rect()
		_request_render()
	else:
		_release_mouse()
	world.active = on
	shown_changed.emit(on)
	if ed != null and ed.canvas != null:
		ed.canvas.queue_redraw()
	_save_soon()


## L'aperçu est-il à l'écran (panneau ou fenêtre détachée) ?
func is_on_screen() -> bool:
	return shown and (visible if not detached else window != null and window.visible)


func set_maximized(on: bool) -> void:
	if detached:
		return
	if on and not maximized:
		_free_rect = Rect2(position, size)
	maximized = on
	if on:
		position = Vector2.ZERO
		size = _area_size()
	else:
		_apply_rect(_free_rect)
	_save_soon()


## Fenêtre séparée : jamais sans affichage ; pendant les tests, seulement si
## le scénario l'autorise (test_window_at : position hors de tous les écrans,
## fenêtre sans focus : elle n'apparaît jamais à l'écran).
func can_detach() -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	return not _autotest() or test_window_at != Vector2i(-1, -1)


## Tests : position (hors écran) imposée à la fenêtre séparée.
var test_window_at := Vector2i(-1, -1)


func _autotest() -> bool:
	var at: Node = get_node_or_null("/root/Autotest")
	return at != null and at.active


func set_detached(on: bool, win_rect := Rect2i()) -> void:
	if on == detached:
		return
	if on and not can_detach():
		ed.set_status(Lang.t("Fenêtre séparée indisponible ici", "Separate window unavailable here"), true)
		return
	if on:
		if not maximized:
			_free_rect = Rect2(position, size)
		window = Window.new()
		window.visible = false
		window.name = "PreviewWindow"
		window.title = Lang.t("APERÇU 3D", "3D PREVIEW") + " — " + (ed.doc.display_name() if ed != null and ed.doc != null else "")
		window.force_native = true
		window.transient = false
		window.min_size = Vector2i(_min_size())
		window.theme = ed.theme if ed != null else null
		window.size = win_rect.size if win_rect.size.x > 0 else Vector2i(_free_rect.size.max(DEFAULT_SIZE))
		window.close_requested.connect(func(): set_detached(false))
		var bg := ColorRect.new()
		bg.color = Color(0.1, 0.1, 0.11)
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		window.add_child(bg)
		content.reparent(window, false)
		content.set_anchors_preset(Control.PRESET_FULL_RECT)
		content.offset_left = 3
		content.offset_top = 3
		content.offset_right = -3
		content.offset_bottom = -3
		if _autotest():
			# Tests : créée réduite (jamais affichée sur le bureau), sans focus.
			window.unfocusable = true
			window.mode = Window.MODE_MINIMIZED
			window.position = test_window_at
		elif win_rect.size.x > 0:
			window.position = win_rect.position
		else:
			window.position = get_window().position + Vector2i(get_global_rect().position)
		add_child(window)
		detached = true
		visible = false
		window.visible = shown
	else:
		detached = false
		if window != null:
			content.reparent(frame.get_node("Outer"), false)
			content.set_anchors_preset(Control.PRESET_TOP_LEFT)
			window.queue_free()
			window = null
		visible = shown
		_apply_rect(_free_rect if not maximized else Rect2(Vector2.ZERO, _area_size()))
	_save_soon()


func _area_size() -> Vector2:
	var p := get_parent() as Control
	return p.size if p != null else get_viewport_rect().size


func _apply_rect(r: Rect2) -> void:
	position = r.position
	size = r.size.max(_min_size())
	_clamp_rect()


## Le panneau reste dans l'éditeur (sa barre de titre toujours atteignable).
func _clamp_rect() -> void:
	if detached:
		return
	var area := _area_size()
	if maximized:
		position = Vector2.ZERO
		size = area
		return
	size = size.min(area).max(_min_size())
	# Jamais sur la barre du haut de l'éditeur (sa hauteur suit la taille de l'interface).
	var top := minf(_top_limit(), maxf(area.y - 30.0, 0.0))
	position = position.clamp(Vector2(-size.x + 80, top), (area - Vector2(80, 30)).max(Vector2(0, top)))


## Haut de la vue 2D dans l'éditeur (sous la barre du haut) ; 0 sans éditeur.
func _top_limit() -> float:
	if ed != null and ed.canvas != null and ed.canvas.is_inside_tree() and ed.canvas.size.x > 0.0:
		return ed.canvas.global_position.y - (get_parent() as Control).global_position.y if get_parent() is Control else ed.canvas.global_position.y
	return 0.0


func _default_rect() -> Rect2:
	var area := _area_size()
	var s := (DEFAULT_SIZE * EditorUi.factor()).round().min(area * 0.6)
	# En haut à droite de la vue 2D (à gauche des panneaux).
	var right := area.x - EditorUi.px(MapEditor.PANEL_W)
	var top := maxf(EditorUi.px(44.0), _top_limit() + 8.0)
	if ed != null and ed.canvas != null and ed.canvas.is_inside_tree() and ed.canvas.size.x > 0.0:
		right = ed.canvas.get_global_rect().end.x
	return Rect2(Vector2(right - s.x - 12, top), s)


## Plus petite taille du panneau, à la taille de l'interface (EditorUi).
func _min_size() -> Vector2:
	return (MIN_SIZE * EditorUi.factor()).round()


## Taille de l'interface changée (MapEditor.apply_ui_scale) : coin de
## redimensionnement, aide, panneau gardé dans l'éditeur.
func ui_scale_changed() -> void:
	var g := EditorUi.px(16.0)
	grip.offset_left = -g
	grip.offset_top = -g
	grip.queue_redraw()
	# Aide collée au bas de la vue (elle grandit vers le haut).
	hint.offset_top = -EditorUi.px(20.0)
	hint.offset_bottom = -EditorUi.px(4.0)
	info.position = Vector2(EditorUi.px(6.0), EditorUi.px(4.0))
	_clamp_rect.call_deferred()


func _title_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		if mb.double_click and mb.pressed:
			set_maximized(not maximized)
			_drag = ""
		elif mb.pressed and not maximized:
			_drag = "move"
			_drag_from = get_global_mouse_position()
			_rect0 = Rect2(position, size)
		elif not mb.pressed:
			if _drag != "":
				_save_soon()
			_drag = ""
	elif event is InputEventMouseMotion and _drag == "move":
		position = _rect0.position + get_global_mouse_position() - _drag_from
		_clamp_rect()


func _grip_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			if maximized:
				maximized = false
			_drag = "resize"
			_drag_from = get_global_mouse_position()
			_rect0 = Rect2(position, size)
		else:
			_drag = ""
			_save_soon()
	elif event is InputEventMouseMotion and _drag == "resize":
		size = (_rect0.size + get_global_mouse_position() - _drag_from).max(_min_size())
		_clamp_rect()


# ------------------------------------------------------------------ entrées de la vue

func _typing() -> bool:
	var f := get_viewport().gui_get_focus_owner()
	return f is LineEdit or f is TextEdit


func _in_view_px(local: Vector2) -> Vector2:
	# Pixel du rendu (SubViewport) sous un point de la vue.
	var vs := Vector2(world.viewport.size)
	return local / view.size.max(Vector2.ONE) * vs


func _view_input(event: InputEvent) -> void:
	var rig := world.rig
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					var steps := mb.factor if mb.factor > 0.0 else 1.0
					rig.zoom(steps if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -steps)
			MOUSE_BUTTON_RIGHT:
				_rmb = mb.pressed
				if mb.pressed:
					_capture(mb.position)
				else:
					_release_mouse()
			MOUSE_BUTTON_MIDDLE:
				_mmb = mb.pressed
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					view.grab_focus()
					_lmb_at = mb.position
					if mb.double_click:
						var id := world.pick(_in_view_px(mb.position))
						if id != "":
							_select(id)
							center_on_selection()
				elif _lmb_at.x >= 0.0 and mb.position.distance_to(_lmb_at) < 5.0:
					var id := world.pick(_in_view_px(mb.position))
					_select(id)
					_lmb_at = Vector2(-1, -1)
		view.accept_event()
		_request_render()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _rmb:
			rig.look(mm.relative)
		elif _mmb:
			rig.pan(mm.relative)
		if _rmb or _mmb:
			view.accept_event()


## Choisit un élément de l'éditeur depuis l'aperçu ("" : désélectionner).
func _select(id: String) -> void:
	if ed == null:
		return
	ed.select(id)
	if id != "":
		ed.set_status(Lang.t("Aperçu 3D : %s choisi", "3D preview: %s selected") % ed._label(ed.doc.find(id)))


func _capture(at: Vector2) -> void:
	_capture_at = at
	var au: Node = get_node_or_null("/root/Autotest")
	if au != null and au.active:
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _release_mouse() -> void:
	_rmb = false
	_mmb = false
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if view != null and view.is_inside_tree():
			view.warp_mouse(_capture_at)


## Les touches de déplacement vont à l'aperçu quand la souris est dessus (ou
## pendant qu'on regarde au clic droit).
func nav_active() -> bool:
	return is_on_screen() and (_mouse_in_view or _rmb) and not _typing()


func _view_key(event: InputEvent) -> void:
	if not event is InputEventKey or (ed != null and ed.options_open()):
		return
	var k := event as InputEventKey
	# P dans la fenêtre détachée (celle de l'éditeur : _input).
	if detached and k.pressed and not k.echo and k.keycode == KEY_P and not k.ctrl_pressed and not k.alt_pressed and not _typing():
		set_shown(false)
		view.get_viewport().set_input_as_handled()
		return
	if nav_active() and not k.ctrl_pressed and (k.is_action("jump") or k.keycode == KEY_SPACE):
		# Espace : monter / sauter (pas le déplacement de la vue 2D).
		view.get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if not event is InputEventKey or (ed != null and ed.options_open()):
		return
	var k := event as InputEventKey
	if k.pressed and not k.echo and k.keycode == KEY_P and not k.ctrl_pressed and not k.alt_pressed and not k.meta_pressed and not _typing():
		toggle()
		get_viewport().set_input_as_handled()


func _read_keys() -> void:
	var rig := world.rig
	if not nav_active():
		rig.move = Vector2.ZERO
		rig.rise = 0.0
		rig.sprint = false
		rig.jump = false
		return
	rig.move = Vector2(Input.get_axis("move_left", "move_right"), Input.get_axis("move_back", "move_forward"))
	rig.sprint = Input.is_action_pressed("sprint")
	rig.jump = Input.is_action_pressed("jump")
	rig.rise = (1.0 if Input.is_action_pressed("jump") else 0.0) - (1.0 if Input.is_action_pressed("crouch") else 0.0)


# ------------------------------------------------------------------ caméra et 2D

func center_on_selection() -> void:
	if ed == null:
		return
	var e := ed.doc.find(ed.selected)
	if e.is_empty():
		ed.set_status(Lang.t("Choisissez d'abord un élément", "Pick an element first"))
		return
	var f := world.element_focus(e)
	if not f.is_empty():
		world.rig.focus(f[0], f[1])
		_refresh_menu()
		_refresh_hint()
		_request_render()


## Clic sur la carte 2D : Ctrl + double-clic y place la caméra (les clics
## avec Ctrl ne posent rien quand l'aperçu est ouvert). Vrai si consommé.
func canvas_click(mb: InputEventMouseButton, m: Vector2) -> bool:
	if not is_on_screen() or mb.button_index != MOUSE_BUTTON_LEFT or not mb.ctrl_pressed:
		return false
	if mb.pressed and mb.double_click:
		place_camera(m)
	return true


## Place la caméra au point `m` (m, éditeur) de l'étage affiché.
func place_camera(m: Vector2) -> void:
	var sol := ed.doc.floor_sol(ed.floor_k) if ed != null else 0.0
	world.rig.place_at(Vector3(m.x + OFF, sol, m.y + OFF))
	ed.set_status(Lang.t("Aperçu 3D : caméra placée en x %.1f m, y %.1f m", "3D preview: camera moved to x %.1f m, y %.1f m") % [m.x, m.y])
	_request_render()


## Repère de la caméra de l'aperçu sur la vue 2D : point, champ de vision et
## direction (estompé si la caméra est à un autre étage).
func draw_on_canvas(cv: MapCanvas) -> void:
	if not is_on_screen() or world.rig.cam == null:
		return
	var eye := world.rig.eye()
	var m := Vector2(eye.x - OFF, eye.z - OFF)
	var f := world.rig.forward()
	var d := Vector2(f.x, f.z)
	d = d.normalized() if d.length() > 0.01 else Vector2.UP
	var here := world.floor_of_y(eye.y - 0.3) == ed.floor_k or world.rig.mode == MapPreviewCamera.Mode.ORBIT
	var col := Color(COL_CAM, 1.0 if here else 0.4)
	var c := cv.to_px(m)
	var half := deg_to_rad(35.0)
	var l := 34.0
	var wedge := PackedVector2Array([c, c + d.rotated(-half) * l, c + d.rotated(half) * l])
	cv.draw_colored_polygon(wedge, Color(col, 0.18 * col.a))
	cv.draw_line(c, c + d.rotated(-half) * l, col, 1.5)
	cv.draw_line(c, c + d.rotated(half) * l, col, 1.5)
	cv.draw_line(c, c + d * (l + 8.0), col, 2.0)
	cv.draw_circle(c, 5.0, col)
	cv.draw_circle(c, 5.0, Color.BLACK, false, 1.0)
	if world.rig.mode == MapPreviewCamera.Mode.ORBIT:
		var pv := cv.to_px(Vector2(world.rig.pivot.x - OFF, world.rig.pivot.z - OFF))
		cv.draw_line(pv - Vector2(6, 0), pv + Vector2(6, 0), col, 1.5)
		cv.draw_line(pv - Vector2(0, 6), pv + Vector2(0, 6), col, 1.5)
		cv.draw_dashed_line(c, pv, Color(col, 0.5), 1.0, 4.0)


# ------------------------------------------------------------------ boucle

func _process(delta: float) -> void:
	if ed == null:
		return
	world.doc = ed.doc
	if _save_t > 0.0:
		_save_t -= delta
		if _save_t <= 0.0:
			save_prefs()
	if not shown:
		world.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	if not detached:
		_clamp_rect()
	world.set_view_floor(ed.floor_k)
	_update_hover()
	world.selected_id = ed.selected
	world.update_overlay()
	_read_keys()
	if follow and ed.canvas != null:
		var c := ed.canvas.to_m(ed.canvas.size * 0.5)
		world.rig.follow(Vector3(c.x + OFF, ed.doc.floor_sol(ed.floor_k), c.y + OFF), delta)
	var moved := world.rig.take_moved()
	if moved and ed.canvas != null:
		ed.canvas.queue_redraw()
	_update_info()
	# Rendu : taille, pause sans focus, cadence.
	if pause_unfocused and not _app_focused():
		world.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	var want := Vector2i((view.size * render_scale).round()).max(Vector2i(16, 16))
	if want != world.viewport.size:
		world.viewport.size = want
		moved = true
	_render_t -= delta
	if moved or _render_t <= 0.0 or world.building:
		_render_t = 1.0 / IDLE_FPS
		world.viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		renders += 1


func _request_render() -> void:
	_render_t = 0.0


func _app_focused() -> bool:
	if get_window().has_focus():
		return true
	return window != null and window.has_focus()


## Élément survolé dans la 2D (même sans la liste des objets ouverte).
func _update_hover() -> void:
	var cv := ed.canvas
	var hov := ed.hover_id
	if cv != null and cv.is_visible_in_tree():
		var mp := cv.get_global_mouse_position()
		var over_me := not detached and get_global_rect().has_point(mp)
		if cv.get_global_rect().has_point(mp) and not over_me:
			if cv.mouse_m != _hover_m:
				_hover_m = cv.mouse_m
				_hover_2d = String(ed.element_at(cv.mouse_m).get("id", ""))
			if _hover_2d != "":
				hov = _hover_2d
		else:
			_hover_m = Vector2(INF, INF)
			_hover_2d = ""
	world.hover_id = hov


func _update_info() -> void:
	var s := ""
	if world.building or world.is_stale():
		s = Lang.t("Mise à jour…", "Updating…")
	elif world.data.is_empty():
		s = Lang.t("Dessinez une pièce : elle apparaîtra ici", "Draw a room: it will appear here")
	else:
		var sec := snappedf(world.last_times.total / 1000.0, 0.01)
		s = Lang.t("À jour (%s s)", "Up to date (%s s)") % (str(sec).replace(".", ",") if not Lang.is_en() else str(sec))
		if world.errors > 0:
			s += Lang.t(" · carte pas encore jouable : aperçu indicatif", " · map not playable yet: indicative preview")
	if s != _last_status:
		_last_status = s
		info.text = s


# ------------------------------------------------------------------ réglages mémorisés

func _save_soon() -> void:
	_save_t = 0.5


func state() -> Dictionary:
	var r := _free_rect if (maximized or detached) and _free_rect.size.x > 0.0 else Rect2(position, size)
	var d := {
		"visible": shown, "rect": [r.position.x, r.position.y, r.size.x, r.size.y], "max": maximized,
		"detached": detached, "camera": int(world.rig.mode), "follow": follow, "power": world.power_on,
		"full": world.full_light, "ceil": world.hide_ceilings, "floors": int(world.floors_mode),
		"scale": render_scale, "pause": pause_unfocused,
	}
	if window != null:
		d["window"] = [window.position.x, window.position.y, window.size.x, window.size.y]
	return d


func save_prefs() -> void:
	_save_t = -1.0
	MapEditor.set_pref(PREF_KEY, state())


func _load_prefs() -> void:
	var p: Dictionary = MapEditor.pref(PREF_KEY, {})
	apply_state(p)


## Réglages relus (valeurs invalides ignorées).
func apply_state(p: Dictionary) -> void:
	var r: Array = p.get("rect", []) if p.get("rect") is Array else []
	_free_rect = _default_rect()
	if r.size() == 4 and r.all(func(v): return v is float or v is int):
		_free_rect = Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
	world.set_options({
		"power": bool(p.get("power", true)), "full": bool(p.get("full", false)), "ceil": bool(p.get("ceil", false)),
		"floors": clampi(int(p.get("floors", 0)), 0, 2)})
	var sc := float(p.get("scale", 0.75)) if (p.get("scale") is float or p.get("scale") is int) else 0.75
	render_scale = clampf(sc, 0.25, 1.0)
	pause_unfocused = bool(p.get("pause", true))
	follow = bool(p.get("follow", false))
	# La vue joueur a besoin de la carte construite : on repart en orbite.
	var cm := clampi(int(p.get("camera", 0)), 0, 2)
	world.rig.set_mode(cm as MapPreviewCamera.Mode if cm != MapPreviewCamera.Mode.WALK else MapPreviewCamera.Mode.ORBIT)
	maximized = false
	_apply_rect(_free_rect)
	if bool(p.get("max", false)):
		set_maximized(true)
	_refresh_menu()
	_refresh_hint()
	if bool(p.get("detached", false)) and can_detach():
		var w: Array = p.get("window", []) if p.get("window") is Array else []
		var wr := Rect2i()
		if w.size() == 4 and w.all(func(v): return v is float or v is int):
			wr = Rect2i(int(w[0]), int(w[1]), clampi(int(w[2]), int(MIN_SIZE.x), 8192), clampi(int(w[3]), int(MIN_SIZE.y), 8192))
			# Écran débranché depuis : position par défaut.
			var seen := false
			for i in DisplayServer.get_screen_count():
				if DisplayServer.screen_get_usable_rect(i).intersects(wr):
					seen = true
			if not seen:
				wr = Rect2i()
		set_detached(true, wr)
	set_shown(bool(p.get("visible", false)))
	_save_t = -1.0
