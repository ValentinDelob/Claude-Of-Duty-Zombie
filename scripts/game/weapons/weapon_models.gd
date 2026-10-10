class_name WeaponModels
extends RefCounted
## Modèles des armes, assemblés à partir de primitives arrondies (WeaponMesh).
## Repère : l'arme pointe vers -Z, origine au niveau de la détente.
##
## Chaque arme est décrite par un ARCHÉTYPE paramétré (SPECS) : pistolet,
## revolver, arme longue (PM, fusil, mitrailleuse, sniper), fusil à pompe,
## lance-grenades, lance-roquettes... Le constructeur produit une liste de pièces
## [forme, données, position, matériau, rotation, groupe] où :
##   forme  : "box" (données = taille), "cyl" (Vector3(rayon, 0, longueur), axe Z),
##            "prism" ({pts: profil (z, y), w: largeur X, b: chanfrein}) ou
##            "lathe" ({prof: profil de révolution (z, rayon) autour de Z})
##   rotation : float (degrés autour de X) ou Vector3 (angles d'Euler en degrés)
##   groupe : pièce mobile de la vue FPS ("" : carcasse) — "mag" (chargeur),
##            "slide" (culasse, glissière, levier d'armement), "pump" (pompe),
##            "barrels" (canons basculants), "cyl" (barillet), "cover" (capot).
## et les points remarquables (bouche du canon, visée, poignée, main d'appui,
## pivots des pièces mobiles "pivot_<groupe>", sens de sortie du chargeur...).
##
## Les pièces sont fusionnées en un maillage par matériau (et par groupe en vue
## FPS), construit une seule fois puis partagé par toutes les instances.
##
## Organes de visée : l'ancre "sight" (cran de mire, œilleton, oculaire) et
## l'ancre "front" (guidon, objectif) sont TOUJOURS à la même hauteur : la
## ligne de mire est parallèle à l'axe -Z du modèle. En visée, ViewModel pose
## cette ligne exactement sur l'axe de la caméra (celui des balles), l'œil à
## "ads".z mètres derrière le cran. "eject" : fenêtre d'éjection des douilles.

## [couleur sRGB, rugosité, métal, usure des arêtes, veinage du bois]
const MATERIALS := {
	# Acier bronzé (noir bleuté) : arêtes usées qui laissent voir l'acier nu.
	"metal": [Color(0.23, 0.235, 0.24), 0.42, 0.85, 0.55, 0.0],
	"metal_dark": [Color(0.1, 0.105, 0.115), 0.48, 0.8, 0.7, 0.0],
	"metal_worn": [Color(0.33, 0.32, 0.3), 0.5, 0.8, 0.45, 0.0],
	# Phosphatation grise (armes américaines : M1911, M14, M16).
	"parker": [Color(0.17, 0.175, 0.16), 0.62, 0.6, 0.5, 0.0],
	# Bois vernis (noyer rougeâtre du M14 et de l'Olympia, bois des AK).
	"wood": [Color(0.23, 0.12, 0.068), 0.6, 0.0, 0.35, 1.0],
	"wood_dark": [Color(0.17, 0.085, 0.045), 0.6, 0.0, 0.3, 1.0],
	"wood_light": [Color(0.36, 0.22, 0.11), 0.58, 0.0, 0.35, 1.0],
	"polymer": [Color(0.09, 0.095, 0.09), 0.72, 0.0, 0.25, 0.0],
	"olive": [Color(0.22, 0.24, 0.15), 0.78, 0.0, 0.3, 0.0],
	"tan": [Color(0.44, 0.38, 0.25), 0.8, 0.0, 0.25, 0.0],
	"brass": [Color(0.62, 0.46, 0.2), 0.32, 0.9, 0.3, 0.0],
	# Étui de cartouche de chasse (plastique rouge).
	"hull": [Color(0.5, 0.07, 0.05), 0.55, 0.0, 0.2, 0.0],
	"glow": [Color(1.0, 0.45, 0.15), 0.3, 0.0, 0.0, 0.0],
	"glow_blue": [Color(0.35, 0.75, 1.0), 0.3, 0.0, 0.0, 0.0],
	"copper": [Color(0.55, 0.28, 0.15), 0.38, 0.85, 0.4, 0.0],
	"glass": [Color(0.08, 0.14, 0.16), 0.08, 0.3, 0.0, 0.0],
	# Âme du canon, lumière d'éjection : noir mat.
	"bore": [Color(0.015, 0.015, 0.015), 0.9, 0.0, 0.0, 0.0],
}

## Vue FPS : épaisseur (m, selon Z) des tranches de la partie courbée par la
## joue de visée (WeaponMesh.slice_z).
const BEND_SLICE := 0.005

## Description de chaque modèle (id du modèle = id de l'arme par défaut).
const SPECS := {
	# ---------------------------------------------------------------- poing
	"m1911": {"arch": "pistol", "len": 0.21, "slide": "parker", "frame": "parker", "grip": "wood_dark"},
	"cz75": {"arch": "pistol", "len": 0.2, "slide": "metal_dark", "frame": "metal_dark", "grip": "polymer", "h": 0.034, "mag_ext": 0.02, "cz": true},
	"python": {"arch": "revolver", "barrel": 0.17},
	# ---------------------------------------------------------------- pistolets-mitrailleurs
	# MP5K : très court, chargeur incurvé, poignée avant, sans crosse.
	"mp5k": {"arch": "long", "rec": [-0.2, 0.08, 0.065], "rec_mat": "metal_dark", "hg": [0.06, 0.055, "polymer"],
		"barrel": [0.05, 0.011], "muzzle": "none", "mag": ["curved", -0.07, 0.17, 18.0], "stock": ["none"],
		"top": "drum_sight", "front_grip": true, "charge": "left_top", "hk": true},
	# MPL : chargeur dans la poignée, crosse repliée sur le côté.
	"mpl": {"arch": "long", "rec": [-0.22, 0.08, 0.06], "rec_mat": "metal", "hg": [0.0, 0.0, "metal"],
		"barrel": [0.1, 0.012], "muzzle": "none", "mag": ["grip", 0.0, 0.1], "stock": ["folded_side", 0.24],
		"top": "iron", "shroud": true, "charge": "top"},
	# PM63 : minuscule, culasse apparente, chargeur dans la poignée, poignée avant rabattue.
	"pm63": {"arch": "long", "rec": [-0.16, 0.035, 0.055], "rec_mat": "metal", "hg": [0.0, 0.0, "metal"],
		"barrel": [0.04, 0.01], "muzzle": "brake", "mag": ["grip", 0.0, 0.09], "stock": ["wire_folded", 0.18],
		"top": "iron", "front_grip": true, "grip": "polymer", "charge": "none"},
	# MP40 : long tube, chargeur droit vertical devant la détente, crosse repliée dessous.
	"mp40": {"arch": "long", "rec": [-0.24, 0.1, 0.055], "rec_mat": "metal_dark", "hg": [0.06, 0.05, "polymer"],
		"barrel": [0.15, 0.011], "muzzle": "none", "mag": ["straight", -0.1, 0.22, 0.0], "stock": ["under_folded", 0.24],
		"top": "iron", "barrel_hook": true, "round": true, "charge": "left"},
	"spectre": {"arch": "long", "rec": [-0.2, 0.09, 0.065], "rec_mat": "metal_dark", "hg": [0.12, 0.06, "metal_dark"],
		"barrel": [0.04, 0.012], "muzzle": "none", "mag": ["straight", -0.08, 0.2, 6.0], "stock": ["top_folded", 0.26],
		"top": "iron", "shroud": true, "charge": "top"},
	# AK74u : garde-main en bois, chargeur incurvé, crosse repliée à gauche, cache-flamme.
	"ak74u": {"arch": "long", "rec": [-0.14, 0.12, 0.07], "rec_mat": "metal_dark", "hg": [0.13, 0.055, "wood"],
		"barrel": [0.06, 0.012], "muzzle": "ak", "mag": ["curved", -0.1, 0.19, 34.0], "stock": ["folded_side", 0.3],
		"top": "ak", "grip": "wood_dark"},
	# ---------------------------------------------------------------- fusils d'assaut
	# M14 : fût en noyer vernis sur toute la longueur, poignée demi-pistolet.
	"m14": {"arch": "long", "rec": [-0.12, 0.12, 0.05], "rec_mat": "parker", "hg": [0.24, 0.05, "wood"],
		"barrel": [0.24, 0.011], "muzzle": "flash", "mag": ["straight", -0.06, 0.12, 4.0], "stock": ["rifle", 0.3, "wood"],
		"top": "iron", "grip": "none", "wood_body": "wood", "upper_wood": true},
	# M16 : poignée de transport, garde-main rond, guidon triangulaire, crosse fixe.
	"m16": {"arch": "long", "rec": [-0.2, 0.12, 0.065], "rec_mat": "polymer", "hg": [0.24, 0.055, "polymer"],
		"barrel": [0.2, 0.01], "muzzle": "flash", "mag": ["straight", -0.08, 0.17, 6.0], "stock": ["solid", 0.28, "polymer"],
		"top": "handle", "round_hg": true, "front_post": true, "charge": "none"},
	"commando": {"arch": "long", "rec": [-0.2, 0.12, 0.065], "rec_mat": "polymer", "hg": [0.16, 0.055, "polymer"],
		"barrel": [0.08, 0.011], "muzzle": "brake", "mag": ["straight", -0.08, 0.17, 6.0], "stock": ["tube", 0.24],
		"top": "handle", "round_hg": true, "front_post": true, "charge": "none"},
	"galil": {"arch": "long", "rec": [-0.18, 0.12, 0.065], "rec_mat": "metal_dark", "hg": [0.18, 0.055, "wood_light"],
		"barrel": [0.16, 0.011], "muzzle": "flash", "mag": ["curved", -0.1, 0.2, 26.0], "stock": ["wire", 0.28],
		"top": "ak", "bipod": true},
	# FAMAS : bullpup, longue poignée de transport sur toute la longueur.
	"famas": {"arch": "long", "rec": [-0.3, 0.3, 0.07], "rec_mat": "polymer", "hg": [0.0, 0.0, "polymer"],
		"barrel": [0.14, 0.011], "muzzle": "flash", "mag": ["straight", 0.16, 0.14, 4.0], "stock": ["none"],
		"top": "famas", "bullpup": true, "charge": "none"},
	# AUG : bullpup vert, lunette intégrée, poignée avant verticale.
	"aug": {"arch": "long", "rec": [-0.24, 0.32, 0.075], "rec_mat": "olive", "hg": [0.0, 0.0, "olive"],
		"barrel": [0.2, 0.011], "muzzle": "flash", "mag": ["straight", 0.16, 0.15, 4.0], "stock": ["none"],
		"top": "scope_short", "bullpup": true, "front_grip": true, "rec_h": 0.085, "charge": "left"},
	# G11 : un bloc sans aspérité, poignée-lunette sur le dessus.
	"g11": {"arch": "long", "rec": [-0.4, 0.3, 0.07], "rec_mat": "polymer", "hg": [0.0, 0.0, "polymer"],
		"barrel": [0.0, 0.01], "muzzle": "none", "mag": ["none"], "stock": ["none"],
		"top": "g11", "bullpup": true, "rec_h": 0.13, "charge": "none"},
	"fnfal": {"arch": "long", "rec": [-0.2, 0.12, 0.06], "rec_mat": "metal_dark", "hg": [0.22, 0.06, "polymer"],
		"barrel": [0.2, 0.011], "muzzle": "flash", "mag": ["straight", -0.09, 0.14, 4.0], "stock": ["solid", 0.3, "polymer"],
		"top": "handle_low", "charge": "left"},
	# ---------------------------------------------------------------- mitrailleuses
	# HK21 : gros boîtier de bande sous l'arme, bipied, canon à manchon perforé.
	"hk21": {"arch": "long", "rec": [-0.26, 0.12, 0.07], "rec_mat": "metal", "hg": [0.2, 0.06, "polymer"],
		"barrel": [0.3, 0.014], "muzzle": "flash", "mag": ["box", -0.1, 0.13], "stock": ["solid", 0.28, "polymer"],
		"top": "iron", "bipod": true, "shroud": true, "rec_h": 0.09, "charge": "left_top", "hk": true},
	# RPK : AK allongée à tambour, crosse bois, bipied.
	"rpk": {"arch": "long", "rec": [-0.18, 0.12, 0.07], "rec_mat": "metal_dark", "hg": [0.16, 0.055, "wood"],
		"barrel": [0.32, 0.013], "muzzle": "flash", "mag": ["drum", -0.1, 0.08], "stock": ["rifle", 0.3, "wood"],
		"top": "ak", "grip": "wood_dark", "bipod": true},
	# ---------------------------------------------------------------- précision
	"dragunov": {"arch": "long", "rec": [-0.18, 0.1, 0.055], "rec_mat": "metal_dark", "hg": [0.22, 0.06, "wood"],
		"barrel": [0.36, 0.01], "muzzle": "flash", "mag": ["curved", -0.07, 0.13, 16.0], "stock": ["thumbhole", 0.32, "wood"],
		"top": "scope", "grip": "none"},
	"l96a1": {"arch": "long", "rec": [-0.2, 0.1, 0.06], "rec_mat": "metal", "hg": [0.22, 0.07, "olive"],
		"barrel": [0.4, 0.014], "muzzle": "brake", "mag": ["straight", -0.05, 0.08, 0.0], "stock": ["thumbhole", 0.34, "olive"],
		"top": "scope", "grip": "none", "bipod": true, "bolt": true, "wood_body": "olive", "charge": "none"},
	# ---------------------------------------------------------------- fusils à pompe
	"olympia": {"arch": "shotgun", "barrels": 2, "len": 0.66, "stock": "wood", "grip": "none"},
	"stakeout": {"arch": "shotgun", "barrels": 1, "len": 0.5, "stock": "none", "pump": true, "grip": "wood"},
	"spas12": {"arch": "shotgun", "barrels": 1, "len": 0.5, "stock": "top_folded", "pump": true, "grip": "polymer", "shroud": true},
	"hs10": {"arch": "shotgun", "barrels": 1, "len": 0.34, "stock": "none", "pump": false, "grip": "polymer"},
	# ---------------------------------------------------------------- explosifs
	"china_lake": {"arch": "launcher"},
	"law": {"arch": "rocket"},
	# ---------------------------------------------------------------- couteau (KnifeDB)
	# Couteau de combat : lame noircie, manche en polymère.
	"knife": {"arch": "knife", "blade": 0.17, "w": 0.028, "blade_mat": "metal_dark", "handle": "polymer", "guard": false},
}

