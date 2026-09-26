class_name ZombieModel
extends RefCounted
## Apparence des zombies, façon Kino der Toten (Black Ops 1) : silhouettes
## humaines maigres, uniformes allemands feldgrau déchirés, casques et
## casquettes, bottes ; variantes civiles et scientifiques ; peau grise
## verdâtre, plaies, côtes à vif, mâchoire pendante, YEUX JAUNES LUMINEUX.
##
## Maillage procédural à normales lissées (ellipsoïdes et tubes de sections,
## RigBuilder), skinné sur le squelette commun (articulations partagées entre
## deux os : pas de fissure aux coudes ni aux genoux). Un seul draw call.
##
## Déterministe : la variante (0..99999, tirée par le serveur) choisit un des
## LOOK_COUNT « looks » ; le mesh de chaque look est construit une fois puis
## partagé (cache), comme le Skin (repos identique pour tous les zombies).

enum Arch { HELMET, CAP, OFFICER, RAGGED, SCIENTIST, CIVILIAN }
const ARCH_NAMES := ["soldat casqué", "soldat en calot", "officier", "soldat débraillé", "scientifique", "civil"]
## Répartition des archétypes (Kino : surtout des soldats).
const ARCH_SEQ := [0, 1, 3, 0, 2, 1, 4, 0, 5, 1, 3, 0, 4, 1, 5, 0, 2, 3]
const LOOK_COUNT := 36

## Couleurs pensées en sRGB (converties en linéaire par RigBuilder).
const FELDGRAU := [
	Color(0.42, 0.43, 0.35), Color(0.37, 0.39, 0.32), Color(0.4, 0.39, 0.33),
	Color(0.35, 0.37, 0.34), Color(0.44, 0.42, 0.34),
]
const TROUSERS := [Color(0.33, 0.33, 0.31), Color(0.36, 0.37, 0.33), Color(0.3, 0.3, 0.29)]
const COLLAR := Color(0.17, 0.21, 0.16)
const SKINS := [
	Color(0.54, 0.55, 0.47), Color(0.49, 0.52, 0.45), Color(0.56, 0.52, 0.47),
	Color(0.46, 0.48, 0.43), Color(0.52, 0.5, 0.48),
]
const LEATHER := Color(0.075, 0.065, 0.055)
const LEATHER_BROWN := Color(0.2, 0.13, 0.08)
const METAL := Color(0.45, 0.45, 0.42)
const HELMET_PAINT := Color(0.27, 0.29, 0.25)
const BLOOD := Color(0.36, 0.035, 0.03)
const BLOOD_DARK := Color(0.16, 0.015, 0.015)
const FLESH := Color(0.55, 0.14, 0.12)
const BONE := Color(0.72, 0.66, 0.52)
const TEETH := Color(0.62, 0.56, 0.4)
const SOCKET := Color(0.06, 0.03, 0.03)
const HAIR := [Color(0.1, 0.085, 0.07), Color(0.2, 0.17, 0.12), Color(0.3, 0.29, 0.27)]
## Yeux jaunes de Kino der Toten.
const EYE := Color(1.0, 0.86, 0.3)
const EYE_EMISSION := Color(1.0, 0.78, 0.18)
const COAT := [Color(0.7, 0.69, 0.62), Color(0.62, 0.62, 0.56)]
const SHIRT := [Color(0.62, 0.6, 0.53), Color(0.48, 0.47, 0.43), Color(0.42, 0.44, 0.47)]
const VEST := [Color(0.22, 0.17, 0.13), Color(0.18, 0.18, 0.19), Color(0.28, 0.24, 0.18)]
const CIV_TROUSERS := [Color(0.2, 0.17, 0.14), Color(0.17, 0.17, 0.18), Color(0.25, 0.23, 0.2)]

## Silhouette du torse maigre (hauteur relative au bassin, demi-largeur,
## demi-profondeur), du col à l'entrejambe.
const TORSO := [
	[0.66, 0.047, 0.05], [0.625, 0.062, 0.06], [0.585, 0.14, 0.09], [0.535, 0.19, 0.1],
	[0.45, 0.172, 0.108], [0.35, 0.152, 0.1], [0.23, 0.132, 0.09], [0.13, 0.132, 0.088],
	[0.03, 0.148, 0.098], [-0.06, 0.152, 0.102],
]
const HIPS_Y := 0.95
## Couche de rendu 2 : les décalques de sang (Fx, masque 1) ne se projettent
## pas sur les zombies debout dessus (bottes « peintes » en rouge).
const RENDER_LAYERS := 2


static var _material: ShaderMaterial
static var _dissolve_material: ShaderMaterial
static var _skin: Skin
static var _meshes := {}
static var _limbs := {}
static var _rest := {}
## Préchauffage en arrière-plan : tableaux prêts, looks pris en charge.
static var _mutex := Mutex.new()
static var _ready_arrays := {}
static var _claimed := {}
static var _task := -1


static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = preload("res://assets/shaders/zombie.gdshader")
		_material.set_shader_parameter("emission_color", EYE_EMISSION)
		_material.set_shader_parameter("emission_energy", 6.5)
		_material.set_shader_parameter("noise_lattice", NoiseLattice.tex3d())
	return _material


## Variante « dissolution » (corps qui disparaissent) : seule à contenir un
## `discard`, pour que les zombies vivants gardent la pré-passe de profondeur
## et les passes d'ombre simples.
static func dissolve_material() -> ShaderMaterial:
	if _dissolve_material == null:
		_dissolve_material = ShaderMaterial.new()
		_dissolve_material.shader = preload("res://assets/shaders/zombie_dissolve.gdshader")
		_dissolve_material.set_shader_parameter("emission_color", EYE_EMISSION)
		_dissolve_material.set_shader_parameter("emission_energy", 6.5)
		_dissolve_material.set_shader_parameter("noise_lattice", NoiseLattice.tex3d())
	return _dissolve_material


## Dissolution (0 : intact, 1 : disparu) du maillage d'un zombie.
static func set_dissolve(mi: MeshInstance3D, k: float) -> void:
	var want := dissolve_material() if k > 0.0 else material()
	if mi.material_override != want:
		mi.material_override = want
	mi.set_instance_shader_parameter("dissolve", k)


## Look (0..LOOK_COUNT-1) de la variante.
static func look_key(variant: int) -> int:
	return posmod(variant, LOOK_COUNT)


static func archetype(variant: int) -> int:
	return ARCH_SEQ[look_key(variant) % ARCH_SEQ.size()]


## Première variante de l'archétype `arch` (n-ième occurrence) : captures, tests.
static func variant_of(arch: int, n := 0) -> int:
	var seen := 0
	for k in LOOK_COUNT:
		if archetype(k) == arch:
			if seen == n:
				return k
			seen += 1
	return 0


