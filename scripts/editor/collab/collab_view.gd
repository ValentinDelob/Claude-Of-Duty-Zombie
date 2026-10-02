class_name CollabView
extends Node
## RENDU DE LA COLLABORATION SUR LE PLAN (docs/MAP_COLLAB.md § 6) : curseurs
## des autres (flèche de leur couleur et pseudo, glissés en douceur d'une
## présence à la suivante), leur sélection (contour de leur couleur), l'aperçu
## en direct de ce qu'ils glissent (silhouette), le clignotement des éléments
## touchés par un changement reçu, les lots de Claude (éléments qui
## apparaissent un par un, contour pulsé violet, bulle « Claude : … »), la
## commande highlight de Claude et la surbrillance du panneau Historique.
## Tout est VISUEL : la carte, l'historique et la session ont déjà reçu les
## changements entiers ; ce nœud ne fait que retenir quoi dessiner et le
## dessine dans la vue (MapCanvas._draw_peers l'appelle pendant son dessin).

## Durée du clignotement d'un élément touché par un changement reçu.
const FLASH_SEC := 0.8
## Apparition d'un lot de Claude : un élément toutes les ANIM_STEP s, 1,5 s
## au plus pour tout le lot (plusieurs éléments par image si le lot est gros).
const ANIM_STEP := 0.12
const ANIM_MAX_SEC := 1.5
## Bulle d'un lot de Claude, puis de la commande highlight.
const BUBBLE_SEC := 3.0
const HIGHLIGHT_SEC := 4.0
const FADE_SEC := 0.4
const CLAUDE_COLOR := Color("#a066ff")
## Vitesse du glissement des curseurs vers leur dernière position reçue.
const CURSOR_SMOOTH := 14.0

var ed: MapEditor
## id -> {color: Color, t: float}
var flashes: Dictionary = {}
## Lot de Claude en cours d'apparition : {ids: [à révéler, dans l'ordre],
## step, t, shown: int} ; {} sinon.
var anim: Dictionary = {}
## Éléments d'un lot pas encore apparus (non dessinés).
var hidden: Dictionary = {}
## Éléments entourés d'un contour pulsé violet : {ids, t, life} ; {} sinon.
var pulse: Dictionary = {}
## Bulle de Claude : {text, ids, t, life} ; {} sinon.
var bubble: Dictionary = {}
## Éléments survolés dans le panneau Historique.
var hover_ids: Array = []
## Pair -> {pos: Vector2 affichée, floor}
var cursors: Dictionary = {}
## Pair -> {coll, el} : aperçu en direct validé (presence.live).
var live: Dictionary = {}
var _floor_seen := -1


func setup(editor: MapEditor) -> void:
	ed = editor
	ed.collab.committed.connect(on_committed)
	ed.collab.presence_changed.connect(on_presence)
	ed.collab.peers_changed.connect(_on_peers)
	ed.collab.session_changed.connect(_on_peers)
	ed.collab.map_replaced.connect(clear)


## Vue Dessus et élévations (couches du dessus) redessinées.
func _redraw() -> void:
	ed.canvas.queue_redraw()
	if ed.views != null:
		ed.views.redraw_overlays()


## Tout oublié (autre carte, carte entière reçue).
func clear() -> void:
	flashes.clear()
	anim = {}
	hidden.clear()
	pulse = {}
	bubble = {}
	hover_ids = []
	live.clear()


func active() -> bool:
	return not (flashes.is_empty() and anim.is_empty() and pulse.is_empty() and bubble.is_empty())


func _process(delta: float) -> void:
	if ed == null:
		return
	if ed.floor_k != _floor_seen:
		_floor_seen = ed.floor_k
		if ed.collab_ui != null:
			ed.collab_ui.update_pills()
	var redraw := advance(delta)
	if redraw:
		_redraw()


