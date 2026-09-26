class_name ViewModel
extends Node3D
## Arme vue à la première personne (joueur local uniquement) : bras, arme,
## animations procédurales (recul, balancement, rechargement, changement,
## sprint, visée) et flash de bouche.

const HIP_POS := Vector3(0.18, -0.2, -0.4)
const SPRINT_POS := Vector3(0.12, -0.24, -0.3)
const SPRINT_ROT := Vector3(-0.35, 0.9, 0.25)

## Flamme de bouche par famille (WeaponDB "flash") : [taille du cœur (m),
## longueur des pointes (m), largeur des pointes (m), énergie de la lumière].
const FLASH := {
	"pistol": [0.05, 0.1, 0.045, 1.6],
	"smg": [0.05, 0.12, 0.04, 1.5],
	"rifle": [0.07, 0.18, 0.06, 2.2],
	"shotgun": [0.1, 0.22, 0.1, 3.0],
	"sniper": [0.09, 0.26, 0.08, 3.0],
	"launcher": [0.08, 0.1, 0.09, 2.0],
}

var model_id := ""
var pap := false
var model: Node3D
var arms: Node3D
var ads := 0.0
## Durée de la mise en joue de l'arme en main (WeaponDB "ads_time").
var ads_time := 0.2
## Écran de lunette affiché (WeaponController) : le modèle est masqué.
var scoped := false
## Recul du modèle : ressort de recul (m) et ressort de montée du canon (rad).
var _kick := 0.0
var _kick_vel := 0.0
var _kick_rot := 0.0
var _kick_rot_vel := 0.0
var _kick_roll := 0.0
var _kick_back := 0.012
var _kick_climb := 0.03
var _rear_parts: Array[MeshInstance3D] = []
var _sway := Vector2.ZERO
var _sprint := 0.0
var _reload_t := -1.0
var _reload_dur := 1.0
var _switch_t := -1.0
var _switch_dur := 0.5
var _switch_cb: Callable
var _switch_mid_done := false
var _melee_t := -1.0
var _melee_lunge := false
var _dive := 0.0
var _pickup_t := -1.0
var _pickup_dur := 2.0
var knife_id := KnifeDB.DEFAULT
## Durée de l'animation d'un coup de couteau (s) : armé, tranche, retrait.
const MELEE_ANIM := 0.5
## Poses clés du bras gauche + couteau : [t, position, rotation (Euler, rad)].
## Armé en haut à gauche, tranche vers le bas à droite, sortie par le bas.
const MELEE_KEYS := [
	[0.0, Vector3(-0.48, -0.5, -0.36), Vector3(0.4, -0.2, 0.3)],
	[0.3, Vector3(-0.32, -0.1, -0.5), Vector3(0.18, -0.55, 0.25)],
	[0.52, Vector3(0.18, -0.21, -0.52), Vector3(-0.08, 0.35, -0.2)],
	[1.0, Vector3(0.32, -0.6, -0.32), Vector3(-0.2, 0.5, -0.3)],
]
var _drink_t := -1.0
var _drink_dur := 2.0
var _bottle: MeshInstance3D
## Flamme de bouche : cœur face caméra + deux pointes croisées le long du canon.
var _flash_rig: Node3D
var _flash_mesh: MeshInstance3D
var _flash_side: MeshInstance3D
var _flash_light: OmniLight3D
var _flash_t := 0.0
var _flash_energy := 1.8
var _bob := 0.0
## Arme baissée hors champ (lancer de grenade, voir ThrowController) : 0..1.
var lowered := 0.0
var _lower := 0.0


