class_name SurgeonAnim
extends RefCounted
## Animation procédurale du Chirurgien cubique (SurgeonModel, ossature
## RigBuilder.BONES). Fonctions pures : `pose(...)` rend la pose (rotations
## d'os en angles d'Euler, hauteur, tangage et roulis de la racine) ;
## `apply` l'écrit sur le squelette. Conventions (repos sans rotation, il
## regarde vers +Z ; Euler YXZ de Quaternion.from_euler) : rotation négative
## autour de X = membre levé vers l'avant, positive = buste penché en avant
## pour le dos, tête baissée pour le cou et la tête, bouche ouverte pour la
## mâchoire ; autour de Z positive = bras gauche écarté (le droit :
## négative) ; autour de Y (axe vertical, appliqué d'abord) : bras levé qui
## balaie à l'horizontale (positif : vers sa gauche).
##
## Animations (`action`, Surgeon.Action) :
##   - marche dégingandée : grands pas, buste voûté, scalpel tenu devant lui
##     (bras droit), bras gauche qui ballant ; enragé : plus voûté, plus
##     vite, bras écartés ;
##   - préparation de l'entaille (SLASH_WINDUP) : scalpel levé haut à droite,
##     buste tourné ; entailles (SLASH) : balayages horizontaux en aller-retour
##     (un par coup du combo) puis retour ;
##   - préparation du lancer (THROW_WINDUP) : bras droit armé au-dessus de
##     l'épaule, bras gauche tendu qui vise ; lancer (THROW) : bras abattu
##     devant lui ;
##   - opération (SURGERY) : penché en avant, mains qui s'affairent sur un
##     patient invisible ;
##   - changement de phase (ROAR) : il se ramasse, bras croisés sur le cœur,
##     puis s'ouvre d'un coup (onde de choc), tête rejetée en arrière, et
##     rugit en tremblant ;
##   - mort : il porte la main à son cœur en titubant, puis tombe en arrière
##     d'un bloc, raide comme une planche, bras en croix.

const NONE := 0
const SLASH_WINDUP := 1
const SLASH := 2
const THROW_WINDUP := 3
const THROW := 4
const SURGERY := 5
const ROAR := 6
## Mort : titube (DEATH_STAGGER s), puis chute en arrière (DEATH_FALL s),
## immobile après DEATH_SETTLE ; tangage final (sur le dos) et hauteur de la
## racine qui garde le dos au-dessus du sol.
const DEATH_STAGGER := 0.7
const DEATH_FALL := 0.65
const DEATH_SETTLE := 1.6
const DEATH_PITCH := -1.5
const DEATH_LIFT := 0.12

const BONES := ["hips", "spine", "chest", "neck", "head", "jaw", "arm_l", "arm_r", "forearm_l", "forearm_r",
	"thigh_l", "thigh_r", "shin_l", "shin_r"]


## Pose complète : {"bones": {os: Vector3 (Euler)}, "lift": m, "pitch": rad,
## "roll": rad}.
##   gait : phase de foulée (rad) ; move : 0 (arrêt) à 1 (marche) ; t : temps
##   de vie ; action / action_t : action en cours (Surgeon.Action) et secondes
##   depuis son début ; rage : phase 2 ; death : secondes depuis la mort
##   (< 0 : vivant).
static func pose(gait: float, move: float, t: float, action := NONE, action_t := 0.0, rage := false, death := -1.0) -> Dictionary:
	var b := {}
	for n in BONES:
		b[n] = Vector3.ZERO
	var out := {"bones": b, "lift": 0.0, "pitch": 0.0, "roll": 0.0}
	if death >= 0.0:
		_death(out, death)
		return out
	match action:
		SLASH_WINDUP:
			_slash_windup(out, action_t, rage, t)
		SLASH:
			_slash(out, action_t, t)
		THROW_WINDUP:
			_throw_windup(out, action_t, rage, t)
		THROW:
			_throw(out, action_t)
		SURGERY:
			_surgery(out, action_t, t)
		ROAR:
			_roar(out, action_t, t)
		_:
			_walk(out, gait, clampf(move, 0.0, 1.0), t, rage)
	return out


