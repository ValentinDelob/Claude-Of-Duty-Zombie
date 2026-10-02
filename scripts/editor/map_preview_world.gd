class_name MapPreviewWorld
extends Node
## Monde de l'APERÇU 3D de l'éditeur de cartes (MapPreviewPanel) : la carte
## éditée construite en direct par le code du jeu, dans son propre monde 3D
## (SubViewport à monde propre), avec l'éclairage de la partie
## (WorldLook.setup_environment : environnement, grain de film, RenderQuality).
##
## Mise à jour après chaque modification : l'empreinte de la carte est lue
## toutes les 0,1 s ; stable depuis DELAY, la carte est recopiée et convertie
## HORS DU FIL PRINCIPAL (Thread : MapRaster -> étapes du validateur utiles à
## la géométrie -> MapLayoutExport, les mêmes que pour une partie), puis les
## morceaux qui ont changé (architecture, décor, lampes, objets de jeu) sont
## reconstruits, UN PAR IMAGE, l'ancien morceau restant affiché jusqu'au
## remplacement. Objets de jeu (portes, fenêtres barricadées, atouts, armes,
## boîte, Pack-a-Punch, courant, téléporteur, pièges, grenades) : les
## fonctions de construction de Game (_build_doors...) appelées sur un « jeu »
## hors de l'arbre, sans réseau ni joueurs, figés (aucun _process : ni son ni
## animation).
##
## Options : courant rétabli ou coupé, éclairage du jeu ou plein, plafonds
## masqués (vue de dessus en coupe), étages montrés, surlignage de l'élément
## choisi ou survolé, sélection par un rayon (pick).

signal rebuilt

## Délai après la dernière modification avant la mise à jour (s).
const DELAY := 0.3
const POLL := 0.1
const OFF := MapGeom.WORLD_OFFSET
enum Floors { ALL, UP_TO, ONLY }
const PARTS := ["arch", "decor", "lamps", "stuff"]
const COL_SEL := Color(1.0, 0.85, 0.3)
const COL_HOVER := Color(0.35, 0.9, 1.0)

var viewport: SubViewport
var root3d: Node3D
var env: Environment
var rig: MapPreviewCamera
## Carte suivie (celle de l'éditeur).
var doc: EditorMap
## Construction et rendu actifs (panneau visible).
var active := false
## Mise à jour automatique (sinon : rebuild_now).
var auto := true

# ------------------------------------------------------------------ options
var power_on := true
var full_light := false
var hide_ceilings := false
## Barrières invisibles (format 5) montrées en pavés translucides.
var show_clips := true
var floors_mode := Floors.ALL
## Étage affiché dans la vue 2D (options « jusqu'à » / « seulement »).
var view_floor := 0
var selected_id := ""
var hover_id := ""

# ------------------------------------------------------------------ état
## Dernière carte construite (copie) et sa description.
var built_map: EditorMap
var data: Dictionary = {}
var layout: MeshMapLayout
var def: EditorMapDef
## Erreurs relevées pendant la conversion (carte pas encore jouable).
var errors := 0
var groups: Dictionary = {}     # morceau -> Node3D
var builders: Dictionary = {}   # morceau -> MapProps (courant, grésillement)
var _hashes: Dictionary = {}    # morceau -> empreinte des données
## Faux jeu des objets de jeu (hors de l'arbre) et son registre.
var _game: Game
var _interact: InteractionSystem
## Unités affichables : nœud -> [étage, sorte] (visibilité par étage / plafond).
var _units: Dictionary = {}
var _floor_sols: Array = [0.0]
## Temps mesurés (ms) : conversion hors du fil principal, construction sur le
## fil principal (somme des étapes), plus longue étape, délai total.
var last_times := {"thread": 0.0, "apply": 0.0, "step_max": 0.0, "total": 0.0, "parts": []}
var builds := 0
var building := false

var _thread: Thread
var _job: Job
var _built_hash := 0
var _job_hash := 0
var _seen_hash := 0
var _stable := 0.0
var _poll_t := 0.0
var _change_t := 0
var _queue: Array[Callable] = []
var _result: Dictionary = {}
var _apply_ms := 0.0
var _step_max := 0.0
var _overlay: MeshInstance3D
var _overlay_key := ""
var _base_env := {}
var _framed_doc := 0


