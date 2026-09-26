class_name WeaponModels
extends RefCounted
## Modèles low-poly des armes, assemblés à partir de primitives.
## Repère : l'arme pointe vers -Z, origine au niveau de la détente.
##
## Chaque arme est décrite par un ARCHÉTYPE paramétré (SPECS) : pistolet,
## revolver, arme longue (PM, fusil, mitrailleuse, sniper), fusil à pompe,
## lance-grenades, lance-roquettes... Le constructeur produit une liste de pièces
## [forme, taille, position, matériau, rotation] où :
##   forme : "box" ou "cyl" (cylindre orienté selon Z, taille.x = rayon, taille.z = longueur)
##   rotation : float (degrés autour de X) ou Vector3 (angles d'Euler en degrés)
## et les points remarquables (bouche du canon, visée, poignée, main d'appui).
##
## Organes de visée : l'ancre "sight" (cran de mire, œilleton, oculaire) et
## l'ancre "front" (guidon, objectif) sont TOUJOURS à la même hauteur : la
## ligne de mire est parallèle à l'axe -Z du modèle. En visée, ViewModel pose
## cette ligne exactement sur l'axe de la caméra (celui des balles), l'œil à
## "ads".z mètres derrière le cran. "eject" : fenêtre d'éjection des douilles.

const MATERIALS := {
	"metal": [Color(0.16, 0.16, 0.17), 0.45, 0.8],
	"metal_dark": [Color(0.07, 0.07, 0.075), 0.5, 0.7],
	"metal_worn": [Color(0.3, 0.29, 0.27), 0.55, 0.7],
	"wood": [Color(0.26, 0.14, 0.07), 0.8, 0.0],
	"wood_dark": [Color(0.14, 0.07, 0.04), 0.85, 0.0],
	"wood_light": [Color(0.38, 0.22, 0.1), 0.75, 0.0],
	"polymer": [Color(0.09, 0.1, 0.09), 0.75, 0.0],
	"olive": [Color(0.2, 0.22, 0.14), 0.8, 0.0],
	"tan": [Color(0.42, 0.36, 0.24), 0.8, 0.0],
	"brass": [Color(0.55, 0.42, 0.18), 0.35, 0.9],
	"glow": [Color(1.0, 0.45, 0.15), 0.3, 0.0],
	"glow_blue": [Color(0.35, 0.75, 1.0), 0.3, 0.0],
	"copper": [Color(0.5, 0.26, 0.14), 0.4, 0.85],
	"glass": [Color(0.1, 0.18, 0.2), 0.1, 0.3],
}

