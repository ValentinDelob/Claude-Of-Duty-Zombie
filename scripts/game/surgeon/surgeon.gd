class_name Surgeon
extends Zombie
## Le Chirurgien (premier boss, vague de boss, GAME_CONCEPT.md §4.4) : ancien
## chef du bloc opératoire, grand, voûté, en blouse et masque, un scalpel
## géant à la main et le CŒUR MUTANT à vif dans la poitrine (point faible).
## « Type d'entité » du ZombieManager (KIND_SURGEON), comme le Brancardier :
## même canal réseau (apparition, instantanés, mort), mêmes dégâts, ferraille
## et pièges que les zombies ; ni démembrement, ni ragdoll, ni leurre, ni
## recyclage du Spawner (SurgeonRound le replace s'il s'égare).
##
## Combat (serveur ; règles et chiffres : SurgeonRules) : actions
## TÉLÉGRAPHIÉES (Action) : combo au scalpel au contact, scalpels lancés en
## éventail à distance (SurgeonScalpels), opération qui relève des patients
## (zombies) à 75 % et 25 % des PV, changement de phase à 50 % (rugissement,
## onde de choc) puis enragé (plus rapide, plus de coups).
##
## Réseau (hôte autoritaire) : le serveur décide de tout ; chaque action part
## en RPC FIABLE (_cl_action : la préparation et ses sons ne doivent jamais
## manquer) et voyage aussi dans le code d'animation des instantanés (bits
## 3-5, bit 6 : enragé).

enum Action { NONE, SLASH_WINDUP, SLASH, THROW_WINDUP, THROW, SURGERY, ROAR }

## Capsule de déplacement (silhouette longiligne) et séparation. Plus basse
## que le modèle (2,3 m) : il passe sous les linteaux des portes de 2 m.
const RADIUS_S := 0.3
const HEIGHT_S := 1.95
const SEPARATION_S := 0.9
## Mort : le corps reste puis se dissout (avant le retrait par ZombieManager,
## DISSOLVE_DELAY + DISSOLVE_TIME + 0,3 s du zombie).
const S_DISSOLVE_DELAY := 2.5
const S_DISSOLVE_TIME := 1.2
## Lueur des yeux et du cœur : phase 1, phase 2 (enragé).
const EYE_GLOW := [1.0, 2.2]
const HEART_GLOW := [1.0, 2.0]
## Battements du cœur (s entre deux) : phase 1, phase 2.
const BEAT := [1.0, 0.6]
## Battements audibles à moins de cette distance (m).
const BEAT_HEAR := 11.0

signal action_started(a: int)
signal player_slashed(pid: int)
signal scalpels_thrown(n: int)
signal shock_wave(hit: int)

## Toutes les machines : action en cours, secondes depuis son début, phase 2.
var action: int = Action.NONE
var action_time := 0.0
var rage := false
## Serveur : délais avant le prochain combo / lancer ; opérations faites
## (masque des seuils SurgeonRules.SURGERY_AT) ; compteurs (tests).
var slash_cooldown := 0.0
var throw_cooldown := 2.5
var surgeries := 0
var combos := 0
var throws := 0
var slash_hits := 0
var _slash_done := 0
var _summoned := false
var _shock_done := false
## Client : actions reçues (_cl_action), à jouer dans l'ordre.
var _net_actions: Array = []
var _life_t := 0.0
var _gait := 0.0
var _last_step := 0
var _beat_t := 0.0
var _whoosh := 0
var _ring: Node3D
var hit_skull: Area3D


