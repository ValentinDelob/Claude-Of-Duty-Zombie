class_name Zombie
extends CharacterBody3D
## Zombie. Le SERVEUR simule (IA, déplacement, santé) ; les clients n'ont qu'une
## marionnette interpolée à partir des instantanés du ZombieManager, avec des
## hitboxes pour que le tireur puisse viser localement.

## BARRIER : marche vers sa fenêtre et en arrache les planches ; VAULT : l'enjambe.
enum State { EMERGE, IDLE, CHASE, ATTACK, DEAD, BARRIER, VAULT }

## Vitesses par classe (m/s) : marcheur, trotteur, coureur, sprinteur.
const SPEEDS := [1.25, 2.3, 3.7, 5.0]
## Écart entre la capsule de collision et le sol (déplacement flottant).
const FLOOR_GAP := 0.04
## Décollement de la capsule sur les cartes à plusieurs niveaux.
const STEP_GAP := 0.3
## Animation hors champ ou lointaine : cadence réduite (secondes entre deux poses).
const POSE_STEP_OFFSCREEN := 1.0 / 20.0
const POSE_STEP_FAR := 1.0 / 60.0
const POSE_STEP_VERY_FAR := 1.0 / 30.0
## Les membres d'un corps ont fini de retomber après ce délai.
const DEATH_SETTLE_TIME := 1.5
const RADIUS := 0.3
const HEIGHT := 1.75
const EMERGE_TIME := 1.4
## Couche physique « zombies ».
const BODY_LAYER := 1 << 2
const INTERP_DELAY := 0.12
## Bit du code d'animation (anim_code) : pause « de folie » entre deux planches.
const FRENZY_BIT := 1 << 5
const HITBOX_LAYER := 1 << 3
const ATTACK_RANGE := 1.25
const ATTACK_TIME := 0.9
## En dessous de cette distance, poursuite directe si la ligne de vue est dégagée.
const DIRECT_RANGE := 12.0
const ATTACK_HIT_TIME := 0.42
const DISSOLVE_DELAY := 2.4
const DISSOLVE_TIME := 1.4

var id := 0
var variant := 0
var speed_class := 0
var server_side := false
var state: State = State.EMERGE
var yaw := 0.0
var health := 150
var max_health := 150
var speed_mult := 1.0
var target: Player
## Serveur : attiré par un SINGE-TAMBOUR (ThrowableSystem.lure_for).
var lured := false
## Fenêtre à franchir avant d'entrer dans la zone (null : déjà dedans).
var barricade: Barricade
## Arrachage à la fenêtre (BarricadeRules.tear_tick) : temps écoulé dans la
## phase en cours (agrippe-tire, ou pause « de folie » si `tear_frenzy`).
## Serveur : fait foi ; marionnette : bit FRENZY_BIT du code d'animation,
## `tear_t` recompté sur place (purement visuel).
var tear_t := 0.0
var tear_frenzy := false
## Serveur : durée de la pause en cours.
var tear_pause := 0.0
var _vault_from := Vector3.ZERO
var _vault_to := Vector3.ZERO
## Membres arrachés (masque ZombieGibs) ; temps écoulé depuis la chute du
## RAMPANT (< 0 : debout). Toutes les machines (ZombieManager._cl_gib).
var gibs := 0
var crawl_t := -1.0

var _path := PackedVector3Array()
var _path_i := 0
var _repath_t := 0.0
## Escalier de chaque point du chemin (MapNav.last_lane_marks : 0 = aucun,
## k + 1 = couloir d'ancres k). Les points d'un couloir ne sont jamais sautés.
var _marks := PackedByteArray()
## Séparation réduite sur un escalier : la horde monte en file sur son couloir.
const LANE_SEPARATION := 0.35
## Accélération de virage sur un escalier (m/s², 12 ailleurs).
const LANE_TURN := 30.0
## Vitesse au plus (m/s) à l'approche d'un virage serré d'escalier (palier
## d'un L ou d'un U) : un sprinteur ne part plus vers le bord du palier.
const LANE_CORNER_SPEED := 3.0
## Recul (part de la direction) d'un zombie qui cède le passage (give_way).
const GIVE_WAY_BACK := 0.35
## Portée (au carré, m²) de la file sur un escalier : on cède à un voisin à
## moins de 0,67 m.
const YIELD_RANGE2 := 0.45
var _lane_speed := 1.0
## Ligne de vue vers la cible, recalculée toutes les LOS_PERIOD secondes.
const LOS_PERIOD := 0.1
var _los_t := 0.0
var _los_ok := false
## Carte à plusieurs niveaux : le zombie suit le sol (sinon y = 0).
var _multilevel := false
## Écart de hauteur au-delà duquel une cible est « à un autre niveau ».
const LEVEL_TOLERANCE := 1.2
var _stuck_t := 0.0
var _stuck_pos := Vector3.ZERO
var _attack_hit_done := false
var _groan_t := randf_range(ZombieVoice.FIRST_DELAY.x, ZombieVoice.FIRST_DELAY.y)
var _last_vocal := 0
var _step_i := 0
var _headless := false
var _low_move_t := 0.0
var _stuck_sample_t := 0.0
var _stuck_sample_pos := Vector3.ZERO

## Animation (lue sur toutes les machines).
var anim_speed := 0.0      # vitesse horizontale actuelle (m/s)
var _phase := 0.0
var _state_time := 0.0
var _attack_t := -1.0
var _death_t := -1.0
var _death_dir := 1.0
var _flash := 0.0
var _head_tilt := 0.0
## Clients : instantanés reçus (tampon circulaire, voir push_snapshot).
const SNAP_CAP := 12
var _snap_t := _packed_f64(SNAP_CAP)
var _snap_pos := _packed_v3(SNAP_CAP)
var _snap_yaw := _packed_f64(SNAP_CAP)
var _snap_code := _packed_i32(SNAP_CAP)
var _snap_head := 0
var _snap_n := 0
var _last_vel := Vector3.ZERO

