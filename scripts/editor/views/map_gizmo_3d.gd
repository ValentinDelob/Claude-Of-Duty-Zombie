class_name MapGizmo3D
extends Control
## Gizmo de rotation de la vue 3D (format 14, docs/EDITOR_SCALE_ROTATE.md §
## 3.2 ; maquette, écran 2) : trois anneaux X rouge, Y vert, Z bleu autour du
## centre de la boîte du décor choisi, sur les AXES DU MONDE, de taille fixe
## à l'écran (rayon 90 px à 100 %) ; X et Y seulement si le décor s'incline.
## Premier geste d'édition de la 3D : glisser le long d'un anneau (bande de
## prise de 8 px ; l'anneau survolé s'épaissit, les autres s'estompent
## pendant le geste), crans de 15° (Maj ou Alt : libre), valeur tapée puis
## Entrée, Échap annule ; secteur balayé, graduations, pastille d'angle en or,
## position d'avant en pointillés ; « Rester posé ».
## Pendant le geste, seuls les nœuds du décor sont déplacés dans l'aperçu
## (aucune reconstruction : < 2 ms par mouvement de souris) ; la carte entière
## est reconstruite au relâché (une étape d'annulation).

var panel: MapPreviewPanel
## Anneau survolé (0 : X, 1 : Y, 2 : Z ; -1 : aucun).
var hover := -1
## Geste en cours : {axis, a0, deg, orig, snap, nodes: {nœud: Transform3D}, f0, entry, moved} ; vide sinon.
var drag: Dictionary = {}
const SEGS := 72


func _init(p: MapPreviewPanel) -> void:
	panel = p
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	set_meta(EditorUi.SKIP, true)


func ed() -> MapEditor:
	return panel.ed


func cam() -> Camera3D:
	return panel.world.rig.cam


## Décor choisi seul qui tourne ({} sinon).
func target() -> Dictionary:
	if ed() == null or ed().group.size() >= 2:
		return {}
	var e := ed().doc.find(ed().selected)
	if e.is_empty() or String(e.get("type", "")) != "prefab" or MapScale.def_of(e).is_empty() or MapScale.mount_of(e) == "mur":
		return {}
	return e


## Axes des anneaux : Z toujours, X et Y si le décor s'incline.
static func axes_of(e: Dictionary) -> Array:
	return [0, 1, 2] if MapScale.tiltable(e) else [2]


## Centre (jeu) de la boîte du décor : son centre, à mi-hauteur.
func center3(e: Dictionary) -> Vector3:
	var k := int(e.get("etage", 0))
	var sols: Array = panel.world._floor_sols
	var sol := float(sols[k]) if k < sols.size() else 0.0
	var p := MapGeom.v2(e.get("position", [0, 0]))
	var zc := 0.0
	if MapScale.mount_of(e) == "plafond":
		var v := ed().raster().v
		zc = MapVertical.room_h(v, e) - MapVertical.descente(e) - MapScale.dims(e).z * 0.5
	else:
		zc = MapVertical.decor_z(e) + MapScale.half_z(e)
	return Vector3(p.x + MapGeom.WORLD_OFFSET, sol + zc, p.y + MapGeom.WORLD_OFFSET)


## Base (u, v) du plan d'un anneau, repère du JEU : tourner u de +θ (§ 3.1)
## donne cos θ u + sin θ v.
static func plane_uv(axis: int) -> Array:
	# Carte : Z -> (X, Y) ; Y -> (X, -Z) ; X -> (Y, Z) ; jeu : (x, y haut, z sud).
	match axis:
		0:
			return [Vector3(0, 0, 1), Vector3(0, 1, 0)]
		1:
			return [Vector3(1, 0, 0), Vector3(0, -1, 0)]
	return [Vector3(1, 0, 0), Vector3(0, 0, 1)]


## Point (px de cette couche) d'un point du monde ; null derrière la caméra.
func to_px(p: Vector3) -> Variant:
	var c := cam()
	if c == null or c.is_position_behind(p):
		return null
	var vs := Vector2(panel.world.viewport.size)
	return c.unproject_position(p) / vs.max(Vector2.ONE) * size


## Rayon (m) d'un anneau de 90 px à l'écran au centre `c`.
func radius_m(c: Vector3) -> float:
	var cm := cam()
	if cm == null:
		return 1.0
	var d := cm.global_position.distance_to(c)
	var vs := Vector2(panel.world.viewport.size)
	var px_per_m := (vs.y * 0.5) / maxf(0.001, d * tan(deg_to_rad(cm.fov) * 0.5))
	var scale := size.y / maxf(vs.y, 1.0)
	return EditorUi.px(MapGizmo.RING_3D) / maxf(px_per_m * scale, 0.0001)


