class_name WorldLook
extends RefCounted
## Direction artistique du monde : matériaux, environnement, éclairage.
## Centralisé ici pour pouvoir ajuster l'ambiance (et les réglages de qualité)
## sans toucher au gameplay.


static func map_materials() -> Dictionary:
	return {
		"floor": _mat(Color(0.23, 0.22, 0.2), 0.95),
		"wall": _mat(Color(0.33, 0.32, 0.3), 0.9),
		"ceiling": _mat(Color(0.12, 0.12, 0.12), 1.0),
	}


static func _mat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


static func setup_environment(parent: Node3D) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.01, 0.012)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.32, 0.34, 0.4)
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.05
	env.fog_enabled = true
	env.fog_light_color = Color(0.05, 0.05, 0.06)
	env.fog_density = 0.035
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	parent.add_child(we)


## Lampes de plafond sur les marqueurs 'L'.
static func place_lamps(parent: Node3D, data: MapData) -> void:
	var root := Node3D.new()
	root.name = "Lamps"
	parent.add_child(root)
	var bulb_mat := StandardMaterial3D.new()
	bulb_mat.emission_enabled = true
	bulb_mat.emission = Color(1.0, 0.75, 0.45)
	bulb_mat.emission_energy_multiplier = 3.0
	bulb_mat.albedo_color = Color(1, 0.8, 0.5)
	var bulb_mesh := SphereMesh.new()
	bulb_mesh.radius = 0.09
	bulb_mesh.height = 0.18
	var i := 0
	for c in data.markers.get("L", []):
		var light := OmniLight3D.new()
		light.name = "Lamp%d" % i
		light.position = MapData.cell_to_world(c, MapBuilder.WALL_HEIGHT - 0.35)
		light.light_color = Color(1.0, 0.78, 0.55)
		light.light_energy = 1.6
		light.omni_range = 8.0
		light.omni_attenuation = 1.2
		# Ombres sur une lampe sur deux seulement (budget GTX 1050).
		light.shadow_enabled = i % 2 == 0
		root.add_child(light)
		var bulb := MeshInstance3D.new()
		bulb.mesh = bulb_mesh
		bulb.material_override = bulb_mat
		bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		light.add_child(bulb)
		i += 1
