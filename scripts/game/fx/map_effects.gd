class_name MapEffects
extends RefCounted
## Effets posés dans l'éditeur de cartes (type « effet », MapCatalog.EFFECTS) :
## chaque effet est construit EN CODE à partir de couches :
##   - particules GPU (GPUParticles3D + ParticleProcessMaterial) : panneaux
##     face caméra, additifs (feu, étincelles, électricité) ou fondus et
##     éclairés (fumées, brume, cendres), doux au contact du sol (« soft
##     particles », proximity fade), tailles et couleurs le long de la vie,
##     turbulence, rotation au hasard ; étincelles étirées dans le sens de leur
##     vitesse (Y aligné + panneau Y fixe) et qui REBONDISSENT sur le sol
##     (GPUParticlesCollisionBox3D) ; gouttes qui disparaissent au sol, ronds
##     dans l'eau synchronisés sur leur chute ;
##   - lumières (OmniLight3D sans ombre) qui vacillent, crépitent ou éclatent
##     (MapEffect) ;
##   - arcs électriques (panneaux texturés re-tirés au hasard toutes les
##     quelques centièmes de seconde) ;
##   - petits objets sans collision (bûches, torche, tuyau, boîtier,
##     électrodes, câble, flaque).
## Textures : assets/textures/fx/ (Kenney « Particle Pack », CC0, voir
## docs/ASSETS.md) ; à défaut, dégradés calculés (aucun fichier requis).
##
## Repère d'un effet : origine au point posé, y vers le haut ; effet mural :
## +z sort du mur vers la pièce. `opts` (layout « effects ») : intensity
## (quantité de particules et lumière), scale (taille), color (« rrggbb »,
## effets qui se teintent), ground (distance au sol, m), room_h (hauteur de
## la pièce, m).

## Particules au plus par carte (au-delà, MeshMapBuilder les réduit toutes).
const PARTICLE_BUDGET := 9000
## Lumières d'effets au plus par carte (les suivantes restent éteintes).
const LIGHT_BUDGET := 16
const TEX_DIR := "res://assets/textures/fx/"

static var _tex: Dictionary = {}
static var _mats: Dictionary = {}
static var _quads: Dictionary = {}

const FIRE_RAMP := [[0.0, Color(1.0, 0.9, 0.6, 0.0)], [0.08, Color(1.0, 0.78, 0.35, 0.6)], [0.35, Color(1.0, 0.42, 0.08, 0.5)],
	[0.7, Color(0.65, 0.14, 0.03, 0.22)], [1.0, Color(0.2, 0.04, 0.02, 0.0)]]
const TONGUE_RAMP := [[0.0, Color(1.0, 0.95, 0.75, 0.0)], [0.1, Color(1.0, 0.88, 0.5, 0.95)], [0.5, Color(1.0, 0.5, 0.12, 0.6)],
	[1.0, Color(0.5, 0.1, 0.02, 0.0)]]
const EMBER_RAMP := [[0.0, Color(1.0, 0.85, 0.5, 1.0)], [0.4, Color(1.0, 0.45, 0.1, 1.0)], [1.0, Color(0.6, 0.1, 0.02, 0.0)]]
const SPARK_RAMP := [[0.0, Color(1.0, 0.97, 0.85, 1.0)], [0.25, Color(1.0, 0.75, 0.35, 1.0)], [0.7, Color(1.0, 0.4, 0.08, 0.9)],
	[1.0, Color(0.7, 0.15, 0.02, 0.0)]]
const WATER := Color(0.72, 0.82, 0.92)


## Effet `id` construit, ou null s'il est inconnu.
static func build(id: String, opts: Dictionary = {}) -> MapEffect:
	if not MapCatalog.EFFECTS.has(id):
		return null
	var e := MapEffect.new()
	e.fx_id = id
	e.name = "Effect_" + id
	e.intensity = clampf(_f(opts, "intensity", 1.0), MapCatalog.EFFECT_LIMITS.intensite[0], MapCatalog.EFFECT_LIMITS.intensite[1])
	e.size = clampf(_f(opts, "scale", 1.0), MapCatalog.EFFECT_LIMITS.taille[0], MapCatalog.EFFECT_LIMITS.taille[1])
	e.body.scale = Vector3.ONE * e.size
	var d: Dictionary = MapCatalog.EFFECTS[id]
	var tint := Color.html(String(d.get("couleur", "#ffffff")))
	var cs := String(opts.get("color", ""))
	if d.has("couleur") and Color.html_is_valid(cs):
		tint = Color.html(cs)
	# Distance au sol et hauteur de pièce dans le repère du corps (mis à l'échelle).
	var ground := maxf(0.0, _f(opts, "ground", 0.0)) / e.size
	var room_h := maxf(1.0, _f(opts, "room_h", 3.2)) / e.size
	var b := Builder.new(e, tint, ground, room_h)
	b.call_fx(id)
	return e


static func _f(opts: Dictionary, key: String, def: float) -> float:
	var v: Variant = opts.get(key, def)
	return float(v) if (v is float or v is int) and is_finite(float(v)) else def


# ------------------------------------------------------------------ ressources partagées

## Texture des effets ; absente : dégradé rond calculé.
static func tex(name: String) -> Texture2D:
	if _tex.has(name):
		return _tex[name]
	var t: Texture2D = null
	var path := TEX_DIR + name + ".png"
	if name != "dot" and name != "ring" and ResourceLoader.exists(path):
		t = load(path) as Texture2D
	if t == null:
		t = _gradient_tex(name)
	_tex[name] = t
	return t


## Dégradé rond : point doux (« dot » et textures absentes) ou anneau (« ring »).
static func _gradient_tex(name: String) -> Texture2D:
	var g := Gradient.new()
	if name == "ring":
		g.offsets = PackedFloat32Array([0.0, 0.7, 0.84, 0.92, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0.25), Color(1, 1, 1, 0)])
	else:
		g.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 64
	gt.height = 64
	return gt


## Matériau d'affichage des particules. `blend` : « add » (lumineux),
## « mix » (fondu, sans éclairage) ou « lit » (fondu, éclairé par les lampes
## et les feux) ; `soft` : fondu au contact des surfaces (m) ; `mode` :
## « face » (panneau face caméra), « streak » (étiré dans le sens de la
## vitesse), « flat » (à plat sur le sol).
static func draw_mat(texture: String, blend: String, soft := 0.0, mode := "face", flip := Vector2.ONE) -> StandardMaterial3D:
	var key := "%s|%s|%.2f|%s|%s" % [texture, blend, soft, mode, flip]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex(texture)
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL if blend == "lit" else BaseMaterial3D.SHADING_MODE_UNSHADED
	if blend == "add":
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	if blend == "lit":
		m.roughness = 1.0
		m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		m.disable_receive_shadows = true
	match mode:
		"face":
			m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
			m.billboard_keep_scale = true
		"streak":
			m.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
			m.billboard_keep_scale = true
		_:
			m.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	if soft > 0.0:
		m.proximity_fade_enabled = true
		m.proximity_fade_distance = soft
	if flip != Vector2.ONE:
		m.uv1_scale = Vector3(flip.x, flip.y, 1.0)
		m.uv1_offset = Vector3(1.0 if flip.x < 0 else 0.0, 1.0 if flip.y < 0 else 0.0, 0.0)
	_mats[key] = m
	return m


