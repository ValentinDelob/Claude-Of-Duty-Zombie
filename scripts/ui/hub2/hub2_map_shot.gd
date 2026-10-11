class_name Hub2MapShot
extends Node
## Aperçu en jeu d'une carte PERSONNALISÉE pour l'écran JOUER du hub v2 (les
## cartes du jeu ont leur vue pré-rendue : tools/map_shots.sh). La première
## fois qu'une carte perso est choisie, elle est construite hors écran dans
## un SubViewport (monde 3D à part : la carte, son éclairage et son
## étalonnage, ses portes), vue des yeux du joueur au départ tournée vers la
## porte la plus proche, comme map_shots ; l'image (1280 × 720) est gardée
## dans user://map_previews/<empreinte>.png, l'empreinte étant celle des
## fichiers de la carte (une carte modifiée a un nouvel aperçu). Les
## fichiers de la carte ne sont que LUS. Sans rendu (--headless) : rien,
## l'écran garde le plan (MapPreview).
##
## Une demande à la fois ; la dernière demandée passe ensuite. Signal
## `ready_shot(map_id, texture)` quand une image est prête (ou relue du
## cache).

signal ready_shot(map_id: String, texture: Texture2D)

const SIZE := Vector2i(1280, 720)
## Images gardées au plus (les plus anciennes effacées).
const MAX_FILES := 40

var _busy := false
var _queued := ""
var _mem: Dictionary = {}  # chemin -> Texture2D


## Dossier du cache (autotests : un dossier de tests/_out, jamais user://).
static func cache_dir() -> String:
	if AutotestMode.is_running():
		return ProjectSettings.globalize_path("res://tests/_out/map_previews_%s" % AutotestMode.scenario_name())
	return "user://map_previews"


## Empreinte des fichiers d'une carte perso ("" : carte inconnue).
static func key_of(map_id: String) -> String:
	if map_id.begins_with(EditorMapDef.SHARED_PREFIX):
		return map_id.trim_prefix(EditorMapDef.SHARED_PREFIX).validate_filename()
	if not map_id.begins_with(EditorMapDef.CUSTOM_PREFIX):
		return ""
	var dir := EditorMap.map_dir(map_id.trim_prefix(EditorMapDef.CUSTOM_PREFIX))
	if dir == "" or not DirAccess.dir_exists_absolute(dir):
		return ""
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	var files := Array(DirAccess.get_files_at(dir))
	files.sort()
	for f in files:
		ctx.update(String(f).to_utf8_buffer())
		ctx.update(FileAccess.get_file_as_bytes(dir.path_join(f)))
	return ctx.finish().hex_encode().left(32)


static func cache_path(map_id: String) -> String:
	var k := key_of(map_id)
	return "" if k == "" else cache_dir().path_join(k + ".png")


## Le rendu est-il possible (fenêtre réelle, pas --headless) ?
static func can_render() -> bool:
	return DisplayServer.get_name() != "headless"


## Image déjà faite pour `map_id` (null : pas encore).
func cached(map_id: String) -> Texture2D:
	var p := cache_path(map_id)
	if p == "":
		return null
	if _mem.has(p):
		return _mem[p]
	if not FileAccess.file_exists(p):
		return null
	var img := Image.load_from_file(ProjectSettings.globalize_path(p) if p.begins_with("user://") else p)
	if img == null or img.is_empty():
		return null
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_mem[p] = tex
	return tex


## Demande l'aperçu de `map_id` : relu du cache, sinon rendu (signal
## ready_shot). Faux si impossible (pas de rendu, carte illisible).
func request(map_id: String) -> bool:
	var t := cached(map_id)
	if t:
		ready_shot.emit.call_deferred(map_id, t)
		return true
	if not can_render() or cache_path(map_id) == "":
		return false
	if _busy:
		_queued = map_id
		return true
	_render(map_id)
	return true


