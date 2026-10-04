class_name MapAgentLink
extends Node
## LIAISON AGENT (Claude, via le pont MCP tools/mcp/map_editor_mcp.py ;
## docs/MAP_COLLAB.md § 5.2) : écoute sur 127.0.0.1 seulement (port 7791, ou
## le suivant libre jusqu'à 7799), jeton tiré au hasard. Le port et le jeton
## sont écrits dans user://editor_collab/agent.json ({port, token, pid,
## map_id}), supprimé à l'arrêt. Requête {id, cmd, args} -> réponse {id, ok,
## result | error} ; première requête obligatoire : hello avec le jeton.
## Les changements de Claude passent par la session (MapCollab) comme ceux
## d'un auteur « <moi>:claude » : un lot = une entrée d'historique, annulable
## par Ctrl+Z de la personne qui l'a lancé.

## Points d'accroche du rendu riche (contour pulsé, apparition un par un,
## bulle) : l'éditeur reçoit ces signaux après une commande highlight ou un
## lot apply avec animate.
signal highlight_requested(ids: Array, message: String)
signal animate_requested(ids: Array, label: String)

const HOST := "127.0.0.1"
const FIRST_PORT := 7791
const LAST_PORT := 7799
const MAX_LINE := MapOps.MAX_BYTES
const MAX_CLIENTS := 4
const HELLO_SEC := 5.0
const SHOT_SIZE := Vector2i(1280, 960)

## Dossier de agent.json (tests : un dossier à eux, jamais celui du joueur).
static var dir_override := ""

var collab: MapCollab
## Éditeur (sélection, étage, curseur, capture) ; null : sans interface.
var editor: Node
var port := 0
var token := ""
var _server: TCPServer
var _clients: Array = []


class Client:
	var tcp: StreamPeerTCP
	var buf := PackedByteArray()
	var authed := false
	var age := 0.0
	var closed := false
	var busy := false


static func dir() -> String:
	if dir_override != "":
		return dir_override
	if AutotestMode.is_running():
		return ProjectSettings.globalize_path("res://tests/_out/editor_collab_%s" % AutotestMode.scenario_name())
	return "user://editor_collab"


static func file_path() -> String:
	return dir().path_join("agent.json")


func is_running() -> bool:
	return _server != null


## Écoute sur le premier port libre de 7791 à 7799 (`first` : autre plage,
## tests) et écrit agent.json. Rend OK ou l'erreur.
func start(first := FIRST_PORT, last := LAST_PORT) -> Error:
	stop()
	var err := ERR_CANT_OPEN
	for p in range(first, last + 1):
		var srv := TCPServer.new()
		err = srv.listen(p, HOST)
		if err == OK:
			_server = srv
			port = p
			break
	if err != OK:
		push_warning("[MapAgentLink] aucun port libre de %d à %d" % [first, last])
		return err
	token = Crypto.new().generate_random_bytes(16).hex_encode()
	write_file()
	collab.committed.connect(_on_committed)
	collab.peers_changed.connect(_on_peers)
	return OK


## agent.json (à refaire quand la carte change : map_id).
func write_file() -> void:
	if _server == null:
		return
	DirAccess.make_dir_recursive_absolute(dir())
	var f := FileAccess.open(file_path(), FileAccess.WRITE)
	if f == null:
		push_warning("[MapAgentLink] agent.json non écrit (%s)" % error_string(FileAccess.get_open_error()))
		return
	f.store_string(JSON.stringify({"port": port, "token": token, "pid": OS.get_process_id(), "map_id": collab.doc.id()}))
	f.close()


func stop() -> void:
	for c in _clients:
		c.tcp.disconnect_from_host()
	_clients.clear()
	if _server == null:
		return
	_server.stop()
	_server = null
	if collab.committed.is_connected(_on_committed):
		collab.committed.disconnect(_on_committed)
		collab.peers_changed.disconnect(_on_peers)
	collab.set_agent(false)
	# Seulement notre fichier (un autre éditeur ouvert après l'a peut-être remplacé).
	var txt: Variant = EditorMap.read_text(file_path(), 4096)
	var d: Variant = JSON.parse_string(txt) if txt != null else null
	if d is Dictionary and int(d.get("pid", -1)) == OS.get_process_id() and int(d.get("port", -1)) == port:
		DirAccess.remove_absolute(file_path())


