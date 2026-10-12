class_name MenuBackdrop
extends Node3D
## Fond 3D du menu titre (et, assombri, du hub) : le couloir de l'aile du
## laboratoire, la nuit, en alerte. Tout est cubique et à l'échelle du jeu
## (GAME_CONCEPT.md §4.19) : murs, sol et plafond en boîtes calées sur la
## grille de 5 cm avec les textures pixel art du jeu (PixelSurfaces), décor
## cubique de l'éditeur (assets/models/props/voxel/ : chariot, étagère,
## électrodes, bobine, bureau...), zombie cubique (ZombieModel, modèle
## zombie_voxel.glb), poussière en cubes (VoxelFx), contour noir du jeu
## (ScreenOutline).
##
## Ambiance : néons froids (l'un grésille, un autre est mort), gyrophare
## orange au-dessus de la porte du laboratoire qui balaie le couloir, lueur
## d'alarme qui pulse, hublots de la porte éclairés en menthe (écrans du
## laboratoire). De temps en temps, après une coupure de courant, un zombie
## traverse le couloir de part en part par le couloir transversal (signal
## `presence`). La caméra dérive très lentement et suit un peu la souris.

## Émis quand le zombie entre dans le couloir (true) ou en ressort (false).
signal presence(shown: bool)

const H := 3.0  # hauteur sous plafond
const HALF_W := 1.5  # demi-largeur du couloir
const Z_NEAR := 3.0
const Z_FAR := -16.0
## Couloir transversal (le zombie y passe) : z de CROSS_Z1 à CROSS_Z0.
const CROSS_Z0 := -5.5
const CROSS_Z1 := -7.5
const CROSS_HALF := 6.5
## Porte du laboratoire (fond) : x de DOOR_X0 à DOOR_X1, hauteur DOOR_H.
const DOOR_X0 := -0.8
const DOOR_X1 := 0.8
const DOOR_H := 2.2
const CAM_POS := Vector3(-0.45, 1.6, 1.8)
const CAM_TARGET := Vector3(0.35, 1.35, -14.0)
const NEON := Color(0.8, 0.92, 1.0)
const ALARM := Color(1.0, 0.42, 0.08)
const MINT := Color(0.45, 0.95, 0.78)
## Marche du zombie (m/s) et bornes de sa traversée (x).
const WALK_SPEED := 0.75
const WALK_FROM := 5.8
const WALK_TO := -5.8
const PROPS := "res://assets/models/props/voxel/%s.glb"

var camera: Camera3D
## Boîtes de l'architecture posées par _span : [clé de surface, AABB].
var spans: Array = []
var _batches := {}
var _t := 0.0
var _rng := RandomNumberGenerator.new()
var _env: Environment
var _parallax := Vector2.ZERO
var _blackout := 0.0  # coupure forcée (s)
# Néons : [lumière, matériau du tube] ; 0 stable, 1 grésille, 2 mort.
var _neons: Array = []
var _flicker_on := true
var _flicker_timer := 1.0
# Gyrophare et lueur d'alarme.
var _beacon_pivot: Node3D
var _beacons: Array[SpotLight3D] = []
var _beacon_mat: StandardMaterial3D
var _alarm_glow: OmniLight3D
var _door_glow: OmniLight3D
var _window_mat: StandardMaterial3D
var _dust: GPUParticles3D
# Zombie qui traverse.
var _zombie_root: Node3D
var _zombie: Skeleton3D
var _zb := {}
var _zombie_mesh: MeshInstance3D
var _walking := false
var _standing := false
var _walk_x := WALK_FROM
var _phase := 0.0
var _next_walk := 7.0
var _pending := false


