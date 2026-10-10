class_name PixelSurfaces
extends RefCounted
## Textures « PIXEL ART » de toutes les surfaces (GAME_CONCEPT.md § 4.19,
## docs/VOXEL_ARCHITECTURE_PLAN.md lot C) : un pixel de texture = un cube de
## décor de 5 cm (20 pixels par mètre), couleurs unies par pixel, filtrage au
## plus proche. Chaque image est GÉNÉRÉE ici (aucun fichier, déterministe :
## même image à chaque lancement, sur chaque machine) d'après les teintes de
## voxel_lib.DECOR_PALETTE (PAL), puis posée en coordonnées MONDE par
## assets/shaders/pixel_surface.gdshader : les pixels tombent sur la grille de
## 5 cm du monde, sans étirement ni couture d'un morceau à l'autre.
##
## Mêmes clés que WorldLook.SURFACES (une carte existante se charge telle
## quelle), plus « plank » (bois des encadrements de fenêtres, Barricade).
## Douze générateurs : béton, carrelage, planches, tôle, mur peint, pierre à
## veines lumineuses, dalles de plafond, moquette, lambris et papier peint,
## briques, velours, pavés ; chaque clé les règle (teinte, taille, usure).
##
## Murs : la ligne 0 de l'image est au sol de la salle (floor_y), la ligne k à
## k × 5 cm au-dessus ; au-delà de la hauteur de l'image, les lignes
## [wrap, hauteur) se répètent (le soubassement peint ne revient pas en haut
## d'un grand mur). Sols et plafonds : x vers l'est, y vers le sud.
## Lueur : l'alpha de l'image vaut 1 - lueur (veines de la pierre rituelle).

const PX_PER_M := 20
const CELL := 1.0 / PX_PER_M
const SIZE := 64
const SHADER := preload("res://assets/shaders/pixel_surface.gdshader")

## Réglages communs par défaut d'une clé (DEFS les surcharge) :
##   gen : générateur ; tone : teinte de PAL (nom, ou [nom A, nom B, part de
##   B]) ; f : facteur de luminosité (l'architecture est plus sombre que le
##   décor) ; seed : graine ; wrap : première ligne répétée au-dessus de
##   l'image (murs) ; rough, metal : surface ; matte : sans reflet spéculaire
##   (plâtre, pierre, brique, tissu) ; glow : intensité des veines lumineuses ;
##   wall : surface de mur (planches de validation : ligne 0 en bas).
const BASE := {"tone": "concrete", "f": 0.5, "seed": 0, "wrap": 0, "rough": 0.9, "metal": 0.0,
	"matte": false, "glow": 0.0, "wall": false}

