class_name ViewModel
extends Node3D
## Arme vue à la première personne (joueur local uniquement) : mains et bras
## (ViewHands), arme, animations procédurales (recul, culasse, pompe,
## balancement, rechargement propre à chaque mécanisme, sortie et rangement,
## sprint, visée) et flash de bouche.
##
## Champ de vision propre à l'arme (comme BO1) : l'arme est dessinée avec
## VIEW_FOV quel que soit le champ de vision du joueur (réglage, sprint,
## zoom de visée) ; weapon.gdshader applique le rapport `vm_fov_scale` aux
## sommets des matériaux « viewmodel ». Un point P du repère de la caméra
## apparaît donc à l'écran là où la caméra verrait apparent(P) : la flamme
## de bouche, les douilles et les traçantes partent de ces points apparents.

## Champ de vision (vertical) de l'arme : cg_fov 65 de BO1 (horizontal en
## 4:3), soit ~51° verticalement.
const VIEW_FOV := 51.3
## En visée, le champ de l'arme s'élargit : la carcasse sous l'œil ne bouche
## pas l'écran, les organes de visée restent centrés.
const VIEW_FOV_ADS := 72.0
const HIP_POS := Vector3(0.25, -0.294, -0.95)
## Hanche : canon légèrement relevé et tourné vers le réticule (on voit le
## dessus et le flanc gauche de l'arme, la crosse sort par le bas de l'écran).
const HIP_ROT := Vector3(0.07, 0.06, 0.0)
const SPRINT_POS := Vector3(0.15, -0.3, -0.85)
const SPRINT_ROT := Vector3(-0.3, 0.9, 0.3)

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

## Rapport tan(fov caméra / 2) / tan(VIEW_FOV / 2) courant (ThrowView s'en sert).
static var fov_k := 1.0
## Tenue des mains du joueur local (ThrowView s'en sert).
static var style := -1

var model_id := ""
var pap := false
var model: Node3D
var hands: ViewHands
var arms: Node3D
var ads := 0.0
## Durée de la mise en joue de l'arme en main (WeaponDB "ads_time").
var ads_time := 0.2
## Écran de lunette affiché (WeaponController) : le modèle est masqué.
var scoped := false
## Tenue des mains (emplacement du joueur : ViewHands.STYLES).
var hand_style := -1
var _stats: Dictionary = {}
## Pièces mobiles du modèle (nœuds de groupe) et leur position de repos.
var _groups: Dictionary = {}
var _group_rest: Dictionary = {}
## Recul du modèle : ressort de recul (m) et ressort de montée du canon (rad).
var _kick := 0.0
var _kick_vel := 0.0
var _kick_rot := 0.0
var _kick_rot_vel := 0.0
var _kick_roll := 0.0
var _kick_back := 0.012
var _kick_climb := 0.03
## Culasse / glissière qui recule à chaque tir (0..1).
var _slide_kick := 0.0
## Réarmement (pompe, verrou) : temps écoulé et durée ; < 0 : aucun.
var _cycle_t := -1.0
var _cycle_dur := 0.4
var _cycle_delay := 0.0
var _sway := Vector2.ZERO
var _sprint := 0.0
var _reload_t := -1.0
var _reload_start := 0.0
var _reload_dur := 1.0
var _reload_kind := "mag"
var _reload_empty := false
var _reload_count := 1
var _reload_pending := false
var _switch_t := -1.0
var _switch_start := 0.0
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
## Positions pour le champ de vision de l'arme (profondeur x ~1,75).
const MELEE_KEYS := [
	[0.0, Vector3(-0.48, -0.5, -0.63), Vector3(0.4, -0.2, 0.3)],
	[0.3, Vector3(-0.32, -0.1, -0.87), Vector3(0.18, -0.55, 0.25)],
	[0.52, Vector3(0.18, -0.21, -0.91), Vector3(-0.08, 0.35, -0.2)],
	[1.0, Vector3(0.32, -0.6, -0.56), Vector3(-0.2, 0.5, -0.3)],
]
var _drink_t := -1.0
var _drink_dur := 2.0
var _bottle: MeshInstance3D
## Cartouche tenue par la main gauche (rechargement coup par coup).
var _shell: Node3D
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


