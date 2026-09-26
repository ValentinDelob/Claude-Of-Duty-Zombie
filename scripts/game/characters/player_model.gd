class_name PlayerModel
extends Node3D
## Soldat low-poly des joueurs vus par les autres (1 draw call + l'arme).
## Animations procédurales pilotées par l'état réseau : marche, course,
## accroupi, visée (le buste suit le regard), tir, joueur à terre.

const SKIN := Color(0.52, 0.4, 0.32)
const UNIFORM := Color(0.2, 0.22, 0.15)
const PANTS := Color(0.16, 0.17, 0.12)
const VEST := Color(0.12, 0.13, 0.1)
const HELMET := Color(0.17, 0.19, 0.13)
const BOOTS := Color(0.06, 0.05, 0.04)

static var _material: ShaderMaterial

var skel: Skeleton3D
var bones: Dictionary
var weapon_attach: BoneAttachment3D
var weapon_model: Node3D
var weapon_key := ""
var _phase := 0.0
var _recoil := 0.0
var _down_k := 0.0
var _prone_k := 0.0


static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = preload("res://assets/shaders/character.gdshader")
		_material.set_shader_parameter("grime", 0.25)
		_material.set_shader_parameter("stain_amount", 0.12)
		_material.set_shader_parameter("emission_energy", 0.0)
	return _material


func build(slot_color: Color) -> void:
	var p: Array = []
	p.append(["hips", Vector3(0.34, 0.2, 0.21), Vector3.ZERO, PANTS, 0.0])
	p.append(["spine", Vector3(0.33, 0.27, 0.21), Vector3(0, 0.12, 0), UNIFORM, 0.0])
	p.append(["chest", Vector3(0.42, 0.3, 0.25), Vector3(0, 0.1, 0), VEST, 0.0])
	p.append(["chest", Vector3(0.36, 0.14, 0.05), Vector3(0, 0.05, 0.13), VEST.lightened(0.1), 0.0])
	p.append(["neck", Vector3(0.1, 0.1, 0.1), Vector3(0, 0.03, 0), SKIN, 0.0])
	p.append(["head", Vector3(0.21, 0.24, 0.22), Vector3(0, 0.13, 0), SKIN, 0.0])
	p.append(["head", Vector3(0.27, 0.13, 0.28), Vector3(0, 0.25, -0.01), HELMET, 0.0])
	p.append(["head", Vector3(0.29, 0.03, 0.31), Vector3(0, 0.19, 0.0), HELMET.darkened(0.2), 0.0])
	p.append(["head", Vector3(0.16, 0.03, 0.02), Vector3(0, 0.15, 0.112), Color(0.05, 0.05, 0.05), 0.0])
	for side in ["l", "r"]:
		p.append(["arm_" + side, Vector3(0.11, 0.3, 0.11), Vector3(0, -0.14, 0), UNIFORM, 0.0])
		# Brassard à la couleur du joueur (repérage des coéquipiers).
		p.append(["arm_" + side, Vector3(0.12, 0.06, 0.12), Vector3(0, -0.06, 0), slot_color, 0.0])
		p.append(["forearm_" + side, Vector3(0.09, 0.27, 0.09), Vector3(0, -0.13, 0), UNIFORM, 0.0])
		p.append(["forearm_" + side, Vector3(0.08, 0.1, 0.06), Vector3(0, -0.3, 0.01), Color(0.1, 0.08, 0.06), 0.0])
		p.append(["thigh_" + side, Vector3(0.15, 0.46, 0.16), Vector3(0, -0.22, 0), PANTS, 0.0])
		p.append(["shin_" + side, Vector3(0.13, 0.44, 0.13), Vector3(0, -0.22, 0), PANTS, 0.0])
		p.append(["shin_" + side, Vector3(0.13, 0.08, 0.25), Vector3(0, -0.45, 0.04), BOOTS, 0.0])
	skel = RigBuilder.build(p, material())
	# Le modèle regarde vers +Z ; le joueur vers -Z.
	skel.rotation.y = PI
	add_child(skel)
	bones = RigBuilder.bone_indices(skel)
	weapon_attach = BoneAttachment3D.new()
	weapon_attach.bone_name = "forearm_r"
	skel.add_child(weapon_attach)


## Affiche l'arme tenue (id + amélioration). Ne reconstruit que si elle change.
func set_weapon(id: String, pap: bool) -> void:
	var key := "%s_%s" % [id, pap]
	if key == weapon_key:
		return
	weapon_key = key
	if weapon_model:
		weapon_model.queue_free()
		weapon_model = null
	if id == "" or not WeaponDB.exists(id):
		return
	weapon_model = WeaponModels.build(WeaponDB.stats(id).model, false, pap)
	# Dans la main : le canon suit l'avant-bras tendu vers l'avant.
	weapon_model.position = Vector3(0, -0.3, 0.05)
	weapon_model.rotation = Vector3(PI * 0.5, PI, 0)
	weapon_attach.add_child(weapon_model)


