class_name PowerupDrop
extends Node3D
## Bonus posé au sol (visuel, toutes les machines). Le serveur décide de son
## apparition, de son ramassage et de sa disparition (PowerupSystem).

const FLOAT_HEIGHT := 0.85
const BOB := 0.08
const SPIN := 1.6  # rad/s

var drop_id := 0
var type := ""
## Secondes écoulées depuis l'apparition (clignotement de fin de vie).
var age := 0.0
## Visible à cet instant (faux pendant les phases éteintes du clignotement).
var shown := true
var _visual: Node3D
var _model: Node3D
var _light: OmniLight3D
var _loop: AudioStreamPlayer3D


func setup(id: int, t: String, start_age := 0.0) -> void:
	drop_id = id
	type = t
	age = start_age
	name = "Drop%d" % id


func _ready() -> void:
	_visual = Node3D.new()
	_visual.position.y = FLOAT_HEIGHT
	add_child(_visual)
	_model = PowerupModels.build(type)
	_model.scale = Vector3.ONE * 1.6
	_visual.add_child(_model)
	var h := PowerupModels.halo(1.6)
	_visual.add_child(h)
	_light = OmniLight3D.new()
	_light.light_color = Color(0.3, 1.0, 0.35)
	_light.light_energy = 1.6
	_light.omni_range = 3.2
	_light.shadow_enabled = false
	_visual.add_child(_light)
	_loop = AudioStreamPlayer3D.new()
	_loop.bus = "SFX"
	_loop.stream = Audio.get_stream("powerup_loop")
	_loop.unit_size = 3.0
	_loop.max_distance = 25.0
	_loop.volume_db = -6.0
	_visual.add_child(_loop)
	if _loop.stream:
		_loop.play()


func _process(delta: float) -> void:
	age += delta
	_model.rotation.y += SPIN * delta
	_visual.position.y = FLOAT_HEIGHT + sin(age * 2.2) * BOB
	var vis := PowerupRules.drop_visible(age)
	if shown != vis:
		shown = vis
		# Le son en boucle continue pendant le clignotement.
		for c in _visual.get_children():
			if c is Node3D and c != _loop:
				c.visible = vis


## Position de référence pour le ramassage (au sol).
func ground_position() -> Vector3:
	return global_position