func _ready() -> void:
	_mgr = get_parent() as ZombieManager
	game = _mgr.game if _mgr else null
	_multilevel = map_is_multilevel()
	speed_class = 0
	speed_mult = 1.0
	sep_range = SEPARATION_S
	collision_layer = 0
	collision_mask = 1 | (1 << 1) | (1 << 2)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = RADIUS_S
	cap.height = HEIGHT_S
	cs.shape = cap
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	max_slides = 3
	wall_min_slide_angle = 0.0
	cs.position.y = HEIGHT_S * 0.5 + floor_gap()
	_body_shape = cs
	add_child(cs)
	_update_solidity()

	skel = SurgeonModel.build(variant)
	add_child(skel)
	mesh = skel.get_node("Mesh")
	bones = RigBuilder.bone_indices(skel)
	var rng := RandomNumberGenerator.new()
	rng.seed = variant
	_gait = rng.randf() * TAU

	# Zones de touche (SurgeonModel.hit_shapes) : tronc debout, crâne (compté
	# corps : coiffe et masque), CŒUR sur l'os chest (zone 1 : multiplicateur
	# de tête de l'arme, son point faible), bras.
	var shapes := SurgeonModel.hit_shapes()
	var body: Array = shapes.body
	var body_cap := CapsuleShape3D.new()
	body_cap.radius = body[1]
	body_cap.height = body[2]
	hit_body = _make_hitbox(0, body_cap)
	hit_body.position = body[0]
	add_child(hit_body)
	var head_att := BoneAttachment3D.new()
	head_att.bone_name = "head"
	skel.add_child(head_att)
	var skull := SphereShape3D.new()
	skull.radius = shapes.head[1]
	hit_skull = _make_hitbox(0, skull)
	hit_skull.name = "HitSkull"
	hit_skull.position = shapes.head[0]
	head_att.add_child(hit_skull)
	var chest_att := BoneAttachment3D.new()
	chest_att.bone_name = "chest"
	skel.add_child(chest_att)
	var heart := SphereShape3D.new()
	heart.radius = shapes.heart[1]
	hit_head = _make_hitbox(1, heart)
	hit_head.name = "HitHeart"
	hit_head.position = shapes.heart[0]
	chest_att.add_child(hit_head)
	for side in ["l", "r"]:
		for part in ["arm", "forearm"]:
			var arm_att := BoneAttachment3D.new()
			arm_att.bone_name = part + "_" + side
			skel.add_child(arm_att)
			var acap := CapsuleShape3D.new()
			acap.radius = 0.1
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


## Point faible (validation des « tirs à la tête » par le serveur, Combat) :
## le cœur mutant.
func head_position() -> Vector3:
	return hit_head.global_position


## Centre du corps pour le contrôle des touches (géant de 2,3 m).
func hit_center_height() -> float:
	return 1.35


func move_speed() -> float:
	return SurgeonRules.walk_speed(rage)


func is_crawler() -> bool:
	return false


func _fit_radius(slim: bool) -> float:
	return RADIUS_S + SLIM_MARGIN if slim else RADIUS_S + 0.06


func _leg_radius() -> float:
	return RADIUS_S


## Code d'animation : état (3 bits) | action (3 bits) | enragé (bit 6).
func anim_code() -> int:
	return int(state) | (action << 3) | (64 if rage else 0)


## Serveur -> clients : début d'une action, en message FIABLE (rare). Mis en
## file, joué par _process dans l'ordre reçu.
@rpc("authority", "call_remote", "reliable")
func _cl_action(a: int, enraged: bool) -> void:
	if server_side or a < Action.NONE or a > Action.ROAR:
		return
	_net_actions.append([a, enraged])


# --------------------------------------------------------------------------
# Serveur
# --------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	if state == State.CHASE and action == Action.NONE:
		# Seuils de PV : changement de phase, puis opérations.
		if not rage and SurgeonRules.enraged(health, max_health):
			_set_action(Action.ROAR)
		else:
			var due := SurgeonRules.surgery_due(health, max_health, surgeries)
			if due >= 0:
				surgeries |= 1 << due
				_set_action(Action.SURGERY)
	if state == State.CHASE and action != Action.NONE:
		_state_time += delta
		action_time += delta
		_action_step(delta)
		return
	if state == State.CHASE:
		slash_cooldown -= delta
		throw_cooldown -= delta
		if _try_throw():
			return
	super(delta)


## Lancer de scalpels : cible à portée, en vue.
func _try_throw() -> bool:
	if game == null or game.nav == null or throw_cooldown > 0.0:
		return false
	if target == null or not is_instance_valid(target) or not _is_target_valid(target):
		return false
	var to := target.global_position - global_position
	var dy := absf(to.y)
	to.y = 0.0
	if not SurgeonRules.can_throw(to.length(), dy, true, throw_cooldown):
		return false
	if not game.nav.world_line_clear(global_position + Vector3.UP * 1.5, target.global_position + Vector3.UP * 1.2):
		throw_cooldown = 0.5
		return false
	_set_action(Action.THROW_WINDUP)
	return true


## Combo au scalpel au contact (appelé par Zombie._chase à portée d'attaque
## et par notre _chase plus loin, SLASH_START).
func _start_attack() -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	if slash_cooldown <= 0.0:
		_set_action(Action.SLASH_WINDUP)


