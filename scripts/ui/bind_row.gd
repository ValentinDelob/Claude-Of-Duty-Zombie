class_name MenuBindRow
extends Control
## Ligne de réaffectation d'une action (OPTIONS > COMMANDES) : libellé à
## gauche, deux cases à droite : la touche (clavier / souris) puis le bouton
## de manette (une seule commande par action et par périphérique).
## Clavier / manette : ◄ / ► choisissent la case, Entrée (A / Croix) la
## réaffecte, Retour arrière, Suppr ou X / Carré la vide. Souris : clic sur
## une case. La saisie de la nouvelle commande est faite par l'écran
## d'options (signal rebind_requested).
## `header` : ligne de titres des deux colonnes (ni focus ni saisie).

signal rebind_requested(row: MenuBindRow, slot: int)
signal clear_requested(row: MenuBindRow, slot: int)

const HEIGHT := 34.0
const SLOT_W := 180.0
const SLOT_GAP := 12.0
## Cases : touche, puis manette.
const SLOT_KEY := 0
const SLOT_PAD := 1
const SLOTS := 2

var action := ""
var label_text := ""
var header := false
## Case sélectionnée (SLOT_KEY ou SLOT_PAD).
var slot := 0
## Case en attente d'une commande (-1 : aucune).
var capturing := -1

var _focus_t := 0.0
var _flash := 0.0
var _blink := 0.0


static func make(action_name: String, label: String) -> MenuBindRow:
	var r := MenuBindRow.new()
	r.action = action_name
	r.label_text = label
	return r


## Titres des colonnes, au-dessus des lignes.
static func make_header() -> MenuBindRow:
	var r := MenuBindRow.new()
	r.header = true
	return r


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS  # molette : défilement de la page
	custom_minimum_size = Vector2(MenuOptionRow.VALUE_X + SLOT_W * SLOTS + SLOT_GAP + 20.0, HEIGHT * (0.7 if header else 1.0))
	if header:
		focus_mode = Control.FOCUS_NONE
		Settings.input_device_changed.connect(_on_device_changed)
		return
	focus_mode = Control.FOCUS_ALL
	mouse_entered.connect(func(): grab_focus())
	mouse_exited.connect(queue_redraw)
	focus_entered.connect(func():
		Audio.play_ui(MenuStyle.SND_MOVE, MenuStyle.VOL_MOVE)
		set_process(true))
	focus_exited.connect(func(): set_process(true))
	Settings.bindings_changed.connect(queue_redraw)
	# Noms Xbox ou PlayStation selon la manette utilisée.
	Settings.input_device_changed.connect(_on_device_changed)


## Éclat bref (commande changée, ou retirée par un conflit).
func flash() -> void:
	_flash = 1.0
	set_process(true)


func set_capturing(s: int) -> void:
	capturing = s
	_blink = 0.0
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	var target := 1.0 if has_focus() else 0.0
	_focus_t = move_toward(_focus_t, target, delta * (7.0 if target > _focus_t else 4.0))
	_flash = maxf(_flash - delta * 2.5, 0.0)
	_blink += delta
	queue_redraw()
	if _focus_t == target and _flash == 0.0 and capturing < 0:
		set_process(false)


func _gui_input(event: InputEvent) -> void:
	if capturing >= 0 or header:
		return
	if event.is_action_pressed("ui_left", true):
		_select(SLOT_KEY)
		accept_event()
	elif event.is_action_pressed("ui_right", true):
		_select(SLOT_PAD)
		accept_event()
	elif event.is_action_pressed("ui_accept"):
		rebind_requested.emit(self, slot)
		accept_event()
	elif (event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode in [KEY_BACKSPACE, KEY_DELETE]) \
			or (event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_X):
		clear_requested.emit(self, slot)
		accept_event()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		grab_focus()
		var s := slot_at(event.position.x)
		if s >= 0:
			_select(s)
		rebind_requested.emit(self, slot)
		accept_event()
	elif event is InputEventMouseMotion:
		var s := slot_at(event.position.x)
		if s >= 0 and s != slot:
			_select(s, false)


