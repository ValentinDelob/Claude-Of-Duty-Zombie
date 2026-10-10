class_name PixelSurfaces
extends RefCounted
## Textures « PIXEL ART » de l'architecture (GAME_CONCEPT.md § 4.19,
## docs/VOXEL_ARCHITECTURE_PLAN.md) : un pixel de texture = un cube de décor de
## 5 cm (20 pixels par mètre), couleurs unies par pixel, filtrage au plus
## proche. Chaque image est GÉNÉRÉE ici (aucun fichier, déterministe : même
## image à chaque lancement, sur chaque machine) d'après les teintes de
## voxel_lib.DECOR_PALETTE (PAL), puis posée en coordonnées MONDE
## par assets/shaders/pixel_surface.gdshader : les pixels tombent sur la
## grille de 5 cm du monde, sans étirement ni couture d'un morceau à l'autre.
##
## Mêmes clés que WorldLook.SURFACES (une carte existante se charge telle
## quelle) : WorldLook.surface(clé) rend la version pixel si la clé est ici.
## Pilote : béton, carrelage d'hôpital, mur peint ; les autres clés gardent
## surface.gdshader jusqu'à leur lot (plan, lot C).
##
## Murs : la ligne 0 de l'image est au sol de la salle (floor_y), la ligne k à
## k × 5 cm au-dessus ; au-delà de la hauteur de l'image, les lignes
## [wrap, hauteur) se répètent (le soubassement peint ne revient pas en haut
## d'un grand mur). Sols et plafonds : x vers l'est, y vers le sud.

const PX_PER_M := 20
const CELL := 1.0 / PX_PER_M
const SHADER := preload("res://assets/shaders/pixel_surface.gdshader")

## clé -> {gen : générateur, w, h : taille de l'image (px), wrap : première
## ligne répétée au-dessus de l'image (murs), rough, metal}.
const DEFS := {
	"concrete": {"gen": "concrete", "w": 64, "h": 64, "wrap": 0, "rough": 0.95, "metal": 0.0},
	"tiles": {"gen": "tiles", "w": 64, "h": 64, "wrap": 0, "rough": 0.55, "metal": 0.0},
	"wall": {"gen": "painted_wall", "w": 64, "h": 64, "wrap": 32, "rough": 0.9, "metal": 0.0},
}

static var _images: Dictionary = {}
static var _mats: Dictionary = {}


static func has(key: String) -> bool:
	return DEFS.has(key)


## Teintes (sRGB) de tools/blender/voxel/voxel_lib.py DECOR_PALETTE, mêmes
## valeurs : l'architecture et le décor partagent une palette.
const PAL := {
	"charred": Color(0.12, 0.10, 0.09),
	"concrete": Color(0.58, 0.57, 0.54),
	"plaster": Color(0.80, 0.80, 0.76),
	"paint_olive": Color(0.36, 0.40, 0.31),
	"paint_white": Color(0.86, 0.86, 0.82),
	"medic_red": Color(0.72, 0.10, 0.10),
	"tile_green": Color(0.56, 0.68, 0.62),
	"rust": Color(0.45, 0.25, 0.14),
}


## Teinte de la palette (sRGB) multipliée par `f`.
static func pal(name: String, f := 1.0) -> Color:
	var c: Color = PAL[name]
	return Color(clampf(c.r * f, 0.0, 1.0), clampf(c.g * f, 0.0, 1.0), clampf(c.b * f, 0.0, 1.0))


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
	var fx := float(x) / cell
	var fy := float(y) / cell
	var x0 := int(floor(fx))
	var y0 := int(floor(fy))
	var tx := fx - x0
	var ty := fy - y0
	var a := noise(posmod(x0, nx), posmod(y0, ny), seed)
	var b := noise(posmod(x0 + 1, nx), posmod(y0, ny), seed)
	var c := noise(posmod(x0, nx), posmod(y0 + 1, ny), seed)
	var d := noise(posmod(x0 + 1, nx), posmod(y0 + 1, ny), seed)
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), ty)


## Palier de bruit par pixel : `levels` teintes de -amp à +amp (texture
## « un pixel = un cube », comme voxel_lib C.fill).
static func grain(x: int, y: int, seed: int, amp: float, levels := 3) -> float:
	var k := mini(levels - 1, int(noise(x, y, seed) * levels))
	return 1.0 + amp * (2.0 * k / maxf(1.0, levels - 1.0) - 1.0)


static func image(key: String) -> Image:
	if _images.has(key):
		return _images[key]
	var d: Dictionary = DEFS[key]
	var img := Image.create(int(d.w), int(d.h), false, Image.FORMAT_RGB8)
	match String(d.gen):
		"concrete":
			_concrete(img)
		"tiles":
			_tiles(img)
		"painted_wall":
			_painted_wall(img)
	_images[key] = img
	return img


static func texture(key: String) -> ImageTexture:
	var img := image(key).duplicate() as Image
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Matériau d'une clé (mis en cache, partagé par toutes les cartes).
static func material(key: String) -> ShaderMaterial:
	if _mats.has(key):
		return _mats[key]
	var d: Dictionary = DEFS[key]
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("albedo_tex", texture(key))
	m.set_shader_parameter("size_px", Vector2(float(d.w), float(d.h)))
	m.set_shader_parameter("wrap_px", float(d.wrap))
	m.set_shader_parameter("roughness_base", float(d.rough))
	m.set_shader_parameter("metallic_base", float(d.metal))
	_mats[key] = m
	return m


# ------------------------------------------------------------------ générateurs

