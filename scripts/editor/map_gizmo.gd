class_name MapGizmo
extends RefCounted
## Poignées d'échelle et anneaux de rotation de l'éditeur de cartes (format
## 14, docs/EDITOR_SCALE_ROTATE.md § 2.4 et § 3.2), logique pure partagée
## par la vue Dessus (MapCanvas), les élévations (MapElevationTools) et la
## vue 3D : géométrie des poignées dans le repère de l'objet, point fixe selon
## le montage (§ 2.2), pas et aimants de l'échelle (E4), angle d'un anneau
## (crans de 15°, sens de chaque vue), élément résultant d'un geste.

## Pas de l'échelle selon l'aimantation : grille 1 m, grille fine, libre.
const STEP_GRID := 0.25
const STEP_FINE := 0.05
const STEP_FREE := 0.01
## Aimants de l'échelle (grille fine et libre) : à moins de ce facteur.
const MAGNET_TOL := 0.03
## Anneau en vue plane (px à 100 %) : demi-diagonale + 14, de 36 à 140 ;
## anneau de la vue 3D : 90 ; bande de prise : 8.
const RING_PAD := 14.0
const RING_MIN := 36.0
const RING_MAX := 140.0
const RING_3D := 90.0
const RING_BAND := 8.0
## Cran des anneaux (degrés).
const ANGLE_STEP := 15.0
## Couleurs des axes (docs/EDITOR_VIEWS.md) et des poignées.
const COL_X := Color("E5484D")
const COL_Y := Color("46A758")
const COL_Z := Color("3E7BFA")
const COL_HANDLE := Color("FFD94D")
const COL_LOCK := Color("55555C")
const COL_GOLD := Color("F2C759")


# ------------------------------------------------------------------ pas et aimants (E4)

static func scale_step(mode: String) -> float:
	match mode:
		"grille":
			return STEP_GRID
		"fine":
			return STEP_FINE
	return STEP_FREE


## Facteur `v` aimanté : au pas du mode, borné ; en grille fine et libre, les
## aimants ×1, ×0,5, ×2 et `extra` ([{f, label}] : taille d'un décor voisin)
## l'attirent. -> {v, label ("" : pas d'aimant)}.
static func snap_scale(v: float, mode: String, extra: Array = []) -> Dictionary:
	if mode != "grille":
		var best := {}
		var best_d := MAGNET_TOL
		var mags := [{"f": 1.0, "label": "×" + MapView.num(1.0, 2)}, {"f": 0.5, "label": "×" + MapView.num(0.5, 2)}, {"f": 2.0, "label": "×" + MapView.num(2.0, 2)}]
		mags.append_array(extra)
		for m in mags:
			var d := absf(v - float(m.f))
			if d <= best_d:
				best_d = d
				best = m
		if not best.is_empty():
			return {"v": clampf(float(best.f), MapScale.LO, MapScale.HI), "label": String(best.label)}
	var stp := scale_step(mode)
	return {"v": clampf(snappedf(v, stp), MapScale.LO, MapScale.HI), "label": ""}


## Aimants « taille d'un décor voisin » (§ 2.4) pour l'axe `axis` de `o` :
## facteurs qui donnent à cette dimension celle d'un décor proche (3 m),
## [{f, label « = Bureau »}].
static func neighbour_magnets(doc: EditorMap, o: Dictionary, axis: int) -> Array:
	var out := []
	var base := MapScale.base_dims(o)[axis]
	if base <= 0.0 or doc == null:
		return out
	var p := MapGeom.v2(o.get("position", [0, 0]))
	for q in doc.objects_on(int(o.get("etage", 0))):
		if String(q.get("id", "")) == String(o.get("id", "")) or String(q.get("type", "")) != "prefab":
			continue
		if MapGeom.v2(q.get("position", [0, 0])).distance_to(p) > 3.0 + MapScale.dims(q).length() * 0.5:
			continue
		var f := MapScale.dims(q)[axis] / base
		if f >= MapScale.LO and f <= MapScale.HI:
			out.append({"f": f, "label": "= " + String(MapScale.label_of(q)[0 if not Lang.is_en() else 1])})
	return out


# ------------------------------------------------------------------ repère de l'objet