func _exit_tree() -> void:
	stop()


func _process(delta: float) -> void:
	if _server == null:
		return
	while _server.is_connection_available():
		var tcp := _server.take_connection()
		if _clients.size() >= MAX_CLIENTS:
			tcp.disconnect_from_host()
			continue
		var c := Client.new()
		c.tcp = tcp
		_clients.append(c)
	for c: Client in _clients.duplicate():
		c.age += delta
		c.tcp.poll()
		if c.tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED or (not c.authed and c.age > HELLO_SEC):
			_close(c)
			continue
		if c.busy:
			continue
		var n := c.tcp.get_available_bytes()
		if n > 0:
			var r: Array = c.tcp.get_partial_data(mini(n, MAX_LINE + 1))
			if r[0] == OK:
				c.buf.append_array(r[1])
		while not c.closed and not c.busy:
			var i := c.buf.find(10)
			if i < 0:
				if c.buf.size() > MAX_LINE:
					_close(c)
				break
			var line := c.buf.slice(0, i)
			c.buf = c.buf.slice(i + 1)
			if not line.is_empty():
				_handle(c, line.get_string_from_utf8())
	var agents := _clients.any(func(x): return x.authed and not x.closed)
	if agents != collab.agent_on:
		collab.set_agent(agents)


func _close(c: Client) -> void:
	c.closed = true
	c.tcp.disconnect_from_host()
	_clients.erase(c)


func _reply(c: Client, msg: Dictionary) -> void:
	if c.closed:
		return
	var b := (JSON.stringify(msg, "", false, true) + "\n").to_utf8_buffer()
	if b.size() > MAX_LINE:
		b = (JSON.stringify({"id": msg.get("id"), "ok": false, "error": "réponse trop grosse / reply too big"}) + "\n").to_utf8_buffer()
	c.tcp.put_data(b)


func _push(msg: Dictionary) -> void:
	for c in _clients:
		if c.authed and not c.closed:
			_reply(c, msg)


func _handle(c: Client, text: String) -> void:
	var j := JSON.new()
	if j.parse(text) != OK or not j.data is Dictionary:
		_reply(c, {"id": null, "ok": false, "error": "JSON invalide / invalid JSON"})
		if not c.authed:
			_close(c)
		return
	var req: Dictionary = j.data
	var id: Variant = req.get("id")
	if not (id == null or id is String or id is float or id is int):
		id = null
	var cmd := String(req.get("cmd", "")) if req.get("cmd") is String else ""
	var args: Dictionary = req.get("args") if req.get("args") is Dictionary else {}
	if not c.authed:
		if cmd != "hello" or not (args.get("token") is String and _same(String(args.token), token)):
			_reply(c, {"id": id, "ok": false, "error": Lang.t("jeton refusé : hello avec le jeton de agent.json d'abord", "token refused: hello with the agent.json token first")})
			_close(c)
			return
		c.authed = true
		_reply(c, {"id": id, "ok": true, "result": _hello()})
		return
	var res: Variant
	match cmd:
		"hello":
			res = _hello()
		"status":
			res = _status()
		"get_map":
			res = collab.doc.snapshot()
		"get_selection":
			res = _selection()
		"get_elements":
			res = cmd_get_elements(args)
		"apply":
			res = cmd_apply(args)
		"undo":
			res = cmd_undo()
		"validate":
			res = cmd_validate()
		"screenshot":
			c.busy = true
			res = await cmd_screenshot(args)
			c.busy = false
		"highlight":
			res = cmd_highlight(args)
		"catalog":
			res = catalog()
		_:
			res = {"error": Lang.t("commande inconnue : %s", "unknown command: %s") % cmd.left(40)}
	if res is Dictionary and (res as Dictionary).size() == 1 and (res as Dictionary).has("error"):
		_reply(c, {"id": id, "ok": false, "error": String(res.error)})
	else:
		_reply(c, {"id": id, "ok": true, "result": res})


