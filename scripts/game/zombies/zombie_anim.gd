class_name ZombieAnim
extends RefCounted
## Animations procédurales des zombies (toutes les machines, purement
## cosmétique) : écrit les rotations d'os du squelette RigBuilder. Réglées
## pour le zombie CUBIQUE (ZombieModel, cubes de 2,5 cm) : grosse tête posée
## sur le buste, bras longs écartés du torse, jambes courtes dans une blouse
## dont le bas suit les cuisses. Chaque pièce est rigide : les poses évitent
## qu'elles se traversent (tests/test_zombie_voxel_anim.gd mesure les cubes
## qui se chevauchent à chaque image clé).
##
## * Marche traînante (classe 0) : petits pas, jambe qui traîne (boiterie
##   propre à chaque zombie), une épaule plus basse, tête qui oscille, buste
##   qui tangue ; bras tendus devant, un seul bras levé, ou bras ballants.
## * Course (classes 1, 2) et sprint (3) : penché en avant, BRAS TENDUS VERS
##   L'AVANT qui battent, plus haut et plus raides au sprint.
## * Attaque : coup de griffes à deux bras (armé au-dessus de la tête, frappe
##   plongeante, le bras droit mène), mâchoire qui claque en avant.
## * Sortie du sol : UNE main crève le sol, puis l'autre ; les mains se
##   posent à plat sur le sol et le corps se hisse (tête, épaules, buste), une
##   jambe enjambe le bord du trou.
## * Fenêtre / porte barricadée : les deux mains agrippent la planche du haut,
##   le zombie se jette en arrière (les deux mains tirent vers l'arrière, la
##   planche cède à BarricadeRules.TEAR_RIP), la jette derrière lui, une
##   planche par geste ; entre deux planches, pause « de folie » (frappe les
##   planches à coups de bras alternés). Passage : mains sur l'appui, il se
##   hisse, bascule à plat ventre par-dessus (jambes tendues derrière), puis
##   ramène les jambes et se redresse dedans.
## * Morts variées (chute procédurale : qualité BASSE ou plafond de ragdolls) :
##   bascule avant/arrière, effondrement à genoux puis face contre terre,
##   vrille sur le côté, chute raide (tir à la tête) ; le corps se pose sur
##   sa face (épaisseur du modèle), sans s'enfoncer dans le sol.
##
## Rappels du repère (os au repos, membres pendants vers -Y, modèle vers +Z) :
## rotation X négative = membre vers l'avant ; tibia positif = genou plié ;
## tronc positif = penché en avant ; tête positive = regard vers le bas ;
## rotation Z positive = bras GAUCHE écarté vers l'extérieur (droit : négative).
## Un bras pend à la verticale quand sa rotation X vaut moins l'inclinaison du
## buste (angle « monde » = bras + buste).

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
## Tête : écart d'angle avec le buste (rad) au-delà duquel la grosse tête
## cubique mordrait sur les épaules ; la tête pivote en plus sur l'arête de
## sa base qui s'abaisse (_set_head).
const HEAD_UP := -0.32
const HEAD_DOWN := 0.3
## Sortie du sol : hauteur du corps (m, 0 = debout).
const K_EMERGE_ROOT := [[0.0, -2.25], [0.22, -2.0], [0.4, -1.7], [0.6, -1.05], [0.82, -0.35], [1.0, 0.0]]
## Passage : bascule du bassin (corps à plat ventre au milieu), hauteur,
## angle MONDE des bras (0 : vers le bas), cuisses (+ : tendues derrière) et
## tibias.
const K_VAULT_PITCH := [[0.0, 0.12], [0.22, 0.6], [0.5, 1.35], [0.75, 0.85], [1.0, 0.12]]
const K_VAULT_ROOT := [[0.0, 0.0], [0.22, 0.3], [0.5, 0.45], [0.75, 0.2], [1.0, 0.0]]
const K_VAULT_ARM_W := [[0.0, -1.1], [0.2, -0.35], [0.45, -0.1], [0.62, -0.45], [0.8, -0.15], [1.0, -1.2]]
const K_VAULT_THIGH_L := [[0.0, -0.1], [0.22, 0.3], [0.5, 0.12], [0.68, -0.65], [0.85, -0.45], [1.0, -0.12]]
const K_VAULT_THIGH_R := [[0.0, 0.05], [0.22, 0.4], [0.5, 0.18], [0.75, -0.5], [0.9, -0.3], [1.0, 0.0]]
const K_VAULT_SHIN := [[0.0, 0.2], [0.22, 0.9], [0.5, 0.45], [0.7, 1.15], [1.0, 0.2]]
## Arrachage (t = fraction de TEAR_PULL ; la planche cède à 0,7) : bras et
## avant-bras (relatifs au buste), écart, dos, buste, cuisses.
const K_TEAR_ARM := [[0.0, -1.45], [0.25, -1.95], [0.45, -1.8], [0.7, -0.55], [0.85, 0.35], [1.0, -1.45]]
const K_TEAR_FOREARM := [[0.0, -0.35], [0.25, -0.3], [0.45, -0.7], [0.7, -0.9], [0.85, -0.35], [1.0, -0.35]]
const K_TEAR_ARM_Z := [[0.0, 0.0], [0.7, 0.04], [0.85, 0.12], [1.0, 0.0]]
const K_TEAR_SPINE := [[0.0, 0.25], [0.25, 0.38], [0.45, 0.25], [0.7, -0.18], [0.85, -0.08], [1.0, 0.25]]
const K_TEAR_CHEST_X := [[0.0, 0.1], [0.25, 0.15], [0.7, -0.08], [1.0, 0.1]]
const K_TEAR_CHEST_Y := [[0.0, 0.0], [0.7, 0.05], [0.85, 0.32], [1.0, 0.0]]
const K_TEAR_THIGH_L := [[0.0, -0.05], [0.25, -0.1], [0.7, -0.28], [1.0, -0.05]]
const K_TEAR_THIGH_R := [[0.0, 0.22], [0.25, 0.25], [0.7, 0.08], [1.0, 0.22]]
const K_ATTACK_ARM_R := [[0.0, -1.3], [0.28, -2.45], [0.5, -0.85], [0.7, -1.0], [1.0, -1.2]]
const K_ATTACK_ARM_L := [[0.0, -1.3], [0.32, -2.35], [0.56, -0.9], [0.75, -1.05], [1.0, -1.2]]
const K_ATTACK_FOREARM_L := [[0.0, -0.3], [0.3, -0.9], [0.55, -0.15], [1.0, -0.3]]
const K_ATTACK_FOREARM_R := [[0.0, -0.3], [0.26, -0.9], [0.48, -0.12], [1.0, -0.3]]
const K_ATTACK_ARM_Z := [[0.0, 0.02], [0.28, 0.1], [0.5, 0.02], [1.0, 0.02]]
const K_ATTACK_SPINE := [[0.0, 0.2], [0.28, 0.02], [0.5, 0.4], [1.0, 0.25]]
const K_ATTACK_CHEST_Y := [[0.0, 0.0], [0.28, 0.2], [0.5, -0.25], [1.0, 0.0]]
## À travers les planches (BO1) : le bras droit plonge dans le trou vers le
## joueur, la main se referme (coup porté à 0,6, Zombie.ATTACK_HIT_TIME) puis
## le bras revient ; le gauche reste en appui sur les planches, buste penché
## vers l'entrée, épaule droite en avant.
const K_REACH_ARM_R := [[0.0, -1.3], [0.3, -1.85], [0.6, -1.65], [0.8, -1.5], [1.0, -1.25]]
const K_REACH_FOREARM_R := [[0.0, -0.3], [0.3, -0.05], [0.55, -0.1], [0.7, -0.85], [1.0, -0.3]]
const K_REACH_ARM_L := [[0.0, -1.3], [0.3, -1.6], [0.8, -1.55], [1.0, -1.3]]
const K_REACH_FOREARM_L := [[0.0, -0.3], [0.3, -0.7], [0.8, -0.7], [1.0, -0.3]]
const K_REACH_SPINE := [[0.0, 0.25], [0.3, 0.45], [0.65, 0.42], [1.0, 0.25]]
const K_REACH_CHEST_Y := [[0.0, 0.0], [0.3, -0.35], [0.65, -0.3], [1.0, 0.0]]


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
## Épaule plus basse (rad, roulis du buste ; côté de la boiterie).
var shoulder_drop := 0.0
## Mélanges lissés (changement de classe de vitesse en cours de manche).
var run_k := 0.0
var sprint_k := 0.0
var death_style: int = Death.TOPPLE
var _t := 0.0
## Indices des os écrits à chaque pose (ordre de POSE_BONES), repos du bassin
## et de la tête, longueur du bras (épaule -> paume).
var _bi := PackedInt32Array()
var _hips_rest_y := 0.95
var _head_rest := Vector3.ZERO
var _shoulder_y := 0.45
var _arm_len := 0.75
## Ouverture de la mâchoire -> rotation de l'os : le zombie cubique a la
## bouche sous l'avant de la tête, devant le col ; elle s'ouvre en avançant
## le menton (sinon il rentrerait dans le buste).
var _jaw_dir := 1.0
## Pose de folie de l'image (frenzy_pose), réutilisée : aucune allocation.
var _fz: Array = []
## Coins des pièces de chaque os (repère de l'os, modèle cubique) : le corps
## est posé sur le sol par son point le plus bas (ground). Indices d'os.
var _corners := {}
var _feet := PackedInt32Array()
var _all := PackedInt32Array()
## Tête des morts (rotation lissée, voir death).
var _dead_hx := 0.0
var _dead_hz := 0.0


