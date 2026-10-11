class_name BrancardierAnim
extends RefCounted
## Animation procédurale du Brancardier cubique (BrancardierModel, ossature
## RigBuilder.BONES). Fonctions pures : `pose(...)` rend la pose (rotations
## d'os en angles d'Euler, hauteur, tangage et roulis de la racine) ;
## `apply` l'écrit sur le squelette. Conventions (repos sans rotation, il
## regarde vers +Z) : rotation positive autour de X = vers l'arrière pour un
## membre pendant, buste penché en avant pour le dos, tête baissée pour le
## cou et la tête, bouche ouverte pour la mâchoire ; autour de Z positive =
## bras gauche écarté (le droit : négative).
##
## Animations (`mode`, Brancardier.Phase pour la charge) :
##   - marche lourde : grands pas lents, bassin qui tangue de côté, buste
##     voûté, bras de gorille qui ballent, coudes fléchis ; à l'arrêt :
##     souffle (poitrine, mâchoire) ;
##   - préparation de la charge (WINDUP) : il se ramasse, bras écartés en
##     arrière, tête relevée et gueule ouverte (rugissement), le pied droit
##     gratte le sol trois fois ;
##   - charge (CHARGE) : course penchée en avant, épaule et poings devant ;
##   - étourdi (STUN, choc contre un mur) : il recule d'un pas, tête qui
##     dodeline, bras ballants, corps qui oscille ;
##   - coup (attaque) : les deux poings levés au-dessus de la tête puis
##     abattus devant lui ;
##   - mort : les genoux lâchent, il tombe à genoux puis s'effondre face
##     contre terre, le brancard en l'air sur le dos.

const NONE := 0
const WINDUP := 1
const CHARGE := 2
const STUN := 3
## Durées (s).
const DEATH_KNEEL := 0.55
const DEATH_FALL := 0.7
const DEATH_SETTLE := 1.6
## Mort : tangage final (face contre terre) et hauteur de la racine qui
## garde la poitrine et le ventre au-dessus du sol ; agenouillé : la racine
## descend de la longueur du tibia.
const DEATH_PITCH := 1.45
const DEATH_LIFT := 0.24
const KNEEL_DROP := 0.34
## Pointe du sabot dans le repère du tibia (vers le bas, vers l'avant), m.
const SHIN_REACH := Vector2(0.5, 0.22)
## Coup : instant de l'impact (fraction de BrancardRules.SMASH_TIME).
const SMASH_HIT := 0.48

const BONES := ["hips", "spine", "chest", "neck", "head", "jaw", "arm_l", "arm_r", "forearm_l", "forearm_r",
	"thigh_l", "thigh_r", "shin_l", "shin_r"]


## Pose complète : {"bones": {os: Vector3 (Euler)}, "lift": m, "pitch": rad,
## "roll": rad}.
##   gait : phase de foulée (rad) ; move : 0 (arrêt) à 1 (marche) ; t : temps
##   de vie ; mode / mode_t : phase de la charge et secondes depuis son début ;
##   attack : progression du coup 0..1 (< 0 : aucun) ; death : secondes
##   depuis la mort (< 0 : vivant).
static func pose(gait: float, move: float, t: float, mode := NONE, mode_t := 0.0, attack := -1.0, death := -1.0) -> Dictionary:
	var b := {}
	for n in BONES:
		b[n] = Vector3.ZERO
	var out := {"bones": b, "lift": 0.0, "pitch": 0.0, "roll": 0.0}
	if death >= 0.0:
		_death(out, death)
		return out
	match mode:
		WINDUP:
			_windup(out, mode_t, t)
		CHARGE:
			_walk(out, gait, 1.0, t, true)
		STUN:
			_stun(out, mode_t, t)
		_:
			_walk(out, gait, clampf(move, 0.0, 1.0), t, false)
	if attack >= 0.0 and attack <= 1.0:
		_smash(out, attack)
	return out


