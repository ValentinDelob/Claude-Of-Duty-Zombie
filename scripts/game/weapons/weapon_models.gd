class_name WeaponModels
extends RefCounted
## Modèles CUBIQUES des armes et objets tenus (cubes de 2,5 cm, GAME_CONCEPT
## §4.19), construits sous Blender par tools/blender/weapons/weapons_voxel.py :
##   * assets/models/weapons/voxel/<modèle>.glb : un nœud par PIÈCE MOBILE
##     « wpn__<modèle>__<groupe> » ("body" : carcasse ; "mag" chargeur,
##     "slide" culasse / glissière / verrou / levier d'armement, "pump" pompe,
##     "barrels" canons basculants, "cyl" barillet), couleur par face de cube
##     (COLOR_0, alpha 0 : face lumineuse), matériaux voxel_lib (metal, wood,
##     rubber, glass, glow, cloth, leather) ;
##   * assets/models/weapons/voxel/weapons_voxel.json : par modèle, points
##     remarquables, données (« info ») et pavés des pièces (contrôles de la
##     vue FPS, joue de visée), triangles.
## Repère : l'arme pointe vers -Z, origine au niveau de la détente.
##
## spec(modèle) = {"parts": pavés [forme "box", taille, centre, matériau,
## rotation 0, groupe], "anchors": points remarquables (Vector3), "info": données}.
## Points : bouche du canon "muzzle", cran / œilleton / oculaire "sight" et
## guidon / objectif "front" (TOUJOURS à la même hauteur : la ligne de mire
## est parallèle à -Z ; ViewModel la pose sur l'axe de la caméra en visée),
## "ads" (z : distance de l'œil au cran), "grip" (haut de la poignée, entre
## ses deux colonnes : repère du poing de ViewHands), "support" (main
## d'appui : dessous du garde-main, haut de la poignée avant...), "eject",
## pivots des pièces mobiles "pivot_<groupe>", "mag_dir" (sortie du
## chargeur), "hold" / "hold_rot" (tenue à la hanche).
##
## Les maillages des .glb sont lus une fois (fil principal), puis découpés
## pour la joue de visée (vue FPS) et partagés par toutes les instances.

const DIR := "res://assets/models/weapons/voxel/"
const SPEC_PATH := DIR + "weapons_voxel.json"
## Côté d'un cube des objets tenus (m).
const CUBE := 0.025

## Matières des modèles cubiques : [rugosité, métal]. La couleur vient de
## la face (COLOR_0) ; « glow » : faces lumineuses (alpha 0).
const MATERIALS := {
	"metal": [0.42, 0.55],
	"wood": [0.72, 0.0],
	"rubber": [0.82, 0.0],
	"glass": [0.12, 0.25],
	"glow": [0.4, 0.0],
	"cloth": [0.95, 0.0],
	"leather": [0.78, 0.0],
	"skin": [0.7, 0.0],
	# Zone d'équipe des mains FPS (gris teinté par la couleur du joueur :
	# team_material).
	"team": [0.95, 0.0],
}

## Vue FPS : épaisseur (m, selon Z) des tranches de la partie courbée par la
## joue de visée (WeaponMesh.slice_z).
const BEND_SLICE := 0.005

## Modèles d'armes définis (id du modèle = id de l'arme ; couteau et
## cartouches tenues compris) et leur famille. Mains : HANDS.
const SPECS := {
	"m1911": "pistol", "cz75": "pistol", "python": "revolver",
	"mp40": "smg", "mp5k": "smg", "pm63": "smg", "mpl": "smg", "spectre": "smg", "ak74u": "smg",
	"m14": "rifle", "m16": "rifle", "fnfal": "rifle", "g11": "rifle", "galil": "rifle", "famas": "rifle",
	"commando": "rifle", "aug": "rifle",
	"rpk": "lmg", "hk21": "lmg",
	"olympia": "shotgun", "stakeout": "shotgun", "spas12": "shotgun", "hs10": "shotgun",
	"l96a1": "sniper", "dragunov": "sniper",
	"china_lake": "launcher", "law": "rocket",
	"bat": "melee", "knife": "melee",
	"round_shell": "round", "round_40mm": "round",
}
## Mains et avant-bras (ViewHands), grenade et peluche (Throwable).
const HANDS := "hands"
const FRAG := "frag"
const TEDDY := "teddy"