var skel: Skeleton3D
var mesh: MeshInstance3D
var bones: Dictionary
## Animations procédurales (poses, morts) : ZombieAnim.
var anim: ZombieAnim
var hit_body: Area3D
var hit_head: Area3D
## Avant-bras (zone 2 : dégâts du corps) : les bras tendus dépassent de la
## capsule du corps ; ces hitboxes suivent les os pour qu'un tir au bras
## touche vraiment le bras (et l'arrache, comme BO1).
var hit_arms: Array[Area3D] = []
var _body_shape: CollisionShape3D
var _mgr: ZombieManager
## Partie de ce zombie : celle de son ZombieManager (lue dans _ready), null
## hors partie (zombie seul des tests unitaires). Jamais Game.instance ici.
var game: Game
## Temps écoulé depuis la dernière pose écrite (animation à cadence réduite).
var _pose_accum := 0.0
## Rayon de sol réutilisé par _follow_floor (cartes à étages).
var _floor_q: PhysicsRayQueryParameters3D

## Accès publics pour les animations (ZombieAnim, ZombieGibs) : mêmes valeurs
## que les champs privés ci-dessus.
## Phase de la démarche (rad), avancée par l'animation.
var gait_phase: float:
	get:
		return _phase
	set(value):
		_phase = value
## Temps passé dans l'état courant (s), lecture seule.
var state_time: float:
	get:
		return _state_time
## Avancement de l'attaque (0 -> 1), -1 hors attaque ; l'animation l'avance.
var attack_t: float:
	get:
		return _attack_t
	set(value):
		_attack_t = value
## L'attaque en cours part d'une fenêtre ou d'une porte barricadée : le
## zombie passe le bras par le trou des planches (pose propre, ZombieAnim).
var attack_through := false
## Inclinaison de tête propre à ce zombie (rad).
var head_tilt: float:
	get:
		return _head_tilt
## Forme de collision du corps (capsule), ou null avant _ready.
var body_shape: CollisionShape3D:
	get:
		return _body_shape


func setup(zid: int, zvariant: int, zspeed: int, is_server: bool) -> void:
	id = zid
	variant = zvariant
	speed_class = zspeed
	server_side = is_server
	name = "Z%d" % zid


func _ready() -> void:
	_mgr = get_parent() as ZombieManager
	game = _mgr.game if _mgr else null
	_multilevel = map_is_multilevel()
	_update_solidity()
	collision_mask = 1 | (1 << 1) | (1 << 2) | Barricade.BARRIER_LAYER  # monde, joueurs, zombies, fenêtres
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = RADIUS
	cap.height = HEIGHT
	cs.shape = cap
	# Cartes plates : déplacement « flottant » à y = 0, capsule légèrement
	# décollée du sol. move_and_slide ne gère alors ni contact ni accroche au
	# sol (une bonne part de son coût) pour la même trajectoire.
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	# 3 glissements suffisent (angle de deux murs) ; les 6 par défaut
	# doublaient le coût des zombies coincés dans la horde.
	max_slides = 3
	# Cartes à étages : capsule plus haute que les petits rebords (<= 0,3 m,
	# comme la marche maximale du navmesh) ; le sol est suivi par _follow_floor.
	cs.position.y = HEIGHT * 0.5 + floor_gap()
	_body_shape = cs
	add_child(cs)

	skel = ZombieModel.build(variant)
	add_child(skel)
	mesh = skel.get_node("Mesh")
	bones = RigBuilder.bone_indices(skel)
	var rng := RandomNumberGenerator.new()
	rng.seed = variant
	_head_tilt = rng.randf_range(-0.35, 0.35)
	_phase = rng.randf() * TAU
	anim = ZombieAnim.new(self)

	hit_body = _make_hitbox(0, CapsuleShape3D.new())
	(hit_body.get_child(0).shape as CapsuleShape3D).radius = 0.28
	(hit_body.get_child(0).shape as CapsuleShape3D).height = 1.35
	hit_body.position.y = 0.8
	add_child(hit_body)
	var att := BoneAttachment3D.new()
	att.bone_name = "head"
	skel.add_child(att)
	var sph := SphereShape3D.new()
	sph.radius = 0.16
	hit_head = _make_hitbox(1, sph)
	hit_head.position = Vector3(0, 0.13, 0.01)
	att.add_child(hit_head)
	for side in ["l", "r"]:
		var arm_att := BoneAttachment3D.new()
		arm_att.bone_name = "forearm_" + side
		skel.add_child(arm_att)
		var arm_cap := CapsuleShape3D.new()
		arm_cap.radius = 0.075
		arm_cap.height = 0.42
		var ha := _make_hitbox(2, arm_cap)
		ha.name = "HitArm_" + side
		# L'avant-bras s'étend selon -Y de l'os : la capsule couvre avant-bras et main.
		ha.position = Vector3(0, -0.2, 0)
		arm_att.add_child(ha)
		hit_arms.append(ha)

	if not server_side:
		# Marionnette : pas de simulation physique locale.
		set_physics_process(false)
	_update_pose(0.0)


func _make_hitbox(zone: int, shape: Shape3D) -> Area3D:
	var a := Area3D.new()
	a.name = "HitHead" if zone == 1 else "HitBody"
	a.collision_layer = HITBOX_LAYER
	a.collision_mask = 0
	a.monitoring = false
	a.monitorable = false
	a.set_meta("zombie_id", id)
	a.set_meta("zone", zone)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	a.add_child(cs)
	return a