## clé -> réglages (voir BASE et chaque générateur).
const DEFS := {
	# Béton : dalles sciées au sol, banches et trous de tiges aux murs.
	"floor": {"gen": "concrete", "f": 0.44, "seed": 1, "slab": true, "cracks": 2, "oil": 0.0, "rough": 0.95},
	"concrete": {"gen": "concrete", "f": 0.52, "cracks": 2, "rough": 0.95},
	"concrete_dark": {"gen": "concrete", "f": 0.34, "seed": 3, "slab": true, "cracks": 2, "oil": 0.22, "rough": 0.95},
	"wall_concrete": {"gen": "concrete", "f": 0.5, "seed": 4, "cracks": 2, "matte": true, "wall": true, "rough": 0.95},
	# Carrelage : hôpital au sol, faïence de laboratoire aux murs, marbre.
	"tiles": {"gen": "tiles", "tone": "plaster", "f": 0.78, "rough": 0.55, "blood": 1, "missing": 0.025, "cracked": 0.04},
	"wall_lab": {"gen": "tiles", "tone": "porcelain", "f": 0.7, "seed": 5, "missing": 0.035, "cracked": 0.08,
		"frieze": 3, "frieze_tone": "enamel_green", "frieze_f": 0.85, "grime": true, "wrap": 32, "wall": true, "rough": 0.45},
	"marble": {"gen": "tiles", "tone": ["stone", "wood", 0.35], "f": 0.95, "seed": 6, "ts": 16, "missing": 0.0,
		"cracked": 0.1, "veins": true, "blood": 0, "rough": 0.4},
	# Planches : parquet du bunker, caisses, scène, bois sombre, planche grise.
	"wood": {"gen": "planks", "tone": "wood", "f": 0.5, "seed": 7, "bw": 4, "len": [20, 40], "rough": 0.85},
	"crate": {"gen": "planks", "tone": "wood", "f": 0.62, "seed": 8, "bw": 4, "len": [64, 64], "nails": true},
	"stage_wood": {"gen": "planks", "tone": "wood_dark", "f": 0.85, "seed": 9, "bw": 4, "len": [28, 48], "rough": 0.7},
	"parquet": {"gen": "planks", "tone": "wood", "f": 0.5, "seed": 10, "bw": 2, "len": [8, 8], "rough": 0.6},
	"dark_wood": {"gen": "planks", "tone": "wood_dark", "f": 0.45, "seed": 11, "bw": 4, "len": [24, 48], "rough": 0.6},
	"plank": {"gen": "planks", "tone": ["wood", "ash", 0.55], "f": 0.82, "seed": 12, "bw": 4, "len": [32, 64], "nails": true,
		"weathered": true, "rough": 0.92},
	# Tôle : plancher strié, tôle ondulée rouillée, acier, porte, fût peint, laiton.
	"metal": {"gen": "metal", "style": "tread", "tone": "metal_dark", "f": 0.9, "seed": 13, "rust": 0.18, "rough": 0.6, "metal": 0.5},
	"wall_rust": {"gen": "metal", "style": "ribs", "tone": "metal_dark", "f": 0.88, "seed": 14, "rust": 0.55, "rough": 0.65,
		"metal": 0.5, "wall": true},
	"steel": {"gen": "metal", "style": "plate", "tone": "steel", "f": 0.47, "seed": 15, "rust": 0.1, "pw": 32, "ph": 16,
		"rough": 0.5, "metal": 0.6},
	"door": {"gen": "metal", "style": "plate", "tone": "metal_dark", "f": 0.95, "seed": 16, "rust": 0.3, "pw": 16, "ph": 32,
		"rough": 0.55, "metal": 0.6},
	"barrel": {"gen": "metal", "style": "hoops", "tone": "medic_red", "f": 0.42, "seed": 17, "rust": 0.35, "rough": 0.6, "metal": 0.4},
	"brass": {"gen": "metal", "style": "plate", "tone": "brass", "f": 0.75, "seed": 18, "rust": 0.0, "pw": 32, "ph": 32,
		"rough": 0.35, "metal": 0.85},
	# Murs peints : soubassement, liseré, écailles, coulures, crasse au pied.
	"wall": {"gen": "painted_wall", "tone": "plaster", "f": 0.46, "paint": "tile_green", "pf": 0.42, "wrap": 32,
		"matte": true, "wall": true},
	"wall_green": {"gen": "painted_wall", "tone": ["plaster", "paint_olive", 0.3], "f": 0.5, "seed": 19,
		"paint": "enamel_green", "pf": 0.62, "wrap": 32, "matte": true, "wall": true},
	"wall_cell": {"gen": "painted_wall", "tone": ["plaster", "concrete", 0.5], "f": 0.42, "seed": 20,
		"paint": ["drum_blue", "concrete", 0.45], "pf": 0.5, "wrap": 32, "matte": true, "wall": true, "tally": true},
	"wall_loges": {"gen": "painted_wall", "tone": ["plaster", "wood", 0.35], "f": 0.55, "seed": 21,
		"paint": ["medic_red", "wood_dark", 0.5], "pf": 0.62, "wrap": 32, "matte": true, "wall": true},
	"plaster_theater": {"gen": "painted_wall", "tone": ["plaster", "tile_green", 0.3], "f": 0.44, "seed": 22,
		"paint": "paint_olive", "pf": 0.55, "wrap": 32, "matte": true, "wall": true},
	# Pierre à veines lumineuses (salle rituelle).
	"stone": {"gen": "stone", "tone": "stone", "f": 0.27, "seed": 23, "glow": 1.1, "veins": 2, "matte": true},
	"wall_ritual": {"gen": "stone", "tone": ["stone", "charred", 0.4], "f": 0.32, "seed": 24, "glow": 1.1, "veins": 2,
		"blood": true, "matte": true, "wall": true},
	# Plafonds : dalles suspendues, voûte, caissons.
	"ceiling": {"gen": "ceiling", "tone": "ash", "f": 0.4, "seed": 25, "ps": 16, "rough": 1.0},
	"vault_theater": {"gen": "ceiling", "tone": ["plaster", "ash", 0.5], "f": 0.36, "seed": 26, "ps": 32, "rough": 1.0},
	"ceiling_theater": {"gen": "ceiling", "tone": "wood_dark", "f": 0.48, "seed": 27, "ps": 16, "coffer": true, "rough": 1.0},
	# Moquettes et tissu.
	"carpet_red": {"gen": "carpet", "tone": "medic_red", "f": 0.42, "seed": 28, "accent": "brass", "af": 0.55, "rough": 1.0},
	"carpet_theater": {"gen": "carpet", "tone": ["case_grey", "drum_blue", 0.3], "f": 0.55, "seed": 29,
		"accent": "burlap", "af": 0.42, "rough": 1.0},
	"fabric": {"gen": "carpet", "tone": "burlap", "f": 0.58, "seed": 30, "weave": true, "matte": true, "rough": 1.0},
	# Lambris et papier peint (foyer, hall, salle).
	"wall_theater": {"gen": "wainscot", "tone": "medic_red", "f": 0.42, "seed": 31, "accent": "brass", "af": 0.45,
		"wood": "wood_dark", "wf": 0.8, "wrap": 32, "matte": true, "wall": true},
	"wall_lobby": {"gen": "wainscot", "tone": ["brass", "wood", 0.5], "f": 0.55, "seed": 32, "accent": "wood_dark", "af": 0.7,
		"wood": "wood_dark", "wf": 0.75, "wrap": 32, "matte": true, "wall": true},
	"wall_foyer": {"gen": "wainscot", "tone": "enamel_green", "f": 0.5, "seed": 33, "accent": "brass", "af": 0.42,
		"wood": "wood_dark", "wf": 0.8, "wrap": 32, "matte": true, "wall": true},
	# Briques, velours, pavés.
	"brick": {"gen": "brick", "tone": "brick", "f": 0.6, "seed": 34, "matte": true},
	"velvet": {"gen": "velvet", "tone": "medic_red", "f": 0.6, "seed": 35, "matte": true, "rough": 0.8},
	"cobble": {"gen": "cobble", "tone": "stone", "f": 0.42, "seed": 36},
}

