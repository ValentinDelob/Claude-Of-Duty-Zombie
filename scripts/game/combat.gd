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

## Tolérance de cadence : rafale max acceptée d'un coup (gigue réseau), en
## tirs au moins FIRE_BURST_TOKENS, et au moins FIRE_BURST_SEC de tirs de
## l'arme : pour une arme très rapide (20 coups/s), 4 tirs ne
## couvraient qu'un à-coup de 0,2 s (tirs d'un joueur honnête refusés).
const FIRE_BURST_TOKENS := 4.0
const FIRE_BURST_SEC := 0.4
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
## Points revendiqués par tir au plus (impacts position / normale, touches) :
## 8 plombs x pénétration, largement ; au-delà, le reste est ignoré.
const MAX_CLAIMED_POINTS := 128
## Demi-angle du cône où un point d'explosion revendiqué est accepté (la
## dispersion la plus large, fusil de précision à la hanche, fait 7 à 10°).
const SPLASH_CONE_DEG := 20.0
## Écart max entre le point d'impact revendiqué sur un zombie et son corps.
const MAX_HIT_POINT_ERROR := 2.5

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
## Serveur : un joueur a atterri d'un plongeon (crochet pour un futur effet
## à l'atterrissage selon `height`).
signal player_dived_landed(pid: int, position: Vector3, height: float)

var game: Game
var session: Session

## Serveur : état par joueur.
## Cadence de tir : seau de jetons au débit et à la rafale de l'arme en main
## (_validate_fire).
var _fire_limit := NetGuard.Limiter.new(0.0, FIRE_BURST_TOKENS)
var _reload_end: Dictionary = {}    # pid -> [slot, end_time, start_time, durée]
var _last_hurt: Dictionary = {}     # pid -> sec
var _melee_ready: Dictionary = {}   # pid -> sec
## Resynchronisations après un tir refusé (4 par seconde au plus et par joueur).
var _resync_limit := NetGuard.Limiter.new(4.0, 4.0)
## Requêtes de rechargement / changement d'arme (bien au-delà d'un humain).
var _action_limit := NetGuard.Limiter.new(15.0, 15.0)
## Serveur : dernier plongeon accepté par joueur (s).
var _dive_last: Dictionary = {}
var _regen_sync := 0.0
## Serveur : zombies en feu (balles incendiaires) : zid -> [pid, dps, fin].
var _burns: Dictionary = {}
var _burn_next := 0.0
const BURN_TICK := 0.25
## Serveur : effets de tir et de touche de l'image, envoyés groupés (_flush_fx).
var _fx_buf := PackedByteArray()
## Serveur : contexte du coup en cours pour le démembrement (_apply_hits).
var _gib_at := Vector3.INF
var _gib_weapon := ""
## Tests automatisés uniquement : les joueurs ne subissent aucun dégât.
var debug_invulnerable := false


func _ready() -> void:
	game = get_parent()
	session = game.get_node("Session")


func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_flush_fx()
	var t := GameClock.now()
	for pid in _reload_end.keys():
		var r: Array = _reload_end[pid]
		if t >= r[1]:
			_reload_end.erase(pid)
			_finish_reload(pid, r[0])
	if not _burns.is_empty():
		_tick_burns(t)
	_regenerate(delta, t)


# --------------------------------------------------------------------------
# Tir
# --------------------------------------------------------------------------