## Marche lourde (ou course de charge : `run`). sin(gait) > 0 : jambe gauche
## en avant.
static func _walk(out: Dictionary, ph: float, k: float, t: float, run: bool) -> void:
	var b: Dictionary = out.bones
	var s := sin(ph)
	var c := cos(ph)
	var amp := 0.85 if run else 0.42
	var breath := sin(t * 1.7)
	# Jambes : cuisse en avant (négatif), genou qui plie au retour.
	b.thigh_l = Vector3(-amp * k * s, 0.0, 0.0)
	b.thigh_r = Vector3(amp * k * s, 0.0, 0.0)
	b.shin_l = Vector3(maxf(0.0, c) * (1.0 if run else 0.55) * k + 0.08, 0.0, 0.0)
	b.shin_r = Vector3(maxf(0.0, -c) * (1.0 if run else 0.55) * k + 0.08, 0.0, 0.0)
	# Buste voûté, bassin qui tangue de côté à chaque pas.
	var lean := 0.62 if run else 0.16
	b.hips = Vector3(0.0, 0.0, 0.07 * s * k)
	b.spine = Vector3(lean + 0.03 * absf(s) * k + breath * 0.012 * (1.0 - k), 0.0, -0.05 * s * k)
	b.chest = Vector3((0.16 if run else 0.08) + breath * 0.015 * (1.0 - k), 0.12 * s * k * (0.4 if run else 1.0), 0.0)
	b.neck = Vector3(-(0.55 if run else 0.18), 0.0, 0.0)
	b.head = Vector3(-(0.12 if run else 0.04), -0.06 * s * k, 0.0)
	b.jaw = Vector3((0.32 if run else 0.06) + 0.05 * maxf(0.0, breath) * (1.0 - k), 0.0, 0.0)
	if run:
		# Charge : épaule en avant, poings serrés devant la poitrine.
		b.arm_l = Vector3(-0.55 + 0.25 * s, 0.0, 0.22)
		b.arm_r = Vector3(-0.75 - 0.25 * s, 0.0, -0.22)
		b.forearm_l = Vector3(-1.0, 0.0, 0.0)
		b.forearm_r = Vector3(-1.1, 0.0, 0.0)
	else:
		# Bras de gorille : ballant à l'opposé des jambes, coudes fléchis.
		b.arm_l = Vector3(0.38 * s * k - 0.05, 0.0, 0.14)
		b.arm_r = Vector3(-0.38 * s * k - 0.05, 0.0, -0.14)
		b.forearm_l = Vector3(-0.32 - 0.15 * maxf(0.0, -s) * k, 0.0, 0.0)
		b.forearm_r = Vector3(-0.32 - 0.15 * maxf(0.0, s) * k, 0.0, 0.0)
	# Chaque pas pèse : le corps s'enfonce au poser du pied.
	out.lift = -(0.035 if run else 0.02) * (1.0 - absf(c)) * k
	out.roll = 0.04 * s * k * (0.5 if run else 1.0)


## Préparation de la charge : ramassé, bras en arrière, rugissement, pied
## droit qui gratte le sol (3 fois).
static func _windup(out: Dictionary, mt: float, t: float) -> void:
	var b: Dictionary = out.bones
	var k := ease(clampf(mt / 0.35, 0.0, 1.0), 0.5)
	var roar := smoothstep(0.15, 0.4, mt) * (1.0 - smoothstep(1.05, 1.3, mt))
	b.spine = Vector3(0.38 * k, 0.0, 0.0)
	b.chest = Vector3(0.12 * k - 0.1 * roar, 0.0, 0.0)
	b.neck = Vector3(-0.3 * roar - 0.1 * k, 0.0, 0.0)
	b.head = Vector3(-0.05 * roar, sin(t * 21.0) * 0.04 * roar, 0.0)
	b.jaw = Vector3(0.1 + 0.6 * roar, 0.0, 0.0)
	b.arm_l = Vector3(0.55 * k, 0.0, 0.45 * k)
	b.arm_r = Vector3(0.55 * k, 0.0, -0.45 * k)
	b.forearm_l = Vector3(-0.7 * k, 0.0, 0.0)
	b.forearm_r = Vector3(-0.7 * k, 0.0, 0.0)
	b.thigh_l = Vector3(-0.25 * k, 0.0, 0.0)
	b.shin_l = Vector3(0.3 * k, 0.0, 0.0)
	# Grattage : la jambe droite part en arrière et revient, sabot au sol.
	var scrape := 0.0
	if mt > 0.25 and mt < 1.15:
		scrape = maxf(0.0, sin((mt - 0.25) / 0.3 * PI))
	b.thigh_r = Vector3(0.05 * k + 0.4 * scrape, 0.0, 0.0)
	b.shin_r = Vector3(0.08 * k - 0.15 * scrape, 0.0, 0.0)
	out.lift = -0.03 * k


## Étourdi : recule d'un pas, tête qui dodeline, bras ballants, oscille.
static func _stun(out: Dictionary, mt: float, t: float) -> void:
	var b: Dictionary = out.bones
	var hit := 1.0 - smoothstep(0.0, 0.45, mt)  # contrecoup du choc
	var w := sin(t * 2.6)
	b.spine = Vector3(-0.18 * hit + 0.1, 0.0, 0.06 * w)
	b.chest = Vector3(-0.12 * hit, 0.0, 0.0)
	b.neck = Vector3(0.35 - 0.4 * hit, 0.0, 0.0)
	b.head = Vector3(0.15, 0.25 * sin(t * 1.9), 0.45 * w)
	b.jaw = Vector3(0.38 + 0.05 * sin(t * 5.0), 0.0, 0.0)
	b.arm_l = Vector3(-0.1 - 0.2 * hit, 0.0, 0.32 + 0.06 * w)
	b.arm_r = Vector3(-0.1 - 0.2 * hit, 0.0, -0.32 + 0.06 * w)
	b.forearm_l = Vector3(-0.15, 0.0, 0.0)
	b.forearm_r = Vector3(-0.2, 0.0, 0.0)
	b.thigh_l = Vector3(-0.3, 0.0, 0.0)
	b.shin_l = Vector3(0.38, 0.0, 0.0)
	b.thigh_r = Vector3(-0.2 + 0.12 * hit, 0.0, 0.0)
	b.shin_r = Vector3(0.28, 0.0, 0.0)
	out.lift = -0.05
	out.roll = 0.09 * w
	out.pitch = -0.08 * hit