static var _json: Dictionary = {}
static var _mat_cache: Dictionary = {}
## model_id -> {"parts": Array, "anchors": Dictionary, "info": Dictionary}
static var _spec_cache: Dictionary = {}
## model_id -> {groupe: {matériau: [sommets, normales, couleurs]}} (repère du modèle)
static var _raw_cache: Dictionary = {}
## "model_id|vm" -> {groupe: {"pivot": Vector3, "meshes": {matériau: ArrayMesh}}}
static var _geo_cache: Dictionary = {}


## Matériau d'une matière cubique (vue FPS ou 3e personne). `pap` : en
## sommeil (amélioration supprimée), gardé pour l'appel.
static func material(key: String, viewmodel: bool, pap := false) -> ShaderMaterial:
	var cache_key := "%s_%s" % [key, viewmodel]
	if _mat_cache.has(cache_key):
		return _mat_cache[cache_key]
	var spec_m: Array = MATERIALS.get(key, MATERIALS.rubber)
	var m := ShaderMaterial.new()
	m.shader = preload("res://assets/shaders/weapon.gdshader")
	m.set_shader_parameter("voxel", 1.0)
	m.set_shader_parameter("albedo", Color.WHITE)
	m.set_shader_parameter("roughness", spec_m[0])
	m.set_shader_parameter("metallic", spec_m[1])
	m.set_shader_parameter("emission_energy", 2.5 if key == "glow" else 0.0)
	m.set_shader_parameter("viewmodel", 1.0 if viewmodel else 0.0)
	m.set_shader_parameter("pap", 0.0)
	m.set_shader_parameter("team", 0.0)
	_mat_cache[cache_key] = m
	return m


## Matériau de la ZONE D'ÉQUIPE des mains (matière « team », peinte en gris
## dans hands.glb) à la couleur du joueur `col` (sRGB, HudStyle.PLAYER_COLORS) :
## weapon.gdshader la teinte comme player_voxel.gdshader le joueur vu par les
## autres (couleur × gris / 0,8). Un matériau par couleur (cache).
static func team_material(col: Color, viewmodel: bool) -> ShaderMaterial:
	var cache_key := "team_%s_%s" % [col.to_html(false), viewmodel]
	if _mat_cache.has(cache_key):
		return _mat_cache[cache_key]
	var m := material("team", viewmodel).duplicate() as ShaderMaterial
	m.set_shader_parameter("team", 1.0)
	m.set_shader_parameter("team_color", col)
	_mat_cache[cache_key] = m
	return m


## Maillage au même format que les armes (sommets, normales, couleurs) : sert
## au préchauffage des shaders (warmup.gd).
static func warmup_mesh() -> ArrayMesh:
	var acc := WeaponMesh.Acc.new()
	WeaponMesh.box(acc, Vector3.ONE * 0.05)
	return acc.commit()


# --------------------------------------------------------------------------
# Données (.json) et maillages (.glb)

static func _data() -> Dictionary:
	if _json.is_empty():
		var f := FileAccess.open(SPEC_PATH, FileAccess.READ)
		if f != null:
			var d: Variant = JSON.parse_string(f.get_as_text())
			if d is Dictionary:
				_json = d
		if _json.is_empty():
			push_warning("[WeaponModels] données absentes : " + SPEC_PATH)
			_json = {"_": {}}
	return _json


static func _vec(v: Variant, def := Vector3.ZERO) -> Vector3:
	if v is Array and v.size() >= 3:
		return Vector3(float(v[0]), float(v[1]), float(v[2]))
	return def


