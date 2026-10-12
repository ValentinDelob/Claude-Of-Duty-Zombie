class_name StationDraw
extends RefCounted
## Éléments dessinés de la station de construction
## (docs/hub_v2/Station.dc.html) : effet de rareté animé derrière le rendu
## d'une arme, carte d'une arme du rail, tête de colonne « NIV. N », filet
## du rail, flèches ‹ ›, filtres CONSTRUCTIBLES / TOUTES, ligne de l'arme en
## main. Valeurs de la maquette (px à 100 %) passées par Hub2Style.px / fs.

## Effet de rareté (maquette : fxOf) : rien pour une commune ; halo pulsé
## (rarGlow) dès la rare, plus fort pour épique et au-delà ; rayons tournants
## (rarSpin) en plus pour légendaire et unique. Opacité du halo au centre
## par rareté (OwnedWeapon.Rarity).
const GLOW_ALPHA := [0.0, 0.45, 0.6, 0.75, 0.75]
const RAYS_FROM := 3
## Rayons (côté du carré, px de la maquette) : carte 120, fiche 220.
const RAYS_CARD := 120.0
const RAYS_SHEET := 220.0

## @keyframes rarGlow { 0%, 100% { opacity: .45; scale(.9) } 50% { opacity: .9;
## scale(1.08) } } 2,6 s ease-in-out ; @keyframes rarSpin 9 s linear.
## .rar-glow { inset: -6px 8% } : halo dépassant de 6 px en haut et en bas,
## rentré de 8 % à gauche et à droite ; radial-gradient(ellipse at center,
## couleur@a 0 %, transparent 70 %). .rar-rays : repeating-conic-gradient
## (couleur 55 0-10°, transparent 10-30°), masque radial (noir 20 %,
## transparent 70 %). Un seul quad par effet, animé par TIME : rien à
## mettre à jour depuis le script.
const FX_SHADER := """
shader_type canvas_item;
uniform vec2 rect_size = vec2(100.0, 40.0);
uniform vec4 tint : source_color = vec4(1.0);
uniform float glow_a = 0.0;
uniform float out_y = 6.0;
uniform float rays_px = 0.0;

// cubic-bezier(0.42, 0, 0.58, 1) (ease-in-out) : x(s) = t résolu par Newton.
float ease_io(float t) {
	float s = t;
	for (int i = 0; i < 5; i++) {
		float x = 3.0 * (1.0 - s) * (1.0 - s) * s * 0.42 + 3.0 * (1.0 - s) * s * s * 0.58 + s * s * s;
		float dx = 3.0 * (1.0 - s) * (1.0 - s) * 0.42 + 6.0 * (1.0 - s) * s * (0.58 - 0.42) + 3.0 * s * s * (1.0 - 0.58);
		s = clamp(s - (x - t) / max(dx, 1e-4), 0.0, 1.0);
	}
	return s * s * (3.0 - 2.0 * s);
}

void fragment() {
	vec2 p = UV * rect_size;
	vec2 c = rect_size * 0.5;
	vec2 q = p - c;
	float ra = 0.0;
	if (rays_px > 0.0) {
		float rot = TIME / 9.0 * 6.2831853;
		vec2 r = vec2(q.x * cos(rot) + q.y * sin(rot), -q.x * sin(rot) + q.y * cos(rot));
		float deg = mod(degrees(atan(r.x, -r.y)) + 360.0, 30.0);
		float inside = deg <= 10.0 ? min(deg, 10.0 - deg) : -min(deg - 10.0, 30.0 - deg);
		float len = length(q);
		float cov = clamp(radians(inside) * len + 0.5, 0.0, 1.0);
		float m = clamp(1.0 - (len / (rays_px * 0.70710678) - 0.2) / 0.5, 0.0, 1.0);
		ra = 0.3333 * cov * m;
	}
	float ga = 0.0;
	if (glow_a > 0.0) {
		float ph = mod(TIME, 2.6) / 2.6;
		float k = ph < 0.5 ? ease_io(ph * 2.0) : 1.0 - ease_io((ph - 0.5) * 2.0);
		float sc = mix(0.9, 1.08, k);
		float op = mix(0.45, 0.9, k);
		vec2 half_size = vec2(rect_size.x * 0.42, rect_size.y * 0.5 + out_y) * sc;
		vec2 d = q / (half_size * 1.41421356);
		float inbox = step(abs(q.x), half_size.x) * step(abs(q.y), half_size.y);
		ga = glow_a * clamp(1.0 - length(d) / 0.7, 0.0, 1.0) * op * inbox;
	}
	COLOR = vec4(tint.rgb, ga + ra * (1.0 - ga));
}
"""