func _ready() -> void:
	arms = _build_knife()
	add_child(arms)
	_flash_rig = Node3D.new()
	_flash_rig.name = "MuzzleFlash"
	_flash_rig.visible = false
	add_child(_flash_rig)
	_flash_mesh = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	_flash_mesh.mesh = q
	_flash_mesh.material_override = flash_material(_flash_texture(), true)
	_flash_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash_rig.add_child(_flash_mesh)
	# Pointes : deux quads croisés couchés le long de l'axe du canon.
	_flash_side = MeshInstance3D.new()
	_flash_side.mesh = prong_mesh()
	_flash_side.material_override = flash_material(prong_texture(), false)
	_flash_side.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash_rig.add_child(_flash_side)
	_flash_light = OmniLight3D.new()
	_flash_light.light_color = Color(1.0, 0.7, 0.4)
	_flash_light.omni_range = 6.0
	_flash_light.light_energy = 0.0
	_flash_light.shadow_enabled = false
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
	# Pièces nettement en arrière du cran (crosse, plaque de couche) : sous la
	# joue en visée, elles ne doivent pas boucher le bas de l'écran.
	_rear_parts.clear()
	var rear_z := maxf(WeaponModels.anchor(mid, "sight").z + 0.06, 0.12)
	for c in model.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).position.z > rear_z:
			_rear_parts.append(c)
	model.add_child(_build_arms(mid))
	add_child(model)
	ads_time = maxf(float(s.get("ads_time", 0.2)), 0.05)


func muzzle_global() -> Vector3:
	if model == null:
		return global_position
	return model.to_global(WeaponModels.anchor(model_id, "muzzle"))


## Pose de visée (repère de la caméra) : la ligne de mire cran -> guidon du
## modèle est posée EXACTEMENT sur l'axe -Z de la caméra (celui des balles),
## le cran à "ads".z m de l'œil. Retourne [position, tangage (rad)].
static func ads_pose(mid: String) -> Array:
	var sight := WeaponModels.anchor(mid, "sight")
	var front := WeaponModels.anchor(mid, "front")
	var d := front - sight
	# Rotation autour de X qui couche la ligne de mire sur -Z.
	var pitch := atan(d.y / d.z) if absf(d.z) > 0.001 else 0.0
	var b := Basis(Vector3.RIGHT, pitch)
	var eye := WeaponModels.anchor(mid, "ads").z
	return [Vector3(0, 0, -eye) - b * sight, pitch]


## Tir : recul du modèle (recul + montée du canon, ressorts), flamme de bouche
## de la famille, lumière brève, fumée, douille éjectée (sauf si `eject` est
## faux : armes à réarmement manuel, la douille sort au réarmement).
func fire(s: Dictionary, fx: Fx, p: Player, eject := true) -> void:
	var r := float(s.recoil)
	# Impulsions normalisées (crête ~1) ; amplitudes selon le recul de l'arme.
	_kick_vel += 32.0
	_kick_rot_vel += 23.0
	_kick_roll += randf_range(-1.0, 1.0) * clampf(r * 0.006, 0.0, 0.04)
	_kick_back = clampf(0.012 + r * 0.004, 0.012, 0.05)
	_kick_climb = clampf(0.02 + r * 0.01, 0.02, 0.1)
	var fl: Array = FLASH.get(String(s.get("flash", "rifle")), [])
	if model == null:
		return
	var muzzle := muzzle_global()
	if not fl.is_empty():
		_flash_t = 0.05
		_flash_energy = fl[3]
		var k := randf_range(0.8, 1.25) * (0.6 if ads > 0.5 else 1.0)
		_flash_mesh.scale = Vector3.ONE * fl[0] * 1.8 * k
		(_flash_mesh.material_override as StandardMaterial3D).albedo_texture = flash_variant(randi() % 4)
		_flash_mesh.rotation = Vector3(0, 0, randf() * TAU)
		_flash_side.scale = Vector3(fl[2], fl[2], fl[1]) * k
		_flash_side.rotation.z = randf() * TAU
		if fx:
			fx.smoke(muzzle, -global_transform.basis.z, 2 if s.get("flash", "") == "shotgun" else 1)
	if eject and fx:
		eject_shell(fx, p, String(s.get("shell", "")))


## Douille éjectée par la fenêtre d'éjection, vers la droite et le haut.
func eject_shell(fx: Fx, p: Player, kind: String) -> void:
	if kind == "" or model == null or fx == null or scoped:
		return
	var b := global_transform.basis
	var pos := model.to_global(WeaponModels.anchor(model_id, "eject"))
	var vel := b * Vector3(randf_range(1.4, 2.2), randf_range(1.2, 1.9), randf_range(-0.1, 0.5))
	if p:
		vel += p.velocity
	fx.eject_shell(pos, vel, kind)


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


## Coup de couteau (bras gauche). `lunge` : fente (l'arme s'abaisse davantage).
func start_melee(lunge := false) -> void:
	_melee_t = 0.0
	_melee_lunge = lunge