## Conversion d'une copie de la carte, dans le fil de travail. Tout ce qu'il
## lit est à lui ou figé avant le lancement (ThreadGuard, docs/ARCHITECTURE.md
## « Fils de travail ») : `map` (copie profonde, faite sur le fil principal),
## `lang_en` (langue des textes), le catalogue (MapCatalog, construit puis mis
## en lecture seule sur le fil principal) et des constantes. Les caches du
## fil principal (MapRules, WeaponDB...) refusent tout accès depuis le fil.
class Job extends RefCounted:
	var map: EditorMap
	var lang_en := false

	func run() -> Dictionary:
		ThreadGuard.enter(lang_en)
		var res := MapPreviewWorld.compute(map)
		ThreadGuard.leave()
		return res


func _ready() -> void:
	viewport = SubViewport.new()
	viewport.name = "PreviewViewport"
	viewport.own_world_3d = true
	viewport.size = Vector2i(640, 400)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.audio_listener_enable_3d = false
	viewport.handle_input_locally = false
	viewport.physics_object_picking = false
	add_child(viewport)
	root3d = Node3D.new()
	root3d.name = "PreviewWorld"
	viewport.add_child(root3d)
	# Éclairage de la partie : environnement BO1, grain, préréglage de qualité
	# (RenderQuality règle ombres, glow, brume et résolution 3D du SubViewport).
	WorldLook.setup_environment(root3d, {})
	var we := root3d.get_node("WorldEnvironment") as WorldEnvironment
	env = we.environment
	_base_env = {"ambient_color": env.ambient_light_color, "ambient_energy": env.ambient_light_energy,
		"fog": env.fog_enabled, "exposure": env.tonemap_exposure}
	Settings.changed.connect(_apply_light)
	rig = MapPreviewCamera.new()
	rig.name = "Camera"
	root3d.add_child(rig)
	_overlay = MeshInstance3D.new()
	_overlay.name = "Highlight"
	_overlay.mesh = ImmediateMesh.new()
	_overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.render_priority = 10
	_overlay.material_override = mat
	root3d.add_child(_overlay)
	_apply_light()


func _exit_tree() -> void:
	_join()
	_free_game()


## Libéré sans passer par _exit_tree (jamais entré dans l'arbre) : le fil est
## attendu avant que son travail ne disparaisse.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_join()


func _join() -> void:
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null
		_job = null


# ------------------------------------------------------------------ conversion (fil de travail)

## Carte de l'éditeur -> description en maillage, comme pour une partie
## (EditorMapDef._setup) mais sans les vérifications d'accès ni les
## indicateurs d'amusement du validateur (plusieurs secondes sur une grande
## carte, inutiles à la géométrie) : seules les étapes qui relèvent les
## zones, escaliers, ouvertures et objets (MapValidator.analyze, dans le même
## ordre). Une carte pas encore jouable s'affiche quand même (sans départ :
## un point de vue au milieu de la première pièce). Fonction pure : aucune
## scène, aucun nœud, aucune ressource, aucun état partagé modifiable
## (appelée hors du fil principal : tests/test_preview_thread.gd).
static func compute(m: EditorMap) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var out := {"data": {}, "errors": 0, "map": m, "sols": [], "ms": 0.0}
	for k in m.floor_count():
		out.sols.append(m.floor_sol(k))
	if m.pieces.is_empty():
		out.ms = (Time.get_ticks_usec() - t0) / 1000.0
		return out
	var v := MapRaster.build(m).v
	v.check_floors()
	if v.errors().is_empty():
		# _counts : leviers rattachés à leurs pièges (sans lui, aucun piège).
		for step in ["_find_blobs", "_marker_zones", "_stairs", "_openings", "_wall_markers", "_floor_markers", "_zone_graph", "_counts"]:
			v.call(step)
	if v.start_points.is_empty():
		var r: Dictionary = m.pieces[0]
		var c := MapGeom.centroid(m.room_poly(r))
		v.start_points = [[clampi(int(r.get("etage", 0)), 0, v.floors.size() - 1), Vector2(MapGeom.cell_of(c)) + Vector2(0.5, 0.5)]]
	out.errors = v.errors().size()
	out.data = MapLayoutExport.build(v)
	out.ms = (Time.get_ticks_usec() - t0) / 1000.0
	return out


# ------------------------------------------------------------------ boucle