func _select(s: int, sound := true) -> void:
	s = clampi(s, 0, SLOTS - 1)
	if s != slot and sound:
		Audio.play_ui(MenuStyle.SND_MOVE, MenuStyle.VOL_MOVE + 2.0)
	slot = s
	queue_redraw()


## Case sous l'abscisse `x` (-1 : libellé).
func slot_at(x: float) -> int:
	for i in SLOTS:
		var r := slot_rect(i)
		if x >= r.position.x - SLOT_GAP * 0.5 and x <= r.end.x + SLOT_GAP * 0.5:
			return i
	return -1


func slot_rect(i: int) -> Rect2:
	return Rect2(MenuOptionRow.VALUE_X + i * (SLOT_W + SLOT_GAP), 3.0, SLOT_W, HEIGHT - 6.0)


## Code de la case `i` (« » : vide).
func code(i: int) -> String:
	return Settings.binding(action, i == SLOT_PAD)


func _draw() -> void:
	var h := size.y
	if header:
		var hf := UiStyle.font("impact")
		for i in SLOTS:
			var hr := slot_rect(i)
			var t := Lang.t("CLAVIER / SOURIS", "KEYBOARD / MOUSE") if i == SLOT_KEY else Lang.t("MANETTE", "CONTROLLER")
			draw_string(hf, Vector2(hr.position.x, h - 6.0), t, HORIZONTAL_ALIGNMENT_CENTER, hr.size.x, 16, MenuStyle.DIM_TEXT)
		return
	var f := _focus_t
	if f > 0.001:
		MenuStyle.draw_highlight(self, Rect2(0, 2, size.x * (0.35 + 0.65 * f), h - 4), f)
	var font := UiStyle.font("impact")
	var col := MenuStyle.IDLE.lerp(MenuStyle.FOCUS_TEXT, f)
	var fs := 21
	var base_y := h * 0.5 + fs * 0.36
	draw_string_outline(font, Vector2(16 + 10 * f, base_y), label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(0, 0, 0, 0.85))
	draw_string(font, Vector2(16 + 10 * f, base_y), label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	if capturing >= 0:
		# Une seule grande case clignotante : « APPUYEZ SUR UNE TOUCHE… ».
		var r := Rect2(slot_rect(0).position, Vector2(SLOT_W * SLOTS + SLOT_GAP, HEIGHT - 6.0))
		var pulse := 0.5 + 0.5 * cos(_blink * 7.0)
		draw_rect(r, Color(0.12, 0.02, 0.02, 0.9))
		draw_rect(r, MenuStyle.HOVER.lerp(Color(1, 0.6, 0.5), pulse), false, 2.0)
		var t := Lang.t("APPUYEZ SUR UN BOUTON DE LA MANETTE…", "PRESS A CONTROLLER BUTTON…") if capturing == SLOT_PAD \
				else Lang.t("APPUYEZ SUR UNE TOUCHE…", "PRESS A KEY…")
		draw_string(font, Vector2(r.position.x, base_y), t, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 20,
				UiStyle.BONE.lerp(Color(1, 0.8, 0.7), pulse))
		return
	var style := Settings.pad_style()
	for i in SLOTS:
		var r := slot_rect(i)
		var sel := f > 0.5 and i == slot
		var bg := Color(0.04, 0.03, 0.03, 0.8) if not sel else Color(0.14, 0.03, 0.02, 0.9)
		draw_rect(r, bg)
		var border := Color(0.3, 0.07, 0.05, 0.9).lerp(MenuStyle.HOVER, 1.0 if sel else 0.0)
		draw_rect(r, border, false, 2.0 if sel else 1.0)
		var c := code(i)
		@warning_ignore("static_called_on_instance")
		var t := Settings.code_label(c, style) if c != "" else "—"
		var tc := UiStyle.BONE if c != "" else MenuStyle.DIM_TEXT
		tc = tc.lerp(Color(1, 0.55, 0.45), _flash)
		draw_string(UiStyle.font("mono"), Vector2(r.position.x + 6, base_y - 1), t, HORIZONTAL_ALIGNMENT_CENTER,
				r.size.x - 12, 18, tc)


func _on_device_changed(_pad: bool) -> void:
	queue_redraw()