static var _fx_shader: Shader


static func fx_shader() -> Shader:
	if _fx_shader == null:
		_fx_shader = Shader.new()
		_fx_shader.code = FX_SHADER
	return _fx_shader


## Effet visible pour cette rareté ?
static func has_fx(rarity: int) -> bool:
	return rarity >= 1


static func has_rays(rarity: int) -> bool:
	return rarity >= RAYS_FROM


## Effet de rareté : un rectangle (la boîte du rendu, overflow: hidden) au
## shader animé.
class RarityFx extends ColorRect:
	var rarity := 0
	var rays := RAYS_CARD
	var _mat: ShaderMaterial

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		color = Color.WHITE
		_mat = ShaderMaterial.new()
		_mat.shader = StationDraw.fx_shader()
		material = _mat
		resized.connect(_apply)

	func set_rarity(r: int, rays_css: float) -> void:
		rarity = r
		rays = rays_css
		_apply()

	func _apply() -> void:
		var on := StationDraw.has_fx(rarity)
		visible = on
		if not on:
			return
		_mat.set_shader_parameter("rect_size", size)
		_mat.set_shader_parameter("tint", Hub2Style.rarity_color(rarity))
		_mat.set_shader_parameter("glow_a", float(GLOW_ALPHA[clampi(rarity, 0, GLOW_ALPHA.size() - 1)]))
		_mat.set_shader_parameter("out_y", Hub2Style.px(6))
		_mat.set_shader_parameter("rays_px", Hub2Style.px(rays) if StationDraw.has_rays(rarity) else 0.0)


## Rendu d'une arme sur son effet de rareté : boîte (overflow: hidden), effet
## dessous, image en object-fit: contain avec drop-shadow(0 `dy` `blur`
## rgba(0,0,0,.6)) dessus.
class FxImage extends Control:
	var fx: RarityFx
	var img: Control
	var tex: Texture2D
	var shadow_dy := 4.0
	var shadow_blur := 6.0

	func _init(rays_css := RAYS_CARD) -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip_contents = true
		fx = RarityFx.new()
		fx.rays = rays_css
		fx.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(fx)
		img = Control.new()
		img.mouse_filter = Control.MOUSE_FILTER_IGNORE
		img.set_anchors_preset(Control.PRESET_FULL_RECT)
		img.draw.connect(_draw_img)
		add_child(img)

	func set_data(t: Texture2D, rarity: int) -> void:
		tex = t
		fx.set_rarity(rarity, fx.rays)
		img.queue_redraw()

	func _draw_img() -> void:
		Hub2ArsenalDraw.draw_render(img, tex, Rect2(Vector2.ZERO, img.size), Hub2Style.px(shadow_dy),
				Hub2Style.px(shadow_blur), 0.6)


