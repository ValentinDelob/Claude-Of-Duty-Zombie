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
##   17 px 700 0,04em ; rareté Chakra Petch 12 px 700 0,1em à gauche, à
##   droite les emplacements (carrés 6 px, écart 3 : turquoise = pièce
##   installée) puis le score JetBrains Mono 13 px 700 (écart 8), ou
##   « NIV. N REQUIS » (Chakra Petch 11 px 700 0,08em #FF7A5C).
## AUCUN TEXTE COUPÉ (pas de « … ») : un nom trop long rapetisse (17 px ->
## 13 px au plus petit) puis passe sur deux lignes ; si la rareté et les
## emplacements + score ne tiennent pas sur une ligne, les emplacements et
## le score passent sur la ligne suivante, à droite ; « NIV. N REQUIS » passe
## à la ligne aux espaces (comme le flex de la maquette), ou sous la rareté.
## La carte grandit d'autant (hauteur selon la largeur).
## Pièce : pixel art de la pièce à la place du rendu, qualité à la place de
## la rareté, puis ses effets (vert / rouge), un par ligne.
## La carte ne dessine pas de cadre de focus : la sélection (jaune) suit le
## focus dans le rail.
## ◄ ► ▲ ▼ sont rendus au panneau (`nav`), qui gère le rail par niveau.

signal nav(dir: Vector2i)

const PAD := Vector4(15, 10, 12, 10)  # gauche, haut, droite, bas
const IMG_H := 50.0
const GAP := 5.0
## Nom : taille de la maquette, puis plus petit au besoin (px à 100 %).
const NAME_SIZE := 17.0
const NAME_MIN := 13.0

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


## Largeur intérieure (sans liseré ni padding) d'une carte de largeur `w`.
static func inner_width(w: float) -> float:
	return w - Hub2Style.px(1) * 2.0 - Hub2Style.px(PAD.x) - Hub2Style.px(PAD.z)


## Hauteur selon la largeur (nom, rangée de la rareté).
func _update_height() -> void:
	var w := size.x if size.x > 0.0 else Hub2Style.px(135)
	var h := roundf(layout(inner_width(w)).height)
	if not is_equal_approx(custom_minimum_size.y, h):
		custom_minimum_size = Vector2(0, h)
	face.queue_redraw()


static func _f(weight := 700) -> Font:
	return Hub2Style.font(Hub2Style.CHAKRA, weight)


static func _w(t: String, size_css: float, track_em: float, family := Hub2Style.CHAKRA, weight := 700) -> float:
	var s := Hub2Style.fs(size_css)
	return Hub2Style.text_width(t, Hub2Style.font(family, weight), s, Hub2Style.tracking_px(track_em, s))


## Lignes de `t` en coupant aux espaces pour tenir dans `room` (un mot seul
## trop long reste entier).
static func wrap_words(t: String, size_css: float, track_em: float, room: float, family := Hub2Style.CHAKRA,
		weight := 700) -> Array[String]:
	var lines: Array[String] = []
	var cur := ""
	for wd in t.split(" ", false):
		var cand := wd if cur == "" else cur + " " + wd
		if cur != "" and _w(cand, size_css, track_em, family, weight) > room:
			lines.append(cur)
			cur = wd
		else:
			cur = cand
	if cur != "":
		lines.append(cur)
	return lines


## Nom : {size (px de la maquette), lines} — une ligne à la plus grande
## taille qui tient (17 -> 13), sinon deux lignes (ou plus) aux espaces.
static func fit_name(t: String, room: float) -> Dictionary:
	var s := NAME_SIZE
	while s >= NAME_MIN:
		if _w(t, s, 0.04) <= room:
			return {"size": s, "lines": [t]}
		s -= 0.5
	s = NAME_SIZE
	while s >= NAME_MIN:
		var lines := wrap_words(t, s, 0.04, room)
		var ok := true
		for ln in lines:
			ok = ok and _w(ln, s, 0.04) <= room
		if ok:
			return {"size": s, "lines": lines}
		s -= 0.5
	# Un mot plus large que la carte même à 13 px (REINFORCEMENT) : coupé
	# avec un trait d'union, jamais avec « … ».
	var out: Array[String] = []
	for ln in wrap_words(t, NAME_MIN, 0.04, room):
		var rest := ln
		while _w(rest, NAME_MIN, 0.04) > room and rest.length() > 2:
			var k := rest.length() - 1
			while k > 1 and _w(rest.left(k) + "-", NAME_MIN, 0.04) > room:
				k -= 1
			out.append(rest.left(k) + "-")
			rest = rest.substr(k)
		out.append(rest)
	return {"size": NAME_MIN, "lines": out}


