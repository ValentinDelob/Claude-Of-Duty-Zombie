extends AutotestScenario
## @rendu : captures du plafond sous une pièce de l'étage du dessus, revue humaine.
## @niveau perf : hors check par défaut (captures d'une correction en cours) ;
## lancer avec SCENARIOS="ceiling_under_floor_look" JOBS=1 GUI_JOBS=1 bash tools/check.sh.
## DRAFT ARENA, entrepôt (double hauteur) sous la passerelle de l'étage 1 :
## aperçu 3D en orbite, vol libre et vue joueur (étage 0 puis 1 choisi dans
## l'éditeur, tous les étages ou « jusqu'à l'étage courant »), puis en jeu
## (TESTER), en regardant le plafond ; rayon vers le haut : surface touchée
## (nœud, hauteur). Carte simple à deux étages : vue joueur sous la pièce du haut.

const OFF := MapGeom.WORLD_OFFSET
const UnitTest := preload("res://tests/test_ceiling_under_floor.gd")
## Sous la passerelle de DRAFT ARENA (2,5-7,5 x 4,5-9,5).
const UNDER := Vector2(5.0, 8.5)

var ed: MapEditor
var pv: MapPreviewPanel
var w: MapPreviewWorld


func run() -> void:
	timeout_sec = 180
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 5.0, "menu principal")
	tree().change_scene_to_file(MapEditor.SCENE)
	if not await until(func(): return tree().current_scene is MapEditor, 6.0, "éditeur ouvert"):
		return
	ed = tree().current_scene
	pv = ed.preview
	w = pv.world
	await frames(3)
	ed.open_example("draft_arena")
	await frames(3)
	pv.pause_unfocused = false
	pv.set_render_scale(1.0)
	if not pv.shown:
		await _key_p()
	if not await until(func(): return w.builds > 0 and w.idle() and not w.is_stale(), 30.0, "aperçu construit"):
		return
	pv.set_maximized(true)
	await _preview_shots("arena")
	# Étage 1 choisi dans l'éditeur, puis « jusqu'à l'étage courant » à l'étage 0.
	ed.set_floor(1)
	await frames(2)
	await _walk_shot("arena_etage1_choisi")
	ed.set_floor(0)
	pv.set_option("floors", MapPreviewWorld.Floors.UP_TO)
	await frames(2)
	await _walk_shot("arena_jusqua_etage0")
	pv.set_option("floors", MapPreviewWorld.Floors.ALL)
	pv.set_maximized(false)

	# Carte simple à deux étages (pièce du bas 10 x 8, pièce du haut sur sa moitié ouest).
	ed.new_map(true)
	ed._reset(UnitTest._two_floors())
	if not await until(func(): return w.idle() and not w.is_stale(), 30.0, "aperçu de la carte simple"):
		return
	pv.set_maximized(true)
	await seconds(0.5)
	pv.set_camera_mode(MapPreviewCamera.Mode.FLY)
	w.rig.fly_pos = Vector3(4.0 + OFF, 1.6, 6.5 + OFF)
	w.rig.yaw = deg_to_rad(20.0)
	w.rig.pitch = 0.75
	w.rig._apply()
	await seconds(0.6)
	_probe("simple, aperçu", w.root3d, Vector3(2.0 + OFF, 1.6, 4.0 + OFF))
	await at.screenshot("simple_apercu_vol")
	# Passage entre une pièce haute (4,5 m) et une pièce basse (3,2 m).
	if not await _load(UnitTest._two_heights()):
		return
	await _fly(Vector3(2.5, 1.7, 5.5), -PI * 0.5, 0.35, "passage_apercu_cote_haut")
	await _fly(Vector3(10.0, 1.7, 5.5), PI * 0.5, 0.25, "passage_apercu_cote_bas")
	# Escalier montant dans une pièce de l'étage 1 au plafond réglé à 5 m.
	if not await _load(UnitTest._stairs_high_room()):
		return
	await _fly(Vector3(2.25, 1.2, 9.8), 0.0, 0.9, "escalier_apercu_marches")
	await _fly(Vector3(8.0, 5.1, 7.0), PI * 0.42, 0.3, "escalier_apercu_etage")
	pv.set_maximized(false)
	pv.set_camera_mode(MapPreviewCamera.Mode.ORBIT)

	# En jeu (TESTER) sur DRAFT ARENA, au même endroit.
	ed.open_example("draft_arena")
	await frames(3)
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
	await seconds(2.5)   # fin du titre « chargement »
	p.teleport_to(Vector3(UNDER.x + OFF, 0.05, UNDER.y + 1.5 + OFF))
	await seconds(0.4)
	AutotestHelpers.aim_at(p, Vector3(UNDER.x + OFF, 3.2, UNDER.y - 3.0 + OFF))
	await seconds(0.4)
	_probe("arena, en jeu", p, Vector3(UNDER.x + OFF, 1.6, UNDER.y + OFF))
	await at.screenshot("arena_jeu")
	# Passage de l'atelier (3,2 m) vers l'entrepôt en double hauteur (o4,
	# 4 m en x = 11,75 sur le mur z = 17).
	p.teleport_to(Vector3(11.75 + OFF, 0.05, 20.5 + OFF))
	await seconds(0.4)
	AutotestHelpers.aim_at(p, Vector3(11.75 + OFF, 3.4, 17.0 + OFF))
	await seconds(0.4)
	await at.screenshot("passage_jeu_atelier")
	p.teleport_to(Vector3(11.75 + OFF, 0.05, 12.0 + OFF))
	await seconds(0.4)
	AutotestHelpers.aim_at(p, Vector3(11.75 + OFF, 3.6, 17.0 + OFF))
	await seconds(0.4)
	await at.screenshot("passage_jeu_entrepot")
	Router.back_to_menu()
	await until(func(): return tree().current_scene is MapEditor, 10.0, "retour dans l'éditeur")