## Teintes (sRGB) de tools/blender/voxel/voxel_lib.py DECOR_PALETTE, mêmes
## valeurs : l'architecture et le décor partagent une palette
## (tests/test_voxel_archi.gd relit voxel_lib.py pour les garder égales).
const PAL := {
	"wood": Color(0.52, 0.36, 0.22),
	"wood_dark": Color(0.33, 0.22, 0.13),
	"charred": Color(0.12, 0.10, 0.09),
	"ash": Color(0.36, 0.35, 0.34),
	"stone": Color(0.50, 0.48, 0.45),
	"concrete": Color(0.58, 0.57, 0.54),
	"plaster": Color(0.80, 0.80, 0.76),
	"burlap": Color(0.62, 0.54, 0.38),
	"steel": Color(0.55, 0.57, 0.59),
	"metal_dark": Color(0.24, 0.25, 0.26),
	"rust": Color(0.45, 0.25, 0.14),
	"case_grey": Color(0.28, 0.30, 0.31),
	"paint_olive": Color(0.36, 0.40, 0.31),
	"paint_white": Color(0.86, 0.86, 0.82),
	"medic_red": Color(0.72, 0.10, 0.10),
	"hazard_yellow": Color(0.88, 0.70, 0.12),
	"tile_green": Color(0.56, 0.68, 0.62),
	"brass": Color(0.66, 0.50, 0.22),
	"drum_blue": Color(0.21, 0.37, 0.58),
	"porcelain": Color(0.86, 0.84, 0.78),
	"enamel_green": Color(0.27, 0.45, 0.40),
	"brick": Color(0.56, 0.27, 0.17),
}

static var _images: Dictionary = {}
static var _mats: Dictionary = {}
static var _matte_shader: Shader
## Treillis de blotch() déjà calculés (petits : au plus 64 valeurs).
static var _lattices: Dictionary = {}
## Temps passé à générer les images (µs) et nombre d'images générées depuis
## le lancement (mesure du coût au chargement d'une carte).
static var gen_usec := 0
static var gen_count := 0


static func has(key: String) -> bool:
	return DEFS.has(key)


## Réglages complets d'une clé (BASE surchargé par DEFS).
static func def(key: String) -> Dictionary:
	var d := BASE.duplicate()
	d.merge(DEFS[key], true)
	return d


## Clés dont le matériau est déjà créé (mesures de perf_costs).
static func loaded_keys() -> Array:
	return _mats.keys()


## Teinte de la palette (sRGB) multipliée par `f`.
static func pal(name: String, f := 1.0) -> Color:
	var c: Color = PAL[name]
	return Color(clampf(c.r * f, 0.0, 1.0), clampf(c.g * f, 0.0, 1.0), clampf(c.b * f, 0.0, 1.0))


## Teinte d'un réglage : nom de PAL ou [nom A, nom B, part de B], × `f`.
static func tone(spec: Variant, f := 1.0) -> Color:
	if spec is Array:
		var a := pal(String(spec[0]))
		var c := a.lerp(pal(String(spec[1])), float(spec[2]))
		return Color(clampf(c.r * f, 0.0, 1.0), clampf(c.g * f, 0.0, 1.0), clampf(c.b * f, 0.0, 1.0))
	return pal(String(spec), f)