func is_alive() -> bool:
	return state != State.DEAD


## Code d'animation envoyé dans les instantanés : état (3 bits) | vitesse
## (2 bits) | pause « de folie » à la fenêtre (FRENZY_BIT).
func anim_code() -> int:
	return int(state) | (speed_class << 3) | (FRENZY_BIT if tear_frenzy and state == State.BARRIER else 0)


# --------------------------------------------------------------------------
# Serveur : simulation
# --------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_state_time += delta
	match state:
		State.EMERGE:
			if _state_time >= EMERGE_TIME:
				_set_state(State.CHASE)
		State.CHASE:
			_chase(delta)
		State.ATTACK:
			_attack(delta)
		State.BARRIER:
			if is_instance_valid(barricade):
				barricade.srv_zombie_barrier(self, delta)
			else:
				barricade = null
				_set_state(State.CHASE)
		State.VAULT:
			_vault()
		State.DEAD:
			return
	# Déplacement au sol : y = 0 sur les cartes plates ; sur les cartes à
	# plusieurs niveaux, le zombie suit le sol (escaliers, pentes, balcons).
	velocity.y = 0.0
	if state != State.EMERGE and state != State.VAULT:
		move_and_slide()
		if _multilevel:
			_follow_floor()
		elif global_position.y != 0.0:
			global_position.y = 0.0
	anim_speed = Vector2(velocity.x, velocity.z).length()
	# Mesure de blocage sur des fenêtres d'une seconde (déplacement réel).
	_stuck_sample_t += delta
	if _stuck_sample_t >= 1.0:
		if state == State.CHASE and not lured and global_position.distance_to(_stuck_sample_pos) < 0.6:
			_low_move_t += _stuck_sample_t
		else:
			_low_move_t = 0.0
		_stuck_sample_t = 0.0
		_stuck_sample_pos = global_position


## Poursuite : ligne droite si le joueur est visible et proche, sinon chemin
## A* recalculé régulièrement. Séparation entre zombies pour éviter les amas.
func _chase(delta: float) -> void:
	if game == null or game.nav == null:
		return
	_repath_t -= delta
	# SINGE-TAMBOUR : un leurre actif passe avant tous les joueurs.
	var lure: Vector3 = game.throwables.lure_for(self) if game.throwables else Vector3.INF
	lured = lure != Vector3.INF
	if lured:
		_chase_lure(lure, delta)
		return
	if _repath_t <= 0.0 or target == null or not is_instance_valid(target) or not _is_target_valid(target):
		target = _nearest_player()
	var desired := Vector3.ZERO
	if target:
		var tpos := target.global_position
		var to := tpos - global_position
		var dy := absf(to.y)
		to.y = 0.0
		var dist := to.length()
		if dist < ATTACK_RANGE and dy < LEVEL_TOLERANCE:
			_start_attack()
			return
		var dir := Vector3.ZERO
		# Ligne de vue mise en cache (LOS_PERIOD) : le tracé sur la grille à
		# chaque pas de chaque zombie pesait dans la horde, pour une réaction
		# identique à l'œil.
		_los_t -= delta
		if _los_t <= 0.0:
			_los_t = LOS_PERIOD
			# Jamais en ligne droite par-dessus le bord d'un escalier : par ses ancres.
			_los_ok = dist < DIRECT_RANGE and game.nav.world_line_clear(global_position, tpos) \
				and not game.nav.crosses_stairs(global_position, tpos)
		# En ligne droite seulement au même niveau (sinon : escaliers, par le chemin).
		var sep_k := 0.9
		_lane_speed = 1.0
		if _los_ok and dist < DIRECT_RANGE and dy < 0.9:
			dir = to / dist
			_path.clear()
			_marks.clear()
		else:
			if _repath_t <= 0.0 or _path_i >= _path.size():
				_set_path(game.nav.find_path(global_position, tpos, lane_bias()))
				_repath_t = randf_range(0.35, 0.7)
			dir = _follow_path()
			if _on_lane():
				sep_k = LANE_SEPARATION
			if _mark_at(_path_i) > 0:
				# Vers un escalier ou dessus : file derrière celui qui est juste
				# devant (pas de bouchon de la horde qui pousse à l'entrée étroite).
				var give := _lane_yield(dir, _path[_path_i] if _path_i < _path.size() else global_position)
				if give != Vector3.ZERO:
					_lane_speed *= 0.5
					dir = give_way(dir, give)
		if _repath_t <= 0.0:
			_repath_t = randf_range(0.35, 0.7)
		desired = (dir + _separation() * sep_k).normalized() * move_speed() * speed_mult * _lane_speed
		_check_stuck(delta)
	# Sur un escalier, virage net aux paliers (pas d'élan qui porte au bord).
	var horiz := Vector3(velocity.x, 0.0, velocity.z).move_toward(desired, (LANE_TURN if _on_lane() else 12.0) * delta)
	velocity.x = horiz.x
	velocity.z = horiz.z
	if horiz.length() > 0.1:
		# Le modèle regarde vers +Z.
		yaw = lerp_angle(yaw, atan2(horiz.x, horiz.z), 1.0 - exp(-delta * 8.0))
	rotation.y = yaw


