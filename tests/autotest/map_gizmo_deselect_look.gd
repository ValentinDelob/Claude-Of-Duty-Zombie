extends AutotestScenario
## @rendu : captures du correctif « le gizmo suit toujours la sélection »
## (docs/EDITOR_SCALE_ROTATE.md § 3.2).
## @niveau perf : hors check (captures d'un correctif en cours, à retirer
## une fois validé) ; lancer avec
## SCENARIOS="map_gizmo_deselect_look" JOBS=1 GUI_JOBS=1 bash tools/check.sh.
## 4 vues : poutre tournée par l'anneau Y de la 3D (anneaux visibles), puis
## clic dans le vide de la vue Dessus et caméra 3D tournée : aucun anneau ne
## doit rester (avant le correctif : anneaux figés à l'écran) ; puis reclic
## sur la poutre en 3D. Captures : tests/_out/shots/map_gizmo_deselect_look_*.png.

const Deselect := preload("res://tests/autotest/map_gizmo_deselect.gd")

var ed: MapEditor
var pv: MapPreviewPanel


func run() -> void:
	timeout_sec = 90
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 5.0, "menu principal")
	tree().change_scene_to_file(MapEditor.SCENE)
	if not await until(func(): return tree().current_scene is MapEditor, 6.0, "éditeur ouvert"):
		return
	ed = tree().current_scene
	await frames(3)
	ed.new_map(true)
	ed._reset(Deselect.test_map())
	ed.views.setup("4", ["dessus", "3d", "avant", "droite"])
	await frames(5)
	pv = ed.preview
	var gz := pv.gizmo
	ed.canvas.zoom = 30.0
	ed.canvas.origin = Vector2(30, 30)
	pv.world.rebuild_now()
	ed.select("d91")
	pv.center_on_selection()
	await _ready_3d()
	# Geste d'anneau Y en 3D, relâché.
	var c := gz.center3(ed.doc.find("d91"))
	var pts := gz.ring_px(c, gz.radius_m(c), 1)
	if pts.size() > 10:
		_mouse3(pts[0], -1)
		_mouse3(pts[0], 1)
		for i in range(1, 7):
			_mouse3(pts[i], -1)
			await frames(1)
		_mouse3(pts[6], 0)
	await _ready_3d()
	await at.screenshot("1_anneaux")
	# Clic dans le vide de la vue Dessus, puis la caméra 3D tourne.
	var cv := ed.canvas
	# Plan dézoomé : un point hors des pièces visible (20 ; 13).
	cv.zoom = 15.0
	var empty := cv.to_px(Vector2(20.0, 13.0))
	for p in [-1, 1, 0]:
		_mouse(cv, empty, p)
	await frames(2)
	pv.world.rig.zoom(-3.0)
	pv.world.rig.pan(Vector2(80, 30))
	pv._request_render()
	await _ready_3d()
	await at.screenshot("2_vide_camera_tournee")
	# Reclic sur la poutre en 3D : choisie, puis reclic : désélectionnée.
	ed.select("d91")
	pv.center_on_selection()
	await _ready_3d()
	await at.screenshot("3_rechoisie")
	var q: Variant = gz.to_px(gz.center3(ed.doc.find("d91")))
	if q != null:
		for p in [-1, 1, 0]:
			_mouse3(q, p)
	await frames(2)
	pv.world.rig.pan(Vector2(-60, 20))
	pv._request_render()
	await _ready_3d()
	await at.screenshot("4_reclic_camera_tournee")


func _ready_3d() -> void:
	await until(func(): return pv.world.idle() and not pv.world.is_stale(), 15.0, "aperçu reconstruit")
	await frames(6)


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