## `impacts` : positions/normales d'impact sur le décor (visuel, relayé aux autres).
## `hits` : touches revendiquées [zid, zone, distance, position] (validées ici).
@rpc("any_peer", "call_local", "reliable")
func srv_fire(slot: int, origin: Vector3, dir: Vector3, impacts: PackedVector3Array, hits: Array) -> void:
	# Pas de contrôle « vivant » ici : _validate_fire donne la raison du refus
	# (signal shot_rejected, resynchronisation du client).
	var pid := NetGuard.server_sender(self)
	if pid == NetGuard.NO_SENDER:
		return
	# Arguments du client bornés AVANT tout contrôle : un NaN ferait échouer
	# les comparaisons de distance (touches acceptées partout sur la carte).
	var reason := "tir invalide" if not NetGuard.finite_vec(origin) or not NetGuard.valid_dir(dir) else _validate_fire(pid, slot, origin)
	if reason != "":
		shot_rejected.emit(pid, reason)
		# Resynchronise le client dont la prédiction a divergé (borné : un
		# client qui inonde de tirs refusés ne fait pas inonder les autres).
		if _resync_limit.allow(pid):
			print("[Combat] tir refusé (%d) : %s" % [pid, reason])
			session.sync_inventory(pid)
		return
	dir = dir.normalized()
	impacts = NetGuard.clean_vecs(impacts, MAX_CLAIMED_POINTS, true)
	if hits.size() > MAX_CLAIMED_POINTS:
		hits = hits.slice(0, MAX_CLAIMED_POINTS)
	var pd := session.get_data(pid)
	var w: Dictionary = pd.current_weapon()
	w.mag -= 1
	shot_validated.emit(pid)
	# Point d'explosion revendiqué (grenade, roquette) : sur la trajectoire du
	# tir seulement, jamais une explosion posée n'importe où sur la carte.
	var s0 := WeaponDB.stats(w.id, w.pap)
	if (s0.has("splash_radius") or s0.has("projectile_speed")) and not plausible_splash(origin, dir, _splash_center(impacts, hits)):
		print("[Combat] explosion refusée (%d) : hors de la trajectoire" % pid)
		impacts = PackedVector3Array()
		hits = []
	var blood_points := PackedVector3Array()
	# Projectile (grenade, roquette) : effet à l'arrivée, pas à l'instant du tir.
	var delay := WeaponDB.projectile_delay(w.id, w.pap, origin, _splash_center(impacts, hits))
	if delay > 0.0:
		var shot := {"id": w.id, "pap": w.pap}
		get_tree().create_timer(delay).timeout.connect(func():
			_apply_hits(pid, shot, origin, dir.normalized(), hits)
			_apply_splash(pid, shot, impacts, hits))
	else:
		blood_points = _apply_hits(pid, w, origin, dir.normalized(), hits)
		_apply_splash(pid, w, impacts, hits)
	if delay > 0.0:
		# Les autres joueurs voient le projectile filer jusqu'au point d'explosion.
		impacts = PackedVector3Array([_splash_center(impacts, hits), Vector3.UP])
	NetCodec.append_shot(_fx_buf, pid, w.id, w.pap, origin, impacts, blood_points)


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
	if p and not origin_ok(p.srv_origin(), origin, MAX_ORIGIN_ERROR + 1.7):
		return "origine incohérente"
	# Seau de jetons : cadence moyenne respectée, rafale courte tolérée.
	var t := GameClock.now()
	var rate := 1.0 / WeaponDB.fire_interval(w.id, w.pap)
	if not _fire_limit.take(pid, t, rate * 1.25, fire_burst(rate)):
		return "cadence trop élevée"
	return ""


## Vrai si l'origine annoncée `origin` (finie) est à `tol` m au plus de la
## position de référence du serveur `ref` (Player.srv_origin : dernier état
## reçu et accepté, pas la position interpolée affichée).
static func origin_ok(ref: Vector3, origin: Vector3, tol: float) -> bool:
	return NetGuard.finite_vec(origin) and ref.distance_to(origin) <= tol


## Position d'atterrissage retenue pour un plongeon : celle du client si elle
## est cohérente avec la référence du serveur `ref`, sinon `ref`.
static func dive_landing(ref: Vector3, claimed: Vector3) -> Vector3:
	return claimed if origin_ok(ref, claimed, MAX_ORIGIN_ERROR) else ref


## Rafale tolérée (jetons) pour une arme tirant `rate` coups par seconde.
static func fire_burst(rate: float) -> float:
	return maxf(FIRE_BURST_TOKENS, rate * FIRE_BURST_SEC)