static func quad(sz: Vector2, flat := false) -> QuadMesh:
	var key := "%s|%s" % [sz, flat]
	if not _quads.has(key):
		var q := QuadMesh.new()
		q.size = sz
		if flat:
			q.orientation = PlaneMesh.FACE_Y
		_quads[key] = q
	return _quads[key]


static func ramp(stops: Array, tint := Color.WHITE) -> GradientTexture1D:
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for s in stops:
		offs.append(float(s[0]))
		var c: Color = s[1]
		cols.append(Color(c.r * tint.r, c.g * tint.g, c.b * tint.b, c.a))
	g.offsets = offs
	g.colors = cols
	var gt := GradientTexture1D.new()
	gt.gradient = g
	gt.width = 64
	return gt


static func curve(pts: Array) -> CurveTexture:
	var c := Curve.new()
	var hi := 1.0
	for p in pts:
		hi = maxf(hi, float(p[1]))
	c.max_value = hi
	for p in pts:
		c.add_point(Vector2(float(p[0]), float(p[1])))
	var ct := CurveTexture.new()
	ct.curve = c
	ct.width = 64
	return ct


## Matériau d'un petit objet de l'effet (bûches, torche, tuyau...).
static func solid(albedo: Color, metal := 0.0, rough := 0.85, glow := Color.BLACK, glow_e := 0.0) -> StandardMaterial3D:
	var key := "solid|%s|%.2f|%.2f|%s|%.2f" % [albedo, metal, rough, glow, glow_e]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.metallic = metal
	m.roughness = rough
	if glow_e > 0.0:
		m.emission_enabled = true
		m.emission = glow
		m.emission_energy_multiplier = glow_e
	if albedo.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mats[key] = m
	return m


# ------------------------------------------------------------------ construction

