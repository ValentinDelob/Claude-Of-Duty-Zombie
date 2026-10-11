class_name NurseAnim
extends RefCounted
## Animation procédurale de l'Infirmière hurlante cubique (NurseModel,
## ossature RigBuilder.BONES). Fonctions pures : `pose(...)` rend la pose
## (rotations d'os en angles d'Euler, hauteur, tangage et roulis de la
## racine) ; `apply` l'écrit sur le squelette. Mêmes conventions que
## BrancardierAnim (repos sans rotation, regard vers +Z ; X positif : membre
## pendant vers l'arrière, dos penché en avant, tête baissée, bouche ouverte ;
## Z positif : bras gauche écarté).
##
## Animations (`mode`, Nurse.Phase pour le cri) :
##   - marche : petits pas glissés, tête penchée de côté qui tressaille par
##     à-coups, main gauche griffue qui pend, seringue tenue devant ; course
##     de FUITE (move > 1) : penchée en avant, grandes enjambées, bras en
##     arrière ;
##   - préparation du cri (WINDUP) : elle se cambre et inspire, tête renversée,
##     bras écartés, mâchoire qui tremble ;
##   - cri (SCREAM) : buste projeté en avant, gueule grande ouverte, bras
##     rejetés en arrière, tout le corps vibre ;
##   - étranglée (CHOKE, cri avorté par une touche à la gorge) : pliée en
##     deux, mains à la gorge, quintes de toux ;
##   - coup de seringue (attaque) : bras droit levé puis abattu ;
##   - touchée : recul bref du buste et de la tête ;
##   - mort : mains à la gorge, puis elle bascule raide sur le dos, bras en
##     croix.

const NONE := 0
const WINDUP := 1
const SCREAM := 2
const CHOKE := 3
## Durées (s).
const DEATH_CLUTCH := 0.6
const DEATH_FALL := 0.65
const DEATH_SETTLE := 1.5
const HIT_TIME := 0.35
## Mort : tangage final (sur le dos) et hauteur de la racine qui garde le dos
## et les cheveux au-dessus du sol.
const DEATH_PITCH := -1.45
const DEATH_LIFT := 0.16
## Coup : instant de l'impact (fraction de NurseRules.STAB_TIME).
const STAB_HIT := 0.47

const BONES := ["hips", "spine", "chest", "neck", "head", "jaw", "arm_l", "arm_r", "forearm_l", "forearm_r",
	"thigh_l", "thigh_r", "shin_l", "shin_r"]


## Pose complète : {"bones": {os: Vector3 (Euler)}, "lift": m, "pitch": rad,
## "roll": rad}.
##   gait : phase de foulée (rad) ; move : vitesse / marche (0 arrêt, 1 marche,
##   jusqu'à ~1,8 en fuite) ; t : temps de vie ; mode / mode_t : phase du cri et
##   secondes depuis son début ; attack : progression du coup 0..1 (< 0 :
##   aucun) ; death : secondes depuis la mort (< 0 : vivante) ; hit : secondes
##   depuis la dernière touche (< 0 : aucune).
static func pose(gait: float, move: float, t: float, mode := NONE, mode_t := 0.0, attack := -1.0, death := -1.0, hit := -1.0) -> Dictionary:
	var b := {}
	for n in BONES:
		b[n] = Vector3.ZERO
	var out := {"bones": b, "lift": 0.0, "pitch": 0.0, "roll": 0.0}
	if death >= 0.0:
		_death(out, death, t)
		return out
	match mode:
		WINDUP:
			_windup(out, mode_t, t)
		SCREAM:
			_scream(out, mode_t, t)
		CHOKE:
			_choke(out, mode_t, t)
		_:
			_walk(out, gait, maxf(move, 0.0), t)
	if attack >= 0.0 and attack <= 1.0:
		_stab(out, attack)
	if hit >= 0.0 and hit < HIT_TIME:
		_hit(out, hit)
	return out


