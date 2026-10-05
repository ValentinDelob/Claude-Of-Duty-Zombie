extends AutotestScenario
## @rendu : le gizmo (anneaux, poignées d'échelle, flèches) suit TOUJOURS la
## sélection dans toutes les vues (docs/EDITOR_SCALE_ROTATE.md § 3.2,
## correctif du 04/10/2026). Bug : après une rotation, désélectionner
## laissait les anneaux de la vue 3D affichés, figés à l'écran (la couche du
## gizmo n'était plus redessinée sans décor choisi).
## Vrai éditeur en 4 vues (Dessus, 3D, Avant, Droite), puis aperçu flottant :
##   - après un geste d'anneau, chaque façon de désélectionner (reclic en
##     vue Dessus, en élévation et en 3D, clic dans le vide, Échap, Maj + clic
##     qui le retire, Suppr, Ctrl+Z, changement d'étage, autre élément,
##     sélection multiple, élément retiré par Claude) : plus de gizmo dans
##     aucune vue, couche 3D redessinée vide, gestes remis à zéro ;
##   - geste EN COURS quand la sélection change (désélection, autre élément,
##     Maj + clic, Ctrl+Z, retrait par Claude) : annulé, carte d'avant
##     remise, aucune étape d'annulation ; Échap pendant le geste 3D : seul
##     le geste est annulé (la sélection reste).

const Objects := preload("res://tests/test_map_objects.gd")

var ed: MapEditor
var pv: MapPreviewPanel
var gz: MapGizmo3D
## Dessins de la couche 3D du gizmo, et le dernier avait-il un décor ?
var draws := 0
var drew_target := false
var _d0 := 0


func run() -> void:
	timeout_sec = 180
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 5.0, "menu principal")
	tree().change_scene_to_file(MapEditor.SCENE)
	if not await until(func(): return tree().current_scene is MapEditor, 6.0, "éditeur ouvert"):
		return
	ed = tree().current_scene
	await frames(3)
	ed.new_map(true)
	ed._reset(test_map())
	ed.views.setup("4", ["dessus", "3d", "avant", "droite"])
	await frames(5)
	pv = ed.preview
	if pv == null or pv.gizmo == null:
		at.fail("aperçu 3D ou gizmo absent")
		return
	gz = pv.gizmo
	gz.draw.connect(func():
		draws += 1
		drew_target = not gz.target().is_empty())
	pv.world.rebuild_now()
	await _frame_views()

	await _after_gesture()
	await _during_gesture()
	await _floating()


## Carte : salle haute (6,80 m), poutre (3 anneaux), piles de caisses.
static func test_map() -> EditorMap:
	var doc := Objects.objects_map()
	doc.objets = doc.objets.filter(func(o): return o.type != "bloc_invisible")
	doc.pieces[0]["plafond"] = 6.8
	doc.find("s1")["position"] = [6.0, 8.5]
	doc.objets.append({"id": "d91", "type": "prefab", "prefab": "poutre", "altitude": 0, "position": [5.0, 3.5]})
	doc.objets.append({"id": "d90", "type": "prefab", "prefab": "caisses", "altitude": 0, "position": [10.0, 6.5]})
	doc.objets.append({"id": "d92", "type": "prefab", "prefab": "caisses", "altitude": 0, "position": [19.0, 5.0]})
	return doc


func _frame_views() -> void:
	var cv := ed.canvas
	cv.zoom = 30.0
	cv.origin = Vector2(30, 30)
	for i in [2, 3]:
		var ev: MapElevation = ed.views.panes[i].view
		ev.zoom = 30.0
		ev.origin = Vector2(30, ev.size.y - 40.0)
	await frames(3)


# ------------------------------------------------------------------ outils

func _av() -> MapElevation:
	return ed.views.panes[2].view


