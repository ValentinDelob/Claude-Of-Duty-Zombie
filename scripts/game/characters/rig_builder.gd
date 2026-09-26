class_name RigBuilder
extends RefCounted
## Construit un personnage low-poly « skinné » : un Skeleton3D procédural et UN
## SEUL mesh (1 draw call) dont chaque pièce est liée à un ou plusieurs os.
## Les animations sont procédurales (rotations d'os écrites par le code).
##
## Os (repère au repos : aucune rotation, les membres pendent vers -Y) :
##   hips > spine > chest > neck > head > jaw
##   chest > arm_l > forearm_l ; chest > arm_r > forearm_r
##   hips > thigh_l > shin_l ; hips > thigh_r > shin_r
##
## Pièces (`parts`) :
## * Array (historique, joueurs et chiens) : boîte rigide
##   [os, taille, centre (repère de l'os), couleur, émissif(0..1), rotation°].
## * Dictionary (zombies) : formes arrondies à normales lissées, voir
##   _add_part : "box", "ell" (ellipsoïde) et "loft" (tube de sections
##   elliptiques : membres, torse, vêtements) dont chaque section peut être
##   partagée entre plusieurs os (articulations sans fissure).
##
## Chaque sommet porte, en plus de sa couleur (sRGB -> linéaire, alpha =
## masque d'émission), sa position de repos (UV.xy, UV2.x : bruit du shader
## qui ne « glisse » pas pendant l'animation) et un identifiant de matière
## (UV2.y : tissu, peau, cuir, métal, plaie, os ; voir zombie.gdshader).

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
	# Mâchoire (pivot sous les oreilles) : seuls les zombies y lient des pièces.
	["jaw", "head", Vector3(0, 0.07, 0.01)],
]

## Matières (UV2.y), lues par zombie.gdshader.
const MAT_CLOTH := 0
const MAT_SKIN := 1
const MAT_LEATHER := 2
const MAT_METAL := 3
const MAT_WOUND := 4
const MAT_BONE := 5


## Accumulateur de sommets indexés : tableaux compacts remplis directement
## (bien plus rapide que SurfaceTool), un seul ArrayMesh à la fin.
class _Acc:
	var n := 0
	var skinned := true
	var index := {}
	var rest := {}
	## Repère appliqué aux positions de repos (morceau arraché : repère de l'os).
	var to_local := Transform3D.IDENTITY
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	var cols := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var idx := PackedInt32Array()
	## Taches de sang : [centre (repère du modèle), rayon, intensité].
	var blood: Array = []
	## Poids déjà convertis (le même dictionnaire sert à tout un anneau).
	var _w_src: Dictionary = {}
	var _w_b := PackedInt32Array([0, 0, 0, 0])
	var _w_w := PackedFloat32Array([1.0, 0.0, 0.0, 0.0])

	func vert(p: Vector3, nrm_in: Vector3, col: Color, mat: int, w: Dictionary) -> int:
		if skinned:
			if not is_same(w, _w_src):
				_w_src = w
				_w_b = PackedInt32Array([0, 0, 0, 0])
				_w_w = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
				var k := 0
				var total := 0.0
				for b in w:
					if k >= 4:
						break
					_w_b[k] = index[b]
					_w_w[k] = w[b]
					total += w[b]
					k += 1
				for i in k:
					_w_w[i] /= maxf(total, 0.0001)
			bones.append_array(_w_b)
			weights.append_array(_w_w)
		cols.append(col)
		nrm.append((to_local.basis * nrm_in).normalized())
		uv.append(Vector2(p.x, p.y))
		# Sang peint : fraction de UV2.y (0..0,45) = quantité de sang du sommet.
		var b := 0.0
		for s in blood:
			var d: float = p.distance_to(s[0])
			if d < s[1]:
				b = maxf(b, s[2] * (1.0 - d / s[1]))
		uv2.append(Vector2(p.z, float(mat) + minf(b, 1.0) * 0.45))
		pos.append(to_local * p)
		n += 1
		return n - 1

	## Triangle orienté automatiquement : face avant du côté des normales
	## (Godot : sommets dans le sens horaire vus de face).
	func tri(a: int, b: int, c: int) -> void:
		var fn := (pos[b] - pos[a]).cross(pos[c] - pos[a])
		idx.append(a)
		if fn.dot(nrm[a] + nrm[b] + nrm[c]) > 0.0:
			idx.append(c)
			idx.append(b)
		else:
			idx.append(b)
			idx.append(c)

	func commit() -> ArrayMesh:
		return RigBuilder.mesh_from_arrays(arrays())

	## Tableaux de surface (Mesh.ARRAY_*), vides si aucun sommet.
	func arrays() -> Array:
		if n == 0:
			return []
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = pos
		arr[Mesh.ARRAY_NORMAL] = nrm
		arr[Mesh.ARRAY_COLOR] = cols
		arr[Mesh.ARRAY_TEX_UV] = uv
		arr[Mesh.ARRAY_TEX_UV2] = uv2
		if skinned:
			arr[Mesh.ARRAY_BONES] = bones
			arr[Mesh.ARRAY_WEIGHTS] = weights
		arr[Mesh.ARRAY_INDEX] = idx
		return arr


