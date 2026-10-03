class_name MapElevationTools
extends RefCounted
## Édition dans une élévation (docs/EDITOR_VIEWS.md, § 6) : glisser un
## élément sur les deux axes de la vue (hauteur de pose continue, ou étage
## aimanté sur les sols, selon son type : MapVertical.pose_kind), flèches
## d'axe (X rouge, Y vert, Z bleu ; carré central : les deux axes),
## verrouillage X / Y / Z pendant le glissement, poignées (côtés sur l'axe de
## la vue, losange du haut : plafond d'une pièce, hauteur d'une barrière ou
## d'une zone d'effet), étiquettes de niveau (sol d'un étage), aimants
## verticaux nommés, cotes (hauteur au-dessus du sol, écart, distance au mur),
## fantôme de la position d'avant, saisie d'une valeur (Tab), curseurs.
## Sélection multiple : Maj + clic ajoute ou retire un élément ; un élément
## du groupe choisi glisse tout le groupe (MapGroup.move : axe de la vue,
## hauteur de pose ou étage).
## Un glissement = une étape d'annulation (au relâché).

## Flèches d'axe (px à 100 %, maquette, écran 2).
const ARROW_FROM := 14.0
const ARROW_TO := 44.0
const ARROW_HEAD := 51.0
## Rayon des aimants verticaux (px) : on les croise sans y rester collé.
const MAGNET_PX := 6.0
const COL_BONE := Color("DBD1B8")
const COL_GOLD := Color("F2C759")
const COL_MAGNET := Color(0.35, 0.9, 1.0)
const COL_CHIP := Color("121214")
const COL_CHIP_LINE := Color("38383D")

var ev: MapElevation
## Glissement en cours : {kind (move, side, top, level, topceil), start_m,
## snap, orig, attached, moved, lock ("", "h", "v", "both" : immobile), ...} ; vide sinon.
var drag: Dictionary = {}
## Valeur tapée pendant le glissement (Tab, chiffres, Entrée).
var entry := ""
var entering := false
## Aimant vertical actif : {z, label} ; vide sinon.
var magnet: Dictionary = {}
## Refus affiché près du curseur.
var refusal := ""


func _init(view: MapElevation) -> void:
	ev = view


func ed() -> MapEditor:
	return ev.ed


func u(v: float) -> float:
	return EditorUi.px(v)


# ------------------------------------------------------------------ géométrie de la sélection

## L'élément choisi, projeté dans la vue ({} s'il n'y est pas ou est caché).
func sel() -> Dictionary:
	var e := ev.projected_of(ed().selected) if ed().selected != "" else {}
	if e.is_empty() or not ev.floor_shown(int(e.f)) or not ev.in_cut(e) or ev.plane == "dessous":
		return {}
	return e


## Point d'accroche des flèches (px) : le milieu de la boîte ; la hauteur de
## la lumière ou de l'effet pour un luminaire ou un effet.
func anchor_px(e: Dictionary) -> Vector2:
	var r := ev.rect_px(e)
	var it: Dictionary = e.it
	if it.has("z"):
		return Vector2(r.get_center().x, ev.to_px(Vector2(0, -float(it.z))).y)
	return r.get_center()


## Axe de la carte de l'axe horizontal de l'écran : « X » ou « Y ».
func h_letter() -> String:
	return String(MapView.h_axis(ev.plane)[0])


func h_sign() -> float:
	return float(MapView.h_axis(ev.plane)[1])


## Direction de la carte (plan) de l'axe horizontal de l'écran.
func h_dir() -> Vector2:
	return Vector2(h_sign(), 0) if h_letter() == "X" else Vector2(0, h_sign())


## L'élément peut-il glisser sur l'axe horizontal de la vue ? Une ouverture ou
## un objet mural seulement si son mur est face à la vue (parallèle à l'écran).
func can_h(e: Dictionary) -> bool:
	var o: Dictionary = e.it.e
	var t := String(o.get("type", ""))
	var wall_bound := t in MapRules.ouvertures_types() or MapCatalog.tool_of(o) == "wall_item"
	if not wall_bound:
		return true
	var dv := MapGeom.item_wall_dir(o) if not t in MapRules.ouvertures_types() else _opening_normal(o)
	return absf(dv.dot(h_dir())) < 0.3


func _opening_normal(o: Dictionary) -> Vector2:
	var poly := MapElevationItems.opening_poly(ed().doc, o)
	var along := (poly[1] - poly[0]).normalized()
	return Vector2(-along.y, along.x)


## Glissement vertical possible (hauteur de pose ou étage) ?
func can_v(e: Dictionary) -> bool:
	var o: Dictionary = e.it.e
	var kind := MapVertical.pose_kind(o)
	if kind == "fixe":
		return false
	if kind == "niveau":
		return ed().doc.floor_count() > 1
	return true


## Poignées de l'élément choisi : [{id (side_l, side_r, top), p (px), lock (cadenas)}].
func handles(e: Dictionary) -> Array:
	var out := []
	if e.is_empty():
		return out
	var o: Dictionary = e.it.e
	var r := ev.rect_px(e)
	var mid := r.get_center().y
	if _side_kind(o) != "":
		out.append({"id": "side_l", "p": Vector2(r.position.x, mid)})
		out.append({"id": "side_r", "p": Vector2(r.end.x, mid)})
	var top := _top_kind(o)
	if top != "":
		# Effet au plafond : sa zone pend sous le plafond, la poignée est en bas.
		var y := r.end.y if top == "zone" and MapCatalog.effect_mount(o) == "plafond" else r.position.y
		out.append({"id": "top", "p": Vector2(r.get_center().x, y), "lock": top == "lock"})
	return out


## Grandeur des poignées de côté : « room » (côtés d'une pièce rectangle),
## « mids » (zone d'un effet), « rect » (pilier, piège), « ends » (mur libre,
## effet mural), « width » (porte, débris, passage) ; "" : aucune.
func _side_kind(o: Dictionary) -> String:
	var t := String(o.get("type", ""))
	if o.has("contour"):
		var poly := ed().doc.room_poly(o)
		return "room" if MapGeom.is_axis_rect(poly) and not o.has("forme") else ""
	if t in ["porte", "debris", "passage"]:
		return "width" if absf(_opening_normal(o).dot(h_dir())) < 0.3 else ""
	if t in ["pilier", "piege"] and MapGeom.rot_of(o) == 0:
		return "rect"
	if t == "mur":
		var d := (MapGeom.v2(o.b) - MapGeom.v2(o.a)).normalized()
		return "ends" if absf(d.dot(h_dir())) > 0.99 else ""
	if t == "effet":
		if MapCatalog.effect_mount(o) == "mur":
			return "ends" if absf(MapGeom.item_wall_dir(o).dot(h_dir())) < 0.3 else ""
		return "mids" if MapGeom.rot_of(o) % 90 == 0 else ""
	return ""


