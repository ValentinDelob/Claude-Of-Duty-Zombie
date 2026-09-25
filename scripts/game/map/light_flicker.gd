class_name LightFlicker
extends Node
## Fait grésiller des lampes (un seul script pour toutes : pas de coût par
## lampe). Alternance de phases stables et de coupures brèves, irrégulières.

var _lights: Array[OmniLight3D] = []
var _base: PackedFloat32Array = []
var _timer: PackedFloat32Array = []
var _state: PackedByteArray = []
var _rng := RandomNumberGenerator.new()
## 0..1 : multiplicateur global (courant coupé / rétabli).
var master := 1.0


func add(light: OmniLight3D) -> void:
	_lights.append(light)
	_base.append(light.light_energy)
	_timer.append(_rng.randf_range(0.5, 4.0))
	_state.append(1)


func _ready() -> void:
	_rng.seed = 4242


func _process(delta: float) -> void:
	for i in _lights.size():
		_timer[i] -= delta
		if _timer[i] <= 0.0:
			if _state[i] == 1:
				_state[i] = 0
				_timer[i] = _rng.randf_range(0.03, 0.18)
			else:
				_state[i] = 1
				# Parfois une rafale de coupures rapprochées.
				_timer[i] = _rng.randf_range(0.04, 0.3) if _rng.randf() < 0.5 else _rng.randf_range(1.0, 5.0)
		var e := _base[i] * master
		_lights[i].light_energy = e if _state[i] == 1 else e * 0.08


## Met à jour l'énergie de référence d'une lampe (changement de courant).
func set_base(light: OmniLight3D, energy: float) -> void:
	var i := _lights.find(light)
	if i >= 0:
		_base[i] = energy