## Carte d'une arme du rail (maquette : c.style) : flex column, gap 3,
## padding 8 10 8 13, liseré 1 px rgba(255,255,255,.07), fond
## rgba(255,255,255,.04) ; choisie : fond rgba(245,197,66,.12), liseré
## #F5C542 ; niveau trop haut : opacité 0,5. Ligne de rareté de 3 px à
## gauche ; rendu 40 px (effet de rareté, drop-shadow 0 4 6) ; nom Chakra
## Petch 14 700 ; rareté Chakra Petch 11 700 0,12em ; puis, sous un filet
## 1 px (padding-top 5), le prix (JetBrains Mono 13 700, #FF7A5C si trop cher
## ou niveau trop haut : « NIV. N REQUIS ») et la durée (Barlow 11, 60 %).
## Construction du joueur sur cette arme : la durée laisse place à
## « EN COURS » / « PRÊTE » (turquoise).
## La sélection (jaune) suit le focus ; ◄ ► ▲ ▼ sont rendus au panneau
## (`nav`).
class Card extends Hub2Button:
	signal nav(dir: Vector2i)

	const PAD := Vector4(13, 8, 10, 8)  # gauche, haut, droite, bas
	const IMG_H := 40.0
	const GAP := 3.0
	const NAME_SIZE := 14.0
	const NAME_MIN := 10.0

	## {name, color, rarity, rarity_name, img, locked, price, price_bad,
	##  rounds, rounds_color}
	var data: Dictionary = {}
	var uid := ""
	var level := 0
	var selected := false:
		set(v):
			selected = v
			_style()
	## Dernier appui venu de la souris (clic : choisir ; A / Entrée : construire).
	var pressed_by_mouse := false
	var face: Control
	var art: FxImage

	func _init() -> void:
		super()
		show_focus = false
		face = Control.new()
		face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		face.draw.connect(_draw_face)
		face.resized.connect(_place_art)
		add_content(face)
		art = FxImage.new(RAYS_CARD)
		face.add_child(art)
		resized.connect(_update_height)
		_style()

	func setup(d: Dictionary) -> void:
		data = d
		modulate.a = 0.5 if d.get("locked", false) else 1.0
		art.set_data(d.get("img"), int(d.get("rarity", 0)))
		_update_height()
		face.queue_redraw()

	static func _w(t: String, family: String, weight: int, size_css: float, track_em := 0.0) -> float:
		var s := Hub2Style.fs(size_css)
		return Hub2Style.text_width(t, Hub2Style.font(family, weight), s, Hub2Style.tracking_px(track_em, s))

	static func inner_width(w: float) -> float:
		return w - Hub2Style.px(1) * 2.0 - Hub2Style.px(PAD.x) - Hub2Style.px(PAD.z)

	## Mise en page pour une largeur intérieure `inner` : {name_size, price_lines,
	## row_h, height}. Rien n'est coupé : le nom rapetisse (14 -> 10 px) ; le
	## prix passe à la ligne aux espaces s'il ne tient pas à côté de la durée.
	func layout(inner: float) -> Dictionary:
		var nm := String(data.get("name", ""))
		var ns := NAME_SIZE
		while ns > NAME_MIN and _w(nm, Hub2Style.CHAKRA, 700, ns) > inner:
			ns -= 0.5
		var price := String(data.get("price", ""))
		var rounds := String(data.get("rounds", ""))
		var room := inner - _w(rounds, Hub2Style.BARLOW, 400, 11) - Hub2Style.px(6)
		var lines: Array[String] = [price]
		if _w(price, Hub2Style.MONO, 700, 13) > room:
			lines = Hub2ArsenalCard.wrap_words(price, 13, 0.0, maxf(room, Hub2Style.px(20)), Hub2Style.MONO, 700)
		var plh := Hub2ArsenalDraw.line_h(Hub2Style.MONO, 700, 13)
		var row_h := maxf(plh * lines.size(), Hub2ArsenalDraw.line_h(Hub2Style.BARLOW, 400, 11))
		var h := Hub2Style.px(1) + Hub2Style.px(PAD.y) + Hub2Style.px(IMG_H) + Hub2Style.px(GAP) \
				+ Hub2ArsenalDraw.line_h(Hub2Style.CHAKRA, 700, ns) + Hub2Style.px(GAP) \
				+ Hub2ArsenalDraw.line_h(Hub2Style.CHAKRA, 700, 11) + Hub2Style.px(GAP) \
				+ Hub2Style.px(1) + Hub2Style.px(5) + row_h + Hub2Style.px(PAD.w) + Hub2Style.px(1)
		return {"name_size": ns, "price_lines": lines, "row_h": row_h, "height": h}

	func _update_height() -> void:
		var w := size.x if size.x > 0.0 else Hub2Style.px(138)
		var h := roundf(float(layout(inner_width(w)).height))
		if not is_equal_approx(custom_minimum_size.y, h):
			custom_minimum_size = Vector2(0, h)
		face.queue_redraw()

	func _place_art() -> void:
		var b := Hub2Style.px(1)
		var left := b + Hub2Style.px(PAD.x)
		var right := face.size.x - b - Hub2Style.px(PAD.z)
		art.position = Vector2(left, b + Hub2Style.px(PAD.y))
		art.size = Vector2(maxf(right - left, 0.0), Hub2Style.px(IMG_H))

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
		var b := Hub2Style.px(1)
		var col: Color = data.get("color", Hub2Style.TEXT)
		ci.draw_rect(Rect2(b, b, Hub2Style.px(3), ci.size.y - b * 2.0), col)
		var left := b + Hub2Style.px(PAD.x)
		var right := ci.size.x - b - Hub2Style.px(PAD.z)
		var lay := layout(right - left)
		var y := b + Hub2Style.px(PAD.y) + Hub2Style.px(IMG_H) + Hub2Style.px(GAP)
		var ns: float = lay.name_size
		var nh := Hub2ArsenalDraw.line_h(Hub2Style.CHAKRA, 700, ns)
		Hub2ArsenalDraw.text(ci, String(data.get("name", "")), Hub2Style.CHAKRA, 700, ns, Hub2Style.TEXT, 0.0, left,
				roundf(Hub2ArsenalDraw.baseline(Hub2Style.CHAKRA, 700, ns, y, nh)))
		y += nh + Hub2Style.px(GAP)
		var rh := Hub2ArsenalDraw.line_h(Hub2Style.CHAKRA, 700, 11)
		Hub2ArsenalDraw.text(ci, String(data.get("rarity_name", "")), Hub2Style.CHAKRA, 700, 11, col, 0.12, left,
				roundf(Hub2ArsenalDraw.baseline(Hub2Style.CHAKRA, 700, 11, y, rh)))
		y += rh + Hub2Style.px(GAP)
		ci.draw_rect(Rect2(left, y, right - left, maxf(b, 1.0)), Hub2Style.LINE)
		y += b + Hub2Style.px(5)
		var row_h: float = lay.row_h
		var plh := Hub2ArsenalDraw.line_h(Hub2Style.MONO, 700, 13)
		var lines: Array = lay.price_lines
		var py := y + (row_h - plh * lines.size()) * 0.5
		var pc: Color = Hub2Style.BAD if data.get("price_bad", false) else Hub2Style.TEXT
		for ln: String in lines:
			Hub2ArsenalDraw.text(ci, ln, Hub2Style.MONO, 700, 13, pc, 0.0, left,
					roundf(Hub2ArsenalDraw.baseline(Hub2Style.MONO, 700, 13, py, plh)))
			py += plh
		Hub2ArsenalDraw.text(ci, String(data.get("rounds", "")), Hub2Style.BARLOW, 400, 11,
				data.get("rounds_color", Hub2Style.text_a(0.6)), 0.0, left,
				roundf(Hub2ArsenalDraw.baseline(Hub2Style.BARLOW, 400, 11, y, row_h)), right - left, HORIZONTAL_ALIGNMENT_RIGHT)

	## Les textes tiennent-ils dans la carte (tests) ?
	func texts_fit() -> bool:
		var inner := inner_width(size.x if size.x > 0.0 else Hub2Style.px(138))
		var lay := layout(inner)
		if _w(String(data.get("name", "")), Hub2Style.CHAKRA, 700, float(lay.name_size)) > inner + 0.5:
			return false
		if _w(String(data.get("rarity_name", "")), Hub2Style.CHAKRA, 700, 11, 0.12) > inner + 0.5:
			return false
		var rw := _w(String(data.get("rounds", "")), Hub2Style.BARLOW, 400, 11)
		for ln: String in lay.price_lines:
			if _w(ln, Hub2Style.MONO, 700, 13) + rw > inner + 0.5:
				return false
		return true


