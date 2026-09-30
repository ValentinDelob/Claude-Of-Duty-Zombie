class_name MenuBackdrop
extends Node3D
## Fond 3D du menu principal : salle de bunker abandonnée, à peine éclairée.
## Lampe qui grésille et se balance, ampoule mourante, gyrophare rouge dans la
## pièce du fond (derrière une porte blindée entrouverte), rai de lumière
## froide par une grille, poussière, brume basse, sang, un cadavre, un zombie
## immobile dans la pénombre et une silhouette qui apparaît / disparaît dans
## l'embrasure pendant les coupures de courant. La caméra dérive très
## lentement (et suit un peu la souris).
## Tout est construit en code ; la géométrie statique est regroupée par
## matériau (un maillage par matériau) pour rester léger.

## Émis quand la silhouette du fond apparaît (true) ou disparaît (false).
signal presence(shown: bool)

const H := 3.4  # hauteur sous plafond
const Z_NEAR := 3.2
const Z_FAR := -20.2
const DOOR_X0 := 0.5
const DOOR_X1 := 2.1
const DOOR_H := 2.3
const CAM_POS := Vector3(-1.5, 1.58, -0.4)
const CAM_TARGET := Vector3(-1.9, 1.3, -20.0)
const WARM := Color(1.0, 0.7, 0.42)
const COLD := Color(0.5, 0.6, 0.85)
const RED := Color(1.0, 0.1, 0.05)

var camera: Camera3D
var _batches := {}
var _mats := {}
var _t := 0.0
var _rng := RandomNumberGenerator.new()
var _env: Environment
var _parallax := Vector2.ZERO

# Lampe principale (grésille, se balance).
var _lamp_pivot: Node3D
var _lamp: SpotLight3D
var _lamp_bounce: OmniLight3D
var _bulb_mat: StandardMaterial3D
var _lamp_on := true
var _lamp_timer := 2.5
var _lamp_level := 1.0
var _blackout := 0.0  # coupure forcée (s)
# Ampoule mourante au fond.
var _lamp2: SpotLight3D
var _bulb2_mat: StandardMaterial3D
var _lamp2_timer := 4.0
var _lamp2_on := false
# Gyrophare.
var _beacon_pivot: Node3D
var _beacon: SpotLight3D
var _back_glow: OmniLight3D
var _wall_lamp: OmniLight3D
var _bulb3_mat: StandardMaterial3D
# Rai de lumière.
var _moon: SpotLight3D
var _shaft_mat: ShaderMaterial
# Particules / brume.
var _dust: GPUParticles3D
var _smoke: Array[MeshInstance3D] = []
# Zombies.
var _stalker: Skeleton3D
var _stalker_b := {}
var _figure_root: Node3D
var _figure: Skeleton3D
var _figure_b := {}
var _figure_mesh: MeshInstance3D
var _figure_shown := false
var _figure_timer := 6.0
var _figure_pending := false
var _figure_t := 0.0


func _ready() -> void:
	_rng.seed = 7031
	_build_environment()
	_build_room()
	_build_props()
	_commit_batches()
	_build_blood()
	_build_lights()
	_build_zombies()
	_build_atmosphere()
	camera = Camera3D.new()
	camera.fov = 58.0
	camera.near = 0.05
	camera.far = 60.0
	add_child(camera)
	camera.position = CAM_POS
	camera.look_at(CAM_TARGET)
	camera.current = true
	for s in _smoke:
		var p := s.global_position
		s.look_at(Vector3(CAM_POS.x, p.y, CAM_POS.z))
	_apply_quality()
	Settings.changed.connect(_apply_quality)


# ------------------------------------------------------------------ construction

func _mat(key: String) -> Material:
	if _mats.has(key):
		return _mats[key]
	return WorldLook.surface(key)


func _append(key: String, mesh: Mesh, xf: Transform3D) -> void:
	if not _batches.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_batches[key] = st
	(_batches[key] as SurfaceTool).append_from(mesh, 0, xf)


func _xf(pos: Vector3, rot_deg := Vector3.ZERO, scl := Vector3.ONE) -> Transform3D:
	return Transform3D(Basis.from_euler(rot_deg * (PI / 180.0)).scaled(scl), pos)


func _box(key: String, size: Vector3, pos: Vector3, rot_deg := Vector3.ZERO) -> void:
	var m := BoxMesh.new()
	m.size = size
	_append(key, m, _xf(pos, rot_deg))


func _cyl(key: String, r_top: float, r_bot: float, height: float, pos: Vector3, rot_deg := Vector3.ZERO, sides := 10) -> void:
	var m := CylinderMesh.new()
	m.top_radius = r_top
	m.bottom_radius = r_bot
	m.height = height
	m.radial_segments = sides
	m.rings = 1
	_append(key, m, _xf(pos, rot_deg))


func _blob(key: String, size: Vector3, pos: Vector3, rot_deg := Vector3.ZERO) -> void:
	var m := SphereMesh.new()
	m.radius = 0.5
	m.height = 1.0
	m.radial_segments = 8
	m.rings = 4
	_append(key, m, _xf(pos, rot_deg, size))


