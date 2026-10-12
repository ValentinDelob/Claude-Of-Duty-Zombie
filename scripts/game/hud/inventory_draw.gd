class_name InventoryDraw
extends RefCounted
## Éléments dessinés de l'inventaire de partie
## (docs/hub_v2/InventaireJeu.dc.html) : voile radial sur la partie, en-tête
## (INVENTAIRE, ferraille, « LA PARTIE CONTINUE · MANCHE N »), titres de
## section, en-tête de la fiche (rareté · famille, nom, NIV., « Comparé à »),
## lignes des pièces de la fiche. Valeurs de la maquette (px à 100 %) passées
## par Hub2Style.px / fs.

const TAG_BG := Color(1.0, 107 / 255.0, 87 / 255.0, 0.12)
const TAG_LINE := Color(1.0, 107 / 255.0, 87 / 255.0, 0.5)
const TAG_TEXT := Color("FF8A78")
const TAG_DOT := Color("FF6B57")
const SCRAP_DIAMOND := Color("C9C7BE")

const VEIL_SHADER := """
shader_type canvas_item;
// radial-gradient(ellipse at 50% 55%, rgba(8,9,11,.55), rgba(8,9,11,.85)) :
// ellipse « farthest-corner » aux proportions de « closest-side » (CSS).
// Station de construction (Station.dc.html) : .6 -> .88.
uniform vec2 rect_size = vec2(1280.0, 720.0);
uniform float alpha_in = 0.55;
uniform float alpha_out = 0.85;
void fragment() {
	vec2 p = UV * rect_size;
	vec2 c = vec2(0.5, 0.55) * rect_size;
	vec2 cs = min(c, rect_size - c);
	vec2 fc = max(c, rect_size - c);
	float ratio = cs.x / max(cs.y, 1.0);
	float rx0 = fc.x / ratio;
	float ry = sqrt(rx0 * rx0 + fc.y * fc.y);
	vec2 d = (p - c) / vec2(ratio * ry, ry);
	float t = clamp(length(d), 0.0, 1.0);
	COLOR = vec4(8.0 / 255.0, 9.0 / 255.0, 11.0 / 255.0, mix(alpha_in, alpha_out, t));
}
"""


## Voile plein cadre sur la partie (opacité au centre et au bord : .55 / .85
## pour l'inventaire, .6 / .88 pour la station).
class Veil extends ColorRect:
	var _mat: ShaderMaterial

	func _init(a_in := 0.55, a_out := 0.85) -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)
		var sh := Shader.new()
		sh.code = VEIL_SHADER
		_mat = ShaderMaterial.new()
		_mat.shader = sh
		_mat.set_shader_parameter("alpha_in", a_in)
		_mat.set_shader_parameter("alpha_out", a_out)
		material = _mat
		resized.connect(func(): _mat.set_shader_parameter("rect_size", size))

	func _draw() -> void:
		_mat.set_shader_parameter("rect_size", size)


