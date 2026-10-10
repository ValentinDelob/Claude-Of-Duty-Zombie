class_name DogAnim
extends RefCounted
## Animation procédurale du chien cubique (HellhoundModel, ossature du jeu
## replacée en quadrupède). Fonctions pures : `pose(...)` rend la pose
## (rotations d'os en angles d'Euler, position et roulis de la racine) ;
## `apply` l'écrit sur le squelette. Conventions (repos sans rotation, le
## chien regarde vers +Z) : rotation positive autour de X = vers l'arrière
## pour une patte (le pied part vers -Z), museau vers le bas pour le cou et
## la tête, croupe qui monte pour le bassin ; mâchoire : positive = ouverte.
##
## Animations :
##   - galop (rotatif) : pattes avant et arrière en opposition, extension
##     (pattes avant lancées, arrière poussées) puis regroupement (pattes
##     sous le corps, dos voûté), coudes et jarrets qui se plient pendant le
##     retour de la patte, petit temps de suspension ; au pas lent, la même
##     foulée plus courte ; à l'arrêt : halètement ;
##   - apparition : le chien jaillit accroupi (pattes repliées, tête basse,
##     babines retroussées) puis se détend dans la course ;
##   - bond d'attaque et morsure : appel accroupi, cabré pattes avant
##     tendues, gueule grande ouverte en vol, claquement puis secousse de la
##     tête (il arrache) ;
##   - mort : les pattes lâchent, il bascule sur le flanc, pattes raides
##     agitées de soubresauts, puis immobile (dissolution par Hellhound).

## Durées (s).
const APPEAR_TIME := 0.55
const ATTACK_TIME := 0.6
const DEATH_BUCKLE := 0.22
const DEATH_ROLL := 0.5
const DEATH_SETTLE := 1.3
## Roulis final sur le flanc (rad) et relèvement de la racine (m) pour que le
## flanc touche le sol sans le traverser.
const DEATH_ROLL_ANGLE := 1.42
const DEATH_SIDE_LIFT := 0.13

const LEGS := ["arm_l", "arm_r", "forearm_l", "forearm_r", "thigh_l", "thigh_r", "shin_l", "shin_r"]
const BODY := ["hips", "spine", "chest", "neck", "head", "jaw"]


## Pose complète : {"bones": {os: Vector3 (Euler)}, "lift": m, "roll": rad,
## "pitch": rad}.
##   phase : phase de foulée (rad) ; move : 0 (arrêt) à 1 (pleine course) ;
##   t : temps de vie (halètement) ; attack, appear : progression 0..1, ou
##   < 0 hors de l'animation ; death : secondes depuis la mort (< 0 : vivant) ;
##   side : côté de la chute (+1 : sur le flanc droit, -1 : gauche).
static func pose(phase: float, move: float, t: float, attack := -1.0, appear := -1.0, death := -1.0, side := 1.0) -> Dictionary:
	var b := {}
	for n in LEGS + BODY:
		b[n] = Vector3.ZERO
	var out := {"bones": b, "lift": 0.0, "roll": 0.0, "pitch": 0.0}
	if death >= 0.0:
		_death(out, death, side)
		return out
	_gallop(out, phase, clampf(move, 0.0, 1.0), t)
	if appear >= 0.0 and appear < 1.0:
		_appear(out, appear)
	if attack >= 0.0 and attack <= 1.0:
		_attack(out, attack)
	return out


