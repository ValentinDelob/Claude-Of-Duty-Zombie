class_name ZombieAnim
extends RefCounted
## Animations procédurales des zombies, façon Black Ops 1 (toutes les machines,
## purement cosmétique) : écrit les rotations d'os du squelette RigBuilder.
##
## * Marche traînante et titubante (classe 0) : genoux fléchis, jambe qui
##   traîne (boiterie propre à chaque zombie), buste voûté qui tangue, bras
##   tendus en avant, un seul bras levé, ou bras ballants selon le zombie.
## * Trot / course (classes 1, 2) : penché en avant, bras ballants qui battent.
## * Sprint (classe 3) : très penché, bras tendus vers la proie qui battent.
## * Attaque : coup de griffes à deux bras (armé au-dessus de la tête, frappe
##   plongeante, le bras droit mène), mâchoire grande ouverte.
## * Émergence : les mains crèvent le sol d'abord, puis la tête ; le zombie
##   prend appui sur le sol et s'extirpe.
## * Fenêtre : agrippe une planche, l'arrache en se jetant en arrière, la
##   jette sur le côté ; entre deux planches, pause « de folie » (frappe les
##   planches à coups de bras alternés, tête secouée) ; enjambement de l'allège.
## * Morts variées : bascule avant/arrière, effondrement à genoux puis face
##   contre terre, vrille sur le côté, chute raide (tir à la tête).
##
## Rappels du repère (os au repos, membres pendants vers -Y, modèle vers +Z) :
## rotation X négative = membre vers l'avant ; tibia positif = genou plié ;
## tronc positif = penché en avant ; tête positive = regard vers le bas.

enum Death { TOPPLE, CRUMPLE, SPIN, STIFF }
enum Arms { REACH, ONE_ARM, DANGLE }
const POSE_BONES := ["hips", "spine", "chest", "neck", "head", "jaw", "thigh_l", "thigh_r",
		"shin_l", "shin_r", "arm_l", "arm_r", "forearm_l", "forearm_r"]

## Tables de clés des poses (t, valeur) : constantes partagées, aucune
## allocation à chaque image (ZombieAnim._keys).
const RUN_TARGET := [0.0, 0.65, 1.0, 1.0]
## Pause de folie à la fenêtre : cadence des coups (rad/s, ~2,4 coups par
## seconde et par bras) et nombre de valeurs de frenzy_pose.
const FRENZY_RATE := 15.0
const FRENZY_VALUES := 14
const STIFF_BONES := ["thigh_l", "thigh_r", "shin_l", "shin_r", "spine", "chest"]
const K_EMERGE_ROOT := [[0.0, -2.3], [0.18, -1.95], [0.42, -1.4], [0.78, -0.2], [1.0, 0.0]]
const K_VAULT_THIGH_L := [[0.0, -0.3], [0.35, -1.4], [0.7, -0.6], [1.0, -0.1]]
const K_VAULT_THIGH_R := [[0.0, 0.1], [0.3, -0.5], [0.6, -1.3], [1.0, -0.2]]
const K_VAULT_SHIN_L := [[0.0, 0.3], [0.35, 1.8], [0.8, 0.6], [1.0, 0.2]]
const K_VAULT_SHIN_R := [[0.0, 0.2], [0.5, 1.6], [0.9, 0.9], [1.0, 0.2]]
const K_VAULT_ARM_L := [[0.0, -1.3], [0.3, -0.7], [0.7, -0.3], [1.0, -1.1]]
const K_VAULT_ARM_R := [[0.0, -1.2], [0.3, -0.65], [0.7, -0.35], [1.0, -1.0]]
const K_TEAR_ARM_L := [[0.0, -1.3], [0.35, -1.75], [0.5, -1.7], [0.7, -0.55], [0.85, -1.2], [1.0, -1.3]]
const K_TEAR_ARM_R := [[0.0, -1.25], [0.35, -1.7], [0.5, -1.68], [0.7, -0.5], [0.85, -1.7], [1.0, -1.25]]
const K_TEAR_FOREARM_L := [[0.0, -0.3], [0.45, -0.25], [0.7, -1.4], [1.0, -0.3]]
const K_TEAR_FOREARM_R := [[0.0, -0.3], [0.45, -0.25], [0.7, -1.3], [0.85, -0.3], [1.0, -0.3]]
const K_TEAR_ARM_R_Z := [[0.0, 0.1], [0.7, 0.1], [0.85, -0.6], [1.0, 0.1]]
const K_TEAR_SPINE := [[0.0, 0.35], [0.45, 0.45], [0.7, -0.05], [1.0, 0.35]]
const K_TEAR_CHEST_X := [[0.0, 0.2], [0.45, 0.25], [0.7, 0.0], [1.0, 0.2]]
const K_TEAR_CHEST_Y := [[0.0, 0.0], [0.7, 0.1], [0.85, -0.5], [1.0, 0.0]]
const K_ATTACK_ARM_R := [[0.0, -1.3], [0.28, -2.45], [0.5, -0.85], [0.7, -1.0], [1.0, -1.2]]
const K_ATTACK_ARM_L := [[0.0, -1.3], [0.32, -2.35], [0.56, -0.9], [0.75, -1.05], [1.0, -1.2]]
const K_ATTACK_FOREARM_L := [[0.0, -0.3], [0.3, -0.9], [0.55, -0.15], [1.0, -0.3]]
const K_ATTACK_FOREARM_R := [[0.0, -0.3], [0.26, -0.9], [0.48, -0.12], [1.0, -0.3]]
const K_ATTACK_SPINE := [[0.0, 0.3], [0.28, 0.1], [0.5, 0.5], [1.0, 0.35]]
const K_ATTACK_CHEST_Y := [[0.0, 0.0], [0.28, 0.2], [0.5, -0.25], [1.0, 0.0]]