## Repère de la boîte d'un décor dans le plan : {c (centre, m), ex, ey (axes
## locaux X largeur, Y profondeur ; mural : X le long du mur, Y vers la
## pièce), h (demi-dimensions finales, Vector3), mount}.
static func frame(o: Dictionary) -> Dictionary:
	var d := MapScale.dims(o)
	var h := d * 0.5
	var mount := MapScale.mount_of(o)
	var p := MapGeom.v2(o.get("position", [0, 0]))
	if mount == "mur":
		var dv := MapGeom.item_wall_dir(o)
		var ey := -dv
		var ex := Vector2(dv.y, -dv.x)
		var face := p - dv * MapGeom.WALL_HALF
		return {"c": face + ey * h.y, "ex": ex, "ey": ey, "h": h, "mount": mount}
	var a := deg_to_rad(float(MapGeom.rot_of(o)))
	return {"c": p, "ex": Vector2(cos(a), sin(a)), "ey": Vector2(-sin(a), cos(a)), "h": h, "mount": mount}


## Poignées d'échelle en vue Dessus (§ 2.4) : coins (uniforme) et faces X /
## Y (si l'objet n'est pas incliné) : [{id, p (m), kind « corner » | « face »,
## axis (0 : X, 1 : Y), side (±1), corner (Vector2 de ±1)}]. Incliné : les
## coins de son emprise à l'écran. Mural : pas de face côté mur (fixe).
static func top_handles(o: Dictionary) -> Array:
	var out := []
	if MapScale.is_tilted(o):
		var bb := MapGeom.bbox(MapScale.ground_poly(o))
		var cs := [bb.position, Vector2(bb.end.x, bb.position.y), bb.end, Vector2(bb.position.x, bb.end.y)]
		for i in 4:
			var q: Vector2 = cs[i]
			out.append({"id": "c%d" % i, "p": q, "kind": "corner", "corner": Vector2(signf(q.x - bb.get_center().x), signf(q.y - bb.get_center().y)), "screen": true})
		return out
	var f := frame(o)
	var c: Vector2 = f.c
	var ex: Vector2 = f.ex
	var ey: Vector2 = f.ey
	var h: Vector3 = f.h
	var i := 0
	for s in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		out.append({"id": "c%d" % i, "p": c + ex * h.x * s.x + ey * h.y * s.y, "kind": "corner", "corner": s})
		i += 1
	out.append({"id": "fx-", "p": c - ex * h.x, "kind": "face", "axis": 0, "side": -1})
	out.append({"id": "fx+", "p": c + ex * h.x, "kind": "face", "axis": 0, "side": 1})
	if f.mount != "mur":
		out.append({"id": "fy-", "p": c - ey * h.y, "kind": "face", "axis": 1, "side": -1})
	out.append({"id": "fy+", "p": c + ey * h.y, "kind": "face", "axis": 1, "side": 1})
	if MapScale.uniform_only(o):
		return out.filter(func(x): return x.kind == "corner")
	return out


## Couleur d'une poignée de face (axe local : X rouge, Y vert, Z bleu).
static func axis_col(axis: int) -> Color:
	return [COL_X, COL_Y, COL_Z][clampi(axis, 0, 2)]


# ------------------------------------------------------------------ gestes d'échelle

## Élément `o0` dont l'axe local `axis` (0 : X, 1 : Y, 2 : Z) passe au
## facteur `v`, le côté `side` tiré (±1) : le côté opposé reste en place
## (`alt` : le centre) ; règles du § 2.2 : au sol la base reste sur son
## support, mural la face du mur reste fixe, au plafond l'attache reste.
## Copie.
static func scale_axis(o0: Dictionary, axis: int, v: float, side: int, alt: bool) -> Dictionary:
	var o := o0.duplicate(true)
	if not is_finite(v):
		return o   # valeur illisible : rien ne change
	var s := MapScale.scale_of(o0)
	var s1 := s
	s1[axis] = clampf(v, MapScale.LO, MapScale.HI)
	MapScale.set_scale(o, s1)
	var k := MapScale.scale_of(o)[axis] / maxf(s[axis], 0.0001)
	var f := frame(o0)
	var h: Vector3 = f.h
	var a := 0.0 if alt else -float(side)
	if axis == 1 and f.mount == "mur":
		return o   # face du mur fixe : la position (sur le trait du mur) ne bouge pas
	if axis == 2:
		_shift_z(o, o0, f, a, h.z * (1.0 - k))
		return o
	var dc := a * h[axis] * (1.0 - k)
	var dirv: Vector2 = f.ex if axis == 0 else f.ey
	_shift_plane(o, f, dirv * dc)
	return o


