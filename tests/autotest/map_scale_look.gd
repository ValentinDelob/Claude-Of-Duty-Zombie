extends AutotestScenario
## @rendu : captures de l'échelle et de la rotation 3D du décor (format 14,
## docs/EDITOR_SCALE_ROTATE.md, maquette docs/editor_scale_rotate_mockup).
## @niveau perf : hors check par défaut (captures d'un ajout en cours) ;
## lancer avec SCENARIOS="map_scale_look" JOBS=1 GUI_JOBS=1 bash tools/check.sh.
## Éditeur : écran 1 (pile de caisses agrandie par son coin, geste en
## cours), écran 3 (prefab bloqué, cadenas survolé), panneau Propriétés (Échelle, Rotation) d'une pile × 1,5, d'une
## poutre inclinée et d'un prefab qui contient un Pack-a-Punch.
## En jeu (TESTER) : pile de caisses × 1,5 et poutre inclinée de 30°, vues
## par le joueur. Captures : tests/_out/shots/map_scale_look_*.png.

const Objects := preload("res://tests/test_map_objects.gd")

var ed: MapEditor
var off := MapGeom.WORLD_OFFSET


func run() -> void:
	timeout_sec = 120
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 5.0, "menu principal")
	var root := EditorMap.maps_root()
	tree().change_scene_to_file(MapEditor.SCENE)
	if not await until(func(): return tree().current_scene is MapEditor, 6.0, "éditeur ouvert"):
		return
	ed = tree().current_scene
	await frames(3)
	ed.new_map(true)
	await _shot_panel()
	await _shot_scale()
	await _shot_blocked()
	await _shot_rings()
	await _shot_3d()
	ed._reset(game_map())
	await frames(3)
	await _game_shots()
	_clean(root)


## Carte de la partie : salle A haute (6,80 m), caisses × 1,5, poutre inclinée de 30°.
static func game_map() -> EditorMap:
	var doc := Objects.objects_map()
	doc.objets = doc.objets.filter(func(o): return o.type != "bloc_invisible")
	doc.pieces[0]["plafond"] = 6.8
	doc.find("s1")["position"] = [6.0, 7.5]
	doc.objets.append({"id": "d90", "type": "prefab", "prefab": "caisses", "etage": 0, "position": [11.0, 7.0], "echelle": [1.5, 1.5, 1.5]})
	doc.objets.append({"id": "d91", "type": "prefab", "prefab": "poutre", "etage": 0, "position": [5.0, 3.5], "incl": [0, 30]})
	return doc


func _game_shots() -> void:
	if not ed.test_map():
		at.fail("TESTER refusé : %s" % str(ed.validator.errors().map(func(m): return m.fr) if ed.validator else []))
		return
	if not await until(func(): return Game.instance != null and Game.instance.local_player != null, 20.0, "partie lancée"):
		return
	var game := Game.instance
	var p := game.local_player
	p.bot_controlled = true
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	await AutotestHelpers.clear_zombies(self)
	# Vers le nord-est : la pile agrandie.
	p.teleport_to(Vector3(6.5 + off, 0.05, 9.0 + off), deg_to_rad(-40.0))
	p.pitch = deg_to_rad(-8.0)
	await seconds(2.0)
	await at.screenshot("jeu_caisses")
	# Vers le nord-ouest : la poutre inclinée (bout ouest en haut, bout est au sol).
	p.teleport_to(Vector3(7.0 + off, 0.05, 8.5 + off), deg_to_rad(15.0))
	p.pitch = deg_to_rad(5.0)
	await seconds(0.6)
	await at.screenshot("jeu_poutre")
	Router.back_to_menu()
	await until(func(): return tree().current_scene is MapEditor, 10.0, "retour dans l'éditeur")