func _ready() -> void:
	_rng.seed = 7031
	_build_environment()
	_plan_relief()
	_build_corridor()
	_emit_relief()
	_commit_batches()
	_build_props()
	_build_lights()
	_build_zombie()
	_build_dust()
	if ScreenOutline.supported():
		var outline := ScreenOutline.new()
		outline.name = "ScreenOutline"
		add_child(outline)
	camera = Camera3D.new()
	camera.fov = 58.0
	camera.near = 0.05
	camera.far = 60.0
	add_child(camera)
	camera.position = CAM_POS
	camera.look_at(CAM_TARGET)
	camera.current = true
	_apply_quality()
	Settings.changed.connect(_apply_quality)


# ------------------------------------------------------------------ construction

func _append(key: String, mesh: Mesh, xf: Transform3D) -> void:
	if not _batches.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_batches[key] = st
	(_batches[key] as SurfaceTool).append_from(mesh, 0, xf)


## Boîte de taille `size` centrée en `pos` (dimensions multiples de 5 cm).
## Avec le relief : ses six faces, percées des creux du relief.
func _box(key: String, size: Vector3, pos: Vector3) -> void:
	if _relief != null:
		var lo := pos - size * 0.5
		var hi := pos + size * 0.5
		for n: Vector3i in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
			_relief.box_face(n, lo, hi, func(p: Array, nn: Vector3) -> void: _face(key, p, nn))
		return
	var m := BoxMesh.new()
	m.size = size
	_append(key, m, Transform3D(Basis.IDENTITY, pos))


## Rectangle `p` (sens direct vu de la normale `n`) ajouté au lot `key`.
func _face(key: String, p: Array, n: Vector3) -> void:
	if not _batches.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_batches[key] = st
	var st: SurfaceTool = _batches[key]
	for i in [0, 2, 1, 0, 3, 2]:
		st.set_normal(n)
		st.set_uv(Vector2(i & 1, i >> 1))
		st.add_vertex(p[i])


# ------------------------------------------------------------------ relief

## Relief des surfaces du couloir (SurfaceRelief, comme les cartes) :
## carreaux manquants et flaques au sol, faïence abîmée, plinthe et
## couvre-joint aux murs, ossature et dalles tombées au plafond. Pas de
## creux devant les portes ni derrière les objets muraux, pas de dalle
## tombée près des néons.
var _relief: SurfaceRelief


func _plan_relief() -> SurfaceRelief:
	var rel := SurfaceRelief.new()
	rel.seed = SurfaceRelief.seed_of("menu_backdrop")
	_relief = rel
	var w := HALF_W
	var wo := w + 0.2
	var in_floor := func(x: float, z: float) -> bool:
		return (absf(x) < w and z > Z_FAR and z < Z_NEAR) or (absf(x) > w and absf(x) < CROSS_HALF and z > CROSS_Z1 and z < CROSS_Z0)
	# Devant les portes (fond, salle latérale) et sous le premier plan.
	var near_door := func(x: float, z: float) -> bool:
		return z < Z_FAR + 1.2 or (x > w - 1.0 and z > -4.9 and z < -2.9) or z > Z_NEAR - 0.6
	rel.plan_floor("tiles", 0.0, Rect2(-CROSS_HALF, Z_FAR, CROSS_HALF * 2.0, Z_NEAR - Z_FAR),
		func(x: float, z: float) -> bool: return in_floor.call(x, z) and not near_door.call(x, z))
	var neons := [-0.6, -3.4, -6.5, -9.8, -12.8]
	var off_neon := func(x: float, z: float) -> bool:
		for zn: float in neons:
			if absf(x) < 0.4 and absf(z - zn) < 0.8:
				return false
		return true
	rel.plan_ceiling("ceiling", H, Rect2(-w, Z_FAR, w * 2.0, Z_NEAR - Z_FAR),
		func(x: float, z: float) -> bool: return absf(x) < w and z > Z_FAR and z < Z_NEAR and off_neon.call(x, z), off_neon, "", 0.05)
	# Murs du couloir (faïence) : objets muraux et porte latérale réservés.
	var wall_free := func(x: float, z: float) -> bool:
		if x > 0.0:
			return not ((z > -4.7 and z < -3.1) or (z > -2.2 and z < -1.0) or (z > -10.9 and z < -9.5) or z < -14.3)
		return not ((z > -11.0 and z < -9.8) or (z > -13.0 and z < -11.6))
	for s: float in [-1.0, 1.0]:
		var n := Vector3i(-int(s), 0, 0)
		rel.plan_wall("wall_lab", n, s * w, CROSS_Z0, Z_NEAR, 0.0, H, 0.0, wall_free)
		rel.plan_wall("wall_lab", n, s * w, Z_FAR, CROSS_Z1, 0.0, H, 0.0, wall_free)
		# Couloir transversal (mur peint).
		rel.plan_wall("wall", Vector3i(0, 0, 1), CROSS_Z1, s * wo, s * CROSS_HALF, 0.0, 2.4, 0.0, Callable())
		rel.plan_wall("wall", Vector3i(0, 0, -1), CROSS_Z0, s * wo, s * CROSS_HALF, 0.0, 2.4, 0.0, Callable())
	return rel


