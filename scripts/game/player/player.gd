class_name Player
extends CharacterBody3D
## Joueur (FPS). Un nœud Player existe sur chaque machine pour chaque joueur.
##
## * Sur la machine du joueur (autorité = son peer id) : lecture des entrées,
##   déplacement physique, envoi de l'état aux autres à NET_SEND_RATE Hz.
## * Ailleurs : « marionnette » interpolée à partir des états reçus.
## Les données critiques (santé, points, armes...) sont gérées par le serveur,
## pas ici.

signal landed(impact_speed: float)
signal footstep
## Joueur local : fin d'un plongeon (à plat ventre). `height` : hauteur de chute
## depuis le sommet du plongeon (le serveur relaie via Combat.player_dived_landed).
signal dived_landed(position: Vector3, height: float)

const WALK_SPEED := 4.4
const SPRINT_SPEED := 6.8
const CROUCH_SPEED := 2.3
const ADS_SPEED := 2.9
const DOWNED_SPEED := 0.9
const GROUND_ACCEL := 45.0
const GROUND_DECEL := 38.0
const AIR_ACCEL := 7.0
const JUMP_VELOCITY := 5.0
const GRAVITY := 16.0
const EYE_HEIGHT := 1.62
const CROUCH_EYE_HEIGHT := 1.05
const DOWNED_EYE_HEIGHT := 0.55
const STAND_HEIGHT := 1.8
const CROUCH_HEIGHT := 1.2
const RADIUS := 0.35
const SPRINT_DURATION := 4.0
const SPRINT_RECOVERY := 1.6  # secondes de sprint regagnées par seconde de repos... (x/s)
const PITCH_LIMIT := deg_to_rad(88.0)
## Allongé (prone) : touche accroupie maintenue à l'arrêt, ou fin de plongeon.
const PRONE_SPEED := 1.0
const PRONE_EYE_HEIGHT := 0.4
const PRONE_HEIGHT := 0.72
const PRONE_HOLD := 0.6
## Plongeon (dolphin dive de BO1) : accroupi en plein sprint.
const DIVE_SPEED := 7.2
const DIVE_UP := 3.4
const DIVE_EYE_HEIGHT := 0.85
## Immobilisé à plat ventre après l'atterrissage (glissade), s.
const DIVE_LAND_LOCK := 0.55

const NET_SEND_RATE := 20.0
const INTERP_DELAY := 0.1
## État inchangé : renvoyé quand même à cette période (maintien).
const NET_KEEPALIVE := 1.0

## Bit flags envoyés sur le réseau avec la position.
const FLAG_CROUCH := 1
const FLAG_SPRINT := 2
const FLAG_AIM := 4
const FLAG_GROUNDED := 8
const FLAG_MOVING := 16
const FLAG_PRONE := 32
const FLAG_DIVE := 64

var peer_id := 1
var is_local := false
## Vrai si un script (autotest) pilote ce joueur à la place du clavier.
var bot_controlled := false
var input := PlayerInput.new()
var input_enabled := true
## Armes (joueur local uniquement).
var weapons: WeaponController

var yaw := 0.0
var pitch := 0.0
var crouching := false
var sprinting := false
var aiming := false
var downed := false
var stamina := SPRINT_DURATION
var sprint_duration_bonus := 0.0
var speed_multiplier := 1.0
## Ignoré par les zombies (téléportation, cinématique...).
var untargetable := false
var revive_target: ReviveTarget
var _flinch := Vector2.ZERO
var _lunge_vel := Vector3.ZERO
var _lunge_left := 0.0
## Allongé / en plein plongeon.
var prone := false
var diving := false
var _crouch_was := false
var _prone_hold := 0.0
var _prone_lock := 0.0
var _dive_time := 0.0
var _dive_peak_y := 0.0