static func build(variant: int) -> Skeleton3D:
	var key := look_key(variant)
	if _skin == null:
		var tmp := RigBuilder.build_skeleton()
		_skin = tmp.create_skin_from_rest_transforms()
		tmp.free()
		prewarm_async()
	var skel := RigBuilder.instantiate(_mesh(key), material(), {}, _skin)
	(skel.get_node("Mesh") as MeshInstance3D).layers = RENDER_LAYERS
	return skel


## Mesh (partagé) du look `key` : préparé par le thread de travail s'il est
## prêt, sinon construit tout de suite.
static func _mesh(key: int) -> ArrayMesh:
	if _meshes.has(key):
		return _meshes[key]
	_mutex.lock()
	var arr: Variant = _ready_arrays.get(key)
	_ready_arrays.erase(key)
	_claimed[key] = true
	_mutex.unlock()
	if arr == null:
		var d := parts_for(key)
		arr = RigBuilder.build_arrays(d[0], d[1], d[2])
	_meshes[key] = RigBuilder.mesh_from_arrays(arr)
	return _meshes[key]


## Prépare en arrière-plan (WorkerThreadPool) les tableaux de tous les looks :
## aucun zombie n'a à attendre la construction de son mesh (~20 ms par look)
## en pleine manche. Lancé au premier zombie construit (préchauffage).
static func prewarm_async() -> void:
	if _task != -1:
		return
	_origin("hips")  # repos initialisés sur le thread principal
	_task = WorkerThreadPool.add_task(_prewarm_all, false, "Looks des zombies")


static func _prewarm_all() -> void:
	for k in LOOK_COUNT:
		_mutex.lock()
		var skip: bool = _claimed.has(k)
		_claimed[k] = true
		_mutex.unlock()
		if skip:
			continue
		var d := parts_for(k)
		var arr := RigBuilder.build_arrays(d[0], d[1], d[2])
		_mutex.lock()
		_ready_arrays[k] = arr
		_mutex.unlock()


## Attend la fin du préchauffage (tests, mesures).
static func wait_prewarm() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -2


## Nombre de sommets du mesh d'un look (mesures).
static func vertex_count(variant: int) -> int:
	return _mesh(look_key(variant)).surface_get_array_len(0)


## Morceau de corps arraché (démembrement) : mesh non skinné des pièces des
## os `limb_bones`, dans le repère de repos du premier os. Mêmes couleurs que
## le zombie `variant` (déterministe, mis en cache).
static func limb_mesh(variant: int, limb_bones: Array) -> ArrayMesh:
	var key := "%d:%s" % [look_key(variant), ",".join(limb_bones)]
	if not _limbs.has(key):
		var d := parts_for(look_key(variant))
		_limbs[key] = RigBuilder.build_static(d[0], limb_bones, {}, d[2])
	return _limbs[key]


## Vide les caches (tests de coût de construction).
static func clear_cache() -> void:
	wait_prewarm()
	_meshes.clear()
	_limbs.clear()
	_ready_arrays.clear()
	_claimed.clear()


# --------------------------------------------------------------------------
# Construction des pièces
# --------------------------------------------------------------------------

## Origine de repos (repère du modèle) de l'os `b`.
static func _origin(b: String) -> Vector3:
	if _rest.is_empty():
		_rest = RigBuilder._rest_globals({})
	return (_rest[b] as Transform3D).origin


## Point exprimé relativement au bassin -> relatif à l'os `b`.
static func _at(b: String, hr: Vector3) -> Vector3:
	return hr + Vector3(0, HIPS_Y, 0) - _origin(b)


static func _ell(bone: String, size: Vector3, center: Vector3, color: Color, mat: int, extra := {}) -> Dictionary:
	var d := {"shape": "ell", "bone": bone, "size": size, "center": center, "color": color, "mat": mat}
	d.merge(extra, true)
	return d


static func _box(bone: String, size: Vector3, center: Vector3, color: Color, mat: int, rot := Vector3.ZERO) -> Dictionary:
	return {"shape": "box", "bone": bone, "size": size, "center": center, "color": color, "mat": mat, "rot": rot}


static func _loft(bone: String, rings: Array, color: Color, mat: int, extra := {}) -> Dictionary:
	var d := {"shape": "loft", "bone": bone, "rings": rings, "color": color, "mat": mat}
	d.merge(extra, true)
	return d


## Rayons du torse à la hauteur `y` (relative au bassin), interpolés.
static func _torso_r(y: float) -> Vector2:
	for i in TORSO.size() - 1:
		var a: Array = TORSO[i]
		var b: Array = TORSO[i + 1]
		if y <= a[0] and y >= b[0]:
			var t: float = (a[0] - y) / (a[0] - b[0])
			return Vector2(lerpf(a[1], b[1], t), lerpf(a[2], b[2], t))
	var last: Array = TORSO[TORSO.size() - 1]
	return Vector2(last[1], last[2])


## Poids d'os du torse selon la hauteur.
static func _torso_w(y: float) -> Dictionary:
	if y >= 0.64:
		return {"chest": 0.55, "neck": 0.45}
	if y >= 0.42:
		return {"chest": 1.0}
	if y >= 0.3:
		return {"chest": 0.5, "spine": 0.5}
	if y >= 0.18:
		return {"spine": 1.0}
	if y >= 0.08:
		return {"spine": 0.5, "hips": 0.5}
	return {"hips": 1.0}


## Os dominant du torse à la hauteur `y` (pièces rigides : poches, plaies).
static func _torso_bone(y: float) -> String:
	if y >= 0.6:
		return "chest"
	if y >= 0.3:
		return "chest"
	if y >= 0.1:
		return "spine"
	return "hips"


## Point (relatif au bassin) et angle de la surface du torse : hauteur `y`,
## angle `ang` autour de l'axe (0 = devant, + vers la gauche du zombie),
## épaisseur de vêtement `pad`.
static func _torso_point(y: float, ang: float, pad: float, broad: float) -> Vector3:
	var r := _torso_r(y)
	return Vector3(sin(ang) * (r.x * broad + pad), y, cos(ang) * (r.y + pad))


## Pièce plate plaquée sur le torse (plaie, poche, bouton...).
static func _on_torso(y: float, ang: float, pad: float, broad: float, size: Vector3, color: Color, mat: int, shape := "ell") -> Dictionary:
	var hr := _torso_point(y, ang, pad, broad)
	var bone := _torso_bone(y)
	var rot := Vector3(0, rad_to_deg(ang), 0)
	if shape == "box":
		return _box(bone, size, _at(bone, hr), color, mat, rot)
	return _ell(bone, size, _at(bone, hr), color, mat, {"rot": rot, "rings": 4, "sides": 7})