## Faces du relief : un maillage sans ombre par matériau.
func _emit_relief() -> void:
	if _relief == null:
		return
	var groups := _relief.emit_groups()
	for key: String in groups:
		for tag: String in groups[key]:
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = groups[key][tag][0]
			arrays[Mesh.ARRAY_NORMAL] = groups[key][tag][1]
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var mi := MeshInstance3D.new()
			mi.name = "Relief_" + key
			mi.mesh = mesh
			mi.material_override = SurfaceRelief.material(key)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)


## Boîte donnée par ses deux coins (plus lisible pour l'architecture).
## Les boîtes de l'architecture ne doivent jamais se chevaucher (faces
## coplanaires : z-fighting) ; elles sont gardées dans `spans`
## (tests/test_menu_backdrop.gd).
func _span(key: String, a: Vector3, b: Vector3) -> void:
	var lo := Vector3(minf(a.x, b.x), minf(a.y, b.y), minf(a.z, b.z))
	var hi := Vector3(maxf(a.x, b.x), maxf(a.y, b.y), maxf(a.z, b.z))
	spans.append([key, AABB(lo, hi - lo)])
	_box(key, hi - lo, (lo + hi) * 0.5)


func _commit_batches() -> void:
	for key in _batches:
		var mi := MeshInstance3D.new()
		mi.name = "Static_" + key
		mi.mesh = (_batches[key] as SurfaceTool).commit()
		mi.material_override = SurfaceRelief.material(key)
		add_child(mi)
	_batches.clear()


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.36, 0.42, 0.5)
	env.ambient_light_energy = 0.12
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.15
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_strength = 1.0
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.fog_enabled = true
	env.fog_light_color = Color(0.03, 0.035, 0.045)
	env.fog_density = 0.035
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.85
	env.adjustment_contrast = 1.1
	_env = env
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _build_corridor() -> void:
	var w := HALF_W
	# Sol carrelé (hôpital), plafond en dalles.
	_span("tiles", Vector3(-w, -0.2, Z_NEAR), Vector3(w, 0, Z_FAR))
	_span("ceiling", Vector3(-w, H, Z_NEAR), Vector3(w, H + 0.2, Z_FAR))
	# Murs du couloir en faïence de laboratoire, ouverts sur le couloir
	# transversal.
	for s: float in [-1.0, 1.0]:
		var x0 := s * w
		var x1 := s * (w + 0.2)
		_span("wall_lab", Vector3(x0, 0, Z_NEAR), Vector3(x1, H, CROSS_Z0))
		_span("wall_lab", Vector3(x0, 0, CROSS_Z1), Vector3(x1, H, Z_FAR))
		_span("wall_lab", Vector3(x0, 2.4, CROSS_Z0), Vector3(x1, H, CROSS_Z1))
	# Couloir transversal : sol, plafond, murs, fonds sombres.
	_span("tiles", Vector3(-CROSS_HALF, -0.2, CROSS_Z0), Vector3(-w, 0, CROSS_Z1))
	_span("tiles", Vector3(w, -0.2, CROSS_Z0), Vector3(CROSS_HALF, 0, CROSS_Z1))
	# Plafond et murs du transversal : à partir de la face EXTÉRIEURE des murs
	# du couloir (w + 0,2). Partir de w les faisait chevaucher l'épaisseur de
	# ces murs : faces coplanaires de textures différentes (dessous du linteau
	# des ouvertures, chants des montants), qui scintillaient (z-fighting).
	var wo := w + 0.2
	_span("ceiling", Vector3(-CROSS_HALF, 2.4, CROSS_Z0), Vector3(-wo, 2.6, CROSS_Z1))
	_span("ceiling", Vector3(wo, 2.4, CROSS_Z0), Vector3(CROSS_HALF, 2.6, CROSS_Z1))
	for s: float in [-1.0, 1.0]:
		_span("wall", Vector3(s * wo, 0, CROSS_Z1), Vector3(s * CROSS_HALF, 2.4, CROSS_Z1 - 0.2))
		_span("wall", Vector3(s * wo, 0, CROSS_Z0), Vector3(s * CROSS_HALF, 2.4, CROSS_Z0 + 0.2))
		_span("wall_concrete", Vector3(s * CROSS_HALF, 0, CROSS_Z0), Vector3(s * (CROSS_HALF + 0.2), 2.4, CROSS_Z1))
	# Mur du fond et porte du laboratoire (deux battants d'acier, hublots).
	var zf := Z_FAR
	_span("wall_lab", Vector3(-w, 0, zf), Vector3(DOOR_X0 - 0.1, H, zf - 0.2))
	_span("wall_lab", Vector3(DOOR_X1 + 0.1, 0, zf), Vector3(w, H, zf - 0.2))
	_span("wall_lab", Vector3(DOOR_X0 - 0.1, DOOR_H + 0.1, zf), Vector3(DOOR_X1 + 0.1, H, zf - 0.2))
	_span("steel", Vector3(DOOR_X0 - 0.1, 0, zf + 0.05), Vector3(DOOR_X0, DOOR_H + 0.1, zf - 0.2))
	_span("steel", Vector3(DOOR_X1, 0, zf + 0.05), Vector3(DOOR_X1 + 0.1, DOOR_H + 0.1, zf - 0.2))
	_span("steel", Vector3(DOOR_X0, DOOR_H, zf + 0.05), Vector3(DOOR_X1, DOOR_H + 0.1, zf - 0.2))
	for side in [[DOOR_X0, -0.05], [0.05, DOOR_X1]]:
		var a: float = side[0]
		var b: float = side[1]
		# Battant percé d'un hublot carré (0,3 m) à hauteur d'yeux.
		_span("door", Vector3(a, 0, zf - 0.05), Vector3(b, 1.35, zf - 0.1))
		_span("door", Vector3(a, 1.65, zf - 0.05), Vector3(b, DOOR_H, zf - 0.1))
		var mid := (a + b) * 0.5
		_span("door", Vector3(a, 1.35, zf - 0.05), Vector3(mid - 0.15, 1.65, zf - 0.1))
		_span("door", Vector3(mid + 0.15, 1.35, zf - 0.05), Vector3(b, 1.65, zf - 0.1))
	_span("steel", Vector3(-0.05, 0, zf - 0.05), Vector3(0.05, DOOR_H, zf - 0.1))
	# Porte d'une salle latérale (droite), fermée.
	_span("door", Vector3(w - 0.05, 0, -3.4), Vector3(w, 2.1, -4.4))
	_span("steel", Vector3(w - 0.1, 2.1, -3.35), Vector3(w, 2.2, -4.45))
	# Plinthe et conduites au plafond (acier, sections de 10 cm).
	_span("steel", Vector3(w - 0.25, 2.65, Z_NEAR), Vector3(w - 0.15, 2.75, Z_FAR))
	_span("steel", Vector3(w - 0.45, 2.75, Z_NEAR), Vector3(w - 0.3, 2.9, Z_FAR))
	_span("metal", Vector3(-w, 2.8, Z_NEAR), Vector3(-w + 0.1, 2.9, Z_FAR))


