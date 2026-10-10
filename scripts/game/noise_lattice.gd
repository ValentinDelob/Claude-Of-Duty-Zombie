class_name NoiseLattice
extends RefCounted
## Treillis de bruit de valeur précalculés (procéduraux, générés au premier
## usage) pour les shaders de la caisse au hasard et des zombies.
##
## Un bruit de valeur interpole les valeurs aléatoires des nœuds d'un
## treillis entier avec des poids lissés s(f) = f²(3 - 2f). Plutôt que de
## hacher 4 (2D) ou 8 (3D) nœuds par pixel, les shaders lisent une texture
## dont chaque texel est un nœud, avec le filtrage linéaire du GPU, à la
## coordonnée i + s(f) : UNE lecture filtrée donne exactement le mélange lissé
## des nœuds voisins (même allure que le bruit calculé, période SIZE_2D /
## SIZE_3D nœuds). Voir les shaders de box_model.gd et vnoise() dans
## zombie_body.gdshaderinc ; gain mesuré dans docs/ARCHITECTURE.md.

const SIZE_2D := 64
const SIZE_3D := 32
const SEED := 0x5eed

static var _tex2d: ImageTexture
static var _tex3d: ImageTexture3D


## Valeurs (0..255) des nœuds, déterministes.
static func lattice_bytes(count: int, seed_offset: int) -> PackedByteArray:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + seed_offset
	var b := PackedByteArray()
	b.resize(count)
	for i in count:
		b[i] = rng.randi() & 0xff
	return b


static func tex2d() -> ImageTexture:
	if _tex2d == null:
		var img := Image.create_from_data(SIZE_2D, SIZE_2D, false, Image.FORMAT_R8, lattice_bytes(SIZE_2D * SIZE_2D, 0))
		_tex2d = ImageTexture.create_from_image(img)
	return _tex2d


static func tex3d() -> ImageTexture3D:
	if _tex3d == null:
		var layers: Array[Image] = []
		var all := lattice_bytes(SIZE_3D * SIZE_3D * SIZE_3D, 1)
		var n2 := SIZE_3D * SIZE_3D
		for z in SIZE_3D:
			layers.append(Image.create_from_data(SIZE_3D, SIZE_3D, false, Image.FORMAT_R8, all.slice(z * n2, (z + 1) * n2)))
		_tex3d = ImageTexture3D.new()
		_tex3d.create(Image.FORMAT_R8, SIZE_3D, SIZE_3D, SIZE_3D, false, layers)
	return _tex3d