func _process(delta: float) -> void:
	if _thread != null and not _thread.is_alive():
		var got: Variant = _thread.wait_to_finish()
		_thread = null
		_job = null
		print("[Apercu3D] calcul fini (%.0f ms), construction sur le fil principal" % (float(got.get("ms", 0.0)) if got is Dictionary else -1.0))
		# Calcul interrompu (erreur dans le fil) : rien de construit, jamais
		# une valeur d'un autre type passée à la suite.
		_on_computed(got if got is Dictionary else {"data": {}, "errors": 1, "map": doc.duplicate_map() if doc != null else null, "sols": [0.0]})
	if not _queue.is_empty():
		_run_step()
		return
	if not active or not auto or doc == null or _thread != null:
		return
	_poll_t -= delta
	if _poll_t > 0.0:
		return
	_poll_t = POLL
	var h := doc_hash()
	if h == _built_hash:
		_seen_hash = h
		return
	if h != _seen_hash:
		_seen_hash = h
		_stable = 0.0
		_change_t = Time.get_ticks_msec()
		return
	_stable += POLL
	if _stable >= DELAY - 0.001:
		_start(h)


func doc_hash() -> int:
	return hash(doc.to_dict()) if doc != null else 0


## La carte suivie a changé depuis la dernière construction (ou en cours) ?
func is_stale() -> bool:
	return doc != null and doc_hash() != _built_hash


func _start(h: int) -> void:
	# Préparé ici, sur le fil principal : catalogue construit et figé, copie
	# profonde de la carte, langue. Le fil n'a rien d'autre à lire.
	MapCatalog.items()
	_job_hash = h
	_job = Job.new()
	_job.map = doc.duplicate_map()
	_job.lang_en = Lang.is_en()
	building = true
	# Journal (vidé à chaque ligne) : un plantage pendant le calcul s'y voit.
	print("[Apercu3D] calcul lancé : %d pièces, %d ouvertures, %d objets" % [doc.pieces.size(), doc.ouvertures.size(), doc.objets.size()])
	_thread = Thread.new()
	_thread.start(_job.run)


## Reconstruction immédiate, sans fil ni étalement (tests, première image).
func rebuild_now() -> void:
	_join()   # calcul en cours : attendu, remplacé par le calcul immédiat
	while not _queue.is_empty():
		_run_step()
	if doc == null:
		return
	_change_t = Time.get_ticks_msec()
	_job_hash = doc_hash()
	building = true
	_on_computed(compute(doc.duplicate_map()))
	while not _queue.is_empty():
		_run_step()


## Attend la fin de la mise à jour en cours (tests).
func idle() -> bool:
	return _thread == null and _queue.is_empty() and not building


func _on_computed(res: Dictionary) -> void:
	# Accès refusés dans le fil (cache du fil principal atteint : bogue à corriger).
	for what in ThreadGuard.take_violations():
		push_error("[Apercu3D] état partagé touché hors du fil principal : " + what)
	_result = res
	_apply_ms = 0.0
	_step_max = 0.0
	last_times.thread = float(res.get("ms", 0.0))
	var nd: Dictionary = res.get("data", {})
	var todo := []
	var hashes := {
		"arch": MapPreviewBuilder.part_hash(nd, MapPreviewBuilder.ARCH_KEYS),
		"decor": MapPreviewBuilder.part_hash(nd, MapPreviewBuilder.DECOR_KEYS),
		"lamps": MapPreviewBuilder.lamps_hash(nd),
		"stuff": MapPreviewBuilder.markers_hash(nd),
	}
	for p in PARTS:
		if not groups.has(p) or int(_hashes.get(p, 0)) != int(hashes[p]):
			todo.append(p)
	last_times.parts = todo
	last_times.part_ms = {}
	_queue.clear()
	_queue.append(func(): _prepare(res, hashes))
	for p in todo:
		_queue.append(_build_part.bind(p))
	_queue.append(_finish)


func _run_step() -> void:
	var t := Time.get_ticks_usec()
	var step: Callable = _queue.pop_front()
	step.call()
	var ms := (Time.get_ticks_usec() - t) / 1000.0
	_apply_ms += ms
	_step_max = maxf(_step_max, ms)


func _prepare(res: Dictionary, hashes: Dictionary) -> void:
	built_map = res.get("map")
	data = res.get("data", {})
	errors = int(res.get("errors", 0))
	_floor_sols = res.get("sols", [0.0])
	def = _def_of(data, built_map)
	layout = MeshMapLayout.new(def, data, "") if not data.is_empty() else null
	_result = {"hashes": hashes}


