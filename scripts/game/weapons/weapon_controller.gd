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
var _drink_end := -1.0
## Couteau de mêlée tenu (KnifeDB) et fin de l'animation de récupération.
var knife_id := ""
var _pickup_end := -1.0
## Vrai entre le début d'une fente et le coup de couteau qui la termine.
var lunging := false
## Coups restant à tirer dans la rafale en cours (M16, G11...).
var _burst_left := 0
## Grenades et SINGE-TAMBOUR (dégoupillage, cuisson, lancer).
var throws: ThrowController
## DEADEYE DRAM : aimantation de la visée vers la tête.
var deadeye := DeadeyeAim.new()
## Dispersion (degrés) du dernier tir (tests).
var last_spread_deg := 0.0

## Sons de rechargement par mécanisme : [fraction de la durée, son].
const RELOAD_SOUNDS := {
	"mag": [[0.0, "mag_out"], [0.55, "mag_in"], [0.85, "slide"]],
	"belt": [[0.0, "mag_out"], [0.3, "break_open"], [0.6, "mag_in"], [0.85, "bolt"]],
	"break": [[0.05, "break_open"], [0.4, "shell_in"], [0.55, "shell_in"], [0.85, "break_close"]],
	"bolt": [[0.08, "bolt"], [0.3, "mag_out"], [0.6, "mag_in"], [0.86, "bolt"]],
	"cylinder": [[0.05, "break_open"], [0.2, "shell"], [0.55, "shell_in"], [0.85, "break_close"]],
	"rocket": [[0.1, "mag_out"], [0.55, "mag_in"], [0.85, "break_close"]],
	# TONNERRE-7 : réservoirs vidés, nouveaux réservoirs, tambour qui se recharge en pression.
	"thunder": [[0.05, "break_open"], [0.25, "mag_out"], [0.5, "mag_in"], [0.62, "thunder_charge"], [0.9, "break_close"]],
}


func setup(p: Player, game: Game) -> void:
	player = p
	combat = game.get_node("Combat")
	session = game.get_node("Session")
	fx = game.fx_root
	view = ViewModel.new()
	view.name = "ViewModel"
	p.camera.add_child(view)
	throws = ThrowController.new()
	throws.name = "Throws"
	add_child(throws)
	throws.setup(self, game)
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
	if not pd.powerup_weapon.is_empty() and pd.life == PlayerData.Life.ALIVE:
		# Arme de bonus seule en main (pas de changement d'arme) ; `slot` reste
		# celui du serveur pour la validation des tirs.
		weapons = [pd.powerup_weapon.duplicate()]
	if pd.knife != knife_id:
		_on_knife_changed(pd.knife)
	var w := current()
	# Mains vides (arme déposée dans le Pack-a-Punch...).
	view.visible = not w.is_empty()
	if w.is_empty():
		ammo_changed.emit()
		return
	if w.id != old_id or w.pap != old_pap:
		if old_id == "":
			view.set_weapon(w.id, w.pap)
		else:
			_switch_end = now() + SWITCH_TIME
			view.start_switch(SWITCH_TIME, func(): view.set_weapon(w.id, w.pap))
			Audio.play_2d("weapon_switch", -6.0)
		_reload_end = -1.0
		_burst_left = 0
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
	throws.tick(delta)
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

	var busy := _reload_end > 0.0 or t < _switch_end or t < _drink_end or t < _melee_ready - WeaponDB.MELEE_COOLDOWN * 0.3 or t < _pickup_end \
		or throws.busy()
	var dead := false
	var pd := session.get_data(player.peer_id)
	if pd:
		dead = pd.life == PlayerData.Life.DEAD

	if not inp.fire:
		_trigger_released = true

	if not dead and _burst_left > 0:
		# Rafale en cours : les coups suivants partent seuls, même détente relâchée.
		if busy or w.mag <= 0:
			_burst_left = 0
		elif t >= _next_fire:
			_fire(w, s)
	elif not dead:
		if inp.switch_weapon and weapons.size() > 1 and not busy:
			combat.srv_switch.rpc_id(1, (slot + 1) % weapons.size())
		elif inp.reload and not busy:
			_try_reload(w, s)
		elif inp.melee and t >= _melee_ready and t >= _pickup_end and not throws.busy():
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
	if not dead:
		# Rechargement automatique quand le chargeur est vide.
		if w.mag == 0 and w.reserve > 0 and _reload_end < 0.0 and t >= _next_fire and not busy:
			_try_reload(w, s)

	# Récupération partielle du recul.
	if _recoil_debt > 0.0:
		var back := minf(_recoil_debt, delta * 4.0 * maxf(_recoil_debt, 0.02))
		_recoil_debt -= back
		player.pitch -= back
	deadeye.tick(self, delta)
	view.update(delta, player)


