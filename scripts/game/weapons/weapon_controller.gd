class_name WeaponController
extends Node
## Gestion des armes du joueur LOCAL (prédiction client).
##
## Le client joue immédiatement tir, recul, effets et décompte de munitions
## pour un ressenti sans latence, puis envoie ses intentions au serveur
## (Combat.srv_*). Le serveur fait foi : chaque resynchronisation d'inventaire
## écrase la prédiction locale.

const SWITCH_TIME := 0.55
const RAY_LENGTH := 150.0
const HITBOX_LAYER := 1 << 3

signal fired
signal ammo_changed

var player: Player
var combat: Combat
var session: Session
var fx: Fx
var view: ViewModel

## Copie locale (prédite) de l'inventaire.
var weapons: Array = []
var slot := 0
var _next_fire := 0.0
var _reload_end := -1.0
var _switch_end := -1.0
var _melee_ready := 0.0
var _recoil_debt := 0.0
var _trigger_released := true


func setup(p: Player, game: Game) -> void:
	player = p
	combat = game.get_node("Combat")
	session = game.get_node("Session")
	fx = game.fx_root
	view = ViewModel.new()
	view.name = "ViewModel"
	p.camera.add_child(view)
	session.inventory_changed.connect(_on_inventory_changed)
	_on_inventory_changed(p.peer_id)


func _on_inventory_changed(pid: int) -> void:
	if pid != player.peer_id:
		return
	var pd := session.get_data(pid)
	if pd == null:
		return
	var old_id: String = current().get("id", "")
	var old_pap: bool = current().get("pap", false)
	weapons = pd.weapons.duplicate(true)
	slot = pd.slot
	var w := current()
	if w.is_empty():
		return
	if w.id != old_id or w.pap != old_pap:
		if old_id == "":
			view.set_weapon(w.id, w.pap)
		else:
			_switch_end = now() + SWITCH_TIME
			view.start_switch(SWITCH_TIME, func(): view.set_weapon(w.id, w.pap))
			Audio.play_2d("weapon_switch", -6.0)
		_reload_end = -1.0
		view.cancel_reload()
	ammo_changed.emit()


static func now() -> float:
	return Time.get_ticks_msec() / 1000.0


func current() -> Dictionary:
	if weapons.is_empty():
		return {}
	return weapons[clampi(slot, 0, weapons.size() - 1)]


func current_stats() -> Dictionary:
	var w := current()
	return WeaponDB.stats(w.id, w.pap) if not w.is_empty() else {}


func is_reloading() -> bool:
	return _reload_end > 0.0


## Appelé par Player._local_physics à chaque image physique.
func tick(delta: float) -> void:
	var w := current()
	var t := now()
	if w.is_empty():
		return
	var s := current_stats()
	var inp := player.input

	# Fin de rechargement (prédite)
	if _reload_end > 0.0 and t >= _reload_end:
		_reload_end = -1.0
		var take: int = mini(s.mag - w.mag, w.reserve)
		w.mag += take
		w.reserve -= take
		ammo_changed.emit()

	var busy := _reload_end > 0.0 or t < _switch_end or t < _melee_ready - WeaponDB.MELEE_COOLDOWN * 0.3
	var dead := false
	var pd := session.get_data(player.peer_id)
	if pd:
		dead = pd.life == PlayerData.Life.DEAD

	if not inp.fire:
		_trigger_released = true

	if not dead:
		if inp.switch_weapon and weapons.size() > 1 and not busy:
			combat.srv_switch.rpc_id(1, (slot + 1) % weapons.size())
		elif inp.reload and not busy:
			_try_reload(w, s)
		elif inp.melee and t >= _melee_ready:
			_melee()
		elif inp.fire and not busy and not player.sprinting:
			var want: bool = s.auto or _trigger_released
			if want and t >= _next_fire:
				if w.mag > 0:
					_fire(w, s)
				elif _trigger_released:
					Audio.play_2d("dry_fire", -4.0)
					_trigger_released = false
					_try_reload(w, s)
		# Rechargement automatique quand le chargeur est vide.
		if w.mag == 0 and w.reserve > 0 and _reload_end < 0.0 and t >= _next_fire and not busy:
			_try_reload(w, s)

	# Récupération partielle du recul.
	if _recoil_debt > 0.0:
		var back := minf(_recoil_debt, delta * 4.0 * maxf(_recoil_debt, 0.02))
		_recoil_debt -= back
		player.pitch -= back
	view.update(delta, player)