## Couteau tenu dans la main gauche (KnifeDB) : reconstruit le modèle.
func set_knife(id: String) -> void:
	if id == knife_id and arms != null and arms.get_child_count() > 0:
		return
	knife_id = id
	if arms == null:
		return
	for c in arms.get_children():
		c.queue_free()
	_fill_knife_rig(arms, KnifeDB.model(id))


## Récupération du couteau de chasse : l'arme descend, le couteau est sorti,
## retourné et observé, puis rangé (~2 s, comme BO1).
func start_knife_pickup(duration: float) -> void:
	_pickup_t = 0.0
	_pickup_dur = duration
	_melee_t = -1.0


func is_knife_busy() -> bool:
	return _melee_t >= 0.0 or _pickup_t >= 0.0


func update(delta: float, p: Player) -> void:
	if model == null:
		return
	# Visée
	var want_ads := 1.0 if p.aiming and _reload_t < 0.0 and _switch_t < 0.0 else 0.0
	ads = move_toward(ads, want_ads, delta / ads_time)
	_sprint = move_toward(_sprint, 1.0 if p.sprinting else 0.0, delta * 5.0)
	# Ressorts du recul : l'arme recule et le canon monte, puis tout revient.
	_kick_vel += (-_kick * 180.0 - _kick_vel * 22.0) * delta
	_kick = clampf(_kick + _kick_vel * delta, -1.0, 2.5)
	_kick_rot_vel += (-_kick_rot * 120.0 - _kick_rot_vel * 16.0) * delta
	_kick_rot = clampf(_kick_rot + _kick_rot_vel * delta, -1.0, 2.5)
	_kick_roll = lerpf(_kick_roll, 0.0, 1.0 - exp(-delta * 10.0))
	# Balancement (inertie du regard)
	var look := p.input.look * 0.0006
	_sway = _sway.lerp(Vector2(-look.x, look.y).limit_length(0.06), 1.0 - exp(-delta * 10.0))
	# Bob
	var speed := Vector2(p.velocity.x, p.velocity.z).length()
	if p.is_on_floor() and speed > 0.5:
		_bob += delta * speed * (1.6 if p.sprinting else 2.0)
	var bob_amp := (0.012 if not p.sprinting else 0.03) * (1.0 - ads * 0.85) * clampf(speed / 4.0, 0.0, 1.5)

	# Visée : la ligne de mire se pose sur l'axe de la caméra (ads_pose).
	var aim_pose := ads_pose(model_id)
	var ak := ads * ads * (3.0 - 2.0 * ads)
	var pos: Vector3 = (HIP_POS + WeaponModels.anchor(model_id, "hold")).lerp(aim_pose[0], ak)
	pos = pos.lerp(SPRINT_POS, _sprint)
	pos += Vector3(sin(_bob) * bob_amp, -absf(cos(_bob)) * bob_amp, 0.0)
	pos += Vector3(_sway.x, _sway.y, 0.0) * (1.0 - ak * 0.7)
	pos.z += _kick * _kick_back * (1.0 - ak * 0.4)
	var rot := Vector3(float(aim_pose[1]) * ak + _kick_rot * _kick_climb * (1.0 - ak * 0.55), 0.0, _kick_roll * (1.0 - ak * 0.5))
	rot += SPRINT_ROT * _sprint
	rot.z += -_sway.x * 1.5 * (1.0 - ak)
	# Plongeon : l'arme bascule sur le côté pendant le vol.
	_dive = move_toward(_dive, 1.0 if p.diving else 0.0, delta * 7.0)
	pos += Vector3(-0.03, -0.07, 0.05) * _dive
	rot += Vector3(0.35, 0.0, 0.45) * _dive

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
	# Coup de couteau : l'arme s'écarte vers le bas à droite, le bras gauche
	# arme le couteau puis tranche de gauche à droite.
	arms.visible = false
	if _melee_t >= 0.0:
		_melee_t += delta / MELEE_ANIM
		var melee_k := sin(clampf(_melee_t, 0.0, 1.0) * PI)
		var drop := 1.4 if _melee_lunge else 1.0
		pos += Vector3(0.12, -0.16, 0.04) * melee_k * drop
		rot += Vector3(-0.35, -0.5, -0.2) * melee_k * drop
		arms.visible = true
		var pose := melee_pose(clampf(_melee_t, 0.0, 1.0))
		arms.position = pose[0]
		arms.rotation = pose[1]
		if _melee_t >= 1.0:
			_melee_t = -1.0
	# Récupération du couteau de chasse.
	if _pickup_t >= 0.0:
		_pickup_t += delta / _pickup_dur
		var t := clampf(_pickup_t, 0.0, 1.0)
		var down := smoothstep(0.0, 0.12, t) * (1.0 - smoothstep(0.88, 1.0, t))
		pos += Vector3(0.0, -0.5, 0.1) * down
		rot += Vector3(-0.8, 0.0, 0.0) * down
		var pose := pickup_pose(t)
		arms.visible = t > 0.08 and t < 0.92
		arms.position = pose[0]
		arms.rotation = pose[1]
		if _pickup_t >= 1.0:
			_pickup_t = -1.0

	# Lancer de grenade : l'arme descend sous l'écran.
	_lower = move_toward(_lower, lowered, delta * 6.0)
	if _lower > 0.0:
		var kl := ease(_lower, -1.8)
		pos += Vector3(0.04, -0.42, 0.12) * kl
		rot += Vector3(-0.7, 0.2, 0.0) * kl

	model.position = pos
	model.rotation = rot
	# Lunette : l'écran de lunette (HUD) remplace l'arme.
	model.visible = not scoped
	for rp in _rear_parts:
		rp.visible = ak < 0.75

	# Flamme de bouche : suit la bouche du canon (position et axe du modèle).
	if _flash_t > 0.0:
		_flash_t -= delta
		var mt := model.transform
		_flash_rig.transform = Transform3D(mt.basis.orthonormalized(), mt * WeaponModels.anchor(model_id, "muzzle"))
		_flash_rig.visible = not scoped
		_flash_light.position = _flash_rig.position + mt.basis * Vector3(0, 0, -0.1)
		_flash_light.light_energy = _flash_energy * clampf(_flash_t / 0.05, 0.0, 1.0)
	else:
		_flash_rig.visible = false
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
	var rig := Node3D.new()
	rig.name = "Knife"
	rig.visible = false
	_fill_knife_rig(rig, KnifeDB.model(knife_id))
	return rig