static var _mat_cache: Dictionary = {}
## model_id -> {"parts": Array, "anchors": Dictionary}
static var _spec_cache: Dictionary = {}
## "model_id|vm" -> {groupe: {"pivot": Vector3, "meshes": {matériau: ArrayMesh}}}
static var _geo_cache: Dictionary = {}


static func material(key: String, viewmodel: bool, pap: bool) -> ShaderMaterial:
	var cache_key := "%s_%s_%s" % [key, viewmodel, pap]
	if _mat_cache.has(cache_key):
		return _mat_cache[cache_key]
	var mat_spec: Array = MATERIALS[key]
	var m := ShaderMaterial.new()
	m.shader = preload("res://assets/shaders/weapon.gdshader")
	m.set_shader_parameter("albedo", mat_spec[0])
	m.set_shader_parameter("roughness", mat_spec[1])
	m.set_shader_parameter("metallic", mat_spec[2])
	m.set_shader_parameter("edge_wear", mat_spec[3])
	m.set_shader_parameter("grain", mat_spec[4])
	m.set_shader_parameter("tone_var", 0.18)
	m.set_shader_parameter("viewmodel", 1.0 if viewmodel else 0.0)
	var no_pap := key.begins_with("glow") or key == "glass" or key == "bore"
	m.set_shader_parameter("pap", 1.0 if pap and not no_pap else 0.0)
	if key.begins_with("glow"):
		m.set_shader_parameter("emission", mat_spec[0])
		m.set_shader_parameter("emission_energy", 3.0)
	_mat_cache[cache_key] = m
	return m


## Maillage au même format que les armes (sommets, normales, couleurs) : sert
## au préchauffage des shaders (warmup.gd).
static func warmup_mesh() -> ArrayMesh:
	var acc := WeaponMesh.Acc.new()
	WeaponMesh.box(acc, Vector3.ONE * 0.05)
	return acc.commit()


## Pièces et points remarquables d'un modèle (calculés une fois).
static func spec(model_id: String) -> Dictionary:
	if _spec_cache.has(model_id):
		return _spec_cache[model_id]
	var p: Dictionary = SPECS.get(model_id, SPECS.m1911)
	var out: Dictionary
	match p.arch:
		"pistol": out = _pistol(p)
		"revolver": out = _revolver(p)
		"long": out = _long(p)
		"shotgun": out = _shotgun(p)
		"launcher": out = _launcher()
		"rocket": out = _rocket()
		_: out = _knife(p)
	_spec_cache[model_id] = out
	return out


static func _part_basis(part: Array) -> Basis:
	var r: Variant = part[4]
	if r is Vector3:
		return Basis.from_euler(Vector3(deg_to_rad(r.x), deg_to_rad(r.y), deg_to_rad(r.z)))
	return Basis(Vector3.RIGHT, deg_to_rad(float(r)))


## Boîte englobante locale d'une pièce (avant rotation) : [centre, taille].
static func _local_box(part: Array) -> Array:
	match part[0]:
		"box":
			return [Vector3.ZERO, part[1]]
		"cyl":
			return [Vector3.ZERO, Vector3(part[1].x * 2.0, part[1].x * 2.0, part[1].z)]
		"prism":
			var lo := Vector2(INF, INF)
			var hi := Vector2(-INF, -INF)
			for q: Vector2 in part[1].pts:
				lo = lo.min(q)
				hi = hi.max(q)
			return [Vector3(0, (lo.y + hi.y) * 0.5, (lo.x + hi.x) * 0.5), Vector3(part[1].w, hi.y - lo.y, hi.x - lo.x)]
		"lathe":
			var z0 := INF
			var z1 := -INF
			var r := 0.0
			for q: Vector2 in part[1].prof:
				z0 = minf(z0, q.x)
				z1 = maxf(z1, q.x)
				r = maxf(r, q.y)
			return [Vector3(0, 0, (z0 + z1) * 0.5), Vector3(r * 2.0, r * 2.0, z1 - z0)]
	return [Vector3.ZERO, Vector3.ZERO]


static func _emit(acc: WeaponMesh.Acc, part: Array) -> void:
	match part[0]:
		"box":
			WeaponMesh.box(acc, part[1])
		"cyl":
			WeaponMesh.cyl(acc, part[1].x, part[1].z)
		"prism":
			var d: Dictionary = part[1]
			var b: float = d.b if d.b >= 0.0 else clampf(float(d.w) * 0.14, 0.0005, 0.0045)
			WeaponMesh.prism(acc, d.pts, d.w, b)
		"lathe":
			WeaponMesh.lathe(acc, part[1].prof)


## Géométrie fusionnée d'un modèle (cache). Vue FPS : un sous-ensemble par
## groupe mobile, plus "rear" (pièces nettement en arrière du cran : crosse,
## plaque de couche) masqué en visée pour ne pas boucher le bas de l'écran.
static func geometry(model_id: String, viewmodel: bool) -> Dictionary:
	var key := "%s|%s" % [model_id, viewmodel]
	if _geo_cache.has(key):
		return _geo_cache[key]
	var arr: Variant = take_arrays(key)
	if arr == null:
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
## principal (les SPECS doivent déjà être en cache).
static func geometry_arrays(model_id: String, viewmodel: bool) -> Dictionary:
	var sp: Dictionary = _spec_cache[model_id] if _spec_cache.has(model_id) else spec(model_id)
	var rear_z := maxf(anchor(model_id, "sight").z + 0.06, 0.12)
	var accs := {}
	var i := 0
	for part in sp.parts:
		i += 1
		var g: String = part[5] if part.size() > 5 else ""
		var b := _part_basis(part)
		if not viewmodel:
			g = ""
		elif g == "":
			var lb := _local_box(part)
			g = "rear" if (part[2] + b * lb[0]).z > rear_z else "body"
		var pivot: Vector3 = sp.anchors.get("pivot_" + g, Vector3.ZERO) if viewmodel else Vector3.ZERO
		if not accs.has(g):
			accs[g] = {}
		var mk: String = part[3]
		if not accs[g].has(mk):
			var a := WeaponMesh.Acc.new()
			a.seg = 16 if viewmodel else 8
			accs[g][mk] = a
		var acc: WeaponMesh.Acc = accs[g][mk]
		acc.xf = Transform3D(b, part[2] - pivot)
		acc.tone = fposmod(float(i) * 0.618034, 1.0)
		_emit(acc, part)
	# Vue FPS : la partie qui passe sous la joue de visée (ViewModel.bend :
	# derrière le cran) est découpée en tranches de BEND_SLICE m le long de Z
	# (avec 6 cm de marge en avant du cran pour le recul et la mise en joue),
	# pour que le shader la courbe sans pans plats.
	var slice_from := INF
	if viewmodel and not sp.get("info", {}).get("no_sights", false):
		slice_from = anchor(model_id, "sight").z - 0.06
	var out := {}
	for g in accs:
		var arrays := {}
		var gp: Vector3 = sp.anchors.get("pivot_" + g, Vector3.ZERO) if viewmodel else Vector3.ZERO
		for mk in accs[g]:
			if not accs[g][mk].is_empty():
				arrays[mk] = accs[g][mk].arrays()
				if slice_from < INF:
					arrays[mk] = WeaponMesh.slice_z(arrays[mk], slice_from, BEND_SLICE, gp.z)
		out[g] = {"pivot": sp.anchors.get("pivot_" + g, Vector3.ZERO) if viewmodel else Vector3.ZERO, "arrays": arrays}
	return out


# --------------------------------------------------------------------------
# Préchargement hors du fil principal : toute la géométrie (armes en vue FPS
# et 3e personne, pièces des mains) est calculée par une tâche de fond au
# lancement de la partie ; le fil principal n'a plus qu'à créer les maillages
# (rapide) au premier affichage. Sans préchargement, le calcul se fait à la
# demande.

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


static func precompute_async(hand_style := 0) -> void:
	if _task >= 0:
		return
	# Les SPECS se calculent ici (fil principal) : la tâche ne fait que les lire.
	for id in SPECS:
		spec(id)
	var style := posmod(hand_style, ViewHands.STYLES.size())
	_task = WorkerThreadPool.add_task(_precompute_all.bind(style), false, "Modèles des armes")


## Attend la fin du préchargement (sortie du jeu, tests).
static func wait_precompute() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -2


static func _precompute_all(style: int) -> void:
	var jobs := []
	for piece in ViewHands.PIECES:
		jobs.append(["hand|%d|%s" % [style, piece], piece])
	for vm in [true, false]:
		for id in SPECS:
			jobs.append(["%s|%s" % [id, vm], id, vm])
	for j in jobs:
		var arr: Dictionary
		if j.size() == 2:
			arr = ViewHands.piece_arrays(style, j[1])
		else:
			arr = geometry_arrays(j[1], j[2])
		_mutex.lock()
		_ready_arrays[j[0]] = arr
		_mutex.unlock()


## Construit le modèle d'une arme. `viewmodel` : matériaux et découpage de la
## vue FPS (un nœud par groupe mobile : "body", "rear", "mag", "slide"...) ;
## sinon un MeshInstance3D par matériau, directement sous la racine.
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


## Milieu de l'arme sur son axe (de la bouche du canon à la crosse) : sert à
## centrer les présentoirs (craie murale, boîte mystère).
static func center_z(model_id: String) -> float:
	var zmin := 0.0
	var zmax := 0.0
	for r in profile(model_id):
		zmin = minf(zmin, r[0].x - r[1].x * 0.5)
		zmax = maxf(zmax, r[0].x + r[1].x * 0.5)
	return (zmin + zmax) * 0.5