## Échelle uniforme (× `k` sur les trois axes, depuis l'échelle de `o0`)
## autour du point fixe `fixed` du plan (m) ; hauteur : base (sol), attache
## (plafond) fixes ; mural : `fz` (-1 bas, 0 centre, 1 haut). Copie.
static func scale_uniform(o0: Dictionary, k: float, fixed: Vector2, fz := 0.0) -> Dictionary:
	var o := o0.duplicate(true)
	if not (is_finite(k) and k > 0.0 and is_finite(fixed.x) and is_finite(fixed.y)):
		return o   # valeur illisible : rien ne change
	var s := MapScale.scale_of(o0)
	MapScale.set_scale(o, s * k)
	var kk := MapScale.scale_of(o).x / maxf(s.x, 0.0001)
	var f := frame(o0)
	var c: Vector2 = f.c
	var nc := fixed + (c - fixed) * kk
	if f.mount == "mur":
		# Le long du mur seulement (la face du mur reste fixe).
		var ex: Vector2 = f.ex
		_shift_plane(o, f, ex * (nc - c).dot(ex))
		_shift_z(o, o0, f, fz, (f.h as Vector3).z * (1.0 - kk))
	else:
		_shift_plane(o, f, nc - c)
	return o


## Déplace le décor dans le plan (position ; mural : le long de son mur).
static func _shift_plane(o: Dictionary, f: Dictionary, d: Vector2) -> void:
	var p := MapGeom.v2(o.get("position", [0, 0])) + d
	o["position"] = MapGeom.arr(MapGeom.round_mm(p))


## Hauteur : au sol et au plafond rien ne bouge (base, attache fixes) ;
## mural, la « hauteur » (au centre) suit le point fixe `a` (-1 bas, 0 centre, 1 haut).
static func _shift_z(o: Dictionary, o0: Dictionary, f: Dictionary, a: float, dh: float) -> void:
	if f.mount != "mur":
		return
	var hz := MapCatalog.wall_light_height(o0) + a * dh
	MapCatalog.set_wall_light_height(o, snappedf(hz, 0.01))


## Facteur d'un geste le long du segment fixe -> poignée : projection de
## `m - fixed` sur `h0 - fixed` (1 : la poignée n'a pas bougé).
static func ratio(fixed: Vector2, h0: Vector2, m: Vector2) -> float:
	var d := h0 - fixed
	if d.length_squared() < 0.000001:
		return 1.0
	return maxf(0.0, (m - fixed).dot(d) / d.length_squared())


## Valeur tapée pendant un geste d'échelle : « 1,5 » (facteur) ou « 3m »
## (dimension en mètres, rapportée à `dim0`, dimension d'origine × échelle
## courante `s0`). -> nouveau facteur, NAN si illisible.
static func typed_factor(t: String, dim_now: float, s_now: float) -> float:
	var s := t.strip_edges().replace(",", ".").replace("×", "").replace(" ", "")
	var out := NAN
	if s.ends_with("m"):
		var mv := s.trim_suffix("m")
		if mv.is_valid_float() and dim_now > 0.0:
			out = s_now * float(mv) / dim_now
	else:
		if s.begins_with("x"):
			s = s.substr(1)
		if s.is_valid_float():
			out = float(s)
	# Illisible, nul, négatif ou infini : NAN (le geste garde sa dernière valeur).
	return out if is_finite(out) and out > 0.0 else NAN


# ------------------------------------------------------------------ anneaux (§ 3.2)

## Rayon (px) de l'anneau Z d'un décor en vue plane : demi-diagonale de son
## emprise + 14, de 36 à 140 (à 100 %).
static func ring_radius(o: Dictionary, zoom: float, scale := 1.0) -> float:
	var bb := MapGeom.bbox(MapRaster.floor_poly(o)) if MapCatalog.tool_of(o) == "floor_item" else MapRules.footprint_rect(o)
	return clampf(bb.size.length() * 0.5 * zoom + RING_PAD * scale, RING_MIN * scale, RING_MAX * scale)


## Axe (0 : X, 1 : Y, 2 : Z) de l'anneau d'une vue plane : Dessus -> Z, Avant
## et Arrière -> Y, Droite et Gauche -> X ; -1 : aucun (Dessous).
static func ring_axis(plane: String) -> int:
	match plane:
		"dessus":
			return 2
		"avant", "arriere":
			return 1
		"droite", "gauche":
			return 0
	return -1


