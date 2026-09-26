class_name Combat
extends Node
## Autorité serveur sur le combat (chemin réseau : /root/Game/Combat).
##
## * Armes : le client envoie ses intentions (tir, rechargement, changement,
##   couteau) ; le serveur vérifie munitions, cadence, position.
## * Dégâts aux zombies : les touches revendiquées par le client sont VALIDÉES
##   (zombie vivant, rayon cohérent avec la position serveur, portée) puis les
##   dégâts sont calculés ici, à partir de WeaponDB. Le client ne décide jamais
##   des dégâts, ni de la mort, ni des points.
## * Dégâts aux joueurs : infligés par les zombies (serveur), santé et
##   régénération gérées ici.

## Tolérance de cadence : rafale max acceptée d'un coup (gigue réseau).
const FIRE_BURST_TOKENS := 4.0
## Écart max toléré entre l'origine du tir annoncée et la position serveur.
const MAX_ORIGIN_ERROR := 3.0
## Le serveur termine le rechargement un peu plus tôt que le client : le premier
## tir après un rechargement n'est jamais refusé à cause de la latence.
const RELOAD_LENIENCY := 0.85
## Distance max entre le rayon du tir et le zombie (côté serveur) : absorbe
## l'écart dû à l'interpolation des marionnettes chez le tireur.
const HIT_TOLERANCE := 1.4
const HEAD_TOLERANCE := 0.75
const MAX_RANGE := 160.0

const ZOMBIE_DAMAGE := 50
const REGEN_DELAY := 2.6
const REGEN_RATE := 110.0  # PV / s

enum HitKind { BULLET, MELEE, SPLASH, TRAP, SPECIAL }

signal shot_validated(pid: int)
signal shot_rejected(pid: int, reason: String)
## Serveur : un zombie a été touché. `killed` indique s'il en est mort.
signal zombie_damaged(pid: int, zid: int, damage: int, killed: bool, headshot: bool, kind: HitKind)
## Serveur : un joueur a atteint 0 PV.
signal player_fell(pid: int)
## Toutes les machines : un autre joueur a tiré (effets reçus du serveur).
signal remote_shot(pid: int)

var game: Game
var session: Session

## Serveur : état par joueur.
var _tokens: Dictionary = {}        # pid -> float
var _last_refill: Dictionary = {}   # pid -> sec
var _reload_end: Dictionary = {}    # pid -> [slot, end_time]
var _last_hurt: Dictionary = {}     # pid -> sec
var _melee_ready: Dictionary = {}   # pid -> sec
var _regen_sync := 0.0
## Tests automatisés uniquement : les joueurs ne subissent aucun dégât.
var debug_invulnerable := false


func _ready() -> void:
	game = get_parent()
	session = game.get_node("Session")


static func now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	var t := now()
	for pid in _reload_end.keys():
		var r: Array = _reload_end[pid]
		if t >= r[1]:
			_reload_end.erase(pid)
			_finish_reload(pid, r[0])
	_regenerate(delta, t)


# --------------------------------------------------------------------------
# Tir
# --------------------------------------------------------------------------

## `impacts` : positions/normales d'impact sur le décor (visuel, relayé aux autres).
## `hits` : touches revendiquées [zid, zone, distance, position] (validées ici).
@rpc("any_peer", "call_local", "reliable")
func srv_fire(slot: int, origin: Vector3, dir: Vector3, impacts: PackedVector3Array, hits: Array) -> void:
	if not multiplayer.is_server():
		return
	var pid := multiplayer.get_remote_sender_id()
	var reason := _validate_fire(pid, slot, origin)
	if reason != "":
		shot_rejected.emit(pid, reason)
		print("[Combat] tir refusé (%d) : %s" % [pid, reason])
		# Resynchronise le client dont la prédiction a divergé.
		session.sync_inventory(pid)
		return
	var pd := session.get_data(pid)
	var w: Dictionary = pd.current_weapon()
	w.mag -= 1
	shot_validated.emit(pid)
	var blood_points := _apply_hits(pid, w, origin, dir.normalized(), hits)
	_apply_splash(pid, w, impacts, hits)
	_cl_shot_fx.rpc(pid, w.id, w.pap, origin, impacts, blood_points)