## Poignée du haut : « ceiling » (plafond d'une pièce), « lock » (pièce en
## double hauteur : cadenas), « clip » (hauteur d'une barrière), « zone »
## (hauteur de la zone d'un effet) ; "" : aucune.
func _top_kind(o: Dictionary) -> String:
	if o.has("contour"):
		return "lock" if bool(o.get("double_hauteur", false)) else "ceiling"
	match String(o.get("type", "")):
		"bloc_invisible":
			return "clip"
		"effet":
			return "zone" if MapCatalog.effect_dims(String(o.get("effet", ""))).has("h") else ""
	return ""


## Cible sous le pixel `px` : flèches, carré central, poignées ; "" sinon.
func target_at(px: Vector2) -> String:
	var e := sel()
	if e.is_empty() or ed().tool() != "select":
		return ""
	for h in handles(e):
		if (h.p as Vector2).distance_to(px) <= u(7.0) + 2.0:
			return String(h.id)
	var o := anchor_px(e)
	if can_h(e) and Rect2(o + Vector2(u(ARROW_FROM), -u(5)), Vector2(u(ARROW_HEAD - ARROW_FROM + 2), u(10))).has_point(px):
		return "arrow_h"
	if can_v(e) and Rect2(o + Vector2(-u(5), -u(ARROW_HEAD + 6)), Vector2(u(10), u(ARROW_HEAD + 6 - 18))).has_point(px):
		return "arrow_v"
	if can_h(e) and can_v(e) and Rect2(o + Vector2(u(10), -u(28)), Vector2(u(13), u(13))).has_point(px):
		return "center"
	return ""


## Étiquette de niveau ou trait du plafond du dernier étage sous le pixel :
## « level:k » (sol de l'étage k ≥ 1), « topceil » ; "" sinon.
func level_at(px: Vector2) -> String:
	if ed().tool() != "select" or not MapView.is_elevation(ev.plane):
		return ""
	var doc := ed().doc
	for k in range(1, doc.floor_count()):
		var y := ev.to_px(Vector2(0, -doc.floor_sol(k))).y
		if Rect2(ev._ruler() + u(2), y - u(8), u(78), u(15)).has_point(px):
			return "level:%d" % k
	var top := doc.floor_count() - 1
	var yc := ev.to_px(Vector2(0, -(doc.floor_sol(top) + doc.floor_height(top)))).y
	if absf(px.y - yc) <= 4.0 and px.x > ev._ruler() + u(84):
		return "topceil"
	return ""


## Curseur de la souris selon ce qui est dessous (§ 6.3).
func cursor_at(px: Vector2) -> Control.CursorShape:
	if not drag.is_empty():
		match String(drag.kind):
			"move", "gmove":
				return Control.CURSOR_FORBIDDEN if drag.lock == "both" else Control.CURSOR_VSIZE if drag.lock == "v" else (Control.CURSOR_HSIZE if drag.lock == "h" else Control.CURSOR_MOVE)
			"side":
				return Control.CURSOR_HSIZE
		return Control.CURSOR_VSIZE
	var t := target_at(px)
	match t:
		"arrow_h", "side_l", "side_r":
			return Control.CURSOR_HSIZE
		"arrow_v", "top":
			return Control.CURSOR_VSIZE
		"center":
			return Control.CURSOR_MOVE
	if level_at(px) != "":
		return Control.CURSOR_VSIZE
	if ed().tool() == "select" and not ev.element_at(ev.to_m(px)).is_empty():
		return Control.CURSOR_MOVE
	return Control.CURSOR_ARROW


# ------------------------------------------------------------------ glissements

## Appui du bouton gauche (outil Sélection) : poignée, flèche, étiquette de
## niveau, sinon l'élément sous le curseur (choisi, puis glissé). Vrai si pris.
func press(px: Vector2) -> bool:
	ev.hover = ""
	ed().map_hovered("")
	# Sélection multiple : Maj + clic ajoute ou retire l'élément ; un élément
	# du groupe choisi : tout le groupe glisse (sur l'axe de la vue, et d'étage).
	if ed().canvas.shift_held():
		var sh := ev.element_at(ev.to_m(px))
		if not sh.is_empty():
			ed().toggle_selected(String(sh.id))
		return true
	if ed().group.size() >= 2:
		var gh := ev.element_at(ev.to_m(px))
		if not gh.is_empty() and ed().group.has(String(gh.id)):
			var pg := ev.projected_of(String(gh.id))
			if not pg.is_empty():
				_begin_group(pg)
				return true
	var t := target_at(px)
	var e := sel()
	if t in ["side_l", "side_r", "top"]:
		var h := handles(e).filter(func(x): return String(x.id) == t)
		if t == "top" and not h.is_empty() and bool(h[0].get("lock", false)):
			ed().set_status(Lang.t("Pièce en double hauteur : ouverte sur l'étage du dessus, pas de plafond à régler", "Double-height room: open to the floor above, no ceiling to set"))
			return true
		_begin(t if t == "top" else "side", e, {"which": t})
		return true
	if t in ["arrow_h", "arrow_v", "center"]:
		_begin("move", e, {"lock": {"arrow_h": "h", "arrow_v": "v"}.get(t, "")})
		return true
	var lv := level_at(px)
	if lv != "":
		var k := int(lv.substr(6)) if lv.begins_with("level:") else ed().doc.floor_count() - 1
		drag = {"kind": "level" if lv.begins_with("level:") else "topceil", "k": k, "start_m": ev.mouse_m, "snap": ed().doc.snapshot(), "moved": false,
			"v0": ed().doc.floor_sol(k) if lv.begins_with("level:") else ed().doc.floor_height(k)}
		return true
	# L'élément choisi d'abord (des boîtes se recouvrent en élévation).
	if not e.is_empty() and ev.rect_px(e).grow(3.0).has_point(px):
		_begin("move", e, {"lock": ""})
		return true
	var hit := ev.element_at(ev.to_m(px))
	ed().select(String(hit.get("id", "")))
	if hit.is_empty():
		return true
	var pe := ev.projected_of(String(hit.id))
	if not pe.is_empty():
		_begin("move", pe, {"lock": ""})
	return true


func _begin(kind: String, e: Dictionary, extra: Dictionary) -> void:
	var o: Dictionary = e.it.e
	var doc := ed().doc
	var v := ed().raster().v
	drag = {"kind": kind, "start_m": ev.mouse_m, "snap": doc.snapshot(), "orig": o.duplicate(true), "attached": ed().attached_to(o),
		"moved": false, "lock": "", "k0": int(o.get("etage", 0)), "rect0": ev.rect_px(e), "box0": e.duplicate()}
	drag.merge(extra, true)
	var k := int(o.get("etage", 0))
	drag["za0"] = doc.floor_sol(k) + (MapVertical.pose_z(doc, v, o) if MapVertical.pose_kind(o) == "pose" else 0.0)
	if kind == "top":
		drag["v0"] = _top_value(o)
	# Axes permis (un objet mural face à la vue ne quitte pas son mur, une
	# ouverture ne change pas d'étage) : verrou forcé ; « both » : immobile.
	drag["can_h"] = can_h(e)
	drag["can_v"] = can_v(e)
	drag["lock"] = _allowed_lock(String(drag.lock))
	entry = ""
	entering = false
	refusal = ""