## Tube du torse (vêtement ou peau) entre les hauteurs `top` et `bottom`, avec
## éventuellement une jupe (pans de veste, blouse) qui suit les cuisses.
static func _torso_loft(top: float, bottom: float, pad: float, broad: float, color: Color, mat: int, skirt: Array, jag: float, seed: int, sides := 12) -> Dictionary:
	var rings: Array = []
	for row in TORSO:
		var y: float = row[0]
		if y > top + 0.001 or y < bottom - 0.001:
			continue
		var r := _torso_r(y)
		rings.append([_at("hips", Vector3(0, y, 0)), Vector2(r.x * broad + pad, r.y + pad), _torso_w(y)])
	for s in skirt:
		# [hauteur, demi-largeur, demi-profondeur, décalage avant]
		rings.append([_at("hips", Vector3(0, s[0], s[3] if s.size() > 3 else 0.0)), Vector2(s[1] * broad, s[2]), {"hips": 1.0}])
	var extra := {"sides": sides, "jag": jag, "seed": seed, "wfn": _skirt_weights}
	return _loft("hips", rings, color, mat, extra)


## Pans sous la ceinture : liés progressivement aux cuisses (la veste ou la
## blouse suit les jambes au lieu d'être traversée par elles).
static func _skirt_weights(p: Vector3, w: Dictionary) -> Dictionary:
	var y := p.y - HIPS_Y
	if y > -0.03:
		return w
	var t := clampf((-0.03 - y) / 0.25, 0.0, 1.0) * 0.8
	var a := smoothstep(-0.06, 0.06, p.x)
	return {"hips": 1.0 - t, "thigh_l": t * a, "thigh_r": t * (1.0 - a)}


## Semelle plate au sol.
static func _sole(p: Vector3, _ang: float, _i: int) -> Vector3:
	return Vector3(p.x, maxf(p.y, 0.004), p.z)


## [pièces, positions de repos surchargées, taches de sang] du look `variant`.
static func parts_for(variant: int) -> Array:
	var key := look_key(variant)
	var rng := RandomNumberGenerator.new()
	rng.seed = key * 7919 + 17
	var arch: int = ARCH_SEQ[key % ARCH_SEQ.size()]
	var p: Array = []
	var skin: Color = SKINS[rng.randi() % SKINS.size()]
	skin = skin.lerp(Color(0.44, 0.5, 0.4), rng.randf() * 0.35)
	var broad := rng.randf_range(0.92, 1.06)
	var soldier := arch <= Arch.RAGGED
	var tunic: Color = FELDGRAU[rng.randi() % FELDGRAU.size()]
	tunic = tunic.darkened(rng.randf() * 0.12)
	var trousers: Color = TROUSERS[rng.randi() % TROUSERS.size()] if soldier else CIV_TROUSERS[rng.randi() % CIV_TROUSERS.size()]
	if arch == Arch.OFFICER:
		tunic = tunic.darkened(0.12)
		trousers = Color(0.24, 0.24, 0.21)
	# Manches déchirées (bras nu dessous) : gauche, droite.
	var torn := [rng.randf() < 0.35, rng.randf() < 0.3]
	var seed := key * 31 + 5

	# --- Torse -------------------------------------------------------------
	match arch:
		Arch.HELMET, Arch.CAP, Arch.OFFICER:
			var hem := [[-0.13, 0.172, 0.122], [-0.2, 0.178, 0.126]]
			p.append(_torso_loft(0.66, -0.06, 0.012, broad, tunic, RigBuilder.MAT_CLOTH, hem, 0.05, seed))
			_uniform_details(p, rng, broad, tunic, arch)
		Arch.RAGGED:
			p.append(_torso_loft(0.66, 0.03, 0.0, broad, skin, RigBuilder.MAT_SKIN, [], 0.0, seed))
			_ribs(p, broad, skin)
			# Pantalon remonté jusqu'à la taille, bretelles.
			p.append(_torso_loft(0.13, -0.06, 0.012, broad, trousers, RigBuilder.MAT_CLOTH, [[-0.13, 0.165, 0.118]], 0.0, seed))
			for sgn in [-1.0, 1.0]:
				for k in 4:
					var y := 0.18 + k * 0.1
					p.append(_on_torso(y, sgn * 0.42, 0.004, broad, Vector3(0.028, 0.105, 0.01), LEATHER_BROWN, RigBuilder.MAT_LEATHER, "box"))
					p.append(_on_torso(y, PI - sgn * 0.45, 0.004, broad, Vector3(0.028, 0.105, 0.01), LEATHER_BROWN, RigBuilder.MAT_LEATHER, "box"))
			_belt(p, broad, LEATHER, false)
		Arch.SCIENTIST:
			var coat: Color = COAT[rng.randi() % COAT.size()]
			var skirt := [[-0.14, 0.19, 0.135], [-0.3, 0.205, 0.145], [-0.46, 0.215, 0.15], [-0.56, 0.22, 0.152]]
			p.append(_torso_loft(0.66, -0.06, 0.02, broad, coat, RigBuilder.MAT_CLOTH, skirt, 0.07, seed))
			# Chemise et cravate dans l'encolure, boutons, poche de poitrine.
			p.append(_on_torso(0.56, 0.0, 0.021, broad, Vector3(0.05, 0.1, 0.012), SHIRT[0], RigBuilder.MAT_CLOTH, "box"))
			p.append(_on_torso(0.5, 0.0, 0.026, broad, Vector3(0.026, 0.14, 0.008), Color(0.12, 0.1, 0.12), RigBuilder.MAT_CLOTH, "box"))
			for k in 4:
				p.append(_on_torso(0.38 - k * 0.12, 0.05, 0.022, broad, Vector3(0.014, 0.014, 0.008), Color(0.3, 0.3, 0.28), RigBuilder.MAT_BONE, "box"))
			p.append(_on_torso(0.45, 0.55, 0.022, broad, Vector3(0.08, 0.07, 0.008), coat.darkened(0.12), RigBuilder.MAT_CLOTH, "box"))
			tunic = coat
		Arch.CIVILIAN:
			var shirt: Color = SHIRT[rng.randi() % SHIRT.size()]
			p.append(_torso_loft(0.66, -0.06, 0.008, broad, shirt, RigBuilder.MAT_CLOTH, [[-0.12, 0.165, 0.118]], 0.03, seed))
			# Gilet sans manches par-dessus (ouvert au col).
			var vest: Color = VEST[rng.randi() % VEST.size()]
			p.append(_torso_loft(0.54, -0.02, 0.02, broad, vest, RigBuilder.MAT_CLOTH, [[-0.08, 0.165, 0.122]], 0.025, seed + 1))
			for k in 4:
				p.append(_on_torso(0.44 - k * 0.1, 0.0, 0.021, broad, Vector3(0.013, 0.013, 0.008), Color(0.15, 0.13, 0.1), RigBuilder.MAT_BONE, "box"))
			tunic = shirt
			torn = [true, true]  # manches retroussées

	_neck(p, skin)
	_head(p, rng, skin, arch)
	# --- Bras --------------------------------------------------------------
	var sleeve := tunic
	for side in ["l", "r"]:
		var sgn := 1.0 if side == "l" else -1.0
		_arm(p, side, sgn, sleeve, skin, torn[0 if side == "l" else 1], arch == Arch.CIVILIAN, seed + (3 if side == "l" else 4))
	# --- Jambes ------------------------------------------------------------
	var boots := arch <= Arch.RAGGED
	for side in ["l", "r"]:
		_leg(p, side, trousers, boots, arch == Arch.OFFICER, seed + (7 if side == "l" else 8))
	# --- Plaies et sang ----------------------------------------------------
	var blood: Array = []
	_wounds(p, blood, rng, broad, arch)
	return [p, {}, blood]


