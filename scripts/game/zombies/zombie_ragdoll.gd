class_name ZombieRagdoll
extends PhysicalBoneSimulator3D
## Ragdoll d'un zombie tué (toutes les machines, purement visuel) : le corps
## tombe sous la physique au lieu de l'animation procédurale de chute.
##
## * Enfant du squelette du zombie mort (Zombie.die) : 11 PhysicalBone3D
##   (bassin, colonne, tête + cou, bras, avant-bras, cuisses, tibias) en
##   capsules, dimensionnées d'après le repos du squelette (modèles Blender
##   compris). Jointures : cônes (colonne, cou, épaules, hanches) et charnières
##   limitées (coudes, genoux). La tête suit l'os du cou sans corps propre :
##   une tête éclatée (échelle quasi nulle) le reste.
## * Départ de la pose courante (pas de saut), élan du zombie gardé, plus
##   l'impulsion du coup fatal (kill_impulse) : direction et force selon
##   l'arme, calculées par le SERVEUR et transmises dans le message de mort
##   existant (longueur du vecteur `dir` de ZombieManager._cl_die). Le
##   TONNERRE-7 donne directement la vitesse du vol (ZombieManager._cl_die_flung).
##   Aucun état physique synchronisé : chaque machine simule sa chute.
## * Couche dédiée LAYER : les corps ne touchent que le décor (masque 1), ni
##   les joueurs, ni les zombies, ni les tirs (aucun rayon ne vise cette couche),
##   ni les autres ragdolls ni eux-mêmes.
## * Coût borné : au plus cap() ragdolls simulés en même temps (selon la
##   qualité ; BASSE : aucun, ancienne chute procédurale). Un corps immobile,
##   ou simulé depuis MAX_SIM_TIME, est FIGÉ : sa pose est recopiée dans le
##   squelette et ses corps physiques sont retirés ; au-delà du plafond, le plus
##   ancien corps figeable l'est pour laisser la place, sinon le nouveau mort
##   tombe avec l'animation procédurale. La dissolution ne change pas.

## Couche physique « ragdolls » (7).
const LAYER := 1 << 6
## Décor seulement (sol, murs, portes).
const MASK := 1
## Ragdolls simulés en même temps (index = Settings.Quality : BASSE, MOYENNE, HAUTE).
const CAPS := [0, 8, 12]
## Vitesse d'impulsion maximale acceptée (m/s), quelle que soit la source.
const MAX_IMPULSE := 25.0
## Durée de simulation au plus, puis le corps est figé.
const MAX_SIM_TIME := 3.0
## Immobile : toutes les parties sous ces vitesses pendant REST_TIME secondes.
const REST_SPEED := 0.15
const REST_SPIN := 0.8
const REST_TIME := 0.3
## Pas de figement « au repos » avant ce délai (le corps vient de partir).
const MIN_SIM_TIME := 0.5
## Âge à partir duquel un ragdoll peut être figé pour faire place à un nouveau.
const EVICT_AGE := 1.0
## Part de l'impulsion reçue par tout le corps (le reste : la partie touchée).
const BODY_SHARE := 0.35
## Élan du zombie (sa marche) gardé à la mort.
const CARRY := 0.7
## Gravité d'un corps projeté par le TONNERRE-7 (x 9,8 m/s² : ~ ZombieFling.GRAVITY).
const FLING_GRAVITY := 2.0
## Vitesse de départ au-delà de laquelle la détection continue est activée.
const CCD_SPEED := 5.0
## Corps perdu (tombé sous le décor, projeté trop loin) : figé aussitôt.
const LOST_DROP := 3.0
const LOST_DIST := 45.0

## [os, masse (kg)] des parties simulées, parents avant enfants.
const PARTS := [
	["hips", 10.0], ["spine", 14.0], ["neck", 5.0],
	["arm_l", 2.5], ["forearm_l", 1.6], ["arm_r", 2.5], ["forearm_r", 1.6],
	["thigh_l", 8.0], ["shin_l", 4.5], ["thigh_r", 8.0], ["shin_r", 4.5],
]

