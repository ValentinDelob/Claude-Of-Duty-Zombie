class_name ZombieModel
extends RefCounted
## Génère l'apparence d'un zombie à partir d'une graine (variante) : couleurs de
## peau et de vêtements, membres manquants, bosse... Déterministe : la même
## variante donne le même zombie sur toutes les machines.

const SKINS := [
	Color(0.36, 0.38, 0.3), Color(0.42, 0.4, 0.34), Color(0.3, 0.33, 0.29),
	Color(0.45, 0.36, 0.33), Color(0.33, 0.3, 0.27),
]
const SHIRTS := [
	Color(0.2, 0.22, 0.15), Color(0.16, 0.17, 0.13), Color(0.55, 0.53, 0.48),
	Color(0.24, 0.2, 0.16), Color(0.14, 0.15, 0.18), Color(0.3, 0.12, 0.1),
]
const PANTS := [
	Color(0.14, 0.15, 0.11), Color(0.1, 0.1, 0.1), Color(0.2, 0.18, 0.14), Color(0.12, 0.13, 0.16),
]
const BOOTS := Color(0.06, 0.05, 0.04)
const WOUND := Color(0.32, 0.03, 0.03)
const EYE := Color(1.0, 0.55, 0.2)

static var _material: ShaderMaterial


static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = preload("res://assets/shaders/character.gdshader")
		# Yeux orange « Claude ».
		_material.set_shader_parameter("emission_color", Color(1.0, 0.45, 0.12))
		_material.set_shader_parameter("emission_energy", 5.0)
	return _material


static func build(variant: int) -> Skeleton3D:
	var d := parts_for(variant)
	return RigBuilder.build(d[0], material(), d[1])


## Morceau de corps arraché (démembrement) : mesh non skinné des boîtes des os
## `limb_bones`, dans le repère de repos du premier os. Mêmes couleurs que le
## zombie `variant` (déterministe).
static func limb_mesh(variant: int, limb_bones: Array) -> ArrayMesh:
	var d := parts_for(variant)
	return RigBuilder.build_static(d[0], limb_bones, d[1])


## [boîtes, positions de repos surchargées] du zombie `variant`.
static func parts_for(variant: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = variant * 7919 + 17
	var skin: Color = SKINS[rng.randi() % SKINS.size()]
	skin = skin.lerp(Color(0.3, 0.35, 0.25), rng.randf() * 0.3)
	var shirt: Color = SHIRTS[rng.randi() % SHIRTS.size()]
	var pants: Color = PANTS[rng.randi() % PANTS.size()]
	var bald := rng.randf() < 0.5
	var missing_forearm := -1
	if rng.randf() < 0.15:
		missing_forearm = rng.randi() % 2
	var torn_sleeve := rng.randf() < 0.5
	var broad := rng.randf_range(0.92, 1.12)
	var tall := rng.randf_range(0.95, 1.06)

	var p: Array = []
	# Bassin / torse
	p.append(["hips", Vector3(0.34 * broad, 0.2, 0.2), Vector3(0, 0, 0), pants, 0.0])
	p.append(["spine", Vector3(0.31 * broad, 0.26, 0.19), Vector3(0, 0.12, 0), shirt, 0.0])
	p.append(["chest", Vector3(0.4 * broad, 0.28, 0.22), Vector3(0, 0.1, 0), shirt, 0.0])
	# Plaie ouverte sur le torse
	p.append(["chest", Vector3(0.14, 0.12, 0.02), Vector3(rng.randf_range(-0.1, 0.1), 0.08, 0.112), WOUND, 0.0])
	p.append(["spine", Vector3(0.1, 0.08, 0.02), Vector3(rng.randf_range(-0.1, 0.1), 0.1, 0.098), WOUND, 0.0])
	# Cou / tête
	p.append(["neck", Vector3(0.1, 0.12, 0.1), Vector3(0, 0.03, 0), skin, 0.0])
	p.append(["head", Vector3(0.22, 0.25, 0.23), Vector3(0, 0.14, 0.0), skin, 0.0])
	p.append(["head", Vector3(0.19, 0.06, 0.17), Vector3(0, 0.0, 0.04), skin.darkened(0.25), 0.0, Vector3(12, 0, 0)])
	p.append(["head", Vector3(0.16, 0.025, 0.02), Vector3(0, 0.035, 0.121), Color(0.12, 0.05, 0.04), 0.0])
	p.append(["head", Vector3(0.05, 0.028, 0.02), Vector3(0.052, 0.15, 0.116), EYE, 1.0])
	p.append(["head", Vector3(0.05, 0.028, 0.02), Vector3(-0.052, 0.15, 0.116), EYE, 1.0])
	p.append(["head", Vector3(0.24, 0.04, 0.05), Vector3(0, 0.185, 0.1), skin.darkened(0.35), 0.0])
	if not bald:
		p.append(["head", Vector3(0.235, 0.06, 0.24), Vector3(0, 0.27, -0.01), Color(0.08, 0.07, 0.06), 0.0])
	# Bras (manche + avant-bras + main)
	for side in ["l", "r"]:
		var sleeve := skin if torn_sleeve and side == "l" else shirt
		p.append(["arm_" + side, Vector3(0.1, 0.3, 0.1), Vector3(0, -0.14, 0), sleeve, 0.0])
		var missing: bool = (side == "l" and missing_forearm == 0) or (side == "r" and missing_forearm == 1)
		if missing:
			p.append(["forearm_" + side, Vector3(0.07, 0.06, 0.07), Vector3(0, -0.02, 0), WOUND, 0.0])
		else:
			p.append(["forearm_" + side, Vector3(0.085, 0.27, 0.085), Vector3(0, -0.13, 0), skin, 0.0])
			p.append(["forearm_" + side, Vector3(0.075, 0.11, 0.045), Vector3(0, -0.31, 0.01), skin.darkened(0.1), 0.0])
	# Jambes
	for side in ["l", "r"]:
		p.append(["thigh_" + side, Vector3(0.14, 0.46, 0.15), Vector3(0, -0.22, 0), pants, 0.0])
		p.append(["shin_" + side, Vector3(0.12, 0.44, 0.12), Vector3(0, -0.22, 0), pants.darkened(0.1), 0.0])
		p.append(["shin_" + side, Vector3(0.12, 0.07, 0.23), Vector3(0, -0.45, 0.04), BOOTS, 0.0])

	var overrides := {
		"hips": Vector3(0, 0.95 * tall, 0),
		"chest": Vector3(0, 0.25 * tall, 0),
	}
	return [p, overrides]
