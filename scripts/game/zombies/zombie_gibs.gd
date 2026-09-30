class_name ZombieGibs
extends RefCounted
## Démembrement et RAMPANTS façon Black Ops 1 (zombie_gib / zombie_gib_on_damage).
##
## * Le SERVEUR décide (decide) à chaque coup, à partir des dégâts, du type de
##   coup et du membre touché (limb_at, calculé sur SON squelette) ; il diffuse
##   les membres arrachés par un RPC fiable (ZombieManager._cl_gib), envoyé
##   AVANT la mort éventuelle (même canal : ordre garanti).
## * Toutes les machines appliquent (apply) : l'os disparaît, le morceau tombe
##   au sol (GibPool), giclée de sang. Un zombie qui survit à la perte de ses
##   jambes devient un RAMPANT : il se traîne (crawl_pose), lentement, frappe au
##   ras du sol et ses hitboxes sont couchées (plus petites, plus basses).
## * Règles BO1 reprises : aucun démembrement si le coup enlève moins de 10 %
##   des PV restants, ni au couteau, ni par les pièges, ni au pistolet ; un tir
##   au bras arrache l'avant-bras ; un tir à la tête mortel fait éclater la tête
##   (Zombie.die) ; les explosions arrachent les jambes (rampant) ou, si elles
##   tuent, déchiquettent le corps.

## Membres arrachés (masque, Zombie.gibs).
const ARM_L := 1
const ARM_R := 2
const LEGS := 4
## Membre touché (limb_at) : TORSO = ni bras ni jambes.
const TORSO := 0

## Pourcentage minimal des PV d'avant le coup (zombie_should_gib : 10 %).
const MIN_DAMAGE_PCT := 10.0
## Tir aux jambes non mortel : chance de faire un rampant.
const CRAWL_BULLET_CHANCE := 0.2
## Explosion non mortelle : chance de faire un rampant, et d'arracher un bras.
const CRAWL_SPLASH_CHANCE := 0.8
const SPLASH_ARM_CHANCE := 0.3
## Explosion mortelle : chance de perdre les jambes, chaque bras.
const DEATH_LEGS_CHANCE := 0.6
const DEATH_ARM_CHANCE := 0.5

## Rampant : vitesse (m/s), durée de la chute avant de ramper.
const CRAWL_SPEED := 0.75
const CRAWL_FALL_TIME := 0.7
## Hauteur du bassin et inclinaison du corps couché.
const CRAWL_HIPS_Y := 0.24
const CRAWL_PITCH := 1.38

## Tests : force toutes les chances (1 = toujours, 0 = jamais ; < 0 : normal).
static var debug_chance := -1.0


static func _chance(p: float, rng: RandomNumberGenerator) -> bool:
	if debug_chance >= 0.0:
		return debug_chance >= 0.5
	return rng.randf() < p


## Le coup peut-il arracher quelque chose (zombie_should_gib) ?
static func eligible(kind: int, weapon_class: String, dmg: int, health_before: int) -> bool:
	if kind != Combat.HitKind.BULLET and kind != Combat.HitKind.SPLASH:
		return false
	if kind == Combat.HitKind.BULLET and weapon_class == "pistol":
		return false
	return float(dmg) * 100.0 / float(maxi(health_before, 1)) >= MIN_DAMAGE_PCT


## Membres à arracher (bits absents de `mask`) pour un coup. Fonction pure
## (hors tirage `rng`), testée dans tests/test_gibs.gd.
static func decide(kind: int, weapon_class: String, dmg: int, health_before: int, killed: bool,
		headshot: bool, limb: int, mask: int, rng: RandomNumberGenerator) -> int:
	if not eligible(kind, weapon_class, dmg, health_before):
		return 0
	var bits := 0
	if kind == Combat.HitKind.BULLET:
		if headshot:
			return 0  # la tête éclate à la mort (Zombie.die)
		if limb == ARM_L or limb == ARM_R:
			bits = limb
		elif limb == LEGS and (killed or _chance(CRAWL_BULLET_CHANCE, rng)):
			bits = LEGS
	else:
		if killed:
			if _chance(DEATH_LEGS_CHANCE, rng):
				bits |= LEGS
			if _chance(DEATH_ARM_CHANCE, rng):
				bits |= ARM_L
			if _chance(DEATH_ARM_CHANCE, rng):
				bits |= ARM_R
			if bits == 0:
				bits = LEGS
		else:
			if _chance(CRAWL_SPLASH_CHANCE, rng):
				bits |= LEGS
			if _chance(SPLASH_ARM_CHANCE, rng):
				bits |= ARM_L if rng.randf() < 0.5 else ARM_R
	return bits & ~mask


## Vitesse d'un rampant `t` secondes après sa chute.
static func crawl_speed(t: float) -> float:
	return CRAWL_SPEED * clampf((t - CRAWL_FALL_TIME) / 0.4, 0.0, 1.0)