## Tête de colonne : « NIV. N » (Chakra Petch 15 px 700 0,06em ; jaune si
## choisie, 35 % au-dessus du niveau du joueur) et « ×n » (JetBrains Mono
## 11 px, 55 %) en bas d'une boîte de 36 px (+ padding-bottom 2), écart 6 ;
## losange de 8 px (jaune / 40 %) centré dans 12 px, puis 10 px vides.
class ColumnHead extends Control:
	const H := 60.0
	var level := 1
	var count := 1
	var on := false
	var over := false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _ready() -> void:
		custom_minimum_size.y = Hub2Style.px(36) + Hub2Style.px(2) + Hub2Style.px(12) + Hub2Style.px(10)

	func _draw() -> void:
		var f := Hub2Style.font(Hub2Style.CHAKRA, 700)
		var s := Hub2Style.fs(15)
		var tr := Hub2Style.tracking_px(0.06, s)
		var t := Hub2ArsenalView.level_text(level)
		var lw := Hub2Style.text_width(t, f, s, tr)
		var mf := Hub2Style.font(Hub2Style.MONO, 500)
		var ms := Hub2Style.fs(11)
		var ct := "×%d" % count
		var cw := Hub2Style.text_width(ct, mf, ms) if count > 1 else 0.0
		var gap := Hub2Style.px(6) if count > 1 else 0.0
		var x := roundf((size.x - lw - gap - cw) * 0.5)
		var lh := Hub2ArsenalDraw.line_h(Hub2Style.CHAKRA, 700, 15)
		var bottom := Hub2Style.px(36)
		var base := roundf(Hub2ArsenalDraw.baseline(Hub2Style.CHAKRA, 700, 15, bottom - lh, lh))
		var col := Hub2Style.YELLOW if on else (Hub2Style.text_a(0.35) if over else Hub2Style.TEXT)
		Hub2Style.draw_text(self, f, Vector2(x, base), t, s, col, tr)
		if count > 1:
			var mlh := Hub2ArsenalDraw.line_h(Hub2Style.MONO, 500, 11)
			Hub2Style.draw_text(self, mf, Vector2(x + lw + gap, roundf(Hub2ArsenalDraw.baseline(Hub2Style.MONO, 500, 11, bottom - mlh, mlh))),
					ct, ms, Hub2Style.text_a(0.55))
		var c := Vector2(roundf(size.x * 0.5), Hub2Style.px(38) + Hub2Style.px(6))
		Hub2ArsenalDraw.draw_diamond(self, c, Hub2Style.px(8), Hub2Style.YELLOW if on else Hub2Style.text_a(0.4))