## Serveur : marche vers le SINGE-TAMBOUR (chemin A*) puis l'encercle.
## Appelé par _chase seulement (partie et navigation présentes).
func _chase_lure(pos: Vector3, delta: float) -> void:
	var to := pos - global_position
	to.y = 0.0
	var dist := to.length()
	var dir := Vector3.ZERO
	if dist > ThrowableRules.LURE_STOP:
		if dist < DIRECT_RANGE and game.nav.world_line_clear(global_position, pos) and not game.nav.crosses_stairs(global_position, pos):
			dir = to / dist
			_path.clear()
			_marks.clear()
		else:
			if _repath_t <= 0.0 or _path_i >= _path.size():
				_set_path(game.nav.find_path(global_position, pos, lane_bias()))
				_repath_t = randf_range(0.35, 0.7)
			while _path_i < _path.size() and (_flat_dist(_path[_path_i]) < 0.45 or (_mark_at(_path_i) > 0 and _lane_point_passed(_path_i))):
				_path_i += 1
			if _path_i < _path.size():
				var wp := _path[_path_i] - global_position
				wp.y = 0.0
				dir = wp.normalized()
				if _on_lane():
					dir = (dir + game.nav.lane_push(_mark_at(_path_i), global_position) * 1.5).normalized()
	if _repath_t <= 0.0:
		_repath_t = randf_range(0.35, 0.7)
	var desired: Vector3 = (dir + _separation() * (LANE_SEPARATION if _on_lane() else 0.9)).limit_length(1.0) * move_speed() * speed_mult
	var horiz := Vector3(velocity.x, 0.0, velocity.z).move_toward(desired, 12.0 * delta)
	velocity.x = horiz.x
	velocity.z = horiz.z
	# Tourné vers le singe.
	if dist > 0.05:
		yaw = lerp_angle(yaw, atan2(to.x, to.z), 1.0 - exp(-delta * 8.0))
	rotation.y = yaw


## Vitesse de poursuite (m/s) : classe de vitesse, ou reptation d'un RAMPANT.
func move_speed() -> float:
	if crawl_t >= 0.0:
		return ZombieGibs.crawl_speed(crawl_t)
	return SPEEDS[speed_class]


func is_crawler() -> bool:
	return crawl_t >= 0.0


func _flat_dist(p: Vector3) -> float:
	return Vector2(p.x - global_position.x, p.z - global_position.z).length()


## Répulsion douce des zombies voisins (rayon √0,8 ≈ 0,9 m). Seules les 9
## cases de la grille spatiale du ZombieManager autour du zombie sont lues,
## au lieu de tous les zombies vivants.
func separation() -> Vector3:
	return _separation()


func _separation() -> Vector3:
	var push := Vector3.ZERO
	# _mgr : le parent lu dans _ready (un zombie n'est jamais déplacé).
	if _mgr == null:
		return push
	var grid := _mgr.separation_grid()
	var pos := global_position
	# Clés des 9 cases (ZombieManager.grid_key) : celle du coin, puis +1 par
	# colonne et +GRID_ROW par rangée ; mêmes cases, même ordre qu'avant.
	var row0 := ZombieManager.grid_key(floori(pos.x / ZombieManager.GRID_CELL) - 1, floori(pos.z / ZombieManager.GRID_CELL) - 1)
	for gz in 3:
		var row := row0 + gz * ZombieManager.GRID_ROW
		for gx in 3:
			var bucket: Array = grid.get(row + gx, ZombieManager.EMPTY)
			# Sa propre position (distance nulle) est écartée par le test l2.
			for op: Vector3 in bucket:
				var d := pos - op
				if absf(d.y) > 1.0:
					continue  # autre niveau (balcon, escalier)
				d.y = 0.0
				var l2 := d.length_squared()
				if l2 < 0.8 and l2 > 0.0001:
					push += d / l2 * 0.25
	return push.limit_length(1.0)


## File sur un couloir d'escalier : direction (à plat, unitaire) du zombie à
## laisser passer, ZERO sinon. On cède à un zombie juste à côté ou devant (à
## moins de 0,67 m, dans le demi-plan de la direction suivie) et plus avancé
## sur le couloir (StairLane.left_to : reste à parcourir jusqu'au bout du
## couloir, même mesure pour toute la horde : de deux voisins, un seul cède
## à l'autre). Ancienne règle (plus près de SON point visé de 0,2 m au moins,
## dans un cône de 45°, et seulement ralenti) : deux zombies côte à côte à
## l'ouverture d'un escalier de service (1 m) ne se cédaient pas le passage,
## ou celui qui cédait avançait encore contre l'autre ; poussés vers l'axe,
## ils se coinçaient et toute la horde restait en haut des marches.
func _lane_yield(dir: Vector3, goal: Vector3) -> Vector3:
	if _mgr == null or dir == Vector3.ZERO or game == null or game.nav == null:
		return Vector3.ZERO
	var mark := _mark_at(_path_i)
	var j := _path_i
	while j + 1 < _path.size() and _mark_at(j + 1) == mark:
		j += 1
	var exit := _path[j] if j < _path.size() else goal
	var mine := game.nav.lane_left(mark, global_position, exit)
	if mine == INF:
		return Vector3.ZERO
	var grid := _mgr.separation_grid()
	var pos := global_position
	var best := INF
	var out := Vector3.ZERO
	var row0 := ZombieManager.grid_key(floori(pos.x / ZombieManager.GRID_CELL) - 1, floori(pos.z / ZombieManager.GRID_CELL) - 1)
	for gz in 3:
		var row := row0 + gz * ZombieManager.GRID_ROW
		for gx in 3:
			var bucket: Array = grid.get(row + gx, ZombieManager.EMPTY)
			for op: Vector3 in bucket:
				var d := op - pos
				if absf(d.y) > 1.0:
					continue
				d.y = 0.0
				var l2 := d.length_squared()
				if l2 >= best:
					continue
				if l2 > 0.0001 and l2 <= YIELD_RANGE2 and yields_to(d, dir, mine, game.nav.lane_left(mark, op, exit)):
					best = l2
					out = d / sqrt(l2)
	return out