## Tests : impose le plafond (-1 : selon la qualité).
static var debug_cap := -1
## Ragdolls simulés (du plus ancien au plus récent).
static var _active: Array[ZombieRagdoll] = []
## Capsules partagées (_capsule) : (rayon, hauteur) en mm -> forme.
static var _shapes: Dictionary = {}

var zombie: Zombie
## Temps de simulation écoulé.
var age := 0.0
## Figé : plus aucun corps physique, la pose est dans le squelette.
var frozen := false
var _rest_t := 0.0
var _start := Vector3.ZERO
## Dernière position connue du bassin (après le figement aussi).
var _hips_at := Vector3.ZERO
## os -> PhysicalBone3D
var bodies: Dictionary = {}


# --------------------------------------------------------------------------
# Règles pures
# --------------------------------------------------------------------------

## Plafond de ragdolls simulés pour la qualité courante.
static func cap() -> int:
	if debug_cap >= 0:
		return debug_cap
	return CAPS[clampi(Settings.quality, 0, CAPS.size() - 1)]


## Ragdolls simulés en ce moment (les figés et les libérés sont retirés).
static func active_count() -> int:
	_prune()
	return _active.size()


## Serveur : impulsion du coup fatal (m/s, repère monde) d'un coup de type
## `kind` (Combat.HitKind), arme `weapon_id` ("" si inconnue), direction
## unitaire `dir`. Envoyée telle quelle dans le message de mort (_cl_die).
## `jitter` dans [-1, 1] : variation tirée par le serveur.
static func kill_impulse(kind: int, weapon_id: String, headshot: bool, dir: Vector3, jitter := 0.0) -> Vector3:
	var flat := Vector3(dir.x, 0.0, dir.z)
	flat = flat.normalized() if flat.length_squared() > 0.0001 else Vector3.ZERO
	var d := dir.normalized() if dir.length_squared() > 0.0001 else flat
	var k := 1.0 + 0.15 * clampf(jitter, -1.0, 1.0)
	var out := Vector3.ZERO
	match kind:
		Combat.HitKind.BULLET:
			var wclass: String = WeaponDB.stats(weapon_id).get("class", "pistol") if weapon_id != "" else "pistol"
			var speed: float = {"pistol": 2.2, "smg": 2.4, "rifle": 3.2, "lmg": 3.4, "revolver": 4.5,
					"sniper": 5.0, "shotgun": 6.0, "wonder": 5.0}.get(wclass, 3.0)
			if headshot:
				speed *= 1.25
			out = d * speed
			if wclass == "shotgun":
				out += Vector3.UP * 0.8
		Combat.HitKind.MELEE:
			out = flat * 3.0 + Vector3.UP * 0.4
		Combat.HitKind.SPLASH:
			# Explosion (grenade, CLAUDE-RAY, lance-grenades) : soufflé vers le haut.
			out = (flat if flat != Vector3.ZERO else d) * 6.5 + Vector3.UP * 4.5
		Combat.HitKind.TRAP:
			# Électrocution : le corps s'effondre sur place.
			out = Vector3.UP * 0.4
		_:
			# Nuke, brûlure : poussée légère.
			out = flat * 1.2
	return (out * k).limit_length(MAX_IMPULSE)


# --------------------------------------------------------------------------
# Départ (toutes les machines)
# --------------------------------------------------------------------------

## Passe le zombie mort `z` en ragdoll. `impulse` : coup fatal (kill_impulse),
## `carry` : sa vitesse au moment de la mort, `fling` : vol du TONNERRE-7
## (vitesse de tout le corps, ZERO sinon). Faux (plafond plein, qualité
## BASSE) : le zombie garde sa chute procédurale.
static func start(z: Zombie, impulse: Vector3, carry: Vector3, headshot: bool, fling := Vector3.ZERO) -> ZombieRagdoll:
	if z == null or z.skel == null or not z.is_inside_tree():
		return null
	var limit := cap()
	if limit <= 0 or not _make_room(limit):
		return null
	var r := ZombieRagdoll.new()
	r.zombie = z
	r.name = "Ragdoll"
	r._build()
	z.skel.add_child(r)
	if r.bodies.is_empty():
		r.queue_free()
		return null
	_active.append(r)
	r._start = z.global_position
	r._hips_at = z.global_position
	r.physical_bones_start_simulation()
	r._launch(impulse, carry, headshot, fling)
	return r