func _fire(w: Dictionary, s: Dictionary) -> void:
	var t := now()
	var interval := WeaponDB.fire_interval(w.id, w.pap) / combat.game_rate_mult(player.peer_id)
	_next_fire = t + interval
	_trigger_released = false
	w.mag -= 1
	var burst: int = s.get("burst", 0)
	if burst > 1:
		_burst_left = burst - 1 if _burst_left <= 0 else _burst_left - 1
		if _burst_left <= 0 or w.mag <= 0:
			_burst_left = 0
			_next_fire += float(s.get("burst_delay", 0.2))
	# Fusil à pompe / à verrou : bruit du mécanisme entre deux coups.
	var cycle: String = s.get("cycle", "")
	if cycle != "" and w.mag > 0:
		get_tree().create_timer(interval * 0.4).timeout.connect(func(): Audio.play_2d(cycle, -4.0))

	var origin := player.camera.global_position
	var fwd := player.aim_direction()
	var ppd := session.get_data(player.peer_id)
	var spread_deg: float = lerpf(s.spread_hip * PerkDB.hip_spread_mult(ppd), s.spread_ads, view.ads)
	var speed := Vector2(player.velocity.x, player.velocity.z).length()
	if speed > 1.0:
		spread_deg *= 1.4
	if player.prone:
		spread_deg *= 0.6
	elif player.crouching:
		spread_deg *= 0.75
	last_spread_deg = spread_deg
	var impacts := PackedVector3Array()
	var hits: Array = []
	var blast: bool = s.has("blast_range")
	# Onde de choc (TONNERRE-7) : pas de balle, le serveur calcule le cône.
	for i in (0 if blast else int(s.pellets)):
		var dir := _spread_dir(fwd, spread_deg)
		_trace(origin, dir, int(s.penetration), impacts, hits)

	# Effets locaux immédiats
	var muzzle := view.muzzle_global()
	Audio.play_2d(s.sound, -1.0, 0.05, "SFX", s.get("sound_pitch", 0.8 if w.pap else 1.0))
	view.fire_kick(s.recoil)
	if blast:
		ThunderBlast.play_fx(fx, muzzle, fwd, w.pap, s.blast_range)
		var bkick := deg_to_rad(float(s.recoil))
		player.pitch += bkick
		_recoil_debt += bkick * 0.7
		combat.srv_fire.rpc_id(1, slot, origin, fwd, impacts, hits)
		fired.emit()
		ammo_changed.emit()
		return
	var tracer_col := Color(1.0, 0.45, 0.1, 1.0) if s.get("tracer", "") == "ray" else Color(1.0, 0.8, 0.5, 0.7)
	var ray_end: Vector3 = impacts[0] if impacts.size() >= 2 else (hits[0][3] if not hits.is_empty() else origin + fwd * 40.0)
	if s.has("projectile_speed"):
		# Grenade / roquette : projectile visible, l'explosion vient du serveur.
		ProjectileFx.launch(fx, muzzle, ray_end, s.projectile_speed, s.get("tracer", "grenade"), w.pap)
	else:
		if s.get("tracer", "") == "ray":
			fx.tracer(muzzle, ray_end, tracer_col, 0.12)
		for i in range(0, impacts.size() - 1, 2):
			if s.get("tracer", "") != "ray" and (i < 6 or randf() < 0.3):
				fx.tracer(muzzle, impacts[i], tracer_col)
			fx.impact(impacts[i], impacts[i + 1], i == 0)
	var kick := deg_to_rad(float(s.recoil)) * (0.55 if view.ads > 0.5 else 0.8) * PerkDB.recoil_mult(ppd)
	player.pitch += kick
	player.yaw += deg_to_rad(randf_range(-0.3, 0.3) * float(s.recoil)) * PerkDB.recoil_mult(ppd)
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
			hits.append([int(col.get_meta("zombie_id")), int(col.get_meta("zone", 0)), origin.distance_to(r.position), r.position])
			fx.blood_hit(r.position, dir, 0.6)
			Game.instance.hud.hit_marker(false, int(col.get_meta("zone", 0)) == 1)
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
	_burst_left = 0
	for step in reload_sounds(s, w):
		get_tree().create_timer(maxf(dur * float(step[0]), 0.001)).timeout.connect(func():
			if _reload_end > 0.0:
				Audio.play_2d(step[1], -3.0))
	combat.srv_reload.rpc_id(1, slot)


