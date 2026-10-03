class_name MapGizmoElev
extends RefCounted
## Poignées d'échelle et anneau d'inclinaison d'une élévation (format 14,
## docs/EDITOR_SCALE_ROTATE.md § 2.4, § 3.2 ; maquette, écrans 1 et 2) pour
## le décor choisi seul :
##   - coins jaunes (échelle uniforme ; au sol la base reste sur son support,
##     au plafond l'attache reste, mural le côté opposé, Alt : le centre),
##     côtés gauche et droit (l'axe de la vue, s'il est face à l'écran :
##     X rouge en Avant, Y vert en Droite), losange bleu de la hauteur (Z) ;
##     incliné ou tourné en biais : les coins seulement ;
##   - anneau Y (Avant, Arrière) ou X (Droite, Gauche) d'un décor qui
##     s'incline : crans de 15°, Maj ou Alt : libre ; « Rester posé » ;
##   - pendant le geste : contour d'avant en pointillés, cotes, facteur ou
##     angle en or, barre d'état ; une étape d'annulation au relâché.

## Outils de la vue (lus par la vue, un nœud : pas de cycle de références
## entre MapElevationTools et ce gizmo, qui serait une fuite).
var view: MapElevation
var t: MapElevationTools:
	get:
		return view.tools


func _init(tools: MapElevationTools) -> void:
	view = tools.ev


func ev() -> MapElevation:
	return t.ev


func ed() -> MapEditor:
	return t.ev.ed


func u(v: float) -> float:
	return EditorUi.px(v)


## Décor choisi seul, projeté ({} sinon) ; `o` : l'élément de la carte.
func target() -> Dictionary:
	if ed().group.size() >= 2 or t.offscreen_tools():
		return {}
	var e := t.sel()
	if e.is_empty() or String(e.it.e.get("type", "")) != "prefab" or MapScale.def_of(e.it.e).is_empty():
		return {}
	return e


func _o(e: Dictionary) -> Dictionary:
	return ed().doc.find(String(e.it.e.get("id", "")))


## Rectangle (px) de la boîte projetée de l'élément.
func _rect(e: Dictionary) -> Rect2:
	return ev().rect_px(e)


## Axe local (0 : X, 1 : Y) face à l'écran sur l'axe horizontal de la vue,
## et son sens (σ : +1 si l'axe local va vers la droite de l'écran) ; [-1, 0]
## s'il n'y en a pas (incliné, tourné en biais).
func h_local(o: Dictionary) -> Array:
	if MapScale.is_tilted(o):
		return [-1, 0]
	var f := MapGizmo.frame(o)
	var hd := t.h_dir()
	var dx := (f.ex as Vector2).dot(hd)
	var dy := (f.ey as Vector2).dot(hd)
	if absf(dx) > 0.999:
		return [0, int(signf(dx))]
	if absf(dy) > 0.999:
		# Mural : la profondeur (face du mur fixe) ne se règle pas ici.
		if f.mount == "mur":
			return [-1, 0]
		return [1, int(signf(dy))]
	return [-1, 0]


## Poignées d'échelle (px) : [{id, p, kind (« corner », « side », « top »), ...}].
func handles_of(e: Dictionary) -> Array:
	var o := _o(e)
	if o.is_empty():
		return []
	var r := _rect(e)
	var out := []
	var blocked := not MapScale.scalable(o)
	var cs := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	for i in 4:
		out.append({"id": "c%d" % i, "p": cs[i], "kind": "corner", "lock": blocked})
	if blocked:
		return out
	var hl := h_local(o)
	if int(hl[0]) >= 0 and not MapScale.uniform_only(o):
		out.append({"id": "sl", "p": Vector2(r.position.x, r.get_center().y), "kind": "side", "screen": -1, "axis": int(hl[0]), "sigma": int(hl[1])})
		out.append({"id": "sr", "p": Vector2(r.end.x, r.get_center().y), "kind": "side", "screen": 1, "axis": int(hl[0]), "sigma": int(hl[1])})
	if not MapScale.is_tilted(o) and not MapScale.uniform_only(o):
		var ceil := MapScale.mount_of(o) == "plafond"
		out.append({"id": "top", "p": Vector2(r.get_center().x, r.end.y if ceil else r.position.y), "kind": "top", "side": -1 if ceil else 1})
	return out


## Anneau de l'élément : {c (px), r (px), axis} ; {} s'il ne s'incline pas.
func ring_of(e: Dictionary) -> Dictionary:
	var o := _o(e)
	var axis := MapGizmo.ring_axis(ev().plane)
	if not MapGizmoTop.RINGS or o.is_empty() or axis < 0 or axis == 2 or not MapScale.tiltable(o):
		return {}
	var r := _rect(e)
	var rad := clampf(r.size.length() * 0.5 + u(MapGizmo.RING_PAD), u(MapGizmo.RING_MIN), u(MapGizmo.RING_MAX))
	return {"c": r.get_center(), "r": rad, "axis": axis}