## Règle de la file (_lane_yield) : un zombie de direction `dir`, à qui il
## reste `mine` m de couloir, cède-t-il à un voisin à `d` (à plat, à moins de
## √YIELD_RANGE2 m) à qui il en reste `theirs` ? Devant ou à côté, et plus
## avancé que soi. Deux voisins ne se cèdent jamais l'un à l'autre, et le
## plus avancé d'un groupe ne cède à personne (tests/test_stairs.gd).
static func yields_to(d: Vector3, dir: Vector3, mine: float, theirs: float) -> bool:
	return d.dot(dir) > 0.0 and theirs < mine


## Direction d'un zombie qui cède le passage au zombie dans la direction
## `give` (_lane_yield) : plus rien vers lui, et un léger recul qui lui
## laisse la place (il ne reste pas coincé entre celui qui cède et le bord).
static func give_way(dir: Vector3, give: Vector3) -> Vector3:
	if give == Vector3.ZERO:
		return dir
	return dir - give * maxf(dir.dot(give), 0.0) - give * GIVE_WAY_BACK


## Coincé (contre un autre zombie, un angle...) : recalcul immédiat du chemin.
func _check_stuck(delta: float) -> void:
	_stuck_t += delta
	if _stuck_t < 1.2:
		return
	if global_position.distance_to(_stuck_pos) < 0.3:
		_repath_t = 0.0
		velocity += Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * 2.0
	_stuck_pos = global_position
	_stuck_t = 0.0


func _start_attack() -> void:
	_set_state(State.ATTACK)
	_attack_hit_done = false
	velocity.x = 0.0
	velocity.z = 0.0
	play_attack()


func _attack(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 20.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 20.0 * delta)
	if target and is_instance_valid(target):
		var to := target.global_position - global_position
		yaw = lerp_angle(yaw, atan2(to.x, to.z), 1.0 - exp(-delta * 10.0))
		rotation.y = yaw
	if not _attack_hit_done and _state_time >= ATTACK_HIT_TIME:
		_attack_hit_done = true
		if target and is_instance_valid(target) and _is_target_valid(target):
			var d := target.global_position - global_position
			var dy := absf(d.y)
			d.y = 0.0
			# À travers une fenêtre, le bras passe au-dessus de l'allège.
			if dy < LEVEL_TOLERANCE and d.length() < ATTACK_RANGE + (0.65 if barricade else 0.45):
				# `game` non nul : _is_target_valid l'exige.
				game.combat.damage_player(target.peer_id, Combat.ZOMBIE_DAMAGE, global_position + Vector3.UP * 1.2)
	if _state_time >= ATTACK_TIME:
		_set_state(State.BARRIER if barricade else State.CHASE)


# --------------------------------------------------------------------------
# Fenêtres barricadées (logique dans Barricade)
# --------------------------------------------------------------------------

## Toutes les machines : le zombie est apparu derrière la fenêtre `b`.
func enter_barricade(b: Barricade) -> void:
	barricade = b
	tear_t = 0.0
	tear_frenzy = false
	_set_state(State.BARRIER)
	yaw = atan2(b.inward.x, b.inward.z)
	rotation.y = yaw


## Serveur : coup porté à travers la fenêtre au joueur `target`.
func barrier_attack() -> void:
	_start_attack()


## Serveur : enjambe la fenêtre de `from` (dehors) à `to` (dedans).
func start_vault(from: Vector3, to: Vector3) -> void:
	_vault_from = from
	_vault_to = to
	velocity = Vector3.ZERO
	_set_state(State.VAULT)


func _vault() -> void:
	# Fenêtre ou porte à zombies (battant cassé à mi-hauteur) : on enjambe.
	var k := clampf(_state_time / BarricadeRules.VAULT_TIME, 0.0, 1.0)
	global_position = _vault_from.lerp(_vault_to, ease(k, -1.6))
	if k >= 1.0:
		if is_instance_valid(barricade):
			barricade.srv_vault_done(self)
		barricade = null
		_repath_t = 0.0
		_set_state(State.CHASE)


## Joueur ciblable : vivant et pas intouchable (utilisé aussi par Barricade).
## Hors partie : aucun.
func is_target_valid(p: Player) -> bool:
	return _is_target_valid(p)


func _is_target_valid(p: Player) -> bool:
	if game == null:
		return false
	var pd := game.session.get_data(p.peer_id)
	return pd != null and pd.life == PlayerData.Life.ALIVE and not p.untargetable


func _nearest_player() -> Player:
	var best: Player = null
	var best_d := INF
	if game == null:
		return null
	for p: Player in game.players.values():
		if not _is_target_valid(p):
			continue
		var d: float = p.global_position.distance_squared_to(global_position)
		if d < best_d:
			best_d = d
			best = p
	return best


func _set_state(s: State) -> void:
	state = s
	_state_time = 0.0
	_update_solidity()


## Pendant l'émergence, le corps n'est pas solide : un joueur debout sur le
## point d'apparition n'est ni poussé ni soulevé (les hitboxes restent actives).
func _update_solidity() -> void:
	if state == State.DEAD:
		return
	collision_layer = 0 if state == State.EMERGE else BODY_LAYER


# --------------------------------------------------------------------------
# Clients : interpolation des instantanés
# --------------------------------------------------------------------------