var z: Zombie
## Traits propres à chaque zombie (graine = variante).
var limp_side := 1.0
var limp := 0.0
var arm_style: int = Arms.REACH
var hunch := 0.3
var head_tilt := 0.0
var jaw_open := 0.3
var sway := 0.1
var reach := 0.0
var seed_phase := 0.0
## Mélanges lissés (changement de classe de vitesse en cours de manche).
var run_k := 0.0
var sprint_k := 0.0
var death_style: int = Death.TOPPLE
var _t := 0.0
## Indices des os écrits à chaque pose (ordre de POSE_BONES), repos du bassin.
var _bi := PackedInt32Array()
var _hips_rest_y := 0.95
## Pose de folie de l'image (frenzy_pose), réutilisée : aucune allocation.
var _fz: Array = []


func _init(zombie: Zombie) -> void:
	z = zombie
	for b in POSE_BONES:
		_bi.append(z.bones[b])
	_hips_rest_y = z.skel.get_bone_rest(z.bones.hips).origin.y
	var rng := RandomNumberGenerator.new()
	rng.seed = z.variant * 2654435761 + 11
	limp_side = 1.0 if rng.randf() < 0.5 else -1.0
	limp = rng.randf_range(0.0, 0.75) if rng.randf() < 0.6 else 0.0
	var r := rng.randf()
	arm_style = Arms.REACH if r < 0.5 else (Arms.ONE_ARM if r < 0.75 else Arms.DANGLE)
	hunch = rng.randf_range(0.32, 0.52)
	head_tilt = rng.randf_range(-0.3, 0.3)
	jaw_open = rng.randf_range(0.18, 0.42)
	sway = rng.randf_range(0.06, 0.14)
	reach = rng.randf_range(-0.15, 0.15)
	seed_phase = rng.randf() * TAU
	var cls := z.speed_class
	run_k = _run_target(cls)
	sprint_k = 1.0 if cls >= 3 else 0.0
	_fz.resize(FRENZY_VALUES)
	_fz.fill(0.0)


static func _q(x: float, y := 0.0, zr := 0.0) -> Quaternion:
	return Quaternion.from_euler(Vector3(x, y, zr))