func _clean(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for d in DirAccess.get_directories_at(dir):
		_clean(dir.path_join(d))
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


# ------------------------------------------------------------------ éditeur (écrans de la maquette)

const Scale := preload("res://tests/test_map_scale.gd")


## Carte de l'éditeur des écrans : entrepôt haut (6,80 m), pile de caisses,
## poutre tombée, prefab « Coin Pack-a-Punch ».
static func editor_map() -> EditorMap:
	var doc := Objects.objects_map()
	doc.objets = doc.objets.filter(func(o): return o.type != "bloc_invisible")
	doc.pieces[0]["plafond"] = 6.8
	doc.find("s1")["position"] = [6.0, 8.5]
	doc.prefabs["coin_pap"] = Scale.PAP_DEF.duplicate(true)
	doc.objets.append({"id": "d90", "type": "prefab", "prefab": "caisses", "etage": 0, "position": [10.0, 6.5]})
	doc.objets.append({"id": "d91", "type": "prefab", "prefab": "poutre", "etage": 0, "position": [5.0, 3.5]})
	doc.objets.append({"id": "d93", "type": "prefab", "prefab": "map:coin_pap", "etage": 0, "position": [19.0, 4.5]})
	return doc


func _editor_open(layout: String, planes: Array) -> void:
	ed.new_map(true)
	ed._reset(editor_map())
	ed.doc.activate_prefabs()
	ed.views.setup(layout, planes)
	await frames(4)


func _mouse(v: MapView, m: Vector2, press: int) -> void:
	if press < 0:
		var mm := InputEventMouseMotion.new()
		mm.position = v.to_px(m)
		v._gui_input(mm)
		return
	var mb := InputEventMouseButton.new()
	mb.position = v.to_px(m)
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = press == 1
	v._gui_input(mb)


## Panneau Propriétés (étape 3) : pile × 1,5, poutre inclinée, prefab bloqué.
func _shot_panel() -> void:
	await _editor_open("2v", ["dessus", "avant"])
	ed.canvas.zoom = 34.0
	ed.canvas.origin = Vector2(40, 40)
	var c := ed.doc.find("d90")
	MapScale.set_scale(c, Vector3.ONE * 1.5)
	var b := ed.doc.find("d91")
	MapScale.set_incl(b, Vector2(0, 30))
	ed.changed()
	ed.select("d90")
	await frames(4)
	await at.screenshot("panneau_caisses")
	ed.select("d91")
	await frames(4)
	await at.screenshot("panneau_poutre")
	ed.select("d93")
	await frames(4)
	await at.screenshot("panneau_bloque")


## Écran 1 : pile de caisses agrandie par son coin sud-est (×1,50), geste en cours.
func _shot_scale() -> void:
	await _editor_open("2v", ["dessus", "avant"])
	var cv := ed.canvas
	cv.set_snap_mode("fine")
	cv.zoom = 30.0
	cv.origin = cv.size * 0.5 - Vector2(10.0, 6.2) * cv.zoom
	var av: MapElevation = ed.views.panes[1].view
	av.zoom = 30.0
	av.origin = Vector2(av.size.x * 0.5 - 10.0 * 30.0, av.size.y - 50.0)
	ed.select("d90")
	await frames(3)
	var o := ed.doc.find("d90")
	var se: Vector2 = MapGizmo.frame(o).c + Vector2(MapScale.dims(o).x, MapScale.dims(o).y) * 0.5
	var nw: Vector2 = MapGizmo.frame(o).c - Vector2(MapScale.dims(o).x, MapScale.dims(o).y) * 0.5
	_mouse(cv, se, -1)
	_mouse(cv, se, 1)
	for i in 6:
		_mouse(cv, se.lerp(nw + (se - nw) * 1.5, (i + 1) / 6.0), -1)
		await frames(1)
	await frames(3)
	await at.screenshot("ecran1_echelle")
	_mouse(cv, nw + (se - nw) * 1.5, 0)
	await frames(2)
	await at.screenshot("ecran1_relache")


## Écran 3 : prefab qui contient un Pack-a-Punch, cadenas survolé.
func _shot_blocked() -> void:
	await _editor_open("1", ["dessus"])
	var cv := ed.canvas
	cv.set_snap_mode("grille")
	cv.zoom = 60.0
	cv.origin = Vector2(-700, 40)
	ed.select("d93")
	await frames(3)
	var hs := cv.gizmo.handles_of(ed.doc.find("d93"))
	if hs.size() == 4:
		var lp: Vector2 = hs[1].m
		_mouse(cv, lp, -1)
		cv.mouse_default_cursor_shape = cv.cursor_at(cv.to_px(lp))
		_mouse(cv, lp, 1)
		_mouse(cv, lp, 0)
		_mouse(cv, lp, -1)
	await frames(3)
	await at.screenshot("ecran3_bloque")


## Anneaux (étape 5) : anneau Z en vue Dessus, anneau Y en vue Avant pendant
## le geste (poutre à +30°).
func _shot_rings() -> void:
	await _editor_open("2v", ["dessus", "avant"])
	var cv := ed.canvas
	cv.zoom = 30.0
	cv.origin = cv.size * 0.5 - Vector2(6.0, 4.5) * cv.zoom
	ed.select("d91")
	await frames(3)
	var av: MapElevation = ed.views.panes[1].view
	av.zoom = 30.0
	av.origin = Vector2(av.size.x * 0.5 - 6.0 * 30.0, av.size.y - 30.0)
	await frames(3)
	var e := av.projected_of("d91")
	var rg := av.tools.gizmo.ring_of(e)
	if rg.is_empty():
		at.fail("anneau Y absent")
		return
	var c: Vector2 = rg.c
	var g := c + Vector2(0, -float(rg.r))
	_mouse_px(av, g, -1)
	_mouse_px(av, g, 1)
	for i in 6:
		_mouse_px(av, c + (g - c).rotated(deg_to_rad(31.0 * (i + 1) / 6.0)), -1)
		await frames(1)
	await frames(3)
	await at.screenshot("ecran2_anneau_avant")
	_mouse_px(av, c + (g - c).rotated(deg_to_rad(31.0)), 0)
	await frames(3)
	await at.screenshot("ecran2_relache")


func _mouse_px(v: MapView, px: Vector2, press: int) -> void:
	_mouse(v, v.to_m(px), press)


## Écran 2 : vue 3D (anneaux X, Y, Z de la poutre) à gauche, Dessus et Avant à
## droite ; anneau Y tourné de 30° dans la 3D.
func _shot_3d() -> void:
	await _editor_open("3b", ["3d", "dessus", "avant"])
	var pv := ed.preview
	if pv == null or pv.gizmo == null:
		at.fail("aperçu 3D absent")
		return
	pv.world.rebuild_now()
	ed.select("d91")
	pv.center_on_selection()
	await frames(10)
	var gz := pv.gizmo
	var c := gz.center3(ed.doc.find("d91"))
	var pts := gz.ring_px(c, gz.radius_m(c), 1)
	if pts.size() < 10:
		at.fail("anneau Y non projeté")
		return
	for press in [[pts[0], -1], [pts[0], 1]]:
		_mouse3(pv, press[0], press[1])
	for i in range(1, 7):
		_mouse3(pv, pts[i], -1)
		await frames(1)
	await frames(3)
	await at.screenshot("ecran2_3d_geste")
	_mouse3(pv, pts[6], 0)
	await until(func(): return pv.world.idle() and not pv.world.is_stale(), 15.0, "aperçu reconstruit")
	await frames(5)
	await at.screenshot("ecran2_3d")


func _mouse3(pv: MapPreviewPanel, px: Vector2, press: int) -> void:
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