var head: Node3D
var camera: Camera3D
var visual: PlayerModel
var name_tag: Label3D
var dead := false
var _remote_speed := 0.0
var _last_remote_pos := Vector3.ZERO
var _remote_step := 0.0
var _collision: CollisionShape3D
var _capsule: CapsuleShape3D
var _eye_height := EYE_HEIGHT
var _bob_t := 0.0
var _step_accum := 0.0
var _was_on_floor := true
var _send_accum := 0.0
var _net_flags := 0
## Tampon d'interpolation des marionnettes : [temps, pos, yaw, pitch, flags]
var _snapshots: Array = []
var _last_sent_state := PackedByteArray()
var _last_sent_t := -INF


func setup(id: int, local: bool) -> void:
	peer_id = id
	is_local = local
	name = str(id)
	set_multiplayer_authority(id)


func _ready() -> void:
	collision_layer = 1 << 1          # couche « players »
	collision_mask = 1 | (1 << 2) | Barricade.BARRIER_LAYER  # monde + zombies + fenêtres
	floor_max_angle = deg_to_rad(50.0)
	_capsule = CapsuleShape3D.new()
	_capsule.radius = RADIUS
	_capsule.height = STAND_HEIGHT
	_collision = CollisionShape3D.new()
	_collision.shape = _capsule
	_collision.position.y = STAND_HEIGHT * 0.5
	add_child(_collision)

	head = Node3D.new()
	head.name = "Head"
	head.position.y = EYE_HEIGHT
	add_child(head)
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.near = 0.03
	camera.far = 120.0
	camera.fov = Settings.fov
	head.add_child(camera)

	visual = PlayerModel.new()
	visual.name = "Visual"
	visual.build(ScorePanel.slot_color(Net.player_slot(peer_id)))
	add_child(visual)
	name_tag = Label3D.new()
	name_tag.text = Net.player_name(peer_id)
	name_tag.font = UiStyle.font("impact")
	name_tag.font_size = 40
	name_tag.pixel_size = 0.0035
	name_tag.outline_size = 10
	name_tag.modulate = ScorePanel.slot_color(Net.player_slot(peer_id))
	name_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_tag.fixed_size = false
	name_tag.position.y = 2.15
	add_child(name_tag)

	if is_local:
		camera.current = true
		visual.visible = false
		name_tag.visible = false
		footstep.connect(func(): Audio.play_2d("footstep_%d" % (1 + randi() % 4), -14.0, 0.1))
	else:
		camera.current = false


func _unhandled_input(event: InputEvent) -> void:
	if not is_local or bot_controlled or not input_enabled:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		input.look += event.relative


func _physics_process(delta: float) -> void:
	if is_local:
		_local_physics(delta)
	else:
		_remote_interpolate()
		visual.animate(delta, _remote_speed, pitch, _net_flags, downed, dead)


# --------------------------------------------------------------------------
# Joueur local
# --------------------------------------------------------------------------

func _local_physics(delta: float) -> void:
	if not input_enabled:
		input = PlayerInput.new()
		_move(delta)
		_update_camera_effects(delta)
		return
	if not bot_controlled:
		if input_enabled and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			input.read_devices()
		else:
			var keep_look := input.look
			input = PlayerInput.new()
			input.look = keep_look if input_enabled else Vector2.ZERO

	_apply_look()
	_update_stance(delta)
	_move(delta)
	_update_camera_effects(delta)
	if weapons:
		weapons.tick(delta)
	if Game.instance and Game.instance.interact:
		Game.instance.interact.local_tick(self)

	_send_accum += delta
	if _send_accum >= 1.0 / NET_SEND_RATE:
		_send_accum = 0.0
		_net_flags = _compute_flags()
		if Net.is_online():
			_send_state()
	input.clear_edges()


func _apply_look() -> void:
	var sens := Settings.mouse_sensitivity * 0.01
	if aiming:
		sens *= weapons.ads_look_mult() if weapons else 0.6
	yaw -= input.look.x * sens
	var dy := input.look.y * sens
	pitch -= -dy if Settings.invert_y else dy
	pitch = clampf(pitch, -PITCH_LIMIT, PITCH_LIMIT)
	rotation.y = yaw
	head.rotation.x = pitch