## Marche dégingandée. sin(gait) > 0 : jambe gauche en avant.
static func _walk(out: Dictionary, ph: float, k: float, t: float, rage: bool) -> void:
	var b: Dictionary = out.bones
	var s := sin(ph)
	var c := cos(ph)
	var amp := 0.55 if rage else 0.42
	var breath := sin(t * (2.6 if rage else 1.4))
	b.thigh_l = Vector3(-amp * k * s, 0.0, 0.0)
	b.thigh_r = Vector3(amp * k * s, 0.0, 0.0)
	b.shin_l = Vector3(maxf(0.0, c) * 0.7 * k + 0.05, 0.0, 0.0)
	b.shin_r = Vector3(maxf(0.0, -c) * 0.7 * k + 0.05, 0.0, 0.0)
	var lean := 0.3 if rage else 0.16
	b.hips = Vector3(0.0, 0.08 * s * k, 0.04 * s * k)
	b.spine = Vector3(lean + 0.02 * absf(s) * k + breath * 0.012, -0.06 * s * k, 0.0)
	b.chest = Vector3(0.1 + breath * 0.015, -0.1 * s * k, 0.0)
	b.neck = Vector3(-0.22 - (0.12 if rage else 0.0), 0.0, 0.0)
	b.head = Vector3(-0.05, 0.08 * sin(t * 0.7), 0.06 * sin(t * 1.1))
	b.jaw = Vector3(0.04 + (0.12 * maxf(0.0, breath) if rage else 0.0), 0.0, 0.0)
	# Scalpel tenu devant lui (bras droit), le gauche ballant.
	b.arm_r = Vector3(-0.28 - 0.08 * s * k, 0.0, -0.12 - (0.15 if rage else 0.0))
	b.forearm_r = Vector3(-0.55, 0.0, 0.0)
	b.arm_l = Vector3(0.32 * s * k - 0.05, 0.0, 0.1 + (0.3 if rage else 0.0))
	b.forearm_l = Vector3(-0.25 - 0.15 * maxf(0.0, -s) * k - (0.4 if rage else 0.0), 0.0, 0.0)
	out.lift = -0.02 * (1.0 - absf(c)) * k
	out.roll = 0.03 * s * k


## Scalpel levé haut à droite, buste tourné (préparation de l'entaille).
static func _slash_windup(out: Dictionary, at: float, rage: bool, t: float) -> void:
	var b: Dictionary = out.bones
	var k := ease(clampf(at / (SurgeonRules.slash_windup(rage) * 0.7), 0.0, 1.0), 0.5)
	var shiver := sin(t * 31.0) * 0.02 * k
	b.spine = Vector3(0.12 * k, -0.25 * k, 0.0)
	b.chest = Vector3(-0.05 * k, -0.3 * k, 0.0)
	b.neck = Vector3(-0.2, 0.25 * k, 0.0)
	b.head = Vector3(0.05 * k, 0.15 * k, 0.0)
	b.jaw = Vector3(0.25 * k, 0.0, 0.0)
	b.arm_r = Vector3(-2.3 * k + shiver, -0.7 * k, -0.35 * k)
	b.forearm_r = Vector3(-0.9 * k, 0.0, 0.0)
	b.arm_l = Vector3(-0.5 * k, 0.0, 0.35 * k)
	b.forearm_l = Vector3(-0.6 * k, 0.0, 0.0)
	b.thigh_l = Vector3(-0.3 * k, 0.0, 0.0)
	b.shin_l = Vector3(0.35 * k, 0.0, 0.0)
	b.thigh_r = Vector3(0.15 * k, 0.0, 0.0)
	b.shin_r = Vector3(0.2 * k, 0.0, 0.0)
	out.lift = -0.03 * k


## Entailles du combo : balayage horizontal du bras levé, une fois de droite
## à gauche, une fois de gauche à droite… puis retour au repos.
static func _slash(out: Dictionary, at: float, t: float) -> void:
	var b: Dictionary = out.bones
	var i := int(floor(at / SurgeonRules.SLASH_TIME))
	var k := clampf((at - i * SurgeonRules.SLASH_TIME) / SurgeonRules.SLASH_TIME, 0.0, 1.0)
	# Balayage rapide au début de chaque entaille (le coup tombe à SLASH_HIT_AT).
	var sweep := ease(clampf(k / 0.55, 0.0, 1.0), 0.4)
	var from := -1.15 if i % 2 == 0 else 0.75
	var to := 0.75 if i % 2 == 0 else -1.15
	var yaw := lerpf(from, to, sweep)
	b.arm_r = Vector3(-1.45, yaw, -0.1)
	b.forearm_r = Vector3(-0.25, 0.0, 0.0)
	b.spine = Vector3(0.25, yaw * 0.25, 0.0)
	b.chest = Vector3(0.05, yaw * 0.3, 0.0)
	b.neck = Vector3(-0.2, -yaw * 0.2, 0.0)
	b.jaw = Vector3(0.3 + 0.1 * sin(t * 18.0), 0.0, 0.0)
	b.arm_l = Vector3(-0.6, 0.0, 0.5)
	b.forearm_l = Vector3(-0.7, 0.0, 0.0)
	# Fente : jambe gauche en avant.
	b.thigh_l = Vector3(-0.45, 0.0, 0.0)
	b.shin_l = Vector3(0.45, 0.0, 0.0)
	b.thigh_r = Vector3(0.25, 0.0, 0.0)
	b.shin_r = Vector3(0.15, 0.0, 0.0)
	out.lift = -0.05