## Zone des colonnes : filet de 1 px rgba(255,255,255,.16) à 42 px du haut.
class RailArea extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_rect(Rect2(0, Hub2Style.px(42), size.x, maxf(Hub2Style.px(1), 1.0)), Hub2Style.white_a(0.16))


## Flèche ‹ › du rail (32 px, Chakra Petch 28 px ; jaune si active, 15 %).
class ArrowFace extends Control:
	var glyph := "‹"
	var enabled := true:
		set(v):
			enabled = v
			queue_redraw()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		Hub2ArsenalDraw.text(self, glyph, Hub2Style.CHAKRA, 500, 28, Hub2Style.YELLOW if enabled else Hub2Style.text_a(0.15), 0.0,
				0.0, Hub2ArsenalDraw.baseline(Hub2Style.CHAKRA, 500, 28, 0.0, size.y), size.x, HORIZONTAL_ALIGNMENT_CENTER)


## Filtre CONSTRUCTIBLES / TOUTES : 28 px, padding 0 12, liseré 1 px,
## Chakra Petch 12 px 0,1em ; actif : fond et liseré #F2F0EA, texte
## #0B0B0C 700 ; sinon fond rgba(10,11,13,.5), liseré rgba(255,255,255,.14),
## texte 75 % 600.
class Chip extends Hub2Button:
	var label := ""
	var on := false:
		set(v):
			on = v
			_style()
	var _face: Control

	func _init() -> void:
		super()
		focus_mode = Control.FOCUS_NONE
		_face = Control.new()
		_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_face.draw.connect(_draw_face)
		add_content(_face)

	func set_label(t: String) -> void:
		label = t
		_style()

	func _style() -> void:
		var w := 700 if on else 600
		var s := Hub2Style.fs(12)
		var tw := Hub2Style.text_width(label, Hub2Style.font(Hub2Style.CHAKRA, w), s, Hub2Style.tracking_px(0.1, s))
		custom_minimum_size = Vector2(ceilf(tw + Hub2Style.px(12) * 2.0 + Hub2Style.px(1) * 2.0), Hub2Style.px(28))
		if on:
			box.flat(Hub2Style.TEXT, Hub2Style.TEXT, 1.0)
		else:
			box.flat(Color(10 / 255.0, 11 / 255.0, 13 / 255.0, 0.5), Hub2Style.white_a(0.14), 1.0)
		if _face:
			_face.queue_redraw()

	func _draw_face() -> void:
		var w := 700 if on else 600
		Hub2ArsenalDraw.text(_face, label, Hub2Style.CHAKRA, w, 12, Hub2Style.INK if on else Hub2Style.text_a(0.75), 0.1,
				0.0, Hub2ArsenalDraw.baseline(Hub2Style.CHAKRA, w, 12, 0.0, _face.size.y), _face.size.x, HORIZONTAL_ALIGNMENT_CENTER)


