class_name BreathFeedback
extends Node
## Essoufflement audible du joueur local (GAME_CONCEPT §4.14, ENERGY_PLAN lot 2).
##
## L'énergie est invisible : la fatigue ne s'entend que par la respiration.
## Rien au-dessus de 35 % ; en dessous, souffles de plus en plus rapprochés et
## forts ; halètement fort et rapide tant que le joueur est épuisé ; puis
## retour progressif au calme (l'intensité redescend lentement).
##
##   var breath := BreathFeedback.new()
##   add_child(breath)          # joueur local seulement
##   breath.setup(energy)       # objet énergie : ratio() -> float, exhausted: bool
##
## Priorité à la santé basse : hud.gd joue déjà sa propre respiration avec le
## battement de cœur. Le propriétaire règle `suppressed` (par exemple avec
## `health_breath_active()`, même seuil que hud.gd) : tant qu'il est vrai,
## aucun souffle d'énergie n'est joué, pour ne jamais superposer les deux.
##
## Mixage : sons 2D sur le bus SFX, jamais plus forts que la respiration de
## santé basse de hud.gd (-8 dB), et aucun autre son n'est baissé.

## Sous ce ratio d'énergie, la respiration devient audible.
const THRESHOLD := 0.35
## Intervalle entre deux souffles (s) : juste sous le seuil -> au plus bas.
const INTERVAL_CALM := 2.4
const INTERVAL_LOW := 0.95
## Halètement de l'épuisement.
const INTERVAL_EXHAUSTED := 0.7
## Volume (dB) : discret au seuil, plafonné au niveau de la respiration de
## santé basse de hud.gd (-8 dB).
const VOLUME_CALM := -20.0
const VOLUME_MAX := -8.0
## Hauteur : un souffle court est plus aigu.
const PITCH_CALM := 0.95
const PITCH_MAX := 1.1
## Intensité atteinte à énergie nulle hors épuisement (l'épuisement vaut 1).
const LOW_MAX_INTENSITY := 0.8
## Vitesses de variation de l'intensité (par seconde) : monte vite, redescend
## lentement (environ 5 s de l'épuisement au silence).
const RISE_RATE := 2.0
const FALL_RATE := 0.2
## Sous cette intensité, plus aucun souffle.
const SILENT := 0.02
## Variations aléatoires pour éviter la répétition.
const VOLUME_JITTER := 1.5
const INTERVAL_JITTER := 0.12
const PITCH_JITTER := 0.05
## Seuil de la respiration de santé basse de hud.gd (`hurt > 0.45`).
const HEALTH_BREATH_HURT := 0.45

## Le propriétaire coupe la respiration d'énergie (santé basse, à terre...).
var suppressed := false
## Intensité lissée courante (0 : calme, 1 : halètement), lue par les tests.
var intensity := 0.0
## Nombre de souffles joués depuis setup() (diagnostic, tests).
var breaths := 0

var _energy: Object = null
var _until_next := 0.0
var _last_sound := 0


## Objet énergie lu à chaque image (duck typing : `ratio()` et `exhausted`).
func setup(energy: Object) -> void:
	_energy = energy
	intensity = 0.0
	breaths = 0
	_until_next = 0.0


## Intensité visée (0..1) pour un ratio d'énergie et l'état d'épuisement.
static func target_intensity(ratio: float, exhausted: bool) -> float:
	if exhausted:
		return 1.0
	if ratio >= THRESHOLD:
		return 0.0
	return clampf((THRESHOLD - ratio) / THRESHOLD, 0.0, 1.0) * LOW_MAX_INTENSITY


## Intensité lissée : monte vite vers la cible, redescend lentement.
static func smooth_intensity(current: float, target: float, delta: float) -> float:
	if target > current:
		return minf(current + RISE_RATE * delta, target)
	return maxf(current - FALL_RATE * delta, target)


## Intervalle (s) entre deux souffles pour une intensité (0..1).
static func interval_for(k: float) -> float:
	k = clampf(k, 0.0, 1.0)
	if k <= LOW_MAX_INTENSITY:
		return lerpf(INTERVAL_CALM, INTERVAL_LOW, k / LOW_MAX_INTENSITY)
	return lerpf(INTERVAL_LOW, INTERVAL_EXHAUSTED, (k - LOW_MAX_INTENSITY) / (1.0 - LOW_MAX_INTENSITY))


## Volume (dB) d'un souffle pour une intensité (0..1), plafonné à VOLUME_MAX.
static func volume_for(k: float) -> float:
	return lerpf(VOLUME_CALM, VOLUME_MAX, clampf(k, 0.0, 1.0))


## Hauteur d'un souffle pour une intensité (0..1).
static func pitch_for(k: float) -> float:
	return lerpf(PITCH_CALM, PITCH_MAX, clampf(k, 0.0, 1.0))


## Intervalle entre deux souffles directement depuis l'état d'énergie
## (sans lissage) ; INF quand le joueur respire normalement.
static func breath_interval(ratio: float, exhausted: bool) -> float:
	var k := target_intensity(ratio, exhausted)
	return INF if k < SILENT else interval_for(k)


## Volume (dB) directement depuis l'état d'énergie (sans lissage) ; -INF
## quand le joueur respire normalement.
static func breath_volume(ratio: float, exhausted: bool) -> float:
	var k := target_intensity(ratio, exhausted)
	return -INF if k < SILENT else volume_for(k)


## La respiration de santé basse de hud.gd est-elle en cours ? (même
## condition que hud.gd : vivant et plus de 45 % de la santé perdue.)
static func health_breath_active(health: float, max_health: float, alive: bool) -> bool:
	return alive and 1.0 - health / maxf(max_health, 1.0) > HEALTH_BREATH_HURT


func _process(delta: float) -> void:
	if _energy == null or not is_instance_valid(_energy):
		return
	var ratio := float(_energy.call("ratio"))
	var exhausted := bool(_energy.get("exhausted"))
	intensity = smooth_intensity(intensity, target_intensity(ratio, exhausted), delta)
	if intensity < SILENT:
		_until_next = 0.0
		return
	_until_next -= delta
	if _until_next > 0.0:
		return
	_until_next = interval_for(intensity) * (1.0 + randf_range(-INTERVAL_JITTER, INTERVAL_JITTER))
	# Santé basse prioritaire : le rythme continue mais rien n'est joué.
	if suppressed:
		return
	_breathe()


func _breathe() -> void:
	# Alterne les deux souffles, avec un doublé de temps en temps.
	if randf() < 0.7:
		_last_sound = 1 - _last_sound
	breaths += 1
	var vol := minf(volume_for(intensity) + randf_range(-VOLUME_JITTER, VOLUME_JITTER), VOLUME_MAX)
	Audio.play_2d("player_breath_%d" % (1 + _last_sound), vol, PITCH_JITTER, "SFX", pitch_for(intensity))