func _init(zombie: Zombie) -> void:
	z = zombie
	for b in POSE_BONES:
		_bi.append(z.bones[b])
	_hips_rest_y = z.skel.get_bone_rest(z.bones.hips).origin.y
	_head_rest = z.skel.get_bone_rest(z.bones.head).origin
	var sh := z.skel.get_bone_global_rest(z.bones.arm_l).origin
	_shoulder_y = sh.y - _hips_rest_y
	_arm_len = z.skel.get_bone_rest(z.bones.forearm_l).origin.length() + 0.42
	var bb := ZombieModel.bone_bounds()
	if not bb.is_empty():
		_jaw_dir = -0.5
		_arm_len = z.skel.get_bone_rest(z.bones.forearm_l).origin.length() + (bb.forearm_l as AABB).size.y * 0.85
		for b: String in bb:
			var box: AABB = bb[b]
			var o := z.skel.get_bone_global_rest(z.bones[b]).origin
			var pts := PackedVector3Array()
			for i in 8:
				pts.append(box.get_endpoint(i) - o)
			_corners[z.bones[b]] = pts
			_all.append(z.bones[b])
		_feet = PackedInt32Array([z.bones.shin_l, z.bones.shin_r])
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
	shoulder_drop = rng.randf_range(0.07, 0.13) * limp_side
	var cls := z.speed_class
	run_k = _run_target(cls)
	sprint_k = 1.0 if cls >= 3 else 0.0
	_fz.resize(FRENZY_VALUES)
	_fz.fill(0.0)


