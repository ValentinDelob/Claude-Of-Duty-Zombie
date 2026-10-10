class_name WorldLook
extends RefCounted
## Direction artistique du monde : matériaux, environnement, éclairage.
## Centralisé ici pour pouvoir ajuster l'ambiance (et les réglages de qualité)
## sans toucher au gameplay.

## Clés des surfaces du jeu (sols, murs, plafonds des cartes, décor), citées
## par les cartes et l'éditeur (MapCatalog.materials) -> famille. Toutes sont
## des textures PIXEL ART générées « un pixel = un cube de 5 cm »
## (PixelSurfaces, docs/VOXEL_ARCHITECTURE_PLAN.md lot C).
const SURFACES := {
	"floor": "sol", "wall": "mur", "ceiling": "plafond",
	"concrete": "sol", "concrete_dark": "sol", "tiles": "sol", "wood": "sol", "metal": "sol", "stone": "mur",
	"wall_green": "mur", "wall_cell": "mur", "wall_lab": "mur", "wall_rust": "mur", "wall_concrete": "mur",
	"wall_ritual": "mur",
	# Décor
	"crate": "decor", "barrel": "decor", "steel": "decor", "fabric": "decor", "door": "decor",
	# Théâtre (KINO)
	"carpet_red": "sol", "marble": "sol", "stage_wood": "sol", "parquet": "sol", "wall_theater": "mur",
	"wall_lobby": "mur", "wall_foyer": "mur", "wall_loges": "mur", "brick": "mur", "cobble": "sol",
	"velvet": "decor", "brass": "decor", "plaster_theater": "mur", "vault_theater": "plafond",
	"carpet_theater": "sol", "ceiling_theater": "plafond", "dark_wood": "sol",
}

## Environnement normal (voir aussi apply_dog_round_look).
const BASE_FOG_COLOR := Color(0.085, 0.09, 0.105)
const BASE_FOG_DENSITY := 0.016
const BASE_AMBIENT_ENERGY := 0.5
const BASE_SATURATION := 0.78
## Brume volumétrique (qualités MEDIUM et HIGH, voir RenderQuality) : fine,
## elle ne se voit que dans les halos et faisceaux des lampes (BO1).
const BASE_VOLUMETRIC_DENSITY := 0.006

## Étalonnage BO1 (table de correspondance 3D procédurale, voir grade_color).
## Surchargeable par carte : MapDef.look["grade"].
##   shadow_tint    : teinte des ombres (vert-de-gris froid des zones éteintes)
##   highlight_tint : teinte des hautes lumières (chaleur des ampoules)
##   toe            : exposant du pied de courbe (> 1 : noirs plus denses)
##   lift           : relèvement du noir (lisibilité des zones sombres)
##   lift_tint      : couleur de ce relèvement (noirs bleu-vert, pas neutres)
##   desat          : désaturation des couleurs vives (image « délavée »)
##   gain           : gain final (compense le pied de courbe : pas plus sombre)
const GRADE_DEFAULT := {
	"shadow_tint": Color(0.84, 1.0, 1.04),
	"highlight_tint": Color(1.05, 1.0, 0.92),
	"lift_tint": Color(0.7, 1.0, 1.15),
	"toe": 1.3,
	"lift": 0.016,
	"desat": 0.3,
	"gain": 1.06,
}
const LUT_SIZE := 24
## Poids des niveaux de glow 1 à 7 (index 0 à 6) : surtout les niveaux larges.
const GLOW_LEVELS := [0.0, 0.2, 0.55, 0.75, 0.45, 0.2, 0.0]
const LUMA := Vector3(0.2126, 0.7152, 0.0722)

static var _luts: Dictionary = {}
## Images des tables de base (sans gamma), pour dériver vite les variantes.
static var _lut_layers: Dictionary = {}


## Matériau d'une surface du jeu (texture pixel art, mise en cache par
## PixelSurfaces et partagée par toutes les cartes) ; clé inconnue : plâtre.
static func surface(key: String) -> ShaderMaterial:
	return PixelSurfaces.material(key if PixelSurfaces.has(key) else "wall")