## Comparaison de jetons sans sortie anticipée.
static func _same(a: String, b: String) -> bool:
	if a.length() != b.length() or b.is_empty():
		return false
	var d := 0
	for i in a.length():
		d |= a.unicode_at(i) ^ b.unicode_at(i)
	return d == 0


# ------------------------------------------------------------------ commandes

func _hello() -> Dictionary:
	return {"map_id": collab.doc.id(), "map_name": collab.doc.display_name(), "role": collab.role_name(), "peers": collab.peer_list(),
		"editor_version": String(ProjectSettings.get_setting("application/config/version", "")), "you": collab.my_id + ":claude"}


func _status() -> Dictionary:
	var d := _hello()
	var s := _selection()
	d["floor"] = s.floor
	d["selection"] = s.ids
	d["dirty"] = bool(editor.get("dirty")) if editor != null else false
	d["seq"] = collab.seq
	d["can_undo"] = collab.history.can_undo(collab.my_id, true)
	return d


func _selection() -> Dictionary:
	var ids := []
	var floor_k := 0
	var cursor := [0.0, 0.0]
	if editor != null:
		# Sélection multiple (MapGroup) : tous les éléments choisis.
		if editor.has_method("sel_ids"):
			ids = editor.sel_ids()
		else:
			var sel := String(editor.get("selected"))
			if sel != "":
				ids.append(sel)
		floor_k = int(editor.get("floor_k"))
		var cv: Variant = editor.get("canvas")
		if cv != null:
			var m: Vector2 = cv.mouse_m
			cursor = [snappedf(m.x, 0.01), snappedf(m.y, 0.01)]
	var els := []
	for eid in ids:
		var e := collab.doc.find(eid)
		if not e.is_empty():
			els.append(e)
	return {"ids": ids, "elements": els, "floor": floor_k, "cursor": cursor}


## apply : un lot = un changement d'auteur « <moi>:claude ». `add` admis (ids
## provisoires « $n »). Les éléments au contenu refusé (types, clés, valeurs)
## ne sont pas appliqués ; ceux mal placés (MapRules, dessinés en rouge) le
## sont : les deux sont listés dans `invalid`.
func cmd_apply(args: Dictionary) -> Dictionary:
	var ops: Variant = args.get("ops")
	var err := MapOps.validate(ops, true)
	if err != "":
		return {"error": err}
	var label := String(args.get("label", "")).left(120) if args.get("label") is String else ""
	if label == "":
		label = Lang.t("Changement de Claude", "Claude's change")
	MapOps.normalize(ops)
	var res := MapOps.resolve_adds(collab.doc, ops)
	var chk := MapOps.check_elements(collab.doc, res.ops)
	# Format 14 : échelle et inclinaison arrondies à leur pas, défauts retirés ;
	# mêmes règles que dans l'éditeur (MapScale.check : plafond, décor posé
	# dessus, chevauchements) quand elles changent : refus nommé sinon.
	var scale_v: MapValidator = null
	var kept := []
	for op in chk.ops:
		if op is Dictionary and String(op.get("coll", "")) == "objets" and op.get("el") is Dictionary:
			var el: Dictionary = op.el
			# Nombre de marches d'un escalier : plus réglable (toujours
			# automatique) ; refus nommé plutôt qu'un réglage ignoré en silence.
			if String(el.get("type", "")) == "escalier" and el.has("marches"):
				chk.invalid[String(el.get("id", ""))] = Lang.t("le nombre de marches n'est plus réglable (toujours automatique, ≈ 18 cm par marche) : retire « marches »",
					"the number of steps can no longer be set (always automatic, ≈ 18 cm per step): remove \"marches\"")
				continue
			MapCatalog.tidy_stair(el)
			MapScale.tidy(el)
			var before := collab.doc.find(String(el.get("id", "")))
			var changed := MapScale.transformed(el) and (before.is_empty() or not MapScale.scale_of(before).is_equal_approx(MapScale.scale_of(el))
				or not MapScale.incl_of(before).is_equal_approx(MapScale.incl_of(el)))
			if changed:
				if scale_v == null:
					scale_v = MapRaster.build(collab.doc).v
				var r := MapScale.check(collab.doc, scale_v, el, before)
				if not r.get("ok", false):
					chk.invalid[String(el.get("id", ""))] = MapRules.why(r)
					continue
		kept.append(op)
	chk.ops = kept
	var invalid: Dictionary = chk.invalid
	var good: Array = chk.ops
	# Pièce posée par-dessus d'autres (MapCarve) : refus expliqué, ou avec
	# « decouper »: true, découpe des pièces recouvertes dans le MÊME lot (une
	# seule annulation).
	var cut := MapCarve.carve_ops(collab.doc, good, args.get("decouper") is bool and bool(args.decouper))
	if not cut.ok:
		return {"error": MapRules.why(cut)}
	good = cut.ops
	var cid := ""
	if not good.is_empty():
		cid = String(collab.submit_ops(good, Lang.t("Claude : %s", "Claude: %s") % label, collab.my_id + ":claude").cid)
	var ids := MapOps.ids_of(good)
	MapRules.begin_batch(collab.doc)
	for eid in ids:
		var e := collab.doc.find(eid)
		if e.is_empty() or not (e.has("contour") or e.has("type")):
			continue
		var r := MapRules.check_existing(collab.doc, e)
		if not r.ok:
			invalid[eid] = MapRules.why(r)
	MapRules.end_batch()
	if bool(args.get("animate", true)) and not ids.is_empty():
		animate_requested.emit(ids, label)
	var out := {"cid": cid, "ids": res.ids, "invalid": invalid}
	if not (cut.reports as Array).is_empty():
		out["decoupe"] = (cut.reports as Array).map(func(r): return MapCarve.summary(r))
	return out