## Luminance (approchée, sRGB) d'une couleur.
static func lum(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


## `c` mise à la luminance de `ref` × `k` (salissures, rouille, sang : même
## valeur relative sur un béton clair ou sombre).
static func like(c: Color, ref: Color, k := 1.0) -> Color:
	var s := lum(ref) * k / maxf(lum(c), 0.001)
	return Color(clampf(c.r * s, 0.0, 1.0), clampf(c.g * s, 0.0, 1.0), clampf(c.b * s, 0.0, 1.0))


## Bruit entier déterministe 0..1 d'une cellule (même hachage que
## voxel_lib.noise : reproductible).
static func noise(x: int, y: int, seed := 0) -> float:
	var h := (x * 73856093) ^ (y * 19349663) ^ (seed * 83492791)
	h &= 0xFFFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
	return float((h ^ (h >> 16)) & 0xFFFF) / 65535.0


## Bruit de valeur par blocs de `cell` pixels (taches, marbrures), répété
## sans couture sur une image de `w` × `h` : interpolation bilinéaire des
## nœuds, 0..1.
static func blotch(x: int, y: int, cell: int, w: int, h: int, seed: int) -> float:
	var nx := maxi(1, w / cell)
	var ny := maxi(1, h / cell)
	# Nœuds du treillis calculés une fois par (cellule, taille, graine) :
	# quatre lectures au lieu de quatre hachages par pixel.
	var lk := Vector4i(cell, nx, ny, seed)
	var lat: PackedFloat32Array = _lattices.get(lk, PackedFloat32Array())
	if lat.is_empty():
		lat.resize(nx * ny)
		for j in ny:
			for i in nx:
				lat[j * nx + i] = noise(i, j, seed)
		_lattices[lk] = lat
	var fx := float(x) / cell
	var fy := float(y) / cell
	var x0 := int(floor(fx))
	var y0 := int(floor(fy))
	var tx := fx - x0
	var ty := fy - y0
	var i0 := posmod(x0, nx)
	var i1 := posmod(x0 + 1, nx)
	var j0 := posmod(y0, ny) * nx
	var j1 := posmod(y0 + 1, ny) * nx
	return lerpf(lerpf(lat[j0 + i0], lat[j0 + i1], tx), lerpf(lat[j1 + i0], lat[j1 + i1], tx), ty)


## Palier de bruit par pixel : `levels` teintes de -amp à +amp (texture
## « un pixel = un cube », comme voxel_lib C.fill).
static func grain(x: int, y: int, seed: int, amp: float, levels := 3) -> float:
	var k := mini(levels - 1, int(noise(x, y, seed) * levels))
	return 1.0 + amp * (2.0 * k / maxf(1.0, levels - 1.0) - 1.0)


static func image(key: String) -> Image:
	if _images.has(key):
		return _images[key]
	var t0 := Time.get_ticks_usec()
	var d := def(key)
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 1))
	match String(d.gen):
		"concrete":
			_concrete(img, d)
		"tiles":
			_tiles(img, d)
		"planks":
			_planks(img, d)
		"metal":
			_metal(img, d)
		"painted_wall":
			_painted_wall(img, d)
		"stone":
			_stone(img, d)
		"ceiling":
			_ceiling(img, d)
		"carpet":
			_carpet(img, d)
		"wainscot":
			_wainscot(img, d)
		"brick":
			_brick(img, d)
		"velvet":
			_velvet(img, d)
		"cobble":
			_cobble(img, d)
	_images[key] = img
	gen_usec += Time.get_ticks_usec() - t0
	gen_count += 1
	return img


static func texture(key: String) -> ImageTexture:
	var img := image(key).duplicate() as Image
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Shader d'une clé : variante sans reflet spéculaire pour les matières mates
## (invisible sur ces matières et moins cher, perf_costs).
static func shader_for(key: String) -> Shader:
	if not bool(def(key).matte):
		return SHADER
	if _matte_shader == null:
		_matte_shader = Shader.new()
		_matte_shader.code = SHADER.code.replace("render_mode cull_back;", "render_mode cull_back, specular_disabled;")
		assert(_matte_shader.code != SHADER.code, "pixel_surface.gdshader : render_mode introuvable")
	return _matte_shader


## Matériau d'une clé (mis en cache, partagé par toutes les cartes).
static func material(key: String) -> ShaderMaterial:
	if _mats.has(key):
		return _mats[key]
	var d := def(key)
	var m := ShaderMaterial.new()
	m.shader = shader_for(key)
	m.set_shader_parameter("albedo_tex", texture(key))
	m.set_shader_parameter("size_px", Vector2(SIZE, SIZE))
	m.set_shader_parameter("wrap_px", float(d.wrap))
	m.set_shader_parameter("roughness_base", float(d.rough))
	m.set_shader_parameter("metallic_base", float(d.metal))
	m.set_shader_parameter("glow", float(d.glow))
	_mats[key] = m
	return m


# ------------------------------------------------------------------ générateurs

@warning_ignore_start("integer_division")


static func _put(img: Image, x: int, y: int, c: Color, glow := 0.0) -> void:
	img.set_pixel(posmod(x, img.get_width()), posmod(y, img.get_height()), Color(c.r, c.g, c.b, 1.0 - glow))


static func _px(img: Image, x: int, y: int) -> Color:
	return img.get_pixel(posmod(x, img.get_width()), posmod(y, img.get_height()))


## Coupes d'une rangée (planches, pierres) : positions (0..w) des joints, la
## suite répétée sans couture sur `w` ; longueurs entre lo et hi.
static func _cuts(row: int, w: int, lo: int, hi: int, seed: int) -> Array:
	var out := []
	var x := int(noise(row, 1, seed) * w)
	var end := x + w
	var i := 0
	while x < end:
		out.append(posmod(x, w))
		var span := lo + int(noise(row, 10 + i, seed) * (hi - lo + 1))
		span = mini(span, hi)
		# Dernier morceau trop court : fondu avec le précédent.
		if end - (x + span) < lo:
			break
		x += span
		i += 1
	out.sort()
	return out


## Indice du morceau qui contient `x` dans une rangée coupée en `cuts`.
static func _piece(cuts: Array, x: int) -> int:
	var k := -1
	for i in cuts.size():
		if x >= int(cuts[i]):
			k = i
	return k if k >= 0 else cuts.size() - 1


## Fissures : marches de pixels sombres (diagonale « pixel »).
static func _cracks(img: Image, n: int, seed: int, dark: float) -> void:
	for k in n:
		var x := int(noise(k, 1, seed) * img.get_width())
		var y := int(noise(k, 2, seed) * img.get_height())
		var length := 6 + int(noise(k, 3, seed) * 8)
		var dx := 1 if noise(k, 4, seed) > 0.5 else -1
		for i in length:
			_put(img, x, y, _px(img, x, y) * dark)
			if noise(i, k, seed + 7) > 0.45:
				x += dx
			else:
				y += 1