## Glissement du GROUPE choisi depuis l'élément projeté `e` (MapGroup.move) :
## sur l'axe horizontal de la vue ; verticalement, la hauteur de pose si tous
## les éléments sont posés (décor, luminaires), sinon l'étage (aimanté sur
## les sols, comme une pièce).
func _begin_group(e: Dictionary) -> void:
	var o: Dictionary = e.it.e
	var doc := ed().doc
	var ids: Array = ed().group.duplicate()
	var z0 := {}
	if ids.all(func(i): return MapVertical.pose_kind(doc.find(String(i))) == "pose"):
		var v := ed().raster().v
		for i in ids:
			z0[String(i)] = MapVertical.pose_z(doc, v, doc.find(String(i)))
	drag = {"kind": "gmove", "start_m": ev.mouse_m, "snap": doc.snapshot(), "all": MapGroup.movers(doc, ids), "ids": ids,
		"click": String(o.id), "k0": int(o.get("etage", 0)), "z0": z0, "moved": false, "lock": "", "can_h": true,
		"can_v": not z0.is_empty() or doc.floor_count() > 1, "rect0": ev.rect_px(e), "box0": e.duplicate()}
	drag["lock"] = _allowed_lock("")
	entry = ""
	entering = false
	refusal = ""


## Mouvement du groupe : écart sur l'axe de la vue au pas de l'aimantation ;
## vertical : hauteur de pose (tous posés) ou étage le plus proche.
func _update_group() -> void:
	var doc := ed().doc
	var d := _delta()
	var dh := d.x * h_sign()
	if _typed() == null:
		dh = snappedf(dh, _step())
	var delta2 := Vector2(dh, 0.0) if h_letter() == "X" else Vector2(0.0, dh)
	var dz := -d.y
	var dk := 0
	var dzz := NAN
	var k0 := int(drag.k0)
	if not (drag.z0 as Dictionary).is_empty():
		dzz = dz if _typed() != null else snappedf(dz, _step())
	elif bool(drag.can_v):
		dk = MapVertical.nearest_floor(doc, doc.floor_sol(k0) + dz) - k0
	var res := MapGroup.move(ed(), drag.all, delta2, dk, drag.snap, dzz, drag.z0)
	if res.ok:
		refusal = ""
		drag.moved = drag.moved or delta2.length() > 0.001 or dk != 0 or (not is_nan(dzz) and absf(dzz) > 0.0005)
		drag["dh"] = dh
		drag["dz"] = dzz if not is_nan(dzz) else doc.floor_sol(k0 + dk) - doc.floor_sol(k0)
		drag["dk"] = dk
		ed().send_live(String(drag.click))
		var parts := []
		if absf(dh) > 0.0005:
			parts.append("Δ%s %s m" % [h_letter(), _signed(dh * h_sign())])
		if dk != 0:
			parts.append(Lang.t("étage %d → %d", "floor %d → %d") % [k0, k0 + dk])
		elif not is_nan(dzz) and absf(dzz) > 0.0005:
			parts.append("ΔZ %s m" % _signed(dzz))
		ed().set_status(Lang.t("Groupe de %d éléments", "Group of %d elements") % (drag.ids as Array).size()
			+ (" : " + " · ".join(parts) if not parts.is_empty() else "") + Lang.t(" · relâcher pour valider, Échap pour annuler", " · release to apply, Esc to cancel"))
	else:
		refusal = MapRules.why(res)
		ed().canvas.refusal_elems = [res.el] if res.get("el") is Dictionary else []


## Grandeur de la poignée du haut au début : plafond, hauteur de barrière ou de zone.
func _top_value(o: Dictionary) -> float:
	var k := int(o.get("etage", 0))
	if o.has("contour"):
		return float(o.get("plafond", ed().doc.floor_height(k)))
	if String(o.get("type", "")) == "bloc_invisible":
		return float(o.get("hauteur", MapVertical.top(ed().raster().v, k) - ed().doc.floor_sol(k)))
	return MapCatalog.effect_zone(o).z


## Verrou d'axe `want` ("", "h", "v") ramené aux axes permis du glissement.
func _allowed_lock(want: String) -> String:
	var ch := bool(drag.get("can_h", true))
	var cv := bool(drag.get("can_v", true))
	if not ch and not cv:
		return "both"
	if not ch:
		return "v"
	if not cv:
		return "h"
	return want


func dragging() -> bool:
	return not drag.is_empty()


## Carte entière remplacée (MapEditor._on_map_replaced) : le glissement est
## abandonné sans remettre sa carte de départ (l'ancienne carte).
func drop() -> void:
	if drag.is_empty():
		return
	ed().send_live("")
	drag = {}
	magnet = {}
	entry = ""
	entering = false
	refusal = ""
	ev.queue_redraw()


## Mouvement de la souris pendant un glissement.
func update() -> void:
	if drag.is_empty():
		return
	match String(drag.kind):
		"move":
			_update_move()
		"gmove":
			_update_group()
		"side":
			_update_side()
		"top":
			_update_top()
		"level", "topceil":
			_update_level()
	ev.queue_redraw()


## Écart (uv, m) depuis le début du glissement, axes verrouillés et valeur tapée compris.
func _delta() -> Vector2:
	var d: Vector2 = ev.mouse_m - Vector2(drag.start_m)
	match String(drag.get("lock", "")):
		"h":
			d.y = 0.0
		"v":
			d.x = 0.0
		"both":
			return Vector2.ZERO
	var typed: Variant = _typed()
	if typed != null:
		# Valeur tapée : l'écart sur l'axe verrouillé (vertical par défaut).
		if String(drag.get("lock", "")) == "h":
			d.x = float(typed) * h_sign()
		else:
			d = Vector2(d.x if drag.get("lock", "") == "" else 0.0, -float(typed))
	return d


func _typed() -> Variant:
	if entry == "":
		return null
	var s := entry.replace(",", ".")
	return float(s) if s.is_valid_float() else null


## Pas de l'aimantation courante (m) : grille 1 m, grille fine, libre (cm).
func _step() -> float:
	var mode := ed().canvas.mode_now()
	return 0.01 if mode == "libre" else ed().canvas.step()


