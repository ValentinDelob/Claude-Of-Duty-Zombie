class_name VoxelCheck
extends RefCounted
## Vérification automatique du STYLE CUBIQUE (GAME_CONCEPT.md § 4.19,
## docs/MAP_DESIGN_RULES.md « Style cubique ») : 1 cube = 5 cm pour le décor
## et les objets (CUBE), 2,5 cm pour les personnages et les mobs (CUBE_CHAR) ;
## aucun élément qui n'est pas cubique ou hors de l'échelle des cubes n'entre
## dans le jeu. Fonctions pures (aucun nœud ajouté à l'arbre, rien d'écrit).
## Pas de grille : celui du mode (statique 5 cm, animé 2,5 cm), ou forcé par
## le paramètre `cube` (m) des fonctions d'entrée.
##
## Un maillage respecte le style si :
##   - chaque face (triangle) a sa normale géométrique alignée sur un axe
##     (|composante dominante| ≥ NORMAL_MIN, ≈ 1,8° d'écart au plus) : ni
##     pente, ni biseau, ni courbe ;
##   - chaque normale de sommet fournie par le modèle est aussi alignée sur un
##     axe (sinon : ombrage lissé, interdit) ;
##   - chaque sommet est sur la grille du cube (5 ou 2,5 cm), à GRID_TOL près, la
##     grille partant du coin minimal de la boîte englobante de la partie
##     vérifiée (le modèle est déplacé librement : seules comptent les
##     distances entre ses sommets) ;
##   - le maillage n'a que des triangles (ni lignes ni points).
## Les triangles dégénérés (aire nulle) sont ignorés.
##
## Deux modes :
##   - STATIQUE (décor, prefab importé, objet ; grille de 5 cm) : tout le modèle dans le repère
##     de sa racine (transformations des nœuds comprises : un nœud tourné de
##     45° est refusé) ;
##   - ANIMÉ (personnages, zombies : `animated` ; grille de 2,5 cm) : chaque partie dans son
##     propre repère — un maillage skinné, triangle par triangle dans le
##     repère de REPOS de l'os qui le porte (pose de liaison de la Skin,
##     poids dominant du premier sommet ; la partie est aussi acceptée si elle
##     est cubique dans le repère du modèle au repos : os orienté de biais
##     dans Blender, membre aligné) ; un maillage non skinné, dans le
##     repère de son nœud (sans sa rotation, avec son échelle globale). Les
##     membres peuvent ainsi tourner à n'importe quel angle quand ils sont
##     animés, mais chaque membre est fait de cubes.
##
## Rapport (Dictionary) : ok, faces (triangles vérifiés), bad_faces (faces
## fautives), oblique (faces non alignées), off_grid (faces avec un sommet
## hors grille), smooth (sommets à normale lissée), other_prims (surfaces qui
## ne sont pas des triangles), first (premier exemple : [fr, en]), fr, en
## (texte lisible), `parts` (parties vérifiées) et `cube` (pas de grille, m).

## Taille d'un cube du décor et des objets de la carte (m) : mode STATIQUE.
const CUBE := 0.05
## Taille d'un cube des personnages et des mobs (m) : mode ANIMÉ
## (GAME_CONCEPT.md § 4.19 : 2 cubes de personnage = 1 cube de décor).
const CUBE_CHAR := 0.025


## Écart admis d'un sommet à la grille (m) : arrondis d'export.
const GRID_TOL := 0.002
## |composante dominante| minimale d'une normale « alignée » (cos 1,8°).
const NORMAL_MIN := 0.9995
## Mesh.PRIMITIVE_TRIANGLES.
const _TRIS := Mesh.PRIMITIVE_TRIANGLES


## Pas de grille d'un mode : `cube` > 0 forcé, sinon 2,5 cm (animé) ou 5 cm.
static func cube_for(animated: bool, cube := 0.0) -> float:
	return cube if cube > 0.0 else (CUBE_CHAR if animated else CUBE)


# ------------------------------------------------------------------ entrées
# `cube` (m) : pas de grille forcé ; 0 = celui du mode (cube_for).

## Vérifie un maillage seul (`xf` : repère dans lequel le lire ; `scale` :
## échelle uniforme appliquée ensuite, celle d'un prefab importé).
static func check_mesh(mesh: Mesh, xf := Transform3D.IDENTITY, scale := 1.0, name := "", cube := 0.0) -> Dictionary:
	var acc := _new_acc(cube_for(false, cube))
	if mesh != null:
		_add_mesh(acc, mesh, xf, null, scale, name if name != "" else "mesh")
	return _finish(acc)