## Vrai si le point d'explosion `c` revendiqué par le tireur est sur la
## trajectoire du tir (cône de SPLASH_CONE_DEG autour de la visée : couvre la
## dispersion de toutes les armes), à portée. Vector3.INF (rien touché) : vrai.
static func plausible_splash(origin: Vector3, dir: Vector3, c: Vector3) -> bool:
	if c == Vector3.INF:
		return true
	if not NetGuard.finite_vec(c):
		return false
	var rd := NetGuard.ray_distance(origin, dir, c)
	# Derrière le tireur (au-delà d'un mètre) ou hors de portée : jamais.
	if rd.y < -1.0 or rd.y > MAX_RANGE + 5.0:
		return false
	if rd.x <= HIT_TOLERANCE + 0.6:
		return true
	return rd.x <= maxf(rd.y, 0.0) * tan(deg_to_rad(SPLASH_CONE_DEG))


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
		if not (h is Array) or h.size() < 4 or not (h[0] is int) or not (h[1] is int):
			continue
		var zid: int = h[0]
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
		# Point d'impact (sang, démembrement) : sur le zombie, sinon son centre.
		var at: Vector3 = h[3] if h[3] is Vector3 and NetGuard.finite_vec(h[3]) and (h[3] as Vector3).distance_to(center) <= MAX_HIT_POINT_ERROR else center
		var acc: Array = per_zombie.get(zid, [0.0, false, at])
		acc[0] += dmg
		acc[1] = acc[1] or head
		per_zombie[zid] = acc
	for zid in per_zombie:
		var acc: Array = per_zombie[zid]
		# Démembrement : point d'impact et arme du coup (ZombieManager.srv_gib).
		_gib_at = acc[2] if acc[2] is Vector3 else Vector3.INF
		_gib_weapon = w.id
		damage_zombie(zid, int(acc[0]), pid, acc[1], dir, HitKind.BULLET)
		_gib_at = Vector3.INF
		_gib_weapon = ""
		if acc[2] is Vector3:
			blood.append(acc[2])
		# Munitions incendiaires : le zombie brûle quelques secondes.
		if s.has("burn_dps"):
			_burns[zid] = [pid, float(s.burn_dps), GameClock.now() + float(s.get("burn_time", 2.0))]
	return blood


## Serveur : dégâts de brûlure, appliqués par tranches de BURN_TICK secondes.
func _tick_burns(t: float) -> void:
	if t < _burn_next:
		return
	_burn_next = t + BURN_TICK
	for zid in _burns.keys():
		var b: Array = _burns[zid]
		var z: Zombie = game.zombies.get_zombie(zid)
		if z == null or not z.is_alive() or t > b[2]:
			_burns.erase(zid)
			continue
		damage_zombie(zid, int(b[1] * BURN_TICK), b[0], false, Vector3.UP, HitKind.SPECIAL)


## Dégâts de zone (arme spéciale) au premier impact.
func _apply_splash(pid: int, w: Dictionary, impacts: PackedVector3Array, hits: Array) -> void:
	var s := WeaponDB.stats(w.id, w.pap)
	if not s.has("splash_radius"):
		return
	var center := _splash_center(impacts, hits)
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
			damage_zombie(z.id, int(float(s.splash_damage) * k), pid, false, (z.global_position - center).normalized(), HitKind.SPLASH)
	# Dégâts à soi réduits (pas de tir ami entre joueurs, comme BO1).
	if p and s.has("self_damage"):
		var ds := (p.global_position + Vector3.UP * 0.9).distance_to(center)
		if ds <= r:
			damage_player(pid, int(float(s.self_damage) * (1.0 - ds / r * 0.5)), center)
	_cl_splash_fx.rpc(center, r)


## Point d'explosion : premier zombie touché, sinon premier impact sur le décor.
static func _splash_center(impacts: PackedVector3Array, hits: Array) -> Vector3:
	if not hits.is_empty() and hits[0] is Array and hits[0].size() >= 4 and hits[0][3] is Vector3:
		return hits[0][3]
	if impacts.size() >= 2:
		return impacts[0]
	return Vector3.INF


## Serveur : explosion d'un objet lancé (grenade, PELUCHE LEURRE) : dégâts de
## zone décroissants aux zombies en vue du centre (pas à travers les murs),
## dégâts réduits au seul lanceur (pas de tir ami, comme BO1).
func explosion(pid: int, center: Vector3, radius: float, damage: int, self_damage: int) -> void:
	if not multiplayer.is_server():
		return
	var space := game.get_world_3d().direct_space_state
	var eye := center + Vector3.UP * 0.25
	for z: Zombie in game.zombies.alive.duplicate():
		var body := z.global_position + Vector3.UP * 0.9
		var d := body.distance_to(center)
		if d > radius:
			continue
		var q := PhysicsRayQueryParameters3D.create(eye, body, 1)
		if not space.intersect_ray(q).is_empty():
			continue
		damage_zombie(z.id, ThrowableRules.splash(damage, radius, d), pid, false, (z.global_position - center).normalized(), HitKind.SPLASH)
	var p: Player = game.players.get(pid)
	if p and self_damage > 0:
		var ds := (p.global_position + Vector3.UP * 0.9).distance_to(center)
		if ds <= radius:
			damage_player(pid, int(ThrowableRules.splash(self_damage, radius, ds)), center)