func _update_move() -> void:
	var doc := ed().doc
	var orig: Dictionary = drag.orig
	var kind := MapVertical.pose_kind(orig)
	var d := _delta()
	# Horizontal : sur l'axe de la vue, au pas de l'aimantation.
	var dh := d.x * h_sign()
	if _typed() == null:
		dh = snappedf(dh, _step())
	var delta2 := Vector2(dh, 0.0) if h_letter() == "X" else Vector2(0.0, dh)
	# Vertical.
	var k0 := int(drag.k0)
	var k_new := k0
	var z_local := NAN
	magnet = {}
	var dz := -d.y
	match kind:
		"pose":
			var za := float(drag.za0) + dz
			var probe := MapEditor._shift(orig, delta2)
			if _typed() == null:
				za = _snap_z(za, k0, probe)
			# Sous le plafond réel de sa pièce (double hauteur, dernier étage
			# plus haut que l'étage) : il reste à son étage ; il n'en change
			# qu'en quittant ce volume.
			var sol0 := doc.floor_sol(k0)
			if za >= sol0 - 0.001 and za <= sol0 + MapVertical.room_h(ed().raster().v, probe) + 0.001:
				k_new = k0
			else:
				k_new = MapVertical.floor_at(doc, za)
			if k_new < 0:
				refusal = Lang.t("pas d'étage à cette hauteur", "no floor at that height")
				return
			z_local = za - doc.floor_sol(k_new)
		"niveau":
			k_new = MapVertical.nearest_floor(doc, doc.floor_sol(k0) + dz)
	var res := ed().try_move_3d(orig, drag.attached, delta2, k_new, z_local, drag.snap)
	if res.ok:
		refusal = ""
		drag.moved = drag.moved or delta2.length() > 0.001 or k_new != k0 or (not is_nan(z_local) and absf(z_local + doc.floor_sol(k_new) - float(drag.za0)) > 0.001)
		drag["dh"] = dh
		drag["dz"] = (z_local + doc.floor_sol(k_new) - float(drag.za0)) if not is_nan(z_local) else doc.floor_sol(k_new) - doc.floor_sol(k0)
		ed().send_live(String(orig.id))
		ed().panels.live_position(true)
		_status_move()
	else:
		refusal = MapRules.why(res)


## Altitude aimantée : aimant vertical proche (grille fine et libre), sinon
## la grille sur la hauteur au-dessus du sol de l'étage.
func _snap_z(za: float, k: int, probe: Dictionary) -> float:
	var doc := ed().doc
	var mode := ed().canvas.mode_now()
	if mode != "grille":
		var radius := MAGNET_PX / ev.zoom
		var best := {}
		# Aimants autour de l'élément là où il va (dessus du décor dessous).
		for m in MapVertical.magnets(doc, ed().raster().v, probe):
			if absf(float(m.z) - za) <= radius and (best.is_empty() or absf(float(m.z) - za) < absf(float(best.z) - za)):
				best = m
		if not best.is_empty():
			magnet = best
			return float(best.z)
	var kk := MapVertical.floor_at(doc, za)
	var sol := doc.floor_sol(kk if kk >= 0 else k)
	return sol + snappedf(za - sol, _step())


func _status_move() -> void:
	var o: Dictionary = drag.orig
	var fr := not Lang.is_en()
	var parts := []
	if absf(float(drag.get("dh", 0.0))) > 0.0005:
		parts.append("Δ%s %s%s m" % [h_letter(), "+" if float(drag.dh) * h_sign() >= 0.0 else "", m2(float(drag.dh) * h_sign())])
	var doc := ed().doc
	var now := doc.find(String(o.id))
	if MapVertical.pose_kind(o) == "pose" and not now.is_empty():
		var z0 := float(drag.za0) - doc.floor_sol(int(drag.k0))
		var z1 := MapVertical.pose_z(doc, ed().raster().v, now)
		ed().set_status(Lang.t("Déplacement vertical : %s → %s m (ΔZ %s) · relâcher pour valider, Échap pour annuler", "Vertical move: %s → %s m (ΔZ %s) · release to apply, Esc to cancel") % [
			m2(z0), m2(z1), _signed(float(drag.get("dz", 0.0)))] + ("  ·  " + " · ".join(parts) if not parts.is_empty() else ""))
	elif int(now.get("etage", 0)) != int(drag.k0):
		ed().set_status(Lang.t("Étage %d → %d · relâcher pour valider, Échap pour annuler", "Floor %d → %d · release to apply, Esc to cancel") % [int(drag.k0), int(now.etage)])
	elif not parts.is_empty():
		ed().set_status(" · ".join(parts) + Lang.t(" · relâcher pour valider, Échap pour annuler", " · release to apply, Esc to cancel"))


## Longueur au centimètre, à la française (2 décimales, comme la maquette).
static func m2(v: float) -> String:
	return MapView.num(v, 2)


static func _signed(v: float) -> String:
	return ("+" if v >= 0.0 else "−") + m2(absf(v))


## Poignée de côté : la grandeur sur l'axe de la vue (pièce, zone d'effet,
## pilier, piège, mur, largeur d'une ouverture).
func _update_side() -> void:
	var orig: Dictionary = drag.orig
	var doc := ed().doc
	var left := String(drag.which) == "side_l"
	var p3 := MapView.point_of(ev.plane, ev.mouse_m, 0.0)
	var axis := h_letter()
	var cur := p3.x if axis == "X" else p3.y
	if _typed() == null:
		cur = snappedf(cur, _step())
	# Le bord tiré : le plus petit (gauche de l'écran si h_sign > 0) ou le plus grand.
	var want_min := left == (h_sign() > 0.0)
	var res := {}
	match _side_kind(orig):
		"width":
			var c := MapGeom.v2(orig.position)
			var half := absf(cur - (c.x if axis == "X" else c.y))
			var w := clampf(snappedf(half * 2.0, 0.5), 1.0, 6.0)
			doc.restore(drag.snap)
			res = MapRules.place_opening(doc, int(orig.etage), String(orig.type), c, w, String(orig.id))
			if res.ok:
				var o := doc.find(String(orig.id))
				o["largeur"] = w
				o["position"] = res.position
				ed().moved_live()
				drag["value"] = w
		"rect":
			var r := MapGeom.rect_of(orig.rect)
			var lo := r.position.x if axis == "X" else r.position.y
			var hi := r.end.x if axis == "X" else r.end.y
			if want_min:
				lo = minf(cur, hi - 0.5)
			else:
				hi = maxf(cur, lo + 0.5)
			var nr := Rect2(Vector2(lo, r.position.y), Vector2(hi - lo, r.size.y)) if axis == "X" else Rect2(Vector2(r.position.x, lo), Vector2(r.size.x, hi - lo))
			res = MapRules.check_rect(doc, int(orig.etage), String(orig.type), nr, String(orig.id))
			if res.ok:
				doc.restore(drag.snap)
				var o := doc.find(String(orig.id))
				o["rect"] = MapGeom.rect_arr(nr)
				ed().moved_live()
				drag["value"] = hi - lo
		_:
			# Pièce rectangle, zone d'effet, mur libre, effet mural : la poignée du
			# plan (MapCanvas.handles) la plus à gauche / à droite sur l'axe.
			var hs := ed().canvas.handles()
			var idx := -1
			var best := INF if want_min else -INF
			var only_mids := _side_kind(orig) in ["room", "mids"]
			for i in hs.size():
				if only_mids and i < 4:
					continue
				var c := hs[i].x if axis == "X" else hs[i].y
				if (want_min and c < best) or (not want_min and c > best):
					best = c
					idx = i
			if idx < 0:
				return
			var p := hs[idx]
			if axis == "X":
				p.x = cur
			else:
				p.y = cur
			res = ed().try_handle(orig, idx, p, drag.snap)
			if res.ok:
				var o := doc.find(String(orig.id))
				var bb := MapRules.footprint_rect(o) if not o.has("contour") else MapGeom.bbox(doc.room_poly(o))
				drag["value"] = bb.size.x if axis == "X" else bb.size.y
	if res.get("ok", false):
		drag.moved = true
		refusal = ""
		ed().send_live(String(orig.id))
		ed().set_status(Lang.t("Largeur sur l'axe %s : %s m · relâcher pour valider", "Width on the %s axis: %s m · release to apply") % [axis, m2(float(drag.get("value", 0.0)))])
	elif not res.is_empty():
		refusal = MapRules.why(res)