## Décor cubique de l'éditeur (`id` : assets/models/props/voxel/<id>.glb),
## couleur de face du modèle (matériau « voxel » des cartes), tourné par
## quarts de tour.
func _prop(id: String, pos: Vector3, quarter := 0) -> Node3D:
	var ps := load(PROPS % id) as PackedScene
	if ps == null:
		return null
	var n := ps.instantiate() as Node3D
	var mat := MeshMapBuilder.material_for(MeshMapBuilder.VOXEL_MAT)
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = mat
	n.position = pos
	n.rotation.y = quarter * PI * 0.5
	add_child(n)
	return n


func _build_props() -> void:
	var w := HALF_W
	# Chariot de soins contre le mur gauche, électrodes au mur, bureau et
	# lampe plus loin ; étagère et boîtier électrique à droite ; bobine du
	# scientifique près de sa porte ; débris et flaque au sol.
	_prop("chariot", Vector3(-w + 0.35, 0, -2.6), 1)
	_prop("electrodes", Vector3(-w, 0.6, -10.4), 1)
	_prop("chaise_renversee", Vector3(0.35, 0, -4.4), 1)
	_prop("debris_epars", Vector3(0.0, 0, -9.4), 0)
	_prop("etagere", Vector3(w - 0.2, 0, -10.2), 3)
	_prop("boitier_electrique", Vector3(w, 1.7, -1.6), 3)
	_prop("flaque_eau", Vector3(0.45, 0, -11.4), 0)
	_prop("bureau", Vector3(-w + 0.35, 0, -12.4), 1)
	_prop("lampe_bureau", Vector3(-w + 0.3, 1.0, -12.0), 1)
	_prop("bobine_tesla", Vector3(w - 0.35, 0, -14.9), 0)
	_prop("gravats", Vector3(-4.6, 0, -6.5), 0)
	_prop("caisses", Vector3(4.9, 0, -6.5), 1)
	# Néons au plafond (le long du couloir) : stable, grésillant, mort.
	var spots := [[-0.6, 2], [-3.4, 1], [-6.5, 0], [-9.8, 0], [-12.8, 2]]
	for s in spots:
		var z: float = s[0]
		var n := _prop("neon", Vector3(0, H, z), 1)
		var tube := StandardMaterial3D.new()
		tube.albedo_color = NEON * 0.6
		tube.emission_enabled = true
		tube.emission = NEON
		tube.emission_energy_multiplier = 3.0
		# Tube lumineux : une boîte émissive sous l'armature cubique.
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.1, 0.05, 1.2)
		mi.mesh = bm
		mi.material_override = tube
		mi.position = Vector3(0, H - 0.125, z)
		add_child(mi)
		var l := OmniLight3D.new()
		l.light_color = NEON
		l.omni_range = 5.5
		l.omni_attenuation = 1.3
		l.position = Vector3(0, H - 0.4, z)
		add_child(l)
		_neons.append([l, tube, int(s[1]), n])