## Tampon circulaire des instantanés : SNAP_CAP derniers au plus, le plus
## ancien à l'indice _snap_head (mêmes valeurs qu'une liste où l'on ajoute à
## la fin et retire au début, sans tableau alloué par instantané).
func push_snapshot(t: float, pos: Vector3, net_yaw: float, code: int) -> void:
	if _snap_n > 0:
		var last := (_snap_head + _snap_n - 1) % SNAP_CAP
		var dt: float = t - _snap_t[last]
		if dt > 0.001:
			_last_vel = (pos - _snap_pos[last]) / dt
			_last_vel.y = 0.0
	var i := (_snap_head + _snap_n) % SNAP_CAP
	if _snap_n < SNAP_CAP:
		_snap_n += 1
	else:
		# Plein : le nouveau remplace le plus ancien.
		_snap_head = (_snap_head + 1) % SNAP_CAP
	_snap_t[i] = t
	_snap_pos[i] = pos
	_snap_yaw[i] = net_yaw
	_snap_code[i] = code


## Nombre d'instantanés en attente d'interpolation.
func snapshot_count() -> int:
	return _snap_n


## Instantané `k` (0 : le plus ancien) : [temps, position, lacet, code].
func snapshot(k: int) -> Array:
	var i := (_snap_head + k) % SNAP_CAP
	return [_snap_t[i], _snap_pos[i], _snap_yaw[i], _snap_code[i]]


func clear_snapshots() -> void:
	_snap_n = 0
	_snap_head = 0


static func _packed_f64(n: int) -> PackedFloat64Array:
	var a := PackedFloat64Array()
	a.resize(n)
	return a


static func _packed_v3(n: int) -> PackedVector3Array:
	var a := PackedVector3Array()
	a.resize(n)
	return a


static func _packed_i32(n: int) -> PackedInt32Array:
	var a := PackedInt32Array()
	a.resize(n)
	return a


func _interpolate() -> void:
	if _snap_n == 0:
		return
	interpolate_at(Time.get_ticks_usec() / 1000000.0 - INTERP_DELAY)


## Pose la marionnette à l'instant `render_t` (horloge des instantanés).
func interpolate_at(render_t: float) -> void:
	if _snap_n == 0:
		return
	while _snap_n >= 2 and _snap_t[(_snap_head + 1) % SNAP_CAP] <= render_t:
		_snap_head = (_snap_head + 1) % SNAP_CAP
		_snap_n -= 1
	var ia := _snap_head
	var a_t: float = _snap_t[ia]
	var pos: Vector3 = _snap_pos[ia]
	var ny: float = _snap_yaw[ia]
	if _snap_n == 1 and render_t > a_t and _last_vel != Vector3.ZERO:
		# Paquet en retard : on prolonge brièvement le dernier mouvement connu
		# au lieu de figer le zombie (max 0,25 s).
		pos = _snap_pos[ia] + _last_vel * minf(render_t - a_t, 0.25)
	if _snap_n >= 2 and render_t > a_t:
		var ib := (ia + 1) % SNAP_CAP
		var b_t: float = _snap_t[ib]
		var t := clampf((render_t - a_t) / maxf(b_t - a_t, 0.001), 0.0, 1.0)
		pos = _snap_pos[ia].lerp(_snap_pos[ib], t)
		ny = lerp_angle(_snap_yaw[ia], _snap_yaw[ib], t)
	var prev := global_position
	global_position = pos
	yaw = ny
	rotation.y = yaw
	var dt := get_process_delta_time()
	if dt > 0.0:
		var v := (pos - prev) / dt
		anim_speed = lerpf(anim_speed, Vector2(v.x, v.z).length(), 0.2)
	var code: int = _snap_code[ia]
	var new_state: State = (code & 7) as State
	speed_class = (code >> 3) & 3
	# Arrachage : la phase (geste / pause) vient du serveur ; le temps dans la
	# phase repart de zéro à chaque changement, et tant que le zombie marche
	# encore vers sa place.
	var frenzy := code & FRENZY_BIT != 0
	if frenzy != tear_frenzy or new_state != State.BARRIER or anim_speed >= 0.4:
		tear_t = 0.0
	tear_frenzy = frenzy
	if new_state != state and state != State.DEAD:
		if new_state == State.ATTACK:
			play_attack()
		state = new_state
		_state_time = 0.0
		_update_solidity()


# --------------------------------------------------------------------------
# Animation procédurale (toutes les machines)
# --------------------------------------------------------------------------

func _process(delta: float) -> void:
	if state == State.DEAD:
		_process_death(delta)
		return
	if not server_side:
		_interpolate()
		_state_time += delta
		tear_t += delta
	_groan(delta)
	if crawl_t >= 0.0:
		crawl_t += delta
	# Pose recalculée à chaque image de près ; hors champ ou au loin, à cadence
	# réduite avec le temps cumulé (même animation, moins d'écritures d'os).
	_pose_accum += delta
	if _mgr == null or _pose_accum >= _mgr.pose_step(global_position):
		_update_pose(_pose_accum)
		_pose_accum = 0.0
		_footstep()
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 6.0, 0.0)
		mesh.set_instance_shader_parameter("hit_flash", _flash)


func flash_hit() -> void:
	_flash = 1.0


func play_attack() -> void:
	_attack_t = 0.0
	attack_through = barricade != null
	Audio.play_3d("zombie_attack_%d" % (1 + randi() % ZombieVoice.ATTACKS), global_position + Vector3.UP * 1.5, 0.0, 0.08, 3, 1.0, ZombieVoice.GROUP)
	_groan_t = maxf(_groan_t, 1.5)


func head_position() -> Vector3:
	return hit_head.global_position


