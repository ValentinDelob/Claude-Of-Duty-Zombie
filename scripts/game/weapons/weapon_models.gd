class_name WeaponModels
extends RefCounted
## Modèles low-poly des armes, assemblés à partir de primitives.
## Repère : l'arme pointe vers -Z, origine au niveau de la détente.
## Chaque pièce : [forme, taille, position, matériau, rotation X (degrés)]
##   forme : "box" ou "cyl" (cylindre orienté selon Z, taille.x = rayon)

const MATERIALS := {
	"metal": [Color(0.16, 0.16, 0.17), 0.45, 0.8],
	"metal_dark": [Color(0.07, 0.07, 0.075), 0.5, 0.7],
	"metal_worn": [Color(0.3, 0.29, 0.27), 0.55, 0.7],
	"wood": [Color(0.26, 0.14, 0.07), 0.8, 0.0],
	"wood_dark": [Color(0.14, 0.07, 0.04), 0.85, 0.0],
	"polymer": [Color(0.09, 0.1, 0.09), 0.75, 0.0],
	"olive": [Color(0.2, 0.22, 0.14), 0.8, 0.0],
	"brass": [Color(0.55, 0.42, 0.18), 0.35, 0.9],
	"glow": [Color(1.0, 0.45, 0.15), 0.3, 0.0],
	"glass": [Color(0.1, 0.18, 0.2), 0.1, 0.3],
}

## Points remarquables : bouche du canon, point de visée (pour la visée ADS).
const ANCHORS := {
	"pistol": {"muzzle": Vector3(0, 0.035, -0.19), "sight": Vector3(0, 0.062, 0.02), "grip": Vector3(0, -0.06, 0.03), "support": Vector3(-0.02, -0.07, 0.02)},
	"carbine": {"muzzle": Vector3(0, 0.03, -0.72), "sight": Vector3(0, 0.075, 0.08), "grip": Vector3(0, -0.05, 0.08), "support": Vector3(0, -0.04, -0.3)},
	"smg": {"muzzle": Vector3(0, 0.03, -0.42), "sight": Vector3(0, 0.08, 0.05), "grip": Vector3(0, -0.06, 0.03), "support": Vector3(0, -0.1, -0.13)},
	"shotgun": {"muzzle": Vector3(0, 0.04, -0.7), "sight": Vector3(0, 0.07, 0.0), "grip": Vector3(0, -0.04, 0.12), "support": Vector3(0, -0.01, -0.3)},
	"assault": {"muzzle": Vector3(0, 0.035, -0.6), "sight": Vector3(0, 0.095, 0.06), "grip": Vector3(0, -0.06, 0.05), "support": Vector3(0, -0.01, -0.33)},
	"lmg": {"muzzle": Vector3(0, 0.04, -0.72), "sight": Vector3(0, 0.1, 0.05), "grip": Vector3(0, -0.07, 0.08), "support": Vector3(0, -0.01, -0.4)},
	"sniper": {"muzzle": Vector3(0, 0.035, -0.85), "sight": Vector3(0, 0.115, 0.08), "grip": Vector3(0, -0.05, 0.1), "support": Vector3(0, -0.04, -0.3)},
	"ray": {"muzzle": Vector3(0, 0.04, -0.3), "sight": Vector3(0, 0.1, 0.0), "grip": Vector3(0, -0.06, 0.04), "support": Vector3(-0.02, -0.07, 0.03)},
}

