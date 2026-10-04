class_name MapGizmoTop
extends RefCounted
## Poignées d'échelle et anneau Z de la vue Dessus (format 14,
## docs/EDITOR_SCALE_ROTATE.md § 2.4, § 3.2 ; maquette, écrans 1 et 3) pour
## le décor choisi seul :
##   - coins jaunes (échelle uniforme, coin opposé fixe ; Alt : le centre),
##     faces X rouges et Y vertes (un axe, côté opposé fixe), sur le rectangle
##     orienté ; incliné : coins de son emprise seulement ;
##   - prefab qui contient un objet de jeu : cadenas gris aux coins, curseur
##     interdit et bulle qui nomme l'objet au survol ;
##   - anneau Z bleu (prise au nord) à la place de la poignée ronde pour le
##     décor, les luminaires et les effets : crans de 15°, Maj ou Alt : libre ;
##   - pendant un geste : contour d'avant en pointillés, point fixe, cotes,
##     facteur ou angle en or près du curseur, aimant en bleu, hauteur « H »,
##     flèches et anneau estompés, valeur tapée au clavier, barre d'état.
## Un geste = une étape d'annulation (au relâché) ; Échap annule.

## Anneaux de rotation (§ 3.2) : à la place de la poignée ronde du décor,
## des luminaires et des effets.
const RINGS := true

var cv: MapCanvas
## Cadenas survolé (indice du coin, -1 : aucun).
var hover_lock := -1


func _init(canvas: MapCanvas) -> void:
	cv = canvas


func ed() -> MapEditor:
	return cv.ed


func u(v: float) -> float:
	return EditorUi.px(v)


## Décor choisi seul, à l'étage affiché, outil Sélection ({} sinon).
func target() -> Dictionary:
	if cv.offscreen or ed().tool() != "select" or ed().group.size() >= 2:
		return {}
	var e := ed().doc.find(ed().selected)
	if e.is_empty() or int(e.get("etage", 0)) != ed().floor_k:
		return {}
	return e


## L'élément a-t-il l'anneau Z (décor, luminaire, effet qui tournent ;
## format 15 : boîte mystère posée au sol) ?
static func has_ring(e: Dictionary) -> bool:
	if not RINGS or e.is_empty() or not (MapCatalog.is_decor(e) or MapCatalog.floor_box(e)) or not MapTransform.can_rotate(e):
		return false
	return MapCatalog.tool_of(e) != "wall_item" and MapVertical.mount_of(e) != "mur"


## Anneau Z de l'élément : {c (px), r (px)} ; {} sans anneau.
func ring_of(e: Dictionary) -> Dictionary:
	if not has_ring(e):
		return {}
	return {"c": cv.to_px(MapTransform.pivot(ed().doc, e)), "r": MapGizmo.ring_radius(e, cv.zoom, EditorUi.factor())}


## Poignées d'échelle (px) : [{id, p, kind, axis, side, corner, lock}].
func handles_of(e: Dictionary) -> Array:
	if String(e.get("type", "")) != "prefab" or MapScale.def_of(e).is_empty():
		return []
	var blocked := not MapScale.scalable(e)
	var out := []
	for h in MapGizmo.top_handles(e):
		if blocked and h.kind != "corner":
			continue
		var q: Dictionary = h.duplicate()
		q["m"] = h.p
		q["p"] = cv.to_px(h.p)
		q["lock"] = blocked
		out.append(q)
	return out


## Cible sous le pixel : {kind: « scale » | « lock » | « ring », ...} ; {} sinon.
func hit(px: Vector2) -> Dictionary:
	var e := target()
	if e.is_empty():
		return {}
	for h in handles_of(e):
		if (h.p as Vector2).distance_to(px) <= u(7) + 2.0:
			return {"kind": "lock" if h.lock else "scale", "h": h}
	var rg := ring_of(e)
	if not rg.is_empty():
		var d := (px - Vector2(rg.c)).length()
		var grip := Vector2(rg.c) + Vector2(0, -float(rg.r))
		if px.distance_to(grip) <= u(8) or absf(d - float(rg.r)) <= u(MapGizmo.RING_BAND) * 0.5 + 1.0:
			return {"kind": "ring", "c": rg.c, "r": rg.r}
	return {}