## Avance les effets de `delta` s ; rend true s'il faut redessiner.
func advance(delta: float) -> bool:
	var redraw := active()
	for id in flashes.keys():
		flashes[id].t += delta
		if float(flashes[id].t) >= FLASH_SEC:
			flashes.erase(id)
	if not anim.is_empty():
		anim.t += delta
		var n := 1 + floori(float(anim.t) / float(anim.step))
		if float(anim.step) < ANIM_STEP:
			# Gros lot : au moins un élément de plus à chaque image.
			n = maxi(n, int(anim.shown) + 1)
		n = mini((anim.ids as Array).size(), n)
		while int(anim.shown) < n:
			hidden.erase(anim.ids[anim.shown])
			anim.shown += 1
		if int(anim.shown) >= (anim.ids as Array).size():
			anim = {}
			hidden.clear()
	for fx in [pulse, bubble]:
		if not fx.is_empty():
			fx.t += delta
	if not pulse.is_empty() and float(pulse.t) >= float(pulse.life):
		pulse = {}
	if not bubble.is_empty() and float(bubble.t) >= float(bubble.life):
		bubble = {}
	# Curseurs : vers la dernière position reçue.
	var k := 1.0 - exp(-CURSOR_SMOOTH * delta)
	for id in cursors:
		var c: Dictionary = cursors[id]
		var to: Vector2 = c.target
		if (c.pos as Vector2).distance_squared_to(to) > 0.0001:
			c.pos = (c.pos as Vector2).lerp(to, k)
			redraw = true
		elif c.pos != to:
			c.pos = to
			redraw = true
	return redraw


# ------------------------------------------------------------------ présence

## Présence reçue d'un pair : cible de son curseur, aperçu en direct validé
## (mêmes règles que les éléments reçus : un aperçu illisible n'est pas dessiné).
func on_presence(peer: String) -> void:
	var p: Dictionary = ed.collab.peers.get(peer, {})
	var pr: Dictionary = p.get("presence", {})
	if pr.has("cursor"):
		var to := Vector2(float(pr.cursor[0]), float(pr.cursor[1]))
		var fl := int(pr.get("floor", 0))
		var c: Dictionary = cursors.get(peer, {})
		if c.is_empty() or int(c.floor) != fl:
			cursors[peer] = {"pos": to, "target": to, "floor": fl}
		else:
			c.target = to
	live.erase(peer)
	var lv: Variant = pr.get("live")
	if lv is Dictionary and lv.get("coll") in ["pieces", "ouvertures", "objets"] and lv.get("el") is Dictionary \
			and (lv.el as Dictionary).get("id") is String:
		var chk := MapOps.check_elements(ed.doc, [{"op": "put", "coll": lv.coll, "el": lv.el}])
		if not (chk.ops as Array).is_empty():
			live[peer] = {"coll": lv.coll, "el": lv.el}
	if ed.collab_ui != null:
		ed.collab_ui.update_pills()
	_redraw()


func _on_peers() -> void:
	for id in cursors.keys():
		if not ed.collab.peers.has(id):
			cursors.erase(id)
	for id in live.keys():
		if not ed.collab.peers.has(id):
			live.erase(id)
	_redraw()


## Collection d'un élément de la carte ("" s'il n'existe pas).
static func coll_of(doc: EditorMap, eid: String) -> String:
	for coll in ["pieces", "ouvertures", "objets", "zones"]:
		for e in MapOps.list(doc, coll):
			if String(e.get("id", "")) == eid:
				return coll
	return ""


# ------------------------------------------------------------------ changements

## Changement confirmé : clignotement des éléments touchés dans la couleur de
## l'auteur s'il vient d'un autre (ou d'une annulation de mon Claude) ; un
## changement qui arrive pendant l'apparition d'un lot la termine tout de suite
## (sauf l'écho de ce lot lui-même chez un invité).
func on_committed(change: Dictionary) -> void:
	var author := String(change.get("author", ""))
	var ids := MapOps.ids_of(change.get("ops", []))
	var mine := author == ed.collab.my_id
	var my_agent := author == ed.collab.my_id + ":claude"
	var undo := change.has("undo") or change.has("redo")
	if not anim.is_empty():
		var echo := my_agent and not undo and ids.any(func(i): return (anim.all as Dictionary).has(i))
		if not echo:
			finish_animation()
	if mine or (my_agent and not undo):
		return
	var col := peer_color(author)
	for id in ids:
		var e := ed.doc.find(String(id))
		if not e.is_empty() and e.has("etage"):
			flashes[String(id)] = {"color": col, "t": 0.0}
	_redraw()