const PARTS := {
	"pistol": [
		["box", Vector3(0.034, 0.036, 0.21), Vector3(0, 0.035, -0.07), "metal_worn", 0],
		["box", Vector3(0.03, 0.026, 0.17), Vector3(0, 0.005, -0.06), "metal", 0],
		["box", Vector3(0.03, 0.11, 0.045), Vector3(0, -0.05, 0.02), "wood_dark", 12],
		["cyl", Vector3(0.009, 0, 0.03), Vector3(0, 0.035, -0.18), "metal_dark", 0],
		["box", Vector3(0.006, 0.012, 0.01), Vector3(0, 0.058, -0.165), "metal_dark", 0],
		["box", Vector3(0.024, 0.012, 0.01), Vector3(0, 0.058, 0.02), "metal_dark", 0],
		["box", Vector3(0.012, 0.02, 0.03), Vector3(0, -0.018, -0.02), "metal_dark", 0],
	],
	"carbine": [
		["box", Vector3(0.05, 0.06, 0.62), Vector3(0, 0.0, -0.2), "wood", 0],
		["box", Vector3(0.045, 0.1, 0.24), Vector3(0, -0.035, 0.2), "wood", -8],
		["box", Vector3(0.04, 0.045, 0.3), Vector3(0, 0.045, -0.02), "metal", 0],
		["cyl", Vector3(0.011, 0, 0.3), Vector3(0, 0.03, -0.56), "metal_dark", 0],
		["box", Vector3(0.035, 0.1, 0.035), Vector3(0, -0.07, -0.06), "metal_dark", 0],
		["box", Vector3(0.008, 0.03, 0.01), Vector3(0, 0.065, -0.68), "metal_dark", 0],
		["box", Vector3(0.03, 0.02, 0.02), Vector3(0, 0.075, 0.08), "metal_dark", 0],
	],
	"smg": [
		["box", Vector3(0.05, 0.065, 0.34), Vector3(0, 0.03, -0.12), "metal", 0],
		["box", Vector3(0.035, 0.12, 0.05), Vector3(0, -0.05, 0.02), "polymer", 14],
		["box", Vector3(0.03, 0.17, 0.035), Vector3(0, -0.08, -0.13), "metal_dark", 6],
		["cyl", Vector3(0.016, 0, 0.12), Vector3(0, 0.03, -0.35), "metal_dark", 0],
		["box", Vector3(0.02, 0.02, 0.22), Vector3(0, 0.02, 0.18), "metal_dark", 0],
		["box", Vector3(0.03, 0.06, 0.02), Vector3(0, 0.0, 0.29), "metal_dark", 0],
		["box", Vector3(0.012, 0.03, 0.02), Vector3(0, 0.075, 0.05), "metal_dark", 0],
		["box", Vector3(0.008, 0.028, 0.012), Vector3(0, 0.075, -0.27), "metal_dark", 0],
	],
	"shotgun": [
		["cyl", Vector3(0.018, 0, 0.62), Vector3(0, 0.045, -0.36), "metal_dark", 0],
		["cyl", Vector3(0.015, 0, 0.5), Vector3(0, 0.012, -0.32), "metal", 0],
		["box", Vector3(0.05, 0.05, 0.16), Vector3(0, 0.012, -0.3), "wood", 0],
		["box", Vector3(0.05, 0.07, 0.2), Vector3(0, 0.03, 0.0), "metal", 0],
		["box", Vector3(0.045, 0.11, 0.3), Vector3(0, -0.04, 0.23), "wood", -10],
		["box", Vector3(0.012, 0.012, 0.012), Vector3(0, 0.07, -0.66), "brass", 0],
	],
	"assault": [
		["box", Vector3(0.05, 0.075, 0.36), Vector3(0, 0.03, -0.08), "polymer", 0],
		["box", Vector3(0.055, 0.065, 0.2), Vector3(0, 0.03, -0.35), "olive", 0],
		["cyl", Vector3(0.012, 0, 0.18), Vector3(0, 0.035, -0.52), "metal_dark", 0],
		["box", Vector3(0.035, 0.16, 0.06), Vector3(0, -0.07, -0.12), "metal_dark", 12],
		["box", Vector3(0.035, 0.11, 0.045), Vector3(0, -0.05, 0.05), "polymer", 14],
		["box", Vector3(0.045, 0.08, 0.26), Vector3(0, 0.0, 0.25), "olive", 0],
		["box", Vector3(0.03, 0.03, 0.2), Vector3(0, 0.08, 0.0), "metal_dark", 0],
		["box", Vector3(0.02, 0.03, 0.02), Vector3(0, 0.1, 0.06), "glass", 0],
	],
	"lmg": [
		["box", Vector3(0.07, 0.09, 0.42), Vector3(0, 0.03, -0.08), "metal", 0],
		["cyl", Vector3(0.02, 0, 0.36), Vector3(0, 0.04, -0.52), "metal_dark", 0],
		["box", Vector3(0.1, 0.12, 0.13), Vector3(0.05, -0.04, -0.08), "olive", 0],
		["box", Vector3(0.04, 0.12, 0.05), Vector3(0, -0.06, 0.08), "polymer", 14],
		["box", Vector3(0.05, 0.09, 0.25), Vector3(0, 0.0, 0.28), "wood_dark", -5],
		["box", Vector3(0.05, 0.03, 0.22), Vector3(0, 0.085, -0.05), "metal_dark", 0],
		["box", Vector3(0.012, 0.02, 0.12), Vector3(0, -0.02, -0.55), "metal_dark", 50],
	],
	"sniper": [
		["box", Vector3(0.05, 0.06, 0.55), Vector3(0, 0.0, -0.08), "wood_dark", 0],
		["cyl", Vector3(0.013, 0, 0.42), Vector3(0, 0.035, -0.62), "metal_dark", 0],
		["box", Vector3(0.045, 0.1, 0.25), Vector3(0, -0.04, 0.28), "wood_dark", -10],
		["box", Vector3(0.04, 0.04, 0.24), Vector3(0, 0.04, -0.02), "metal", 0],
		["cyl", Vector3(0.022, 0, 0.3), Vector3(0, 0.1, 0.0), "metal_dark", 0],
		["cyl", Vector3(0.026, 0, 0.05), Vector3(0, 0.1, -0.16), "metal_dark", 0],
		["cyl", Vector3(0.018, 0, 0.01), Vector3(0, 0.1, 0.155), "glass", 0],
		["box", Vector3(0.03, 0.09, 0.03), Vector3(0, -0.06, -0.05), "metal_dark", 0],
	],
	"ray": [
		["box", Vector3(0.07, 0.08, 0.22), Vector3(0, 0.035, -0.06), "metal_worn", 0],
		["cyl", Vector3(0.045, 0, 0.1), Vector3(0, 0.04, -0.2), "metal", 0],
		["cyl", Vector3(0.03, 0, 0.06), Vector3(0, 0.04, -0.27), "glow", 0],
		["box", Vector3(0.035, 0.12, 0.05), Vector3(0, -0.05, 0.03), "metal_dark", 14],
		["box", Vector3(0.012, 0.05, 0.16), Vector3(0, 0.1, -0.06), "metal", 0],
		["cyl", Vector3(0.012, 0, 0.12), Vector3(0.04, 0.04, -0.06), "glow", 0],
		["cyl", Vector3(0.012, 0, 0.12), Vector3(-0.04, 0.04, -0.06), "glow", 0],
	],
}