func _update_stance(delta: float) -> void:
	var crouch_pressed := input.crouch and not _crouch_was
	_crouch_was = input.crouch
	if downed:
		prone = false
		diving = false
	# Plongeon (BO1) : s'accroupir en plein sprint.
	if crouch_pressed and sprinting and not diving and not prone and not downed and is_on_floor():
		_start_dive()
	if diving:
		crouching = false
		sprinting = false
		aiming = false
	else:
		_update_prone(delta)
		var want_crouch := input.crouch and not downed and not prone
		if crouching and not want_crouch and not prone and not _can_stand():
			want_crouch = true
		crouching = want_crouch
		aiming = input.aim and not sprinting
		var moving_forward := input.move.y > 0.3
		var want_sprint := input.sprint and moving_forward and not crouching and not prone and not downed and not aiming
		if want_sprint and stamina > 0.05:
			sprinting = true
			stamina = maxf(stamina - delta, 0.0)
		else:
			sprinting = false
			stamina = minf(stamina + SPRINT_RECOVERY * delta, SPRINT_DURATION + sprint_duration_bonus)

	var target_h := STAND_HEIGHT
	if prone:
		target_h = PRONE_HEIGHT
	elif crouching or downed or diving:
		target_h = CROUCH_HEIGHT
	_capsule.height = move_toward(_capsule.height, target_h, delta * 6.0)
	_collision.position.y = _capsule.height * 0.5
	var target_eye := EYE_HEIGHT
	if downed:
		target_eye = DOWNED_EYE_HEIGHT
	elif diving:
		target_eye = DIVE_EYE_HEIGHT
	elif prone:
		target_eye = PRONE_EYE_HEIGHT
	elif crouching:
		target_eye = CROUCH_EYE_HEIGHT
	_eye_height = lerpf(_eye_height, target_eye, 1.0 - exp(-delta * (16.0 if diving else 12.0)))


## Allongé : on s'y met en maintenant la touche accroupie à l'arrêt (BO1) ;
## on se relève en la relâchant (ou en sautant), une fois l'atterrissage fini.
func _update_prone(delta: float) -> void:
	if prone:
		_prone_lock = maxf(_prone_lock - delta, 0.0)
		if _prone_lock <= 0.0 and (not input.crouch or input.jump) and _can_fit(CROUCH_HEIGHT):
			prone = false
			# Sous un plafond bas : on se relève seulement accroupi.
			crouching = not _can_stand()
		return
	if input.crouch and not downed and is_on_floor() and Vector2(velocity.x, velocity.z).length() < 0.6:
		_prone_hold += delta
		if _prone_hold >= PRONE_HOLD:
			prone = true
			_prone_hold = 0.0
	else:
		_prone_hold = 0.0


func _start_dive() -> void:
	var dir := Vector3(velocity.x, 0.0, velocity.z)
	if dir.length_squared() < 1.0:
		dir = -transform.basis.z
		dir.y = 0.0
	dir = dir.normalized()
	diving = true
	prone = false
	crouching = false
	sprinting = false
	_dive_time = 0.0
	_dive_peak_y = global_position.y
	_lunge_left = 0.0
	velocity = dir * DIVE_SPEED + Vector3.UP * DIVE_UP
	Audio.play_2d("knife_swing", -8.0, 0.1, "SFX", 0.6)


## Fin du plongeon : à plat ventre, courte glissade, signal (atout à venir).
func _land_dive() -> void:
	diving = false
	prone = true
	_prone_lock = DIVE_LAND_LOCK
	_prone_hold = 0.0
	velocity.x *= 0.45
	velocity.z *= 0.45
	_flinch = Vector2(0.03, -0.07)
	var height := maxf(_dive_peak_y - global_position.y, 0.0)
	Audio.play_2d("dive_land", -3.0, 0.05)
	dived_landed.emit(global_position, height)
	if Game.instance and Game.instance.combat:
		Game.instance.combat.srv_dive_landed.rpc_id(1, global_position, height)


func _can_stand() -> bool:
	return _can_fit(STAND_HEIGHT)