static func mesh_from_arrays(arr: Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if not arr.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh


static func _rest_globals(bone_overrides: Dictionary) -> Dictionary:
	var global_rest := {}
	for b in BONES:
		var rest_pos: Vector3 = bone_overrides.get(b[0], b[2])
		var parent_global: Transform3D = global_rest.get(b[1], Transform3D.IDENTITY)
		global_rest[b[0]] = parent_global * Transform3D(Basis.IDENTITY, rest_pos)
	return global_rest


## Squelette seul (os et repos), sans mesh.
static func build_skeleton(bone_overrides := {}) -> Skeleton3D:
	var skel := Skeleton3D.new()
	skel.name = "Skeleton"
	var index := {}
	for b in BONES:
		var idx := skel.add_bone(b[0])
		index[b[0]] = idx
		var rest_pos: Vector3 = bone_overrides.get(b[0], b[2])
		if b[1] != "":
			skel.set_bone_parent(idx, index[b[1]])
		skel.set_bone_rest(idx, Transform3D(Basis.IDENTITY, rest_pos))
		skel.set_bone_pose_position(idx, rest_pos)
	return skel


## Mesh skinné (repère du modèle) des pièces `parts` ; `blood` : taches de
## sang peintes [centre (repère du modèle), rayon, intensité].
static func build_mesh(parts: Array, bone_overrides := {}, blood := []) -> ArrayMesh:
	return mesh_from_arrays(build_arrays(parts, bone_overrides, blood))


## Tableaux de surface du mesh skinné (sans ressource : utilisable depuis un
## thread de travail, le mesh est créé ensuite sur le thread principal).
static func build_arrays(parts: Array, bone_overrides := {}, blood := []) -> Array:
	var acc := _Acc.new()
	acc.rest = _rest_globals(bone_overrides)
	acc.blood = blood
	for i in BONES.size():
		acc.index[BONES[i][0]] = i
	for p in parts:
		_add_part(acc, p)
	return acc.arrays()


## Squelette + MeshInstance3D « Mesh » (mesh et Skin partageables : un modèle
## mis en cache ne coûte qu'un squelette et une instance).
static func instantiate(mesh: ArrayMesh, material: Material, bone_overrides := {}, skin: Skin = null) -> Skeleton3D:
	var skel := build_skeleton(bone_overrides)
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = mesh
	mi.material_override = material
	skel.add_child(mi)
	mi.skeleton = NodePath("..")
	mi.skin = skin if skin else skel.create_skin_from_rest_transforms()
	return skel


## Retourne le Skeleton3D (avec le MeshInstance3D en enfant « Mesh »).
static func build(parts: Array, material: Material, bone_overrides := {}) -> Skeleton3D:
	return instantiate(build_mesh(parts, bone_overrides), material, bone_overrides)


## Mesh NON skinné des pièces liées aux os `only` (morceau de corps arraché),
## exprimé dans le repère de repos du premier os de `only`.
static func build_static(parts: Array, only: Array, bone_overrides := {}, blood := []) -> ArrayMesh:
	var acc := _Acc.new()
	acc.skinned = false
	acc.rest = _rest_globals(bone_overrides)
	acc.blood = blood
	var root: Transform3D = acc.rest.get(only[0], Transform3D.IDENTITY)
	acc.to_local = root.affine_inverse()
	for p in parts:
		var bone: String = p[0] if p is Array else p.bone
		if bone in only:
			_add_part(acc, p)
	return acc.commit()


static func _add_part(acc: _Acc, p: Variant) -> void:
	if p is Array:
		var rot: Vector3 = p[5] if p.size() > 5 else Vector3.ZERO
		_box(acc, p[0], p[1], p[2], rot, p[3], p[4], MAT_CLOTH)
		return
	var d: Dictionary = p
	var col: Color = d.get("color", Color.WHITE)
	var emit: float = d.get("emit", 0.0)
	var mat: int = d.get("mat", MAT_CLOTH)
	match d.get("shape", "box"):
		"box":
			_box(acc, d.bone, d.size, d.get("center", Vector3.ZERO), d.get("rot", Vector3.ZERO), col, emit, mat)
		"ell":
			_ellipsoid(acc, d, col, emit, mat)
		"loft":
			_loft(acc, d, col, emit, mat)


static func _vcol(color: Color, emissive: float) -> Color:
	# RGB = albédo (converti en linéaire : les couleurs sont pensées en sRGB),
	# A = masque d'émission (1 = pas d'émission).
	var lin := color.srgb_to_linear()
	return Color(lin.r, lin.g, lin.b, 1.0 - emissive)


static func _box(acc: _Acc, bone: String, size: Vector3, center: Vector3, rot_deg: Vector3, color: Color, emissive: float, mat: int) -> void:
	var h := size * 0.5
	var xf: Transform3D = acc.rest[bone] * Transform3D(Basis.from_euler(rot_deg * (PI / 180.0)), center)
	var faces := [
		[Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)],
		[Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)],
		[Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1)],
		[Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
		[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)],
		[Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0)],
	]
	var col := _vcol(color, emissive)
	var w := {bone: 1.0}
	for f in faces:
		var nn: Vector3 = f[0]
		var c: Vector3 = nn * h
		var du: Vector3 = f[1] * h
		var dv: Vector3 = f[2] * h
		var world_n := (xf.basis * nn).normalized()
		var i0 := acc.vert(xf * (c - du - dv), world_n, col, mat, w)
		var i1 := acc.vert(xf * (c + du - dv), world_n, col, mat, w)
		var i2 := acc.vert(xf * (c + du + dv), world_n, col, mat, w)
		var i3 := acc.vert(xf * (c - du + dv), world_n, col, mat, w)
		acc.tri(i0, i2, i1)
		acc.tri(i0, i3, i2)