## Description de chaque modèle (id du modèle = id de l'arme par défaut).
const SPECS := {
	# ---------------------------------------------------------------- poing
	"m1911": {"arch": "pistol", "len": 0.21, "slide": "metal_worn", "grip": "wood_dark"},
	"cz75": {"arch": "pistol", "len": 0.2, "slide": "metal_dark", "grip": "polymer", "h": 0.034, "mag_ext": 0.02},
	"python": {"arch": "revolver", "barrel": 0.17},
	# ---------------------------------------------------------------- pistolets-mitrailleurs
	# MP5K : très court, chargeur incurvé, poignée avant, sans crosse.
	"mp5k": {"arch": "long", "rec": [-0.2, 0.08, 0.065], "rec_mat": "metal_dark", "hg": [0.06, 0.055, "polymer"],
		"barrel": [0.05, 0.011], "muzzle": "none", "mag": ["curved", -0.07, 0.17], "stock": ["none"],
		"top": "drum_sight", "front_grip": true},
	# MPL : chargeur dans la poignée, crosse repliée sur le côté.
	"mpl": {"arch": "long", "rec": [-0.22, 0.08, 0.06], "rec_mat": "metal", "hg": [0.0, 0.0, "metal"],
		"barrel": [0.1, 0.012], "muzzle": "none", "mag": ["grip", 0.0, 0.1], "stock": ["folded_side", 0.24],
		"top": "iron", "shroud": true},
	# PM63 : minuscule, culasse apparente, chargeur dans la poignée, poignée avant rabattue.
	"pm63": {"arch": "long", "rec": [-0.16, 0.035, 0.055], "rec_mat": "metal", "hg": [0.0, 0.0, "metal"],
		"barrel": [0.04, 0.01], "muzzle": "brake", "mag": ["grip", 0.0, 0.09], "stock": ["wire_folded", 0.18],
		"top": "iron", "front_grip": true, "grip": "polymer"},
	# MP40 : long tube, chargeur droit vertical devant la détente, crosse repliée dessous.
	"mp40": {"arch": "long", "rec": [-0.24, 0.1, 0.055], "rec_mat": "metal_dark", "hg": [0.06, 0.05, "polymer"],
		"barrel": [0.15, 0.011], "muzzle": "none", "mag": ["straight", -0.1, 0.22, 0.0], "stock": ["under_folded", 0.24],
		"top": "iron", "barrel_hook": true, "round": true},
	"spectre": {"arch": "long", "rec": [-0.2, 0.09, 0.065], "rec_mat": "metal_dark", "hg": [0.12, 0.06, "metal_dark"],
		"barrel": [0.04, 0.012], "muzzle": "none", "mag": ["straight", -0.08, 0.2, 6.0], "stock": ["top_folded", 0.26],
		"top": "iron", "shroud": true},
	# AK74u : garde-main en bois, chargeur incurvé, crosse repliée à gauche, cache-flamme.
	"ak74u": {"arch": "long", "rec": [-0.14, 0.12, 0.07], "rec_mat": "metal_dark", "hg": [0.13, 0.055, "wood"],
		"barrel": [0.06, 0.012], "muzzle": "ak", "mag": ["curved", -0.1, 0.19], "stock": ["folded_side", 0.3],
		"top": "ak", "grip": "wood_dark"},
	# ---------------------------------------------------------------- fusils d'assaut
	"m14": {"arch": "long", "rec": [-0.12, 0.12, 0.05], "rec_mat": "metal", "hg": [0.24, 0.05, "wood"],
		"barrel": [0.24, 0.011], "muzzle": "flash", "mag": ["straight", -0.06, 0.12, 4.0], "stock": ["rifle", 0.3, "wood"],
		"top": "iron", "grip": "none", "wood_body": "wood"},
	# M16 : poignée de transport, garde-main rond, guidon triangulaire, crosse fixe.
	"m16": {"arch": "long", "rec": [-0.2, 0.12, 0.065], "rec_mat": "polymer", "hg": [0.24, 0.055, "polymer"],
		"barrel": [0.2, 0.01], "muzzle": "flash", "mag": ["straight", -0.08, 0.17, 6.0], "stock": ["solid", 0.28, "polymer"],
		"top": "handle", "round_hg": true, "front_post": true},
	"commando": {"arch": "long", "rec": [-0.2, 0.12, 0.065], "rec_mat": "polymer", "hg": [0.16, 0.055, "polymer"],
		"barrel": [0.08, 0.011], "muzzle": "brake", "mag": ["straight", -0.08, 0.17, 6.0], "stock": ["tube", 0.24],
		"top": "handle", "round_hg": true, "front_post": true},
	"galil": {"arch": "long", "rec": [-0.18, 0.12, 0.065], "rec_mat": "metal_dark", "hg": [0.18, 0.055, "wood_light"],
		"barrel": [0.16, 0.011], "muzzle": "flash", "mag": ["curved", -0.1, 0.2], "stock": ["wire", 0.28],
		"top": "ak", "bipod": true},
	# FAMAS : bullpup, longue poignée de transport sur toute la longueur.
	"famas": {"arch": "long", "rec": [-0.3, 0.3, 0.07], "rec_mat": "polymer", "hg": [0.0, 0.0, "polymer"],
		"barrel": [0.14, 0.011], "muzzle": "flash", "mag": ["straight", 0.16, 0.14, 4.0], "stock": ["none"],
		"top": "famas", "bullpup": true},
	# AUG : bullpup vert, lunette intégrée, poignée avant verticale.
	"aug": {"arch": "long", "rec": [-0.24, 0.32, 0.075], "rec_mat": "olive", "hg": [0.0, 0.0, "olive"],
		"barrel": [0.2, 0.011], "muzzle": "flash", "mag": ["straight", 0.16, 0.15, 4.0], "stock": ["none"],
		"top": "scope_short", "bullpup": true, "front_grip": true, "rec_h": 0.085},
	# G11 : un bloc sans aspérité, poignée-lunette sur le dessus.
	"g11": {"arch": "long", "rec": [-0.4, 0.3, 0.07], "rec_mat": "polymer", "hg": [0.0, 0.0, "polymer"],
		"barrel": [0.0, 0.01], "muzzle": "none", "mag": ["none"], "stock": ["none"],
		"top": "g11", "bullpup": true, "rec_h": 0.13},
	"fnfal": {"arch": "long", "rec": [-0.2, 0.12, 0.06], "rec_mat": "metal_dark", "hg": [0.22, 0.06, "polymer"],
		"barrel": [0.2, 0.011], "muzzle": "flash", "mag": ["straight", -0.09, 0.14, 4.0], "stock": ["solid", 0.3, "polymer"],
		"top": "handle_low"},
	# ---------------------------------------------------------------- mitrailleuses
	# HK21 : gros boîtier de bande sous l'arme, bipied, canon à manchon perforé.
	"hk21": {"arch": "long", "rec": [-0.26, 0.12, 0.07], "rec_mat": "metal", "hg": [0.2, 0.06, "polymer"],
		"barrel": [0.3, 0.014], "muzzle": "flash", "mag": ["box", -0.1, 0.13], "stock": ["solid", 0.28, "polymer"],
		"top": "iron", "bipod": true, "shroud": true, "rec_h": 0.09},
	# RPK : AK allongée à tambour, crosse bois, bipied.
	"rpk": {"arch": "long", "rec": [-0.18, 0.12, 0.07], "rec_mat": "metal_dark", "hg": [0.16, 0.055, "wood"],
		"barrel": [0.32, 0.013], "muzzle": "flash", "mag": ["drum", -0.1, 0.08], "stock": ["rifle", 0.3, "wood"],
		"top": "ak", "grip": "wood_dark", "bipod": true},
	# ---------------------------------------------------------------- précision
	"dragunov": {"arch": "long", "rec": [-0.18, 0.1, 0.055], "rec_mat": "metal_dark", "hg": [0.22, 0.06, "wood"],
		"barrel": [0.36, 0.01], "muzzle": "flash", "mag": ["curved", -0.07, 0.13], "stock": ["thumbhole", 0.32, "wood"],
		"top": "scope", "grip": "none"},
	"l96a1": {"arch": "long", "rec": [-0.2, 0.1, 0.06], "rec_mat": "metal", "hg": [0.22, 0.07, "olive"],
		"barrel": [0.4, 0.014], "muzzle": "brake", "mag": ["straight", -0.05, 0.08, 0.0], "stock": ["thumbhole", 0.34, "olive"],
		"top": "scope", "grip": "none", "bipod": true, "bolt": true, "wood_body": "olive"},
	# ---------------------------------------------------------------- fusils à pompe
	"olympia": {"arch": "shotgun", "barrels": 2, "len": 0.66, "stock": "wood_light", "grip": "none"},
	"stakeout": {"arch": "shotgun", "barrels": 1, "len": 0.5, "stock": "none", "pump": true, "grip": "wood"},
	"spas12": {"arch": "shotgun", "barrels": 1, "len": 0.5, "stock": "top_folded", "pump": true, "grip": "polymer", "shroud": true},
	"hs10": {"arch": "shotgun", "barrels": 1, "len": 0.34, "stock": "none", "pump": false, "grip": "polymer"},
	# ---------------------------------------------------------------- explosifs
	"china_lake": {"arch": "launcher"},
	"law": {"arch": "rocket"},
	# ---------------------------------------------------------------- merveille
	"ray": {"arch": "ray"},
	# TONNERRE-7 : gros tambour cylindrique à ailettes, réservoirs latéraux, bouche évasée.
	"thunder": {"arch": "thunder"},
	# ---------------------------------------------------------------- bonus
	# FAUCHEUSE (DEATH MACHINE) : minigun à six canons.
	"death_machine": {"arch": "minigun"},
	# ---------------------------------------------------------------- couteaux (KnifeDB)
	# Couteau de combat : lame noircie, manche en polymère.
	"knife": {"arch": "knife", "blade": 0.17, "w": 0.028, "blade_mat": "metal_dark", "handle": "polymer", "guard": false},
	# Couteau de chasse (Bowie) : longue lame à contre-pointe, garde et pommeau en laiton.
	"bowie": {"arch": "knife", "blade": 0.25, "w": 0.042, "blade_mat": "metal_worn", "handle": "wood", "guard": true},
}

static var _mat_cache: Dictionary = {}
static var _mesh_cache: Dictionary = {}
## model_id -> {"parts": Array, "anchors": Dictionary}
static var _spec_cache: Dictionary = {}


static func material(key: String, viewmodel: bool, pap: bool) -> ShaderMaterial:
	var cache_key := "%s_%s_%s" % [key, viewmodel, pap]
	if _mat_cache.has(cache_key):
		return _mat_cache[cache_key]
	var spec: Array = MATERIALS[key]
	var m := ShaderMaterial.new()
	m.shader = preload("res://assets/shaders/weapon.gdshader")
	m.set_shader_parameter("albedo", spec[0])
	m.set_shader_parameter("roughness", spec[1])
	m.set_shader_parameter("metallic", spec[2])
	m.set_shader_parameter("viewmodel", 1.0 if viewmodel else 0.0)
	m.set_shader_parameter("pap", 1.0 if pap and not key.begins_with("glow") and key != "glass" else 0.0)
	if key.begins_with("glow"):
		m.set_shader_parameter("emission", spec[0])
		m.set_shader_parameter("emission_energy", 3.0)
	_mat_cache[cache_key] = m
	return m