func peer_color(author: String) -> Color:
	if MapHistory.is_agent(author):
		return CLAUDE_COLOR
	var p: Dictionary = ed.collab.peers.get(author, {})
	var html := String(p.get("color", MapCollab.COLORS[0]))
	return Color.html(html) if Color.html_is_valid(html) else Color.html(MapCollab.COLORS[0])


## Lot de Claude (apply avec animate) : déjà appliqué en entier à la carte et
## inscrit dans l'historique (une seule entrée) ; ici, les éléments
## apparaissent un par un, contour pulsé violet, bulle « Claude : <label> ».
func animate(ids: Array, label: String) -> void:
	finish_animation()
	var drawn := []
	for id in ids:
		var e := ed.doc.find(String(id))
		if not e.is_empty() and e.has("etage"):
			drawn.append(String(id))
	if drawn.is_empty():
		return
	var all := {}
	for id in drawn:
		all[id] = true
	var step := minf(ANIM_STEP, ANIM_MAX_SEC / maxf(1.0, drawn.size() - 1))
	anim = {"ids": drawn, "all": all, "step": step, "t": 0.0, "shown": 1}
	hidden = all.duplicate()
	hidden.erase(drawn[0])
	if drawn.size() == 1:
		anim = {}
		hidden.clear()
	pulse = {"ids": drawn, "t": 0.0, "life": BUBBLE_SEC}
	bubble = {"text": Lang.t("Claude : %s", "Claude: %s") % label, "ids": drawn, "t": 0.0, "life": BUBBLE_SEC}
	_bring_into_view(drawn, false)
	_redraw()


## Fin immédiate de l'apparition en cours : tout est montré.
func finish_animation() -> void:
	if anim.is_empty():
		return
	anim = {}
	hidden.clear()
	_redraw()


## Commande highlight de Claude : contour pulsé, bulle avec le message, vue
## amenée sur les éléments s'ils sont hors champ (étage compris), ~4 s.
func highlight(ids: Array, message: String) -> void:
	var drawn := []
	for id in ids:
		var e := ed.doc.find(String(id))
		if not e.is_empty() and e.has("etage"):
			drawn.append(String(id))
	pulse = {"ids": drawn, "t": 0.0, "life": HIGHLIGHT_SEC}
	var text := Lang.t("Claude : %s", "Claude: %s") % message if message != "" else Lang.t("Claude montre %d élément(s)", "Claude shows %d element(s)") % drawn.size()
	bubble = {"text": text, "ids": drawn, "t": 0.0, "life": HIGHLIGHT_SEC}
	_bring_into_view(drawn, true)
	_redraw()


## Rectangle (m) des éléments `ids` à l'étage `k` ; NONE si aucun n'y est.
const NONE := Rect2(Vector2.INF, Vector2.ZERO)


func bounds_of(ids: Array, k: int) -> Rect2:
	var bb := NONE
	var first := true
	for id in ids:
		var e := _find(String(id))
		if e.is_empty() or int(e.get("etage", -1)) != k:
			continue
		var r := ed.canvas.elem_rect_m(e)
		bb = r if first else bb.merge(r)
		first = false
	return bb


## Amène la vue sur les éléments s'ils ne sont pas visibles (autre étage ou
## hors champ) ; jamais pendant un glissement. `zoom_out` : dézoome si le
## groupe est plus grand que la vue.
func _bring_into_view(ids: Array, zoom_out: bool) -> void:
	if ids.is_empty() or not ed.canvas.drag.is_empty():
		return
	var cv := ed.canvas
	var k := ed.floor_k
	var bb := bounds_of(ids, k)
	var view := Rect2(cv.to_m(Vector2.ZERO), cv.size / cv.zoom)
	if bb.position.is_finite() and view.intersects(bb, true):
		return
	if not bb.position.is_finite():
		k = int(ed.doc.find(String(ids[0])).get("etage", k))
		ed.set_floor(k)
		bb = bounds_of(ids, k)
		if not bb.position.is_finite():
			return
	if zoom_out and cv.size.x > 0.0:
		var avail := cv.size * 0.6
		var z := minf(avail.x / maxf(bb.size.x, 1.0), avail.y / maxf(bb.size.y, 1.0))
		if z < cv.zoom:
			cv.zoom = clampf(z, MapCanvas.MIN_ZOOM, MapCanvas.MAX_ZOOM)
	cv.center_on(bb.get_center())


