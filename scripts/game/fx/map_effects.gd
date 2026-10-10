class_name MapEffects
extends RefCounted
## Effets posés dans l'éditeur de cartes (type « effet », MapCatalog.EFFECTS) :
## chaque effet est construit EN CODE à partir de couches :
##   - particules GPU (GPUParticles3D + ParticleProcessMaterial) CUBIQUES
##     (VoxelFx, GAME_CONCEPT.md § 4.19) : chaque particule est un cube de
##     couleur unie (rampe de couleur, aucune texture, aucun panneau face
##     caméra) ou une touffe de cubes pour les grosses (flammes, volutes de
##     fumée, bouffées de vapeur : leurs cubes s'écartent en grossissant,
##     jamais plus de 15 cm) ; côté de chaque cube arrondi à 2,5 cm ; elles
##     disparaissent en RÉTRÉCISSANT (l'alpha de la rampe règle la taille,
##     l'opacité de la couche est son alpha le plus haut). Additives
##     (étincelles, braises, lueurs), fondues (flammes, vapeur) ou éclairées
##     (fumées, cendres) ; tailles et couleurs le long de la vie, turbulence,
##     rotation au hasard ; étincelles en files de cubes alignées sur leur
##     vitesse et qui REBONDISSENT sur le sol (GPUParticlesCollisionBox3D) ;
##     gouttes qui disparaissent au sol ; plats en pixel art de 2,5 ou 5 cm
##     (ronds dans l'eau synchronisés sur les gouttes, nappes de brume, métal
##     chauffé) ;
##   - lumières (OmniLight3D sans ombre) qui vacillent, crépitent ou éclatent
##     (MapEffect) ;
##   - arcs électriques : chaînes de cubes de 2,5 ou 5 cm en zigzag, re-tirées
##     au hasard toutes les quelques centièmes de seconde.
## Format 11 : des EFFETS PURS. Aucun objet solide (bûches, torche, tuyau,
## boîtier, électrodes, bobine, câble, flaque sont des décors à part :
## MapCatalog.PREFABS, EditorPrefabs) et aucune collision. Aucun fichier de
## texture.
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
##
## VOLUME (MapCatalog.effect_volume, la boîte dessinée dans l'éditeur) :
## TOUT ce que l'effet affiche y reste. Chaque couche est réglée pour, puis
## Builder.contain le garantit : l'étendue de chaque couche (part_reach :
## boîte d'émission + trajectoires simulées comme le shader de Godot, avec
## vitesse, gravité, amortissement, turbulence bornée par une vitesse
## limite, rebond sur le sol + rayon visible des particules) est ramenée
## dans le volume en resserrant d'abord l'émission, puis le mouvement (vitesse,
## gravité et amortissement ensemble : même trajectoire en plus petit, même
## rythme), enfin la taille. Arcs : bouts gardés dans le volume (MapEffect).
## Sol de collision (étincelles qui rebondissent, gouttes) : le bas du volume,
## seulement s'il descend jusqu'au sol. Lumières : leur source dans le volume
## (leur éclairage porte au-delà).

## Particules au plus par carte (au-delà, MeshMapBuilder les réduit toutes).
const PARTICLE_BUDGET := 9000
## Lumières d'effets au plus par carte (les suivantes restent éteintes).
const LIGHT_BUDGET := 16
## Portée maximale (m) d'une lumière d'effet.
const MAX_LIGHT_RANGE := 20.0

static var _quads: Dictionary = {}

## Flammes en cubes : couleurs franches (jaune, orange, rouge, braise) ;
## l'alpha règle la taille des cubes (VoxelFx).
const FIRE_RAMP := [[0.0, Color(1.0, 0.82, 0.3, 0.0)], [0.08, Color(1.0, 0.68, 0.18, 0.6)], [0.35, Color(0.98, 0.36, 0.05, 0.5)],
	[0.7, Color(0.6, 0.1, 0.02, 0.22)], [1.0, Color(0.2, 0.04, 0.02, 0.0)]]
const TONGUE_RAMP := [[0.0, Color(1.0, 0.92, 0.55, 0.0)], [0.1, Color(1.0, 0.8, 0.3, 0.95)], [0.5, Color(1.0, 0.42, 0.06, 0.6)],
	[1.0, Color(0.5, 0.08, 0.02, 0.0)]]
const EMBER_RAMP := [[0.0, Color(1.0, 0.85, 0.5, 1.0)], [0.4, Color(1.0, 0.45, 0.1, 1.0)], [1.0, Color(0.6, 0.1, 0.02, 0.0)]]
const SPARK_RAMP := [[0.0, Color(1.0, 0.97, 0.85, 1.0)], [0.25, Color(1.0, 0.75, 0.35, 1.0)], [0.7, Color(1.0, 0.4, 0.08, 0.9)],
	[1.0, Color(0.7, 0.15, 0.02, 0.0)]]
## Eau : bleu-gris (cubes non éclairés, pas de reflet doux).
const WATER := Color(0.5, 0.64, 0.8)
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
	var room_h := maxf(1.0, _f(opts, "room_h", 3.2))
	# Sans « ground » : posé comme dans une pièce de `room_h` (au sol, à sa
	# hauteur par défaut au mur, sous le plafond).
	var def_ground := 0.0
	match String(d.mount):
		"mur":
			def_ground = float(d.get("y", 1.5))
		"plafond":
			def_ground = room_h - 0.02
	var ground := maxf(0.0, _f(opts, "ground", def_ground))
	e.volume = MapCatalog.effect_volume(id, e.zone, ground, room_h)
	# Bas du volume sur le sol (ou sur ce qui porte l'effet : « appui ») : rien
	# de visible dessous.
	if absf(e.volume.position.y + ground) <= 0.02 or d.get("appui", false):
		e.floor_y = e.volume.position.y
	# Effet mural : le mur au fond du volume cache ce qui passe derrière lui.
	if String(d.mount) == "mur":
		e.wall_z = e.volume.position.z
	var b := Builder.new(e, tint, ground, room_h, MapCatalog.effect_default_zone(id), String(d.mount))
	b.call_fx(id)
	b.fit_cap(int(d.get("cap", 600)))
	# « _brut » (diagnostic) : sans contain.
	if not opts.get("_brut", false):
		b.contain()
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

## Dessin d'une couche (ancien nom de texture `look` gardé comme « genre » de
## particule) : [maillage, motif des plats (0 : cubes), côté maximal d'un
## cube (m)]. Touffes : flammes (« fire_billow », « fire_core » : boule ;
## « flame_tongue » : langue), fumées et vapeur (« smoke_a », « smoke_b » :
## nuage de cubes), éclair et tourbillon (boule) ; « dot » : un cube, ou une
## boule si la particule dépasse 15 cm ; « streak » : file de cubes le long
## de la vitesse (étincelle, goutte, filet). À plat (`mode` « flat ») : rond
## (« ring »), disque (« dot ») ou nappe de brume en pixels.
static func look(texture: String, mode: String, quad_sz: Vector2, size_max: float) -> Array:
	if mode == "flat":
		match texture:
			"ring":
				return [quad(quad_sz), 1, VoxelFx.BIG]
			"dot":
				return [quad(quad_sz), 2, VoxelFx.BIG]
			_:
				return [quad(quad_sz), 3, VoxelFx.BIG]
	if mode == "streak":
		var n := clampi(roundi(quad_sz.y / maxf(quad_sz.x, 0.001) * 0.6), 1, 5)
		return [VoxelFx.chain(n, quad_sz.x, quad_sz.y), 0, VoxelFx.SMALL]
	var big := size_max * maxf(quad_sz.x, quad_sz.y) > VoxelFx.BIG
	match texture:
		"flame_tongue":
			return [VoxelFx.cluster("tongue"), 0, VoxelFx.BIG]
		"smoke_a", "smoke_b":
			return [VoxelFx.cluster("cloud") if big else VoxelFx.cube(), 0, VoxelFx.BIG]
		"dot":
			return [VoxelFx.cluster("puff") if big else VoxelFx.cube(), 0, VoxelFx.BIG if big else VoxelFx.SMALL]
	return [VoxelFx.cluster("puff") if big else VoxelFx.cube(), 0, VoxelFx.BIG]


## Matériau des particules (VoxelFx). `blend` : « add » (lumineux), « mix »
## (fondu, non éclairé), « fire » (flamme : fondue, non éclairée, plus vive)
## ou « lit » (fondu, éclairé par les lampes et les feux) ; `opacity` : alpha
## le plus haut de la rampe ; `pattern` : plats (VoxelFx). Les cubes
## disparaissent en rétrécissant (l'alpha de la rampe règle leur taille) ;
## les plats, en fondu.
static func draw_mat(blend: String, opacity: float, pattern := 0, mx := VoxelFx.BIG) -> ShaderMaterial:
	var o := {"max": mx, "opacity": snappedf(clampf(opacity, 0.02, 1.0), 0.01), "shrink": pattern == 0}
	var b := blend
	match blend:
		"add":
			o["energy"] = 1.0
		"fire":
			b = "mix"
			o["energy"] = 0.85
			o["edge"] = 0.15
		"mix", "lit":
			o["edge"] = 0.2 if pattern == 0 else 0.0
	if pattern > 0:
		o["pattern"] = pattern
		o["px"] = VoxelFx.GRID if pattern < 3 else VoxelFx.GRID * 2.0
	return VoxelFx.material(b, o)