static func _prune() -> void:
	for i in range(_active.size() - 1, -1, -1):
		var r := _active[i]
		if not is_instance_valid(r) or r.frozen or not r.is_inside_tree():
			_active.remove_at(i)


## Place pour un ragdoll de plus : fige le plus ancien qui peut l'être.
static func _make_room(limit: int) -> bool:
	_prune()
	while _active.size() >= limit:
		var victim: ZombieRagdoll = null
		for r in _active:
			if r.age >= EVICT_AGE or r._rest_t > 0.0:
				victim = r
				break
		if victim == null:
			return false
		victim.freeze()
	return true


## Crée les corps : capsules taillées d'après le repos du squelette.
func _build() -> void:
	var skel := zombie.skel
	var b := zombie.bones
	var rest := func(bone: String) -> Vector3:
		return skel.get_bone_rest(b[bone]).origin
	var arm_len: float = maxf(0.2, rest.call("forearm_l").length())
	var thigh_len: float = maxf(0.3, rest.call("shin_l").length())
	# Du genou au sol : hauteur du bassin moins la cuisse.
	var shin_len: float = maxf(0.3, rest.call("hips").y + rest.call("thigh_l").y - thigh_len)
	var torso_len: float = maxf(0.3, rest.call("chest").y + rest.call("neck").y)
	var head_len: float = rest.call("head").y + 0.27
	var hip_w: float = absf(rest.call("thigh_l").x - rest.call("thigh_r").x)
	for part in PARTS:
		var bone: String = part[0]
		if not b.has(bone) or _cut(bone):
			continue
		var pb := PhysicalBone3D.new()
		pb.name = "B_" + bone
		pb.bone_name = bone
		pb.mass = part[1]
		pb.friction = 0.9
		pb.bounce = 0.0
		pb.linear_damp = 0.15
		pb.angular_damp = 2.5
		pb.collision_layer = LAYER
		pb.collision_mask = MASK
		var cs := CollisionShape3D.new()
		pb.add_child(cs)
		var radius := 0.0
		var height := 0.0
		# Longueur signée le long de Y de l'os (membres : vers le bas).
		var length := 0.0
		match bone:
			"hips":
				radius = 0.13
				height = hip_w + 0.26
				cs.rotation.z = PI * 0.5
				pb.body_offset = Transform3D(Basis.IDENTITY, Vector3(0, -0.04, 0))
			"spine":
				length = torso_len
				radius = 0.15
			"neck":
				length = head_len
				radius = 0.11
			"arm_l", "arm_r":
				length = -arm_len
				radius = 0.06
			"forearm_l", "forearm_r":
				length = -arm_len * 1.25
				radius = 0.05
			"thigh_l", "thigh_r":
				length = -thigh_len
				radius = 0.085
			"shin_l", "shin_r":
				length = -shin_len
				radius = 0.065
		if bone != "hips":
			height = maxf(absf(length), radius * 2.0 + 0.01)
			# Corps au milieu du segment, jointure (repère identité du corps) à
			# l'origine de l'os. Les axes des jointures sont donnés en tournant le
			# CORPS (body_offset) et non par joint_rotation, qui rend les
			# charnières instables (corps qui explosent en quelques images).
			var basis := _joint(pb, bone, length)
			pb.body_offset = Transform3D(basis, Vector3(0, length * 0.5, 0))
			pb.joint_offset = Transform3D(Basis.IDENTITY, basis.inverse() * Vector3(0, -length * 0.5, 0))
			# Capsule le long de l'os quel que soit le repère du corps.
			cs.basis = basis.inverse()
		cs.shape = _capsule(radius, height)
		add_child(pb)
		bodies[bone] = pb