# ------------------------------------------------------------------ dessin

## Dessine par-dessus le plan (appelé pendant MapCanvas._draw) à l'étage `k`.
func draw_on(cv: MapCanvas, font: Font, k: int) -> void:
	# Index des éléments le temps de ce dessin (un lot de Claude peut en
	# compter des centaines, sur une carte de 2000 objets).
	_idx = {}
	for coll in ["pieces", "ouvertures", "objets"]:
		for e in MapOps.list(ed.doc, coll):
			_idx[String(e.get("id", ""))] = e
	_draw_all(cv, font, k)
	_idx = {}


## Dessine par-dessus une élévation (docs/EDITOR_VIEWS.md § 6.4 ; couche du
## dessus de MapElevation) à travers sa projection : aperçus en direct et
## sélections des autres, clignotements, contour pulsé de Claude, curseurs
## (à leur vraie hauteur s'ils sont dans une élévation, sinon un trait
## vertical dans la colonne de leur position).
func draw_on_elevation(ev: MapElevation, c: CanvasItem, font: Font) -> void:
	var session := ed.collab.is_session()
	if session:
		for id in live:
			var el: Dictionary = live[id].el
			var r := ev.element_rect_px(el)
			if r.size == Vector2.ZERO:
				continue
			var col := peer_color(id)
			c.draw_rect(r, Color(col, 0.28))
			c.draw_rect(r, Color(col, 0.85), false, 1.5)
		for id in ed.collab.peers:
			if id == ed.collab.my_id:
				continue
			var pr: Dictionary = ed.collab.peers[id].get("presence", {})
			for sid in pr.get("selection", []):
				var e := ev.projected_of(String(sid))
				if not e.is_empty():
					c.draw_rect(ev.rect_px(e).grow(5.0), peer_color(id), false, 2.0)
	for id in flashes:
		var e := ev.projected_of(String(id))
		if e.is_empty():
			continue
		var f: Dictionary = flashes[id]
		var a := (1.0 - float(f.t) / FLASH_SEC) * (0.55 + 0.45 * cos(float(f.t) * TAU * 3.0))
		c.draw_rect(ev.rect_px(e), Color(f.color, 0.18 * a))
		c.draw_rect(ev.rect_px(e).grow(3.0), Color(f.color, a), false, 3.0)
	if not pulse.is_empty():
		var fade := clampf((float(pulse.life) - float(pulse.t)) / FADE_SEC, 0.0, 1.0)
		var a := (0.6 + 0.4 * sin(float(pulse.t) * TAU * 1.5)) * fade
		for id in pulse.ids:
			var e := ev.projected_of(String(id))
			if not e.is_empty() and not hidden.has(id):
				c.draw_rect(ev.rect_px(e).grow(4.0), Color(CLAUDE_COLOR, a), false, 2.5)
	if not session:
		return
	var s := EditorUi.factor() / Settings.EDITOR_UI_SCALE_DEFAULT
	for id in cursors:
		if id == ed.collab.my_id or not ed.collab.peers.has(id):
			continue
		var cur: Dictionary = cursors[id]
		var pr: Dictionary = ed.collab.peers[id].get("presence", {})
		var col := peer_color(id)
		var pos: Vector2 = cur.pos
		var nm := String(ed.collab.peers[id].name)
		var fs := EditorUi.fs(12)
		var w := font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		if String(pr.get("vue", "")) == ev.plane and pr.has("z"):
			var at := ev.project(Vector3(pos.x, pos.y, float(pr.z)))
			var arrow := PackedVector2Array()
			for v in [Vector2(0, 0), Vector2(0, 17), Vector2(4.5, 13), Vector2(7.5, 19.5), Vector2(10, 18.5), Vector2(7, 12), Vector2(12.5, 12)]:
				arrow.append(at + v * s)
			c.draw_colored_polygon(arrow, col)
			c.draw_polyline(arrow + PackedVector2Array([arrow[0]]), Color(0, 0, 0, 0.9), 1.0)
			var box := Rect2(at + Vector2(13, 17) * s, Vector2(w + 8 * s, fs + 5 * s))
			c.draw_rect(box, col)
			c.draw_string(font, box.position + Vector2(4 * s, fs + 1 * s), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.05, 0.05, 0.06))
		else:
			# Pas dans cette vue : un trait vertical dans la colonne de sa position.
			var x := ev.project(Vector3(pos.x, pos.y, 0.0)).x
			if x < ev._ruler() or x > ev.size.x:
				continue
			c.draw_dashed_line(Vector2(x, ev._ruler()), Vector2(x, ev.size.y), Color(col, 0.6), 1.0, EditorUi.px(5))
			var box := Rect2(Vector2(x + 3 * s, ev._ruler() + 2 * s), Vector2(w + 8 * s, fs + 5 * s))
			c.draw_rect(box, Color(col, 0.85))
			c.draw_string(font, box.position + Vector2(4 * s, fs + 1 * s), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.05, 0.05, 0.06))


