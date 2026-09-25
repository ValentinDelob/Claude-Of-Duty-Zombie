class_name Teleporter
extends Interactable
## Téléporteur du quai vers la salle du rituel (Pack-a-Punch).
##
## Serveur : IDLE -> CHARGING (3 s) -> ACTIVE (joueurs dans la salle, 25 s)
## -> COOLDOWN (60 s) -> IDLE. Tous les joueurs présents sur la plateforme au
## moment du départ (positions serveur) sont transportés, puis ramenés.
## Chaque client déplace lui-même son joueur (autorité de mouvement), sur
## ordre du serveur.

enum State { IDLE, CHARGING, ACTIVE, COOLDOWN }

const COST := 1500
const CHARGE_TIME := 3.0
const ACTIVE_TIME := 25.0
const COOLDOWN_TIME := 60.0
const PAD_RADIUS := 1.6

var state: State = State.IDLE
var exit_pos := Vector3.ZERO
var _timer := 0.0
var _travellers: Array = []
var _ring_mat: StandardMaterial3D
var _light: OmniLight3D
var _exit_ring_mat: StandardMaterial3D
var _t := 0.0
var end_time_msec := 0


func setup(pad_cells: Array, exit_cell: Vector2i) -> void:
	interact_id = "teleporter"
	name = "Teleporter"
	position = MapData.cells_center(pad_cells)
	exit_pos = MapData.cell_to_world(exit_cell, 0.05)
	interact_range = 2.4


func _ready() -> void:
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.albedo_color = Color(0.1, 0.05, 0.02)
	_ring_mat.emission_enabled = true
	_ring_mat.emission = Color(1.0, 0.5, 0.15)
	_ring_mat.emission_energy_multiplier = 0.0
	_build_pad(self, 1.0, _ring_mat)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.55, 0.2)
	_light.omni_range = 6.0
	_light.light_energy = 0.0
	_light.position = Vector3(0, 1.5, 0)
	add_child(_light)
	# Plateforme d'arrivée dans la salle du rituel.
	_exit_ring_mat = _ring_mat.duplicate()
	var exit_pad := Node3D.new()
	exit_pad.name = "ExitPad"
	get_parent().add_child.call_deferred(exit_pad)
	exit_pad.position = exit_pos - Vector3(0, 0.05, 0)
	_build_pad(exit_pad, 0.7, _exit_ring_mat)
	system.game.power_changed.connect(func(_on): _refresh())
	_refresh()


func _build_pad(parent: Node3D, scale_k: float, ring_mat: Material) -> void:
	var steel := WorldLook.surface("steel")
	var disc := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = 1.4 * scale_k
	dm.bottom_radius = 1.5 * scale_k
	dm.height = 0.12
	dm.radial_segments = 18
	disc.mesh = dm
	disc.material_override = steel
	disc.position.y = 0.06
	parent.add_child(disc)
	var ring := MeshInstance3D.new()
	var rm := TorusMesh.new()
	rm.inner_radius = 1.05 * scale_k
	rm.outer_radius = 1.2 * scale_k
	rm.rings = 18
	rm.ring_segments = 6
	ring.mesh = rm
	ring.material_override = ring_mat
	ring.position.y = 0.13
	parent.add_child(ring)
	# Quatre bobines.
	for k in 4:
		var a := k * TAU / 4.0 + PI / 4.0
		var coil := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.06
		cm.bottom_radius = 0.12
		cm.height = 1.6 * scale_k
		cm.radial_segments = 8
		coil.mesh = cm
		coil.material_override = steel
		coil.position = Vector3(cos(a), 0, sin(a)) * 1.3 * scale_k + Vector3(0, 0.8 * scale_k, 0)
		parent.add_child(coil)
		var tip := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.1
		sm.height = 0.2
		tip.mesh = sm
		tip.material_override = ring_mat
		tip.position = coil.position + Vector3(0, 0.85 * scale_k, 0)
		parent.add_child(tip)


func _refresh() -> void:
	var on := system.game.power_on
	_ring_mat.emission_energy_multiplier = 1.5 if on else 0.0
	_exit_ring_mat.emission_energy_multiplier = 1.0 if on else 0.0


func interact_point() -> Vector3:
	return global_position + Vector3.UP * 1.0


func prompt(_pid: int) -> String:
	if state != State.IDLE:
		return ""
	if not system.game.power_on:
		return "Le courant doit être rétabli"
	return "[F] Activer le téléporteur %s" % Interactable.cost_text(COST)


