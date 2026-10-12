class_name LootArc
extends RefCounted
## Trajectoire d'un butin qui JAILLIT d'un zombie tué (comme les objets de
## Minecraft) : petite impulsion vers le haut, écart horizontal, chute sous
## la gravité, un ou deux rebonds, puis l'objet se pose et s'élève doucement
## jusqu'à sa hauteur de flottement (léger va-et-vient, rotation lente).
##
## Pur et DÉTERMINISTE : le serveur choisit le point de départ (le corps) et
## le point d'arrivée (au sol, LootSystem.scatter_point) ; chaque machine
## rejoue le même arc à partir de (départ, arrivée, graine). Testé par
## tests/test_loot_fx.gd.

## Gravité du vol (m/s², un peu flottante : on suit l'objet des yeux).
const GRAVITY := 11.0
## Hauteur du saut au-dessus du point de départ (m).
const APEX_MIN := 0.45
const APEX_MAX := 0.75
## Part du trajet horizontal faite pendant le vol (le reste aux rebonds).
const FLY_SHARE := 0.82
const BOUNCE1_SHARE := 0.13
## Hauteurs des deux rebonds (m).
const BOUNCE1_MIN := 0.10
const BOUNCE1_MAX := 0.16
const BOUNCE2_RATIO := 0.3
## Flottement une fois posé : hauteur (m), montée (s), va-et-vient.
const HOVER_H := 0.3
const HOVER_RISE := 0.55
const BOB_AMP := 0.035
const BOB_SPEED := 2.2
## Rotation : en vol (rad/s, ralentit jusqu'au sol) puis au repos.
const SPIN_FLY := 9.0
const SPIN_IDLE := 0.9


## Plan de l'arc de `start` à `end` (graine `seed`) : {start, end, apex (m
## au-dessus du départ), t_up, t_down, b1 [début, durée, hauteur], b2,
## settle (fin des rebonds, s), dir (sens de rotation ±1), phase}.
static func plan(start: Vector3, end: Vector3, seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var apex := rng.randf_range(APEX_MIN, APEX_MAX)
	var t_up := sqrt(2.0 * apex / GRAVITY)
	var fall := maxf(apex + start.y - end.y, 0.05)
	var t_down := sqrt(2.0 * fall / GRAVITY)
	var h1 := rng.randf_range(BOUNCE1_MIN, BOUNCE1_MAX)
	var h2 := h1 * BOUNCE2_RATIO
	var d1 := 2.0 * sqrt(2.0 * h1 / GRAVITY)
	var d2 := 2.0 * sqrt(2.0 * h2 / GRAVITY)
	var t1 := t_up + t_down
	return {
		"start": start, "end": end, "apex": apex, "t_up": t_up, "t_down": t_down,
		"b1": [t1, d1, h1], "b2": [t1 + d1, d2, h2], "settle": t1 + d1 + d2,
		"dir": 1.0 if rng.randf() < 0.5 else -1.0, "phase": rng.randf() * TAU,
	}


## Instants où l'objet touche le sol (s) : fin du vol et de chaque rebond.
static func landings(p: Dictionary) -> PackedFloat32Array:
	var b1: Array = p.b1
	var b2: Array = p.b2
	return PackedFloat32Array([float(b1[0]), float(b2[0]), float(p.settle)])


## Position de l'objet (point de repos du modèle, sans le flottement) au
## temps `t` (s depuis l'apparition).
static func position(p: Dictionary, t: float) -> Vector3:
	var start: Vector3 = p.start
	var end: Vector3 = p.end
	if t <= 0.0:
		return start
	if t >= float(p.settle):
		return end
	var t_up: float = p.t_up
	var t_fly := t_up + float(p.t_down)
	var flat_from := Vector2(start.x, start.z)
	var flat_to := Vector2(end.x, end.z)
	var share := 0.0
	var y := end.y
	if t < t_fly:
		share = FLY_SHARE * t / t_fly
		# Montée puis chute : parabole de sommet start.y + apex en t_up.
		var top := start.y + float(p.apex)
		y = top - 0.5 * GRAVITY * (t - t_up) * (t - t_up)
		y = maxf(y, end.y)
	else:
		var b: Array = p.b1 if t < float(p.b2[0]) else p.b2
		var u := (t - float(b[0])) / maxf(float(b[1]), 0.0001)
		var from_share := FLY_SHARE if b == p.b1 else FLY_SHARE + BOUNCE1_SHARE
		var to_share := FLY_SHARE + BOUNCE1_SHARE if b == p.b1 else 1.0
		share = lerpf(from_share, to_share, u)
		y = end.y + float(b[2]) * 4.0 * u * (1.0 - u)
	var flat := flat_from.lerp(flat_to, share)
	return Vector3(flat.x, y, flat.y)


## Hauteur de flottement au-dessus du point de repos, `since` s après la fin
## des rebonds (0 avant) : montée douce puis va-et-vient.
static func hover(p: Dictionary, since: float) -> float:
	if since <= 0.0:
		return 0.0
	var rise := smoothstep(0.0, HOVER_RISE, since)
	return HOVER_H * rise + BOB_AMP * sin(since * BOB_SPEED + float(p.phase)) * rise


## Rotation autour de la verticale (rad) au temps `t` : rapide en vol,
## ralentit jusqu'au repos, puis tour lent continu.
static func spin(p: Dictionary, t: float) -> float:
	var settle: float = p.settle
	var dir: float = p.dir
	var base := float(p.phase)
	if t <= settle:
		# Vitesse qui décroît linéairement de SPIN_FLY à SPIN_IDLE.
		var k := clampf(t / settle, 0.0, 1.0)
		var w0 := SPIN_FLY
		var w1 := SPIN_IDLE
		return base + dir * (w0 * t + (w1 - w0) * 0.5 * t * k)
	var at_settle := base + dir * (SPIN_FLY * settle + (SPIN_IDLE - SPIN_FLY) * 0.5 * settle)
	return at_settle + dir * SPIN_IDLE * (t - settle)


## Bascule en vol (rad, autour de l'axe horizontal) : l'objet culbute un peu
## puis se pose à plat.
static func tumble(p: Dictionary, t: float) -> float:
	var settle: float = p.settle
	if t <= 0.0 or t >= settle:
		return 0.0
	return 0.55 * sin(PI * t / settle) * float(p.dir)