func _commit_batches() -> void:
	for key in _batches:
		var mi := MeshInstance3D.new()
		mi.name = "Static_" + key
		mi.mesh = (_batches[key] as SurfaceTool).commit()
		mi.material_override = _mat(key)
		add_child(mi)
	_batches.clear()


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.32, 0.36, 0.46)
	env.ambient_light_energy = 0.1
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.1
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_strength = 1.0
	env.glow_bloom = 0.02
	env.glow_hdr_threshold = 0.9
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.fog_enabled = true
	env.fog_light_color = Color(0.03, 0.03, 0.04)
	env.fog_density = 0.024
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.72
	env.adjustment_contrast = 1.14
	_env = env
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _build_room() -> void:
	var room_len := Z_NEAR - Z_FAR
	var zc := (Z_NEAR + Z_FAR) * 0.5
	_box("concrete_dark", Vector3(9.8, 0.2, room_len), Vector3(0, -0.1, zc))
	_box("ceiling", Vector3(9.8, 0.2, room_len), Vector3(0, H + 0.1, zc))
	_box("wall_green", Vector3(0.4, H, room_len), Vector3(-4.7, H * 0.5, zc))
	_box("wall_rust", Vector3(0.4, H, room_len), Vector3(4.7, H * 0.5, zc))
	_box("wall_concrete", Vector3(9.8, H, 0.4), Vector3(0, H * 0.5, Z_NEAR + 0.2))
	# Mur du fond percé d'une porte.
	var zf := Z_FAR - 0.2
	_box("wall_concrete", Vector3(DOOR_X0 + 4.5, H, 0.4), Vector3((DOOR_X0 - 4.5) * 0.5, H * 0.5, zf))
	_box("wall_concrete", Vector3(4.5 - DOOR_X1, H, 0.4), Vector3((DOOR_X1 + 4.5) * 0.5, H * 0.5, zf))
	_box("wall_concrete", Vector3(DOOR_X1 - DOOR_X0, H - DOOR_H, 0.4), Vector3((DOOR_X0 + DOOR_X1) * 0.5, (H + DOOR_H) * 0.5, zf))
	# Encadrement et porte blindée entrouverte (charnière à droite).
	var dc := (DOOR_X0 + DOOR_X1) * 0.5
	_box("steel", Vector3(0.14, DOOR_H + 0.14, 0.6), Vector3(DOOR_X0 - 0.07, DOOR_H * 0.5, zf))
	_box("steel", Vector3(0.14, DOOR_H + 0.14, 0.6), Vector3(DOOR_X1 + 0.07, DOOR_H * 0.5, zf))
	_box("steel", Vector3(DOOR_X1 - DOOR_X0 + 0.28, 0.16, 0.6), Vector3(dc, DOOR_H + 0.08, zf))
	var leaf := BoxMesh.new()
	leaf.size = Vector3(1.55, 2.24, 0.12)
	var hinge := Transform3D(Basis(Vector3.UP, deg_to_rad(68.0)), Vector3(DOOR_X1, 0.0, zf + 0.32))
	_append("door", leaf, hinge * Transform3D(Basis.IDENTITY, Vector3(-0.78, 1.12, 0.0)))
	var wheel := CylinderMesh.new()
	wheel.top_radius = 0.2
	wheel.bottom_radius = 0.2
	wheel.height = 0.05
	wheel.radial_segments = 10
	_append("steel", wheel, hinge * Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(-1.1, 1.15, 0.1)))
	# Pièce du fond (cellule).
	var bz := zf - 3.2
	_box("concrete_dark", Vector3(4.6, 0.2, 6.0), Vector3(dc, -0.1, bz))
	_box("ceiling", Vector3(4.6, 0.2, 6.0), Vector3(dc, 3.1, bz))
	_box("wall_cell", Vector3(0.3, 3.2, 6.0), Vector3(dc - 2.3, 1.5, bz))
	_box("wall_cell", Vector3(0.3, 3.2, 6.0), Vector3(dc + 2.3, 1.5, bz))
	_box("wall_cell", Vector3(4.6, 3.2, 0.3), Vector3(dc, 1.5, bz - 3.0))
	# Chaise à sangles dans la cellule.
	_box("metal", Vector3(0.55, 0.06, 0.55), Vector3(dc - 0.9, 0.5, bz - 1.6))
	_box("metal", Vector3(0.55, 0.8, 0.06), Vector3(dc - 0.9, 0.9, bz - 1.9))
	for lx in [-0.24, 0.24]:
		for lz in [-0.24, 0.24]:
			_box("metal", Vector3(0.05, 0.5, 0.05), Vector3(dc - 0.9 + lx, 0.25, bz - 1.6 + lz))
	# Nervures : pilastres et poutres tous les 4 m.
	for z in [-1.8, -5.8, -9.8, -13.8, -17.8]:
		_box("concrete", Vector3(0.36, H, 0.55), Vector3(-4.33, H * 0.5, z))
		_box("concrete", Vector3(0.36, H, 0.55), Vector3(4.33, H * 0.5, z))
		_box("concrete", Vector3(9.0, 0.42, 0.55), Vector3(0, H - 0.21, z))
		# Colliers des tuyaux.
		_box("steel", Vector3(0.9, 0.06, 0.1), Vector3(3.75, 2.96, z + 0.35))
	# Tuyaux le long du plafond et chemin de câbles.
	_cyl("steel", 0.12, 0.12, Z_NEAR - Z_FAR, Vector3(3.85, 2.98, zc), Vector3(90, 0, 0), 12)
	_cyl("steel", 0.07, 0.07, Z_NEAR - Z_FAR, Vector3(3.5, 3.12, zc), Vector3(90, 0, 0), 8)
	_cyl("metal", 0.09, 0.09, Z_NEAR - Z_FAR, Vector3(-3.95, 3.05, zc), Vector3(90, 0, 0), 8)
	_box("metal", Vector3(0.4, 0.04, Z_NEAR - Z_FAR), Vector3(-3.55, 2.72, zc))
	_cyl("steel", 0.1, 0.1, H, Vector3(4.28, H * 0.5, -7.3), Vector3.ZERO, 10)
	var valve := CylinderMesh.new()
	valve.top_radius = 0.22
	valve.bottom_radius = 0.22
	valve.height = 0.04
	valve.radial_segments = 10
	_append("steel", valve, _xf(Vector3(4.08, 1.35, -7.3), Vector3(0, 0, 90)))
	# Grille au plafond (rai de lumière).
	for i in 5:
		_box("steel", Vector3(0.9, 0.05, 0.05), Vector3(-2.5, H - 0.02, -10.9 + i * 0.2))


