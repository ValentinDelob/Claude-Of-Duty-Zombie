class_name ViewModel
extends Node3D
## Arme vue à la première personne (joueur local uniquement) : bras, arme,
## animations procédurales (recul, balancement, rechargement, changement,
## sprint, visée) et flash de bouche.

const HIP_POS := Vector3(0.18, -0.2, -0.4)
const SPRINT_POS := Vector3(0.12, -0.24, -0.3)
const SPRINT_ROT := Vector3(-0.35, 0.9, 0.25)
const ADS_DEPTH := 0.3

var model_id := ""
var pap := false
var model: Node3D
var arms: Node3D
var ads := 0.0
var _kick := 0.0
var _kick_vel := 0.0
var _kick_rot := 0.0
var _sway := Vector2.ZERO
var _sprint := 0.0
var _reload_t := -1.0
var _reload_dur := 1.0
var _switch_t := -1.0
var _switch_dur := 0.5
var _switch_cb: Callable
var _switch_mid_done := false
var _melee_t := -1.0
var _drink_t := -1.0
var _drink_dur := 2.0
var _bottle: MeshInstance3D
var _flash_mesh: MeshInstance3D
var _flash_light: OmniLight3D
var _flash_t := 0.0
var _bob := 0.0


func _ready() -> void:
	arms = _build_knife()
	add_child(arms)
	_flash_mesh = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.16, 0.16)
	_flash_mesh.mesh = q
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.albedo_texture = _flash_texture()
	fm.albedo_color = Color(1.0, 0.75, 0.4)
	fm.no_depth_test = true
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_flash_mesh.material_override = fm
	_flash_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash_mesh.visible = false
	add_child(_flash_mesh)
	_flash_light = OmniLight3D.new()
	_flash_light.light_color = Color(1.0, 0.7, 0.4)
	_flash_light.omni_range = 5.0
	_flash_light.light_energy = 0.0
	add_child(_flash_light)


func set_weapon(id: String, is_pap: bool) -> void:
	var s := WeaponDB.stats(id, is_pap)
	var mid: String = s.model
	if mid == model_id and is_pap == pap and model != null:
		return
	model_id = mid
	pap = is_pap
	if model:
		model.queue_free()
	model = WeaponModels.build(mid, true, is_pap)
	model.add_child(_build_arms(mid))
	add_child(model)
	_flash_mesh.position = WeaponModels.anchor(mid, "muzzle")


func muzzle_global() -> Vector3:
	if model == null:
		return global_position
	return model.to_global(WeaponModels.anchor(model_id, "muzzle"))


func fire_kick(strength: float) -> void:
	_kick_vel += strength * 0.9
	_kick_rot += strength * 0.035
	_flash_t = 0.045
	_flash_mesh.rotation.z = randf() * TAU
	_flash_mesh.scale = Vector3.ONE * randf_range(0.8, 1.3)


func start_reload(duration: float) -> void:
	_reload_t = 0.0
	_reload_dur = duration


func cancel_reload() -> void:
	_reload_t = -1.0


## Baisse l'arme, appelle `on_mid` (changement de modèle), puis la remonte.
func start_switch(duration: float, on_mid: Callable) -> void:
	_switch_t = 0.0
	_switch_dur = duration
	_switch_cb = on_mid
	_switch_mid_done = false


func start_melee() -> void:
	_melee_t = 0.0