static func _mesh_for(part: Array) -> Mesh:
	var key := var_to_str(part.slice(0, 2))
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var mesh: Mesh
	if part[0] == "cyl":
		var c := CylinderMesh.new()
		c.top_radius = part[1].x
		c.bottom_radius = part[1].x
		c.height = part[1].z
		c.radial_segments = 8
		c.rings = 1
		mesh = c
	else:
		var b := BoxMesh.new()
		b.size = part[1]
		mesh = b
	_mesh_cache[key] = mesh
	return mesh


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
		"knife": out = _knife(p)
		"thunder": out = _thunder()
		"minigun": out = _minigun()
		_: out = _ray()
	_spec_cache[model_id] = out
	return out


## Construit le modèle d'une arme. `viewmodel` : matériaux vue FPS.
static func build(model_id: String, viewmodel: bool, pap := false) -> Node3D:
	var root := Node3D.new()
	root.name = "Model_" + model_id
	for part in spec(model_id).parts:
		var mi := MeshInstance3D.new()
		mi.mesh = _mesh_for(part)
		mi.material_override = material(part[3], viewmodel, pap)
		mi.position = part[2]
		var base := Basis(Vector3.RIGHT, PI * 0.5) if part[0] == "cyl" else Basis.IDENTITY
		var r = part[4]
		if r is Vector3:
			mi.basis = Basis.from_euler(Vector3(deg_to_rad(r.x), deg_to_rad(r.y), deg_to_rad(r.z))) * base
		else:
			mi.basis = Basis(Vector3.RIGHT, deg_to_rad(float(r))) * base
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if viewmodel else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if viewmodel:
			# Pas de culling par frustum : l'arme est toujours à l'écran.
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
	return Vector3.ZERO


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
		var sz: Vector3 = part[1]
		var pos: Vector3 = part[2]
		var r = part[4]
		var ang := deg_to_rad(r.x if r is Vector3 else float(r))
		var extent := Vector2(sz.z, sz.x * 2.0) if part[0] == "cyl" else Vector2(sz.z, sz.y)
		# Rotation d'Euler autour de Y (pièce vue par le bout) : largeur apparente.
		if r is Vector3 and absf(r.y) > 45.0:
			extent = Vector2(sz.x * 2.0 if part[0] == "cyl" else sz.x, extent.y)
		out.append([Vector2(pos.z, pos.y), extent, ang])
	return out


# ==========================================================================
# Primitives d'assemblage
# ==========================================================================

static func _b(parts: Array, size: Vector3, pos: Vector3, mat: String, rot: Variant = 0.0) -> void:
	parts.append(["box", size, pos, mat, rot])


static func _c(parts: Array, radius: float, length: float, pos: Vector3, mat: String, rot: Variant = 0.0) -> void:
	parts.append(["cyl", Vector3(radius, 0, length), pos, mat, rot])


## Chargeur (ou pièce) en segments successifs vers le bas : chaque segment
## [longueur, inclinaison en degrés (positive : le bas part vers l'avant)].
static func _chain(parts: Array, top: Vector3, segs: Array, w: float, d: float, mat: String) -> Vector3:
	var p := top
	for sg in segs:
		var a := deg_to_rad(float(sg[1]))
		var dir := Vector3(0, -cos(a), -sin(a))
		_b(parts, Vector3(w, sg[0], d), p + dir * sg[0] * 0.5, mat, sg[1])
		p += dir * sg[0]
	return p


## Poignée pistolet standard (origine = détente).
static func _pistol_grip(parts: Array, mat: String, z := 0.05, ang := -14.0) -> void:
	_b(parts, Vector3(0.034, 0.11, 0.045), Vector3(0, -0.05, z), mat, ang)
	# Pontet
	_b(parts, Vector3(0.008, 0.008, 0.06), Vector3(0, -0.04, z - 0.06), "metal_dark")


## Cran de mire : socle plein puis deux oreilles dont le sommet est sur la
## ligne de mire `line` (l'encoche laisse voir le guidon).
static func _notch(parts: Array, z: float, base_y: float, line: float, w := 0.026, notch := 0.009, mat := "metal_dark") -> void:
	var ear_h := 0.007
	var body_h := maxf(line - ear_h - base_y, 0.002)
	_b(parts, Vector3(w, body_h, 0.01), Vector3(0, line - ear_h - body_h * 0.5, z), mat)
	var ear_w := (w - notch) * 0.5
	for sx in [-1.0, 1.0]:
		_b(parts, Vector3(ear_w, ear_h, 0.01), Vector3(sx * (notch + ear_w) * 0.5, line - ear_h * 0.5, z), mat)


## Guidon : lame dont la pointe est exactement sur la ligne de mire.
## `hood` : oreilles de protection de part et d'autre (AK, M16).
static func _post(parts: Array, z: float, base_y: float, line: float, w := 0.005, hood := false, mat := "metal_dark") -> void:
	var h := maxf(line - base_y, 0.004)
	_b(parts, Vector3(w, h, 0.008), Vector3(0, line - h * 0.5, z), mat)
	if hood:
		for sx in [-1.0, 1.0]:
			_b(parts, Vector3(0.004, h + 0.006, 0.012), Vector3(sx * 0.012, line + 0.006 - (h + 0.006) * 0.5, z), mat)
		_b(parts, Vector3(0.028, 0.006, 0.014), Vector3(0, line - h + 0.003, z), mat)


## Œilleton (dioptre) : anneau carré percé, centré sur la ligne de mire.
static func _aperture(parts: Array, z: float, base_y: float, line: float, hole := 0.009, outer := 0.026, mat := "metal_dark") -> void:
	var bar := (outer - hole) * 0.5
	_b(parts, Vector3(outer, bar, 0.008), Vector3(0, line + (hole + bar) * 0.5, z), mat)
	var low_h := maxf(line - hole * 0.5 - base_y, bar)
	_b(parts, Vector3(outer, low_h, 0.008), Vector3(0, line - hole * 0.5 - low_h * 0.5, z), mat)
	for sx in [-1.0, 1.0]:
		_b(parts, Vector3(bar, hole, 0.008), Vector3(sx * (hole + bar) * 0.5, line, z), mat)


# ==========================================================================
# Archétypes
# ==========================================================================

static func _pistol(p: Dictionary) -> Dictionary:
	var parts := []
	var L: float = p.get("len", 0.21)
	var h: float = p.get("h", 0.036)
	var front := 0.035 - L
	_b(parts, Vector3(0.034, h, L), Vector3(0, 0.035, 0.035 - L * 0.5), p.get("slide", "metal_worn"))
	_b(parts, Vector3(0.03, 0.026, L * 0.8), Vector3(0, 0.005, 0.035 - L * 0.45), "metal")
	_b(parts, Vector3(0.03, 0.11, 0.045), Vector3(0, -0.05, 0.02), p.get("grip", "wood_dark"), -12.0)
	var ext: float = p.get("mag_ext", 0.0)
	if ext > 0.0:
		_b(parts, Vector3(0.026, ext, 0.036), Vector3(0, -0.108 - ext * 0.5, 0.034), "metal_dark", -12.0)
	_c(parts, 0.009, 0.03, Vector3(0, 0.035, front + 0.01), "metal_dark")
	# Guidon et cran de mire sur la même ligne.
	var slide_top := 0.035 + h * 0.5
	var line := slide_top + 0.009
	_post(parts, front + 0.02, slide_top, line, 0.005)
	_notch(parts, 0.02, slide_top, line, 0.026, 0.009)
	_b(parts, Vector3(0.012, 0.02, 0.03), Vector3(0, -0.018, -0.02), "metal_dark")
	# Chien
	_b(parts, Vector3(0.01, 0.018, 0.012), Vector3(0, 0.05, 0.04), "metal_dark", -30.0)
	return {"parts": parts, "anchors": {
		"muzzle": Vector3(0, 0.035, front - 0.005), "sight": Vector3(0, line, 0.02),
		"front": Vector3(0, line, front + 0.02), "ads": Vector3(0, 0, 0.4),
		"eject": Vector3(0.018, slide_top - 0.004, -0.04),
		"grip": Vector3(0, -0.06, 0.03), "support": Vector3(-0.02, -0.07, 0.02)}}