func cmd_undo() -> Dictionary:
	var r := collab.request_undo(true)
	if r.is_empty():
		return {"error": Lang.t("rien à annuler (aucun changement de Claude encore actif)", "nothing to undo (no active Claude change)")}
	if r.has("queued"):
		return {"queued": true}
	return {"cid": r.cid, "undone": r.undo, "label": r.label, "skipped": r.skipped, "conflict": collab.conflict_text(r)}


func cmd_validate() -> Dictionary:
	var v := MapRaster.build(collab.doc).v
	v.analyze()
	var problems := []
	for m in v.messages:
		var pts := []
		for cc in (m.get("cells", []) as Array).slice(0, 12):
			var p := MapGeom.cell_center(cc)
			pts.append([snappedf(p.x, 0.01), snappedf(p.y, 0.01)])
		problems.append({"level": m.level, "text": MapValidator.text_of(m), "floor": int(m.get("floor", -1)), "points": pts})
	return {"ok": v.ok(), "errors": v.errors().size(), "warnings": v.warnings().size(), "text": v.report_text(), "problems": problems}


## Éléments complets d'après leurs ids, avec leur collection et leurs
## hauteurs (docs/EDITOR_VIEWS.md § 6.4) : `z_min` / `z_max` (m, absolus :
## la boîte de l'élément, plafond réel compris), `z_monde` (altitude de son
## point de pose : sol de l'étage + hauteur de pose), `hauteur_pose` (m
## au-dessus du sol, quand le type en a une) et `glissement_vertical`
## (« pose », « niveau » ou « fixe »).
func cmd_get_elements(args: Dictionary) -> Dictionary:
	var ids: Array = (args.get("ids") as Array).slice(0, 500) if args.get("ids") is Array else []
	var doc := collab.doc
	var v := MapRaster.build(doc).v
	var found := {}
	var missing := []
	for eid in ids:
		if not eid is String:
			continue
		var e := doc.find(eid)
		if e.is_empty():
			missing.append(eid)
			continue
		var coll := CollabView.coll_of(doc, eid)
		var d := {"coll": coll, "el": e}
		if coll != "zones":
			var it := MapElevationItems.item_of(doc, v, e)
			if not it.is_empty():
				d["z_min"] = snappedf(float(it.z0), 0.01)
				d["z_max"] = snappedf(float(it.z1), 0.01)
			var k := int(e.get("etage", 0))
			var sol := doc.floor_sol(k) if k < doc.floor_count() else 0.0
			var kind := MapVertical.pose_kind(e)
			d["glissement_vertical"] = kind
			if kind == "pose":
				var z := MapVertical.pose_z(doc, v, e)
				d["hauteur_pose"] = snappedf(z, 0.01)
				d["z_monde"] = snappedf(sol + z, 0.01)
			else:
				d["z_monde"] = snappedf(sol, 0.01)
			# Format 14 : dimensions finales, échelle et inclinaison possibles (raison sinon).
			if coll == "objets" and e.has("type"):
				d.merge(scale_info(e))
		found[eid] = d
	return {"elements": found, "absents": missing}