func _exit_tree() -> void:
	fov_k = 1.0
	RenderingServer.global_shader_parameter_set("vm_fov_scale", 1.0)


func set_weapon(id: String, is_pap: bool) -> void:
	var s := WeaponDB.stats(id, is_pap)
	var mid: String = s.model
	_stats = s
	if mid == model_id and is_pap == pap and model != null:
		return
	model_id = mid
	pap = is_pap
	if model:
		model.queue_free()
	model = WeaponModels.build(mid, true, is_pap)
	_groups.clear()
	_group_rest.clear()
	for c in model.get_children():
		_groups[String(c.name)] = c
		_group_rest[String(c.name)] = (c as Node3D).position
	hands = ViewHands.new()
	hands.name = "Hands"
	model.add_child(hands)
	hands.setup(mid, maxi(hand_style, 0))
	add_child(model)
	# Cartouche (ou grenade de 40 mm) tenue pour le chargement coup par coup.
	_shell = null
	if String(s.get("reload_kind", "")) == "shells":
		_shell = _make_round(String(s.get("shell", "")) == "")
		model.add_child(_shell)
	ads_time = maxf(float(s.get("ads_time", 0.2)), 0.05)
	_slide_kick = 0.0
	_cycle_t = -1.0


## Point apparent (repère de la caméra = repère de ce nœud) d'un point dessiné
## avec le champ de vision de l'arme.
static func apparent(p: Vector3) -> Vector3:
	return Vector3(p.x * fov_k, p.y * fov_k, p.z)


## Position (monde) où l'on VOIT le point `local` du modèle.
func model_point_global(local: Vector3) -> Vector3:
	return to_global(apparent(model.transform * local))


func muzzle_global() -> Vector3:
	if model == null:
		return global_position
	return model_point_global(WeaponModels.anchor(model_id, "muzzle"))


## Pose de visée (repère de la caméra) : la ligne de mire cran -> guidon du
## modèle est posée EXACTEMENT sur l'axe -Z de la caméra (celui des balles),
## le cran à "ads".z m de l'œil. Retourne [position, tangage (rad)].
## (L'axe optique passe par le centre de l'écran quel que soit le champ de
## vision : l'alignement ne dépend pas de VIEW_FOV.)
static func ads_pose(mid: String) -> Array:
	var sight := WeaponModels.anchor(mid, "sight")
	var front := WeaponModels.anchor(mid, "front")
	var d := front - sight
	# Rotation autour de X qui couche la ligne de mire sur -Z.
	var pitch := atan(d.y / d.z) if absf(d.z) > 0.001 else 0.0
	var b := Basis(Vector3.RIGHT, pitch)
	var eye := WeaponModels.anchor(mid, "ads").z
	return [Vector3(0, 0, -eye) - b * sight, pitch]


## Tir : recul du modèle (recul + montée du canon, ressorts), culasse qui
## recule, flamme de bouche de la famille, lumière brève, fumée, douille
## éjectée (sauf si `eject` est faux : armes à réarmement manuel, la douille
## sort au réarmement, et la pompe / le verrou s'anime).
func fire(s: Dictionary, fx: Fx, p: Player, eject := true) -> void:
	var r := float(s.recoil)
	# Impulsions normalisées (crête ~1) ; amplitudes selon le recul de l'arme.
	_kick_vel += 32.0
	_kick_rot_vel += 23.0
	_kick_roll += randf_range(-1.0, 1.0) * clampf(r * 0.006, 0.0, 0.04)
	_kick_back = clampf(0.012 + r * 0.004, 0.012, 0.05)
	_kick_climb = clampf(0.02 + r * 0.01, 0.02, 0.1)
	_slide_kick = 1.0
	var cycle: String = s.get("cycle", "")
	if cycle != "":
		var interval := 60.0 / maxf(float(s.rpm), 1.0)
		_cycle_delay = interval * 0.3
		_cycle_dur = interval * 0.55
		_cycle_t = 0.0
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
	var pos := model_point_global(WeaponModels.anchor(model_id, "eject"))
	var vel := b * Vector3(randf_range(1.4, 2.2), randf_range(1.2, 1.9), randf_range(-0.1, 0.5))
	if p:
		vel += p.velocity
	fx.eject_shell(pos, vel, kind)