static func _neck(p: Array, skin: Color) -> void:
	# Cou décharné (tendons), du col à la base du crâne.
	p.append(_loft("neck", [
		[Vector3(0, 0.13, 0.0), Vector2(0.042, 0.044), {"head": 1.0}],
		[Vector3(0, 0.07, 0.005), Vector2(0.041, 0.042), {"neck": 0.5, "head": 0.5}],
		[Vector3(0, 0.02, 0.005), Vector2(0.045, 0.045), {"neck": 1.0}],
		[Vector3(0, -0.04, 0.0), Vector2(0.056, 0.055), {"neck": 0.4, "chest": 0.6}],
	], skin, RigBuilder.MAT_SKIN, {"sides": 8}))
	# Moignon (visible si la tête éclate).
	p.append(_ell("neck", Vector3(0.075, 0.03, 0.075), Vector3(0, 0.07, 0.005), FLESH, RigBuilder.MAT_WOUND, {"rings": 3, "sides": 7}))
	# Tendons saillants.
	for sgn in [-1.0, 1.0]:
		p.append(_ell("neck", Vector3(0.018, 0.12, 0.018), Vector3(sgn * 0.024, 0.04, 0.035), skin.darkened(0.08), RigBuilder.MAT_SKIN, {"rot": Vector3(0, 0, sgn * 18), "rings": 4, "sides": 5}))


static func _head(p: Array, rng: RandomNumberGenerator, skin: Color, arch: int) -> void:
	var dark := skin.darkened(0.22)
	# Crâne, visage creusé, arcades.
	p.append(_ell("head", Vector3(0.158, 0.2, 0.192), Vector3(0, 0.1, -0.006), skin, RigBuilder.MAT_SKIN, {"rings": 8, "sides": 12}))
	p.append(_ell("head", Vector3(0.122, 0.085, 0.118), Vector3(0, 0.07, 0.035), dark, RigBuilder.MAT_SKIN, {"rings": 5, "sides": 10}))
	p.append(_ell("head", Vector3(0.148, 0.03, 0.06), Vector3(0, 0.142, 0.075), dark, RigBuilder.MAT_SKIN, {"rings": 3, "sides": 8}))
	# Yeux enfoncés : cernes sombres autour des orbites.
	p.append(_ell("head", Vector3(0.118, 0.05, 0.03), Vector3(0, 0.116, 0.079), skin.darkened(0.55), RigBuilder.MAT_SKIN, {"rings": 4, "sides": 10}))
	for sgn in [-1.0, 1.0]:
		# Orbites sombres et yeux jaunes lumineux.
		p.append(_ell("head", Vector3(0.043, 0.032, 0.022), Vector3(sgn * 0.036, 0.117, 0.087), SOCKET, RigBuilder.MAT_WOUND, {"rings": 3, "sides": 7}))
		p.append({"shape": "ell", "bone": "head", "size": Vector3(0.025, 0.02, 0.012), "center": Vector3(sgn * 0.036, 0.117, 0.095),
				"color": EYE, "emit": 1.0, "mat": RigBuilder.MAT_SKIN, "rings": 3, "sides": 6})
		# Pommettes saillantes, oreilles.
		p.append(_ell("head", Vector3(0.036, 0.028, 0.045), Vector3(sgn * 0.047, 0.088, 0.068), skin, RigBuilder.MAT_SKIN, {"rings": 3, "sides": 6}))
		p.append(_ell("head", Vector3(0.018, 0.05, 0.034), Vector3(sgn * 0.079, 0.1, -0.005), dark, RigBuilder.MAT_SKIN, {"rings": 3, "sides": 6}))
	# Nez (parfois rongé : trou sombre).
	if rng.randf() < 0.3:
		p.append(_ell("head", Vector3(0.026, 0.03, 0.02), Vector3(0, 0.094, 0.1), SOCKET, RigBuilder.MAT_WOUND, {"rings": 3, "sides": 6}))
	else:
		p.append(_ell("head", Vector3(0.022, 0.048, 0.03), Vector3(0, 0.096, 0.1), dark, RigBuilder.MAT_SKIN, {"rot": Vector3(-18, 0, 0), "rings": 3, "sides": 6}))
	# Bouche : intérieur rouge sombre, dents supérieures sans lèvres.
	p.append(_ell("head", Vector3(0.07, 0.05, 0.06), Vector3(0, 0.05, 0.05), BLOOD_DARK, RigBuilder.MAT_WOUND, {"rings": 3, "sides": 7}))
	p.append(_ell("head", Vector3(0.066, 0.02, 0.026), Vector3(0, 0.052, 0.086), TEETH, RigBuilder.MAT_BONE, {"rings": 3, "sides": 7}))
	# Mâchoire pendante (os « jaw » : animée) avec dents inférieures.
	p.append(_ell("jaw", Vector3(0.104, 0.045, 0.1), Vector3(0, -0.032, 0.045), dark, RigBuilder.MAT_SKIN, {"rot": Vector3(-8, 0, 0), "rings": 4, "sides": 8}))
	p.append(_ell("jaw", Vector3(0.06, 0.018, 0.02), Vector3(0, -0.012, 0.086), TEETH, RigBuilder.MAT_BONE, {"rings": 3, "sides": 6}))
	p.append(_ell("jaw", Vector3(0.05, 0.03, 0.02), Vector3(0, -0.05, 0.085), BLOOD, RigBuilder.MAT_WOUND, {"rings": 3, "sides": 6}))
	# Joue arrachée (dents visibles sur le côté).
	if rng.randf() < 0.45:
		var sgn := 1.0 if rng.randf() < 0.5 else -1.0
		p.append(_ell("head", Vector3(0.02, 0.04, 0.05), Vector3(sgn * 0.056, 0.064, 0.058), FLESH, RigBuilder.MAT_WOUND, {"rings": 3, "sides": 6}))
		p.append(_ell("head", Vector3(0.012, 0.016, 0.035), Vector3(sgn * 0.06, 0.056, 0.062), TEETH, RigBuilder.MAT_BONE, {"rings": 3, "sides": 5}))
	# Couvre-chef.
	match arch:
		Arch.HELMET:
			_helmet(p)
		Arch.CAP:
			if rng.randf() < 0.75:
				_field_cap(p, FELDGRAU[rng.randi() % FELDGRAU.size()].darkened(0.1))
			else:
				_hair(p, rng)
		Arch.OFFICER:
			_officer_cap(p)
		Arch.CIVILIAN:
			if rng.randf() < 0.6:
				_flat_cap(p, VEST[rng.randi() % VEST.size()].lightened(0.05))
			else:
				_hair(p, rng)
		_:
			if rng.randf() < 0.6:
				_hair(p, rng)
			else:
				# Crâne chauve, plaie ouverte jusqu'à l'os.
				p.append(_ell("head", Vector3(0.06, 0.02, 0.06), Vector3(rng.randf_range(-0.03, 0.03), 0.198, -0.02), BONE, RigBuilder.MAT_BONE, {"rot": Vector3(-20, 0, 0), "rings": 3, "sides": 7}))
				p.append(_ell("head", Vector3(0.075, 0.018, 0.075), Vector3(0, 0.194, -0.02), BLOOD, RigBuilder.MAT_WOUND, {"rot": Vector3(-20, 0, 0), "rings": 3, "sides": 7}))