func srv_use(pid: int) -> void:
	var game := system.game
	if state != State.IDLE:
		return
	if not game.power_on:
		system.deny(pid, "Pas de courant")
		return
	if not game.session.try_spend(pid, COST):
		system.deny(pid, "Pas assez de points")
		return
	system.purchase_fx(self)
	_timer = CHARGE_TIME
	_set_state(State.CHARGING)


func _set_state(s: State) -> void:
	state = s
	end_time_msec = Time.get_ticks_msec() + int(_timer * 1000.0)
	broadcast_state()


func _process(delta: float) -> void:
	_animate(delta)
	if not multiplayer.is_server() or state == State.IDLE:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	var game := system.game
	match state:
		State.CHARGING:
			_travellers = []
			for p: Player in game.players.values():
				var pd := game.session.get_data(p.peer_id)
				var flat := p.global_position - global_position
				flat.y = 0.0
				if pd and pd.life == PlayerData.Life.ALIVE and flat.length() <= PAD_RADIUS:
					_travellers.append(p.peer_id)
			if _travellers.is_empty():
				# Personne sur la plateforme : l'énergie se dissipe.
				_timer = COOLDOWN_TIME * 0.25
				_set_state(State.COOLDOWN)
				return
			for i in _travellers.size():
				var off := Vector3(cos(i * 1.7), 0, sin(i * 1.7)) * (0.6 if i > 0 else 0.0)
				_send(_travellers[i], exit_pos + off, true)
			print("[Teleporter] %d joueur(s) vers la salle du rituel" % _travellers.size())
			_timer = ACTIVE_TIME
			_set_state(State.ACTIVE)
		State.ACTIVE:
			for i in _travellers.size():
				var off := Vector3(cos(i * 1.7), 0, sin(i * 1.7)) * 0.7
				_send(_travellers[i], global_position + off + Vector3(0, 0.05, 0), false)
			_travellers = []
			_timer = COOLDOWN_TIME
			_set_state(State.COOLDOWN)
		State.COOLDOWN:
			_set_state(State.IDLE)


## Serveur : ordonne au client propriétaire de déplacer son joueur.
func _send(pid: int, pos: Vector3, outbound: bool) -> void:
	system.game.teleport_player(pid, pos, outbound)


func get_state() -> Dictionary:
	return {"state": state, "remaining": _timer}


func apply_state(s: Dictionary, animate: bool) -> void:
	state = s.get("state", State.IDLE)
	end_time_msec = Time.get_ticks_msec() + int(float(s.get("remaining", 0.0)) * 1000.0)
	if animate and state == State.CHARGING:
		Audio.play_3d("tele_charge", global_position + Vector3.UP, 0.0, 0.0)


func seconds_left() -> int:
	return maxi(0, int(ceil((end_time_msec - Time.get_ticks_msec()) / 1000.0)))


func _animate(delta: float) -> void:
	if _ring_mat == null:
		return
	_t += delta
	var on := system.game.power_on
	match state:
		State.CHARGING:
			var k := 1.0 - clampf((end_time_msec - Time.get_ticks_msec()) / (CHARGE_TIME * 1000.0), 0.0, 1.0)
			_ring_mat.emission = Color(1.0, 0.6, 0.3).lerp(Color(1, 1, 1), k)
			_ring_mat.emission_energy_multiplier = 2.0 + k * 10.0 + sin(_t * 40.0) * 2.0
			_light.light_energy = 1.0 + k * 5.0
			if randf() < delta * 30.0:
				var a := randf() * TAU
				system.game.fx_root.sparks.burst(global_position + Vector3(cos(a), 1.6, sin(a)) * 1.3, Vector3.UP, 2, 3.0, 1.0, 0.3, Color(1.0, 0.8, 0.5))
		State.COOLDOWN:
			_ring_mat.emission = Color(1.0, 0.12, 0.05)
			_ring_mat.emission_energy_multiplier = 0.8 + 0.4 * sin(_t * 3.0)
			_light.light_energy = 0.3
		_:
			_ring_mat.emission = Color(1.0, 0.5, 0.15)
			_ring_mat.emission_energy_multiplier = (1.5 + 0.3 * sin(_t * 2.0)) if on else 0.0
			_light.light_energy = 0.6 if on else 0.0
