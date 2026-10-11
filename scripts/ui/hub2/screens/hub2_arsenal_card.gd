class_name Hub2ArsenalCard
extends Hub2Button
## Carte d'une arme (ou d'une pièce) du rail de l'ARSENAL du hub v2
## (docs/hub_v2/Arsenal.dc.html, `w.cardStyle`) :
##   padding 10 12 10 15, liseré 1 px rgba(255,255,255,.07), fond
##   rgba(255,255,255,.04) ; choisie : fond rgba(245,197,66,.12), liseré
##   #F5C542 ; verrouillée (niveau trop haut) : opacité 0,5 ;
##   ligne de rareté de 3 px à gauche ; rendu de l'arme (50 px de haut,
##   margin -2 -4 0 -2, contain, drop-shadow 0 4 6 rgba(0,0,0,.5)) avec
##   l'étiquette NEUF (fond jaune) ou BASE en haut à droite ; nom Chakra Petch
##   17 px 700 0,04em (coupé « … ») ; rareté Chakra Petch 12 px 700 0,1em à
##   gauche, à droite les emplacements (carrés 6 px, écart 3 : turquoise =
##   pièce installée) puis le score JetBrains Mono 13 px 700 (écart 8), ou
##   « NIV. N REQUIS » (Chakra Petch 11 px 700 0,08em #FF7A5C).
## Pièce : pixel art de la pièce à la place du rendu, qualité à la place de
## la rareté, une ligne de plus avec les effets (vert / rouge).
## La carte ne dessine pas de cadre de focus : la sélection (jaune) suit le
## focus dans le rail.
## ◄ ► ▲ ▼ sont rendus au panneau (`nav`), qui gère le rail par niveau.

signal nav(dir: Vector2i)

const PAD := Vector4(15, 10, 12, 10)  # gauche, haut, droite, bas
const IMG_H := 50.0
const GAP := 5.0

## Données affichées : {name, color, kind_name, img: Texture2D, part_art: bool,
## is_new, base, locked, required, slots, filled, score, effects: [[texte, bon]]}.
var data: Dictionary = {}
## Identifiant de l'objet (uid de l'arme ou de la pièce).
var key := ""
var level := 0
var selected := false:
	set(v):
		selected = v
		_style()
## Dernier appui venu de la souris (clic : choisir ; A / Entrée : ouvrir).
var pressed_by_mouse := false

var face: Control


func _init() -> void:
	super()
	show_focus = false
	face = Control.new()
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.draw.connect(_draw_face)
	add_content(face)


func setup(d: Dictionary) -> void:
	data = d
	modulate.a = 0.5 if d.get("locked", false) else 1.0
	_update_height()
	_style()
	face.queue_redraw()


func _ready() -> void:
	resized.connect(_update_height)


## Hauteur selon la largeur (« NIV. N REQUIS » sur deux lignes si besoin).
func _update_height() -> void:
	var extra: float = 0.0
	if data.get("locked", false) and size.x > 0.0:
		var inner := size.x - Hub2Style.px(1) * 2.0 - Hub2Style.px(PAD.x) - Hub2Style.px(PAD.z)
		extra = maxf(float(_req_layout(inner).h) - _row_h(), 0.0)
	var h := roundf(card_height(data.get("effects", []).size() > 0 or data.get("part_art", false)) + extra)
	if not is_equal_approx(custom_minimum_size.y, h):
		custom_minimum_size = Vector2(0, h)
	face.queue_redraw()


static func _row_h() -> float:
	return maxf(Hub2ArsenalDraw.line_h(Hub2Style.CHAKRA, 700, 12), Hub2ArsenalDraw.line_h(Hub2Style.MONO, 700, 13))


## Lignes de « NIV. N REQUIS » dans la place laissée par la rareté (largeur
## intérieure `inner`) : {lines, w (plus longue ligne), h (hauteur de la rangée)}.
func _req_layout(inner: float) -> Dictionary:
	var f := Hub2Style.font(Hub2Style.CHAKRA, 700)
	var s11 := Hub2Style.fs(11)
	var tr11 := Hub2Style.tracking_px(0.08, s11)
	var s12 := Hub2Style.fs(12)
	var kind_w := Hub2Style.text_width(String(data.get("kind_name", "")), f, s12, Hub2Style.tracking_px(0.1, s12))
	var room := inner - kind_w
	var words := String(data.get("required", "")).split(" ", false)
	var lines: Array[String] = []
	var cur := ""
	for wd in words:
		var cand := wd if cur == "" else cur + " " + wd
		if cur != "" and Hub2Style.text_width(cand, f, s11, tr11) > room:
			lines.append(cur)
			cur = wd
		else:
			cur = cand
	if cur != "":
		lines.append(cur)
	var w := 0.0
	for ln in lines:
		w = maxf(w, Hub2Style.text_width(ln, f, s11, tr11))
	var h := maxf(_row_h(), Hub2ArsenalDraw.line_h(Hub2Style.CHAKRA, 700, 11) * lines.size())
	return {"lines": lines, "w": w, "h": h}