func hit(px: Vector2) -> Dictionary:
	var e := target()
	if e.is_empty():
		return {}
	for h in handles_of(e):
		if (h.p as Vector2).distance_to(px) <= u(7) + 2.0:
			return {"kind": "lock" if h.get("lock", false) else "scale", "h": h, "e": e}
	var rg := ring_of(e)
	if not rg.is_empty():
		var grip := Vector2(rg.c) + Vector2(0, -float(rg.r))
		if px.distance_to(grip) <= u(8) or absf(px.distance_to(Vector2(rg.c)) - float(rg.r)) <= u(MapGizmo.RING_BAND) * 0.5 + 1.0:
			return {"kind": "ring", "rg": rg, "e": e}
	return {}


func cursor(px: Vector2) -> int:
	match String(t.drag.get("kind", "")):
		"ring":
			return Control.CURSOR_POINTING_HAND
		"scale":
			return Control.CURSOR_FDIAGSIZE
	var h := hit(px)
	match String(h.get("kind", "")):
		"lock":
			return Control.CURSOR_FORBIDDEN
		"ring":
			return Control.CURSOR_POINTING_HAND
		"scale":
			match String(h.h.kind):
				"side":
					return Control.CURSOR_HSIZE
				"top":
					return Control.CURSOR_VSIZE
			return Control.CURSOR_FDIAGSIZE if String(h.h.id) in ["c0", "c2"] else Control.CURSOR_BDIAGSIZE
	return -1


func press(px: Vector2) -> bool:
	var h := hit(px)
	if h.is_empty():
		return false
	var o := _o(h.e)
	match String(h.kind):
		"lock":
			var rf := MapScale.scale_refusal(o)
			ed().canvas.show_refusal(MapRules.refuse(rf[0], rf[1]))
			return true
		"scale":
			t.drag = {"kind": "scale", "h": h.h, "snap": ed().doc.snapshot(), "orig": o.duplicate(true), "moved": false, "rect0": _rect(h.e), "box0": (h.e as Dictionary).duplicate(), "lock": ""}
			t.entry = ""
			return true
		"ring":
			var rg: Dictionary = h.rg
			t.drag = {"kind": "ring", "c": rg.c, "r": rg.r, "axis": rg.axis, "a0": (px - Vector2(rg.c)).angle(), "snap": ed().doc.snapshot(), "orig": o.duplicate(true),
				"moved": false, "deg": 0.0, "rect0": _rect(h.e), "box0": (h.e as Dictionary).duplicate(), "lock": ""}
			t.entry = ""
			return true
	return false


func update() -> void:
	if t.drag.kind == "scale":
		_update_scale()
	else:
		_update_ring()


## u (coordonnée de l'écran, m) d'un point du plan.
func _u_of(p: Vector2) -> float:
	return MapView.uv_of(ev().plane, Vector3(p.x, p.y, 0.0)).x