func fire_kick() -> void:
	_recoil = 1.0


func _q(x: float, y := 0.0, z := 0.0) -> Quaternion:
	return Quaternion.from_euler(Vector3(x, y, z))


## Anime le squelette. `speed` m/s, `pitch` regard (rad), `flags` = Player.FLAG_*.
func animate(delta: float, speed: float, pitch: float, flags: int, downed: bool, dead: bool) -> void:
	if skel == null:
		return
	var crouch := flags & Player.FLAG_CROUCH != 0
	var sprint := flags & Player.FLAG_SPRINT != 0
	_down_k = move_toward(_down_k, 1.0 if (downed or dead) else 0.0, delta * 3.0)
	var move_k := clampf(speed / 4.0, 0.0, 1.6)
	_phase += delta * (2.0 + speed * 1.7)
	var s := sin(_phase)
	var c := cos(_phase)
	var leg := (0.45 if not sprint else 0.8) * move_k
	var hips_drop := 0.35 if crouch else 0.0
	_recoil = maxf(_recoil - delta * 8.0, 0.0)

	# Allongé / plongeon : le corps bascule à plat ventre, tête vers l'avant.
	var flat := flags & (Player.FLAG_PRONE | Player.FLAG_DIVE) != 0 and not (downed or dead)
	var dive := flags & Player.FLAG_DIVE != 0
	_prone_k = move_toward(_prone_k, 1.0 if flat else 0.0, delta * (7.0 if dive else 3.5))
	var pk := _prone_k
	if pk > 0.0:
		crouch = false
		leg *= 0.3
		hips_drop = 0.0

	skel.set_bone_pose_position(bones.hips, Vector3(0, 0.95 - hips_drop - _down_k * 0.55 + absf(c) * 0.03 * move_k * (1.0 - pk), 0))
	var knee := 0.6 if crouch else 0.0
	var kick := 0.5 if dive else 0.0  # jambes repliées en plein vol
	skel.set_bone_pose_rotation(bones.thigh_l, _q(s * leg - knee - _down_k * 1.3 - kick * 0.3))
	skel.set_bone_pose_rotation(bones.thigh_r, _q(-s * leg - knee - _down_k * 1.1 - kick * 0.2, 0.0, 0.2 * _down_k))
	skel.set_bone_pose_rotation(bones.shin_l, _q(-maxf(0.0, -c) * leg * 1.2 + knee * 1.8 + _down_k * 1.4 + kick))
	skel.set_bone_pose_rotation(bones.shin_r, _q(-maxf(0.0, c) * leg * 1.2 + knee * 1.8 + _down_k * 0.4 + kick * 0.6))
	var lean := lerpf(0.05 + (0.3 if sprint else 0.0) - _down_k * 0.35, 0.0, pk)
	skel.set_bone_pose_rotation(bones.spine, _q(lean - pitch * 0.3 * (1.0 - pk)))
	skel.set_bone_pose_rotation(bones.chest, _q(-pitch * 0.35 * (1.0 - pk)))
	# Allongé, la tête se redresse pour regarder devant.
	skel.set_bone_pose_rotation(bones.head, _q(lerpf(-pitch * 0.35, -1.15 - pitch * 0.3, pk)))
	# Bras : arme épaulée (tendue vers l'avant), balancée en sprint ; allongé,
	# bras tendus dans l'axe du corps.
	var aim_arm := -1.45 - pitch * 0.3 + _recoil * 0.25
	if sprint:
		aim_arm = -0.7 + s * 0.3
	aim_arm = lerpf(aim_arm, -2.75 - pitch * 0.2 + _recoil * 0.2, pk)
	skel.set_bone_pose_rotation(bones.arm_r, _q(aim_arm, 0.0, 0.1))
	skel.set_bone_pose_rotation(bones.forearm_r, _q(-0.1))
	skel.set_bone_pose_rotation(bones.arm_l, _q(aim_arm + 0.1, 0.0, lerpf(-0.55, -0.35, pk)))
	skel.set_bone_pose_rotation(bones.forearm_l, _q(-0.8, 0.0, 0.3))
	var body_x := 0.0
	if dead:
		body_x = -PI * 0.47
	elif pk > 0.0:
		body_x = PI * 0.5 * pk
	skel.rotation.x = lerpf(skel.rotation.x, body_x, 1.0 - exp(-delta * (30.0 if pk > 0.0 else 6.0)))
	# Pivot aux pieds : on recentre le corps allongé sur la position du joueur.
	skel.position = Vector3(0.0, 0.16 * pk, 0.85 * pk)