## Réglages de la carte lus dans sa description (comme EditorMapDef._setup).
static func _def_of(d: Dictionary, m: EditorMap) -> EditorMapDef:
	var ed := EditorMapDef.new()
	ed.editor_map = m
	ed.id = "apercu"
	ed.layout_data = d
	var md: Dictionary = d.get("map_def", {})
	ed.zone_names = md.get("zone_names", {})
	ed.doors = md.get("doors", {})
	ed.open_links = md.get("open_links", {})
	ed.box_start = int(md.get("box_start", 0))
	ed.box_starts = md.get("box_starts", [])
	if bool(md.get("teleporter_link", false)):
		ed.teleporter_link = true
		ed.teleporter_cost = 0
	return ed


func _build_part(part: String) -> void:
	var t0 := Time.get_ticks_usec()
	_build_part_now(part)
	last_times.part_ms[part] = snappedf((Time.get_ticks_usec() - t0) / 1000.0, 0.1)


func _build_part_now(part: String) -> void:
	if groups.has(part) and is_instance_valid(groups[part]):
		(groups[part] as Node).name = "Old_" + part
	var holder := Node3D.new()
	holder.name = "Part_" + part
	root3d.add_child(holder)
	if not data.is_empty():
		match part:
			"arch", "decor", "lamps":
				var b := MapPreviewBuilder.new(data)
				match part:
					"arch":
						b.build_architecture(holder)
					"decor":
						b.build_decor(holder)
					"lamps":
						b.build_lamps(holder)
				builders[part] = b
			"stuff":
				_build_stuff(holder)
	else:
		builders.erase(part)
	if groups.has(part) and is_instance_valid(groups[part]):
		# Libéré en fin d'image (après les ajouts différés de ses objets :
		# tas de planches des emplacements de la boîte...), caché dès maintenant.
		var old: Node3D = groups[part]
		_forget_units(old)
		old.visible = false
		old.queue_free()
	groups[part] = holder
	_hashes[part] = int(_result.get("hashes", {}).get(part, 0))
	_classify(part, holder)
	_apply_power()
	_apply_visibility()
	if part == "stuff":
		# Objets ajoutés en différé (tas de planches de la boîte, arrivée du
		# téléporteur) : rangés par étage à la fin de l'image.
		(func():
			if is_instance_valid(holder) and groups.get("stuff") == holder:
				_classify("stuff", holder)
				_apply_visibility()).call_deferred()


## Objets de jeu : les fonctions de construction de Game, sur un jeu hors de
## l'arbre (sans joueurs, réseau, zombies ni navigation).
func _build_stuff(holder: Node3D) -> void:
	_free_game()
	if layout == null:
		return
	_game = Game.new()
	_game.name = "PreviewGame"
	_interact = InteractionSystem.new()
	_interact.game = _game
	_game.map_def = def
	_game.layout = layout
	_game.world = holder
	_game.interact = _interact
	var lamps: MapProps = builders.get("lamps")
	if lamps == null:
		lamps = MapPreviewBuilder.new(data)
		lamps.build_lamps(holder)
		builders["lamps"] = lamps
	_game.props = lamps
	_game._build_doors()
	_game._build_wall_buys()
	_game._build_power()
	_game._build_perk_machines()
	_game._build_mystery_box()
	_game._build_pack_a_punch()
	_game._build_teleporter()
	_game._build_traps()
	# Fenêtres barricadées (comme BarricadeSystem.setup) et grenades
	# (ThrowableSystem._build_buys).
	var wroot := Node3D.new()
	wroot.name = "Barricades"
	holder.add_child(wroot)
	for w: BarricadeLayout.Opening in layout.windows():
		var b := Barricade.new()
		b.setup(w)
		_interact.register(b)
		wroot.add_child(b)
	var ts := ThrowableSystem.new()
	ts.game = _game
	ts._build_buys()
	ts.free()
	# Figés : aucune animation, aucun son, aucun calcul par image.
	for n in holder.find_children("*", "", true, false):
		n.set_process(false)
		n.set_physics_process(false)
	# Les portes se traversent en vue joueur (visite de la carte).
	var bodies := []
	for d in holder.find_children("Door*", "Door", true, false):
		bodies.append_array(d.find_children("*", "StaticBody3D", true, false))
	rig.door_bodies = bodies