func _validate_fire(pid: int, slot: int, origin: Vector3) -> String:
	var pd := session.get_data(pid)
	if pd == null:
		return "joueur inconnu"
	if pd.life == PlayerData.Life.DEAD:
		return "joueur mort"
	if slot != pd.slot:
		return "mauvais emplacement"
	var w: Dictionary = pd.current_weapon()
	if w.is_empty() or w.mag <= 0:
		return "chargeur vide"
	if _reload_end.has(pid):
		return "rechargement en cours"
	var p: Player = game.players.get(pid)
	if p and p.global_position.distance_to(origin) > MAX_ORIGIN_ERROR + 1.7:
		return "origine incohérente"
	# Seau de jetons : cadence moyenne respectée, rafale courte tolérée.
	var t := now()
	var rate := 1.0 / WeaponDB.fire_interval(w.id, w.pap) * game_rate_mult(pid)
	var tokens: float = _tokens.get(pid, FIRE_BURST_TOKENS)
	tokens = minf(tokens + (t - _last_refill.get(pid, t)) * rate * 1.25, FIRE_BURST_TOKENS)
	_last_refill[pid] = t
	if tokens < 1.0:
		_tokens[pid] = tokens
		return "cadence trop élevée"
	_tokens[pid] = tokens - 1.0
	return ""


## Multiplicateur de cadence (atout TWIN SHOT).
func game_rate_mult(pid: int) -> float:
	return PerkDB.fire_rate_mult(session.get_data(pid))


## Multiplicateur de dégâts d'un joueur (atouts).
func damage_mult(pid: int) -> float:
	return PerkDB.damage_mult(session.get_data(pid))


## Valide et applique les touches. Retourne les points de sang à afficher chez
## les autres joueurs.
func _apply_hits(pid: int, w: Dictionary, origin: Vector3, dir: Vector3, hits: Array) -> PackedVector3Array:
	var blood := PackedVector3Array()
	if hits.is_empty():
		return blood
	var s := WeaponDB.stats(w.id, w.pap)
	var max_hits := int(s.pellets) * int(s.penetration)
	# Cumul par zombie (plombs de fusil à pompe sur une même cible).
	var per_zombie := {}
	var n := 0
	for h in hits:
		if n >= max_hits:
			break
		n += 1
		if not (h is Array) or h.size() < 4:
			continue
		var zid := int(h[0])
		var z: Zombie = game.zombies.get_zombie(zid)
		if z == null or not z.is_alive():
			continue
		var center := z.global_position + Vector3.UP * 0.95
		var to_c := center - origin
		var along := to_c.dot(dir)
		if along < 0.0 or along > MAX_RANGE:
			continue
		var ray_dist := (to_c - dir * along).length()
		if ray_dist > HIT_TOLERANCE:
			print("[Combat] touche refusée (%d) : zombie %d à %.2f m du rayon" % [pid, zid, ray_dist])
			continue
		var head := false
		if int(h[1]) == 1:
			var hp := z.head_position()
			var to_h := hp - origin
			var hd := (to_h - dir * to_h.dot(dir)).length()
			head = hd < HEAD_TOLERANCE
		var dmg: float = float(s.damage) * WeaponDB.falloff(w.id, w.pap, along)
		if head:
			dmg *= float(s.head_mult)
		var acc: Array = per_zombie.get(zid, [0.0, false, h[3]])
		acc[0] += dmg
		acc[1] = acc[1] or head
		per_zombie[zid] = acc
	for zid in per_zombie:
		var acc: Array = per_zombie[zid]
		damage_zombie(zid, int(acc[0] * damage_mult(pid)), pid, acc[1], dir, HitKind.BULLET)
		if acc[2] is Vector3:
			blood.append(acc[2])
	return blood


## Dégâts de zone (arme spéciale) au premier impact.
func _apply_splash(pid: int, w: Dictionary, impacts: PackedVector3Array, hits: Array) -> void:
	var s := WeaponDB.stats(w.id, w.pap)
	if not s.has("splash_radius"):
		return
	var center := Vector3.INF
	if not hits.is_empty() and hits[0] is Array and hits[0].size() >= 4 and hits[0][3] is Vector3:
		center = hits[0][3]
	elif impacts.size() >= 2:
		center = impacts[0]
	if center == Vector3.INF:
		return
	var p: Player = game.players.get(pid)
	if p and p.global_position.distance_to(center) > MAX_RANGE:
		return
	var r: float = s.splash_radius
	for z: Zombie in game.zombies.alive.duplicate():
		# Distance au centre du corps (et non aux pieds).
		var d := (z.global_position + Vector3.UP * 0.9).distance_to(center)
		if d <= r:
			var k := 1.0 - d / r * 0.5
			damage_zombie(z.id, int(float(s.splash_damage) * k * damage_mult(pid)), pid, false, (z.global_position - center).normalized(), HitKind.SPLASH)
	_cl_splash_fx.rpc(center, r)


