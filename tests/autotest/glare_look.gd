extends AutotestScenario
## @rendu : captures des lumières fortes par préréglage de qualité.
## @niveau perf : hors check par défaut (captures et mesures de luminance) ;
## lancer avec SCENARIOS="glare_look" JOBS=1 GUI_JOBS=1 bash tools/check.sh.
## Éblouissement en qualité HAUTE : mêmes points de vue en MOYENNE puis en
## HAUTE, luminance mesurée sur chaque capture (part de pixels brûlés,
## luminance moyenne) ; HAUTE ne doit jamais être nettement plus brûlée que
## MOYENNE.
##  1. BUNKER K-7 en partie : boîte mystère au repos, pendant le tirage, arme
##     prête ; courant rétabli : lampe, Pack-a-Punch, atout, flamme de bouche ;
##  2. éditeur, aperçu 3D de DRAFT ARENA avec tous les luminaires : lampes de
##     près et de dessous, boîte mystère, vue d'ensemble.
## Captures : tests/_out/shots/glare_look_*.png.

var H := AutotestHelpers
## Écart maximal toléré (HAUTE - MOYENNE) de la part de pixels saturés.
const MAX_EXTRA_SATURATED := 0.004
## Écart maximal toléré (HAUTE / MOYENNE) de la luminance moyenne.
const MAX_MEAN_RATIO := 1.25
## Pixel « brûlé » : luminance de sortie (0..1) au-dessus de ce seuil (les
## blancs chauds des ampoules comptent aussi, pas seulement le blanc pur).
const BURNT_LUMA := 0.93

## Luminaires posés dans la salle des machines de DRAFT ARENA (aperçu 3D) :
## [luminaire, position (m), rotation].
const LAMPS := [
	["ampoule", [7.0, 25.0], 0], ["suspension", [9.5, 25.5], 0], ["neon", [12.0, 25.0], 0],
	["lustre", [10.0, 28.5], 0], ["applique", [10.0, 32.75], 180],
	["lampe_bureau", [5.5, 30.0], 0], ["projecteur", [14.0, 30.5], 0],
	["bougies", [7.5, 31.0], 0], ["feu", [12.0, 31.0], 0],
]

var _stats := {}


func run() -> void:
	timeout_sec = 300
	var initial := Settings.quality
	await _game_pass()
	Router.back_to_menu()
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 5.0, "retour au menu")
	await _editor_pass()
	Settings.quality = initial
	Settings.changed.emit()
	_compare()


func _set_quality(q: int) -> void:
	Settings.quality = q
	Settings.changed.emit()
	await seconds(0.6)  # préréglage appliqué, brume temporelle posée


# ------------------------------------------------------------------ partie

func _game_pass() -> void:
	var p: Player = await H.start_solo_game(self, "bunker_k7")
	if p == null:
		return
	var game := Game.instance
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	await H.clear_zombies(self)
	for id in game.doors:
		game.doors[id].srv_open()
	await seconds(0.5)  # collisions des portes coupées (différé) avant les téléports
	var box: MysteryBox = game.interact.get_obj("box")
	at.check(box != null, "bunker_k7 : boîte mystère")
	if box == null:
		return
	game.session.add_points(1, 50000)
	for q in [Settings.Quality.MEDIUM, Settings.Quality.HIGH]:
		var qn: String = RenderQuality.preset(q).name
		await _set_quality(q)
		_place(p, box, 2.6)
		await seconds(0.6)  # capture : image posée
		await _shot(at.get_viewport(), "boite_repos_" + qn)
		p.input.interact_pressed = true
		await until(func(): return box.state == MysteryBox.State.ROLLING, 2.0, "défilement")
		await seconds(1.2)  # capture : couvercle ouvert, armes qui défilent
		await _shot(at.get_viewport(), "boite_tirage_" + qn)
		await until(func(): return box.state == MysteryBox.State.READY, 6.0, "arme prête")
		await seconds(0.3)
		await _shot(at.get_viewport(), "boite_prete_" + qn)
		p.input.interact_pressed = true
		await until(func(): return box.state == MysteryBox.State.IDLE, 2.0, "arme prise")
	# Courant rétabli : lampes, Pack-a-Punch et atouts allumés.
	(game.interact.get_obj("power") as PowerSwitch).srv_use(1)
	await seconds(3.0)  # cascade d'allumage terminée
	var lamp := _nearest_lamp(p.global_position)
	var pap: Node3D = game.interact.get_obj("pap")
	var perks := tree().current_scene.find_children("*", "PerkMachine", true, false)
	# Arme de départ en main (flamme de bouche), chargeur plein.
	var pd := game.session.local_data()
	pd.weapons = [WeaponDB.new_instance(WeaponDB.STARTING_WEAPON)]
	pd.slot = 0
	game.session.sync_inventory(1)
	await seconds(WeaponController.SWITCH_TIME + 0.25)
	for q in [Settings.Quality.MEDIUM, Settings.Quality.HIGH]:
		var qn: String = RenderQuality.preset(q).name
		await _set_quality(q)
		if lamp != null:
			await _look_at(p, lamp.global_position, 3.0, "lampe_" + qn)
		if pap != null:
			await _look_at(p, pap.global_position + Vector3.UP * 1.0, 2.8, "pap_" + qn)
		if not perks.is_empty():
			await _look_at(p, (perks[0] as Node3D).global_position + Vector3.UP * 1.2, 2.8, "atout_" + qn)
		# Flamme de bouche : capture pendant le tir, face à un mur sombre.
		p.input.fire = true
		for i in 30:
			await frames(1)
			if p.weapons.view._flash_rig.visible:
				break
		print("[glare_look] tir_%s : flamme %s" % [qn, "visible" if p.weapons.view._flash_rig.visible else "déjà éteinte"])
		await _shot(at.get_viewport(), "tir_" + qn, 0)
		p.input.fire = false
		await seconds(0.4)