func cursor(px: Vector2) -> int:
	if cv.drag.get("kind", "") == "ring":
		return Control.CURSOR_POINTING_HAND
	if cv.drag.get("kind", "") == "scale":
		return Control.CURSOR_FDIAGSIZE
	var t := hit(px)
	hover_lock = -1
	match String(t.get("kind", "")):
		"lock":
			hover_lock = int(String(t.h.id).substr(1))
			return Control.CURSOR_FORBIDDEN
		"scale":
			var h: Dictionary = t.h
			if h.kind == "face":
				var d: Vector2 = (h.p as Vector2) - cv.to_px(MapGizmo.frame(target()).c)
				return Control.CURSOR_HSIZE if absf(d.x) > absf(d.y) else Control.CURSOR_VSIZE
			var dd: Vector2 = (h.p as Vector2) - cv.to_px(MapGizmo.frame(target()).c)
			return Control.CURSOR_FDIAGSIZE if dd.x * dd.y > 0.0 else Control.CURSOR_BDIAGSIZE
		"ring":
			return Control.CURSOR_POINTING_HAND
	return -1


# ------------------------------------------------------------------ gestes

## Appui (outil Sélection) : poignée d'échelle, cadenas, anneau. Vrai si pris.
func press(px: Vector2) -> bool:
	var t := hit(px)
	if t.is_empty():
		return false
	var e := target()
	match String(t.kind):
		"lock":
			cv.show_refusal(MapRules.refuse(MapScale.scale_refusal(e)[0], MapScale.scale_refusal(e)[1]))
			return true
		"scale":
			var h: Dictionary = t.h
			cv.drag = {"kind": "scale", "h": h, "snap": ed().doc.snapshot(), "orig": e.duplicate(true), "moved": false, "entry": "", "label": ""}
			return true
		"ring":
			cv.drag = {"kind": "ring", "c": t.c, "a0": (px - Vector2(t.c)).angle(), "snap": ed().doc.snapshot(), "orig": e.duplicate(true),
				"moved": false, "deg": 0.0, "entry": ""}
			return true
	return false


## Mouvement pendant un geste « scale » ou « ring ».
func update() -> void:
	if cv.drag.kind == "scale":
		_update_scale()
	else:
		_update_ring()


func _update_scale() -> void:
	var d := cv.drag
	var o0: Dictionary = d.orig
	var h: Dictionary = d.h
	var alt := Input.is_key_pressed(KEY_ALT)
	var mode := cv.mode_now()
	var s0 := MapScale.scale_of(o0)
	var cand := {}
	var f := MapGizmo.frame(o0)
	var typed := String(d.get("entry", ""))
	if h.kind == "face":
		var axis := int(h.axis)
		var side := int(h.side)
		var lm := cv.mouse_m - Vector2(f.c)
		var dirv: Vector2 = f.ex if axis == 0 else f.ey
		var half := float((f.h as Vector3)[axis])
		var fixed := 0.0 if (alt and not (axis == 1 and f.mount == "mur")) else -float(side) * half
		var k := (lm.dot(dirv) - fixed) / maxf(float(side) * half - fixed, 0.0001)
		var v := s0[axis] * maxf(k, 0.0)
		if typed != "":
			v = MapGizmo.typed_factor(typed, MapScale.dims(o0)[axis], s0[axis])
		# Valeur tapée illisible (« m », « . », « - »…) : rien ne change.
		if not is_finite(v):
			return
		var sn := MapGizmo.snap_scale(v, mode, MapGizmo.neighbour_magnets(ed().doc, o0, axis)) if typed == "" else {"v": v, "label": ""}
		d["label"] = String(sn.label)
		d["axes"] = [axis]
		cand = MapGizmo.scale_axis(o0, axis, float(sn.v), side, alt)
	else:
		# Coin : le coin opposé reste fixe (Alt : le centre).
		var c: Vector2 = f.c
		if bool(h.get("screen", false)):
			c = MapGeom.bbox(MapScale.ground_poly(o0)).get_center()
		var hm: Vector2 = h.m
		var fixed := c if alt else c - (hm - c)
		var k := MapGizmo.ratio(fixed, hm, cv.mouse_m)
		var v := s0.x * k
		if typed != "":
			v = MapGizmo.typed_factor(typed, MapScale.dims(o0).x, s0.x)
		# Valeur tapée illisible (« m », « . », « - »…) : rien ne change.
		if not is_finite(v):
			return
		var sn := MapGizmo.snap_scale(v, mode) if typed == "" else {"v": v, "label": ""}
		d["label"] = String(sn.label)
		d["axes"] = [0, 1, 2]
		d["fixed"] = fixed
		cand = MapGizmo.scale_uniform(o0, float(sn.v) / maxf(s0.x, 0.0001), fixed, 0.0)
	_try(cand)