## Serveur : inflige des dégâts à un zombie. Point d'entrée unique pour toutes
## les sources (balles, couteau, pièges...).
func damage_zombie(zid: int, dmg: int, pid: int, headshot: bool, dir: Vector3, kind: HitKind) -> void:
	if not multiplayer.is_server():
		return
	var z: Zombie = game.zombies.get_zombie(zid)
	if z == null or not z.is_alive() or dmg <= 0:
		return
	# Bonus MORT INSTANTANÉE : tout coup d'un joueur tue.
	if pid > 0 and game.powerups and game.powerups.insta_kill():
		dmg = maxi(dmg, z.health)
	z.health -= dmg
	var killed := z.health <= 0
	if killed:
		game.zombies.kill(zid, headshot, dir, kind == HitKind.SPLASH or kind == HitKind.TRAP)
	else:
		_cl_zombie_hit.rpc(zid, headshot)
	zombie_damaged.emit(pid, zid, dmg, killed, headshot, kind)
	if pid > 0 and killed:
		if pid == multiplayer.get_unique_id():
			_cl_hit_confirm(killed, headshot)
		else:
			_cl_hit_confirm.rpc_id(pid, killed, headshot)


@rpc("authority", "call_local", "reliable")
func _cl_shot_fx(pid: int, weapon_id: String, pap: bool, origin: Vector3, impacts: PackedVector3Array, blood_points: PackedVector3Array) -> void:
	# Le tireur a déjà joué ses effets localement (prédiction).
	if pid == multiplayer.get_unique_id():
		return
	var fx: Fx = game.fx_root
	var s := WeaponDB.stats(weapon_id, pap)
	var shooter: Player = game.players.get(pid)
	if shooter:
		shooter.visual.fire_kick()
	remote_shot.emit(pid)
	Audio.play_3d(s.sound, origin, 0.0, 0.05, 8, s.get("sound_pitch", 0.8 if pap else 1.0))
	fx.muzzle_flash(origin)
	for i in range(0, impacts.size() - 1, 2):
		fx.tracer(origin, impacts[i])
		fx.impact(impacts[i], impacts[i + 1], i == 0)
	for bp in blood_points:
		fx.blood_hit(bp, (bp - origin).normalized(), 0.7)


@rpc("authority", "call_local", "reliable")
func _cl_zombie_hit(zid: int, headshot: bool) -> void:
	var z: Zombie = game.zombies.get_zombie(zid)
	if z:
		z.flash_hit()
		Audio.play_3d("flesh_hit_%d" % (1 + randi() % 3), z.global_position + Vector3.UP, -4.0 if not headshot else 0.0, 0.1, 5)


@rpc("authority", "call_local", "reliable")
func _cl_splash_fx(center: Vector3, radius: float) -> void:
	game.fx_root.explosion(center, radius)


## Retour au tireur : sa touche a été confirmée par le serveur.
@rpc("authority", "call_remote", "reliable")
func _cl_hit_confirm(killed: bool, headshot: bool) -> void:
	game.hud.hit_marker(killed, headshot)


# --------------------------------------------------------------------------
# Mêlée
# --------------------------------------------------------------------------

