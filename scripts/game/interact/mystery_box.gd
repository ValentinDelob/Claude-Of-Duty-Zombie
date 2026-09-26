class_name MysteryBox
extends Interactable
## Boîte mystère. Le serveur tire l'arme (ou le crâne) dès l'achat ; les
## clients jouent l'animation de défilement puis affichent le résultat.
##
## États : IDLE (achetable) -> ROLLING -> READY (seul l'acheteur peut prendre
## l'arme) -> IDLE. Le crâne remplace parfois l'arme : points remboursés, la
## boîte s'envole et réapparaît ailleurs.

enum State { IDLE, ROLLING, READY, MOVING }

const COST := 950
const ROLL_TIME := 4.2
const READY_TIME := 9.0
const MOVE_TIME := 9.0
## Nombre d'utilisations avant que le crâne puisse apparaître.
const MIN_USES_BEFORE_SKULL := 4
const SKULL_CHANCE := 0.15
## Liste et poids des armes : WeaponDB.box_pool() (CLAUDE-RAY plus rare).

var state: State = State.IDLE
var location := 0
var weapon := ""
var owner_pid := 0
var skull := false
var uses := 0
## Bonus LIQUIDATION en cours (toutes les machines) : la boîte coûte 10.
var fire_sale := false
## Serveur : nombre de déménagements (la liquidation n'apparaît qu'après le premier).
var moves := 0
## Serveur : prix payé par l'acheteur courant (remboursé par le crâne).
var _paid := COST
## Tests : force le prochain tirage.
var force_result := ""
## LIQUIDATION (BO1) : pendant le bonus, une boîte temporaire apparaît à chaque
## autre emplacement de la carte, toutes à 10 points ; à la fin, elles
## disparaissent (celle qu'on utilise finit d'abord son tirage). Créées et
## retirées sur toutes les machines (set_fire_sale, appelé par PowerupSystem).
var temporary := false
## Vraie boîte : boîtes temporaires en place. Temporaire : sa vraie boîte.
var fire_sale_boxes: Array = []
var _source: MysteryBox
var _expiring := false
var _fs_music: AudioStreamPlayer3D

var spots: Array = []   # [{pos, basis}]
var _root: Node3D
var _lid: Node3D
var _beam: MeshInstance3D
var _light: OmniLight3D
var _display: Node3D
var _display_model: Node3D
var _timer := 0.0
var _cycle_t := 0.0
var _rng := RandomNumberGenerator.new()
var _markers: Array[Node3D] = []


func setup(cells: Array, start: int, data: MapData) -> void:
	interact_id = "box"
	name = "MysteryBox"
	interact_range = 2.0
	for c in cells:
		var n := MapDef.wall_normal(data, c)
		var pos := MapData.cell_to_world(c) + n * 0.05
		spots.append({"pos": pos, "normal": n})
	location = clampi(start, 0, spots.size() - 1)
	_rng.randomize()