static func _revolver(p: Dictionary) -> Dictionary:
	var parts := []
	var bl: float = p.get("barrel", 0.16)
	# Carcasse, barillet, canon à bande ventilée et tenon plein.
	_b(parts, Vector3(0.03, 0.05, 0.09), Vector3(0, 0.03, -0.01), "metal")
	_c(parts, 0.028, 0.05, Vector3(0, 0.03, -0.02), "metal_worn")
	_c(parts, 0.011, bl, Vector3(0, 0.045, -0.055 - bl * 0.5), "metal")
	_b(parts, Vector3(0.018, 0.018, bl), Vector3(0, 0.03, -0.055 - bl * 0.5), "metal")
	_b(parts, Vector3(0.01, 0.012, bl + 0.04), Vector3(0, 0.061, -0.04 - bl * 0.5), "metal_dark")
	# Guidon à rampe au bout de la bande, cran de mire sur le haut de la carcasse.
	var line := 0.079
	_post(parts, -0.05 - bl, 0.067, line, 0.005)
	_notch(parts, 0.0, 0.055, line, 0.024, 0.009)
	_b(parts, Vector3(0.034, 0.12, 0.05), Vector3(0, -0.05, 0.04), "wood", -22.0)
	_b(parts, Vector3(0.008, 0.008, 0.05), Vector3(0, -0.02, -0.02), "metal_dark")
	_b(parts, Vector3(0.012, 0.022, 0.014), Vector3(0, 0.06, 0.035), "metal_dark", -35.0)
	return {"parts": parts, "anchors": {
		"muzzle": Vector3(0, 0.045, -0.06 - bl), "sight": Vector3(0, line, 0.0),
		"front": Vector3(0, line, -0.05 - bl), "ads": Vector3(0, 0, 0.4),
		"grip": Vector3(0, -0.065, 0.05), "support": Vector3(-0.02, -0.08, 0.04)}}