## Main gauche gantée, avant-bras (manche) et couteau tenu lame en avant.
func _fill_knife_rig(rig: Node3D, mid: String) -> void:
	var sleeve := _arm_mat(Color(0.13, 0.14, 0.1), 0.25)
	var glove := _arm_mat(Color(0.07, 0.06, 0.05), 0.15)
	_limb(rig, Vector3(0.0, -0.01, 0.05), Vector3(-0.06, -0.14, 0.34), 0.07, sleeve)
	_limb(rig, Vector3(0.0, 0.0, -0.025), Vector3(0.0, -0.01, 0.07), 0.056, glove)
	# Lame couchée : le tranchant regarde vers la droite (coup de gauche à droite).
	var knife := WeaponModels.build(mid, true)
	knife.name = "Blade"
	knife.rotation.z = 1.15
	knife.position = -WeaponModels.anchor(mid, "grip")
	rig.add_child(knife)


## Pose [position, rotation] du bras gauche à l'instant `t` (0..1) du coup.
static func melee_pose(t: float) -> Array:
	for i in MELEE_KEYS.size() - 1:
		var a: Array = MELEE_KEYS[i]
		var b: Array = MELEE_KEYS[i + 1]
		if t <= b[0]:
			var k := smoothstep(a[0], b[0], t)
			return [a[1].lerp(b[1], k), a[2].lerp(b[2], k)]
	var last: Array = MELEE_KEYS[MELEE_KEYS.size() - 1]
	return [last[1], last[2]]


## Pose de la récupération : le couteau monte au centre, pointe vers le haut,
## pivote pour montrer la lame, puis redescend.
static func pickup_pose(t: float) -> Array:
	var rise := smoothstep(0.08, 0.3, t) * (1.0 - smoothstep(0.78, 0.92, t))
	var low := Vector3(-0.12, -0.62, -0.42)
	var high := Vector3(-0.03, -0.14, -0.48)
	var turn := smoothstep(0.3, 0.72, t)
	var rot := Vector3(1.15, 0.55 - 1.1 * turn, 0.1 - sin(turn * PI) * 0.3)
	rot.x -= sin(turn * PI) * 0.2
	return [low.lerp(high, rise), rot]