## `look` : surcharges propres à la carte (MapDef.look) ; `with_outline` :
## contour noir en jeu (ScreenOutline ; faux pour l'aperçu de l'éditeur).
static func setup_environment(parent: Node3D, look := {}, with_outline := true) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.0, 0.0, 0.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.36, 0.38, 0.44)
	env.ambient_light_energy = BASE_AMBIENT_ENERGY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.3
	# Bloom BO1 : halo large et doux autour des ampoules, des écrans et des
	# néons des machines ; seul ce qui dépasse le blanc (sources) « bave ».
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_strength = 1.0
	env.glow_bloom = 0.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.glow_hdr_threshold = 1.1
	env.glow_hdr_scale = 1.4
	for i in GLOW_LEVELS.size():
		env.set_glow_level(i, GLOW_LEVELS[i])
	env.fog_enabled = true
	env.fog_light_color = BASE_FOG_COLOR
	env.fog_density = BASE_FOG_DENSITY
	# Brume volumétrique : activée par RenderQuality (MEDIUM, HIGH).
	env.volumetric_fog_density = BASE_VOLUMETRIC_DENSITY
	env.volumetric_fog_albedo = Color(0.78, 0.8, 0.76)
	env.volumetric_fog_anisotropy = 0.7
	env.volumetric_fog_length = 32.0
	env.volumetric_fog_detail_spread = 1.6
	env.volumetric_fog_ambient_inject = 0.0
	env.volumetric_fog_gi_inject = 0.0
	env.volumetric_fog_sky_affect = 0.0
	env.volumetric_fog_temporal_reprojection_enabled = true
	env.volumetric_fog_temporal_reprojection_amount = 0.9
	env.adjustment_enabled = true
	env.adjustment_saturation = BASE_SATURATION
	env.adjustment_contrast = 1.08
	env.ambient_light_color = look.get("ambient_color", env.ambient_light_color)
	env.ambient_light_energy = look.get("ambient_energy", env.ambient_light_energy)
	env.fog_light_color = look.get("fog_color", env.fog_light_color)
	env.fog_density = look.get("fog_density", env.fog_density)
	env.adjustment_saturation = look.get("saturation", env.adjustment_saturation)
	env.tonemap_exposure = look.get("exposure", env.tonemap_exposure)
	env.volumetric_fog_density = look.get("volumetric_density", env.volumetric_fog_density)
	env.volumetric_fog_albedo = look.get("volumetric_albedo", env.volumetric_fog_albedo)
	# Ciel de la carte (cartes de l'éditeur aux pièces sans plafond) ; noir par défaut.
	if look.get("sky") is Dictionary:
		apply_sky(env, look.sky)
	# Étalonnage BO1 (table 3D procédurale), luminosité des options comprise
	# (RenderQuality la refait quand Settings.brightness change).
	env.set_meta("grade", look.get("grade", {}))
	env.adjustment_color_correction = map_lut(look.get("grade", {}))
	# Valeurs « normales » de la carte, reprises après une manche de chiens.
	env.set_meta("base_look", {"fog_color": env.fog_light_color, "fog_density": env.fog_density,
			"ambient_energy": env.ambient_light_energy, "saturation": env.adjustment_saturation,
			"volumetric_density": env.volumetric_fog_density})
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	parent.add_child(we)
	# Grain de film, vignettage et aberration (plein écran, sous le HUD).
	var post := FilmPost.new()
	post.name = "FilmPost"
	parent.add_child(post)
	# Contour noir en jeu (pièces et marches de cubes), sous les transparents.
	if with_outline:
		var outline := ScreenOutline.new()
		outline.name = "ScreenOutline"
		parent.add_child(outline)
	# Préréglages de qualité : appliqués maintenant puis à chaque changement
	# d'options (glow, SSAO, brume, ombres des lampes, résolution 3D...).
	var rq := RenderQuality.new()
	rq.name = "RenderQuality"
	rq.environment = env
	parent.add_child(rq)


# --------------------------------------------------------------------------
# Ciel (format 17 des cartes de l'éditeur : pièces sans plafond)
# --------------------------------------------------------------------------

const NIGHT_SKY := preload("res://assets/shaders/night_sky.gdshader")
## Ciel de jour : couvert, gris-bleu délavé (BO1), sans soleil (aucune
## lumière directionnelle : l'éclairage de la carte ne change pas).
const DAY_TOP := Color(0.3, 0.38, 0.5)
const DAY_HORIZON := Color(0.58, 0.6, 0.62)
const DAY_GROUND := Color(0.1, 0.1, 0.1)
## Part de la brume de la carte posée sur le ciel (1 : ciel noyé dans la brume).
const SKY_FOG := 0.2


