extends AutotestScenario
## @rendu : a besoin du rendu (captures de l'éditeur et de l'aperçu 3D, fenêtre hors écran).
## APERÇU 3D de l'éditeur de cartes, avec les vrais outils : DRAFT ARENA
## ouverte, touche P (panneau affiché, construit hors du fil principal : murs,
## fenêtres barricadées, portes, objets de jeu) ; une pièce tracée au glisser
## et un luminaire posé depuis la barre rapide apparaissent tout seuls dans
## l'aperçu (seules les lampes refaites pour le luminaire) ; clic dans
## l'aperçu : l'élément est choisi dans l'éditeur ; caméras : orbite (clic
## droit, molette), vol libre (touche de déplacement du jeu), vue joueur posée
## par Ctrl + double-clic sur la carte 2D, qui marche vers un mur sans le
## traverser ; repère de la caméra sur la 2D ; fenêtre séparée refusée en
## test (aucune fenêtre à l'écran) ; P : masqué, plus aucun rendu.
## Captures : tests/_out/shots/map_preview_*.png (apercu_3d : éditeur avec
## l'aperçu ouvert ; vue_joueur : l'aperçu agrandi en vue joueur).

const OFF := MapGeom.WORLD_OFFSET

var ed: MapEditor
var cv: MapCanvas
var pv: MapPreviewPanel
var w: MapPreviewWorld


