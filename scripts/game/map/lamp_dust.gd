class_name LampDust
extends GPUParticles3D
## Poussière en suspension dans les cônes des lampes (docs/ART_DIRECTION.md
## « Lumière et ambiance ») : UN seul système de particules par carte (un
## appel de dessin), cubes de 2,5 cm (VoxelFx, matériau éclairé : ils
## brillent dans la flaque de la lampe et disparaissent dans l'ombre),
## émis sur des points tirés dans le cône de chaque lampe à flaque
## (MapProps.add_lamp -> add_cone). Dérive lente et turbulente.
## Qualité (RenderQuality.GROUP) : aucune en LOW, PER_LAMP grains par lampe
## en MEDIUM et HIGH (au plus MAX).

const PER_LAMP := {"low": 0, "medium": 18, "high": 30}
const MAX := 1400
## Points d'émission tirés par cône.
const POINTS_PER_CONE := 24
const LIFE := 14.0

var _points := PackedVector3Array()
var _cones := 0
var _rng := RandomNumberGenerator.new()
var _lo := Vector3.INF
var _hi := -Vector3.INF


func _init() -> void:
	name = "LampDust"
	# Rien n'est émis avant finish() (lampes toutes posées).
	emitting = false
	_rng.seed = 9137


## Cône d'une lampe : sommet `apex` (la lampe), vers le bas, demi-angle
## `angle_deg`, sur `height` m (jusqu'au sol).
func add_cone(apex: Vector3, angle_deg: float, height: float) -> void:
	_cones += 1
	var t := tan(deg_to_rad(clampf(angle_deg, 5.0, 80.0))) * 0.75
	for i in POINTS_PER_CONE:
		# Plus de grains en bas du cône (plus large), jamais collés à la lampe.
		var d := lerpf(0.35, height - 0.15, sqrt(_rng.randf()))
		var r := d * t * sqrt(_rng.randf())
		var a := _rng.randf() * TAU
		var p := apex + Vector3(cos(a) * r, -d, sin(a) * r)
		_points.append(p)
		_lo = _lo.min(p)
		_hi = _hi.max(p)


func cone_count() -> int:
	return _cones


## Construit le système (après toutes les lampes) ; sans cône : rien.
func finish() -> void:
	if _points.is_empty():
		return
	var img := Image.create(_points.size(), 1, false, Image.FORMAT_RGBF)
	for i in _points.size():
		var p := _points[i]
		img.set_pixel(i, 0, Color(p.x, p.y, p.z))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINTS
	pm.emission_point_texture = ImageTexture.create_from_image(img)
	pm.emission_point_count = _points.size()
	pm.gravity = Vector3(0, -0.004, 0)
	pm.direction = Vector3(0.3, 0.15, 0.2)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.005
	pm.initial_velocity_max = 0.03
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.5
	pm.turbulence_noise_scale = 3.5
	pm.turbulence_influence_min = 0.01
	pm.turbulence_influence_max = 0.03
	# Cubes de 1,5 à 2,5 cm qui naissent et meurent en grandissant / rapetissant
	# (pas de transparence à trier).
	pm.scale_min = 0.015
	pm.scale_max = 0.025
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 0.0))
	sc.add_point(Vector2(0.15, 1.0))
	sc.add_point(Vector2(0.85, 1.0))
	sc.add_point(Vector2(1.0, 0.0))
	var st := CurveTexture.new()
	st.curve = sc
	pm.scale_curve = st
	process_material = pm
	var cube := BoxMesh.new()
	cube.size = Vector3.ONE
	draw_pass_1 = cube
	material_override = material()
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lifetime = LIFE
	preprocess = LIFE
	local_coords = false
	visibility_aabb = AABB(_lo - Vector3.ONE, (_hi - _lo) + Vector3.ONE * 2.0)
	add_to_group(RenderQuality.GROUP)
	apply_quality(RenderQuality.current())


static var _mat: StandardMaterial3D


## Matériau des grains : éclairé (ils ne brillent que dans la lumière),
## gris clair mat, effacés près de la caméra (tramage, sans transparence :
## jamais un gros cube devant les yeux).
static func material() -> StandardMaterial3D:
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.albedo_color = Color(0.55, 0.53, 0.5)
		_mat.roughness = 1.0
		_mat.metallic_specular = 0.0
		_mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER
		_mat.distance_fade_min_distance = 0.9
		_mat.distance_fade_max_distance = 2.2
	return _mat


## Grains selon le préréglage (RenderQuality.GROUP).
func apply_quality(q: Dictionary) -> void:
	if _points.is_empty():
		return
	var n := mini(MAX, _cones * int(PER_LAMP.get(String(q.get("name", "medium")), 18)))
	visible = n > 0
	emitting = n > 0
	if n > 0 and n != amount:
		amount = n