## Serveur : inflige des dégâts à un zombie. Point d'entrée unique pour toutes
## les sources (balles, couteau, pièges...). `fling` non nul : mort projetée
## à cette vitesse (corps envoyé en vol, ZombieFling).
func damage_zombie(zid: int, dmg: int, pid: int, headshot: bool, dir: Vector3, kind: HitKind, fling := Vector3.ZERO) -> void:
	if not multiplayer.is_server():
		return
	var z: Zombie = game.zombies.get_zombie(zid)
	if z == null or not z.is_alive() or dmg <= 0:
		return
	z.health -= dmg
	var killed := z.health <= 0
	# Un zombie projeté n'est pas démembré.
	if fling == Vector3.ZERO:
		game.zombies.srv_gib(z, dmg, killed, headshot, kind, _gib_at, _gib_weapon, dir)
	if killed and fling != Vector3.ZERO:
		game.zombies.kill_flung(zid, fling)
	elif killed:
		# Force du coup (ragdoll) dans la longueur de `dir` : même chute partout.
		var impulse := ZombieRagdoll.kill_impulse(kind, _gib_weapon, headshot, dir, randf_range(-1.0, 1.0))
		game.zombies.kill(zid, headshot, impulse, kind == HitKind.SPLASH or kind == HitKind.TRAP)
	else:
		NetCodec.append_zombie_hit(_fx_buf, zid, headshot)
	zombie_damaged.emit(pid, zid, dmg, killed, headshot, kind)
	# Tireur parti entre le tir et l'impact (projectile en vol, brûlure) : les
	# dégâts comptent, mais aucune confirmation vers un pair inconnu.
	if pid > 0 and killed and session.get_data(pid) != null:
		if pid == multiplayer.get_unique_id():
			_cl_hit_confirm(killed, headshot)
		else:
			_cl_hit_confirm.rpc_id(pid, killed, headshot)


## Serveur : envoie en un seul message (non fiable, purement visuel et sonore)
## les tirs et touches de l'image, au lieu d'un RPC fiable chacun.
func _flush_fx() -> void:
	if _fx_buf.is_empty():
		return
	var buf := _fx_buf
	_fx_buf = PackedByteArray()
	_cl_fx.rpc(buf)