func _free_game() -> void:
	if _interact != null:
		_interact.free()
		_interact = null
	if _game != null:
		_game.free()
		_game = null


func _finish() -> void:
	_built_hash = _job_hash
	building = false
	builds += 1
	last_times.apply = _apply_ms
	last_times.step_max = _step_max
	last_times.total = float(Time.get_ticks_msec() - _change_t)
	# Première construction ou autre carte ouverte : vue d'ensemble.
	if doc != null and doc.get_instance_id() != _framed_doc:
		_framed_doc = doc.get_instance_id()
		frame_map()
	_overlay_key = ""
	update_overlay()
	print("[Apercu3D] mise à jour : conversion %.0f ms (hors fil principal), construction %.0f ms (plus longue étape %.0f ms), morceaux %s" % [
		last_times.thread, last_times.apply, last_times.step_max, str(last_times.part_ms)])
	rebuilt.emit()


# ------------------------------------------------------------------ étages, plafonds, courant, lumière

## Étage (index de l'éditeur) d'une hauteur du monde.
func floor_of_y(y: float) -> int:
	var k := 0
	for i in _floor_sols.size():
		if float(_floor_sols[i]) <= y + 0.05:
			k = i
	return k


func floor_sol(k: int) -> float:
	return float(_floor_sols[clampi(k, 0, _floor_sols.size() - 1)])


## Range les nœuds visibles d'un morceau par étage (et repère les plafonds).
func _classify(part: String, holder: Node3D) -> void:
	for n in holder.find_children("*", "Node3D", true, false):
		var kind := ""
		var y := 0.0
		if part == "arch":
			if not (n is MeshInstance3D or n is StaticBody3D):
				continue
			var parts := String(n.name).split("__")
			if parts.size() < 3:
				continue
			kind = parts[2]
			if n is MeshInstance3D:
				var bb := (n as MeshInstance3D).get_aabb()
				# Sol et dalle : leur dessus ; plafond : l'étage du dessous ;
				# le reste (murs, escaliers...) : leur pied.
				match kind:
					"floor", "slab":
						y = bb.end.y - 0.05
					"ceil":
						y = bb.position.y - 0.5
					_:
						y = bb.position.y + 0.05
			else:
				continue
		else:
			# Unités : objets de jeu posés directement dans le morceau, enfants
			# des racines (décor, lampes, portes, fenêtres, machines...).
			var par := n.get_parent()
			var unit := false
			if par == holder:
				unit = n is Interactable or String(n.name) == "ExitPad"
			elif par.get_parent() == holder:
				unit = not par is Interactable and String(n.name) != "Blockers"
			if not unit:
				continue
			y = (n as Node3D).global_position.y
			if n is OmniLight3D:
				y -= 0.6
			y += 0.05
		_units[n] = [floor_of_y(y), kind]
		if part == "arch" and n is MeshInstance3D:
			var body := n.get_parent().get_node_or_null(NodePath(String(n.name) + "__col"))
			if body != null:
				_units[body] = [floor_of_y(y), kind]


func _forget_units(holder: Node) -> void:
	for n in _units.keys():
		if not is_instance_valid(n) or holder.is_ancestor_of(n):
			_units.erase(n)


func floor_shown(k: int) -> bool:
	match floors_mode:
		Floors.UP_TO:
			return k <= view_floor
		Floors.ONLY:
			return k == view_floor
	return true


func _apply_visibility() -> void:
	for n in _units:
		if not is_instance_valid(n):
			continue
		var u: Array = _units[n]
		var show: bool = floor_shown(int(u[0])) and not (hide_ceilings and String(u[1]) == "ceil")
		if String(n.name).begins_with("ClipView_"):
			show = show and show_clips
		if n is Node3D and not n is StaticBody3D:
			(n as Node3D).visible = show


## Nœud caché (plafond masqué, étage non montré) : les rayons le traversent.
func unit_hidden(n: Node) -> bool:
	var cur := n
	while cur != null and cur != root3d:
		if _units.has(cur):
			var u: Array = _units[cur]
			return not floor_shown(int(u[0])) or (hide_ceilings and String(u[1]) == "ceil")
		cur = cur.get_parent()
	return false