func _can_fit(height: float) -> bool:
	var params := PhysicsShapeQueryParameters3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = RADIUS * 0.9
	shape.height = height
	params.shape = shape
	params.transform = Transform3D(Basis.IDENTITY, global_position + Vector3.UP * (height * 0.5 + 0.05))
	params.collision_mask = 1
	return get_world_3d().direct_space_state.intersect_shape(params, 1).is_empty()


func current_max_speed() -> float:
	var s := WALK_SPEED
	if downed:
		s = DOWNED_SPEED
	elif prone:
		s = PRONE_SPEED
	elif crouching:
		s = CROUCH_SPEED
	elif sprinting:
		s = SPRINT_SPEED
	elif aiming:
		s = ADS_SPEED
	# Poids de l'arme en main (BO1 : pistolets/PM rapides, mitrailleuses lentes).
	var weapon_mult := 1.0
	if weapons and not downed:
		weapon_mult = float(weapons.current_stats().get("move_mult", 1.0))
	return s * speed_multiplier * weapon_mult


func _move(delta: float) -> void:
	var on_floor := is_on_floor()
	if not on_floor:
		velocity.y -= GRAVITY * delta
	elif input.jump and not crouching and not downed and not prone and not diving:
		velocity.y = JUMP_VELOCITY

	if diving:
		# Plongeon : trajectoire balistique, aucun contrôle en l'air.
		_dive_time += delta
		_dive_peak_y = maxf(_dive_peak_y, global_position.y)
	else:
		var wish := (transform.basis * Vector3(input.move.x, 0.0, -input.move.y))
		wish.y = 0.0
		if wish.length_squared() > 1.0:
			wish = wish.normalized()
		var target := wish * current_max_speed()
		var horiz := Vector3(velocity.x, 0.0, velocity.z)
		var accel := AIR_ACCEL
		if on_floor:
			accel = GROUND_ACCEL if wish.length_squared() > 0.01 else GROUND_DECEL
		if prone and _prone_lock > 0.0:
			# Glissade à plat ventre après le plongeon.
			target = Vector3.ZERO
			accel = 7.0
		horiz = horiz.move_toward(target, accel * delta)
		velocity.x = horiz.x
		velocity.z = horiz.z

	# Fente au couteau : projection imposée vers le zombie visé.
	if _lunge_left > 0.0:
		_lunge_left -= delta
		velocity.x = _lunge_vel.x
		velocity.z = _lunge_vel.z
		if _lunge_left <= 0.0:
			velocity.x *= 0.2
			velocity.z *= 0.2

	var fall_speed := -velocity.y
	move_and_slide()
	if is_on_floor() and not _was_on_floor and fall_speed > 2.0:
		landed.emit(fall_speed)
	_was_on_floor = is_on_floor()
	if diving and _dive_time > 0.08 and is_on_floor():
		_land_dive()


func _update_camera_effects(delta: float) -> void:
	var horiz_speed := Vector2(velocity.x, velocity.z).length()
	var bob_offset := Vector3.ZERO
	if is_on_floor() and horiz_speed > 0.5:
		var freq := 1.9 if not sprinting else 2.6
		_bob_t += delta * freq * TAU * clampf(horiz_speed / WALK_SPEED, 0.5, 1.6) * 0.5
		var amp := 0.035 if not aiming else 0.008
		if sprinting:
			amp = 0.06
		bob_offset = Vector3(cos(_bob_t) * amp * 0.6, absf(sin(_bob_t)) * amp, 0.0)
		_step_accum += horiz_speed * delta
		if _step_accum > (2.2 if not sprinting else 2.7):
			_step_accum = 0.0
			footstep.emit()
	else:
		_bob_t = lerpf(_bob_t, 0.0, delta * 4.0)
	head.position = Vector3(bob_offset.x, _eye_height + bob_offset.y, 0.0)
	_flinch = _flinch.lerp(Vector2.ZERO, 1.0 - exp(-delta * 9.0))
	var sway := weapons.aim_offset() if weapons else Vector2.ZERO
	camera.rotation = Vector3(_flinch.y + sway.x, sway.y, _flinch.x)
	var base_fov := Settings.fov
	var target_fov := base_fov
	if aiming:
		target_fov = base_fov * 0.72
	elif sprinting:
		target_fov = base_fov * 1.06
	camera.fov = weapons.camera_fov(base_fov, target_fov, camera.fov, delta) if weapons else lerpf(camera.fov, target_fov, 1.0 - exp(-delta * 14.0))