func _chase(delta: float) -> void:
	# Pas de leurre pour le boss ; le combo part un peu plus loin qu'une
	# morsure (bras et scalpel longs).
	if game == null or game.nav == null:
		return
	if target and is_instance_valid(target) and _is_target_valid(target):
		var to := target.global_position - global_position
		var dy := absf(to.y)
		to.y = 0.0
		if to.length() < SurgeonRules.SLASH_START and dy < LEVEL_TOLERANCE:
			if slash_cooldown <= 0.0:
				_start_attack()
				return
			# Recharge du combo : il tourne autour de sa proie sans la coller.
			if to.length() < 1.2:
				velocity.x = move_toward(velocity.x, 0.0, 10.0 * delta)
				velocity.z = move_toward(velocity.z, 0.0, 10.0 * delta)
				yaw = lerp_angle(yaw, atan2(to.x, to.z), 1.0 - exp(-delta * 8.0))
				rotation.y = yaw
				return
	super(delta)


func _action_step(delta: float) -> void:
	var stop := true
	match action:
		Action.SLASH_WINDUP:
			_face_target(delta, 9.0)
			if action_time >= SurgeonRules.slash_windup(rage):
				_set_action(Action.SLASH)
		Action.SLASH:
			var hits := SurgeonRules.slash_hits(rage)
			var i := int(floor(action_time / SurgeonRules.SLASH_TIME))
			if i < hits:
				var k := action_time - i * SurgeonRules.SLASH_TIME
				if k < SurgeonRules.LUNGE_TIME:
					var fwd := Vector3(sin(yaw), 0.0, cos(yaw))
					velocity.x = fwd.x * SurgeonRules.LUNGE_SPEED * speed_mult
					velocity.z = fwd.z * SurgeonRules.LUNGE_SPEED * speed_mult
					stop = false
				elif k > 0.3:
					_face_target(delta, 7.0)
				if _slash_done <= i and k >= SurgeonRules.SLASH_HIT_AT:
					_slash_done = i + 1
					_slash_damage()
			elif action_time >= hits * SurgeonRules.SLASH_TIME + SurgeonRules.SLASH_RECOVER:
				slash_cooldown = SurgeonRules.SLASH_COOLDOWN
				_end_action()
		Action.THROW_WINDUP:
			if action_time < SurgeonRules.throw_windup(rage) * 0.8:
				_face_target(delta, 10.0)
			if action_time >= SurgeonRules.throw_windup(rage):
				_throw()
				_set_action(Action.THROW)
		Action.THROW:
			if action_time >= SurgeonRules.THROW_RECOVER:
				throw_cooldown = SurgeonRules.throw_cooldown(rage)
				_end_action()
		Action.SURGERY:
			if not _summoned and action_time >= SurgeonRules.SUMMON_AT:
				_summoned = true
				var sr: SurgeonRound = game.rounds.surgeon if game and game.rounds else null
				if sr:
					sr.srv_summon(self)
			if action_time >= SurgeonRules.SURGERY_TIME:
				_end_action()
		Action.ROAR:
			if not _shock_done and action_time >= SurgeonRules.ROAR_SHOCK_AT:
				_shock_done = true
				_shock()
			if action_time >= SurgeonRules.ROAR_TIME:
				_end_action()
	if stop:
		velocity.x = move_toward(velocity.x, 0.0, 20.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 20.0 * delta)
	velocity.y = 0.0
	move_and_slide()
	if _multilevel:
		_follow_floor()
	elif global_position.y != 0.0:
		global_position.y = 0.0
	anim_speed = Vector2(velocity.x, velocity.z).length()