## Capsule partagée (mêmes dimensions pour tous les ragdolls d'un look :
## aucune forme physique créée par mort).
static func _capsule(radius: float, height: float) -> CapsuleShape3D:
	var key := Vector2i(roundi(radius * 1000.0), roundi(height * 1000.0))
	var s: CapsuleShape3D = _shapes.get(key)
	if s == null:
		s = CapsuleShape3D.new()
		s.radius = radius
		s.height = height
		_shapes[key] = s
	return s


## Partie arrachée (démembrement) ou réduite : pas de corps, l'os suit son parent.
func _cut(bone: String) -> bool:
	var skel := zombie.skel
	var i: int = zombie.bones[bone]
	while i >= 0:
		if skel.get_bone_pose_scale(i).x < 0.99:
			return true
		i = skel.get_bone_parent(i)
	return false


## Type et limites (degrés) de la jointure ; retourne l'orientation du corps
## dans le repère de l'os : cône (axe de torsion = X du corps) le long du
## membre, charnière (axe = Z du corps) sur l'axe X de l'os (coude : vers
## l'avant, genou : vers l'arrière, voir ZombieAnim).
func _joint(pb: PhysicalBone3D, bone: String, length: float) -> Basis:
	if bone.begins_with("forearm") or bone.begins_with("shin"):
		pb.joint_type = PhysicalBone3D.JOINT_TYPE_HINGE
		pb.set("joint_constraints/angular_limit_enabled", true)
		# Angle de la charnière = OPPOSÉ de la rotation X de l'os (mesuré) :
		# coude plié vers l'avant (X de l'os < 0), genou vers l'arrière (X > 0).
		if bone.begins_with("forearm"):
			pb.set("joint_constraints/angular_limit_upper", 140.0)
			pb.set("joint_constraints/angular_limit_lower", -5.0)
		else:
			pb.set("joint_constraints/angular_limit_upper", 5.0)
			pb.set("joint_constraints/angular_limit_lower", -140.0)
		# Z du corps = X de l'os.
		return Basis(Vector3.UP, PI * 0.5)
	pb.joint_type = PhysicalBone3D.JOINT_TYPE_CONE
	var swing := 30.0
	var twist := 20.0
	match bone:
		"neck":
			swing = 40.0
			twist = 35.0
		"arm_l", "arm_r":
			swing = 75.0
			twist = 40.0
		"thigh_l", "thigh_r":
			swing = 50.0
			twist = 15.0
	pb.set("joint_constraints/swing_span", swing)
	pb.set("joint_constraints/twist_span", twist)
	# X du corps = axe du membre (+Y de l'os pour le tronc, -Y pour les membres).
	return Basis(Vector3.BACK, PI * 0.5 if length > 0.0 else -PI * 0.5)


## Vitesses de départ : élan du zombie + impulsion répartie (tout le corps,
## plus la partie touchée : le buste, ou le cou pour un tir à la tête).
func _launch(impulse: Vector3, carry: Vector3, headshot: bool, fling: Vector3) -> void:
	impulse = impulse.limit_length(MAX_IMPULSE) if impulse.is_finite() else Vector3.ZERO
	fling = fling.limit_length(MAX_IMPULSE * 1.5) if fling.is_finite() else Vector3.ZERO
	var base := Vector3(carry.x, 0.0, carry.z).limit_length(6.0) * CARRY if carry.is_finite() else Vector3.ZERO
	var hit := "neck" if headshot else "spine"
	# Corps lancés vite (TONNERRE-7, explosion) : détection continue, sinon
	# ils traversent un mur fin en une image (0,3 m par pas à 20 m/s).
	var ccd := (base + fling + impulse).length() > CCD_SPEED
	for bone in bodies:
		var pb: PhysicalBone3D = bodies[bone]
		if ccd:
			PhysicsServer3D.body_set_enable_continuous_collision_detection(pb.get_rid(), true)
		var v := base + fling + impulse * BODY_SHARE
		if bone == hit or (bone == "spine" and headshot):
			v += impulse * (1.0 - BODY_SHARE) * (1.0 if bone == hit else 0.5)
		# Les jambes partent moins vite que le buste : le corps bascule.
		if bone.begins_with("thigh") or bone.begins_with("shin"):
			v -= (impulse + fling) * 0.15
		pb.apply_central_impulse(v * pb.mass)
		if fling != Vector3.ZERO:
			# Même parabole que le vol procédural (ZombieFling.GRAVITY).
			pb.gravity_scale = FLING_GRAVITY
	if fling != Vector3.ZERO and bodies.has("spine"):
		# Culbute en arrière (la tête part dans le sens du vol).
		var axis := Vector3.UP.cross(Vector3(fling.x, 0.0, fling.z)).normalized()
		var spine: PhysicalBone3D = bodies.spine
		PhysicsServer3D.body_set_state(spine.get_rid(), PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY,
				axis * clampf(fling.length() * 0.4, 2.0, 8.0))