## Élément `eid` (index du dessin en cours, sinon recherche dans la carte).
func _find(eid: String) -> Dictionary:
	if not _idx.is_empty():
		return _idx.get(eid, {})
	return ed.doc.find(eid)


var _idx: Dictionary = {}


func _draw_all(cv: MapCanvas, font: Font, k: int) -> void:
	var session := ed.collab.is_session()
	if session:
		# Aperçus en direct (silhouettes) et sélections des autres.
		for id in live:
			var el: Dictionary = live[id].el
			if int(el.get("etage", 0)) != k:
				continue
			var col := peer_color(id)
			cv.fill_elem(el, Color(col, 0.28))
			cv.outline_elem(el, Color(col, 0.85), 1.5, 0.0)
		for id in ed.collab.peers:
			if id == ed.collab.my_id:
				continue
			var pr: Dictionary = ed.collab.peers[id].get("presence", {})
			for sid in pr.get("selection", []):
				var e := _find(String(sid))
				if e.is_empty() or int(e.get("etage", 0)) != k:
					continue
				cv.outline_elem(e, peer_color(id), 2.0, 5.0)
	# Changements reçus : clignotement dans la couleur de l'auteur.
	for id in flashes:
		var e := _find(String(id))
		if e.is_empty() or int(e.get("etage", 0)) != k:
			continue
		var f: Dictionary = flashes[id]
		var a := (1.0 - float(f.t) / FLASH_SEC) * (0.55 + 0.45 * cos(float(f.t) * TAU * 3.0))
		cv.fill_elem(e, Color(f.color, 0.18 * a))
		cv.outline_elem(e, Color(f.color, a), 3.0, 3.0)
	# Lot ou highlight de Claude : contour pulsé violet.
	if not pulse.is_empty():
		var fade := clampf((float(pulse.life) - float(pulse.t)) / FADE_SEC, 0.0, 1.0)
		var a := (0.6 + 0.4 * sin(float(pulse.t) * TAU * 1.5)) * fade
		for id in pulse.ids:
			if hidden.has(id):
				continue
			var e := _find(String(id))
			if e.is_empty() or int(e.get("etage", 0)) != k:
				continue
			cv.outline_elem(e, Color(CLAUDE_COLOR, a), 2.5, 4.0)
	# Survol d'une entrée du panneau Historique.
	for id in hover_ids:
		var e := _find(String(id))
		if not e.is_empty() and int(e.get("etage", 0)) == k:
			cv._draw_glow(e)
	if session:
		_draw_cursors(cv, font, k)
	if not bubble.is_empty():
		_draw_bubble(cv, font, k)