## Panneau à plat (FACE_Y) des plats en pixel art.
static func quad(sz: Vector2) -> QuadMesh:
	var key := "%s" % sz
	if not _quads.has(key):
		var q := QuadMesh.new()
		q.size = sz
		q.orientation = PlaneMesh.FACE_Y
		_quads[key] = q
	return _quads[key]


## Alpha le plus haut d'une rampe ([[t, Color]...]).
static func ramp_alpha_max(stops: Array) -> float:
	var hi := 0.0
	for s in stops:
		hi = maxf(hi, (s[1] as Color).a)
	return hi


## Rampe de couleur (× `tint`) ; `norm` > 0 : alpha divisé par `norm` (la
## rampe d'une couche cubique va jusqu'à 1 : l'alpha y est la taille).
static func ramp(stops: Array, tint := Color.WHITE, norm := 1.0) -> GradientTexture1D:
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for s in stops:
		offs.append(float(s[0]))
		var c: Color = s[1]
		cols.append(Color(c.r * tint.r, c.g * tint.g, c.b * tint.b, clampf(c.a / maxf(norm, 0.001), 0.0, 1.0)))
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


## Plus grande valeur d'une courbe (CurveTexture ; 1 sans courbe).
static func curve_max(t: Texture2D) -> float:
	var ct := t as CurveTexture
	if ct == null or ct.curve == null or ct.curve.point_count == 0:
		return 1.0
	var hi := -INF
	for i in ct.curve.point_count:
		hi = maxf(hi, ct.curve.get_point_position(i).y)
	return hi


# ------------------------------------------------------------------ étendue des particules

## Trajectoires simulées (clé des réglages -> boîte des déplacements).
static var _motion_cache: Dictionary = {}
## Trajectoires gardées au plus (au-delà, le cache repart de zéro).
const MOTION_CACHE_MAX := 4000

## Direction initiale d'une particule, comme le shader de Godot
## (get_random_direction_from_spread) : `u1`, `u2` dans [-1, 1].
static func spread_dir(dir: Vector3, spread: float, flatness: float, u1: float, u2: float) -> Vector3:
	var s := deg_to_rad(spread)
	var a1 := u1 * s
	var a2 := u2 * s * (1.0 - flatness)
	var dxz := Vector3(sin(a1), 0.0, cos(a1))
	var dyz := Vector3(0.0, sin(a2), cos(a2))
	dyz.z = dyz.z / maxf(0.0001, sqrt(absf(dyz.z)))
	var sd := Vector3(dxz.x * dyz.z, dyz.y, dxz.z * dyz.z)
	var dn := dir.normalized() if dir.length() > 0.0 else Vector3(0, 0, 1)
	var bin := Vector3.UP.cross(dn)
	if bin.length() < 0.0001:
		bin = Vector3(0, 0, 1)
	bin = bin.normalized()
	var nrm := bin.cross(dn)
	return (bin * sd.x + nrm * sd.y + dn * sd.z).normalized()


## Demi-étendue de la boîte d'émission (repère de la couche).
static func emission_ext(pm: ParticleProcessMaterial) -> Vector3:
	match pm.emission_shape:
		ParticleProcessMaterial.EMISSION_SHAPE_BOX:
			return pm.emission_box_extents.abs()
		ParticleProcessMaterial.EMISSION_SHAPE_SPHERE, ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE:
			return Vector3.ONE * pm.emission_sphere_radius
	return Vector3.ZERO


## Rayon visible d'une particule, par axe (repère de la couche), taille
## maximale (échelle × haut de la courbe) : à plat, demi-côté du panneau et
## rien en hauteur ; sinon (VoxelFx.half_extent) centres des cubes × taille
## + demi-côté des cubes (arrondi à 2,5 cm, au moins 2,5 cm, au plus le côté
## maximal de la couche, méta « vox_max »). Rotation autour de z (angle,
## vitesse angulaire) : x et y tournent (rayon du disque des centres, demi-
## diagonale des cubes). File de cubes alignée sur la vitesse : demi-longueur
## × la plus grande part de la vitesse sur l'axe (`dirs`, motion_dirs) +
## demi-diagonale d'un cube (la file tourne aussi autour de son axe).
static func part_radius(p: GPUParticles3D, dirs := Vector3.ONE) -> Vector3:
	var pm := p.process_material as ParticleProcessMaterial
	var s := pm.scale_max * curve_max(pm.scale_curve)
	var q := p.draw_pass_1 as QuadMesh
	if q != null:
		return Vector3(q.size.x, 0.0, q.size.y) * 0.5 * s
	var mx: Vector3 = p.get_meta("vox_max", Vector3.ONE * VoxelFx.BIG)
	var he := VoxelFx.half_extent(p.draw_pass_1, s, mx)
	var c: Vector3 = he[0]
	var side: Vector3 = he[1]
	if p.transform_align == GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY:
		return dirs * c.y + Vector3.ONE * side.x * 0.87
	if pm.angle_min != 0.0 or pm.angle_max != 0.0 or pm.angular_velocity_min != 0.0 or pm.angular_velocity_max != 0.0:
		var rxy := float(p.draw_pass_1.get_meta("vox_rxy", Vector2(c.x, c.y).length() / maxf(s, 0.000001))) * s
		return Vector3(rxy, rxy, c.z) + side * Vector3(0.71, 0.71, 0.5)
	return c + side * 0.5


## Plus petit rayon d'une particule (part_radius quand sa taille tend vers 0) :
## un cube de 2,5 cm (le shader ne descend pas plus bas) ; plats : rien.
static func part_radius_min(p: GPUParticles3D) -> Vector3:
	if p.draw_pass_1 is QuadMesh:
		return Vector3.ZERO
	var pm := p.process_material as ParticleProcessMaterial
	var g := VoxelFx.GRID
	if p.transform_align == GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY:
		return Vector3.ONE * g * 0.87
	if pm.angle_min != 0.0 or pm.angle_max != 0.0 or pm.angular_velocity_min != 0.0 or pm.angular_velocity_max != 0.0:
		return Vector3(0.71, 0.71, 0.5) * g
	return Vector3.ONE * g * 0.5


## Vitesse limite (m/s) d'une couche (velocity_limit_curve), INF sans.
static func speed_limit(pm: ParticleProcessMaterial) -> float:
	return curve_max(pm.velocity_limit_curve) if pm.velocity_limit_curve != null else INF


## Boîte des DÉPLACEMENTS d'une particule depuis son point d'émission
## pendant `life` s, toutes directions de départ (grille du cône), vitesses et
## amortissements extrêmes, simulés comme le shader de Godot : gravité, puis
## amortissement (la vitesse perd `damping` m/s par seconde, jamais négative),
## vitesse limite, position. Turbulence : la direction peut devenir
## n'importe laquelle (et la vitesse gagner un peu à chaque image) : une
## boule du chemin parcouru. `fy` : sol de collision sous le point
## d'émission (NAN : aucun) ; rebond (vitesse verticale × bounce, glissement
## freiné) ou disparition au contact. `fine` (tests) : directions plus
## serrées, pas de 1/60 s (au plus 120 pas sur la vie).
static func motion(pm: ParticleProcessMaterial, life: float, fy := NAN, fine := false) -> AABB:
	return _motion(pm, life, fy, fine)[0]


## Part la plus grande de la vitesse sur chaque axe (direction des
## étincelles étirées le long de leur vitesse ; arrêtée : vers le haut).
static func motion_dirs(pm: ParticleProcessMaterial, life: float, fy := NAN, fine := false) -> Vector3:
	return _motion(pm, life, fy, fine)[1]


static func _motion(pm: ParticleProcessMaterial, life: float, fy: float, fine: bool) -> Array:
	var collide := pm.collision_mode != ParticleProcessMaterial.COLLISION_DISABLED and is_finite(fy)
	# Tout se met à l'échelle : vitesses, gravité, amortissement, vitesse
	# limite et sol divisés par `q` donnent la même trajectoire divisée par
	# `q` (même rythme). Calcul en unités réduites : une couche ralentie par
	# contain, ou la même couche dans une autre zone, retrouve le cache.
	var q := maxf(pm.initial_velocity_max, maxf(pm.gravity.length(), maxf(pm.damping_max, 0.0001)))
	var vlim := speed_limit(pm) / q
	var turb := pm.turbulence_enabled
	# Sol de collision en unités réduites, arrondi plus bas sur une grille de
	# 8 % (plus de chute : un peu plus de chemin, jamais moins) : le cache sert
	# encore quand la couche est ralentie ou la zone retaillée.
	var fn := fy / q if collide else 0.0
	if collide and fn < -0.0001:
		fn = -pow(1.08, ceilf(log(-fn) / log(1.08)))
	var key := "%s|%.3f|%.3f|%.4f|%.4f|%s|%.4f|%.4f|%.4f|%.4f|%.4f|%d|%.3f|%.3f|%.3f|%s|%s" % [pm.direction.normalized(), pm.spread, pm.flatness,
		pm.initial_velocity_min / q, pm.initial_velocity_max / q, (pm.gravity / q).snapped(Vector3.ONE * 0.0001), pm.damping_min / q,
		pm.damping_max / q, life, fn, vlim if is_finite(vlim) else -1.0, pm.collision_mode if collide else 0,
		pm.collision_bounce, pm.collision_friction, pm.turbulence_influence_max if turb else -1.0, turb, fine]
	var res: Array
	if _motion_cache.has(key):
		res = _motion_cache[key]
	else:
		res = _motion_unit(pm, life, fn if collide else NAN, vlim, q, fine)
		if _motion_cache.size() >= MOTION_CACHE_MAX:
			_motion_cache.clear()
		_motion_cache[key] = res
	var box: AABB = res[0]
	return [AABB(box.position * q, box.size * q), res[1]]