## Silhouette (profil) du modèle : liste de rectangles [centre (z, y), taille (z, y), angle]
## projetés sur le plan latéral. Sert aux dessins à la craie des achats muraux.
static func profile(model_id: String) -> Array:
	var out := []
	for part in spec(model_id).parts:
		var lb := _local_box(part)
		var sz: Vector3 = lb[1]
		var b := _part_basis(part)
		var c: Vector3 = part[2] + b * lb[0]
		var r: Variant = part[4]
		var ang := deg_to_rad(r.x if r is Vector3 else float(r))
		var extent := Vector2(sz.z, sz.y)
		# Rotation d'Euler autour de Y (pièce vue par le bout) : largeur apparente.
		if r is Vector3 and absf(r.y) > 45.0:
			extent = Vector2(sz.x, sz.y)
		out.append([Vector2(c.z, c.y), extent, ang])
	return out


# ==========================================================================
# Primitives d'assemblage
# ==========================================================================

static func _b(parts: Array, size: Vector3, pos: Vector3, mat: String, rot: Variant = 0.0, g := "") -> void:
	parts.append(["box", size, pos, mat, rot, g])


static func _c(parts: Array, radius: float, length: float, pos: Vector3, mat: String, rot: Variant = 0.0, g := "") -> void:
	parts.append(["cyl", Vector3(radius, 0, length), pos, mat, rot, g])


## Prisme : profil `pts` (Vector2(z, y)) extrudé sur la largeur `w`.
static func _p(parts: Array, pts: Array, w: float, pos: Vector3, mat: String, rot: Variant = 0.0, g := "", bev := -1.0) -> void:
	parts.append(["prism", {"pts": pts, "w": w, "b": bev}, pos, mat, rot, g])


## Révolution : profil (Vector2(z, rayon), z croissant) autour de l'axe Z.
static func _l(parts: Array, prof: Array, pos: Vector3, mat: String, rot: Variant = 0.0, g := "") -> void:
	parts.append(["lathe", {"prof": prof}, pos, mat, rot, g])


## Section transversale `pts` (Vector2(x, y)) extrudée le long de Z, de z0 à z1.
static func _x(parts: Array, pts: Array, z0: float, z1: float, mat: String, g := "", bev := -1.0) -> void:
	_p(parts, pts, absf(z1 - z0), Vector3(0, 0, (z0 + z1) * 0.5), mat, Vector3(0, 90, 0), g, bev)


## Section arrondie (x, y) de largeur `w`, hauteur `h`, centrée en (0, cy) :
## rayons des coins du haut `rt` et du bas `rb`.
static func _sec(w: float, h: float, cy: float, rt: float, rb: float, n := 3) -> Array:
	var hw := w * 0.5
	var hh := h * 0.5
	rt = minf(rt, minf(hw, hh) * 0.98)
	rb = minf(rb, minf(hw, hh) * 0.98)
	var out := []
	var corners := [[Vector2(hw - rb, -hh + rb), rb, -PI * 0.5], [Vector2(hw - rt, hh - rt), rt, 0.0],
		[Vector2(-hw + rt, hh - rt), rt, PI * 0.5], [Vector2(-hw + rb, -hh + rb), rb, PI]]
	for k in corners:
		var c: Vector2 = k[0]
		var r: float = k[1]
		for s in n + 1:
			var a: float = k[2] + PI * 0.5 * s / n
			out.append(c + Vector2(cos(a), sin(a)) * r + Vector2(0, cy))
	return out


## Profil (z, y) déplacé et tourné (degrés, même sens que les rotations des pièces).
static func _xf2(pts: Array, off: Vector2, deg := 0.0) -> Array:
	var out := []
	var a := deg_to_rad(deg)
	for q: Vector2 in pts:
		# Rotation autour de X : (y, z) -> (y cos - z sin, y sin + z cos).
		out.append(Vector2(q.y * sin(a) + q.x * cos(a), q.y * cos(a) - q.x * sin(a)) + off)
	return out


## Pontet : U renversé sous la carcasse, de z_back à z_front (z_front < z_back).
static func _guard(parts: Array, z_back: float, z_front: float, y_top: float, depth: float, t := 0.0045, w := 0.009, mat := "metal_dark") -> void:
	var yb := y_top - depth
	var pts := [Vector2(z_back, y_top), Vector2(z_back + 0.002, yb + 0.01), Vector2(z_back - 0.008, yb), Vector2(z_front + 0.01, yb),
		Vector2(z_front, yb + 0.012), Vector2(z_front, y_top),
		Vector2(z_front + t, y_top), Vector2(z_front + t, yb + 0.012 + t * 0.3), Vector2(z_front + 0.01 + t * 0.4, yb + t),
		Vector2(z_back - 0.008, yb + t), Vector2(z_back - t + 0.002, yb + 0.01 + t * 0.4), Vector2(z_back - t, y_top)]
	_p(parts, pts, w, Vector3.ZERO, mat, 0.0, "", 0.0015)


## Détente incurvée juste derrière le pontet avant.
static func _trigger(parts: Array, z: float, y_top: float) -> void:
	_p(parts, [Vector2(z - 0.002, y_top), Vector2(z + 0.004, y_top), Vector2(z + 0.001, y_top - 0.012), Vector2(z - 0.004, y_top - 0.02), Vector2(z - 0.007, y_top - 0.018), Vector2(z - 0.004, y_top - 0.01)],
		0.006, Vector3.ZERO, "metal_dark", 0.0, "", 0.001)


## Poignée pistolet (origine = détente) : crosse de pistolet à cannelures pour
## les doigts, inclinée de `ang` degrés, plaquettes, pontet et détente.
static func _pistol_grip(parts: Array, mat: String, z := 0.05, ang := -14.0, top := -0.005) -> void:
	var prof := [Vector2(-0.021, 0.05), Vector2(0.022, 0.05), Vector2(0.025, 0.02), Vector2(0.023, -0.045), Vector2(0.017, -0.056),
		Vector2(-0.016, -0.056), Vector2(-0.021, -0.046), Vector2(-0.025, -0.032), Vector2(-0.021, -0.022), Vector2(-0.025, -0.01),
		Vector2(-0.021, 0.0), Vector2(-0.024, 0.012), Vector2(-0.02, 0.03)]
	_p(parts, prof, 0.032, Vector3(0, -0.05, z), mat, ang, "", 0.0065)
	_guard(parts, z - 0.03, z - 0.095, top, 0.032)
	_trigger(parts, z - 0.058, top)


## Cran de mire : socle plein puis deux oreilles dont le sommet est sur la
## ligne de mire `line` (l'encoche laisse voir le guidon).
static func _notch(parts: Array, z: float, base_y: float, line: float, w := 0.026, notch := 0.009, mat := "metal_dark", g := "") -> void:
	var ear_h := 0.007
	var body_h := maxf(line - ear_h - base_y, 0.002)
	_b(parts, Vector3(w, body_h, 0.01), Vector3(0, line - ear_h - body_h * 0.5, z), mat, 0.0, g)
	var ear_w := (w - notch) * 0.5
	for sx in [-1.0, 1.0]:
		_b(parts, Vector3(ear_w, ear_h, 0.01), Vector3(sx * (notch + ear_w) * 0.5, line - ear_h * 0.5, z), mat, 0.0, g)


## Guidon : lame dont la pointe est exactement sur la ligne de mire.
## `hood` : oreilles de protection de part et d'autre (AK, M16).
static func _post(parts: Array, z: float, base_y: float, line: float, w := 0.005, hood := false, mat := "metal_dark", g := "") -> void:
	var h := maxf(line - base_y, 0.004)
	_b(parts, Vector3(w, h, 0.008), Vector3(0, line - h * 0.5, z), mat, 0.0, g)
	if hood:
		for sx in [-1.0, 1.0]:
			_p(parts, [Vector2(-0.007, 0.0), Vector2(0.007, 0.0), Vector2(0.005, h + 0.006), Vector2(-0.004, h + 0.006)], 0.004,
				Vector3(sx * 0.012, line - h, z), mat, 0.0, g, 0.001)
		_b(parts, Vector3(0.028, 0.006, 0.014), Vector3(0, line - h + 0.003, z), mat, 0.0, g)


## Œilleton (dioptre) : anneau percé centré sur la ligne de mire (un disque
## sombre : on voit à travers le trou).
static func _aperture(parts: Array, z: float, base_y: float, line: float, hole := 0.009, outer := 0.026, mat := "metal_dark") -> void:
	var bar := (outer - hole) * 0.5
	_b(parts, Vector3(outer, bar, 0.008), Vector3(0, line + (hole + bar) * 0.5, z), mat)
	var low_h := maxf(line - hole * 0.5 - base_y, bar)
	_b(parts, Vector3(outer, low_h, 0.008), Vector3(0, line - hole * 0.5 - low_h * 0.5, z), mat)
	for sx in [-1.0, 1.0]:
		_b(parts, Vector3(bar, hole, 0.008), Vector3(sx * (hole + bar) * 0.5, line, z), mat)


## Canon : tube de rayon `r` de z0 (bouche, le plus en avant) à z1, renflé
## près du boîtier, avec l'âme noire à la bouche.
static func _barrel(parts: Array, r: float, z0: float, z1: float, y: float, mat := "metal_dark") -> void:
	var l := z1 - z0
	var prof := [Vector2(z0, r * 0.9), Vector2(z0 + 0.002, r), Vector2(z1 - minf(0.04, l * 0.3), r), Vector2(z1 - minf(0.03, l * 0.25), r * 1.25), Vector2(z1, r * 1.25)]
	_l(parts, prof, Vector3(0, y, 0), mat)
	_c(parts, r * 0.55, 0.004, Vector3(0, y, z0 + 0.0015), "bore")


## Chargeur courbe (profil (z, y)) : arc qui part du haut `top` vers le bas en
## se courbant vers l'avant de `curve` degrés sur la longueur `l`.
static func _curved_pts(top: Vector2, l: float, depth: float, curve: float, steps := 8) -> Array:
	var front := []
	var back := []
	var c := top
	var ds := l / steps
	for s in steps + 1:
		var a := deg_to_rad(curve) * float(s) / steps
		var n := Vector2(-cos(a), sin(a))
		var d := depth * (1.0 - 0.08 * float(s) / steps)
		front.append(c + n * d * 0.5)
		back.append(c - n * d * 0.5)
		c += Vector2(-sin(a), -cos(a)) * ds
	back.reverse()
	return front + back


# ==========================================================================
# Archétypes
# ==========================================================================

