extends RefCounted
## Interpénétration des pièces du zombie cubique dans une pose : chaque cube
## du modèle (tools/blender/zombies/zombie_voxel_cells.json, os de chaque
## cellule) est placé par la pose de son os ; deux cubes d'os DIFFÉRENTS qui
## tombent dans la même case de 2,5 cm se traversent. Ne comptent pas les
## cubes voisins d'une articulation (LINKS) : une pièce rigide qui pivote y
## mord forcément sur sa voisine (pli du ventre, du coude, du genou).
## Outil de mise au point des animations (ZombieAnim, ZombieGibs.crawl_pose) et
## garde-fou des tests (tests/test_zombie_voxel_anim.gd, zombie_voxel_anims).

const CELLS := "res://tools/blender/zombies/zombie_voxel_cells.json"
## Bas de la jupe lié aux cuisses (zombie_voxel.py, SKIRT_SPLIT_Z) : le cache
## garde le bassin, la liaison est refaite ici.
const SKIRT_SPLIT_Z := 26
## Articulations : [os, os, règle, distance (m)]. « plan » : cubes à moins de
## la distance (verticale) du plan horizontal de la jointure (tronc, coudes,
## genoux, hanches) ; « boule » : à moins de la distance de la jointure
## (épaules, mâchoire). Jointure : origine du second os.
const LINKS := [["hips", "spine", "plan", 0.075], ["spine", "chest", "plan", 0.075], ["chest", "head", "plan", 0.075],
		["head", "jaw", "boule", 0.26], ["chest", "arm_l", "boule", 0.16], ["chest", "arm_r", "boule", 0.16],
		["arm_l", "forearm_l", "plan", 0.075], ["arm_r", "forearm_r", "plan", 0.075],
		["hips", "thigh_l", "plan", 0.125], ["hips", "thigh_r", "plan", 0.125],
		["thigh_l", "shin_l", "plan", 0.075], ["thigh_r", "shin_r", "plan", 0.075],
		["spine", "thigh_l", "plan", 0.075], ["spine", "thigh_r", "plan", 0.075]]

var cube := 0.025
## Centres de repos (repère du modèle), indice d'os (RigBuilder.BONES) par cube.
var centers := PackedVector3Array()
var bone_of := PackedInt32Array()
## Par cube : masque des os voisins dont il est assez près de la jointure.
var near := PackedInt32Array()
var _rest := {}


func _init(overrides: Dictionary) -> void:
	var f := FileAccess.open(CELLS, FileAccess.READ)
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	cube = data.cube
	var names: Array = []
	for b in RigBuilder.BONES:
		names.append(b[0])
	_rest = RigBuilder._rest_globals(overrides)
	for line: String in data.cells:
		var head := line.get_slice(" ", 0).split(",")
		var x := int(head[0])
		var y := int(head[1])
		var z := int(head[2])
		var bone: String = data.bones[int(head[4])]
		if data.parts[int(head[5])] == "skirt" and z < SKIRT_SPLIT_Z:
			bone = "thigh_l" if x >= 0 else "thigh_r"
		# Blender (Z en haut, avant -Y) -> Godot (Y en haut, avant +Z).
		centers.append(Vector3(x + 0.5, z + 0.5, -(y + 0.5)) * cube)
		bone_of.append(names.find(bone))
	near.resize(centers.size())
	for i in centers.size():
		var mask := 0
		var b: String = names[bone_of[i]]
		for l in LINKS:
			if l[0] != b and l[1] != b:
				continue
			var other: String = l[1] if l[0] == b else l[0]
			var joint: Vector3 = (_rest[l[1]] as Transform3D).origin
			var d: float = absf(centers[i].y - joint.y) if l[2] == "plan" else centers[i].distance_to(joint)
			if d < l[3]:
				mask |= 1 << names.find(other)
		near[i] = mask


## Cubes qui se traversent dans la pose actuelle du squelette `skel` (os de
## `bones` : RigBuilder.bone_indices). Retourne {"count": n, "pairs": {"a/b": n},
## "floor": bas du cube le plus bas (m, repère du zombie : 0 = sol)}.
func check(skel: Skeleton3D, bones: Dictionary) -> Dictionary:
	var mats: Array[Transform3D] = []
	for b in RigBuilder.BONES:
		mats.append(skel.get_bone_global_pose(bones[b[0]]) * (_rest[b[0]] as Transform3D).affine_inverse())
	var occ := {}
	var pairs := {}
	var count := 0
	var inv := 1.0 / cube
	var to_parent := skel.transform
	var low := INF
	for i in centers.size():
		var bi := bone_of[i]
		var w := mats[bi] * centers[i]
		low = minf(low, (to_parent * w).y - cube * 0.5)
		var q := w * inv
		var key := Vector3i(floori(q.x), floori(q.y), floori(q.z))
		var prev: Variant = occ.get(key)
		if prev == null:
			occ[key] = i
			continue
		var j: int = prev
		var bj := bone_of[j]
		if bj == bi:
			continue
		if (near[i] & (1 << bj)) and (near[j] & (1 << bi)):
			continue
		count += 1
		var k := "%s/%s" % [RigBuilder.BONES[mini(bi, bj)][0], RigBuilder.BONES[maxi(bi, bj)][0]]
		pairs[k] = int(pairs.get(k, 0)) + 1
	return {"count": count, "pairs": pairs, "floor": low}