func _build_props() -> void:
	# Table renversée et chaise, à gauche au premier plan.
	_box("wood", Vector3(1.4, 0.05, 0.8), Vector3(-3.1, 0.42, -2.9), Vector3(0, 15, 72))
	_box("wood", Vector3(0.05, 0.7, 0.05), Vector3(-2.7, 0.8, -2.6), Vector3(0, 15, -18))
	_box("wood", Vector3(0.05, 0.7, 0.05), Vector3(-2.75, 0.78, -3.3), Vector3(0, 15, -18))
	_box("metal", Vector3(0.45, 0.05, 0.45), Vector3(-2.0, 0.25, -3.9), Vector3(80, 30, 0))
	_box("metal", Vector3(0.45, 0.5, 0.05), Vector3(-2.2, 0.05, -3.6), Vector3(10, 30, 0))
	# Casier ouvert contre le mur gauche.
	_box("metal", Vector3(0.5, 1.9, 0.9), Vector3(-4.25, 0.95, -4.1))
	_box("metal", Vector3(0.04, 1.8, 0.44), Vector3(-3.85, 0.95, -3.5), Vector3(0, -55, 0))
	# Brancard renversé (droite).
	_box("fabric", Vector3(0.8, 0.14, 1.9), Vector3(2.2, 0.42, -6.8), Vector3(0, 18, 74))
	_box("steel", Vector3(0.86, 0.04, 1.96), Vector3(2.02, 0.36, -6.86), Vector3(0, 18, 74))
	for dz in [-0.85, 0.85]:
		_box("steel", Vector3(0.04, 0.7, 0.04), Vector3(1.75, 0.2 + dz * 0.0, -6.8 + dz), Vector3(0, 18, -16))
	# Caisses empilées (gauche).
	_box("crate", Vector3(1.0, 0.8, 0.8), Vector3(-3.7, 0.4, -8.6))
	_box("crate", Vector3(0.8, 0.7, 0.8), Vector3(-3.75, 1.15, -8.5), Vector3(0, 9, 0))
	_box("crate", Vector3(0.7, 0.7, 0.7), Vector3(-3.4, 0.35, -9.6), Vector3(0, 24, 0))
	_box("crate", Vector3(0.6, 0.5, 0.6), Vector3(-2.8, 0.25, -8.4), Vector3(0, -12, 0))
	# Fûts (droite).
	_cyl("barrel", 0.3, 0.3, 0.9, Vector3(3.85, 0.45, -11.2), Vector3.ZERO, 12)
	_cyl("barrel", 0.3, 0.3, 0.9, Vector3(3.9, 0.45, -11.9), Vector3.ZERO, 12)
	_cyl("barrel", 0.3, 0.3, 0.9, Vector3(3.1, 0.3, -12.3), Vector3(90, 35, 0), 12)
	# Sacs de sable : barricade à gauche avant la porte.
	for i in 6:
		_blob("fabric", Vector3(0.62, 0.24, 0.36), Vector3(-3.2 + i * 0.55, 0.12, -15.6 + (i % 2) * 0.05), Vector3(0, _rng.randf_range(-8, 8), 0))
	for i in 5:
		_blob("fabric", Vector3(0.62, 0.24, 0.36), Vector3(-2.95 + i * 0.55, 0.34, -15.6), Vector3(0, _rng.randf_range(-10, 10), 0))
	for i in 3:
		_blob("fabric", Vector3(0.62, 0.24, 0.36), Vector3(-2.6 + i * 0.55, 0.55, -15.62), Vector3(0, _rng.randf_range(-10, 10), 0))
	# Chaîne et crochet pendus à une poutre.
	for i in 11:
		var y := H - 0.42 - i * 0.1
		if i % 2 == 0:
			_box("steel", Vector3(0.03, 0.11, 0.012), Vector3(0.35, y, -9.8))
		else:
			_box("steel", Vector3(0.012, 0.11, 0.03), Vector3(0.35, y, -9.8))
	_box("steel", Vector3(0.025, 0.2, 0.025), Vector3(0.35, H - 1.6, -9.8))
	_box("steel", Vector3(0.12, 0.025, 0.025), Vector3(0.4, H - 1.7, -9.8), Vector3(0, 0, 30))
	_box("steel", Vector3(0.025, 0.08, 0.025), Vector3(0.46, H - 1.64, -9.8))
	# Papiers au sol.
	_mats["paper"] = _std(Color(0.42, 0.4, 0.34), 1.0)
	for i in 9:
		var p := Vector3(_rng.randf_range(-3.0, 2.5), 0.004, _rng.randf_range(-12.0, -2.0))
		_box("paper", Vector3(0.21, 0.004, 0.29), p, Vector3(0, _rng.randf_range(0, 180), 0))
	# Mare de sang brillante sous le cadavre.
	_mats["blood_pool"] = _std(Color(0.1, 0.0, 0.0), 0.12)
	_blob("blood_pool", Vector3(1.3, 0.012, 0.9), Vector3(0.3, 0.004, -7.45), Vector3(0, 25, 0))