## Arme longue générique (PM, fusil, mitrailleuse, sniper).
##   rec [avant, arrière, largeur] du boîtier (z), hg [longueur, hauteur, matériau] du garde-main
##   barrel [longueur, rayon], mag [type, z, longueur, inclinaison], stock [type, longueur, matériau]
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
	if p.get("round", false):
		_c(parts, rh * 0.42, rb - rf, Vector3(0, y + 0.005, (rf + rb) * 0.5), rm)
		_b(parts, Vector3(rw * 0.8, rh * 0.5, rb - rf), Vector3(0, y - rh * 0.2, (rf + rb) * 0.5), rm)
	else:
		_b(parts, Vector3(rw, rh, rb - rf), Vector3(0, y, (rf + rb) * 0.5), rm)
	# Fût en bois courant sous le boîtier (M14, L96).
	if p.has("wood_body"):
		_b(parts, Vector3(rw + 0.008, 0.045, rb - rf + 0.02), Vector3(0, bottom - 0.005, (rf + rb) * 0.5), p.wood_body)
	# Garde-main
	var hg: Array = p.get("hg", [0.0, 0.0, "metal"])
	var hl: float = hg[0]
	var front := rf
	var support := Vector3(0, bottom - 0.02, rf + 0.04)
	if hl > 0.0:
		if p.get("round_hg", false):
			_c(parts, hg[1] * 0.5, hl, Vector3(0, y, rf - hl * 0.5), hg[2])
		else:
			_b(parts, Vector3(rw + 0.004, hg[1], hl), Vector3(0, y - 0.004, rf - hl * 0.5), hg[2])
		front = rf - hl
		support = Vector3(0, y - hg[1] * 0.5 - 0.02, rf - hl * 0.55)
	# Manchon perforé (canon refroidi) : anneaux sombres.
	if p.get("shroud", false):
		var zz := front + 0.02
		for i in 3:
			_c(parts, rh * 0.36, 0.012, Vector3(0, y + 0.004, zz - 0.02 - i * 0.035), "metal_dark")
	# Canon et bouche
	var bar: Array = p.barrel
	var bl: float = bar[0]
	var br: float = bar[1]
	var by := y + 0.006
	if bl > 0.0:
		_c(parts, br, bl, Vector3(0, by, front - bl * 0.5), "metal_dark")
	var muzzle_z := front - bl
	match p.get("muzzle", "none"):
		"flash":
			_c(parts, br * 1.5, 0.05, Vector3(0, by, muzzle_z - 0.025), "metal_dark")
			muzzle_z -= 0.05
		"brake":
			_b(parts, Vector3(br * 3.2, br * 2.4, 0.045), Vector3(0, by, muzzle_z - 0.022), "metal_dark")
			muzzle_z -= 0.045
		"ak":
			_c(parts, br * 1.9, 0.07, Vector3(0, by, muzzle_z - 0.035), "metal_dark")
			muzzle_z -= 0.07
	if p.get("barrel_hook", false):
		_b(parts, Vector3(0.012, 0.035, 0.03), Vector3(0, bottom - 0.005, front - 0.03), "metal_dark")
	# Chargeur
	var mag: Array = p.get("mag", ["none"])
	var mz: float = mag[1] if mag.size() > 1 else 0.0
	var ml: float = mag[2] if mag.size() > 2 else 0.15
	match mag[0]:
		"straight":
			var tilt: float = mag[3] if mag.size() > 3 else 6.0
			_chain(parts, Vector3(0, bottom + 0.01, mz), [[ml, tilt]], 0.03, 0.055, "metal_dark")
		"curved":
			_chain(parts, Vector3(0, bottom + 0.01, mz), [[ml * 0.4, 8.0], [ml * 0.35, 22.0], [ml * 0.3, 36.0]], 0.03, 0.055, "metal_dark")
		"box":
			_b(parts, Vector3(0.1, ml, 0.13), Vector3(0.03, bottom - ml * 0.5 + 0.01, mz), "olive")
			_b(parts, Vector3(0.03, 0.03, 0.06), Vector3(0.02, bottom + 0.005, mz), "brass")
		"drum":
			_c(parts, ml, 0.06, Vector3(0, bottom - ml + 0.01, mz), "metal_dark", Vector3(0, 90, 0))
			_c(parts, ml * 0.35, 0.064, Vector3(0, bottom - ml + 0.01, mz), "metal", Vector3(0, 90, 0))
		"grip":
			# Chargeur logé dans la poignée : dépasse sous la crosse de pistolet.
			_b(parts, Vector3(0.026, ml, 0.036), Vector3(0, -0.11 - ml * 0.5 + 0.03, 0.068), "metal_dark", -14.0)
	# Poignée
	var gz := 0.05
	var bullpup: bool = p.get("bullpup", false)
	match p.get("grip", "polymer"):
		"none":
			# Crosse « à poignée de fusil » : le poignet de la crosse sert de poignée.
			var stk: Array = p.get("stock", ["none"])
			var wrist: String = p.get("wood_body", stk[2] if stk.size() > 2 else "wood")
			_b(parts, Vector3(0.042, 0.075, 0.12), Vector3(0, bottom - 0.02, rb + 0.02), wrist, 18.0)
			_b(parts, Vector3(0.008, 0.008, 0.06), Vector3(0, -0.04, -0.01), "metal_dark")
		var gm:
			_pistol_grip(parts, gm, gz)
	if p.get("front_grip", false):
		_b(parts, Vector3(0.03, 0.09, 0.035), Vector3(0, bottom - 0.045, front + 0.04), "polymer", 8.0)
		support = Vector3(0, bottom - 0.07, front + 0.04)
	if p.get("bipod", false):
		for x in [-0.018, 0.018]:
			_b(parts, Vector3(0.008, 0.008, 0.18), Vector3(x, by - 0.02, front - bl * 0.35 + 0.02), "metal_dark", 8.0)
	if p.get("bolt", false):
		_b(parts, Vector3(0.05, 0.01, 0.01), Vector3(0.035, top - 0.01, rb - 0.04), "metal_dark")
		_c(parts, 0.012, 0.012, Vector3(0.06, top - 0.01, rb - 0.04), "metal_dark", Vector3(0, 90, 0))
	# Crosse
	var st: Array = p.get("stock", ["none"])
	var sl: float = st[1] if st.size() > 1 else 0.25
	var sm: String = st[2] if st.size() > 2 else "polymer"
	match st[0]:
		"solid":
			_b(parts, Vector3(0.045, 0.07, sl), Vector3(0, y - 0.005, rb + sl * 0.5), sm, 4.0)
			_b(parts, Vector3(0.045, 0.11, 0.03), Vector3(0, y - 0.025, rb + sl), "polymer")
		"rifle":
			_b(parts, Vector3(0.045, 0.065, sl), Vector3(0, y - 0.03, rb + sl * 0.5 + 0.04), sm, 7.0)
			_b(parts, Vector3(0.045, 0.11, 0.025), Vector3(0, y - 0.07, rb + sl + 0.03), "metal_dark", 7.0)
		"thumbhole":
			_b(parts, Vector3(0.045, 0.04, sl), Vector3(0, y, rb + sl * 0.5), sm)
			_b(parts, Vector3(0.04, 0.025, sl * 0.55), Vector3(0, y - 0.085, rb + sl * 0.7), sm)
			_b(parts, Vector3(0.045, 0.13, 0.04), Vector3(0, y - 0.04, rb + sl), sm)
		"tube":
			_c(parts, 0.014, sl, Vector3(0, y, rb + sl * 0.5), "metal_dark")
			_b(parts, Vector3(0.04, 0.09, 0.07), Vector3(0, y - 0.015, rb + sl - 0.02), "polymer")
		"wire":
			_b(parts, Vector3(0.01, 0.01, sl), Vector3(0, y + 0.02, rb + sl * 0.5), "metal_dark")
			_b(parts, Vector3(0.01, 0.01, sl), Vector3(0, y - 0.04, rb + sl * 0.5), "metal_dark", 6.0)
			_b(parts, Vector3(0.04, 0.1, 0.02), Vector3(0, y - 0.02, rb + sl), "metal_dark")
		"folded_side":
			# Crosse repliée le long du flanc gauche.
			var x := -(rw * 0.5 + 0.008)
			_b(parts, Vector3(0.012, 0.03, sl), Vector3(x, y + 0.004, rb - sl * 0.5 + 0.02), "metal_dark")
			_b(parts, Vector3(0.014, 0.08, 0.025), Vector3(x, y - 0.012, rb - sl + 0.02), "metal_dark")
			_b(parts, Vector3(0.02, 0.03, 0.03), Vector3(0, y, rb + 0.012), "metal_dark")
		"wire_folded":
			_b(parts, Vector3(0.008, 0.008, sl), Vector3(0.02, top + 0.005, rb - sl * 0.5), "metal_dark")
			_b(parts, Vector3(0.008, 0.008, sl), Vector3(-0.02, top + 0.005, rb - sl * 0.5), "metal_dark")
			_b(parts, Vector3(0.05, 0.012, 0.03), Vector3(0, top + 0.005, rb + 0.01), "metal_dark")
		"under_folded":
			# MP40 : bras de crosse replié sous le boîtier, plaque derrière la poignée.
			_b(parts, Vector3(0.01, 0.012, sl), Vector3(0.018, bottom - 0.006, rb - sl * 0.5), "metal_dark")
			_b(parts, Vector3(0.01, 0.012, sl), Vector3(-0.018, bottom - 0.006, rb - sl * 0.5), "metal_dark")
			_b(parts, Vector3(0.05, 0.035, 0.012), Vector3(0, bottom - 0.02, rb + 0.005), "metal_dark")
		"top_folded":
			_b(parts, Vector3(0.01, 0.012, sl), Vector3(0, top + 0.008, rb - sl * 0.5), "metal_dark")
			_b(parts, Vector3(0.012, 0.035, 0.012), Vector3(0, top + 0.0, rb - sl), "metal_dark")
			_b(parts, Vector3(0.04, 0.02, 0.02), Vector3(0, top + 0.005, rb + 0.005), "metal_dark")
	if bullpup:
		# Plaque de couche au bout du boîtier.
		_b(parts, Vector3(rw + 0.006, rh + 0.03, 0.03), Vector3(0, y - 0.012, rb + 0.01), "polymer")
	# Dessus : organes de visée. `line` : hauteur de la ligne de mire ;
	# `rear_z` / `front_z` : cran (ou œilleton, oculaire) et guidon (objectif).
	var line := top + 0.024
	var rear_z := rb - 0.04
	var front_z := muzzle_z + 0.03
	var eye := 0.3
	match p.get("top", "iron"):
		"iron":
			_notch(parts, rear_z, top, line)
			_post(parts, front_z, by + br, line, 0.005, true)
		"ak":
			# Hausse à planchette à l'avant du boîtier, couvercle de culasse.
			rear_z = rf + 0.05
			line = top + 0.03
			front_z = muzzle_z + 0.09
			_b(parts, Vector3(rw * 0.8, 0.014, rb - rf - 0.08), Vector3(0, top + 0.004, (rf + rb) * 0.5 + 0.04), rm)
			_notch(parts, rear_z, top, line, 0.032, 0.01)
			_post(parts, front_z, by + br, line, 0.005, true)
			eye = 0.34
		"drum_sight":
			# MP5K : tambour de dioptre à l'arrière, guidon à tunnel.
			line = top + 0.024
			rear_z = rb - 0.03
			front_z = rf + 0.02
			_aperture(parts, rear_z, top, line, 0.01, 0.022)
			_post(parts, front_z, top, line, 0.005, true)
			eye = 0.16
		"handle", "handle_low":
			var hh := 0.04 if p.top == "handle" else 0.022
			var hz0 := rb - 0.03
			var hz1: float = rf + 0.05 if p.top == "handle" else rb - 0.1
			_b(parts, Vector3(0.022, 0.016, hz0 - hz1 + 0.03), Vector3(0, top + hh, (hz0 + hz1) * 0.5), rm)
			_b(parts, Vector3(0.018, hh, 0.02), Vector3(0, top + hh * 0.5, hz1), rm)
			_b(parts, Vector3(0.018, hh, 0.02), Vector3(0, top + hh * 0.5, hz0), rm)
			# Œilleton sur l'arrière de la poignée de transport.
			line = top + hh + 0.022
			rear_z = hz0
			_aperture(parts, rear_z, top + hh + 0.008, line, 0.011, 0.02)
			# Guidon (triangulaire sur M16) : embase sur le canon, lame jusqu'à la ligne.
			var tri: bool = p.get("front_post", false)
			front_z = front - bl * 0.3 if tri else muzzle_z + 0.04
			var base_h := maxf(line - 0.014 - by, 0.01)
			_b(parts, Vector3(0.012, base_h, 0.02), Vector3(0, line - 0.014 - base_h * 0.5, front_z), "polymer" if tri else "metal_dark")
			_post(parts, front_z, line - 0.014, line, 0.005, true)
			eye = 0.15
		"famas":
			# Longue poignée de transport de la bouche à l'arrière.
			var bar_y := top + 0.06
			_b(parts, Vector3(0.022, 0.018, rb - rf - 0.02), Vector3(0, bar_y, (rf + rb) * 0.5 - 0.02), "polymer")
			_b(parts, Vector3(0.02, 0.06, 0.03), Vector3(0, top + 0.03, rf + 0.03), "polymer", 20.0)
			_b(parts, Vector3(0.02, 0.06, 0.03), Vector3(0, top + 0.03, rb - 0.06), "polymer")
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
			_c(parts, 0.02, slen, Vector3(0, sy, sz), "metal_dark")
			_c(parts, 0.027, 0.05, Vector3(0, sy, sz - slen * 0.5 + 0.02), "metal_dark")
			_c(parts, 0.024, 0.04, Vector3(0, sy, sz + slen * 0.5 - 0.02), "metal_dark")
			_c(parts, 0.018, 0.005, Vector3(0, sy, sz + slen * 0.5), "glass")
			_c(parts, 0.024, 0.005, Vector3(0, sy, sz - slen * 0.5), "glass")
			_b(parts, Vector3(0.012, 0.035, 0.02), Vector3(0, top + 0.018, sz - slen * 0.25), "metal_dark")
			_b(parts, Vector3(0.012, 0.035, 0.02), Vector3(0, top + 0.018, sz + slen * 0.25), "metal_dark")
			line = sy
			rear_z = sz + slen * 0.5
			front_z = sz - slen * 0.5
			eye = 0.07
		"g11":
			# Poignée-lunette sur toute la longueur.
			_b(parts, Vector3(0.03, 0.03, 0.34), Vector3(0, top + 0.035, (rf + rb) * 0.5), "polymer")
			_b(parts, Vector3(0.03, 0.035, 0.03), Vector3(0, top + 0.015, rf + 0.1), "polymer")
			_c(parts, 0.012, 0.006, Vector3(0, top + 0.035, (rf + rb) * 0.5 + 0.17), "glass")
			line = top + 0.035
			rear_z = (rf + rb) * 0.5 + 0.17
			front_z = (rf + rb) * 0.5 - 0.17
			eye = 0.07
	return {"parts": parts, "anchors": {
		"muzzle": Vector3(0, by, muzzle_z), "sight": Vector3(0, line, rear_z),
		"front": Vector3(0, line, front_z), "ads": Vector3(0, 0, eye),
		"eject": Vector3(rw * 0.5 + 0.004, y + 0.012, rb - 0.1 if bullpup else rf * 0.35 + rb * 0.65),
		"grip": Vector3(0, -0.06, gz), "support": support,
		# Bullpup : l'arme est tenue plus en avant (crosse à l'épaule).
		"hold": Vector3(0, 0, -0.14) if bullpup else Vector3.ZERO}}