## Bras droit armé au-dessus de l'épaule, bras gauche tendu qui vise.
static func _throw_windup(out: Dictionary, at: float, rage: bool, t: float) -> void:
	var b: Dictionary = out.bones
	var k := ease(clampf(at / (SurgeonRules.throw_windup(rage) * 0.6), 0.0, 1.0), 0.5)
	b.spine = Vector3(-0.08 * k, -0.35 * k, 0.0)
	b.chest = Vector3(-0.05 * k, -0.3 * k, 0.0)
	b.neck = Vector3(-0.1, 0.4 * k, 0.0)
	b.head = Vector3(0.05, 0.2 * k, 0.0)
	b.jaw = Vector3(0.15 * k + 0.05 * sin(t * 9.0), 0.0, 0.0)
	b.arm_r = Vector3(-2.7 * k, 0.0, -0.35 * k)
	b.forearm_r = Vector3(-1.5 * k, 0.0, 0.0)
	b.arm_l = Vector3(-1.4 * k, 0.45 * k, 0.15 * k)
	b.forearm_l = Vector3(-0.1, 0.0, 0.0)
	b.thigh_r = Vector3(0.3 * k, 0.0, 0.0)
	b.shin_r = Vector3(0.25 * k, 0.0, 0.0)
	b.thigh_l = Vector3(-0.25 * k, 0.0, 0.0)
	b.shin_l = Vector3(0.2 * k, 0.0, 0.0)
	out.lift = -0.03 * k


## Lancer : le bras s'abat devant lui (0,25 s), puis retour.
static func _throw(out: Dictionary, at: float) -> void:
	var b: Dictionary = out.bones
	var k := ease(clampf(at / 0.22, 0.0, 1.0), 0.4)
	var back := smoothstep(0.25, SurgeonRules.THROW_RECOVER, at)
	var w := 1.0 - back
	b.spine = Vector3(0.35 * k * w, 0.2 * k * w, 0.0)
	b.chest = Vector3(0.12 * k * w, 0.25 * k * w, 0.0)
	b.neck = Vector3(-0.25 * w, 0.0, 0.0)
	b.arm_r = Vector3(lerpf(-2.7, -0.9, k) * w, 0.0, -0.2 * w)
	b.forearm_r = Vector3(lerpf(-1.5, -0.15, k) * w, 0.0, 0.0)
	b.arm_l = Vector3(lerpf(-1.4, 0.2, k) * w, 0.0, 0.25 * w)
	b.forearm_l = Vector3(-0.4 * w, 0.0, 0.0)
	b.thigh_l = Vector3(-0.35 * w, 0.0, 0.0)
	b.shin_l = Vector3(0.35 * w, 0.0, 0.0)
	b.thigh_r = Vector3(0.25 * w, 0.0, 0.0)
	b.shin_r = Vector3(0.1 * w, 0.0, 0.0)
	out.lift = -0.04 * w


## Opération : penché sur un patient invisible, mains qui s'affairent.
static func _surgery(out: Dictionary, at: float, t: float) -> void:
	var b: Dictionary = out.bones
	var k := ease(clampf(at / 0.4, 0.0, 1.0), 0.5) * (1.0 - smoothstep(SurgeonRules.SURGERY_TIME - 0.4, SurgeonRules.SURGERY_TIME, at))
	var busy := sin(t * 15.0)
	var busy2 := sin(t * 11.0 + 1.3)
	b.spine = Vector3(0.55 * k, 0.0, 0.0)
	b.chest = Vector3(0.25 * k, 0.05 * busy * k, 0.0)
	b.neck = Vector3(0.3 * k, 0.0, 0.0)
	b.head = Vector3(0.15 * k, 0.1 * busy2 * k, 0.0)
	b.jaw = Vector3(0.1 + 0.15 * maxf(0.0, busy2) * k, 0.0, 0.0)
	b.arm_r = Vector3((-0.85 + 0.12 * busy) * k, 0.15 * busy2 * k, -0.1 * k)
	b.forearm_r = Vector3((-0.7 + 0.2 * busy2) * k, 0.0, 0.0)
	b.arm_l = Vector3((-0.85 - 0.1 * busy2) * k, -0.1 * busy * k, 0.1 * k)
	b.forearm_l = Vector3((-0.75 - 0.15 * busy) * k, 0.0, 0.0)
	b.thigh_l = Vector3(-0.35 * k, 0.0, 0.0)
	b.shin_l = Vector3(0.6 * k, 0.0, 0.0)
	b.thigh_r = Vector3(-0.35 * k, 0.0, 0.0)
	b.shin_r = Vector3(0.6 * k, 0.0, 0.0)
	out.lift = -0.03 * k


