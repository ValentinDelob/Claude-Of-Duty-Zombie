class_name Brancardier
extends Zombie
## Le Brancardier (mini-boss de vague spéciale, GAME_CONCEPT.md §4.4) : ancien
## brancardier de l'hôpital devenu une brute massive, son brancard sanglé
## dans le dos. « Type d'entité » du ZombieManager (KIND_BRANCARDIER), comme
## le chien : même canal réseau (apparition, instantanés, mort), mêmes
## dégâts, ferraille et pièges que les zombies. Propres à lui : modèle
## (BrancardierModel), animation (BrancardierAnim), marche lourde, CHARGE
## télégraphiée (il gratte du pied et rugit) qui projette les joueurs, choc
## contre un mur qui l'ÉTOURDIT, coup des deux poings, mort à genoux puis
## face contre terre. Règles et chiffres : BrancardRules.
##
## Réseau (hôte autoritaire) : le serveur décide de tout (charge, touches,
## projection, étourdissement) ; la phase de la charge voyage dans le code
## d'animation des instantanés (bits 3-4, à la place de la classe de vitesse
## des zombies) : les clients en tirent pose, sons et effets.

enum Phase { NONE, WINDUP, CHARGE, STUN }

## Capsule de déplacement (tronc massif) et séparation.
const RADIUS_B := 0.36
const HEIGHT_B := 2.1
const SEPARATION_B := 1.0
## Mort : le corps reste puis se dissout cube par cube (avant le retrait par
## ZombieManager, DISSOLVE_DELAY + DISSOLVE_TIME + 0,3 s du zombie).
const B_DISSOLVE_DELAY := 2.2
const B_DISSOLVE_TIME := 1.2
## Intensité de la lueur des yeux par phase (NONE, WINDUP, CHARGE, STUN).
const EYE_GLOW := [1.0, 3.5, 2.4, 0.35]

signal charge_started
signal charge_hit_player(pid: int)
signal wall_stunned

## Toutes les machines : phase de la charge et secondes depuis son début.
var charge_phase: int = Phase.NONE
var phase_time := 0.0
## Serveur : direction de la charge en cours, délai avant la prochaine,
## joueurs déjà percutés par cette charge ; compteurs (tests).
var charge_dir := Vector3.FORWARD
var charge_cooldown := 2.0
var charges := 0
var wall_hits := 0
var player_hits := 0
var _hit_this_charge := {}
var _life_t := 0.0
var _scrapes := 0
var _stars_t := 0.0
var _stars: Node3D
## Client : phases de la charge reçues (_cl_phase), à jouer.
var _net_phases: Array[int] = []
var _gait := 0.0
var _last_step := 0


func _ready() -> void:
	_mgr = get_parent() as ZombieManager
	game = _mgr.game if _mgr else null
	_multilevel = map_is_multilevel()
	speed_class = 0
	speed_mult = 1.0
	sep_range = SEPARATION_B
	collision_layer = 0
	collision_mask = 1 | (1 << 1) | (1 << 2)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = RADIUS_B
	cap.height = HEIGHT_B
	cs.shape = cap
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	max_slides = 3
	wall_min_slide_angle = 0.0
	cs.position.y = HEIGHT_B * 0.5 + floor_gap()
	_body_shape = cs
	add_child(cs)
	_update_solidity()

	skel = BrancardierModel.build(variant)
	add_child(skel)
	mesh = skel.get_node("Mesh")
	bones = RigBuilder.bone_indices(skel)
	var rng := RandomNumberGenerator.new()
	rng.seed = variant
	_gait = rng.randf() * TAU

	# Zones de touche (BrancardierModel.hit_shapes) : tronc debout, tête sur
	# l'os head (point faible : multiplicateur de tête de l'arme), bras et
	# avant-bras (comptés « corps »).
	var shapes := BrancardierModel.hit_shapes()
	var body: Array = shapes.body
	var body_cap := CapsuleShape3D.new()
	body_cap.radius = body[1]
	body_cap.height = body[2]
	hit_body = _make_hitbox(0, body_cap)
	hit_body.position = body[0]
	add_child(hit_body)
	var att := BoneAttachment3D.new()
	att.bone_name = "head"
	skel.add_child(att)
	var sph := SphereShape3D.new()
	sph.radius = shapes.head[1]
	hit_head = _make_hitbox(1, sph)
	hit_head.position = shapes.head[0]
	att.add_child(hit_head)
	for side in ["l", "r"]:
		for part in ["arm", "forearm"]:
			var arm_att := BoneAttachment3D.new()
			arm_att.bone_name = part + "_" + side
			skel.add_child(arm_att)
			var acap := CapsuleShape3D.new()
			acap.radius = 0.13
			acap.height = 0.5
			var ha := _make_hitbox(2, acap)
			ha.name = ("HitArm_" if part == "forearm" else "HitUpperArm_") + side
			ha.position = Vector3(0.0, -0.25, 0.0)
			arm_att.add_child(ha)
			if part == "forearm":
				hit_arms.append(ha)
			else:
				hit_upper_arms.append(ha)
	if not server_side:
		set_physics_process(false)
	_update_pose(0.0)


