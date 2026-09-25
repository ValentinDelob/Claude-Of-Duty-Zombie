class_name Combat
extends Node
## Validation serveur des actions d'armes (chemin réseau : /root/Game/Combat).
##
## Le client envoie ses intentions (tir, rechargement, changement d'arme) ; le
## serveur vérifie munitions, cadence, position, puis applique les effets et
## diffuse les événements visuels. Le client ne décide jamais des dégâts.

## Tolérance de cadence : rafale max acceptée d'un coup (gigue réseau).
const FIRE_BURST_TOKENS := 4.0
## Écart max toléré entre l'origine du tir annoncée et la position serveur.
const MAX_ORIGIN_ERROR := 3.0
## Le serveur termine le rechargement un peu plus tôt que le client : le premier
## tir après un rechargement n'est jamais refusé à cause de la latence.
const RELOAD_LENIENCY := 0.85

signal shot_validated(pid: int)
signal shot_rejected(pid: int, reason: String)

var game: Game
var session: Session

## Serveur : état par joueur.
var _tokens: Dictionary = {}        # pid -> float
var _last_refill: Dictionary = {}   # pid -> sec
var _reload_end: Dictionary = {}    # pid -> [slot, end_time]


func _ready() -> void:
	game = get_parent()
	session = game.get_node("Session")


static func now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _process(_delta: float) -> void:
	if not multiplayer.is_server():
		return
	var t := now()
	for pid in _reload_end.keys():
		var r: Array = _reload_end[pid]
		if t >= r[1]:
			_reload_end.erase(pid)
			_finish_reload(pid, r[0])


# --------------------------------------------------------------------------
# Tir
# --------------------------------------------------------------------------

## `impacts` : positions/normales d'impact sur le décor (visuel, relayé aux autres).
## `hits` : touches revendiquées sur des zombies [zid, zone, distance] (validées).
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
	_apply_hits(pid, w, origin, dir.normalized(), hits)
	_cl_shot_fx.rpc(pid, w.id, w.pap, origin, impacts)


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


## Multiplicateur de cadence (atout Double Tap plus tard).
func game_rate_mult(_pid: int) -> float:
	return 1.0


func _apply_hits(_pid: int, _w: Dictionary, _origin: Vector3, _dir: Vector3, _hits: Array) -> void:
	# Les zombies n'existent pas encore : implémenté avec le système de dégâts.
	pass


@rpc("authority", "call_local", "reliable")
func _cl_shot_fx(pid: int, weapon_id: String, pap: bool, origin: Vector3, impacts: PackedVector3Array) -> void:
	# Le tireur a déjà joué ses effets localement (prédiction).
	if pid == multiplayer.get_unique_id():
		return
	var fx: Fx = game.fx_root
	var s := WeaponDB.stats(weapon_id, pap)
	Audio.play_3d(s.sound, origin, 0.0, 0.05, 8)
	fx.muzzle_flash(origin)
	for i in range(0, impacts.size() - 1, 2):
		fx.tracer(origin, impacts[i])
		fx.impact(impacts[i], impacts[i + 1], i == 0)


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


func reload_time(_pid: int, w: Dictionary) -> float:
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


# --------------------------------------------------------------------------
# Mêlée
# --------------------------------------------------------------------------

@rpc("any_peer", "call_local", "reliable")
func srv_melee(_origin: Vector3, _dir: Vector3) -> void:
	if not multiplayer.is_server():
		return
	# Les zombies arrivent avec le système de dégâts.


func is_reloading(pid: int) -> bool:
	return _reload_end.has(pid)


func forget_player(pid: int) -> void:
	_tokens.erase(pid)
	_last_refill.erase(pid)
	_reload_end.erase(pid)