## Poignée du haut : plafond d'une pièce (aimanté sur le plafond de l'étage et
## le dessous de la dalle du dessus), hauteur d'une barrière ou d'une zone.
func _update_top() -> void:
	var orig: Dictionary = drag.orig
	var doc := ed().doc
	var k := int(orig.etage)
	var sol := doc.floor_sol(k)
	var h := -ev.mouse_m.y - sol
	var typed: Variant = _typed()
	if typed != null:
		h = float(drag.v0) + float(typed)
	elif ed().canvas.mode_now() != "grille":
		var radius := MAGNET_PX / ev.zoom
		magnet = {}
		for m in MapVertical.magnets(doc, ed().raster().v, orig):
			if absf(float(m.z) - sol - h) <= radius:
				magnet = m
				h = float(m.z) - sol
				break
		if magnet.is_empty():
			h = snappedf(h, _step())
	else:
		h = snappedf(h, _step())
	doc.restore(drag.snap)
	var o := doc.find(String(orig.id))
	var res := {"ok": true}
	if orig.has("contour"):
		var lim := MapVertical.ceiling_max(doc, ed().raster().v, orig)
		h = clampf(h, MapVertical.ROOM_CEILING[0], lim)
		if absf(h - doc.floor_height(k)) < 0.005:
			o.erase("plafond")
		else:
			o["plafond"] = snappedf(h, 0.01)
		drag["limit"] = lim
	elif String(orig.get("type", "")) == "bloc_invisible":
		h = clampf(snappedf(h, MapCatalog.CLIP_HEIGHT_STEP), MapCatalog.CLIP_HEIGHT[0], MapCatalog.CLIP_HEIGHT[1])
		o["hauteur"] = h
	else:
		# Hauteur de la zone, comme elle est dessinée (MapElevationItems._effect) :
		# au sol, du pied au haut ; murale, centrée sur sa hauteur ; au
		# plafond, pendue sous lui (poignée en bas).
		var z := MapCatalog.effect_zone(o)
		var eh := MapCatalog.effect_height(o)
		if typed != null:
			z.z = float(drag.v0) + float(typed)
		else:
			match MapCatalog.effect_mount(o):
				"mur":
					z.z = 2.0 * (h - eh)
				"plafond":
					z.z = MapVertical.pose_z(doc, ed().raster().v, o) - h
				_:
					z.z = h - eh
		MapCatalog.set_effect_zone(o, z)
		h = MapCatalog.effect_zone(o).z
	drag["value"] = h
	drag.moved = true
	ed().moved_live()
	ed().send_live(String(orig.id))
	if orig.has("contour"):
		ed().set_status(Lang.t("Plafond de « %s » : %s → %s m (%s) · relâcher pour valider", "Ceiling of \"%s\": %s → %s m (%s) · release to apply") % [
			String(orig.get("nom", "")), m2(float(drag.v0)), m2(h), _signed(h - float(drag.v0))])
	refusal = "" if res.ok else MapRules.why(res)


## Étiquette de niveau : sol de l'étage k (au moins 3,1 m des voisins) ;
## trait du plafond du dernier étage : sa hauteur.
func _update_level() -> void:
	var doc := ed().doc
	var k := int(drag.k)
	var z := -ev.mouse_m.y
	var typed: Variant = _typed()
	doc.restore(drag.snap)
	var f: Array = doc.carte.etages
	var gap := MapValidator.MIN_CEILING + MapValidator.DALLE
	if drag.kind == "level":
		var v := float(drag.v0) + float(typed) if typed != null else snappedf(z, maxf(_step(), 0.1))
		var lo := doc.floor_sol(k - 1) + gap
		var hi := doc.floor_sol(k + 1) - gap if k + 1 < doc.floor_count() else 200.0
		v = clampf(v, lo, maxf(lo, hi))
		f[k]["sol"] = snappedf(v, 0.01)
		drag["value"] = v
		ed().set_status(Lang.t("Sol de l'étage %d : %s m (au moins %s m au-dessus de l'étage %d)", "Floor %d level: %s m (at least %s m above floor %d)") % [
			k, m2(v), m2(gap), k - 1])
	else:
		var h := float(drag.v0) + float(typed) if typed != null else snappedf(z - doc.floor_sol(k), maxf(_step(), 0.1))
		h = clampf(h, MapValidator.MIN_CEILING, 10.0)
		f[k]["hauteur"] = snappedf(h, 0.01)
		drag["value"] = h
		ed().set_status(Lang.t("Hauteur du dernier étage : %s m", "Top floor height: %s m") % m2(h))
	drag.moved = true
	ed().moved_live()


## Relâché : une étape d'annulation si quelque chose a bougé.
func release() -> void:
	if drag.is_empty():
		return
	ed().send_live("")
	if String(drag.kind) == "gmove":
		# Groupe : une étape d'annulation s'il a bougé ; sinon (simple clic sur
		# un de ses éléments) cet élément seul est choisi.
		var g := drag
		drag = {}
		if g.moved:
			ed().push_undo_snapshot(g.snap)
			ed().changed()
		else:
			ed().select(String(g.click))
		magnet = {}
		entry = ""
		entering = false
		refusal = ""
		ev.queue_redraw()
		return
	var moved_floor := false
	if drag.moved:
		ed().push_undo_snapshot(drag.snap)
		ed().changed()
		if String(drag.kind) == "move":
			var now := ed().doc.find(String(drag.orig.id))
			moved_floor = not now.is_empty() and int(now.get("etage", 0)) != int(drag.k0)
	var oid := String(drag.get("orig", {}).get("id", ""))
	drag = {}
	if moved_floor:
		# Changé d'étage : l'étage courant le suit (plan du dessus, panneaux).
		ed().select(oid)
	magnet = {}
	entry = ""
	entering = false
	ev.queue_redraw()