## Ellipsoïde lissé. Clés : bone, size (diamètres), center, rot (°), rings,
## sides, w (poids d'os, défaut {bone: 1}), half (true : moitié haute seule,
## fermée par un disque), squash (écrase le bas : y *= 1 - squash pour y < 0).
static func _ellipsoid(acc: _Acc, d: Dictionary, color: Color, emissive: float, mat: int) -> void:
	var bone: String = d.bone
	var r: Vector3 = d.size * 0.5
	var xf: Transform3D = acc.rest[bone] * Transform3D(Basis.from_euler(d.get("rot", Vector3.ZERO) * (PI / 180.0)), d.get("center", Vector3.ZERO))
	var rings: int = d.get("rings", 5)
	var sides: int = d.get("sides", 8)
	var w: Dictionary = d.get("w", {bone: 1.0})
	var half: bool = d.get("half", false)
	var col := _vcol(color, emissive)
	var lat_end := 0.0 if half else -PI * 0.5
	var first := acc.n
	var top := acc.vert(xf * Vector3(0, r.y, 0), (xf.basis * Vector3.UP).normalized(), col, mat, w)
	for i in range(1, rings):
		var lat := PI * 0.5 - (PI * 0.5 - lat_end) * float(i) / float(rings)
		for j in sides:
			var lon := TAU * float(j) / float(sides)
			var u := Vector3(cos(lat) * sin(lon), sin(lat), cos(lat) * cos(lon))
			var pos := u * r
			var nrm := Vector3(u.x / r.x, u.y / r.y, u.z / r.z)
			acc.vert(xf * pos, (xf.basis * nrm).normalized(), col, mat, w)
	var ring_count := rings - 1
	# Calotte supérieure.
	for j in sides:
		acc.tri(top, first + 1 + j, first + 1 + (j + 1) % sides)
	for i in ring_count - 1:
		var a := first + 1 + i * sides
		var b := a + sides
		for j in sides:
			var j2 := (j + 1) % sides
			acc.tri(a + j, b + j, b + j2)
			acc.tri(a + j, b + j2, a + j2)
	var last := first + 1 + (ring_count - 1) * sides
	if half:
		# Disque de fermeture (plat, orienté vers le bas).
		var dn := (xf.basis * Vector3.DOWN).normalized()
		var base := acc.n
		var center := acc.vert(xf * Vector3(0, 0, 0), dn, col, mat, w)
		for j in sides:
			var lon := TAU * float(j) / float(sides)
			acc.vert(xf * (Vector3(sin(lon), 0, cos(lon)) * r), dn, col, mat, w)
		for j in sides:
			acc.tri(center, base + 1 + (j + 1) % sides, base + 1 + j)
		# Couronne entre le dernier anneau et l'équateur.
		var eq := acc.n
		for j in sides:
			var lon := TAU * float(j) / float(sides)
			var u := Vector3(sin(lon), 0, cos(lon))
			acc.vert(xf * (u * r), (xf.basis * Vector3(u.x / r.x, 0, u.z / r.z)).normalized(), col, mat, w)
		for j in sides:
			var j2 := (j + 1) % sides
			acc.tri(last + j, eq + j, eq + j2)
			acc.tri(last + j, eq + j2, last + j2)
	else:
		var bottom := acc.vert(xf * Vector3(0, -r.y, 0), (xf.basis * Vector3.DOWN).normalized(), col, mat, w)
		for j in sides:
			acc.tri(bottom, last + (j + 1) % sides, last + j)


