class_name ZombieGlb
extends RefCounted
## Zombies modélisés dans Blender (tools/blender/zombies/) : charge un .glb
## skinné (ossature du jeu, mêmes noms d'os que RigBuilder.BONES) et le
## convertit au format des zombies procéduraux, pour garder le même shader
## (zombie.gdshader) et le même code d'animation :
##   - un seul mesh, un seul draw call ;
##   - couleur par sommet (sRGB -> linéaire), alpha 0 = émissif (yeux) :
##     celle du .glb s'il en a (COLOR_0, déjà linéaire : modèles cubiques de
##     tools/blender/voxel/voxel_lib.py, une couleur par face de cube), sinon
##     celle de la matière (MATS) ;
##   - position de repos en UV.xy / UV2.x, identifiant de matière en UV2.y ;
##   - os remappés sur les indices de RigBuilder.BONES.
## Le repos des os (positions seules, sans rotation) vient du squelette du
## .glb et est passé en `bone_overrides` à RigBuilder.
##
## Matières Blender -> matière du shader et couleur (clé = nom du matériau,
## suffixe « .001 » ignoré).

const MATS := {
	"skin": [RigBuilder.MAT_SKIN, Color(0.52, 0.53, 0.46)],
	"eye": [RigBuilder.MAT_SKIN, Color(1.0, 0.86, 0.3), true],
	"cloth": [RigBuilder.MAT_CLOTH, Color(0.42, 0.43, 0.35)],
	"leather": [RigBuilder.MAT_LEATHER, Color(0.075, 0.065, 0.055)],
	"metal": [RigBuilder.MAT_METAL, Color(0.27, 0.29, 0.25)],
	"wound": [RigBuilder.MAT_WOUND, Color(0.55, 0.14, 0.12)],
	"bone": [RigBuilder.MAT_BONE, Color(0.72, 0.66, 0.52)],
}

static var _cache := {}


## {"mesh": ArrayMesh, "overrides": {os: position relative au parent}}, ou
## {} si le fichier n'existe pas.
static func load_model(path: String) -> Dictionary:
	if _cache.has(path):
		return _cache[path]
	var out := {}
	if ResourceLoader.exists(path):
		var scene := load(path) as PackedScene
		if scene:
			var root := scene.instantiate()
			out = _convert(root)
			root.free()
	_cache[path] = out
	return out


static func _find(n: Node, cls: String) -> Node:
	if n.is_class(cls):
		return n
	for c in n.get_children():
		var f := _find(c, cls)
		if f:
			return f
	return null


## Transformation de `n` dans le repère de `root` (scène hors de l'arbre :
## pas de global_transform).
static func _rel(n: Node, root: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	while n != null and n != root:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


static func _convert(root: Node) -> Dictionary:
	var skel := _find(root, "Skeleton3D") as Skeleton3D
	var mi := _find(root, "MeshInstance3D") as MeshInstance3D
	if skel == null or mi == null:
		push_warning("ZombieGlb : squelette ou mesh introuvable")
		return {}
	# Repos (positions) des os du .glb, relatifs au parent, repère du modèle.
	var overrides := {}
	var remap_ids := PackedInt32Array()
	remap_ids.resize(skel.get_bone_count())
	var names := []
	for b in RigBuilder.BONES:
		names.append(b[0])
	for i in skel.get_bone_count():
		var bn := skel.get_bone_name(i)
		remap_ids[i] = names.find(bn)
		if remap_ids[i] < 0:
			push_warning("ZombieGlb : os inconnu %s" % bn)
			remap_ids[i] = 0
	var glob := {}
	for i in skel.get_bone_count():
		glob[skel.get_bone_name(i)] = (_rel(skel, root) * skel.get_bone_global_rest(i)).origin
	for b in RigBuilder.BONES:
		if not glob.has(b[0]):
			continue
		var parent_pos: Vector3 = glob.get(b[1], Vector3.ZERO) if b[1] != "" else Vector3.ZERO
		overrides[b[0]] = glob[b[0]] - parent_pos
	# Skin du .glb : lien indice de liaison -> os du squelette.
	var skin := mi.skin
	var to_mesh := _rel(mi, root)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var idx := PackedInt32Array()
	var mesh := mi.mesh
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		var mat := mesh.surface_get_material(s)
		var key := (mat.resource_name if mat else "skin").get_slice(".", 0)
		var info: Array = MATS.get(key, MATS.skin)
		var c: Color = (info[1] as Color).srgb_to_linear()
		if info.size() > 2 and info[2]:
			c.a = 0.0
		var base := verts.size()
		var sv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var sn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var sb: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var sw: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var sc: PackedColorArray = arr[Mesh.ARRAY_COLOR] if arr[Mesh.ARRAY_COLOR] != null else PackedColorArray()
		var own_cols := sc.size() == sv.size()
		@warning_ignore("integer_division")
		var per := sb.size() / maxi(1, sv.size())
		for v in sv.size():
			var p := to_mesh * sv[v]
			verts.append(p)
			norms.append((to_mesh.basis * sn[v]).normalized())
			if own_cols:
				var vc := sc[v]
				vc.a = c.a
				cols.append(vc)
			else:
				cols.append(c)
			uv.append(Vector2(p.x, p.y))
			uv2.append(Vector2(p.z, float(info[0])))
			# 4 influences, remappées sur l'ossature du jeu.
			for k in 4:
				if k < per:
					var bind := sb[v * per + k]
					var bi := skin.get_bind_bone(bind) if skin else bind
					if bi < 0:
						bi = skel.find_bone(skin.get_bind_name(bind))
					bones.append(remap_ids[bi])
					weights.append(sw[v * per + k])
				else:
					bones.append(0)
					weights.append(0.0)
		var si: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		for i in si:
			idx.append(base + i)
	var out_arr := []
	out_arr.resize(Mesh.ARRAY_MAX)
	out_arr[Mesh.ARRAY_VERTEX] = verts
	out_arr[Mesh.ARRAY_NORMAL] = norms
	out_arr[Mesh.ARRAY_COLOR] = cols
	out_arr[Mesh.ARRAY_TEX_UV] = uv
	out_arr[Mesh.ARRAY_TEX_UV2] = uv2
	out_arr[Mesh.ARRAY_BONES] = bones
	out_arr[Mesh.ARRAY_WEIGHTS] = weights
	out_arr[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out_arr)
	return {"mesh": am, "overrides": overrides}