## Hauteur des yeux (lignes de vue, tir) : la tête du modèle.
func head_position() -> Vector3:
	return hit_head.global_position


## Centre du corps pour le contrôle des touches (colosse de 2,25 m : sa tête
## est à plus de HIT_TOLERANCE du centre d'un zombie ordinaire).
func hit_center_height() -> float:
	return 1.5


func move_speed() -> float:
	return BrancardRules.WALK_SPEED


func is_crawler() -> bool:
	return false


func _fit_radius(slim: bool) -> float:
	return RADIUS_B + SLIM_MARGIN if slim else RADIUS_B + 0.06


func _leg_radius() -> float:
	return RADIUS_B


## Code d'animation : état (3 bits) | phase de la charge (2 bits).
func anim_code() -> int:
	return int(state) | (charge_phase << 3)


## Serveur -> clients : changement de phase de la charge, en message FIABLE
## (rare : quatre par charge). Les instantanés non fiables peuvent se perdre
## par rafales ; la préparation, le choc et leurs sons ne doivent jamais
## manquer. Mis en file, joué par _process dans l'ordre reçu.
@rpc("authority", "call_remote", "reliable")
func _cl_phase(p: int) -> void:
	if server_side or p < Phase.NONE or p > Phase.STUN:
		return
	_net_phases.append(p)


# --------------------------------------------------------------------------
# Serveur
# --------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	if state == State.CHASE and charge_phase != Phase.NONE:
		_state_time += delta
		phase_time += delta
		_charge_step(delta)
		return
	if state == State.CHASE:
		charge_cooldown -= delta
		if _try_charge():
			return
	super(delta)


## La charge peut-elle partir vers la cible ? Alors : préparation (WINDUP).
func _try_charge() -> bool:
	if game == null or game.nav == null or charge_cooldown > 0.0:
		return false
	if target == null or not is_instance_valid(target) or not _is_target_valid(target):
		return false
	var to := target.global_position - global_position
	var dy := absf(to.y)
	to.y = 0.0
	var d := to.length()
	if not BrancardRules.can_charge(d, dy, true, charge_cooldown):
		return false
	var tpos := target.global_position
	if not (game.nav.world_line_clear(global_position, tpos) and not game.nav.crosses_stairs(global_position, tpos) and _body_fits(tpos, true)):
		charge_cooldown = 0.4  # nouvel essai un peu plus tard (pas à chaque pas)
		return false
	charge_dir = to / d
	_set_phase(Phase.WINDUP)
	return true