static func _put(img: Image, x: int, y: int, c: Color) -> void:
	img.set_pixel(posmod(x, img.get_width()), posmod(y, img.get_height()), c)


## Béton de bunker : banches de 1,6 m (joint sombre d'un pixel, trous de
## tiges de coffrage), marbrures par blocs, grain à trois paliers, fissures
## en escalier de pixels, taches d'humidité.
static func _concrete(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var base := pal("concrete", 0.52)
	for y in h:
		for x in w:
			var m := blotch(x, y, 8, w, h, 11)
			var f := grain(x, y, 3, 0.05) * (0.94 + 0.12 * snappedf(m, 0.25))
			var c := base * f
			# Taches d'humidité (sombres, un peu vertes).
			if blotch(x, y, 16, w, h, 29) > 0.72:
				c = c.lerp(pal("paint_olive", 0.35), 0.25)
			# Joints de banche tous les 32 pixels (1,6 m) et trous de tiges.
			if y % 32 == 31:
				c = c * 0.72
			elif y % 32 == 15 and x % 16 == 7:
				c = pal("charred", 1.4)
			img.set_pixel(x, y, Color(c.r, c.g, c.b))
	_cracks(img, 3, 41, 0.6)


## Fissures : marches de pixels sombres (diagonale « pixel »).
static func _cracks(img: Image, n: int, seed: int, dark: float) -> void:
	for k in n:
		var x := int(noise(k, 1, seed) * img.get_width())
		var y := int(noise(k, 2, seed) * img.get_height())
		var len := 8 + int(noise(k, 3, seed) * 14)
		var dx := 1 if noise(k, 4, seed) > 0.5 else -1
		for i in len:
			var c := img.get_pixel(posmod(x, img.get_width()), posmod(y, img.get_height()))
			_put(img, x, y, c * dark)
			if noise(i, k, seed + 7) > 0.45:
				x += dx
			else:
				y += 1


## Carrelage d'hôpital : carreaux de 40 cm (7 pixels + joint d'un pixel),
## blanc cassé jauni, teinte par carreau, carreaux fêlés ou manquants (béton
## dessous), traînées de sang séché.
static func _tiles(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var tile := pal("plaster", 0.78)
	var grout := pal("concrete", 0.4)
	var under := pal("concrete", 0.36)
	for y in h:
		for x in w:
			var tx := x / 8
			var ty := y / 8
			var c: Color
			if x % 8 == 7 or y % 8 == 7:
				c = grout * grain(x, y, 5, 0.06, 2)
			else:
				var t := 0.92 + 0.12 * noise(tx, ty, 13)
				c = tile * t * grain(x, y, 7, 0.025, 2)
				# Saleté des coins (pixels du bord, un sur deux).
				if (x % 8 == 0 or y % 8 == 0 or x % 8 == 6 or y % 8 == 6) and noise(x, y, 17) > 0.55:
					c = c * 0.88
				var r := noise(tx, ty, 19)
				if r > 0.955:
					# Carreau manquant : béton dessous.
					c = under * grain(x, y, 23, 0.08)
				elif r > 0.88:
					# Carreau fêlé : diagonale de pixels sombres.
					if (x % 8) == (y % 8) or (x % 8) == (y % 8) + 1:
						c = c * 0.55
			img.set_pixel(x, y, Color(c.r, c.g, c.b))
	# Sang séché : deux traînées de gouttes (rouge sombre).
	var blood := pal("medic_red", 0.45)
	for k in 2:
		var x := int(noise(k, 5, 31) * w)
		var y := int(noise(k, 6, 31) * h)
		for i in 10:
			if noise(i, k, 37) > 0.3:
				_put(img, x, y, blood * (0.8 + 0.3 * noise(i, k, 39)))
			if noise(i, k, 43) > 0.6:
				_put(img, x + 1, y, blood * 0.85)
			x += 1
			y += 1 if noise(i, k, 47) > 0.5 else 0


## Mur d'hôpital peint : soubassement vert d'eau jusqu'à 1,25 m (25 pixels)
## au bord écaillé, liseré sombre, plâtre au-dessus, coulures d'eau
## verticales, crasse au pied (trois paliers).
static func _painted_wall(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var plaster := pal("plaster", 0.46)
	var paint := pal("tile_green", 0.42)
	var band := 25
	for x in w:
		# Bord de peinture irrégulier : 0 ou 1 pixel au-dessus de la bande.
		var edge := band + (1 if noise(x / 2, 0, 53) > 0.6 else 0)
		# Coulure : une colonne sur quinze environ, du haut de l'image vers le bas.
		var streak_from := h - 4 - int(noise(x, 1, 59) * 24.0) if noise(x, 0, 59) > 0.93 else h
		for y in h:
			var c: Color
			if y < edge:
				c = paint * grain(x, y, 61, 0.03, 2)
				# Écailles : plâtre visible.
				if blotch(x, y, 4, w, h, 67) > 0.72:
					c = plaster * 0.9
			elif y == edge:
				c = paint * 0.55
			else:
				c = plaster * grain(x, y, 71, 0.035) * (0.94 + 0.1 * snappedf(blotch(x, y, 8, w, h, 73), 0.5))
			# Coulures d'eau sous les fissures du haut.
			if y >= streak_from:
				c = c * 0.88
			# Crasse au pied du mur : trois paliers (0 à 15 cm, à 30, à 45).
			if y < 3:
				c = c * 0.62
			elif y < 6:
				c = c * 0.76
			elif y < 9 and noise(x, y, 79) > 0.4:
				c = c * 0.88
			img.set_pixel(x, y, Color(c.r, c.g, c.b))