## Vérifie une scène (nœuds hors de l'arbre ou dedans) : tous ses
## MeshInstance3D. `animated` : mode ANIMÉ (voir l'en-tête).
static func check_scene(root: Node, animated := false, scale := 1.0, cube := 0.0) -> Dictionary:
	var acc := _new_acc(cube_for(animated, cube))
	if root != null:
		var meshes: Array = root.find_children("*", "MeshInstance3D", true, false)
		if root is MeshInstance3D:
			meshes.push_front(root)
		for n in meshes:
			var mi := n as MeshInstance3D
			if mi.mesh == null:
				continue
			var xf := _to_root(mi, root)
			var nm := String(mi.name)
			if not animated:
				_add_mesh(acc, mi.mesh, xf, null, scale, nm)
			elif mi.skin != null and _skinned(mi.mesh):
				# Échelle globale du nœud (rotation et position ôtées) : les
				# poses de liaison sont dans le repère du squelette.
				_add_mesh(acc, mi.mesh, Transform3D(Basis.from_scale(xf.basis.get_scale()), Vector3.ZERO), mi.skin, scale, nm)
			else:
				_add_mesh(acc, mi.mesh, Transform3D(Basis.from_scale(xf.basis.get_scale()), Vector3.ZERO), null, scale, nm, "node:%d" % mi.get_instance_id())
	return _finish(acc)


## Vérifie un .glb (octets) : lu par GLTFDocument (sans les contrôles de
## sûreté de MapPrefabLib.check_glb : à faire avant pour un fichier venu
## d'ailleurs). `animated` : -1 = deviné (squelette présent), 0 = statique,
## 1 = animé. {ok: false, error: [fr, en]} s'il est illisible.
static func check_glb_bytes(glb: PackedByteArray, animated := -1, scale := 1.0, cube := 0.0) -> Dictionary:
	# En-tête « glTF » v2 de la bonne longueur, sinon illisible (sans erreur du moteur).
	if glb.size() < 28 or glb.decode_u32(0) != 0x46546C67 or glb.decode_u32(4) != 2 or glb.decode_u32(8) != glb.size():
		return _unreadable()
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_buffer(glb, "", st) != OK:
		return _unreadable()
	return _check_generated(doc, st, animated, scale, cube)


## Vérifie un fichier .glb / .gltf du disque (outil tools/voxel_check.gd).
static func check_file(path: String, animated := -1, scale := 1.0, cube := 0.0) -> Dictionary:
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(path, st) != OK:
		return _unreadable()
	return _check_generated(doc, st, animated, scale, cube)


static func _check_generated(doc: GLTFDocument, st: GLTFState, animated: int, scale: float, cube: float) -> Dictionary:
	var scene := doc.generate_scene(st)
	if scene == null:
		return _unreadable()
	var anim := animated == 1 or (animated < 0 and has_skeleton(scene))
	var rep := check_scene(scene, anim, scale, cube)
	rep["animated"] = anim
	scene.free()
	return rep


## La scène a-t-elle un squelette (personnage articulé) ?
static func has_skeleton(root: Node) -> bool:
	return root is Skeleton3D or not root.find_children("*", "Skeleton3D", true, false).is_empty()


static func _unreadable() -> Dictionary:
	return {"ok": false, "faces": 0, "bad_faces": 0, "error": ["modèle illisible", "unreadable model"],
		"fr": "Modèle illisible", "en": "Unreadable model"}


# ------------------------------------------------------------------ objets posés