## Tressaillement : à-coup bref toutes les ~1,7 s (0..1).
static func twitch(t: float) -> float:
	var ph := fposmod(t, 1.7) / 1.7
	return maxf(0.0, 1.0 - absf(ph - 0.08) / 0.05) if ph < 0.13 else 0.0


## Marche glissée ou course de fuite. sin(gait) > 0 : jambe gauche en avant.
static func _walk(out: Dictionary, ph: float, move: float, t: float) -> void:
	var b: Dictionary = out.bones
	var k := clampf(move, 0.0, 1.0)
	var run := clampf((move - 1.15) / 0.5, 0.0, 1.0)
	var s := sin(ph)
	var c := cos(ph)
	var amp := lerpf(0.32, 0.7, run)
	var tw := twitch(t)
	b.thigh_l = Vector3(-amp * k * s, 0.0, 0.0)
	b.thigh_r = Vector3(amp * k * s, 0.0, 0.0)
	b.shin_l = Vector3(maxf(0.0, c) * lerpf(0.4, 1.0, run) * k + 0.04, 0.0, 0.0)
	b.shin_r = Vector3(maxf(0.0, -c) * lerpf(0.4, 1.0, run) * k + 0.04, 0.0, 0.0)
	b.hips = Vector3(0.0, 0.06 * s * k, 0.04 * s * k)
	b.spine = Vector3(lerpf(0.06, 0.45, run) + 0.02 * sin(t * 1.3), -0.04 * s * k, 0.0)
	b.chest = Vector3(lerpf(0.04, 0.12, run), 0.05 * s * k, 0.0)
	# Tête penchée de côté qui tressaille ; relevée vers l'avant en fuite.
	b.neck = Vector3(lerpf(0.05, -0.4, run) + 0.25 * tw, 0.0, 0.18 * (1.0 - run))
	b.head = Vector3(0.05 - 0.15 * tw, 0.25 * tw * sin(t * 37.0), 0.22 * (1.0 - run) + 0.12 * tw)
	b.jaw = Vector3(0.18 + 0.05 * sin(t * 2.3) + 0.2 * run, 0.0, 0.0)
	# Bras : la main gauche pend en griffe, la droite tient la seringue devant
	# (coude plié) ; en fuite, les deux bras ballent en arrière.
	b.arm_l = Vector3(lerpf(0.2 * s * k - 0.05, 0.55 + 0.3 * s, run), 0.0, 0.1)
	b.forearm_l = Vector3(lerpf(-0.25, -0.5, run), 0.0, 0.0)
	b.arm_r = Vector3(lerpf(-0.25 - 0.1 * s * k, 0.5 - 0.3 * s, run), 0.0, -0.12)
	b.forearm_r = Vector3(lerpf(-0.6, -0.4, run), 0.0, 0.0)
	out.lift = -0.015 * (1.0 - absf(c)) * k * (1.0 + run)
	out.roll = 0.03 * s * k


## Préparation du cri : cambrée, tête renversée, bras écartés, mâchoire qui
## tremble (inspiration).
static func _windup(out: Dictionary, mt: float, t: float) -> void:
	var b: Dictionary = out.bones
	var k := ease(clampf(mt / 0.5, 0.0, 1.0), 0.5)
	var shake := sin(t * 47.0) * 0.04 * k
	b.spine = Vector3(-0.18 * k, 0.0, 0.0)
	b.chest = Vector3(-0.16 * k, 0.0, 0.0)
	b.neck = Vector3(-0.35 * k, 0.0, 0.0)
	b.head = Vector3(-0.35 * k + shake, shake, 0.0)
	b.jaw = Vector3(0.25 + 0.3 * k + absf(shake) * 4.0, 0.0, 0.0)
	b.arm_l = Vector3(0.25 * k, 0.0, 1.05 * k)
	b.arm_r = Vector3(0.25 * k, 0.0, -1.05 * k)
	b.forearm_l = Vector3(-0.35 * k, 0.0, 0.0)
	b.forearm_r = Vector3(-0.5 * k, 0.0, 0.0)
	b.thigh_l = Vector3(-0.08 * k, 0.0, 0.03)
	b.thigh_r = Vector3(0.08 * k, 0.0, -0.03)
	b.shin_l = Vector3(0.1 * k, 0.0, 0.0)
	b.shin_r = Vector3(0.04, 0.0, 0.0)
	out.lift = 0.0