func _draw_cursors(cv: MapCanvas, font: Font, k: int) -> void:
	# Flèche et étiquette à leur taille à la taille d'interface par défaut.
	var s := EditorUi.factor() / Settings.EDITOR_UI_SCALE_DEFAULT
	for id in cursors:
		if id == ed.collab.my_id or not ed.collab.peers.has(id):
			continue
		var c: Dictionary = cursors[id]
		if int(c.floor) != k:
			continue
		var col := peer_color(id)
		var at := cv.to_px(c.pos)
		var arrow := PackedVector2Array()
		for v in [Vector2(0, 0), Vector2(0, 17), Vector2(4.5, 13), Vector2(7.5, 19.5), Vector2(10, 18.5), Vector2(7, 12), Vector2(12.5, 12)]:
			arrow.append(at + v * s)
		cv.draw_colored_polygon(arrow, col)
		cv.draw_polyline(arrow + PackedVector2Array([arrow[0]]), Color(0, 0, 0, 0.9), 1.0)
		var nm := String(ed.collab.peers[id].name)
		var fs := EditorUi.fs(12)
		var w := font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var box := Rect2(at + Vector2(13, 17) * s, Vector2(w + 8 * s, fs + 5 * s))
		cv.draw_rect(box, col)
		cv.draw_string(font, box.position + Vector2(4 * s, fs + 1 * s), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.05, 0.05, 0.06))


## Bulle « Claude : … » près des éléments (au-dessus de leur groupe, dans la vue).
func _draw_bubble(cv: MapCanvas, font: Font, k: int) -> void:
	var text := String(bubble.text)
	var fade := clampf((float(bubble.life) - float(bubble.t)) / FADE_SEC, 0.0, 1.0)
	var fs := EditorUi.fs(14)
	var pad := EditorUi.px(9)
	var icon := float(fs) + EditorUi.px(4)
	var max_w := maxf(120.0, cv.size.x * 0.6)
	var tw := minf(font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x, max_w - icon - pad * 3)
	var sz := Vector2(tw + icon + pad * 3, maxf(icon, float(fs)) + pad * 2)
	var bb := bounds_of(bubble.ids, k)
	var anchor := cv.size * Vector2(0.5, 0.0) + Vector2(0, EditorUi.px(40))
	if bb.position.is_finite():
		anchor = cv.to_px(Vector2(bb.get_center().x, bb.position.y))
	var pos := anchor - Vector2(sz.x * 0.5, sz.y + EditorUi.px(12))
	var lo := Vector2(EditorUi.px(26), EditorUi.px(26))
	pos = pos.clamp(lo, (cv.size - sz - Vector2(EditorUi.px(6), EditorUi.px(90))).max(lo))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.11, 0.09, 0.15, 0.95 * fade)
	sb.border_color = Color(CLAUDE_COLOR, fade)
	sb.set_border_width_all(maxi(1, roundi(EditorUi.px(2))))
	sb.set_corner_radius_all(roundi(EditorUi.px(8)))
	cv.draw_style_box(sb, Rect2(pos, sz))
	draw_claude_icon(cv, pos + Vector2(pad + icon * 0.5, sz.y * 0.5), icon * 0.5, Color(CLAUDE_COLOR, fade), Color(1, 1, 1, fade))
	cv.draw_string(font, pos + Vector2(pad * 2 + icon, sz.y * 0.5 + fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, tw, fs, Color(1, 1, 1, fade))


## Icône de Claude : disque violet et étoile à huit branches (pastilles, bulles).
static func draw_claude_icon(ci: CanvasItem, c: Vector2, r: float, bg: Color, fg: Color) -> void:
	ci.draw_circle(c, r, bg)
	var w := maxf(1.0, r * 0.18)
	for i in 8:
		var a := i * TAU / 8.0 + PI / 8.0
		var len := r * (0.68 if i % 2 == 0 else 0.5)
		ci.draw_line(c + Vector2.from_angle(a) * r * 0.12, c + Vector2.from_angle(a) * len, fg, w, true)
