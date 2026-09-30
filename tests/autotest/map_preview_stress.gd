extends AutotestScenario
## @rendu : a besoin du rendu (aperçu 3D affiché, fenêtre hors écran).
## CONTRAINTE du fil de travail de l'APERÇU 3D (plantage 0xc0000005 de la
## v0.1.149 : passage libre posé, aperçu ouvert). Pendant ~60 s, sur une
## carte complète (lampes, luminaire sur un meuble, décor tourné, formes
## libres, murs en biais, mur courbe, étage), un fil de test calcule
## MapPreviewWorld.compute EN BOUCLE, en plus des mises à jour de l'aperçu
## lui-même (son propre fil), pendant que le fil principal martèle tout ce qui
## est partagé : survol et pose de passages, portes, fenêtres, lampe de bureau
## posée sur le bureau, décor ; onglet Vérification (vérification complète et
## lot de vérification MapRules.begin_batch) ; glisser d'une pièce ; annuler /
## rétablir ; cache des armes et des cases intérieures vidés et refaits ;
## langue basculée à chaque image. Attendu : aucun plantage, aucune erreur,
## aucun accès refusé (ThreadGuard), l'aperçu à jour à la fin.

const T := preload("res://tests/test_preview_thread.gd")
const DURATION := 60.0
## Outils tenus tour à tour, et où les survoler (m) : bords communs, murs
## extérieurs, dessus du bureau, milieu d'une pièce.
const TOOLS := [
	["passage", [Vector2(15, 1.5), Vector2(15, 8.5)]],
	["porte", [Vector2(1.5, 10), Vector2(13.5, 10)]],
	["fenetre", [Vector2(16, -0.3), Vector2(24, -0.3)]],
	["luminaire:lampe_bureau", [Vector2(9.8, 14.6), Vector2(11.2, 15.4)]],
	["prefab:caisses", [Vector2(17, 6), Vector2(23, 8)]],
	["passage", [Vector2(25, 1.5), Vector2(25, 8.5)]],
	["luminaire:suspension", [Vector2(27, 3), Vector2(33, 8)]],
]
const CYCLE := 48   # images par outil : pose, puis annuler / rétablir / glisser

var ed: MapEditor
var cv: MapCanvas
var pv: MapPreviewPanel
var w: MapPreviewWorld
var _mutex := Mutex.new()
var _stop := false
var _next: EditorMap
var _computed := 0
var _empty := 0


## Fil de test : calcule la dernière copie reçue, en boucle (comme le fil de
## l'aperçu, mais sans attendre le délai de 0,3 s).
func _worker() -> void:
	ThreadGuard.enter(false)
	while true:
		_mutex.lock()
		var stop := _stop
		var m := _next
		_next = null
		_mutex.unlock()
		if stop:
			break
		if m == null:
			OS.delay_msec(1)
			continue
		var res := MapPreviewWorld.compute(m)
		_mutex.lock()
		_computed += 1
		if (res.data as Dictionary).is_empty():
			_empty += 1
		_mutex.unlock()
	ThreadGuard.leave()