## Sang séché (brun-rouge sombre) : une tache de 3 × 3 pixels aux coins
## rongés et quelques gouttes autour.
static func _blood(img: Image, n: int, seed: int, ref: Color) -> void:
	var blood := like(pal("medic_red").lerp(pal("wood_dark"), 0.45), ref, 0.38)
	for k in n:
		var x := int(noise(k, 5, seed) * img.get_width())
		var y := int(noise(k, 6, seed) * img.get_height())
		for j in range(-1, 2):
			for i in range(-1, 2):
				if absi(i) + absi(j) < 2 or noise(i, j, seed + k) > 0.6:
					_put(img, x + i, y + j, blood * (0.85 + 0.2 * noise(x + i, y + j, seed + 8)))
		for i in 4:
			var dx := int(noise(i, k, seed + 12) * 7.0) - 3
			var dy := int(noise(i, k, seed + 16) * 7.0) - 3
			if absi(dx) + absi(dy) >= 3:
				_put(img, x + dx, y + dy, blood * 1.1)


## Crasse au pied d'un mur : trois paliers (0 à 15 cm, à 30, à 45).
static func _grime(img: Image, seed: int) -> void:
	for y in 9:
		for x in img.get_width():
			var k := 0.62 if y < 3 else (0.76 if y < 6 else (0.88 if noise(x, y, seed + 79) > 0.4 else 1.0))
			if k < 1.0:
				_put(img, x, y, _px(img, x, y) * k)


## Béton : marbrures par blocs, grain à trois paliers, taches d'humidité,
## fissures en escalier. `slab` : dalles sciées de 1,6 m (sols) ; sinon
## banches de 1,6 m (joint sombre d'un pixel) et trous de tiges de coffrage ;
## `oil` : taches d'huile (sols de garage).
static func _concrete(img: Image, d: Dictionary) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var s := int(d.seed) * 101
	var base := tone(d.tone, float(d.f))
	var damp := base * Color(0.86, 0.93, 0.84)
	var slab := bool(d.get("slab", false))
	var oil := float(d.get("oil", 0.0))
	for y in h:
		for x in w:
			var m := blotch(x, y, 8, w, h, s + 11)
			var c := base * grain(x, y, s + 3, 0.05) * (0.94 + 0.12 * snappedf(m, 0.25))
			if blotch(x, y, 16, w, h, s + 29) > 0.72:
				c = c.lerp(damp, 0.6)
			if oil > 0.0 and blotch(x, y, 8, w, h, s + 37) > 1.0 - oil:
				c = c * 0.72
			if slab:
				if x % 32 == 31 or y % 32 == 31:
					c = c * 0.74
			elif y % 32 == 31:
				c = c * 0.72
			elif y % 32 == 15 and x % 16 == 7:
				c = like(pal("charred"), base, 0.5)
			_put(img, x, y, c)
	_cracks(img, int(d.get("cracks", 2)), s + 41, 0.68)


## Carrelage : carreaux de `ts` pixels (joint d'un pixel compris), teinte par
## carreau, coins salis, carreaux fêlés ou manquants (béton dessous), sang
## séché. Murs : `frieze` (rangée de carreaux de couleur), crasse au pied.
## `veins` : marbre (veines claires en escalier).
static func _tiles(img: Image, d: Dictionary) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var s := int(d.seed) * 101
	var ts := int(d.get("ts", 8))
	var tile := tone(d.tone, float(d.f))
	var grout := like(pal("concrete"), tile, 0.62)
	var under := like(pal("concrete"), tile, 0.42)
	var frieze := int(d.get("frieze", -1))
	var ftile := tone(d.get("frieze_tone", "enamel_green"), float(d.get("frieze_f", 0.8)))
	var missing := float(d.get("missing", 0.045))
	var cracked := float(d.get("cracked", 0.07))
	var veins := bool(d.get("veins", false))
	for y in h:
		for x in w:
			var tx := x / ts
			var ty := y / ts
			var lx := x % ts
			var ly := y % ts
			var c: Color
			if lx == ts - 1 or ly == ts - 1:
				c = grout * grain(x, y, s + 5, 0.06, 2)
			else:
				var base := ftile if ty == frieze else tile
				c = base * (0.93 + 0.1 * snappedf(noise(tx, ty, s + 13), 0.34)) * grain(x, y, s + 7, 0.02, 2)
				# Saleté des coins (pixels du bord, un sur deux).
				if (lx == 0 or ly == 0 or lx == ts - 2 or ly == ts - 2) and noise(x, y, s + 17) > 0.6:
					c = c * 0.9
				if veins and blotch(x + y, y - x, 6, w, h, s + 27) > 0.78:
					c = c * 1.12
				var r := noise(tx, ty, s + 19)
				if r > 1.0 - missing:
					c = under * grain(x, y, s + 23, 0.08)
				elif r > 1.0 - missing - cracked:
					if lx == ly:
						c = c * 0.68
			_put(img, x, y, c)
	_blood(img, int(d.get("blood", 0)), s + 31, tile)
	if bool(d.get("grime", false)):
		_grime(img, s)