## Un objet posé sur la carte respecte-t-il le style cubique ? Rotation par
## quarts de tour (« rot » multiple de 90°), pas d'inclinaison (« incl »),
## échelle qui garde ses dimensions sur la grille de 5 cm (`size` : taille
## de l'objet en m avant échelle, ignorée si nulle). [] si oui, [fr, en]
## sinon. Vérification seulement : l'éditeur garde ses rotations libres
## (docs/MAP_DESIGN_RULES.md « Style cubique »).
static func placement_issue(o: Dictionary, size := Vector3.ZERO) -> Array:
	var rot := float(o.get("rot", 0)) if (o.get("rot", 0) is float or o.get("rot", 0) is int) else 0.0
	if absf(rot - roundf(rot / 90.0) * 90.0) > 0.01:
		return ["tourné de %s° : seulement des quarts de tour (0, 90, 180, 270°)" % _n(rot),
			"rotated by %s°: quarter turns only (0, 90, 180, 270°)" % _n(rot)]
	# « incl » et « echelle » lus comme MapScale.incl_of / scale_of (sans en
	# dépendre : l'outil tools/voxel_check.gd tourne sans les autoloads).
	var incl := _vec(o.get("incl"), 2, Vector3.ZERO)
	if not incl.is_zero_approx():
		return ["incliné (%s° ; %s°) : un objet posé reste droit" % [_n(incl.x), _n(incl.y)],
			"tilted (%s°; %s°): a placed object stays upright" % [_n(incl.x), _n(incl.y)]]
	if size != Vector3.ZERO:
		var s := size * _vec(o.get("echelle"), 3, Vector3.ONE)
		for i in 3:
			if not on_grid(s[i]):
				return ["échelle hors grille : %s m n'est pas un multiple de 5 cm" % _n(s[i]),
					"scale off the grid: %s m is not a multiple of 5 cm" % _n(s[i])]
	return []


## Tableau de `n` nombres finis -> Vector3 (composantes absentes : celles de
## `def`) ; `def` si la valeur n'en est pas un.
static func _vec(v: Variant, n: int, def: Vector3) -> Vector3:
	if not (v is Array and (v as Array).size() == n):
		return def
	var out := def
	for i in n:
		if not ((v[i] is float or v[i] is int) and is_finite(float(v[i]))):
			return def
		out[i] = float(v[i])
	return out


## Une longueur (m) est-elle un multiple du cube (5 cm par défaut, à
## GRID_TOL près) ?
static func on_grid(x: float, cube := CUBE) -> bool:
	return absf(x - roundf(x / cube) * cube) <= GRID_TOL


# ------------------------------------------------------------------ cœur

static func _new_acc(cube: float) -> Dictionary:
	# groups : clé -> {tris: Array[PackedVector3Array(3)], where: Array[[nom, n°]]}
	return {"groups": {}, "smooth": 0, "other_prims": 0, "first_smooth": [], "first_prim": [], "cube": cube}


static func _skinned(mesh: Mesh) -> bool:
	for s in mesh.get_surface_count():
		var a := mesh.surface_get_arrays(s)
		if a[Mesh.ARRAY_BONES] != null and (a[Mesh.ARRAY_BONES] as PackedInt32Array).size() > 0:
			return true
	return false