func _fire(w: Dictionary, s: Dictionary) -> void:
	var t := now()
	_next_fire = t + WeaponDB.fire_interval(w.id, w.pap) / combat.game_rate_mult(player.peer_id)
	_trigger_released = false
	w.mag -= 1

	var origin := player.camera.global_position
	var fwd := player.aim_direction()
	var spread_deg: float = lerpf(s.spread_hip, s.spread_ads, view.ads)
	var speed := Vector2(player.velocity.x, player.velocity.z).length()
	if speed > 1.0:
		spread_deg *= 1.4
	if player.crouching:
		spread_deg *= 0.75
	var impacts := PackedVector3Array()
	var hits: Array = []
	for i in int(s.pellets):
		var dir := _spread_dir(fwd, spread_deg)
		_trace(origin, dir, int(s.penetration), impacts, hits)

	# Effets locaux immédiats
	var muzzle := view.muzzle_global()
	Audio.play_2d(s.sound, -1.0, 0.05)
	view.fire_kick(s.recoil)
	for i in range(0, impacts.size() - 1, 2):
		if i < 6 or randf() < 0.3:
			fx.tracer(muzzle, impacts[i])
		fx.impact(impacts[i], impacts[i + 1], i == 0)
	var kick := deg_to_rad(float(s.recoil)) * (0.55 if view.ads > 0.5 else 0.8)
	player.pitch += kick
	player.yaw += deg_to_rad(randf_range(-0.3, 0.3) * float(s.recoil))
	_recoil_debt += kick * 0.6
	combat.srv_fire.rpc_id(1, slot, origin, fwd, impacts, hits)
	fired.emit()
	ammo_changed.emit()


## Lancer de rayon avec pénétration : traverse jusqu'à `pen` zombies, s'arrête au décor.
func _trace(origin: Vector3, dir: Vector3, pen: int, impacts: PackedVector3Array, hits: Array) -> void:
	var space := player.get_world_3d().direct_space_state
	var from := origin
	var exclude: Array[RID] = [player.get_rid()]
	var remaining := pen
	for step in 12:
		var q := PhysicsRayQueryParameters3D.create(from, origin + dir * RAY_LENGTH, 1 | HITBOX_LAYER, exclude)
		q.collide_with_areas = true
		var r := space.intersect_ray(q)
		if r.is_empty():
			return
		var col: Object = r.collider
		if col is Area3D and col.has_meta("zombie_id"):
			hits.append([int(col.get_meta("zombie_id")), int(col.get_meta("zone", 0)), origin.distance_to(r.position)])
			fx.blood_hit(r.position, dir, 0.6)
			exclude.append(r.rid)
			# Les autres hitboxes du même zombie ne comptent pas deux fois.
			for sib in col.get_parent().get_children():
				if sib is Area3D:
					exclude.append(sib.get_rid())
			remaining -= 1
			if remaining <= 0:
				return
			from = r.position + dir * 0.01
		else:
			impacts.append(r.position)
			impacts.append(r.normal)
			return


static func _spread_dir(fwd: Vector3, spread_deg: float) -> Vector3:
	if spread_deg <= 0.001:
		return fwd
	var r := deg_to_rad(spread_deg) * sqrt(randf())
	var a := randf() * TAU
	var right := fwd.cross(Vector3.UP).normalized()
	if right.length_squared() < 0.01:
		right = Vector3.RIGHT
	var up := right.cross(fwd).normalized()
	return (fwd + (right * cos(a) + up * sin(a)) * tan(r)).normalized()


func _try_reload(w: Dictionary, s: Dictionary) -> void:
	if _reload_end > 0.0 or w.mag >= s.mag or w.reserve <= 0:
		return
	var dur := combat.reload_time(player.peer_id, w)
	_reload_end = now() + dur
	view.start_reload(dur)
	Audio.play_2d("mag_out", -3.0)
	get_tree().create_timer(dur * 0.55).timeout.connect(func():
		if _reload_end > 0.0:
			Audio.play_2d("mag_in", -3.0))
	get_tree().create_timer(dur * 0.85).timeout.connect(func():
		if _reload_end > 0.0:
			Audio.play_2d("slide", -5.0))
	combat.srv_reload.rpc_id(1, slot)


func _melee() -> void:
	_melee_ready = now() + WeaponDB.MELEE_COOLDOWN
	view.start_melee()
	Audio.play_2d("weapon_switch", -8.0, 0.2)
	combat.srv_melee.rpc_id(1, player.camera.global_position, player.aim_direction())