func _face_target(delta: float, rate: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var to := target.global_position - global_position
	to.y = 0.0
	if to.length() > 0.1:
		yaw = lerp_angle(yaw, atan2(to.x, to.z), 1.0 - exp(-delta * rate))
		rotation.y = yaw


## Une entaille : joueurs dans l'arc devant lui.
func _slash_damage() -> void:
	var fwd := Vector3(sin(yaw), 0.0, cos(yaw))
	for p: Player in game.players.values():
		if not _is_target_valid(p):
			continue
		var rel := p.global_position - global_position
		if absf(rel.y) > LEVEL_TOLERANCE or not SurgeonRules.in_slash_arc(rel, fwd):
			continue
		slash_hits += 1
		game.combat.damage_player(p.peer_id, SurgeonRules.SLASH_DAMAGE, global_position + Vector3.UP * 1.4, self)
		player_slashed.emit(p.peer_id)


## Éventail de scalpels vers la cible (SurgeonScalpels : visibles de tous).
func _throw() -> void:
	throws += 1
	var sr: SurgeonRound = game.rounds.surgeon if game and game.rounds else null
	if sr == null:
		return
	var fwd := Vector3(sin(yaw), 0.0, cos(yaw))
	var side := Vector3(fwd.z, 0.0, -fwd.x)
	var origin := global_position + Vector3.UP * SurgeonRules.THROW_HEIGHT + fwd * 0.35 - side * 0.3
	var aim := origin + fwd * 10.0
	if target and is_instance_valid(target):
		aim = target.global_position + Vector3.UP * 1.1
	var n := SurgeonRules.throw_count(rage)
	var vels := PackedVector3Array()
	for d in SurgeonRules.fan_dirs(aim - origin, n):
		vels.append(SurgeonRules.throw_velocity(origin, aim, d))
	sr.scalpels.srv_throw(self, origin, vels)
	scalpels_thrown.emit(n)


## Onde de choc du changement de phase : dégâts et projection alentour.
func _shock() -> void:
	var n := 0
	for p: Player in game.players.values():
		if not _is_target_valid(p):
			continue
		var rel := p.global_position - global_position
		if not SurgeonRules.in_shock(rel):
			continue
		n += 1
		game.combat.damage_player(p.peer_id, SurgeonRules.SHOCK_DAMAGE, global_position + Vector3.UP * 1.2, self)
		p.srv_knockback(SurgeonRules.shock_velocity(rel), SurgeonRules.SHOCK_TIME)
	shock_wave.emit(n)


func _end_action() -> void:
	_repath_t = 0.0
	_set_action(Action.NONE)


func _set_action(a: int) -> void:
	if a == Action.ROAR:
		rage = true
	action = a
	action_time = 0.0
	if a == Action.SLASH:
		_slash_done = 0
		combos += 1
	elif a == Action.SURGERY:
		_summoned = false
	elif a == Action.ROAR:
		_shock_done = false
	_on_action(a)
	action_started.emit(a)
	if Net.is_online() and multiplayer.has_multiplayer_peer() and not multiplayer.get_peers().is_empty():
		_cl_action.rpc(a, rage)


## Coincé : recalcul du chemin, sans secousse (il pèse son poids de boss).
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
		# Arrivée : rire étouffé derrière le masque.
		Audio.play_3d("surgeon_laugh", global_position + Vector3.UP * 2.0, -2.0, 0.05, 3)
	_life_t += maxf(delta, 0.0001)
	if state == State.DEAD:
		_process_death(delta)
		return
	if not server_side:
		_interpolate()
		_state_time += delta
		action_time += delta
		if not _net_actions.is_empty():
			var e: Array = _net_actions.pop_front()
			action = int(e[0])
			rage = bool(e[1])
			action_time = 0.0
			_on_action(action)
	_groan(delta)
	_action_fx(delta)
	_heartbeat(delta)
	_pose_accum += delta
	var step := _mgr.pose_step(global_position) if _mgr else 0.0
	if _pose_accum >= step:
		_update_pose(_pose_accum)
		_pose_accum = 0.0
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 6.0, 0.0)
		mesh.set_instance_shader_parameter("hit_flash", _flash)


## Position de la lame du grand scalpel (main droite, devant le poing).
func blade_position() -> Vector3:
	if skel == null or not bones.has("forearm_r"):
		return global_position + Vector3.UP * 1.0
	var t := skel.global_transform * skel.get_bone_global_pose(bones.forearm_r)
	return t * Vector3(0.0, -0.66, 0.4)


