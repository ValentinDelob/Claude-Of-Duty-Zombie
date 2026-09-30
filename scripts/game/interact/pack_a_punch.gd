class_name PackAPunch
extends Interactable
## Autel d'amélioration des armes (salle du rituel, courant requis).
##
## Le joueur dépose l'arme qu'il tient (5000) ; l'autel la « forge » quelques
## secondes puis la rend améliorée (dégâts, chargeur, nom, camouflage animé).
## Non récupérée à temps, elle est perdue. Une arme déjà améliorée peut être
## rechargée pour 2500.

enum State { IDLE, WORKING, READY }

const COST := 5000
const REFILL_COST := 2500
const WORK_TIME := 4.0
const READY_TIME := 10.0

var state: State = State.IDLE
var owner_pid := 0
var weapon_id := ""
var _normal := Vector3.FORWARD
var _timer := 0.0
var _ring: Node3D
var _core_mat: StandardMaterial3D
var _light: OmniLight3D
var _display: Node3D
var _display_model: Node3D
var _t := 0.0
## Modèle de style BO1 (tools/blender/props/kino_theater.py) ; à défaut, blocs.
const MODEL := "res://assets/models/kino/pap_machine.glb"


func setup(cell: Vector2i, data: MapData) -> void:
	setup_marker(GridMapLayout.cell_marker("pap", cell, data))


func setup_marker(m: MapMarker) -> void:
	interact_id = "pap"
	name = "PackAPunch"
	_normal = m.wall
	position = m.pos + _normal * 0.1
	interact_range = 2.1


func _ready() -> void:
	look_at(global_position - _normal, Vector3.UP)
	rotate_object_local(Vector3.UP, PI)
	if ResourceLoader.exists(MODEL):
		_build_model()
		return
	var stone := WorldLook.surface("stone")
	var steel := WorldLook.surface("steel")
	_box(Vector3(1.6, 0.9, 0.9), Vector3(0, 0.45, 0), stone)
	_box(Vector3(1.4, 0.12, 0.8), Vector3(0, 0.96, 0), steel)
	for x in [-0.62, 0.62]:
		_box(Vector3(0.14, 1.9, 0.14), Vector3(x, 1.9, -0.2), steel)
	_box(Vector3(1.4, 0.14, 0.2), Vector3(0, 2.85, -0.2), steel)
	# Cœur incandescent.
	_core_mat = StandardMaterial3D.new()
	_core_mat.albedo_color = Color(0.4, 0.02, 0.02)
	_core_mat.emission_enabled = true
	_core_mat.emission = Color(1.0, 0.08, 0.04)
	_core_mat.emission_energy_multiplier = 0.2
	var core := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.2
	sm.height = 0.4
	sm.radial_segments = 10
	sm.rings = 6
	core.mesh = sm
	core.material_override = _core_mat
	core.position = Vector3(0, 2.1, -0.2)
	add_child(core)
	# Anneau runique qui tourne.
	_ring = Node3D.new()
	_ring.position = core.position
	add_child(_ring)
	for k in 8:
		var a := k * TAU / 8.0
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.1, 0.1, 0.05)
		mi.mesh = bm
		mi.material_override = _core_mat
		mi.position = Vector3(cos(a), sin(a), 0) * 0.45
		mi.rotation.z = a
		_ring.add_child(mi)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.15, 0.08)
	_light.omni_range = 6.0
	_light.light_energy = 0.3
	_light.position = Vector3(0, 2.0, 0.5)
	add_child(_light)
	_display = Node3D.new()
	_display.position = Vector3(0, 1.25, 0.05)
	add_child(_display)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("surface", "metal")  # impacts de balles (Fx.surface_at)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.6, 1.0, 0.9)
	cs.shape = shape
	cs.position.y = 0.5
	body.add_child(cs)
	add_child(body)
	var label := Label3D.new()
	label.text = "PACK-A-PUNCH\n5000"
	label.font = UiStyle.font("stencil")
	label.font_size = 56
	label.pixel_size = 0.004
	label.modulate = Color(0.85, 0.2, 0.12)
	label.position = Vector3(0, 0.55, 0.46)
	add_child(label)