## Points (px) d'un anneau.
func ring_px(c: Vector3, r: float, axis: int) -> PackedVector2Array:
	var uv := plane_uv(axis)
	var out := PackedVector2Array()
	for i in SEGS + 1:
		var a := TAU * i / SEGS
		var q: Variant = to_px(c + (uv[0] as Vector3) * cos(a) * r + (uv[1] as Vector3) * sin(a) * r)
		if q == null:
			return PackedVector2Array()
		out.append(q)
	return out


## Anneau sous le pixel (-1 : aucun) : bande de prise de 8 px.
func ring_at(px: Vector2) -> int:
	var e := target()
	if e.is_empty():
		return -1
	var c := center3(e)
	var r := radius_m(c)
	var best := -1
	var best_d := EditorUi.px(MapGizmo.RING_BAND) * 0.5 + 1.0
	for axis in axes_of(e):
		var pts := ring_px(c, r, axis)
		for i in range(1, pts.size()):
			var d := Geometry2D.get_closest_point_to_segment(px, pts[i - 1], pts[i]).distance_to(px)
			if d < best_d:
				best_d = d
				best = axis
	return best


## Angle (degrés, § 3.1) du point de l'écran `px` autour de l'axe `axis`
## dans le plan de l'anneau (rayon de la caméra coupé par ce plan).
func angle_at(px: Vector2, axis: int, c: Vector3) -> float:
	var cm := cam()
	var vs := Vector2(panel.world.viewport.size)
	var vp := px / size.max(Vector2.ONE) * vs
	var from := cm.project_ray_origin(vp)
	var dir := cm.project_ray_normal(vp)
	var uv := plane_uv(axis)
	var n := (uv[0] as Vector3).cross(uv[1])
	var den := dir.dot(n)
	var p := c
	if absf(den) > 0.0001:
		p = from + dir * ((c - from).dot(n) / den)
	var q := p - c
	return rad_to_deg(atan2(q.dot(uv[1]), q.dot(uv[0])))


# ------------------------------------------------------------------ geste

func press(px: Vector2) -> bool:
	var axis := ring_at(px)
	if axis < 0:
		return false
	var e := target()
	var c := center3(e)
	drag = {"axis": axis, "a0": angle_at(px, axis, c), "deg": 0.0, "orig": e.duplicate(true), "snap": ed().doc.snapshot(), "c": c,
		"nodes": _nodes_of(String(e.id)), "f0": frame3(e), "entry": "", "moved": false, "r": radius_m(c), "px": px}
	panel.world.auto = false
	_cache_map()
	queue_redraw()
	return true


## Emprises de la carte rangées une fois pour tout le geste (2000 objets),
## plafonds, décors posés dessus, place de l'élément dans la liste ; refait
## quand la carte change pendant le geste (map_changed).
func _cache_map() -> void:
	var doc := ed().doc
	MapRules.end_batch()
	MapRules.begin_batch(doc)
	drag["v"] = ed().raster().v
	drag["held"] = MapVertical.resting_on(doc, drag.orig)
	drag["idx"] = doc.objets.find(doc.find(String(drag.orig.id)))
	drag["tried"] = false


## Changement reçu pendant le geste (autre participant, Claude) : la carte de
## départ le reçoit aussi (MapEditor._on_collab_applied) ; si l'élément tenu
## a été changé ou retiré, le geste s'arrête sans rien écrire.
func map_changed(ops: Array) -> void:
	if drag.is_empty():
		return
	MapOps.apply(drag.snap, ops)
	var oid := String(drag.orig.id)
	if MapOps.ids_of(ops).has(oid):
		drop()
		return
	_cache_map()


## Carte entière remplacée (ou élément tenu changé par un autre) : le geste
## est abandonné SANS remettre sa carte de départ.
func drop() -> void:
	if drag.is_empty():
		return
	drag = {}
	MapRules.end_batch()
	panel.world.auto = true
	if is_instance_valid(panel) and is_instance_valid(panel.ed):
		ed().send_live("")
		ed().panels.live_scale(false)
	queue_redraw()


## Geste en cours ?
func dragging() -> bool:
	return not drag.is_empty()


## Nœuds de l'aperçu du décor `eid` (son modèle, ses copies, ses parties) et
## leur transformation au début du geste.
func _nodes_of(eid: String) -> Dictionary:
	var out := {}
	var g: Variant = panel.world.groups.get("decor")
	if not g is Node3D:
		return out
	for n in (g as Node3D).find_children("*", "Node3D", true, false):
		var nm := String(n.name)
		if nm == eid or nm.begins_with(eid + "_"):
			if n.get_parent() != null and (String(n.get_parent().name) == eid or String(n.get_parent().name).begins_with(eid + "_")):
				continue
			out[n] = (n as Node3D).global_transform
	return out