## Début d'une action : sons, effets, bandeaux (toutes les machines).
func _on_action(a: int) -> void:
	_whoosh = 0
	if a != Action.NONE:
		print("[Chirurgien] %d : %s%s (%s)" % [id, ["poursuite", "préparation de l'entaille", "entailles", "préparation du lancer",
			"lancer", "opération", "changement de phase"][a], " (enragé)" if rage else "", "serveur" if server_side else "client"])
	if mesh and state != State.DEAD:
		var r := 1 if rage else 0
		mesh.set_instance_shader_parameter("eye_glow", EYE_GLOW[r] * (1.8 if a == Action.SLASH_WINDUP or a == Action.THROW_WINDUP else 1.0))
	var head := global_position + Vector3.UP * 2.1
	var fx: Fx = game.fx_root if game else null
	match a:
		Action.SLASH_WINDUP, Action.THROW_WINDUP:
			# Télégraphe : la lame brille (« chiing »), étincelles en cubes.
			Audio.play_3d("surgeon_glint", head, 0.0, 0.05, 3)
			if fx:
				fx.sparks.burst(blade_position(), Vector3.UP, 10, 2.0, 0.6, 0.35, Color(0.85, 0.95, 1.0), 1.2)
		Action.THROW:
			Audio.play_3d("surgeon_throw", head, 0.0, 0.06, 3)
		Action.SURGERY:
			Audio.play_3d("surgeon_surgery", global_position + Vector3.UP * 1.0, 1.0, 0.04, 3)
			if game and game.hud:
				game.hud.show_banner(SurgeonRound.surgery_text(), 1.6)
		Action.ROAR:
			Audio.play_3d("surgeon_roar", head, 3.0, 0.04, 3)
			if game and game.hud:
				game.hud.show_banner(SurgeonRound.rage_text(), 2.2)
			if mesh:
				mesh.set_instance_shader_parameter("eye_glow", EYE_GLOW[1])


## Effets continus : sifflement des entailles, onde de choc, mains de
## l'opération (étincelles, sang), patients qui sortent de terre.
func _action_fx(_delta: float) -> void:
	var fx: Fx = game.fx_root if game else null
	match action:
		Action.SLASH:
			var i := int(floor(action_time / SurgeonRules.SLASH_TIME))
			if i < SurgeonRules.slash_hits(rage) and i >= _whoosh:
				_whoosh = i + 1
				Audio.play_3d("surgeon_slash", global_position + Vector3.UP * 1.5, 0.0, 0.08, 4)
				if fx:
					fx.sparks.burst(blade_position(), Vector3(sin(yaw), 0.2, cos(yaw)), 6, 3.0, 0.5, 0.25, Color(0.9, 0.95, 1.0), 1.0)
		Action.ROAR:
			if _whoosh == 0 and action_time >= SurgeonRules.ROAR_SHOCK_AT:
				_whoosh = 1
				Audio.play_3d("brancard_impact", global_position + Vector3.UP * 0.3, 0.0, 0.05, 3)
				_shock_ring()
		Action.SURGERY:
			if _whoosh < 6 and action_time >= 0.3 + _whoosh * 0.45:
				_whoosh += 1
				if fx:
					var hands := global_position + Vector3(sin(yaw), 0.0, cos(yaw)) * 0.7 + Vector3.UP * 0.9
					fx.blood.burst(hands, Vector3.UP, 5, 1.6, 0.6, 0.6, Color(0.45, 0.04, 0.03), 1.0)
					fx.sparks.burst(hands, Vector3.UP, 4, 1.4, 0.6, 0.25, Color(0.9, 0.95, 1.0), 1.0)


## Onde de choc : anneau de poussière et de gravats au sol, secousse de la vue.
func _shock_ring() -> void:
	var fx: Fx = game.fx_root if game else null
	if fx:
		for i in 16:
			var a := TAU * i / 16.0
			var d := Vector3(cos(a), 0.0, sin(a))
			fx.dust.burst(global_position + d * 0.8 + Vector3.UP * 0.1, d + Vector3.UP * 0.2, 2, 5.0, 0.3, 0.9, Color(0.4, 0.36, 0.33, 0.55), 1.6)
		fx.debris.burst(global_position + Vector3.UP * 0.2, Vector3.UP, 16, 4.5, 1.0, 1.0, Color(0.55, 0.53, 0.5), 1.2)
	if game and game.local_player:
		var dist := game.local_player.global_position.distance_to(global_position)
		if dist < 14.0:
			var amp := 0.08 * (1.0 - dist / 14.0)
			game.local_player.add_flinch(Vector2(randf_range(-amp, amp), amp))


## Battements du cœur mutant : lueur qui pulse (double battement), son
## proche ; plus vite et plus fort une fois enragé.
func _heartbeat(delta: float) -> void:
	var r := 1 if rage else 0
	_beat_t += delta
	var period: float = BEAT[r]
	if _beat_t >= period:
		_beat_t -= period
		var ear: Variant = Audio.listener_position()
		if ear != null and global_position.distance_to(ear) < BEAT_HEAR:
			Audio.play_3d("surgeon_heartbeat", head_position(), -6.0 + 3.0 * r, 0.03, 2)
	var ph := _beat_t / period
	var pulse := exp(-pow((ph - 0.05) * 14.0, 2.0)) + 0.7 * exp(-pow((ph - 0.25) * 14.0, 2.0))
	if mesh:
		mesh.set_instance_shader_parameter("heart_glow", HEART_GLOW[r] * (0.45 + 0.75 * pulse))