## Lampe de la carte (allumée) la plus proche de `from`.
func _nearest_lamp(from: Vector3) -> OmniLight3D:
	var best: OmniLight3D = null
	for l in tree().get_nodes_in_group(RenderQuality.LAMP_GROUP):
		var o := l as OmniLight3D
		if o == null or not o.is_visible_in_tree() or o.light_energy <= 0.05:
			continue
		if best == null or o.global_position.distance_to(from) < best.global_position.distance_to(from):
			best = o
	return best


## Joueur à `dist` m (à l'horizontale) de `target`, dans la direction la plus
## dégagée, qui le regarde ; capture.
func _look_at(p: Player, target: Vector3, dist: float, shot_name: String) -> void:
	var space := Game.instance.world.get_world_3d().direct_space_state
	var o := Vector3(target.x, target.y if target.y < 1.6 else 1.6, target.z)
	var best_dir := Vector3.FORWARD
	var best := -1.0
	for k in 12:
		var d := Vector3.FORWARD.rotated(Vector3.UP, k * TAU / 12.0)
		var q := PhysicsRayQueryParameters3D.create(o + d * 0.6, o + d * (dist + 0.8))
		q.exclude = [p.get_rid()]
		var hit := space.intersect_ray(q)
		var free := dist + 0.8 if hit.is_empty() else o.distance_to(hit.position)
		if free > best:
			best = free
			best_dir = d
	var pos := Vector3(target.x, 0.0, target.z) + best_dir * minf(dist, best - 0.6)
	pos.y = target.y - 1.6
	var q2 := PhysicsRayQueryParameters3D.create(Vector3(pos.x, target.y - 0.3, pos.z), Vector3(pos.x, target.y - 20.0, pos.z))
	q2.exclude = [p.get_rid()]
	var g := space.intersect_ray(q2)
	if not g.is_empty():
		pos.y = g.position.y
	p.teleport_to(pos + Vector3(0, 0.05, 0))
	await seconds(0.3)  # posé après le téléport
	H.aim_at(p, target)
	await seconds(0.5)  # capture : image posée (brume temporelle)
	await _shot(at.get_viewport(), shot_name)


## Joueur à `dist` m devant la boîte, qui la regarde.
func _place(p: Player, box: MysteryBox, dist: float) -> void:
	var n: Vector3 = box.spots[box.location].normal
	var fwd := -Vector3(n.x, 0, n.z).normalized()
	p.teleport_to(box.global_position + fwd * dist + fwd.cross(Vector3.UP) * 0.6 + Vector3(0, 0.05, 0))
	await frames(2)
	H.aim_at(p, box.global_position + Vector3.UP * 0.7)


# ------------------------------------------------------------------ éditeur

