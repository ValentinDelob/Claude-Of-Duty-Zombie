class_name HubButton
extends Button
## Bouton du hub (classe .btn de la maquette) : pavé métal à contour noir,
## biseau, ombre pleine de 3 px, texte Impact. Variantes : principal (jaune),
## danger (rouge), grisé (désactivé), grand (.big). Focus : cadre jaune de
## 3 px (.focus). Garde l'API de Button (pressed, disabled, grab_focus…).
## `hint` s'affiche dans la barre d'invites quand il a le focus.

const NORMAL := "normal"
const PRIMARY := "pri"
const DANGER := "danger"

const LOOKS := {
	NORMAL: [Color("3D4042"), Color("5C5957"), Color("26282A"), Color("DBD6C2")],
	PRIMARY: [Color("E0B31F"), Color("F2CC45"), Color("A8840F"), Color("1A1405")],
	DANGER: [Color("7A1A14"), Color("A8342A"), Color("4A0D0A"), Color("FFE2DA")],
}
const OFF := [Color("2A2C2E"), Color("333538"), Color(0, 0, 0, 0), Color("5F5C55")]

var label := "":
	set(v):
		label = v
		_resize()
var kind := NORMAL:
	set(v):
		kind = v
		queue_redraw()
var big := false:
	set(v):
		big = v
		_resize()
## Taille du texte à 100 % (0 : 15, ou 20 pour un grand bouton).
var font_size := 0:
	set(v):
		font_size = v
		_resize()
## Hauteur à 100 % (0 : 34, ou 46 pour un grand bouton).
var height := 0:
	set(v):
		height = v
		_resize()
var hint := ""
## Largeur minimale à 100 % (0 : celle du texte).
var min_width := 0.0:
	set(v):
		min_width = v
		_resize()
var _down := false


static func make(t: String, cb: Callable, k := NORMAL, h := "") -> HubButton:
	var b := HubButton.new()
	b.label = t
	b.kind = k
	b.hint = h
	b.pressed.connect(func():
		Audio.play_ui(MenuStyle.SND_SELECT, MenuStyle.VOL_SELECT)
		cb.call())
	return b


func _ready() -> void:
	text = ""
	flat = true
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var empty := StyleBoxEmpty.new()
	for s in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		add_theme_stylebox_override(s, empty)
	mouse_entered.connect(func():
		if not disabled and focus_mode != Control.FOCUS_NONE:
			grab_focus())
	focus_entered.connect(func():
		Audio.play_ui(MenuStyle.SND_MOVE, MenuStyle.VOL_MOVE)
		queue_redraw())
	focus_exited.connect(queue_redraw)
	button_down.connect(func():
		_down = true
		queue_redraw())
	button_up.connect(func():
		_down = false
		queue_redraw())
	_resize()


func _fsize() -> int:
	return HubStyle.fs(font_size if font_size > 0 else (20 if big else 15))


func _font() -> Font:
	var s := _fsize()
	return HubStyle.font("impact", HubStyle.em(0.05, s))


func _resize() -> void:
	var h := HubStyle.px(height if height > 0 else (46 if big else 34))
	var padx := HubStyle.px(22 if big else 14)
	var w := HubStyle.text_width(label, _font(), _fsize()) + padx * 2.0 + HubStyle.px(2) * 2.0
	custom_minimum_size = Vector2(maxf(ceilf(w), HubStyle.px(min_width)), h)
	queue_redraw()


func _draw() -> void:
	var look: Array = OFF if disabled else LOOKS.get(kind, LOOKS[NORMAL])
	var r := Rect2(Vector2.ZERO, size)
	var press := HubStyle.px(1) if _down and not disabled else 0.0
	r.position += Vector2(press, press)
	HubStyle.draw_box(self, r, look[0], HubStyle.px(2), HubStyle.px(3) - press, look[1], look[2], HubStyle.px(2))
	var f := _font()
	var s := _fsize()
	var tw := HubStyle.text_width(label, f, s)
	var x := r.position.x + maxf((r.size.x - tw) * 0.5, HubStyle.px(4))
	draw_string(f, Vector2(x, HubStyle.baseline(f, s, r.position.y, r.size.y)), label, HORIZONTAL_ALIGNMENT_LEFT,
			r.size.x - HubStyle.px(8), s, look[3])
	if has_focus():
		HubStyle.draw_focus(self, Rect2(Vector2.ZERO, size))