func _charge_step(delta: float) -> void:
	match charge_phase:
		Phase.WINDUP:
			velocity.x = move_toward(velocity.x, 0.0, 20.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, 20.0 * delta)
			# Il suit sa proie des yeux, puis verrouille sa direction.
			if phase_time < BrancardRules.WINDUP_TIME * 0.8 and target and is_instance_valid(target):
				var to := target.global_position - global_position
				to.y = 0.0
				if to.length() > 0.1:
					charge_dir = to.normalized()
			yaw = lerp_angle(yaw, atan2(charge_dir.x, charge_dir.z), 1.0 - exp(-delta * 10.0))
			rotation.y = yaw
			if phase_time >= BrancardRules.WINDUP_TIME:
				_hit_this_charge.clear()
				charges += 1
				# Il traverse zombies et joueurs (touches gérées à la main) ; seul
				# le décor l'arrête.
				collision_mask = 1
				_set_phase(Phase.CHARGE)
				charge_started.emit()
		Phase.CHARGE:
			yaw = atan2(charge_dir.x, charge_dir.z)
			rotation.y = yaw
			var k := clampf(phase_time / 0.25, 0.3, 1.0)
			velocity.x = charge_dir.x * BrancardRules.CHARGE_SPEED * k
			velocity.z = charge_dir.z * BrancardRules.CHARGE_SPEED * k
		Phase.STUN:
			velocity.x = move_toward(velocity.x, 0.0, 12.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, 12.0 * delta)
			if phase_time >= BrancardRules.STUN_TIME:
				_end_charge()
	velocity.y = 0.0
	var before := global_position
	move_and_slide()
	if _multilevel:
		_follow_floor()
	elif global_position.y != 0.0:
		global_position.y = 0.0
	anim_speed = Vector2(velocity.x, velocity.z).length()
	if charge_phase != Phase.CHARGE:
		return
	_charge_hits()
	# Mur de face : étourdi ; bloqué sans avancer : idem.
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		if BrancardRules.hits_wall(c.get_normal(), charge_dir):
			_stun()
			return
	var moved := Vector2(global_position.x - before.x, global_position.z - before.z).length()
	if phase_time > 0.3 and moved < BrancardRules.CHARGE_SPEED * delta * 0.2:
		_stun()
		return
	if phase_time >= BrancardRules.CHARGE_TIME:
		_end_charge()


## Joueurs sur la route de la charge : dégâts et projection (une fois chacun).
func _charge_hits() -> void:
	for p: Player in game.players.values():
		if _hit_this_charge.has(p.peer_id) or not _is_target_valid(p):
			continue
		var rel := p.global_position - global_position
		if absf(rel.y) > LEVEL_TOLERANCE or not BrancardRules.in_charge_path(rel, charge_dir):
			continue
		_hit_this_charge[p.peer_id] = true
		player_hits += 1
		game.combat.damage_player(p.peer_id, BrancardRules.CHARGE_DAMAGE, global_position + Vector3.UP * 1.2)
		p.srv_knockback(BrancardRules.knock_velocity(rel, charge_dir), BrancardRules.KNOCK_TIME)
		charge_hit_player.emit(p.peer_id)


func _stun() -> void:
	wall_hits += 1
	collision_mask = 1 | (1 << 1) | (1 << 2)
	# Recule un peu sous le choc.
	velocity = -charge_dir * 2.2
	_set_phase(Phase.STUN)
	wall_stunned.emit()


func _end_charge() -> void:
	collision_mask = 1 | (1 << 1) | (1 << 2)
	charge_cooldown = BrancardRules.CHARGE_COOLDOWN
	_repath_t = 0.0
	_set_phase(Phase.NONE)


func _set_phase(p: int) -> void:
	charge_phase = p
	phase_time = 0.0
	_on_phase(p)
	if Net.is_online() and multiplayer.has_multiplayer_peer() and not multiplayer.get_peers().is_empty():
		_cl_phase.rpc(p)


## Coup des deux poings (au contact, après la poursuite de Zombie._chase).
func _start_attack() -> void:
	_set_state(State.ATTACK)
	_attack_hit_done = false
	velocity.x = 0.0
	velocity.z = 0.0
	play_attack()