## En-tête : h1 INVENTAIRE (Chakra 30 700 0,1em), pastille de ferraille,
## espace, étiquette rouge « LA PARTIE CONTINUE · MANCHE N » ; écart 24 px,
## align-items: center.
class Header extends Control:
	var title := ""
	var scrap := ""
	var scrap_word := ""
	var tag := ""

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_texts(t: String, s: String, sw: String, tg: String) -> void:
		title = t
		scrap = s
		scrap_word = sw
		tag = tg
		custom_minimum_size = Vector2(0, ceilf(_h()))
		queue_redraw()

	func _chip_h() -> float:
		var inner := maxf(Hub2ArsenalDraw.line_h(Hub2Style.MONO, 700, 16), Hub2ArsenalDraw.line_h(Hub2Style.BARLOW, 400, 13))
		return inner + Hub2Style.px(12) + Hub2Style.px(2)

	func _tag_h() -> float:
		return Hub2ArsenalDraw.line_h(Hub2Style.CHAKRA, 700, 12) + Hub2Style.px(12) + Hub2Style.px(2)

	func _h() -> float:
		return maxf(Hub2ArsenalDraw.line_h(Hub2Style.CHAKRA, 700, 30), maxf(_chip_h(), _tag_h()))

	func _draw() -> void:
		var h := size.y
		var lh := Hub2ArsenalDraw.line_h(Hub2Style.CHAKRA, 700, 30)
		var x := 0.0
		x += Hub2ArsenalDraw.text(self, title, Hub2Style.CHAKRA, 700, 30, Hub2Style.TEXT, 0.1, 0.0,
				Hub2ArsenalDraw.baseline(Hub2Style.CHAKRA, 700, 30, (h - lh) * 0.5, lh))
		x += Hub2Style.px(24)
		# Pastille de ferraille : padding 6px 12px, gap 8px, liseré 1 px.
		var mono := Hub2Style.font(Hub2Style.MONO, 700)
		var bar := Hub2Style.font(Hub2Style.BARLOW, 400)
		var nw := Hub2Style.text_width(scrap, mono, Hub2Style.fs(16))
		var ww := Hub2Style.text_width(scrap_word, bar, Hub2Style.fs(13))
		var ch := _chip_h()
		var cw := Hub2Style.px(1) + Hub2Style.px(12) + Hub2Style.px(8) + Hub2Style.px(8) + nw + Hub2Style.px(8) + ww + Hub2Style.px(12) + Hub2Style.px(1)
		var cr := Rect2(roundf(x), roundf((h - ch) * 0.5), ceilf(cw), roundf(ch))
		draw_rect(cr, Hub2Style.GLASS)
		draw_rect(cr.grow(-0.5), Hub2Style.LINE, false, 1.0)
		var cx := cr.position.x + Hub2Style.px(13)
		var cy := cr.position.y + Hub2Style.px(7)
		var ih := ch - Hub2Style.px(14)
		Hub2ArsenalDraw.draw_diamond(self, Vector2(cx + Hub2Style.px(4), cy + ih * 0.5), Hub2Style.px(8), SCRAP_DIAMOND)
		cx += Hub2Style.px(16)
		Hub2ArsenalDraw.text(self, scrap, Hub2Style.MONO, 700, 16, Hub2Style.TEXT, 0.0, cx,
				Hub2ArsenalDraw.baseline(Hub2Style.MONO, 700, 16, cy, ih))
		cx += nw + Hub2Style.px(8)
		Hub2ArsenalDraw.text(self, scrap_word, Hub2Style.BARLOW, 400, 13, Hub2Style.text_a(0.6), 0.0, cx,
				Hub2ArsenalDraw.baseline(Hub2Style.BARLOW, 400, 13, cy, ih))
		# Étiquette « LA PARTIE CONTINUE », à droite (aucune : station).
		if tag == "":
			return
		var tf := Hub2Style.font(Hub2Style.CHAKRA, 700)
		var ts := Hub2Style.fs(12)
		var tw := Hub2Style.text_width(tag, tf, ts, Hub2Style.tracking_px(0.14, ts))
		var th := _tag_h()
		var w := Hub2Style.px(1) + Hub2Style.px(12) + Hub2Style.px(8) + Hub2Style.px(8) + tw + Hub2Style.px(12) + Hub2Style.px(1)
		var tr := Rect2(roundf(size.x - w), roundf((h - th) * 0.5), ceilf(w), roundf(th))
		draw_rect(tr, TAG_BG)
		draw_rect(tr.grow(-0.5), TAG_LINE, false, 1.0)
		var tx := tr.position.x + Hub2Style.px(13)
		var ty := tr.position.y + Hub2Style.px(7)
		var tih := th - Hub2Style.px(14)
		draw_circle(Vector2(tx + Hub2Style.px(4), ty + tih * 0.5), Hub2Style.px(4), TAG_DOT, true, -1.0, true)
		tx += Hub2Style.px(16)
		Hub2ArsenalDraw.text(self, tag, Hub2Style.CHAKRA, 700, 12, TAG_TEXT, 0.14, tx,
				Hub2ArsenalDraw.baseline(Hub2Style.CHAKRA, 700, 12, ty, tih))