## Choisit `id`, centre la 3D dessus, attend que l'aperçu soit prêt.
func _pick(id: String) -> void:
	ed.select(id)
	pv.center_on_selection()
	# Vue plongeante (aucun mur devant l'élément) ; plafonds affichés : vus
	# d'au-dessus, ils ne sont pas rendus et le clic les traverse.
	pv.world.rig.pitch = -1.3
	pv.world.rig._apply()
	pv._request_render()
	await until(func(): return pv.world.idle() and not pv.world.is_stale(), 15.0, "aperçu reconstruit")
	await frames(4)


## Marque le nombre de dessins de la couche 3D avant une désélection.
func _mark() -> void:
	_d0 = draws


## Plus aucun gizmo nulle part, gestes remis à zéro, couche 3D redessinée vide.
func _gone(how: String) -> void:
	await frames(3)
	var cv := ed.canvas
	at.check(ed.selected == "" or not ed.group.is_empty(), "%s : plus d'élément choisi seul (« %s »)" % [how, ed.selected])
	at.check(cv.gizmo.target().is_empty() and cv.drag.is_empty(), "%s : vue Dessus sans gizmo ni geste" % how)
	for v in ed.views.elevations():
		var ev := v as MapElevation
		at.check(ev.tools.gizmo.target().is_empty() and not ev.tools.dragging(), "%s : %s sans gizmo ni geste" % [how, ev.plane])
	at.check(gz.target().is_empty() and gz.shown_id == "" and gz.drag.is_empty() and gz.hover == -1, "%s : 3D sans anneaux ni geste" % how)
	at.check(draws > _d0 and not drew_target, "%s : couche 3D redessinée vide (%d dessin(s), dernier avec décor : %s)" % [how, draws - _d0, drew_target])
	at.check(pv.world.auto, "%s : l'aperçu repart (jamais figé)" % how)


## Geste complet d'anneau Z en vue Dessus (37° -> 30°), relâché.
func _rotate_top(id: String) -> void:
	var cv := ed.canvas
	var rg := cv.gizmo.ring_of(ed.doc.find(id))
	if rg.is_empty():
		at.fail("anneau Z absent (%s)" % id)
		return
	var c: Vector2 = rg.c
	var g := c + Vector2(0, -float(rg.r))
	await _drag_px(cv, g, c + (g - c).rotated(deg_to_rad(37.0)), true)


## Commence un geste d'anneau Z en vue Dessus (non relâché).
func _start_top(id: String) -> void:
	var cv := ed.canvas
	var rg := cv.gizmo.ring_of(ed.doc.find(id))
	var c: Vector2 = rg.c
	var g := c + Vector2(0, -float(rg.r))
	await _drag_px(cv, g, c + (g - c).rotated(deg_to_rad(37.0)), false)


## Commence un geste d'anneau Y en vue Avant (non relâché).
func _start_elev(id: String) -> void:
	var av := _av()
	var ry := av.tools.gizmo.ring_of(av.projected_of(id))
	if ry.is_empty():
		at.fail("anneau Y de la vue Avant absent (%s)" % id)
		return
	var c: Vector2 = ry.c
	var g := c + Vector2(0, -float(ry.r))
	await _drag_px(av, g, c + (g - c).rotated(deg_to_rad(32.0)), false)


## Commence (ou fait, `release`) un geste d'anneau Y en 3D.
func _start_3d(id: String, release := false) -> void:
	var c := gz.center3(ed.doc.find(id))
	var pts := gz.ring_px(c, gz.radius_m(c), 1)
	if pts.size() <= 10:
		at.fail("anneau Y de la 3D non projeté")
		return
	_mouse3(pts[0], -1)
	_mouse3(pts[0], 1)
	at.check(gz.dragging(), "3D : anneau Y attrapé")
	for i in range(1, 7):
		_mouse3(pts[i], -1)
		await frames(1)
	if release:
		_mouse3(pts[6], 0)
		await frames(2)


