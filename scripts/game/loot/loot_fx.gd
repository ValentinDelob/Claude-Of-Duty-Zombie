class_name LootFx
extends RefCounted
## Habillage d'un BUTIN au sol selon sa rareté (docs/ART_DIRECTION.md
## « Butin ») : tout est cubique (cubes de 2,5 cm, paliers de 5 cm), à la
## couleur de la rareté (Hub2Style.RARITY : commune #C9C7BE, rare #4D9BFF,
## épique #B56CFF, légendaire #FF9A1F, unique #FF4D5E).
##
## * toutes : contour lumineux de la rareté sur l'objet (coque) + liseré
##   additif, petite flaque de lumière au sol ;
## * commune : rien de plus (sobre) ;
## * rare, épique : petites étoiles cubiques qui scintillent autour de
##   l'objet (épique : plus nombreuses, une lueur colorée) ;
## * légendaire, unique : en plus, plusieurs faisceaux verticaux (repère de
##   loin), étincelles qui montent, lumière colorée, grandes étoiles.
##
## Coût : une flaque (1 plan), 0 à 4 faisceaux (boîtes), 0 à 2 systèmes de
## particules GPU (quelques dizaines de cubes), 0 ou 1 lumière sans ombre.
## Les objets restent peu nombreux (butin personnel des vagues spéciales).
## Choix de l'habillage : tier() (pur, tests/test_loot_fx.gd).

const GLOW_SHADER := preload("res://assets/shaders/loot_glow.gdshader")
const HULL_SHADER := preload("res://assets/shaders/loot_hull.gdshader")

const COMMON := 0
const RARE := 1
const EPIC := 2
const LEGENDARY := 3
const UNIQUE := 4

## Sons de ramassage par rareté (tools/gen_audio.gd ; unique : celui de la
## légendaire).
const PICKUP_SOUNDS := ["loot_pickup_common", "loot_pickup_rare", "loot_pickup_epic",
	"loot_pickup_legendary", "loot_pickup_legendary"]
const LAND_SOUND := "loot_land"
const DROP_LEGENDARY_SOUND := "loot_drop_legendary"

## Distance d'affichage des étoiles (m) ; les faisceaux se voient de loin.
const SPARKLE_RANGE := 28.0

static var _mats: Dictionary = {}
static var _meshes: Dictionary = {}


## Couleur d'une rareté (bornée).
static func color(r: int) -> Color:
	return Hub2Style.rarity_color(clampi(r, COMMON, UNIQUE))


## Habillage d'une rareté (pur) : {sparkles: nombre d'étoiles, big_stars,
## beams: faisceaux, beam_h: hauteur (m), motes: étincelles qui montent,
## light: énergie de la lumière (0 : aucune), light_range, pool: intensité
## de la flaque, pool_r: rayon (m), hull: épaisseur du contour (m), rim}.
static func tier(r: int) -> Dictionary:
	match clampi(r, COMMON, UNIQUE):
		RARE:
			return {"sparkles": 7, "big_stars": false, "beams": 0, "beam_h": 0.0, "motes": 0, "light": 0.0,
				"light_range": 0.0, "pool": 0.55, "pool_r": 0.5, "hull": 0.0125, "rim": 0.9}
		EPIC:
			return {"sparkles": 11, "big_stars": false, "beams": 0, "beam_h": 0.0, "motes": 0, "light": 0.35,
				"light_range": 1.6, "pool": 0.6, "pool_r": 0.55, "hull": 0.0125, "rim": 1.1}
		LEGENDARY:
			return {"sparkles": 12, "big_stars": true, "beams": 3, "beam_h": 2.6, "motes": 10, "light": 1.0,
				"light_range": 3.0, "pool": 0.6, "pool_r": 0.7, "hull": 0.015, "rim": 1.3}
		UNIQUE:
			return {"sparkles": 16, "big_stars": true, "beams": 4, "beam_h": 3.0, "motes": 14, "light": 1.2,
				"light_range": 3.2, "pool": 0.65, "pool_r": 0.75, "hull": 0.015, "rim": 1.4}
	return {"sparkles": 0, "big_stars": false, "beams": 0, "beam_h": 0.0, "motes": 0, "light": 0.0,
		"light_range": 0.0, "pool": 0.35, "pool_r": 0.4, "hull": 0.01, "rim": 0.6}