func start_reload(duration: float) -> void:
	_reload_t = 0.0
	_reload_start = WeaponController.now()
	_reload_dur = duration
	# Mécanisme, chargeur vide, nombre de cartouches : lus à l'image suivante.
	_reload_pending = true


func cancel_reload() -> void:
	_reload_t = -1.0
	_reload_pending = false


## Baisse l'arme, appelle `on_mid` (changement de modèle), puis la remonte.
func start_switch(duration: float, on_mid: Callable) -> void:
	_switch_t = 0.0
	_switch_start = WeaponController.now()
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


static func _ss(a: float, b: float, t: float) -> float:
	return smoothstep(a, b, t)


## Bosse lisse : 0 avant a, 1 entre b et c, 0 après d.
static func _hump(t: float, a: float, b: float, c: float, d: float) -> float:
	return smoothstep(a, b, t) * (1.0 - smoothstep(c, d, t))


func update(delta: float, p: Player) -> void:
	# Champ de vision de l'arme (voir weapon.gdshader).
	var cam := get_parent() as Camera3D
	if cam:
		fov_k = tan(deg_to_rad(cam.fov) * 0.5) / tan(deg_to_rad(view_fov()) * 0.5)
		RenderingServer.global_shader_parameter_set("vm_fov_scale", fov_k)
	if model == null:
		return
	var slot := Net.player_slot(p.peer_id)
	if slot != hand_style and slot >= 0:
		hand_style = slot
		style = slot
		hands.setup(model_id, slot)
		for c in arms.get_children():
			c.queue_free()
		_fill_knife_rig(arms, KnifeDB.model(knife_id))
	if _reload_pending:
		_reload_pending = false
		var w: Dictionary = p.weapons.current() if p.weapons else {}
		_reload_kind = String(_stats.get("reload_kind", "mag"))
		_reload_empty = int(w.get("mag", 1)) == 0
		_reload_count = clampi(int(_stats.get("mag", 1)) - int(w.get("mag", 0)), 1, 6)
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
	_slide_kick = move_toward(_slide_kick, 0.0, delta * 16.0)
	# Balancement (inertie du regard)
	var look := p.input.look * 0.0006
	_sway = _sway.lerp(Vector2(-look.x, look.y).limit_length(0.06), 1.0 - exp(-delta * 10.0))
	# Bob : pas lents en marche, grands huit en sprint (comme BO1).
	var speed := Vector2(p.velocity.x, p.velocity.z).length()
	if p.is_on_floor() and speed > 0.5:
		_bob += delta * speed * (1.7 if p.sprinting else 2.0)
	var bob_amp := (0.014 if not p.sprinting else 0.034) * (1.0 - ads * 0.85) * clampf(speed / 4.0, 0.0, 1.5)

	# Visée : la ligne de mire se pose sur l'axe de la caméra (ads_pose).
	var aim_pose := ads_pose(model_id)
	var ak := ads * ads * (3.0 - 2.0 * ads)
	var pos: Vector3 = (HIP_POS + WeaponModels.anchor(model_id, "hold")).lerp(aim_pose[0], ak)
	pos = pos.lerp(SPRINT_POS, _sprint)
	pos += Vector3(sin(_bob) * bob_amp, -absf(cos(_bob)) * bob_amp, 0.0)
	pos += Vector3(_sway.x, _sway.y, 0.0) * (1.0 - ak * 0.7)
	pos.z += _kick * _kick_back * (1.0 - ak * 0.4)
	var rot := Vector3(float(aim_pose[1]) * ak + _kick_rot * _kick_climb * (1.0 - ak * 0.55), 0.0, _kick_roll * (1.0 - ak * 0.5))
	rot += (HIP_ROT + WeaponModels.anchor(model_id, "hold_rot")) * (1.0 - ak) * (1.0 - _sprint)
	rot += SPRINT_ROT * _sprint
	rot += Vector3(sin(_bob * 2.0) * 0.03, cos(_bob) * 0.05, sin(_bob) * 0.06) * _sprint
	rot.z += -_sway.x * 1.5 * (1.0 - ak)
	# Plongeon : l'arme bascule sur le côté pendant le vol.
	_dive = move_toward(_dive, 1.0 if p.diving else 0.0, delta * 7.0)
	pos += Vector3(-0.03, -0.07, 0.05) * _dive
	rot += Vector3(0.35, 0.0, 0.45) * _dive

	# Pièces mobiles : repos, puis culasse, pompe et rechargement.
	var g_off := {}
	var g_rot := {}
	var left := Transform3D.IDENTITY
	var travel := float(WeaponModels.info(model_id, "slide_travel", 0.04))
	var bolt: bool = WeaponModels.info(model_id, "bolt", false)
	if not bolt:
		var lock := 1.0 if (_stats.get("class", "") == "pistol" and int(p.weapons.current().get("mag", 1)) == 0 and _reload_t < 0.0) else 0.0
		g_off["slide"] = Vector3(0, 0, travel * maxf(_slide_kick * (0.9 if _groups.has("slide") else 0.0), lock * 0.85))
	# Réarmement après le tir : pompe tirée puis repoussée, ou verrou.
	if _cycle_t >= 0.0:
		_cycle_t += delta
		var ct := clampf((_cycle_t - _cycle_delay) / _cycle_dur, 0.0, 1.0)
		var c := _hump(ct, 0.0, 0.4, 0.55, 1.0)
		if _groups.has("pump"):
			g_off["pump"] = Vector3(0, 0, 0.075 * c)
			left = Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.075 * c))
		if bolt:
			_bolt_pose(g_off, g_rot, travel, ct)
		rot += Vector3(0.05, 0.0, 0.04) * c
		if _cycle_t > _cycle_delay + _cycle_dur:
			_cycle_t = -1.0

	# Rechargement : chaque mécanisme a sa chorégraphie.
	if _reload_t >= 0.0:
		# Horloge murale, comme WeaponController (_reload_end) : l'animation
		# finit avec le rechargement même si des pas physiques sont sautés.
		_reload_t = (WeaponController.now() - _reload_start) / _reload_dur
		var t := clampf(_reload_t, 0.0, 1.0)
		var r := _reload_anim(t, g_off, g_rot, travel, bolt)
		pos += r[0]
		rot += r[1]
		left = r[2]
		if _reload_t >= 1.0:
			_reload_t = -1.0
	if _shell:
		_shell.visible = _reload_t >= 0.0 and _reload_kind == "shells" and _shell_visible
	# Changement d'arme : rangement vers le bas à droite, sortie en remontant.
	if _switch_t >= 0.0:
		_switch_t = (WeaponController.now() - _switch_start) / _switch_dur
		if _switch_t >= 0.5 and not _switch_mid_done:
			_switch_mid_done = true
			if _switch_cb.is_valid():
				_switch_cb.call()
		var k2 := 1.0 - absf(_switch_t * 2.0 - 1.0)
		k2 = k2 * k2 * (3.0 - 2.0 * k2)
		var coming := _switch_t >= 0.5
		pos += Vector3(0.04 if coming else 0.06, -0.38, 0.08) * k2
		rot += (Vector3(-0.7, 0.2, 0.5) if coming else Vector3(-0.8, -0.1, 0.25)) * k2
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
		_bottle.position = Vector3(0.02, -0.28 + lift * 0.17, (-0.3 + lift * 0.06) * 1.75)
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
		# La main gauche quitte l'arme pendant le coup.
		left = Transform3D(Basis.IDENTITY, Vector3(-0.1, -0.35, 0.1) * minf(melee_k * 2.0, 1.0))
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
	# Crosse sous la joue en visée : masquée pour ne pas boucher l'écran.
	if _groups.has("rear"):
		_groups.rear.visible = ak < 0.75
	for g in _groups:
		if g == "body" or g == "rear" or g == "Hands":
			continue
		var n: Node3D = _groups[g]
		n.position = _group_rest[g] + g_off.get(g, Vector3.ZERO)
		n.rotation = g_rot.get(g, Vector3.ZERO)
	hands.left_pose = left
	hands.update_arm()
	if _shell:
		_shell.transform = left * Transform3D(Basis.IDENTITY, WeaponModels.anchor(model_id, "support") + Vector3(0.012, 0.035, -0.01))

	# Flamme de bouche : suit la bouche du canon (position et axe du modèle),
	# au point où on la voit (champ de vision de l'arme).
	if _flash_t > 0.0:
		_flash_t -= delta
		var mt := model.transform
		_flash_rig.transform = Transform3D(mt.basis.orthonormalized().scaled(Vector3.ONE * fov_k), apparent(mt * WeaponModels.anchor(model_id, "muzzle")))
		_flash_rig.visible = not scoped
		_flash_light.position = _flash_rig.position + mt.basis * Vector3(0, 0, -0.1)
		_flash_light.light_energy = _flash_energy * clampf(_flash_t / 0.05, 0.0, 1.0)
	else:
		_flash_rig.visible = false
		_flash_light.light_energy = 0.0


