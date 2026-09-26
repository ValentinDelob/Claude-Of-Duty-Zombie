class_name BloodTex
extends RefCounted
## Textures procédurales du décor du menu : traînées de sang, empreintes de
## main, bandes de danger ; police « griffonnée » pour les messages au sang.
## Les formes sont blanches (alpha = couverture) : la couleur vient du décalque.

static var _cache := {}


## Traînée (corps traîné, main qui glisse) : longue sur v, étroite sur u.
static func streak(seed_value: int) -> ImageTexture:
	var key := "streak_%d" % seed_value
	if _cache.has(key):
		return _cache[key]
	var w := 64
	var h := 512
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var n := FastNoiseLite.new()
	n.seed = seed_value
	n.frequency = 0.02
	var fine := FastNoiseLite.new()
	fine.seed = seed_value + 5
	fine.frequency = 0.15
	for y in h:
		var v := float(y) / h
		# Largeur et position qui ondulent, couverture qui s'épuise par endroits.
		var center := 0.5 + n.get_noise_2d(0.0, y) * 0.12
		var half := 0.26 + n.get_noise_2d(50.0, y) * 0.1
		var ends := smoothstep(0.0, 0.08, v) * smoothstep(1.0, 0.8, v)
		var supply := smoothstep(-0.35, 0.1, n.get_noise_2d(100.0, y * 0.6))
		for x in w:
			var u := float(x) / w
			var d := absf(u - center) / maxf(half, 0.01)
			var edge := 1.0 - smoothstep(0.7, 1.0, d + fine.get_noise_2d(x * 3.0, y) * 0.25)
			# Stries (doigts, tissu).
			var striae := 0.55 + 0.45 * (fine.get_noise_2d(x * 6.0, y * 0.15) * 0.5 + 0.5)
			var a := edge * striae * ends * lerpf(0.35, 1.0, supply)
			var shade := 0.75 + 0.25 * striae
			img.set_pixel(x, y, Color(shade, shade, shade, clampf(a, 0.0, 1.0)))
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


## Empreinte de main (doigts vers +x), bords baveux.
static func handprint(seed_value: int) -> ImageTexture:
	var key := "hand_%d" % seed_value
	if _cache.has(key):
		return _cache[key]
	var s := 128
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var n := FastNoiseLite.new()
	n.seed = seed_value
	n.frequency = 0.12
	var palm := Vector2(48, 64)
	var fingers := [
		[Vector2(70, 44), Vector2(100, 30), 6.5],
		[Vector2(74, 56), Vector2(110, 50), 7.0],
		[Vector2(74, 68), Vector2(108, 70), 6.8],
		[Vector2(70, 80), Vector2(98, 90), 6.0],
		[Vector2(46, 90), Vector2(66, 112), 7.0],  # pouce
	]
	for y in s:
		for x in s:
			var p := Vector2(x, y)
			var q := (p - palm) / Vector2(28, 25)
			var cov := 1.0 - smoothstep(0.8, 1.05, q.length())
			for f in fingers:
				var dseg := _seg_dist(p, f[0], f[1])
				cov = maxf(cov, 1.0 - smoothstep(f[2] - 1.5, f[2] + 1.0, dseg))
			var nn := n.get_noise_2d(x, y)
			cov *= 0.65 + 0.35 * (nn * 0.5 + 0.5)
			cov = smoothstep(0.25, 0.6, cov + nn * 0.15)
			img.set_pixel(x, y, Color(1, 1, 1, cov))
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)


## Bandes de danger jaune / noir, usées (répétées par uv1_scale).
static func hazard_stripes() -> ImageTexture:
	if _cache.has("hazard"):
		return _cache.hazard
	var w := 64
	var h := 16
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var n := FastNoiseLite.new()
	n.seed = 9
	n.frequency = 0.2
	for y in h:
		for x in w:
			var stripe := fmod(float(x + y * 2), 32.0) < 16.0
			var wear := n.get_noise_2d(x, y) * 0.5 + 0.5
			var c := Color(0.62, 0.5, 0.12) if stripe else Color(0.05, 0.05, 0.04)
			c = c.lerp(Color(0.2, 0.19, 0.17), smoothstep(0.55, 0.8, wear))
			img.set_pixel(x, y, c)
	var tex := ImageTexture.create_from_image(img)
	_cache.hazard = tex
	return tex


## Police manuscrite tremblée (système), repli sur Impact.
static func scrawl_font() -> Font:
	if _cache.has("scrawl"):
		return _cache.scrawl
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Chiller", "Ink Free", "Segoe Script", "Impact", "sans-serif"])
	_cache.scrawl = f
	return f