## Suite de sons [fraction, son] d'un rechargement (cartouches une à une pour
## les fusils à pompe et lance-grenades, comme dans BO1).
static func reload_sounds(s: Dictionary, w: Dictionary) -> Array:
	var kind: String = s.get("reload_kind", "mag")
	if kind != "shells":
		return RELOAD_SOUNDS.get(kind, RELOAD_SOUNDS.mag)
	var n := clampi(int(s.mag) - int(w.get("mag", 0)), 1, 6)
	var out := []
	for i in n:
		out.append([0.12 + 0.65 * float(i) / n, "shell_in"])
	out.append([0.88, "pump"])
	return out


## Coup de couteau. Si un zombie visé est à portée de fente (KnifeDB), le
## joueur se projette d'abord vers lui (LUNGE_TIME), puis frappe : le serveur
## valide le coup depuis la position d'arrivée.
func _melee() -> void:
	_melee_ready = now() + WeaponDB.MELEE_COOLDOWN
	_reload_end = -1.0
	view.cancel_reload()
	_burst_left = 0
	var target := _lunge_target()
	var lunge := target != null
	view.start_melee(lunge)
	Audio.play_2d("knife_swing", -4.0, 0.1)
	if not lunge:
		_strike()
		return
	var to := target.global_position - player.global_position
	to.y = 0.0
	var dist := maxf(to.length() - KnifeDB.LUNGE_STOP, 0.0)
	lunging = true
	player.start_lunge(to.normalized(), dist, KnifeDB.LUNGE_TIME)
	get_tree().create_timer(KnifeDB.LUNGE_TIME).timeout.connect(func():
		lunging = false
		_strike())


func _strike() -> void:
	var pd := session.get_data(player.peer_id)
	if pd == null or pd.life != PlayerData.Life.ALIVE:
		return
	combat.srv_melee.rpc_id(1, player.camera.global_position, player.aim_direction())


## Zombie visé à portée de fente (au-delà de la portée au contact), visible.
func _lunge_target() -> Zombie:
	if Game.instance == null or Game.instance.zombies == null:
		return null
	var alive: Array[Zombie] = Game.instance.zombies.alive
	var positions := []
	for z in alive:
		positions.append(z.global_position)
	var i := KnifeDB.pick_target(player.global_position, player.aim_direction(), positions)
	if i < 0:
		return null
	var z: Zombie = alive[i]
	var flat := z.global_position - player.global_position
	flat.y = 0.0
	if not KnifeDB.needs_lunge(flat.length()):
		return null
	# Pas de fente à travers un mur ou une barricade.
	var q := PhysicsRayQueryParameters3D.create(player.eye_position(), z.global_position + Vector3.UP * 1.0, 1 | Barricade.BARRIER_LAYER, [player.get_rid()])
	if not player.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
		return null
	return z


## Nouveau couteau (achat du COUTEAU DE CHASSE) : animation de récupération.
func _on_knife_changed(id: String) -> void:
	var first := knife_id == ""
	knife_id = id
	view.set_knife(id)
	if first:
		return
	_pickup_end = now() + KnifeDB.PICKUP_TIME
	_reload_end = -1.0
	_burst_left = 0
	view.cancel_reload()
	view.start_knife_pickup(KnifeDB.PICKUP_TIME)
	Audio.play_2d("bowie_draw", -3.0)


func is_picking_up_knife() -> bool:
	return now() < _pickup_end


## Coup de couteau, fente ou récupération du couteau en cours : pas de lancer
## de grenade pendant ce temps (ThrowController).
func is_knifing() -> bool:
	var t := now()
	return t < _melee_ready - WeaponDB.MELEE_COOLDOWN * 0.3 or t < _pickup_end


## Lancer de grenade : le rechargement en cours est abandonné (comme BO1 ;
## le serveur l'annule aussi, voir ThrowableSystem.srv_cook).
func cancel_reload_local() -> void:
	_reload_end = -1.0
	_burst_left = 0
	view.cancel_reload()


## Boisson d'un atout : l'arme est baissée, une bouteille apparaît.
func drink(color: Color, duration: float) -> void:
	_drink_end = now() + duration
	_reload_end = -1.0
	view.cancel_reload()
	view.start_drink(color, duration)