func _update_scale() -> void:
	var d := t.drag
	var o0: Dictionary = d.orig
	var h: Dictionary = d.h
	var r0: Rect2 = d.rect0
	var alt := Input.is_key_pressed(KEY_ALT)
	var mode := ed().canvas.mode_now()
	var s0 := MapScale.scale_of(o0)
	var mpx := ev().to_px(ev().mouse_m)
	var mount := MapScale.mount_of(o0)
	var cand := {}
	match String(h.kind):
		"side":
			var axis := int(h.axis)
			var scr := int(h.screen)
			var fixed_x := r0.get_center().x if alt else (r0.end.x if scr < 0 else r0.position.x)
			var k := (mpx.x - fixed_x) / maxf(absf(Vector2(h.p).x - fixed_x), 0.5) * float(scr)
			var v := s0[axis] * maxf(k, 0.0)
			if t.entry != "":
				v = MapGizmo.typed_factor(t.entry, MapScale.dims(o0)[axis], s0[axis])
			var sn := MapGizmo.snap_scale(v, mode, MapGizmo.neighbour_magnets(ed().doc, o0, axis)) if t.entry == "" else {"v": v, "label": ""}
			d["label"] = String(sn.label)
			d["axes"] = [axis]
			cand = MapGizmo.scale_axis(o0, axis, float(sn.v), scr * int(h.sigma), alt)
		"top":
			var side := int(h.side)
			var base_y := r0.get_center().y if alt and mount == "mur" else (r0.position.y if side < 0 else r0.end.y)
			var k := (base_y - mpx.y) / maxf(absf(base_y - Vector2(h.p).y), 0.5) * float(side)
			var v := s0.z * maxf(k, 0.0)
			if t.entry != "":
				v = MapGizmo.typed_factor(t.entry, MapScale.dims(o0).z, s0.z)
			var sn := MapGizmo.snap_scale(v, mode, MapGizmo.neighbour_magnets(ed().doc, o0, 2)) if t.entry == "" else {"v": v, "label": ""}
			d["label"] = String(sn.label)
			d["axes"] = [2]
			cand = MapGizmo.scale_axis(o0, 2, float(sn.v), side, alt)
		_:
			# Coin : uniforme ; horizontal : côté opposé (Alt : centre) ; vertical
			# selon le montage (base, attache ; mural : côté opposé, Alt : centre).
			var hp: Vector2 = h.p
			var fx := r0.get_center().x if alt else (r0.end.x if hp.x < r0.get_center().x else r0.position.x)
			var top_corner := hp.y < r0.get_center().y
			var fy := r0.end.y
			match mount:
				"plafond":
					fy = r0.position.y
				"mur":
					fy = r0.get_center().y if alt else (r0.end.y if top_corner else r0.position.y)
			var k := MapGizmo.ratio(Vector2(fx, fy), hp, mpx)
			var v := s0.x * k
			if t.entry != "":
				v = MapGizmo.typed_factor(t.entry, MapScale.dims(o0).x, s0.x)
			var sn := MapGizmo.snap_scale(v, mode) if t.entry == "" else {"v": v, "label": ""}
			d["label"] = String(sn.label)
			d["axes"] = [0, 1, 2]
			# Point fixe dans le plan : sur l'axe de la vue, à la profondeur du centre.
			var c: Vector2 = MapGizmo.frame(o0).c
			var fu := ev().to_m(Vector2(fx, fy)).x
			var fixed := c + t.h_dir() * (fu - _u_of(c))
			var fz := 0.0 if alt else (-1.0 if top_corner else 1.0)
			d["fixed_px"] = Vector2(fx, fy)
			cand = MapGizmo.scale_uniform(o0, float(sn.v) / maxf(s0.x, 0.0001), fixed, fz)
	_try(cand)


func _update_ring() -> void:
	var d := t.drag
	var o0: Dictionary = d.orig
	var free := ed().canvas.angle_free() or Input.is_key_pressed(KEY_SHIFT)
	var deg := MapGizmo.ring_angle(Vector2(d.c), float(d.a0), ev().to_px(ev().mouse_m), free)
	if t.entry != "":
		var tv := MapPanelsScale.parse(t.entry)
		if not is_nan(tv):
			deg = tv * MapGizmo.screen_sign(ev().plane)
	d.deg = deg
	_try(MapGizmo.rotated(o0, int(d.axis), deg * MapGizmo.screen_sign(ev().plane), MapPanelsScale.rest_on_support()))


func _try(cand: Dictionary) -> void:
	var d := t.drag
	var o0: Dictionary = d.orig
	var doc := ed().doc
	if cand.is_empty():
		return
	if cand.has("_sous_sol"):
		t.refusal = Lang.t("le décor traverserait le sol : cochez « Rester posé »", "the prop would go through the floor: tick \"Stay grounded\"")
		return
	if not d.has("v"):
		d["v"] = ed().raster().v   # plafonds inchangés pendant le geste (une fois)
	var res := MapScale.check(doc, d.v, cand, o0)
	if not res.ok:
		t.refusal = MapRules.why(res)
		return
	t.refusal = ""
	doc.restore(d.snap)
	MapTransform.replace(doc, cand)
	d.moved = cand != o0
	ed().moved_live()
	ed().send_live(String(o0.id))
	ed().panels.live_scale(true)
	if d.kind == "ring":
		var ax: String = ["X", "Y", "Z"][int(d.axis)]
		var i0 := MapScale.incl_of(o0)[int(d.axis)]
		var i1 := MapScale.incl_of(cand)[int(d.axis)]
		ed().set_status(Lang.t("Rotation %s (axe %s) : %s → %s · cran 15° · Maj : libre · tapez une valeur puis Entrée · Échap : annuler",
			"Rotation %s (%s axis): %s → %s · 15° step · Shift: free · type a value then Enter · Esc: cancel") % [ax, Lang.t(["est", "sud", "haut"][int(d.axis)], ["east", "south", "up"][int(d.axis)]),
			MapPanelsScale.angle_text(i0), MapPanelsScale.angle_text(i1)])
	else:
		ed().set_status(MapGizmoTop.scale_status(o0, cand))


func release() -> void:
	ed().send_live("")
	ed().panels.live_scale(false)
	var d := t.drag
	if d.moved:
		ed().push_undo_snapshot(d.snap)
		ed().changed()
		var now := ed().doc.find(String(d.orig.id))
		if d.kind == "scale" and not now.is_empty():
			ed().set_status(MapGizmoTop.scale_status(d.orig, now, true))
	t.drag = {}
	t.entry = ""
	t.entering = false
	t.refusal = ""