## Signe qui passe d'un angle horaire à l'écran à l'angle du § 3.1 : Arrière
## et Gauche regardent l'axe de l'autre bout (sens inversé à l'écran).
static func screen_sign(plane: String) -> float:
	return -1.0 if plane in ["arriere", "gauche"] else 1.0


## Angle (degrés) tourné depuis `a0` (radians, angle écran au début) jusqu'au
## point `p` autour de `c` (px, y vers le bas : horaire positif), aux crans
## de 15° (sauf `free` : au degré).
static func ring_angle(c: Vector2, a0: float, p: Vector2, free: bool) -> float:
	var deg := rad_to_deg(angle_difference(a0, (p - c).angle()))
	return roundf(deg) if free else snappedf(deg, ANGLE_STEP)


## Décor `o0` tourné de `deg` (§ 3.1) autour de l'axe du MONDE `axis` : Z
## autour de sa position (le lacet change seul) ; X, Y autour du centre de
## sa boîte (« Rester posé » `rest` : son point le plus bas reste à « z » ;
## sinon le centre reste en place). Copie ; `_sous_sol` : il passerait sous le sol.
static func rotated(o0: Dictionary, axis: int, deg: float, rest: bool) -> Dictionary:
	var o := o0.duplicate(true)
	if axis == 2 and not MapScale.is_tilted(o0):
		var r := MapGeom.norm_deg(float(MapGeom.rot_of(o0)) + deg)
		if r == 0:
			o.erase("rot")
		else:
			o["rot"] = r
		return o
	var hz0 := MapScale.half_z(o0)
	MapScale.set_orientation(o, MapScale.axis_rot(axis, deg) * MapScale.matrix(o0))
	if not rest:
		var z := MapVertical.decor_z(o0) + hz0 - MapScale.half_z(o)
		if z < -0.011:
			o["_sous_sol"] = true
		if z < 0.005:
			o.erase("z")
		else:
			o["z"] = snappedf(z, 0.01)
	return o


## Graduations d'un anneau (px) : [[a, b, grande]] tous les 15°, plus longues
## tous les 45° (à 100 % : 4 et 7 px de part et d'autre du cercle).
static func ticks(c: Vector2, r: float, scale := 1.0) -> Array:
	var out := []
	for d in range(0, 360, 15):
		var big := d % 45 == 0
		var a := deg_to_rad(float(d))
		var dv := Vector2(cos(a), sin(a))
		var l := (7.0 if big else 4.0) * scale
		out.append([c + dv * (r - l), c + dv * (r + l), big])
	return out


## Pastille d'angle « Y +30° » (texte sans la lettre).
static func angle_label(deg: float) -> String:
	var r := roundi(deg)
	return ("+" if r > 0 else "") + MapView.num(float(r), 0) + "°"


# ------------------------------------------------------------------ dessin commun (vues planes)
# Style de la maquette (écrans 1 à 3) : poignées carrées jaunes à bord blanc,
# faces aux couleurs des axes, losange bleu de la hauteur, cotes en pastille
# sombre, facteur ou angle en or, aimant en bleu, cadenas gris.

static func _u(v: float) -> float:
	return EditorUi.px(v)


## Poignée carrée (10 px à 100 %), bord blanc.
static func draw_handle(c: CanvasItem, p: Vector2, col: Color, a := 1.0) -> void:
	var s := _u(10)
	var r := Rect2(p - Vector2.ONE * s * 0.5, Vector2.ONE * s)
	c.draw_rect(r, Color(col, a))
	c.draw_rect(r, Color(1, 1, 1, a), false, 1.5)


## Losange bleu de la hauteur (Z).
static func draw_diamond(c: CanvasItem, p: Vector2, a := 1.0) -> void:
	var s := _u(6)
	var pts := PackedVector2Array([p + Vector2(0, -s), p + Vector2(s, 0), p + Vector2(0, s), p + Vector2(-s, 0)])
	c.draw_colored_polygon(pts, Color(COL_Z, a))
	c.draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0, 0, 0, a), 1.0)