## Format 14 (docs/EDITOR_SCALE_ROTATE.md § 6) : `dimensions` [l, p, h] finales
## (m, décor), `echelle_possible`, `inclinaison_possible` et `raison` (qui
## nomme l'objet de jeu d'un prefab bloqué).
static func scale_info(e: Dictionary) -> Dictionary:
	var out := {"echelle_possible": MapScale.scalable(e), "inclinaison_possible": MapScale.tiltable(e)}
	if String(e.get("type", "")) == "prefab" and not MapScale.def_of(e).is_empty():
		var dm := MapScale.dims(e)
		out["dimensions"] = [snappedf(dm.x, 0.01), snappedf(dm.y, 0.01), snappedf(MapScale.height(e), 0.01)]
	var why := MapScale.scale_refusal(e)
	if why.is_empty():
		why = MapScale.tilt_refusal(e)
	if not why.is_empty():
		out["raison"] = Lang.t(String(why[0]), String(why[1]))
	return out


## Image du plan à l'étage demandé (cadrée sur `ids` s'il est donné), dessinée
## hors écran (SubViewport) : ne dépend pas de ce qui est affiché. `view`
## (docs/EDITOR_VIEWS.md § 6.4) : « dessus » (défaut) ou une élévation
## (« avant », « arriere », « gauche », « droite », « dessous »), avec une
## `coupe` [p0, p1] facultative (tranche de profondeur, m).
func cmd_screenshot(args: Dictionary) -> Dictionary:
	var view := String(args.get("view", "dessus")) if args.get("view") is String else "dessus"
	if view != "dessus":
		return await _screenshot_view(args, view)
	if DisplayServer.get_name() == "headless":
		return {"error": Lang.t("capture impossible : éditeur lancé sans affichage (--headless)", "screenshot unavailable: editor started without display (--headless)")}
	if editor == null:
		return {"error": Lang.t("capture impossible sans éditeur", "screenshot unavailable without the editor")}
	var doc := collab.doc
	var k := clampi(int(args.get("floor", editor.get("floor_k"))) if (args.get("floor") is float or args.get("floor") is int) else int(editor.get("floor_k")), 0, doc.floor_count() - 1)
	var bb := Rect2()
	var first := true
	var ids: Array = args.get("ids") if args.get("ids") is Array else []
	for eid in ids.slice(0, 500):
		var e := doc.find(String(eid))
		if e.is_empty() or e.get("nom") is Dictionary:
			continue
		if not args.has("floor") and e.has("etage"):
			k = int(e.etage)
		var r := MapGeom.bbox(doc.room_poly(e)) if e.has("contour") else MapRules.footprint_rect(e)
		bb = r if first else bb.merge(r)
		first = false
	if first:
		for p in doc.rooms_on(k):
			var r := MapGeom.bbox(doc.room_poly(p))
			bb = r if first else bb.merge(r)
			first = false
	if first:
		bb = Rect2(0, 0, 30, 20)
	bb = bb.grow(3.0)
	var vp := SubViewport.new()
	vp.size = SHOT_SIZE
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# Taille fixe en pixels : hors de la mise à l'échelle de l'éditeur.
	vp.set_meta(EditorUi.SKIP, true)
	var cv := MapCanvas.new()
	cv.ed = editor
	cv.offscreen = true
	cv.floor_override = k
	cv.size = Vector2(SHOT_SIZE)
	cv.zoom = clampf(minf(SHOT_SIZE.x / maxf(bb.size.x, 1.0), SHOT_SIZE.y / maxf(bb.size.y, 1.0)), 1.0, 120.0)
	cv.origin = Vector2(SHOT_SIZE) * 0.5 - bb.get_center() * cv.zoom
	vp.add_child(cv)
	add_child(vp)
	for i in 3:
		await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	var m0 := cv.to_m(Vector2.ZERO)
	var m1 := cv.to_m(Vector2(SHOT_SIZE))
	vp.queue_free()
	if img == null or img.is_empty():
		return {"error": Lang.t("capture vide", "empty screenshot")}
	var png := img.save_png_to_buffer()
	return {"png_base64": Marshalls.raw_to_base64(png), "width": img.get_width(), "height": img.get_height(), "floor": k,
		"bounds": [snappedf(m0.x, 0.01), snappedf(m0.y, 0.01), snappedf(m1.x, 0.01), snappedf(m1.y, 0.01)]}