## Échap / clic droit : la carte d'avant le glissement revient.
func cancel() -> void:
	if drag.is_empty():
		return
	ed().send_live("")
	ed().doc.restore(drag.snap)
	ed().changed(false)
	ed().panels.live_position(false)
	drag = {}
	magnet = {}
	entry = ""
	entering = false
	refusal = ""
	ev.queue_redraw()


## Touches pendant un glissement : X / Y / Z (verrou d'axe), chiffres et Tab
## (valeur), Entrée (appliquer la valeur), Échap (annuler). Vrai si prise.
func handle_key(k: InputEventKey) -> bool:
	if drag.is_empty() or not k.pressed:
		return false
	match k.keycode:
		KEY_ESCAPE:
			cancel()
			return true
		KEY_TAB:
			entering = true
			entry = ""
			ev.queue_redraw()
			return true
		KEY_ENTER, KEY_KP_ENTER:
			if entry != "":
				update()
				release()
			return true
		KEY_BACKSPACE:
			entry = entry.left(entry.length() - 1)
			update()
			return true
		KEY_X, KEY_Y, KEY_Z:
			if not String(drag.kind) in ["move", "gmove"]:
				return true
			var letter := OS.get_keycode_string(k.keycode)
			var lk := "v" if letter == "Z" else ("h" if letter == h_letter() else "")
			if lk == "":
				ed().set_status(Lang.t("Axe %s : celui de la profondeur dans cette vue", "%s axis: the depth axis in this view") % letter)
				return true
			if not bool(drag.get("can_h" if lk == "h" else "can_v", true)):
				ed().set_status(Lang.t("Cet élément ne bouge pas sur l'axe %s dans cette vue", "This element cannot move on the %s axis in this view") % letter)
				return true
			drag["lock"] = _allowed_lock("" if drag.lock == lk else lk)
			update()
			return true
	var ch := MapCanvas._entry_char(k)
	if ch != "" and (entering or ch in ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "-"]):
		if ch == "-" and entry != "":
			return true
		if ch == "." and entry.contains("."):
			return true
		entry += ch
		entering = true
		update()
		return true
	return false


# ------------------------------------------------------------------ dessin (couche du dessus)

func draw(c: CanvasItem) -> void:
	var e := sel()
	if not drag.is_empty() and String(drag.kind) in ["level", "topceil"]:
		_draw_level_drag(c)
	if not drag.is_empty() and String(drag.kind) == "gmove":
		# Groupe glissé : place d'avant de l'élément tenu en pointillés, refus.
		if drag.moved:
			_dashed_rect(c, ev.rect_px(drag.box0), Color(COL_BONE, 0.55), 1.0)
		_draw_refusal(c)
		return
	if e.is_empty():
		return
	var r := ev.rect_px(e)
	var o := anchor_px(e)
	var moving := not drag.is_empty() and String(drag.kind) == "move"
	# Fantôme : la position d'avant, en pointillés.
	if not drag.is_empty() and drag.moved and String(drag.kind) == "move":
		var g: Rect2 = ev.rect_px(drag.box0)
		_dashed_rect(c, g, Color(COL_BONE, 0.55), 1.0)
	# Aimant vertical actif : trait bleu et son nom.
	if not magnet.is_empty():
		var my := ev.to_px(Vector2(0, -float(magnet.z))).y
		c.draw_dashed_line(Vector2(ev._ruler(), my), Vector2(ev.size.x, my), Color(COL_MAGNET, 0.55), 1.0, u(2))
		var lbl := String(magnet.label)
		var font := UiStyle.font("body")
		var fs := MapView._fs(10.5)
		var w := font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + u(12)
		var mr := Rect2(ev._ruler() + u(80), my - u(8), w, u(15))
		MapElevation._round_rect(c, mr, Color("0f2a33"), COL_MAGNET)
		c.draw_string(font, Vector2(mr.position.x + u(6), my + u(3.5)), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("bff4ff"))
	# Trait de guide de l'axe verrouillé.
	if moving and String(drag.lock) == "v":
		c.draw_dashed_line(Vector2(o.x, ev._ruler()), Vector2(o.x, ev.size.y), Color(MapView.COL_Z, 0.35), 1.0, u(8))
	elif moving and String(drag.lock) == "h":
		c.draw_dashed_line(Vector2(ev._ruler(), o.y), Vector2(ev.size.x, o.y), Color(MapView.axis_color(h_letter()), 0.35), 1.0, u(8))
	# Contour de la sélection (fait par MapElevation) ; poignées.
	for h in handles(e):
		var p: Vector2 = h.p
		if String(h.id) == "top":
			_diamond(c, p, bool(h.get("lock", false)), not drag.is_empty() and String(drag.kind) == "top")
		else:
			_square(c, p)
	if not offscreen_tools() and (drag.is_empty() or String(drag.kind) == "move"):
		_draw_arrows(c, e, o)
	if moving and drag.moved:
		_draw_move_cotes(c, e, o)
	elif not drag.is_empty() and String(drag.kind) == "top" and drag.moved:
		_draw_top_cotes(c, e, r)
	_draw_refusal(c)


func offscreen_tools() -> bool:
	return ev.offscreen or ed().tool() != "select"


## Flèches d'axe (36 px) et carré central ; celle de l'axe verrouillé plus
## épaisse, l'autre estompée.
func _draw_arrows(c: CanvasItem, e: Dictionary, o: Vector2) -> void:
	var lock := String(drag.get("lock", "")) if not drag.is_empty() else ""
	var hc := MapView.axis_color(h_letter())
	if can_h(e):
		var a := 0.5 if lock == "v" else 1.0
		var w := 3.0 if lock == "h" else 2.2
		c.draw_line(o + Vector2(u(ARROW_FROM), 0), o + Vector2(u(ARROW_TO), 0), Color(hc, a), w)
		var tip := o + Vector2(u(ARROW_HEAD), 0)
		c.draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-u(8), -u(4.5)), tip + Vector2(-u(8), u(4.5))]), Color(hc, a))
	if can_v(e):
		var a := 0.5 if lock == "h" else 1.0
		var w := 3.0 if lock == "v" else 2.2
		c.draw_line(o + Vector2(0, -u(18)), o + Vector2(0, -u(48)), Color(MapView.COL_Z, a), w)
		var tip := o + Vector2(0, -u(57))
		var head := PackedVector2Array([tip, tip + Vector2(u(5.5), u(10)), tip + Vector2(-u(5.5), u(10))])
		c.draw_colored_polygon(head, Color(MapView.COL_Z, a))
		if lock == "v":
			c.draw_polyline(head + PackedVector2Array([head[0]]), Color("cfe0ff"), 1.0)
	if can_h(e) and can_v(e):
		var sq := Rect2(o + Vector2(u(12), -u(26)), Vector2(u(9), u(9)))
		c.draw_rect(sq, Color(hc, 0.35))
		c.draw_rect(sq, Color(MapView.COL_Z, 0.7), false, 1.0)