## Cadenas dessiné (`s` : 1 = 12 × 14 px à 100 %).
static func draw_lock(c: CanvasItem, p: Vector2, col: Color, s := 0.8) -> void:
	var k := _u(1) * s
	var o := p - Vector2(5, 7) * k
	c.draw_arc(o + Vector2(5, 3.6) * k, 3.0 * k, PI, TAU, 10, col, 1.5 * k, true)
	c.draw_line(o + Vector2(2, 3.6) * k, o + Vector2(2, 6) * k, col, 1.5 * k)
	c.draw_line(o + Vector2(8, 3.6) * k, o + Vector2(8, 6) * k, col, 1.5 * k)
	c.draw_rect(Rect2(o + Vector2(0, 5.5) * k, Vector2(10, 7.5) * k), col)
	c.draw_rect(Rect2(o + Vector2(4.3, 8) * k, Vector2(1.4, 2.6) * k), Color("1A1B1D"))


## Cadenas gris d'un coin (prefab bloqué) ; survolé : orangé.
static func draw_lock_square(c: CanvasItem, p: Vector2, hover: bool) -> void:
	var s := _u(14)
	var r := Rect2(p - Vector2.ONE * s * 0.5, Vector2.ONE * s)
	MapElevation._round_rect(c, r, Color("3a3020") if hover else Color("2A2B2F"), Color("D99940") if hover else COL_LOCK, 1.5)
	draw_lock(c, p + Vector2(0, _u(0.5)), Color("D99940") if hover else Color("8C8575"))