func update(delta: float, p: Player) -> void:
	if model == null:
		return
	# Visée
	var want_ads := 1.0 if p.aiming and _reload_t < 0.0 and _switch_t < 0.0 else 0.0
	ads = move_toward(ads, want_ads, delta * 6.0)
	_sprint = move_toward(_sprint, 1.0 if p.sprinting else 0.0, delta * 5.0)
	# Ressort du recul
	_kick_vel += (-_kick * 180.0 - _kick_vel * 22.0) * delta
	_kick += _kick_vel * delta
	_kick_rot = lerpf(_kick_rot, 0.0, 1.0 - exp(-delta * 12.0))
	# Balancement (inertie du regard)
	var look := p.input.look * 0.0006
	_sway = _sway.lerp(Vector2(-look.x, look.y).limit_length(0.06), 1.0 - exp(-delta * 10.0))
	# Bob
	var speed := Vector2(p.velocity.x, p.velocity.z).length()
	if p.is_on_floor() and speed > 0.5:
		_bob += delta * speed * (1.6 if p.sprinting else 2.0)
	var bob_amp := (0.012 if not p.sprinting else 0.03) * (1.0 - ads * 0.85) * clampf(speed / 4.0, 0.0, 1.5)

	var sight := WeaponModels.anchor(model_id, "sight")
	var ads_pos := Vector3(-sight.x, -sight.y, -ADS_DEPTH - sight.z)
	var pos := HIP_POS.lerp(ads_pos, ads)
	pos = pos.lerp(SPRINT_POS, _sprint)
	pos += Vector3(sin(_bob) * bob_amp, -absf(cos(_bob)) * bob_amp, 0.0)
	pos += Vector3(_sway.x, _sway.y, 0.0) * (1.0 - ads * 0.7)
	pos.z += _kick * 0.06
	var rot := Vector3(_kick_rot * (1.0 - ads * 0.6), 0.0, 0.0)
	rot += SPRINT_ROT * _sprint
	rot.z += -_sway.x * 1.5

	# Rechargement : l'arme plonge et pivote.
	if _reload_t >= 0.0:
		_reload_t += delta / _reload_dur
		var k := sin(clampf(_reload_t, 0.0, 1.0) * PI)
		pos += Vector3(-0.04, -0.12, 0.05) * k
		rot += Vector3(0.5, 0.2, 0.7) * k
		if _reload_t >= 1.0:
			_reload_t = -1.0
	# Changement d'arme
	if _switch_t >= 0.0:
		_switch_t += delta / _switch_dur
		if _switch_t >= 0.5 and not _switch_mid_done:
			_switch_mid_done = true
			if _switch_cb.is_valid():
				_switch_cb.call()
		var k2 := 1.0 - absf(_switch_t * 2.0 - 1.0)
		pos += Vector3(0.0, -0.35, 0.05) * k2
		rot += Vector3(-0.6, 0.0, 0.0) * k2
		if _switch_t >= 1.0:
			_switch_t = -1.0
	# Boisson : l'arme descend hors champ, la bouteille monte à la bouche.
	if _drink_t >= 0.0:
		_drink_t += delta / _drink_dur
		var kd := sin(clampf(_drink_t, 0.0, 1.0) * PI)
		pos += Vector3(0.0, -0.5, 0.1) * minf(kd * 2.0, 1.0)
		rot += Vector3(-0.8, 0.0, 0.0) * minf(kd * 2.0, 1.0)
		_bottle.visible = _drink_t > 0.1 and _drink_t < 0.9
		var lift := sin(clampf((_drink_t - 0.1) / 0.8, 0.0, 1.0) * PI)
		_bottle.position = Vector3(0.02, -0.28 + lift * 0.17, -0.3 + lift * 0.06)
		_bottle.rotation = Vector3(0.5 + lift * 1.1, 0.0, 0.1)
		if _drink_t >= 1.0:
			_drink_t = -1.0
			_bottle.visible = false
	# Coup de couteau : l'arme s'écarte, le bras frappe.
	var melee_k := 0.0
	if _melee_t >= 0.0:
		_melee_t += delta / WeaponDB.MELEE_COOLDOWN
		melee_k = sin(clampf(_melee_t * 1.6, 0.0, 1.0) * PI)
		pos += Vector3(0.1, -0.15, 0.0) * melee_k
		rot += Vector3(0.3, -0.6, 0.0) * melee_k
		if _melee_t >= 1.0:
			_melee_t = -1.0

	model.position = pos
	model.rotation = rot
	arms.visible = melee_k > 0.05
	arms.position = Vector3(-0.12 + 0.1 * melee_k, -0.16, -0.35 - 0.15 * melee_k)
	arms.rotation = Vector3(0.2, 1.0 - 1.8 * melee_k, 0.3)

	# Flash
	if _flash_t > 0.0:
		_flash_t -= delta
		_flash_mesh.visible = true
		_flash_mesh.position = model.position + WeaponModels.anchor(model_id, "muzzle").rotated(Vector3.RIGHT, rot.x)
		_flash_light.position = _flash_mesh.position
		_flash_light.light_energy = 1.8
	else:
		_flash_mesh.visible = false
		_flash_light.light_energy = 0.0