## Cri : buste projeté en avant, gueule grande ouverte, bras en arrière,
## vibration de tout le corps ; elle se redresse à la fin.
static func _scream(out: Dictionary, mt: float, t: float) -> void:
	var b: Dictionary = out.bones
	var k := ease(clampf(mt / 0.12, 0.0, 1.0), 0.4) * (1.0 - smoothstep(0.9, 1.2, mt))
	var v := sin(t * 61.0) * 0.035 * k
	b.spine = Vector3(0.3 * k + v, 0.0, 0.0)
	b.chest = Vector3(0.14 * k, 0.0, v)
	b.neck = Vector3(-0.1 * k, v, 0.0)
	b.head = Vector3(-0.32 * k + v, -v, 0.0)
	b.jaw = Vector3(0.25 + 0.95 * k + absf(v) * 2.0, 0.0, 0.0)
	b.arm_l = Vector3(0.75 * k, 0.0, 0.45 * k)
	b.arm_r = Vector3(0.75 * k, 0.0, -0.45 * k)
	b.forearm_l = Vector3(-0.2 * k, 0.0, 0.0)
	b.forearm_r = Vector3(-0.35 * k, 0.0, 0.0)
	b.thigh_l = Vector3(-0.25 * k, 0.0, 0.03)
	b.shin_l = Vector3(0.22 * k, 0.0, 0.0)
	b.thigh_r = Vector3(0.18 * k, 0.0, -0.03)
	b.shin_r = Vector3(0.12 * k, 0.0, 0.0)
	out.lift = -0.02 * k


## Étranglée : pliée en deux, mains à la gorge, toux (à-coups).
static func _choke(out: Dictionary, mt: float, t: float) -> void:
	var b: Dictionary = out.bones
	var k := ease(clampf(mt / 0.25, 0.0, 1.0), 0.5) * (1.0 - smoothstep(NurseRules.CHOKE_TIME - 0.35, NurseRules.CHOKE_TIME, mt))
	var cough := maxf(0.0, sin(t * 11.0)) * k
	b.spine = Vector3(0.38 * k + 0.12 * cough, 0.0, 0.0)
	b.chest = Vector3(0.12 * k, 0.0, 0.0)
	b.neck = Vector3(0.15 * k + 0.1 * cough, 0.0, 0.0)
	b.head = Vector3(-0.15 * k, 0.15 * sin(t * 3.0) * k, 0.0)
	b.jaw = Vector3(0.3 + 0.45 * cough, 0.0, 0.0)
	b.arm_l = Vector3(-1.05 * k, 0.0, -0.32 * k)
	b.arm_r = Vector3(-1.05 * k, 0.0, 0.32 * k)
	b.forearm_l = Vector3(-1.55 * k, 0.0, 0.0)
	b.forearm_r = Vector3(-1.55 * k, 0.0, 0.0)
	b.thigh_l = Vector3(-0.3 * k, 0.0, 0.03)
	b.shin_l = Vector3(0.45 * k, 0.0, 0.0)
	b.thigh_r = Vector3(-0.15 * k, 0.0, -0.03)
	b.shin_r = Vector3(0.35 * k, 0.0, 0.0)
	out.lift = -0.06 * k


## Coup de seringue : bras droit levé au-dessus de la tête puis abattu (k 0..1).
static func _stab(out: Dictionary, k: float) -> void:
	var b: Dictionary = out.bones
	var up := smoothstep(0.0, 0.35, k) * (1.0 - smoothstep(0.35, STAB_HIT, k))
	var down := smoothstep(0.35, STAB_HIT, k) * (1.0 - smoothstep(0.75, 1.0, k))
	var keep := 1.0 - maxf(up, down)
	for n in ["arm_r", "forearm_r", "spine"]:
		b[n] = (b[n] as Vector3) * keep
	b.arm_r += Vector3(-2.6 * up - 1.2 * down, 0.0, -0.15 * up)
	b.forearm_r += Vector3(-0.7 * up - 0.2 * down, 0.0, 0.0)
	b.spine += Vector3(-0.08 * up + 0.3 * down, 0.0, 0.0)
	b.jaw = Vector3(0.3 + 0.5 * maxf(up, down), 0.0, 0.0)