## Ciel de la carte `sky` = {type : « noir » | « jour » | « nuit »,
## luminosite (facteur)} (EditorMap.sky_of). Noir (« sans fond ») : fond noir
## uni ; `open` (une pièce au moins sans plafond) : noir COMPLET (la brume ne
## l'éclaircit pas) ; sinon le fond d'avant (noir voilé par la brume, jamais
## vu d'une carte fermée). Jour : ciel procédural ; nuit : étoiles générées
## (night_sky.gdshader) ; la luminosité règle l'énergie du ciel. Lumière
## ambiante (couleur de la carte) et reflets inchangés : le ciel ne se voit que
## là où il n'y a pas de plafond, il n'éclaire pas les pièces fermées.
static func apply_sky(env: Environment, sky: Dictionary, open := true) -> void:
	var t := String(sky.get("type", "noir"))
	var lum := float(sky.get("luminosite", 1.0))
	if not (lum >= 0.0 and is_finite(lum)):
		lum = 1.0
	env.set_meta("sky", {"type": t, "luminosite": lum})
	env.set_meta("sky_open", open)
	if not t in ["jour", "nuit"]:
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.0, 0.0, 0.0)
		env.background_energy_multiplier = 1.0
		env.sky = null
		env.fog_sky_affect = 0.0 if open else 1.0
		env.reflected_light_source = Environment.REFLECTION_SOURCE_BG
		return
	var s := Sky.new()
	s.radiance_size = Sky.RADIANCE_SIZE_32
	if t == "jour":
		var m := ProceduralSkyMaterial.new()
		m.sky_top_color = DAY_TOP
		m.sky_horizon_color = DAY_HORIZON
		m.ground_horizon_color = DAY_HORIZON.darkened(0.25)
		m.ground_bottom_color = DAY_GROUND
		m.sky_curve = 0.12
		m.energy_multiplier = lum
		s.sky_material = m
	else:
		var m := ShaderMaterial.new()
		m.shader = NIGHT_SKY
		m.set_shader_parameter("brightness", lum)
		s.sky_material = m
	env.sky = s
	env.background_mode = Environment.BG_SKY
	env.background_energy_multiplier = 1.0
	env.fog_sky_affect = SKY_FOG
	# Lumière ambiante : toujours la couleur de la carte (jamais le ciel) ;
	# reflets du ciel coupés (ils éclairaient les sols des pièces fermées).
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED


# --------------------------------------------------------------------------
# Étalonnage BO1
# --------------------------------------------------------------------------

## Réglages complets de l'étalonnage : GRADE_DEFAULT surchargé par `over`.
static func grade_params(over := {}) -> Dictionary:
	var g := GRADE_DEFAULT.duplicate()
	g.merge(over, true)
	return g


## Couleur de sortie de l'étalonnage pour une couleur d'entrée (espace sRGB
## après tonemapping, 0..1). Pure : testée dans tests/test_world_look.gd.
##  1. désaturation douce des couleurs vives (image délavée de BO1) ;
##  2. virage partiel : ombres vert-de-gris froides, hautes lumières chaudes
##     (sans changer la luminance) ;
##  3. pied de courbe : noirs plus denses, tons moyens intacts ;
##  4. relèvement du noir et gain (lisible : jamais plus sombre au milieu).
static func grade_color(c: Color, g: Dictionary) -> Color:
	var v := Vector3(c.r, c.g, c.b)
	var l := v.dot(LUMA)
	var sat := maxf(v.x, maxf(v.y, v.z)) - minf(v.x, minf(v.y, v.z))
	v = v.lerp(Vector3(l, l, l), float(g.desat) * clampf(sat * 1.6, 0.0, 1.0))
	var st: Color = g.shadow_tint
	var ht: Color = g.highlight_tint
	var sh := 1.0 - smoothstep(0.0, 0.5, l)
	var hi := smoothstep(0.35, 0.95, l)
	var tint := Vector3.ONE.lerp(Vector3(st.r, st.g, st.b), sh) * Vector3.ONE.lerp(Vector3(ht.r, ht.g, ht.b), hi)
	v *= tint / maxf(tint.dot(LUMA), 0.001)
	var pivot := 0.3
	var toe := float(g.toe)
	for i in 3:
		var x := maxf(v[i], 0.0)
		if x < pivot:
			x = pivot * pow(x / pivot, toe)
		v[i] = x
	var lift := float(g.lift)
	var lt: Color = g.lift_tint
	v = Vector3(lt.r, lt.g, lt.b) * lift + v * (1.0 - lift) * float(g.gain)
	return Color(clampf(v.x, 0.0, 1.0), clampf(v.y, 0.0, 1.0), clampf(v.z, 0.0, 1.0))


