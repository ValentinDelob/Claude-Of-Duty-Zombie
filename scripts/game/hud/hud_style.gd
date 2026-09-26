class_name HudStyle
extends RefCounted
## Style du HUD de jeu façon Black Ops 1 (voir docs/ART_DIRECTION.md, « HUD ») :
## polices système condensées sans empattement, couleurs, et pinceau
## procédural (traits « peints à la main » du compteur de manche et des
## bandeaux de points). Aucune image externe.

## Rouge sang du compteur de manche (BO1 : rouge profond, légèrement brun).
const ROUND_RED := Color(0.62, 0.04, 0.02)
const ROUND_RED_LIGHT := Color(0.8, 0.1, 0.05)
## Blanc cassé des transitions de manche et des textes.
const CHALK := Color(0.96, 0.94, 0.88)
const TEXT := Color(0.93, 0.92, 0.87)
const TEXT_DIM := Color(0.7, 0.69, 0.64)
const POINTS_GAIN := Color(1.0, 0.86, 0.32)
const POINTS_LOSS := Color(0.9, 0.16, 0.1)
## Couleurs des joueurs (BO1 : blanc, bleu, jaune, vert), puis extras.
const PLAYER_COLORS := [
	Color(0.93, 0.93, 0.9), Color(0.36, 0.6, 1.0), Color(1.0, 0.84, 0.25), Color(0.42, 0.88, 0.38),
	Color(0.9, 0.5, 0.9), Color(0.5, 0.9, 0.9), Color(1.0, 0.6, 0.4), Color(0.7, 0.7, 0.7),
]

static var _fonts: Dictionary = {}


static func player_color(slot: int) -> Color:
	return PLAYER_COLORS[posmod(slot, PLAYER_COLORS.size())]


## « condensed » : chiffres et noms (Bahnschrift étroite, sinon Arial Narrow,
## Impact) ; « text » : invites et sous-titres (Bahnschrift semi-étroite).
static func font(kind := "condensed") -> Font:
	if _fonts.has(kind):
		return _fonts[kind]
	var f := SystemFont.new()
	match kind:
		"condensed":
			f.font_names = PackedStringArray(["Bahnschrift", "Arial Narrow", "Impact", "sans-serif"])
			f.font_weight = 700
			f.font_stretch = 75
		"title":
			f.font_names = PackedStringArray(["Bahnschrift", "Impact", "Arial Black", "sans-serif"])
			f.font_weight = 700
			f.font_stretch = 87
		_:
			f.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Arial", "sans-serif"])
			f.font_weight = 500
			f.font_stretch = 87
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	f.hinting = TextServer.HINTING_LIGHT
	_fonts[kind] = f
	return f


## Étiquette du HUD : ombre portée douce et contour sombre (lisible sur le
## grain et les lumières vives, comme BO1).
static func label(text: String, size: int, color := TEXT, kind := "condensed", outline := 4) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(kind))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("outline_size", outline)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


# --------------------------------------------------------------------------
# Pinceau procédural
# --------------------------------------------------------------------------

## Trait de pinceau le long de `pts` (coordonnées de `ci`) : largeur variable
## (attaque, pression, fin effilée), bords irréguliers, stries sèches plus
## claires et coulures éventuelles. Déterministe pour une graine donnée.
static func brush_stroke(ci: CanvasItem, pts: PackedVector2Array, width: float, col: Color, rng_seed: int, drips := 0.0) -> void:
	if pts.size() < 2:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	# Rééchantillonnage régulier pour un bord irrégulier homogène.
	var path := _resample(pts, maxf(width * 0.35, 2.0))
	var n := path.size()
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var widths := PackedFloat32Array()
	var phase := rng.randf() * TAU
	for i in n:
		var t := float(i) / float(n - 1)
		var dir := (path[mini(i + 1, n - 1)] - path[maxi(i - 1, 0)]).normalized()
		var nrm := Vector2(-dir.y, dir.x)
		# Attaque franche, légère pression au milieu, fin effilée « sèche ».
		var w := width * (0.72 + 0.28 * smoothstep(0.0, 0.12, t)) * (1.0 - 0.55 * smoothstep(0.78, 1.0, t))
		w *= 1.0 + 0.12 * sin(t * 9.0 + phase)
		widths.append(w)
		left.append(path[i] + nrm * (w * 0.5 + rng.randf_range(-0.12, 0.12) * width))
		right.append(path[i] - nrm * (w * 0.5 + rng.randf_range(-0.12, 0.12) * width))
	# Quadrilatères successifs (les boucles des 0, 6, 8, 9 ne forment pas un
	# polygone simple). Opaque : la transparence passe par `modulate`.
	# Triangles bruts (draw_primitive) : aucune triangulation qui pourrait
	# échouer dans les virages serrés.
	var cols := PackedColorArray([col, col, col])
	for i in n - 1:
		ci.draw_primitive(PackedVector2Array([left[i], left[i + 1], right[i + 1]]), cols, PackedVector2Array())
		ci.draw_primitive(PackedVector2Array([left[i], right[i + 1], right[i]]), cols, PackedVector2Array())
	# Stries sèches (poils du pinceau) : plus claires et plus sombres.
	var streaks := 3
	for s in streaks:
		var off := rng.randf_range(-0.32, 0.32)
		var line := PackedVector2Array()
		var start := int(rng.randf_range(0.0, 0.3) * n)
		var stop := int(rng.randf_range(0.65, 1.0) * n)
		for i in range(start, maxi(stop, start + 2)):
			var k := clampi(i, 0, n - 1)
			line.append(right[k].lerp(left[k], 0.5 + off))
		var sc := col.lightened(0.22) if s % 2 == 0 else col.darkened(0.35)
		sc.a *= 0.55
		if line.size() >= 2:
			ci.draw_polyline(line, sc, maxf(width * 0.09, 1.0), true)
	# Coulures : gouttes qui descendent sous le trait.
	if drips > 0.0:
		var count := int(floor(drips + rng.randf()))
		for d in count:
			var i := rng.randi_range(int(n * 0.15), n - 1)
			var base := path[i] + Vector2(0, widths[i] * 0.35)
			var length := width * rng.randf_range(0.5, 1.6)
			var dw := widths[i] * rng.randf_range(0.18, 0.3)
			ci.draw_colored_polygon(PackedVector2Array([base + Vector2(-dw, 0), base + Vector2(dw, 0),
					base + Vector2(dw * 0.45, length), base + Vector2(-dw * 0.45, length)]), col)
			ci.draw_circle(base + Vector2(0, length), dw * 0.65, col)


