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
## qualité), reliée au courant (sinon toujours allumée : bougies, feu),
## grésillante si `flickers`. `color` : couleur une fois le courant rétabli
## (luminaires de l'éditeur ; par défaut l'ampoule chaude des lampes BO1).
## `fixture` : type de luminaire de l'éditeur (« » : lampe de plafond
## automatique ou de BUNKER K-7) ; il choisit le rendu (LampStyle) : sous un
## abat-jour, faible lueur de la lampe + flaque dirigée vers le bas (LampPool).
func add_lamp(pos: Vector3, energy: float, light_range: float, flickers: bool, color := PowerGrid.ON_COLOR, powered := true, fixture := "") -> OmniLight3D:
	var style := LampStyle.of(fixture)
	var light := OmniLight3D.new()
	light.name = "Lamp%d" % _lamp_i
	light.position = pos
	light.light_color = color
	light.light_energy = energy
	light.omni_range = light_range
	light.omni_attenuation = float(style.get("att", 1.3))
	light.light_volumetric_fog_energy = float(style.get("fog", 1.0))
	if LampStyle.has_pool(style):
		var fill := float(style.fill)
		light.light_energy = energy * fill
		light.omni_range = light_range * float(style.fill_range)
		light.omni_attenuation = float(style.fill_att)
		light.light_volumetric_fog_energy = float(style.fill_fog)
		var pool := LampPool.new()
		pool.name = "Pool"
		pool.ratio = float(style.pool) / fill
		pool.rotation.x = -PI * 0.5
		pool.spot_range = light_range * float(style.range_k)
		pool.spot_angle = float(style.angle)
		pool.spot_angle_attenuation = float(style.angle_att)
		pool.spot_attenuation = 1.0
		pool.light_volumetric_fog_energy = float(style.fog)
		pool.shadow_bias = 0.04
		pool.shadow_normal_bias = 1.2
		light.add_child(pool)
	# Ombres et distances de fondu : réglées par RenderQuality.
	light.set_meta("lamp_index", _lamp_i)
	light.add_to_group(RenderQuality.LAMP_GROUP)
	RenderQuality.apply_lamp(light, RenderQuality.current())
	root.add_child(light)
	if flickers:
		flicker.add(light)
	if powered:
		power.add(light, color)
	_lamp_i += 1
	return light