## Table de correspondance 3D (LUT_SIZE³) de l'étalonnage, mise en cache.
## Chaque texel i stocke la sortie pour le centre de sa cellule ((i+0.5)/N) :
## l'interpolation trilinéaire retombe ainsi sur grade_color.
## `over.gamma` (luminosité des options, 1 = neutre) : courbe gamma_curve
## appliquée en sortie, sur la table de base (rapide : une table de 256 valeurs).
static func grade_lut(over := {}) -> ImageTexture3D:
	var base_over := over.duplicate()
	var gamma := float(base_over.get("gamma", 1.0))
	base_over.erase("gamma")
	var g := grade_params(base_over)
	var key := var_to_str(g)
	if not is_equal_approx(gamma, 1.0):
		return _gamma_lut(base_over, key, gamma)
	if _luts.has(key):
		return _luts[key]
	var n := LUT_SIZE
	var layers: Array[Image] = []
	for b in n:
		var img := Image.create(n, n, false, Image.FORMAT_RGB8)
		for gy in n:
			for r in n:
				img.set_pixel(r, gy, grade_color(Color((r + 0.5) / n, (gy + 0.5) / n, (b + 0.5) / n), g))
		layers.append(img)
	var tex := ImageTexture3D.new()
	tex.create(Image.FORMAT_RGB8, n, n, n, false, layers)
	_luts[key] = tex
	_lut_layers[key] = layers
	return tex


## Luminosité (gamma de sortie, comme le réglage de BO1) : > 1 éclaircit les
## tons sombres et moyens, noir et blanc restent en place. Pure.
static func gamma_curve(x: float, gamma: float) -> float:
	return pow(clampf(x, 0.0, 1.0), 1.0 / maxf(gamma, 0.01))


static func _gamma_lut(base_over: Dictionary, base_key: String, gamma: float) -> ImageTexture3D:
	var key := "%s|gamma=%.3f" % [base_key, gamma]
	if _luts.has(key):
		return _luts[key]
	grade_lut(base_over)
	var table := PackedByteArray()
	table.resize(256)
	for i in 256:
		table[i] = clampi(roundi(gamma_curve(i / 255.0, gamma) * 255.0), 0, 255)
	var n := LUT_SIZE
	var layers: Array[Image] = []
	for img: Image in _lut_layers[base_key]:
		var d := img.get_data()
		for j in d.size():
			d[j] = table[d[j]]
		layers.append(Image.create_from_data(n, n, false, Image.FORMAT_RGB8, d))
	var tex := ImageTexture3D.new()
	tex.create(Image.FORMAT_RGB8, n, n, n, false, layers)
	_luts[key] = tex
	return tex


## Table de la carte (surcharges `grade` de MapDef.look) avec la luminosité
## des options (Settings.brightness).
static func map_lut(grade_over: Dictionary) -> ImageTexture3D:
	var o := grade_over.duplicate()
	o["gamma"] = Settings.brightness
	return grade_lut(o)


## Ambiance d'une manche de chiens (k = 0 : normale, 1 : pleine) : brouillard
## plus épais et plus sombre, lumière ambiante baissée, couleurs délavées,
## brume volumétrique épaisse (les halos des lampes se noient dans la brume).
const DOG_FOG_COLOR := Color(0.07, 0.035, 0.03)
const DOG_FOG_DENSITY := 0.05
const DOG_AMBIENT_ENERGY := 0.3
const DOG_SATURATION := 0.62
const DOG_VOLUMETRIC_MULT := 3.0


static func apply_dog_round_look(env: Environment, k: float) -> void:
	k = clampf(k, 0.0, 1.0)
	# Point de départ : l'ambiance propre à la carte (MapDef.look), sinon la base.
	var base: Dictionary = env.get_meta("base_look", {})
	env.fog_light_color = (base.get("fog_color", BASE_FOG_COLOR) as Color).lerp(DOG_FOG_COLOR, k)
	env.fog_density = lerpf(base.get("fog_density", BASE_FOG_DENSITY), DOG_FOG_DENSITY, k)
	env.ambient_light_energy = lerpf(base.get("ambient_energy", BASE_AMBIENT_ENERGY), DOG_AMBIENT_ENERGY, k)
	env.adjustment_saturation = lerpf(base.get("saturation", BASE_SATURATION), DOG_SATURATION, k)
	var vd: float = base.get("volumetric_density", BASE_VOLUMETRIC_DENSITY)
	env.volumetric_fog_density = lerpf(vd, vd * DOG_VOLUMETRIC_MULT, k)