## Simple clic au milieu de l'élément dans la 3D.
func _click3_on(id: String) -> void:
	var p: Variant = gz.to_px(gz.center3(ed.doc.find(id)))
	if p == null:
		at.fail("élément derrière la caméra")
		return
	at.check(pv.world.pick(pv._in_view_px(p)) == id, "3D : le clic vise %s (%s)" % [id, pv.world.pick(pv._in_view_px(p))])
	_mouse3(p, -1)
	_mouse3(p, 1)
	_mouse3(p, 0)


func _key(kc: int, ctrl := false) -> void:
	var k := InputEventKey.new()
	k.pressed = true
	k.keycode = kc
	k.physical_keycode = kc
	k.ctrl_pressed = ctrl
	ed._input(k)


# ------------------------------------------------------------------ après un geste

func _after_gesture() -> void:
	var cv := ed.canvas
	# 1. Reclic en vue Dessus, après un geste d'anneau.
	await _pick("d91")
	at.check(gz.shown_id == "d91" and drew_target, "poutre choisie : anneaux en 3D")
	await _rotate_top("d91")
	at.check(MapGeom.rot_of(ed.doc.find("d91")) == 30, "vue Dessus : Z 30° (%d)" % MapGeom.rot_of(ed.doc.find("d91")))
	_mark()
	var pos := cv.to_px(MapGeom.v2(ed.doc.find("d91").position))
	_mouse(cv, pos, -1)
	_mouse(cv, pos, 1)
	_mouse(cv, pos, 0)
	await _gone("reclic en vue Dessus")
	# Un glissement de l'élément déjà choisi le garde (déplacé).
	await _pick("d91")
	_mouse(cv, pos, -1)
	_mouse(cv, pos, 1)
	_mouse(cv, pos + Vector2(60, 0), -1)
	_mouse(cv, pos + Vector2(60, 0), 0)
	await frames(2)
	at.check(ed.selected == "d91", "glissé (pas un reclic) : toujours choisi")
	ed.undo()
	await frames(2)

	# 2. Reclic en 3D après un geste d'anneau 3D.
	await _pick("d91")
	await _start_3d("d91", true)
	at.check(not gz.dragging(), "3D : geste relâché")
	await until(func(): return pv.world.idle() and not pv.world.is_stale(), 15.0, "aperçu reconstruit")
	await frames(4)
	_mark()
	await _click3_on("d91")
	await _gone("reclic en 3D")
	# Double-clic : jamais un reclic (choisi, centré).
	await _pick("d91")
	var p3: Variant = gz.to_px(gz.center3(ed.doc.find("d91")))
	if p3 != null:
		var mb := InputEventMouseButton.new()
		mb.position = p3
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.pressed = true
		mb.double_click = true
		pv._view_input(mb)
		_mouse3(p3, 0)
		await frames(2)
		at.check(ed.selected == "d91", "3D : double-clic sur l'élément choisi : il reste choisi")

	# 3. Reclic en élévation (vue Avant).
	await _pick("d91")
	var av := _av()
	await frames(2)
	_mark()
	var ap := av.rect_px(av.projected_of("d91")).get_center()
	_mouse(av, ap, -1)
	_mouse(av, ap, 1)
	_mouse(av, ap, 0)
	await _gone("reclic en vue Avant")

	# 4. Clic dans le vide (vue Dessus).
	await _pick("d91")
	_mark()
	# Plan dézoomé : un point hors des pièces visible (20 ; 13).
	cv.zoom = 15.0
	var empty := cv.to_px(Vector2(20.0, 13.0))
	at.check(ed.element_at(Vector2(20.0, 13.0)).is_empty(), "point vide hors des pièces")
	_mouse(cv, empty, -1)
	_mouse(cv, empty, 1)
	_mouse(cv, empty, 0)
	await _gone("clic dans le vide")
	cv.zoom = 30.0

	# 5. Échap.
	await _pick("d91")
	_mark()
	_key(KEY_ESCAPE)
	await _gone("Échap")

	# 6. Maj + clic qui le retire (toggle).
	await _pick("d91")
	_mark()
	ed.toggle_selected("d91")
	await _gone("Maj + clic qui le retire")

	# 7. Autre élément : les anneaux passent à lui.
	await _pick("d91")
	_mark()
	ed.select("d90")
	await frames(3)
	at.check(gz.shown_id == "d90" and draws > _d0 and cv.gizmo.target().get("id", "") == "d90", "autre élément : le gizmo passe à lui")

	# 8. Sélection multiple.
	_mark()
	ed.select_many(["d90", "d91"])
	await _gone("sélection multiple")

	# 9. Suppr.
	await _pick("d92")
	_mark()
	ed.delete_selection()
	await _gone("Suppr")
	ed.undo()
	await frames(2)

	# 10. Ctrl+Z : l'élément choisi disparaît (pose annulée).
	ed.add_object({"type": "prefab", "prefab": "caisses", "position": [11.0, 3.0]}, 0)
	var nid := ed.selected
	pv.center_on_selection()
	await until(func(): return pv.world.idle() and not pv.world.is_stale(), 15.0, "aperçu reconstruit")
	await frames(4)
	at.check(gz.shown_id == nid and nid != "", "décor posé : anneaux en 3D (%s)" % nid)
	_mark()
	_key(KEY_Z, true)
	await _gone("Ctrl+Z (élément retiré)")

	# 11. Changement d'étage (étage ajouté pour l'occasion, retiré ensuite :
	# son sol sous le plafond haut gênerait le clic en 3D).
	ed.add_floor()
	ed.set_floor(0)
	await _pick("d91")
	_mark()
	ed.set_floor(1)
	await _gone("changement d'étage")
	ed.set_floor(0)
	ed.undo()
	await frames(2)
	at.check(ed.doc.level_count() == 1, "étage ajouté retiré (Ctrl+Z)")

	# 12. Élément retiré par Claude.
	await _pick("d92")
	_mark()
	ed.collab.submit_ops([{"op": "del", "coll": "objets", "id": "d92"}], "retrait de Claude", ed.collab.my_id + ":claude")
	await _gone("retiré par Claude")
	ed.collab.submit_ops([{"op": "put", "coll": "objets", "el": {"id": "d92", "type": "prefab", "prefab": "caisses", "altitude": 0, "position": [19.0, 5.0]}}],
		"retour", ed.collab.my_id + ":claude")
	await frames(2)