static func _pistol(p: Dictionary) -> Dictionary:
	var parts := []
	var L: float = p.get("len", 0.21)
	var h: float = p.get("h", 0.036)
	var front := 0.035 - L
	var sm: String = p.get("slide", "metal_worn")
	var fm: String = p.get("frame", "metal")
	var gm: String = p.get("grip", "wood_dark")
	var slide_top := 0.035 + h * 0.5
	var slide_bot := 0.035 - h * 0.5
	var cz: bool = p.get("cz", false)
	var sw := 0.027 if cz else 0.029
	# Glissière (culasse mobile) : profil aux arêtes arrondies, stries arrière,
	# fenêtre d'éjection, bague de canon et âme à l'avant.
	_p(parts, [Vector2(front, slide_bot + 0.004), Vector2(front + 0.004, slide_bot), Vector2(0.036, slide_bot), Vector2(0.038, slide_top - 0.007),
		Vector2(0.034, slide_top), Vector2(front + 0.007, slide_top), Vector2(front, slide_top - 0.007)], sw, Vector3.ZERO, sm, 0.0, "slide", 0.0055)
	for i in 7:
		_b(parts, Vector3(sw + 0.0012, h * 0.55, 0.0013), Vector3(0, 0.037, 0.029 - i * 0.0036), "metal_dark", 0.0, "slide")
	_b(parts, Vector3(0.005, 0.009, 0.032), Vector3(0.0125, slide_top - 0.008, -0.035), "bore", 0.0, "slide")
	_b(parts, Vector3(0.004, 0.005, 0.014), Vector3(0.0118, slide_top - 0.01, -0.04), "brass", 0.0, "slide")
	_c(parts, 0.0098, 0.008, Vector3(0, 0.035, front + 0.003), "metal_dark", 0.0, "slide")
	_c(parts, 0.0045, 0.004, Vector3(0, 0.035, front - 0.0012), "bore", 0.0, "slide")
	# Guidon et cran de mire (sur la glissière) sur la même ligne.
	var line := slide_top + 0.009
	_post(parts, front + 0.02, slide_top, line, 0.005, false, "metal_dark", "slide")
	_notch(parts, 0.02, slide_top, line, 0.026, 0.009, "metal_dark", "slide")
	# Carcasse : cache-poussière sous la glissière, queue de castor, chien,
	# arrêtoir de culasse, pontet et détente.
	_p(parts, [Vector2(front + 0.02, 0.008), Vector2(front + 0.03, -0.004), Vector2(0.034, -0.004), Vector2(0.04, 0.006), Vector2(0.038, slide_bot + 0.001),
		Vector2(front + 0.02, slide_bot + 0.001)], sw - 0.002, Vector3.ZERO, fm, 0.0, "", 0.003)
	_p(parts, [Vector2(0.034, 0.006), Vector2(0.056, 0.012), Vector2(0.06, 0.006), Vector2(0.045, -0.014)], 0.024, Vector3.ZERO, fm, 0.0, "", 0.004)
	_p(parts, [Vector2(0.0, 0.0), Vector2(0.004, 0.017), Vector2(0.012, 0.021), Vector2(0.014, 0.014), Vector2(0.007, 0.0)], 0.008,
		Vector3(0, 0.038, 0.032), "metal_dark", -8.0, "", 0.0015)
	_b(parts, Vector3(0.004, 0.006, 0.024), Vector3(-sw * 0.5 - 0.001, 0.014, -0.028), "metal_dark")
	_c(parts, 0.0035, sw + 0.006, Vector3(0, 0.012, -0.04), "metal_dark", Vector3(0, 90, 0))
	_guard(parts, -0.004, -0.058, 0.0, 0.03)
	_trigger(parts, -0.022, -0.0)
	# Crosse inclinée : carcasse, plaquettes (bois ou caoutchouc) et vis.
	var ga := -12.0
	var gpos := Vector3(0, -0.05, 0.02)
	var gb := Basis(Vector3.RIGHT, deg_to_rad(ga))
	_p(parts, [Vector2(-0.02, 0.055), Vector2(0.022, 0.055), Vector2(0.025, -0.05), Vector2(0.021, -0.057), Vector2(-0.02, -0.057), Vector2(-0.024, -0.05), Vector2(-0.023, 0.02)],
		0.027, gpos, fm, ga, "", 0.004)
	_p(parts, [Vector2(-0.017, 0.043), Vector2(0.019, 0.043), Vector2(0.021, -0.046), Vector2(-0.019, -0.046), Vector2(-0.021, 0.0)], 0.033, gpos, gm, ga, "", 0.0055)
	for yy in [0.03, -0.036]:
		_c(parts, 0.0028, 0.0345, gpos + gb * Vector3(0, yy, 0.0), "metal_worn", Vector3(0, 90, 0))
	# Chargeur (dans la crosse, sort par le bas au rechargement).
	var ext: float = p.get("mag_ext", 0.0)
	var mag_top := gpos + gb * Vector3(0, 0.05, 0.002)
	var mag_dir := gb * Vector3.DOWN
	var ml := 0.108 + ext
	_b(parts, Vector3(0.021, ml - 0.006, 0.032), mag_top + mag_dir * (ml * 0.5 - 0.003), "metal_dark", ga, "mag")
	_b(parts, Vector3(0.026, 0.007, 0.04), mag_top + mag_dir * (ml - 0.001), "metal_dark", ga, "mag")
	if ext > 0.0:
		_b(parts, Vector3(0.025, ext, 0.036), mag_top + mag_dir * (ml - ext * 0.5 - 0.004), "polymer", ga, "mag")
	return {"parts": parts, "info": {"grip_angle": ga, "slide_travel": 0.028, "mag_len": ml}, "anchors": {
		"muzzle": Vector3(0, 0.035, front - 0.005), "sight": Vector3(0, line, 0.02),
		"front": Vector3(0, line, front + 0.02), "ads": Vector3(0, 0, 0.4),
		"eject": Vector3(0.018, slide_top - 0.004, -0.04),
		"grip": Vector3(0, -0.06, 0.03), "support": Vector3(-0.02, -0.07, 0.02),
		"hold": Vector3(-0.06, 0.15, 0.35), "hold_rot": Vector3(0.0, 0.32, -0.08),
		"pivot_mag": mag_top, "mag_dir": mag_dir}}


static func _revolver(p: Dictionary) -> Dictionary:
	var parts := []
	var bl: float = p.get("barrel", 0.16)
	# Carcasse : pont supérieur, fenêtre du barillet, queue de la crosse.
	_p(parts, [Vector2(-0.058, 0.002), Vector2(0.018, 0.002), Vector2(0.03, 0.012), Vector2(0.045, 0.036), Vector2(0.04, 0.056), Vector2(0.026, 0.062),
		Vector2(-0.052, 0.062), Vector2(-0.06, 0.054), Vector2(-0.062, 0.02)], 0.024, Vector3.ZERO, "metal", 0.0, "", 0.004)
	# Barillet cannelé (bascule à gauche au rechargement), chambres à l'avant.
	var cyl_c := Vector3(0, 0.03, -0.02)
	var cp := Vector3(-0.012, 0.008, -0.02)
	_l(parts, [Vector2(-0.025, 0.024), Vector2(-0.022, 0.0285), Vector2(0.021, 0.0285), Vector2(0.025, 0.025)], cyl_c, "metal_worn", 0.0, "cyl")
	for k in 6:
		var a := deg_to_rad(30.0 + k * 60.0)
		_b(parts, Vector3(0.008, 0.005, 0.03), cyl_c + Vector3(cos(a), sin(a), 0) * 0.0272, "metal_dark", Vector3(0, 0, rad_to_deg(a) + 90.0), "cyl")
		_c(parts, 0.0045, 0.003, cyl_c + Vector3(cos(a + PI / 6.0), sin(a + PI / 6.0), 0) * 0.0165 + Vector3(0, 0, -0.025), "bore", 0.0, "cyl")
	_c(parts, 0.006, 0.012, cyl_c + Vector3(0, 0, -0.031), "metal_dark", 0.0, "cyl")
	# Canon rond, tenon plein de l'extracteur dessous, bande ventilée dessus.
	_barrel(parts, 0.0105, -0.055 - bl, -0.045, 0.045, "metal")
	_x(parts, _sec(0.019, 0.02, 0.028, 0.004, 0.009), -0.05 - bl, -0.044, "metal")
	_b(parts, Vector3(0.0095, 0.004, bl + 0.02), Vector3(0, 0.065, -0.045 - bl * 0.5), "metal")
	var n := int(bl / 0.03)
	for i in n + 1:
		_b(parts, Vector3(0.008, 0.006, 0.008), Vector3(0, 0.06, -0.05 - i * bl / n), "metal")
	# Guidon à rampe au bout de la bande, cran de mire sur le haut de la carcasse.
	var line := 0.079
	_post(parts, -0.05 - bl, 0.067, line, 0.005)
	_notch(parts, 0.0, 0.062, line, 0.024, 0.009)
	# Chien, pontet, détente, crosse en bois (angle marqué).
	_p(parts, [Vector2(0.0, 0.0), Vector2(0.004, 0.018), Vector2(0.016, 0.026), Vector2(0.018, 0.018), Vector2(0.008, 0.0)], 0.008,
		Vector3(0, 0.045, 0.03), "metal_dark", -10.0, "", 0.0015)
	_guard(parts, 0.008, -0.045, 0.004, 0.028)
	_trigger(parts, -0.012, 0.004)
	var ga := -22.0
	_p(parts, [Vector2(-0.02, 0.05), Vector2(0.024, 0.05), Vector2(0.028, -0.035), Vector2(0.018, -0.063), Vector2(-0.012, -0.063), Vector2(-0.022, -0.046),
		Vector2(-0.018, -0.03), Vector2(-0.023, -0.016), Vector2(-0.02, 0.01)], 0.035, Vector3(0, -0.05, 0.04), "wood", ga, "", 0.007)
	_c(parts, 0.004, 0.036, Vector3(0, -0.035, 0.035), "metal_worn", Vector3(0, 90, 0))
	return {"parts": parts, "info": {"grip_angle": ga}, "anchors": {
		"muzzle": Vector3(0, 0.045, -0.06 - bl), "sight": Vector3(0, line, 0.0),
		"front": Vector3(0, line, -0.05 - bl), "ads": Vector3(0, 0, 0.4),
		"grip": Vector3(0, -0.065, 0.05), "support": Vector3(-0.02, -0.08, 0.04),
		"hold": Vector3(-0.06, 0.15, 0.33), "hold_rot": Vector3(0.0, 0.32, -0.08),
		"pivot_cyl": cp, "pivot_mag": cyl_c + Vector3(0, 0, 0.03), "mag_dir": Vector3(0, 0, 1)}}