# ------------------------------------------------------------------ dessin

func draw(c: CanvasItem) -> void:
	var e := target()
	if e.is_empty():
		return
	var dk := String(t.drag.get("kind", ""))
	var r := _rect(e)
	var o := _o(e)
	if dk in ["scale", "ring"] and t.drag.moved:
		t._dashed_rect(c, Rect2(t.drag.rect0), Color(MapElevationTools.COL_BONE, 0.55), 1.0)
	var rg := ring_of(e)
	if not rg.is_empty():
		var col := MapGizmo.axis_col(int(rg.axis))
		if dk == "ring":
			var a0 := float(t.drag.a0)
			MapGizmo.draw_ring(c, Vector2(t.drag.c), float(t.drag.r), col, {"sweep": [a0, a0 + deg_to_rad(float(t.drag.deg))], "active": true})
			var wdeg := float(t.drag.deg) * MapGizmo.screen_sign(ev().plane)
			MapGizmo.draw_pill(c, ev().to_px(ev().mouse_m) + Vector2(u(16), -u(12)), MapGizmo.angle_label(wdeg) if t.entry == "" else t.entry + "°", "gold",
				["X", "Y", "Z"][int(rg.axis)], col)
		else:
			var hov: bool = hit(ev().to_px(ev().mouse_m)).get("kind", "") == "ring" and dk == ""
			MapGizmo.draw_ring(c, Vector2(rg.c), float(rg.r), col, {"alpha": 0.25 if dk == "scale" else 0.9, "active": hov})
	# Pendant un geste d'anneau : l'anneau seul (maquette, écran 2).
	for h in ([] if dk == "ring" else handles_of(e)):
		var p: Vector2 = h.p
		if h.get("lock", false):
			MapGizmo.draw_lock_square(c, p, hit(ev().to_px(ev().mouse_m)).get("h", {}).get("id", "") == h.id and dk == "")
		elif h.kind == "corner":
			MapGizmo.draw_handle(c, p, MapGizmo.COL_HANDLE)
		elif h.kind == "side":
			# Côtés : la couleur de l'axe du monde montré (X rouge, Y vert).
			MapGizmo.draw_handle(c, p, MapGizmo.COL_X if t.h_letter() == "X" else MapGizmo.COL_Y)
		else:
			MapGizmo.draw_diamond(c, p)
	if dk == "scale":
		_draw_scale_info(c, o, r)
	if t.refusal != "" and dk in ["scale", "ring"]:
		t._draw_refusal(c)


func _draw_scale_info(c: CanvasItem, o: Dictionary, r: Rect2) -> void:
	var d := t.drag
	var axes: Array = d.get("axes", [])
	var dims := MapScale.dims(o)
	var gap := u(26)
	if axes.has(2):
		# Hauteur : cote verticale à gauche ; au sol, la base reste au sol.
		var lx := r.position.x - gap
		c.draw_line(Vector2(lx - u(6), r.position.y), Vector2(r.position.x - u(6), r.position.y), Color(MapElevationTools.COL_BONE, 0.5), 1.0)
		MapGizmo.draw_dim(c, Vector2(lx, r.end.y), Vector2(lx, r.position.y), MapPanelsScale._m2(MapScale.height(o)), Vector2(-u(34), 0))
		if MapScale.mount_of(o) == "sol":
			c.draw_string(MapView.bold_font(400), Vector2(r.position.x, r.end.y + u(16)), Lang.t("base fixe : reste au sol", "fixed base: stays on the floor"),
				HORIZONTAL_ALIGNMENT_LEFT, -1, EditorUi.fs(10.5), Color("8C8575"))
	var hl := h_local(o)
	if axes.has(0) and int(hl[0]) == 0 or axes.has(1) and int(hl[0]) == 1:
		var w := dims[int(hl[0])]
		MapGizmo.draw_dim(c, Vector2(r.position.x, r.position.y - gap * 0.7), Vector2(r.end.x, r.position.y - gap * 0.7), MapPanelsScale._m2(w))
	if d.has("fixed_px"):
		MapGizmo.draw_cross(c, Vector2(d.fixed_px))
	var s := MapScale.scale_of(o)
	var k: int = axes[0] if axes.size() == 1 else 0
	var lbl := String(d.get("label", ""))
	var txt := t.entry if t.entry != "" else MapPanelsScale.factor_text(s[k])
	MapGizmo.draw_pill(c, ev().to_px(ev().mouse_m) + Vector2(u(14), u(14)), txt if lbl == "" or lbl.begins_with("×") else lbl, "magnet" if lbl != "" else "gold")