# --------------------------------------------------------------------------
# Membre touché (serveur, squelette posé)
# --------------------------------------------------------------------------

static func _seg_dist(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)


static func _bone_xf(z: Zombie, b: String) -> Transform3D:
	return z.skel.global_transform * z.skel.get_bone_global_pose(z.bones[b])


static func _tip(xf: Transform3D, length: float) -> Vector3:
	return xf.origin - xf.basis.y.normalized() * length


## Membre le plus proche du point d'impact `p` (repère monde) : ARM_L, ARM_R,
## LEGS ou TORSO (distance aux segments des os moins leur épaisseur).
static func limb_at(z: Zombie, p: Vector3) -> int:
	if z.skel == null or z.bones.is_empty():
		return TORSO
	var best := TORSO
	var best_d := _seg_dist(p, _bone_xf(z, "hips").origin, _bone_xf(z, "neck").origin) - 0.12
	for side in ["l", "r"]:
		var arm := _bone_xf(z, "arm_" + side)
		var fore := _bone_xf(z, "forearm_" + side)
		var d := minf(_seg_dist(p, arm.origin, fore.origin), _seg_dist(p, fore.origin, _tip(fore, 0.36))) - 0.08
		if d < best_d:
			best_d = d
			best = ARM_L if side == "l" else ARM_R
		var thigh := _bone_xf(z, "thigh_" + side)
		var shin := _bone_xf(z, "shin_" + side)
		var dl := minf(_seg_dist(p, thigh.origin, shin.origin), _seg_dist(p, shin.origin, _tip(shin, 0.47))) - 0.08
		if dl < best_d:
			best_d = dl
			best = LEGS
	return best


# --------------------------------------------------------------------------
# Toutes les machines : application
# --------------------------------------------------------------------------

## Arrache les membres `bits` du zombie `z`. `lethal` : le coup le tue (pas de
## rampant, le corps tombe sans ses membres). `dir` : direction du coup.
static func apply(z: Zombie, bits: int, dir: Vector3, lethal: bool) -> void:
	bits &= ~z.gibs
	if bits == 0 or z.skel == null:
		return
	z.gibs |= bits
	var fx: Fx = z.game.fx_root if z.game else null
	var push := Vector3(dir.x, 0.0, dir.z).normalized() if Vector2(dir.x, dir.z).length() > 0.01 else Vector3.ZERO
	if bits & ARM_L:
		_tear(z, fx, "forearm_l", ["forearm_l"], push, 0.001)
	if bits & ARM_R:
		_tear(z, fx, "forearm_r", ["forearm_r"], push, 0.001)
	# Bras arraché : sa hitbox disparaît avec lui.
	for i in z.hit_arms.size():
		if bits & (ARM_L if i == 0 else ARM_R):
			z.hit_arms[i].collision_layer = 0
			z.hit_arms[i].get_child(0).set_deferred("disabled", true)
	if bits & LEGS:
		for side in ["l", "r"]:
			# Moignon : le haut de la cuisse reste ; le reste de la jambe tombe.
			_tear(z, fx, "thigh_" + side, ["thigh_" + side, "shin_" + side], push, 0.3)
			z.skel.set_bone_pose_scale(z.bones["shin_" + side], Vector3.ONE * 0.001)
		if not lethal and z.is_alive():
			become_crawler(z)
	var at := z.global_position + Vector3.UP * (0.5 if bits & LEGS else 1.3)
	Audio.play_3d("flesh_hit_%d" % (1 + randi() % 3), at, 0.0, 0.1, 5)
	Audio.play_3d("headshot", at, -6.0, 0.15, 4)


static func _tear(z: Zombie, fx: Fx, bone: String, piece_bones: Array, push: Vector3, keep: float) -> void:
	var xf := _bone_xf(z, bone)
	if keep > 0.01:
		# Le morceau part du bas du moignon.
		xf.origin = xf.origin - xf.basis.y.normalized() * 0.46 * keep
	if fx:
		var v := push * randf_range(1.5, 3.0) + Vector3(randf_range(-0.8, 0.8), randf_range(1.2, 2.6), randf_range(-0.8, 0.8))
		var spin := Vector3(randf_range(-7, 7), randf_range(-4, 4), randf_range(-7, 7))
		fx.gibs.spawn_limb(z.variant, piece_bones, xf, v, spin)
		fx.blood_hit(xf.origin, push if push != Vector3.ZERO else Vector3.DOWN, 1.6)
	z.skel.set_bone_pose_scale(z.bones[bone], Vector3.ONE * maxf(keep, 0.001))