static func _shotgun(p: Dictionary) -> Dictionary:
	var parts := []
	var L: float = p.get("len", 0.6)
	var y := 0.03
	var front := -0.12 - L
	# Carcasse
	_b(parts, Vector3(0.05, 0.07, 0.2), Vector3(0, y, 0.0), "metal")
	var barrels: int = p.get("barrels", 1)
	var muzzle_y := y + 0.015
	if barrels == 2:
		# Canons superposés (Olympia) et longuesse en bois.
		_c(parts, 0.017, L, Vector3(0, y + 0.02, -0.1 - L * 0.5), "metal_dark")
		_c(parts, 0.017, L, Vector3(0, y - 0.016, -0.1 - L * 0.5), "metal_dark")
		_b(parts, Vector3(0.006, 0.006, L), Vector3(0, y + 0.04, -0.1 - L * 0.5), "metal")
		_b(parts, Vector3(0.048, 0.04, 0.22), Vector3(0, y - 0.035, -0.24), "wood_light")
		muzzle_y = y + 0.02
	else:
		_c(parts, 0.017, L, Vector3(0, y + 0.015, -0.1 - L * 0.5), "metal_dark")
		# Tube magasin sous le canon.
		_c(parts, 0.013, L * 0.8, Vector3(0, y - 0.02, -0.1 - L * 0.4), "metal")
		if p.get("pump", false):
			_b(parts, Vector3(0.048, 0.045, 0.16), Vector3(0, y - 0.022, -0.3), p.get("grip", "wood") if p.get("grip", "wood") != "polymer" else "polymer")
			for i in 4:
				_b(parts, Vector3(0.05, 0.006, 0.01), Vector3(0, y - 0.022, -0.25 - i * 0.03), "metal_dark")
		else:
			_b(parts, Vector3(0.048, 0.05, 0.14), Vector3(0, y - 0.015, -0.2), "polymer")
		if p.get("shroud", false):
			_b(parts, Vector3(0.042, 0.02, L * 0.6), Vector3(0, y + 0.035, -0.1 - L * 0.4), "metal_dark")
		muzzle_y = y + 0.015
	# Bille de guidon au bout du canon (ou de la bande) : ligne de mire au ras
	# du boîtier et de la bande.
	var rib_top := y + 0.043 if barrels == 2 else (y + 0.045 if p.get("shroud", false) else y + 0.032)
	var line := maxf(rib_top, y + 0.035) + 0.008
	_post(parts, front + 0.03, rib_top, line, 0.009, false, "brass")
	# Crosse et poignée
	match p.get("stock", "none"):
		"wood_light", "wood":
			_b(parts, Vector3(0.045, 0.1, 0.32), Vector3(0, y - 0.045, 0.24), p.stock, 8.0)
			_b(parts, Vector3(0.046, 0.12, 0.02), Vector3(0, y - 0.07, 0.4), "wood_dark", 8.0)
		"top_folded":
			_b(parts, Vector3(0.01, 0.012, 0.3), Vector3(0, y + 0.05, -0.05), "metal_dark")
			_b(parts, Vector3(0.012, 0.04, 0.012), Vector3(0, y + 0.035, -0.2), "metal_dark")
	if p.get("grip", "none") != "none":
		_pistol_grip(parts, p.grip, 0.09, -18.0)
	else:
		_b(parts, Vector3(0.008, 0.008, 0.06), Vector3(0, -0.02, 0.02), "metal_dark")
	return {"parts": parts, "anchors": {
		"muzzle": Vector3(0, muzzle_y, front), "sight": Vector3(0, line, 0.05),
		"front": Vector3(0, line, front + 0.03), "ads": Vector3(0, 0, 0.3),
		"eject": Vector3(0.027, y + 0.01, -0.03),
		"grip": Vector3(0, -0.05, 0.1), "support": Vector3(0, y - 0.05, -0.3)}}