# ------------------------------------------------------------------ pendant un geste

func _during_gesture() -> void:
	# 3D : désélection pendant le geste -> annulé, rien d'écrit.
	await _pick("d91")
	var before := ed.doc.find("d91").duplicate(true)
	var undo0 := ed.collab.history.undo_count(ed.collab.my_id)
	await _start_3d("d91")
	at.check(ed.doc.find("d91") != before, "3D : la poutre tourne pendant le geste")
	_mark()
	ed.select("")
	await _gone("3D, désélection pendant le geste")
	at.check(ed.doc.find("d91") == before, "3D : geste annulé, poutre d'avant")
	# Relâcher ensuite n'écrit rien.
	_mouse3(Vector2(10, 10), 0)
	await frames(2)
	at.check(ed.collab.history.undo_count(ed.collab.my_id) == undo0 and ed.doc.find("d91") == before, "3D : aucune étape d'annulation")

	# 3D : Échap pendant le geste (touche de l'éditeur) -> geste seul annulé.
	await _pick("d91")
	await _start_3d("d91")
	_key(KEY_ESCAPE)
	await frames(2)
	at.check(not gz.dragging() and ed.selected == "d91" and ed.doc.find("d91") == before, "3D : Échap annule le geste, la poutre reste choisie")
	_mouse3(Vector2(10, 10), 0)

	# 3D : autre élément choisi pendant le geste (Claude, liste des objets).
	await _start_3d("d91")
	ed.select("d90")
	await frames(3)
	at.check(not gz.dragging() and ed.doc.find("d91") == before and gz.shown_id == "d90", "3D : autre élément pendant le geste : annulé, anneaux sur lui")
	_mouse3(Vector2(10, 10), 0)

	# 3D : Ctrl+Z pendant le geste.
	await _pick("d91")
	await _start_3d("d91")
	_key(KEY_Z, true)
	await frames(3)
	at.check(not gz.dragging() and pv.world.auto, "3D : Ctrl+Z pendant le geste : geste annulé")
	_mouse3(Vector2(10, 10), 0)
	await frames(2)
	ed.redo()
	await frames(2)

	# 3D : élément retiré par Claude pendant le geste.
	await _pick("d92")
	await _start_3d("d92")
	_mark()
	ed.collab.submit_ops([{"op": "del", "coll": "objets", "id": "d92"}], "retrait de Claude", ed.collab.my_id + ":claude")
	await _gone("3D, retiré par Claude pendant le geste")
	at.check(ed.doc.find("d92").is_empty(), "retrait de Claude gardé")
	_mouse3(Vector2(10, 10), 0)

	# Vue Dessus : autre élément choisi pendant un geste d'anneau.
	await _pick("d91")
	before = ed.doc.find("d91").duplicate(true)
	undo0 = ed.collab.history.undo_count(ed.collab.my_id)
	await _start_top("d91")
	at.check(ed.canvas.drag.get("kind", "") == "ring", "vue Dessus : geste d'anneau en cours")
	ed.select("d90")
	await frames(2)
	at.check(ed.canvas.drag.is_empty() and ed.doc.find("d91") == before, "vue Dessus : autre élément pendant le geste : annulé, poutre d'avant")
	_mouse(ed.canvas, Vector2(10, 10), 0)
	await frames(1)
	at.check(ed.collab.history.undo_count(ed.collab.my_id) == undo0, "vue Dessus : aucune étape d'annulation")

	# Vue Avant : Maj + clic qui retire pendant un geste d'anneau.
	await _pick("d91")
	await _start_elev("d91")
	at.check(_av().tools.drag.get("kind", "") == "ring", "vue Avant : geste d'anneau en cours")
	_mark()
	ed.toggle_selected("d91")
	await _gone("vue Avant, retiré pendant le geste")
	at.check(ed.doc.find("d91") == before, "vue Avant : poutre d'avant")
	_mouse(_av(), Vector2(10, 10), 0)