func _chase(delta: float) -> void:
	# Pas de leurre pour la brute ; coup des deux poings un peu plus loin
	# qu'un zombie (bras longs).
	if game == null or game.nav == null:
		return
	if target and is_instance_valid(target) and _is_target_valid(target):
		var to := target.global_position - global_position
		var dy := absf(to.y)
		to.y = 0.0
		if to.length() < BrancardRules.SMASH_RANGE and dy < LEVEL_TOLERANCE:
			_start_attack()
			return
	super(delta)


func _attack(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 20.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 20.0 * delta)
	if target and is_instance_valid(target) and _state_time < BrancardRules.SMASH_HIT_TIME:
		var to := target.global_position - global_position
		yaw = lerp_angle(yaw, atan2(to.x, to.z), 1.0 - exp(-delta * 6.0))
		rotation.y = yaw
	if not _attack_hit_done and _state_time >= BrancardRules.SMASH_HIT_TIME:
		_attack_hit_done = true
		if target and is_instance_valid(target) and _is_target_valid(target):
			var d := target.global_position - global_position
			var dy := absf(d.y)
			d.y = 0.0
			if d.length() < BrancardRules.SMASH_REACH and dy < LEVEL_TOLERANCE:
				game.combat.damage_player(target.peer_id, BrancardRules.SMASH_DAMAGE, global_position + Vector3.UP * 1.4)
	if _state_time >= BrancardRules.SMASH_TIME:
		_set_state(State.CHASE)


## Coincé (contre un autre zombie, un angle...) : comme un zombie, sans
## secousse au hasard (il pèse trop lourd) ; recalcul du chemin.
func _check_stuck(delta: float) -> void:
	_stuck_t += delta
	if _stuck_t < 1.2:
		return
	if global_position.distance_to(_stuck_pos) < 0.3:
		_repath_t = 0.0
	_stuck_pos = global_position
	_stuck_t = 0.0


# --------------------------------------------------------------------------
# Toutes les machines
# --------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _life_t == 0.0:
		# Apparition : rugissement sourd.
		Audio.play_3d("brancard_roar_2", global_position + Vector3.UP * 2.0, -2.0, 0.08, 3)
	_life_t += maxf(delta, 0.0001)
	if state == State.DEAD:
		_process_death(delta)
		return
	if not server_side:
		_interpolate()
		_state_time += delta
		phase_time += delta
		# Phases reçues (_cl_phase, fiable) dans l'ordre : aucune
		# n'est sautée (une par image : chaque phase est vue et entendue).
		if not _net_phases.is_empty():
			charge_phase = _net_phases.pop_front()
			phase_time = 0.0
			_on_phase(charge_phase)
	_groan(delta)
	_phase_fx(delta)
	_pose_accum += delta
	var step := _mgr.pose_step(global_position) if _mgr else 0.0
	if _pose_accum >= step:
		_update_pose(_pose_accum)
		_pose_accum = 0.0
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 6.0, 0.0)
		mesh.set_instance_shader_parameter("hit_flash", _flash)


## Début d'une phase de la charge : sons et effets (toutes les machines).
func _on_phase(p: int) -> void:
	_scrapes = 0
	if p != Phase.NONE:
		print("[Brancardier] %d : %s (%s)" % [id, ["poursuite", "préparation", "charge", "étourdi"][p], "serveur" if server_side else "client"])
	var head := global_position + Vector3.UP * 2.0
	# Yeux : flamboient à la préparation et pendant la charge (lisible de
	# loin, même à contre-jour), ternes quand il est étourdi.
	if mesh and state != State.DEAD:
		mesh.set_instance_shader_parameter("eye_glow", EYE_GLOW[clampi(p, 0, EYE_GLOW.size() - 1)])
	match p:
		Phase.WINDUP:
			Audio.play_3d("brancard_roar_1", head, 2.0, 0.05, 3)
		Phase.CHARGE:
			Audio.play_3d("brancard_charge", head, 0.0, 0.06, 3)
		Phase.STUN:
			var front := global_position + charge_dir_seen() * 0.6 + Vector3.UP * 1.4
			Audio.play_3d("brancard_impact", front, 3.0, 0.05, 3)
			var fx: Fx = game.fx_root if game else null
			if fx:
				fx.dust.burst(front, -charge_dir_seen(), 18, 3.5, 1.2, 1.1, Color(0.36, 0.34, 0.3, 0.6), 2.2)
				fx.debris.burst(front, -charge_dir_seen(), 10, 4.0, 1.0, 1.0, Color(0.55, 0.53, 0.5), 1.2)
			# Secousse de la vue des joueurs proches.
			if game and game.local_player:
				var dist := game.local_player.global_position.distance_to(global_position)
				if dist < 12.0:
					var amp := 0.06 * (1.0 - dist / 12.0)
					game.local_player.add_flinch(Vector2(randf_range(-amp, amp), amp))
			_stars_t = 0.0