## Arme longue générique (PM, fusil, mitrailleuse, sniper).
##   rec [avant, arrière, largeur] du boîtier (z), hg [longueur, hauteur, matériau] du garde-main
##   barrel [longueur, rayon], mag [type, z, longueur, inclinaison ou courbure], stock [type, longueur, matériau]
static func _long(p: Dictionary) -> Dictionary:
	var parts := []
	var y := 0.03
	var rec: Array = p.rec
	var rf: float = rec[0]
	var rb: float = rec[1]
	var rw: float = rec[2]
	var rh: float = p.get("rec_h", 0.07)
	var rm: String = p.get("rec_mat", "metal")
	var top := y + rh * 0.5
	var bottom := y - rh * 0.5
	var top_kind: String = p.get("top", "iron")
	var bullpup: bool = p.get("bullpup", false)
	var model_info := {"grip_angle": -14.0, "slide_travel": 0.05}
	# ---- Boîtier
	if p.get("round", false):
		# MP40 : tube rond, boîtier inférieur en bakélite, cannelures du tube.
		_l(parts, [Vector2(rf, rh * 0.36), Vector2(rf + 0.004, rh * 0.42), Vector2(rb - 0.004, rh * 0.42), Vector2(rb, rh * 0.38)], Vector3(0, y + 0.005, 0), rm)
		_x(parts, _sec(rw * 0.78, rh * 0.5, y - rh * 0.2, 0.002, 0.008), rf + 0.02, rb, "polymer")
		for i in 5:
			_b(parts, Vector3(rh * 0.86, 0.003, 0.008), Vector3(0, y + 0.005, rb - 0.03 - i * 0.012), "metal_dark")
		_c(parts, rh * 0.3, 0.012, Vector3(0, y + 0.005, rb + 0.004), "metal_dark")
	else:
		var r_top := rw * 0.42 if top_kind == "ak" else (rw * 0.3 if bullpup else 0.008)
		var r_bot := 0.006 if not bullpup else rw * 0.25
		_x(parts, _sec(rw, rh, y, r_top, r_bot), rf, rb, rm, "", 0.004)
		# Arête de couvercle (AK) et rivets ; fenêtre d'éjection à droite.
		if top_kind == "ak":
			_b(parts, Vector3(rw + 0.0016, 0.0025, rb - rf - 0.01), Vector3(0, top - 0.018, (rf + rb) * 0.5), "metal_dark")
			for zz in [rf + 0.03, rb - 0.03, (rf + rb) * 0.5]:
				_c(parts, 0.0028, rw + 0.003, Vector3(0, bottom + 0.012, zz), "metal_worn", Vector3(0, 90, 0))
			# Levier de sûreté (grande plaque sur le flanc droit).
			_p(parts, [Vector2(rb - 0.02, 0.0), Vector2(rb - 0.13, 0.008), Vector2(rb - 0.13, 0.016), Vector2(rb - 0.02, 0.012)], 0.003,
				Vector3(rw * 0.5 + 0.0015, y - 0.004, 0), "metal_worn", 0.0, "", 0.0008)
		if p.get("hk", false):
			# Boîtier en tôle emboutie des HK (nervure latérale).
			_b(parts, Vector3(rw + 0.002, 0.006, rb - rf - 0.03), Vector3(0, y + 0.004, (rf + rb) * 0.5), rm)
	var ez: float = rb - 0.1 if bullpup else rf * 0.35 + rb * 0.65
	_b(parts, Vector3(0.003, 0.014, 0.04), Vector3(rw * 0.5 + 0.0006, y + 0.012, ez), "bore")
	# Fût en bois courant sous le boîtier (M14, L96).
	if p.has("wood_body"):
		_x(parts, _sec(rw + 0.012, 0.05, bottom - 0.005, 0.006, 0.014), rf - 0.01, rb + 0.02, p.wood_body, "", 0.005)
	# ---- Garde-main
	var hg: Array = p.get("hg", [0.0, 0.0, "metal"])
	var hl: float = hg[0]
	var front := rf
	var support := Vector3(0, bottom - 0.02, rf + 0.04)
	if hl > 0.0:
		var hr: float = hg[1] * 0.5
		if p.get("round_hg", false):
			# Garde-main rond nervuré (M16) entre deux bagues.
			var prof := [Vector2(rf - hl, hr * 1.05), Vector2(rf - hl + 0.012, hr * 1.05)]
			var ribs := int((hl - 0.03) / 0.011)
			for i in ribs:
				var z0 := rf - hl + 0.015 + i * 0.011
				prof.append(Vector2(z0, hr * 0.9))
				prof.append(Vector2(z0 + 0.002, hr))
				prof.append(Vector2(z0 + 0.008, hr))
				prof.append(Vector2(z0 + 0.01, hr * 0.9))
			prof.append(Vector2(rf - 0.012, hr * 0.9))
			prof.append(Vector2(rf - 0.01, hr * 1.12))
			prof.append(Vector2(rf, hr * 1.12))
			_l(parts, prof, Vector3(0, y, 0), hg[2])
		else:
			var wood: bool = String(hg[2]).begins_with("wood")
			_x(parts, _sec(rw + 0.006, hg[1], y - 0.004, 0.012 if wood else 0.006, hr * 0.8 if wood else 0.008), rf - hl, rf, hg[2], "", 0.006 if wood else 0.003)
			if not wood:
				# Rainures longitudinales (garde-main polymère des HK, FN FAL).
				for sx in [-1.0, 1.0]:
					for yy in [0.006, -0.012]:
						_b(parts, Vector3(0.002, 0.0035, hl - 0.03), Vector3(sx * (rw * 0.5 + 0.0035), y + yy, rf - hl * 0.5), "bore")
			else:
				# Bague de retenue métallique à l'avant du bois.
				_x(parts, _sec(rw + 0.01, hg[1] + 0.006, y - 0.004, 0.01, hr), rf - hl - 0.008, rf - hl + 0.004, "metal_dark", "", 0.002)
		front = rf - hl
		support = Vector3(0, y - hg[1] * 0.5 - 0.02, rf - hl * 0.55)
	# Garde-main supérieur en bois sur le tube des gaz (AK, M14).
	if (top_kind == "ak" and hl > 0.0) or p.get("upper_wood", false):
		var uw: String = hg[2] if String(hg[2]).begins_with("wood") else "metal_dark"
		_x(parts, _sec(rw * 0.62, 0.022, top - 0.004, 0.009, 0.003), rf - hl * 0.72, rf - 0.004, uw, "", 0.004)
	# Manchon perforé (canon refroidi) : tube sombre et trous.
	if p.get("shroud", false):
		var sl := minf(0.12, maxf(float(p.barrel[0]) * 0.8, 0.06))
		var sz0 := front - sl
		_l(parts, [Vector2(sz0, rh * 0.3), Vector2(sz0 + 0.004, rh * 0.34), Vector2(front, rh * 0.34)], Vector3(0, y + 0.004, 0), "metal_dark")
		for i in int(sl / 0.022):
			_c(parts, 0.004, rh * 0.7, Vector3(0, y + 0.004, sz0 + 0.012 + i * 0.022), "bore", Vector3(0, 90, 0))
	# ---- Canon et bouche
	var bar: Array = p.barrel
	var bl: float = bar[0]
	var br: float = bar[1]
	var by := y + 0.006
	if bl > 0.0:
		_barrel(parts, br, front - bl, front + 0.01, by)
		if bl > 0.12:
			# Bloc des gaz (bague) au deux tiers du canon.
			_l(parts, [Vector2(front - bl * 0.62, br * 1.2), Vector2(front - bl * 0.62 + 0.003, br * 1.75), Vector2(front - bl * 0.62 + 0.017, br * 1.75), Vector2(front - bl * 0.62 + 0.02, br * 1.2)],
				Vector3(0, by, 0), "metal_dark")
	var muzzle_z := front - bl
	match p.get("muzzle", "none"):
		"flash":
			# Cache-flammes à lamelles (« cage à oiseau »).
			var z0 := muzzle_z - 0.05
			_l(parts, [Vector2(z0, br * 1.35), Vector2(z0 + 0.003, br * 1.5), Vector2(muzzle_z - 0.006, br * 1.5), Vector2(muzzle_z, br * 1.25)], Vector3(0, by, 0), "metal_dark")
			for a in [45.0, 135.0, 225.0, 315.0]:
				var ar := deg_to_rad(a)
				_b(parts, Vector3(0.0035, 0.0035, 0.03), Vector3(cos(ar) * br * 1.45, by + sin(ar) * br * 1.45, z0 + 0.02), "bore", Vector3(0, 0, a))
			_c(parts, br * 1.1, 0.004, Vector3(0, by, z0 + 0.0015), "bore")
			muzzle_z = z0
		"brake":
			var z0 := muzzle_z - 0.045
			_l(parts, [Vector2(z0, br * 1.5), Vector2(z0 + 0.004, br * 1.75), Vector2(muzzle_z - 0.004, br * 1.75), Vector2(muzzle_z, br * 1.4)], Vector3(0, by, 0), "metal_dark")
			for i in 3:
				_b(parts, Vector3(br * 3.8, br * 1.4, 0.006), Vector3(0, by, z0 + 0.01 + i * 0.012), "bore")
			_c(parts, br * 0.8, 0.004, Vector3(0, by, z0 + 0.0015), "bore")
			muzzle_z = z0
		"ak":
			# Chambre de détente conique de l'AK74u.
			var z0 := muzzle_z - 0.07
			_l(parts, [Vector2(z0, br * 1.55), Vector2(z0 + 0.004, br * 2.05), Vector2(z0 + 0.03, br * 2.05), Vector2(z0 + 0.052, br * 1.8), Vector2(z0 + 0.056, br * 1.35),
				Vector2(muzzle_z, br * 1.35)], Vector3(0, by, 0), "metal_dark")
			_c(parts, br * 1.3, 0.004, Vector3(0, by, z0 + 0.0015), "bore")
			muzzle_z = z0
	if p.get("barrel_hook", false):
		_p(parts, [Vector2(front - 0.045, bottom - 0.02), Vector2(front - 0.01, bottom - 0.02), Vector2(front, bottom + 0.012), Vector2(front - 0.035, bottom + 0.012)],
			0.012, Vector3.ZERO, "metal_dark", 0.0, "", 0.002)
	# ---- Chargeur (groupe mobile "mag", pivot au puits de chargeur)
	var mag: Array = p.get("mag", ["none"])
	var mz: float = mag[1] if mag.size() > 1 else 0.0
	var ml: float = mag[2] if mag.size() > 2 else 0.15
	var mag_top := Vector3(0, bottom + 0.01, mz)
	var mag_dir := Vector3.DOWN
	match mag[0]:
		"straight":
			var tilt: float = mag[3] if mag.size() > 3 else 6.0
			mag_dir = Basis(Vector3.RIGHT, deg_to_rad(tilt)) * Vector3.DOWN
			var c := mag_top + mag_dir * ml * 0.5
			_p(parts, [Vector2(-0.027, ml * 0.5), Vector2(0.027, ml * 0.5), Vector2(0.027, -ml * 0.5), Vector2(-0.027, -ml * 0.5)], 0.028, c, "metal_dark", tilt, "mag", 0.004)
			# Nervures et semelle.
			for sx in [-1.0, 1.0]:
				_b(parts, Vector3(0.002, ml * 0.8, 0.01), c + Vector3(sx * 0.0145, 0, 0), "metal_dark", tilt, "mag")
			_b(parts, Vector3(0.032, 0.008, 0.06), mag_top + mag_dir * (ml + 0.002), "metal_dark", tilt, "mag")
			model_info["mag_len"] = ml
		"curved":
			var curve: float = mag[3] if mag.size() > 3 else 30.0
			var pts := _curved_pts(Vector2.ZERO, ml, 0.056, curve)
			_p(parts, pts, 0.028, mag_top, "metal_dark", 0.0, "mag", 0.0045)
			# Nervures de renfort (chargeurs d'AK) et semelle au bout de l'arc.
			_p(parts, _curved_pts(Vector2(-0.01, -0.01), ml * 0.8, 0.012, curve * 0.8), 0.031, mag_top, "metal_dark", 0.0, "mag", 0.001)
			var end := Vector2.ZERO
			for s in 8:
				var a := deg_to_rad(curve) * (float(s) + 0.5) / 8.0
				end += Vector2(-sin(a), -cos(a)) * ml / 8.0
			_b(parts, Vector3(0.032, 0.008, 0.058), mag_top + Vector3(0, end.y, end.x), "metal_dark", curve, "mag")
			mag_dir = Vector3(0, end.y, end.x).normalized()
			model_info["mag_len"] = ml
		"box":
			# Boîtier de bande (HK21), bande de cartouches jusqu'au boîtier.
			_p(parts, WeaponMesh.round_rect(0.13, ml, 0.012), 0.1, Vector3(0.03, bottom - ml * 0.5 + 0.01, mz), "olive", 0.0, "mag", 0.006)
			_b(parts, Vector3(0.102, 0.012, 0.132), Vector3(0.03, bottom + 0.004, mz), "metal_dark", 0.0, "mag")
			for i in 4:
				_c(parts, 0.006, 0.035, Vector3(0.02 - i * 0.0, bottom + 0.012 + i * 0.006, mz - 0.03 + i * 0.012), "brass", Vector3(0, 90, 0), "mag")
			model_info["mag_len"] = ml
		"drum":
			var dc := Vector3(0, bottom - ml + 0.01, mz)
			var prof := [Vector2(-0.032, ml * 0.4), Vector2(-0.03, ml * 0.97), Vector2(-0.026, ml), Vector2(0.026, ml), Vector2(0.03, ml * 0.97), Vector2(0.032, ml * 0.4)]
			_l(parts, prof, dc, "metal_dark", Vector3(0, 90, 0), "mag")
			_c(parts, ml * 0.35, 0.068, dc, "metal", Vector3(0, 90, 0), "mag")
			for a in 8:
				var ar := TAU * a / 8.0
				_b(parts, Vector3(0.066, 0.004, 0.006), dc + Vector3(0, sin(ar), cos(ar)) * ml * 0.7, "metal_dark", Vector3(-rad_to_deg(ar), 0, 0), "mag")
			_b(parts, Vector3(0.026, 0.04, 0.05), Vector3(0, bottom - 0.012, mz), "metal_dark", 0.0, "mag")
			model_info["mag_len"] = ml * 2.0
		"grip":
			# Chargeur logé dans la poignée : dépasse sous la crosse de pistolet.
			var gb := Basis(Vector3.RIGHT, deg_to_rad(-14.0))
			mag_top = Vector3(0, -0.02, 0.058)
			mag_dir = gb * Vector3.DOWN
			_b(parts, Vector3(0.024, ml + 0.08, 0.034), mag_top + mag_dir * (ml + 0.08) * 0.5, "metal_dark", -14.0, "mag")
			_b(parts, Vector3(0.03, 0.008, 0.042), mag_top + mag_dir * (ml + 0.084), "metal_dark", -14.0, "mag")
			model_info["mag_len"] = ml + 0.08
	# ---- Poignée
	var gz := 0.05
	var grip := Vector3(0, -0.06, gz)
	match p.get("grip", "polymer"):
		"none":
			# Crosse « à poignée de fusil » : le poignet de la crosse sert de poignée.
			var stk: Array = p.get("stock", ["none"])
			var wrist: String = p.get("wood_body", stk[2] if stk.size() > 2 else "wood")
			_p(parts, [Vector2(rb - 0.1, bottom - 0.01), Vector2(rb + 0.02, bottom - 0.01), Vector2(rb + 0.06, bottom - 0.025), Vector2(rb + 0.03, bottom - 0.075),
				Vector2(rb - 0.01, bottom - 0.078), Vector2(rb - 0.03, bottom - 0.055), Vector2(rb - 0.07, bottom - 0.03)], 0.042, Vector3.ZERO, wrist, 0.0, "", 0.008)
			_guard(parts, rb - 0.055, rb - 0.13, bottom - 0.008, 0.028)
			_trigger(parts, rb - 0.1, bottom - 0.008)
			grip = Vector3(0, bottom - 0.05, rb - 0.02)
			model_info["grip_angle"] = -30.0
		var gm:
			_pistol_grip(parts, gm, gz, -14.0, bottom)
	if p.get("front_grip", false):
		# Poignée avant verticale (révolution), évasée en bas.
		_l(parts, [Vector2(0.0, 0.014), Vector2(0.07, 0.016), Vector2(0.08, 0.019), Vector2(0.088, 0.019), Vector2(0.092, 0.012)],
			Vector3(0, bottom + 0.002, front + 0.04), "polymer", Vector3(98, 0, 0))
		support = Vector3(0, bottom - 0.07, front + 0.04)
	if p.get("bipod", false):
		# Bipied replié le long du canon : collier, deux jambes, patins.
		var bz := front - bl * 0.35
		_l(parts, [Vector2(bz - 0.008, br * 1.9), Vector2(bz + 0.008, br * 1.9)], Vector3(0, by, 0), "metal_dark")
		for x in [-0.013, 0.013]:
			_c(parts, 0.0035, 0.19, Vector3(x, by - 0.018, bz + 0.1), "metal_dark", 4.0)
			_b(parts, Vector3(0.008, 0.01, 0.018), Vector3(x, by - 0.025, bz + 0.19), "metal_dark", 4.0)
	# ---- Levier d'armement (groupe "slide" : tiré en arrière au rechargement)
	var charge: String = p.get("charge", "right")
	if p.get("bolt", false):
		# Culasse à verrou (L96) : levier coudé et boule, tourne puis recule.
		var bp := Vector3(0.0, top - 0.008, rb - 0.04)
		_c(parts, 0.009, 0.06, bp + Vector3(0, 0, 0.005), "metal_dark", 0.0, "slide")
		_c(parts, 0.0035, 0.05, bp + Vector3(0.028, -0.004, 0.0), "metal_dark", Vector3(0, 90, -10), "slide")
		_l(parts, [Vector2(-0.011, 0.0), Vector2(-0.008, 0.009), Vector2(0.008, 0.009), Vector2(0.011, 0.0)], bp + Vector3(0.056, -0.009, 0.0), "metal_dark", Vector3(0, 90, 0), "slide")
		model_info["pivot_slide"] = bp
		model_info["slide_travel"] = 0.07
		model_info["bolt"] = true
	else:
		match charge:
			"right", "left":
				var sx := 1.0 if charge == "right" else -1.0
				var cp := Vector3(sx * (rw * 0.5 + 0.004), y + 0.012 if top_kind != "ak" else y + 0.008, rb - 0.05 if top_kind == "ak" else rf + (rb - rf) * 0.3)
				_b(parts, Vector3(0.008, 0.008, 0.03), cp, "metal_dark", 0.0, "slide")
				_l(parts, [Vector2(-0.006, 0.0), Vector2(-0.004, 0.006), Vector2(0.004, 0.006), Vector2(0.006, 0.0)], cp + Vector3(sx * 0.012, 0, -0.01), "metal_dark", Vector3(0, 90, 0), "slide")
				model_info["pivot_slide"] = cp
			"left_top":
				# Levier HK dans son tube au-dessus du garde-main, à gauche.
				var cp := Vector3(-0.02, top - 0.004, rf + 0.03)
				_c(parts, 0.006, 0.06, Vector3(-0.012, top - 0.004, rf + 0.02), "metal_dark")
				_b(parts, Vector3(0.024, 0.008, 0.008), cp, "metal_dark", Vector3(0, 30, 0), "slide")
				model_info["pivot_slide"] = cp
			"top":
				var cp := Vector3(0, top + 0.004, rb - 0.03)
				_b(parts, Vector3(0.03, 0.008, 0.02), cp, "metal_dark", 0.0, "slide")
				model_info["pivot_slide"] = cp
	# ---- Crosse
	var st: Array = p.get("stock", ["none"])
	var sl: float = st[1] if st.size() > 1 else 0.25
	var sm: String = st[2] if st.size() > 2 else "polymer"
	match st[0]:
		"solid":
			# Crosse pleine effilée (M16, FN FAL), plaque de couche en caoutchouc.
			_p(parts, [Vector2(rb - 0.005, y + 0.024), Vector2(rb + sl, y + 0.028), Vector2(rb + sl, y - 0.085), Vector2(rb + sl * 0.45, y - 0.052),
				Vector2(rb + 0.02, y - 0.032), Vector2(rb - 0.005, y - 0.03)], 0.044, Vector3.ZERO, sm, 0.0, "", 0.009)
			_p(parts, [Vector2(0.0, y + 0.03), Vector2(0.014, y + 0.03), Vector2(0.014, y - 0.088), Vector2(0.0, y - 0.088)], 0.046, Vector3(0, 0, rb + sl - 0.002), "polymer", 0.0, "", 0.006)
		"rifle":
			# Crosse de fusil en bois (M14, RPK) : busc, poignet, plaque de couche.
			_p(parts, [Vector2(rb - 0.012, y + 0.006), Vector2(rb + sl + 0.05, y - 0.016), Vector2(rb + sl + 0.055, y - 0.128), Vector2(rb + sl * 0.55, y - 0.098),
				Vector2(rb + 0.07, y - 0.068), Vector2(rb + 0.04, y - 0.05), Vector2(rb - 0.012, y - 0.03)], 0.044, Vector3.ZERO, sm, 0.0, "", 0.006)
			_p(parts, [Vector2(0.0, y - 0.014), Vector2(0.008, y - 0.014), Vector2(0.013, y - 0.131), Vector2(0.005, y - 0.131)], 0.046, Vector3(0, 0, rb + sl + 0.05), "metal_dark", 0.0, "", 0.003)
		"thumbhole":
			# Crosse squelette (Dragunov, L96) : busc, sabot, montant arrière.
			_p(parts, [Vector2(rb - 0.01, y + 0.02), Vector2(rb + sl, y + 0.02), Vector2(rb + sl, y - 0.02), Vector2(rb + 0.02, y - 0.02)], 0.044, Vector3.ZERO, sm, 0.0, "", 0.008)
			_p(parts, [Vector2(rb + sl * 0.4, y - 0.085), Vector2(rb + sl, y - 0.095), Vector2(rb + sl, y - 0.115), Vector2(rb + sl * 0.45, y - 0.105)], 0.04, Vector3.ZERO, sm, 0.0, "", 0.007)
			_p(parts, [Vector2(rb + sl - 0.045, y + 0.02), Vector2(rb + sl, y + 0.024), Vector2(rb + sl + 0.005, y - 0.118), Vector2(rb + sl - 0.04, y - 0.11)], 0.044, Vector3.ZERO, sm, 0.0, "", 0.008)
			_b(parts, Vector3(0.046, 0.14, 0.012), Vector3(0, y - 0.046, rb + sl + 0.006), "polymer", -2.0)
		"tube":
			_l(parts, [Vector2(rb, 0.014), Vector2(rb + sl - 0.05, 0.014)], Vector3(0, y, 0), "metal_dark")
			_p(parts, [Vector2(-0.04, 0.035), Vector2(0.03, 0.035), Vector2(0.035, -0.06), Vector2(-0.01, -0.045), Vector2(-0.04, 0.0)], 0.042, Vector3(0, y - 0.01, rb + sl - 0.04), "polymer", 0.0, "", 0.007)
		"wire":
			for yy in [0.02, -0.04]:
				_c(parts, 0.005, sl, Vector3(0, y + yy, rb + sl * 0.5), "metal_dark", 6.0 if yy < 0 else 0.0)
			_p(parts, WeaponMesh.round_rect(0.02, 0.1, 0.008), 0.04, Vector3(0, y - 0.02, rb + sl), "metal_dark", 0.0, "", 0.004)
		"folded_side":
			# Crosse repliée le long du flanc gauche (AK74u) : deux bras, plaque.
			var x := -(rw * 0.5 + 0.008)
			_b(parts, Vector3(0.008, 0.01, sl), Vector3(x, y + 0.014, rb - sl * 0.5 + 0.02), "metal_dark")
			_b(parts, Vector3(0.008, 0.01, sl * 0.9), Vector3(x, y - 0.02, rb - sl * 0.45 + 0.02), "metal_dark")
			_p(parts, [Vector2(-0.012, 0.028), Vector2(0.012, 0.028), Vector2(0.014, -0.05), Vector2(-0.01, -0.05)], 0.012, Vector3(x, y - 0.005, rb - sl + 0.02), "metal_dark", 0.0, "", 0.003)
			_c(parts, 0.009, 0.03, Vector3(0, y, rb + 0.012), "metal_dark", Vector3(0, 90, 0))
		"wire_folded":
			for sx in [-1.0, 1.0]:
				_c(parts, 0.004, sl, Vector3(sx * 0.02, top + 0.005, rb - sl * 0.5), "metal_dark")
			_p(parts, WeaponMesh.round_rect(0.03, 0.012, 0.005), 0.05, Vector3(0, top + 0.005, rb + 0.01), "metal_dark", 0.0, "", 0.003)
		"under_folded":
			# MP40 : bras de crosse replié sous le boîtier, plaque derrière la poignée.
			for sx in [-1.0, 1.0]:
				_c(parts, 0.005, sl, Vector3(sx * 0.018, bottom - 0.006, rb - sl * 0.5), "metal_dark")
			_p(parts, WeaponMesh.round_rect(0.012, 0.035, 0.005), 0.05, Vector3(0, bottom - 0.02, rb + 0.005), "metal_dark", 0.0, "", 0.003)
		"top_folded":
			_c(parts, 0.005, sl, Vector3(0, top + 0.008, rb - sl * 0.5), "metal_dark")
			_b(parts, Vector3(0.012, 0.035, 0.012), Vector3(0, top + 0.0, rb - sl), "metal_dark")
			_b(parts, Vector3(0.04, 0.02, 0.02), Vector3(0, top + 0.005, rb + 0.005), "metal_dark")
	if bullpup:
		# Plaque de couche au bout du boîtier.
		_p(parts, WeaponMesh.round_rect(0.03, rh + 0.03, 0.01), rw + 0.006, Vector3(0, y - 0.012, rb + 0.01), "polymer", 0.0, "", 0.008)
	# ---- Dessus : organes de visée. `line` : hauteur de la ligne de mire ;
	# `rear_z` / `front_z` : cran (ou œilleton, oculaire) et guidon (objectif).
	var line := top + 0.024
	var rear_z := rb - 0.04
	var front_z := muzzle_z + 0.03
	var eye := 0.3
	match top_kind:
		"iron":
			_notch(parts, rear_z, top, line)
			_post(parts, front_z, by + br, line, 0.005, true)
		"ak":
			# Hausse à planchette à l'avant du couvercle, guidon à tunnel sur le bloc avant.
			rear_z = rf + 0.05
			line = top + 0.03
			front_z = muzzle_z + 0.09
			_p(parts, [Vector2(-0.03, 0.0), Vector2(0.03, 0.0), Vector2(0.03, 0.012), Vector2(-0.02, 0.014)], rw * 0.7, Vector3(0, top - 0.002, rear_z + 0.01), rm, 0.0, "", 0.003)
			_notch(parts, rear_z, top, line, 0.032, 0.01)
			_p(parts, [Vector2(-0.012, 0.0), Vector2(0.014, 0.0), Vector2(0.006, 0.016), Vector2(-0.008, 0.016)], 0.02, Vector3(0, by + br * 0.4, front_z), "metal_dark", 0.0, "", 0.003)
			_post(parts, front_z, by + br + 0.012, line, 0.005, true)
			eye = 0.34
		"drum_sight":
			# MP5K : tambour de dioptre à l'arrière, guidon à tunnel.
			line = top + 0.024
			rear_z = rb - 0.03
			front_z = rf + 0.02
			_l(parts, [Vector2(-0.012, 0.012), Vector2(-0.01, 0.014), Vector2(0.01, 0.014), Vector2(0.012, 0.012)], Vector3(0, line - 0.012, rear_z + 0.012), "metal_dark", Vector3(0, 90, 0))
			_aperture(parts, rear_z, top, line, 0.01, 0.022)
			_post(parts, front_z, top, line, 0.005, true)
			eye = 0.16
		"handle", "handle_low":
			var hh := 0.04 if p.top == "handle" else 0.022
			var hz0 := rb - 0.03
			var hz1: float = rf + 0.05 if p.top == "handle" else rb - 0.1
			# Poignée de transport en pont (évidée), montants arrondis.
			var ht := top + hh + 0.008
			_p(parts, [Vector2(hz1 - 0.016, top), Vector2(hz1 - 0.006, ht), Vector2(hz0 + 0.012, ht), Vector2(hz0 + 0.014, top), Vector2(hz0 - 0.006, top),
				Vector2(hz0 - 0.006, ht - 0.014), Vector2(hz1 + 0.014, ht - 0.014), Vector2(hz1 + 0.006, top)], 0.022, Vector3.ZERO, rm, 0.0, "", 0.004)
			# Œilleton sur l'arrière de la poignée de transport, entre deux oreilles.
			line = top + hh + 0.022
			rear_z = hz0
			_aperture(parts, rear_z, ht, line, 0.011, 0.02)
			if p.top == "handle":
				for sx in [-1.0, 1.0]:
					_b(parts, Vector3(0.004, 0.02, 0.018), Vector3(sx * 0.0125, ht + 0.009, rear_z + 0.002), rm)
			# Guidon (triangulaire sur M16) : embase sur le canon, lame jusqu'à la ligne.
			var tri: bool = p.get("front_post", false)
			front_z = front - bl * 0.3 if tri else muzzle_z + 0.04
			var base_h := maxf(line - 0.014 - by, 0.01)
			if tri:
				_p(parts, [Vector2(-0.014, -base_h * 0.5 - 0.008), Vector2(0.03, -base_h * 0.5 - 0.008), Vector2(0.006, base_h * 0.5), Vector2(-0.008, base_h * 0.5)], 0.014,
					Vector3(0, line - 0.014 - base_h * 0.5, front_z), "polymer", 0.0, "", 0.003)
			else:
				_b(parts, Vector3(0.012, base_h, 0.02), Vector3(0, line - 0.014 - base_h * 0.5, front_z), "metal_dark")
			_post(parts, front_z, line - 0.014, line, 0.005, true)
			eye = 0.15
		"famas":
			# Longue poignée de transport de la bouche à l'arrière.
			var bar_y := top + 0.06
			_x(parts, _sec(0.024, 0.02, bar_y, 0.008, 0.004), rf + 0.01, rb - 0.03, "polymer", "", 0.004)
			_p(parts, [Vector2(-0.02, -0.03), Vector2(0.02, -0.03), Vector2(0.012, 0.03), Vector2(-0.016, 0.03)], 0.02, Vector3(0, top + 0.03, rf + 0.03), "polymer", 0.0, "", 0.005)
			_p(parts, [Vector2(-0.02, -0.03), Vector2(0.03, -0.03), Vector2(0.02, 0.03), Vector2(-0.02, 0.03)], 0.02, Vector3(0, top + 0.03, rb - 0.06), "polymer", 0.0, "", 0.005)
			line = bar_y + 0.024
			rear_z = rb - 0.06
			front_z = rf + 0.03
			_aperture(parts, rear_z, bar_y + 0.009, line, 0.011, 0.02)
			_post(parts, front_z, bar_y + 0.009, line, 0.005, true)
			eye = 0.15
		"scope", "scope_short":
			var slen := 0.3 if p.top == "scope" else 0.18
			var sy := top + 0.045
			var sz := rb - 0.05 - slen * 0.5 + (0.08 if p.top == "scope_short" else 0.0)
			var z0 := sz - slen * 0.5
			var z1 := sz + slen * 0.5
			# Lunette : objectif évasé, tube, tourelles, oculaire, colliers.
			_l(parts, [Vector2(z0, 0.024), Vector2(z0 + 0.004, 0.028), Vector2(z0 + 0.045, 0.028), Vector2(z0 + 0.075, 0.019), Vector2(z1 - 0.06, 0.019),
				Vector2(z1 - 0.045, 0.023), Vector2(z1 - 0.004, 0.025), Vector2(z1, 0.021)], Vector3(0, sy, 0), "metal_dark")
			_c(parts, 0.021, 0.004, Vector3(0, sy, z0 - 0.001), "glass")
			_c(parts, 0.017, 0.004, Vector3(0, sy, z1 + 0.001), "glass")
			var tz := z0 + slen * 0.48
			_c(parts, 0.009, 0.016, Vector3(0, sy + 0.024, tz), "metal_dark", Vector3(90, 0, 0))
			_c(parts, 0.009, 0.016, Vector3(0.024, sy, tz), "metal_dark", Vector3(0, 90, 0))
			for kz in [sz - slen * 0.25, sz + slen * 0.25]:
				_l(parts, [Vector2(kz - 0.007, 0.022), Vector2(kz + 0.007, 0.022)], Vector3(0, sy, 0), "metal_dark")
				_p(parts, [Vector2(-0.012, 0.0), Vector2(0.012, 0.0), Vector2(0.008, sy - top - 0.02), Vector2(-0.008, sy - top - 0.02)], 0.014, Vector3(0, top - 0.001, kz), "metal_dark", 0.0, "", 0.002)
			line = sy
			rear_z = z1
			front_z = z0
			eye = 0.07
		"g11":
			# Poignée-lunette sur toute la longueur.
			_x(parts, _sec(0.032, 0.032, top + 0.035, 0.012, 0.006), (rf + rb) * 0.5 - 0.17, (rf + rb) * 0.5 + 0.17, "polymer", "", 0.006)
			_p(parts, [Vector2(-0.02, -0.02), Vector2(0.02, -0.02), Vector2(0.015, 0.02), Vector2(-0.015, 0.02)], 0.03, Vector3(0, top + 0.01, rf + 0.1), "polymer", 0.0, "", 0.006)
			_c(parts, 0.012, 0.006, Vector3(0, top + 0.035, (rf + rb) * 0.5 + 0.17), "glass")
			line = top + 0.035
			rear_z = (rf + rb) * 0.5 + 0.17
			front_z = (rf + rb) * 0.5 - 0.17
			eye = 0.07
	var anchors := {
		"muzzle": Vector3(0, by, muzzle_z), "sight": Vector3(0, line, rear_z),
		"front": Vector3(0, line, front_z), "ads": Vector3(0, 0, eye),
		"eject": Vector3(rw * 0.5 + 0.004, y + 0.012, ez),
		"grip": grip, "support": support,
		# Bullpup : l'arme est tenue plus en avant (crosse à l'épaule).
		"hold": Vector3(0, 0, -0.14) if bullpup else Vector3.ZERO,
		"pivot_mag": mag_top, "mag_dir": mag_dir}
	if model_info.has("pivot_slide"):
		anchors["pivot_slide"] = model_info.pivot_slide
	return {"parts": parts, "anchors": anchors, "info": model_info}