static func _hair(p: Array, rng: RandomNumberGenerator) -> void:
	var c: Color = HAIR[rng.randi() % HAIR.size()]
	p.append(_ell("head", Vector3(0.168, 0.16, 0.2), Vector3(0, 0.125, -0.014), c, RigBuilder.MAT_CLOTH, {"rot": Vector3(-14, 0, 0), "half": true, "rings": 4, "sides": 10}))


## Casque d'acier M35 : dôme, bord évasé sur la nuque et les oreilles, visière
## courte relevée au-dessus des yeux.
static func _helmet(p: Array) -> void:
	var raise := func(pos: Vector3, ang: float, i: int) -> Vector3:
		if i >= 4:
			var front := maxf(0.0, cos(ang))
			pos.y += 0.045 * front * front
		return pos
	p.append(_loft("head", [
		[Vector3(0, 0.248, -0.012), Vector2(0.02, 0.022)],
		[Vector3(0, 0.238, -0.012), Vector2(0.078, 0.088)],
		[Vector3(0, 0.212, -0.012), Vector2(0.113, 0.128)],
		[Vector3(0, 0.172, -0.012), Vector2(0.126, 0.143)],
		[Vector3(0, 0.125, -0.014), Vector2(0.13, 0.148)],
		[Vector3(0, 0.09, -0.02), Vector2(0.148, 0.166)],
	], HELMET_PAINT, RigBuilder.MAT_METAL, {"sides": 12, "cap_top": true, "cap_bottom": true, "deform": raise}))
	# Jugulaire.
	for sgn in [-1.0, 1.0]:
		p.append(_box("head", Vector3(0.008, 0.1, 0.012), Vector3(sgn * 0.075, 0.07, 0.01), LEATHER, RigBuilder.MAT_LEATHER, Vector3(0, 0, -sgn * 6)))


## Casquette M43 (calot à visière).
static func _field_cap(p: Array, c: Color) -> void:
	p.append(_loft("head", [
		[Vector3(0, 0.232, -0.01), Vector2(0.094, 0.11)],
		[Vector3(0, 0.215, -0.01), Vector2(0.105, 0.12)],
		[Vector3(0, 0.155, -0.01), Vector2(0.1, 0.116)],
		[Vector3(0, 0.145, -0.012), Vector2(0.101, 0.117)],
	], c, RigBuilder.MAT_CLOTH, {"sides": 10, "cap_top": true}))
	p.append(_ell("head", Vector3(0.12, 0.012, 0.07), Vector3(0, 0.152, 0.11), c.darkened(0.1), RigBuilder.MAT_CLOTH, {"rot": Vector3(-12, 0, 0), "rings": 3, "sides": 8}))
	p.append(_box("head", Vector3(0.022, 0.018, 0.008), Vector3(0, 0.19, 0.117), METAL, RigBuilder.MAT_METAL))


## Casquette d'officier à visière haute (bandeau sombre, plateau relevé).
static func _officer_cap(p: Array) -> void:
	p.append(_loft("head", [
		[Vector3(0, 0.205, -0.008), Vector2(0.1, 0.113)],
		[Vector3(0, 0.15, -0.008), Vector2(0.098, 0.112)],
	], COLLAR, RigBuilder.MAT_CLOTH, {"sides": 10}))
	p.append(_ell("head", Vector3(0.235, 0.055, 0.265), Vector3(0, 0.228, 0.005), HELMET_PAINT.lightened(0.05), RigBuilder.MAT_CLOTH, {"rot": Vector3(-10, 0, 0), "rings": 4, "sides": 12}))
	p.append(_ell("head", Vector3(0.15, 0.014, 0.075), Vector3(0, 0.152, 0.118), LEATHER, RigBuilder.MAT_LEATHER, {"rot": Vector3(-18, 0, 0), "rings": 3, "sides": 8}))
	p.append(_box("head", Vector3(0.14, 0.008, 0.01), Vector3(0, 0.172, 0.113), METAL.lightened(0.2), RigBuilder.MAT_METAL))
	p.append(_box("head", Vector3(0.034, 0.022, 0.01), Vector3(0, 0.215, 0.12), METAL.lightened(0.25), RigBuilder.MAT_METAL, Vector3(-12, 0, 0)))


## Casquette plate (civil).
static func _flat_cap(p: Array, c: Color) -> void:
	p.append(_ell("head", Vector3(0.185, 0.07, 0.215), Vector3(0, 0.19, 0.005), c, RigBuilder.MAT_CLOTH, {"rot": Vector3(-8, 0, 0), "half": true, "rings": 3, "sides": 10}))
	p.append(_ell("head", Vector3(0.14, 0.012, 0.07), Vector3(0, 0.188, 0.105), c.darkened(0.1), RigBuilder.MAT_CLOTH, {"rot": Vector3(-6, 0, 0), "rings": 3, "sides": 8}))