## Cotes d'un déplacement (§ 6.3) : hauteur au-dessus du sol de l'étage,
## distance au mur le plus proche sur l'axe de la vue, écart en or.
func _draw_move_cotes(c: CanvasItem, e: Dictionary, o: Vector2) -> void:
	var doc := ed().doc
	var now := doc.find(String(e.it.id))
	if now.is_empty():
		return
	var k := int(now.get("etage", 0))
	var font := UiStyle.font("body")
	var bf := MapView.bold_font(600)
	var y0 := ev.to_px(Vector2(0, -doc.floor_sol(k))).y
	var pose := MapVertical.pose_kind(now) == "pose"
	if pose:
		# Hauteur au-dessus du sol : trait de cote vertical, flèches, pastille.
		var cx := o.x - u(34)
		c.draw_line(Vector2(cx - u(6), y0), Vector2(o.x - u(12), y0), Color(COL_BONE, 0.6), 1.0)
		c.draw_line(Vector2(cx - u(6), o.y), Vector2(o.x - u(12), o.y), Color(COL_BONE, 0.6), 1.0)
		c.draw_line(Vector2(cx, y0 - 1), Vector2(cx, o.y + 1), COL_BONE, 1.0)
		var dirv := 1.0 if y0 > o.y else -1.0
		c.draw_colored_polygon(PackedVector2Array([Vector2(cx, o.y), Vector2(cx - u(3.5), o.y + u(7) * dirv), Vector2(cx + u(3.5), o.y + u(7) * dirv)]), COL_BONE)
		c.draw_colored_polygon(PackedVector2Array([Vector2(cx, y0), Vector2(cx - u(3.5), y0 - u(7) * dirv), Vector2(cx + u(3.5), y0 - u(7) * dirv)]), COL_BONE)
		var hz := MapVertical.pose_z(doc, ed().raster().v, now)
		var t := "%s m" % m2(hz)
		var mid := (y0 + o.y) * 0.5
		var pr := Rect2(cx - u(26), mid - u(9), u(52), u(18))
		MapElevation._round_rect(c, pr, COL_CHIP, COL_CHIP_LINE)
		var tw := bf.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, EditorUi.fs(12)).x
		c.draw_string(bf, Vector2(cx - tw * 0.5, mid + u(4)), t, HORIZONTAL_ALIGNMENT_LEFT, -1, EditorUi.fs(12), COL_BONE)
	# Distance au mur le plus proche sur l'axe de la vue.
	var wall := _nearest_wall(now)
	if not wall.is_empty():
		var yy := o.y - u(26)
		var xw := ev.to_px(Vector2(float(wall.u), 0)).x
		var xe := o.x - 1.0
		var s := 1.0 if xe > xw else -1.0
		c.draw_line(Vector2(xw, yy), Vector2(xe, yy), Color(COL_BONE, 0.75), 1.0)
		c.draw_colored_polygon(PackedVector2Array([Vector2(xw, yy), Vector2(xw + u(7) * s, yy - u(3.5)), Vector2(xw + u(7) * s, yy + u(3.5))]), Color(COL_BONE, 0.75))
		c.draw_colored_polygon(PackedVector2Array([Vector2(xe, yy), Vector2(xe - u(7) * s, yy - u(3.5)), Vector2(xe - u(7) * s, yy + u(3.5))]), Color(COL_BONE, 0.75))
		var t := "%s m" % m2(float(wall.d))
		var fs := EditorUi.fs(11)
		var tw := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var cr := Rect2((xw + xe) * 0.5 - u(24), yy - u(17), u(48), u(15))
		MapElevation._round_rect(c, cr, COL_CHIP, COL_CHIP_LINE)
		c.draw_string(font, Vector2((xw + xe) * 0.5 - tw * 0.5, yy - u(6)), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("CFC9B8"))
	# Écart près du curseur, en or.
	var parts := []
	if absf(float(drag.get("dh", 0.0))) > 0.0005:
		parts.append("Δ%s %s m" % [h_letter(), _signed(float(drag.dh) * h_sign())])
	if absf(float(drag.get("dz", 0.0))) > 0.0005:
		parts.append("ΔZ %s m" % _signed(float(drag.dz)))
	if not parts.is_empty():
		var t := " · ".join(parts)
		var mx := o.x + u(30)
		var my := o.y - u(40)
		var fs := EditorUi.fs(12)
		var bf7 := MapView.bold_font(700)
		var tw := bf7.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		MapElevation._round_rect(c, Rect2(mx, my - u(13), tw + u(14), u(19)), Color("2b2410"), COL_GOLD)
		c.draw_string(bf7, Vector2(mx + u(6), my + u(1)), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, COL_GOLD)
		var lock := String(drag.lock)
		var hint := ""
		if entering:
			hint = Lang.t("valeur tapée : %s m · Entrée", "typed value: %s m · Enter") % (entry.replace(".", ",") if not Lang.is_en() else entry)
		elif lock == "v":
			hint = Lang.t("Z verrouillé · Tab : valeur", "Z locked · Tab: value")
		elif lock == "h":
			hint = Lang.t("%s verrouillé · Tab : valeur", "%s locked · Tab: value") % h_letter()
		else:
			hint = Lang.t("%s / Z : verrouiller · Tab : valeur", "%s / Z: lock · Tab: value") % h_letter()
		c.draw_string(font, Vector2(mx + tw + u(20), my + u(1)), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, MapView._fs(10.5), Color("8C8575"))


## Mur le plus proche de l'élément sur l'axe de la vue (côté de sa pièce,
## face intérieure) : {u (coordonnée de l'écran du mur), d (m)} ; {} sans pièce.
func _nearest_wall(o: Dictionary) -> Dictionary:
	var doc := ed().doc
	var k := int(o.get("etage", 0))
	var p := MapVertical.anchor_of(o) if o.has("position") else MapRules.footprint_rect(o).get_center()
	if o.has("contour"):
		return {}
	var room := MapRules.room_at(doc, k, p)
	if room.is_empty():
		return {}
	var bb := MapGeom.bbox(doc.room_poly(room)).grow(-MapGeom.WALL_HALF)
	var axis := h_letter()
	var c := p.x if axis == "X" else p.y
	var lo := bb.position.x if axis == "X" else bb.position.y
	var hi := bb.end.x if axis == "X" else bb.end.y
	var w := lo if absf(c - lo) <= absf(hi - c) else hi
	var p3 := Vector3(w, p.y, 0) if axis == "X" else Vector3(p.x, w, 0)
	return {"u": MapView.uv_of(ev.plane, p3).x, "d": absf(c - w)}