func run() -> void:
	timeout_sec = 200
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 5.0, "menu principal")
	_clean(EditorMap.maps_root())
	tree().change_scene_to_file(MapEditor.SCENE)
	if not await until(func(): return tree().current_scene is MapEditor, 6.0, "éditeur ouvert"):
		return
	ed = tree().current_scene
	cv = ed.canvas
	pv = ed.preview
	w = pv.world
	await frames(3)
	ed.open_example("draft_arena")
	await frames(3)
	at.check(not pv.shown and w.builds == 0, "aperçu masqué au départ : rien de construit")
	# Fenêtre de test hors écran, sans focus : rendu quand même.
	pv.pause_unfocused = false
	pv.set_render_scale(1.0)
	await key_p()
	at.check(pv.shown and pv.visible, "P : aperçu affiché")
	if not await until(func(): return w.builds > 0 and w.idle() and not w.is_stale(), 30.0, "première construction"):
		return
	var stuff: Node = w.groups.stuff
	at.check(stuff.find_children("*", "Barricade", true, false).size() == 7, "7 fenêtres barricadées")
	at.check(stuff.find_children("*", "Door", true, false).size() == 3, "3 portes (dont les débris)")
	at.check(stuff.find_children("*", "MysteryBox", true, false).size() == 1, "1 caisse au hasard")
	print("[apercu] DRAFT ARENA : conversion %.0f ms (fil de travail), construction %.0f ms (plus longue étape %.0f ms)" % [
		w.last_times.thread, w.last_times.apply, w.last_times.step_max])
	# Orbite : clic droit glissé, molette.
	var yaw0 := w.rig.yaw
	_view_button(MOUSE_BUTTON_RIGHT, true, pv.view.size * 0.5)
	_view_motion(Vector2(-60, 0))
	_view_button(MOUSE_BUTTON_RIGHT, false, pv.view.size * 0.5)
	at.check(absf(w.rig.yaw - yaw0) > 0.2, "clic droit glissé : la caméra tourne")
	var d0 := w.rig.dist
	_view_button(MOUSE_BUTTON_WHEEL_UP, true, pv.view.size * 0.5)
	at.check(w.rig.dist < d0, "molette : zoom")
	# Vue d'ensemble en coupe pour la capture (plafonds masqués), la carte 2D
	# à gauche du panneau.
	pv.set_option("ceil", true)
	w.frame_map()
	w.rig.yaw = 0.5
	w.rig.pitch = -0.85
	w.rig.dist *= 0.5
	w.rig._apply()
	cv.frame_all()
	cv.origin.x -= 150.0
	cv.queue_redraw()
	# Caisse au hasard choisie : surlignée dans la 2D et dans l'aperçu.
	ed.select("b3")
	await seconds(0.8)
	at.check(pv.renders > 0, "aperçu rendu (%d images)" % pv.renders)
	at.check(w.selected_id == "b3", "élément choisi surligné dans l'aperçu")
	await at.screenshot("apercu_3d")
	ed.select("")
	pv.set_option("ceil", false)

	# Une pièce tracée au glisser (touche 2) : elle apparaît dans l'aperçu.
	var arch0: Node = w.groups.arch
	var rooms0: int = w.data.rooms.size()
	cv.zoom = 14.0
	cv.origin = Vector2(40, 40)
	await key(KEY_2)
	await drag(Vector2(24, 4), Vector2(32, 12))
	at.check(ed.doc.pieces.size() == 6, "pièce posée")
	if not await until(func(): return w.idle() and not w.is_stale(), 20.0, "aperçu mis à jour (pièce)"):
		return
	at.check(w.groups.arch != arch0 and w.data.rooms.size() > rooms0, "la pièce apparaît dans l'aperçu (%d -> %d salles)" % [rooms0, w.data.rooms.size()])
	var new_floor := (w.groups.arch as Node).find_children("*__floor", "MeshInstance3D", true, false).filter(func(n):
		var bb := (n as MeshInstance3D).get_aabb()
		return bb.position.x >= 24.0 + OFF - 0.3 and bb.end.x <= 32.0 + OFF + 0.3)
	at.check(not new_floor.is_empty(), "sol de la nouvelle pièce construit")
	print("[apercu] pièce ajoutée : conversion %.0f ms, construction %.0f ms, délai total %.0f ms, morceaux %s" % [
		w.last_times.thread, w.last_times.apply, w.last_times.total, str(w.last_times.parts)])
	# Un luminaire (barre rapide, case 9) : seules les lampes sont refaites.
	var lamps0 := (w.groups.lamps as Node).find_children("*", "OmniLight3D", true, false).size()
	ed.set_hotbar(8, "luminaire:ampoule")
	await click(Vector2(26, 6))
	at.check(ed.doc.objets.any(func(o): return String(o.get("luminaire", "")) == "ampoule"), "luminaire posé")
	if not await until(func(): return w.idle() and not w.is_stale(), 20.0, "aperçu mis à jour (luminaire)"):
		return
	var lamps1 := (w.groups.lamps as Node).find_children("*", "OmniLight3D", true, false).size()
	at.check(lamps1 == lamps0 + 1 and w.last_times.parts == ["lamps"], "le luminaire s'allume dans l'aperçu (%d -> %d lampes, morceaux %s)" % [lamps0, lamps1, str(w.last_times.parts)])
	print("[apercu] luminaire ajouté : délai total %.0f ms (construction %.0f ms)" % [w.last_times.total, w.last_times.apply])

	# Clic dans l'aperçu : la pièce est choisie dans l'éditeur.
	await key(KEY_QUOTELEFT)
	ed.select("")
	pv.set_option("ceil", true)
	w.rig.pivot = Vector3(30.0 + OFF, 0.0, 10.0 + OFF)
	w.rig.pitch = -1.5
	w.rig.yaw = 0.0
	w.rig.dist = 14.0
	w.rig._apply()
	await tree().physics_frame
	await tree().physics_frame
	_view_button(MOUSE_BUTTON_LEFT, true, pv.view.size * 0.5)
	_view_button(MOUSE_BUTTON_LEFT, false, pv.view.size * 0.5)
	var room: Dictionary = ed.doc.pieces[5]
	at.check(ed.selected == String(room.id), "clic dans l'aperçu : pièce choisie (%s)" % ed.selected)
	await seconds(0.3)
	await at.screenshot("selection")
	pv.set_option("ceil", false)

	# Vol libre : la touche d'avance du jeu fait avancer la caméra.
	pv.set_camera_mode(MapPreviewCamera.Mode.FLY)
	at.check(w.rig.mode == MapPreviewCamera.Mode.FLY, "vol libre")
	var p0 := w.rig.eye()
	pv._mouse_in_view = true
	Input.action_press("move_forward")
	await seconds(0.5)
	Input.action_release("move_forward")
	at.check(w.rig.eye().distance_to(p0) > 2.0, "vol libre : la caméra avance (%.1f m)" % w.rig.eye().distance_to(p0))

	# Vue joueur, posée par Ctrl + double-clic sur la 2D dans l'entrepôt.
	pv.set_camera_mode(MapPreviewCamera.Mode.WALK)
	at.check(w.rig.mode == MapPreviewCamera.Mode.WALK, "vue joueur")
	cv.frame_all()
	await frames(2)
	# (y = 12 : près de la porte à 1000, mur plein à l'est.)
	var n_rooms := ed.doc.pieces.size()
	var n_objs := ed.doc.objets.size()
	_ctrl_double_click(Vector2(13.0, 12.0))
	await tree().physics_frame
	var wp := w.rig.walker.global_position
	at.check(Vector2(wp.x - OFF, wp.z - OFF).distance_to(Vector2(13, 12)) < 0.3, "Ctrl + double-clic : caméra placée (%.1f ; %.1f)" % [wp.x - OFF, wp.z - OFF])
	at.check(ed.doc.pieces.size() == n_rooms and ed.doc.objets.size() == n_objs, "Ctrl + double-clic : rien posé sur la carte (%d pièces, %d objets)" % [ed.doc.pieces.size(), ed.doc.objets.size()])
	await seconds(0.4)
	at.check(absf(w.rig.walker.global_position.y) < 0.2 and w.rig.walker.is_on_floor(), "au sol (y = %.2f)" % w.rig.walker.global_position.y)
	at.check(absf(w.rig.eye().y - w.rig.walker.global_position.y - Player.EYE_HEIGHT) < 0.01, "yeux à %.2f m" % Player.EYE_HEIGHT)
	# Vers le mur est de l'entrepôt (x = 17) en courant : arrêtée par le mur.
	w.rig.yaw = -PI * 0.5
	w.rig.pitch = 0.0
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await seconds(2.0)
	Input.action_release("move_forward")
	Input.action_release("sprint")
	var x := w.rig.walker.global_position.x - OFF
	at.check(x > 15.0 and x < 17.0 - MapGeom.WALL_HALF - Player.RADIUS + 0.05, "vue joueur arrêtée par le mur (x = %.2f m < 16,4)" % x)
	# Repère de la caméra sur la vue 2D.
	var marker := cv.to_px(Vector2(w.rig.eye().x - OFF, w.rig.eye().z - OFF))
	at.check(Rect2(Vector2.ZERO, cv.size).has_point(marker), "repère de la caméra dans la vue 2D")
	# Capture : aperçu agrandi, vue joueur vers la passerelle et l'escalier.
	pv.set_maximized(true)
	w.rig.place_at(Vector3(14.5 + OFF, 0.0, 15.5 + OFF))
	w.rig.yaw = deg_to_rad(52.0)
	w.rig.pitch = 0.08
	await seconds(0.8)
	await at.screenshot("vue_joueur")
	pv.set_maximized(false)
	pv._mouse_in_view = false

	# Fenêtre séparée : refusée pendant les tests, sauf hors de tous les écrans
	# et sans focus (jamais visible).
	pv.set_detached(true)
	at.check(not pv.detached and pv.window == null, "fenêtre séparée refusée en test")
	pv.test_window_at = _offscreen_point()
	pv.set_detached(true)
	@warning_ignore("incompatible_ternary")
	at.check(pv.detached and pv.window != null and pv.window.force_native and pv.content.get_parent() == pv.window and not pv.visible,
		"⧉ : aperçu détaché dans une vraie fenêtre (réduite pendant le test : %s)" % str(pv.window.mode == Window.MODE_MINIMIZED if pv.window else "-"))
	var rd := pv.renders
	await seconds(0.4)
	at.check(pv.renders > rd and pv.is_on_screen(), "fenêtre détachée : rendu")
	pv.set_detached(false)
	at.check(not pv.detached and pv.window == null and pv.visible and pv.content.get_parent().get_parent() == pv.frame, "fenêtre refermée : aperçu revenu dans l'éditeur")
	pv.test_window_at = Vector2i(-1, -1)
	# P : masqué, plus aucun rendu.
	pv.set_camera_mode(MapPreviewCamera.Mode.ORBIT)
	await key_p()
	at.check(not pv.shown and not pv.visible, "P : aperçu masqué")
	var r0 := pv.renders
	await seconds(0.5)
	at.check(pv.renders == r0 and w.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "masqué : aucun rendu")
	pv.save_prefs()
	var saved: Dictionary = MapEditor.pref(MapPreviewPanel.PREF_KEY, {})
	at.check(saved.get("visible") == false and saved.get("scale") == 1.0, "état mémorisé")
	_clean(EditorMap.maps_root())