## Tunique feldgrau : col, boutons, poches, ceinturon, cartouchières, brelages.
static func _uniform_details(p: Array, rng: RandomNumberGenerator, broad: float, tunic: Color, arch: int) -> void:
	var pad := 0.013
	# Col vert bouteille.
	p.append(_loft("chest", [
		[_at("chest", Vector3(0, 0.672, 0.004)), Vector2(0.057, 0.06), {"chest": 0.5, "neck": 0.5}],
		[_at("chest", Vector3(0, 0.628, 0.0)), Vector2(0.074, 0.074)],
	], COLLAR, RigBuilder.MAT_CLOTH, {"sides": 10}))
	# Boutons, poches plaquées à rabat.
	var button := Color(0.42, 0.42, 0.38)
	for k in 5:
		p.append(_on_torso(0.56 - k * 0.11, 0.0, pad + 0.002, broad, Vector3(0.016, 0.016, 0.008), button, RigBuilder.MAT_METAL, "box"))
	for sgn in [-1.0, 1.0]:
		p.append(_on_torso(0.44, sgn * 0.48, pad + 0.002, broad, Vector3(0.08, 0.1, 0.012), tunic.darkened(0.06), RigBuilder.MAT_CLOTH, "box"))
		p.append(_on_torso(0.5, sgn * 0.48, pad + 0.006, broad, Vector3(0.085, 0.035, 0.012), tunic.darkened(0.15), RigBuilder.MAT_CLOTH, "box"))
		p.append(_on_torso(0.03, sgn * 0.62, pad + 0.004, broad, Vector3(0.1, 0.1, 0.014), tunic.darkened(0.08), RigBuilder.MAT_CLOTH, "box"))
		# Pattes d'épaule.
		p.append(_box("chest", Vector3(0.05, 0.012, 0.1), _at("chest", Vector3(sgn * 0.14, 0.598, 0.0)), tunic.darkened(0.2), RigBuilder.MAT_CLOTH, Vector3(0, 0, sgn * 16)))
	_belt(p, broad, LEATHER, true)
	if arch == Arch.OFFICER:
		# Baudrier en travers du torse.
		for k in 4:
			var t := float(k) / 3.0
			var y := lerpf(0.56, 0.15, t)
			p.append(_on_torso(y, lerpf(0.9, -0.5, t), pad + 0.004, broad, Vector3(0.032, 0.13, 0.008), LEATHER_BROWN, RigBuilder.MAT_LEATHER, "box"))
		return
	# Cartouchières sur le ventre, brelages en Y.
	for sgn in [-1.0, 1.0]:
		for k in 3:
			p.append(_on_torso(0.11, sgn * (0.28 + k * 0.24), pad + 0.018, broad, Vector3(0.042, 0.055, 0.03), LEATHER, RigBuilder.MAT_LEATHER, "box"))
		for k in 3:
			p.append(_on_torso(0.25 + k * 0.12, sgn * 0.42, pad + 0.004, broad, Vector3(0.026, 0.13, 0.008), LEATHER, RigBuilder.MAT_LEATHER, "box"))
			p.append(_on_torso(0.25 + k * 0.12, PI - sgn * 0.3, pad + 0.004, broad, Vector3(0.026, 0.13, 0.008), LEATHER, RigBuilder.MAT_LEATHER, "box"))
	# Boîtier cylindrique de masque à gaz dans le dos, ou gourde sur la hanche.
	if rng.randf() < 0.55:
		p.append(_loft("hips", [
			[_at("hips", Vector3(0.0, 0.2, -0.14)), Vector2(0.042, 0.042)],
			[_at("hips", Vector3(0.0, 0.02, -0.145)), Vector2(0.042, 0.042)],
		], HELMET_PAINT.darkened(0.2), RigBuilder.MAT_METAL, {"sides": 8, "cap_top": true, "cap_bottom": true}))
	else:
		p.append(_ell("hips", Vector3(0.06, 0.12, 0.05), _at("hips", Vector3(-0.16, 0.0, -0.06)), Color(0.24, 0.22, 0.17), RigBuilder.MAT_CLOTH, {"rings": 4, "sides": 7}))


static func _belt(p: Array, broad: float, c: Color, buckle: bool) -> void:
	var rings: Array = []
	for y in [0.145, 0.085]:
		var r := _torso_r(y)
		rings.append([_at("hips", Vector3(0, y, 0)), Vector2(r.x * broad + 0.022, r.y + 0.022), _torso_w(y)])
	p.append(_loft("hips", rings, c, RigBuilder.MAT_LEATHER, {"sides": 12}))
	if buckle:
		p.append(_on_torso(0.115, 0.0, 0.026, broad, Vector3(0.06, 0.048, 0.01), METAL, RigBuilder.MAT_METAL, "box"))


## Côtes saillantes du torse nu.
static func _ribs(p: Array, broad: float, skin: Color) -> void:
	for sgn in [-1.0, 1.0]:
		for k in 4:
			var y := 0.46 - k * 0.055
			p.append(_on_torso(y, sgn * 0.45, 0.0, broad, Vector3(0.1, 0.014, 0.012), skin.darkened(0.12), RigBuilder.MAT_SKIN, "ell"))
	# Sternum, clavicules.
	p.append(_on_torso(0.45, 0.0, 0.0, broad, Vector3(0.025, 0.16, 0.012), skin.darkened(0.1), RigBuilder.MAT_SKIN))
	for sgn in [-1.0, 1.0]:
		p.append(_box("chest", Vector3(0.12, 0.018, 0.02), _at("chest", Vector3(sgn * 0.08, 0.575, 0.06)), skin.darkened(0.08), RigBuilder.MAT_SKIN, Vector3(0, 0, sgn * -12)))