func _key_p() -> void:
	var e := InputEventKey.new()
	e.keycode = KEY_P
	e.physical_keycode = KEY_P
	e.pressed = true
	pv._input(e)
	await frames(2)


## Orbite, vol libre et vue joueur sous la passerelle, regard vers le haut.
func _preview_shots(tag: String) -> void:
	var c := Vector3(UNDER.x + OFF, 0.0, UNDER.y + OFF)
	pv.set_camera_mode(MapPreviewCamera.Mode.ORBIT)
	w.rig.pivot = c + Vector3(0, 2.4, -1.5)
	w.rig.yaw = 0.0
	w.rig.pitch = 0.75
	w.rig.dist = 2.5
	w.rig._apply()
	await seconds(0.6)
	_probe(tag + ", aperçu", w.root3d, c + Vector3.UP * 1.6)
	await at.screenshot(tag + "_orbite")
	pv.set_camera_mode(MapPreviewCamera.Mode.FLY)
	w.rig.fly_pos = c + Vector3(0, 1.4, 1.5)
	w.rig.yaw = 0.0
	w.rig.pitch = 0.8
	w.rig._apply()
	await seconds(0.6)
	await at.screenshot(tag + "_vol")
	await _walk_shot(tag + "_joueur")


func _walk_shot(shot: String) -> void:
	pv.set_camera_mode(MapPreviewCamera.Mode.WALK)
	w.rig.place_at(Vector3(UNDER.x + OFF, 0.0, UNDER.y + 1.5 + OFF))
	w.rig.yaw = 0.0
	w.rig.pitch = 0.7
	w.rig._apply()
	await seconds(0.6)
	_probe(shot, w.root3d, Vector3(UNDER.x + OFF, 1.6, UNDER.y + OFF))
	await at.screenshot(shot)


## Rayon vers le haut depuis `from` : surface touchée (collision) et faces
## visibles (maillages) au-dessus de la tête.
func _probe(what: String, node: Node3D, from: Vector3) -> void:
	var space := node.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.UP * 20.0)
	var hit := space.intersect_ray(q)
	var col := "rien"
	if not hit.is_empty():
		col = "%s à y = %.3f" % [(hit.collider as Node).name, (hit.position as Vector3).y]
	var root: Node3D = Game.instance if Game.instance != null else w.groups.arch
	var vis := UnitTest._hit(root, from, true)
	print("[plafond] %s : collision %s ; face visible %s à y = %.3f" % [what, col, vis.get("name", "rien"), float(vis.get("y", 0.0))])
	at.check(String(vis.get("name", "")).ends_with("__ceil"), "%s : plafond vu d'en bas (%s)" % [what, vis.get("name", "rien")])


## Carte de test chargée dans l'éditeur, aperçu reconstruit.
func _load(doc: EditorMap) -> bool:
	ed.new_map(true)
	ed._reset(doc)
	# (Première construction d'une autre carte : vue d'ensemble, MapPreviewWorld.)
	if not await until(func(): return w._framed_doc == ed.doc.get_instance_id() and w.idle() and not w.is_stale(), 30.0, "aperçu de %s" % doc.id):
		return false
	await seconds(0.3)
	return true


## Capture en vol libre depuis `p` (m de l'éditeur, y = hauteur), cap `yaw`, tangage `pitch`.
func _fly(p: Vector3, yaw: float, pitch: float, shot: String) -> void:
	pv.set_camera_mode(MapPreviewCamera.Mode.FLY)
	w.rig.end_glide()
	w.rig.fly_pos = Vector3(p.x + OFF, p.y, p.z + OFF)
	w.rig.yaw = yaw
	w.rig.pitch = pitch
	w.rig._apply()
	await seconds(0.6)
	at.check(w.rig.eye().distance_to(Vector3(p.x + OFF, p.y, p.z + OFF)) < 0.05, "%s : caméra en place" % shot)
	await at.screenshot(shot)
