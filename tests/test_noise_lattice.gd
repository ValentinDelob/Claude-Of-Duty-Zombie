extends TestCase
## Treillis de bruit précalculés (NoiseLattice) lus par surface.gdshader et
## zombie_body.gdshaderinc.


func test_textures_have_one_texel_per_node() -> void:
	var t2 := NoiseLattice.tex2d()
	assert_eq(t2.get_width(), NoiseLattice.SIZE_2D)
	assert_eq(t2.get_height(), NoiseLattice.SIZE_2D)
	var t3 := NoiseLattice.tex3d()
	assert_eq(t3.get_width(), NoiseLattice.SIZE_3D)
	assert_eq(t3.get_depth(), NoiseLattice.SIZE_3D)
	assert_true(NoiseLattice.tex2d() == t2, "mis en cache")


func test_lattice_is_deterministic_and_uniform() -> void:
	var a := NoiseLattice.lattice_bytes(4096, 0)
	assert_eq(a, NoiseLattice.lattice_bytes(4096, 0), "déterministe (même rendu partout)")
	var sum := 0.0
	var low := 0
	for v in a:
		sum += v
		if v < 64:
			low += 1
	# Valeurs uniformes 0..255 comme l'ancien hachage : moyenne ~127,5, un quart sous 64.
	assert_near(sum / a.size(), 127.5, 6.0, "moyenne")
	assert_near(low / float(a.size()), 0.25, 0.03, "répartition")
	assert_true(a != NoiseLattice.lattice_bytes(4096, 1), "2D et 3D indépendants")