## Hauteur d'une carte (px à l'échelle) ; `extra_line` : ligne des effets
## (carte de pièce). Hauteurs de ligne du navigateur (non arrondies).
static func card_height(extra_line := false) -> float:
	var name_h := Hub2ArsenalDraw.line_h(Hub2Style.CHAKRA, 700, 17)
	var h := Hub2Style.px(1) + Hub2Style.px(PAD.y) - Hub2Style.px(2) + Hub2Style.px(IMG_H) + Hub2Style.px(GAP) + name_h \
			+ Hub2Style.px(GAP) + _row_h() + Hub2Style.px(PAD.w) + Hub2Style.px(1)
	if extra_line:
		h += Hub2Style.px(GAP) + Hub2ArsenalDraw.line_h(Hub2Style.BARLOW, 400, 13)
	return h


func _style() -> void:
	if selected:
		box.flat(Hub2Style.yellow_a(0.12), Hub2Style.YELLOW, 1.0)
	else:
		box.flat(Hub2Style.white_a(0.04), Hub2Style.white_a(0.07), 1.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		pressed_by_mouse = true
	elif event.is_action_pressed("ui_accept"):
		pressed_by_mouse = false
	for pair in [["ui_left", Vector2i(-1, 0)], ["ui_right", Vector2i(1, 0)], ["ui_up", Vector2i(0, -1)], ["ui_down", Vector2i(0, 1)]]:
		if event.is_action_pressed(String(pair[0]), true):
			accept_event()
			nav.emit(pair[1])
			return


func _draw_face() -> void:
	if data.is_empty():
		return
	var ci := face
	# Le contenu de la boîte commence au bord (pas de padding sur le box) :
	# les positions sont celles de la carte.
	var w := ci.size.x
	var b := Hub2Style.px(1)
	var col: Color = data.get("color", Hub2Style.TEXT)
	# Ligne de rareté (position absolue dans la boîte de padding : sous le
	# liseré).
	ci.draw_rect(Rect2(b, b, Hub2Style.px(3), ci.size.y - b * 2.0), col)
	var left := b + Hub2Style.px(PAD.x)
	var right := w - b - Hub2Style.px(PAD.z)
	# Image : margin -2 -4 0 -2.
	var img := Rect2(left - Hub2Style.px(2), b + Hub2Style.px(PAD.y) - Hub2Style.px(2),
			right + Hub2Style.px(4) - (left - Hub2Style.px(2)), Hub2Style.px(IMG_H))
	if data.get("part_art", false):
		Hub2ArsenalDraw.draw_part_art(ci, img, maxf(roundf(Hub2Style.px(4.5)), 2.0))
	else:
		Hub2ArsenalDraw.draw_render(ci, data.get("img"), img, Hub2Style.px(4), Hub2Style.px(6), 0.5)
	if data.get("is_new", false):
		_tag_new(ci, img)
	elif data.get("base", false):
		var lh := Hub2ArsenalDraw.line_h(Hub2Style.CHAKRA, 700, 10)
		var tw := Hub2Style.text_width("BASE", Hub2Style.font(Hub2Style.CHAKRA, 700), Hub2Style.fs(10),
				Hub2Style.tracking_px(0.14, Hub2Style.fs(10)))
		Hub2ArsenalDraw.text(ci, "BASE", Hub2Style.CHAKRA, 700, 10, Hub2Style.text_a(0.55), 0.14,
				img.end.x - Hub2Style.px(2) - tw, Hub2ArsenalDraw.baseline(Hub2Style.CHAKRA, 700, 10, img.position.y + Hub2Style.px(2), lh))
	# Nom.
	var y := img.end.y + Hub2Style.px(GAP)
	var name_h := Hub2ArsenalDraw.line_h(Hub2Style.CHAKRA, 700, 17)
	Hub2ArsenalDraw.text(ci, String(data.get("name", "")), Hub2Style.CHAKRA, 700, 17, Hub2Style.TEXT, 0.04, left,
			Hub2ArsenalDraw.baseline(Hub2Style.CHAKRA, 700, 17, y, name_h), right - left)
	y += name_h + Hub2Style.px(GAP)
	# Rareté (ou qualité) et emplacements / score, ou NIV. N REQUIS.
	var row_h := maxf(Hub2ArsenalDraw.line_h(Hub2Style.CHAKRA, 700, 12), Hub2ArsenalDraw.line_h(Hub2Style.MONO, 700, 13))
	var rx := right
	if data.get("locked", false):
		# « NIV. N REQUIS » : la rareté garde toute sa largeur, le texte prend
		# le reste et passe à la ligne aux espaces (flex de la maquette).
		var lay := _req_layout(right - left)
		row_h = lay.h
		var lh11 := Hub2ArsenalDraw.line_h(Hub2Style.CHAKRA, 700, 11)
		var ty := y + (row_h - lh11 * (lay.lines as Array).size()) * 0.5
		rx = right - float(lay.w)
		for ln: String in lay.lines:
			Hub2ArsenalDraw.text(ci, ln, Hub2Style.CHAKRA, 700, 11, Hub2Style.BAD, 0.08, rx,
					roundf(Hub2ArsenalDraw.baseline(Hub2Style.CHAKRA, 700, 11, ty, lh11)))
			ty += lh11
	else:
		var score := String(data.get("score", ""))
		var sw := Hub2Style.text_width(score, Hub2Style.font(Hub2Style.MONO, 700), Hub2Style.fs(13))
		rx = right - sw
		Hub2ArsenalDraw.text(ci, score, Hub2Style.MONO, 700, 13, Hub2Style.TEXT, 0.0, rx,
				Hub2ArsenalDraw.baseline(Hub2Style.MONO, 700, 13, y, row_h))
		var n := int(data.get("slots", 0))
		if n > 0:
			var s := Hub2Style.px(6)
			var g := Hub2Style.px(3)
			var dots_w := n * s + (n - 1) * g
			var x0 := rx - Hub2Style.px(8) - dots_w
			var dy := y + roundf((row_h - s) * 0.5)
			for i in n:
				ci.draw_rect(Rect2(x0 + i * (s + g), dy, s, s),
						Hub2Style.TEAL if i < int(data.get("filled", 0)) else Hub2Style.white_a(0.18))
			rx = x0
	Hub2ArsenalDraw.text(ci, String(data.get("kind_name", "")), Hub2Style.CHAKRA, 700, 12, col, 0.1, left,
			roundf(Hub2ArsenalDraw.baseline(Hub2Style.CHAKRA, 700, 12, y, row_h)), maxf(rx - left, 0.0))
	# Effets d'une pièce.
	var eff: Array = data.get("effects", [])
	if not eff.is_empty():
		y += row_h + Hub2Style.px(GAP)
		var lh2 := Hub2ArsenalDraw.line_h(Hub2Style.BARLOW, 400, 13)
		Hub2ArsenalModLine.draw_effects(ci, eff, left, Hub2ArsenalDraw.baseline(Hub2Style.BARLOW, 400, 13, y, lh2),
				right - left, 13)


## Étiquette NEUF : top 2, right 2 de l'image ; padding 1 5, fond jaune,
## Chakra Petch 10 px 700 0,12em #0B0B0C.
func _tag_new(ci: Control, img: Rect2) -> void:
	var t := Lang.t("NEUF", "NEW")
	var f := Hub2Style.font(Hub2Style.CHAKRA, 700)
	var s := Hub2Style.fs(10)
	var tr := Hub2Style.tracking_px(0.12, s)
	var lh := Hub2ArsenalDraw.line_h(Hub2Style.CHAKRA, 700, 10)
	var r := Rect2(0, 0, Hub2Style.text_width(t, f, s, tr) + Hub2Style.px(10), lh + Hub2Style.px(2))
	r.position = Vector2(img.end.x - Hub2Style.px(2) - r.size.x, img.position.y + Hub2Style.px(2))
	r = Rect2(r.position.round(), r.size.round())
	ci.draw_rect(r, Hub2Style.YELLOW)
	Hub2Style.draw_text(ci, f, Vector2(r.position.x + Hub2Style.px(5),
			roundf(Hub2ArsenalDraw.baseline(Hub2Style.CHAKRA, 700, 10, r.position.y + Hub2Style.px(1), lh))), t, s, Hub2Style.INK, tr)