## Planches : lames de `bw` pixels de large, joints sombres, longueurs de
## `len` [min, max] pixels décalées d'une rangée à l'autre, teinte par lame,
## veinage en tirets, nœuds ; `nails` : clous aux bouts ; `weathered` : bois
## gris fendu (planches de barricade).
static func _planks(img: Image, d: Dictionary) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var s := int(d.seed) * 101
	var bw := int(d.bw)
	var lens: Array = d.get("len", [24, 40])
	var base := tone(d.tone, float(d.f))
	var weathered := bool(d.get("weathered", false))
	var nails := bool(d.get("nails", false))
	var nail := like(pal("steel"), base, 0.9)
	for row in h / bw:
		var cuts := _cuts(row, w, int(lens[0]), int(lens[1]), s + 3)
		for x in w:
			var k := _piece(cuts, x)
			var board := base * (0.88 + 0.08 * int(noise(row * 7 + k, 3, s + 5) * 3.0))
			for j in bw:
				var y := row * bw + j
				var c := board * grain(x, y, s + 9, 0.025, 2)
				# Veinage : tirets de 3 pixels plus sombres.
				if noise(x / 3, y, s + 11 + k) > 0.8:
					c = c * 0.9
				if noise(x, y, s + 13) > 0.996:
					c = c * 0.6
				if weathered and j == bw / 2 and noise(x / 4, row, s + 15) > 0.7:
					c = c * 0.7
				if j == bw - 1:
					c = board * 0.58
				elif x == int(cuts[k]):
					c = board * 0.62
				elif nails and bw >= 3 and j == bw / 2 - (1 if bw >= 4 else 0) and (x == posmod(int(cuts[k]) + 2, w) or x == posmod(int(cuts[(k + 1) % cuts.size()]) - 2, w)):
					c = nail
				_put(img, x, y, c)


## Tôle : `style` « plate » (panneaux de `pw` × `ph` pixels, joints et
## rivets), « tread » (tôle striée de plancher), « ribs » (tôle ondulée,
## ondes verticales de 20 cm), « hoops » (fût : cerclages) ; rouille par
## taches et coulures sous les rivets (`rust` 0..1).
static func _metal(img: Image, d: Dictionary) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var s := int(d.seed) * 101
	var base := tone(d.tone, float(d.f))
	# Rouille brune (pas rouge sang) : mêlée au métal, un peu plus sombre.
	var rust := like(pal("rust").lerp(pal("wood_dark"), 0.35), base, 0.85)
	var ramt := float(d.get("rust", 0.2))
	var style := String(d.get("style", "plate"))
	var pw := int(d.get("pw", 32))
	var ph := int(d.get("ph", 16))
	for y in h:
		for x in w:
			var c := base * grain(x, y, s + 3, 0.03, 2) * (0.96 + 0.06 * snappedf(blotch(x, y, 16, w, h, s + 5), 0.5))
			match style:
				"plate":
					if x % pw == pw - 1 or y % ph == ph - 1:
						c = c * 0.6
					elif (x % pw == 1 or x % pw == pw - 3) and y % 4 == 1:
						c = c * 1.3
					elif (x % pw == 1 or x % pw == pw - 3) and y % 4 == 0:
						c = c * 0.75
				"tread":
					# Losanges en relief alternés (dessus clair, ombre portée).
					var lx := posmod(x + (y / 4 % 2) * 2, 4)
					var ly := y % 4
					if lx == 0 and ly == 0:
						c = c * 1.28
					elif lx == 1 and ly == 1:
						c = c * 0.78
					if x % 32 == 31 or y % 32 == 31:
						c = c * 0.62
				"ribs":
					c = c * [1.12, 1.02, 0.84, 0.94][x % 4]
					if y % 32 == 31:
						c = c * 0.7
				"hoops":
					var ly := y % 16
					if ly == 0:
						c = c * 1.25
					elif ly == 1:
						c = c * 0.7
			if ramt > 0.0 and blotch(x, y, 8, w, h, s + 7) > 1.0 - ramt * 0.5:
				c = c.lerp(rust * grain(x, y, s + 9, 0.06, 2), 0.6)
			_put(img, x, y, c)
	# Coulures de rouille (vers le bas d'un mur : lignes décroissantes).
	if ramt > 0.0:
		for k in int(4 + ramt * 10):
			var x := int(noise(k, 31, s) * w)
			var y := int(noise(k, 32, s) * h)
			var length := 3 + int(noise(k, 33, s) * 8)
			for i in length:
				_put(img, x, y - i, _px(img, x, y - i).lerp(rust, 0.6 - 0.04 * i))