## Capture d'une élévation (hors écran) cadrée sur `ids` ou sur toute la carte.
func _screenshot_view(args: Dictionary, view: String) -> Dictionary:
	if not view in MapView.PLANES:
		return {"error": Lang.t("vue inconnue « %s » (dessus, avant, arriere, gauche, droite, dessous)", "unknown view \"%s\" (dessus, avant, arriere, gauche, droite, dessous)") % view.left(24)}
	if DisplayServer.get_name() == "headless":
		return {"error": Lang.t("capture impossible : éditeur lancé sans affichage (--headless)", "screenshot unavailable: editor started without display (--headless)")}
	if editor == null:
		return {"error": Lang.t("capture impossible sans éditeur", "screenshot unavailable without the editor")}
	var vp := SubViewport.new()
	vp.size = SHOT_SIZE
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.set_meta(EditorUi.SKIP, true)
	var ev := MapElevation.new()
	ev.ed = editor
	ev.offscreen = true
	ev.plane = view
	ev.size = Vector2(SHOT_SIZE)
	vp.add_child(ev)
	add_child(vp)
	var c: Variant = args.get("coupe")
	if c is Array and (c as Array).size() == 2 and (c[0] is float or c[0] is int) and (c[1] is float or c[1] is int):
		ev.coupe = [minf(float(c[0]), float(c[1])), maxf(float(c[0]), float(c[1]))]
		ev.coupe_mode = "perso"
	# Cadrage : les éléments demandés, sinon toute la carte.
	var ids: Array = args.get("ids") if args.get("ids") is Array else []
	var bb := Rect2()
	var first := true
	for eid in ids.slice(0, 500):
		var e := ev.projected_of(String(eid))
		if e.is_empty():
			continue
		var r := Rect2(float(e.u0), float(e.v0), float(e.u1) - float(e.u0), float(e.v1) - float(e.v0))
		bb = r if first else bb.merge(r)
		first = false
	if first:
		ev.frame_all()
	else:
		bb = bb.grow(3.0)
		ev.zoom = clampf(minf(SHOT_SIZE.x / maxf(bb.size.x, 1.0), SHOT_SIZE.y / maxf(bb.size.y, 1.0)), 1.0, 120.0)
		ev.origin = Vector2(SHOT_SIZE) * 0.5 - bb.get_center() * ev.zoom
	ev.queue_redraw()
	for i in 3:
		await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	var m0 := ev.to_m(Vector2.ZERO)
	var m1 := ev.to_m(Vector2(SHOT_SIZE))
	vp.queue_free()
	if img == null or img.is_empty():
		return {"error": Lang.t("capture vide", "empty screenshot")}
	var hs := float(MapView.h_axis(view)[1])
	var out := {"png_base64": Marshalls.raw_to_base64(img.save_png_to_buffer()), "width": img.get_width(), "height": img.get_height(), "view": view}
	if MapView.is_elevation(view):
		# Bornes : l'axe horizontal de l'écran (vraies coordonnées, de gauche à
		# droite) et Z (du bas vers le haut).
		out["axe_horizontal"] = String(MapView.h_axis(view)[0])
		out["bounds_h"] = [snappedf(m0.x * hs, 0.01), snappedf(m1.x * hs, 0.01)]
		out["bounds_z"] = [snappedf(-m1.y, 0.01), snappedf(-m0.y, 0.01)]
	else:
		out["bounds"] = [snappedf(-m0.x, 0.01), snappedf(m0.y, 0.01), snappedf(-m1.x, 0.01), snappedf(m1.y, 0.01)]
	if ev.coupe.size() == 2:
		out["coupe"] = ev.coupe
	return out