@rpc("authority", "call_local", "unreliable_ordered")
func _cl_fx(buf: PackedByteArray) -> void:
	for e: Dictionary in NetCodec.decode_fx(buf):
		if e.type == NetCodec.FX_SHOT:
			_cl_shot_fx(e.pid, e.weapon, e.pap, e.origin, e.impacts, e.blood)
		else:
			_cl_zombie_hit(e.zid, e.headshot)


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
	WeaponAudio.play_3d(s, pap, origin)
	# Les effets partent de la bouche de l'arme du soldat (pas de ses yeux).
	var muzzle := origin
	if shooter and shooter.visual and shooter.visual.weapon_model and shooter.visual.weapon_model.is_visible_in_tree():
		muzzle = shooter.visual.weapon_model.to_global(WeaponModels.anchor(s.model, "muzzle"))
	var aim := (impacts[0] - origin).normalized() if impacts.size() >= 2 else Vector3.ZERO
	if s.get("flash", "rifle") != "none":
		fx.muzzle_flash(muzzle, aim)
	if s.has("projectile_speed") and impacts.size() >= 2:
		ProjectileFx.launch(fx, muzzle, impacts[0], s.projectile_speed, s.get("tracer", "grenade"), pap)
		return
	var n := 0
	for i in range(0, impacts.size() - 1, 2):
		if n < 3:
			fx.tracer(muzzle, impacts[i])
		n += 1
		fx.impact(impacts[i], impacts[i + 1], i == 0, fx.surface_at(impacts[i], impacts[i + 1]))
	for bp in blood_points:
		if n < 3:
			fx.tracer(muzzle, bp)
		n += 1
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
	# À terre, on garde le couteau (comme le pistolet) : seul un mort est refusé.
	var pid := NetGuard.known_sender(self, game)
	var t := GameClock.now()
	if pid == NetGuard.NO_SENDER or t < _melee_ready.get(pid, 0.0):
		return
	var pd := session.get_data(pid)
	if pd.life == PlayerData.Life.DEAD:
		return
	var p: Player = game.players.get(pid)
	if not NetGuard.finite_vec(origin) or not NetGuard.valid_dir(dir):
		return
	# Référence : dernier état reçu et accepté (pas la position interpolée).
	var ref := p.srv_origin()
	if not origin_ok(ref, origin, MAX_ORIGIN_ERROR + 1.7):
		return
	_melee_ready[pid] = t + WeaponDB.MELEE_COOLDOWN * 0.8
	cancel_reload(pid, true)  # le couteau interrompt le rechargement (BO1)
	VoxSystem.say(pid, "exert_melee", 0.3)
	dir = Vector3(dir.x, 0.0, dir.z).normalized()
	# Après une fente, le client frappe depuis sa nouvelle position (`origin`,
	# déjà bornée ci-dessus) : la cible doit être au contact de cette origine,
	# et à portée de fente de la position connue du serveur.
	var feet := Vector3(origin.x, ref.y, origin.z)
	var positions := []
	for z: Zombie in game.zombies.alive:
		positions.append(z.global_position)
	var i := KnifeDB.pick_target(feet, dir, positions, KnifeDB.RANGE + MELEE_SLACK, 0.0)
	if i < 0:
		return
	var best: Zombie = game.zombies.alive[i]
	var flat := best.global_position - ref
	flat.y = 0.0
	if flat.length() > KnifeDB.LUNGE_RANGE + KnifeDB.RANGE + MELEE_SLACK:
		return
	damage_zombie(best.id, KnifeDB.damage(pd.knife), pid, false, dir, HitKind.MELEE)
	_cl_melee_fx.rpc(best.global_position + Vector3.UP * 1.2)


## Marge du couteau côté serveur (interpolation des zombies chez le client).
const MELEE_SLACK := 0.5
## Intervalle minimal entre deux fins de plongeon d'un joueur (s) : un vrai
## plongeon dure bien plus (élan, vol, glissade à plat ventre).
const DIVE_MIN_INTERVAL := 0.5


## Le client annonce la fin de son plongeon ; le serveur borne la position
## (écart avec la position connue) et la hauteur, puis émet le signal.
@rpc("any_peer", "call_local", "reliable")
func srv_dive_landed(pos: Vector3, height: float) -> void:
	var pid := NetGuard.alive_sender(self, game)
	if pid == NetGuard.NO_SENDER:
		return
	var p: Player = game.players.get(pid)
	# Un plongeon par DIVE_MIN_INTERVAL au plus, et seulement si le serveur a
	# vu ce joueur plonger (drapeau de son état de mouvement) : pas
	# d'explosion NOVA FLOP à volonté par simple RPC.
	var t := GameClock.now()
	if t - float(_dive_last.get(pid, -INF)) < DIVE_MIN_INTERVAL or not p.srv_dived_recently():
		return
	_dive_last[pid] = t
	# Référence : dernier état reçu et accepté (la position interpolée traîne
	# derrière le client avec de la latence : atterrissage honnête refusé).
	pos = dive_landing(p.srv_origin(), pos)
	player_dived_landed.emit(pid, pos, clampf(height, 0.0, 12.0) if NetGuard.finite(height) else 0.0)


@rpc("authority", "call_local", "reliable")
func _cl_melee_fx(pos: Vector3) -> void:
	Audio.play_3d("knife_hit", pos, 0.0)
	Audio.play_3d("knife_flesh", pos, -2.0, 0.1)
	game.fx_root.blood_hit(pos, Vector3.DOWN, 1.2)


# --------------------------------------------------------------------------
# Rechargement / changement d'arme
# --------------------------------------------------------------------------