static func _arm(p: Array, side: String, sgn: float, sleeve: Color, skin: Color, torn: bool, rolled: bool, seed: int) -> void:
	var arm := "arm_" + side
	var fore := "forearm_" + side
	var shoulder := {"chest": 0.5, arm: 0.5}
	var elbow := {arm: 0.5, fore: 0.5}
	# Épaule arrondie + manche du haut du bras.
	p.append(_loft(arm, [
		[Vector3(-sgn * 0.01, 0.045, 0.0), Vector2(0.05, 0.05), shoulder],
		[Vector3(0, 0.0, 0.0), Vector2(0.057, 0.055), {"chest": 0.25, arm: 0.75}],
		[Vector3(0, -0.1, 0.0), Vector2(0.051, 0.05)],
		[Vector3(0, -0.22, 0.0), Vector2(0.047, 0.046)],
		[Vector3(0, -0.3 if not torn else -0.25, 0.0), Vector2(0.046, 0.045), elbow if not torn else null],
	], sleeve, RigBuilder.MAT_CLOTH, {"sides": 9, "cap_top": true, "jag": 0.05 if torn else 0.0, "seed": seed}))
	# Moignon (visible si l'avant-bras est arraché).
	p.append(_ell(arm, Vector3(0.058, 0.045, 0.058), Vector3(0, -0.28, 0), FLESH, RigBuilder.MAT_WOUND, {"rings": 3, "sides": 7}))
	if torn:
		# Bras nu, osseux, sous la manche arrachée.
		p.append(_loft(arm, [
			[Vector3(0, -0.2, 0.0), Vector2(0.036, 0.036)],
			[Vector3(0, -0.3, 0.0), Vector2(0.036, 0.034), elbow],
		], skin, RigBuilder.MAT_SKIN, {"sides": 8}))
		p.append(_loft(fore, [
			[Vector3(0, 0.02, 0.0), Vector2(0.036, 0.034), {arm: 0.4, fore: 0.6}],
			[Vector3(0, -0.09, 0.004), Vector2(0.034, 0.032)],
			[Vector3(0, -0.2, 0.0), Vector2(0.027, 0.024)],
			[Vector3(0, -0.27, 0.0), Vector2(0.025, 0.022)],
		], skin, RigBuilder.MAT_SKIN, {"sides": 8}))
		if rolled:
			p.append(_loft(arm, [
				[Vector3(0, -0.24, 0.0), Vector2(0.05, 0.049)],
				[Vector3(0, -0.29, 0.0), Vector2(0.049, 0.048), elbow],
			], sleeve.darkened(0.05), RigBuilder.MAT_CLOTH, {"sides": 9}))
		else:
			# Entaille sur l'avant-bras.
			p.append(_ell(fore, Vector3(0.02, 0.09, 0.012), Vector3(sgn * 0.01, -0.1, 0.03), BLOOD, RigBuilder.MAT_WOUND, {"rings": 3, "sides": 6}))
	else:
		p.append(_loft(fore, [
			[Vector3(0, 0.02, 0.0), Vector2(0.046, 0.045), {arm: 0.4, fore: 0.6}],
			[Vector3(0, -0.1, 0.004), Vector2(0.044, 0.043)],
			[Vector3(0, -0.22, 0.0), Vector2(0.04, 0.04)],
			[Vector3(0, -0.25, 0.0), Vector2(0.042, 0.041)],
		], sleeve, RigBuilder.MAT_CLOTH, {"sides": 9, "cap_bottom": true}))
		p.append(_loft(fore, [
			[Vector3(0, -0.23, 0.0), Vector2(0.028, 0.025)],
			[Vector3(0, -0.28, 0.0), Vector2(0.025, 0.022)],
		], skin, RigBuilder.MAT_SKIN, {"sides": 7}))
	_hand(p, fore, sgn, skin)


## Main décharnée aux doigts crochus.
static func _hand(p: Array, fore: String, sgn: float, skin: Color) -> void:
	p.append(_ell(fore, Vector3(0.032, 0.085, 0.068), Vector3(0, -0.315, 0.006), skin, RigBuilder.MAT_SKIN, {"rings": 4, "sides": 7}))
	p.append(_loft(fore, [
		[Vector3(0, -0.34, 0.012), Vector2(0.015, 0.032)],
		[Vector3(0, -0.38, 0.024), Vector2(0.013, 0.029)],
		[Vector3(0, -0.41, 0.04), Vector2(0.011, 0.024), null, skin.darkened(0.35)],
	], skin.darkened(0.1), RigBuilder.MAT_SKIN, {"sides": 6, "cap_bottom": true}))
	p.append(_ell(fore, Vector3(0.018, 0.05, 0.018), Vector3(-sgn * 0.01, -0.31, 0.042), skin.darkened(0.08), RigBuilder.MAT_SKIN, {"rot": Vector3(35, 0, 0), "rings": 3, "sides": 5}))


static func _leg(p: Array, side: String, trousers: Color, boots: bool, breeches: bool, seed: int) -> void:
	var thigh := "thigh_" + side
	var shin := "shin_" + side
	var knee := {thigh: 0.5, shin: 0.5}
	var baggy := 0.022 if breeches else 0.006
	p.append(_loft(thigh, [
		[Vector3(0, 0.08, 0.0), Vector2(0.09, 0.096), {"hips": 0.7, thigh: 0.3}],
		[Vector3(0, -0.04, 0.0), Vector2(0.088 + baggy * 0.5, 0.094 + baggy * 0.5), {"hips": 0.25, thigh: 0.75}],
		[Vector3(0, -0.18, 0.0), Vector2(0.08 + baggy, 0.084 + baggy)],
		[Vector3(0, -0.34, 0.0), Vector2(0.066 + baggy * 0.3, 0.07 + baggy * 0.3)],
		[Vector3(0, -0.45, 0.006), Vector2(0.061, 0.066), knee],
	], trousers, RigBuilder.MAT_CLOTH, {"sides": 9}))
	# Moignon de cuisse (visible quand la jambe est arrachée) : lié au bassin.
	var hip_stump := _at("hips", Vector3(0, 0, 0)) + (_origin(thigh) - _origin("hips")) + Vector3(0, -0.13, 0)
	p.append(_ell("hips", Vector3(0.12, 0.05, 0.12), hip_stump, FLESH, RigBuilder.MAT_WOUND, {"rings": 3, "sides": 7}))
	p.append(_ell("hips", Vector3(0.035, 0.03, 0.035), hip_stump + Vector3(0, -0.015, 0), BONE, RigBuilder.MAT_BONE, {"rings": 3, "sides": 5}))
	var bottom := -0.2 if boots else -0.4
	p.append(_loft(shin, [
		[Vector3(0, 0.03, 0.0), Vector2(0.062, 0.067), {thigh: 0.35, shin: 0.65}],
		[Vector3(0, -0.1, -0.004), Vector2(0.057, 0.062)],
		[Vector3(0, bottom, 0.0), Vector2(0.053 if boots else 0.052, 0.057 if boots else 0.056)],
	], trousers.darkened(0.04), RigBuilder.MAT_CLOTH, {"sides": 9, "jag": 0.0 if boots else 0.02, "seed": seed}))
	if boots:
		# Bottes de marche (tige haute jusqu'au mollet).
		var top := -0.08 if breeches else -0.13
		p.append(_loft(shin, [
			[Vector3(0, top, -0.004), Vector2(0.063, 0.068)],
			[Vector3(0, top - 0.02, -0.004), Vector2(0.062, 0.067)],
			[Vector3(0, -0.24, 0.0), Vector2(0.055, 0.058)],
			[Vector3(0, -0.34, 0.0), Vector2(0.047, 0.051)],
			[Vector3(0, -0.42, -0.006), Vector2(0.048, 0.055)],
		], LEATHER, RigBuilder.MAT_LEATHER, {"sides": 9, "cap_top": true}))
	else:
		p.append(_loft(shin, [
			[Vector3(0, -0.36, 0.0), Vector2(0.036, 0.038)],
			[Vector3(0, -0.43, -0.004), Vector2(0.04, 0.046)],
		], LEATHER_BROWN.darkened(0.3), RigBuilder.MAT_LEATHER, {"sides": 8}))
	# Pied (semelle plate au sol).
	p.append(_loft(shin, [
		[Vector3(0, -0.428, -0.058), Vector2(0.036, 0.03)],
		[Vector3(0, -0.44, -0.035), Vector2(0.046, 0.042)],
		[Vector3(0, -0.447, 0.045), Vector2(0.05, 0.036)],
		[Vector3(0, -0.456, 0.118), Vector2(0.043, 0.026)],
		[Vector3(0, -0.46, 0.152), Vector2(0.027, 0.018)],
	], LEATHER if boots else LEATHER_BROWN.darkened(0.3), RigBuilder.MAT_LEATHER, {"sides": 8, "axis": Vector3.BACK, "cap_top": true, "cap_bottom": true, "deform": _sole}))