## Mur peint : soubassement de `band` pixels (1,25 m) au bord écaillé,
## liseré sombre, plâtre au-dessus, coulures d'eau, crasse au pied ;
## `tally` : bâtons comptés au mur (cellule).
static func _painted_wall(img: Image, d: Dictionary) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var s := int(d.seed) * 101
	var plaster := tone(d.tone, float(d.f))
	var paint := tone(d.paint, float(d.pf))
	var band := int(d.get("band", 25))
	for x in w:
		# Bord de peinture irrégulier : 0 ou 1 pixel au-dessus de la bande.
		var edge := band + (1 if noise(x / 2, 0, s + 53) > 0.6 else 0)
		# Coulure : une colonne sur quinze environ, du haut de l'image vers le bas.
		var streak_from := h - 4 - int(noise(x, 1, s + 59) * 24.0) if noise(x, 0, s + 59) > 0.93 else h
		for y in h:
			var c: Color
			if y < edge:
				c = paint * grain(x, y, s + 61, 0.025, 2)
				# Écailles : plâtre visible (quelques plaques).
				if blotch(x, y, 8, w, h, s + 67) > 0.8:
					c = plaster * 0.9
			elif y == edge:
				c = paint * 0.55
			else:
				c = plaster * grain(x, y, s + 71, 0.025, 2) * (0.96 + 0.06 * snappedf(blotch(x, y, 8, w, h, s + 73), 0.5))
			if y >= streak_from:
				c = c * 0.88
			_put(img, x, y, c)
	if bool(d.get("tally", false)):
		# Cinq bâtons (quatre traits et une barre) vers 1,6 m.
		var dark := plaster * 0.5
		var x0 := 6 + int(noise(0, 3, s) * 40)
		var y0 := 31
		for i in 4:
			for j in 5:
				_put(img, x0 + i * 2, y0 + j, dark)
		for i in 8:
			_put(img, x0 - 1 + i, y0 + 1 + i / 2, dark)
	_grime(img, s)


## Pierre : assises de 8 pixels (40 cm), blocs de 8 à 16 pixels décalés,
## joints sombres, ombrage peint (arête du haut claire, du bas sombre), veines
## LUMINEUSES (lueur dans l'alpha) ; `blood` : taches de sang séché.
static func _stone(img: Image, d: Dictionary) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var s := int(d.seed) * 101
	var base := tone(d.tone, float(d.f))
	var mortar := base * 0.45
	for row in h / 8:
		var cuts := _cuts(row, w, 8, 16, s + 3)
		for x in w:
			var k := _piece(cuts, x)
			var block := base * (0.86 + 0.08 * int(noise(row * 13 + k, 5, s + 5) * 4.0))
			for j in 8:
				var y := row * 8 + j
				var c := block * grain(x, y, s + 7, 0.04)
				if j == 7 or x == int(cuts[k]):
					c = mortar * grain(x, y, s + 9, 0.08, 2)
				elif j == 6:
					c = c * 1.1
				elif j == 0:
					c = c * 0.85
				_put(img, x, y, c)
	if bool(d.get("blood", false)):
		var blood := like(pal("medic_red"), base, 0.7)
		for y in h:
			for x in w:
				if blotch(x, y, 8, w, h, s + 13) > 0.86:
					_put(img, x, y, _px(img, x, y).lerp(blood, 0.55))
	# Veines : marches de pixels lumineuses (rouge braise).
	var vein := like(pal("medic_red"), base, 1.15)
	for k in int(d.get("veins", 3)):
		var x := int(noise(k, 1, s + 17) * w)
		var y := int(noise(k, 2, s + 17) * h)
		var dx := 1 if noise(k, 4, s + 17) > 0.5 else -1
		for i in 10 + int(noise(k, 3, s + 17) * 8):
			_put(img, x, y, vein, 0.6 + 0.4 * noise(i, k, s + 19))
			if noise(i, k, s + 23) > 0.5:
				x += dx
			else:
				y += 1


## Dalles de plafond : panneaux de `ps` pixels, ossature d'un pixel, teinte
## par dalle, auréoles d'humidité, dalles tombées (trou noir) ; `coffer` :
## caissons à cadre clair.
static func _ceiling(img: Image, d: Dictionary) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var s := int(d.seed) * 101
	var ps := int(d.get("ps", 16))
	var base := tone(d.tone, float(d.f))
	var stain := like(pal("rust"), base, 0.7)
	var coffer := bool(d.get("coffer", false))
	for y in h:
		for x in w:
			var px := x / ps
			var py := y / ps
			var lx := x % ps
			var ly := y % ps
			var r := noise(px, py, s + 3)
			var c := base * (0.92 + 0.08 * snappedf(r, 0.5)) * grain(x, y, s + 5, 0.03, 2)
			if blotch(x, y, 8, w, h, s + 7) > 0.76:
				c = c.lerp(stain, 0.5)
			if lx == ps - 1 or ly == ps - 1:
				c = base * 0.55
			elif coffer and (lx == 0 or ly == 0 or lx == ps - 2 or ly == ps - 2):
				c = base * 1.18
			elif r > 0.975:
				c = base * 0.15
			_put(img, x, y, c)


## Moquette : trame à deux paliers, losanges d'une teinte d'accent tous les
## 80 cm, usure par taches, taches sombres ; `weave` : tissu à rayures de
## trame, sans motif.
static func _carpet(img: Image, d: Dictionary) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var s := int(d.seed) * 101
	var base := tone(d.tone, float(d.f))
	var accent := tone(d.get("accent", "brass"), float(d.get("af", 0.5)))
	var weave := bool(d.get("weave", false))
	for y in h:
		for x in w:
			var c := base * grain(x, y, s + 3, 0.03, 2)
			if weave:
				c = c * (1.04 if (y / 2) % 2 == 0 else 0.96)
			else:
				var a := posmod(x + y, 16)
				var b := posmod(x - y, 16)
				if a == 0 or b == 0:
					c = accent * grain(x, y, s + 5, 0.04, 2)
				elif (a == 8 and b == 8):
					c = accent * 1.1
			# Usure (passages) et taches sombres.
			var m := blotch(x, y, 16, w, h, s + 7)
			if m > 0.72:
				c = c * 0.86
			if blotch(x, y, 8, w, h, s + 9) > 0.85:
				c = c * 0.7
			_put(img, x, y, c)