## Le zombie tombe et rampe : capsule de collision et hitboxes couchées.
static func become_crawler(z: Zombie) -> void:
	if z.crawl_t >= 0.0:
		return
	z.crawl_t = 0.0
	var body := z.body_shape
	var cap := body.shape as CapsuleShape3D if body else null
	if cap:
		cap.height = 0.6
		cap.radius = 0.3
		body.position.y = 0.3 + z.floor_gap()
	var hb := z.hit_body.get_child(0).shape as CapsuleShape3D
	hb.radius = 0.22
	hb.height = 1.1
	# Corps couché vers l'avant (+Z du modèle), au ras du sol.
	z.hit_body.rotation.x = PI * 0.5
	z.hit_body.position = Vector3(0.0, 0.26, 0.2)


## Tête qui éclate (tir à la tête mortel) : éclats de crâne.
static func head_pop(z: Zombie, neck: Vector3, dir: Vector3) -> void:
	if z.game and z.game.fx_root.gibs:
		z.game.fx_root.gibs.head_burst(neck + Vector3.UP * 0.12, dir)


# --------------------------------------------------------------------------
# Animation du rampant (toutes les machines)
# --------------------------------------------------------------------------

static func _q(x: float, y := 0.0, zr := 0.0) -> Quaternion:
	return Quaternion.from_euler(Vector3(x, y, zr))


## Pose procédurale du rampant : chute vers l'avant, puis traction alternée des
## bras, tête relevée vers la cible, moignons qui traînent ; coup de griffe
## vers le haut pendant l'attaque.
static func crawl_pose(z: Zombie, delta: float) -> void:
	var skel := z.skel
	var b := z.bones
	var spd := z.anim_speed
	z.gait_phase += delta * (1.4 + spd * 4.5)
	var s := sin(z.gait_phase)
	var c := cos(z.gait_phase)
	var k := ease(clampf(z.crawl_t / CRAWL_FALL_TIME, 0.0, 1.0), 0.5)
	var move_k := clampf(spd / 0.5, 0.0, 1.0)
	skel.position.y = 0.0
	var rest_y := skel.get_bone_rest(b.hips).origin.y
	var hips_y := lerpf(rest_y, CRAWL_HIPS_Y + absf(s) * 0.03 * move_k, k)
	skel.set_bone_pose_position(b.hips, Vector3(s * 0.03 * move_k, hips_y, lerpf(0.0, -0.3, k)))
	skel.set_bone_pose_rotation(b.hips, _q(CRAWL_PITCH * k, 0.0, s * 0.08 * move_k))
	skel.set_bone_pose_rotation(b.spine, _q(0.04, s * 0.12 * move_k, 0.0))
	skel.set_bone_pose_rotation(b.chest, _q(-0.06, -s * 0.12 * move_k, c * 0.05))
	# Tête relevée vers l'avant (le buste est couché).
	skel.set_bone_pose_rotation(b.head, _q(-1.15 * k - 0.2 + sin(z.gait_phase * 0.7) * 0.06, 0.0, z.head_tilt))
	# Mâchoire pendante, grande ouverte pendant la griffe.
	var jaw := (z.anim.jaw_open if z.anim else 0.3) + sin(z.gait_phase * 1.3) * 0.08
	if z.attack_t >= 0.0:
		jaw = 0.6
	skel.set_bone_pose_rotation(b.jaw, _q(jaw))
	# Bras : traction alternée (tendu devant, puis ramené sous le buste).
	var arm_l := lerpf(-1.3, -2.45 - 0.55 * s * move_k, k)
	var arm_r := lerpf(-1.2, -2.45 + 0.55 * s * move_k, k)
	var fore_l := -0.25 - 0.35 * maxf(0.0, s) * move_k
	var fore_r := -0.25 - 0.35 * maxf(0.0, -s) * move_k
	if z.attack_t >= 0.0:
		z.attack_t += delta / 0.7
		var ak := sin(clampf(z.attack_t, 0.0, 1.0) * PI)
		# Griffe vers le haut (chevilles, jambes du joueur).
		arm_r = lerpf(arm_r, -3.35 + z.attack_t * 1.2, ak)
		arm_l = lerpf(arm_l, -3.1 + z.attack_t * 0.9, ak * 0.7)
		fore_r = lerpf(fore_r, -0.1, ak)
		if z.attack_t >= 1.0:
			z.attack_t = -1.0
	skel.set_bone_pose_rotation(b.arm_l, _q(arm_l, 0.0, -0.3 * k - 0.15))
	skel.set_bone_pose_rotation(b.arm_r, _q(arm_r, 0.0, 0.3 * k + 0.15))
	skel.set_bone_pose_rotation(b.forearm_l, _q(fore_l))
	skel.set_bone_pose_rotation(b.forearm_r, _q(fore_r))
	# Moignons qui traînent derrière.
	skel.set_bone_pose_rotation(b.thigh_l, _q(-0.15 * k + s * 0.12 * move_k, 0.0, 0.12))
	skel.set_bone_pose_rotation(b.thigh_r, _q(-0.15 * k - s * 0.12 * move_k, 0.0, -0.12))