## Point à droite de tous les écrans (comme la fenêtre de test).
func _offscreen_point() -> Vector2i:
	var right := 0
	var top := 0
	for i in DisplayServer.get_screen_count():
		var r := DisplayServer.screen_get_usable_rect(i)
		right = maxi(right, r.end.x)
		top = mini(top, r.position.y)
	return Vector2i(right + 1200, top)


func key_p() -> void:
	var e := InputEventKey.new()
	e.keycode = KEY_P
	e.physical_keycode = KEY_P
	e.pressed = true
	pv._input(e)
	await frames(2)


func _view_button(b: MouseButton, pressed: bool, pos: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = b
	e.pressed = pressed
	e.position = pos
	e.factor = 1.0
	pv._view_input(e)


func _view_motion(rel: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.relative = rel
	e.position = pv.view.size * 0.5 + rel
	pv._view_input(e)


func _ctrl_double_click(m: Vector2) -> void:
	for dbl in [false, true]:
		for pressed in [true, false]:
			var e := InputEventMouseButton.new()
			e.button_index = MOUSE_BUTTON_LEFT
			e.pressed = pressed
			e.double_click = dbl and pressed
			e.ctrl_pressed = true
			e.position = cv.to_px(m)
			cv._gui_input(e)


func _clean(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for d in DirAccess.get_directories_at(dir):
		_clean(dir.path_join(d))
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


func _motion(m: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = cv.to_px(m)
	cv._gui_input(e)


func _button(m: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.position = cv.to_px(m)
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	cv._gui_input(e)


func click(m: Vector2) -> void:
	_motion(m)
	_button(m, true)
	_button(m, false)
	await frames(1)


func drag(a: Vector2, b: Vector2) -> void:
	_motion(a)
	_button(a, true)
	for i in 4:
		_motion(a.lerp(b, (i + 1) / 4.0))
		await frames(1)
	_button(b, false)
	await frames(1)


func key(code: Key, ctrl := false) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.ctrl_pressed = ctrl
	e.pressed = true
	ed._input(e)
	var up := e.duplicate()
	up.pressed = false
	ed._input(up)
	await frames(1)