func _render(map_id: String) -> void:
	_busy = true
	var def := Game.make_map_def(map_id)
	var layout := def.create_layout() if def else null
	if layout == null:
		_done()
		return
	var vp := SubViewport.new()
	vp.size = SIZE
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_2X
	add_child(vp)
	var world := Node3D.new()
	world.name = "World"
	vp.add_child(world)
	layout.build(world)
	WorldLook.setup_environment(world, def.look)
	for m in layout.doors():
		var d := Door.new()
		d.setup_marker(m)
		world.add_child(d)
	var cam := Camera3D.new()
	cam.fov = 75.0
	world.add_child(cam)
	var spawns := layout.player_spawns()
	var eye := (spawns[0] if not spawns.is_empty() else layout.warm_point()) + Vector3.UP * Player.EYE_HEIGHT
	var target := eye + Vector3(0, -0.15, -4)
	var best := INF
	for m in layout.doors():
		var dd := eye.distance_to(m.pos)
		if dd < best and dd > 0.8:
			best = dd
			target = Vector3(m.pos.x, eye.y - 0.15, m.pos.z)
	cam.look_at_from_position(eye, target)
	cam.current = true
	# Cadrage : depuis le départ, regarder dans la direction la plus dégagée
	# (porte la plus proche si elle est assez loin), un peu en recul : la
	# pièce entière plutôt qu'un mur à un mètre.
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not is_inside_tree():
		return
	var space := world.get_world_3d().direct_space_state
	var best_dir := Vector3.ZERO
	var best_len := 0.0
	for k in 16:
		var dir := Vector3(sin(TAU * k / 16.0), 0, cos(TAU * k / 16.0))
		var l := _free(space, eye, dir, 40.0)
		if l > best_len:
			best_len = l
			best_dir = dir
	if best_dir != Vector3.ZERO and (best == INF or eye.distance_to(target) < 3.0 or best_len > eye.distance_to(target) * 2.0):
		target = eye + best_dir * minf(best_len, 12.0) + Vector3.DOWN * 0.6
	var fwd := (target - eye) * Vector3(1, 0, 1)
	if fwd.length() > 0.01:
		var back := _free(space, eye, -fwd.normalized(), 4.0)
		eye -= fwd.normalized() * clampf(back - 0.4, 0.0, 2.5)
	cam.look_at_from_position(eye, target)
	# Lumière d'appoint douce derrière la caméra (une carte sans lampe serait
	# noire) : l'aperçu montre la pièce, pas l'obscurité.
	var fill := OmniLight3D.new()
	fill.light_energy = 1.2
	fill.omni_range = 16.0
	fill.omni_attenuation = 1.2
	fill.shadow_enabled = false
	fill.light_color = Color(1.0, 0.93, 0.82)
	world.add_child(fill)
	fill.global_position = eye + Vector3.UP * 0.3
	cam.current = true
	# Quelques images : lumières, brume et étalonnage posés.
	for i in 6:
		await RenderingServer.frame_post_draw
	if not is_inside_tree():
		return
	var img := vp.get_texture().get_image()
	vp.queue_free()
	var p := cache_path(map_id)
	if img and not img.is_empty() and p != "":
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(cache_dir()))
		img.save_png(ProjectSettings.globalize_path(p))
		_prune()
		img.generate_mipmaps()
		var tex := ImageTexture.create_from_image(img)
		_mem[p] = tex
		ready_shot.emit(map_id, tex)
	_done()


func _done() -> void:
	_busy = false
	if _queued != "":
		var next := _queued
		_queued = ""
		request(next)


## Distance libre depuis `from` dans la direction `dir` (au plus `max_len`).
static func _free(space: PhysicsDirectSpaceState3D, from: Vector3, dir: Vector3, max_len: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * max_len)
	var hit := space.intersect_ray(q)
	return max_len if hit.is_empty() else from.distance_to(hit.position)


## Garde les MAX_FILES images les plus récentes.
func _prune() -> void:
	var dir := ProjectSettings.globalize_path(cache_dir())
	var files := []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".png"):
			files.append([FileAccess.get_modified_time(dir.path_join(f)), f])
	if files.size() <= MAX_FILES:
		return
	files.sort()
	for i in files.size() - MAX_FILES:
		DirAccess.remove_absolute(dir.path_join(String(files[i][1])))
