extends AutotestScenario
## @rendu : captures de l'échelle et de la rotation 3D du décor (format 14,
## docs/EDITOR_SCALE_ROTATE.md, maquette docs/editor_scale_rotate_mockup).
## @niveau perf : hors check par défaut (captures d'un ajout en cours) ;
## lancer avec SCENARIOS="map_scale_look" JOBS=1 GUI_JOBS=1 bash tools/check.sh.
## Éditeur : panneau Propriétés (Échelle, Rotation) d'une pile × 1,5, d'une
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