## China Lake : gros tube, magasin tubulaire à pompe, crosse bois, hausse à échelle.
static func _launcher() -> Dictionary:
	var parts := []
	var y := 0.035
	_b(parts, Vector3(0.06, 0.08, 0.2), Vector3(0, y, 0.0), "metal_dark")
	_c(parts, 0.032, 0.42, Vector3(0, y + 0.01, -0.3), "metal_dark")
	_c(parts, 0.036, 0.04, Vector3(0, y + 0.01, -0.5), "metal")
	_c(parts, 0.028, 0.34, Vector3(0, y - 0.05, -0.25), "metal")
	_b(parts, Vector3(0.07, 0.06, 0.16), Vector3(0, y - 0.05, -0.28), "wood")
	# Hausse à échelle (cran) sur le boîtier, guidon haut au bout du tube.
	var line := y + 0.1
	_notch(parts, -0.09, y + 0.04, line, 0.03, 0.01, "metal_worn")
	_post(parts, -0.49, y + 0.042, line, 0.006, true)
	_b(parts, Vector3(0.05, 0.1, 0.3), Vector3(0, y - 0.045, 0.24), "wood", 6.0)
	_b(parts, Vector3(0.05, 0.12, 0.025), Vector3(0, y - 0.065, 0.39), "wood_dark", 6.0)
	_pistol_grip(parts, "wood_dark", 0.06, -16.0)
	return {"parts": parts, "anchors": {
		"muzzle": Vector3(0, y + 0.01, -0.52), "sight": Vector3(0, line, -0.09),
		"front": Vector3(0, line, -0.49), "ads": Vector3(0, 0, 0.28),
		"grip": Vector3(0, -0.06, 0.06), "support": Vector3(0, y - 0.08, -0.28)}}


## M72 LAW : tube olive déployé, visée repliable, poignée de mise à feu.
static func _rocket() -> Dictionary:
	var parts := []
	var y := 0.07
	_c(parts, 0.04, 0.9, Vector3(0, y, -0.15), "olive")
	_c(parts, 0.043, 0.05, Vector3(0, y, -0.58), "olive")
	_c(parts, 0.043, 0.05, Vector3(0, y, 0.28), "olive")
	_c(parts, 0.03, 0.01, Vector3(0, y, 0.31), "metal_dark")
	_b(parts, Vector3(0.05, 0.03, 0.12), Vector3(0, y + 0.045, -0.02), "olive")
	# Œilleton arrière et réticule avant (cadre + lame) relevés.
	var line := y + 0.075
	_aperture(parts, 0.06, y + 0.042, line, 0.01, 0.03)
	for sx in [-1.0, 1.0]:
		_b(parts, Vector3(0.004, 0.05, 0.006), Vector3(sx * 0.016, y + 0.067, -0.44), "metal_dark")
	_b(parts, Vector3(0.036, 0.004, 0.006), Vector3(0, y + 0.092, -0.44), "metal_dark")
	_post(parts, -0.44, y + 0.042, line, 0.004)
	_b(parts, Vector3(0.03, 0.08, 0.04), Vector3(0, y - 0.07, 0.02), "polymer", 10.0)
	_b(parts, Vector3(0.012, 0.008, 0.9), Vector3(0.036, y + 0.02, -0.15), "tan")
	return {"parts": parts, "anchors": {
		"muzzle": Vector3(0, y, -0.61), "sight": Vector3(0, line, 0.06),
		"front": Vector3(0, line, -0.44), "ads": Vector3(0, 0, 0.17),
		"grip": Vector3(0, -0.04, 0.03), "support": Vector3(-0.02, y - 0.05, -0.25)}}


static func _ray() -> Dictionary:
	var parts := []
	_b(parts, Vector3(0.07, 0.08, 0.22), Vector3(0, 0.035, -0.06), "metal_worn")
	_c(parts, 0.045, 0.1, Vector3(0, 0.04, -0.2), "metal")
	_c(parts, 0.03, 0.06, Vector3(0, 0.04, -0.27), "glow")
	_b(parts, Vector3(0.035, 0.12, 0.05), Vector3(0, -0.05, 0.03), "metal_dark", -14.0)
	_b(parts, Vector3(0.012, 0.05, 0.16), Vector3(0, 0.1, -0.06), "metal")
	_c(parts, 0.012, 0.12, Vector3(0.04, 0.04, -0.06), "glow")
	_c(parts, 0.012, 0.12, Vector3(-0.04, 0.04, -0.06), "glow")
	return {"parts": parts, "anchors": {
		"muzzle": Vector3(0, 0.04, -0.3), "sight": Vector3(0, 0.13, 0.02),
		"front": Vector3(0, 0.13, -0.14), "ads": Vector3(0, 0, 0.32),
		"grip": Vector3(0, -0.06, 0.04), "support": Vector3(-0.02, -0.07, 0.03)}}