## Galop rotatif ; c = sin(phase) : +1 extension, -1 regroupement.
static func _gallop(out: Dictionary, ph: float, k: float, t: float) -> void:
	var b: Dictionary = out.bones
	if k < 0.08:
		# Arrêt : halètement, tête un peu basse, gueule entrouverte.
		var br := sin(t * 9.0)
		out.lift = br * 0.004
		b.neck = Vector3(0.12, 0.0, 0.0)
		b.head = Vector3(0.05 + br * 0.03, sin(t * 0.7) * 0.12, 0.0)
		b.jaw = Vector3(0.18 + 0.1 * br, 0.0, 0.0)
		b.chest = Vector3(br * 0.01, 0.0, 0.0)
		return
	var af := 0.22 + 0.62 * k
	var ah := 0.18 + 0.52 * k
	# Patte de tête (gauche) un peu en avance sur l'autre, pour chaque paire.
	for side in ["l", "r"]:
		var o := 0.0 if side == "l" else 0.42
		var sf := sin(ph + o)
		var cf := cos(ph + o)
		# Patte avant : grande allonge vers l'avant, retour court sous le poitrail
		# (au-delà, l'épaule entrerait dans le flanc et le pied dans la patte
		# arrière).
		b["arm_" + side] = Vector3(-af * sf if sf > 0.0 else -0.5 * af * sf, 0.0, 0.0)
		# Carpe replié pendant le retour de la patte (vers l'avant).
		b["forearm_" + side] = Vector3(maxf(0.0, cf) * (0.5 + 0.8 * k), 0.0, 0.0)
		var oh := o + 0.3
		var sh := sin(ph + oh)
		var ch := cos(ph + oh)
		# Patte arrière : grande poussée vers l'arrière, retour court.
		b["thigh_" + side] = Vector3(ah * sh if sh > 0.0 else 0.55 * ah * sh, 0.0, 0.0)
		# Jarret fléchi au retour, tendu à la poussée.
		b["shin_" + side] = Vector3(maxf(0.0, -ch) * (0.45 + 0.7 * k) - maxf(0.0, sh) * 0.25 * k, 0.0, 0.0)
	var c := sin(ph)
	# Dos : voûté au regroupement (croupe basse), tendu à l'extension.
	var flex := 0.12 * c * k
	b.hips = Vector3(flex, 0.0, 0.0)
	b.spine = Vector3(-flex * 0.5, 0.0, 0.0)
	b.chest = Vector3(-flex * 0.5, 0.0, 0.0)
	# Suspension : deux petits sauts par foulée.
	out.lift = absf(cos(ph)) * 0.045 * k - 0.015 * k
	# Tête portée bas et en avant, qui compense le tangage.
	b.neck = Vector3(0.12 + 0.14 * k + c * 0.06 * k, 0.0, 0.0)
	b.head = Vector3(-0.06 * k - c * 0.05 * k + sin(ph * 2.0) * 0.03, 0.0, 0.0)
	b.jaw = Vector3(0.12 + 0.12 * k + sin(ph * 2.0) * 0.06, 0.0, 0.0)


## Apparition : accroupi, prêt à bondir, puis détendu dans la course.
static func _appear(out: Dictionary, k: float) -> void:
	var b: Dictionary = out.bones
	var e := 1.0 - ease(clampf(k, 0.0, 1.0), 0.6)  # 1 : accroupi, 0 : course
	var crouch := {
		"arm_l": Vector3(0.55, 0, 0), "arm_r": Vector3(0.5, 0, 0),
		"forearm_l": Vector3(-0.9, 0, 0), "forearm_r": Vector3(-0.85, 0, 0),
		"thigh_l": Vector3(-0.75, 0, 0), "thigh_r": Vector3(-0.7, 0, 0),
		"shin_l": Vector3(1.2, 0, 0), "shin_r": Vector3(1.15, 0, 0),
		"hips": Vector3(-0.05, 0, 0), "spine": Vector3(0.03, 0, 0), "chest": Vector3(0.02, 0, 0),
		"neck": Vector3(0.45, 0, 0), "head": Vector3(-0.2, 0, 0), "jaw": Vector3(0.3, 0, 0),
	}
	for n in crouch:
		b[n] = (b[n] as Vector3).lerp(crouch[n], e)
	out.lift = lerpf(out.lift, -0.08, e)