## Pastille (texte) : fond sombre, bord gris ; or ou bleu selon `kind`
## (« dim » : cote ; « gold » : facteur, angle ; « magnet » : aimant).
## `lead` : lettre d'axe en couleur avant le texte. Rend son rectangle.
static func draw_pill(c: CanvasItem, at: Vector2, text: String, kind := "dim", lead := "", lead_col := Color.WHITE, center := false) -> Rect2:
	var bf := MapView.bold_font(700 if kind == "gold" else 600)
	var fs := EditorUi.fs(12)
	var lw := (bf.get_string_size(lead, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + _u(5)) if lead != "" else 0.0
	var tw := bf.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var r := Rect2(at - Vector2(0, _u(13)), Vector2(lw + tw + _u(12), _u(19)))
	if center:
		r.position.x -= r.size.x * 0.5
		r.position.y += _u(4)
	var fill := Color("121214")
	var border := Color("38383D")
	var col := Color("DBD1B8")
	match kind:
		"gold":
			fill = Color("2b2410")
			border = COL_GOLD
			col = COL_GOLD
		"magnet":
			fill = Color("101a2e")
			border = COL_Z
			col = Color("cfe0ff")
	MapElevation._round_rect(c, r, fill, border)
	var base := r.position + Vector2(_u(6), _u(14))
	if lead != "":
		c.draw_string(bf, base, lead, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, lead_col)
	c.draw_string(bf, base + Vector2(lw, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	return r


## Cote (trait fléché entre deux points, px) et son étiquette centrée,
## décalée de `off` (px).
static func draw_dim(c: CanvasItem, a: Vector2, b: Vector2, label: String, off := Vector2.ZERO, col := Color("DBD1B8")) -> void:
	var d := b - a
	if d.length() < 2.0:
		return
	var u := d.normalized()
	var n := Vector2(-u.y, u.x)
	c.draw_line(a, b, col, 1.0)
	var ah := _u(7)
	var aw := _u(3.5)
	c.draw_colored_polygon(PackedVector2Array([a, a + u * ah + n * aw, a + u * ah - n * aw]), col)
	c.draw_colored_polygon(PackedVector2Array([b, b - u * ah + n * aw, b - u * ah - n * aw]), col)
	draw_pill(c, (a + b) * 0.5 + off, label, "dim", "", Color.WHITE, true)


## Petite croix (point fixe d'un geste d'échelle).
static func draw_cross(c: CanvasItem, p: Vector2, col := Color("DBD1B8")) -> void:
	var s := _u(5)
	c.draw_line(p + Vector2(-s, -s), p + Vector2(s, s), col, 1.5)
	c.draw_line(p + Vector2(-s, s), p + Vector2(s, -s), col, 1.5)


## Anneau d'une vue plane (§ 3.2) : cercle à la couleur de l'axe (épaissi
## s'il est survolé ou tourné), prise ronde (`grip_a`, radians écran), point
## central ; pendant le geste (`sweep` [a0, a1] en radians) : graduations,
## secteur balayé à 25 %, rayon d'avant en pointillés, prise au bout.
static func draw_ring(c: CanvasItem, ctr: Vector2, r: float, col: Color, o: Dictionary = {}) -> void:
	var a := float(o.get("alpha", 0.9))
	var active := bool(o.get("active", false))
	if active:
		col = col.lightened(0.15)
	if o.has("sweep"):
		var sw: Array = o.sweep
		var a0 := float(sw[0])
		var a1 := float(sw[1])
		for t in ticks(ctr, r, _u(1)):
			c.draw_line(t[0], t[1], Color(col, 0.85), 1.6 if t[2] else 1.0)
		var pts := PackedVector2Array([ctr])
		var n := 24
		for i in n + 1:
			var ang := a0 + (a1 - a0) * float(i) / n
			pts.append(ctr + Vector2(cos(ang), sin(ang)) * r)
		if absf(a1 - a0) > 0.001:
			c.draw_colored_polygon(pts, Color(col, 0.25))
		var p0 := ctr + Vector2(cos(a0), sin(a0)) * r
		var p1 := ctr + Vector2(cos(a1), sin(a1)) * r
		c.draw_dashed_line(ctr, p0, Color(Color("DBD1B8"), 0.6), 1.0, _u(3))
		c.draw_line(ctr, p1, col, 1.5)
		c.draw_arc(ctr, r, 0, TAU, 72, Color(col, a), 3.0 if active else 1.6, true)
		c.draw_circle(p1, _u(5.5), col)
		c.draw_arc(p1, _u(5.5), 0, TAU, 16, Color.WHITE, 1.5, true)
	else:
		c.draw_arc(ctr, r, 0, TAU, 72, Color(col, a), 3.0 if active else 1.6, true)
		if o.get("grip", true):
			var ga := float(o.get("grip_a", -PI * 0.5))
			var g := ctr + Vector2(cos(ga), sin(ga)) * r
			c.draw_circle(g, _u(4.5), Color(col, a))
			c.draw_arc(g, _u(4.5), 0, TAU, 14, Color(0, 0, 0, a), 1.0, true)
	c.draw_circle(ctr, _u(2.5), Color(1, 1, 1, minf(1.0, a + 0.1)))
	c.draw_arc(ctr, _u(2.5), 0, TAU, 10, Color(0, 0, 0, minf(1.0, a + 0.1)), 1.0, true)


## Bulle d'avertissement d'un prefab bloqué (survol d'un cadenas) : titre et
## lignes, accrochée au point `anchor` (px).
static func draw_warning(c: CanvasItem, anchor: Vector2, title: String, lines: Array) -> void:
	var bf := MapView.bold_font(700)
	var f := MapView.bold_font(400)
	var fs := EditorUi.fs(12)
	var w := bf.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, EditorUi.fs(13)).x
	for l in lines:
		w = maxf(w, f.get_string_size(String(l), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	var r := Rect2(anchor + Vector2(_u(23), -_u(51)), Vector2(w + _u(20), _u(26) + lines.size() * _u(16)))
	c.draw_line(anchor, r.position + Vector2(0, _u(20)), Color("D99940"), 1.0)
	MapElevation._round_rect(c, r, Color("2e2412"), Color("D99940"))
	c.draw_string(bf, r.position + Vector2(_u(10), _u(19)), title, HORIZONTAL_ALIGNMENT_LEFT, -1, EditorUi.fs(13), Color("FFE7B8"))
	for i in lines.size():
		c.draw_string(f, r.position + Vector2(_u(10), _u(37) + i * _u(16)), String(lines[i]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("FFD9A0"))


## Textes de la bulle d'un décor bloqué : [titre, lignes].
static func warning_text(o: Dictionary) -> Array:
	var nt := MapScale.names_text(MapScale.blockers_of(o))
	if String(o.get("type", "")) == "prefab":
		return [Lang.t("⚠  Échelle impossible pour ce prefab", "⚠  Scale impossible for this prefab"),
			[Lang.t("Il contient %s : les objets de jeu" % nt[0], "It contains %s: game objects" % nt[1]),
			Lang.t("gardent leur taille. Rotation Z permise.", "keep their size. Z rotation allowed.")]]
	var ph := MapScale.phrase(o)
	return [Lang.t("⚠  Échelle impossible", "⚠  Scale impossible"), [Lang.t("%s garde sa taille." % ph[0], "%s keeps its size." % ph[1])]]