## Pause « de folie » à la fenêtre, entre deux planches : le zombie frappe
## les planches à coups de bras alternés (levés au-dessus de la tête, griffes
## repliées, puis abattus), épaules qui vrillent, buste qui pompe à chaque
## coup, tête secouée, mâchoire grande ouverte, genoux qui rebondissent.
## Écrit dans `out` (FRENZY_VALUES valeurs) : bras g/d, avant-bras g/d,
## écart des bras g/d, dos, buste (avant, torsion), tête (avant, roulis),
## mâchoire, tibias g/d. `phase` décale chaque zombie (pas de cadence commune).
static func frenzy_pose(out: Array, t: float, phase: float, tilt: float, jaw0: float) -> void:
	var ph := t * FRENZY_RATE + phase
	var raise_l := 0.5 + 0.5 * sin(ph)
	var raise_r := 0.5 + 0.5 * sin(ph + PI * 0.9)
	out[0] = lerpf(-1.35, -2.45, raise_l)
	out[1] = lerpf(-1.35, -2.4, raise_r)
	out[2] = lerpf(-0.25, -1.0, raise_l)
	out[3] = lerpf(-0.25, -1.0, raise_r)
	out[4] = -0.2 - 0.12 * sin(ph * 0.5 + 1.0)
	out[5] = 0.2 + 0.12 * sin(ph * 0.5)
	out[6] = 0.32 + 0.1 * absf(sin(ph))
	out[7] = 0.15 + 0.08 * absf(sin(ph + 0.6))
	out[8] = 0.22 * sin(ph)
	out[9] = -0.5 + 0.15 * sin(ph * 2.0 + 0.4)
	out[10] = tilt + 0.28 * sin(t * 7.3 + phase * 1.7)
	out[11] = jaw0 + 0.3 + 0.12 * sin(t * 9.0 + phase)
	out[12] = 0.35 + 0.12 * absf(sin(ph))
	out[13] = 0.25 + 0.12 * absf(sin(ph + PI * 0.9))


static func _run_target(cls: int) -> float:
	return RUN_TARGET[clampi(cls, 0, 3)]


## Interpolation par morceaux lissée : `keys` = [[t, valeur], ...] (t croissant).
static func _keys(t: float, keys: Array) -> float:
	if t <= keys[0][0]:
		return keys[0][1]
	for i in keys.size() - 1:
		var a: Array = keys[i]
		var b: Array = keys[i + 1]
		if t <= b[0]:
			return lerpf(a[1], b[1], smoothstep(0.0, 1.0, (t - a[0]) / maxf(b[0] - a[0], 0.0001)))
	return keys[keys.size() - 1][1]


# --------------------------------------------------------------------------
# Pose debout (marche, course, attaque, émergence, fenêtres)
# --------------------------------------------------------------------------

