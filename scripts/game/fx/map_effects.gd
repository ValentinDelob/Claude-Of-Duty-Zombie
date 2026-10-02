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
##     quelques centièmes de seconde).
## Format 11 : des EFFETS PURS. Aucun objet solide (bûches, torche, tuyau,
## boîtier, électrodes, bobine, câble, flaque sont des décors à part :
## MapCatalog.PREFABS, EditorPrefabs) et aucune collision.
## Textures : assets/textures/fx/ (Kenney « Particle Pack », CC0, voir
## docs/ASSETS.md) ; à défaut, dégradés calculés (aucun fichier requis).
##
## Repère d'un effet : origine au point posé, y vers le haut ; effet mural :
## +z sort du mur vers la pièce, x le long du mur. `opts` (layout
## « effects ») : intensity (quantité de particules et lumière), zone
## [largeur, profondeur, hauteur] (m, MapCatalog.effect_zone), color
## (« rrggbb », effets qui se teintent), ground (distance au sol, m), room_h
## (hauteur de la pièce, m).
##
## ZONE (format 11) : l'émission remplit la zone (boîte tournée avec
## l'effet) ; le nombre de particules suit sa surface (densité constante,
## × intensité) jusqu'au plafond de l'effet (« cap » du catalogue), puis les
## budgets de la carte (PARTICLE_BUDGET, MeshMapBuilder). Les particules
## gardent leur taille : une grande zone a PLUS de particules, pas de plus
## grosses (seules les nappes de fumée grossissent un peu quand le plafond
## est atteint, pour rester couvrantes). Lumières : portée selon la zone.

## Particules au plus par carte (au-delà, MeshMapBuilder les réduit toutes).
const PARTICLE_BUDGET := 9000
## Lumières d'effets au plus par carte (les suivantes restent éteintes).
const LIGHT_BUDGET := 16
## Portée maximale (m) d'une lumière d'effet.
const MAX_LIGHT_RANGE := 20.0
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
## Bout du câble suspendu (décor « cable_suspendu ») sous le plafond : là
## où naissent la pluie d'étincelles et les étincelles de câble.
const CABLE_TIP := Vector3(0.0, -0.62, 0.075)


## Effet `id` construit, ou null s'il est inconnu.
static func build(id: String, opts: Dictionary = {}) -> MapEffect:
	if not MapCatalog.EFFECTS.has(id):
		return null
	var e := MapEffect.new()
	e.fx_id = id
	e.name = "Effect_" + id
	e.intensity = clampf(_f(opts, "intensity", 1.0), MapCatalog.EFFECT_LIMITS.intensite[0], MapCatalog.EFFECT_LIMITS.intensite[1])
	var d: Dictionary = MapCatalog.EFFECTS[id]
	e.zone = zone_of(id, opts)
	var tint := Color.html(String(d.get("couleur", "#ffffff")))
	var cs := String(opts.get("color", ""))
	if d.has("couleur") and Color.html_is_valid(cs):
		tint = Color.html(cs)
	var ground := maxf(0.0, _f(opts, "ground", 0.0))
	var room_h := maxf(1.0, _f(opts, "room_h", 3.2))
	var b := Builder.new(e, tint, ground, room_h, MapCatalog.effect_default_zone(id), String(d.mount))
	b.call_fx(id)
	b.fit_cap(int(d.get("cap", 600)))
	return e


## Zone d'un effet tirée de `opts` (« zone » : [largeur, profondeur,
## hauteur], bornée à celles de l'effet) ; à défaut, la zone par défaut
## (× « scale » d'une description d'avant le format 11).
static func zone_of(id: String, opts: Dictionary) -> Vector3:
	var def := MapCatalog.effect_default_zone(id)
	var zv: Variant = opts.get("zone")
	if not (zv is Array and (zv as Array).size() == 3):
		var k := clampf(_f(opts, "scale", 1.0), MapCatalog.EFFECT_LIMITS.taille[0], MapCatalog.EFFECT_LIMITS.taille[1])
		zv = [def.x * k, def.y * k, def.z * k]
	var out := def
	var keys := ["l", "p", "h"]
	for i in 3:
		var x: Variant = zv[i]
		if not ((x is float or x is int) and is_finite(float(x))):
			continue
		var b := MapCatalog.effect_zone_bounds(id, keys[i])
		out[i] = clampf(float(x), b[0], b[1])
	# Effet mural : profondeur = sa portée (fixe) ; sans volume : hauteur 0.
	if String(MapCatalog.EFFECTS[id].mount) == "mur":
		out.y = def.y
	if def.z <= 0.0:
		out.z = 0.0
	return out


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


# ------------------------------------------------------------------ construction