## Direction de la charge vue par toutes les machines (le client suit le lacet).
func charge_dir_seen() -> Vector3:
	return Vector3(sin(yaw), 0.0, cos(yaw))


## Effets continus : pieds qui grattent le sol, étoiles d'étourdissement.
func _phase_fx(delta: float) -> void:
	var fx: Fx = game.fx_root if game else null
	if charge_phase == Phase.WINDUP:
		# Trois grattages du pied droit (BrancardierAnim._windup).
		var n := int(floor((phase_time - 0.25) / 0.3)) + 1
		if phase_time > 0.25 and n > _scrapes and n <= 3:
			_scrapes = n
			var foot := global_position + Vector3(-cos(yaw), 0.0, sin(yaw)) * 0.16 - charge_dir_seen() * 0.3
			Audio.play_3d("brancard_scrape", foot, -2.0, 0.1, 4)
			if fx:
				fx.dust.burst(foot + Vector3.UP * 0.05, Vector3.UP - charge_dir_seen(), 6, 1.4, 0.7, 0.8, Color(0.3, 0.28, 0.24, 0.5), 1.4)
	# Étoiles d'étourdissement : couronne de cubes jaunes lumineux (5 cm,
	# effets cubiques du jeu) qui tourne au-dessus de la tête.
	var stunned := charge_phase == Phase.STUN and state != State.DEAD
	if stunned and _stars == null:
		_stars = _make_stars()
	if _stars:
		_stars.visible = stunned
		if stunned:
			_stars_t += delta
			_stars.global_position = head_position() + Vector3.UP * 0.3
			_stars.rotation = Vector3(0.0, _stars_t * 4.0, 0.0)
			for i in _stars.get_child_count():
				var c := _stars.get_child(i) as Node3D
				var a := TAU * i / _stars.get_child_count()
				c.position = Vector3(cos(a) * 0.32, sin(_stars_t * 6.0 + a * 2.0) * 0.04, sin(a) * 0.32)
				c.rotation = Vector3(_stars_t * 3.0, _stars_t * 2.0 + a, 0.0)


func _make_stars() -> Node3D:
	var root := Node3D.new()
	root.name = "StunStars"
	root.top_level = true
	var box := BoxMesh.new()
	box.size = Vector3.ONE * 0.05
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.86, 0.25)
	for i in 5:
		var mi := MeshInstance3D.new()
		mi.mesh = box
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	add_child(root)
	return root


func play_attack() -> void:
	_attack_t = 0.0
	Audio.play_3d("brancard_roar_2", global_position + Vector3.UP * 2.0, 0.0, 0.08, 3)
	get_tree().create_timer(BrancardRules.SMASH_HIT_TIME).timeout.connect(func():
		if is_instance_valid(self) and state != State.DEAD:
			Audio.play_3d("brancard_impact", global_position + Vector3(sin(yaw), 0.3, cos(yaw)), -4.0, 0.1, 3))


