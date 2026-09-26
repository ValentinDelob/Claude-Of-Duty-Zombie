class_name HellhoundModel
extends RefCounted
## Chien de l'enfer low-poly : même squelette procédural que les zombies
## (RigBuilder), os replacés en quadrupède. Le modèle regarde vers +Z.
##
##   hips = bassin (arrière) > spine > chest (avant) > neck > head
##   arm_* / forearm_* = pattes avant ; thigh_* / shin_* = pattes arrière

const HIDE := Color(0.17, 0.12, 0.1)
const HIDE_DARK := Color(0.08, 0.06, 0.05)
const MUSCLE := Color(0.36, 0.07, 0.05)
const BONE := Color(0.62, 0.56, 0.46)
const EMBER := Color(1.0, 0.35, 0.08)
const EYE := Color(1.0, 0.1, 0.04)

## Repos des os (relatif au parent) : dos horizontal à ~0,55 m.
const OVERRIDES := {
	"hips": Vector3(0, 0.52, -0.32),
	"spine": Vector3(0, 0.02, 0.3),
	"chest": Vector3(0, 0.02, 0.3),
	"neck": Vector3(0, 0.08, 0.14),
	"head": Vector3(0, 0.12, 0.1),
	"arm_l": Vector3(0.11, -0.04, 0.02),
	"forearm_l": Vector3(0, -0.24, 0),
	"arm_r": Vector3(-0.11, -0.04, 0.02),
	"forearm_r": Vector3(0, -0.24, 0),
	"thigh_l": Vector3(0.11, -0.02, -0.04),
	"shin_l": Vector3(0, -0.24, 0),
	"thigh_r": Vector3(-0.11, -0.02, -0.04),
	"shin_r": Vector3(0, -0.24, 0),
}

static var _material: ShaderMaterial


static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = preload("res://assets/shaders/character.gdshader")
		# Yeux rouges et braises incandescentes.
		_material.set_shader_parameter("emission_color", Color(1.0, 0.16, 0.05))
		_material.set_shader_parameter("emission_energy", 7.0)
		_material.set_shader_parameter("grime", 0.45)
		_material.set_shader_parameter("stain_amount", 0.9)
	return _material


static func build(variant: int) -> Skeleton3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = variant * 104729 + 3
	var hide := HIDE.lerp(HIDE_DARK, rng.randf() * 0.6)
	var p: Array = []
	# Corps : bassin, dos, poitrail plus large.
	p.append(["hips", Vector3(0.26, 0.26, 0.36), Vector3(0, 0.02, -0.02), hide, 0.0])
	p.append(["spine", Vector3(0.24, 0.24, 0.34), Vector3(0, 0.0, 0.0), hide, 0.0])
	p.append(["chest", Vector3(0.32, 0.34, 0.34), Vector3(0, -0.01, 0.02), hide, 0.0])
	# Côtes à vif et échine osseuse.
	for side in [-1.0, 1.0]:
		p.append(["spine", Vector3(0.02, 0.14, 0.26), Vector3(side * 0.121, -0.01, 0.0), MUSCLE, 0.0])
		for k in 3:
			p.append(["spine", Vector3(0.025, 0.16, 0.025), Vector3(side * 0.126, 0.0, -0.09 + k * 0.09), BONE, 0.0])
		# Fissures de braise sur le poitrail et les flancs.
		p.append(["chest", Vector3(0.02, 0.16, 0.04), Vector3(side * 0.161, 0.0, 0.08), EMBER, 0.85])
		p.append(["hips", Vector3(0.02, 0.1, 0.05), Vector3(side * 0.131, 0.03, 0.05), EMBER, 0.7])
	for k in 5:
		p.append(["spine" if k < 3 else "chest", Vector3(0.05, 0.05, 0.07), Vector3(0, 0.135, -0.1 + (k % 3) * 0.1), BONE, 0.0, Vector3(20, 0, 0)])
	# Cou épais, tête de molosse.
	p.append(["neck", Vector3(0.17, 0.2, 0.22), Vector3(0, 0.03, 0.02), hide, 0.0, Vector3(-35, 0, 0)])
	p.append(["head", Vector3(0.21, 0.17, 0.22), Vector3(0, 0.02, 0.0), hide, 0.0])
	p.append(["head", Vector3(0.13, 0.1, 0.2), Vector3(0, -0.03, 0.19), hide, 0.0])
	p.append(["head", Vector3(0.11, 0.04, 0.17), Vector3(0, -0.1, 0.15), MUSCLE, 0.0, Vector3(14, 0, 0)])
	p.append(["head", Vector3(0.12, 0.03, 0.02), Vector3(0, -0.075, 0.285), BONE, 0.0])
	p.append(["head", Vector3(0.1, 0.02, 0.02), Vector3(0, -0.105, 0.225), BONE, 0.0])
	p.append(["head", Vector3(0.05, 0.03, 0.03), Vector3(0, 0.025, 0.29), HIDE_DARK, 0.0])
	for side in [-1.0, 1.0]:
		p.append(["head", Vector3(0.045, 0.03, 0.02), Vector3(side * 0.06, 0.05, 0.111), EYE, 1.0])
		p.append(["head", Vector3(0.05, 0.11, 0.035), Vector3(side * 0.075, 0.13, -0.06), hide, 0.0, Vector3(-25, 0, side * 12)])
	# Queue.
	p.append(["hips", Vector3(0.05, 0.05, 0.28), Vector3(0, 0.09, -0.3), hide, 0.0, Vector3(30, 0, 0)])
	# Pattes : épaule / cuisse musclée, jambe fine, patte griffue.
	for side in ["l", "r"]:
		p.append(["arm_" + side, Vector3(0.1, 0.26, 0.13), Vector3(0, -0.1, 0), hide, 0.0])
		p.append(["forearm_" + side, Vector3(0.065, 0.24, 0.075), Vector3(0, -0.12, 0), hide, 0.0])
		p.append(["forearm_" + side, Vector3(0.085, 0.05, 0.13), Vector3(0, -0.245, 0.03), HIDE_DARK, 0.0])
		p.append(["thigh_" + side, Vector3(0.12, 0.28, 0.17), Vector3(0, -0.1, 0.02), hide, 0.0])
		p.append(["thigh_" + side, Vector3(0.02, 0.1, 0.08), Vector3((0.061 if side == "l" else -0.061), -0.08, 0.02), MUSCLE, 0.0])
		p.append(["shin_" + side, Vector3(0.065, 0.24, 0.075), Vector3(0, -0.12, -0.02), hide, 0.0])
		p.append(["shin_" + side, Vector3(0.085, 0.05, 0.13), Vector3(0, -0.245, 0.02), HIDE_DARK, 0.0])
	return RigBuilder.build(p, material(), OVERRIDES)