static var _mat_cache: Dictionary = {}
static var _mesh_cache: Dictionary = {}


static func material(key: String, viewmodel: bool, pap: bool) -> ShaderMaterial:
	var cache_key := "%s_%s_%s" % [key, viewmodel, pap]
	if _mat_cache.has(cache_key):
		return _mat_cache[cache_key]
	var spec: Array = MATERIALS[key]
	var m := ShaderMaterial.new()
	m.shader = preload("res://assets/shaders/weapon.gdshader")
	m.set_shader_parameter("albedo", spec[0])
	m.set_shader_parameter("roughness", spec[1])
	m.set_shader_parameter("metallic", spec[2])
	m.set_shader_parameter("viewmodel", 1.0 if viewmodel else 0.0)
	m.set_shader_parameter("pap", 1.0 if pap and key != "glow" and key != "glass" else 0.0)
	if key == "glow":
		m.set_shader_parameter("emission", spec[0])
		m.set_shader_parameter("emission_energy", 3.0)
	_mat_cache[cache_key] = m
	return m


static func _mesh_for(part: Array) -> Mesh:
	var key := var_to_str(part.slice(0, 2))
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var mesh: Mesh
	if part[0] == "cyl":
		var c := CylinderMesh.new()
		c.top_radius = part[1].x
		c.bottom_radius = part[1].x
		c.height = part[1].z
		c.radial_segments = 8
		c.rings = 1
		mesh = c
	else:
		var b := BoxMesh.new()
		b.size = part[1]
		mesh = b
	_mesh_cache[key] = mesh
	return mesh


## Construit le modèle d'une arme. `viewmodel` : matériaux vue FPS.
static func build(model_id: String, viewmodel: bool, pap := false) -> Node3D:
	var root := Node3D.new()
	root.name = "Model_" + model_id
	for part in PARTS.get(model_id, PARTS.pistol):
		var mi := MeshInstance3D.new()
		mi.mesh = _mesh_for(part)
		mi.material_override = material(part[3], viewmodel, pap)
		mi.position = part[2]
		if part[0] == "cyl":
			mi.rotation.x = PI * 0.5
		if part[4] != 0:
			mi.rotation.x += deg_to_rad(part[4])
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if viewmodel else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if viewmodel:
			# Pas de culling par frustum : l'arme est toujours à l'écran.
			mi.extra_cull_margin = 1.0
		root.add_child(mi)
	return root


static func anchor(model_id: String, point: String) -> Vector3:
	return ANCHORS.get(model_id, ANCHORS.pistol)[point]