## Touchée : recul bref du buste et de la tête (h : secondes depuis la touche).
static func _hit(out: Dictionary, h: float) -> void:
	var b: Dictionary = out.bones
	var k := sin(clampf(h / HIT_TIME, 0.0, 1.0) * PI)
	b.spine = (b.spine as Vector3) + Vector3(-0.12 * k, 0.0, 0.0)
	b.chest = (b.chest as Vector3) + Vector3(-0.1 * k, 0.0, 0.05 * k)
	b.head = (b.head as Vector3) + Vector3(-0.25 * k, 0.0, 0.15 * k)
	b.jaw = (b.jaw as Vector3) + Vector3(0.2 * k, 0.0, 0.0)


## Mort : mains à la gorge (DEATH_CLUTCH), puis elle bascule raide sur le
## dos (DEATH_FALL), bras en croix ; immobile après DEATH_SETTLE.
static func _death(out: Dictionary, d: float, t: float) -> void:
	var b: Dictionary = out.bones
	var clutch := ease(clampf(d / 0.25, 0.0, 1.0), 0.5)
	var fall := ease(clampf((d - DEATH_CLUTCH) / DEATH_FALL, 0.0, 1.0), 2.2)
	var hold := clutch * (1.0 - fall)
	var tremble := sin(t * 40.0) * 0.04 * hold
	b.spine = Vector3(0.2 * hold - 0.1 * fall, 0.0, 0.0)
	b.chest = Vector3(0.05 * hold, 0.0, tremble)
	b.neck = Vector3(0.2 * hold - 0.3 * fall, 0.0, 0.0)
	b.head = Vector3(-0.2 * hold - 0.2 * fall + tremble, 0.0, 0.4 * fall)
	b.jaw = Vector3(0.7 * hold + 0.55 * fall, 0.0, 0.0)
	b.arm_l = Vector3(-1.05 * hold - 0.2 * fall, 0.0, -0.32 * hold + 1.25 * fall)
	b.arm_r = Vector3(-1.05 * hold - 0.2 * fall, 0.0, 0.32 * hold - 1.2 * fall)
	b.forearm_l = Vector3(-1.55 * hold - 0.2 * fall, 0.0, 0.0)
	b.forearm_r = Vector3(-1.55 * hold - 0.35 * fall, 0.0, 0.0)
	# Jambes : genoux qui fléchissent au début de la chute, raides au sol.
	var bend := sin(clampf((d - DEATH_CLUTCH) / DEATH_FALL, 0.0, 1.0) * PI) * 0.35
	b.thigh_l = Vector3(-bend - 0.1 * hold, 0.0, 0.05 * fall)
	b.thigh_r = Vector3(-bend * 0.7, 0.0, -0.08 * fall)
	b.shin_l = Vector3(bend * 1.4 + 0.15 * hold, 0.0, 0.0)
	b.shin_r = Vector3(bend, 0.0, 0.0)
	out.lift = DEATH_LIFT * fall - 0.03 * hold
	out.pitch = DEATH_PITCH * fall


## Écrit la pose `p` sur le squelette (rotations d'os, racine).
static func apply(skel: Skeleton3D, bones: Dictionary, p: Dictionary) -> void:
	var b: Dictionary = p.bones
	for n in b:
		if bones.has(n):
			skel.set_bone_pose_rotation(bones[n], Quaternion.from_euler(b[n]))
	skel.position = Vector3(0.0, p.lift, 0.0)
	skel.rotation = Vector3(p.pitch, 0.0, p.roll)
