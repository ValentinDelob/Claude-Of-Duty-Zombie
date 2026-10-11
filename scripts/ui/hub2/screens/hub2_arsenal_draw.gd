class_name Hub2ArsenalDraw
extends RefCounted
## Dessin de l'ARSENAL du hub v2 (docs/hub_v2/Arsenal.dc.html) : rendu d'arme
## en object-fit: contain avec filter: drop-shadow (ombre floue approchée par
## des copies noires décalées), losange (transform: rotate(45deg)), texte d'une
## ligne (jamais coupé), pièce en pixel art (un
## pixel = un cube), icônes des statistiques : les <path> SVG de la maquette
## rendus par le moteur SVG de Godot (trait carré, angles vifs) à la taille
## finale × suréchantillonnage, en cache.

## Copies de l'ombre (centre + anneau) : approche le flou gaussien du CSS.
const SHADOW_TAPS := [Vector2(0, 0), Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1),
	Vector2(0.7, 0.7), Vector2(-0.7, 0.7), Vector2(0.7, -0.7), Vector2(-0.7, -0.7)]
## Suréchantillonnage des icônes SVG (nettes jusqu'au 4K).
const SVG_OVERSAMPLE := 4.0

static var _svg_cache: Dictionary = {}


## Rectangle de `tex` en object-fit: contain dans `box`.
static func contain(tex_size: Vector2, box: Rect2) -> Rect2:
	if tex_size.x <= 0.0 or tex_size.y <= 0.0 or box.size.x <= 0.0 or box.size.y <= 0.0:
		return Rect2(box.position, Vector2.ZERO)
	var k := minf(box.size.x / tex_size.x, box.size.y / tex_size.y)
	var s := tex_size * k
	return Rect2(box.position + (box.size - s) * 0.5, s)


## Texture `tex` en contain dans `box` avec drop-shadow(0 `dy` `blur`
## rgba(0, 0, 0, `alpha`)) (valeurs déjà à l'échelle). `modulate` : teinte.
static func draw_render(ci: CanvasItem, tex: Texture2D, box: Rect2, dy: float, blur: float, alpha: float,
		modulate := Color.WHITE) -> void:
	if tex == null:
		return
	var r := contain(tex.get_size(), box)
	if r.size.x <= 0.0:
		return
	# Opacité par copie : n copies superposées au centre donnent `alpha`.
	var n := SHADOW_TAPS.size()
	var a := 1.0 - pow(1.0 - clampf(alpha * modulate.a, 0.0, 0.99), 1.0 / float(n))
	var rad := blur * 0.5
	for t: Vector2 in SHADOW_TAPS:
		var o := Vector2(0, dy) + t * rad
		ci.draw_texture_rect(tex, Rect2(r.position + o, r.size), false, Color(0, 0, 0, a))
	ci.draw_texture_rect(tex, r, false, modulate)


## Losange plein de `side` px (carré tourné de 45°) centré en `c`, bords
## adoucis.
static func draw_diamond(ci: CanvasItem, c: Vector2, side: float, col: Color) -> void:
	var h := side * 0.7071
	var pts := PackedVector2Array([c + Vector2(0, -h), c + Vector2(h, 0), c + Vector2(0, h), c + Vector2(-h, 0)])
	ci.draw_colored_polygon(pts, col)
	pts.append(pts[0])
	ci.draw_polyline(pts, col, 1.0, true)


## Texte d'une ligne à la ligne de base `y`, aligné dans [x, x + w]
## (`align` : HORIZONTAL_ALIGNMENT_*) ; jamais coupé (l'appelant adapte la
## taille ou passe à la ligne) ; rend la largeur.
static func text(ci: CanvasItem, t: String, family: String, weight: int, size_css: float, col: Color, tracking_em: float,
		x: float, y: float, w := -1.0, align := HORIZONTAL_ALIGNMENT_LEFT) -> float:
	var f := Hub2Style.font(family, weight)
	var s := Hub2Style.fs(size_css)
	var tr := Hub2Style.tracking_px(tracking_em, s)
	var tw := Hub2Style.text_width(t, f, s, tr)
	var px := x
	if w >= 0.0:
		match align:
			HORIZONTAL_ALIGNMENT_CENTER:
				px = x + (w - tw) * 0.5
			HORIZONTAL_ALIGNMENT_RIGHT:
				px = x + w - tw
	Hub2Style.draw_text(ci, f, Vector2(roundf(px), roundf(y)), t, s, col, tr)
	return tw


## Hauteur de ligne (line-height: normal) d'une police de la maquette, comme
## le navigateur : (ascendante + descendante de la police) × taille, sans
## l'arrondi au pixel de chaque mesure que fait Godot aux petites tailles
## (Chakra Petch 17 px : 22,1 et non 23).
static func line_h(family: String, weight: int, size_css: float) -> float:
	var m := css_metrics(family, weight)
	return (m.x + m.y) * float(Hub2Style.fs(size_css))


