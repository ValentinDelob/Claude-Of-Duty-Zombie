class_name PowerupModels
extends RefCounted
## Modèles 3D procéduraux des bonus (~50 cm, centrés sur l'origine).
## Crâne (mort instantanée), bombe (nuke), « x2 » (points doubles), caisse de
## munitions, marteau et scie (charpentier), étiquette de prix (liquidation).

static var _mats: Dictionary = {}


static func mat(key: String) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	match key:
		"bone":
			m.albedo_color = Color(0.86, 0.82, 0.7)
			m.roughness = 0.7
		"socket":
			m.albedo_color = Color(0.02, 0.02, 0.02)
			m.emission_enabled = true
			m.emission = Color(0.2, 1.0, 0.25)
			m.emission_energy_multiplier = 1.5
		"gold":
			m.albedo_color = Color(0.95, 0.72, 0.2)
			m.metallic = 0.9
			m.roughness = 0.3
			m.emission_enabled = true
			m.emission = Color(0.9, 0.6, 0.15)
			m.emission_energy_multiplier = 0.6
		"bomb":
			m.albedo_color = Color(0.22, 0.26, 0.2)
			m.metallic = 0.6
			m.roughness = 0.45
		"hazard":
			m.albedo_color = Color(0.95, 0.75, 0.1)
			m.roughness = 0.5
		"olive":
			m.albedo_color = Color(0.25, 0.3, 0.16)
			m.roughness = 0.8
		"brass":
			m.albedo_color = Color(0.85, 0.62, 0.25)
			m.metallic = 0.9
			m.roughness = 0.35
		"steel":
			m.albedo_color = Color(0.55, 0.57, 0.6)
			m.metallic = 0.9
			m.roughness = 0.35
		"wood":
			m.albedo_color = Color(0.45, 0.28, 0.14)
			m.roughness = 0.8
		"tag":
			m.albedo_color = Color(0.85, 0.08, 0.05)
			m.roughness = 0.6
			m.emission_enabled = true
			m.emission = Color(0.8, 0.05, 0.02)
			m.emission_energy_multiplier = 0.4
		"paper":
			m.albedo_color = Color(0.92, 0.9, 0.82)
			m.roughness = 0.9
		"halo":
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
			m.albedo_texture = Fx.soft_dot_texture()
			m.albedo_color = Color(0.25, 1.0, 0.3, 0.85)
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.no_depth_test = false
	# Légère lumière propre : le bonus reste lisible dans les salles sombres.
	if key != "halo" and not m.emission_enabled:
		m.emission_enabled = true
		m.emission = m.albedo_color
		m.emission_energy_multiplier = 0.45
	_mats[key] = m
	return m