func _build_lights() -> void:
	# Gyrophare au-dessus de la porte : cube orange, deux faisceaux opposés.
	_beacon_mat = StandardMaterial3D.new()
	_beacon_mat.albedo_color = ALARM * 0.5
	_beacon_mat.emission_enabled = true
	_beacon_mat.emission = ALARM
	_beacon_mat.emission_energy_multiplier = 4.0
	var bx := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.2, 0.15, 0.2)
	bx.mesh = bm
	bx.material_override = _beacon_mat
	bx.position = Vector3(0, DOOR_H + 0.45, Z_FAR + 0.15)
	add_child(bx)
	_span("steel", Vector3(-0.15, DOOR_H + 0.3, Z_FAR), Vector3(0.15, DOOR_H + 0.375, Z_FAR + 0.3))
	_commit_batches()
	_beacon_pivot = Node3D.new()
	_beacon_pivot.position = bx.position
	add_child(_beacon_pivot)
	for k in 2:
		var sp := SpotLight3D.new()
		sp.light_color = ALARM
		sp.light_energy = 6.0
		sp.spot_range = 18.0
		sp.spot_angle = 22.0
		sp.spot_attenuation = 0.8
		sp.rotation.y = k * PI
		sp.rotation.x = -0.12
		_beacon_pivot.add_child(sp)
		_beacons.append(sp)
	# Lueur d'alarme qui pulse dans tout le fond du couloir.
	_alarm_glow = OmniLight3D.new()
	_alarm_glow.light_color = ALARM
	_alarm_glow.omni_range = 9.0
	_alarm_glow.position = Vector3(0, 2.4, -13.5)
	add_child(_alarm_glow)
	# Hublots : écrans du laboratoire derrière la porte (menthe).
	_window_mat = StandardMaterial3D.new()
	_window_mat.albedo_color = MINT * 0.3
	_window_mat.emission_enabled = true
	_window_mat.emission = MINT
	_window_mat.emission_energy_multiplier = 2.2
	for mid in [(DOOR_X0 - 0.05) * 0.5, (DOOR_X1 + 0.05) * 0.5]:
		var win := MeshInstance3D.new()
		var wm := BoxMesh.new()
		wm.size = Vector3(0.3, 0.3, 0.05)
		win.mesh = wm
		win.material_override = _window_mat
		win.position = Vector3(mid, 1.5, Z_FAR - 0.1)
		add_child(win)
	_door_glow = OmniLight3D.new()
	_door_glow.light_color = MINT
	_door_glow.light_energy = 0.5
	_door_glow.omni_range = 3.5
	_door_glow.position = Vector3(0, 1.5, Z_FAR + 0.6)
	add_child(_door_glow)