func pose(delta: float) -> void:
	var skel := z.skel
	_t += delta
	var cls := z.speed_class
	run_k = move_toward(run_k, _run_target(cls), delta * 2.0)
	sprint_k = move_toward(sprint_k, 1.0 if cls >= 3 else 0.0, delta * 2.0)
	var spd := z.anim_speed
	# Longueur d'un pas : la cadence suit la vitesse réelle (pas de glisse).
	var stride := lerpf(0.4, 0.8, run_k) + 0.18 * sprint_k
	z.gait_phase += delta * (PI * spd / stride + 0.5)
	var ph := z.gait_phase
	var s := sin(ph)
	var c := cos(ph)
	var move_k := clampf(spd / lerpf(0.9, 2.2, run_k), 0.0, 1.0)
	var state := z.state

	# --- Jambes : genoux fléchis, boiterie (jambe qui traîne) ---------------
	var amp := (lerpf(0.34, 0.62, run_k) + 0.14 * sprint_k) * move_k
	var drag_l := 1.0 - (limp * 0.55 if limp_side > 0.0 else 0.0) * (1.0 - run_k)
	var drag_r := 1.0 - (limp * 0.55 if limp_side < 0.0 else 0.0) * (1.0 - run_k)
	var knee := 0.14 + 0.18 * run_k
	var lift := lerpf(1.1, 1.9, run_k)
	var th_l := -s * amp * drag_l - knee * 0.5
	var th_r := s * amp * drag_r - knee * 0.5
	var sh_l := knee + maxf(0.0, c) * amp * lift * drag_l
	var sh_r := knee + maxf(0.0, -c) * amp * lift * drag_r
	var hips_y := _hips_rest_y - 0.025 - 0.035 * run_k + absf(c) * 0.035 * move_k
	var hip_roll := s * 0.05 * move_k + limp_side * limp * 0.05 * (1.0 - run_k) * absf(s)
	var hip_twist := s * 0.1 * move_k

	# --- Tronc voûté, qui tangue ---------------------------------------------
	var lean := hunch + run_k * 0.22 + sprint_k * 0.18
	var stagger := sin(ph * 0.5 + seed_phase) * sway * (1.0 - run_k * 0.6) + sin(_t * 0.9 + seed_phase) * 0.04
	var spine_x := lean * 0.55 + c * 0.03 * move_k
	var chest_x := lean * 0.45
	var chest_y := -s * (0.1 + 0.08 * run_k) * move_k
	var head_x := -(lean * 1.0 + 0.2) + sin(ph * 0.8) * 0.05
	var head_z := head_tilt + sin(_t * 0.6 + seed_phase) * 0.08 * (1.0 - run_k)
	var jaw := jaw_open + sin(_t * 2.3 + seed_phase) * 0.07

	# --- Bras -----------------------------------------------------------------
	# Compensation : bras qui pendent à la verticale malgré le buste penché.
	var hang := lean
	var al := 0.0
	var ar := 0.0
	var fl := -0.2
	var fr := -0.2
	var zl := -0.1
	var zr := 0.1
	match arm_style:
		Arms.REACH:
			al = -1.3 + reach + lean * 0.3 + s * 0.08 * move_k
			ar = -1.22 - reach + lean * 0.3 - s * 0.08 * move_k
			fl = -0.3
			fr = -0.22
		Arms.ONE_ARM:
			var up_l := limp_side > 0.0
			var reach_a := -1.35 + reach + lean * 0.3 + s * 0.06
			var hang_a := hang * 0.9 + 0.05
			al = reach_a if up_l else hang_a - s * 0.18 * move_k
			ar = hang_a + s * 0.18 * move_k if up_l else reach_a
			fl = -0.28 if up_l else -0.12
			fr = -0.12 if up_l else -0.28
			zl = -0.1 if up_l else 0.06
			zr = -0.06 if up_l else 0.1
		Arms.DANGLE:
			al = hang * 0.95 - 0.05 - s * 0.2 * move_k
			ar = hang * 0.95 - 0.05 + s * 0.2 * move_k
			fl = -0.15
			fr = -0.18
			zl = 0.08
			zr = -0.08
	# Course : bras ballants qui battent (coudes mous).
	if run_k > 0.0:
		var swing := 0.6 * move_k + 0.1
		var run_al := hang * 0.8 - 0.25 + s * swing
		var run_ar := hang * 0.8 - 0.25 - s * swing
		var run_f := lerpf(-0.55, -1.0, clampf((run_k - 0.65) / 0.35, 0.0, 1.0)) - absf(s) * 0.25
		al = lerpf(al, run_al, run_k)
		ar = lerpf(ar, run_ar, run_k)
		fl = lerpf(fl, run_f, run_k)
		fr = lerpf(fr, run_f, run_k)
		zl = lerpf(zl, 0.14, run_k)
		zr = lerpf(zr, -0.14, run_k)
	# Sprint : bras tendus vers la proie, qui battent.
	if sprint_k > 0.0:
		al = lerpf(al, -1.5 + lean * 0.4 + s * 0.35, sprint_k)
		ar = lerpf(ar, -1.45 + lean * 0.4 - s * 0.35, sprint_k)
		fl = lerpf(fl, -0.12, sprint_k)
		fr = lerpf(fr, -0.12, sprint_k)
		zl = lerpf(zl, -0.08, sprint_k)
		zr = lerpf(zr, 0.08, sprint_k)
		head_x = lerpf(head_x, -(lean + 0.35), sprint_k)

	var root_y := 0.0
	# --- Émergence : les mains d'abord, puis la tête, puis tout le corps ----
	if state == Zombie.State.EMERGE:
		var k := clampf(z.state_time / Zombie.EMERGE_TIME, 0.0, 1.0)
		root_y = _keys(k, K_EMERGE_ROOT)
		var claw := sin(_t * 11.0) * 0.12
		var up := 1.0 - smoothstep(0.3, 0.55, k)
		var push := smoothstep(0.3, 0.55, k) * (1.0 - smoothstep(0.8, 1.0, k))
		al = lerpf(lerpf(al, 0.1, push), -3.0 + claw, up)
		ar = lerpf(lerpf(ar, 0.15, push), -2.9 - claw, up)
		fl = lerpf(lerpf(fl, -1.1, push), -0.1, up)
		fr = lerpf(lerpf(fr, -1.1, push), -0.1, up)
		zl = lerpf(zl, 0.45, push)
		zr = lerpf(zr, -0.45, push)
		var climb := smoothstep(0.35, 0.6, k) * (1.0 - smoothstep(0.85, 1.0, k))
		spine_x = lerpf(spine_x, 0.7, climb)
		chest_x = lerpf(chest_x, 0.35, climb)
		head_x = lerpf(head_x, -0.9, climb + up * 0.6)
		# Une jambe enjambe le bord du trou.
		var step := smoothstep(0.6, 0.8, k) * (1.0 - smoothstep(0.9, 1.0, k))
		th_l = lerpf(th_l, -1.1, step)
		sh_l = lerpf(sh_l, 1.4, step)
		jaw = lerpf(jaw, 0.55, up)

	# --- Fenêtre : arrachage des planches / enjambement ---------------------
	var tearing := state == Zombie.State.BARRIER and spd < 0.4
	# Porte à zombies (format 8) : enjambée comme une fenêtre (battant cassé
	# à mi-hauteur, à hauteur d'allège).
	if state == Zombie.State.VAULT:
		var vk := clampf(z.state_time / BarricadeRules.VAULT_TIME, 0.0, 1.0)
		var v := sin(vk * PI)
		root_y = v * 0.95
		spine_x += v * 0.9
		chest_x += v * 0.3
		head_x -= v * 0.9
		th_l = _keys(vk, K_VAULT_THIGH_L)
		th_r = _keys(vk, K_VAULT_THIGH_R)
		sh_l = _keys(vk, K_VAULT_SHIN_L)
		sh_r = _keys(vk, K_VAULT_SHIN_R)
		# Mains en appui sur l'allège puis bras qui se relèvent.
		al = _keys(vk, K_VAULT_ARM_L)
		ar = _keys(vk, K_VAULT_ARM_R)
		fl = -0.35
		fr = -0.35
	elif tearing:
		var tt := clampf(z.tear_t / BarricadeRules.TEAR_PULL, 0.0, 1.0)
		# Agrippe (bras tendus vers la planche), tire en se jetant en
		# arrière (coudes ramenés), puis jette la planche sur le côté.
		al = _keys(tt, K_TEAR_ARM_L)
		ar = _keys(tt, K_TEAR_ARM_R)
		fl = _keys(tt, K_TEAR_FOREARM_L)
		fr = _keys(tt, K_TEAR_FOREARM_R)
		zl = -0.1
		zr = _keys(tt, K_TEAR_ARM_R_Z)
		spine_x = _keys(tt, K_TEAR_SPINE)
		chest_x = _keys(tt, K_TEAR_CHEST_X)
		chest_y = _keys(tt, K_TEAR_CHEST_Y)
		head_x = -0.55
		jaw = jaw_open + 0.15 * sin(_t * 5.0)
		# Pieds plantés, l'un devant l'autre.
		th_l = -0.3
		sh_l = 0.35
		th_r = 0.15
		sh_r = 0.25
		hip_twist = 0.0
		hip_roll = 0.0
		# Pause « de folie » entre deux planches : fondu depuis la fin du geste
		# (0,25 s), et retour fondu au début du geste suivant (0,2 s).
		var fw := smoothstep(0.0, 0.25, z.tear_t) if z.tear_frenzy else 1.0 - smoothstep(0.0, 0.2, z.tear_t)
		if fw > 0.0:
			var f := _fz
			frenzy_pose(f, _t, seed_phase, head_tilt, jaw_open)
			al = lerpf(al, f[0], fw)
			ar = lerpf(ar, f[1], fw)
			fl = lerpf(fl, f[2], fw)
			fr = lerpf(fr, f[3], fw)
			zl = lerpf(zl, f[4], fw)
			zr = lerpf(zr, f[5], fw)
			spine_x = lerpf(spine_x, f[6], fw)
			chest_x = lerpf(chest_x, f[7], fw)
			chest_y = lerpf(chest_y, f[8], fw)
			head_x = lerpf(head_x, f[9], fw)
			head_z = lerpf(head_z, f[10], fw)
			jaw = lerpf(jaw, f[11], fw)
			sh_l = lerpf(sh_l, f[12], fw)
			sh_r = lerpf(sh_r, f[13], fw)
			hips_y -= 0.03 * fw * absf(sin(_t * FRENZY_RATE * 2.0 + seed_phase))

	# --- Attaque : griffes à deux bras ---------------------------------------
	if z.attack_t >= 0.0:
		z.attack_t += delta / 0.7
		var at := clampf(z.attack_t, 0.0, 1.0)
		var w := smoothstep(0.0, 0.12, at) * (1.0 - smoothstep(0.8, 1.0, at))
		var a_r := _keys(at, K_ATTACK_ARM_R)
		var a_l := _keys(at, K_ATTACK_ARM_L)
		al = lerpf(al, a_l, w)
		ar = lerpf(ar, a_r, w)
		fl = lerpf(fl, _keys(at, K_ATTACK_FOREARM_L), w)
		fr = lerpf(fr, _keys(at, K_ATTACK_FOREARM_R), w)
		zl = lerpf(zl, -0.2, w)
		zr = lerpf(zr, 0.2, w)
		spine_x = lerpf(spine_x, _keys(at, K_ATTACK_SPINE), w)
		chest_y = lerpf(chest_y, _keys(at, K_ATTACK_CHEST_Y), w)
		head_x = lerpf(head_x, -0.45, w)
		jaw = lerpf(jaw, 0.62, w)
		if z.attack_t >= 1.0:
			z.attack_t = -1.0

	skel.position.y = root_y
	skel.set_bone_pose_position(z.bones.hips, Vector3(0, hips_y, 0))
	skel.set_bone_pose_rotation(_bi[0], _q(0.0, hip_twist, hip_roll))
	skel.set_bone_pose_rotation(_bi[1], _q(spine_x, -hip_twist * 0.5, stagger))
	skel.set_bone_pose_rotation(_bi[2], _q(chest_x, chest_y, -stagger * 0.5))
	skel.set_bone_pose_rotation(_bi[3], _q(0.25, 0.0, 0.0))
	skel.set_bone_pose_rotation(_bi[4], _q(head_x, 0.0, head_z))
	skel.set_bone_pose_rotation(_bi[5], _q(jaw))
	skel.set_bone_pose_rotation(_bi[6], _q(th_l, 0.0, 0.03))
	skel.set_bone_pose_rotation(_bi[7], _q(th_r, 0.0, -0.03))
	skel.set_bone_pose_rotation(_bi[8], _q(sh_l))
	skel.set_bone_pose_rotation(_bi[9], _q(sh_r))
	skel.set_bone_pose_rotation(_bi[10], _q(al, 0.0, zl))
	skel.set_bone_pose_rotation(_bi[11], _q(ar, 0.0, zr))
	skel.set_bone_pose_rotation(_bi[12], _q(fl + c * 0.06 * move_k))
	skel.set_bone_pose_rotation(_bi[13], _q(fr - c * 0.06 * move_k))