## Arme en main de la bande MUNITIONS : « NOM en main · » (Barlow 14) puis
## « chargeur / réserve » (JetBrains Mono 14) ; coupée avec « … » si besoin.
class AmmoLine extends Control:
	var name_text := ""
	var count := ""

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_texts(n: String, c: String) -> void:
		name_text = n
		count = c
		custom_minimum_size.y = ceilf(Hub2ArsenalDraw.line_h(Hub2Style.BARLOW, 400, 14))
		queue_redraw()

	func _draw() -> void:
		var bf := Hub2Style.font(Hub2Style.BARLOW, 400)
		var bs := Hub2Style.fs(14)
		var mf := Hub2Style.font(Hub2Style.MONO, 500)
		var cw := Hub2Style.text_width(count, mf, bs)
		var base := Hub2ArsenalDraw.baseline(Hub2Style.BARLOW, 400, 14, 0.0, size.y)
		var room := size.x - cw
		var nt := Hub2Prompts.ellipsis(name_text, bf, bs, maxf(room, 0.0)) if count != "" else Hub2Prompts.ellipsis(name_text, bf, bs, size.x)
		var x := Hub2ArsenalDraw.text(self, nt, Hub2Style.BARLOW, 400, 14, Hub2Style.TEXT, 0.0, 0.0, base)
		if count != "":
			Hub2Style.draw_text(self, mf, Vector2(roundf(x), roundf(base)), count, bs, Hub2Style.TEXT)


## Rendu de l'arme en main (70 × 32, contain, sans ombre).
class SmallRender extends Control:
	var tex: Texture2D

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _ready() -> void:
		custom_minimum_size = Hub2Style.pxv(70, 32)

	func _draw() -> void:
		if tex:
			draw_texture_rect(tex, Hub2ArsenalDraw.contain(tex.get_size(), Rect2(Vector2.ZERO, size)), false)