func _build_zombie() -> void:
	_zombie = ZombieModel.build(5)
	_zb = RigBuilder.bone_indices(_zombie)
	_zombie_root = Node3D.new()
	_zombie_root.add_child(_zombie)
	_zombie_root.visible = false
	add_child(_zombie_root)
	_zombie_mesh = _zombie.get_node("Mesh")
	_zombie_mesh.set_instance_shader_parameter("eye_glow", 1.0)


func _build_dust() -> void:
	# Poussière en suspension : cubes de 2,5 cm (VoxelFx), éclairés.
	_dust = GPUParticles3D.new()
	_dust.amount = 160
	_dust.lifetime = 16.0
	_dust.preprocess = 16.0
	_dust.position = Vector3(0, 1.6, -6.5)
	_dust.visibility_aabb = AABB(Vector3(-3, -2.5, -10), Vector3(6, 5, 20))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(1.4, 1.4, 8.5)
	pm.gravity = Vector3(0, -0.006, 0)
	pm.direction = Vector3(0.4, 0.2, 0.1)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.01
	pm.initial_velocity_max = 0.05
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_noise_scale = 4.0
	pm.turbulence_influence_min = 0.01
	pm.turbulence_influence_max = 0.04
	pm.scale_min = 0.01
	pm.scale_max = 0.025
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0))
	ramp.set_color(1, Color(1, 1, 1, 0))
	ramp.add_point(0.2, Color(1, 1, 1, 1))
	ramp.add_point(0.8, Color(1, 1, 1, 1))
	var rt := GradientTexture1D.new()
	rt.gradient = ramp
	pm.color_ramp = rt
	_dust.process_material = pm
	_dust.draw_pass_1 = VoxelFx.cube()
	_dust.material_override = VoxelFx.material("lit", {"max": VoxelFx.GRID, "opacity": 0.8, "tint": Color(0.9, 0.95, 1.0)})
	add_child(_dust)