static func _shotgun(p: Dictionary) -> Dictionary:
	var parts := []
	var L: float = p.get("len", 0.6)
	var y := 0.03
	var front := -0.12 - L
	var barrels: int = p.get("barrels", 1)
	var model_info := {"grip_angle": -18.0}
	# Carcasse aux flancs plats, arrondie sur le dessus, fenêtre d'éjection.
	_x(parts, _sec(0.05, 0.07, y, 0.012, 0.006), -0.1, 0.1, "metal", "", 0.004)
	var muzzle_y := y + 0.015
	var anchors := {}
	if barrels == 2:
		# Canons superposés (Olympia), bande, longuesse en bois, charnière :
		# l'ensemble bascule au rechargement (groupe "barrels").
		var hinge := Vector3(0, y - 0.03, -0.1)
		for yy in [0.02, -0.016]:
			_l(parts, [Vector2(-0.1 - L, 0.016), Vector2(-0.1 - L + 0.003, 0.0172), Vector2(-0.1, 0.0172)], Vector3(0, y + yy, 0), "metal_dark", 0.0, "barrels")
			_c(parts, 0.011, 0.004, Vector3(0, y + yy, -0.1 - L + 0.0015), "bore", 0.0, "barrels")
		_b(parts, Vector3(0.006, 0.006, L), Vector3(0, y + 0.04, -0.1 - L * 0.5), "metal", 0.0, "barrels")
		_b(parts, Vector3(0.012, 0.01, L), Vector3(0, y + 0.002, -0.1 - L * 0.5), "metal_dark", 0.0, "barrels")
		_x(parts, _sec(0.05, 0.042, y - 0.035, 0.008, 0.016), -0.34, -0.12, "wood", "barrels", 0.006)
		_post(parts, front + 0.03, y + 0.043, y + 0.051, 0.009, false, "brass", "barrels")
		# Clé d'ouverture sur le dessus de la carcasse.
		_p(parts, [Vector2(0.0, 0.0), Vector2(0.03, 0.004), Vector2(0.035, 0.012), Vector2(0.0, 0.01)], 0.012, Vector3(0.004, y + 0.035, 0.07), "metal_dark", Vector3(0, -15, 0), "", 0.002)
		muzzle_y = y + 0.02
		anchors["pivot_barrels"] = hinge
	else:
		_barrel(parts, 0.017, -0.1 - L, -0.095, y + 0.015)
		# Tube magasin sous le canon et son bouchon.
		_l(parts, [Vector2(-0.1 - L * 0.8, 0.012), Vector2(-0.1 - L * 0.8 + 0.003, 0.0135), Vector2(-0.1, 0.0135)], Vector3(0, y - 0.02, 0), "metal")
		_c(parts, 0.015, 0.02, Vector3(0, y - 0.02, -0.1 - L * 0.8 - 0.005), "metal_dark")
		if p.get("pump", false):
			# Pompe nervurée (groupe "pump" : recule à chaque réarmement).
			var gm: String = p.get("grip", "wood")
			var pm := "wood" if gm == "wood" else "polymer"
			var prof := [Vector2(-0.38, 0.02), Vector2(-0.375, 0.025)]
			for i in 9:
				var z0 := -0.37 + i * 0.016
				prof.append(Vector2(z0, 0.025))
				prof.append(Vector2(z0 + 0.003, 0.0275))
				prof.append(Vector2(z0 + 0.011, 0.0275))
				prof.append(Vector2(z0 + 0.014, 0.025))
			prof.append(Vector2(-0.22, 0.025))
			prof.append(Vector2(-0.215, 0.02))
			_l(parts, prof, Vector3(0, y - 0.018, 0), pm, 0.0, "pump")
			anchors["pivot_pump"] = Vector3.ZERO
		else:
			_x(parts, _sec(0.048, 0.05, y - 0.015, 0.01, 0.018), -0.27, -0.13, "polymer", "", 0.006)
		if p.get("shroud", false):
			_x(parts, _sec(0.04, 0.022, y + 0.036, 0.009, 0.002), -0.1 - L * 0.7, -0.1, "metal_dark", "", 0.003)
			for i in 6:
				_c(parts, 0.004, 0.042, Vector3(0, y + 0.036, -0.14 - i * 0.045), "bore", Vector3(0, 90, 0))
		muzzle_y = y + 0.015
		# Fenêtre de chargement sous la carcasse.
		_b(parts, Vector3(0.022, 0.004, 0.07), Vector3(0, y - 0.034, -0.02), "bore")
	_b(parts, Vector3(0.003, 0.018, 0.05), Vector3(0.0255, y + 0.012, -0.03), "bore")
	# Bille de guidon au bout du canon (ou de la bande) : ligne de mire au ras
	# du boîtier et de la bande.
	var rib_top := y + 0.043 if barrels == 2 else (y + 0.045 if p.get("shroud", false) else y + 0.032)
	var line := maxf(rib_top, y + 0.035) + 0.008
	if barrels != 2:
		_post(parts, front + 0.03, rib_top, line, 0.009, false, "brass")
	# Crosse et poignée
	match p.get("stock", "none"):
		"wood_light", "wood":
			# Crosse anglaise en bois vernis, poignet fin, talon arrondi.
			var sm: String = p.stock
			_p(parts, [Vector2(0.095, y + 0.03), Vector2(0.43, y - 0.005), Vector2(0.44, y - 0.12), Vector2(0.3, y - 0.085), Vector2(0.16, y - 0.06),
				Vector2(0.11, y - 0.045), Vector2(0.095, y - 0.03)], 0.045, Vector3.ZERO, sm, 0.0, "", 0.006)
			_p(parts, [Vector2(0.0, y - 0.003), Vector2(0.012, y - 0.003), Vector2(0.018, y - 0.124), Vector2(0.006, y - 0.124)], 0.047, Vector3(0, 0, 0.43), "wood_dark", 0.0, "", 0.004)
		"top_folded":
			_c(parts, 0.005, 0.3, Vector3(0, y + 0.05, -0.05), "metal_dark")
			_b(parts, Vector3(0.012, 0.04, 0.012), Vector3(0, y + 0.035, -0.2), "metal_dark")
			_b(parts, Vector3(0.04, 0.02, 0.02), Vector3(0, y + 0.045, 0.1), "metal_dark")
	var grip := Vector3(0, -0.05, 0.1)
	if p.get("grip", "none") != "none":
		_pistol_grip(parts, p.grip, 0.09, -18.0, y - 0.035)
	else:
		_guard(parts, 0.06, -0.01, y - 0.035, 0.028)
		_trigger(parts, 0.02, y - 0.035)
		grip = Vector3(0, y - 0.08, 0.13)
		model_info["grip_angle"] = -35.0
	anchors.merge({
		"muzzle": Vector3(0, muzzle_y, front), "sight": Vector3(0, line, 0.05),
		"front": Vector3(0, line, front + 0.03), "ads": Vector3(0, 0, 0.3),
		"eject": Vector3(0.027, y + 0.01, -0.03),
		"grip": grip, "support": Vector3(0, y - 0.05, -0.3 if barrels == 2 or p.get("pump", false) else -0.2),
		"pivot_mag": Vector3(0, y - 0.035, -0.02), "mag_dir": Vector3(0, -1, 0)})
	return {"parts": parts, "anchors": anchors, "info": model_info}