## Cotes de la poignée du haut : ancien contour en pointillés, cote, écart, règle vérifiée.
func _draw_top_cotes(c: CanvasItem, e: Dictionary, r: Rect2) -> void:
	var g: Rect2 = drag.rect0
	_dashed_rect(c, g, Color(COL_BONE, 0.55), 1.0)
	var orig: Dictionary = drag.orig
	var doc := ed().doc
	var k := int(orig.etage)
	var y0 := ev.to_px(Vector2(0, -doc.floor_sol(k))).y
	var top := r.position.y
	var cx := r.end.x - u(22)
	var bf := MapView.bold_font(600)
	c.draw_line(Vector2(cx, top + 1), Vector2(cx, y0 - 1), COL_BONE, 1.0)
	c.draw_colored_polygon(PackedVector2Array([Vector2(cx, top), Vector2(cx - u(3.5), top + u(7)), Vector2(cx + u(3.5), top + u(7))]), COL_BONE)
	c.draw_colored_polygon(PackedVector2Array([Vector2(cx, y0), Vector2(cx - u(3.5), y0 - u(7)), Vector2(cx + u(3.5), y0 - u(7))]), COL_BONE)
	var fr := not Lang.is_en()
	var name := Lang.t("Plafond", "Ceiling") if orig.has("contour") else (Lang.t("Hauteur de zone", "Zone height") if String(orig.get("type", "")) == "effet" else Lang.t("Hauteur", "Height"))
	var t := "%s %s m" % [name, m2(float(drag.get("value", 0.0)))]
	var fs := EditorUi.fs(12)
	var tw := bf.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var mid := (top + y0) * 0.5
	MapElevation._round_rect(c, Rect2(cx - tw - u(20), mid - u(10), tw + u(12), u(19)), COL_CHIP, COL_CHIP_LINE)
	c.draw_string(bf, Vector2(cx - tw - u(14), mid + u(4)), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, COL_BONE)
	var d := _signed(float(drag.get("value", 0.0)) - float(drag.v0)) + " m"
	var bf7 := MapView.bold_font(700)
	var dw := bf7.get_string_size(d, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var mx := r.get_center().x + u(14)
	MapElevation._round_rect(c, Rect2(mx, top - u(27), dw + u(12), u(19)), Color("2b2410"), COL_GOLD)
	c.draw_string(bf7, Vector2(mx + u(6), top - u(13)), d, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, COL_GOLD)
	if orig.has("contour"):
		# Règle vérifiée en direct : ce qu'il y a au-dessus.
		var lim := float(drag.get("limit", MapVertical.ROOM_CEILING[1]))
		var free := lim >= MapVertical.ROOM_CEILING[1] - 0.001
		var msg := (Lang.t("✔ Rien au-dessus (étage %d) : jusqu'à %s m", "✔ Nothing above (floor %d): up to %s m") % [k + 1, m2(lim)]) if free \
			else (Lang.t("Dalle de l'étage %d au-dessus : jusqu'à %s m", "Floor %d slab above: up to %s m") % [k + 1, m2(lim)])
		var font := UiStyle.font("body")
		var mw := font.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, EditorUi.fs(11)).x + u(12)
		var br := Rect2(r.position.x, top - u(62), mw, u(19))
		MapElevation._round_rect(c, br, Color(18 / 255.0, 30 / 255.0, 20 / 255.0, 0.92) if free else Color(40 / 255.0, 28 / 255.0, 16 / 255.0, 0.92), Color("2f6b3a") if free else Color("8a6a2f"))
		c.draw_string(font, Vector2(br.position.x + u(6), br.position.y + u(13)), msg, HORIZONTAL_ALIGNMENT_LEFT, -1, EditorUi.fs(11), Color("9be8a8") if free else Color("f2d49b"))


## Étiquette de niveau tirée : trait du nouveau sol et sa valeur.
func _draw_level_drag(c: CanvasItem) -> void:
	var doc := ed().doc
	var k := int(drag.k)
	var z := doc.floor_sol(k) if drag.kind == "level" else doc.floor_sol(k) + doc.floor_height(k)
	var y := ev.to_px(Vector2(0, -z)).y
	c.draw_line(Vector2(ev._ruler(), y), Vector2(ev.size.x, y), Color(COL_GOLD, 0.8), 1.5)


func _draw_refusal(c: CanvasItem) -> void:
	if refusal == "" or drag.is_empty():
		return
	var font := UiStyle.font("body")
	var fs := EditorUi.fs(13)
	var p := ev.to_px(ev.mouse_m) + Vector2(u(16), u(22))
	var w := font.get_string_size(refusal, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	p.x = minf(p.x, ev.size.x - w - u(12))
	var rr := Rect2(p + Vector2(-u(6), -u(15)), Vector2(w + u(12), u(21)))
	c.draw_rect(rr, Color(0.15, 0.02, 0.02, 0.92))
	c.draw_rect(rr, Color(1.0, 0.25, 0.2), false, 1.0)
	c.draw_string(font, p, refusal, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 0.85, 0.8))


## Poignée carrée (7 px, jaune bordé de noir).
func _square(c: CanvasItem, p: Vector2) -> void:
	var s := u(7)
	var r := Rect2(p - Vector2(s, s) * 0.5, Vector2(s, s))
	c.draw_rect(r, MapView.COL_SEL)
	c.draw_rect(r, Color.BLACK, false, 1.0)


## Poignée de hauteur en losange ; cadenas (double hauteur) ; bord blanc tirée.
func _diamond(c: CanvasItem, p: Vector2, locked: bool, active: bool) -> void:
	var s := u(6)
	var pts := PackedVector2Array([p + Vector2(0, -s), p + Vector2(s, 0), p + Vector2(0, s), p + Vector2(-s, 0)])
	if locked:
		var body := Rect2(p + Vector2(-u(5), -u(1)), Vector2(u(10), u(8)))
		c.draw_arc(p + Vector2(0, -u(1)), u(3.5), PI, TAU, 10, MapView.COL_SEL, 1.5)
		c.draw_rect(body, MapView.COL_SEL)
		c.draw_rect(body, Color.BLACK, false, 1.0)
		return
	c.draw_colored_polygon(pts, MapView.COL_SEL)
	c.draw_polyline(pts + PackedVector2Array([pts[0]]), Color.WHITE if active else Color.BLACK, 1.5 if active else 1.0)


func _dashed_rect(c: CanvasItem, r: Rect2, col: Color, w: float) -> void:
	var p := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	for i in 4:
		c.draw_dashed_line(p[i], p[(i + 1) % 4], col, w, u(5))