## highlight : montre des éléments à la personne (version simple : choix et
## cadrage du premier, message dans la barre d'état ; signal pour le rendu riche).
## « select » vrai : ils deviennent aussi la sélection de l'éditeur (plusieurs :
## sélection multiple), pour que la personne agisse dessus (clic droit...).
func cmd_highlight(args: Dictionary) -> Dictionary:
	var ids: Array = (args.get("ids") as Array).filter(func(x): return x is String and not collab.doc.find(x).is_empty()) if args.get("ids") is Array else []
	var msg := String(args.get("message", "")).left(300) if args.get("message") is String else ""
	if editor != null and editor.has_method("agent_highlight"):
		editor.agent_highlight(ids, msg)
	highlight_requested.emit(ids, msg)
	var out := {"shown": ids.size()}
	if args.get("select") is bool and bool(args.select) and editor != null and editor.has_method("select_many"):
		if editor.has_method("gesture_busy") and editor.gesture_busy():
			# Geste en cours (déplacement, anneau, poignée, tracé) : changer la
			# sélection l'annulerait et remettrait la carte. Sélection inchangée,
			# Claude réessaie plus tard ; seuls les éléments sont montrés.
			out["selected"] = editor.sel_ids()
			out["busy"] = "l'utilisateur est en train de modifier la carte (geste en cours) : sélection inchangée, réessaie dans un instant"
			return out
		editor.select_many(ids)
		out["selected"] = editor.sel_ids()
	return out