static func _row_h() -> float:
	return maxf(Hub2ArsenalDraw.line_h(Hub2Style.CHAKRA, 700, 12), Hub2ArsenalDraw.line_h(Hub2Style.MONO, 700, 13))


## Largeur des emplacements + score (écart 8).
func _right_w() -> float:
	var n := int(data.get("slots", 0))
	var w := _w(String(data.get("score", "")), 13, 0.0, Hub2Style.MONO, 700)
	if n > 0:
		w += Hub2Style.px(8) + n * Hub2Style.px(6) + (n - 1) * Hub2Style.px(3)
	return w


## Mise en page pour une largeur intérieure `inner` :
## {name: fit_name, row_split (emplacements / score sous la rareté),
##  req_lines, req_below (« NIV. N REQUIS » sous la rareté), req_w,
##  row_h, effects_h, height}.
func layout(inner: float) -> Dictionary:
	var nm := fit_name(String(data.get("name", "")), inner)
	var name_h := Hub2ArsenalDraw.line_h(Hub2Style.CHAKRA, 700, float(nm.size)) * (nm.lines as Array).size()
	var kind_w := _w(String(data.get("kind_name", "")), 12, 0.1)
	var rh := _row_h()
	var out := {"name": nm, "row_split": false, "req_lines": [], "req_below": false, "req_w": 0.0}
	var row_total := rh
	if data.get("locked", false):
		var lh11 := Hub2ArsenalDraw.line_h(Hub2Style.CHAKRA, 700, 11)
		var req := String(data.get("required", ""))
		var room := inner - kind_w
		var lines := wrap_words(req, 11, 0.08, room)
		var widest := 0.0
		for ln in lines:
			widest = maxf(widest, _w(ln, 11, 0.08))
		if widest > room + 0.5:
			# Pas la place à côté de la rareté : en dessous, à droite.
			lines = wrap_words(req, 11, 0.08, inner)
			widest = 0.0
			for ln in lines:
				widest = maxf(widest, _w(ln, 11, 0.08))
			out.req_below = true
			row_total = rh + lh11 * lines.size()
		else:
			row_total = maxf(rh, lh11 * lines.size())
		out.req_lines = lines
		out.req_w = widest
	elif kind_w + _right_w() > inner + 0.5 and _right_w() > 0.0:
		out.row_split = true
		row_total = rh * 2.0
	out.row_h = row_total
	var eff_h := 0.0
	var eff: Array = data.get("effects", [])
	if not eff.is_empty():
		eff_h = Hub2Style.px(GAP) + Hub2ArsenalDraw.line_h(Hub2Style.BARLOW, 400, 13) * _effect_lines(inner).size()
	out.effects_h = eff_h
	out.height = Hub2Style.px(1) + Hub2Style.px(PAD.y) - Hub2Style.px(2) + Hub2Style.px(IMG_H) + Hub2Style.px(GAP) + name_h \
			+ Hub2Style.px(GAP) + row_total + eff_h + Hub2Style.px(PAD.w) + Hub2Style.px(1)
	return out


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
	var lay := layout(right - left)
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
		var tw := _w("BASE", 10, 0.14)
		Hub2ArsenalDraw.text(ci, "BASE", Hub2Style.CHAKRA, 700, 10, Hub2Style.text_a(0.55), 0.14,
				img.end.x - Hub2Style.px(2) - tw, roundf(Hub2ArsenalDraw.baseline(Hub2Style.CHAKRA, 700, 10, img.position.y + Hub2Style.px(2), lh)))
	# Nom (une ou deux lignes, taille ajustée).
	var y := img.end.y + Hub2Style.px(GAP)
	var ns: float = lay.name.size
	var name_h := Hub2ArsenalDraw.line_h(Hub2Style.CHAKRA, 700, ns)
	for ln: String in lay.name.lines:
		Hub2ArsenalDraw.text(ci, ln, Hub2Style.CHAKRA, 700, ns, Hub2Style.TEXT, 0.04, left,
				roundf(Hub2ArsenalDraw.baseline(Hub2Style.CHAKRA, 700, ns, y, name_h)))
		y += name_h
	y += Hub2Style.px(GAP)
	# Rareté (ou qualité) et emplacements / score, ou NIV. N REQUIS.
	var rh := _row_h()
	var row_h: float = lay.row_h
	var kind_y := y + ((row_h - rh) * 0.5 if not (lay.row_split or lay.req_below) else 0.0)
	Hub2ArsenalDraw.text(ci, String(data.get("kind_name", "")), Hub2Style.CHAKRA, 700, 12, col, 0.1, left,
			roundf(Hub2ArsenalDraw.baseline(Hub2Style.CHAKRA, 700, 12, kind_y, rh)))
	if data.get("locked", false):
		var lh11 := Hub2ArsenalDraw.line_h(Hub2Style.CHAKRA, 700, 11)
		var lines: Array = lay.req_lines
		var ty := y + rh if lay.req_below else y + (row_h - lh11 * lines.size()) * 0.5
		var rx := right - float(lay.req_w)
		for ln: String in lines:
			Hub2ArsenalDraw.text(ci, ln, Hub2Style.CHAKRA, 700, 11, Hub2Style.BAD, 0.08, rx,
					roundf(Hub2ArsenalDraw.baseline(Hub2Style.CHAKRA, 700, 11, ty, lh11)))
			ty += lh11
	else:
		var ry := y + rh if lay.row_split else y
		var score := String(data.get("score", ""))
		var sw := _w(score, 13, 0.0, Hub2Style.MONO, 700)
		var rx := right - sw
		Hub2ArsenalDraw.text(ci, score, Hub2Style.MONO, 700, 13, Hub2Style.TEXT, 0.0, rx,
				roundf(Hub2ArsenalDraw.baseline(Hub2Style.MONO, 700, 13, ry, rh)))
		var n := int(data.get("slots", 0))
		if n > 0:
			var s := Hub2Style.px(6)
			var g := Hub2Style.px(3)
			var x0 := rx - Hub2Style.px(8) - (n * s + (n - 1) * g)
			var dy := ry + roundf((rh - s) * 0.5)
			for i in n:
				ci.draw_rect(Rect2(x0 + i * (s + g), dy, s, s),
						Hub2Style.TEAL if i < int(data.get("filled", 0)) else Hub2Style.white_a(0.18))
	# Effets d'une pièce, un par ligne.
	var eff: Array = data.get("effects", [])
	if not eff.is_empty():
		y += row_h + Hub2Style.px(GAP)
		var lh2 := Hub2ArsenalDraw.line_h(Hub2Style.BARLOW, 400, 13)
		for it: Array in _effect_lines(right - left):
			Hub2ArsenalDraw.text(ci, String(it[0]), Hub2Style.BARLOW, 400, 13, it[1], 0.0, left,
					roundf(Hub2ArsenalDraw.baseline(Hub2Style.BARLOW, 400, 13, y, lh2)))
			y += lh2