## Changement de phase : ramassé (bras croisés sur le cœur), il s'ouvre d'un
## coup (onde de choc à ROAR_SHOCK_AT), tête rejetée en arrière, et rugit.
static func _roar(out: Dictionary, at: float, t: float) -> void:
	var b: Dictionary = out.bones
	var gather := ease(clampf(at / 0.55, 0.0, 1.0), 0.5) * (1.0 - smoothstep(0.6, ROAR_OPEN, at))
	var open := smoothstep(0.6, ROAR_OPEN, at) * (1.0 - smoothstep(SurgeonRules.ROAR_TIME - 0.45, SurgeonRules.ROAR_TIME, at))
	var tremble := sin(t * 37.0) * 0.03 * open
	b.spine = Vector3(0.45 * gather - 0.2 * open, 0.0, tremble)
	b.chest = Vector3(0.2 * gather - 0.15 * open, 0.0, 0.0)
	b.neck = Vector3(0.35 * gather - 0.45 * open, 0.0, 0.0)
	b.head = Vector3(0.1 * gather - 0.25 * open + tremble, 0.0, tremble)
	b.jaw = Vector3(0.05 + 0.75 * open, 0.0, 0.0)
	b.arm_l = Vector3(-1.0 * gather - 0.35 * open, 0.0, -0.45 * gather + 1.35 * open)
	b.arm_r = Vector3(-1.0 * gather - 0.35 * open, 0.0, 0.45 * gather - 1.35 * open)
	b.forearm_l = Vector3(-1.6 * gather - 0.2 * open, 0.0, 0.0)
	b.forearm_r = Vector3(-1.6 * gather - 0.2 * open, 0.0, 0.0)
	b.thigh_l = Vector3(-0.3 * gather - 0.15 * open, 0.0, 0.12 * open)
	b.shin_l = Vector3(0.55 * gather + 0.2 * open, 0.0, 0.0)
	b.thigh_r = Vector3(-0.3 * gather - 0.15 * open, 0.0, -0.12 * open)
	b.shin_r = Vector3(0.55 * gather + 0.2 * open, 0.0, 0.0)
	out.lift = -0.03 * gather - 0.02 * open
	out.pitch = -0.04 * open


## Instant (s) où il s'ouvre pendant le changement de phase (onde de choc).
const ROAR_OPEN := 0.85


## Mort : la main gauche sur le cœur, il titube, puis tombe en arrière d'un
## bloc (jambes tendues), bras en croix.
static func _death(out: Dictionary, d: float) -> void:
	var b: Dictionary = out.bones
	var st := ease(clampf(d / 0.3, 0.0, 1.0), 0.5) * (1.0 - smoothstep(DEATH_STAGGER, DEATH_STAGGER + 0.25, d))
	var fall := ease(clampf((d - DEATH_STAGGER) / DEATH_FALL, 0.0, 1.0), 2.6)
	var sway := sin(d * 9.0) * 0.06 * st
	b.spine = Vector3(0.25 * st + sway, 0.0, sway)
	b.chest = Vector3(0.15 * st, 0.0, 0.0)
	b.neck = Vector3(-0.35 * st - 0.25 * fall, 0.0, 0.0)
	b.head = Vector3(-0.2 * st, 0.0, 0.3 * fall)
	b.jaw = Vector3(0.5 * st + 0.4 * fall, 0.0, 0.0)
	# Main gauche sur le cœur, scalpel qui pend ; bras en croix au sol.
	b.arm_l = Vector3(-0.9 * st, 0.4 * st, -0.2 * st + 1.25 * fall)
	b.forearm_l = Vector3(-1.5 * st, 0.0, 0.0)
	b.arm_r = Vector3(0.15 * st, 0.0, -0.15 * st - 1.3 * fall)
	b.forearm_r = Vector3(-0.15 * (1.0 - fall), 0.0, 0.0)
	# Pas en arrière en titubant, puis jambes raides.
	b.thigh_l = Vector3(0.2 * st, 0.0, 0.0)
	b.shin_l = Vector3(0.25 * st, 0.0, 0.0)
	b.thigh_r = Vector3(-0.15 * st, 0.0, 0.0)
	b.shin_r = Vector3(0.3 * st, 0.0, 0.0)
	out.lift = -0.04 * st + DEATH_LIFT * fall
	out.pitch = -0.08 * st + DEATH_PITCH * fall
	out.roll = sway * 0.5


## Écrit la pose `p` sur le squelette (rotations d'os, racine).
static func apply(skel: Skeleton3D, bones: Dictionary, p: Dictionary) -> void:
	var b: Dictionary = p.bones
	for n in b:
		if bones.has(n):
			skel.set_bone_pose_rotation(bones[n], Quaternion.from_euler(b[n]))
	skel.position = Vector3(0.0, p.lift, 0.0)
	skel.rotation = Vector3(p.pitch, 0.0, p.roll)