static func build(type: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Model"
	match type:
		PowerupRules.INSTA_KILL:
			_skull(root)
		PowerupRules.NUKE:
			_bomb(root)
		PowerupRules.DOUBLE_POINTS:
			_x2(root)
		PowerupRules.MAX_AMMO:
			_ammo_crate(root)
		PowerupRules.CARPENTER:
			_hammer_saw(root)
		PowerupRules.FIRE_SALE:
			_price_tag(root)
		_:
			_box(root, Vector3(0.3, 0.3, 0.3), Vector3.ZERO, mat("gold"))
	return root


## Halo vert lumineux (sprite additif).
static func halo(size := 1.3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	mi.mesh = q
	mi.material_override = mat("halo")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


# --------------------------------------------------------------------------

static func _box(parent: Node3D, size: Vector3, pos: Vector3, m: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.position = pos
	mi.rotation = rot
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func _cyl(parent: Node3D, r_top: float, r_bot: float, h: float, pos: Vector3, m: Material, rot := Vector3.ZERO, seg := 12) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bot
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	mi.mesh = c
	mi.position = pos
	mi.rotation = rot
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func _sphere(parent: Node3D, r: float, pos: Vector3, m: Material, scale := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 14
	s.rings = 8
	mi.mesh = s
	mi.position = pos
	mi.scale = scale
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## Crâne : calotte, pommettes, mâchoire à dents, orbites luisantes.
static func _skull(root: Node3D) -> void:
	var bone := mat("bone")
	_sphere(root, 0.19, Vector3(0, 0.06, -0.02), bone, Vector3(1.0, 1.0, 1.08))
	_box(root, Vector3(0.28, 0.12, 0.2), Vector3(0, -0.07, 0.06), bone)
	_box(root, Vector3(0.2, 0.08, 0.16), Vector3(0, -0.16, 0.08), bone)
	for i in 5:
		_box(root, Vector3(0.028, 0.045, 0.02), Vector3(-0.07 + i * 0.035, -0.115, 0.165), bone)
	var eye := mat("socket")
	for x in [-0.075, 0.075]:
		_sphere(root, 0.052, Vector3(x, 0.02, 0.15), eye, Vector3(1.0, 0.85, 0.5))
	# Cavité nasale.
	_box(root, Vector3(0.04, 0.06, 0.02), Vector3(0, -0.05, 0.165), eye, Vector3(0, 0, PI * 0.25))


## Bombe : ogive, empennage, bande jaune.
static func _bomb(root: Node3D) -> void:
	var body := Node3D.new()
	body.rotation = Vector3(0, 0, PI * 0.5)
	root.add_child(body)
	var bm := mat("bomb")
	_sphere(body, 0.16, Vector3(0, 0.0, 0), bm, Vector3(1.0, 1.6, 1.0))
	_cyl(body, 0.06, 0.11, 0.16, Vector3(0, -0.3, 0), bm)
	_cyl(body, 0.165, 0.165, 0.06, Vector3(0, 0.1, 0), mat("hazard"))
	for k in 4:
		var fin := Node3D.new()
		fin.rotation.y = k * PI * 0.5
		body.add_child(fin)
		_box(fin, Vector3(0.02, 0.14, 0.22), Vector3(0, -0.36, 0), mat("hazard"))
	_cyl(body, 0.13, 0.13, 0.02, Vector3(0, -0.43, 0), bm)
	root.position.x = 0.04


## « x2 » doré en volume (segments).
static func _x2(root: Node3D) -> void:
	var g := mat("gold")
	var d := 0.08
	# x
	_box(root, Vector3(0.05, 0.26, d), Vector3(-0.16, -0.03, 0), g, Vector3(0, 0, 0.7))
	_box(root, Vector3(0.05, 0.26, d), Vector3(-0.16, -0.03, 0), g, Vector3(0, 0, -0.7))
	# 2 (affichage à segments)
	var w := 0.2
	var cx := 0.12
	_box(root, Vector3(w, 0.055, d), Vector3(cx, 0.17, 0), g)
	_box(root, Vector3(0.055, 0.17, d), Vector3(cx + w * 0.5 - 0.0275, 0.09, 0), g)
	_box(root, Vector3(w, 0.055, d), Vector3(cx, 0.0, 0), g)
	_box(root, Vector3(0.055, 0.17, d), Vector3(cx - w * 0.5 + 0.0275, -0.085, 0), g)
	_box(root, Vector3(w, 0.055, d), Vector3(cx, -0.17, 0), g)


## Caisse de munitions : caisse kaki, couvercle, bande jaune, balles dessus.
static func _ammo_crate(root: Node3D) -> void:
	var o := mat("olive")
	_box(root, Vector3(0.44, 0.24, 0.26), Vector3(0, -0.06, 0), o)
	_box(root, Vector3(0.46, 0.04, 0.28), Vector3(0, 0.08, 0), o)
	_box(root, Vector3(0.445, 0.05, 0.265), Vector3(0, -0.04, 0), mat("hazard"))
	_box(root, Vector3(0.14, 0.03, 0.04), Vector3(0, 0.115, 0), mat("steel"))
	for i in 5:
		var x := -0.14 + i * 0.07
		_cyl(root, 0.012, 0.02, 0.12, Vector3(x, 0.17, 0.02), mat("brass"), Vector3.ZERO, 8)


## Marteau et scie croisés.
static func _hammer_saw(root: Node3D) -> void:
	var hammer := Node3D.new()
	hammer.rotation.z = 0.5
	root.add_child(hammer)
	_box(hammer, Vector3(0.05, 0.42, 0.05), Vector3(0, -0.04, 0.03), mat("wood"))
	_box(hammer, Vector3(0.22, 0.08, 0.08), Vector3(0.02, 0.18, 0.03), mat("steel"))
	_box(hammer, Vector3(0.06, 0.05, 0.06), Vector3(-0.1, 0.2, 0.03), mat("steel"), Vector3(0, 0, 0.5))
	var saw := Node3D.new()
	saw.rotation.z = -0.55
	root.add_child(saw)
	_box(saw, Vector3(0.1, 0.4, 0.012), Vector3(0, 0.03, -0.03), mat("steel"))
	for i in 9:
		_box(saw, Vector3(0.025, 0.025, 0.012), Vector3(-0.05, -0.14 + i * 0.042, -0.03), mat("steel"), Vector3(0, 0, PI * 0.25))
	_box(saw, Vector3(0.12, 0.13, 0.04), Vector3(0.01, -0.22, -0.03), mat("wood"))


## Étiquette de prix rouge avec « 10 » et œillet.
static func _price_tag(root: Node3D) -> void:
	var t := mat("tag")
	_box(root, Vector3(0.3, 0.24, 0.05), Vector3(0.04, 0, 0), t)
	_box(root, Vector3(0.17, 0.17, 0.05), Vector3(-0.11, 0, 0), t, Vector3(0, 0, PI * 0.25))
	_cyl(root, 0.03, 0.03, 0.04, Vector3(-0.15, 0, 0), mat("paper"), Vector3(PI * 0.5, 0, 0), 10)
	for side in [1.0, -1.0]:
		var l := Label3D.new()
		l.text = "10"
		l.font = UiStyle.font("impact")
		l.font_size = 96
		l.pixel_size = 0.0022
		l.modulate = Color(1, 0.95, 0.85)
		l.outline_size = 0
		l.position = Vector3(0.05, 0, 0.028 * side)
		l.rotation.y = 0.0 if side > 0 else PI
		l.shaded = false
		root.add_child(l)