## Construit les couches d'un effet (une fonction par effet du catalogue).
class Builder:
	var e: MapEffect
	var tint: Color
	var ground: float
	var room_h: float

	func _init(fx: MapEffect, t: Color, g: float, h: float) -> void:
		e = fx
		tint = t
		ground = g
		room_h = h

	## Couche de particules. Clés de `c` : tex, blend, soft, mode (face, streak,
	## flat), quad (taille du panneau), n, life, pre (préchauffage, s), explo,
	## rand, at, shape (point, sphere, box), r, ext, dir, spread, flatness, v
	## [min, max], g (gravité), damp, size [min, max], curve, ramp, tint (bool :
	## couleur de l'effet), spin [min, max] (°/s), angle (rotation au hasard),
	## turb (force), turb_scale, collide (« bounce », « hide »), burst, cycle,
	## aabb.
	func parts(c: Dictionary) -> GPUParticles3D:
		var p := GPUParticles3D.new()
		var pm := ParticleProcessMaterial.new()
		var burst := bool(c.get("burst", false))
		p.amount = maxi(1, roundi(float(c.get("n", 8)) * (e.intensity if not burst else sqrt(e.intensity))))
		p.lifetime = float(c.get("life", 1.0))
		p.explosiveness = float(c.get("explo", 0.0))
		p.randomness = float(c.get("rand", 0.0))
		p.preprocess = 0.0 if burst else float(c.get("pre", p.lifetime))
		p.local_coords = true
		var mode := String(c.get("mode", "face"))
		var blend := String(c.get("blend", "add"))
		p.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH if blend != "add" else GPUParticles3D.DRAW_ORDER_INDEX
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.draw_pass_1 = MapEffects.quad(c.get("quad", Vector2.ONE), mode == "flat")
		p.material_override = MapEffects.draw_mat(String(c.get("tex", "dot")), blend, float(c.get("soft", 0.0)), mode)
		p.position = c.get("at", Vector3.ZERO)
		match String(c.get("shape", "point")):
			"sphere":
				pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
				pm.emission_sphere_radius = float(c.get("r", 0.2))
			"box":
				pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
				pm.emission_box_extents = c.get("ext", Vector3(0.2, 0.0, 0.2))
			_:
				pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
		pm.direction = c.get("dir", Vector3.UP)
		pm.spread = float(c.get("spread", 10.0))
		pm.flatness = float(c.get("flatness", 0.0))
		var v: Vector2 = c.get("v", Vector2(0.5, 1.0))
		pm.initial_velocity_min = v.x
		pm.initial_velocity_max = v.y
		pm.gravity = c.get("g", Vector3.ZERO)
		var damp: Vector2 = c.get("damp", Vector2.ZERO)
		pm.damping_min = damp.x
		pm.damping_max = damp.y
		var sz: Vector2 = c.get("size", Vector2(0.3, 0.5))
		pm.scale_min = sz.x
		pm.scale_max = sz.y
		if c.has("curve"):
			pm.scale_curve = MapEffects.curve(c.curve)
		pm.color_ramp = MapEffects.ramp(c.get("ramp", [[0.0, Color.WHITE], [1.0, Color(1, 1, 1, 0)]]), tint if c.get("tint", false) else Color.WHITE)
		if mode == "streak":
			p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
		elif mode != "flat" and c.get("angle", true):
			var arange := float(c.get("angle_deg", 180.0))
			pm.angle_min = -arange
			pm.angle_max = arange
		var spin: Vector2 = c.get("spin", Vector2.ZERO)
		pm.angular_velocity_min = spin.x
		pm.angular_velocity_max = spin.y
		if float(c.get("turb", 0.0)) > 0.0:
			pm.turbulence_enabled = true
			pm.turbulence_noise_strength = float(c.turb)
			pm.turbulence_noise_scale = float(c.get("turb_scale", 1.5))
			pm.turbulence_noise_speed = Vector3(0.0, 0.25, 0.0)
			pm.turbulence_influence_min = 0.05
			pm.turbulence_influence_max = 0.18
		match String(c.get("collide", "")):
			"bounce":
				pm.collision_mode = ParticleProcessMaterial.COLLISION_RIGID
				pm.collision_bounce = 0.35
				pm.collision_friction = 0.45
				p.collision_base_size = 0.01
			"hide":
				pm.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
				p.collision_base_size = 0.01
		p.process_material = pm
		p.visibility_aabb = c.get("aabb", AABB(Vector3(-2.5, -ground - 0.5, -2.5) - p.position, Vector3(5.0, ground + 5.0, 5.0)))
		e.add_part(p, burst, bool(c.get("cycle", false)))
		return p

	## Lumière de l'effet (sans ombre), à `at` dans le repère du corps.
	func light(at: Vector3, col: Color, energy: float, rng: float, mode: int, minor := false) -> OmniLight3D:
		var l := OmniLight3D.new()
		l.position = at * e.size
		l.light_color = col
		l.light_energy = energy * clampf(e.intensity, 0.5, 1.6)
		l.omni_range = rng * e.size
		l.omni_attenuation = 1.4
		l.shadow_enabled = false
		l.light_specular = 0.35
		e.add_light(l, mode, minor)
		return l

	func mesh(m: Mesh, mat: Material, xf: Transform3D) -> MeshInstance3D:
		var mi := MeshInstance3D.new()
		mi.mesh = m
		mi.material_override = mat
		mi.transform = xf
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		e.body.add_child(mi)
		return mi

	func cyl(r_top: float, r_bot: float, h: float, segs := 10) -> CylinderMesh:
		var c := CylinderMesh.new()
		c.top_radius = r_top
		c.bottom_radius = r_bot
		c.height = h
		c.radial_segments = segs
		c.rings = 1
		return c

	func box(sz: Vector3) -> BoxMesh:
		var bm := BoxMesh.new()
		bm.size = sz
		return bm

	func sphere(r: float) -> SphereMesh:
		var s := SphereMesh.new()
		s.radius = r
		s.height = r * 2.0
		s.radial_segments = 12
		s.rings = 6
		return s

	## Arc électrique : `mode` 0 de a à b, 1 rayon au hasard autour de a
	## (b.x, b.y : longueur min, max).
	func arc(a: Vector3, b: Vector3, width: float, mode := 0, burst_only := false) -> void:
		if e.arc_mats.is_empty():
			for f in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
				var m := MapEffects.draw_mat("arc", "add", 0.0, "streak", f).duplicate() as StandardMaterial3D
				m.albedo_color = Color(tint.r, tint.g, tint.b, 1.0).lightened(0.25)
				m.vertex_color_use_as_albedo = false
				e.arc_mats.append(m)
		var mi := MeshInstance3D.new()
		mi.mesh = MapEffects.quad(Vector2.ONE)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.material_override = e.arc_mats[0]
		e.add_arc(mi, mode, a, b, width, burst_only)

	## Collision du sol (étincelles qui rebondissent, gouttes qui s'arrêtent).
	func floor_collider(half: float) -> void:
		var cb := GPUParticlesCollisionBox3D.new()
		cb.size = Vector3(half * 2.0, 0.4, half * 2.0)
		cb.position = Vector3(0, -ground - 0.2, 0)
		e.body.add_child(cb)

	# -------------------------------------------------------------- flammes

	## Feu en couches : flammes (volutes et langues), cœur lumineux, braises,
	## fumée, lumière vacillante. `ext` : demi-emprise du foyer (x, z), `h` :
	## hauteur des flammes (m), `dens` : densité, `dark` : fumée noire (0 à 1).
	func fire(at: Vector3, ext: Vector2, h: float, dens: float, dark: float, energy: float, rng: float, n_lights := 1) -> void:
		var w := (ext.x + ext.y) * 0.5
		var life := 0.55 + h * 0.35
		var bx := Vector3(ext.x, 0.03, ext.y)
		parts({"tex": "fire_billow", "n": 12 * dens, "angle_deg": 25.0, "life": life, "rand": 0.3, "at": at, "shape": "box", "ext": bx, "spread": 10.0,
			"v": Vector2(0.25, 0.55) * h / life, "g": Vector3(0, h * 1.1 / (life * life), 0), "damp": Vector2(0.4, 1.0),
			"size": Vector2(w * 1.6 + 0.12, w * 2.6 + 0.2), "curve": [[0.0, 0.35], [0.2, 1.0], [0.6, 0.75], [1.0, 0.1]],
			"ramp": MapEffects.FIRE_RAMP, "spin": Vector2(-20, 20), "turb": 0.3, "turb_scale": 1.2,
			"aabb": AABB(Vector3(-ext.x - 1.0, -0.2, -ext.y - 1.0), Vector3(ext.x * 2.0 + 2.0, h * 2.0 + 1.0, ext.y * 2.0 + 2.0))})
		parts({"tex": "flame_tongue", "n": 9 * dens, "life": life * 0.7, "rand": 0.35, "at": at, "shape": "box", "ext": bx * 0.8, "spread": 6.0,
			"v": Vector2(0.3, 0.6) * h / life, "g": Vector3(0, h / (life * life), 0), "damp": Vector2(0.5, 1.2), "angle": false,
			"size": Vector2(w * 1.3 + 0.12, w * 2.0 + 0.2), "curve": [[0.0, 0.5], [0.25, 1.0], [1.0, 0.25]], "ramp": MapEffects.TONGUE_RAMP,
			"aabb": AABB(Vector3(-ext.x - 1.0, -0.2, -ext.y - 1.0), Vector3(ext.x * 2.0 + 2.0, h * 2.0 + 1.0, ext.y * 2.0 + 2.0))})
		parts({"tex": "fire_core", "n": 3 * dens, "life": 0.6, "at": at + Vector3(0, h * 0.15, 0), "shape": "box", "ext": bx * 0.5,
			"v": Vector2(0.02, 0.08), "size": Vector2(w * 2.4 + 0.2, w * 3.2 + 0.3), "spin": Vector2(-25, 25),
			"ramp": [[0.0, Color(1.0, 0.5, 0.15, 0.0)], [0.3, Color(1.0, 0.42, 0.1, 0.32)], [1.0, Color(0.6, 0.15, 0.03, 0.0)]]})
		parts({"tex": "dot", "n": 10 * dens, "life": 2.2, "rand": 0.45, "at": at + Vector3(0, h * 0.2, 0), "shape": "sphere", "r": w + 0.05,
			"spread": 25.0, "v": Vector2(0.6, 1.3) * maxf(1.0, h), "g": Vector3(0, 0.25, 0), "damp": Vector2(0.3, 0.8),
			"size": Vector2(0.02, 0.045), "curve": [[0.0, 1.0], [0.7, 0.8], [1.0, 0.0]], "ramp": MapEffects.EMBER_RAMP, "turb": 1.1, "turb_scale": 0.6,
			"aabb": AABB(Vector3(-3, -0.5, -3), Vector3(6, room_h + 1.0, 6))})
		var sc := Color(0.24, 0.23, 0.22).lerp(Color(0.04, 0.035, 0.03), dark)
		parts({"tex": "smoke_a", "blend": "lit", "soft": 0.5, "n": 6 * dens, "life": 3.0 + h, "rand": 0.3, "at": at + Vector3(0, h * 0.75, 0),
			"shape": "sphere", "r": w * 0.6 + 0.05, "spread": 12.0, "v": Vector2(0.35, 0.6) * maxf(1.0, h * 0.8), "g": Vector3(0, 0.1, 0),
			"damp": Vector2(0.2, 0.45), "size": Vector2(w * 2.0 + 0.4, w * 3.0 + 0.6), "curve": [[0.0, 0.4], [1.0, 1.9]],
			"ramp": [[0.0, Color(sc, 0.0)], [0.15, Color(sc, 0.35 + dark * 0.35)], [1.0, Color(sc, 0.0)]], "spin": Vector2(-25, 25), "turb": 0.35,
			"aabb": AABB(Vector3(-4, -0.5, -4), Vector3(8, room_h + 2.0, 8))})
		var col := Color(1.0, 0.55, 0.22)
		if n_lights <= 1:
			light(at + Vector3(0, h * 0.45, 0), col, energy, rng, MapEffect.Light.FIRE)
		else:
			for i in n_lights:
				var x := ext.x * (float(i) / (n_lights - 1) * 1.2 - 0.6)
				light(at + Vector3(x, h * 0.45, 0), col, energy / n_lights * 1.4, rng, MapEffect.Light.FIRE, i > 0)

	## Bûches croisées (braises dans le bois) et, pour le brasier, un cercle de pierres.
	func logs(r: float, stones: bool) -> void:
		var wood := MapEffects.solid(Color(0.06, 0.045, 0.035), 0.0, 0.95, Color(0.9, 0.22, 0.04), 0.18)
		for i in 4:
			var yaw := i * PI / 4.0 * 1.7 + 0.3
			var xf := Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, PI * 0.5 - 0.18), Vector3(0, r * 0.18, 0))
			mesh(cyl(r * 0.11, r * 0.13, r * 1.9, 7), wood, xf)
		if stones:
			var stone := MapEffects.solid(Color(0.22, 0.21, 0.2), 0.0, 0.95)
			for i in 10:
				var a := i * TAU / 10.0
				var s := r * (0.16 + fposmod(i * 0.37, 0.08))
				mesh(sphere(s), stone, Transform3D(Basis().scaled(Vector3(1.2, 0.7, 1.0)), Vector3(cos(a) * r * 1.15, s * 0.5, sin(a) * r * 1.15)))

	func petit_feu() -> void:
		logs(0.26, false)
		fire(Vector3(0, 0.05, 0), Vector2(0.14, 0.14), 0.75, 1.0, 0.0, 1.8, 6.0)

	func brasier() -> void:
		logs(0.45, true)
		fire(Vector3(0, 0.08, 0), Vector2(0.3, 0.3), 1.3, 2.0, 0.15, 2.8, 9.0)

	func baril_feu() -> void:
		fire(Vector3(0, 0.02, 0), Vector2(0.18, 0.18), 0.9, 1.3, 0.5, 2.2, 7.5)

	func torche() -> void:
		var iron := MapEffects.solid(Color(0.16, 0.16, 0.17), 0.8, 0.5)
		var wood := MapEffects.solid(Color(0.28, 0.17, 0.09), 0.0, 0.9)
		# Patte de fixation au mur, manche incliné vers la pièce, tête goudronnée.
		mesh(box(Vector3(0.09, 0.16, 0.025)), iron, Transform3D(Basis(), Vector3(0, -0.05, 0.012)))
		var tilt := Basis(Vector3.RIGHT, 0.55)
		mesh(cyl(0.022, 0.016, 0.46, 8), wood, Transform3D(tilt, Vector3(0, 0.02, 0.13)))
		mesh(cyl(0.035, 0.03, 0.09, 8), MapEffects.solid(Color(0.05, 0.04, 0.03), 0.0, 1.0, Color(1.0, 0.35, 0.08), 0.8),
			Transform3D(tilt, Vector3(0, 0.21, 0.255)))
		mesh(box(Vector3(0.05, 0.02, 0.06)), iron, Transform3D(Basis(), Vector3(0, -0.02, 0.05)))
		fire(Vector3(0, 0.27, 0.29), Vector2(0.04, 0.04), 0.38, 0.7, 0.3, 1.4, 5.5)

	func incendie() -> void:
		# Planches calcinées sous la nappe de feu.
		var char_mat := MapEffects.solid(Color(0.06, 0.05, 0.045), 0.0, 1.0, Color(1.0, 0.28, 0.05), 0.4)
		for i in 5:
			var x := -1.0 + i * 0.5
			mesh(box(Vector3(0.9, 0.05, 0.16)), char_mat, Transform3D(Basis(Vector3.UP, 0.4 + i * 0.9), Vector3(x, 0.025, fposmod(i * 0.47, 0.8) - 0.4)))
		fire(Vector3(0, 0.05, 0), Vector2(1.2, 0.75), 1.8, 3.2, 0.8, 3.2, 12.0, 2)

	# -------------------------------------------------------------- fumées

	func fumee_legere() -> void:
		var c := Color(0.58, 0.58, 0.58)
		for t in [["smoke_b", 10], ["smoke_a", 5]]:
			parts({"tex": t[0], "blend": "lit", "soft": 0.6, "n": t[1], "life": 6.5, "rand": 0.3, "at": Vector3(0, 0.15, 0), "shape": "sphere", "r": 0.25,
				"spread": 15.0, "v": Vector2(0.18, 0.38), "g": Vector3(0, 0.05, 0), "damp": Vector2(0.05, 0.15), "size": Vector2(0.5, 0.85),
				"curve": [[0.0, 0.5], [1.0, 2.4]], "tint": true, "spin": Vector2(-15, 15), "turb": 0.25, "turb_scale": 2.0,
				"ramp": [[0.0, Color(c, 0.0)], [0.2, Color(c, 0.3)], [0.7, Color(c, 0.16)], [1.0, Color(c, 0.0)]],
				"aabb": AABB(Vector3(-3, -0.5, -3), Vector3(6, room_h + 1.0, 6))})

	func fumee_noire() -> void:
		var c := Color(0.035, 0.03, 0.028)
		for t in [["smoke_a", 16, 1.0], ["smoke_b", 10, 0.8]]:
			parts({"tex": t[0], "blend": "lit", "soft": 0.6, "n": t[1], "life": 7.0, "rand": 0.25, "at": Vector3(0, 0.2, 0), "shape": "sphere", "r": 0.35,
				"spread": 12.0, "v": Vector2(0.6, 0.95), "g": Vector3(0, 0.08, 0), "damp": Vector2(0.15, 0.3), "size": Vector2(0.9, 1.3) * float(t[2]),
				"curve": [[0.0, 0.5], [0.5, 1.6], [1.0, 2.8]], "spin": Vector2(-18, 18), "turb": 0.45, "turb_scale": 2.2,
				"ramp": [[0.0, Color(c, 0.0)], [0.1, Color(c, 0.8)], [0.6, Color(c, 0.55)], [1.0, Color(c, 0.0)]],
				"aabb": AABB(Vector3(-4, -0.5, -4), Vector3(8, room_h + 2.0, 8))})
		# Foyer qui couve au pied de la colonne.
		parts({"tex": "fire_core", "n": 3, "life": 1.4, "at": Vector3(0, 0.06, 0), "shape": "box", "ext": Vector3(0.25, 0.0, 0.25),
			"v": Vector2(0.02, 0.05), "size": Vector2(0.5, 0.8), "spin": Vector2(-20, 20),
			"ramp": [[0.0, Color(1.0, 0.35, 0.08, 0.0)], [0.4, Color(1.0, 0.3, 0.06, 0.3)], [1.0, Color(0.5, 0.08, 0.02, 0.0)]]})
		parts({"tex": "dot", "n": 8, "life": 1.8, "rand": 0.4, "shape": "sphere", "r": 0.3, "spread": 30.0, "v": Vector2(0.4, 0.9),
			"g": Vector3(0, 0.2, 0), "size": Vector2(0.015, 0.035), "ramp": MapEffects.EMBER_RAMP, "turb": 0.8})
		light(Vector3(0, 0.2, 0), Color(1.0, 0.4, 0.12), 0.7, 3.5, MapEffect.Light.FIRE, true)

	func vapeur() -> void:
		var steel := MapEffects.solid(Color(0.3, 0.3, 0.29), 0.75, 0.45)
		mesh(cyl(0.05, 0.05, 0.18, 12), steel, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, 0.09)))
		mesh(cyl(0.075, 0.075, 0.025, 12), steel, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, 0.015)))
		mesh(cyl(0.058, 0.058, 0.02, 12), MapEffects.solid(Color(0.12, 0.12, 0.12), 0.6, 0.5), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, 0.18)))
		var c := Color(0.8, 0.83, 0.86)
		parts({"tex": "smoke_b", "blend": "mix", "soft": 0.3, "n": 34, "life": 1.8, "rand": 0.3, "at": Vector3(0, 0, 0.19), "dir": Vector3(0, 0.12, 1.0),
			"spread": 7.0, "v": Vector2(2.4, 3.2), "g": Vector3(0, 0.6, 0), "damp": Vector2(2.4, 3.4), "size": Vector2(0.12, 0.2),
			"curve": [[0.0, 0.3], [0.3, 1.3], [1.0, 3.4]], "spin": Vector2(-45, 45), "turb": 0.3,
			"ramp": [[0.0, Color(c, 0.0)], [0.06, Color(c, 0.6)], [0.5, Color(c, 0.25)], [1.0, Color(c, 0.0)]],
			"aabb": AABB(Vector3(-1.5, -1.0, -0.2), Vector3(3, 3, 4))})
		parts({"tex": "streak", "blend": "mix", "mode": "streak", "quad": Vector2(0.012, 0.05), "n": 6, "life": 0.7, "at": Vector3(0, -0.03, 0.19),
			"dir": Vector3(0, 0.1, 1), "spread": 15.0, "v": Vector2(1.0, 2.0), "g": Vector3(0, -9.8, 0), "size": Vector2(0.8, 1.2),
			"ramp": [[0.0, Color(MapEffects.WATER, 0.6)], [1.0, Color(MapEffects.WATER, 0.0)]], "collide": "hide"})
		floor_collider(2.0)

	func brouillard() -> void:
		var c := Color(1, 1, 1)
		parts({"tex": "smoke_a", "blend": "lit", "soft": 1.0, "n": 18, "life": 14.0, "rand": 0.3, "at": Vector3(0, 0.3, 0), "shape": "box",
			"ext": Vector3(1.8, 0.1, 1.8), "dir": Vector3(1, 0, 0), "spread": 180.0, "flatness": 1.0, "v": Vector2(0.02, 0.07),
			"size": Vector2(2.0, 3.0), "curve": [[0.0, 0.6], [0.5, 1.0], [1.0, 1.2]], "tint": true, "spin": Vector2(-4, 4),
			"ramp": [[0.0, Color(c, 0.0)], [0.3, Color(c, 0.17)], [0.7, Color(c, 0.17)], [1.0, Color(c, 0.0)]],
			"aabb": AABB(Vector3(-4, -0.5, -4), Vector3(8, 3, 8))})
		parts({"tex": "smoke_b", "blend": "lit", "soft": 0.8, "n": 10, "life": 10.0, "rand": 0.3, "at": Vector3(0, 0.12, 0), "shape": "box",
			"ext": Vector3(1.6, 0.05, 1.6), "dir": Vector3(1, 0, 0), "spread": 180.0, "flatness": 1.0, "v": Vector2(0.03, 0.09),
			"size": Vector2(1.2, 1.8), "tint": true, "spin": Vector2(-6, 6),
			"ramp": [[0.0, Color(c, 0.0)], [0.3, Color(c, 0.14)], [0.7, Color(c, 0.14)], [1.0, Color(c, 0.0)]],
			"aabb": AABB(Vector3(-4, -0.5, -4), Vector3(8, 3, 8))})

	# -------------------------------------------------------------- étincelles

	## Gerbe d'étincelles étirées (rebondissent au sol).
	func sparks(at: Vector3, n: int, dir: Vector3, spread: float, v: Vector2, life: float, burst: bool, cycle := false, col_tint := false) -> void:
		parts({"tex": "streak", "mode": "streak", "quad": Vector2(0.045, 0.24), "n": n, "life": life, "rand": 0.5, "explo": 0.92 if burst else 0.0,
			"at": at, "shape": "sphere", "r": 0.03, "dir": dir, "spread": spread, "v": v, "g": Vector3(0, -9.8, 0), "damp": Vector2(0.1, 0.4),
			"size": Vector2(0.7, 1.2), "ramp": MapEffects.SPARK_RAMP if not col_tint else [[0.0, Color(1, 1, 1, 1)], [0.5, Color(0.8, 0.85, 1.0, 0.9)], [1.0, Color(0.5, 0.6, 1.0, 0.0)]],
			"tint": col_tint, "collide": "bounce", "burst": burst, "cycle": cycle,
			"aabb": AABB(Vector3(-3, -ground - 0.5, -3) - at, Vector3(6, ground + 3.0, 6))})

	## Éclair blanc au point de la salve.
	func flash(at: Vector3, col: Color, sz: float) -> void:
		parts({"tex": "flash", "n": 2, "life": 0.14, "explo": 1.0, "at": at, "v": Vector2.ZERO, "size": Vector2(sz, sz * 1.5), "burst": true,
			"ramp": [[0.0, Color(col, 1.0)], [1.0, Color(col, 0.0)]]})

	func pluie_etincelles() -> void:
		var cable := MapEffects.solid(Color(0.05, 0.05, 0.05), 0.2, 0.7)
		mesh(cyl(0.012, 0.012, 0.35, 6), cable, Transform3D(Basis(Vector3.FORWARD, 0.15), Vector3(0.025, -0.17, 0)))
		mesh(cyl(0.006, 0.006, 0.04, 6), MapEffects.solid(Color(0.75, 0.45, 0.2), 0.9, 0.3), Transform3D(Basis(), Vector3(0.05, -0.36, 0)))
		var tip := Vector3(0.05, -0.38, 0)
		sparks(tip, 28, Vector3.DOWN, 70.0, Vector2(0.5, 2.2), 1.3, true)
		flash(tip, Color(1.0, 0.85, 0.6), 0.35)
		sparks(tip, 3, Vector3.DOWN, 25.0, Vector2(0.1, 0.6), 1.0, false)
		floor_collider(3.0)
		light(tip, Color(1.0, 0.78, 0.45), 2.6, 5.5, MapEffect.Light.FLASH)
		e.burst_every = Vector2(0.6, 3.0)
		e.burst_pops = 0.45

	func soudure() -> void:
		# Métal chauffé au rouge sur le mur, gerbe continue par à-coups.
		parts({"tex": "dot", "n": 2, "life": 0.5, "at": Vector3(0, 0, 0.012), "mode": "flat", "quad": Vector2(0.14, 0.14), "v": Vector2.ZERO,
			"size": Vector2(0.9, 1.1), "ramp": [[0.0, Color(1.0, 0.35, 0.08, 0.7)], [1.0, Color(1.0, 0.35, 0.08, 0.7)]]}).rotation.x = PI * 0.5
		sparks(Vector3(0, 0, 0.12), 70, Vector3(0, 0.2, 1), 40.0, Vector2(1.8, 4.0), 0.8, false, true)
		parts({"tex": "dot", "n": 4, "life": 0.08, "rand": 0.5, "at": Vector3(0, 0, 0.12), "v": Vector2.ZERO, "size": Vector2(0.25, 0.42), "cycle": true,
			"ramp": [[0.0, Color(0.8, 0.9, 1.0, 1.0)], [1.0, Color(0.6, 0.75, 1.0, 0.0)]]})
		parts({"tex": "smoke_b", "blend": "lit", "soft": 0.3, "n": 4, "life": 2.2, "at": Vector3(0, 0.05, 0.15), "v": Vector2(0.25, 0.45), "spread": 20.0,
			"size": Vector2(0.2, 0.3), "curve": [[0.0, 0.5], [1.0, 3.0]], "spin": Vector2(-30, 30), "turb": 0.3,
			"ramp": [[0.0, Color(0.5, 0.5, 0.52, 0.0)], [0.2, Color(0.5, 0.5, 0.52, 0.22)], [1.0, Color(0.5, 0.5, 0.52, 0.0)]]})
		floor_collider(3.0)
		light(Vector3(0, 0, 0.3), Color(0.72, 0.84, 1.0), 2.8, 6.5, MapEffect.Light.WELD)
		e.cycle_on = Vector2(1.5, 4.0)
		e.cycle_off = Vector2(0.4, 1.6)

	func court_circuit() -> void:
		var paint := MapEffects.solid(Color(0.26, 0.29, 0.25), 0.3, 0.7)
		mesh(box(Vector3(0.32, 0.42, 0.12)), paint, Transform3D(Basis(), Vector3(0, 0, 0.06)))
		mesh(box(Vector3(0.3, 0.4, 0.015)), MapEffects.solid(Color(0.2, 0.22, 0.2), 0.3, 0.7),
			Transform3D(Basis(Vector3.UP, -0.7), Vector3(-0.2, 0, 0.22)))
		mesh(box(Vector3(0.24, 0.3, 0.01)), MapEffects.solid(Color(0.03, 0.03, 0.03)), Transform3D(Basis(), Vector3(0, 0, 0.122)))
		var at := Vector3(0.02, 0.04, 0.14)
		sparks(at, 34, Vector3(0, 0.3, 1), 75.0, Vector2(1.0, 3.2), 0.9, true)
		flash(at, Color(0.8, 0.88, 1.0), 0.45)
		parts({"tex": "smoke_b", "blend": "lit", "soft": 0.3, "n": 5, "life": 2.4, "explo": 0.8, "at": at, "v": Vector2(0.2, 0.5), "spread": 30.0,
			"size": Vector2(0.2, 0.3), "curve": [[0.0, 0.4], [1.0, 3.0]], "spin": Vector2(-30, 30), "burst": true,
			"ramp": [[0.0, Color(0.35, 0.35, 0.36, 0.0)], [0.1, Color(0.35, 0.35, 0.36, 0.3)], [1.0, Color(0.35, 0.35, 0.36, 0.0)]]})
		tint = Color(0.7, 0.82, 1.0)
		for i in 2:
			arc(at, Vector3(0.12, 0.3, 0), 0.12, 1, true)
		floor_collider(3.0)
		light(at + Vector3(0, 0, 0.15), Color(0.72, 0.82, 1.0), 3.2, 6.0, MapEffect.Light.FLASH)
		e.burst_every = Vector2(1.2, 4.5)
		e.burst_pops = 0.55

	# -------------------------------------------------------------- électricité

	func _glow(at: Vector3, sz: float, alpha: float) -> void:
		parts({"tex": "dot", "n": 2, "life": 0.3, "at": at, "v": Vector2.ZERO, "size": Vector2(sz * 0.8, sz), "tint": true, "spin": Vector2(-90, 90),
			"ramp": [[0.0, Color(1, 1, 1, 0.0)], [0.3, Color(1, 1, 1, alpha)], [1.0, Color(1, 1, 1, 0.0)]]})

	func arc_() -> void:
		var copper := MapEffects.solid(Color(0.55, 0.32, 0.18), 0.9, 0.35)
		var steel := MapEffects.solid(Color(0.22, 0.22, 0.23), 0.7, 0.5)
		for sx in [-0.62, 0.62]:
			mesh(cyl(0.02, 0.03, maxf(0.05, ground), 8), steel, Transform3D(Basis(), Vector3(sx, -ground * 0.5, 0)))
			mesh(sphere(0.05), copper, Transform3D(Basis(), Vector3(sx, 0.0, 0)))
			mesh(cyl(0.06, 0.06, 0.03, 10), MapEffects.solid(Color(0.85, 0.82, 0.75), 0.0, 0.6), Transform3D(Basis(), Vector3(sx, -0.12, 0)))
			_glow(Vector3(sx, 0, 0), 0.3, 0.55)
			parts({"tex": "streak", "mode": "streak", "quad": Vector2(0.02, 0.1), "n": 5, "life": 0.6, "rand": 0.5, "at": Vector3(sx, 0, 0),
				"shape": "sphere", "r": 0.04, "spread": 90.0, "v": Vector2(0.4, 1.4), "g": Vector3(0, -9.8, 0), "size": Vector2(0.6, 1.0), "tint": true,
				"ramp": [[0.0, Color(1, 1, 1, 1)], [1.0, Color(0.6, 0.7, 1.0, 0.0)]], "collide": "bounce"})
		for i in 3:
			arc(Vector3(-0.58, 0, 0), Vector3(0.58, 0, 0), 0.38)
		floor_collider(2.0)
		light(Vector3.ZERO, tint, 2.0, 6.0, MapEffect.Light.CRACKLE)

	func tesla() -> void:
		var copper := MapEffects.solid(Color(0.55, 0.32, 0.18), 0.9, 0.35)
		var steel := MapEffects.solid(Color(0.2, 0.2, 0.21), 0.7, 0.5)
		mesh(sphere(0.14), steel, Transform3D(Basis(), Vector3.ZERO))
		mesh(cyl(0.1, 0.1, 0.5, 14), copper, Transform3D(Basis(), Vector3(0, -0.4, 0)))
		mesh(cyl(0.04, 0.05, maxf(0.05, ground - 0.6), 8), steel, Transform3D(Basis(), Vector3(0, -0.65 - maxf(0.0, ground - 0.65) * 0.5, 0)))
		_glow(Vector3.ZERO, 0.75, 0.45)
		for i in 5:
			arc(Vector3.ZERO, Vector3(0.45, 1.15, 0), 0.32, 1)
		parts({"tex": "dot", "n": 10, "life": 0.7, "rand": 0.5, "shape": "sphere", "r": 0.16, "spread": 180.0, "v": Vector2(0.5, 1.3),
			"g": Vector3(0, -3.0, 0), "size": Vector2(0.015, 0.03), "tint": true, "ramp": [[0.0, Color(1, 1, 1, 1)], [1.0, Color(1, 1, 1, 0)]]})
		light(Vector3.ZERO, tint, 2.4, 7.0, MapEffect.Light.CRACKLE)

	func cable_nu() -> void:
		var cable := MapEffects.solid(Color(0.04, 0.04, 0.045), 0.1, 0.7)
		mesh(cyl(0.012, 0.012, 0.6, 6), cable, Transform3D(Basis(Vector3.RIGHT, 0.12), Vector3(0, -0.3, 0.035)))
		var tip := Vector3(0, -0.62, 0.075)
		mesh(cyl(0.004, 0.004, 0.05, 5), MapEffects.solid(Color(0.75, 0.45, 0.2), 0.9, 0.3), Transform3D(Basis(Vector3.FORWARD, 0.5), tip + Vector3(0.01, 0.02, 0)))
		_glow(tip, 0.3, 0.6)
		for i in 2:
			arc(tip, Vector3(0.12, 0.3, 0), 0.12, 1)
		sparks(tip, 5, Vector3.DOWN, 40.0, Vector2(0.2, 0.8), 1.0, false, false, true)
		sparks(tip, 18, Vector3.DOWN, 80.0, Vector2(0.5, 2.0), 1.1, true, false, true)
		flash(tip, tint.lightened(0.4), 0.3)
		floor_collider(3.0)
		light(tip, tint, 1.6, 5.0, MapEffect.Light.CRACKLE)
		light(tip, tint, 2.4, 5.0, MapEffect.Light.FLASH, true)
		e.burst_every = Vector2(2.0, 6.0)
		e.burst_pops = 0.3

	# -------------------------------------------------------------- eau

	func water_mat() -> StandardMaterial3D:
		return MapEffects.solid(Color(0.1, 0.12, 0.14, 0.5), 0.6, 0.03)

	## Gouttes qui tombent de `at` et ronds au sol synchronisés sur leur chute.
	func drops(at: Vector3, n: int, life: float, dir: Vector3, v: Vector2, spread: float, quad_sz: Vector2, land: Vector3, ripples: int) -> void:
		var drop := float(at.y - land.y)
		var fall := sqrt(2.0 * maxf(0.05, drop) / 9.8)
		parts({"tex": "streak", "blend": "mix", "mode": "streak", "quad": quad_sz, "n": n, "life": life, "at": at, "dir": dir, "spread": spread,
			"v": v, "g": Vector3(0, -9.8, 0), "size": Vector2(0.9, 1.1), "pre": 0.0,
			"ramp": [[0.0, Color(MapEffects.WATER, 0.75)], [1.0, Color(MapEffects.WATER, 0.6)]], "collide": "hide",
			"aabb": AABB(Vector3(-2, -drop - 0.5, -2), Vector3(4, drop + 1.0, 4))})
		if ripples > 0:
			# Même rythme que les gouttes, décalé de leur temps de chute (préchauffage).
			parts({"tex": "ring", "blend": "mix", "mode": "flat", "n": ripples, "life": life, "at": land + Vector3(0, 0.012, 0),
				"pre": fposmod(life - fall, life), "shape": "sphere", "r": 0.02, "v": Vector2.ZERO, "size": Vector2(0.06, 0.08),
				"curve": [[0.0, 0.2], [1.0, 6.0]], "ramp": [[0.0, Color(0.75, 0.85, 0.95, 0.0)], [0.06, Color(0.75, 0.85, 0.95, 0.55)], [1.0, Color(0.7, 0.8, 0.9, 0.0)]]})
			parts({"tex": "streak", "blend": "mix", "mode": "streak", "quad": Vector2(0.008, 0.035), "n": ripples * 3, "life": life, "explo": 0.0,
				"at": land + Vector3(0, 0.02, 0), "pre": fposmod(life - fall, life), "spread": 35.0, "v": Vector2(0.4, 0.9), "g": Vector3(0, -9.8, 0),
				"size": Vector2(0.8, 1.0), "ramp": [[0.0, Color(MapEffects.WATER, 0.6)], [0.25, Color(MapEffects.WATER, 0.0)], [1.0, Color(MapEffects.WATER, 0.0)]]})

	func goutte() -> void:
		mesh(sphere(0.014), water_mat(), Transform3D(Basis().scaled(Vector3(1, 1.3, 1)), Vector3(0, -0.015, 0)))
		mesh(cyl(0.3, 0.3, 0.004, 20), water_mat(), Transform3D(Basis().scaled(Vector3(1, 1, 0.8)), Vector3(0, -ground + 0.003, 0)))
		drops(Vector3(0, -0.03, 0), 2, 1.4, Vector3.DOWN, Vector2(0.0, 0.05), 0.0, Vector2(0.012, 0.07), Vector3(0, -ground, 0), 2)
		floor_collider(1.0)

	func fuite() -> void:
		var rust := MapEffects.solid(Color(0.3, 0.17, 0.1), 0.7, 0.6)
		mesh(cyl(0.065, 0.065, 1.0, 14), rust, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0, 0, 0.09)))
		for sx in [-0.42, 0.42]:
			mesh(box(Vector3(0.05, 0.03, 0.09)), MapEffects.solid(Color(0.15, 0.15, 0.15), 0.8, 0.5), Transform3D(Basis(), Vector3(sx, 0.07, 0.045)))
		var at := Vector3(0.05, -0.03, 0.15)
		var fall := sqrt(2.0 * maxf(0.1, ground) / 9.8)
		var land := Vector3(0.05, -ground, 0.15 + 1.05 * fall)
		parts({"tex": "streak", "blend": "mix", "mode": "streak", "quad": Vector2(0.035, 0.3), "n": 110, "life": fall + 0.3, "at": at,
			"dir": Vector3(0, -0.15, 1.0), "spread": 4.0, "v": Vector2(0.95, 1.15), "g": Vector3(0, -9.8, 0), "size": Vector2(0.8, 1.2),
			"ramp": [[0.0, Color(MapEffects.WATER, 0.55)], [1.0, Color(MapEffects.WATER, 0.45)]], "collide": "hide",
			"aabb": AABB(Vector3(-1, -ground - 0.5, -0.5), Vector3(2, ground + 1.0, 4))})
		parts({"tex": "streak", "blend": "mix", "mode": "streak", "quad": Vector2(0.01, 0.04), "n": 16, "life": 0.45, "rand": 0.4, "at": land + Vector3(0, 0.03, 0),
			"shape": "sphere", "r": 0.06, "spread": 50.0, "v": Vector2(0.6, 1.4), "g": Vector3(0, -9.8, 0), "size": Vector2(0.8, 1.1),
			"ramp": [[0.0, Color(MapEffects.WATER, 0.7)], [1.0, Color(MapEffects.WATER, 0.0)]]})
		parts({"tex": "ring", "blend": "mix", "mode": "flat", "n": 4, "life": 0.9, "rand": 0.3, "at": land + Vector3(0, 0.012, 0), "shape": "sphere", "r": 0.1,
			"v": Vector2.ZERO, "size": Vector2(0.08, 0.12), "curve": [[0.0, 0.3], [1.0, 5.0]],
			"ramp": [[0.0, Color(0.75, 0.85, 0.95, 0.0)], [0.08, Color(0.75, 0.85, 0.95, 0.45)], [1.0, Color(0.7, 0.8, 0.9, 0.0)]]})
		parts({"tex": "smoke_b", "blend": "mix", "soft": 0.3, "n": 3, "life": 1.6, "at": land + Vector3(0, 0.08, 0), "v": Vector2(0.05, 0.15),
			"size": Vector2(0.35, 0.5), "curve": [[0.0, 0.6], [1.0, 1.6]], "spin": Vector2(-20, 20),
			"ramp": [[0.0, Color(0.8, 0.85, 0.9, 0.0)], [0.3, Color(0.8, 0.85, 0.9, 0.1)], [1.0, Color(0.8, 0.85, 0.9, 0.0)]]})
		mesh(cyl(0.5, 0.5, 0.004, 22), water_mat(), Transform3D(Basis().scaled(Vector3(1.2, 1, 0.8)), land + Vector3(0, 0.003, 0)))
		floor_collider(3.0)

	func flaque() -> void:
		mesh(cyl(0.65, 0.65, 0.004, 28), water_mat(), Transform3D(Basis().scaled(Vector3(1.0, 1.0, 0.75)), Vector3(0, 0.003, 0)))
		mesh(cyl(0.3, 0.3, 0.004, 18), water_mat(), Transform3D(Basis().scaled(Vector3(1.0, 1.0, 0.6)), Vector3(0.55, 0.002, 0.28)))
		parts({"tex": "ring", "blend": "mix", "mode": "flat", "n": 4, "life": 1.9, "rand": 0.4, "at": Vector3(0, 0.012, 0), "shape": "box",
			"ext": Vector3(0.45, 0.0, 0.3), "v": Vector2.ZERO, "size": Vector2(0.05, 0.08), "curve": [[0.0, 0.2], [1.0, 5.5]],
			"ramp": [[0.0, Color(0.75, 0.85, 0.95, 0.0)], [0.08, Color(0.75, 0.85, 0.95, 0.35)], [1.0, Color(0.7, 0.8, 0.9, 0.0)]]})

	# -------------------------------------------------------------- ambiance

	func poussiere() -> void:
		var c := Color(1.0, 0.92, 0.78)
		parts({"tex": "dot", "n": 70, "life": 12.0, "rand": 0.3, "at": Vector3(0, 1.25, 0), "shape": "box", "ext": Vector3(1.4, 1.0, 1.4),
			"dir": Vector3(1, 0, 0), "spread": 180.0, "v": Vector2(0.01, 0.04), "g": Vector3(0, -0.004, 0), "size": Vector2(0.012, 0.028),
			"curve": [[0.0, 0.0], [0.15, 1.0], [0.85, 1.0], [1.0, 0.0]], "turb": 0.12, "turb_scale": 3.0,
			"ramp": [[0.0, Color(c, 0.0)], [0.2, Color(c, 0.3)], [0.8, Color(c, 0.3)], [1.0, Color(c, 0.0)]],
			"aabb": AABB(Vector3(-2.5, -0.5, -2.5), Vector3(5, 3.5, 5))})

	func braises() -> void:
		parts({"tex": "dot", "n": 34, "life": 4.5, "rand": 0.4, "at": Vector3(0, 0.1, 0), "shape": "box", "ext": Vector3(0.9, 0.05, 0.9),
			"spread": 25.0, "v": Vector2(0.25, 0.6), "g": Vector3(0, 0.08, 0), "damp": Vector2(0.2, 0.4), "size": Vector2(0.018, 0.04),
			"curve": [[0.0, 0.4], [0.1, 1.0], [0.8, 0.8], [1.0, 0.0]], "turb": 0.9, "turb_scale": 0.8,
			"ramp": [[0.0, Color(1.0, 0.75, 0.35, 0.0)], [0.08, Color(1.0, 0.6, 0.2, 1.0)], [0.6, Color(1.0, 0.3, 0.05, 0.85)], [1.0, Color(0.5, 0.08, 0.02, 0.0)]],
			"aabb": AABB(Vector3(-2.5, -0.5, -2.5), Vector3(5, room_h + 1.0, 5))})
		light(Vector3(0, 0.4, 0), Color(1.0, 0.45, 0.15), 0.5, 4.0, MapEffect.Light.FIRE, true)

	func cendres() -> void:
		var top := maxf(0.5, room_h - ground - 0.2)
		var aabb := AABB(Vector3(-2.5, -0.5 - top, -2.5), Vector3(5, top + 1.0, 5))
		var c := Color(0.55, 0.53, 0.5)
		parts({"tex": "dot", "blend": "lit", "n": 50, "life": 14.0, "rand": 0.3, "at": Vector3(0, top, 0), "shape": "box", "ext": Vector3(1.4, 0.05, 1.4),
			"dir": Vector3.DOWN, "spread": 20.0, "v": Vector2(0.05, 0.15), "g": Vector3(0, -0.05, 0), "damp": Vector2(0.4, 0.6),
			"size": Vector2(0.02, 0.045), "spin": Vector2(-90, 90), "turb": 0.5, "turb_scale": 1.5, "collide": "hide",
			"ramp": [[0.0, Color(c, 0.0)], [0.1, Color(c, 0.85)], [0.85, Color(c, 0.85)], [1.0, Color(c, 0.0)]], "aabb": aabb})
		parts({"tex": "dot", "n": 8, "life": 12.0, "rand": 0.3, "at": Vector3(0, top, 0), "shape": "box", "ext": Vector3(1.3, 0.05, 1.3),
			"dir": Vector3.DOWN, "spread": 20.0, "v": Vector2(0.05, 0.15), "g": Vector3(0, -0.05, 0), "damp": Vector2(0.4, 0.6),
			"size": Vector2(0.015, 0.03), "turb": 0.5, "collide": "hide", "ramp": MapEffects.EMBER_RAMP, "aabb": aabb})
		floor_collider(2.5)

	func feux_follets() -> void:
		var at := Vector3(0, 0.9, 0)
		var aabb := AABB(Vector3(-2.5, -1.5, -2.5), Vector3(5, 4, 5))
		parts({"tex": "dot", "n": 5, "life": 5.0, "rand": 0.3, "at": at, "shape": "sphere", "r": 0.6, "spread": 180.0, "v": Vector2(0.05, 0.15),
			"size": Vector2(0.35, 0.55), "curve": [[0.0, 0.0], [0.2, 1.0], [0.8, 1.0], [1.0, 0.0]], "tint": true, "spin": Vector2(-60, 60),
			"turb": 1.4, "turb_scale": 0.7, "ramp": [[0.0, Color(1, 1, 1, 0.0)], [0.2, Color(1, 1, 1, 0.6)], [0.8, Color(1, 1, 1, 0.5)], [1.0, Color(1, 1, 1, 0.0)]],
			"aabb": aabb})
		parts({"tex": "dot", "n": 6, "life": 5.0, "rand": 0.3, "at": at, "shape": "sphere", "r": 0.6, "spread": 180.0, "v": Vector2(0.05, 0.15),
			"size": Vector2(0.05, 0.08), "curve": [[0.0, 0.0], [0.2, 1.0], [0.8, 1.0], [1.0, 0.0]], "turb": 1.4, "turb_scale": 0.7,
			"ramp": [[0.0, Color(0.85, 1.0, 0.88, 0.0)], [0.2, Color(0.85, 1.0, 0.88, 1.0)], [1.0, Color(0.85, 1.0, 0.88, 0.0)]], "aabb": aabb})
		parts({"tex": "twirl", "n": 8, "life": 1.8, "rand": 0.4, "at": at, "shape": "sphere", "r": 0.6, "v": Vector2(0.0, 0.1), "size": Vector2(0.15, 0.3),
			"tint": true, "spin": Vector2(-200, 200), "ramp": [[0.0, Color(1, 1, 1, 0.0)], [0.3, Color(1, 1, 1, 0.3)], [1.0, Color(1, 1, 1, 0.0)]], "aabb": aabb})
		parts({"tex": "dot", "n": 24, "life": 3.0, "rand": 0.4, "at": at, "shape": "box", "ext": Vector3(0.7, 0.5, 0.7), "v": Vector2(0.05, 0.12),
			"size": Vector2(0.01, 0.018), "tint": true, "turb": 0.6, "ramp": [[0.0, Color(1, 1, 1, 0.0)], [0.3, Color(1, 1, 1, 0.9)], [1.0, Color(1, 1, 1, 0.0)]],
			"aabb": aabb})
		light(at, tint, 0.9, 4.5, MapEffect.Light.PULSE)

	## Construit l'effet `id` (« arc » : arc_, le nom étant pris).
	func call_fx(id: String) -> void:
		if id == "arc":
			arc_()
		elif has_method(id):
			call(id)