## Types admis et listes de choix (MapCatalog) : de quoi écrire des opérations
## valides sans lire le code.
static func catalog() -> Dictionary:
	var items := []
	for it in MapCatalog.items():
		var entry := {"id": it.id, "cat": it.cat, "fr": it.get("fr", ""), "en": it.get("en", ""), "tool": it.get("tool", ""),
			"make": jsonable(it.get("make", {})), "price": it.get("price", 0)}
		# Format 14 : objets qui ne changent jamais d'échelle (tout sauf le décor).
		if not MapScale.scalable(it.get("make", {})):
			entry["echelle"] = false
		if it.get("descend", false):
			# Outil de l'éditeur seulement : la carte n'a qu'un type d'escalier.
			entry["descend"] = true
			entry["note"] = "escalier qui descend de l'étage k : écrire un « escalier » d'etage k - 1 dont « monte » pointe vers l'endroit où l'on arrive en haut"
		if it.get("wall_snap", false):
			# Format 15 : boîte mystère au sol ou contre un mur.
			entry["note"] = "au sol : « position » = centre et « rot » (0 : avant au sud), sans « mur » ; contre un mur : « position » sur le trait et « mur » (+ « angle »), sans « rot »"
		items.append(entry)
	var prefabs := {}
	for p in MapCatalog.PREFABS:
		var d: Dictionary = MapCatalog.PREFABS[p]
		prefabs[p] = {"fr": d.get("fr", ""), "en": d.get("en", ""), "fp": jsonable(d.get("fp", [1, 1])), "h": d.get("h", 0.0), "bloque": d.get("bloque", ""),
			"mount": d.get("mount", "sol"), "inclinaison": String(d.get("mount", "sol")) == "sol"}
		if d.has("y"):
			prefabs[p]["y"] = d.y
	# Format 10 : prefabs de la carte ouverte (« prefab » : « map:<pid> »).
	for it in MapCatalog.map_items():
		var d := MapCatalog.prefab_def(String(it.make.prefab))
		prefabs[String(it.make.prefab)] = {"fr": d.get("fr", ""), "en": d.get("en", ""), "fp": jsonable(d.get("fp", [1, 1])), "h": d.get("h", 0.0), "bloque": d.get("bloque", ""), "map": true}
		if d.has("fixe"):
			# Format 14 : prefab qui contient un objet de jeu : échelle bloquée.
			prefabs[String(it.make.prefab)]["echelle"] = false
			prefabs[String(it.make.prefab)]["inclinaison"] = false
			prefabs[String(it.make.prefab)]["raison"] = MapScale.names_text(d.fixe)[0 if not Lang.is_en() else 1]
	var lights := {}
	for l in MapCatalog.LIGHTS:
		var d: Dictionary = MapCatalog.LIGHTS[l]
		lights[l] = {"fr": d.get("fr", ""), "en": d.get("en", ""), "mount": d.get("mount", ""), "fp": jsonable(d.get("fp", [1, 1]))}
	# Format 11 : effets purs (aucun objet : le décor qui va avec est dans
	# « decor »), zone en m : « dims » = ordre de la clé « zone » de l'objet,
	# « zone » = {dimension: [défaut, min, max]}.
	var effects := {}
	for f in MapCatalog.EFFECTS:
		var d: Dictionary = MapCatalog.EFFECTS[f]
		effects[f] = {"fr": d.fr, "en": d.en, "sub": d.sub, "mount": d.mount, "dims": MapCatalog.effect_dims(f), "zone": jsonable(d.zone),
			"y": d.get("y", 0.0), "teinte": d.has("couleur"), "decor": jsonable(d.get("decor", []))}
	var weapons := []
	for w in WeaponDB.WEAPONS:
		if WeaponDB.wall_cost(w) > 0:
			weapons.append({"id": w, "name": WeaponDB.display_name(w), "price": WeaponDB.wall_cost(w)})
	var perks := []
	for p in PerkDB.PERKS:
		perks.append({"id": p, "name": PerkDB.display_name(p)})
	# Schéma d'ÉCRITURE : « marches » (nombre de marches) n'est plus réglable ;
	# allowed_kinds le garde pour LIRE les cartes d'avant (tidy_stair l'efface).
	var kinds := MapCatalog.allowed_kinds()
	(kinds.escalier.keys as Dictionary).erase("marches")
	return {"kinds": jsonable(kinds), "room_keys": jsonable(MapCatalog.room_keys()), "zone_keys": jsonable(MapCatalog.zone_keys()),
		"items": items, "prefabs": prefabs, "lights": lights, "effects": effects, "weapons": weapons, "perks": perks, "variants": jsonable(MapCatalog.VARIANTS),
		"door_prices": MapCatalog.DOOR_PRICES, "max_floors": MapCatalog.MAX_FLOORS, "max_coord": MapCatalog.MAX_COORD,
		"id_prefixes": jsonable(MapOps.OBJ_PREFIX), "surfaces": MapCatalog.allowed_surfaces()}


## Valeur sans type Godot (couleurs en « #rrggbb », vecteurs en listes).
static func jsonable(v: Variant) -> Variant:
	match typeof(v):
		TYPE_DICTIONARY:
			var out := {}
			for k in v:
				out[str(k)] = jsonable(v[k])
			return out
		TYPE_ARRAY:
			return (v as Array).map(func(x): return jsonable(x))
		TYPE_COLOR:
			return "#" + (v as Color).to_html(false)
		TYPE_VECTOR2, TYPE_VECTOR2I:
			return [v.x, v.y]
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
			return v
		TYPE_STRING_NAME:
			return String(v)
	return str(v)


# ------------------------------------------------------------------ événements poussés

func _on_committed(change: Dictionary) -> void:
	_push({"event": "change", "cid": change.get("cid", ""), "author": change.get("author", ""), "label": change.get("label", ""),
		"seq": change.get("seq", 0), "ids": MapOps.ids_of(change.get("ops", []))})


func _on_peers() -> void:
	_push({"event": "peers", "peers": collab.peer_list()})


## Sélection changée dans l'éditeur (appelé par lui).
func notify_selection(ids: Array) -> void:
	_push({"event": "selection", "ids": ids})