func set_options(o: Dictionary) -> void:
	power_on = bool(o.get("power", power_on))
	full_light = bool(o.get("full", full_light))
	hide_ceilings = bool(o.get("ceil", hide_ceilings))
	show_clips = bool(o.get("clips", show_clips))
	floors_mode = int(o.get("floors", floors_mode)) as Floors
	_apply_power()
	_apply_light()
	_apply_visibility()


func set_view_floor(k: int) -> void:
	if k == view_floor:
		return
	view_floor = k
	if floors_mode != Floors.ALL:
		_apply_visibility()


func _apply_power() -> void:
	for b: MapProps in builders.values():
		if b != null and b.power != null:
			b.power.apply_immediate(power_on)
	if _game != null:
		_game.set_power(power_on)


## Éclairage de jeu (environnement de la partie) ou plein (tout voir : lumière
## ambiante forte, sans brume).
func _apply_light() -> void:
	if env == null:
		return
	if full_light:
		env.ambient_light_color = Color(0.85, 0.85, 0.82)
		env.ambient_light_energy = 1.6
		env.fog_enabled = false
		env.volumetric_fog_enabled = false
		env.tonemap_exposure = 1.0
	else:
		env.ambient_light_color = _base_env.get("ambient_color", env.ambient_light_color)
		env.ambient_light_energy = float(_base_env.get("ambient_energy", env.ambient_light_energy))
		env.fog_enabled = bool(_base_env.get("fog", true))
		env.volumetric_fog_enabled = bool(RenderQuality.current().volumetric_fog)
		env.tonemap_exposure = float(_base_env.get("exposure", env.tonemap_exposure))
	var post := root3d.get_node_or_null("FilmPost") as CanvasLayer
	if post != null:
		post.visible = not full_light


# ------------------------------------------------------------------ caméra et carte

## Boîte englobante des pièces de la carte construite (repère du monde).
func map_bounds() -> AABB:
	var m := built_map if built_map != null else doc
	if m == null or m.pieces.is_empty():
		return AABB(Vector3(OFF, 0, OFF), Vector3(20, 3, 20))
	var bb := Rect2()
	var first := true
	var top := 0.0
	for p in m.pieces:
		var r := MapGeom.bbox(m.room_poly(p))
		bb = r if first else bb.merge(r)
		first = false
		top = maxf(top, m.floor_sol(int(p.get("etage", 0))) + m.floor_height(int(p.get("etage", 0))))
	return AABB(Vector3(bb.position.x + OFF, 0.0, bb.position.y + OFF), Vector3(bb.size.x, top, bb.size.y))


func frame_map() -> void:
	var bb := map_bounds()
	rig.focus(bb.get_center() * Vector3(1, 0, 1), maxf(bb.size.x, bb.size.z) * 0.5)


# ------------------------------------------------------------------ éléments (surlignage, sélection)