func _ready() -> void:
	_root = Node3D.new()
	add_child(_root)
	var crate := WorldLook.surface("crate")
	_part(_root, Vector3(1.8, 0.75, 0.85), Vector3(0, 0.375, 0), crate)
	for x in [-0.86, 0.86]:
		_part(_root, Vector3(0.08, 0.8, 0.9), Vector3(x, 0.4, 0), WorldLook.surface("steel"))
	_lid = Node3D.new()
	_lid.position = Vector3(0, 0.75, -0.42)
	_root.add_child(_lid)
	_part(_lid, Vector3(1.82, 0.1, 0.88), Vector3(0, 0.05, 0.42), crate)
	for side in [-1.0, 1.0]:
		var q := Label3D.new()
		q.text = "?"
		q.font = UiStyle.font("title")
		q.font_size = 160
		q.pixel_size = 0.003
		q.modulate = Color(1.0, 0.6, 0.25)
		q.position = Vector3(side * 0.45, 0.4, 0.43)
		q.shaded = false
		_root.add_child(q)
	# Faisceau lumineux qui signale la boîte de loin.
	_beam = MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.5
	bm.bottom_radius = 0.35
	bm.height = 2.4
	bm.radial_segments = 12
	_beam.mesh = bm
	var beam_mat := StandardMaterial3D.new()
	beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	beam_mat.albedo_color = Color(1.0, 0.5, 0.2, 0.08)
	beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_beam.material_override = beam_mat
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.position = Vector3(0, 1.95, 0)
	_root.add_child(_beam)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.55, 0.25)
	_light.omni_range = 4.0
	_light.light_energy = 1.0
	_light.position = Vector3(0, 1.3, 0.3)
	_root.add_child(_light)
	_display = Node3D.new()
	_display.position = Vector3(0, 1.05, 0)
	_root.add_child(_display)
	_root.add_child(_collider(Vector3(1.8, 0.85, 0.85)))
	if temporary:
		_place(self, location)
		# Arrivée : la boîte se déploie, avec la ritournelle de la liquidation.
		_root.scale = Vector3.ONE * 0.05
		create_tween().tween_property(_root, "scale", Vector3.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		Audio.play_3d("powerup_spawn", global_position + Vector3.UP, -4.0, 0.05)
		var stream := Audio.get_stream("fire_sale_loop")
		if stream:
			_fs_music = AudioStreamPlayer3D.new()
			_fs_music.bus = "Music"
			_fs_music.stream = stream
			_fs_music.unit_size = 6.0
			_fs_music.max_distance = 40.0
			_fs_music.volume_db = -4.0
			_fs_music.position = Vector3.UP * 1.2
			add_child(_fs_music)
			_fs_music.play()
		return
	# Emplacements vides : un simple tas de planches.
	for i in spots.size():
		var m := Node3D.new()
		_part(m, Vector3(1.5, 0.12, 0.7), Vector3(0, 0.06, 0), crate)
		_part(m, Vector3(0.9, 0.1, 0.5), Vector3(0.2, 0.17, 0.05), crate)
		m.add_child(_collider(Vector3(1.5, 0.3, 0.7)))
		get_parent().add_child.call_deferred(m)
		_markers.append(m)
		_place(m, i)
	_move_to(location)


func _part(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)


func _collider(size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.position.y = size.y * 0.5
	body.add_child(cs)
	return body


## Serveur, avant le début de la partie : emplacement de départ tiré au sort
## parmi `choices` (index des X), comme à Kino der Toten.
func srv_random_start(choices: Array) -> void:
	var valid := choices.filter(func(i): return i >= 0 and i < spots.size())
	if valid.is_empty():
		return
	_move_to(valid[_rng.randi() % valid.size()])
	print("[Box] départ : emplacement %d" % location)
	broadcast_state()


## Toutes les machines (vraie boîte) : début ou fin de la LIQUIDATION.
func set_fire_sale(on: bool) -> void:
	fire_sale = on
	if not on:
		for b: MysteryBox in fire_sale_boxes.duplicate():
			b.expire()
		return
	for i in spots.size():
		if i == location:
			continue
		var existing: MysteryBox = null
		for b: MysteryBox in fire_sale_boxes:
			if b.location == i:
				existing = b
		if existing:
			# Nouvelle liquidation avant la fin du tirage : la boîte reste.
			existing._expiring = false
			existing.fire_sale = true
			continue
		var fs := MysteryBox.new()
		fs.setup_temporary(self, i)
		system.register(fs)
		get_parent().add_child(fs)
		fire_sale_boxes.append(fs)
		if i < _markers.size():
			_markers[i].visible = false
	print("[Box] liquidation : %d boîtes temporaires" % fire_sale_boxes.size())


## Boîte temporaire de liquidation à l'emplacement `i` de `src`.
func setup_temporary(src: MysteryBox, i: int) -> void:
	temporary = true
	_source = src
	spots = src.spots
	location = i
	fire_sale = true
	interact_id = "box_fs_%d" % i
	name = "FireSaleBox%d" % i
	interact_range = src.interact_range
	_rng.randomize()


## Fin de la liquidation : retirée tout de suite si libre, sinon à la fin du
## tirage en cours (apply_state IDLE).
func expire() -> void:
	_expiring = true
	fire_sale = false
	if state == State.IDLE:
		_remove()


func _remove() -> void:
	if _source and is_instance_valid(_source):
		_source.fire_sale_boxes.erase(self)
		if location < _source._markers.size():
			_source._markers[location].visible = location != _source.location
	if system:
		system.unregister(self)
	Audio.play_3d("box_fly", global_position + Vector3.UP, -8.0, 0.05)
	queue_free()


## Prix courant (bonus LIQUIDATION : 10 points).
func cost() -> int:
	return PowerupRules.FIRE_SALE_COST if fire_sale else COST


## Cellules occupées par un emplacement (la boîte fait 2 cases de long).
static func spot_cells(c: Vector2i, data: MapData) -> Array:
	var n := MapDef.wall_normal(data, c)
	var along := Vector2i(1, 0) if absf(n.z) > 0.5 else Vector2i(0, 1)
	return [c - along, c, c + along]


func _place(node: Node3D, i: int) -> void:
	var s: Dictionary = spots[i]
	node.position = s.pos
	node.basis = Basis.looking_at(-s.normal, Vector3.UP).rotated(Vector3.UP, PI)


func _move_to(i: int) -> void:
	location = i
	_place(self, i)
	for k in _markers.size():
		_markers[k].visible = k != i


# --------------------------------------------------------------------------
# Interaction
# --------------------------------------------------------------------------

func interact_point() -> Vector3:
	return global_position - (spots[location].normal as Vector3) * 0.7 + Vector3.UP * 0.9


func prompt(pid: int) -> String:
	match state:
		State.IDLE:
			return "[F] Boîte mystère %s" % Interactable.cost_text(cost())
		State.READY:
			if pid == owner_pid and not skull:
				return "[F] Prendre %s" % (ThrowableRules.MONKEY_NAME if weapon == ThrowableRules.MONKEY_ID else WeaponDB.display_name(weapon))
	return ""


func srv_use(pid: int) -> void:
	var game := system.game
	var pd := game.session.get_data(pid)
	if pd == null or pd.life != PlayerData.Life.ALIVE:
		return
	match state:
		State.IDLE:
			var price := cost()
			if not game.session.try_spend(pid, price):
				system.deny(pid, "Pas assez de points")
				return
			_paid = price
			owner_pid = pid
			uses += 1
			_roll(pd)
			state = State.ROLLING
			_timer = ROLL_TIME
			broadcast_state()
		State.READY:
			if pid != owner_pid or skull:
				return
			if weapon == ThrowableRules.MONKEY_ID:
				# SINGE-TAMBOUR : arme tactique (touche dédiée), pas un emplacement.
				game.throwables.srv_give_monkeys(pid)
			else:
				WeaponDB.give(pd, weapon)
				game.combat.cancel_reload(pid)
				game.session.sync_inventory(pid)
			_close()


## Serveur : tirage de l'arme (jamais une arme déjà possédée).
func _roll(pd: PlayerData) -> void:
	skull = false
	# Pas de crâne pendant une liquidation (la boîte ne déménage pas).
	if force_result == "skull" or (force_result == "" and not fire_sale and not temporary and uses > MIN_USES_BEFORE_SKULL and _rng.randf() < SKULL_CHANCE):
		skull = true
		weapon = ""
		force_result = ""
		return
	if force_result != "":
		weapon = force_result
		force_result = ""
		return
	weapon = pick_weapon(pd, _rng, wonders_taken(system.game))


## Serveur : armes merveilles uniques (WeaponDB.is_unique) déjà présentes dans
## la partie : en main d'un joueur ou en cours d'amélioration au Pack-a-Punch.
static func wonders_taken(game: Game) -> Dictionary:
	var out := {}
	if game == null:
		return out
	for pid in game.session.data:
		for w in game.session.data[pid].weapons:
			if WeaponDB.is_unique(w.id):
				out[w.id] = true
	for obj in game.interact.objects.values():
		if obj is PackAPunch and WeaponDB.is_unique(obj.weapon_id):
			out[obj.weapon_id] = true
	return out


## Tirage pondéré dans la liste de la boîte (WeaponDB.box_pool), sans jamais
## proposer une arme que le joueur possède déjà (comme BO1), ni une arme
## merveille unique déjà présente dans la partie (`taken`).
static func pick_weapon(pd: PlayerData, rng: RandomNumberGenerator, taken := {}) -> String:
	var pool := []
	var weights := []
	var box := WeaponDB.box_pool()
	for id in box:
		if pd != null and pd.has_weapon(id) >= 0:
			continue
		if taken.has(id):
			continue
		pool.append(id)
		weights.append(box[id])
	# SINGE-TAMBOUR (jamais si le joueur en a déjà).
	if pd == null or not pd.has_monkeys:
		pool.append(ThrowableRules.MONKEY_ID)
		weights.append(ThrowableRules.MONKEY_BOX_WEIGHT)
	if pool.is_empty():
		return ""
	var total := 0.0
	for w in weights:
		total += w
	var r := rng.randf() * total
	for i in pool.size():
		r -= weights[i]
		if r <= 0.0:
			return pool[i]
	return pool[pool.size() - 1]


func _close() -> void:
	state = State.IDLE
	owner_pid = 0
	weapon = ""
	broadcast_state()


func _process(delta: float) -> void:
	_animate(delta)
	if not multiplayer.is_server() or state == State.IDLE:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	match state:
		State.ROLLING:
			if skull:
				# Remboursement et départ de la boîte.
				system.game.session.add_points(owner_pid, _paid)
				state = State.MOVING
				_timer = MOVE_TIME
				uses = 0
			else:
				state = State.READY
				_timer = READY_TIME
			broadcast_state()
		State.READY:
			_close()
		State.MOVING:
			var next := location
			if spots.size() > 1:
				while next == location:
					next = _rng.randi() % spots.size()
			location = next
			moves += 1
			_close()


# --------------------------------------------------------------------------
# Réplication et visuels (toutes les machines)
# --------------------------------------------------------------------------

func get_state() -> Dictionary:
	return {"state": state, "location": location, "weapon": weapon, "owner": owner_pid, "skull": skull}


func apply_state(s: Dictionary, animate: bool) -> void:
	var prev := state
	state = s.get("state", State.IDLE)
	weapon = s.get("weapon", "")
	owner_pid = s.get("owner", 0)
	skull = s.get("skull", false)
	var loc: int = s.get("location", location)
	match state:
		State.ROLLING:
			_cycle_t = 0.0
			_timer = ROLL_TIME
			if animate:
				Audio.play_3d("box_open", global_position + Vector3.UP, 0.0, 0.03)
				Audio.play_3d("box_music", global_position + Vector3.UP, -2.0, 0.0)
		State.READY:
			_show_model(weapon)
		State.MOVING:
			_show_model("")
			_show_skull()
			if animate:
				Audio.play_3d("box_skull", global_position + Vector3.UP * 1.5, 2.0, 0.0)
				var tw := create_tween()
				tw.tween_interval(1.6)
				tw.tween_property(_root, "position:y", 6.0, 1.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
				tw.tween_callback(func(): _root.visible = false)
				tw.tween_callback(func(): Audio.play_3d("box_fly", global_position + Vector3.UP * 2.0, 0.0, 0.0))
		State.IDLE:
			_show_model("")
			if prev == State.MOVING or loc != location:
				_root.position.y = 0.0
				_root.visible = true
				_move_to(loc)
			if prev != State.IDLE and animate:
				Audio.play_3d("box_open", global_position + Vector3.UP, -6.0, 0.1)
			if _expiring:
				_remove()
				return
	if loc != location and state != State.MOVING:
		_move_to(loc)


func _animate(delta: float) -> void:
	if _lid == null:
		return
	var open := state == State.ROLLING or state == State.READY
	_lid.rotation.x = lerp_angle(_lid.rotation.x, -1.9 if open else 0.0, 1.0 - exp(-delta * 6.0))
	_light.light_energy = lerpf(_light.light_energy, 2.6 if open else 0.8, 1.0 - exp(-delta * 4.0))
	_beam.visible = state != State.MOVING
	if state == State.ROLLING:
		# Défilement des armes : de plus en plus lent, monte hors de la boîte.
		_cycle_t -= delta
		_timer -= delta if not multiplayer.is_server() else 0.0
		var progress := 1.0 - clampf(_timer / ROLL_TIME, 0.0, 1.0)
		_display.position.y = 0.4 + progress * 0.75
		if _cycle_t <= 0.0:
			_cycle_t = lerpf(0.07, 0.35, progress * progress)
			var ids := WeaponDB.box_pool().keys() + [ThrowableRules.MONKEY_ID]
			_show_model(ids[randi() % ids.size()])
	if _display_model:
		_display.rotation.y += delta * (1.5 if state == State.READY else 0.0)


func _show_model(id: String) -> void:
	if _display_model:
		_display_model.queue_free()
		_display_model = null
	if id == ThrowableRules.MONKEY_ID:
		_display_model = Throwable.build_model(ThrowableRules.Kind.MONKEY, false)
		_display_model.scale = Vector3.ONE * 2.6
		_display_model.position.y = -0.25
		_display.add_child(_display_model)
		return
	if id == "" or not WeaponDB.exists(id):
		return
	_display_model = WeaponModels.build(WeaponDB.stats(id).model, false)
	_display_model.rotation.y = PI * 0.5
	_display_model.scale = Vector3.ONE * 1.6
	# Centré au-dessus de la boîte (de la bouche du canon à la crosse).
	_display_model.position.x = -WeaponModels.center_z(WeaponDB.stats(id).model) * 1.6
	_display.add_child(_display_model)


func _show_skull() -> void:
	# Crâne de fortune : boîtes blanchâtres et orbites rouges.
	_display_model = Node3D.new()
	var bone := StandardMaterial3D.new()
	bone.albedo_color = Color(0.8, 0.76, 0.65)
	var eye := PropBuilder._emissive(Color(1.0, 0.1, 0.05), 5.0)
	_part(_display_model, Vector3(0.36, 0.32, 0.36), Vector3(0, 0.1, 0), bone)
	_part(_display_model, Vector3(0.26, 0.12, 0.26), Vector3(0, -0.12, 0.04), bone)
	for x in [-0.08, 0.08]:
		_part(_display_model, Vector3(0.08, 0.08, 0.02), Vector3(x, 0.12, 0.185), eye)
	_display.position.y = 1.0
	_display.add_child(_display_model)