## China Lake : gros tube, magasin tubulaire à pompe, crosse bois, hausse à échelle.
static func _launcher() -> Dictionary:
	var parts := []
	var y := 0.035
	_x(parts, _sec(0.06, 0.08, y, 0.018, 0.008), -0.1, 0.1, "metal_dark", "", 0.004)
	_l(parts, [Vector2(-0.53, 0.03), Vector2(-0.525, 0.036), Vector2(-0.48, 0.036), Vector2(-0.475, 0.032), Vector2(-0.09, 0.032)], Vector3(0, y + 0.01, 0), "metal_dark")
	_c(parts, 0.024, 0.004, Vector3(0, y + 0.01, -0.531), "bore")
	_l(parts, [Vector2(-0.43, 0.024), Vector2(-0.08, 0.028)], Vector3(0, y - 0.05, 0), "metal")
	# Pompe en bois (groupe "pump").
	_x(parts, _sec(0.07, 0.06, y - 0.05, 0.02, 0.026), -0.36, -0.2, "wood", "pump", 0.008)
	# Hausse à échelle (cran) sur le boîtier, guidon haut au bout du tube.
	var line := y + 0.1
	_b(parts, Vector3(0.036, 0.004, 0.05), Vector3(0, y + 0.042, -0.08), "metal_worn")
	for sx in [-1.0, 1.0]:
		_b(parts, Vector3(0.004, 0.05, 0.006), Vector3(sx * 0.016, y + 0.07, -0.09), "metal_worn", -12.0)
	_notch(parts, -0.09, y + 0.04, line, 0.03, 0.01, "metal_worn")
	_post(parts, -0.49, y + 0.042, line, 0.006, true)
	_p(parts, [Vector2(0.09, y + 0.03), Vector2(0.39, y + 0.0), Vector2(0.4, y - 0.12), Vector2(0.24, y - 0.09), Vector2(0.12, y - 0.07), Vector2(0.09, y - 0.03)],
		0.05, Vector3.ZERO, "wood", 0.0, "", 0.006)
	_p(parts, [Vector2(0.0, y + 0.002), Vector2(0.014, y + 0.002), Vector2(0.018, y - 0.124), Vector2(0.004, y - 0.124)], 0.052, Vector3(0, 0, 0.39), "wood_dark", 0.0, "", 0.004)
	_pistol_grip(parts, "wood_dark", 0.06, -16.0, y - 0.04)
	return {"parts": parts, "info": {"grip_angle": -16.0}, "anchors": {
		"muzzle": Vector3(0, y + 0.01, -0.53), "sight": Vector3(0, line, -0.09),
		"front": Vector3(0, line, -0.49), "ads": Vector3(0, 0, 0.28),
		"grip": Vector3(0, -0.06, 0.06), "support": Vector3(0, y - 0.08, -0.28),
		"pivot_pump": Vector3.ZERO, "pivot_mag": Vector3(0, y - 0.04, -0.02), "mag_dir": Vector3(0, -1, 0)}}