## Titre de section : h2 (Chakra 16 700 0,16em) et sous-titre (Barlow 13,
## rgba(242, 240, 234, 0.55)) sur la même ligne de base, écart 12 px.
class SectionHead extends Control:
	var title := ""
	var sub := ""

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_texts(t: String, s: String) -> void:
		title = t
		sub = s
		custom_minimum_size = Vector2(0, ceilf(_lh()))
		queue_redraw()

	func _lh() -> float:
		return maxf(Hub2ArsenalDraw.line_h(Hub2Style.CHAKRA, 700, 16), Hub2ArsenalDraw.line_h(Hub2Style.BARLOW, 400, 13))

	func _draw() -> void:
		var base := Hub2ArsenalDraw.baseline(Hub2Style.CHAKRA, 700, 16, 0.0, Hub2ArsenalDraw.line_h(Hub2Style.CHAKRA, 700, 16))
		var w := Hub2ArsenalDraw.text(self, title, Hub2Style.CHAKRA, 700, 16, Hub2Style.TEXT, 0.16, 0.0, base)
		var x := w + Hub2Style.px(12)
		var f := Hub2Style.font(Hub2Style.BARLOW, 400)
		var shown := Hub2Prompts.ellipsis(sub, f, Hub2Style.fs(13), maxf(size.x - x, 0.0))
		Hub2ArsenalDraw.text(self, shown, Hub2Style.BARLOW, 400, 13, Hub2Style.text_a(0.55), 0.0, x, base)


## En-tête de la fiche : liseré haut 3 px de la rareté, padding 18 18 14,
## « RARETÉ · FAMILLE » (Chakra 12 700 0,14em), nom (Chakra 30 700,
## line-height 1) et NIV. (JetBrains Mono 13) sur la même ligne de base à
## 4 px, « Comparé à X (en main) » (Barlow 13) à 8 px.
class DetailHead extends Control:
	var color := Hub2Style.TEXT
	var kicker := ""
	var title := ""
	var level := ""
	var level_color := Hub2Style.text_a(0.7)
	## [avant, nom, après] ; vide : pas de comparaison.
	var compare: Array = []
	## padding-bottom (px de la maquette) : 14 (inventaire), 10 (station).
	var pad_bottom := 14.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_data(col: Color, k: String, t: String, lvl: String, lvl_col: Color, cmp: Array) -> void:
		color = col
		kicker = k
		title = t
		level = lvl
		level_color = lvl_col
		compare = cmp
		custom_minimum_size = Vector2(0, ceilf(_h()))
		update_minimum_size()
		queue_redraw()

	## Ligne de « RARETÉ · FAMILLE » : un <span> dans un bloc en Barlow 16 px
	## (police de la fiche), dont la ligne (strut) compte aussi, comme dans le
	## navigateur : [hauteur, ligne de base depuis le haut].
	func _kicker_box() -> Vector2:
		var mb := Hub2ArsenalDraw.css_metrics(Hub2Style.BARLOW, 400)
		var mc := Hub2ArsenalDraw.css_metrics(Hub2Style.CHAKRA, 700)
		var s16 := float(Hub2Style.fs(16))
		var s12 := float(Hub2Style.fs(12))
		var asc := maxf(mb.x * s16, mc.x * s12)
		var desc := maxf(mb.y * s16, mc.y * s12)
		return Vector2(asc + desc, asc)

	func _h() -> float:
		var h := Hub2Style.px(3) + Hub2Style.px(18) + _kicker_box().x + Hub2Style.px(4) \
			+ Hub2Style.px(30) + Hub2Style.px(pad_bottom)
		if not compare.is_empty():
			h += Hub2Style.px(8) + Hub2ArsenalDraw.line_h(Hub2Style.BARLOW, 400, 13)
		return h

	func _draw() -> void:
		draw_rect(Rect2(0, 0, size.x, Hub2Style.px(3)), color)
		var x := Hub2Style.px(18)
		var w := size.x - x * 2.0
		var y := Hub2Style.px(3) + Hub2Style.px(18)
		var kb := _kicker_box()
		Hub2ArsenalDraw.text(self, kicker, Hub2Style.CHAKRA, 700, 12, color, 0.14, x, y + kb.y)
		y += kb.x + Hub2Style.px(4)
		var nh := Hub2Style.px(30)
		var base := Hub2ArsenalDraw.baseline(Hub2Style.CHAKRA, 700, 30, y, nh)
		var lw := Hub2Style.text_width(level, Hub2Style.font(Hub2Style.MONO, 500), Hub2Style.fs(13))
		var f := Hub2Style.font(Hub2Style.CHAKRA, 700)
		var sz := 30.0
		while sz > 18.0 and Hub2Style.text_width(title, f, Hub2Style.fs(sz)) > w - lw - Hub2Style.px(8):
			sz -= 1.0
		Hub2ArsenalDraw.text(self, title, Hub2Style.CHAKRA, 700, sz, Hub2Style.TEXT, 0.0, x, base)
		Hub2ArsenalDraw.text(self, level, Hub2Style.MONO, 500, 13, level_color, 0.0, x, base, w, HORIZONTAL_ALIGNMENT_RIGHT)
		y += nh
		if compare.size() == 3:
			y += Hub2Style.px(8)
			var ch := Hub2ArsenalDraw.line_h(Hub2Style.BARLOW, 400, 13)
			var cb := Hub2ArsenalDraw.baseline(Hub2Style.BARLOW, 400, 13, y, ch)
			var cx := x
			cx += Hub2ArsenalDraw.text(self, String(compare[0]), Hub2Style.BARLOW, 400, 13, Hub2Style.text_a(0.65), 0.0, cx, cb)
			cx += Hub2ArsenalDraw.text(self, String(compare[1]), Hub2Style.BARLOW, 600, 13, Hub2Style.TEXT, 0.0, cx, cb)
			Hub2ArsenalDraw.text(self, String(compare[2]), Hub2Style.BARLOW, 400, 13, Hub2Style.text_a(0.65), 0.0, cx, cb)


