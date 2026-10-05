extends AutotestScenario
## @rendu : captures d'une pièce sans plafond sous chacun des trois ciels de la
## carte (noir, jour, nuit étoilée), revue humaine (étape 2 de docs/LEVELS_PLAN.md).
## @niveau perf : hors check par défaut (captures d'un ajout en cours) ;
## lancer avec SCENARIOS="map_sky_look" JOBS=1 GUI_JOBS=1 bash tools/check.sh
## (ou sh tools/scenario.sh map_sky_look).
## DRAFT ARENA, salle des machines (p1) à ciel ouvert : aperçu 3D en vol libre,
## regard vers le haut, pour chaque ciel ; luminosité moyenne d'une vue de
## l'entrepôt (pièce fermée) : le ciel ne doit pas changer son éclairage ;
## puis en jeu (TESTER) sous le ciel de jour.

const OFF := MapGeom.WORLD_OFFSET
## Salle des machines (2,5-17 x 21,5-33) : regard vers le mur nord et le ciel.
const EYE := Vector3(9.75, 1.7, 31.5)
## Entrepôt (pièce fermée, 2,5-17 x 4,5-17).
const CLOSED := Vector3(12.0, 1.7, 15.5)

var ed: MapEditor
var pv: MapPreviewPanel
var w: MapPreviewWorld


func run() -> void:
	timeout_sec = 180
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 5.0, "menu principal")
	# Copie de récupération d'un passage précédent (dossier du scénario) : pas de question.
	MapUnsaved.drop_recovery()
	tree().change_scene_to_file(MapEditor.SCENE)
	if not await until(func(): return tree().current_scene is MapEditor, 6.0, "éditeur ouvert"):
		return
	ed = tree().current_scene
	pv = ed.preview
	w = pv.world
	await frames(3)
	ed.open_example("draft_arena")
	await frames(3)
	EditorMap.set_no_ceiling(ed.doc.find("p1"), true)
	ed.changed()
	pv.pause_unfocused = false
	pv.set_render_scale(1.0)
	if not pv.shown:
		pv.set_shown(true)
	if not await _built("aperçu construit"):
		return
	pv.set_maximized(true)
	var lums := {}
	for shot in ["noir", "jour", "nuit", "noir2"]:
		var t: String = String(shot).trim_suffix("2")
		EditorMap.set_sky(ed.doc.carte, t, 1.0)
		ed.changed()
		if not await _built("aperçu, ciel %s" % t):
			return
		at.check(String(w.env.get_meta("sky", {"type": "noir"}).get("type", "")) == t, "ciel %s appliqué à l'aperçu" % t)
		if shot == t:
			await _fly(EYE, 0.0, 0.5)
			await at.screenshot("apercu_" + t)
		await _fly(CLOSED, 0.0, -0.1)
		# Plus forte des mesures sur 3 s (lampes qui vacillent : un creux passager).
		var samples := []
		for i in 6:
			samples.append(_mean_lum())
			await seconds(0.5)
		lums[shot] = samples.max()
		print("[ciel] %s : luminosité moyenne de l'entrepôt (pièce fermée) %.4f (mesures %s)" % [shot, lums[shot], str(samples.map(func(x): return snappedf(x, 0.0001)))])
	for t in ["jour", "nuit"]:
		at.check(absf(float(lums[t]) - float(lums.noir)) < 0.01, "ciel %s : pièce fermée éclairée comme avant (%.4f contre %.4f)" % [t, lums[t], lums.noir])
	# Luminosité réglée (jour, 40 %).
	EditorMap.set_sky(ed.doc.carte, "jour", 0.4)
	ed.changed()
	if await _built("aperçu, jour à 40 %"):
		await _fly(EYE, 0.0, 0.5)
		await at.screenshot("apercu_jour_40")
	pv.set_maximized(false)

	# En jeu (TESTER), ciel de jour.
	EditorMap.set_sky(ed.doc.carte, "jour", 1.0)
	ed.changed()
	await frames(2)
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
	var we := game.world.get_node_or_null("WorldEnvironment") as WorldEnvironment
	at.check(we != null and we.environment.background_mode == Environment.BG_SKY, "ciel de jour en jeu")
	p.teleport_to(Vector3(EYE.x + OFF, 0.05, EYE.z + OFF))
	await seconds(0.4)
	AutotestHelpers.aim_at(p, Vector3(EYE.x + OFF, 6.0, 23.0 + OFF))
	await seconds(0.4)
	var space := p.get_world_3d().direct_space_state
	var from := Vector3(EYE.x + OFF, 1.6, EYE.z + OFF)
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3.UP * 30.0))
	at.check(hit.is_empty(), "ciel ouvert en jeu : aucune collision au-dessus (%s)" % str(hit.get("collider")))
	await at.screenshot("jeu_jour")
	Router.back_to_menu()
	await until(func(): return tree().current_scene is MapEditor, 10.0, "retour dans l'éditeur")


func _built(what: String) -> bool:
	await frames(2)
	return await until(func(): return w.builds > 0 and w.idle() and not w.is_stale(), 30.0, what)


## Vol libre depuis `pos` (m de l'éditeur, y = hauteur), cap `yaw`, tangage `pitch`.
func _fly(pos: Vector3, yaw: float, pitch: float) -> void:
	pv.set_camera_mode(MapPreviewCamera.Mode.FLY)
	w.rig.end_glide()
	w.rig.fly_pos = Vector3(pos.x + OFF, pos.y, pos.z + OFF)
	w.rig.yaw = yaw
	w.rig.pitch = pitch
	w.rig._apply()
	await seconds(0.6)


## Luminosité moyenne (0..1) de l'image de l'aperçu.
func _mean_lum() -> float:
	var img := w.viewport.get_texture().get_image()
	if img == null or img.is_empty():
		return -1.0
	img.resize(64, 40, Image.INTERPOLATE_BILINEAR)
	var s := 0.0
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			s += c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722
	return s / float(img.get_width() * img.get_height())
