class_name MapProps
extends RefCounted
## Décor d'une carte vu par le jeu : courant (PowerGrid), grésillement des
## lampes (LightFlicker) et matériaux à shader dédié à préchauffer. Commun aux
## cartes grille (PropBuilder) et aux cartes en maillage (MeshMapBuilder).

var root: Node3D
var flicker: LightFlicker
var power: PowerGrid
## Matériaux à shader dédié, montrés pendant le préchauffage (Warmup).
var warmup_materials: Array[Material] = []
var _lamp_i := 0


## Nœud racine du décor, avec le grésillement et le réseau électrique.
func _make_root(parent: Node3D, root_name := "Props") -> void:
	root = Node3D.new()
	root.name = root_name
	parent.add_child(root)
	flicker = LightFlicker.new()
	flicker.name = "LightFlicker"
	root.add_child(flicker)
	power = PowerGrid.new()
	power.name = "PowerGrid"
	power.setup(flicker)
	root.add_child(power)


## Lampe de la carte : groupe RenderQuality (ombres et fondu selon la
## qualité), reliée au courant, grésillante si `flickers`.
func add_lamp(pos: Vector3, energy: float, light_range: float, flickers: bool) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.name = "Lamp%d" % _lamp_i
	light.position = pos
	light.light_color = Color(1.0, 0.74, 0.5)
	light.light_energy = energy
	light.omni_range = light_range
	light.omni_attenuation = 1.3
	# Ombres et distances de fondu : réglées par RenderQuality.
	light.set_meta("lamp_index", _lamp_i)
	light.add_to_group(RenderQuality.LAMP_GROUP)
	RenderQuality.apply_lamp(light, RenderQuality.current())
	root.add_child(light)
	if flickers:
		flicker.add(light)
	power.add(light)
	_lamp_i += 1
	return light