static func _q(x: float, y := 0.0, zr := 0.0) -> Quaternion:
	return Quaternion.from_euler(Vector3(x, y, zr))


## Tête (rotation relative au cou) : la grosse tête cubique pivote sur
## l'arête de sa base qui descend (arrière quand elle se relève, menton quand
## elle s'incline, côté quand elle penche) au lieu de son centre : elle ne
## s'enfonce pas dans les épaules. Utilisé aussi par le rampant (ZombieGibs).
func set_head(hx: float, hz: float) -> void:
	var r := Basis.from_euler(Vector3(hx, 0.0, hz))
	var c := Vector3(-0.2 * signf(hz), -0.12 if hx > 0.0 else 0.0, 0.2 if hx > 0.0 else -0.2)
	z.skel.set_bone_pose_rotation(_bi[4], r.get_rotation_quaternion())
	z.skel.set_bone_pose_position(_bi[4], _head_rest + c - r * c)


## Mâchoire ouverte de `open` (0 : fermée, ~0,6 : grande ouverte).
func set_jaw(open: float) -> void:
	z.skel.set_bone_pose_rotation(_bi[5], _q(open * _jaw_dir))


## Pause « de folie » à la fenêtre, entre deux planches : le zombie frappe
## les planches à coups de bras alternés (levés au-dessus de la tête, griffes
## repliées, puis abattus), épaules qui vrillent, buste qui pompe à chaque
## coup, tête secouée, mâchoire grande ouverte, genoux qui rebondissent.
## Écrit dans `out` (FRENZY_VALUES valeurs) : bras g/d, avant-bras g/d,
## écart des bras g/d (vers l'extérieur : la tête est entre les bras levés),
## dos, buste (avant, torsion), tête (avant, roulis), mâchoire, tibias g/d.
## `phase` décale chaque zombie (pas de cadence commune).
static func frenzy_pose(out: Array, t: float, phase: float, tilt: float, jaw0: float) -> void:
	var ph := t * FRENZY_RATE + phase
	var raise_l := 0.5 + 0.5 * sin(ph)
	var raise_r := 0.5 + 0.5 * sin(ph + PI * 0.9)
	out[0] = lerpf(-1.35, -2.45, raise_l)
	out[1] = lerpf(-1.35, -2.4, raise_r)
	out[2] = lerpf(-0.25, -1.0, raise_l)
	out[3] = lerpf(-0.25, -1.0, raise_r)
	out[4] = 0.04 + 0.08 * raise_l
	out[5] = -0.04 - 0.08 * raise_r
	out[6] = 0.22 + 0.1 * absf(sin(ph))
	out[7] = 0.1 + 0.08 * absf(sin(ph + 0.6))
	out[8] = 0.2 * sin(ph)
	out[9] = -0.28 + 0.1 * sin(ph * 2.0 + 0.4)
	out[10] = tilt + 0.22 * sin(t * 7.3 + phase * 1.7)
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