## Mort (toutes les machines). `dir` : direction du coup fatal.
func die(dir: Vector3, headshot: bool) -> void:
	if state == State.DEAD:
		return
	state = State.DEAD
	_state_time = 0.0
	_death_t = 0.0
	var fwd := Vector3(sin(yaw), 0.0, cos(yaw))
	_death_dir = 1.0 if fwd.dot(dir) > 0.0 else -1.0
	if anim:
		anim.start_death(headshot)
	collision_layer = 0
	collision_mask = 1
	hit_body.collision_layer = 0
	hit_head.collision_layer = 0
	# Corps : plus aucune forme dans l'espace physique (hitboxes, capsule).
	hit_body.get_child(0).set_deferred("disabled", true)
	hit_head.get_child(0).set_deferred("disabled", true)
	for ha in hit_arms:
		ha.collision_layer = 0
		ha.get_child(0).set_deferred("disabled", true)
	if _body_shape:
		_body_shape.set_deferred("disabled", true)
	velocity = Vector3.ZERO
	set_physics_process(false)
	clear_snapshots()
	if headshot:
		_headless = true
		skel.set_bone_pose_scale(bones.head, Vector3.ONE * 0.001)
		var neck := skel.global_transform * skel.get_bone_global_pose(bones.neck).origin
		if game:
			game.fx_root.blood_hit(neck, Vector3.UP, 3.0)
		ZombieGibs.head_pop(self, neck, dir)
		Audio.play_3d("headshot", neck, 0.0, 0.08)
	else:
		Audio.play_3d("zombie_death_%d" % (1 + randi() % ZombieVoice.DEATHS), global_position + Vector3.UP * 1.4, -1.0, 0.08, 3, 1.0, ZombieVoice.GROUP)


## Mort projetée (onde de choc du TONNERRE-7) : le corps s'envole à la vitesse
## `vel` calculée par le serveur (vol procédural : ZombieFling).
func die_flung(vel: Vector3) -> void:
	if state == State.DEAD:
		return
	die(vel, false)
	add_child(ZombieFling.new(vel))


func _q(x: float, y := 0.0, z := 0.0) -> Quaternion:
	return Quaternion.from_euler(Vector3(x, y, z))


func _update_pose(delta: float) -> void:
	if skel == null:
		return
	if crawl_t >= 0.0:
		ZombieGibs.crawl_pose(self, delta)
		return
	anim.pose(delta)


## Grognements d'ambiance (cosmétique, non synchronisé).
func _groan(delta: float) -> void:
	_groan_t -= delta
	if _groan_t > 0.0:
		return
	_groan_t = ZombieVoice.interval(speed_class, randf())
	if state == State.EMERGE:
		Audio.play_3d("emerge", global_position, -4.0, 0.1, 2)
		return
	_last_vocal = ZombieVoice.pick(ZombieVoice.vocal_count(speed_class), _last_vocal, randi())
	Audio.play_3d(ZombieVoice.vocal_name(speed_class, _last_vocal), global_position + Vector3.UP * 1.5,
		-3.0, 0.06, 3, 1.0, ZombieVoice.GROUP)


## Pas traînants (de près seulement), un par demi-cycle de marche.
func _footstep() -> void:
	var step := int(floor(_phase / PI))
	if step == _step_i:
		return
	_step_i = step
	if state == State.DEAD or state == State.EMERGE or anim_speed < 0.3:
		return
	var ear: Variant = Audio.listener_position()
	if ear == null or global_position.distance_to(ear) > ZombieVoice.STEP_RANGE:
		return
	Audio.play_3d("zombie_step_%d" % (1 + randi() % ZombieVoice.STEPS), global_position + Vector3.UP * 0.05,
		-9.0 if speed_class < 2 else -6.0, 0.1, 6, 1.0, ZombieVoice.STEP_GROUP)


## Chute, puis dissolution. Le nœud est libéré par ZombieManager (despawn).
func _process_death(delta: float) -> void:
	var before := _death_t
	_death_t += delta
	# Chute et membres qui retombent mollement ; ensuite le corps est immobile
	# (les rotations ont convergé) : plus aucune écriture d'os.
	if before <= DEATH_SETTLE_TIME:
		anim.death(delta, _death_t, _death_dir)
	if before < 0.6 and _death_t >= 0.6:
		Audio.play_3d("body_fall", global_position, -6.0, 0.1, 3)
		if game:
			game.fx_root.blood_decal(global_position + Vector3.UP * 0.1 + Vector3(sin(yaw), 0, cos(yaw)) * _death_dir * 0.8, Vector3.UP, randf_range(0.8, 1.4))
	if _death_t > DISSOLVE_DELAY:
		ZombieModel.set_dissolve(mesh, clampf((_death_t - DISSOLVE_DELAY) / DISSOLVE_TIME, 0.0, 1.0))
		if before <= DISSOLVE_DELAY:
			mesh.set_instance_shader_parameter("eye_glow", 0.0)


## Temps passé quasi immobile en poursuite (serveur) : sert au recyclage.
func stuck_time() -> float:
	return _low_move_t


## Cartes à plusieurs niveaux : pose le zombie sur le sol sous lui (rayon
## vers le bas sur le décor, couche 1). Immobile : rien à faire.
func _follow_floor() -> void:
	if absf(velocity.x) + absf(velocity.z) < 0.01:
		return
	# Requête gardée d'un pas à l'autre (seuls les deux points changent) : même
	# rayon, sans objet alloué par zombie et par pas.
	if _floor_q == null:
		_floor_q = PhysicsRayQueryParameters3D.create(Vector3.ZERO, Vector3.DOWN, 1)
	_floor_q.from = global_position + Vector3.UP * 0.9
	_floor_q.to = global_position + Vector3.DOWN * 1.1
	var hit := get_world_3d().direct_space_state.intersect_ray(_floor_q)
	if not hit.is_empty():
		global_position.y = hit.position.y