# --------------------------------------------------------------------------
# Morts
# --------------------------------------------------------------------------

## Choisit la mort (déterministe : même mort sur toutes les machines).
func start_death(headshot: bool) -> void:
	if headshot:
		death_style = Death.STIFF
	else:
		death_style = [Death.TOPPLE, Death.CRUMPLE, Death.SPIN][posmod(z.id * 7 + z.variant, 3)]


## Chute (avant DEATH_SETTLE_TIME) ; `dir` = ±1 (coup venu de l'arrière/avant).
func death(delta: float, t: float, dir: float) -> void:
	var skel := z.skel
	var blend := minf(delta * 6.0, 1.0)
	if z.is_crawler():
		# Déjà au sol : s'affaisse, bras écartés, tête qui retombe.
		_slerp("arm_l", _q(-2.2, 0.0, -0.4), blend)
		_slerp("arm_r", _q(-2.0, 0.0, 0.5), blend)
		_slerp("forearm_l", _q(-0.2), blend)
		_slerp("forearm_r", _q(-0.3), blend)
		_slerp("head", _q(0.2, 0.0, 0.5), blend)
		_slerp("jaw", _q(0.5), blend)
		return
	var k := ease(clampf(t / 0.65, 0.0, 1.0), 0.4)
	_slerp("jaw", _q(0.6), blend)
	match death_style:
		Death.TOPPLE:
			skel.rotation = Vector3(dir * k * PI * 0.47, 0.0, 0.0)
			skel.position.y = -k * 0.08
			var buckle := sin(clampf(t / 0.5, 0.0, 1.0) * PI) * 0.6
			_slerp("thigh_l", _q(-buckle), blend)
			_slerp("thigh_r", _q(-buckle * 0.6), blend)
			_slerp("shin_l", _q(buckle * 1.2), blend)
			_slerp("shin_r", _q(buckle), blend)
			# Bras projetés, puis inertes.
			var fling := -0.5 * dir - 1.2 * (1.0 - k) if dir < 0.0 else -0.4
			_slerp("arm_l", _q(fling, 0.0, 0.3), blend)
			_slerp("arm_r", _q(fling * 0.8, 0.0, -0.5), blend)
			_slerp("spine", _q(0.1 * dir), blend)
			_slerp("chest", Quaternion.IDENTITY, blend)
			_slerp("head", _q(0.3 * dir, 0.0, 0.4), blend)
		Death.CRUMPLE:
			# À genoux, puis face contre terre.
			var kneel := smoothstep(0.0, 0.4, t)
			var fall := smoothstep(0.4, 1.0, t)
			skel.rotation = Vector3(fall * PI * 0.45, 0.0, 0.0)
			skel.position = Vector3(0.0, -kneel * (1.0 - fall) * 0.42 - fall * 0.08, -fall * 0.35)
			_slerp("thigh_l", _q(lerpf(-1.45, -0.1, fall) * kneel), blend)
			_slerp("thigh_r", _q(lerpf(-1.35, 0.1, fall) * kneel), blend)
			_slerp("shin_l", _q(lerpf(2.3, 0.5, fall) * kneel), blend)
			_slerp("shin_r", _q(lerpf(2.2, 0.3, fall) * kneel), blend)
			_slerp("spine", _q(lerpf(0.55, 0.05, fall)), blend)
			_slerp("chest", _q(0.2 * (1.0 - fall)), blend)
			_slerp("arm_l", _q(lerpf(0.3, -2.6, fall), 0.0, 0.3), blend)
			_slerp("arm_r", _q(lerpf(0.2, -2.3, fall), 0.0, -0.4), blend)
			_slerp("forearm_l", _q(-0.3), blend)
			_slerp("forearm_r", _q(-0.6), blend)
			_slerp("head", _q(lerpf(0.5, -0.4, fall), 0.0, 0.6 * fall), blend)
		Death.SPIN:
			# Vrille et tombe sur le côté.
			var side := dir * (1.0 if z.variant % 2 == 0 else -1.0)
			skel.rotation = Vector3(0.15 * dir * k, side * k * 1.3, side * k * PI * 0.46)
			skel.position.y = -k * 0.06
			_slerp("arm_l", _q(-0.6, 0.0, 1.3 * k), blend)
			_slerp("arm_r", _q(-1.0, 0.0, -0.9 * k), blend)
			_slerp("thigh_l", _q(-0.5 * k, 0.0, 0.2), blend)
			_slerp("shin_l", _q(0.9 * k), blend)
			_slerp("thigh_r", _q(-0.1), blend)
			_slerp("shin_r", _q(0.3), blend)
			_slerp("spine", _q(0.2, 0.3 * side, 0.0), blend)
			_slerp("head", _q(0.2, 0.0, -0.6 * side), blend)
		Death.STIFF:
			# Tir à la tête : le corps s'effondre raide, bras en croix.
			var ks := ease(clampf(t / 0.5, 0.0, 1.0), 0.35)
			skel.rotation = Vector3(dir * ks * PI * 0.48, 0.0, 0.0)
			skel.position.y = -ks * 0.08
			_slerp("arm_l", _q(-0.5, 0.0, 0.9 * ks), blend)
			_slerp("arm_r", _q(-0.4, 0.0, -0.8 * ks), blend)
			_slerp("forearm_l", _q(-0.1), blend)
			_slerp("forearm_r", _q(-0.2), blend)
			for b: String in STIFF_BONES:
				_slerp(b, Quaternion.IDENTITY, blend)


func _slerp(b: String, target: Quaternion, w: float) -> void:
	var i: int = z.bones[b]
	z.skel.set_bone_pose_rotation(i, z.skel.get_bone_pose_rotation(i).slerp(target, w))