## Tube de sections elliptiques (du haut vers le bas). Clés :
##   bone : os principal (repère des centres, morceau arraché) ;
##   rings : Array de [centre (relatif à l'origine de repos de `bone`),
##           rayons Vector2(x, z), poids {os: w} ou null (= bone),
##           couleur (optionnelle)] ;
##   sides (8), axis (Vector3.UP : sections perpendiculaires, du haut vers
##   le bas le long de -axis), cap_top / cap_bottom (disques de fermeture),
##   jag (déchirure : décalage aléatoire du dernier anneau le long de l'axe),
##   seed, deform : Callable(position, angle, i_anneau) -> position (repère
##   du modèle), wfn : Callable(position, poids de l'anneau) -> poids du sommet.
static func _loft(acc: _Acc, d: Dictionary, color: Color, emissive: float, mat: int) -> void:
	var bone: String = d.bone
	var origin: Vector3 = acc.rest[bone].origin
	var rings: Array = d.rings
	var sides: int = d.get("sides", 8)
	var axis: Vector3 = d.get("axis", Vector3.UP)
	var basis := _axis_basis(axis)
	var jag: float = d.get("jag", 0.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = d.get("seed", 1)
	var deform: Callable = d.get("deform", Callable())
	var wfn: Callable = d.get("wfn", Callable())
	var nr := rings.size()
	# Positions de la grille.
	var grid: Array[PackedVector3Array] = []
	for i in nr:
		var ring: Array = rings[i]
		var c: Vector3 = origin + ring[0]
		var rad: Vector2 = ring[1]
		var row := PackedVector3Array()
		for j in sides:
			var ang := TAU * float(j) / float(sides)
			var local := Vector3(sin(ang) * rad.x, 0.0, cos(ang) * rad.y)
			var pos := c + basis * local
			if jag > 0.0 and i == nr - 1:
				pos -= axis * rng.randf_range(0.0, jag)
			if deform.is_valid():
				pos = deform.call(pos, ang, i)
			row.append(pos)
		grid.append(row)
	var first := acc.n
	for i in nr:
		var ring: Array = rings[i]
		var w: Dictionary = ring[2] if ring.size() > 2 and ring[2] != null else {bone: 1.0}
		var col := _vcol(ring[3] if ring.size() > 3 else color, emissive)
		for j in sides:
			var along: Vector3 = grid[mini(i + 1, nr - 1)][j] - grid[maxi(i - 1, 0)][j]
			var around: Vector3 = grid[i][(j + 1) % sides] - grid[i][(j - 1 + sides) % sides]
			var nrm := around.cross(along)
			var outward: Vector3 = grid[i][j] - (origin + ring[0])
			if nrm.length_squared() < 1e-10:
				nrm = outward
			elif nrm.dot(outward) < 0.0:
				nrm = -nrm
			var wv: Dictionary = wfn.call(grid[i][j], w) if wfn.is_valid() else w
			acc.vert(grid[i][j], nrm.normalized(), col, mat, wv)
	for i in nr - 1:
		var a := first + i * sides
		var b := a + sides
		for j in sides:
			var j2 := (j + 1) % sides
			acc.tri(a + j, b + j2, b + j)
			acc.tri(a + j, a + j2, b + j2)
	if d.get("cap_top", false):
		_cap(acc, grid[0], rings[0], bone, color, emissive, mat, axis, true)
	if d.get("cap_bottom", false):
		_cap(acc, grid[nr - 1], rings[nr - 1], bone, color, emissive, mat, -axis, false)


static func _cap(acc: _Acc, row: PackedVector3Array, ring: Array, bone: String, color: Color, emissive: float, mat: int, nrm: Vector3, top: bool) -> void:
	var w: Dictionary = ring[2] if ring.size() > 2 and ring[2] != null else {bone: 1.0}
	var col := _vcol(ring[3] if ring.size() > 3 else color, emissive)
	var c := Vector3.ZERO
	for p in row:
		c += p
	c /= float(row.size())
	var base := acc.n
	var ci := acc.vert(c, nrm, col, mat, w)
	for p in row:
		acc.vert(p, nrm, col, mat, w)
	var s := row.size()
	for j in s:
		var j2 := (j + 1) % s
		if top:
			acc.tri(ci, base + 1 + j2, base + 1 + j)
		else:
			acc.tri(ci, base + 1 + j, base + 1 + j2)


## Base dont Y = axe du tube (sections dans le plan X/Z de la base).
static func _axis_basis(axis: Vector3) -> Basis:
	var y := axis.normalized()
	if y.is_equal_approx(Vector3.UP):
		return Basis.IDENTITY
	var ref := Vector3.UP if absf(y.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var x := ref.cross(y).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


## Indices des os d'un squelette construit par build().
static func bone_indices(skel: Skeleton3D) -> Dictionary:
	var d := {}
	for b in BONES:
		d[b[0]] = skel.find_bone(b[0])
	return d