## Angle (relatif au buste incliné de `lean`) d'un bras dont la paume se pose
## sur le sol, l'épaule étant à `h` m au-dessus : bras tendu vers l'avant,
## vers le haut si l'épaule est sous le sol (sortie du sol).
func _planted(h: float, lean: float) -> float:
	return -acos(clampf(h / _arm_len, -1.0, 1.0)) - lean


## Point le plus bas (m, repère du zombie) des pièces des os `ids` dans la
## pose courante ; INF sans modèle cubique.
func lowest(ids: PackedInt32Array) -> float:
	var skel := z.skel
	var xf := skel.transform
	var low := INF
	for bi in ids:
		var g := xf * skel.get_bone_global_pose(bi)
		for c: Vector3 in _corners[bi]:
			low = minf(low, (g * c).y)
	return low


## Pose le corps sur le sol : son point le plus bas (pieds seuls si `feet`)
## à y = 0. Rien sans modèle cubique (zombies procéduraux : réglages fixes).
func ground(feet: bool) -> void:
	if _corners.is_empty():
		return
	var low := lowest(_feet if feet else _all)
	if is_finite(low):
		z.skel.position.y -= low


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
	# Longueur d'un pas : la cadence suit la vitesse réelle (pas de glisse) ;
	# jambes courtes : petits pas rapides.
	var stride := lerpf(0.34, 0.66, run_k) + 0.14 * sprint_k
	z.gait_phase += delta * (PI * spd / stride + 0.5)
	var ph := z.gait_phase
	var s := sin(ph)
	var c := cos(ph)
	var move_k := clampf(spd / lerpf(0.9, 2.2, run_k), 0.0, 1.0)
	var state := z.state

	# --- Jambes : petits pas traînants, boiterie (jambe qui traîne) ---------
	var amp := (lerpf(0.26, 0.42, run_k) + 0.1 * sprint_k) * move_k
	var drag_l := 1.0 - (limp * 0.55 if limp_side > 0.0 else 0.0) * (1.0 - run_k)
	var drag_r := 1.0 - (limp * 0.55 if limp_side < 0.0 else 0.0) * (1.0 - run_k)
	var knee := 0.1 + 0.2 * run_k
	var lift := lerpf(0.8, 1.7, run_k)
	var th_l := -s * amp * drag_l - knee * 0.4
	var th_r := s * amp * drag_r - knee * 0.4
	var sh_l := knee + maxf(0.0, c) * amp * lift * drag_l
	var sh_r := knee + maxf(0.0, -c) * amp * lift * drag_r
	var hips_y := _hips_rest_y - 0.02 - 0.03 * run_k + absf(c) * 0.025 * move_k
	var hip_roll := s * 0.05 * move_k + limp_side * limp * 0.05 * (1.0 - run_k) * absf(s)
	var hip_twist := s * 0.08 * move_k
	var hips_x := 0.0

	# --- Tronc voûté (le modèle l'est déjà au repos), qui tangue --------------
	var lean := 0.1 + hunch * 0.3 + run_k * 0.18 + sprint_k * 0.18
	var stagger := sin(ph * 0.5 + seed_phase) * sway * (1.0 - run_k * 0.6) + sin(_t * 0.9 + seed_phase) * 0.04
	var spine_x := lean * 0.55 + c * 0.03 * move_k
	var chest_x := lean * 0.45
	var chest_y := -s * (0.08 + 0.06 * run_k) * move_k
	# Une épaule plus basse (roulis du buste), moins marquée en course.
	var chest_z := shoulder_drop * (1.0 - 0.5 * run_k) - stagger * 0.5
	# Tête : regard vers l'avant malgré le buste penché, dans la limite des
	# épaules ; oscille en marchant (dodeline, hoche).
	var walk_k := 1.0 - run_k * 0.7
	var head_x := -minf(lean, -HEAD_UP) + 0.1 + sin(ph * 2.0) * 0.06 * move_k * walk_k
	var head_z := head_tilt * 0.5 + sin(ph * 0.5 + seed_phase) * 0.15 * walk_k + sin(_t * 0.6 + seed_phase) * 0.05
	var jaw := jaw_open + sin(_t * 2.3 + seed_phase) * 0.07

	# --- Bras (angles « monde » convertis : buste incliné de `lean`) ----------
	var al := 0.0
	var ar := 0.0
	var fl := -0.2
	var fr := -0.2
	# Écart : vers l'extérieur quand le bras pend (le torse est contre lui),
	# légèrement vers l'intérieur une fois tendu devant.
	var zl := 0.05
	var zr := -0.05
	var low_l := shoulder_drop > 0.0
	match arm_style:
		Arms.REACH:
			al = -1.45 - lean + reach + s * 0.08 * move_k
			ar = -1.4 - lean - reach - s * 0.08 * move_k
			fl = -0.25
			fr = -0.2
			zl = 0.0
			zr = 0.0
		Arms.ONE_ARM:
			# Le bras du côté de l'épaule basse pend et ballotte.
			var reach_a := -1.45 - lean + reach + s * 0.06
			var hang_a := -lean + 0.05
			al = hang_a - s * 0.18 * move_k if low_l else reach_a
			ar = reach_a if low_l else hang_a + s * 0.18 * move_k
			fl = -0.12 if low_l else -0.28
			fr = -0.28 if low_l else -0.12
			zl = 0.06 if low_l else 0.0
			zr = 0.0 if low_l else -0.06
		Arms.DANGLE:
			al = -lean - 0.05 - s * 0.2 * move_k
			ar = -lean - 0.05 + s * 0.2 * move_k
			fl = -0.15
			fr = -0.18
			zl = 0.07
			zr = -0.07
	# Course : bras tendus vers l'avant, qui battent (coudes mous).
	if run_k > 0.0:
		var swing := 0.25 * move_k + 0.05
		var run_al := -1.35 - lean + s * swing
		var run_ar := -1.35 - lean - s * swing
		var run_f := -0.35 - absf(s) * 0.2
		al = lerpf(al, run_al, run_k)
		ar = lerpf(ar, run_ar, run_k)
		fl = lerpf(fl, run_f, run_k)
		fr = lerpf(fr, run_f, run_k)
		zl = lerpf(zl, 0.0, run_k)
		zr = lerpf(zr, 0.0, run_k)
	# Sprint : bras raides tendus vers la proie, plus haut, qui battent fort.
	if sprint_k > 0.0:
		al = lerpf(al, -1.6 - lean + s * 0.3, sprint_k)
		ar = lerpf(ar, -1.55 - lean - s * 0.3, sprint_k)
		fl = lerpf(fl, -0.12, sprint_k)
		fr = lerpf(fr, -0.12, sprint_k)
		zl = lerpf(zl, 0.0, sprint_k)
		zr = lerpf(zr, 0.0, sprint_k)

	var root_y := 0.0
	var pitch := 0.0
	# --- Sortie du sol : une main, puis l'autre, puis le corps se hisse ------
	if state == Zombie.State.EMERGE:
		var k := clampf(z.state_time / Zombie.EMERGE_TIME, 0.0, 1.0)
		root_y = _keys(k, K_EMERGE_ROOT)
		var climb := smoothstep(0.35, 0.6, k) * (1.0 - smoothstep(0.85, 1.0, k))
		var e_lean := 0.45 * climb
		spine_x = lerpf(spine_x, e_lean * 0.6, climb)
		chest_x = lerpf(chest_x, e_lean * 0.4, climb)
		var lean_now := spine_x + chest_x
		# Épaules : hauteur au-dessus du sol ; paumes posées à plat devant.
		var h := root_y + hips_y + _shoulder_y * cos(lean_now)
		var planted := _planted(h - 0.03, lean_now)
		var claw := sin(_t * 11.0) * 0.12
		var lead_l := limp_side > 0.0
		# Main de tête : crève le sol (bras tendu vers le haut, griffe), puis
		# se pose ; l'autre la suit (cachée sous terre, puis posée).
		var lead_a := lerpf(-2.95 + claw - lean_now, planted, smoothstep(0.26, 0.36, k))
		var other_a := lerpf(-0.3 - lean_now, planted, smoothstep(0.28, 0.42, k))
		var out := smoothstep(0.84, 1.0, k)
		al = lerpf(lead_a if lead_l else other_a, al, out)
		ar = lerpf(other_a if lead_l else lead_a, ar, out)
		var push := smoothstep(0.3, 0.45, k) * (1.0 - out)
		fl = lerpf(lerpf(fl, -0.1, 1.0 - out), -0.02, push)
		fr = lerpf(lerpf(fr, -0.1, 1.0 - out), -0.02, push)
		zl = lerpf(zl, 0.12, 1.0 - out)
		zr = lerpf(zr, -0.12, 1.0 - out)
		# Tête relevée vers la surface, mâchoire grande ouverte.
		head_x = lerpf(head_x, HEAD_UP, 1.0 - out)
		# Une jambe enjambe le bord du trou.
		var step := smoothstep(0.62, 0.8, k) * (1.0 - smoothstep(0.9, 1.0, k))
		var l_step := not lead_l
		th_l = lerpf(th_l, -0.6, step if l_step else step * 0.3)
		sh_l = lerpf(sh_l, 1.2, step if l_step else step * 0.3)
		th_r = lerpf(th_r, -0.6, step * 0.3 if l_step else step)
		sh_r = lerpf(sh_r, 1.2, step * 0.3 if l_step else step)
		jaw = lerpf(jaw, 0.6, 1.0 - out)

	# --- Fenêtre : arrachage des planches / passage ---------------------------
	var tearing := state == Zombie.State.BARRIER and spd < 0.4
	# Porte à zombies (format 8) : passée comme une fenêtre (battant cassé
	# à mi-hauteur, à hauteur d'allège).
	if state == Zombie.State.VAULT:
		var vk := clampf(z.state_time / BarricadeRules.VAULT_TIME, 0.0, 1.0)
		pitch = _keys(vk, K_VAULT_PITCH)
		root_y = _keys(vk, K_VAULT_ROOT)
		spine_x = 0.08
		chest_x = 0.05
		chest_y = 0.0
		chest_z = 0.0
		var body := pitch + spine_x + chest_x
		var aw := _keys(vk, K_VAULT_ARM_W)
		al = aw - body
		ar = aw - body - 0.08
		fl = -0.2
		fr = -0.25
		zl = 0.1
		zr = -0.1
		th_l = _keys(vk, K_VAULT_THIGH_L)
		th_r = _keys(vk, K_VAULT_THIGH_R)
		sh_l = _keys(vk, K_VAULT_SHIN)
		sh_r = _keys(clampf(vk - 0.06, 0.0, 1.0), K_VAULT_SHIN)
		hip_twist = 0.0
		hip_roll = 0.0
		# Regard vers l'avant, dans la limite des épaules.
		head_x = HEAD_UP * smoothstep(0.1, 0.4, vk) * (1.0 - smoothstep(0.75, 1.0, vk))
		head_z = head_tilt * 0.4
		jaw = jaw_open + 0.2
	elif tearing:
		var tt := clampf(z.tear_t / BarricadeRules.TEAR_PULL, 0.0, 1.0)
		# Agrippe la planche du haut à deux mains, tire en se jetant en
		# arrière (les deux mains ramenées vers l'arrière, coudes derrière),
		# puis la jette derrière lui.
		var arm := _keys(tt, K_TEAR_ARM)
		al = arm
		ar = arm - 0.05
		fl = _keys(tt, K_TEAR_FOREARM)
		fr = fl
		zl = _keys(tt, K_TEAR_ARM_Z)
		zr = -zl
		spine_x = _keys(tt, K_TEAR_SPINE)
		chest_x = _keys(tt, K_TEAR_CHEST_X)
		chest_y = _keys(tt, K_TEAR_CHEST_Y)
		chest_z = shoulder_drop * 0.5
		var body := spine_x + chest_x
		# Regard sur la planche (vers le haut, sans quitter les épaules).
		head_x = clampf(-0.25 - body, HEAD_UP, HEAD_DOWN)
		head_z = head_tilt * 0.3
		jaw = jaw_open + 0.15 * sin(_t * 5.0) + 0.2 * smoothstep(0.45, 0.7, tt)
		# Pieds plantés, l'un devant l'autre ; bassin qui recule au moment
		# de l'arrachage (le poids part en arrière).
		th_l = _keys(tt, K_TEAR_THIGH_L)
		sh_l = 0.32
		th_r = _keys(tt, K_TEAR_THIGH_R)
		sh_r = 0.22
		hips_y -= 0.04 * smoothstep(0.45, 0.7, tt) * (1.0 - smoothstep(0.85, 1.0, tt))
		hips_x = 0.0
		hip_twist = 0.0
		hip_roll = 0.0
		# Pause « de folie » entre deux planches : fondu depuis la fin du geste
		# (0,25 s), et retour fondu au début du geste suivant (0,2 s).
		var fw := smoothstep(0.0, 0.25, z.tear_t) if z.tear_frenzy else 1.0 - smoothstep(0.0, 0.2, z.tear_t)
		if fw > 0.0:
			var f := _fz
			frenzy_pose(f, _t, seed_phase, head_tilt * 0.5, jaw_open)
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
		if z.attack_through:
			# Bras passé par le trou des planches, vers le joueur.
			al = lerpf(al, _keys(at, K_REACH_ARM_L), w)
			ar = lerpf(ar, _keys(at, K_REACH_ARM_R), w)
			fl = lerpf(fl, _keys(at, K_REACH_FOREARM_L), w)
			fr = lerpf(fr, _keys(at, K_REACH_FOREARM_R), w)
			zl = lerpf(zl, 0.0, w)
			zr = lerpf(zr, 0.0, w)
			spine_x = lerpf(spine_x, _keys(at, K_REACH_SPINE), w)
			chest_y = lerpf(chest_y, _keys(at, K_REACH_CHEST_Y), w)
		else:
			al = lerpf(al, _keys(at, K_ATTACK_ARM_L), w)
			ar = lerpf(ar, _keys(at, K_ATTACK_ARM_R), w)
			fl = lerpf(fl, _keys(at, K_ATTACK_FOREARM_L), w)
			fr = lerpf(fr, _keys(at, K_ATTACK_FOREARM_R), w)
			var az := _keys(at, K_ATTACK_ARM_Z)
			zl = lerpf(zl, az, w)
			zr = lerpf(zr, -az, w)
			spine_x = lerpf(spine_x, _keys(at, K_ATTACK_SPINE), w)
			chest_y = lerpf(chest_y, _keys(at, K_ATTACK_CHEST_Y), w)
		head_x = lerpf(head_x, clampf(-0.2 - spine_x - chest_x, HEAD_UP, HEAD_DOWN), w)
		jaw = lerpf(jaw, 0.62, w)
		if z.attack_t >= 1.0:
			z.attack_t = -1.0

	head_x = clampf(head_x, HEAD_UP, HEAD_DOWN)
	skel.position.y = root_y
	skel.rotation = Vector3.ZERO
	skel.set_bone_pose_position(_bi[0], Vector3(hips_x, hips_y, z.skel.get_bone_rest(_bi[0]).origin.z))
	skel.set_bone_pose_rotation(_bi[0], _q(pitch, hip_twist, hip_roll))
	skel.set_bone_pose_rotation(_bi[1], _q(spine_x, -hip_twist * 0.5, stagger))
	skel.set_bone_pose_rotation(_bi[2], _q(chest_x, chest_y, chest_z))
	skel.set_bone_pose_rotation(_bi[3], Quaternion.IDENTITY)
	set_head(head_x, head_z)
	set_jaw(jaw)
	# Cuisses légèrement écartées (les pans de la blouse ne se croisent pas).
	skel.set_bone_pose_rotation(_bi[6], _q(th_l, 0.0, 0.03))
	skel.set_bone_pose_rotation(_bi[7], _q(th_r, 0.0, -0.03))
	skel.set_bone_pose_rotation(_bi[8], _q(sh_l))
	skel.set_bone_pose_rotation(_bi[9], _q(sh_r))
	skel.set_bone_pose_rotation(_bi[10], _q(al, 0.0, zl))
	skel.set_bone_pose_rotation(_bi[11], _q(ar, 0.0, zr))
	skel.set_bone_pose_rotation(_bi[12], _q(fl + c * 0.06 * move_k))
	skel.set_bone_pose_rotation(_bi[13], _q(fr - c * 0.06 * move_k))
	# Debout : le pied le plus bas touche le sol (ni enfoncé, ni en l'air).
	if state != Zombie.State.EMERGE and state != Zombie.State.VAULT:
		ground(true)