func _std(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


func _decal(tex: Texture2D, pos: Vector3, size: Vector3, rot_deg: Vector3, col: Color) -> void:
	var d := Decal.new()
	d.texture_albedo = tex
	d.size = size
	d.modulate = col
	d.albedo_mix = 1.0
	d.upper_fade = 0.2
	d.lower_fade = 0.2
	d.position = pos
	d.rotation_degrees = rot_deg
	add_child(d)


func _build_blood() -> void:
	var dark := Color(0.5, 0.02, 0.018)
	# Sol : mare sous le cadavre et traînée jusqu'à la porte.
	_decal(Fx.blood_splat_texture(0), Vector3(0.2, 0.05, -7.25), Vector3(3.4, 0.4, 3.4), Vector3(0, 20, 0), dark)
	_decal(BloodTex.streak(11), Vector3(0.8, 0.05, -13.5), Vector3(0.9, 0.4, 12.0), Vector3(0, -4.8, 0), Color(0.42, 0.01, 0.01, 0.95))
	_decal(Fx.blood_splat_texture(2), Vector3(-1.4, 0.05, -12.5), Vector3(1.2, 0.4, 1.2), Vector3(0, 70, 0), dark)
	_decal(Fx.blood_splat_texture(1), Vector3(2.8, 0.05, -4.2), Vector3(0.9, 0.4, 0.9), Vector3(0, 10, 0), dark)
	# Mur gauche : mains ensanglantées qui glissent, éclaboussures.
	var hand := BloodTex.handprint(3)
	_decal(hand, Vector3(4.48, 1.45, -9.4), Vector3(0.34, 0.3, 0.34), Vector3(8, 0, 90), dark)
	_decal(hand, Vector3(4.48, 1.3, -9.85), Vector3(0.32, 0.3, 0.32), Vector3(-12, 0, 90), dark)
	_decal(BloodTex.streak(5), Vector3(4.48, 0.85, -9.6), Vector3(0.3, 0.3, 1.1), Vector3(90, 0, 90), Color(0.32, 0.01, 0.01, 0.9))
	_decal(Fx.blood_splat_texture(3), Vector3(-4.48, 1.6, -11.8), Vector3(1.6, 0.3, 1.6), Vector3(0, 0, -90), dark)
	# Mur droit : giclée près du brancard.
	_decal(Fx.blood_splat_texture(1), Vector3(4.48, 1.2, -6.5), Vector3(1.4, 0.3, 1.4), Vector3(0, 0, 90), dark)
	# Message tracé au sang.
	var msg := Label3D.new()
	msg.text = Lang.t("ILS ENTENDENT.", "THEY HEAR.")
	msg.font = BloodTex.scrawl_font()
	msg.font_size = 110
	msg.pixel_size = 0.0042
	msg.modulate = Color(0.45, 0.02, 0.02)
	msg.outline_size = 0
	msg.shaded = true
	msg.position = Vector3(4.47, 1.95, -11.0)
	msg.rotation_degrees = Vector3(0, -90, 3)
	add_child(msg)
	# Marquage au pochoir (mur droit).
	var plate := Label3D.new()
	plate.text = Lang.t("SECTEUR K7", "SECTOR K7")
	plate.font = UiStyle.font("stencil")
	plate.font_size = 120
	plate.pixel_size = 0.004
	plate.modulate = Color(0.55, 0.46, 0.2, 0.75)
	plate.outline_size = 0
	plate.shaded = true
	plate.position = Vector3(4.47, 2.15, -6.4)
	plate.rotation_degrees = Vector3(0, -90, 0)
	add_child(plate)
	var sub := plate.duplicate() as Label3D
	sub.text = Lang.t("NIVEAU -3  ·  ACCÈS RESTREINT", "LEVEL -3  ·  RESTRICTED ACCESS")
	sub.font_size = 44
	sub.position = Vector3(4.47, 1.8, -6.4)
	add_child(sub)
	var stripes := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(3.0, 0.16)
	stripes.mesh = q
	var sm := StandardMaterial3D.new()
	sm.albedo_texture = BloodTex.hazard_stripes()
	sm.albedo_color = Color(0.7, 0.7, 0.65)
	sm.roughness = 0.9
	sm.uv1_scale = Vector3(8, 1, 1)
	stripes.material_override = sm
	stripes.position = Vector3(4.48, 1.55, -6.4)
	stripes.rotation_degrees = Vector3(0, -90, 0)
	add_child(stripes)


func _build_lights() -> void:
	# Lampe principale suspendue (se balance, grésille, porte les ombres).
	_lamp_pivot = Node3D.new()
	_lamp_pivot.position = Vector3(-0.9, H, -5.3)
	add_child(_lamp_pivot)
	_bulb_mat = StandardMaterial3D.new()
	_bulb_mat.albedo_color = Color(1.0, 0.85, 0.6)
	_bulb_mat.emission_enabled = true
	_bulb_mat.emission = WARM
	_bulb_mat.emission_energy_multiplier = 8.0
	_lamp_pivot.add_child(_mesh_node(_box_mesh(Vector3(0.015, 0.55, 0.015)), Vector3(0, -0.27, 0), WorldLook.surface("steel")))
	var shade := CylinderMesh.new()
	shade.top_radius = 0.07
	shade.bottom_radius = 0.28
	shade.height = 0.2
	shade.radial_segments = 12
	shade.cap_bottom = false
	var shade_mat := _std(Color(0.12, 0.13, 0.11), 0.6)
	shade_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	shade_mat.metallic = 0.6
	_lamp_pivot.add_child(_mesh_node(shade, Vector3(0, -0.62, 0), shade_mat))
	var bulb := SphereMesh.new()
	bulb.radius = 0.055
	bulb.height = 0.11
	bulb.radial_segments = 8
	bulb.rings = 4
	_lamp_pivot.add_child(_mesh_node(bulb, Vector3(0, -0.7, 0), _bulb_mat))
	_lamp = SpotLight3D.new()
	_lamp.light_color = WARM
	_lamp.light_energy = 5.0
	_lamp.spot_range = 7.5
	_lamp.spot_angle = 62.0
	_lamp.spot_attenuation = 0.9
	_lamp.shadow_enabled = true
	_lamp.shadow_blur = 1.5
	_lamp.position = Vector3(0, -0.72, 0)
	_lamp.rotation_degrees = Vector3(-90, 0, 0)
	_lamp_pivot.add_child(_lamp)
	_lamp_bounce = OmniLight3D.new()
	_lamp_bounce.light_color = Color(0.9, 0.6, 0.4)
	_lamp_bounce.light_energy = 0.55
	_lamp_bounce.omni_range = 5.0
	_lamp_bounce.position = Vector3(-0.9, 0.5, -5.3)
	add_child(_lamp_bounce)

	# Ampoule mourante au fond, près du zombie immobile.
	_bulb2_mat = _bulb_mat.duplicate()
	var cage := Node3D.new()
	cage.position = Vector3(2.3, H - 0.25, -13.3)
	add_child(cage)
	cage.add_child(_mesh_node(bulb, Vector3.ZERO, _bulb2_mat))
	cage.add_child(_mesh_node(_box_mesh(Vector3(0.2, 0.03, 0.2)), Vector3(0, 0.12, 0), WorldLook.surface("steel")))
	_lamp2 = SpotLight3D.new()
	_lamp2.light_color = WARM
	_lamp2.light_energy = 0.0
	_lamp2.spot_range = 7.0
	_lamp2.spot_angle = 70.0
	_lamp2.rotation_degrees = Vector3(-90, 0, 0)
	cage.add_child(_lamp2)

	# Gyrophare rouge dans la cellule : balaye la pièce et, par la porte,
	# projette les ombres jusqu'à la caméra.
	_beacon_pivot = Node3D.new()
	_beacon_pivot.position = Vector3(DOOR_X0 + 1.5, 2.75, Z_FAR - 2.6)
	add_child(_beacon_pivot)
	var dome_mat := StandardMaterial3D.new()
	dome_mat.albedo_color = Color(0.6, 0.05, 0.03)
	dome_mat.emission_enabled = true
	dome_mat.emission = RED
	dome_mat.emission_energy_multiplier = 4.0
	var dome := SphereMesh.new()
	dome.radius = 0.12
	dome.height = 0.2
	dome.radial_segments = 10
	dome.rings = 4
	_beacon_pivot.add_child(_mesh_node(dome, Vector3(0, 0.02, 0), dome_mat))
	_beacon = SpotLight3D.new()
	_beacon.light_color = RED
	_beacon.light_energy = 14.0
	_beacon.spot_range = 22.0
	_beacon.spot_angle = 22.0
	_beacon.spot_attenuation = 0.6
	_beacon.shadow_enabled = true
	_beacon.rotation_degrees = Vector3(-8, 0, 0)
	_beacon_pivot.add_child(_beacon)
	_back_glow = OmniLight3D.new()
	_back_glow.light_color = Color(1.0, 0.12, 0.06)
	_back_glow.light_energy = 4.0
	_back_glow.omni_range = 7.0
	_back_glow.position = Vector3((DOOR_X0 + DOOR_X1) * 0.5, 1.6, Z_FAR - 4.5)
	add_child(_back_glow)

	# Lueur rouge qui déborde de la porte sur le sol du couloir (contre-jour
	# des silhouettes) et petite lampe de secours au-dessus de la porte.
	var spill := OmniLight3D.new()
	spill.light_color = Color(1.0, 0.14, 0.07)
	spill.light_energy = 1.8
	spill.omni_range = 6.5
	spill.omni_attenuation = 1.6
	spill.position = Vector3((DOOR_X0 + DOOR_X1) * 0.5, 1.0, Z_FAR - 1.7)
	add_child(spill)
	var exit_mat := dome_mat.duplicate() as StandardMaterial3D
	exit_mat.emission_energy_multiplier = 2.5
	add_child(_mesh_node(_box_mesh(Vector3(0.36, 0.12, 0.1)), Vector3((DOOR_X0 + DOOR_X1) * 0.5, DOOR_H + 0.3, Z_FAR + 0.05), exit_mat))
	# Applique grillagée sur le mur droit (révèle la tôle rouillée).
	_wall_lamp = OmniLight3D.new()
	_wall_lamp.light_color = Color(1.0, 0.62, 0.35)
	_wall_lamp.light_energy = 0.9
	_wall_lamp.omni_range = 4.5
	_wall_lamp.omni_attenuation = 1.4
	_wall_lamp.position = Vector3(4.1, 2.55, -8.6)
	add_child(_wall_lamp)
	_bulb3_mat = _bulb_mat.duplicate()
	_bulb3_mat.emission_energy_multiplier = 3.0
	add_child(_mesh_node(bulb, Vector3(4.33, 2.55, -8.6), _bulb3_mat))
	add_child(_mesh_node(_box_mesh(Vector3(0.14, 0.22, 0.2)), Vector3(4.42, 2.55, -8.6), WorldLook.surface("steel")))

	# Lumière froide tombant d'une grille du plafond.
	_moon = SpotLight3D.new()
	_moon.light_color = COLD
	_moon.light_energy = 3.2
	_moon.spot_range = 6.0
	_moon.spot_angle = 20.0
	_moon.spot_attenuation = 0.5
	_moon.position = Vector3(-2.5, H + 0.3, -10.5)
	_moon.rotation_degrees = Vector3(-80, 0, -8)
	add_child(_moon)
	var cone := CylinderMesh.new()
	cone.top_radius = 0.42
	cone.bottom_radius = 1.25
	cone.height = H
	cone.radial_segments = 16
	cone.rings = 1
	cone.cap_top = false
	cone.cap_bottom = false
	_shaft_mat = ShaderMaterial.new()
	_shaft_mat.shader = preload("res://assets/shaders/menu_shaft.gdshader")
	_shaft_mat.set_shader_parameter("tint", COLD)
	_shaft_mat.set_shader_parameter("intensity", 0.1)
	var shaft := _mesh_node(cone, Vector3(-2.3, H * 0.5, -10.35), _shaft_mat)
	shaft.rotation_degrees = Vector3(-10, 0, -8)
	shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shaft)


