class_name RigBuilder
extends RefCounted
## Construit un personnage low-poly « skinné » : un Skeleton3D procédural et UN
## SEUL mesh (1 draw call) dont chaque boîte est liée rigidement à un os.
## Les animations sont procédurales (rotations d'os écrites par le code).
##
## Os (repère au repos : aucune rotation, les membres pendent vers -Y) :
##   hips > spine > chest > neck > head
##   chest > arm_l > forearm_l ; chest > arm_r > forearm_r
##   hips > thigh_l > shin_l ; hips > thigh_r > shin_r

const BONES := [
	# [nom, parent, position au repos relative au parent]
	["hips", "", Vector3(0, 0.95, 0)],
	["spine", "hips", Vector3(0, 0.12, 0)],
	["chest", "spine", Vector3(0, 0.25, 0)],
	["neck", "chest", Vector3(0, 0.25, 0)],
	["head", "neck", Vector3(0, 0.08, 0)],
	["arm_l", "chest", Vector3(0.23, 0.2, 0)],
	["forearm_l", "arm_l", Vector3(0, -0.3, 0)],
	["arm_r", "chest", Vector3(-0.23, 0.2, 0)],
	["forearm_r", "arm_r", Vector3(0, -0.3, 0)],
	["thigh_l", "hips", Vector3(0.1, -0.02, 0)],
	["shin_l", "thigh_l", Vector3(0, -0.45, 0)],
	["thigh_r", "hips", Vector3(-0.1, -0.02, 0)],
	["shin_r", "thigh_r", Vector3(0, -0.45, 0)],
]


## `parts` : Array de [os, taille, centre (repère de l'os), couleur, émissif(0..1)]
## Retourne le Skeleton3D (avec le MeshInstance3D en enfant « Mesh »).
static func build(parts: Array, material: Material, bone_overrides := {}) -> Skeleton3D:
	var skel := Skeleton3D.new()
	skel.name = "Skeleton"
	var index := {}
	var global_rest := {}
	for b in BONES:
		var idx := skel.add_bone(b[0])
		index[b[0]] = idx
		var rest_pos: Vector3 = bone_overrides.get(b[0], b[2])
		if b[1] != "":
			skel.set_bone_parent(idx, index[b[1]])
		skel.set_bone_rest(idx, Transform3D(Basis.IDENTITY, rest_pos))
		skel.set_bone_pose_position(idx, rest_pos)
		var parent_global: Transform3D = global_rest.get(b[1], Transform3D.IDENTITY)
		global_rest[b[0]] = parent_global * Transform3D(Basis.IDENTITY, rest_pos)

	var st := SurfaceTool.new()
	st.set_skin_weight_count(SurfaceTool.SKIN_4_WEIGHTS)
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p in parts:
		var bone: String = p[0]
		var xf: Transform3D = global_rest[bone]
		var rot: Vector3 = p[5] if p.size() > 5 else Vector3.ZERO
		_box(st, xf, p[1], p[2], rot, p[3], p[4], index[bone])
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = mesh
	mi.material_override = material
	skel.add_child(mi)
	mi.skeleton = NodePath("..")
	mi.skin = skel.create_skin_from_rest_transforms()
	return skel


static func _box(st: SurfaceTool, bone_xf: Transform3D, size: Vector3, center: Vector3, rot_deg: Vector3, color: Color, emissive: float, bone: int) -> void:
	var h := size * 0.5
	var local := Transform3D(Basis.from_euler(rot_deg * (PI / 180.0)), center)
	var xf := bone_xf * local
	var faces := [
		[Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)],
		[Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)],
		[Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1)],
		[Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
		[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)],
		[Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0)],
	]
	var bones := PackedInt32Array([bone, 0, 0, 0])
	var weights := PackedFloat32Array([1.0, 0.0, 0.0, 0.0])
	# Couleur : RGB = albédo, A = masque d'émission (1 = pas d'émission).
	var col := Color(color.r, color.g, color.b, 1.0 - emissive)
	for f in faces:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var c := n * h
		var du := u * h
		var dv := v * h
		var quad := [c - du - dv, c + du - dv, c + du + dv, c - du + dv]
		var world_n := (xf.basis * n).normalized()
		for i in [0, 2, 1, 0, 3, 2]:
			st.set_bones(bones)
			st.set_weights(weights)
			st.set_color(col)
			st.set_normal(world_n)
			st.set_uv(Vector2(quad[i].x + quad[i].z, quad[i].y) * 2.0)
			st.add_vertex(xf * quad[i])


## Indices des os d'un squelette construit par build().
static func bone_indices(skel: Skeleton3D) -> Dictionary:
	var d := {}
	for b in BONES:
		d[b[0]] = skel.find_bone(b[0])
	return d