## M72 LAW : tube olive déployé, visée repliable, poignée de mise à feu.
static func _rocket() -> Dictionary:
	var parts := []
	var y := 0.07
	_l(parts, [Vector2(-0.61, 0.04), Vector2(-0.605, 0.044), Vector2(-0.555, 0.044), Vector2(-0.55, 0.04), Vector2(0.25, 0.04), Vector2(0.255, 0.044),
		Vector2(0.3, 0.044), Vector2(0.305, 0.038)], Vector3(0, y, 0), "olive")
	_c(parts, 0.036, 0.004, Vector3(0, y, -0.611), "bore")
	_c(parts, 0.032, 0.006, Vector3(0, y, 0.307), "metal_dark")
	# Bandes d'étiquetage jaunes et renfort.
	_l(parts, [Vector2(-0.52, 0.0405), Vector2(-0.51, 0.0405)], Vector3(0, y, 0), "tan")
	_b(parts, Vector3(0.05, 0.03, 0.12), Vector3(0, y + 0.045, -0.02), "olive")
	# Œilleton arrière et réticule avant (cadre + lame) relevés.
	var line := y + 0.075
	_aperture(parts, 0.06, y + 0.042, line, 0.01, 0.03)
	for sx in [-1.0, 1.0]:
		_b(parts, Vector3(0.004, 0.05, 0.006), Vector3(sx * 0.016, y + 0.067, -0.44), "metal_dark")
	_b(parts, Vector3(0.036, 0.004, 0.006), Vector3(0, y + 0.092, -0.44), "metal_dark")
	_post(parts, -0.44, y + 0.042, line, 0.004)
	_p(parts, [Vector2(-0.025, 0.04), Vector2(0.02, 0.04), Vector2(0.024, -0.04), Vector2(-0.018, -0.042)], 0.03, Vector3(0, y - 0.07, 0.02), "polymer", 10.0, "", 0.007)
	_b(parts, Vector3(0.012, 0.008, 0.9), Vector3(0.036, y + 0.02, -0.15), "tan")
	return {"parts": parts, "info": {"grip_angle": 10.0}, "anchors": {
		"muzzle": Vector3(0, y, -0.61), "sight": Vector3(0, line, 0.06),
		"front": Vector3(0, line, -0.44), "ads": Vector3(0, 0, 0.17),
		"grip": Vector3(0, -0.01, 0.025), "support": Vector3(-0.02, y - 0.05, -0.25)}}


## Couteau : lame à plat dans le plan vertical (tranchant en bas), pointe vers
## -Z, origine au milieu du manche (la main).
static func _knife(p: Dictionary) -> Dictionary:
	var parts := []
	var L: float = p.get("blade", 0.17)
	var w: float = p.get("w", 0.03)
	var bm: String = p.get("blade_mat", "metal_dark")
	var z0 := -0.05
	# Manche (révolution aplatie par les bagues), garde, pommeau.
	var hm: String = p.get("handle", "polymer")
	_p(parts, [Vector2(z0 + 0.01, 0.014), Vector2(0.066, 0.016), Vector2(0.07, 0.0), Vector2(0.066, -0.017), Vector2(0.02, -0.015), Vector2(-0.005, -0.018),
		Vector2(z0 + 0.01, -0.014)], 0.024, Vector3.ZERO, hm, 0.0, "", 0.007)
	for gz in [-0.02, 0.012, 0.044]:
		_b(parts, Vector3(0.026, 0.034, 0.005), Vector3(0, 0, gz), "metal_dark")
	if p.get("guard", false):
		_p(parts, [Vector2(-0.006, 0.03), Vector2(0.006, 0.026), Vector2(0.006, -0.036), Vector2(-0.006, -0.04)], 0.022, Vector3(0, -0.004, z0 + 0.006), "brass", 0.0, "", 0.003)
		_l(parts, [Vector2(-0.012, 0.012), Vector2(-0.008, 0.02), Vector2(0.006, 0.02), Vector2(0.012, 0.01)], Vector3(0, 0, 0.078), "brass")
	else:
		_b(parts, Vector3(0.02, 0.05, 0.01), Vector3(0, -0.004, z0 + 0.006), "metal_dark")
		_l(parts, [Vector2(-0.008, 0.012), Vector2(-0.005, 0.017), Vector2(0.005, 0.017), Vector2(0.008, 0.01)], Vector3(0, 0, 0.072), "metal_dark")
	# Lame : profil complet (dos droit, contre-pointe, ventre courbe, pointe),
	# fil clair le long du tranchant.
	var hw := w * 0.5
	var blade := [Vector2(z0, hw), Vector2(z0 - L * 0.7, hw), Vector2(z0 - L, -hw * 0.25), Vector2(z0 - L * 0.9, -hw * 0.62),
		Vector2(z0 - L * 0.7, -hw * 0.92), Vector2(z0 - L * 0.4, -hw), Vector2(z0, -hw)]
	_p(parts, blade, 0.004, Vector3(0, -0.002, 0), bm, 0.0, "", 0.0012)
	_p(parts, [Vector2(z0 - 0.005, -hw + 0.001), Vector2(z0 - L * 0.65, -hw * 0.88), Vector2(z0 - L * 0.9, -hw * 0.5), Vector2(z0 - L * 0.9, -hw * 0.3),
		Vector2(z0 - L * 0.65, -hw * 0.6), Vector2(z0 - 0.005, -hw * 0.7)], 0.0046, Vector3(0, -0.002, 0), "metal_worn", 0.0, "", 0.0005)
	# Gorge (évidement) le long du dos.
	_b(parts, Vector3(0.0048, 0.003, L * 0.5), Vector3(0, hw * 0.45 - 0.002, z0 - L * 0.3), "metal_dark")
	return {"parts": parts, "anchors": {
		"muzzle": Vector3(0, -w * 0.2, z0 - L), "sight": Vector3(0, 0.03, 0.0),
		"grip": Vector3(0, 0, 0.012), "support": Vector3(0, 0, 0.012)}}