func run() -> void:
	timeout_sec = 240
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 5.0, "menu principal")
	tree().change_scene_to_file(MapEditor.SCENE)
	if not await until(func(): return tree().current_scene is MapEditor, 6.0, "éditeur ouvert"):
		return
	ed = tree().current_scene
	cv = ed.canvas
	pv = ed.preview
	w = pv.world
	await frames(3)
	ed._reset(T.rich_map())
	await frames(2)
	cv.frame_all()
	ed.panels.show_tab("check")
	pv.pause_unfocused = false
	pv.set_render_scale(0.5)
	pv.set_shown(true)
	if not await until(func(): return w.builds > 0 and w.idle(), 30.0, "première construction"):
		return
	ThreadGuard.take_violations()
	var lang0 := String(Settings.language)
	var thread := Thread.new()
	thread.start(_worker)
	var t0 := Time.get_ticks_msec()
	var builds0 := w.builds
	var n := 0
	var placed := 0
	var moves := 0
	var validations := 0
	var worst := 0.0
	while Time.get_ticks_msec() - t0 < DURATION * 1000.0:
		var f0 := Time.get_ticks_usec()
		# Une copie neuve pour le fil de test dès qu'il a pris la précédente.
		_mutex.lock()
		if _next == null:
			_next = ed.doc.duplicate_map()
		_mutex.unlock()
		var cyc := n / CYCLE
		var step := n % CYCLE
		var tool: Array = TOOLS[cyc % TOOLS.size()]
		if step == 0:
			ed.set_hotbar(0, String(tool[0]))
		# Survol : vérification de pose à chaque image (MapRules, MapSnap).
		var path: Array = tool[1]
		var m: Vector2 = (path[0] as Vector2).lerp(path[1], fposmod(n * 0.037, 1.0))
		_motion(m)
		if step == 6:
			_button(m, true)
			_button(m, false)
			placed += 1
		elif step == 30:
			match cyc % 3:
				0:
					ed.undo()
				1:
					ed.undo()
					ed.redo()
				2:
					moves += int(_drag_room())
		elif step == 40 and cyc % 2 == 0:
			ed.validate()
			validations += 1
		# Caches partagés du fil principal vidés et refaits (le fil de l'aperçu
		# ne doit jamais les lire) ; lot de vérification ouvert et fermé.
		WeaponDB._cache.clear()
		for id in ["m14", "olympia", "mp5k", "ak74u"]:
			WeaponDB.stats(id)
		if n % 5 == 0:
			MapRules._inner_cache.clear()
			ed._update_invalid()
		Settings.language = "en" if n % 2 == 0 else "fr"
		n += 1
		await frames(1)
		worst = maxf(worst, (Time.get_ticks_usec() - f0) / 1000.0)
	Settings.language = lang0
	_mutex.lock()
	_stop = true
	_mutex.unlock()
	thread.wait_to_finish()
	var bad := ThreadGuard.take_violations()
	print("[stress] %d images, %d poses, %d glissers, %d vérifications, fil de test : %d calculs, aperçu : %d mises à jour, pire image %.0f ms" % [
		n, placed, moves, validations, _computed, w.builds - builds0, worst])
	at.check(bad.is_empty(), "aucun état partagé touché hors du fil principal (%s)" % str(bad))
	at.check(_computed >= 40 and _empty == 0, "fil de test : %d calculs, tous complets" % _computed)
	at.check(w.builds - builds0 >= 15, "l'aperçu s'est mis à jour pendant la contrainte (%d fois)" % (w.builds - builds0))
	at.check(placed >= 40 and moves >= 3 and validations >= 5, "poses, glissers et vérifications faits")
	# Au repos : l'aperçu rattrape la carte.
	if await until(func(): return w.idle() and not w.is_stale(), 20.0, "aperçu à jour"):
		print("[stress] dernière mise à jour : conversion %.0f ms (fil de travail), construction %.0f ms (plus longue étape %.0f ms), délai total %.0f ms" % [
			w.last_times.thread, w.last_times.apply, w.last_times.step_max, w.last_times.total])
	at.check(ThreadGuard.take_violations().is_empty(), "toujours aucun accès refusé")


## Glisse la pièce ronde d'un mètre (comme l'outil Sélection), aller ou retour.
func _drag_room() -> bool:
	var room := {}
	for p in ed.doc.pieces:
		if p.has("forme"):
			room = p
	if room.is_empty():
		return false
	var snap0 := ed.doc.snapshot()
	var dx := 1.0 if float(room.contour[0][0]) < 52.0 else -1.0
	var res := ed.try_move(room.duplicate(true), ed.attached_to(room), Vector2(dx, 0.0), snap0)
	if res.ok:
		ed.push_undo_snapshot(snap0)
		ed.changed()
	return res.ok


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