## Trajectoires en unités réduites (vitesses, gravité, amortissement ÷ `q`).
static func _motion_unit(pm: ParticleProcessMaterial, life: float, fy: float, vlim: float, q: float, fine: bool) -> Array:
	var collide := is_finite(fy)
	var g := pm.gravity / q
	var dt := maxf(1.0 / 60.0, life / (120.0 if fine else 30.0))
	var steps := maxi(1, ceili(life / dt))
	var out := AABB()
	var dirs := Vector3.ZERO
	if pm.turbulence_enabled:
		# Chemin le plus long : gravité dans le sens de la vitesse, amortissement
		# le plus faible, gain de la turbulence à chaque image.
		var i := clampf(pm.turbulence_influence_max, 0.0, 1.0)
		var gain := pow(1.0 + 0.2 * i * (1.0 - i), dt * 60.0)
		var sp := pm.initial_velocity_max / q
		var reach := 0.0
		for n in steps:
			sp = maxf(0.0, sp + g.length() * dt - pm.damping_min / q * dt) * gain
			reach += minf(sp, vlim) * dt
		out = AABB(-Vector3.ONE * reach, Vector3.ONE * reach * 2.0)
		dirs = Vector3.ONE
		if collide:
			var lo := maxf(out.position.y, fy)
			out = AABB(Vector3(out.position.x, lo, out.position.z), Vector3(out.size.x, out.end.y - lo, out.size.z))
		return [out, dirs]
	var grid := 7 if fine else 5
	var speeds := [pm.initial_velocity_min / q, pm.initial_velocity_max / q]
	var damps := [pm.damping_min / q, pm.damping_max / q]
	var hide := pm.collision_mode == ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	var fric := clampf(pm.collision_friction, 0.0, 1.0)
	for a in grid:
		for b in grid:
			var d := spread_dir(pm.direction, pm.spread, pm.flatness, -1.0 + 2.0 * a / (grid - 1), -1.0 + 2.0 * b / (grid - 1))
			for s in speeds:
				for dm in damps:
					var x := Vector3.ZERO
					var v: Vector3 = d * float(s)
					for n in steps:
						v += g * dt
						if dm > 0.0:
							var l := v.length() - float(dm) * dt
							v = v.normalized() * l if l > 0.0 else Vector3.ZERO
						var fv := v
						if fv.length() > vlim:
							fv = fv.normalized() * vlim
						var px := x
						x += fv * dt
						if collide and x.y < fy:
							# Point de contact (entre deux pas) : la particule y va.
							out = out.expand(px.lerp(x, clampf((px.y - fy) / maxf(px.y - x.y, 0.000001), 0.0, 1.0)))
							if hide:
								break
							x.y = fy
							if v.y < 0.0:
								v = Vector3(v.x * (1.0 - fric), -v.y * pm.collision_bounce, v.z * (1.0 - fric))
						out = out.expand(x)
						dirs = dirs.max(v.normalized().abs() if v.length() > 0.01 else Vector3.UP)
	return [out, dirs]


## Sol de collision d'une couche (y dans son repère), NAN s'il ne la touche pas.
static func part_floor(p: GPUParticles3D, floor_y: float) -> float:
	var pm := p.process_material as ParticleProcessMaterial
	if not is_finite(floor_y) or pm.collision_mode == ParticleProcessMaterial.COLLISION_DISABLED:
		return NAN
	if not p.basis.is_equal_approx(Basis.IDENTITY):
		return NAN
	return floor_y - p.position.y


## ÉTENDUE VISIBLE d'une couche de particules (repère du corps de l'effet) :
## boîte d'émission + déplacements (motion) + rayon des particules. `floor_y`
## (repère du corps) : le sol au bas du volume ; rien n'est visible dessous
## (le sol le cache), et les couches qui entrent en collision s'y arrêtent.
## `wall_z` : le mur au fond du volume d'un effet mural (z), qui cache de même
## ce qui passe derrière lui.
static func part_reach(p: GPUParticles3D, floor_y := NAN, fine := false, wall_z := NAN) -> AABB:
	var pm := p.process_material as ParticleProcessMaterial
	var e := emission_ext(pm)
	var fy := part_floor(p, floor_y)
	var d := motion(pm, p.lifetime, fy - e.y if is_finite(fy) else NAN, fine)
	var r := part_radius(p, motion_dirs(pm, p.lifetime, fy - e.y if is_finite(fy) else NAN, fine))
	var lo := -e + d.position - r
	var hi := e + d.end + r
	var out := p.transform * AABB(lo, hi - lo)
	if is_finite(floor_y) and out.position.y < floor_y:
		var top := maxf(out.end.y, floor_y)
		out = AABB(Vector3(out.position.x, floor_y, out.position.z), Vector3(out.size.x, top - floor_y, out.size.z))
	if is_finite(wall_z) and out.position.z < wall_z:
		var front := maxf(out.end.z, wall_z)
		out = AABB(Vector3(out.position.x, out.position.y, wall_z), Vector3(out.size.x, out.size.y, front - wall_z))
	return out


# ------------------------------------------------------------------ construction