## Tache de sang peinte (repère relatif au bassin).
static func _spot(blood: Array, hr: Vector3, radius: float, strength := 1.0) -> void:
	blood.append([hr + Vector3(0, HIPS_Y, 0), radius, strength])


## Plaies, côtes à vif, trous de balles, sang (peint), entrailles.
static func _wounds(p: Array, blood: Array, rng: RandomNumberGenerator, broad: float, arch: int) -> void:
	var pad := 0.022 if arch == Arch.SCIENTIST else (0.0 if arch == Arch.RAGGED else 0.014)
	# Bouche et menton ensanglantés ; coulée sur la poitrine.
	_spot(blood, Vector3(0, 0.735, 0.1), 0.05, 1.0)
	if rng.randf() < 0.75:
		var x := rng.randf_range(-0.08, 0.08)
		_spot(blood, Vector3(x * 0.5, 0.6, 0.12), 0.1, 1.1)
		_spot(blood, Vector3(x, 0.48, 0.13), 0.12, 0.9)
		if rng.randf() < 0.5:
			_spot(blood, Vector3(x * 1.3, 0.34, 0.12), 0.1, 0.7)
	# Mains et bas des manches rougis.
	for sgn in [-1.0, 1.0]:
		if rng.randf() < 0.6:
			_spot(blood, Vector3(sgn * 0.23, -0.13, 0.05), 0.08, 0.85)
			_spot(blood, Vector3(sgn * 0.23, 0.08, 0.03), 0.07, 0.6)
	# Déchirure du vêtement : chair et côtes à vif, sang autour.
	var holes := 1 + rng.randi() % 2
	for h in holes:
		var y := rng.randf_range(0.3, 0.5)
		var ang := rng.randf_range(0.25, 0.8) * (1.0 if rng.randf() < 0.5 else -1.0)
		if rng.randf() < 0.25:
			ang = PI + ang * 0.6  # dans le dos
		var hole := _on_torso(y, ang, pad + 0.001, broad, Vector3(0.1, 0.12, 0.016), FLESH.darkened(0.35), RigBuilder.MAT_WOUND)
		hole.sides = 10
		hole.rings = 5
		p.append(hole)
		for k in 3:
			p.append(_on_torso(y + 0.035 - k * 0.032, ang, pad + 0.004, broad, Vector3(0.075, 0.011, 0.011), BONE, RigBuilder.MAT_BONE))
		_spot(blood, _torso_point(y, ang, pad, broad), 0.14, 1.0)
		_spot(blood, _torso_point(y - 0.12, ang, pad, broad), 0.1, 0.8)
	# Impacts de balles (trou sombre, auréole de sang).
	for k in 2 + rng.randi() % 3:
		var y := rng.randf_range(0.05, 0.55)
		var ang := rng.randf_range(-1.2, 1.2)
		p.append(_on_torso(y, ang, pad + 0.002, broad, Vector3(0.018, 0.018, 0.008), BLOOD_DARK, RigBuilder.MAT_WOUND))
		_spot(blood, _torso_point(y, ang, pad, broad), 0.05, 0.9)
	# Grande tache sur le ventre ou le flanc, sur le pantalon.
	if rng.randf() < 0.6:
		_spot(blood, _torso_point(rng.randf_range(0.1, 0.3), rng.randf_range(-1.0, 1.0), pad, broad), 0.13, 0.9)
	if rng.randf() < 0.6:
		var sgn := 1.0 if rng.randf() < 0.5 else -1.0
		_spot(blood, Vector3(sgn * 0.1, rng.randf_range(-0.45, -0.15), 0.08), 0.12, 0.8)
	# Entrailles pendantes (rare).
	if rng.randf() < 0.12:
		var x := rng.randf_range(-0.06, 0.06)
		p.append(_loft("spine", [
			[_at("spine", Vector3(x, 0.2, 0.08)), Vector2(0.026, 0.024), {"spine": 1.0}],
			[_at("spine", Vector3(x + 0.02, 0.1, 0.12)), Vector2(0.024, 0.022), {"spine": 0.5, "hips": 0.5}],
			[_at("spine", Vector3(x - 0.01, 0.02, 0.125)), Vector2(0.02, 0.02), {"hips": 1.0}],
		], Color(0.42, 0.16, 0.15), RigBuilder.MAT_WOUND, {"sides": 7, "cap_bottom": true}))
		p.append(_on_torso(0.2, 0.0, pad, broad, Vector3(0.09, 0.09, 0.016), BLOOD_DARK, RigBuilder.MAT_WOUND))
		_spot(blood, Vector3(x, 0.12, 0.12), 0.14, 1.0)
	# Plaie au cou.
	if rng.randf() < 0.35:
		p.append(_ell("neck", Vector3(0.03, 0.05, 0.014), Vector3(rng.randf_range(-0.02, 0.02), 0.05, 0.04), FLESH.darkened(0.3), RigBuilder.MAT_WOUND, {"rings": 3, "sides": 7}))
		_spot(blood, Vector3(0, 0.66, 0.06), 0.08, 1.0)