## Coup des deux poings : levés au-dessus de la tête puis abattus (k 0..1).
static func _smash(out: Dictionary, k: float) -> void:
	var b: Dictionary = out.bones
	var up := smoothstep(0.0, 0.38, k) * (1.0 - smoothstep(0.38, SMASH_HIT, k))
	var down := smoothstep(0.38, SMASH_HIT, k) * (1.0 - smoothstep(0.75, 1.0, k))
	var keep := 1.0 - maxf(up, down)
	for n in ["arm_l", "arm_r", "forearm_l", "forearm_r", "spine", "chest"]:
		b[n] = (b[n] as Vector3) * keep
	b.arm_l += Vector3(-2.7 * up - 1.25 * down, 0.0, 0.18 * up)
	b.arm_r += Vector3(-2.7 * up - 1.25 * down, 0.0, -0.18 * up)
	b.forearm_l += Vector3(-0.5 * up - 0.15 * down, 0.0, 0.0)
	b.forearm_r += Vector3(-0.5 * up - 0.15 * down, 0.0, 0.0)
	b.spine += Vector3(-0.12 * up + 0.42 * down, 0.0, 0.0)
	b.chest += Vector3(-0.05 * up + 0.12 * down, 0.0, 0.0)
	b.jaw = Vector3(0.2 + 0.4 * maxf(up, down), 0.0, 0.0)
	out.lift = (out.lift as float) * keep - 0.06 * down


## Mort : à genoux (DEATH_KNEEL), puis face contre terre (DEATH_FALL),
## immobile après DEATH_SETTLE.
static func _death(out: Dictionary, d: float) -> void:
	var b: Dictionary = out.bones
	var kneel := ease(clampf(d / DEATH_KNEEL, 0.0, 1.0), 0.6)
	var fall := ease(clampf((d - DEATH_KNEEL) / DEATH_FALL, 0.0, 1.0), 2.4)
	# Genoux : tibias repliés sous lui, puis jambes qui se détendent au sol.
	b.shin_l = Vector3(1.55 * kneel * (1.0 - 0.75 * fall), 0.0, 0.0)
	b.shin_r = Vector3(1.5 * kneel * (1.0 - 0.7 * fall), 0.0, 0.0)
	b.thigh_l = Vector3(-0.1 * kneel + 0.15 * fall, 0.0, 0.0)
	b.thigh_r = Vector3(-0.05 * kneel + 0.1 * fall, 0.0, 0.0)
	b.spine = Vector3(0.25 * kneel * (1.0 - fall), 0.0, 0.0)
	b.neck = Vector3(0.4 * kneel - 0.5 * fall, 0.0, 0.0)
	b.head = Vector3(0.0, 0.0, 0.35 * fall)
	b.jaw = Vector3(0.45, 0.0, 0.0)
	# Bras : pendants à genoux, jetés en avant dans la chute, puis écartés au sol.
	b.arm_l = Vector3(-0.2 * kneel - 2.75 * fall, 0.0, 0.25 + 0.2 * fall)
	b.arm_r = Vector3(-0.2 * kneel - 2.6 * fall, 0.0, -0.25 - 0.3 * fall)
	b.forearm_l = Vector3(-0.3 * (1.0 - fall), 0.0, 0.0)
	b.forearm_r = Vector3(-0.3 * (1.0 - fall) - 0.3 * fall, 0.0, 0.0)
	# À genoux : la racine descend juste assez pour que la pointe du sabot
	# (tibia de 0,5 m, pointe 0,22 m devant) reste au sol pendant que le tibia
	# bascule en arrière.
	var a := (b.shin_l as Vector3).x
	var drop := minf(SHIN_REACH.x - (SHIN_REACH.x * cos(a) + SHIN_REACH.y * sin(a)), KNEEL_DROP)
	out.lift = -drop * (1.0 - fall) + DEATH_LIFT * fall
	out.pitch = DEATH_PITCH * fall


## Écrit la pose `p` sur le squelette (rotations d'os, racine).
static func apply(skel: Skeleton3D, bones: Dictionary, p: Dictionary) -> void:
	var b: Dictionary = p.bones
	for n in b:
		if bones.has(n):
			skel.set_bone_pose_rotation(bones[n], Quaternion.from_euler(b[n]))
	skel.position = Vector3(0.0, p.lift, 0.0)
	skel.rotation = Vector3(p.pitch, 0.0, p.roll)