## Applique le candidat s'il est valide (sinon la dernière place valide reste).
func _try(cand: Dictionary) -> void:
	var d := cv.drag
	var o0: Dictionary = d.orig
	var doc := ed().doc
	if cand.has("_sous_sol"):
		cv.refusal = Lang.t("le décor traverserait le sol : cochez « Rester posé »", "the prop would go through the floor: tick \"Stay grounded\"")
		cv._refusal_t = 1.5
		return
	if not d.has("v"):
		d["v"] = ed().raster().v   # plafonds inchangés pendant le geste (une fois)
		d["held"] = MapVertical.resting_on(doc, o0)
	var res := MapScale.check(doc, d.v, cand, o0, d.held)
	if not res.ok:
		cv.refusal = MapRules.why(res)
		cv.refusal_marks = []
		cv._refusal_t = 1.5
		return
	# Seul cet élément change : remplacé sur place (pas de carte remise : rapide sur 2000 objets).
	MapTransform.replace(doc, cand)
	d.moved = cand != o0
	ed().moved_live()
	ed().send_live(String(o0.id))
	ed().panels.live_scale(true)
	_status()


func _update_ring() -> void:
	var d := cv.drag
	var o0: Dictionary = d.orig
	var free := cv.angle_free() or Input.is_key_pressed(KEY_SHIFT)
	var deg := MapGizmo.ring_angle(Vector2(d.c), float(d.a0), cv.to_px(cv.mouse_m), free)
	var typed := String(d.get("entry", ""))
	if typed != "":
		var tv := MapPanelsScale.parse(typed)
		if not is_nan(tv):
			deg = tv
	if absf(deg - float(d.deg)) < 0.001 and d.moved:
		return
	d.deg = deg
	if String(o0.get("type", "")) == "prefab":
		_try(MapGizmo.rotated(o0, 2, deg, MapPanelsScale.rest_on_support()))
		return
	var res := MapTransform.apply(ed().doc, o0, [], MapTransform.pivot(ed().doc, o0), deg, d.snap)
	if res.ok:
		d.moved = true
		ed().moved_live()
		ed().send_live(String(o0.id))
		ed().panels.live_scale(true)
		_status()
	else:
		cv.refusal = MapRules.why(res)
		cv._refusal_t = 1.5


func release() -> void:
	var d := cv.drag
	ed().send_live("")
	ed().panels.live_scale(false)
	if d.moved:
		ed().push_undo_snapshot(d.snap)
		ed().changed()
		_status(true)
	cv.drag = {}


func cancel() -> void:
	ed().send_live("")
	ed().doc.restore(cv.drag.snap)
	ed().changed()
	ed().set_status(Lang.t("Geste annulé", "Gesture cancelled"))
	cv.drag = {}


## Touches pendant un geste : chiffres, virgule, « m », Retour arrière,
## Entrée (valide), Échap (annule). Vrai si la touche est prise.
func key(k: InputEventKey) -> bool:
	var d := cv.drag
	match k.keycode:
		KEY_ESCAPE:
			cv.cancel()
			return true
		KEY_ENTER, KEY_KP_ENTER:
			update()
			release()
			return true
		KEY_BACKSPACE:
			var s := String(d.get("entry", ""))
			d["entry"] = s.left(maxi(0, s.length() - 1))
			update()
			cv.queue_redraw()
			return true
		KEY_TAB:
			d["entry"] = ""
			cv.queue_redraw()
			return true
	var ch := MapCanvas._entry_char(k)
	if k.keycode == KEY_M and d.kind == "scale":
		ch = "m"
	if ch == "-" and d.kind == "scale":
		ch = ""
	if ch != "":
		d["entry"] = String(d.get("entry", "")) + ch
		update()
		cv.queue_redraw()
		return true
	return false