## TONNERRE-7 : gros tambour à ailettes (compresseur), bouche évasée qui
## luit, deux réservoirs de cuivre sur les flancs, manomètre, poignée de
## transport, poignées pistolet et avant, crosse tubulaire.
static func _thunder() -> Dictionary:
	var parts := []
	var y := 0.055
	# Tambour et ailettes de refroidissement, bande lumineuse entre les ailettes.
	_c(parts, 0.074, 0.3, Vector3(0, y, -0.12), "metal_worn")
	_c(parts, 0.077, 0.05, Vector3(0, y, -0.12), "glow_blue")
	for k in 6:
		_c(parts, 0.086, 0.012, Vector3(0, y, -0.255 + k * 0.054), "metal_dark")
	# Bouche : col, pavillon évasé, cœur lumineux et trois lames de guidage.
	_c(parts, 0.058, 0.07, Vector3(0, y, -0.305), "metal_dark")
	_c(parts, 0.07, 0.025, Vector3(0, y, -0.345), "metal")
	_c(parts, 0.092, 0.02, Vector3(0, y, -0.365), "metal_worn")
	_c(parts, 0.05, 0.01, Vector3(0, y, -0.37), "glow_blue")
	for a in [90.0, 210.0, 330.0]:
		var r := deg_to_rad(a)
		_b(parts, Vector3(0.012, 0.012, 0.09), Vector3(cos(r) * 0.08, y + sin(r) * 0.08, -0.39), "metal_dark")
	# Boîtier arrière (moteur) et culot arrondi.
	_b(parts, Vector3(0.085, 0.085, 0.1), Vector3(0, y - 0.005, 0.075), "metal_dark")
	_c(parts, 0.05, 0.02, Vector3(0, y, 0.035), "brass")
	_c(parts, 0.036, 0.04, Vector3(0, y, 0.145), "metal")
	# Réservoirs latéraux (cuivre, bouchons en laiton, tuyaux vers le tambour).
	for sx in [-1.0, 1.0]:
		_c(parts, 0.03, 0.22, Vector3(sx * 0.1, y - 0.035, -0.07), "copper")
		_c(parts, 0.032, 0.014, Vector3(sx * 0.1, y - 0.035, -0.185), "brass")
		_c(parts, 0.032, 0.014, Vector3(sx * 0.1, y - 0.035, 0.045), "brass")
		_c(parts, 0.012, 0.1, Vector3(sx * 0.1, y - 0.004, -0.07), "glow_blue")
		_b(parts, Vector3(0.03, 0.012, 0.012), Vector3(sx * 0.075, y - 0.02, 0.05), "metal_dark")
	# Manomètre sur le boîtier, poignée de transport.
	_c(parts, 0.022, 0.012, Vector3(0.028, y + 0.045, 0.08), "brass", Vector3(90, 0, 0))
	_c(parts, 0.017, 0.013, Vector3(0.028, y + 0.046, 0.08), "glass", Vector3(90, 0, 0))
	_b(parts, Vector3(0.018, 0.016, 0.2), Vector3(0, y + 0.11, -0.1), "metal_dark")
	_b(parts, Vector3(0.014, 0.045, 0.014), Vector3(0, y + 0.082, -0.19), "metal_dark")
	_b(parts, Vector3(0.014, 0.045, 0.014), Vector3(0, y + 0.082, -0.01), "metal_dark")
	# Poignées : pistolet sous le boîtier, poignée avant sous le tambour.
	_pistol_grip(parts, "wood_dark", 0.07, -16.0)
	_b(parts, Vector3(0.032, 0.09, 0.036), Vector3(0, y - 0.115, -0.2), "wood_dark", 8.0)
	return {"parts": parts, "anchors": {
		"muzzle": Vector3(0, y, -0.39), "sight": Vector3(0, y + 0.125, 0.0),
		"front": Vector3(0, y + 0.125, -0.2), "ads": Vector3(0, 0, 0.36),
		"grip": Vector3(0, -0.06, 0.08), "support": Vector3(0, y - 0.14, -0.2)}}


## Couteau : lame à plat dans le plan vertical (tranchant en bas), pointe vers
## -Z, origine au milieu du manche (la main).
static func _knife(p: Dictionary) -> Dictionary:
	var parts := []
	var L: float = p.get("blade", 0.17)
	var w: float = p.get("w", 0.03)
	var bm: String = p.get("blade_mat", "metal_dark")
	var z0 := -0.05
	# Manche (et bagues), garde, pommeau.
	_b(parts, Vector3(0.024, 0.03, 0.11), Vector3(0, 0, 0.012), p.get("handle", "polymer"))
	for gz in [-0.02, 0.012, 0.044]:
		_b(parts, Vector3(0.026, 0.032, 0.006), Vector3(0, 0, gz), "metal_dark")
	if p.get("guard", false):
		_b(parts, Vector3(0.022, 0.075, 0.012), Vector3(0, -0.004, z0 + 0.006), "brass")
		_b(parts, Vector3(0.028, 0.036, 0.022), Vector3(0, 0, 0.075), "brass")
	else:
		_b(parts, Vector3(0.02, 0.05, 0.01), Vector3(0, -0.004, z0 + 0.006), "metal_dark")
		_b(parts, Vector3(0.026, 0.032, 0.016), Vector3(0, 0, 0.072), "metal_dark")
	# Lame : corps, dos épaissi, contre-pointe inclinée et pointe.
	var body := L * 0.78
	_b(parts, Vector3(0.004, w, body), Vector3(0, -0.002, z0 - body * 0.5), bm)
	_b(parts, Vector3(0.007, 0.006, body * 0.9), Vector3(0, w * 0.5 - 0.002, z0 - body * 0.47), bm)
	var tip := L - body
	_b(parts, Vector3(0.004, w * 0.62, tip * 1.1), Vector3(0, -w * 0.2, z0 - body - tip * 0.45), bm, -14.0)
	_b(parts, Vector3(0.0035, w * 0.28, tip * 0.8), Vector3(0, -w * 0.3, z0 - L + tip * 0.05), bm, -30.0)
	# Fil de la lame (reflet clair).
	_b(parts, Vector3(0.005, 0.004, body), Vector3(0, -w * 0.5, z0 - body * 0.5), "metal_worn")
	return {"parts": parts, "anchors": {
		"muzzle": Vector3(0, -w * 0.2, z0 - L), "sight": Vector3(0, 0.03, 0.0),
		"grip": Vector3(0, 0, 0.012), "support": Vector3(0, 0, 0.012)}}


## Minigun (FAUCHEUSE) : faisceau de six canons autour de l'axe, trois bagues,
## carter moteur, poignée de transport sur le dessus, poignée arrière, caisse
## de bande à gauche.
static func _minigun() -> Dictionary:
	var parts := []
	var y := 0.02
	for i in 6:
		var a := TAU * i / 6.0
		_c(parts, 0.009, 0.5, Vector3(cos(a) * 0.028, y + sin(a) * 0.028, -0.36), "metal_dark")
	for z in [-0.18, -0.4, -0.58]:
		_c(parts, 0.042, 0.02, Vector3(0, y, z), "metal")
	_c(parts, 0.012, 0.52, Vector3(0, y, -0.34), "metal_worn")
	_b(parts, Vector3(0.1, 0.1, 0.22), Vector3(0, y, 0.0), "metal_dark")
	_c(parts, 0.05, 0.08, Vector3(0, y, -0.12), "metal")
	_b(parts, Vector3(0.02, 0.02, 0.2), Vector3(0, y + 0.1, -0.02), "metal")
	_b(parts, Vector3(0.02, 0.06, 0.02), Vector3(0, y + 0.07, -0.1), "metal")
	_b(parts, Vector3(0.02, 0.06, 0.02), Vector3(0, y + 0.07, 0.06), "metal")
	_b(parts, Vector3(0.1, 0.13, 0.12), Vector3(-0.1, y - 0.04, 0.02), "olive")
	_b(parts, Vector3(0.03, 0.02, 0.1), Vector3(-0.05, y + 0.02, -0.02), "brass", Vector3(0, 0, 20))
	_pistol_grip(parts, "polymer", 0.1, -10.0)
	return {"parts": parts, "anchors": {
		"muzzle": Vector3(0, y, -0.62), "sight": Vector3(0, y + 0.12, -0.02),
		"grip": Vector3(0, -0.06, 0.1), "support": Vector3(0, y + 0.1, -0.05)}}