var _shell_visible := false


## Cartouche de chasse (culot en laiton, étui rouge) ou grenade de 40 mm.
static func _make_round(grenade: bool) -> Node3D:
	var root := Node3D.new()
	root.name = "Round"
	var r := 0.02 if grenade else 0.0105
	var l := 0.1 if grenade else 0.068
	var base := WeaponMesh.Acc.new()
	WeaponMesh.lathe(base, [Vector2(l * 0.5 - 0.012, r), Vector2(l * 0.5 - 0.002, r * 1.08), Vector2(l * 0.5, r * 1.08)], 12)
	var hull := WeaponMesh.Acc.new()
	if grenade:
		WeaponMesh.lathe(hull, [Vector2(-l * 0.5, 0.0), Vector2(-l * 0.5 + 0.01, r * 0.7), Vector2(-l * 0.5 + 0.03, r), Vector2(l * 0.5 - 0.012, r)], 12)
	else:
		WeaponMesh.lathe(hull, [Vector2(-l * 0.5, r * 0.85), Vector2(-l * 0.5 + 0.003, r), Vector2(l * 0.5 - 0.012, r)], 12)
	for pair in [[base, "brass"], [hull, "olive" if grenade else "hull"]]:
		var mi := MeshInstance3D.new()
		mi.mesh = pair[0].commit()
		mi.material_override = WeaponModels.material(pair[1], true, false)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 1.0
		root.add_child(mi)
	root.visible = false
	return root