func _compute_flags() -> int:
	var f := 0
	if crouching: f |= FLAG_CROUCH
	if sprinting: f |= FLAG_SPRINT
	if aiming: f |= FLAG_AIM
	if is_on_floor(): f |= FLAG_GROUNDED
	if Vector2(velocity.x, velocity.z).length() > 0.5: f |= FLAG_MOVING
	if prone: f |= FLAG_PRONE
	if diving: f |= FLAG_DIVE
	return f


## Téléportation imposée (spawn, téléporteur...). Appelée sur la machine locale.
func teleport_to(pos: Vector3, new_yaw := NAN) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	diving = false
	prone = false
	_lunge_left = 0.0
	if not is_nan(new_yaw):
		yaw = new_yaw
		rotation.y = yaw
	_snapshots.clear()


## Fente au couteau (joueur local) : parcourt `dist` m selon `dir` (plan
## horizontal) en `duration` s. La position suit la synchro réseau habituelle.
func start_lunge(dir: Vector3, dist: float, duration: float) -> void:
	if downed or dist <= 0.01 or duration <= 0.0:
		return
	_lunge_vel = Vector3(dir.x, 0.0, dir.z).normalized() * (dist / duration)
	_lunge_left = duration


func is_lunging() -> bool:
	return _lunge_left > 0.0


func eye_position() -> Vector3:
	return head.global_position


func aim_direction() -> Vector3:
	return -camera.global_transform.basis.z


# --------------------------------------------------------------------------
# Réseau : état de mouvement
# --------------------------------------------------------------------------

## Joueur local : état compact (NetCodec, 17 octets) envoyé seulement s'il a
## changé depuis le dernier envoi, ou toutes les NET_KEEPALIVE secondes.
func _send_state() -> void:
	var buf := NetCodec.encode_player_state(global_position, yaw, pitch, _net_flags)
	var t := Time.get_ticks_usec() / 1000000.0
	if buf == _last_sent_state and t - _last_sent_t < NET_KEEPALIVE:
		return
	_last_sent_state = buf
	_last_sent_t = t
	_net_state.rpc(buf)


@rpc("authority", "call_remote", "unreliable_ordered")
func _net_state(buf: PackedByteArray) -> void:
	var s := NetCodec.decode_player_state(buf)
	if s.is_empty():
		return
	var t := Time.get_ticks_usec() / 1000000.0
	# Après un silence (joueur immobile : aucun envoi), l'interpolation repart
	# du dernier état connu tenu jusqu'à un intervalle avant ce message, au lieu
	# de glisser depuis l'instant du message précédent.
	if not _snapshots.is_empty():
		var last: Array = _snapshots[_snapshots.size() - 1]
		if t - last[0] > 1.5 / NET_SEND_RATE:
			var hold := last.duplicate()
			hold[0] = t - 1.0 / NET_SEND_RATE
			_snapshots.append(hold)
	_snapshots.append([t, s[0], s[1], s[2], s[3]])
	if _snapshots.size() > 20:
		_snapshots.pop_front()


func _remote_interpolate() -> void:
	if _snapshots.is_empty():
		return
	var render_t := Time.get_ticks_usec() / 1000000.0 - INTERP_DELAY
	# Cherche les deux états qui encadrent render_t.
	while _snapshots.size() >= 2 and _snapshots[1][0] <= render_t:
		_snapshots.pop_front()
	var a: Array = _snapshots[0]
	if _snapshots.size() == 1 or render_t <= a[0]:
		_apply_remote(a[1], a[2], a[3], a[4])
		return
	var b: Array = _snapshots[1]
	var t := clampf((render_t - a[0]) / maxf(b[0] - a[0], 0.001), 0.0, 1.0)
	_apply_remote(a[1].lerp(b[1], t), lerp_angle(a[2], b[2], t), lerpf(a[3], b[3], t), b[4])