## Barre d'état pendant et après le geste (§ 2.4, § 3.2).
func _status(done := false) -> void:
	var d := cv.drag
	var o0: Dictionary = d.orig
	var now := ed().doc.find(String(o0.id))
	if now.is_empty():
		return
	if d.kind == "ring":
		var r0 := MapGeom.rot_of(o0)
		var r1 := MapGeom.rot_of(now)
		ed().set_status(Lang.t("Rotation Z : %d° → %d° · cran 15° · Maj : libre · tapez une valeur puis Entrée · Échap : annuler",
			"Rotation Z: %d° → %d° · 15° step · Shift: free · type a value then Enter · Esc: cancel") % [r0, r1] if not done
			else Lang.t("Rotation Z : %d° (Ctrl+Z : annuler)", "Rotation Z: %d° (Ctrl+Z: undo)") % r1)
		return
	ed().set_status(scale_status(o0, now, done))


## Texte de la barre d'état d'un geste d'échelle.
static func scale_status(o0: Dictionary, now: Dictionary, done := false) -> String:
	var s0 := MapScale.scale_of(o0)
	var s1 := MapScale.scale_of(now)
	var d0 := MapScale.dims(o0)
	var d1 := MapScale.dims(now)
	var dims := "%s → %s m" % [MapPanelsScale._dims_text(d0), MapPanelsScale._dims_text(d1)]
	var head := ""
	if MapScale.is_uniform(s1) and MapScale.is_uniform(s0):
		head = Lang.t("Échelle uniforme : %s → %s", "Uniform scale: %s → %s") % [MapPanelsScale.factor_text(s0.x), MapPanelsScale.factor_text(s1.x)]
	else:
		var parts := []
		for i in 3:
			if not is_equal_approx(s0[i], s1[i]):
				parts.append("%s %s → %s" % [["X", "Y", "Z"][i], MapPanelsScale.factor_text(s0[i]), MapPanelsScale.factor_text(s1[i])])
		head = Lang.t("Échelle : ", "Scale: ") + ", ".join(parts)
	if done:
		return "%s · %s %s" % [head, dims, Lang.t("(Ctrl+Z : annuler)", "(Ctrl+Z: undo)")]
	return "%s · %s · %s" % [head, dims, Lang.t("relâcher pour valider, Échap pour annuler", "release to apply, Esc to cancel")]


# ------------------------------------------------------------------ dessin

## Les flèches et l'anneau sont estompés (25 %) pendant un geste d'échelle.
func busy_scale() -> bool:
	return cv.drag.get("kind", "") == "scale"


func draw(font: Font) -> void:
	var e := target()
	if e.is_empty():
		return
	var dk := String(cv.drag.get("kind", ""))
	var scaling := dk == "scale"
	var rotating := dk == "ring"
	# Contour d'avant en pointillés et point fixe pendant un geste.
	if scaling or rotating:
		var o0: Dictionary = cv.drag.orig
		var old := cv._px_poly(MapRaster.floor_poly(o0) if MapCatalog.tool_of(o0) != "wall_item" else MapRules.wall_item_poly(o0))
		for i in old.size():
			cv.draw_dashed_line(old[i], old[(i + 1) % old.size()], Color(Color("DBD1B8"), 0.6), 1.0, u(4))
	# Anneau Z.
	var rg := ring_of(e)
	if not rg.is_empty():
		if rotating:
			var a0 := float(cv.drag.a0)
			var sgn := 1.0
			MapGizmo.draw_ring(cv, Vector2(rg.c), float(rg.r), MapGizmo.COL_Z, {"sweep": [a0, a0 + deg_to_rad(float(cv.drag.deg)) * sgn], "active": true})
			MapGizmo.draw_pill(cv, cv.to_px(cv.mouse_m) + Vector2(u(16), u(-12)), MapGizmo.angle_label(float(cv.drag.deg)) if String(cv.drag.get("entry", "")) == "" else String(cv.drag.entry) + "°",
				"gold", "Z", MapGizmo.COL_Z)
		else:
			var hov: bool = hit(cv.to_px(cv.mouse_m)).get("kind", "") == "ring" and dk == ""
			MapGizmo.draw_ring(cv, Vector2(rg.c), float(rg.r), MapGizmo.COL_Z, {"alpha": 0.25 if scaling else 0.9, "active": hov})
	# Poignées d'échelle (ou cadenas).
	# Pendant un geste d'anneau : l'anneau seul (maquette, écran 2).
	var hs := [] if rotating else handles_of(e)
	for h in hs:
		var p: Vector2 = h.p
		if h.lock:
			MapGizmo.draw_lock_square(cv, p, int(String(h.id).substr(1)) == hover_lock)
		elif h.kind == "corner":
			MapGizmo.draw_handle(cv, p, MapGizmo.COL_HANDLE)
		else:
			MapGizmo.draw_handle(cv, p, MapGizmo.axis_col(int(h.axis)))
	if hover_lock >= 0 and not hs.is_empty() and hs[0].lock and dk == "":
		var w := MapGizmo.warning_text(e)
		for h in hs:
			if int(String(h.id).substr(1)) == hover_lock:
				MapGizmo.draw_warning(cv, Vector2(h.p) + Vector2(u(7), -u(7)), String(w[0]), w[1])
	if scaling:
		_draw_scale_info(font, e)