## Pavés, points remarquables et données d'un modèle (calculés une fois).
## Modèle inconnu : celui du pistolet de départ.
static func spec(model_id: String) -> Dictionary:
	if _spec_cache.has(model_id):
		return _spec_cache[model_id]
	var data := _data()
	var d: Dictionary = data.get(model_id, data.get("m1911", {}))
	var parts := []
	for b in d.get("boxes", []):
		parts.append(["box", Vector3(float(b[5]), float(b[6]), float(b[7])), Vector3(float(b[2]), float(b[3]), float(b[4])),
			String(b[1]), 0.0, String(b[0])])
	var anchors := {}
	var a: Dictionary = d.get("anchors", {})
	for k in a:
		anchors[String(k)] = _vec(a[k])
	var out := {"parts": parts, "anchors": anchors, "info": d.get("info", {}), "family": d.get("family", ""),
		"tris": int(d.get("tris", 0)), "groups": d.get("groups", [])}
	_spec_cache[model_id] = out
	return out


## Triangles du .glb d'un objet, par pièce et par matière, dans le repère de
## l'objet (transformations des nœuds appliquées) : {pièce: {matière:
## [sommets, normales, couleurs]}}. Pièce = dernier segment du nom du nœud
## (« wpn__<modèle>__<pièce> », « hand__<pièce> »...). Fil principal (chargement).
static func raw(model_id: String) -> Dictionary:
	if _raw_cache.has(model_id):
		return _raw_cache[model_id]
	var out := {}
	var path := DIR + model_id + ".glb"
	var ps: PackedScene = load(path) if ResourceLoader.exists(path) else null
	if ps == null:
		push_warning("[WeaponModels] modèle absent : " + path)
		_raw_cache[model_id] = out
		return out
	var scene := ps.instantiate()
	for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		var piece := String(mi.name).get_slice("__", String(mi.name).get_slice_count("__") - 1)
		var xf := _to_root(mi, scene)
		var nb := xf.basis.orthonormalized()
		var by_mat: Dictionary = out.get(piece, {})
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var mat := mi.mesh.surface_get_material(s)
			var key := (mat.resource_name if mat else "rubber").get_slice(".", 0)
			if not MATERIALS.has(key):
				key = "rubber"
			var sv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var sn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var sc: PackedColorArray = arr[Mesh.ARRAY_COLOR] if arr[Mesh.ARRAY_COLOR] != null else PackedColorArray()
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			if idx.is_empty():
				idx.resize(sv.size())
				for i in sv.size():
					idx[i] = i
			var acc: Array = by_mat.get(key, [PackedVector3Array(), PackedVector3Array(), PackedColorArray()])
			var v: PackedVector3Array = acc[0]
			var n: PackedVector3Array = acc[1]
			var c: PackedColorArray = acc[2]
			for i in idx:
				v.append(xf * sv[i])
				n.append(nb * sn[i])
				c.append(sc[i] if i < sc.size() else Color.WHITE)
			by_mat[key] = [v, n, c]
		out[piece] = by_mat
	scene.free()
	_raw_cache[model_id] = out
	return out