## Son de ramassage d'un objet de rareté `r`.
static func pickup_sound(r: int) -> String:
	return PICKUP_SOUNDS[clampi(r, COMMON, UNIQUE)]


## Rareté affichée d'un échantillon : chiens commune, mini-boss rare,
## Chirurgien épique, son cœur légendaire (trophée du boss).
static func sample_rarity(id: String) -> int:
	if id == "surgeon_heart":
		return LEGENDARY
	if id.begins_with("surgeon_"):
		return EPIC
	if id.begins_with("dog_") or id == "":
		return COMMON
	return RARE


## Rareté affichée d'une pièce (format LootRules.roll_part) : sa qualité
## (Hub2ArsenalView.part_quality : ordinaire, solide, excellente).
static func part_rarity(p: Dictionary) -> int:
	var wp := WeaponPart.create(String(p.get("id", "part")), int(p.get("level", 1)), p.get("mods", {}))
	return clampi(Hub2ArsenalView.part_quality(wp), COMMON, EPIC)


# --------------------------------------------------------------------------
# Matériaux
# --------------------------------------------------------------------------

## Matériau des lueurs (loot_glow.gdshader) : `mode` 0 liseré, 1 flaque,
## 2 faisceau ; `extent` : rayon de la flaque ou hauteur du faisceau (m) ;
## `half_w` : demi-largeur du faisceau (m).
static func glow_material(mode: int, r: int, intensity: float, extent := 1.0, half_w := 0.05) -> ShaderMaterial:
	var key := "g|%d|%d|%.3f|%.3f|%.3f" % [mode, r, intensity, extent, half_w]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = GLOW_SHADER
	m.set_shader_parameter("mode", mode)
	m.set_shader_parameter("color", color(r))
	m.set_shader_parameter("intensity", intensity)
	m.set_shader_parameter("height", extent)
	m.set_shader_parameter("half_width", half_w)
	m.render_priority = 1
	_mats[key] = m
	return m


## Contour de rareté (coque) suivi du liseré additif (next_pass).
static func hull_material(r: int, width: float, rim: float) -> ShaderMaterial:
	var key := "h|%d|%.4f|%.3f" % [r, width, rim]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = HULL_SHADER
	m.set_shader_parameter("color", color(r))
	m.set_shader_parameter("width", width)
	m.set_shader_parameter("energy", 1.25 + 0.15 * r)
	m.next_pass = glow_material(0, r, rim)
	_mats[key] = m
	return m


## Pose le contour et le liseré de la rareté `r` sur tous les maillages de
## `model`.
static func dress(model: Node, r: int) -> void:
	var t := tier(r)
	var mat := hull_material(r, float(t.hull), float(t.rim))
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		mi.material_overlay = mat
	if model is MeshInstance3D:
		(model as MeshInstance3D).material_overlay = mat


# --------------------------------------------------------------------------
# Effets autour de l'objet
# --------------------------------------------------------------------------