@rpc("any_peer", "call_local", "reliable")
func srv_melee(origin: Vector3, dir: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var pid := multiplayer.get_remote_sender_id()
	var pd := session.get_data(pid)
	var p: Player = game.players.get(pid)
	var t := now()
	if pd == null or p == null or pd.life != PlayerData.Life.ALIVE or t < _melee_ready.get(pid, 0.0):
		return
	if p.global_position.distance_to(origin) > MAX_ORIGIN_ERROR + 1.7:
		return
	_melee_ready[pid] = t + WeaponDB.MELEE_COOLDOWN * 0.8
	dir = Vector3(dir.x, 0.0, dir.z).normalized()
	var best: Zombie = null
	var best_d := INF
	for z: Zombie in game.zombies.alive:
		var to := z.global_position - p.global_position
		to.y = 0.0
		var d := to.length()
		if d < WeaponDB.MELEE_RANGE and d < best_d and (d < 0.6 or to.normalized().dot(dir) > 0.45):
			best = z
			best_d = d
	if best:
		damage_zombie(best.id, int(WeaponDB.MELEE_DAMAGE * damage_mult(pid)), pid, false, dir, HitKind.MELEE)
		_cl_melee_fx.rpc(best.global_position + Vector3.UP * 1.2)


@rpc("authority", "call_local", "reliable")
func _cl_melee_fx(pos: Vector3) -> void:
	Audio.play_3d("knife_hit", pos, 0.0)
	game.fx_root.blood_hit(pos, Vector3.DOWN, 1.2)


# --------------------------------------------------------------------------
# Rechargement / changement d'arme
# --------------------------------------------------------------------------

@rpc("any_peer", "call_local", "reliable")
func srv_reload(slot: int) -> void:
	if not multiplayer.is_server():
		return
	var pid := multiplayer.get_remote_sender_id()
	var pd := session.get_data(pid)
	if pd == null or slot != pd.slot or _reload_end.has(pid):
		return
	var w: Dictionary = pd.current_weapon()
	var s := WeaponDB.stats(w.id, w.pap)
	if w.mag >= s.mag or w.reserve <= 0:
		return
	_reload_end[pid] = [slot, now() + reload_time(pid, w) * RELOAD_LENIENCY]
	_cl_reload_fx.rpc(pid)


func reload_time(pid: int, w: Dictionary) -> float:
	return WeaponDB.stats(w.id, w.pap).reload * PerkDB.reload_mult(session.get_data(pid))


func _finish_reload(pid: int, slot: int) -> void:
	var pd := session.get_data(pid)
	if pd == null or slot != pd.slot:
		return
	var w: Dictionary = pd.current_weapon()
	var s := WeaponDB.stats(w.id, w.pap)
	var need: int = s.mag - w.mag
	var take: int = mini(need, w.reserve)
	w.mag += take
	w.reserve -= take
	session.sync_inventory(pid)


@rpc("any_peer", "call_local", "reliable")
func srv_switch(slot: int) -> void:
	if not multiplayer.is_server():
		return
	var pid := multiplayer.get_remote_sender_id()
	var pd := session.get_data(pid)
	if pd == null or slot < 0 or slot >= pd.weapons.size() or slot == pd.slot:
		return
	_reload_end.erase(pid)
	pd.slot = slot
	session.sync_inventory(pid)


@rpc("authority", "call_local", "reliable")
func _cl_reload_fx(pid: int) -> void:
	if pid == multiplayer.get_unique_id():
		return
	var p: Player = game.players.get(pid)
	if p:
		Audio.play_3d("mag_out", p.global_position + Vector3.UP, -4.0)


## Serveur : annule un rechargement en cours (changement d'arme, achat...).
func cancel_reload(pid: int) -> void:
	_reload_end.erase(pid)


func is_reloading(pid: int) -> bool:
	return _reload_end.has(pid)


# --------------------------------------------------------------------------
# Santé des joueurs (serveur)
# --------------------------------------------------------------------------

## Inflige des dégâts à un joueur. `from` : position de la source (direction
## de l'indicateur de dégâts).
func damage_player(pid: int, amount: int, from: Vector3) -> void:
	if not multiplayer.is_server():
		return
	if debug_invulnerable:
		return
	var pd := session.get_data(pid)
	if pd == null or pd.life != PlayerData.Life.ALIVE or amount <= 0:
		return
	pd.health = maxi(pd.health - amount, 0)
	_last_hurt[pid] = now()
	session.sync_stats(pid)
	_cl_player_hurt.rpc(pid, from)
	if pd.health <= 0:
		player_fell.emit(pid)


func _regenerate(delta: float, t: float) -> void:
	_regen_sync += delta
	var do_sync := _regen_sync >= 0.25
	if do_sync:
		_regen_sync = 0.0
	for pid in session.data:
		var pd: PlayerData = session.data[pid]
		if pd.life != PlayerData.Life.ALIVE or pd.health >= pd.max_health:
			continue
		if t - _last_hurt.get(pid, 0.0) < REGEN_DELAY * PerkDB.regen_delay_mult(pd):
			continue
		pd.health = mini(pd.health + int(ceil(REGEN_RATE * delta)), pd.max_health)
		if do_sync or pd.health >= pd.max_health:
			session.sync_stats(pid)


@rpc("authority", "call_local", "reliable")
func _cl_player_hurt(pid: int, from: Vector3) -> void:
	var p: Player = game.players.get(pid)
	if p == null:
		return
	Audio.play_3d("player_hurt_%d" % (1 + randi() % 2), p.global_position + Vector3.UP * 1.5, -2.0)
	if p.is_local:
		game.hud.damage_flash(from)
		p.flinch(from)


func forget_player(pid: int) -> void:
	_tokens.erase(pid)
	_last_refill.erase(pid)
	_reload_end.erase(pid)
	_last_hurt.erase(pid)
	_melee_ready.erase(pid)