## Ligne de base d'un texte centré verticalement dans [y, y + h].
static func baseline(family: String, weight: int, size_css: float, y: float, h: float) -> float:
	var m := css_metrics(family, weight)
	var s := float(Hub2Style.fs(size_css))
	return y + (h - (m.x + m.y) * s) * 0.5 + m.x * s


static var _metrics: Dictionary = {}


## Ascendante et descendante de la police en fraction de sa taille (mesurées
## à 1000 px : précision au millième).
static func css_metrics(family: String, weight: int) -> Vector2:
	var key := "%s:%d" % [family, weight]
	if _metrics.has(key):
		return _metrics[key]
	var f := Hub2Style.font(family, weight)
	var m := Vector2(f.get_ascent(1000) / 1000.0, f.get_descent(1000) / 1000.0)
	_metrics[key] = m
	return m


## Pièce en pixel art (8 × 8, un pixel = un cube ; « M » acier clair, « n »
## acier sombre, « . » vide).
const PART_ART := ["...MM...", ".M.MM.M.", "..MMMM..", "MMMnnMMM", "MMMnnMMM", "..MMMM..", ".M.MM.M.", "...MM..."]
const PART_PAL := {"M": "8C9196", "n": "5C6064"}


## Pièce en pixel art (PART_ART, un pixel = un cube, contour noir), centrée
## dans `box`, cellule de `cell` px ; `alpha` : opacité.
static func draw_part_art(ci: CanvasItem, box: Rect2, cell: float, alpha := 1.0) -> void:
	var rows: Array = PART_ART
	var g := Vector2i(String(PART_ART[0]).length(), PART_ART.size())
	var off := (box.position + (box.size - Vector2(g) * cell) * 0.5).floor()
	var o := maxf(roundf(cell * 0.35), 1.0)
	for pass_i in 2:
		for y in rows.size():
			var row := String(rows[y])
			for x in row.length():
				var ch := row[x]
				if ch == "." or not PART_PAL.has(ch):
					continue
				if pass_i == 0:
					ci.draw_rect(Rect2(off + Vector2(x * cell - o, y * cell - o), Vector2(cell + o * 2.0, cell + o * 2.0)),
							Color(0, 0, 0, 0.85 * alpha))
				else:
					var col := Color(PART_PAL[ch])
					col.a = alpha
					ci.draw_rect(Rect2(off + Vector2(x * cell, y * cell), Vector2(cell, cell)), col)


## Icône d'une statistique : `d` (<path> SVG, viewBox 24) à `size` px (déjà à
## l'échelle), trait `stroke` (unités du viewBox), couleur `col`.
static func svg_icon(d: String, size: float, col: Color, stroke := 2.0) -> Texture2D:
	var px := maxi(roundi(size * SVG_OVERSAMPLE), 8)
	var key := "%s|%d|%s|%s" % [d, px, col.to_html(), stroke]
	if _svg_cache.has(key):
		return _svg_cache[key]
	var svg := ("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"24\" height=\"24\" viewBox=\"0 0 24 24\" fill=\"none\" "
			+ "stroke=\"#%s\" stroke-width=\"%s\" stroke-linecap=\"square\" stroke-linejoin=\"miter\">"
			+ "<path d=\"%s\"/></svg>") % [col.to_html(false), stroke, d]
	var img := Image.new()
	var err := img.load_svg_from_string(svg, float(px) / 24.0)
	var tex: Texture2D = null
	if err == OK:
		img.generate_mipmaps()
		tex = ImageTexture.create_from_image(img)
	else:
		tex = HubRenders.empty()
	_svg_cache[key] = tex
	return tex


## Tirets (border: 1px dashed) autour de `r`.
static func draw_dashed_rect(ci: CanvasItem, r: Rect2, col: Color, w := 1.0) -> void:
	var dash := maxf(roundf(w * 3.0), 3.0)
	var gap := dash
	for side in 4:
		var a: Vector2
		var b: Vector2
		match side:
			0:
				a = r.position
				b = Vector2(r.end.x, r.position.y)
			1:
				a = Vector2(r.end.x - w, r.position.y)
				b = Vector2(r.end.x - w, r.end.y)
			2:
				a = Vector2(r.position.x, r.end.y - w)
				b = Vector2(r.end.x, r.end.y - w)
			_:
				a = r.position
				b = Vector2(r.position.x, r.end.y)
		var length := a.distance_to(b)
		var dir := (b - a).normalized()
		var t := 0.0
		while t < length:
			var e := minf(t + dash, length)
			var p0 := a + dir * t
			var p1 := a + dir * e
			var rect := Rect2(p0, Vector2(maxf(p1.x - p0.x, w), maxf(p1.y - p0.y, w)))
			ci.draw_rect(rect, col)
			t += dash + gap