## Verrou (L96) : levé, tiré en arrière, repoussé, rabattu (ct : 0..1).
func _bolt_pose(g_off: Dictionary, g_rot: Dictionary, travel: float, ct: float) -> void:
	var up := _hump(ct, 0.0, 0.2, 0.8, 1.0)
	var back := _hump(ct, 0.2, 0.42, 0.58, 0.8)
	g_rot["slide"] = Vector3(0, 0, 1.1 * up)
	g_off["slide"] = Vector3(0, 0, travel * back)


## Chorégraphie du rechargement à l'instant t (0..1) : retourne [décalage de
## l'arme, rotation de l'arme, pose de la main gauche] et anime les pièces.
func _reload_anim(t: float, g_off: Dictionary, g_rot: Dictionary, travel: float, bolt: bool) -> Array:
	var pos := Vector3.ZERO
	var rot := Vector3.ZERO
	var support := WeaponModels.anchor(model_id, "support")
	var mag_top := WeaponModels.anchor(model_id, "pivot_mag")
	var mag_dir := WeaponModels.anchor(model_id, "mag_dir").normalized()
	var mag_len := float(WeaponModels.info(model_id, "mag_len", 0.12))
	var hand := Vector3.ZERO  # décalage de la main gauche (repère de l'arme)
	var hand_rot := Vector3.ZERO
	var tilt := _hump(t, 0.0, 0.12, 0.86, 1.0)
	# Main au bout du chargeur (sous la semelle).
	var at_mag := mag_top + mag_dir * (mag_len + 0.01) - support
	var pouch := Vector3(-0.12, -0.4, 0.2)
	_shell_visible = false
	match _reload_kind:
		"break":
			# Canons basculés : éjection, deux cartouches, fermeture d'un coup sec.
			var open := _hump(t, 0.05, 0.18, 0.8, 0.88)
			g_rot["barrels"] = Vector3(-0.55 * open, 0, 0)
			rot += Vector3(0.28, 0.1, 0.25) * tilt
			pos += Vector3(-0.03, -0.02, 0.02) * tilt
			var fetch := _hump(t, 0.22, 0.34, 0.4, 0.5) + _hump(t, 0.5, 0.58, 0.62, 0.72)
			hand = pouch.lerp(Vector3(0.0, 0.05, 0.15), 1.0 - fetch) * _hump(t, 0.18, 0.24, 0.72, 0.8)
			rot.x += 0.12 * _hump(t, 0.8, 0.84, 0.86, 0.95)
		"cylinder":
			# Barillet basculé à gauche, éjection (arme levée), chargeur rapide.
			var open := _hump(t, 0.05, 0.16, 0.8, 0.9)
			g_rot["cyl"] = Vector3(0, 0, 1.4 * open)
			rot += Vector3(0.35 * _hump(t, 0.15, 0.22, 0.3, 0.38), 0.0, 0.55 * tilt)
			pos += Vector3(-0.05, 0.0, 0.0) * tilt
			var reach := _hump(t, 0.3, 0.45, 0.62, 0.74)
			hand = pouch.lerp(Vector3(0.0, 0.03, 0.06), reach) * _hump(t, 0.2, 0.3, 0.74, 0.86)
		"shells":
			# Coup par coup : arme couchée sur la droite, la main gauche pousse
			# chaque cartouche dans la fenêtre de chargement, puis un coup de pompe.
			rot += Vector3(0.12, 0.1, 0.36) * tilt
			pos += Vector3(-0.04, 0.03, 0.02) * tilt
			var n := _reload_count
			var span := 0.65
			var k := clampf((t - 0.12) / span, 0.0, 0.9999)
			var phase := fposmod(k * n, 1.0)
			var port := mag_top + Vector3(0, -0.015, 0.03) - support
			var push := _hump(phase, 0.1, 0.45, 0.6, 0.95)
			var active := _ss(0.08, 0.14, t) * (1.0 - _ss(0.77, 0.82, t))
			hand = (port + Vector3(0, -0.12, 0.08)).lerp(port, push) * active
			_shell_visible = active > 0.5 and phase < 0.62
			hand_rot = Vector3(0.6, 0, 0) * active
			var pump := _hump(t, 0.84, 0.88, 0.9, 0.96)
			if _groups.has("pump"):
				g_off["pump"] = Vector3(0, 0, 0.075 * pump)
				hand += Vector3(0, 0, 0.075 * pump)
		"rocket":
			# Tube jeté, nouveau tube : l'arme sort par le bas puis revient.
			var low := _hump(t, 0.05, 0.3, 0.65, 0.9)
			pos += Vector3(0.05, -0.45, 0.1) * low
			rot += Vector3(-0.9, 0.3, 0.2) * low
		_:
			# Chargeur (et bande, verrou, réservoirs) : l'arme bascule sur la
			# droite, la main gauche saisit le chargeur, le retire, en rapporte
			# un neuf, l'enfonce d'un coup sec, puis arme la culasse si vide.
			rot += Vector3(0.08, 0.15, -0.38) * tilt
			pos += Vector3(-0.04, 0.03, 0.0) * tilt
			if bolt:
				_bolt_pose(g_off, g_rot, travel, clampf(t / 0.28, 0.0, 1.0) * 0.5 + clampf((t - 0.74) / 0.18, 0.0, 1.0) * 0.5)
			var grab := _ss(0.06, 0.16, t)
			var out := _ss(0.17, 0.28, t)
			var back_in := _ss(0.42, 0.6, t)
			var seat := _ss(0.6, 0.66, t)
			# Chargeur : retiré (il tombe hors champ), puis le neuf remonte.
			var drop := 0.0
			if t < 0.4:
				drop = out * 0.09 + _ss(0.28, 0.4, t) * 0.5
			else:
				drop = (1.0 - back_in) * 0.5 + (1.0 - seat) * 0.03
			g_off["mag"] = mag_dir * drop
			# Main : vers le chargeur, suit sa chute, revient avec le neuf.
			var mag_hand := at_mag + mag_dir * drop
			var h := Vector3.ZERO.lerp(at_mag, grab)
			if t >= 0.17 and t < 0.66:
				h = mag_hand
			elif t >= 0.66:
				h = at_mag.lerp(Vector3.ZERO, _ss(0.7, 0.86, t))
			# Coup sec en fin d'insertion.
			rot.x += 0.06 * _hump(t, 0.6, 0.63, 0.64, 0.7)
			if _reload_empty and _groups.has("slide") and not bolt:
				# Armement : la main va au levier et le tire en arrière.
				var cp := WeaponModels.anchor(model_id, "pivot_slide") - support
				var arm_k := _hump(t, 0.66, 0.72, 0.84, 0.9)
				h = h.lerp(cp + Vector3(0, 0.0, 0.02), arm_k)
				var pull := _hump(t, 0.74, 0.78, 0.8, 0.83)
				g_off["slide"] = Vector3(0, 0, travel * pull)
				h.z += travel * pull
				rot += Vector3(0.0, -0.1, 0.25) * arm_k
			hand = h
			hand_rot = Vector3(0.2, 0.0, 0.0) * _hump(t, 0.1, 0.2, 0.6, 0.7)
	return [pos, rot, Transform3D(Basis.from_euler(hand_rot), hand)]