## Construit les effets de la rareté `r` : flaque, faisceaux et lumière sous
## `ground` (posé au sol, ne tourne pas), étoiles sous `item` (suit l'objet
## en vol et en flottement). `size` : demi-taille de l'objet (m). Rend les
## nœuds dont la lueur apparaît à l'atterrissage ({fade: [GeometryInstance3D],
## light, beams: [MeshInstance3D]}).
static func build(ground: Node3D, item: Node3D, r: int, size := 0.25) -> Dictionary:
	var t := tier(r)
	var out := {"fade": [], "light": null, "beams": []}
	var pool := MeshInstance3D.new()
	pool.name = "Pool"
	var pm := PlaneMesh.new()
	var pr := float(t.pool_r) + size * 0.4
	pm.size = Vector2(pr * 2.0, pr * 2.0)
	pool.mesh = pm
	pool.material_override = glow_material(1, r, float(t.pool), pr)
	pool.position = Vector3(0, 0.015, 0)
	pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ground.add_child(pool)
	out.fade.append(pool)
	var nb := int(t.beams)
	if nb > 0:
		var beams := Node3D.new()
		beams.name = "Beams"
		ground.add_child(beams)
		var bh := float(t.beam_h)
		# Colonnes fines autour d'un fût central plus large et plus pâle.
		var core := _beam(beams, Vector3(0.3, bh, 0.3), Vector3.ZERO, r, 1.0, bh)
		out.fade.append(core)
		out.beams.append(core)
		for k in nb:
			var ang := TAU * float(k) / nb + 0.4
			var w := 0.075 if k % 2 == 0 else 0.1
			var h := bh * (0.62 + 0.38 * float((k * 7) % 5) / 4.0)
			var off := Vector3(cos(ang), 0, sin(ang)) * (0.17 + 0.05 * (k % 2))
			off = (off / 0.025).round() * 0.025
			var b := _beam(beams, Vector3(w, h, w), off, r, 3.2, h)
			b.set_instance_shader_parameter("seed", float(k) * 0.37)
			out.fade.append(b)
			out.beams.append(b)
	if int(t.sparkles) > 0:
		item.add_child(_sparkles(r, int(t.sparkles), bool(t.big_stars), size))
	if int(t.motes) > 0:
		ground.add_child(_motes(r, int(t.motes), float(t.beam_h)))
	if float(t.light) > 0.0:
		var l := OmniLight3D.new()
		l.name = "Light"
		l.light_color = color(r)
		l.light_energy = float(t.light)
		l.omni_range = float(t.light_range)
		l.omni_attenuation = 1.4
		l.shadow_enabled = false
		l.position = Vector3(0, 0.45, 0)
		ground.add_child(l)
		out.light = l
	for g: GeometryInstance3D in out.fade:
		g.set_instance_shader_parameter("fade", 0.0)
	return out