func _apply_remote(pos: Vector3, r_yaw: float, r_pitch: float, flags: int) -> void:
	global_position = pos
	yaw = r_yaw
	pitch = r_pitch
	rotation.y = yaw
	head.rotation.x = pitch
	_net_flags = flags
	crouching = flags & FLAG_CROUCH != 0
	sprinting = flags & FLAG_SPRINT != 0
	aiming = flags & FLAG_AIM != 0
	# Plongeon d'un coéquipier : bruit d'atterrissage à plat ventre.
	var was_diving := diving
	prone = flags & FLAG_PRONE != 0
	diving = flags & FLAG_DIVE != 0
	if was_diving and not diving:
		Audio.play_3d("dive_land", pos, -4.0, 0.05, 6)
	head.position.y = CROUCH_EYE_HEIGHT if crouching else EYE_HEIGHT
	if prone:
		head.position.y = PRONE_EYE_HEIGHT
	elif diving:
		head.position.y = DIVE_EYE_HEIGHT
	name_tag.position.y = 0.9 if (prone or diving) else 2.15
	# Vitesse estimée (animation, pas) à partir des positions interpolées.
	var dt := get_physics_process_delta_time()
	var moved := Vector2(pos.x - _last_remote_pos.x, pos.z - _last_remote_pos.z).length()
	_last_remote_pos = pos
	if moved < 3.0:
		_remote_speed = lerpf(_remote_speed, moved / dt, 0.25)
		_remote_step += moved
		if _remote_step > (2.7 if sprinting else 2.2) and flags & FLAG_GROUNDED != 0:
			_remote_step = 0.0
			Audio.play_3d("footstep_%d" % (1 + randi() % 4), pos, -8.0, 0.1, 6)


func net_flags() -> int:
	return _net_flags


## Secousse de caméra quand on est frappé (joueur local).
func flinch(from: Vector3) -> void:
	var to := (from - global_position)
	var side := signf(to.dot(global_transform.basis.x))
	_flinch = Vector2(side * 0.06, 0.05)


## Mort du joueur (toutes les machines) : plus de contrôle, caméra au sol.
func set_dead(is_dead: bool) -> void:
	input_enabled = not is_dead
	untargetable = is_dead
	if is_dead:
		input = PlayerInput.new()
		velocity = Vector3.ZERO
		var tw := create_tween().set_parallel(true)
		tw.tween_property(self, "_eye_height", 0.25, 0.9).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		tw.tween_property(camera, "rotation:z", 0.9, 0.9)
		if weapons:
			weapons.view.visible = false
		if not is_local:
			visual.rotation.x = -PI * 0.5
			visual.position.y = 0.3
	else:
		camera.rotation = Vector3.ZERO
		if weapons:
			weapons.view.visible = true
		visual.rotation.x = 0.0
		visual.position.y = 0.0


var _down_marker: Label3D


## À terre (toutes les machines) : on rampe, caméra basse, repère « À TERRE »
## visible par les coéquipiers à travers les murs.
func set_downed(is_down: bool) -> void:
	downed = is_down
	untargetable = is_down or dead
	if is_local:
		var tw := create_tween()
		tw.tween_property(camera, "rotation:z", 0.18 if is_down else 0.0, 0.6)
		return
	if is_down and _down_marker == null:
		_down_marker = Label3D.new()
		_down_marker.text = "✚ À TERRE"
		_down_marker.font = UiStyle.font("impact")
		_down_marker.font_size = 48
		_down_marker.pixel_size = 0.004
		_down_marker.outline_size = 12
		_down_marker.modulate = Color(1.0, 0.25, 0.15)
		_down_marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_down_marker.no_depth_test = true
		_down_marker.fixed_size = true
		_down_marker.pixel_size = 0.0009
		_down_marker.position.y = 1.2
		add_child(_down_marker)
	if _down_marker:
		_down_marker.visible = is_down
	name_tag.visible = not is_down