static var _flash_tex: Texture2D
static var _prong_tex: Texture2D
static var _prong_mesh: ArrayMesh


## Matériau additif non éclairé de la flamme de bouche.
static func flash_material(tex: Texture2D, billboard: bool) -> StandardMaterial3D:
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.albedo_texture = tex
	fm.albedo_color = Color(1.0, 0.9, 0.75)
	fm.no_depth_test = true
	fm.cull_mode = BaseMaterial3D.CULL_DISABLED
	if billboard:
		fm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		fm.billboard_keep_scale = true
	return fm


## Deux quads croisés (plans XZ et YZ) de z = 0 à z = -1, largeur 1.
static func prong_mesh() -> ArrayMesh:
	if _prong_mesh:
		return _prong_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for axis in [Vector3.RIGHT, Vector3.UP]:
		var a: Vector3 = axis * 0.5
		var quad := [[-a, Vector2(0, 0)], [a, Vector2(1, 0)], [a + Vector3(0, 0, -1), Vector2(1, 1)], [-a + Vector3(0, 0, -1), Vector2(0, 1)]]
		for i in [0, 1, 2, 0, 2, 3]:
			st.set_uv(quad[i][1])
			st.add_vertex(quad[i][0])
	_prong_mesh = st.commit()
	return _prong_mesh


## Pointe de flamme : large et vive à la bouche (v = 0), effilée au bout.
static func prong_texture() -> Texture2D:
	if _prong_tex:
		return _prong_tex
	var w := 32
	var h := 64
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var v := float(y) / (h - 1)
			var u := absf((x + 0.5) / w * 2.0 - 1.0)
			var half := lerpf(0.9, 0.05, pow(v, 0.7))
			var a := clampf((half - u) / maxf(half, 0.01), 0.0, 1.0) * (1.0 - v * 0.85)
			img.set_pixel(x, y, Color(1, 0.9 - v * 0.3, 0.75 - v * 0.5, a * a))
	_prong_tex = ImageTexture.create_from_image(img)
	return _prong_tex


static func _flash_texture() -> Texture2D:
	if _flash_tex:
		return _flash_tex
	_flash_tex = flash_variant(0)
	return _flash_tex


static var _flash_variants: Array[Texture2D] = []


## Flamme vue de face, variante `v` (0..3) : cœur blanc-jaune, pétales
## irréguliers orangés (longueurs et largeurs aléatoires), bord doux.
static func flash_variant(v: int) -> Texture2D:
	while _flash_variants.size() < 4:
		_flash_variants.append(_make_flash(_flash_variants.size()))
	return _flash_variants[v % 4]


static func _make_flash(seed_v: int) -> Texture2D:
	var n := 96
	var rng := RandomNumberGenerator.new()
	rng.seed = 911 + seed_v * 17
	var petals := rng.randi_range(4, 6)
	var lens := []
	var phases := []
	for k in petals:
		lens.append(rng.randf_range(0.55, 1.0))
		phases.append(TAU * (k + rng.randf_range(-0.2, 0.2)) / petals)
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var p := Vector2(x - n * 0.5 + 0.5, y - n * 0.5 + 0.5) / (n * 0.5)
			var r := p.length()
			var ang := p.angle()
			var petal := 0.0
			for k in petals:
				var da := absf(wrapf(ang - float(phases[k]), -PI, PI))
				var width := 0.34 * (1.0 - r / float(lens[k]))
				if width > 0.0:
					petal = maxf(petal, clampf(1.0 - da / width, 0.0, 1.0) * (1.0 - r / float(lens[k])))
			var core := clampf(1.0 - r * 3.2, 0.0, 1.0)
			var glow := clampf(1.0 - r * 1.6, 0.0, 1.0) * 0.35
			var a := clampf(core + petal * 0.9 + glow, 0.0, 1.0)
			# Blanc-jaune au centre, orange vers l'extérieur.
			var hot := clampf(1.0 - r * 1.8, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, lerpf(0.55, 0.95, hot), lerpf(0.2, 0.8, hot), a))
	return ImageTexture.create_from_image(img)


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