## Effets d'une pièce, un par ligne, passés à la ligne aux espaces :
## [[texte, couleur], …].
func _effect_lines(inner: float) -> Array:
	var out := []
	for it: Array in data.get("effects", []):
		var col: Color = Hub2ArsenalView.GOOD if it[1] else Hub2ArsenalView.HARMFUL
		for ln in wrap_words(String(it[0]), 13, 0.0, inner, Hub2Style.BARLOW, 400):
			out.append([ln, col])
	return out


## Textes affichés par la carte (tests : jamais de « … »).
func shown_texts() -> Array[String]:
	var out: Array[String] = []
	var lay := layout(inner_width(size.x if size.x > 0.0 else Hub2Style.px(135)))
	for ln: String in lay.name.lines:
		out.append(ln)
	out.append(String(data.get("kind_name", "")))
	for ln: String in lay.req_lines:
		out.append(ln)
	return out


## Les textes tiennent-ils dans la carte (largeur intérieure) ?
func texts_fit() -> bool:
	var inner := inner_width(size.x if size.x > 0.0 else Hub2Style.px(135))
	var lay := layout(inner)
	for ln: String in lay.name.lines:
		if _w(ln, float(lay.name.size), 0.04) > inner + 0.5:
			return false
	var kind_w := _w(String(data.get("kind_name", "")), 12, 0.1)
	if kind_w > inner + 0.5:
		return false
	if not data.get("locked", false) and not lay.row_split and kind_w + _right_w() > inner + 0.5:
		return false
	if lay.row_split and _right_w() > inner + 0.5:
		return false
	for it: Array in _effect_lines(inner):
		if _w(String(it[0]), 13, 0.0, Hub2Style.BARLOW, 400) > inner + 0.5:
			return false
	return float(lay.req_w) <= inner + 0.5


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