## Repère du décor dans le jeu (rotation × échelle, origine du modèle).
func frame3(e: Dictionary) -> Transform3D:
	var b := MapScale.game_basis(e) * Basis.from_scale(MapScale.game_scale(e))
	var c := center3(e)
	return Transform3D(b, c)


func update(px: Vector2) -> void:
	if drag.is_empty():
		return
	drag["px"] = px
	var axis := int(drag.axis)
	var o0: Dictionary = drag.orig
	var deg := rad_to_deg(angle_difference(deg_to_rad(float(drag.a0)), deg_to_rad(angle_at(px, axis, Vector3(drag.c)))))
	var free := Input.is_key_pressed(KEY_SHIFT) or Input.is_key_pressed(KEY_ALT)
	deg = roundf(deg) if free else snappedf(deg, MapGizmo.ANGLE_STEP)
	if String(drag.entry) != "":
		var tv := MapPanelsScale.parse(String(drag.entry))
		if not is_nan(tv):
			deg = tv
	# Même cran qu'au mouvement d'avant : rien à recalculer (dessin seulement).
	if bool(drag.get("tried", false)) and is_equal_approx(deg, float(drag.deg)):
		queue_redraw()
		return
	drag.deg = deg
	drag["tried"] = true
	var cand := MapGizmo.rotated(o0, axis, deg, MapPanelsScale.rest_on_support())
	if cand.has("_sous_sol"):
		ed().set_status(Lang.t("le décor traverserait le sol : cochez « Rester posé »", "the prop would go through the floor: tick \"Stay grounded\""), true)
		return
	var res := MapScale.check(ed().doc, drag.v, cand, o0, drag.held)
	if not res.ok:
		ed().set_status(MapRules.why(res), true)
		queue_redraw()
		return
	var doc := ed().doc
	# Seul ce décor change : remplacé sur place (pas de carte remise : rapide sur 2000 objets).
	var idx := int(drag.idx)
	if idx >= 0 and idx < doc.objets.size() and String(doc.objets[idx].get("id", "")) == String(o0.id):
		doc.objets[idx] = cand
	else:
		MapTransform.replace(doc, cand)
	drag.moved = cand != o0
	# Aperçu : seuls les nœuds de ce décor bougent (pas de reconstruction).
	var t := frame3(cand) * (drag.f0 as Transform3D).affine_inverse()
	for n in drag.nodes:
		if is_instance_valid(n):
			(n as Node3D).global_transform = t * (drag.nodes[n] as Transform3D)
	ed().moved_live()
	ed().send_live(String(o0.id))
	ed().panels.live_scale(true)
	var ax: String = ["X", "Y", "Z"][axis]
	var i0 := float(MapGeom.rot_of(o0)) if axis == 2 else MapScale.incl_of(o0)[axis]
	var i1 := float(MapGeom.rot_of(cand)) if axis == 2 else MapScale.incl_of(cand)[axis]
	ed().set_status(Lang.t("Rotation %s (axe %s) : %s → %s · cran 15° · Maj : libre · tapez une valeur puis Entrée · Échap : annuler",
		"Rotation %s (%s axis): %s → %s · 15° step · Shift: free · type a value then Enter · Esc: cancel") % [ax,
		Lang.t(["est", "sud", "haut"][axis], ["east", "south", "up"][axis]), MapPanelsScale.angle_text(i0, axis != 2), MapPanelsScale.angle_text(i1, axis != 2)])
	panel._request_render()
	queue_redraw()


func release() -> void:
	if drag.is_empty():
		return
	var d := drag
	drag = {}
	MapRules.end_batch()
	panel.world.auto = true
	ed().send_live("")
	ed().panels.live_scale(false)
	if d.moved:
		ed().push_undo_snapshot(d.snap)
		ed().changed()
	queue_redraw()


func cancel() -> void:
	if drag.is_empty():
		return
	for n in drag.nodes:
		if is_instance_valid(n):
			(n as Node3D).global_transform = drag.nodes[n]
	MapRules.end_batch()
	var snap: Dictionary = drag.snap
	drag = {}
	panel.world.auto = true
	if is_instance_valid(panel) and is_instance_valid(panel.ed):
		ed().send_live("")
		ed().doc.restore(snap)
		ed().changed()
		ed().panels.live_scale(false)
	queue_redraw()


## Touches pendant le geste : chiffres, Entrée, Retour arrière, Échap.
func key(k: InputEventKey) -> bool:
	if drag.is_empty() or not k.pressed:
		return false
	match k.keycode:
		KEY_ESCAPE:
			cancel()
			return true
		KEY_ENTER, KEY_KP_ENTER:
			# La valeur tapée s'applique même sans bouger la souris.
			drag["tried"] = false
			update(Vector2(drag.px))
			release()
			return true
		KEY_BACKSPACE:
			drag.entry = String(drag.entry).left(maxi(0, String(drag.entry).length() - 1))
			drag["tried"] = false
			update(Vector2(drag.px))
			return true
	var ch := MapCanvas._entry_char(k)
	if ch != "":
		drag.entry = String(drag.entry) + ch
		drag["tried"] = false
		update(Vector2(drag.px))
		return true
	return false