static func _beam(parent: Node3D, size: Vector3, off: Vector3, r: int, intensity: float, h: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = glow_material(2, r, intensity, h, size.x * 0.5)
	mi.position = off + Vector3(0, h * 0.5, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## Étoile cubique : cube central et six branches (croix 3D, lisible sous
## tous les angles) ; grande : branches de deux cubes. Repère de la
## particule (diamètre 1).
static func star_mesh(big: bool) -> ArrayMesh:
	var key := "star|%s" % big
	if _meshes.has(key):
		return _meshes[key]
	var n := 5 if big else 3
	var cell := 1.0 / n
	var arm := 2 if big else 1
	var centers := PackedVector3Array([Vector3.ZERO])
	for ax in 3:
		for sg in [-1, 1]:
			for k in range(1, arm + 1):
				var c := Vector3.ZERO
				c[ax] = sg * k * cell
				centers.append(c)
	var mesh := VoxelFx.build(centers, cell)
	_meshes[key] = mesh
	return mesh


## Étoiles qui scintillent autour de l'objet : chacune grandit (ses
## branches s'écartent) puis se replie, cubes de 2,5 cm, additives.
static func _sparkles(r: int, n: int, big: bool, size: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Sparkles"
	p.amount = n
	p.lifetime = 1.3
	p.preprocess = 1.3
	p.randomness = 0.6
	p.local_coords = true
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.draw_pass_1 = star_mesh(big)
	p.material_override = VoxelFx.material("add", {"max": 0.025, "energy": 1.25, "shade": false})
	p.visibility_range_end = SPARKLE_RANGE
	p.visibility_aabb = AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE
	pm.emission_sphere_radius = size + 0.12
	pm.direction = Vector3.UP
	pm.spread = 25.0
	pm.initial_velocity_min = 0.02
	pm.initial_velocity_max = 0.12
	pm.gravity = Vector3.ZERO
	var s := (5.0 if big else 3.0) * 0.025
	pm.scale_min = s
	pm.scale_max = s * (1.4 if big else 1.0)
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.15))
	curve.add_point(Vector2(0.35, 1.0))
	curve.add_point(Vector2(0.65, 0.9))
	curve.add_point(Vector2(1.0, 0.1))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	var g := Gradient.new()
	var c := color(r)
	g.offsets = PackedFloat32Array([0.0, 0.2, 0.5, 0.85, 1.0])
	g.colors = PackedColorArray([Color(c, 0.0), Color(c, 1.0), Color(c.lerp(Color.WHITE, 0.3), 1.0), Color(c, 1.0), Color(c, 0.0)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	return p


## Étincelles qui montent dans les faisceaux (légendaire, unique).
static func _motes(r: int, n: int, h: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Motes"
	p.amount = n
	p.lifetime = 2.2
	p.preprocess = 2.2
	p.randomness = 0.5
	p.local_coords = true
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.draw_pass_1 = VoxelFx.cube()
	p.material_override = VoxelFx.material("add", {"max": 0.05, "energy": 2.0, "shade": false})
	p.visibility_aabb = AABB(Vector3(-0.6, 0, -0.6), Vector3(1.2, h + 0.5, 1.2))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.2, 0.05, 0.2)
	pm.direction = Vector3.UP
	pm.spread = 6.0
	pm.initial_velocity_min = 0.55
	pm.initial_velocity_max = 1.1
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.025
	pm.scale_max = 0.05
	var g := Gradient.new()
	var c := color(r)
	g.offsets = PackedFloat32Array([0.0, 0.15, 1.0])
	g.colors = PackedColorArray([Color(c.lerp(Color.WHITE, 0.5), 0.0), Color(c.lerp(Color.WHITE, 0.4), 1.0), Color(c, 0.0)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	return p


## Apparition des lueurs (0..1) : flaque, faisceaux (qui montent du sol) et
## lumière.
static func set_fade(fx: Dictionary, k: float, light_energy: float) -> void:
	for g: GeometryInstance3D in fx.get("fade", []):
		g.set_instance_shader_parameter("fade", k)
	for b: MeshInstance3D in fx.get("beams", []):
		var h := (b.mesh as BoxMesh).size.y
		var e := clampf(k, 0.02, 1.0)
		b.scale = Vector3(1, e, 1)
		b.position.y = h * 0.5 * e
	var l: OmniLight3D = fx.get("light")
	if l:
		l.light_energy = light_energy * k


# --------------------------------------------------------------------------
# Modèles des pièces et des échantillons (cubes de 2,5 cm)
# --------------------------------------------------------------------------

## Matériau des petits objets (couleur par cube).
static func item_material() -> StandardMaterial3D:
	if _mats.has("item"):
		return _mats["item"]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.55
	m.metallic = 0.2
	_mats["item"] = m
	return m


## Fiole d'échantillon : verre clair, liquide à la couleur de la rareté,
## bouchon de liège (3 × 5 × 3 cubes de 2,5 cm, centrée).
static func sample_mesh(r: int) -> ArrayMesh:
	var key := "sample|%d" % r
	if _meshes.has(key):
		return _meshes[key]
	var g := 0.025
	var liquid := color(r)
	var glass := Color(0.78, 0.86, 0.88)
	var cork := Color(0.55, 0.38, 0.22)
	var centers := PackedVector3Array()
	var colors := PackedColorArray()
	for y in 6:
		for x in 3:
			for z in 3:
				var edge := x != 1 or z != 1
				var col := glass
				if y == 5:
					if edge and not (x == 1 or z == 1):
						continue
					col = cork
				elif y <= 3 and not edge:
					col = liquid
				elif y <= 2:
					col = liquid.lerp(glass, 0.35)
				centers.append(Vector3(x - 0.5, y - 2.5, z - 0.5) * g)
				colors.append(col)
	var mesh := VoxelFx.build(centers, g, colors)
	_meshes[key] = mesh
	return mesh


## Pièce d'arme : bloc de métal sombre, bande à la couleur de la rareté,
## vis claire (5 × 2 × 3 cubes de 2,5 cm, centrée).
static func part_mesh(r: int) -> ArrayMesh:
	var key := "part|%d" % r
	if _meshes.has(key):
		return _meshes[key]
	var g := 0.025
	var metal := Color(0.24, 0.25, 0.27)
	var light := Color(0.62, 0.63, 0.6)
	var band := color(r)
	var centers := PackedVector3Array()
	var colors := PackedColorArray()
	for x in 5:
		for y in 2:
			for z in 3:
				var col := metal
				if x == 1:
					col = band
				elif y == 1 and x == 3 and z == 1:
					col = light
				centers.append(Vector3(x - 1.5, y - 0.5, z - 0.5) * g)
				colors.append(col)
	# Ergot sur le dessus (rail de fixation).
	for x in [0, 4]:
		centers.append(Vector3(x - 1.5, 1.5, 0.5) * g)
		colors.append(metal)
	var mesh := VoxelFx.build(centers, g, colors)
	_meshes[key] = mesh
	return mesh