func _box_mesh(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _mesh_node(mesh: Mesh, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	return mi


func _build_zombies() -> void:
	# Cadavre étendu sur le dos, bras écartés.
	var corpse := ZombieModel.build(14)
	var cb := RigBuilder.bone_indices(corpse)
	var holder := Node3D.new()
	holder.position = Vector3(0.25, 0.13, -7.35)
	holder.rotation_degrees = Vector3(-90, 160, 0)
	holder.rotation_order = EULER_ORDER_YXZ
	holder.add_child(corpse)
	add_child(holder)
	_pose(corpse, cb, {"arm_l": Vector3(0, 0, 70), "arm_r": Vector3(0, 0, -95), "forearm_r": Vector3(0, 0, -30),
			"head": Vector3(0, 35, 10), "thigh_l": Vector3(0, 0, 12), "shin_l": Vector3(-25, 0, 0)})
	(corpse.get_node("Mesh") as MeshInstance3D).set_instance_shader_parameter("eye_glow", 0.0)
	# Zombie immobile dans la pénombre, tête penchée, qui oscille à peine.
	_stalker = ZombieModel.build(5)
	_stalker_b = RigBuilder.bone_indices(_stalker)
	var sh := Node3D.new()
	sh.position = Vector3(3.3, 0.0, -14.6)
	sh.rotation_degrees = Vector3(0, -28, 0)
	sh.add_child(_stalker)
	add_child(sh)
	(_stalker.get_node("Mesh") as MeshInstance3D).set_instance_shader_parameter("eye_glow", 0.9)
	# Silhouette dans l'embrasure de la porte (apparaît / disparaît).
	_figure = ZombieModel.build(23)
	_figure_b = RigBuilder.bone_indices(_figure)
	_figure_root = Node3D.new()
	_figure_root.position = Vector3((DOOR_X0 + DOOR_X1) * 0.5 - 0.1, 0.0, Z_FAR - 0.9)
	_figure_root.add_child(_figure)
	_figure_root.visible = false
	add_child(_figure_root)
	_figure_mesh = _figure.get_node("Mesh")
	_pose(_figure, _figure_b, {"arm_l": Vector3(8, 0, 6), "arm_r": Vector3(-6, 0, -4), "head": Vector3(12, 0, -14)})


## Rotations d'os en degrés (repère de repos de RigBuilder).
func _pose(skel: Skeleton3D, bones: Dictionary, rot: Dictionary) -> void:
	for b in rot:
		skel.set_bone_pose_rotation(bones[b], Quaternion.from_euler(rot[b] * (PI / 180.0)))


func _build_atmosphere() -> void:
	# Poussière en suspension (éclairée : visible dans les faisceaux).
	_dust = GPUParticles3D.new()
	_dust.amount = 260
	_dust.lifetime = 16.0
	_dust.preprocess = 16.0
	_dust.position = Vector3(-0.5, 1.7, -7.5)
	_dust.visibility_aabb = AABB(Vector3(-5, -2.5, -10), Vector3(10, 5, 20))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(4.0, 1.6, 8.5)
	pm.gravity = Vector3(0, -0.006, 0)
	pm.direction = Vector3(0.4, 0.2, 0.1)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.01
	pm.initial_velocity_max = 0.06
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_noise_scale = 4.0
	pm.turbulence_influence_min = 0.01
	pm.turbulence_influence_max = 0.04
	pm.scale_min = 0.5
	pm.scale_max = 1.6
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0))
	ramp.set_color(1, Color(1, 1, 1, 0))
	ramp.add_point(0.2, Color(1, 1, 1, 1))
	ramp.add_point(0.8, Color(1, 1, 1, 1))
	var rt := GradientTexture1D.new()
	rt.gradient = ramp
	pm.color_ramp = rt
	_dust.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.016, 0.016)
	var dm := StandardMaterial3D.new()
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.vertex_color_use_as_albedo = true
	dm.albedo_color = Color(1.0, 0.95, 0.85, 0.85)
	dm.albedo_texture = Fx.soft_dot_texture()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	q.material = dm
	_dust.draw_pass_1 = q
	add_child(_dust)
	# Brume basse et volutes de fumée.
	var smoke_mat := ShaderMaterial.new()
	smoke_mat.shader = preload("res://assets/shaders/menu_smoke.gdshader")
	var spots := [
		[Vector3(-2.4, 0.4, -5.2), Vector2(3.5, 1.0)],
		[Vector3(2.8, 0.4, -9.0), Vector2(3.0, 1.0)],
		[Vector3(-2.2, 0.8, -10.6), Vector2(3.0, 2.4)],
		[Vector3(1.2, 0.9, -18.2), Vector2(5.0, 1.6)],
		[Vector3(1.3, 1.1, -20.6), Vector2(2.6, 2.4)],
		[Vector3(-1.0, 2.6, -12.0), Vector2(7.0, 1.3)],
		[Vector3(3.1, 0.45, -13.6), Vector2(2.5, 1.1)],
	]
	for i in spots.size():
		var mi := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = spots[i][1]
		mi.mesh = qm
		mi.material_override = smoke_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = spots[i][0]
		mi.set_instance_shader_parameter("seed", float(i) * 1.37)
		add_child(mi)
		_smoke.append(mi)


