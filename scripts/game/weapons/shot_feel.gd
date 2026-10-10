class_name ShotFeel
extends RefCounted
## Sensation de tir du joueur LOCAL (façon BO1), purement côté client :
##
## * dispersion dynamique : cône de base de l'arme, ouvert par le déplacement
##   (x2 en l'air) et par les tirs récents (« bloom »), refermé en ~0,3 s ;
##   quasi nul en visée. Le réticule du HUD dessine exactement ce cône ;
## * recul : chaque coup ajoute une montée du canon (et un écart latéral
##   aléatoire) appliquée progressivement sur ~0,1 s au regard du joueur, puis
##   une partie (`recoil_recover`) est rendue automatiquement après le tir ;
## * lunette : balancement lent de la visée (décalage de la caméra, donc des
##   balles), respiration retenue avec [Maj] pendant HOLD_TIME s, puis souffle
##   court (balancement accru pendant GASP_TIME s).
##
## Multiplicateurs (1 aujourd'hui, anciens atouts) : `hip_mult` (dispersion à la
## hanche) et `recoil_mult` (recul) passés par WeaponController.

## Vitesse d'application de la montée du canon (1/s) : ~95 % en 0,1 s.
const KICK_RATE := 30.0
## Délai après le dernier coup avant le retour automatique (s), et vitesse.
const RECOVER_DELAY := 0.12
const RECOVER_RATE := 7.0
## Le bloom commence à se refermer après ce délai (s) : il s'accumule en rafale.
const BLOOM_DELAY := 0.15
## Respiration retenue (s) et essoufflement qui suit (s).
const HOLD_TIME := 4.0
const GASP_TIME := 2.5
## Amplitude du balancement dans la lunette (°), debout et immobile.
const SWAY_DEG := 0.5

var bloom := 0.0
var move_k := 0.0
## Dispersion courante (°) : celle du prochain tir et du réticule.
var spread := 0.0
## Montée restant à appliquer (tangage, lacet ; rad) et part à rendre (rad).
var kick_left := Vector2.ZERO
var debt := 0.0
var last_shot := -10.0
## Montée (°) du dernier coup (tests : DEADEYE DRAM réduit le recul).
var last_kick_deg := 0.0

## Lunette : réserve de souffle (0..1), respiration retenue, essoufflement.
var breath := 1.0
var holding := false
var gasp := 0.0
var _sway_t := 0.0
## Décalage de visée (tangage, lacet ; rad) ajouté à la caméra par Player.
var aim_offset := Vector2.ZERO


## À chaque image physique. `scoped` : l'écran de lunette est affiché ;
## `hold` : touche de respiration enfoncée.
func update(delta: float, p: Player, s: Dictionary, ads: float, scoped: bool, hold: bool, hip_mult: float, t: float) -> void:
	# Déplacement : 0 à l'arrêt, 1 à la vitesse de marche, 2 en l'air.
	var speed := Vector2(p.velocity.x, p.velocity.z).length()
	var want := clampf(speed / Player.WALK_SPEED, 0.0, 1.3)
	if not p.is_on_floor():
		want = 2.0
	move_k = move_toward(move_k, want, delta * 5.0)
	if t - last_shot > BLOOM_DELAY:
		bloom = move_toward(bloom, 0.0, delta * maxf(float(s.get("spread_hip", 1.0)) * 4.0, 4.0))
	var stance := 0.6 if p.prone else (0.75 if p.crouching else 1.0)
	spread = WeaponDB.spread_deg(s, ads, move_k, stance, bloom, hip_mult) if not s.is_empty() else 0.0

	# Recul : montée progressive, puis retour partiel.
	if kick_left.length_squared() > 1e-10:
		var k := 1.0 - exp(-delta * KICK_RATE)
		var step := kick_left * k
		kick_left -= step
		p.pitch = clampf(p.pitch + step.x, -Player.PITCH_LIMIT, Player.PITCH_LIMIT)
		p.yaw += step.y
	if debt > 0.0 and t - last_shot > RECOVER_DELAY:
		var back := minf(debt, debt * (1.0 - exp(-delta * RECOVER_RATE)) + delta * 0.002)
		debt -= back
		p.pitch = clampf(p.pitch - back, -Player.PITCH_LIMIT, Player.PITCH_LIMIT)

	# Lunette : respiration et balancement.
	if gasp > 0.0:
		gasp -= delta
	holding = scoped and hold and gasp <= 0.0 and breath > 0.0
	if holding:
		breath -= delta / HOLD_TIME
		if breath <= 0.0:
			breath = 0.0
			holding = false
			gasp = GASP_TIME
	else:
		breath = minf(breath + delta / 3.0, 1.0)
	var target := Vector2.ZERO
	if scoped:
		_sway_t += delta
		var amp := deg_to_rad(SWAY_DEG) * stance * (1.0 + move_k * 1.5)
		if holding:
			amp *= 0.06
		elif gasp > 0.0:
			amp *= 1.0 + 1.4 * clampf(gasp / GASP_TIME, 0.0, 1.0)
		target = amp * sway_curve(_sway_t)
	aim_offset = aim_offset.lerp(target, 1.0 - exp(-delta * (6.0 if scoped else 14.0)))


## Un coup vient de partir : ouvre le réticule et prépare la montée du canon.
func on_shot(s: Dictionary, ads: float, recoil_mult: float, t: float) -> void:
	last_shot = t
	bloom = minf(bloom + float(s.get("bloom", 0.3)), WeaponDB.bloom_max(s))
	var ads_k := 0.65 if ads > 0.5 else 1.0
	var up := deg_to_rad(float(s.recoil)) * ads_k * recoil_mult * randf_range(0.9, 1.1)
	var side := deg_to_rad(float(s.get("recoil_side", float(s.recoil) * 0.3))) * randf_range(-1.0, 1.0) * ads_k * recoil_mult
	kick_left += Vector2(up, side)
	debt += up * float(s.get("recoil_recover", 0.6))
	last_kick_deg = rad_to_deg(up)


## Arme changée ou joueur à terre : plus de recul ni de bloom en attente.
func reset() -> void:
	bloom = 0.0
	kick_left = Vector2.ZERO
	debt = 0.0


## Courbe de balancement (lente, non périodique à l'œil), amplitude ~1.
static func sway_curve(t: float) -> Vector2:
	return Vector2(sin(t * 1.3) * 0.6 + sin(t * 2.9 + 1.0) * 0.25, cos(t * 0.9) * 0.7 + sin(t * 2.1 + 0.4) * 0.3)