func _editor_pass() -> void:
	tree().change_scene_to_file(MapEditor.SCENE)
	if not await until(func(): return tree().current_scene is MapEditor, 6.0, "éditeur ouvert"):
		return
	var ed: MapEditor = tree().current_scene
	var pv := ed.preview
	var w := pv.world
	await frames(3)
	ed.open_example("draft_arena")
	await frames(3)
	# Tous les luminaires dans la salle des machines (plafond, mur, sol).
	for l in LAMPS:
		ed.add_object({"type": "luminaire", "luminaire": l[0], "position": l[1], "rot": l[2]}, 0)
	ed.changed()
	pv.pause_unfocused = false
	pv.set_render_scale(1.0)
	# P : aperçu affiché (il peut l'être déjà : état de l'éditeur retenu).
	if not pv.shown:
		var e := InputEventKey.new()
		e.keycode = KEY_P
		e.physical_keycode = KEY_P
		e.pressed = true
		pv._input(e)
	await frames(2)
	pv.set_maximized(true)
	if not await until(func(): return w.builds > 0 and w.idle() and not w.is_stale(), 120.0, "aperçu construit"):
		return
	at.check(w.viewport.find_children("*", "OmniLight3D", true, false).size() >= LAMPS.size(), "luminaires dans l'aperçu")
	# [nom, point visé (carte : x, hauteur, y), lacet, tangage, distance]
	var views := [
		["lampes", Vector3(10.0, 1.8, 26.0), 0.0, -0.12, 5.0],
		["lampes_dessous", Vector3(9.5, 2.4, 25.5), PI * 0.8, 0.15, 3.5],
		["boite", Vector3(6.75, 1.0, 17.5), PI, -0.25, 3.5],
		["ensemble", Vector3(10.0, 0.0, 22.0), 0.5, -0.85, 22.0],
	]
	for v in views:
		var p: Vector3 = v[1]
		w.rig.set_mode(MapPreviewCamera.Mode.ORBIT)
		w.rig.pivot = Vector3(p.x + MapGeom.WORLD_OFFSET, p.y, p.z + MapGeom.WORLD_OFFSET)
		w.rig.yaw = v[2]
		w.rig.pitch = v[3]
		w.rig.dist = v[4]
		w.rig._apply()
		for q in [Settings.Quality.MEDIUM, Settings.Quality.HIGH]:
			await _set_quality(q)
			await seconds(0.6)  # quelques images de l'aperçu (24 images/s au repos)
			await _shot(w.viewport, "apercu_%s_%s" % [v[0], RenderQuality.preset(q).name])
	pv.set_maximized(false)


# ------------------------------------------------------------------ mesures

## Capture d'un viewport et mesure : part de pixels brûlés (luminance >=
## BURNT_LUMA) et luminance moyenne. `wait_frames` : images attendues avant.
func _shot(vp: Viewport, shot_name: String, wait_frames := 2) -> void:
	await frames(wait_frames)
	if DisplayServer.get_name() == "headless":
		return
	var img := vp.get_texture().get_image()
	if img == null:
		return
	var dir := ProjectSettings.globalize_path("res://tests/_out/shots")
	DirAccess.make_dir_recursive_absolute(dir)
	img.save_png("%s/glare_look_%s.png" % [dir, shot_name])
	var s := luminance_stats(img)
	_stats[shot_name] = s
	print("[glare_look] %s : saturés %.4f, luminance moyenne %.3f, max %.3f" % [shot_name, s.saturated, s.mean, s.max])


static func luminance_stats(img: Image) -> Dictionary:
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGB8)
	var data := img.get_data()
	var n := data.size() / 3
	var sat := 0
	var total := 0.0
	var mx := 0.0
	# Un pixel sur 4 suffit (images de 1280x720).
	var i := 0
	var count := 0
	while i < n:
		var r := data[i * 3]
		var g := data[i * 3 + 1]
		var b := data[i * 3 + 2]
		var l := (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0
		if l >= BURNT_LUMA:
			sat += 1
		total += l
		mx = maxf(mx, l)
		count += 1
		i += 4
	return {"saturated": float(sat) / maxi(count, 1), "mean": total / maxi(count, 1), "max": mx}


func _compare() -> void:
	for key in _stats:
		# Tir : flamme et lumière de bouche fugaces, capturées à un instant
		# différent d'un préréglage à l'autre (capture à regarder, sans mesure).
		if not key.ends_with("_high") or key.begins_with("tir_"):
			continue
		var med_key: String = key.trim_suffix("_high") + "_medium"
		if not _stats.has(med_key):
			continue
		var hi: Dictionary = _stats[key]
		var me: Dictionary = _stats[med_key]
		at.check(hi.saturated - me.saturated <= MAX_EXTRA_SATURATED,
				"%s : HAUTE pas plus brûlée que MOYENNE (saturés %.4f / %.4f)" % [key.trim_suffix("_high"), hi.saturated, me.saturated])
		at.check(hi.mean <= me.mean * MAX_MEAN_RATIO + 0.01,
				"%s : HAUTE pas plus lumineuse que MOYENNE (moyenne %.3f / %.3f)" % [key.trim_suffix("_high"), hi.mean, me.mean])