@rpc("any_peer", "call_local", "reliable")
func srv_reload(slot: int) -> void:
	# Limiteur avant les refus signalés au client (une demande refusée lui
	# renvoie un message : pas d'amplification d'une inondation).
	var pid := NetGuard.server_sender(self)
	if pid == NetGuard.NO_SENDER:
		return
	var pd := session.get_data(pid)
	if pd == null or _reload_end.has(pid) or not _action_limit.allow(pid):
		return
	var w: Dictionary = pd.current_weapon()
	if slot != pd.slot or w.is_empty() or w.mag >= WeaponDB.stats(w.id, w.pap).mag or w.reserve <= 0:
		# Refusé (arme changée ou chargeur déjà plein ici, demande partie avant
		# que le client ne l'apprenne) : le client arrête le rechargement qu'il a
		# prédit.
		_notify_reload_cancelled(pid)
		return
	var t := GameClock.now()
	var dur := reload_time(pid, w)
	_reload_end[pid] = [slot, t + dur * RELOAD_LENIENCY, t, dur]
	_cl_reload_fx.rpc(pid)
	if w.mag == 0:
		VoxSystem.say(pid, "reload", 0.2)


func reload_time(pid: int, w: Dictionary) -> float:
	return WeaponDB.stats(w.id, w.pap).reload


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
	var pid := NetGuard.server_sender(self)
	if pid == NetGuard.NO_SENDER:
		return
	var pd := session.get_data(pid)
	if pd == null or slot < 0 or slot >= pd.weapons.size() or slot == pd.slot or not _action_limit.allow(pid):
		return
	# Changer d'arme annule le rechargement (BO1) : rien n'est remis dans le
	# chargeur, sauf les cartouches déjà poussées (fusil à pompe).
	_keep_loaded_shells(pid, _reload_end.get(pid, []))
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
## `keep_shells` : interruption par le joueur sur la même arme (couteau,
## grenade) : les cartouches déjà poussées une à une restent, comme côté
## client (WeaponController.abort_reload), et l'inventaire est resynchronisé
## (même sans cartouche : la prédiction du client, à quelques ms près, est
## corrigée).
func cancel_reload(pid: int, keep_shells := false) -> void:
	var r: Array = _reload_end.get(pid, [])
	_reload_end.erase(pid)
	if keep_shells and not r.is_empty():
		_keep_loaded_shells(pid, r)
		session.sync_inventory(pid)
	elif not keep_shells and not r.is_empty():
		# Annulation décidée par le serveur (mise à terre, caisse…)
		# sans forcément changer d'arme : le client, qui prédit son
		# rechargement, doit l'arrêter aussi, sinon il remplirait son chargeur
		# à l'échéance (chargeur plein affiché, tirs refusés ici).
		_notify_reload_cancelled(pid)


## Serveur : prévient le joueur `pid` que son rechargement n'a pas (ou plus)
## lieu ici (WeaponController.server_cancelled_reload).
func _notify_reload_cancelled(pid: int) -> void:
	if not is_inside_tree():
		return
	if pid == multiplayer.get_unique_id():
		_cl_reload_cancelled()
	else:
		_cl_reload_cancelled.rpc_id(pid)


@rpc("authority", "call_remote", "reliable")
func _cl_reload_cancelled() -> void:
	var p: Player = game.local_player if game else null
	if p and p.weapons:
		p.weapons.server_cancelled_reload()


## Rechargement coup par coup `r` ([slot, fin, début, durée]) interrompu :
## les cartouches insérées jusque-là passent de la réserve au chargeur.
## Vrai si des munitions ont bougé.
func _keep_loaded_shells(pid: int, r: Array) -> bool:
	var pd := session.get_data(pid)
	if r.size() < 4 or pd == null or int(r[0]) != pd.slot or float(r[3]) <= 0.0:
		return false
	var w: Dictionary = pd.current_weapon()
	if w.is_empty():
		return false
	var frac := (GameClock.now() - float(r[2])) / float(r[3])
	var n := WeaponController.shells_loaded(WeaponDB.stats(w.id, w.pap), w, frac)
	w.mag += n
	w.reserve -= n
	return n > 0


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
	_last_hurt[pid] = GameClock.now()
	session.sync_stats(pid)
	_cl_player_hurt.rpc(pid, from)
	if pd.health > 0 and pd.health < pd.max_health * 0.35:
		VoxSystem.say(pid, "low_health", 0.7)
	if pd.health > 0:
		VoxSystem.say(pid, "hurt", 0.55)
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
		if t - _last_hurt.get(pid, 0.0) < REGEN_DELAY:
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
	_fire_limit.forget(pid)
	_reload_end.erase(pid)
	_last_hurt.erase(pid)
	_melee_ready.erase(pid)
	_dive_last.erase(pid)
	_resync_limit.forget(pid)
	_action_limit.forget(pid)