func _apply_quality() -> void:
	var q: int = Settings.quality
	_env.glow_enabled = q >= Settings.Quality.MEDIUM
	_lamp.shadow_enabled = q >= Settings.Quality.MEDIUM
	_beacon.shadow_enabled = q >= Settings.Quality.HIGH
	_lamp2.shadow_enabled = q >= Settings.Quality.HIGH
	_moon.shadow_enabled = q >= Settings.Quality.HIGH
	_dust.amount = [120, 260, 400][q]
	for s in _smoke:
		s.visible = q >= Settings.Quality.MEDIUM


# ------------------------------------------------------------------ animation

func _process(delta: float) -> void:
	_t += delta
	_animate_camera(delta)
	_animate_lamps(delta)
	# Gyrophare : tour complet en 5 s.
	_beacon_pivot.rotation.y = fmod(_t * TAU / 5.0, TAU)
	# Zombie immobile : oscillation infime, la tête suit lentement.
	var sway := sin(_t * 0.45)
	_pose(_stalker, _stalker_b, {
		"spine": Vector3(4 + sway * 2.0, 0, sway * 1.5),
		"head": Vector3(18, -22 + sin(_t * 0.21) * 6.0, 26 + sway * 3.0),
		"arm_l": Vector3(-6 + sway * 2.0, 0, 5), "arm_r": Vector3(-10, 0, -4 - sway * 2.0),
		"forearm_r": Vector3(-20, 0, 0)})
	_animate_figure(delta)