static func _resample(pts: PackedVector2Array, step: float) -> PackedVector2Array:
	var out := PackedVector2Array([pts[0]])
	for i in range(1, pts.size()):
		var a := pts[i - 1]
		var b := pts[i]
		var d := a.distance_to(b)
		var k := maxi(1, int(ceil(d / step)))
		for j in range(1, k + 1):
			out.append(a.lerp(b, float(j) / k))
	return out


## Chiffre « peint à la main » (0-9) : liste de traits dans une boîte 0..1
## (x vers la droite, y vers le bas), largeur 0,62 de la hauteur.
static func digit_strokes(d: int) -> Array:
	match d:
		0:
			return [_arc(Vector2(0.31, 0.5), Vector2(0.27, 0.46), -100.0, 262.0)]
		1:
			return [PackedVector2Array([Vector2(0.12, 0.2), Vector2(0.34, 0.03)]),
					PackedVector2Array([Vector2(0.34, 0.02), Vector2(0.33, 0.98)])]
		2:
			var a := _arc(Vector2(0.3, 0.28), Vector2(0.24, 0.24), 200.0, 390.0)
			a.append(Vector2(0.06, 0.95))
			return [a, PackedVector2Array([Vector2(0.05, 0.95), Vector2(0.6, 0.93)])]
		3:
			return [_arc(Vector2(0.28, 0.26), Vector2(0.24, 0.22), 200.0, 450.0),
					_arc(Vector2(0.28, 0.72), Vector2(0.28, 0.25), -90.0, 160.0)]
		4:
			return [PackedVector2Array([Vector2(0.44, 0.02), Vector2(0.03, 0.68), Vector2(0.62, 0.68)]),
					PackedVector2Array([Vector2(0.45, 0.3), Vector2(0.46, 0.98)])]
		5:
			var s := PackedVector2Array([Vector2(0.56, 0.05), Vector2(0.12, 0.05), Vector2(0.08, 0.44)])
			s.append_array(_arc(Vector2(0.28, 0.67), Vector2(0.28, 0.29), -120.0, 150.0))
			return [s]
		6:
			var six := PackedVector2Array([Vector2(0.5, 0.04), Vector2(0.22, 0.3)])
			six.append_array(_arc(Vector2(0.3, 0.68), Vector2(0.26, 0.28), 200.0, 560.0))
			return [six]
		7:
			return [PackedVector2Array([Vector2(0.04, 0.05), Vector2(0.6, 0.04), Vector2(0.22, 0.98)])]
		8:
			return [_arc(Vector2(0.31, 0.25), Vector2(0.21, 0.21), 90.0, 450.0),
					_arc(Vector2(0.31, 0.72), Vector2(0.27, 0.26), -90.0, 270.0)]
		9:
			var nine := _arc(Vector2(0.31, 0.3), Vector2(0.25, 0.26), 20.0, 380.0)
			nine.append(Vector2(0.5, 0.6))
			nine.append(Vector2(0.28, 0.98))
			return [nine]
	return []


## Arc d'ellipse (angles en degrés, 0 = droite, sens horaire à l'écran).
static func _arc(c: Vector2, r: Vector2, from_deg: float, to_deg: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var steps := maxi(6, int(absf(to_deg - from_deg) / 15.0))
	for i in steps + 1:
		var a := deg_to_rad(lerpf(from_deg, to_deg, float(i) / steps))
		out.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
	return out