## Repère d'un nœud dans celui de `root` (nœuds hors de l'arbre compris).
static func _to_root(n: Node, root: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


## Ajoute les triangles d'un maillage. `skin` : chaque triangle va dans le
## groupe de l'os dominant de son premier sommet, lu dans le repère de repos
## de cet os ; le groupe garde aussi ses triangles dans le repère du
## maillage (pose de repos) : une partie est acceptée si elle est cubique
## dans l'un OU l'autre (os orienté de biais, membre aligné sur le modèle).
## `key` : groupe (grille propre) ; "" = groupe unique « modèle ».
static func _add_mesh(acc: Dictionary, mesh: Mesh, xf: Transform3D, skin: Skin, scale: float, name: String, key := "") -> void:
	var sx := Transform3D(Basis.from_scale(Vector3.ONE * scale), Vector3.ZERO)
	for s in mesh.get_surface_count():
		# PrimitiveMesh (BoxMesh...) : toujours des triangles.
		if mesh is ArrayMesh and (mesh as ArrayMesh).surface_get_primitive_type(s) != _TRIS:
			acc.other_prims += 1
			if acc.first_prim.is_empty():
				acc.first_prim = [name, s]
			continue
		var a := mesh.surface_get_arrays(s)
		var pos: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		if pos.is_empty():
			continue
		var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var nrm: PackedVector3Array = a[Mesh.ARRAY_NORMAL] if a[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
		var bones: PackedInt32Array = a[Mesh.ARRAY_BONES] if skin != null and a[Mesh.ARRAY_BONES] != null else PackedInt32Array()
		var weights: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS] if skin != null and a[Mesh.ARRAY_WEIGHTS] != null else PackedFloat32Array()
		@warning_ignore("integer_division")
		var per := bones.size() / pos.size() if not bones.is_empty() else 0
		@warning_ignore("integer_division")
		var n_tri := (idx.size() if not idx.is_empty() else pos.size()) / 3
		var base := sx * xf
		for t in n_tri:
			var ids := [idx[t * 3], idx[t * 3 + 1], idx[t * 3 + 2]] if not idx.is_empty() else [t * 3, t * 3 + 1, t * 3 + 2]
			var full := base
			var g := key if key != "" else "model"
			if per > 0:
				var bi := _dominant(bones, weights, int(ids[0]), per)
				if bi >= 0 and bi < skin.get_bind_count():
					full = sx * xf * skin.get_bind_pose(bi)
					g = "bone:%s" % (String(skin.get_bind_name(bi)) if String(skin.get_bind_name(bi)) != "" else str(skin.get_bind_bone(bi)))
			if not acc.groups.has(g):
				acc.groups[g] = {"spaces": [[], []] if per > 0 else [[]], "where": []}
			var spaces: Array = acc.groups[g].spaces
			for k in spaces.size():
				var m: Transform3D = full if k == 0 else base
				var tri := PackedVector3Array([m * pos[ids[0]], m * pos[ids[1]], m * pos[ids[2]]])
				var ns := PackedVector3Array()
				if not nrm.is_empty():
					for v in ids:
						ns.append(m.basis * nrm[v])
				spaces[k].append([tri, ns])
			acc.groups[g].where.append([name, t])


## Os (indice de liaison) au plus fort poids du sommet `v`.
static func _dominant(bones: PackedInt32Array, weights: PackedFloat32Array, v: int, per: int) -> int:
	var best := -1
	var bw := -1.0
	for k in per:
		var w := weights[v * per + k] if v * per + k < weights.size() else (1.0 if k == 0 else 0.0)
		if w > bw:
			bw = w
			best = bones[v * per + k]
	return best


## Une normale (unitaire) est-elle alignée sur un axe ?
static func axis_aligned(n: Vector3) -> bool:
	return maxf(absf(n.x), maxf(absf(n.y), absf(n.z))) >= NORMAL_MIN


## Fautes d'un groupe de triangles ([tri, normales de sommet]) dans un repère,
## grille partant du coin minimal du groupe.
static func _eval(items: Array, where: Array, cube: float) -> Dictionary:
	var r := {"faces": 0, "bad": 0, "oblique": 0, "off": 0, "smooth": 0, "first_ob": [], "first_off": [], "first_smooth": []}
	var lo := Vector3(INF, INF, INF)
	for it in items:
		for p in it[0]:
			lo = lo.min(p)
	for i in items.size():
		var tri: PackedVector3Array = items[i][0]
		for nv in (items[i][1] as PackedVector3Array):
			if nv.length_squared() > 1e-12 and not axis_aligned(nv.normalized()):
				r.smooth += 1
				if r.first_smooth.is_empty():
					r.first_smooth = [where[i][0], nv.normalized()]
		var nn := (tri[1] - tri[0]).cross(tri[2] - tri[0])
		if nn.length_squared() < 1e-14:
			continue
		r.faces += 1
		var fault := false
		var n := nn.normalized()
		if not axis_aligned(n):
			r.oblique += 1
			fault = true
			if r.first_ob.is_empty():
				r.first_ob = [where[i][0], where[i][1], n]
		for p in tri:
			var q: Vector3 = p - lo
			if not (on_grid(q.x, cube) and on_grid(q.y, cube) and on_grid(q.z, cube)):
				r.off += 1
				fault = true
				if r.first_off.is_empty():
					r.first_off = [where[i][0], where[i][1], q]
				break
		if fault:
			r.bad += 1
	return r


static func _finish(acc: Dictionary) -> Dictionary:
	var faces := 0
	var bad := 0
	var oblique := 0
	var off := 0
	var smooth := 0
	var first_ob: Array = []
	var first_off: Array = []
	var first_smooth: Array = []
	for g in acc.groups:
		# Repère de l'os, sinon celui du maillage s'il a moins de fautes.
		var best := {}
		for items in acc.groups[g].spaces:
			var e := _eval(items, acc.groups[g].where, acc.cube)
			if best.is_empty() or e.bad + e.smooth < best.bad + best.smooth:
				best = e
		faces += best.faces
		bad += best.bad
		oblique += best.oblique
		off += best.off
		smooth += best.smooth
		if first_ob.is_empty():
			first_ob = best.first_ob
		if first_off.is_empty():
			first_off = best.first_off
		if first_smooth.is_empty():
			first_smooth = best.first_smooth
	acc["smooth"] = smooth
	acc["first_smooth"] = first_smooth
	var rep := {"faces": faces, "bad_faces": bad, "oblique": oblique, "off_grid": off, "smooth": acc.smooth,
		"other_prims": acc.other_prims, "parts": acc.groups.size(), "cube": acc.cube}
	rep["ok"] = faces > 0 and bad == 0 and acc.smooth == 0 and acc.other_prims == 0
	var cm := _cm(acc.cube)
	var ex_fr: Array = []
	var ex_en: Array = []
	if oblique > 0:
		ex_fr.append("%d face(s) oblique(s) (ex. « %s » face %d, normale %s)" % [oblique, first_ob[0], first_ob[1], _v(first_ob[2])])
		ex_en.append("%d slanted face(s) (e.g. \"%s\" face %d, normal %s)" % [oblique, first_ob[0], first_ob[1], _v(first_ob[2])])
	if off > 0:
		ex_fr.append("%d face(s) avec un sommet hors de la grille de %s cm (ex. « %s » face %d, sommet à %s m du coin)" % [off, cm[0], first_off[0], first_off[1], _v(first_off[2])])
		ex_en.append("%d face(s) with a vertex off the %s cm grid (e.g. \"%s\" face %d, vertex at %s m from the corner)" % [off, cm[1], first_off[0], first_off[1], _v(first_off[2])])
	if acc.smooth > 0:
		ex_fr.append("%d sommet(s) à ombrage lissé (ex. « %s », normale %s)" % [acc.smooth, acc.first_smooth[0], _v(acc.first_smooth[1])])
		ex_en.append("%d vertex(es) with smooth shading (e.g. \"%s\", normal %s)" % [acc.smooth, acc.first_smooth[0], _v(acc.first_smooth[1])])
	if acc.other_prims > 0:
		ex_fr.append("%d surface(s) qui ne sont pas des triangles (ex. « %s »)" % [acc.other_prims, acc.first_prim[0]])
		ex_en.append("%d surface(s) that are not triangles (e.g. \"%s\")" % [acc.other_prims, acc.first_prim[0]])
	if faces == 0 and acc.other_prims == 0:
		rep["fr"] = "Modèle non cubique : aucune face"
		rep["en"] = "Non-cubic model: no faces"
	elif rep.ok:
		rep["fr"] = "Modèle cubique (1 cube = %s cm) : %d faces conformes" % [cm[0], faces]
		rep["en"] = "Cubic model (1 cube = %s cm): %d compliant faces" % [cm[1], faces]
	else:
		rep["fr"] = "Modèle non cubique (1 cube = %s cm) : %d face(s) fautive(s) sur %d — %s" % [cm[0], bad, faces, " ; ".join(ex_fr)]
		rep["en"] = "Non-cubic model (1 cube = %s cm): %d faulty face(s) out of %d — %s" % [cm[1], bad, faces, "; ".join(ex_en)]
	rep["first"] = [ex_fr[0], ex_en[0]] if not ex_fr.is_empty() else []
	return rep


## Taille d'un cube en cm, lisible : [fr (virgule), en (point)].
static func _cm(cube: float) -> Array:
	var s := str(snappedf(cube * 100.0, 0.1))
	if s.ends_with(".0"):
		s = s.substr(0, s.length() - 2)
	return [s.replace(".", ","), s]


## Message de refus d'un import ([fr, en]) tiré d'un rapport.
static func refusal(rep: Dictionary) -> Array:
	return ["modèle refusé, pas dans le style cubique du jeu (règle § 4.19 : que des cubes de 5 cm alignés sur la grille). " + String(rep.get("fr", "")),
		"model refused, not in the game's cubic style (rule § 4.19: only 5 cm cubes aligned on the grid). " + String(rep.get("en", ""))]


static func _n(x: float) -> String:
	return str(snappedf(x, 0.001))


static func _v(v: Vector3) -> String:
	return "(%s ; %s ; %s)" % [_n(v.x), _n(v.y), _n(v.z)]