func _animate_camera(delta: float) -> void:
	var vp := get_viewport()
	if vp:
		var r := vp.get_visible_rect().size
		var m := vp.get_mouse_position()
		var target := Vector2.ZERO
		if r.x > 0.0 and r.y > 0.0:
			target = (m / r - Vector2(0.5, 0.5)).clampf(-0.5, 0.5)
		_parallax = _parallax.lerp(target, clampf(delta * 0.8, 0.0, 1.0))
	var drift := Vector3(sin(_t * 0.071) * 0.22, sin(_t * 0.113) * 0.05, sin(_t * 0.053) * 0.35)
	camera.position = CAM_POS + drift
	camera.look_at(CAM_TARGET + Vector3(sin(_t * 0.061) * 0.6, sin(_t * 0.089) * 0.25, 0))
	camera.rotate_object_local(Vector3.UP, -_parallax.x * 0.05)
	camera.rotate_object_local(Vector3.RIGHT, -_parallax.y * 0.03)
	camera.rotate_object_local(Vector3.FORWARD, sin(_t * 0.043) * 0.008)


func _animate_lamps(delta: float) -> void:
	# Balancement de la lampe.
	_lamp_pivot.rotation = Vector3(sin(_t * 0.9) * 0.035, 0, sin(_t * 0.67 + 1.0) * 0.05)
	# Grésillement : phases stables, coupures brèves, rafales.
	_lamp_timer -= delta
	if _lamp_timer <= 0.0:
		_lamp_on = not _lamp_on
		if _lamp_on:
			_lamp_timer = _rng.randf_range(0.03, 0.2) if _rng.randf() < 0.45 else _rng.randf_range(1.5, 6.0)
		else:
			_lamp_timer = _rng.randf_range(0.03, 0.14)
	if _blackout > 0.0:
		_blackout -= delta
	var on := _lamp_on and _blackout <= 0.0
	var target := 1.0 if on else 0.04
	_lamp_level = target if not on else lerpf(_lamp_level, target, clampf(delta * 30.0, 0.0, 1.0))
	var buzz := 0.93 + 0.07 * sin(_t * 120.0) * sin(_t * 7.3)
	_lamp.light_energy = 5.0 * _lamp_level * buzz
	_lamp_bounce.light_energy = 0.55 * _lamp_level
	var wall := (0.05 if _blackout > 0.0 else 0.85 + 0.15 * sin(_t * 97.0) * sin(_t * 3.1))
	_wall_lamp.light_energy = 0.9 * wall
	_bulb3_mat.emission_energy_multiplier = 3.0 * wall
	_bulb_mat.emission_energy_multiplier = 8.0 * _lamp_level + 0.2
	_shaft_mat.set_shader_parameter("flicker", 0.85 + 0.15 * sin(_t * 0.7) if _blackout <= 0.0 else 0.3)
	# Ampoule mourante : presque toujours éteinte, sursauts rares.
	_lamp2_timer -= delta
	if _lamp2_timer <= 0.0:
		_lamp2_on = not _lamp2_on
		if _lamp2_on:
			_lamp2_timer = _rng.randf_range(0.04, 0.35)
		else:
			_lamp2_timer = _rng.randf_range(0.05, 0.25) if _rng.randf() < 0.5 else _rng.randf_range(3.0, 9.0)
	var l2 := 1.0 if _lamp2_on and _blackout <= 0.0 else 0.0
	_lamp2.light_energy = 2.4 * l2
	_bulb2_mat.emission_energy_multiplier = 6.0 * l2 + 0.05