static func _to_root(n: Node, root: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur := n
	while cur != null and cur != root:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


## Géométrie d'un modèle (cache). Vue FPS : un sous-ensemble par pièce
## mobile ("body", "mag", "slide"...), autour de son pivot ; 3e personne :
## tout dans un seul groupe "".
static func geometry(model_id: String, viewmodel: bool) -> Dictionary:
	var key := "%s|%s" % [model_id, viewmodel]
	if _geo_cache.has(key):
		return _geo_cache[key]
	var arr: Variant = take_arrays(key)
	if arr == null:
		raw(model_id)
		arr = geometry_arrays(model_id, viewmodel)
	var out := {}
	for g in arr:
		var meshes := {}
		for mk in arr[g].arrays:
			meshes[mk] = WeaponMesh.Acc.make_mesh(arr[g].arrays[mk])
		out[g] = {"pivot": arr[g].pivot, "meshes": meshes}
	_geo_cache[key] = out
	return out


## Tableaux de la géométrie d'un modèle ({groupe: {pivot, arrays: {matériau:
## [sommets, normales, couleurs]}}}) : données pures, calculables hors du fil
## principal (raw() et spec() doivent déjà être en cache).
static func geometry_arrays(model_id: String, viewmodel: bool) -> Dictionary:
	var sp: Dictionary = _spec_cache[model_id] if _spec_cache.has(model_id) else spec(model_id)
	if not ThreadGuard.worker():
		raw(model_id)
	var src: Dictionary = _raw_cache.get(model_id, {})
	# Vue FPS : la partie qui passe sous la joue de visée (ViewModel.bend :
	# derrière le cran) est découpée en tranches de BEND_SLICE m le long de Z
	# (avec 6 cm de marge en avant du cran pour le recul et la mise en joue),
	# pour que le shader la courbe sans pans plats.
	var slice_from := INF
	if viewmodel and not sp.get("info", {}).get("no_sights", false):
		slice_from = anchor(model_id, "sight").z - 0.06
	var out := {}
	for piece in src:
		var g: String = piece if viewmodel else ""
		var pivot: Vector3 = sp.anchors.get("pivot_" + g, Vector3.ZERO) if viewmodel and g != "body" else Vector3.ZERO
		if not out.has(g):
			out[g] = {"pivot": pivot, "arrays": {}}
		for mk in src[piece]:
			var a: Array = src[piece][mk]
			var v := PackedVector3Array(a[0])
			if pivot != Vector3.ZERO:
				for i in v.size():
					v[i] -= pivot
			var cur: Array = out[g].arrays.get(mk, [PackedVector3Array(), PackedVector3Array(), PackedColorArray()])
			var cv: PackedVector3Array = cur[0]
			var cn: PackedVector3Array = cur[1]
			var cc: PackedColorArray = cur[2]
			cv.append_array(v)
			cn.append_array(a[1])
			cc.append_array(a[2])
			out[g].arrays[mk] = [cv, cn, cc]
	if slice_from < INF:
		for g in out:
			for mk in out[g].arrays:
				out[g].arrays[mk] = WeaponMesh.slice_z(out[g].arrays[mk], slice_from, BEND_SLICE, (out[g].pivot as Vector3).z)
	return out


# --------------------------------------------------------------------------
# Préchargement hors du fil principal : les .glb sont lus ici (fil principal,
# rapide), puis la découpe de la vue FPS et les pièces des mains sont
# calculées par une tâche de fond au lancement de la partie ; le fil
# principal n'a plus qu'à créer les maillages (rapide) au premier affichage.

static var _mutex := Mutex.new()
static var _ready_arrays: Dictionary = {}
static var _task := -1


## Tableaux précalculés pour `key` (retirés du stock) ou null.
static func take_arrays(key: String) -> Variant:
	_mutex.lock()
	var a: Variant = _ready_arrays.get(key)
	_ready_arrays.erase(key)
	_mutex.unlock()
	return a


static func precompute_async() -> void:
	if _task >= 0:
		return
	# Lecture des .glb et des données ici (fil principal) : la tâche ne fait
	# que les lire.
	for id in SPECS:
		spec(id)
		raw(id)
	raw(HANDS)
	spec(HANDS)
	_task = WorkerThreadPool.add_task(_precompute_all, false, "Modèles des armes")


## Attend la fin du préchargement (sortie du jeu, tests).
static func wait_precompute() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -2


static func _precompute_all() -> void:
	var jobs := []
	for piece in ViewHands.PIECES:
		jobs.append(["hand|" + piece, piece])
	for vm in [true, false]:
		for id in SPECS:
			jobs.append(["%s|%s" % [id, vm], id, vm])
	for j in jobs:
		var arr: Dictionary
		if j.size() == 2:
			arr = ViewHands.piece_arrays(j[1])
		else:
			arr = geometry_arrays(j[1], j[2])
		_mutex.lock()
		_ready_arrays[j[0]] = arr
		_mutex.unlock()


## Construit le modèle d'une arme. `viewmodel` : matériaux et découpage de la
## vue FPS (un nœud par pièce mobile : "body", "mag", "slide"...) ; sinon un
## MeshInstance3D par matériau, directement sous la racine.
static func build(model_id: String, viewmodel: bool, pap := false) -> Node3D:
	var root := Node3D.new()
	root.name = "Model_" + model_id
	var geo := geometry(model_id, viewmodel)
	for g in geo:
		var holder := root
		if viewmodel:
			holder = Node3D.new()
			holder.name = g
			holder.position = geo[g].pivot
			root.add_child(holder)
		for mk in geo[g].meshes:
			var mi := MeshInstance3D.new()
			mi.mesh = geo[g].meshes[mk]
			mi.material_override = material(mk, viewmodel, pap)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if viewmodel else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			if viewmodel:
				# Pas de culling par frustum : l'arme est toujours à l'écran.
				mi.extra_cull_margin = 1.0
			holder.add_child(mi)
	return root


## Nœud d'une pièce d'un objet à pièces indépendantes (mains, grenade,
## peluche) : un MeshInstance3D par matière, sommets dans le repère de la
## pièce (son décalage de grille compris).
static func piece_node(model_id: String, piece: String, viewmodel: bool) -> Node3D:
	var root := Node3D.new()
	root.name = piece
	var src: Dictionary = raw(model_id).get(piece, {})
	for mk in src:
		var mi := MeshInstance3D.new()
		mi.mesh = WeaponMesh.Acc.make_mesh(src[mk])
		mi.material_override = material(mk, viewmodel)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if viewmodel else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if viewmodel:
			mi.extra_cull_margin = 1.0
		root.add_child(mi)
	return root


static func anchor(model_id: String, point: String) -> Vector3:
	var a: Dictionary = spec(model_id).anchors
	if a.has(point):
		return a[point]
	match point:
		"front":
			return a.get("sight", Vector3.ZERO) + Vector3(0, 0, -0.3)
		"ads":
			return Vector3(0, 0, 0.3)
		"eject":
			return a.get("sight", Vector3.ZERO) + Vector3(0.02, -0.02, -0.05)
		"mag_dir":
			return Vector3.DOWN
	return Vector3.ZERO


## Donnée scalaire d'un modèle (angle de la poignée...).
static func info(model_id: String, key: String, default: Variant = 0.0) -> Variant:
	return spec(model_id).get("info", {}).get(key, default)


## Triangles d'un modèle (budget, docs/WEAPONS.md).
static func triangles(model_id: String) -> int:
	return int(spec(model_id).get("tris", 0))


## Milieu de l'arme sur son axe (de la bouche du canon à la crosse) : sert à
## centrer les présentoirs.
static func center_z(model_id: String) -> float:
	var zmin := 0.0
	var zmax := 0.0
	for r in profile(model_id):
		zmin = minf(zmin, r[0].x - r[1].x * 0.5)
		zmax = maxf(zmax, r[0].x + r[1].x * 0.5)
	return (zmin + zmax) * 0.5


## Silhouette (profil) du modèle : liste de rectangles [centre (z, y), taille (z, y), angle]
## projetés sur le plan latéral.
static func profile(model_id: String) -> Array:
	var out := []
	for part in spec(model_id).parts:
		out.append([Vector2(part[2].z, part[2].y), Vector2(part[1].z, part[1].y), 0.0])
	return out


## Base d'un pavé (toujours sans rotation : cubes alignés sur la grille).
static func _part_basis(_part: Array) -> Basis:
	return Basis.IDENTITY


## Boîte englobante locale d'un pavé : [centre, taille].
static func _local_box(part: Array) -> Array:
	return [Vector3.ZERO, part[1]]