## Point de passage déjà dépassé : tout près, et l'un des quatre suivants est
## plus près du zombie que de lui, en vue. Un chemin recalculé en haut d'un
## escalier de KINO repartait du bord du palier, derrière le zombie : il
## faisait demi-tour à chaque recalcul et restait bloqué en haut des marches.
func _waypoint_passed(i: int) -> bool:
	if i + 1 >= _path.size() or _flat_dist(_path[i]) > 1.2:
		return false
	# Couloir d'ancres d'un escalier : on suit chaque point (jamais de raccourci
	# vers un point plus loin, qui couperait l'angle d'un palier ou le bord).
	if _mark_at(i) > 0 or _mark_at(i + 1) > 0:
		return false
	for j in range(i + 1, mini(i + 5, _path.size())):
		var nxt := _path[j]
		if global_position.distance_to(nxt) < _path[i].distance_to(nxt) and game.nav.world_line_clear(global_position, nxt):
			return true
	return false


## Point de passage atteint (à plat, et au même niveau sur les cartes à étages).
func _waypoint_reached(p: Vector3) -> bool:
	return _flat_dist(p) < 0.45 and absf(p.y - global_position.y) < 1.0


## Nouveau chemin (et l'escalier de chacun de ses points).
func _set_path(p: PackedVector3Array) -> void:
	_path = p
	_marks = game.nav.last_lane_marks() if game and game.nav else PackedByteArray()
	_path_i = 0
	# Chemin qui part d'un couloir d'escalier (déjà engagé) : son premier point
	# est là où l'on est (ramené sur le navmesh), jamais un point à rejoindre ;
	# le tronçon suivant est sur le couloir (_on_lane : poussée vers l'axe,
	# séparation réduite). Sans cela, à chaque recalcul, un zombie arrivé à
	# côté de l'ouverture d'un escalier étroit n'était plus ramené vers l'axe.
	if _mark_at(0) > 0 and _path.size() > 1:
		_path_i = 1


func _mark_at(i: int) -> int:
	return _marks[i] if i >= 0 and i < _marks.size() else 0


## Écart latéral de ce zombie sur les couloirs d'ancres des escaliers (-1 à
## 1, tiré de son identifiant : une horde se répartit sur la largeur).
func lane_bias() -> float:
	return fposmod(float(id) * 0.6180339, 1.0) * 2.0 - 1.0


## Le point visé est sur un couloir d'ancres, et le précédent aussi (le zombie
## est sur les marches ou à leurs ancres).
func _on_lane() -> bool:
	return _path_i < _path.size() and _mark_at(_path_i) > 0 and (_path_i == 0 or _mark_at(_path_i - 1) > 0)


## Point d'un couloir dépassé : le zombie a franchi le plan perpendiculaire à
## la direction d'arrivée sur ce point (une poussée de la horde qui l'écarte
## d'un pas ne le fait pas revenir en arrière).
func _lane_point_passed(i: int) -> bool:
	var p := _path[i]
	if _flat_dist(p) > 1.5 or absf(p.y - global_position.y) > 1.0:
		return false
	var prev := _path[i - 1] if i > 0 else global_position
	var d := Vector2(p.x - prev.x, p.z - prev.z)
	if d.length_squared() < 0.0001:
		return false
	var rel := Vector2(global_position.x - p.x, global_position.z - p.z)
	# Franchi, et pas trop à côté (sinon : on le rejoint d'abord).
	return rel.dot(d) > 0.0 and absf(rel.dot(Vector2(-d.y, d.x).normalized())) < 0.6


## Suit le chemin : direction (à plat) vers le point visé, en passant chaque
## point d'un couloir d'escalier dans l'ordre, ramené dans sa largeur permise.
func _follow_path() -> Vector3:
	while _path_i < _path.size():
		var lane_pt := _mark_at(_path_i) > 0
		# Point d'un couloir : atteint de plus près (0,25 m), ou dépassé.
		var reached := _flat_dist(_path[_path_i]) < 0.25 and absf(_path[_path_i].y - global_position.y) < 1.0 if lane_pt \
			else _waypoint_reached(_path[_path_i])
		if not (reached or _waypoint_passed(_path_i) or (lane_pt and _lane_point_passed(_path_i))):
			break
		_path_i += 1
	if _path_i >= _path.size():
		return Vector3.ZERO
	var wp := _path[_path_i] - global_position
	wp.y = 0.0
	var dir := wp.normalized()
	_lane_speed = 1.0
	if _on_lane():
		dir = (dir + game.nav.lane_push(_mark_at(_path_i), global_position) * 1.5).normalized()
		# Virage serré d'un palier (L, U, colimaçon) : on ralentit à l'approche
		# de l'angle au lieu de partir vers le bord.
		if _path_i + 1 < _path.size() and _mark_at(_path_i + 1) > 0 and wp.length() < 1.8:
			var nxt := _path[_path_i + 1] - _path[_path_i]
			nxt.y = 0.0
			if nxt.length() > 0.05 and dir.dot(nxt.normalized()) < 0.5:
				_lane_speed = LANE_CORNER_SPEED / maxf(move_speed() * speed_mult, LANE_CORNER_SPEED)
	return dir


## La partie de ce zombie se joue-t-elle sur une carte à plusieurs niveaux ?
func map_is_multilevel() -> bool:
	return game != null and game.layout != null and game.layout.is_multilevel()


## Décollement de la capsule au-dessus du sol (voir STEP_GAP).
func floor_gap() -> float:
	return STEP_GAP if _multilevel else FLOOR_GAP