## Geste qui ne peut pas se terminer normalement (aperçu masqué, fenêtre qui
## perd le focus, vue retirée de la disposition, éditeur fermé) : annulé,
## l'aperçu repart (jamais figé).
func _notification(what: int) -> void:
	if drag.is_empty():
		return
	match what:
		NOTIFICATION_VISIBILITY_CHANGED:
			if not is_visible_in_tree():
				cancel()
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_EXIT_TREE:
			cancel()


# ------------------------------------------------------------------ dessin

func _process(_delta: float) -> void:
	if not drag.is_empty() or not target().is_empty():
		queue_redraw()


func _draw() -> void:
	var e := target()
	if e.is_empty() or panel.world == null or cam() == null:
		return
	var c := center3(e) if drag.is_empty() else Vector3(drag.c)
	var r := radius_m(c) if drag.is_empty() else float(drag.r)
	var cols := [MapGizmo.COL_X, MapGizmo.COL_Y, MapGizmo.COL_Z]
	for axis in axes_of(e):
		var pts := ring_px(c, r, axis)
		if pts.size() < 2:
			continue
		var active: bool = (not drag.is_empty() and int(drag.axis) == axis) or (drag.is_empty() and hover == axis)
		var a := 0.25 if (not drag.is_empty() and not active) else 0.9
		var col: Color = cols[axis]
		if active:
			col = col.lightened(0.15)
		if not drag.is_empty() and active:
			_draw_sweep(c, r, axis, col)
		draw_polyline(pts, Color(col, a), 3.0 if active else 1.8, true)
	var cp: Variant = to_px(c)
	if cp != null:
		draw_circle(cp, EditorUi.px(2.5), Color.WHITE)
	if not drag.is_empty():
		var ax := int(drag.axis)
		var m := get_local_mouse_position()
		var txt := MapGizmo.angle_label(float(drag.deg)) if String(drag.entry) == "" else String(drag.entry) + "°"
		MapGizmo.draw_pill(self, m + Vector2(EditorUi.px(16), -EditorUi.px(12)), txt, "gold", ["X", "Y", "Z"][ax], cols[ax])
		draw_string(MapView.bold_font(400), m + Vector2(EditorUi.px(16), EditorUi.px(14)), Lang.t("cran 15° · Maj : libre", "15° step · Shift: free"),
			HORIZONTAL_ALIGNMENT_LEFT, -1, EditorUi.fs(11), Color("8C8575"))


## Secteur balayé, graduations, rayon d'avant en pointillés.
func _draw_sweep(c: Vector3, r: float, axis: int, col: Color) -> void:
	var uv := plane_uv(axis)
	var a0 := deg_to_rad(float(drag.a0))
	var a1 := a0 + deg_to_rad(float(drag.deg))
	var poly := PackedVector2Array()
	var cp: Variant = to_px(c)
	if cp == null:
		return
	poly.append(cp)
	for i in 25:
		var a := lerpf(a0, a1, i / 24.0)
		var q: Variant = to_px(c + (uv[0] as Vector3) * cos(a) * r + (uv[1] as Vector3) * sin(a) * r)
		if q != null:
			poly.append(q)
	if poly.size() >= 3 and absf(a1 - a0) > 0.001:
		draw_colored_polygon(poly, Color(col, 0.25))
	for d in range(0, 360, 15):
		var a := deg_to_rad(float(d))
		var big := d % 45 == 0
		var dv := (uv[0] as Vector3) * cos(a) + (uv[1] as Vector3) * sin(a)
		var q0: Variant = to_px(c + dv * r * (0.93 if big else 0.96))
		var q1: Variant = to_px(c + dv * r * (1.07 if big else 1.04))
		if q0 != null and q1 != null:
			draw_line(q0, q1, Color(col, 0.85), 1.6 if big else 1.0)
	var p0: Variant = to_px(c + ((uv[0] as Vector3) * cos(a0) + (uv[1] as Vector3) * sin(a0)) * r)
	var p1: Variant = to_px(c + ((uv[0] as Vector3) * cos(a1) + (uv[1] as Vector3) * sin(a1)) * r)
	if p0 != null:
		draw_dashed_line(cp, p0, Color(Color("DBD1B8"), 0.6), 1.0, EditorUi.px(3))
	if p1 != null:
		draw_line(cp, p1, col, 1.5)
		draw_circle(p1, EditorUi.px(5.5), col)
