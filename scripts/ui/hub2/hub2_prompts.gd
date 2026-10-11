class_name Hub2Prompts
extends Control
## Barre d'invites du hub v2 (Prompts.dc.html) : 48 px, dégradé
## rgba(8, 9, 11, 0.8) en bas -> transparent en haut, padding 0 28 px.
## À gauche le texte d'aide (Barlow 15 px, rgba(242, 240, 234, 0.72), coupé
## avec « … »), à droite les invites (écart 24 px) : touche (Hub2Keycap) puis
## libellé (Chakra Petch 14 px 600, letter-spacing 0.1em, #F2F0EA) à 8 px.
##
## Les touches suivent le périphérique utilisé en dernier
## (Settings.input_device_changed, Hub2Input). Chaque invite se clique : elle
## émet `prompt_clicked(id)`, comme sa touche.

const H := 48.0
const GAP_ITEMS := 24.0
const GAP_KEY := 8.0
const HELP_SIZE := 15.0
const LABEL_SIZE := 14.0
const LABEL_TRACKING := 0.1

## Invites : [{id, text, keys: PackedStringArray, pads: Array}].
var items: Array = []
var help := "":
	set(v):
		help = v
		queue_redraw()

signal prompt_clicked(id: String)

var _hit: Array = []  # [Rect2, id]
var _grad: GradientTexture2D


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	var g := Gradient.new()
	g.set_color(0, Hub2Style.shade(0.8))
	g.set_color(1, Hub2Style.shade(0.0))
	_grad = GradientTexture2D.new()
	_grad.gradient = g
	# linear-gradient(to top, …) : de bas (0.8) en haut (0).
	_grad.fill_from = Vector2(0, 1)
	_grad.fill_to = Vector2(0, 0)
	_grad.width = 4
	_grad.height = 64


func _ready() -> void:
	custom_minimum_size = Vector2(0, Hub2Style.px(H))
	Settings.input_device_changed.connect(_on_device)


func _exit_tree() -> void:
	if Settings.input_device_changed.is_connected(_on_device):
		Settings.input_device_changed.disconnect(_on_device)


func _on_device(_pad: bool) -> void:
	queue_redraw()


## Remplace les invites : `list` = [[identifiant, texte], …] ou
## [[identifiant, texte, touches_clavier, boutons_manette], …] pour une
## action propre à l'écran (sinon Hub2Input.keys_of / pads_of).
func set_items(list: Array) -> void:
	items.clear()
	for it in list:
		if not (it is Array and it.size() >= 2):
			continue
		var id := String(it[0])
		var keys: PackedStringArray = PackedStringArray(it[2]) if it.size() > 2 else Hub2Input.keys_of(id)
		var pads: Array = it[3] if it.size() > 3 else Hub2Input.pads_of(id)
		items.append({"id": id, "text": String(it[1]).to_upper(), "keys": keys, "pads": pads})
	queue_redraw()


## Textes affichés (tests) : « A CHOISIR », « LB RB ONGLETS »…
func describe() -> PackedStringArray:
	var out := PackedStringArray()
	for it in items:
		out.append(Hub2Input.keycap_text(it.keys, it.pads, Settings.using_pad) + " " + String(it.text))
	return out


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_texture_rect(_grad, r, false)
	_hit.clear()
	var pad := Settings.using_pad
	var side := Hub2Style.px(Hub2Style.SIDE)
	var lf := Hub2Style.font(Hub2Style.CHAKRA, 600)
	var ls := Hub2Style.fs(LABEL_SIZE)
	var lt := Hub2Style.tracking_px(LABEL_TRACKING, ls)
	var kh := Hub2Style.px(Hub2Keycap.H)
	var ky := roundf((r.size.y - kh) * 0.5)
	# Largeur des invites (à droite), puis dessin de droite à gauche.
	var widths: Array = []
	var total := 0.0
	for it in items:
		var kt := Hub2Input.keycap_text(it.keys, it.pads, pad)
		var kw := Hub2Style.px(Hub2Keycap.MIN_W) if Hub2Input.ps_symbol(it.pads, pad) >= 0 else Hub2Keycap.width_for(kt)
		var w := kw + Hub2Style.px(GAP_KEY) + Hub2Style.text_width(it.text, lf, ls, lt)
		widths.append([kt, kw, w])
		total += w
	if items.size() > 1:
		total += Hub2Style.px(GAP_ITEMS) * (items.size() - 1)
	var x := r.size.x - side - total
	var right_start := x
	for i in items.size():
		var it: Dictionary = items[i]
		var kt: String = widths[i][0]
		var kw: float = widths[i][1]
		var x0 := x
		Hub2Keycap.draw_keycap(self, Rect2(x, ky, kw, kh), kt, Hub2Input.ps_symbol(it.pads, pad))
		x += kw + Hub2Style.px(GAP_KEY)
		Hub2Style.draw_text(self, lf, Vector2(x, Hub2Style.baseline(lf, ls, 0.0, r.size.y)), it.text, ls, Hub2Style.TEXT, lt)
		x = x0 + float(widths[i][2])
		_hit.append([Rect2(x0, 0, x - x0, r.size.y), it.id])
		x += Hub2Style.px(GAP_ITEMS)
	# Aide : à gauche, coupée avant les invites (gap: 24px).
	if help != "":
		var hf := Hub2Style.font(Hub2Style.BARLOW, 400)
		var hs := Hub2Style.fs(HELP_SIZE)
		var room := right_start - Hub2Style.px(GAP_ITEMS) - side
		if room > Hub2Style.px(20):
			var shown := ellipsis(help, hf, hs, room)
			draw_string(hf, Vector2(side, Hub2Style.baseline(hf, hs, 0.0, r.size.y)), shown,
					HORIZONTAL_ALIGNMENT_LEFT, -1, hs, Hub2Style.text_a(0.72))


## Texte coupé avec « … » pour tenir dans `w` (text-overflow: ellipsis).
static func ellipsis(t: String, f: Font, s: int, w: float) -> String:
	if f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, s).x <= w:
		return t
	var n := t.length()
	while n > 0 and f.get_string_size(t.left(n) + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, s).x > w:
		n -= 1
	return t.left(n) + "…"


func _gui_input(event: InputEvent) -> void:
	var mm := event as InputEventMouseMotion
	if mm:
		var over := false
		for h in _hit:
			if (h[0] as Rect2).has_point(mm.position):
				over = true
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if over else Control.CURSOR_ARROW
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		for h in _hit:
			if (h[0] as Rect2).has_point(mb.position):
				accept_event()
				prompt_clicked.emit(String(h[1]))
				return