func _apply_quality() -> void:
	var q: int = Settings.quality
	_env.glow_enabled = q >= Settings.Quality.MEDIUM
	for sp in _beacons:
		sp.shadow_enabled = q >= Settings.Quality.HIGH
	for n in _neons:
		(n[0] as OmniLight3D).shadow_enabled = q >= Settings.Quality.HIGH and n[2] == 0
	_dust.amount = [80, 160, 240][q]


# ------------------------------------------------------------------ animation

func _process(delta: float) -> void:
	_t += delta
	if _blackout > 0.0:
		_blackout -= delta
	_animate_camera(delta)
	_animate_lights(delta)
	_animate_zombie(delta)


func _animate_camera(delta: float) -> void:
	var vp := get_viewport()
	if vp:
		var r := vp.get_visible_rect().size
		var m := vp.get_mouse_position()
		var target := Vector2.ZERO
		if r.x > 0.0 and r.y > 0.0:
			target = (m / r - Vector2(0.5, 0.5)).clampf(-0.5, 0.5)
		_parallax = _parallax.lerp(target, clampf(delta * 0.8, 0.0, 1.0))
	var drift := Vector3(sin(_t * 0.071) * 0.12, sin(_t * 0.113) * 0.04, sin(_t * 0.053) * 0.3)
	camera.position = CAM_POS + drift
	camera.look_at(CAM_TARGET + Vector3(sin(_t * 0.061) * 0.4, sin(_t * 0.089) * 0.2, 0))
	camera.rotate_object_local(Vector3.UP, -_parallax.x * 0.05)
	camera.rotate_object_local(Vector3.RIGHT, -_parallax.y * 0.03)


func _animate_lights(delta: float) -> void:
	var dark := _blackout > 0.0
	# Néon qui grésille : phases stables, coupures brèves, rafales.
	_flicker_timer -= delta
	if _flicker_timer <= 0.0:
		_flicker_on = not _flicker_on
		if _flicker_on:
			_flicker_timer = _rng.randf_range(0.03, 0.18) if _rng.randf() < 0.5 else _rng.randf_range(1.2, 5.0)
		else:
			_flicker_timer = _rng.randf_range(0.03, 0.12)
	for n in _neons:
		var level := 1.0
		match int(n[2]):
			1:
				level = 1.0 if _flicker_on else 0.05
			2:
				level = 0.0
		if dark:
			level = 0.0
		var buzz := 0.95 + 0.05 * sin(_t * 120.0)
		(n[0] as OmniLight3D).light_energy = 0.85 * level * buzz
		(n[1] as StandardMaterial3D).emission_energy_multiplier = 3.2 * level + 0.05
	# Gyrophare : un tour en 2,4 s ; lueur d'alarme qui pulse (même période).
	_beacon_pivot.rotation.y = fmod(_t * TAU / 2.4, TAU)
	var pulse := 0.5 + 0.5 * sin(_t * TAU / 1.2)
	_alarm_glow.light_energy = 0.25 + 0.9 * pulse * pulse
	_beacon_mat.emission_energy_multiplier = 3.0 + 4.0 * pulse
	# Hublots : écrans qui vacillent à peine, éteints pendant les coupures.
	var screen := 0.0 if dark else 0.9 + 0.1 * sin(_t * 31.0) * sin(_t * 2.3)
	_window_mat.emission_energy_multiplier = 2.2 * screen
	_door_glow.light_energy = 0.5 * screen


## Coupure de courant forcée (néons et écrans éteints, l'alarme continue),
## en secondes.
func blackout(duration: float) -> void:
	_blackout = maxf(_blackout, duration)


