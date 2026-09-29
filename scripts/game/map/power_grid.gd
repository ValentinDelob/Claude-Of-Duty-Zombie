class_name PowerGrid
extends Node
## Éclairage de la carte selon l'état du courant.
##
## Courant coupé : lampes faibles, blanc pâle neutre (comme BO1 avant le
## courant, sans teinte de secours rouge ; à peine chaud car l'étalonnage
## refroidit les zones sombres), grésillement.
## Courant rétabli : les lampes se rallument en cascade depuis le générateur.
## Purement visuel ; l'état du courant fait foi côté serveur (PowerSwitch).

const OFF_ENERGY := 0.4
const OFF_COLOR := Color(0.95, 0.9, 0.82)
const ON_COLOR := Color(1.0, 0.74, 0.5)
const CASCADE_SPEED := 14.0  # m/s

var _lights: Array[OmniLight3D] = []
var _base: PackedFloat32Array = []
## Couleur de chaque lampe une fois le courant rétabli (luminaires colorés de l'éditeur).
var _on_color: PackedColorArray = []
var _flicker: LightFlicker
## Décor lié au courant (écran de cinéma, faisceau du projecteur...) :
## Callable(on: bool), appelés à chaque changement.
var _hooks: Array[Callable] = []
var powered := false


func setup(flicker: LightFlicker) -> void:
	_flicker = flicker


func add_hook(cb: Callable) -> void:
	_hooks.append(cb)
	cb.call(powered)


func add(light: OmniLight3D, on_color := ON_COLOR) -> void:
	_lights.append(light)
	_base.append(light.light_energy)
	_on_color.append(on_color)


## État initial sans animation (chargement de la carte).
func apply_immediate(on: bool) -> void:
	powered = on
	for i in _lights.size():
		_set_light(i, on)
	for h in _hooks:
		h.call(on)
	if _flicker:
		_flicker.master = 1.0


## Rallumage en cascade depuis `origin`.
func power_on_from(origin: Vector3) -> void:
	powered = true
	for h in _hooks:
		h.call(true)
	for i in _lights.size():
		var l := _lights[i]
		var delay := l.global_position.distance_to(origin) / CASCADE_SPEED
		var tw := l.create_tween()
		tw.tween_interval(delay)
		# Petit clignotement avant l'allumage.
		tw.tween_callback(func(): l.light_energy = _base[i] * 1.6; l.light_color = _on_color[i])
		tw.tween_interval(0.06)
		tw.tween_callback(func(): l.light_energy = 0.0)
		tw.tween_interval(0.08)
		tw.tween_callback(_set_light.bind(i, true))
		if i % 4 == 0:
			tw.tween_callback(func(): Audio.play_3d("lamp_on", l.global_position, -10.0, 0.1, 3))


func _set_light(i: int, on: bool) -> void:
	var l := _lights[i]
	l.light_color = _on_color[i] if on else OFF_COLOR
	l.light_energy = _base[i] if on else _base[i] * OFF_ENERGY
	# LightFlicker lit l'énergie de base : on la met à jour.
	if _flicker:
		_flicker.set_base(l, l.light_energy)