## Construit les couches d'un effet (une fonction par effet du catalogue).
class Builder:
	var e: MapEffect
	var tint: Color
	var ground: float
	var room_h: float
	var mount: String
	## Demi-largeur (x), demi-profondeur (z ; effet mural : portée), hauteur
	## de la zone (m) ; zone par défaut de l'effet (rapports de surface).
	var hx: float
	var hz: float
	var zh: float
	var z0: Vector3
	## Portée des lumières selon la zone (rapport à la zone par défaut, borné).
	var light_k := 1.0

	func _init(fx: MapEffect, t: Color, g: float, h: float, def: Vector3, m: String) -> void:
		e = fx
		tint = t
		ground = g
		room_h = h
		z0 = def
		mount = m
		hx = fx.zone.x * 0.5
		hz = fx.zone.y * 0.5
		zh = fx.zone.z
		var r := maxf(fx.zone.x / maxf(def.x, 0.01), fx.zone.y / maxf(def.y, 0.01))
		if def.z > 0.0:
			r = maxf(r, fx.zone.z / def.z)
		light_k = clampf(sqrt(r), 0.7, 2.5)

	## Surface de la zone rapportée à celle par défaut (densité constante) :
	## largeur × profondeur au sol et au plafond, largeur × hauteur au mur.
	func area_k() -> float:
		if mount == "mur":
			return (e.zone.x * e.zone.z) / maxf(z0.x * z0.z, 0.0001)
		return (e.zone.x * e.zone.y) / maxf(z0.x * z0.y, 0.0001)

	## Volume de la zone rapporté à celui par défaut (poussière, feux follets).
	func vol_k() -> float:
		return area_k() * (e.zone.z / maxf(z0.z, 0.0001) if z0.z > 0.0 else 1.0)

	## Demi-étendue d'émission au sol : la zone moins `margin` (taille des
	## flammes, volutes), jamais moins de `lo`.
	func inset(margin: float, lo := 0.02) -> Vector2:
		return Vector2(maxf(hx - margin, lo), maxf(hz - margin, lo))

	## Boîte de visibilité (repère de l'effet) : la zone, `up` m au-dessus de
	## l'origine, jusqu'au sol, `margin` m de marge.
	func zone_aabb(up: float, margin := 1.5) -> AABB:
		if mount == "mur":
			return AABB(Vector3(-hx - margin, -ground - 0.5, -0.3), Vector3(hx * 2.0 + margin * 2.0, ground + up + 1.0, e.zone.y + margin + 0.3))
		return AABB(Vector3(-hx - margin, -ground - 0.5, -hz - margin), Vector3(hx * 2.0 + margin * 2.0, ground + up + 1.0, hz * 2.0 + margin * 2.0))

	## Couche de particules. Clés de `c` : tex, blend, soft, mode (face, streak,
	## flat), quad (taille du panneau), n, k (multiplicateur de surface : la
	## couche remplit la zone, plafonnée par fit_cap), cover (nappe : grossit
	## un peu si le plafond est atteint), life, pre (préchauffage, s), explo,
	## rand, at, shape (point, sphere, box), r, ext, dir, spread, flatness, v
	## [min, max], g (gravité), damp, size [min, max], curve, ramp, tint
	## (bool : couleur de l'effet), spin [min, max] (°/s), angle (rotation au
	## hasard), turb (force), turb_scale, collide (« bounce », « hide »),
	## burst, cycle, aabb (repère de l'effet ; défaut : la zone).
	func parts(c: Dictionary) -> GPUParticles3D:
		var p := GPUParticles3D.new()
		var pm := ParticleProcessMaterial.new()
		var burst := bool(c.get("burst", false))
		var k := maxf(0.0, float(c.get("k", 1.0)))
		p.amount = maxi(1, roundi(float(c.get("n", 8)) * k * (e.intensity if not burst else sqrt(e.intensity))))
		p.set_meta("area", c.has("k"))
		p.set_meta("cover", bool(c.get("cover", false)))
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
		var bb: AABB = c.get("aabb", zone_aabb(room_h))
		p.visibility_aabb = AABB(bb.position - p.position, bb.size)
		e.add_part(p, burst, bool(c.get("cycle", false)))
		return p

	## Plafond de particules de l'effet : au-delà, les couches qui remplissent
	## la zone (« k ») sont réduites d'autant ; les nappes (« cover »)
	## grossissent un peu (au plus ×2) pour rester couvrantes.
	func fit_cap(cap: int) -> void:
		var fixed := 0
		var flex := 0
		for p in e.parts:
			if p.get_meta("area", false):
				flex += p.amount
			else:
				fixed += p.amount
		if flex == 0 or fixed + flex <= cap:
			return
		var k := clampf(float(maxi(cap - fixed, int(flex * 0.02) + 1)) / flex, 0.02, 1.0)
		for p in e.parts:
			if not p.get_meta("area", false):
				continue
			p.amount = maxi(1, int(p.amount * k))
			if p.get_meta("cover", false):
				var pm := p.process_material as ParticleProcessMaterial
				var g := minf(2.0, sqrt(1.0 / k))
				pm.scale_min *= g
				pm.scale_max *= g

	## Lumière de l'effet (sans ombre), à `at` dans le repère de l'effet ;
	## portée selon la zone (light_k).
	func light(at: Vector3, col: Color, energy: float, rng: float, mode: int, minor := false) -> OmniLight3D:
		var l := OmniLight3D.new()
		l.position = at
		l.light_color = col
		l.light_energy = energy * clampf(e.intensity, 0.5, 1.6)
		l.omni_range = minf(rng * light_k, MapEffects.MAX_LIGHT_RANGE)
		l.omni_attenuation = 1.4
		l.shadow_enabled = false
		l.light_specular = 0.35
		e.add_light(l, mode, minor)
		return l

	## Arc électrique : `mode` 0 de a à b, 1 rayon au hasard autour de a
	## (b.x, b.y : longueur min, max). Panneau texturé (pas un objet solide).
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

	## Collision du sol pour les particules seulement (étincelles qui
	## rebondissent, gouttes qui s'arrêtent) : sous toute la zone, 1,5 m de marge.
	func floor_collider() -> void:
		var cb := GPUParticlesCollisionBox3D.new()
		if mount == "mur":
			cb.size = Vector3(hx * 2.0 + 3.0, 0.4, e.zone.y + 3.0)
			cb.position = Vector3(0, -ground - 0.2, e.zone.y * 0.5)
		else:
			cb.size = Vector3(hx * 2.0 + 3.0, 0.4, hz * 2.0 + 3.0)
			cb.position = Vector3(0, -ground - 0.2, 0)
		e.body.add_child(cb)

	# -------------------------------------------------------------- flammes

	## Feu en couches : flammes (volutes et langues), cœur lumineux, braises,
	## fumée, lumière vacillante. `ext` : demi-étendue du foyer (x, z), `w` :
	## largeur d'une flamme (taille des panneaux, fixe), `h` : hauteur des
	## flammes (m), `dens` : densité, `k` : multiplicateur de surface, `dark` :
	## fumée noire (0 à 1). `n_lights` : 0 = selon la zone (1 à 3, le long du
	## plus grand côté).
	func fire(at: Vector3, ext: Vector2, w: float, h: float, dens: float, k: float, dark: float, energy: float, rng: float, n_lights := 1) -> void:
		var life := 0.55 + h * 0.35
		var bx := Vector3(ext.x, 0.03, ext.y)
		var fire_bb := AABB(at + Vector3(-ext.x - 1.0, -0.2, -ext.y - 1.0), Vector3(ext.x * 2.0 + 2.0, h * 2.0 + 1.0, ext.y * 2.0 + 2.0))
		parts({"tex": "fire_billow", "n": 12 * dens, "k": k, "angle_deg": 25.0, "life": life, "rand": 0.3, "at": at, "shape": "box", "ext": bx, "spread": 10.0,
			"v": Vector2(0.25, 0.55) * h / life, "g": Vector3(0, h * 1.1 / (life * life), 0), "damp": Vector2(0.4, 1.0),
			"size": Vector2(w * 1.6 + 0.12, w * 2.6 + 0.2), "curve": [[0.0, 0.35], [0.2, 1.0], [0.6, 0.75], [1.0, 0.1]],
			"ramp": MapEffects.FIRE_RAMP, "spin": Vector2(-20, 20), "turb": 0.3, "turb_scale": 1.2, "aabb": fire_bb})
		parts({"tex": "flame_tongue", "n": 9 * dens, "k": k, "life": life * 0.7, "rand": 0.35, "at": at, "shape": "box", "ext": bx * 0.8, "spread": 6.0,
			"v": Vector2(0.3, 0.6) * h / life, "g": Vector3(0, h / (life * life), 0), "damp": Vector2(0.5, 1.2), "angle": false,
			"size": Vector2(w * 1.3 + 0.12, w * 2.0 + 0.2), "curve": [[0.0, 0.5], [0.25, 1.0], [1.0, 0.25]], "ramp": MapEffects.TONGUE_RAMP,
			"aabb": fire_bb})
		parts({"tex": "fire_core", "n": 3 * dens, "k": k, "life": 0.6, "at": at + Vector3(0, h * 0.15, 0), "shape": "box", "ext": bx * 0.5,
			"v": Vector2(0.02, 0.08), "size": Vector2(w * 2.4 + 0.2, w * 3.2 + 0.3), "spin": Vector2(-25, 25), "aabb": fire_bb,
			"ramp": [[0.0, Color(1.0, 0.5, 0.15, 0.0)], [0.3, Color(1.0, 0.42, 0.1, 0.32)], [1.0, Color(0.6, 0.15, 0.03, 0.0)]]})
		parts({"tex": "dot", "n": 10 * dens, "k": k, "life": 2.2, "rand": 0.45, "at": at + Vector3(0, h * 0.2, 0), "shape": "box",
			"ext": Vector3(ext.x + w * 0.5, 0.1, ext.y + w * 0.5), "spread": 25.0, "v": Vector2(0.6, 1.3) * maxf(1.0, h), "g": Vector3(0, 0.25, 0),
			"damp": Vector2(0.3, 0.8), "size": Vector2(0.02, 0.045), "curve": [[0.0, 1.0], [0.7, 0.8], [1.0, 0.0]], "ramp": MapEffects.EMBER_RAMP,
			"turb": 1.1, "turb_scale": 0.6, "aabb": zone_aabb(room_h)})
		var sc := Color(0.24, 0.23, 0.22).lerp(Color(0.04, 0.035, 0.03), dark)
		parts({"tex": "smoke_a", "blend": "lit", "soft": 0.5, "n": 6 * dens, "k": k, "cover": true, "life": 3.0 + h, "rand": 0.3,
			"at": at + Vector3(0, h * 0.75, 0), "shape": "box", "ext": Vector3(ext.x * 0.8 + 0.05, 0.1, ext.y * 0.8 + 0.05), "spread": 12.0,
			"v": Vector2(0.35, 0.6) * maxf(1.0, h * 0.8), "g": Vector3(0, 0.1, 0), "damp": Vector2(0.2, 0.45), "size": Vector2(w * 2.0 + 0.4, w * 3.0 + 0.6),
			"curve": [[0.0, 0.4], [1.0, 1.9]], "ramp": [[0.0, Color(sc, 0.0)], [0.15, Color(sc, 0.35 + dark * 0.35)], [1.0, Color(sc, 0.0)]],
			"spin": Vector2(-25, 25), "turb": 0.35, "aabb": zone_aabb(room_h + 2.0, 2.5)})
		var col := Color(1.0, 0.55, 0.22)
		if n_lights <= 0:
			n_lights = clampi(ceili(maxf(ext.x, ext.y) - 0.05), 1, 3)
		if n_lights <= 1:
			light(at + Vector3(0, h * 0.45, 0), col, energy, rng, MapEffect.Light.FIRE)
		else:
			# Le long du plus grand côté du foyer.
			var axis := Vector3(ext.x, 0, 0) if ext.x >= ext.y else Vector3(0, 0, ext.y)
			for i in n_lights:
				var f := float(i) / (n_lights - 1) * 1.2 - 0.6
				light(at + axis * f + Vector3(0, h * 0.45, 0), col, energy / n_lights * 1.4, rng, MapEffect.Light.FIRE, i > 0)

	func petit_feu() -> void:
		fire(Vector3(0, 0.05, 0), inset(0.16), 0.14, 0.75, 1.0, area_k(), 0.0, 1.8, 6.0)

	func brasier() -> void:
		fire(Vector3(0, 0.08, 0), inset(0.3), 0.3, 1.3, 2.0, area_k(), 0.15, 2.8, 9.0)

	func baril_feu() -> void:
		fire(Vector3(0, 0.02, 0), inset(0.12), 0.18, 0.9, 1.3, area_k(), 0.5, 2.2, 7.5)

	## Flamme au bout de la torche murale (décor « torche_murale ») : largeur
	## et hauteur de la flamme selon la zone (petite, peu étirable).
	func torche() -> void:
		var kw := e.zone.x / z0.x
		var kh := e.zone.z / z0.z
		fire(Vector3(0, 0.27, 0.29), Vector2(0.04, 0.04) * kw, 0.04 * kw, 0.38 * kh, 0.7, 1.0, 0.3, 1.4, 5.5)

	## Nappe de feu sur toute la zone, fumée épaisse, 1 à 3 lumières.
	func incendie() -> void:
		fire(Vector3(0, 0.05, 0), inset(0.28), 0.9, 1.8, 3.2, area_k(), 0.8, 3.2, 12.0, 0)

	# -------------------------------------------------------------- fumées

	func fumee_legere() -> void:
		var c := Color(0.58, 0.58, 0.58)
		var ex := inset(0.25, 0.05)
		for t in [["smoke_b", 10], ["smoke_a", 5]]:
			parts({"tex": t[0], "blend": "lit", "soft": 0.6, "n": t[1], "k": area_k(), "cover": true, "life": 6.5, "rand": 0.3, "at": Vector3(0, 0.15, 0),
				"shape": "box", "ext": Vector3(ex.x, 0.05, ex.y), "spread": 15.0, "v": Vector2(0.18, 0.38), "g": Vector3(0, 0.05, 0),
				"damp": Vector2(0.05, 0.15), "size": Vector2(0.5, 0.85), "curve": [[0.0, 0.5], [1.0, 2.4]], "tint": true, "spin": Vector2(-15, 15),
				"turb": 0.25, "turb_scale": 2.0, "ramp": [[0.0, Color(c, 0.0)], [0.2, Color(c, 0.3)], [0.7, Color(c, 0.16)], [1.0, Color(c, 0.0)]],
				"aabb": zone_aabb(room_h, 2.5)})

	func fumee_noire() -> void:
		var c := Color(0.035, 0.03, 0.028)
		var ex := inset(0.4, 0.05)
		for t in [["smoke_a", 16, 1.0], ["smoke_b", 10, 0.8]]:
			parts({"tex": t[0], "blend": "lit", "soft": 0.6, "n": t[1], "k": area_k(), "cover": true, "life": 7.0, "rand": 0.25, "at": Vector3(0, 0.2, 0),
				"shape": "box", "ext": Vector3(ex.x, 0.05, ex.y), "spread": 12.0, "v": Vector2(0.6, 0.95), "g": Vector3(0, 0.08, 0),
				"damp": Vector2(0.15, 0.3), "size": Vector2(0.9, 1.3) * float(t[2]), "curve": [[0.0, 0.5], [0.5, 1.6], [1.0, 2.8]], "spin": Vector2(-18, 18),
				"turb": 0.45, "turb_scale": 2.2, "ramp": [[0.0, Color(c, 0.0)], [0.1, Color(c, 0.8)], [0.6, Color(c, 0.55)], [1.0, Color(c, 0.0)]],
				"aabb": zone_aabb(room_h + 2.0, 3.0)})
		# Foyer qui couve au pied de la colonne.
		var fx := inset(0.5)
		parts({"tex": "fire_core", "n": 3, "k": area_k(), "life": 1.4, "at": Vector3(0, 0.06, 0), "shape": "box", "ext": Vector3(fx.x, 0.0, fx.y),
			"v": Vector2(0.02, 0.05), "size": Vector2(0.5, 0.8), "spin": Vector2(-20, 20),
			"ramp": [[0.0, Color(1.0, 0.35, 0.08, 0.0)], [0.4, Color(1.0, 0.3, 0.06, 0.3)], [1.0, Color(0.5, 0.08, 0.02, 0.0)]]})
		parts({"tex": "dot", "n": 8, "k": area_k(), "life": 1.8, "rand": 0.4, "shape": "box", "ext": Vector3(ex.x, 0.1, ex.y), "spread": 30.0,
			"v": Vector2(0.4, 0.9), "g": Vector3(0, 0.2, 0), "size": Vector2(0.015, 0.035), "ramp": MapEffects.EMBER_RAMP, "turb": 0.8})
		light(Vector3(0, 0.2, 0), Color(1.0, 0.4, 0.12), 0.7, 3.5, MapEffect.Light.FIRE, true)

	## Jet de vapeur (le tuyau est le décor « tuyau_vapeur ») : un jet par
	## point de la zone (largeur le long du mur × hauteur).
	func vapeur() -> void:
		var c := Color(0.8, 0.83, 0.86)
		var ext := Vector3(maxf(hx - 0.15, 0.0), maxf(zh * 0.5 - 0.15, 0.0), 0.0)
		var reach := e.zone.y
		parts({"tex": "smoke_b", "blend": "mix", "soft": 0.3, "n": 34, "k": area_k(), "life": 1.8, "rand": 0.3, "at": Vector3(0, 0, 0.19),
			"shape": "box", "ext": ext, "dir": Vector3(0, 0.12, 1.0), "spread": 7.0, "v": Vector2(2.4, 3.2) * (reach / 1.5), "g": Vector3(0, 0.6, 0),
			"damp": Vector2(2.4, 3.4), "size": Vector2(0.12, 0.2), "curve": [[0.0, 0.3], [0.3, 1.3], [1.0, 3.4]], "spin": Vector2(-45, 45), "turb": 0.3,
			"ramp": [[0.0, Color(c, 0.0)], [0.06, Color(c, 0.6)], [0.5, Color(c, 0.25)], [1.0, Color(c, 0.0)]], "aabb": zone_aabb(2.5)})
		parts({"tex": "streak", "blend": "mix", "mode": "streak", "quad": Vector2(0.012, 0.05), "n": 6, "k": area_k(), "life": 0.7,
			"at": Vector3(0, -0.03, 0.19), "shape": "box", "ext": ext, "dir": Vector3(0, 0.1, 1), "spread": 15.0, "v": Vector2(1.0, 2.0),
			"g": Vector3(0, -9.8, 0), "size": Vector2(0.8, 1.2), "ramp": [[0.0, Color(MapEffects.WATER, 0.6)], [1.0, Color(MapEffects.WATER, 0.0)]],
			"collide": "hide"})
		floor_collider()

	## Nappe de brume rampante sur toute la zone, épaisse de sa hauteur.
	func brouillard() -> void:
		var c := Color(1, 1, 1)
		var ex := inset(0.2, 0.3)
		var th := maxf(zh, 0.3)
		parts({"tex": "smoke_a", "blend": "lit", "soft": 1.0, "n": 18, "k": area_k(), "cover": true, "life": 14.0, "rand": 0.3, "at": Vector3(0, th * 0.5, 0),
			"shape": "box", "ext": Vector3(ex.x, th * 0.17, ex.y), "dir": Vector3(1, 0, 0), "spread": 180.0, "flatness": 1.0, "v": Vector2(0.02, 0.07),
			"size": Vector2(2.0, 3.0) * clampf(th / 0.6, 0.7, 1.8), "curve": [[0.0, 0.6], [0.5, 1.0], [1.0, 1.2]], "tint": true, "spin": Vector2(-4, 4),
			"ramp": [[0.0, Color(c, 0.0)], [0.3, Color(c, 0.17)], [0.7, Color(c, 0.17)], [1.0, Color(c, 0.0)]], "aabb": zone_aabb(th + 2.0, 3.0)})
		parts({"tex": "smoke_b", "blend": "lit", "soft": 0.8, "n": 10, "k": area_k(), "cover": true, "life": 10.0, "rand": 0.3, "at": Vector3(0, th * 0.2, 0),
			"shape": "box", "ext": Vector3(maxf(ex.x - 0.2, 0.3), th * 0.08, maxf(ex.y - 0.2, 0.3)), "dir": Vector3(1, 0, 0), "spread": 180.0, "flatness": 1.0,
			"v": Vector2(0.03, 0.09), "size": Vector2(1.2, 1.8) * clampf(th / 0.6, 0.7, 1.8), "tint": true, "spin": Vector2(-6, 6),
			"ramp": [[0.0, Color(c, 0.0)], [0.3, Color(c, 0.14)], [0.7, Color(c, 0.14)], [1.0, Color(c, 0.0)]], "aabb": zone_aabb(th + 2.0, 3.0)})

	# -------------------------------------------------------------- étincelles

	## Gerbe d'étincelles étirées (rebondissent au sol) ; `ext` : demi-étendue
	## de la boîte d'émission (zone), `k` : multiplicateur de surface.
	func sparks(at: Vector3, n: int, dir: Vector3, spread: float, v: Vector2, life: float, burst: bool, cycle := false, col_tint := false,
			ext := Vector3.ZERO, k := 1.0) -> void:
		var c := {"tex": "streak", "mode": "streak", "quad": Vector2(0.045, 0.24), "n": n, "life": life, "rand": 0.5, "explo": 0.92 if burst else 0.0,
			"at": at, "shape": "box" if ext != Vector3.ZERO else "sphere", "r": 0.03, "ext": ext, "dir": dir, "spread": spread, "v": v,
			"g": Vector3(0, -9.8, 0), "damp": Vector2(0.1, 0.4), "size": Vector2(0.7, 1.2),
			"ramp": MapEffects.SPARK_RAMP if not col_tint else [[0.0, Color(1, 1, 1, 1)], [0.5, Color(0.8, 0.85, 1.0, 0.9)], [1.0, Color(0.5, 0.6, 1.0, 0.0)]],
			"tint": col_tint, "collide": "bounce", "burst": burst, "cycle": cycle, "aabb": zone_aabb(3.0, 3.0)}
		if k != 1.0:
			c["k"] = k
		parts(c)

	## Éclair blanc au point de la salve.
	func flash(at: Vector3, col: Color, sz: float) -> void:
		parts({"tex": "flash", "n": 2, "life": 0.14, "explo": 1.0, "at": at, "v": Vector2.ZERO, "size": Vector2(sz, sz * 1.5), "burst": true,
			"ramp": [[0.0, Color(col, 1.0)], [1.0, Color(col, 0.0)]]})

	## Pluie d'étincelles du plafond (le câble est le décor « cable_suspendu ») :
	## gerbes nées n'importe où dans la zone, autour du bout du câble.
	func pluie_etincelles() -> void:
		var ex := inset(0.22, 0.03)
		var ext := Vector3(ex.x, 0.02, ex.y)
		sparks(MapEffects.CABLE_TIP, 28, Vector3.DOWN, 70.0, Vector2(0.5, 2.2), 1.3, true, false, false, ext, area_k())
		flash(MapEffects.CABLE_TIP, Color(1.0, 0.85, 0.6), 0.35)
		sparks(MapEffects.CABLE_TIP, 3, Vector3.DOWN, 25.0, Vector2(0.1, 0.6), 1.0, false, false, false, ext, area_k())
		floor_collider()
		light(MapEffects.CABLE_TIP, Color(1.0, 0.78, 0.45), 2.6, 5.5, MapEffect.Light.FLASH)
		e.burst_every = Vector2(0.6, 3.0)
		e.burst_pops = 0.45

	## Soudure sur le mur : métal chauffé au rouge, gerbe continue par à-coups,
	## sur la zone (largeur × hauteur).
	func soudure() -> void:
		var ext := Vector3(maxf(hx - 0.2, 0.0), maxf(zh * 0.5 - 0.2, 0.0), 0.0)
		parts({"tex": "dot", "n": 2, "k": area_k(), "life": 0.5, "at": Vector3(0, 0, 0.012), "mode": "flat", "quad": Vector2(0.14, 0.14), "v": Vector2.ZERO,
			"shape": "box", "ext": Vector3(ext.x, 0.0, ext.y), "size": Vector2(0.9, 1.1),
			"ramp": [[0.0, Color(1.0, 0.35, 0.08, 0.7)], [1.0, Color(1.0, 0.35, 0.08, 0.7)]]}).rotation.x = PI * 0.5
		sparks(Vector3(0, 0, 0.12), 70, Vector3(0, 0.2, 1), 40.0, Vector2(1.8, 4.0), 0.8, false, true, false, ext, area_k())
		parts({"tex": "dot", "n": 4, "k": area_k(), "life": 0.08, "rand": 0.5, "at": Vector3(0, 0, 0.12), "shape": "box", "ext": ext, "v": Vector2.ZERO,
			"size": Vector2(0.25, 0.42), "cycle": true, "ramp": [[0.0, Color(0.8, 0.9, 1.0, 1.0)], [1.0, Color(0.6, 0.75, 1.0, 0.0)]]})
		parts({"tex": "smoke_b", "blend": "lit", "soft": 0.3, "n": 4, "k": area_k(), "life": 2.2, "at": Vector3(0, 0.05, 0.15), "shape": "box", "ext": ext,
			"v": Vector2(0.25, 0.45), "spread": 20.0, "size": Vector2(0.2, 0.3), "curve": [[0.0, 0.5], [1.0, 3.0]], "spin": Vector2(-30, 30), "turb": 0.3,
			"ramp": [[0.0, Color(0.5, 0.5, 0.52, 0.0)], [0.2, Color(0.5, 0.5, 0.52, 0.22)], [1.0, Color(0.5, 0.5, 0.52, 0.0)]]})
		floor_collider()
		light(Vector3(0, 0, 0.3), Color(0.72, 0.84, 1.0), 2.8, 6.5, MapEffect.Light.WELD)
		e.cycle_on = Vector2(1.5, 4.0)
		e.cycle_off = Vector2(0.4, 1.6)

	## Court-circuit (le boîtier est le décor « boitier_electrique ») :
	## claquements, étincelles, fumée et arcs, sur la zone.
	func court_circuit() -> void:
		var at := Vector3(0.02, 0.04, 0.14)
		var ext := Vector3(maxf(hx - 0.2, 0.0), maxf(zh * 0.5 - 0.25, 0.0), 0.0)
		sparks(at, 34, Vector3(0, 0.3, 1), 75.0, Vector2(1.0, 3.2), 0.9, true, false, false, ext, area_k())
		flash(at, Color(0.8, 0.88, 1.0), 0.45)
		parts({"tex": "smoke_b", "blend": "lit", "soft": 0.3, "n": 5, "k": area_k(), "life": 2.4, "explo": 0.8, "at": at, "shape": "box", "ext": ext,
			"v": Vector2(0.2, 0.5), "spread": 30.0, "size": Vector2(0.2, 0.3), "curve": [[0.0, 0.4], [1.0, 3.0]], "spin": Vector2(-30, 30), "burst": true,
			"ramp": [[0.0, Color(0.35, 0.35, 0.36, 0.0)], [0.1, Color(0.35, 0.35, 0.36, 0.3)], [1.0, Color(0.35, 0.35, 0.36, 0.0)]]})
		tint = Color(0.7, 0.82, 1.0)
		var n_arcs := clampi(roundi(2.0 * sqrt(area_k())), 2, 6)
		for i in n_arcs:
			var off := Vector3(ext.x * (float(i) / maxf(1.0, n_arcs - 1) * 2.0 - 1.0), 0, 0) if n_arcs > 2 else Vector3.ZERO
			arc(at + off, Vector3(0.12, 0.3, 0), 0.12, 1, true)
		floor_collider()
		light(at + Vector3(0, 0, 0.15), Color(0.72, 0.82, 1.0), 3.2, 6.0, MapEffect.Light.FLASH)
		e.burst_every = Vector2(1.2, 4.5)
		e.burst_pops = 0.55

	# -------------------------------------------------------------- électricité

	func _glow(at: Vector3, sz: float, alpha: float) -> void:
		parts({"tex": "dot", "n": 2, "life": 0.3, "at": at, "v": Vector2.ZERO, "size": Vector2(sz * 0.8, sz), "tint": true, "spin": Vector2(-90, 90),
			"ramp": [[0.0, Color(1, 1, 1, 0.0)], [0.3, Color(1, 1, 1, alpha)], [1.0, Color(1, 1, 1, 0.0)]]})

	## Arc d'un bout à l'autre de la zone (largeur) ; plusieurs arcs de front
	## si la zone est profonde (les électrodes sont le décor « electrodes »).
	func arc_() -> void:
		var half := maxf(hx - 0.17, 0.1)
		var rows := clampi(roundi(hz * 2.0 / 0.4), 1, 4)
		for row in rows:
			var z := (float(row) / (rows - 1) - 0.5) * (hz * 2.0 - 0.2) if rows > 1 else 0.0
			for sx in [-1.0, 1.0]:
				var end := Vector3(sx * (half + 0.04), 0, z)
				_glow(end, 0.3, 0.55)
				parts({"tex": "streak", "mode": "streak", "quad": Vector2(0.02, 0.1), "n": 5, "life": 0.6, "rand": 0.5, "at": end,
					"shape": "sphere", "r": 0.04, "spread": 90.0, "v": Vector2(0.4, 1.4), "g": Vector3(0, -9.8, 0), "size": Vector2(0.6, 1.0), "tint": true,
					"ramp": [[0.0, Color(1, 1, 1, 1)], [1.0, Color(0.6, 0.7, 1.0, 0.0)]], "collide": "bounce", "aabb": zone_aabb(2.0)})
			for i in 3:
				arc(Vector3(-half, 0, z), Vector3(half, 0, z), 0.38 * clampf(half / 0.58, 0.8, 2.0))
		floor_collider()
		light(Vector3.ZERO, tint, 2.0, 6.0, MapEffect.Light.CRACKLE)

	## Décharges rayonnantes jusqu'au bord de la zone (la bobine est le décor
	## « bobine_tesla »).
	func tesla() -> void:
		var reach := minf(hx, hz)
		var kr := reach / 1.2
		_glow(Vector3.ZERO, 0.75, 0.45)
		for i in clampi(roundi(5.0 * sqrt(maxf(kr, 0.2))), 3, 10):
			arc(Vector3.ZERO, Vector3(0.45 * kr, 1.15 * kr, 0), 0.32 * clampf(kr, 0.6, 1.6), 1)
		parts({"tex": "dot", "n": 10, "k": clampf(kr, 0.5, 4.0), "life": 0.7, "rand": 0.5, "shape": "sphere", "r": 0.16, "spread": 180.0,
			"v": Vector2(0.5, 1.3) * clampf(kr, 0.6, 2.0), "g": Vector3(0, -3.0, 0), "size": Vector2(0.015, 0.03), "tint": true,
			"ramp": [[0.0, Color(1, 1, 1, 1)], [1.0, Color(1, 1, 1, 0)]]})
		light(Vector3.ZERO, tint, 2.4, 7.0, MapEffect.Light.CRACKLE)

	## Crépitements au bout du câble suspendu (décor « cable_suspendu »).
	func cable_nu() -> void:
		var tip := MapEffects.CABLE_TIP
		var ex := inset(0.22, 0.03)
		var ext := Vector3(ex.x, 0.02, ex.y)
		_glow(tip, 0.3, 0.6)
		for i in clampi(roundi(2.0 * sqrt(area_k())), 2, 6):
			arc(tip, Vector3(0.12, 0.3, 0), 0.12, 1)
		sparks(tip, 5, Vector3.DOWN, 40.0, Vector2(0.2, 0.8), 1.0, false, false, true, ext, area_k())
		sparks(tip, 18, Vector3.DOWN, 80.0, Vector2(0.5, 2.0), 1.1, true, false, true, ext, area_k())
		flash(tip, tint.lightened(0.4), 0.3)
		floor_collider()
		light(tip, tint, 1.6, 5.0, MapEffect.Light.CRACKLE)
		light(tip, tint, 2.4, 5.0, MapEffect.Light.FLASH, true)
		e.burst_every = Vector2(2.0, 6.0)
		e.burst_pops = 0.3

	# -------------------------------------------------------------- eau

	## Gouttes qui tombent de `at` (n'importe où dans `ext`) et ronds au sol
	## synchronisés sur leur chute.
	func drops(at: Vector3, n: int, life: float, dir: Vector3, v: Vector2, spread: float, quad_sz: Vector2, land: Vector3, ripples: int,
			ext := Vector3.ZERO, k := 1.0) -> void:
		var drop := float(at.y - land.y)
		var fall := sqrt(2.0 * maxf(0.05, drop) / 9.8)
		var shape := "box" if ext != Vector3.ZERO else "point"
		parts({"tex": "streak", "blend": "mix", "mode": "streak", "quad": quad_sz, "n": n, "k": k, "life": life, "at": at, "shape": shape, "ext": ext,
			"dir": dir, "spread": spread, "v": v, "g": Vector3(0, -9.8, 0), "size": Vector2(0.9, 1.1), "pre": 0.0,
			"ramp": [[0.0, Color(MapEffects.WATER, 0.75)], [1.0, Color(MapEffects.WATER, 0.6)]], "collide": "hide"})
		if ripples > 0:
			# Même rythme que les gouttes, décalé de leur temps de chute (préchauffage).
			parts({"tex": "ring", "blend": "mix", "mode": "flat", "n": ripples, "k": k, "life": life, "at": land + Vector3(0, 0.012, 0),
				"pre": fposmod(life - fall, life), "shape": "box", "ext": Vector3(ext.x + 0.02, 0.0, ext.z + 0.02), "v": Vector2.ZERO, "size": Vector2(0.06, 0.08),
				"curve": [[0.0, 0.2], [1.0, 6.0]], "ramp": [[0.0, Color(0.75, 0.85, 0.95, 0.0)], [0.06, Color(0.75, 0.85, 0.95, 0.55)], [1.0, Color(0.7, 0.8, 0.9, 0.0)]]})
			parts({"tex": "streak", "blend": "mix", "mode": "streak", "quad": Vector2(0.008, 0.035), "n": ripples * 3, "k": k, "life": life, "explo": 0.0,
				"at": land + Vector3(0, 0.02, 0), "pre": fposmod(life - fall, life), "shape": "box", "ext": Vector3(ext.x + 0.02, 0.0, ext.z + 0.02),
				"spread": 35.0, "v": Vector2(0.4, 0.9), "g": Vector3(0, -9.8, 0),
				"size": Vector2(0.8, 1.0), "ramp": [[0.0, Color(MapEffects.WATER, 0.6)], [0.25, Color(MapEffects.WATER, 0.0)], [1.0, Color(MapEffects.WATER, 0.0)]]})

	## Gouttes du plafond sur toute la zone (la flaque au sol est le décor
	## « petite_flaque » ou « flaque_eau »).
	func goutte() -> void:
		var ex := inset(0.25, 0.0)
		drops(Vector3(0, -0.03, 0), 2, 1.4, Vector3.DOWN, Vector2(0.0, 0.05), 0.0, Vector2(0.012, 0.07), Vector3(0, -ground, 0), 2,
			Vector3(ex.x, 0.0, ex.y), area_k())
		floor_collider()

	## Filet d'eau qui tombe du mur (le tuyau est le décor « tuyau_fuite ») :
	## un filet par point de la zone, éclaboussures et ronds là où il tombe.
	func fuite() -> void:
		var at := Vector3(0.05, -0.03, 0.15)
		var ext := Vector3(maxf(hx - 0.15, 0.0), maxf(zh * 0.5 - 0.1, 0.0), 0.0)
		var fall := sqrt(2.0 * maxf(0.1, ground) / 9.8)
		var land := Vector3(0.05, -ground, 0.15 + 1.05 * fall)
		var lx := Vector3(ext.x, 0.0, 0.0)
		parts({"tex": "streak", "blend": "mix", "mode": "streak", "quad": Vector2(0.035, 0.3), "n": 110, "k": area_k(), "life": fall + 0.3, "at": at,
			"shape": "box", "ext": ext, "dir": Vector3(0, -0.15, 1.0), "spread": 4.0, "v": Vector2(0.95, 1.15), "g": Vector3(0, -9.8, 0),
			"size": Vector2(0.8, 1.2), "ramp": [[0.0, Color(MapEffects.WATER, 0.55)], [1.0, Color(MapEffects.WATER, 0.45)]], "collide": "hide"})
		parts({"tex": "streak", "blend": "mix", "mode": "streak", "quad": Vector2(0.01, 0.04), "n": 16, "k": area_k(), "life": 0.45, "rand": 0.4,
			"at": land + Vector3(0, 0.03, 0), "shape": "box", "ext": lx + Vector3(0.06, 0.0, 0.06), "spread": 50.0, "v": Vector2(0.6, 1.4),
			"g": Vector3(0, -9.8, 0), "size": Vector2(0.8, 1.1), "ramp": [[0.0, Color(MapEffects.WATER, 0.7)], [1.0, Color(MapEffects.WATER, 0.0)]]})
		parts({"tex": "ring", "blend": "mix", "mode": "flat", "n": 4, "k": area_k(), "life": 0.9, "rand": 0.3, "at": land + Vector3(0, 0.012, 0),
			"shape": "box", "ext": lx + Vector3(0.1, 0.0, 0.1), "v": Vector2.ZERO, "size": Vector2(0.08, 0.12), "curve": [[0.0, 0.3], [1.0, 5.0]],
			"ramp": [[0.0, Color(0.75, 0.85, 0.95, 0.0)], [0.08, Color(0.75, 0.85, 0.95, 0.45)], [1.0, Color(0.7, 0.8, 0.9, 0.0)]]})
		parts({"tex": "smoke_b", "blend": "mix", "soft": 0.3, "n": 3, "k": area_k(), "life": 1.6, "at": land + Vector3(0, 0.08, 0), "shape": "box", "ext": lx,
			"v": Vector2(0.05, 0.15), "size": Vector2(0.35, 0.5), "curve": [[0.0, 0.6], [1.0, 1.6]], "spin": Vector2(-20, 20),
			"ramp": [[0.0, Color(0.8, 0.85, 0.9, 0.0)], [0.3, Color(0.8, 0.85, 0.9, 0.1)], [1.0, Color(0.8, 0.85, 0.9, 0.0)]]})
		floor_collider()

	## Ronds qui s'étalent sur l'eau, partout dans la zone (l'eau elle-même
	## est le décor « flaque_eau »).
	func flaque() -> void:
		var ex := Vector2(maxf(hx - 0.3, 0.05), maxf(hz - 0.2, 0.05))
		parts({"tex": "ring", "blend": "mix", "mode": "flat", "n": 4, "k": area_k(), "life": 1.9, "rand": 0.4, "at": Vector3(0, 0.012, 0), "shape": "box",
			"ext": Vector3(ex.x, 0.0, ex.y), "v": Vector2.ZERO, "size": Vector2(0.05, 0.08), "curve": [[0.0, 0.2], [1.0, 5.5]],
			"ramp": [[0.0, Color(0.75, 0.85, 0.95, 0.0)], [0.08, Color(0.75, 0.85, 0.95, 0.35)], [1.0, Color(0.7, 0.8, 0.9, 0.0)]]})

	# -------------------------------------------------------------- ambiance

	## Grains de poussière dans tout le volume de la zone.
	func poussiere() -> void:
		var c := Color(1.0, 0.92, 0.78)
		var ex := inset(0.1, 0.2)
		var th := maxf(zh, 0.5)
		parts({"tex": "dot", "n": 70, "k": vol_k(), "life": 12.0, "rand": 0.3, "at": Vector3(0, 0.25 + th * 0.5, 0), "shape": "box",
			"ext": Vector3(ex.x, th * 0.5, ex.y), "dir": Vector3(1, 0, 0), "spread": 180.0, "v": Vector2(0.01, 0.04), "g": Vector3(0, -0.004, 0),
			"size": Vector2(0.012, 0.028), "curve": [[0.0, 0.0], [0.15, 1.0], [0.85, 1.0], [1.0, 0.0]], "turb": 0.12, "turb_scale": 3.0,
			"ramp": [[0.0, Color(c, 0.0)], [0.2, Color(c, 0.3)], [0.8, Color(c, 0.3)], [1.0, Color(c, 0.0)]], "aabb": zone_aabb(th + 1.0, 1.0)})

	func braises() -> void:
		var ex := inset(0.1, 0.1)
		parts({"tex": "dot", "n": 34, "k": area_k(), "life": 4.5, "rand": 0.4, "at": Vector3(0, 0.1, 0), "shape": "box", "ext": Vector3(ex.x, 0.05, ex.y),
			"spread": 25.0, "v": Vector2(0.25, 0.6), "g": Vector3(0, 0.08, 0), "damp": Vector2(0.2, 0.4), "size": Vector2(0.018, 0.04),
			"curve": [[0.0, 0.4], [0.1, 1.0], [0.8, 0.8], [1.0, 0.0]], "turb": 0.9, "turb_scale": 0.8,
			"ramp": [[0.0, Color(1.0, 0.75, 0.35, 0.0)], [0.08, Color(1.0, 0.6, 0.2, 1.0)], [0.6, Color(1.0, 0.3, 0.05, 0.85)], [1.0, Color(0.5, 0.08, 0.02, 0.0)]],
			"aabb": zone_aabb(room_h, 1.0)})
		light(Vector3(0, 0.4, 0), Color(1.0, 0.45, 0.15), 0.5, 4.0, MapEffect.Light.FIRE, true)

	func cendres() -> void:
		var top := maxf(0.5, room_h - ground - 0.2)
		var ex := inset(0.1, 0.2)
		var aabb := zone_aabb(top + 0.5, 1.0)
		var c := Color(0.55, 0.53, 0.5)
		parts({"tex": "dot", "blend": "lit", "n": 50, "k": area_k(), "life": 14.0, "rand": 0.3, "at": Vector3(0, top, 0), "shape": "box",
			"ext": Vector3(ex.x, 0.05, ex.y), "dir": Vector3.DOWN, "spread": 20.0, "v": Vector2(0.05, 0.15), "g": Vector3(0, -0.05, 0), "damp": Vector2(0.4, 0.6),
			"size": Vector2(0.02, 0.045), "spin": Vector2(-90, 90), "turb": 0.5, "turb_scale": 1.5, "collide": "hide",
			"ramp": [[0.0, Color(c, 0.0)], [0.1, Color(c, 0.85)], [0.85, Color(c, 0.85)], [1.0, Color(c, 0.0)]], "aabb": aabb})
		parts({"tex": "dot", "n": 8, "k": area_k(), "life": 12.0, "rand": 0.3, "at": Vector3(0, top, 0), "shape": "box",
			"ext": Vector3(maxf(ex.x - 0.1, 0.1), 0.05, maxf(ex.y - 0.1, 0.1)), "dir": Vector3.DOWN, "spread": 20.0, "v": Vector2(0.05, 0.15),
			"g": Vector3(0, -0.05, 0), "damp": Vector2(0.4, 0.6), "size": Vector2(0.015, 0.03), "turb": 0.5, "collide": "hide", "ramp": MapEffects.EMBER_RAMP,
			"aabb": aabb})
		floor_collider()

	func feux_follets() -> void:
		var th := maxf(zh, 0.5)
		var at := Vector3(0, 0.3 + th * 0.5, 0)
		var ex := inset(0.15, 0.1)
		var ext := Vector3(ex.x, th * 0.5, ex.y)
		var aabb := zone_aabb(th + 1.5, 1.5)
		var k := vol_k()
		parts({"tex": "dot", "n": 5, "k": k, "life": 5.0, "rand": 0.3, "at": at, "shape": "box", "ext": ext, "spread": 180.0, "v": Vector2(0.05, 0.15),
			"size": Vector2(0.35, 0.55), "curve": [[0.0, 0.0], [0.2, 1.0], [0.8, 1.0], [1.0, 0.0]], "tint": true, "spin": Vector2(-60, 60),
			"turb": 1.4, "turb_scale": 0.7, "ramp": [[0.0, Color(1, 1, 1, 0.0)], [0.2, Color(1, 1, 1, 0.6)], [0.8, Color(1, 1, 1, 0.5)], [1.0, Color(1, 1, 1, 0.0)]],
			"aabb": aabb})
		parts({"tex": "dot", "n": 6, "k": k, "life": 5.0, "rand": 0.3, "at": at, "shape": "box", "ext": ext, "spread": 180.0, "v": Vector2(0.05, 0.15),
			"size": Vector2(0.05, 0.08), "curve": [[0.0, 0.0], [0.2, 1.0], [0.8, 1.0], [1.0, 0.0]], "turb": 1.4, "turb_scale": 0.7,
			"ramp": [[0.0, Color(0.85, 1.0, 0.88, 0.0)], [0.2, Color(0.85, 1.0, 0.88, 1.0)], [1.0, Color(0.85, 1.0, 0.88, 0.0)]], "aabb": aabb})
		parts({"tex": "twirl", "n": 8, "k": k, "life": 1.8, "rand": 0.4, "at": at, "shape": "box", "ext": ext, "v": Vector2(0.0, 0.1), "size": Vector2(0.15, 0.3),
			"tint": true, "spin": Vector2(-200, 200), "ramp": [[0.0, Color(1, 1, 1, 0.0)], [0.3, Color(1, 1, 1, 0.3)], [1.0, Color(1, 1, 1, 0.0)]], "aabb": aabb})
		parts({"tex": "dot", "n": 24, "k": k, "life": 3.0, "rand": 0.4, "at": at, "shape": "box", "ext": ext + Vector3(0.1, -0.1, 0.1), "v": Vector2(0.05, 0.12),
			"size": Vector2(0.01, 0.018), "tint": true, "turb": 0.6, "ramp": [[0.0, Color(1, 1, 1, 0.0)], [0.3, Color(1, 1, 1, 0.9)], [1.0, Color(1, 1, 1, 0.0)]],
			"aabb": aabb})
		light(at, tint, 0.9, 4.5, MapEffect.Light.PULSE)

	## Construit l'effet `id` (« arc » : arc_, le nom étant pris).
	func call_fx(id: String) -> void:
		if id == "arc":
			arc_()
		elif has_method(id):
			call(id)