func _animate_zombie(delta: float) -> void:
	if not _walking and not _standing:
		_next_walk -= delta
		if _next_walk <= 0.0 and not _pending:
			# Le courant saute, puis il est là.
			_pending = true
			blackout(_rng.randf_range(0.25, 0.4))
		if _pending and _blackout < 0.1:
			_pending = false
			_start_walk()
	if _walking:
		_walk_x -= WALK_SPEED * delta
		_phase += delta * PI * WALK_SPEED / 0.36
		_zombie_root.position = Vector3(_walk_x, absf(cos(_phase)) * 0.02, (CROSS_Z0 + CROSS_Z1) * 0.5)
		_pose_walk(_phase)
		if _walk_x <= WALK_TO:
			_set_walking(false)
	elif _standing:
		# Debout au milieu du couloir, face à la caméra : il oscille à peine.
		_pose_stand(_t)


func _start_walk() -> void:
	_walk_x = WALK_FROM
	_phase = 0.0
	_zombie_root.rotation.y = -PI * 0.5
	_set_walking(true)


func _set_walking(on: bool) -> void:
	_walking = on
	_zombie_root.visible = on or _standing
	if not on:
		_next_walk = _rng.randf_range(9.0, 16.0)
	presence.emit(on)


## Pose de marche traînante (angles en radians, repère de repos de RigBuilder ;
## mêmes conventions que ZombieAnim : cuisse négative = vers l'avant).
func _pose_walk(ph: float) -> void:
	var s := sin(ph)
	var c := cos(ph)
	var amp := 0.32
	var lean := 0.18
	_rot("thigh_l", Vector3(-s * amp - 0.05, 0, 0.02))
	_rot("thigh_r", Vector3(s * amp - 0.05, 0, -0.02))
	_rot("shin_l", Vector3(0.12 + maxf(0.0, c) * amp * 0.9, 0, 0))
	_rot("shin_r", Vector3(0.12 + maxf(0.0, -c) * amp * 0.9, 0, 0))
	_rot("spine", Vector3(lean * 0.55, 0, sin(ph * 0.5) * 0.05))
	_rot("chest", Vector3(lean * 0.45, -s * 0.08, 0.06))
	_rot("arm_l", Vector3(-1.4 - lean + s * 0.08, 0, 0.0))
	_rot("arm_r", Vector3(-1.35 - lean - s * 0.08, 0, 0.0))
	_rot("forearm_l", Vector3(-0.25, 0, 0))
	_rot("forearm_r", Vector3(-0.2, 0, 0))
	_rot("head", Vector3(-0.05 + sin(ph * 2.0) * 0.05, 0, sin(ph * 0.5) * 0.12))


func _pose_stand(t: float) -> void:
	var sway := sin(t * 0.45)
	for b in ["thigh_l", "thigh_r", "shin_l", "shin_r"]:
		_rot(b, Vector3.ZERO)
	_rot("spine", Vector3(0.12 + sway * 0.03, 0, sway * 0.03))
	_rot("chest", Vector3(0.08, 0, 0.05))
	_rot("arm_l", Vector3(-1.3, 0, 0.04))
	_rot("arm_r", Vector3(-0.15 + sway * 0.05, 0, -0.06))
	_rot("forearm_l", Vector3(-0.3, 0, 0))
	_rot("forearm_r", Vector3(-0.15, 0, 0))
	_rot("head", Vector3(0.1, sin(t * 0.21) * 0.15, 0.3 + sway * 0.05))


func _rot(bone: String, euler: Vector3) -> void:
	if _zb.has(bone):
		_zombie.set_bone_pose_rotation(_zb[bone], Quaternion.from_euler(euler))


## Pour les tests et le lancement d'une partie : le zombie se tient (true)
## au milieu du couloir, face à la caméra, ou disparaît (false).
func force_figure(shown: bool) -> void:
	_standing = shown
	if shown:
		_walking = false
		_zombie_root.position = Vector3(0.25, 0, -9.0)
		_zombie_root.rotation.y = 0.0
		_pose_stand(_t)
	_zombie_root.visible = shown
	if not shown:
		_walking = false
		_next_walk = _rng.randf_range(9.0, 16.0)


func figure_visible() -> bool:
	return _zombie_root.visible
