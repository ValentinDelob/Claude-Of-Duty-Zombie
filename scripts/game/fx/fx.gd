class_name Fx
extends Node3D
## Effets visuels locaux (chaque machine joue ses propres effets à partir des
## événements réseau) : impacts, sang, traçantes, flashs, décalques.
## Tout est mis en pool : aucune création de nœud pendant les combats.

const MAX_HOLES := 48
const MAX_BLOOD_DECALS := 40
const MAX_TRACERS := 24

var sparks: ParticlePool
var dust: ParticlePool
var blood: ParticlePool
var _holes: Array[Decal] = []
var _hole_i := 0
var _blood_decals: Array[Decal] = []
var _blood_i := 0
var _tracers: Array[MeshInstance3D] = []
var _tracer_life: PackedFloat32Array = []
var _tracer_i := 0
var _flash: OmniLight3D
var _flash_t := 0.0

static var _tex_cache: Dictionary = {}


func _ready() -> void:
	sparks = ParticlePool.new().setup(160, _particle_mat(true), 0.035)
	sparks.gravity = 12.0
	sparks.drag = 0.8
	add_child(sparks)
	dust = ParticlePool.new().setup(160, _particle_mat(false, true), 0.07)
	dust.gravity = -0.2
	dust.drag = 4.0
	dust.grow = 1.5
	add_child(dust)
	blood = ParticlePool.new().setup(240, _particle_mat(false, true), 0.07)
	blood.gravity = 9.0
	blood.drag = 1.0
	add_child(blood)

	for i in MAX_HOLES:
		var d := Decal.new()
		d.texture_albedo = bullet_hole_texture()
		d.size = Vector3(0.12, 0.2, 0.12)
		d.visible = false
		d.cull_mask = 1
		add_child(d)
		_holes.append(d)
	for i in MAX_BLOOD_DECALS:
		var d := Decal.new()
		d.texture_albedo = blood_splat_texture(i % 4)
		d.size = Vector3(1.0, 0.6, 1.0)
		d.modulate = Color(0.55, 0.02, 0.02)
		d.visible = false
		d.cull_mask = 1
		add_child(d)
		_blood_decals.append(d)

	var tracer_mat := StandardMaterial3D.new()
	tracer_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tracer_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tracer_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	tracer_mat.vertex_color_use_as_albedo = true
	tracer_mat.albedo_color = Color(1.0, 0.8, 0.5, 0.8)
	var tracer_mesh := BoxMesh.new()
	tracer_mesh.size = Vector3(0.012, 0.012, 1.0)
	_tracer_life.resize(MAX_TRACERS)
	for i in MAX_TRACERS:
		var t := MeshInstance3D.new()
		t.mesh = tracer_mesh
		t.material_override = tracer_mat
		t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		t.visible = false
		t.top_level = true
		add_child(t)
		_tracers.append(t)

	_flash = OmniLight3D.new()
	_flash.light_color = Color(1.0, 0.72, 0.4)
	_flash.omni_range = 6.0
	_flash.light_energy = 0.0
	_flash.shadow_enabled = false
	add_child(_flash)


func _process(delta: float) -> void:
	for i in MAX_TRACERS:
		if _tracer_life[i] > 0.0:
			_tracer_life[i] -= delta
			if _tracer_life[i] <= 0.0:
				_tracers[i].visible = false
	if _flash_t > 0.0:
		_flash_t -= delta
		_flash.light_energy = maxf(_flash_t / 0.05, 0.0) * 2.5


## Impact de balle sur le décor.
func impact(pos: Vector3, normal: Vector3, with_sound := true) -> void:
	sparks.burst(pos + normal * 0.02, normal, 4, 5.0, 0.7, 0.25, Color(0.8, 0.42, 0.15, 0.8))
	dust.burst(pos + normal * 0.05, normal, 3, 0.7, 0.5, 0.8, Color(0.4, 0.38, 0.34, 0.35))
	var d := _holes[_hole_i]
	_hole_i = (_hole_i + 1) % MAX_HOLES
	_place_decal(d, pos, normal, randf() * TAU)
	if with_sound:
		Audio.play_3d("impact_concrete", pos, -8.0, 0.15, 4)


## Gerbe de sang (touche un zombie). `dir` = direction de la balle.
func blood_hit(pos: Vector3, dir: Vector3, amount := 1.0) -> void:
	blood.burst(pos, -dir * 0.3 + Vector3.UP * 0.4, int(8 * amount), 3.0, 0.8, 0.7, Color(0.45, 0.0, 0.0, 0.95))
	blood.burst(pos, dir, int(4 * amount), 4.0, 0.4, 0.5, Color(0.35, 0.0, 0.0, 0.9), 1.3)