func _box(size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.position = pos
	mi.material_override = mat
	add_child(mi)


func interact_point() -> Vector3:
	return global_position - _normal * 0.9 + Vector3.UP * 1.1


func prompt(pid: int) -> String:
	var game := system.game
	var pd := game.session.get_data(pid)
	if pd == null:
		return ""
	match state:
		State.WORKING:
			return ""
		State.READY:
			return "[F] Prendre %s" % WeaponDB.display_name(weapon_id, true) if pid == owner_pid else ""
	if not game.power_on:
		return "Le courant doit être rétabli"
	var w := pd.current_weapon()
	if w.is_empty():
		return ""
	if w.pap:
		return "" if WeaponDB.is_full(w) else "[F] Recharger %s %s" % [WeaponDB.display_name(w.id, true), Interactable.cost_text(REFILL_COST)]
	return "[F] Améliorer %s %s" % [WeaponDB.display_name(w.id), Interactable.cost_text(COST)]


func srv_use(pid: int) -> void:
	var game := system.game
	var session := game.session
	var pd := session.get_data(pid)
	if pd == null or pd.life != PlayerData.Life.ALIVE:
		return
	if state == State.READY:
		if pid != owner_pid:
			return
		WeaponDB.give(pd, weapon_id, true)
		VoxSystem.say(pid, "pap_take", 0.9)
		game.combat.cancel_reload(pid)
		session.sync_inventory(pid)
		_set_state(State.IDLE, 0, "")
		return
	if state != State.IDLE or not game.power_on:
		if not game.power_on:
			system.deny(pid, "Pas de courant")
		return
	var w := pd.current_weapon()
	if w.is_empty():
		return
	if w.pap:
		if WeaponDB.is_full(w) or not session.try_spend(pid, REFILL_COST):
			system.deny(pid, "Pas assez de points")
			return
		WeaponDB.refill(pd, pd.slot)
		game.combat.cancel_reload(pid)
		system.purchase_fx(self)
		session.sync_inventory(pid)
		return
	if not session.try_spend(pid, COST):
		system.deny(pid, "Pas assez de points")
		return
	system.purchase_fx(self)
	# L'arme quitte les mains du joueur.
	pd.weapons.remove_at(pd.slot)
	pd.slot = clampi(pd.slot, 0, maxi(pd.weapons.size() - 1, 0))
	game.combat.cancel_reload(pid)
	session.sync_inventory(pid)
	_timer = WORK_TIME
	_set_state(State.WORKING, pid, w.id)
	VoxSystem.say(pid, "pap_upgrade", 0.9)
	VoxSystem.say_later(4.5, pid, "pap_wait", 0.5)


func _set_state(s: State, pid: int, wid: String) -> void:
	state = s
	owner_pid = pid
	weapon_id = wid
	broadcast_state()


func _process(delta: float) -> void:
	_animate(delta)
	if not multiplayer.is_server() or state == State.IDLE:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	if state == State.WORKING:
		_timer = READY_TIME
		_set_state(State.READY, owner_pid, weapon_id)
	elif state == State.READY:
		# Arme non récupérée : perdue.
		_set_state(State.IDLE, 0, "")


func get_state() -> Dictionary:
	return {"state": state, "owner": owner_pid, "weapon": weapon_id}


func apply_state(s: Dictionary, animate: bool) -> void:
	state = s.get("state", State.IDLE)
	owner_pid = s.get("owner", 0)
	weapon_id = s.get("weapon", "")
	if _display_model:
		_display_model.queue_free()
		_display_model = null
	match state:
		State.WORKING:
			if animate:
				Audio.play_3d("pap_forge", global_position + Vector3.UP * 1.5, 0.0, 0.0)
		State.READY:
			_display_model = WeaponModels.build(WeaponDB.stats(weapon_id).model, false, true)
			_display_model.rotation.y = PI * 0.5
			_display_model.scale = Vector3.ONE * 1.5
			_display.add_child(_display_model)
			if animate:
				Audio.play_3d("pap_ready", global_position + Vector3.UP * 1.5, 0.0, 0.0)


func _animate(delta: float) -> void:
	if _ring == null:
		return
	_t += delta
	var on := system.game.power_on
	var working := state == State.WORKING
	_ring.rotation.z += delta * (4.0 if working else (0.6 if on else 0.1))
	var glow := 0.2
	if on:
		glow = 2.0 + 0.6 * sin(_t * 2.0)
	if working:
		glow = 5.0 + 3.0 * sin(_t * 18.0)
	_core_mat.emission_energy_multiplier = glow
	_light.light_energy = glow * 0.5
	if working and randf() < delta * 20.0:
		system.game.fx_root.sparks.burst(global_position + Vector3.UP * 1.1 - _normal * 0.3, -_normal + Vector3.UP, 3, 3.0, 0.8, 0.4, Color(1.0, 0.3, 0.1))
	if _display_model:
		_display.rotation.y += delta * 1.2


## Machine de style BO1 : coffre bleu-vert sur pieds, rouleaux dans
## l'ouverture avant, enseigne au-dessus. La lueur (_core_mat) éclaire
## l'ouverture pendant l'amélioration ; l'arme y est présentée (_display).
func _build_model() -> void:
	var packed := load(MODEL) as PackedScene
	if packed == null:
		push_error("[PackAPunch] modèle introuvable : " + MODEL)
		return
	var model: Node3D = packed.instantiate()
	model.name = "Model"
	add_child(model)
	for n in model.find_children("*", "", true, false):
		var parts := String(n.name).split("__")
		if n is MeshInstance3D and parts.size() >= 3:
			(n as MeshInstance3D).material_override = MeshMapBuilder.material_for(parts[0])
			if parts[2] == "ns":
				(n as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif n is StaticBody3D:
			n.queue_free()  # collision propre ci-dessous (activée ou non selon la révélation)
	_core_mat = StandardMaterial3D.new()
	_core_mat.albedo_color = Color(0.4, 0.02, 0.02)
	_core_mat.emission_enabled = true
	_core_mat.emission = Color(1.0, 0.35, 0.1)
	_core_mat.emission_energy_multiplier = 0.2
	var core := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(1.2, 0.45)
	core.mesh = qm
	core.material_override = _core_mat
	core.position = Vector3(0, 0.78, 0.3)
	add_child(core)
	_ring = Node3D.new()  # l'anneau runique n'existe pas sur ce modèle
	add_child(_ring)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.45, 0.2)
	_light.omni_range = 5.0
	_light.light_energy = 0.3
	_light.position = Vector3(0, 1.0, 0.9)
	add_child(_light)
	_display = Node3D.new()
	_display.position = Vector3(0, 0.8, 0.35)
	add_child(_display)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("surface", "metal")
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.75, 1.35, 0.95)
	cs.shape = shape
	cs.position.y = 0.675
	body.add_child(cs)
	add_child(body)