# --------------------------------------------------------------------------
# Morts
# --------------------------------------------------------------------------

## Choisit la mort (déterministe : même mort sur toutes les machines).
func start_death(headshot: bool) -> void:
	var e := z.skel.get_bone_pose_rotation(_bi[4]).get_euler()
	_dead_hx = e.x
	_dead_hz = e.z
	if headshot:
		death_style = Death.STIFF
	else:
		death_style = [Death.TOPPLE, Death.CRUMPLE, Death.SPIN][posmod(z.id * 7 + z.variant, 3)]




## Chute (avant DEATH_SETTLE_TIME) ; `dir` = ±1 (coup venu de l'arrière/avant).
## Le corps tourne autour de ses pieds ; zombie cubique : il est ensuite posé
## sur le sol par son point le plus bas (face, dos, flanc, genoux : ground).
func death(delta: float, t: float, dir: float) -> void:
	var skel := z.skel
	var blend := minf(delta * 6.0, 1.0)
	if z.is_crawler():
		# Déjà au sol : s'affaisse, bras écartés, tête qui retombe.
		_slerp("arm_l", _q(-2.2, 0.0, 0.25), blend)
		_slerp("arm_r", _q(-2.0, 0.0, -0.25), blend)
		_slerp("forearm_l", _q(-0.2), blend)
		_slerp("forearm_r", _q(-0.3), blend)
		_head_to(-0.2, 0.3, blend)
		ground(false)
		return
	var k := ease(clampf(t / 0.65, 0.0, 1.0), 0.4)
	_slerp("jaw", _q(0.6 * _jaw_dir), blend)
	match death_style:
		Death.TOPPLE:
			skel.rotation = Vector3(dir * k * PI * 0.47, 0.0, 0.0)
			skel.position.y = -k * 0.08
			var buckle := sin(clampf(t / 0.5, 0.0, 1.0) * PI) * 0.6
			_slerp("thigh_l", _q(-buckle * 0.5, 0.0, 0.03), blend)
			_slerp("thigh_r", _q(-buckle * 0.3, 0.0, -0.03), blend)
			_slerp("shin_l", _q(buckle * 1.2), blend)
			_slerp("shin_r", _q(buckle), blend)
			# Bras projetés, puis inertes, écartés du corps.
			var fling := -0.5 * dir - 1.2 * (1.0 - k) if dir < 0.0 else -0.4
			_slerp("arm_l", _q(fling, 0.0, 0.18), blend)
			_slerp("arm_r", _q(fling * 0.8, 0.0, -0.22), blend)
			_slerp("spine", _q(0.05 * dir), blend)
			_slerp("chest", Quaternion.IDENTITY, blend)
			_head_to(0.15 * dir, 0.3, blend)
		Death.CRUMPLE:
			# À genoux (cuisses droites, tibias repliés au sol), puis face
			# contre terre.
			var kneel := smoothstep(0.0, 0.4, t)
			var fall := smoothstep(0.4, 1.0, t)
			skel.rotation = Vector3(fall * PI * 0.45, 0.0, 0.0)
			skel.position = Vector3(0.0, -kneel * (1.0 - fall) * 0.42 - fall * 0.08, -fall * 0.35)
			_slerp("thigh_l", _q(lerpf(-0.25, -0.05, fall) * kneel, 0.0, 0.05), blend)
			_slerp("thigh_r", _q(lerpf(-0.2, 0.05, fall) * kneel, 0.0, -0.05), blend)
			_slerp("shin_l", _q(lerpf(1.25, 0.3, fall) * kneel), blend)
			_slerp("shin_r", _q(lerpf(1.2, 0.2, fall) * kneel), blend)
			_slerp("spine", _q(lerpf(0.3, 0.0, fall)), blend)
			_slerp("chest", _q(0.1 * (1.0 - fall)), blend)
			_slerp("arm_l", _q(lerpf(-0.2, -2.6, fall), 0.0, 0.3), blend)
			_slerp("arm_r", _q(lerpf(-0.25, -2.3, fall), 0.0, -0.35), blend)
			_slerp("forearm_l", _q(-0.3), blend)
			_slerp("forearm_r", _q(-0.5), blend)
			_head_to(lerpf(0.25, -0.3, fall), 0.4 * fall, blend)
		Death.SPIN:
			# Vrille et tombe sur le côté, bras tendus devant lui au sol.
			var side := dir * (1.0 if z.variant % 2 == 0 else -1.0)
			skel.rotation = Vector3(0.15 * dir * k, side * k * 1.3, side * k * PI * 0.4)
			skel.position.y = -k * 0.06
			_slerp("arm_l", _q(-1.45, 0.0, 0.02), blend)
			_slerp("arm_r", _q(-1.3, 0.0, -0.02), blend)
			_slerp("thigh_l", _q(-0.5 * k, 0.0, 0.15), blend)
			_slerp("shin_l", _q(0.9 * k), blend)
			_slerp("thigh_r", _q(-0.1, 0.0, -0.05), blend)
			_slerp("shin_r", _q(0.3), blend)
			_slerp("spine", _q(0.1, 0.2 * side, 0.0), blend)
			_head_to(-0.1, -0.3 * side, blend)
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
	ground(false)


## Tête des morts : rotation lissée vers (hx, hz), pivot de set_head.
func _head_to(hx: float, hz: float, w: float) -> void:
	_dead_hx = lerpf(_dead_hx, hx, w)
	_dead_hz = lerpf(_dead_hz, hz, w)
	set_head(_dead_hx, _dead_hz)


func _slerp(b: String, target: Quaternion, w: float) -> void:
	var i: int = z.bones[b]
	z.skel.set_bone_pose_rotation(i, z.skel.get_bone_pose_rotation(i).slerp(target, w))