## Cotes, facteur, aimant, hauteur et point fixe d'un geste d'échelle (écran 1).
func _draw_scale_info(_font: Font, e: Dictionary) -> void:
	var d := cv.drag
	var axes: Array = d.get("axes", [])
	var f := MapGizmo.frame(e)
	var c: Vector2 = f.c
	var ex: Vector2 = f.ex
	var ey: Vector2 = f.ey
	var h: Vector3 = f.h
	var dims := MapScale.dims(e)
	var gap := u(18) / cv.zoom
	# Cote de la largeur (au-dessus) et de la profondeur (à gauche).
	if axes.has(0):
		var a := c - ey * (h.y + gap) - ex * h.x
		var b := c - ey * (h.y + gap) + ex * h.x
		MapGizmo.draw_dim(cv, cv.to_px(a), cv.to_px(b), MapPanelsScale._m2(dims.x))
	if axes.has(1):
		var a := c - ex * (h.x + gap) - ey * h.y
		var b := c - ex * (h.x + gap) + ey * h.y
		MapGizmo.draw_dim(cv, cv.to_px(a), cv.to_px(b), MapPanelsScale._m2(dims.y), Vector2(-u(34), 0))
	# Hauteur (lecture) sous l'objet.
	if axes.has(2):
		var bb := cv._px_poly(MapRaster.floor_poly(e) if MapCatalog.tool_of(e) != "wall_item" else MapRules.wall_item_poly(e))
		var r := MapGeom.bbox(bb)
		MapGizmo.draw_pill(cv, Vector2(r.get_center().x, r.end.y + u(16)), "H " + MapPanelsScale._m2(MapScale.height(e)), "magnet", "", Color.WHITE, true)
	if d.has("fixed"):
		MapGizmo.draw_cross(cv, cv.to_px(Vector2(d.fixed)))
	# Facteur près du curseur (aimant en bleu).
	var s := MapScale.scale_of(e)
	var at := cv.to_px(cv.mouse_m) + Vector2(u(14), u(14))
	var typed := String(d.get("entry", ""))
	var k: int = axes[0] if axes.size() == 1 else 0
	var txt := typed if typed != "" else MapPanelsScale.factor_text(s[k])
	var lbl := String(d.get("label", ""))
	var pr := MapGizmo.draw_pill(cv, at, txt if lbl == "" or lbl.begins_with("×") else lbl, "magnet" if lbl != "" else "gold")
	var hint := Lang.t("uniforme · Alt : depuis le centre", "uniform · Alt: from the centre") if axes.size() == 3 else Lang.t("axe %s · Alt : depuis le centre", "%s axis · Alt: from the centre") % ["X", "Y", "Z"][k]
	cv.draw_string(MapView.bold_font(400), Vector2(pr.end.x + u(6), pr.position.y + u(14)), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, EditorUi.fs(11), Color("8C8575"))