# --------------------------------------------------------------------------
# Simulation et figement
# --------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if frozen:
		return
	age += delta
	var calm := true
	var lost := false
	for bone in bodies:
		var pb: PhysicalBone3D = bodies[bone]
		var rid := pb.get_rid()
		var lv: Vector3 = PhysicsServer3D.body_get_state(rid, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
		var av: Vector3 = PhysicsServer3D.body_get_state(rid, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)
		if lv.length() > REST_SPEED or av.length() > REST_SPIN:
			calm = false
		var p := pb.global_position
		if p.y < _start.y - LOST_DROP or p.distance_to(_start) > LOST_DIST or not p.is_finite():
			lost = true
	_rest_t = _rest_t + delta if calm else 0.0
	if lost or age >= MAX_SIM_TIME or (age >= MIN_SIM_TIME and _rest_t >= REST_TIME):
		freeze()


## Position du bassin (sol, décalque de sang), ou celle du zombie.
func hips_position() -> Vector3:
	if bodies.has("hips"):
		_hips_at = (bodies.hips as PhysicalBone3D).global_position
	return _hips_at


## Fige le corps : pose actuelle recopiée dans le squelette (locale, parents
## d'abord), puis plus aucun corps physique.
func freeze() -> void:
	if frozen:
		return
	hips_position()
	frozen = true
	_active.erase(self)
	if zombie:
		zombie.ragdoll_rest = _hips_at
		# Corps projeté (TONNERRE-7) : il retombe maintenant (la chute
		# ordinaire a son bruit et son sang à 0,6 s, Zombie._process_death).
		if zombie._fling_vel != Vector3.ZERO and zombie.is_inside_tree():
			var ground := Vector3(_hips_at.x, minf(_hips_at.y, _start.y + 0.3), _hips_at.z)
			Audio.play_3d("body_fall", ground, -3.0, 0.1, 3)
			if zombie.game:
				zombie.game.fx_root.blood_decal(ground + Vector3.UP * 0.1, Vector3.UP, randf_range(0.9, 1.4))
	var skel := zombie.skel if zombie else null
	if skel and is_inside_tree():
		var inv := skel.global_transform.affine_inverse()
		var n := skel.get_bone_count()
		var glob: Array[Transform3D] = []
		glob.resize(n)
		var local: Array = []
		local.resize(n)
		for i in n:
			var parent := skel.get_bone_parent(i)
			var name_i := skel.get_bone_name(i)
			var pb: PhysicalBone3D = bodies.get(name_i)
			if pb:
				glob[i] = (inv * pb.global_transform * pb.body_offset.affine_inverse()).orthonormalized()
				local[i] = glob[i] if parent < 0 else glob[parent].affine_inverse() * glob[i]
			else:
				var lp := Transform3D(Basis(skel.get_bone_pose_rotation(i)).scaled(skel.get_bone_pose_scale(i)), skel.get_bone_pose_position(i))
				glob[i] = lp if parent < 0 else glob[parent] * lp
		physical_bones_stop_simulation()
		for i in n:
			if local[i] != null:
				var t: Transform3D = local[i]
				skel.set_bone_pose_position(i, t.origin)
				skel.set_bone_pose_rotation(i, t.basis.get_rotation_quaternion())
	active = false
	for pb in bodies.values():
		(pb as Node).queue_free()
	bodies.clear()
	queue_free()


func _exit_tree() -> void:
	_active.erase(self)