# ------------------------------------------------------------------ aperçu flottant

func _floating() -> void:
	ed.views.setup("2v", ["dessus", "avant"])
	await frames(3)
	pv.set_shown(true)
	await frames(3)
	await _pick("d91")
	at.check(gz.shown_id == "d91" and drew_target, "aperçu flottant : anneaux de la poutre")
	await _start_3d("d91", true)
	await until(func(): return pv.world.idle() and not pv.world.is_stale(), 15.0, "aperçu reconstruit")
	await frames(3)
	_mark()
	await _click3_on("d91")
	await _gone("aperçu flottant, reclic")
	pv.set_shown(false)


# ------------------------------------------------------------------ souris

func _drag_px(v: MapView, a: Vector2, b: Vector2, release: bool) -> void:
	_mouse(v, a, -1)
	_mouse(v, a, 1)
	for i in 6:
		_mouse(v, a.lerp(b, (i + 1) / 6.0), -1)
		await frames(1)
	if release:
		_mouse(v, b, 0)
		await frames(1)


## Souris dans une vue plane (px) : `press` -1 mouvement, 1 appui, 0 relâché.
func _mouse(v: MapView, px: Vector2, press: int) -> void:
	if press < 0:
		var mm := InputEventMouseMotion.new()
		mm.position = px
		v._gui_input(mm)
		return
	var mb := InputEventMouseButton.new()
	mb.position = px
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = press == 1
	v._gui_input(mb)


## Souris dans l'aperçu 3D (px de la vue).
func _mouse3(px: Vector2, press: int) -> void:
	if press < 0:
		var mm := InputEventMouseMotion.new()
		mm.position = px
		pv._view_input(mm)
		return
	var mb := InputEventMouseButton.new()
	mb.position = px
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = press == 1
	pv._view_input(mb)