## Lambris et papier peint : plinthe sombre, panneaux de bois moulurés de
## 80 cm jusqu'à 1 m (20 pixels), cimaise claire, papier peint à rayures et
## petits losanges d'accent, lambeaux arrachés (plâtre), coulures.
static func _wainscot(img: Image, d: Dictionary) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var s := int(d.seed) * 101
	var paper := tone(d.tone, float(d.f))
	var accent := tone(d.get("accent", "brass"), float(d.get("af", 0.5)))
	var wood := tone(d.get("wood", "wood_dark"), float(d.get("wf", 0.8)))
	var plaster := like(pal("plaster"), paper, 1.25)
	for x in w:
		var streak_from := h - 4 - int(noise(x, 1, s + 59) * 20.0) if noise(x, 0, s + 59) > 0.94 else h
		for y in h:
			var c: Color
			var lx := x % 16
			if y < 2:
				c = wood * 0.6
			elif y < 18:
				# Panneau mouluré : cadre (montants, traverses) et creux.
				c = wood * grain(x, y, s + 3, 0.03, 2)
				if lx == 0 or lx == 15 or y == 2 or y == 17:
					c = c * 1.12
				elif lx == 1 or y == 16:
					c = c * 0.72
				elif noise(x / 3, y, s + 5) > 0.85:
					c = c * 0.92
			elif y < 20:
				c = wood * (1.2 if y == 19 else 0.95)
			elif y == 20:
				c = paper * 0.55
			else:
				c = paper * grain(x, y, s + 7, 0.02, 2)
				var mx := x % 8
				var my := y % 8
				if mx == 0:
					c = c * 0.86
				elif (mx == 4 and (my == 3 or my == 5)) or (my == 4 and (mx == 3 or mx == 5)):
					c = accent
				if blotch(x, y, 8, w, h, s + 9) > 0.8:
					c = plaster * grain(x, y, s + 11, 0.05)
				if y >= streak_from:
					c = c * 0.86
			_put(img, x, y, c)
	_grime(img, s)


## Briques : assises de 4 pixels (3 de brique, 1 de joint), briques de
## 8 pixels décalées d'une demi-brique, teinte par brique, briques noircies,
## arête du haut éclairée, éclats (joint visible).
static func _brick(img: Image, d: Dictionary) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var s := int(d.seed) * 101
	var base := tone(d.tone, float(d.f))
	var mortar := like(pal("concrete"), base, 0.9)
	for y in h:
		var row := y / 4
		var off := (row % 2) * 4
		for x in w:
			var bx := posmod(x + off, w) / 8
			var c: Color
			if y % 4 == 3 or posmod(x + off, 8) == 7:
				c = mortar * grain(x, y, s + 3, 0.06, 2)
			else:
				var r := noise(bx, row, s + 5)
				c = base * (0.86 + 0.08 * int(r * 4.0)) * grain(x, y, s + 7, 0.04, 2)
				if noise(bx, row, s + 9) > 0.86:
					c = c * 0.62
				if y % 4 == 2:
					c = c * 1.08
				if noise(x, y, s + 11) > 0.985:
					c = mortar * 0.8
			_put(img, x, y, c)


## Velours : plis verticaux de 8 pixels (40 cm), ombrage peint par colonne,
## poussière par taches.
static func _velvet(img: Image, d: Dictionary) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var s := int(d.seed) * 101
	var base := tone(d.tone, float(d.f))
	var folds := [0.62, 0.78, 0.94, 1.06, 1.1, 1.0, 0.86, 0.7]
	for y in h:
		for x in w:
			var c := base * float(folds[x % 8]) * grain(x, y, s + 3, 0.025, 2)
			if blotch(x, y, 16, w, h, s + 5) > 0.75:
				c = c * 0.88
			_put(img, x, y, c)


## Pavés : pavés de 8 pixels (40 cm, joint compris) en rangées décalées, coins
## arrondis en escalier, bombés (bord haut clair, bas sombre), teinte par
## pavé, terre dans les joints.
static func _cobble(img: Image, d: Dictionary) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var s := int(d.seed) * 101
	var base := tone(d.tone, float(d.f))
	var dirt := like(tone(["charred", "wood_dark", 0.5]), base, 0.45)
	for y in h:
		var row := y / 8
		var off := (row % 2) * 4
		for x in w:
			var lx := posmod(x + off, 8)
			var ly := y % 8
			var cx := posmod(x + off, w) / 8
			var c: Color
			var corner := (lx == 0 or lx == 6) and (ly == 0 or ly == 6)
			if lx == 7 or ly == 7 or corner:
				c = dirt * grain(x, y, s + 3, 0.08, 2)
			else:
				c = base * (0.84 + 0.08 * int(noise(cx, row, s + 5) * 4.0)) * grain(x, y, s + 7, 0.04, 2)
				if ly == 0 or lx == 0:
					c = c * 1.12
				elif ly == 6 or lx == 6:
					c = c * 0.8
			_put(img, x, y, c)


@warning_ignore_restore("integer_division")