## Mort : râle, il tombe à genoux puis s'effondre face contre terre.
func die(_dir: Vector3, _headshot: bool) -> void:
	if state == State.DEAD:
		return
	state = State.DEAD
	_state_time = 0.0
	_death_t = 0.0
	charge_phase = Phase.NONE
	collision_layer = 0
	collision_mask = 1
	hit_body.collision_layer = 0
	hit_head.collision_layer = 0
	hit_body.get_child(0).set_deferred("disabled", true)
	hit_head.get_child(0).set_deferred("disabled", true)
	for ha in hit_arms + hit_upper_arms:
		ha.collision_layer = 0
		ha.get_child(0).set_deferred("disabled", true)
	if _body_shape:
		_body_shape.set_deferred("disabled", true)
	velocity = Vector3.ZERO
	set_physics_process(false)
	clear_snapshots()
	Audio.play_3d("brancard_death", global_position + Vector3.UP * 2.0, 2.0, 0.05, 3)
	var fx: Fx = game.fx_root if game else null
	if fx:
		fx.blood_hit(global_position + Vector3.UP * 1.6, Vector3.UP, 4.0)


func _process_death(delta: float) -> void:
	var before := _death_t
	_death_t += delta
	if before <= BrancardierAnim.DEATH_SETTLE + 0.1:
		BrancardierAnim.apply(skel, bones, BrancardierAnim.pose(_gait, 0.0, _life_t, 0, 0.0, -1.0, _death_t))
	var land := BrancardierAnim.DEATH_KNEEL + BrancardierAnim.DEATH_FALL * 0.8
	if before < BrancardierAnim.DEATH_KNEEL * 0.8 and _death_t >= BrancardierAnim.DEATH_KNEEL * 0.8:
		Audio.play_3d("body_fall", global_position, -2.0, 0.1, 3)
	if before < land and _death_t >= land:
		var at := global_position + Vector3(sin(yaw), 0.0, cos(yaw)) * 1.2
		Audio.play_3d("brancard_impact", at, -1.0, 0.1, 3)
		var fx: Fx = game.fx_root if game else null
		if fx:
			fx.dust.burst(at + Vector3.UP * 0.1, Vector3.UP, 14, 2.0, 1.2, 1.0, Color(0.3, 0.28, 0.25, 0.55), 2.0)
			fx.blood_decal(at + Vector3.UP * 0.1, Vector3.UP, 1.8)
	if _death_t > B_DISSOLVE_DELAY:
		var k := clampf((_death_t - B_DISSOLVE_DELAY) / B_DISSOLVE_TIME, 0.0, 1.0)
		BrancardierModel.set_dissolve(mesh, k)
		if before <= B_DISSOLVE_DELAY:
			mesh.set_instance_shader_parameter("eye_glow", 0.0)
		if k >= 1.0:
			skel.visible = false


func _groan(delta: float) -> void:
	_groan_t -= delta
	if _groan_t > 0.0:
		return
	_groan_t = randf_range(2.5, 5.0)
	if charge_phase == Phase.NONE and state != State.EMERGE:
		Audio.play_3d("brancard_groan_%d" % (1 + randi() % 2), global_position + Vector3.UP * 2.0, -3.0, 0.08, 3)


func _update_pose(delta: float) -> void:
	if skel == null:
		return
	var running := charge_phase == Phase.CHARGE
	var spd := anim_speed
	_gait += delta * ((7.5 if running else 2.2) + spd * 0.4)
	# Pas lourds : un son par pied posé (de près).
	var step := int(floor(_gait / PI))
	if step != _last_step:
		_last_step = step
		if spd > 0.3 and state != State.EMERGE:
			var ear: Variant = Audio.listener_position()
			if ear != null and global_position.distance_to(ear) < 25.0:
				Audio.play_3d("brancard_step_%d" % (1 + step % 2), global_position, -4.0 if running else -7.0, 0.08, 6)
	if _attack_t >= 0.0:
		_attack_t += delta / BrancardRules.SMASH_TIME
		if _attack_t > 1.0:
			_attack_t = -1.0
	var p := BrancardierAnim.pose(_gait, spd / BrancardRules.WALK_SPEED, _life_t, charge_phase, phase_time, _attack_t)
	BrancardierAnim.apply(skel, bones, p)