## Contour 2D (m, éditeur) et hauteurs [bas, haut] d'un élément de la carte.
func element_shape(e: Dictionary) -> Dictionary:
	var m := doc
	if e.is_empty() or m == null:
		return {}
	var k := int(e.get("etage", 0))
	var sol := m.floor_sol(k)
	var h := m.floor_height(k)
	var t := String(e.get("type", ""))
	var poly := PackedVector2Array()
	var y0 := sol + 0.02
	var y1 := sol + h
	if e.has("contour"):
		poly = m.room_poly(e)
		y1 = sol + float(e.get("plafond", h))
	elif t in MapRules.ouvertures_types():
		var p := MapGeom.v2(e.position)
		var dir := Vector2.RIGHT
		for r in m.rooms_on(k):
			var rp := m.room_poly(r)
			for i in rp.size():
				var a := rp[i]
				var b := rp[(i + 1) % rp.size()]
				if MapGeom.dist_to_segment(p, a, b) < 0.05:
					dir = (b - a).normalized()
		var n := Vector2(-dir.y, dir.x)
		var w := MapRules.opening_width(e) * 0.5
		poly = PackedVector2Array([p - dir * w - n * 0.35, p + dir * w - n * 0.35, p + dir * w + n * 0.35, p - dir * w + n * 0.35])
		if t == "fenetre" and MapCatalog.barricade_kind(e) != "fenetre":
			y1 = sol + MapValidator.ZOMBIE_DOOR_TOP
		elif t == "fenetre":
			y0 = sol + MapValidator.SILL
			y1 = sol + MapValidator.LINTEL
		else:
			y1 = sol + float(m.carte.get("hauteur_portes", 2.5))
	else:
		if t == "effet":
			# Format 11 : la zone réelle de l'effet (tournée).
			poly = MapRules.effect_poly(e)
		elif MapGeom.item_oblique(e) and MapCatalog.tool_of(e) == "wall_item":
			poly = MapRules.wall_item_poly(e)
		else:
			poly = MapGeom.rect_poly(MapRules.footprint_rect(e))
		match MapCatalog.tool_of(e):
			"wall_item":
				y1 = sol + 2.3
			"floor_item":
				y1 = sol + 1.4
		if t == "luminaire":
			match MapCatalog.light_mount(e):
				"plafond":
					# Format 12 : à sa descente sous le plafond.
					var dz := MapVertical.descente(e)
					y0 = sol + h - dz - 0.4
					y1 = sol + h
				"mur":
					# À la hauteur de l'applique (docs/EDITOR_VIEWS.md § 1.2 : corrigé).
					var wy := MapCatalog.wall_light_height(e)
					y0 = sol + wy - 0.4
					y1 = sol + wy + 0.4
				_:
					var b := MapVertical.floor_light_base(m, e)
					y0 = sol + b + 0.02
					y1 = sol + b + 1.4
		elif t == "effet":
			# Effet (format 10) : autour de sa hauteur (plafond, mur, surélevé) ;
			# format 11 : hauteur de sa zone (volume, effet mural).
			var z := MapCatalog.effect_zone(e)
			match MapCatalog.effect_mount(e):
				"plafond":
					var dz := MapVertical.descente(e)
					y0 = sol + h - dz - 0.8
					y1 = sol + h - dz
				"mur":
					y0 = sol + MapCatalog.effect_height(e) - z.z * 0.5 - 0.2
					y1 = sol + MapCatalog.effect_height(e) + z.z * 0.5 + 0.4
				_:
					y0 = sol + MapCatalog.effect_height(e) + 0.02
					y1 = y0 + maxf(1.2, z.z + 0.3)
		elif t == "prefab" and MapCatalog.light_mount(e) == "mur":
			# Format 11 : décor mural (torche, tuyau, boîtier) à sa hauteur.
			y0 = sol + MapCatalog.wall_light_height(e) - 0.3
			y1 = sol + MapCatalog.wall_light_height(e) + 0.4
		elif t == "prefab" and MapCatalog.light_mount(e) == "plafond":
			y0 = sol + h - MapVertical.descente(e) - 0.8
			y1 = sol + h - MapVertical.descente(e)
		elif t == "prefab":
			# Format 12 : posé sur un autre décor.
			var dz := MapVertical.decor_z(e)
			y0 = sol + dz + 0.02
			y1 = sol + dz + maxf(float(MapCatalog.def_of(e).get("h", 1.4)), 0.2)
		elif t == "escalier":
			y1 = m.floor_sol(k + 1) if k + 1 < m.floor_count() else sol + h
		elif t == "piege":
			y1 = sol + 0.25
	return {"poly": poly, "y0": y0, "y1": y1, "floor": k}


## Centre (monde) et rayon d'un élément, pour y centrer la caméra.
func element_focus(e: Dictionary) -> Array:
	var s := element_shape(e)
	if s.is_empty():
		return []
	var bb := MapGeom.bbox(s.poly)
	var c := bb.get_center()
	return [Vector3(c.x + OFF, float(s.y0), c.y + OFF), maxf(maxf(bb.size.x, bb.size.y) * 0.5, 1.5)]