## Construit les couches d'un effet (une fonction par effet du catalogue),
## puis les contient dans le volume de l'effet (contain).
class Builder:
	## Plus petite part de son mouvement qu'une couche garde (contain) avant
	## que ses particules rapetissent.
	const KMIN := 0.3
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
	## Volume de l'effet (MapEffect.volume, repère de l'effet).
	var vol: AABB
	## Portée des lumières selon la zone (rapport à la zone par défaut, borné).
	var light_k := 1.0

	func _init(fx: MapEffect, t: Color, g: float, h: float, def: Vector3, m: String) -> void:
		e = fx
		tint = t
		ground = g
		room_h = h
		z0 = def
		mount = m
		vol = fx.volume
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

	## Haut du volume (y, repère de l'effet).
	func top() -> float:
		return vol.end.y

	## Taille [min, max] d'une particule ramenée pour que son plus grand
	## diamètre (× `grow`, le haut de sa courbe de taille) ne dépasse pas `diam` m.
	func fit_size(sz: Vector2, grow: float, diam: float) -> Vector2:
		return sz * minf(1.0, diam / maxf(0.001, sz.y * grow))

	## Couche de particules. Clés de `c` : tex, blend, soft, mode (face, streak,
	## flat), quad (taille du panneau), n, k (multiplicateur de surface : la
	## couche remplit la zone, plafonnée par fit_cap), cover (nappe : grossit
	## un peu si le plafond est atteint), life, pre (préchauffage, s), explo,
	## rand, at, shape (point, sphere, box), r, ext, dir, spread, flatness, v
	## [min, max], g (gravité), damp, size [min, max], curve, ramp, tint
	## (bool : couleur de l'effet), spin [min, max] (°/s), angle (rotation au
	## hasard), turb (force ; la vitesse est alors bornée à « vlim », par
	## défaut v max : turbulence bornée), turb_scale, collide (« bounce »,
	## « hide » : sur le sol de collision, floor_collider), burst, cycle.
	## Boîte de visibilité : le volume de l'effet (contain).
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
		# Cubes (VoxelFx) : maillage et côté maximal selon le genre de particule.
		var sz: Vector2 = c.get("size", Vector2(0.3, 0.5))
		var grow := 1.0
		if c.has("curve"):
			for cp in c.curve:
				grow = maxf(grow, float(cp[1]))
		var lk := MapEffects.look(String(c.get("tex", "dot")), mode, c.get("quad", Vector2.ONE), sz.y * grow)
		p.draw_pass_1 = lk[0]
		p.set_meta("vox_max", Vector3.ONE * float(lk[2]))
		var stops: Array = c.get("ramp", [[0.0, Color.WHITE], [1.0, Color(1, 1, 1, 0)]])
		var amax := MapEffects.ramp_alpha_max(stops)
		var fire := String(c.get("tex", "")) in ["fire_billow", "flame_tongue"]
		var opacity := amax
		if blend == "add" and not fire and (lk[0] as Mesh).get_meta("vox_rxy", 0.0) > 0.0 and int(lk[1]) == 0 and mode != "streak":
			# Touffe additive (lueur, éclair, cœur du feu) : ses cubes se
			# superposent et s'additionnent ; l'ancien point doux n'était
			# opaque qu'en son centre (environ un tiers en moyenne).
			opacity *= 0.35
		p.material_override = MapEffects.draw_mat("fire" if fire and blend == "add" else blend, opacity, int(lk[1]), float(lk[2]))
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
		pm.scale_min = sz.x
		pm.scale_max = sz.y
		if c.has("curve"):
			pm.scale_curve = MapEffects.curve(c.curve)
		# Alpha de la rampe ramené à 1, l'opacité (alpha le plus haut) est dans
		# le matériau : sur les cubes il règle la taille, sur les plats le fondu.
		pm.color_ramp = MapEffects.ramp(stops, tint if c.get("tint", false) else Color.WHITE, amax)
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
			# Turbulence : la direction devient n'importe laquelle ; vitesse bornée
			# pour que le chemin parcouru le soit (MapEffects.motion).
			var vl := float(c.get("vlim", v.y))
			pm.velocity_limit_curve = MapEffects.curve([[0.0, vl], [1.0, vl]])
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
		e.add_part(p, burst, bool(c.get("cycle", false)))
		return p

	## Plafond de particules de l'effet : au-delà, les couches qui remplissent
	## la zone (« k ») sont réduites d'autant ; les nappes (« cover »)
	## grossissent un peu (au plus ×2) pour rester couvrantes (contain les
	## garde ensuite dans le volume).
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

	# ---------------------------------------------------------- volume

	## Tout ce que l'effet affiche dans son volume : chaque couche (étendue :
	## MapEffects.part_reach) y est ramenée en resserrant son émission, puis
	## son mouvement (vitesse, gravité, amortissement et vitesse limite × k :
	## même trajectoire en plus petit, même rythme), puis la taille de ses
	## particules ; sans sol de collision dans le volume, aucune collision ;
	## lumières : leur source dans le volume. Méta « fit » de chaque couche :
	## Vector3(part du mouvement, part de la taille, part de l'émission gardées).
	func contain() -> void:
		var inner := AABB(vol.position + Vector3.ONE * 0.01, (vol.size - Vector3.ONE * 0.02).max(Vector3.ZERO))
		for p in e.parts:
			if not e.collider:
				(p.process_material as ParticleProcessMaterial).collision_mode = ParticleProcessMaterial.COLLISION_DISABLED
			_contain_part(p, inner)
		for l in e.lights:
			l.position = l.position.clamp(inner.position, inner.end)

	func _contain_part(p: GPUParticles3D, inner: AABB) -> void:
		# Un cube ne rapetisse pas sous 2,5 cm : le point d'émission reste
		# assez loin des bords pour le plus petit cube (au milieu si la place manque).
		var rmin := MapEffects.part_radius_min(p)
		var lo := inner.position + rmin
		var hi := inner.end - rmin
		for i in 3:
			if lo[i] > hi[i]:
				lo[i] = inner.get_center()[i]
				hi[i] = lo[i]
		p.position = p.position.clamp(lo, hi)
		var inv := p.transform.affine_inverse()
		p.visibility_aabb = (inv * vol).grow(0.05)
		# Rebonds, frottement, vitesse limite : le mouvement n'est pas tout à
		# fait proportionnel à k ; on vérifie et on resserre encore s'il le faut.
		var fit := Vector3.ONE
		for n in 4:
			var f := _contain_step(p, inv * inner)
			fit *= f
			if vol.grow(0.002).encloses(e.part_reach(p)):
				break
		p.set_meta("fit", fit)

	## Une passe de contain sur la couche `p` (`lv` : volume intérieur dans son
	## repère) : rend Vector3(part du mouvement, de la taille, de l'émission).
	func _contain_step(p: GPUParticles3D, lv: AABB) -> Vector3:
		var pm := p.process_material as ParticleProcessMaterial
		var e0 := MapEffects.emission_ext(pm)
		var fy := MapEffects.part_floor(p, e.floor_y)
		var d := MapEffects.motion(pm, p.lifetime, fy - e0.y if is_finite(fy) else NAN)
		var dirs := MapEffects.motion_dirs(pm, p.lifetime, fy - e0.y if is_finite(fy) else NAN)
		var r := MapEffects.part_radius(p, (dirs * 1.05 + Vector3.ONE * 0.02).min(Vector3.ONE))
		# Marge sur la simulation (pas plus grossier que celui des tests).
		d = AABB(d.position * 1.06 - Vector3.ONE * 0.01, d.size * 1.06 + Vector3.ONE * 0.02)
		# Sol au bas du volume, mur au fond : rien de visible au-delà
		# (MapEffects.part_reach) ; NAN : rien de caché sur cet axe.
		var flat := p.basis.is_equal_approx(Basis.IDENTITY)
		var hid := Vector3(NAN, e.floor_y - p.position.y if flat and is_finite(e.floor_y) else NAN, e.wall_z - p.position.z if flat and is_finite(e.wall_z) else NAN)
		var k := 1.0
		var rs := 1.0
		# 1. Émission resserrée, mouvement entier.
		var room := _room(lv, d, r, 1.0, hid)
		if minf(room.x, minf(room.y, room.z)) < 0.0:
			# 2. Mouvement réduit, émission en un point s'il le faut.
			k = _fit_k(lv, d, r, hid)
			if k < KMIN:
				# 3. Particules plus petites, un peu de mouvement gardé.
				k = KMIN
				var free := _room(lv, d, Vector3.ZERO, k, hid)
				if minf(free.x, minf(free.y, free.z)) < 0.0:
					k = 0.0
					free = _room(lv, d, Vector3.ZERO, 0.0, hid)
				for i in 3:
					if r[i] > 0.0:
						rs = minf(rs, maxf(free[i], 0.0) / r[i])
				rs = maxf(rs, 0.01)
			room = _room(lv, d, r * rs, k, hid)
		var e1 := e0.clamp(Vector3.ZERO, room.max(Vector3.ZERO))
		if k < 1.0:
			pm.initial_velocity_min *= k
			pm.initial_velocity_max *= k
			pm.gravity *= k
			pm.damping_min *= k
			pm.damping_max *= k
			if pm.velocity_limit_curve != null:
				var vl := MapEffects.speed_limit(pm) * k
				pm.velocity_limit_curve = MapEffects.curve([[0.0, vl], [1.0, vl]])
		if not e1.is_equal_approx(e0):
			if pm.emission_shape == ParticleProcessMaterial.EMISSION_SHAPE_BOX:
				pm.emission_box_extents = e1
			elif pm.emission_shape == ParticleProcessMaterial.EMISSION_SHAPE_SPHERE:
				pm.emission_sphere_radius = minf(e1.x, minf(e1.y, e1.z))
		if rs < 1.0:
			pm.scale_min *= rs
			pm.scale_max *= rs
		var ek := 1.0
		for i in 3:
			if e0[i] > 0.0:
				ek = minf(ek, e1[i] / e0[i])
		return Vector3(k, rs, ek)

	## Demi-étendue d'émission permise sur chaque axe (repère de la couche :
	## origine au point d'émission) avec le mouvement × `k` et le rayon `r` ;
	## négative : impossible. `hid` : sol (y) et mur (z) qui cachent ce qui
	## passe au-delà (repère de la couche, NAN : aucun) ; l'émission reste devant.
	func _room(lv: AABB, d: AABB, r: Vector3, k: float, hid: Vector3) -> Vector3:
		var out := Vector3.ZERO
		for i in 3:
			var hi := lv.end[i] - k * maxf(d.end[i], 0.0) - r[i]
			var lo := -lv.position[i] + k * minf(d.position[i], 0.0) - r[i]
			if is_finite(hid[i]):
				lo = -hid[i]
			out[i] = minf(hi, lo)
		return out

	## Plus grande part du mouvement qui tient dans le volume, émission en un
	## point (négative : même immobile, la particule déborde).
	func _fit_k(lv: AABB, d: AABB, r: Vector3, hid: Vector3) -> float:
		var k := 1.0
		for i in 3:
			var up := maxf(d.end[i], 0.0)
			var hi := lv.end[i] - r[i]
			if hi < 0.0:
				return -1.0
			if up > 0.0:
				k = minf(k, hi / up)
			if is_finite(hid[i]):
				continue
			var dn := -minf(d.position[i], 0.0)
			var lo := -lv.position[i] - r[i]
			if lo < 0.0:
				return -1.0
			if dn > 0.0:
				k = minf(k, lo / dn)
		return k

	# ---------------------------------------------------------- lumières, arcs, sol

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
	## (b.x, b.y : longueur min, max). Chaîne de cubes lumineux en zigzag
	## (MultiMesh, MapEffect._aim_arc ; pas un objet solide) ; largeur (écart du
	## zigzag) bornée pour tenir dans le volume (de travers à l'arc).
	func arc(a: Vector3, b: Vector3, width: float, mode := 0, burst_only := false) -> void:
		var lim := INF
		var ax := (b - a).normalized() if mode == 0 and (b - a).length() > 0.001 else Vector3.ZERO
		for i in 3:
			if mode == 1 or absf(ax[i]) < 0.999:
				lim = minf(lim, vol.size[i])
		width = minf(width, maxf(0.02, lim / MapEffect.ARC_W_MAX - 0.01))
		if e.arc_mats.is_empty():
			var col := Color(tint.r, tint.g, tint.b, 1.0).lightened(0.25)
			e.arc_mats.append(VoxelFx.material("add", {"max": VoxelFx.SMALL, "shrink": false, "energy": 2.2, "tint": col}))
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = VoxelFx.chain_multimesh(MapEffect.ARC_CUBES)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.material_override = e.arc_mats[0]
		e.add_arc(mi, mode, a, b, width, burst_only)

	## Sol de collision des particules seulement (étincelles qui rebondissent,
	## gouttes qui s'arrêtent) : le bas du volume, sous toute la zone, s'il
	## descend jusqu'au sol (sinon rien : les particules meurent avant).
	func floor_collider() -> void:
		if not is_finite(e.floor_y):
			return
		e.collider = true
		var cb := GPUParticlesCollisionBox3D.new()
		var c := vol.get_center()
		cb.size = Vector3(vol.size.x + 0.4, 0.4, vol.size.z + 0.4)
		cb.position = Vector3(c.x, e.floor_y - 0.2, c.z)
		e.body.add_child(cb)

	# -------------------------------------------------------------- flammes

	## Feu en couches : flammes (volutes et langues), cœur lumineux, braises,
	## fumée, lumière vacillante. `ext` : demi-étendue du foyer (x, z), `w` :
	## largeur d'une flamme (taille des panneaux, fixe), `h` : hauteur des
	## flammes (m, au plus 70 % de la place sous le haut du volume), `dens` :
	## densité, `k` : multiplicateur de surface, `dark` : fumée noire (0 à 1).
	## `n_lights` : 0 = selon la zone (1 à 3, le long du plus grand côté).
	## Panneaux et fumée à la largeur de la zone.
	func fire(at: Vector3, ext: Vector2, w: float, h: float, dens: float, k: float, dark: float, energy: float, rng: float, n_lights := 1) -> void:
		var room := maxf(0.15, top() - at.y)
		h = minf(h, room * 0.7)
		var wide := minf(vol.size.x, vol.size.z if mount != "mur" else vol.size.y)
		var life := 0.55 + h * 0.35
		var bx := Vector3(ext.x, 0.03, ext.y)
		parts({"tex": "fire_billow", "n": 12 * dens, "k": k, "angle_deg": 25.0, "life": life, "rand": 0.3, "at": at, "shape": "box", "ext": bx, "spread": 4.0,
			"v": Vector2(0.25, 0.55) * h / life, "g": Vector3(0, h * 1.1 / (life * life), 0), "damp": Vector2(0.4, 1.0),
			"size": fit_size(Vector2(w * 1.6 + 0.12, w * 2.6 + 0.2), 1.0, wide * 0.7), "curve": [[0.0, 0.35], [0.2, 1.0], [0.6, 0.75], [1.0, 0.1]],
			"ramp": MapEffects.FIRE_RAMP, "spin": Vector2(-20, 20)})
		parts({"tex": "flame_tongue", "n": 9 * dens, "k": k, "life": life * 0.7, "rand": 0.35, "at": at, "shape": "box", "ext": bx * 0.8, "spread": 3.0,
			"v": Vector2(0.3, 0.6) * h / life, "g": Vector3(0, h / (life * life), 0), "damp": Vector2(0.5, 1.2), "angle": false,
			"size": fit_size(Vector2(w * 1.3 + 0.12, w * 2.0 + 0.2), 1.0, wide * 0.7), "curve": [[0.0, 0.5], [0.25, 1.0], [1.0, 0.25]],
			"ramp": MapEffects.TONGUE_RAMP})
		parts({"tex": "fire_core", "n": 3 * dens, "k": k, "life": 0.6, "at": at + Vector3(0, h * 0.15, 0), "shape": "box", "ext": bx * 0.5,
			"v": Vector2(0.02, 0.08), "size": fit_size(Vector2(w * 2.4 + 0.2, w * 3.2 + 0.3), 1.0, wide * 0.7), "spin": Vector2(-25, 25),
			"ramp": [[0.0, Color(1.0, 0.5, 0.15, 0.0)], [0.3, Color(1.0, 0.42, 0.1, 0.32)], [1.0, Color(0.6, 0.15, 0.03, 0.0)]]})
		# Braises : montent, ralenties par l'air (amortissement > gravité :
		# hauteur bornée), dans la place au-dessus du feu.
		parts({"tex": "dot", "n": 10 * dens, "k": k, "life": 2.2, "rand": 0.45, "at": at + Vector3(0, h * 0.2, 0), "shape": "box",
			"ext": Vector3(ext.x + w * 0.5, 0.1, ext.y + w * 0.5), "spread": 25.0, "v": Vector2(0.3, 0.6) * sqrt(room),
			"g": Vector3(0, 0.25, 0), "damp": Vector2(0.35, 0.8), "size": Vector2(0.02, 0.045), "curve": [[0.0, 1.0], [0.7, 0.8], [1.0, 0.0]],
			"ramp": MapEffects.EMBER_RAMP})
		var sc := Color(0.24, 0.23, 0.22).lerp(Color(0.04, 0.035, 0.03), dark)
		parts({"tex": "smoke_a", "blend": "lit", "soft": 0.5, "n": 6 * dens, "k": k, "cover": true, "life": 3.0 + h, "rand": 0.3,
			"at": at + Vector3(0, h * 0.75, 0), "shape": "box", "ext": Vector3(ext.x * 0.8 + 0.05, 0.1, ext.y * 0.8 + 0.05), "spread": 4.0,
			"v": Vector2(0.3, 0.5) * sqrt(maxf(0.1, room - h * 0.75)), "g": Vector3(0, 0.1, 0), "damp": Vector2(0.2, 0.45),
			"size": fit_size(Vector2(w * 2.0 + 0.4, w * 3.0 + 0.6), 1.9, wide * 0.85),
			"curve": [[0.0, 0.4], [1.0, 1.9]], "ramp": [[0.0, Color(sc, 0.0)], [0.15, Color(sc, 0.35 + dark * 0.35)], [1.0, Color(sc, 0.0)]],
			"spin": Vector2(-25, 25)})
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

	## Flamme au bout de la torche murale (décor « torche_murale », posé
	## 0,45 m plus bas que la flamme : le volume est centré sur sa hauteur) :
	## largeur et hauteur de la flamme selon la zone (petite, peu étirable).
	func torche() -> void:
		var kw := e.zone.x / z0.x
		var kh := e.zone.z / z0.z
		var base := maxf(-0.18, vol.position.y + 0.03)
		fire(Vector3(0, base, 0.29), Vector2(0.04, 0.04) * kw, 0.04 * kw, 0.38 * kh, 0.7, 1.0, 0.3, 1.4, 5.5)

	## Nappe de feu sur toute la zone, fumée épaisse, 1 à 3 lumières.
	func incendie() -> void:
		fire(Vector3(0, 0.05, 0), inset(0.28), 0.9, 1.8, 3.2, area_k(), 0.8, 3.2, 12.0, 0)

	# -------------------------------------------------------------- fumées

	## Volutes qui montent lentement, aussi larges que la zone le permet.
	func fumee_legere() -> void:
		var c := Color(0.58, 0.58, 0.58)
		var sz := fit_size(Vector2(0.5, 0.85), 2.4, minf(vol.size.x, vol.size.z) * 0.85)
		var ex := inset(sz.y * 1.2, 0.05)
		for t in [["smoke_b", 10], ["smoke_a", 5]]:
			parts({"tex": t[0], "blend": "lit", "soft": 0.6, "n": t[1], "k": area_k(), "cover": true, "life": 6.5, "rand": 0.3, "at": Vector3(0, 0.15, 0),
				"shape": "box", "ext": Vector3(ex.x, 0.05, ex.y), "spread": 4.0, "v": Vector2(0.15, 0.28), "g": Vector3(0, 0.04, 0),
				"damp": Vector2(0.05, 0.15), "size": sz, "curve": [[0.0, 0.5], [1.0, 2.4]], "tint": true, "spin": Vector2(-15, 15),
				"ramp": [[0.0, Color(c, 0.0)], [0.2, Color(c, 0.3)], [0.7, Color(c, 0.16)], [1.0, Color(c, 0.0)]]})

	## Colonne de fumée noire (aussi large que la zone le permet), foyer qui
	## couve et braises au pied.
	func fumee_noire() -> void:
		var c := Color(0.035, 0.03, 0.028)
		var wide := minf(vol.size.x, vol.size.z) * 0.85
		var ex := inset(0.4, 0.05)
		for t in [["smoke_a", 16, 1.0], ["smoke_b", 10, 0.8]]:
			var sz := fit_size(Vector2(0.9, 1.3) * float(t[2]), 2.8, wide)
			parts({"tex": t[0], "blend": "lit", "soft": 0.6, "n": t[1], "k": area_k(), "cover": true, "life": 6.0, "rand": 0.25, "at": Vector3(0, 0.2, 0),
				"shape": "box", "ext": Vector3(ex.x, 0.05, ex.y), "spread": 4.0, "v": Vector2(0.45, 0.7), "g": Vector3(0, 0.06, 0),
				"damp": Vector2(0.12, 0.25), "size": sz, "curve": [[0.0, 0.5], [0.5, 1.6], [1.0, 2.8]], "spin": Vector2(-18, 18),
				"ramp": [[0.0, Color(c, 0.0)], [0.1, Color(c, 0.8)], [0.6, Color(c, 0.55)], [1.0, Color(c, 0.0)]]})
		# Foyer qui couve au pied de la colonne.
		var fx := inset(0.5)
		parts({"tex": "fire_core", "n": 3, "k": area_k(), "life": 1.4, "at": Vector3(0, 0.06, 0), "shape": "box", "ext": Vector3(fx.x, 0.0, fx.y),
			"v": Vector2(0.02, 0.05), "size": fit_size(Vector2(0.5, 0.8), 1.0, wide), "spin": Vector2(-20, 20),
			"ramp": [[0.0, Color(1.0, 0.35, 0.08, 0.0)], [0.4, Color(1.0, 0.3, 0.06, 0.3)], [1.0, Color(0.5, 0.08, 0.02, 0.0)]]})
		parts({"tex": "dot", "n": 8, "k": area_k(), "life": 1.8, "rand": 0.4, "at": Vector3(0, 0.1, 0), "shape": "box", "ext": Vector3(ex.x, 0.05, ex.y),
			"spread": 30.0, "v": Vector2(0.4, 0.9), "g": Vector3(0, 0.2, 0), "damp": Vector2(0.3, 0.5), "size": Vector2(0.015, 0.035),
			"ramp": MapEffects.EMBER_RAMP})
		light(Vector3(0, 0.2, 0), Color(1.0, 0.4, 0.12), 0.7, 3.5, MapEffect.Light.FIRE, true)

	## Jet de vapeur (le tuyau est le décor « tuyau_vapeur ») : un jet par
	## point de la zone (largeur le long du mur × hauteur), bouffées aussi
	## larges que la zone le permet, freinées avant sa portée.
	func vapeur() -> void:
		var c := Color(0.8, 0.83, 0.86)
		var sz := fit_size(Vector2(0.12, 0.2), 3.4, minf(vol.size.x, vol.size.y) * 0.7)
		var rad := sz.y * 3.4 * 0.5
		var ext := Vector3(maxf(hx - rad, 0.0), maxf(zh * 0.5 - rad, 0.0), 0.0)
		var reach := e.zone.y
		# Bouffées nées au bout du tuyau, assez loin du mur pour ne pas y entrer.
		var z0j := maxf(0.19, rad + 0.02)
		parts({"tex": "smoke_b", "blend": "mix", "soft": 0.3, "n": 34, "k": area_k(), "life": 1.8, "rand": 0.3, "at": Vector3(0, 0, z0j),
			"shape": "box", "ext": ext, "dir": Vector3(0, 0.05, 1.0), "spread": 2.0, "v": Vector2(1.5, 2.2) * (reach / 1.5), "g": Vector3(0, 0.15, 0),
			"damp": Vector2(2.4, 3.4), "size": sz, "curve": [[0.0, 0.3], [0.3, 1.3], [1.0, 3.4]], "spin": Vector2(-45, 45),
			"ramp": [[0.0, Color(c, 0.0)], [0.06, Color(c, 0.6)], [0.5, Color(c, 0.25)], [1.0, Color(c, 0.0)]]})
		# Gouttelettes de condensation projetées (elles s'évaporent vite).
		parts({"tex": "streak", "blend": "mix", "mode": "streak", "quad": Vector2(0.012, 0.05), "n": 6, "k": area_k(), "life": 0.25,
			"at": Vector3(0, -0.03, 0.19), "shape": "box", "ext": ext, "dir": Vector3(0, 0.1, 1), "spread": 15.0, "v": Vector2(1.0, 2.0),
			"g": Vector3(0, -9.8, 0), "size": Vector2(0.8, 1.2), "ramp": [[0.0, Color(MapEffects.WATER, 0.6)], [1.0, Color(MapEffects.WATER, 0.0)]]})

	## Nappe de brume rampante sur toute la zone, épaisse de sa hauteur :
	## grandes nappes à plat (dans l'épaisseur) et bouffées de sa hauteur.
	func brouillard() -> void:
		var c := Color(1, 1, 1)
		var th := vol.size.y
		var wide := minf(vol.size.x, vol.size.z)
		var sheet := fit_size(Vector2(2.0, 3.0) * clampf(th / 0.6, 0.7, 1.8), 1.2, wide * 0.85)
		var ex := inset(sheet.y * 0.6 + 0.3, 0.05)
		parts({"tex": "smoke_a", "blend": "lit", "soft": 1.0, "mode": "flat", "n": 18, "k": area_k(), "cover": true, "life": 14.0, "rand": 0.3,
			"at": Vector3(0, th * 0.5, 0), "shape": "box", "ext": Vector3(ex.x, th * 0.4, ex.y), "dir": Vector3(1, 0, 0), "spread": 180.0, "flatness": 1.0,
			"v": Vector2(0.01, 0.04), "size": sheet, "curve": [[0.0, 0.6], [0.5, 1.0], [1.0, 1.2]], "tint": true,
			"ramp": [[0.0, Color(c, 0.0)], [0.3, Color(c, 0.2)], [0.7, Color(c, 0.2)], [1.0, Color(c, 0.0)]]})
		var puff := Vector2(0.75, 0.9) * th
		var px := inset(th * 0.5 + 0.6, 0.05)
		parts({"tex": "smoke_b", "blend": "lit", "soft": 0.8, "n": 10.0 * clampf(1.5 / th, 1.0, 4.0), "k": area_k(), "cover": true, "life": 10.0, "rand": 0.3,
			"at": Vector3(0, th * 0.5, 0), "shape": "box", "ext": Vector3(px.x, 0.0, px.y), "dir": Vector3(1, 0, 0), "spread": 180.0, "flatness": 1.0,
			"v": Vector2(0.03, 0.06), "size": puff, "tint": true, "spin": Vector2(-6, 6),
			"ramp": [[0.0, Color(c, 0.0)], [0.3, Color(c, 0.14)], [0.7, Color(c, 0.14)], [1.0, Color(c, 0.0)]]})

	# -------------------------------------------------------------- étincelles

	## Gerbe d'étincelles étirées (rebondissent sur le sol de collision) ;
	## `ext` : demi-étendue de la boîte d'émission (zone), `k` : multiplicateur
	## de surface.
	func sparks(at: Vector3, n: int, dir: Vector3, spread: float, v: Vector2, life: float, burst: bool, cycle := false, col_tint := false,
			ext := Vector3.ZERO, k := 1.0, damp := Vector2(0.1, 0.4)) -> void:
		var c := {"tex": "streak", "mode": "streak", "quad": Vector2(0.045, 0.24), "n": n, "life": life, "rand": 0.5, "explo": 0.92 if burst else 0.0,
			"at": at, "shape": "box" if ext != Vector3.ZERO else "sphere", "r": 0.03, "ext": ext, "dir": dir, "spread": spread, "v": v,
			"g": Vector3(0, -9.8, 0), "damp": damp, "size": Vector2(0.7, 1.2),
			"ramp": MapEffects.SPARK_RAMP if not col_tint else [[0.0, Color(1, 1, 1, 1)], [0.5, Color(0.8, 0.85, 1.0, 0.9)], [1.0, Color(0.5, 0.6, 1.0, 0.0)]],
			"tint": col_tint, "collide": "bounce", "burst": burst, "cycle": cycle}
		if k != 1.0:
			c["k"] = k
		parts(c)

	## Éclair blanc au point de la salve.
	func flash(at: Vector3, col: Color, sz: float) -> void:
		parts({"tex": "flash", "n": 2, "life": 0.14, "explo": 1.0, "at": at, "v": Vector2.ZERO, "size": Vector2(sz, sz * 1.5), "burst": true,
			"ramp": [[0.0, Color(col, 1.0)], [1.0, Color(col, 0.0)]]})

	## Pluie d'étincelles du plafond (le câble est le décor « cable_suspendu ») :
	## gerbes nées dans la zone, autour du bout du câble, qui tombent jusqu'au
	## sol (bas du volume) et y rebondissent.
	func pluie_etincelles() -> void:
		var ex := inset(0.22, 0.03)
		var ext := Vector3(ex.x, 0.02, ex.y)
		sparks(MapEffects.CABLE_TIP, 28, Vector3.DOWN, 30.0, Vector2(0.5, 1.8), 1.3, true, false, false, ext, area_k())
		flash(MapEffects.CABLE_TIP, Color(1.0, 0.85, 0.6), 0.35)
		sparks(MapEffects.CABLE_TIP, 3, Vector3.DOWN, 25.0, Vector2(0.1, 0.6), 1.0, false, false, false, ext, area_k())
		floor_collider()
		light(MapEffects.CABLE_TIP, Color(1.0, 0.78, 0.45), 2.6, 5.5, MapEffect.Light.FLASH)
		e.burst_every = Vector2(0.6, 3.0)
		e.burst_pops = 0.45

	## Soudure sur le mur : métal chauffé au rouge, gerbe continue par à-coups,
	## sur la zone (largeur × hauteur) ; les étincelles tombent jusqu'au sol
	## (bas du volume) dans sa portée.
	func soudure() -> void:
		var ext := Vector3(maxf(hx - 0.2, 0.0), maxf(zh * 0.5 - 0.2, 0.0), 0.0)
		parts({"tex": "dot", "n": 2, "k": area_k(), "life": 0.5, "at": Vector3(0, 0, 0.012), "mode": "flat", "quad": Vector2(0.14, 0.14), "v": Vector2.ZERO,
			"shape": "box", "ext": Vector3(ext.x, 0.0, ext.y), "size": Vector2(0.9, 1.1),
			"ramp": [[0.0, Color(1.0, 0.35, 0.08, 0.7)], [1.0, Color(1.0, 0.35, 0.08, 0.7)]]}).rotation.x = PI * 0.5
		sparks(Vector3(0, 0, 0.12), 70, Vector3(0, -0.1, 1), 12.0, Vector2(1.2, 2.8), 0.8, false, true, false, ext, area_k(), Vector2(0.6, 1.2))
		parts({"tex": "dot", "n": 4, "k": area_k(), "life": 0.08, "rand": 0.5, "at": Vector3(0, 0, 0.22), "shape": "box", "ext": ext, "v": Vector2.ZERO,
			"size": Vector2(0.25, 0.42), "cycle": true, "ramp": [[0.0, Color(0.8, 0.9, 1.0, 1.0)], [1.0, Color(0.6, 0.75, 1.0, 0.0)]]})
		parts({"tex": "smoke_b", "blend": "lit", "soft": 0.3, "n": 4, "k": area_k(), "life": 1.6, "at": Vector3(0, 0.0, 0.3), "shape": "box", "ext": ext,
			"dir": Vector3(0, 0.15, 1), "v": Vector2(0.25, 0.45), "spread": 15.0, "size": fit_size(Vector2(0.2, 0.3), 3.0, zh), "curve": [[0.0, 0.5], [1.0, 3.0]], "spin": Vector2(-30, 30),
			"ramp": [[0.0, Color(0.5, 0.5, 0.52, 0.0)], [0.2, Color(0.5, 0.5, 0.52, 0.22)], [1.0, Color(0.5, 0.5, 0.52, 0.0)]]})
		floor_collider()
		light(Vector3(0, 0, 0.3), Color(0.72, 0.84, 1.0), 2.8, 6.5, MapEffect.Light.WELD)
		e.cycle_on = Vector2(1.5, 4.0)
		e.cycle_off = Vector2(0.4, 1.6)

	## Court-circuit (le boîtier est le décor « boitier_electrique ») :
	## claquements, étincelles qui tombent jusqu'au sol, fumée et arcs, sur la zone.
	func court_circuit() -> void:
		var at := Vector3(0.02, 0.04, 0.14)
		var ext := Vector3(maxf(hx - 0.2, 0.0), maxf(zh * 0.5 - 0.25, 0.0), 0.0)
		sparks(at, 34, Vector3(0, 0, 1), 12.0, Vector2(0.8, 2.2), 0.9, true, false, false, ext, area_k(), Vector2(0.4, 0.9))
		flash(at + Vector3(0, 0, 0.2), Color(0.8, 0.88, 1.0), 0.35)
		parts({"tex": "smoke_b", "blend": "lit", "soft": 0.3, "n": 5, "k": area_k(), "life": 2.4, "explo": 0.8, "at": at, "shape": "box", "ext": ext,
			"dir": Vector3(0, 0.15, 1), "v": Vector2(0.2, 0.5), "spread": 15.0, "damp": Vector2(0.15, 0.25), "size": fit_size(Vector2(0.2, 0.3), 3.0, zh), "curve": [[0.0, 0.4], [1.0, 3.0]],
			"spin": Vector2(-30, 30), "burst": true,
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

	## Arc d'un bout à l'autre de la zone (largeur), au milieu du volume (la
	## hauteur de pose est le bas du volume : 0,3 m sous l'arc) ; plusieurs
	## arcs de front si la zone est profonde (les électrodes sont le décor
	## « electrodes »). Étincelles brèves aux bouts.
	func arc_() -> void:
		var cy := vol.get_center().y
		var half := maxf(hx - 0.17, 0.1)
		var rows := clampi(roundi(hz * 2.0 / 0.4), 1, 4)
		for row in rows:
			var z := (float(row) / (rows - 1) - 0.5) * (hz * 2.0 - 0.2) if rows > 1 else 0.0
			for sx in [-1.0, 1.0]:
				var end := Vector3(sx * (half + 0.04), cy, z)
				_glow(end, 0.24, 0.55)
				parts({"tex": "streak", "mode": "streak", "quad": Vector2(0.02, 0.1), "n": 5, "life": 0.3, "rand": 0.5, "at": end,
					"shape": "sphere", "r": 0.04, "spread": 90.0, "v": Vector2(0.2, 0.8), "g": Vector3(0, -9.8, 0), "size": Vector2(0.6, 1.0), "tint": true,
					"ramp": [[0.0, Color(1, 1, 1, 1)], [1.0, Color(0.6, 0.7, 1.0, 0.0)]]})
			for i in 3:
				arc(Vector3(-half, cy, z), Vector3(half, cy, z), 0.38 * clampf(half / 0.58, 0.8, 2.0))
		light(Vector3(0, cy, 0), tint, 2.0, 6.0, MapEffect.Light.CRACKLE)

	## Décharges rayonnantes jusqu'au bord de la zone, depuis le milieu du
	## volume (la boule de la bobine, décor « bobine_tesla », 0,8 m au-dessus
	## de la hauteur de pose).
	func tesla() -> void:
		var c := Vector3(0, vol.get_center().y, 0)
		var reach := minf(hx, hz)
		var kr := reach / 1.2
		_glow(c, 0.75, 0.45)
		for i in clampi(roundi(5.0 * sqrt(maxf(kr, 0.2))), 3, 10):
			arc(c, Vector3(0.45 * kr, 1.15 * kr, 0), 0.32 * clampf(kr, 0.6, 1.6), 1)
		parts({"tex": "dot", "n": 10, "k": clampf(kr, 0.5, 4.0), "life": 0.7, "rand": 0.5, "at": c, "shape": "sphere", "r": 0.16, "spread": 180.0,
			"v": Vector2(0.5, 1.3) * clampf(kr, 0.6, 2.0), "g": Vector3(0, -3.0, 0), "size": Vector2(0.015, 0.03), "tint": true,
			"ramp": [[0.0, Color(1, 1, 1, 1)], [1.0, Color(1, 1, 1, 0)]]})
		light(c, tint, 2.4, 7.0, MapEffect.Light.CRACKLE)

	## Crépitements au bout du câble suspendu (décor « cable_suspendu ») ;
	## les étincelles tombent jusqu'au sol (bas du volume).
	func cable_nu() -> void:
		var tip := MapEffects.CABLE_TIP
		var ex := inset(0.22, 0.03)
		var ext := Vector3(ex.x, 0.02, ex.y)
		_glow(tip, 0.3, 0.6)
		for i in clampi(roundi(2.0 * sqrt(area_k())), 2, 6):
			arc(tip, Vector3(0.12, 0.3, 0), 0.12, 1)
		sparks(tip, 5, Vector3.DOWN, 40.0, Vector2(0.2, 0.8), 1.0, false, false, true, ext, area_k())
		sparks(tip, 18, Vector3.DOWN, 30.0, Vector2(0.4, 1.2), 1.1, true, false, true, ext, area_k())
		flash(tip, tint.lightened(0.4), 0.3)
		floor_collider()
		light(tip, tint, 1.6, 5.0, MapEffect.Light.CRACKLE)
		light(tip, tint, 2.4, 5.0, MapEffect.Light.FLASH, true)
		e.burst_every = Vector2(2.0, 6.0)
		e.burst_pops = 0.3

	# -------------------------------------------------------------- eau

	## Gouttes qui tombent de `at` (n'importe où dans `ext`) et ronds au sol
	## synchronisés sur leur chute ; éclaboussures arrêtées par le sol.
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
				"spread": 35.0, "v": Vector2(0.4, 0.9), "g": Vector3(0, -9.8, 0), "collide": "hide",
				"size": Vector2(0.8, 1.0), "ramp": [[0.0, Color(MapEffects.WATER, 0.6)], [0.25, Color(MapEffects.WATER, 0.0)], [1.0, Color(MapEffects.WATER, 0.0)]]})

	## Gouttes du plafond sur toute la zone jusqu'au sol (bas du volume ; la
	## flaque au sol est le décor « petite_flaque » ou « flaque_eau »).
	func goutte() -> void:
		var ex := inset(0.25, 0.0)
		drops(Vector3(0, -0.06, 0), 2, 1.4, Vector3.DOWN, Vector2(0.0, 0.05), 0.0, Vector2(0.012, 0.07), Vector3(0, -ground, 0), 2,
			Vector3(ex.x, 0.0, ex.y), area_k())
		floor_collider()

	## Filet d'eau qui tombe du mur (le tuyau est le décor « tuyau_fuite ») :
	## un filet par point de la zone, éclaboussures et ronds là où il tombe
	## (au sol, dans la portée du volume).
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
			"at": land + Vector3(0, 0.03, 0), "shape": "box", "ext": lx + Vector3(0.06, 0.0, 0.06), "spread": 30.0, "v": Vector2(0.5, 1.1),
			"g": Vector3(0, -9.8, 0), "size": Vector2(0.8, 1.1), "collide": "hide",
			"ramp": [[0.0, Color(MapEffects.WATER, 0.7)], [1.0, Color(MapEffects.WATER, 0.0)]]})
		parts({"tex": "ring", "blend": "mix", "mode": "flat", "n": 4, "k": area_k(), "life": 0.9, "rand": 0.3, "at": land + Vector3(0, 0.012, 0),
			"shape": "box", "ext": lx + Vector3(0.03, 0.0, 0.1), "v": Vector2.ZERO, "size": fit_size(Vector2(0.08, 0.12), 5.0, vol.size.x * 0.8), "curve": [[0.0, 0.3], [1.0, 5.0]],
			"ramp": [[0.0, Color(0.75, 0.85, 0.95, 0.0)], [0.08, Color(0.75, 0.85, 0.95, 0.45)], [1.0, Color(0.7, 0.8, 0.9, 0.0)]]})
		parts({"tex": "smoke_b", "blend": "mix", "soft": 0.3, "n": 3, "k": area_k(), "life": 1.6, "at": land + Vector3(0, 0.08, 0), "shape": "box", "ext": lx,
			"v": Vector2(0.05, 0.15), "size": fit_size(Vector2(0.35, 0.5), 1.6, vol.size.x * 0.9), "curve": [[0.0, 0.6], [1.0, 1.6]], "spin": Vector2(-20, 20),
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

	## Grains de poussière dans tout le volume de la zone (turbulence lente,
	## vitesse bornée).
	func poussiere() -> void:
		var c := Color(1.0, 0.92, 0.78)
		var th := vol.size.y
		var ex := inset(0.1, 0.2)
		parts({"tex": "dot", "n": 70, "k": vol_k(), "life": 12.0, "rand": 0.3, "at": Vector3(0, th * 0.5, 0), "shape": "box",
			"ext": Vector3(ex.x, th * 0.5, ex.y), "dir": Vector3(1, 0, 0), "spread": 180.0, "v": Vector2(0.01, 0.04), "g": Vector3(0, -0.004, 0),
			"size": Vector2(0.012, 0.028), "curve": [[0.0, 0.0], [0.15, 1.0], [0.85, 1.0], [1.0, 0.0]], "turb": 0.12, "turb_scale": 3.0, "vlim": 0.04,
			"ramp": [[0.0, Color(c, 0.0)], [0.2, Color(c, 0.3)], [0.8, Color(c, 0.3)], [1.0, Color(c, 0.0)]]})

	## Braises qui s'élèvent du sol, freinées par l'air (amortissement plus
	## fort que leur poussée : hauteur bornée) en s'écartant un peu.
	func braises() -> void:
		var ex := inset(0.1, 0.1)
		parts({"tex": "dot", "n": 34, "k": area_k(), "life": 4.5, "rand": 0.4, "at": Vector3(0, 0.1, 0), "shape": "box", "ext": Vector3(ex.x, 0.05, ex.y),
			"spread": 35.0, "v": Vector2(0.25, 0.6), "g": Vector3(0, 0.08, 0), "damp": Vector2(0.18, 0.35), "size": Vector2(0.018, 0.04),
			"curve": [[0.0, 0.4], [0.1, 1.0], [0.8, 0.8], [1.0, 0.0]], "spin": Vector2(-90, 90),
			"ramp": [[0.0, Color(1.0, 0.75, 0.35, 0.0)], [0.08, Color(1.0, 0.6, 0.2, 1.0)], [0.6, Color(1.0, 0.3, 0.05, 0.85)], [1.0, Color(0.5, 0.08, 0.02, 0.0)]]})
		light(Vector3(0, 0.4, 0), Color(1.0, 0.45, 0.15), 0.5, 4.0, MapEffect.Light.FIRE, true)

	## Flocons de cendre qui tombent du haut du volume (le plafond) jusqu'au
	## sol, lentement, un peu de biais.
	func cendres() -> void:
		var top_y := maxf(0.1, top() - 0.05)
		var ex := inset(0.1, 0.2)
		var life := clampf(top_y / 0.2, 4.0, 20.0)
		var c := Color(0.55, 0.53, 0.5)
		parts({"tex": "dot", "blend": "lit", "n": 50, "k": area_k(), "life": life, "rand": 0.3, "at": Vector3(0, top_y, 0), "shape": "box",
			"ext": Vector3(ex.x, 0.03, ex.y), "dir": Vector3.DOWN, "spread": 10.0, "v": Vector2(0.2, 0.32),
			"size": Vector2(0.02, 0.045), "spin": Vector2(-90, 90), "collide": "hide",
			"ramp": [[0.0, Color(c, 0.0)], [0.05, Color(c, 0.85)], [0.85, Color(c, 0.85)], [1.0, Color(c, 0.0)]]})
		parts({"tex": "dot", "n": 8, "k": area_k(), "life": life, "rand": 0.3, "at": Vector3(0, top_y, 0), "shape": "box",
			"ext": Vector3(maxf(ex.x - 0.1, 0.1), 0.03, maxf(ex.y - 0.1, 0.1)), "dir": Vector3.DOWN, "spread": 10.0, "v": Vector2(0.2, 0.32),
			"size": Vector2(0.015, 0.03), "collide": "hide", "ramp": MapEffects.EMBER_RAMP})
		floor_collider()

	## Lueurs vertes qui dérivent dans le volume (turbulence, vitesse bornée).
	func feux_follets() -> void:
		var th := vol.size.y
		var at := Vector3(0, th * 0.5, 0)
		var ex := inset(0.15, 0.1)
		var ext := Vector3(ex.x, th * 0.5, ex.y)
		var k := vol_k()
		parts({"tex": "dot", "n": 5, "k": k, "life": 5.0, "rand": 0.3, "at": at, "shape": "box", "ext": ext, "spread": 180.0, "v": Vector2(0.05, 0.15),
			"size": Vector2(0.35, 0.55), "curve": [[0.0, 0.0], [0.2, 1.0], [0.8, 1.0], [1.0, 0.0]], "tint": true, "spin": Vector2(-60, 60),
			"turb": 1.4, "turb_scale": 0.7, "ramp": [[0.0, Color(1, 1, 1, 0.0)], [0.2, Color(1, 1, 1, 0.6)], [0.8, Color(1, 1, 1, 0.5)], [1.0, Color(1, 1, 1, 0.0)]]})
		parts({"tex": "dot", "n": 6, "k": k, "life": 5.0, "rand": 0.3, "at": at, "shape": "box", "ext": ext, "spread": 180.0, "v": Vector2(0.05, 0.15),
			"size": Vector2(0.05, 0.08), "curve": [[0.0, 0.0], [0.2, 1.0], [0.8, 1.0], [1.0, 0.0]], "turb": 1.4, "turb_scale": 0.7,
			"ramp": [[0.0, Color(0.85, 1.0, 0.88, 0.0)], [0.2, Color(0.85, 1.0, 0.88, 1.0)], [1.0, Color(0.85, 1.0, 0.88, 0.0)]]})
		parts({"tex": "twirl", "n": 8, "k": k, "life": 1.8, "rand": 0.4, "at": at, "shape": "box", "ext": ext, "v": Vector2(0.0, 0.1), "size": Vector2(0.15, 0.3),
			"tint": true, "spin": Vector2(-200, 200), "ramp": [[0.0, Color(1, 1, 1, 0.0)], [0.3, Color(1, 1, 1, 0.3)], [1.0, Color(1, 1, 1, 0.0)]]})
		parts({"tex": "dot", "n": 24, "k": k, "life": 3.0, "rand": 0.4, "at": at, "shape": "box", "ext": ext + Vector3(0.1, -0.1, 0.1), "v": Vector2(0.05, 0.12),
			"size": Vector2(0.01, 0.018), "tint": true, "turb": 0.6, "ramp": [[0.0, Color(1, 1, 1, 0.0)], [0.3, Color(1, 1, 1, 0.9)], [1.0, Color(1, 1, 1, 0.0)]]})
		light(at, tint, 0.9, 4.5, MapEffect.Light.PULSE)

	## Construit l'effet `id` (« arc » : arc_, le nom étant pris).
	func call_fx(id: String) -> void:
		if id == "arc":
			arc_()
		elif has_method(id):
			call(id)