func is_busy() -> bool:
	return _reload_t >= 0.0 or _switch_t >= 0.0


# --------------------------------------------------------------------------

func _build_arms(mid: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Arms"
	var sleeve := _arm_mat(Color(0.13, 0.14, 0.1), 0.25)
	var glove := _arm_mat(Color(0.07, 0.06, 0.05), 0.15)
	var grip := WeaponModels.anchor(mid, "grip")
	var support := WeaponModels.anchor(mid, "support")
	# Main droite sur la poignée, avant-bras vers le bas-droite de l'écran.
	_limb(root, grip + Vector3(0.0, -0.01, 0.03), Vector3(0.2, -0.3, 0.45), 0.075, sleeve)
	_limb(root, grip + Vector3(0.0, 0.0, -0.01), grip + Vector3(0.0, -0.035, 0.06), 0.055, glove)
	# Main gauche en soutien (garde-main ou sous la main droite).
	var elbow := Vector3(-0.24, -0.32, 0.25) if support.z < -0.1 else Vector3(-0.2, -0.32, 0.4)
	_limb(root, support + Vector3(0.0, -0.02, 0.03), elbow, 0.07, sleeve)
	_limb(root, support + Vector3(0.0, 0.0, -0.02), support + Vector3(-0.01, -0.035, 0.05), 0.05, glove)
	return root


func _limb(parent: Node3D, a: Vector3, b: Vector3, thickness: float, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(thickness, thickness, a.distance_to(b))
	mi.mesh = box
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.position = (a + b) * 0.5
	mi.basis = Basis.looking_at(b - a, Vector3.UP)


func _arm_mat(c: Color, wear: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://assets/shaders/weapon.gdshader")
	m.set_shader_parameter("albedo", c)
	m.set_shader_parameter("roughness", 0.9)
	m.set_shader_parameter("metallic", 0.0)
	m.set_shader_parameter("viewmodel", 1.0)
	m.set_shader_parameter("wear", wear)
	return m


func _build_knife() -> Node3D:
	var knife := Node3D.new()
	knife.name = "Knife"
	knife.visible = false
	var blade := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.012, 0.035, 0.22)
	blade.mesh = bm
	blade.position = Vector3(0, 0, -0.12)
	blade.material_override = WeaponModels.material("metal_worn", true, false)
	knife.add_child(blade)
	var handle := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(0.025, 0.035, 0.1)
	handle.mesh = hm
	handle.position = Vector3(0, 0, 0.03)
	handle.material_override = WeaponModels.material("wood_dark", true, false)
	knife.add_child(handle)
	var hand := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(0.06, 0.06, 0.3)
	hand.mesh = gm
	hand.position = Vector3(-0.02, -0.03, 0.2)
	hand.material_override = _arm_mat(Color(0.13, 0.14, 0.1), 0.25)
	knife.add_child(hand)
	return knife


static var _flash_tex: Texture2D


static func _flash_texture() -> Texture2D:
	if _flash_tex:
		return _flash_tex
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var p := Vector2(x - n * 0.5 + 0.5, y - n * 0.5 + 0.5) / (n * 0.5)
			var r := p.length()
			var ang := p.angle()
			var star := pow(absf(cos(ang * 3.0)), 12.0) * clampf(1.0 - r, 0.0, 1.0)
			var core := clampf(1.0 - r * 2.2, 0.0, 1.0)
			var a := clampf(star + core, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_flash_tex = ImageTexture.create_from_image(img)
	return _flash_tex


func start_drink(color: Color, duration: float) -> void:
	if _bottle == null:
		_bottle = MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.018
		cm.bottom_radius = 0.035
		cm.height = 0.2
		cm.radial_segments = 8
		_bottle.mesh = cm
		_bottle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_bottle)
	var m := ShaderMaterial.new()
	m.shader = preload("res://assets/shaders/weapon.gdshader")
	m.set_shader_parameter("albedo", color)
	m.set_shader_parameter("emission", color)
	m.set_shader_parameter("emission_energy", 1.5)
	m.set_shader_parameter("viewmodel", 1.0)
	m.set_shader_parameter("roughness", 0.2)
	_bottle.material_override = m
	_bottle.visible = false
	_drink_t = 0.0
	_drink_dur = duration


func is_drinking() -> bool:
	return _drink_t >= 0.0