func play_attack() -> void:
	pass


## Mort : il porte la main à son cœur, titube et tombe en arrière d'un bloc.
func die(_dir: Vector3, _headshot: bool) -> void:
	if state == State.DEAD:
		return
	state = State.DEAD
	_state_time = 0.0
	_death_t = 0.0
	action = Action.NONE
	collision_layer = 0
	collision_mask = 1
	for a: Area3D in [hit_body, hit_head, hit_skull] + hit_arms + hit_upper_arms:
		a.collision_layer = 0
		a.get_child(0).set_deferred("disabled", true)
	if _body_shape:
		_body_shape.set_deferred("disabled", true)
	velocity = Vector3.ZERO
	set_physics_process(false)
	clear_snapshots()
	Audio.play_3d("surgeon_death", global_position + Vector3.UP * 2.0, 3.0, 0.03, 3)
	var fx: Fx = game.fx_root if game else null
	if fx:
		fx.blood_hit(head_position(), Vector3.UP, 4.0)


func _process_death(delta: float) -> void:
	var before := _death_t
	_death_t += delta
	if before <= SurgeonAnim.DEATH_SETTLE + 0.1:
		SurgeonAnim.apply(skel, bones, SurgeonAnim.pose(_gait, 0.0, _life_t, Action.NONE, 0.0, rage, _death_t))
	# Le cœur s'éteint pendant la chute.
	if mesh and before <= SurgeonAnim.DEATH_STAGGER + SurgeonAnim.DEATH_FALL:
		var k := clampf(_death_t / (SurgeonAnim.DEATH_STAGGER + SurgeonAnim.DEATH_FALL), 0.0, 1.0)
		mesh.set_instance_shader_parameter("heart_glow", 1.6 * (1.0 - k) + 0.6 * sin(_death_t * 30.0) * (1.0 - k))
	var land := SurgeonAnim.DEATH_STAGGER + SurgeonAnim.DEATH_FALL * 0.9
	if before < land and _death_t >= land:
		var at := global_position - Vector3(sin(yaw), 0.0, cos(yaw)) * 1.1
		Audio.play_3d("brancard_impact", at, -2.0, 0.1, 3)
		Audio.play_3d("surgeon_scalpel_hit", global_position + Vector3.UP * 0.2, 0.0, 0.1, 3)
		var fx: Fx = game.fx_root if game else null
		if fx:
			fx.dust.burst(at + Vector3.UP * 0.1, Vector3.UP, 16, 2.2, 1.2, 1.0, Color(0.3, 0.28, 0.25, 0.55), 2.0)
			fx.blood_decal(at + Vector3.UP * 0.1, Vector3.UP, 2.0)
	if _death_t > S_DISSOLVE_DELAY:
		var k := clampf((_death_t - S_DISSOLVE_DELAY) / S_DISSOLVE_TIME, 0.0, 1.0)
		SurgeonModel.set_dissolve(mesh, k)
		if before <= S_DISSOLVE_DELAY:
			mesh.set_instance_shader_parameter("eye_glow", 0.0)
			mesh.set_instance_shader_parameter("heart_glow", 0.0)
		if k >= 1.0:
			skel.visible = false


func _groan(delta: float) -> void:
	_groan_t -= delta
	if _groan_t > 0.0:
		return
	_groan_t = randf_range(3.0, 6.0)
	if action == Action.NONE and state != State.EMERGE:
		Audio.play_3d("surgeon_groan_%d" % (1 + randi() % 2), global_position + Vector3.UP * 2.0, -3.0, 0.08, 3)


func _update_pose(delta: float) -> void:
	if skel == null:
		return
	var spd := anim_speed
	_gait += delta * ((3.0 if rage else 2.4) + spd * 0.5)
	var step := int(floor(_gait / PI))
	if step != _last_step:
		_last_step = step
		if spd > 0.3 and state != State.EMERGE:
			var ear: Variant = Audio.listener_position()
			if ear != null and global_position.distance_to(ear) < 22.0:
				Audio.play_3d("surgeon_step_%d" % (1 + step % 2), global_position, -6.0, 0.08, 6)
	var p := SurgeonAnim.pose(_gait, spd / SurgeonRules.walk_speed(rage), _life_t, action, action_time, rage)
	SurgeonAnim.apply(skel, bones, p)