## Coupure de courant forcée (lampes éteintes), en secondes.
func blackout(duration: float) -> void:
	_blackout = maxf(_blackout, duration)


func _animate_figure(delta: float) -> void:
	_figure_timer -= delta
	if _figure_timer <= 0.0 and not _figure_pending:
		_figure_pending = true
		blackout(_rng.randf_range(0.18, 0.32))
	# Le changement a lieu dans le noir.
	if _figure_pending and _blackout > 0.0 and _blackout < 0.1:
		_figure_pending = false
		_set_figure(not _figure_shown)
	if _figure_shown:
		_figure_t += delta
		# Elle tourne lentement la tête vers la caméra, oscille à peine.
		var k := clampf(_figure_t / 4.0, 0.0, 1.0)
		_pose(_figure, _figure_b, {
			"head": Vector3(12 - 10 * k, lerpf(-35, 8, k), lerpf(-14, 10, k)),
			"spine": Vector3(3, 0, sin(_t * 0.5) * 1.5),
			"arm_l": Vector3(8, 0, 6), "arm_r": Vector3(-6, 0, -4)})
		_figure_mesh.set_instance_shader_parameter("eye_glow", k * 1.2)


func _set_figure(shown: bool) -> void:
	_figure_shown = shown
	_figure_root.visible = shown
	_figure_t = 0.0
	_figure_timer = _rng.randf_range(5.0, 8.0) if shown else _rng.randf_range(10.0, 18.0)
	presence.emit(shown)


## Pour les tests : fait apparaître (ou disparaître) la silhouette tout de suite.
func force_figure(shown: bool) -> void:
	if shown != _figure_shown:
		_set_figure(shown)
	_figure_t = 4.0 if shown else 0.0


func figure_visible() -> bool:
	return _figure_shown