## Ligne d'une pièce de la fiche : pièce montée (fond rgba(255,255,255,.05),
## padding 8 12, nom Chakra 14 700, effet Barlow 12 turquoise) ou
## « Emplacement libre » (liseré 1 px en pointillés rgba(255,255,255,.18)).
class PartRow extends Control:
	var title := ""
	## [[texte, bénéfique], …]
	var effects: Array = []
	var filled := false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_data(t: String, fx: Array, full: bool) -> void:
		title = t
		effects = fx
		filled = full
		var inner := maxf(Hub2ArsenalDraw.line_h(Hub2Style.CHAKRA, 700, 14), Hub2ArsenalDraw.line_h(Hub2Style.BARLOW, 400, 12))
		custom_minimum_size = Vector2(0, ceilf(inner + Hub2Style.px(16) + (0.0 if full else Hub2Style.px(2))))
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var b := 0.0
		if filled:
			draw_rect(r, Hub2Style.white_a(0.05))
		else:
			b = Hub2Style.px(1)
			Hub2ArsenalDraw.draw_dashed_rect(self, r, Hub2Style.white_a(0.18), maxf(b, 1.0))
		var x := b + Hub2Style.px(12)
		var w := size.x - x * 2.0
		var nh := Hub2ArsenalDraw.line_h(Hub2Style.CHAKRA, 700, 14)
		Hub2ArsenalDraw.text(self, title, Hub2Style.CHAKRA, 700, 14, Hub2Style.TEXT if filled else Hub2Style.text_a(0.5), 0.0, x,
				Hub2ArsenalDraw.baseline(Hub2Style.CHAKRA, 700, 14, (size.y - nh) * 0.5, nh))
		if effects.is_empty():
			return
		var mh := Hub2ArsenalDraw.line_h(Hub2Style.BARLOW, 400, 12)
		var mb := Hub2ArsenalDraw.baseline(Hub2Style.BARLOW, 400, 12, (size.y - mh) * 0.5, mh)
		InventoryDraw.draw_effects(self, effects, 12, x, mb, w, HORIZONTAL_ALIGNMENT_RIGHT)


## Effets d'une pièce (« +8 % dégâts · −4 % recul »), chacun de sa couleur
## (#4FE3C1 bénéfique, #FF6B57 nuisible), Barlow `size` px ; rend la largeur.
static func effects_width(effects: Array, size: float) -> float:
	var f := Hub2Style.font(Hub2Style.BARLOW, 400)
	var s := Hub2Style.fs(size)
	var w := 0.0
	for i in effects.size():
		if i > 0:
			w += Hub2Style.text_width(" · ", f, s)
		w += Hub2Style.text_width(String(effects[i][0]), f, s)
	return w


static func draw_effects(ci: CanvasItem, effects: Array, size: float, x: float, base: float, w := -1.0,
		align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var tw := effects_width(effects, size)
	var px := x
	if w >= 0.0 and align == HORIZONTAL_ALIGNMENT_RIGHT:
		px = x + w - tw
	for i in effects.size():
		if i > 0:
			px += Hub2ArsenalDraw.text(ci, " · ", Hub2Style.BARLOW, 400, size, Hub2Style.text_a(0.4), 0.0, px, base)
		var col: Color = Hub2ArsenalView.GOOD if effects[i][1] else Hub2ArsenalView.HARMFUL
		px += Hub2ArsenalDraw.text(ci, String(effects[i][0]), Hub2Style.BARLOW, 400, size, col, 0.0, px, base)