## Bond et morsure (k : 0..1 sur ATTACK_TIME).
static func _attack(out: Dictionary, k: float) -> void:
	var b: Dictionary = out.bones
	# Appel (accroupi) 0..0,18, vol 0,18..0,55, réception 0,55..1.
	var crouch := sin(clampf(k / 0.18, 0.0, 1.0) * PI) if k < 0.18 else 0.0
	var fly := sin(clampf((k - 0.12) / 0.55, 0.0, 1.0) * PI)
	var a := maxf(fly, 0.0)
	var keep := 1.0 - maxf(a, crouch)
	for n in b:
		b[n] = (b[n] as Vector3) * keep
	out.lift = out.lift * keep - 0.08 * crouch + 0.2 * a
	out.pitch = -0.32 * a + 0.06 * crouch
	b.arm_l += Vector3(-1.15 * a + 0.4 * crouch, 0, 0)
	b.arm_r += Vector3(-1.05 * a + 0.35 * crouch, 0, 0)
	b.forearm_l += Vector3(0.25 * a - 0.6 * crouch, 0, 0)
	b.forearm_r += Vector3(0.35 * a - 0.55 * crouch, 0, 0)
	b.thigh_l += Vector3(0.75 * a - 0.5 * crouch, 0, 0)
	b.thigh_r += Vector3(0.68 * a - 0.45 * crouch, 0, 0)
	b.shin_l += Vector3(-0.2 * a + 0.8 * crouch, 0, 0)
	b.shin_r += Vector3(-0.15 * a + 0.75 * crouch, 0, 0)
	b.hips += Vector3(0.18 * a, 0, 0)
	b.neck += Vector3(0.3 * a + 0.3 * crouch, 0, 0)
	b.head += Vector3(0.12 * a - 0.15 * crouch, 0, 0)
	# Gueule : ouverte en grand en vol, claquement (morsure), puis secousse.
	var jaw := 0.0
	if k < 0.36:
		jaw = 0.2 + 0.6 * smoothstep(0.05, 0.3, k)
	elif k < 0.46:
		jaw = lerpf(0.8, 0.05, (k - 0.36) / 0.1)
	else:
		jaw = 0.05
	b.jaw = Vector3(jaw, 0, 0)
	if k >= 0.42:
		var s := (1.0 - k) / 0.58
		b.head += Vector3(0.0, sin(k * 42.0) * 0.32 * s, sin(k * 42.0) * 0.18 * s)
		b.neck += Vector3(0.0, sin(k * 42.0 + 0.6) * 0.15 * s, 0)


## Mort : les pattes lâchent (DEATH_BUCKLE), bascule sur le flanc
## (DEATH_ROLL), soubresauts des pattes, immobile après DEATH_SETTLE.
static func _death(out: Dictionary, d: float, side: float) -> void:
	var b: Dictionary = out.bones
	var buckle := ease(clampf(d / DEATH_BUCKLE, 0.0, 1.0), 0.5)
	var roll := ease(clampf((d - DEATH_BUCKLE * 0.6) / DEATH_ROLL, 0.0, 1.0), 2.2)
	# Pattes qui se dérobent puis raides, écartées du ventre (chien couché sur
	# le flanc) ; soubresauts qui s'éteignent.
	var twitch := sin(minf(d, DEATH_SETTLE) * 15.0) * 0.16 * maxf(0.0, 1.0 - d / DEATH_SETTLE) * roll
	var fold := buckle * (1.0 - roll)
	b.arm_l = Vector3(0.6 * fold - 0.45 * roll + twitch, 0, 0)
	b.arm_r = Vector3(0.55 * fold - 0.3 * roll - twitch, 0, 0)
	b.forearm_l = Vector3(-1.3 * fold + 0.2 * roll, 0, 0)
	b.forearm_r = Vector3(-1.25 * fold + 0.35 * roll, 0, 0)
	b.thigh_l = Vector3(-0.9 * fold + 0.4 * roll - twitch, 0, 0)
	b.thigh_r = Vector3(-0.85 * fold + 0.25 * roll + twitch, 0, 0)
	b.shin_l = Vector3(1.5 * fold + 0.15 * roll, 0, 0)
	b.shin_r = Vector3(1.45 * fold + 0.3 * roll, 0, 0)
	b.neck = Vector3(0.35 * buckle - 0.25 * roll, 0, 0)
	b.head = Vector3(0.1 * roll, 0, 0)
	b.jaw = Vector3(0.15 + 0.35 * roll, 0, 0)
	out.lift = -0.08 * fold + DEATH_SIDE_LIFT * roll
	out.roll = side * DEATH_ROLL_ANGLE * roll


## Écrit la pose `p` sur le squelette (rotations d'os, racine).
static func apply(skel: Skeleton3D, bones: Dictionary, p: Dictionary) -> void:
	var b: Dictionary = p.bones
	for n in b:
		if bones.has(n):
			skel.set_bone_pose_rotation(bones[n], Quaternion.from_euler(b[n]))
	skel.position = Vector3(0.0, p.lift, 0.0)
	skel.rotation = Vector3(p.pitch, 0.0, p.roll)