## Surlignage de l'élément choisi (jaune) et survolé (bleu) : prisme en
## traits et faces transparentes, vu à travers les murs.
func update_overlay() -> void:
	var key := "%s|%s|%d|%d" % [selected_id, hover_id, _built_hash, int(floors_mode) * 100 + view_floor]
	if key == _overlay_key or _overlay == null:
		return
	_overlay_key = key
	var im := _overlay.mesh as ImmediateMesh
	im.clear_surfaces()
	var shapes := []
	if doc != null:
		if selected_id != "":
			shapes.append([element_shape(doc.find(selected_id)), COL_SEL])
		if hover_id != "" and hover_id != selected_id:
			shapes.append([element_shape(doc.find(hover_id)), COL_HOVER])
	shapes = shapes.filter(func(s): return not s[0].is_empty() and (s[0].poly as PackedVector2Array).size() >= 3)
	if shapes.is_empty():
		return
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for s in shapes:
		var sh: Dictionary = s[0]
		var col: Color = s[1]
		im.surface_set_color(col)
		var p: PackedVector2Array = sh.poly
		for i in p.size():
			var a := p[i]
			var b := p[(i + 1) % p.size()]
			for y in [float(sh.y0), float(sh.y1)]:
				im.surface_add_vertex(Vector3(a.x + OFF, y, a.y + OFF))
				im.surface_add_vertex(Vector3(b.x + OFF, y, b.y + OFF))
			im.surface_add_vertex(Vector3(a.x + OFF, float(sh.y0), a.y + OFF))
			im.surface_add_vertex(Vector3(a.x + OFF, float(sh.y1), a.y + OFF))
	im.surface_end()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for s in shapes:
		var sh: Dictionary = s[0]
		var col: Color = s[1]
		im.surface_set_color(Color(col, 0.16))
		var p: PackedVector2Array = sh.poly
		for i in p.size():
			var a := p[i]
			var b := p[(i + 1) % p.size()]
			var q := [Vector3(a.x + OFF, sh.y0, a.y + OFF), Vector3(b.x + OFF, sh.y0, b.y + OFF),
				Vector3(b.x + OFF, sh.y1, b.y + OFF), Vector3(a.x + OFF, sh.y1, a.y + OFF)]
			for j in [0, 1, 2, 0, 2, 3]:
				im.surface_add_vertex(q[j])
		# Sol de l'élément.
		var idx := Geometry2D.triangulate_polygon(p)
		for j in idx:
			im.surface_add_vertex(Vector3(p[j].x + OFF, float(sh.y0), p[j].y + OFF))
	im.surface_end()


## Élément de la carte sous le pixel `px` du rendu (rayon sur les collisions
## visibles), "" s'il n'y a rien.
func pick(px: Vector2) -> String:
	var hit := ray(px)
	if hit.is_empty() or doc == null:
		return ""
	var p: Vector3 = hit.position
	var k := floor_of_y(p.y + 0.3)
	return element_at(Vector2(p.x - OFF, p.z - OFF), k)


## Premier point visible touché par le rayon du pixel `px` ({} : rien).
func ray(px: Vector2) -> Dictionary:
	var cam := rig.cam
	var from := cam.project_ray_origin(px)
	var dir := cam.project_ray_normal(px)
	var space := root3d.get_world_3d().direct_space_state
	var exclude: Array[RID] = []
	for i in 16:
		var q := PhysicsRayQueryParameters3D.create(from, from + dir * 400.0, 0xFFFFFFFF, exclude)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return {}
		if hit.collider is Node and unit_hidden(hit.collider):
			exclude.append(hit.rid)
			continue
		hit.position += dir * 0.05
		return hit
	return {}


## Sol sous le point `p` (plafonds et nœuds cachés traversés), null s'il n'y
## en a pas : où poser la vue joueur.
func ground_below(p: Vector3) -> Variant:
	var space := root3d.get_world_3d().direct_space_state
	var exclude: Array[RID] = []
	for i in 16:
		var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.3, p + Vector3.DOWN * 80.0, 1, exclude)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return null
		var n: Node = hit.collider
		if String(n.name).contains("__ceil") or unit_hidden(n) or rig.door_bodies.has(n):
			exclude.append(hit.rid)
			continue
		return hit.position
	return null


## Élément de l'étage `k` au point `m` (comme MapEditor.element_at :
## ouvertures, puis le plus petit objet, puis la pièce).
func element_at(m: Vector2, k: int) -> String:
	for o in doc.openings_on(k):
		if MapRules.hit(doc, o, m):
			return String(o.id)
	var best := ""
	var best_area := INF
	for o in doc.objects_on(k):
		if MapRules.hit(doc, o, m):
			var a := MapRules.footprint_rect(o).get_area()
			if a < best_area:
				best_area = a
				best = String(o.id)
	if best != "":
		return best
	for p in doc.rooms_on(k):
		if MapRules.hit(doc, p, m):
			return String(p.id)
	return ""


## Nombre de nœuds de chaque sorte dans l'aperçu (tests).
func census() -> Dictionary:
	var out := {}
	for p in PARTS:
		if groups.has(p):
			for n in (groups[p] as Node).find_children("*", "", true, false):
				var c := n.get_class()
				if n is CollisionBox:
					c = "CollisionBox"
				out[c] = int(out.get(c, 0)) + 1
	return out