## Tache de sang au sol ou sur un mur (mort d'un zombie...).
func blood_decal(pos: Vector3, normal := Vector3.UP, scale := 1.0) -> void:
	var d := _blood_decals[_blood_i]
	_blood_i = (_blood_i + 1) % MAX_BLOOD_DECALS
	d.size = Vector3(1.2 * scale, 0.8, 1.2 * scale)
	_place_decal(d, pos, normal, randf() * TAU)


func tracer(from: Vector3, to: Vector3, color := Color(1.0, 0.8, 0.5, 0.7), life := 0.05) -> void:
	var len := from.distance_to(to)
	if len < 0.5:
		return
	var t := _tracers[_tracer_i]
	_tracer_life[_tracer_i] = life
	_tracer_i = (_tracer_i + 1) % MAX_TRACERS
	var mid := (from + to) * 0.5
	var basis := Basis.looking_at(to - from, Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.RIGHT)
	t.global_transform = Transform3D(basis.scaled(Vector3(1, 1, len)), mid)
	var mat := t.material_override as StandardMaterial3D
	mat.albedo_color = color
	t.visible = true


## Flash lumineux d'un tir (joueurs distants).
func muzzle_flash(pos: Vector3) -> void:
	_flash.global_position = pos
	_flash_t = 0.05
	_flash.light_energy = 2.5


func _place_decal(d: Decal, pos: Vector3, normal: Vector3, spin: float) -> void:
	var up := normal.normalized()
	var ref := Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := ref.cross(up).normalized()
	var z := x.cross(up).normalized()
	var b := Basis(x, up, z).rotated(up, spin)
	d.global_transform = Transform3D(b, pos)
	d.visible = true


# --------------------------------------------------------------------------
# Textures générées (aucun fichier externe)
# --------------------------------------------------------------------------

static func _particle_mat(additive: bool, lit := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	# Les particules « matière » (poussière, sang) sont éclairées par la scène
	# pour ne pas briller dans le noir ; les étincelles sont émissives.
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX if lit else BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = soft_dot_texture()
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.no_depth_test = false
	return m


static func soft_dot_texture() -> Texture2D:
	if _tex_cache.has("dot"):
		return _tex_cache.dot
	var n := 32
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var d := Vector2(x - n * 0.5 + 0.5, y - n * 0.5 + 0.5).length() / (n * 0.5)
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	var tex := ImageTexture.create_from_image(img)
	_tex_cache.dot = tex
	return tex


static func bullet_hole_texture() -> Texture2D:
	if _tex_cache.has("hole"):
		return _tex_cache.hole
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for y in n:
		for x in n:
			var p := Vector2(x - n * 0.5, y - n * 0.5)
			var d := p.length() / (n * 0.5)
			var jag := 0.08 * sin(p.angle() * 7.0) + rng.randf_range(-0.05, 0.05)
			var core := clampf((0.32 + jag - d) * 12.0, 0.0, 1.0)
			var ring := clampf((0.75 - d) * 3.0, 0.0, 1.0) * 0.55
			var a := maxf(core, ring * (0.6 + rng.randf() * 0.4))
			var c := lerpf(0.18, 0.02, core)
			img.set_pixel(x, y, Color(c, c * 0.95, c * 0.9, a))
	var tex := ImageTexture.create_from_image(img)
	_tex_cache.hole = tex
	return tex


static func blood_splat_texture(variant: int) -> Texture2D:
	var key := "blood%d" % variant
	if _tex_cache.has(key):
		return _tex_cache[key]
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 100 + variant
	var blobs := []
	blobs.append([Vector2(n * 0.5, n * 0.5), n * 0.22])
	for i in 14:
		var ang := rng.randf() * TAU
		var dist := rng.randf_range(0.1, 0.42) * n
		blobs.append([Vector2(n * 0.5, n * 0.5) + Vector2.from_angle(ang) * dist, rng.randf_range(0.02, 0.09) * n])
	for y in n:
		for x in n:
			var a := 0.0
			for b in blobs:
				var d: float = Vector2(x, y).distance_to(b[0]) / b[1]
				a = maxf(a, clampf((1.0 - d) * 3.0, 0.0, 1.0))
			if a > 0.0:
				var shade := 0.7 + 0.3 * rng.randf()
				img.set_pixel(x, y, Color(shade, shade, shade, a * 0.92))
	var tex := ImageTexture.create_from_image(img)
	_tex_cache[key] = tex
	return tex


## Explosion (arme spéciale, pièges...).
func explosion(pos: Vector3, radius: float) -> void:
	sparks.burst(pos, Vector3.UP, 26, 7.0, 1.0, 0.6, Color(1.0, 0.5, 0.15, 0.9), 1.6)
	dust.burst(pos, Vector3.UP, 12, 2.0, 1.0, 1.4, Color(0.3, 0.28, 0.25, 0.5), 2.5)
	_flash.global_position = pos + Vector3.UP * 0.5
	_flash.omni_range = radius * 4.0
	_flash_t = 0.12
	Audio.play_3d("shotgun_fire", pos, 2.0, 0.2)