func is_busy() -> bool:
	return _reload_t >= 0.0 or _switch_t >= 0.0


# --------------------------------------------------------------------------

func _build_knife() -> Node3D:
	var rig := Node3D.new()
	rig.name = "Knife"
	rig.visible = false
	_fill_knife_rig(rig, KnifeDB.model(knife_id))
	return rig


## Main gauche gantée, avant-bras (manche) et couteau tenu lame en avant.
func _fill_knife_rig(rig: Node3D, mid: String) -> void:
	var hand := ViewHands.knife_hand(maxi(hand_style, 0))
	rig.add_child(hand)
	# Lame couchée : le tranchant regarde vers la droite (coup de gauche à droite).
	var knife := WeaponModels.build(mid, true)
	knife.name = "Blade"
	knife.rotation.z = 1.15
	knife.position = -WeaponModels.anchor(mid, "grip")
	rig.add_child(knife)
	hand.rotation.z = 1.15


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
	var low := Vector3(-0.12, -0.62, -0.74)
	var high := Vector3(-0.03, -0.14, -0.84)
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
		cm.radial_segments = 12
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


## Champ de vision (vertical) courant de l'arme : de la hanche à la visée.
func view_fov() -> float:
	var ak := ads * ads * (3.0 - 2.0 * ads)
	return lerpf(VIEW_FOV, VIEW_FOV_ADS, ak)
