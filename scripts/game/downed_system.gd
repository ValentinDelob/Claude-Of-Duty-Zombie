class_name DownedSystem
extends Node
## Joueurs à terre et réanimation (chemin réseau : /root/Game/Downed).
##
## Serveur : à 0 PV, un joueur passe DOWNED (au lieu de mourir). Il rampe, garde
## un pistolet, peut tirer. Un coéquipier le réanime en maintenant [F] près de
## lui ; sinon il se vide de son sang et meurt (retour à la manche suivante).
## En solo, LAZARUS TONIC relève automatiquement le joueur ; sans lui, c'est
## la fin de la partie.

const BLEEDOUT_TIME := 30.0
const REVIVE_TIME := 4.0
const REVIVE_TIME_LAZARUS := 2.0
const SOLO_SELF_REVIVE := 4.0
const REVIVE_RANGE := 2.4
const REVIVED_HEALTH := 100

signal state_changed(pid: int)

var game: Game
## pid -> {bleed_end, reviver, revive_start, revive_dur, self_revive}
## (côté serveur : temps absolus ; côté client : copie pour l'affichage)
var downed: Dictionary = {}
## Durée de saignement (modifiable par les tests).
var bleedout_time := BLEEDOUT_TIME


func _ready() -> void:
	game = get_parent()


static func now() -> float:
	return Time.get_ticks_msec() / 1000.0


func is_downed(pid: int) -> bool:
	return downed.has(pid)


# --------------------------------------------------------------------------
# Serveur
# --------------------------------------------------------------------------

## Serveur : le joueur tombe à terre.
func srv_down(pid: int) -> void:
	var pd := game.session.get_data(pid)
	if pd == null or pd.life != PlayerData.Life.ALIVE:
		return
	var had_lazarus := pd.has_perk("lazarus")
	pd.life = PlayerData.Life.DOWNED
	pd.downs += 1
	# Dernier recours : on garde le pistolet (ou on en reçoit un).
	pd.saved_weapons = pd.weapons.duplicate(true)
	var pistol := pd.has_weapon(WeaponDB.STARTING_WEAPON)
	var last_stand: Dictionary = pd.weapons[pistol].duplicate() if pistol >= 0 else WeaponDB.new_instance(WeaponDB.STARTING_WEAPON)
	pd.weapons = [last_stand]
	pd.slot = 0
	game.perks.srv_clear(pid)
	game.combat.cancel_reload(pid)
	var entry := {"bleed_end": now() + bleedout_time, "reviver": 0, "revive_start": 0.0, "revive_dur": 0.0, "self_revive": 0.0}
	if Net.mode == Net.Mode.SOLO and had_lazarus:
		entry.self_revive = now() + SOLO_SELF_REVIVE
	downed[pid] = entry
	game.session.sync_stats(pid)
	game.session.sync_inventory(pid)
	print("[Downed] %s est à terre" % Net.player_name(pid))
	_broadcast(pid)
	game.check_game_over()


## Serveur : un coéquipier commence à réanimer `target`.
func srv_start_revive(reviver: int, target: int) -> void:
	var e: Dictionary = downed.get(target, {})
	var rpd := game.session.get_data(reviver)
	if e.is_empty() or reviver == target or rpd == null or rpd.life != PlayerData.Life.ALIVE:
		return
	if e.reviver != 0:
		return
	if not _in_range(reviver, target):
		return
	e.reviver = reviver
	e.revive_start = now()
	e.revive_dur = REVIVE_TIME_LAZARUS if rpd.has_perk("lazarus") else REVIVE_TIME
	_broadcast(target)


func srv_stop_revive(reviver: int, target: int) -> void:
	var e: Dictionary = downed.get(target, {})
	if e.is_empty() or e.reviver != reviver:
		return
	e.reviver = 0
	e.revive_start = 0.0
	_broadcast(target)


func _in_range(a: int, b: int) -> bool:
	var pa: Player = game.players.get(a)
	var pb: Player = game.players.get(b)
	return pa != null and pb != null and pa.global_position.distance_to(pb.global_position) <= REVIVE_RANGE + 0.8


func _process(_delta: float) -> void:
	if not multiplayer.is_server() or downed.is_empty():
		return
	var t := now()
	for pid in downed.keys():
		var e: Dictionary = downed[pid]
		if e.self_revive > 0.0 and t >= e.self_revive:
			_revive(pid)
			continue
		if e.reviver != 0:
			var rpd := game.session.get_data(e.reviver)
			if rpd == null or rpd.life != PlayerData.Life.ALIVE or not _in_range(e.reviver, pid):
				srv_stop_revive(e.reviver, pid)
			elif t - e.revive_start >= e.revive_dur:
				var rev: int = e.reviver
				_revive(pid)
				var r := game.session.get_data(rev)
				if r:
					r.revives += 1
					game.session.sync_stats(rev)
				continue
		# Pas de fin de saignement pendant une réanimation en cours.
		if e.reviver == 0 and t >= e.bleed_end:
			_bleed_out(pid)


func _revive(pid: int) -> void:
	var pd := game.session.get_data(pid)
	downed.erase(pid)
	if pd == null:
		return
	pd.life = PlayerData.Life.ALIVE
	pd.health = mini(REVIVED_HEALTH, pd.max_health)
	# On récupère ses armes, avec les munitions du pistolet utilisé à terre.
	var used: Dictionary = pd.weapons[0] if not pd.weapons.is_empty() else {}
	pd.weapons = pd.saved_weapons.duplicate(true) if not pd.saved_weapons.is_empty() else [WeaponDB.new_instance(WeaponDB.STARTING_WEAPON)]
	var pistol := pd.has_weapon(WeaponDB.STARTING_WEAPON)
	if pistol >= 0 and not used.is_empty() and used.id == WeaponDB.STARTING_WEAPON:
		pd.weapons[pistol] = used
	pd.saved_weapons = []
	pd.slot = clampi(pd.slot, 0, pd.weapons.size() - 1)
	game.session.sync_stats(pid)
	game.session.sync_inventory(pid)
	print("[Downed] %s est réanimé" % Net.player_name(pid))
	_cl_revived.rpc(pid)
	_broadcast(pid)


func _bleed_out(pid: int) -> void:
	downed.erase(pid)
	var pd := game.session.get_data(pid)
	if pd:
		pd.saved_weapons = []
	print("[Downed] %s a succombé" % Net.player_name(pid))
	_broadcast(pid)
	game.kill_player(pid)


## Serveur : un joueur quitte la partie.
func forget(pid: int) -> void:
	downed.erase(pid)
	for other in downed:
		if downed[other].reviver == pid:
			downed[other].reviver = 0
			_broadcast(other)


# --------------------------------------------------------------------------
# Réplication
# --------------------------------------------------------------------------

func _broadcast(pid: int) -> void:
	var t := now()
	var e: Dictionary = downed.get(pid, {})
	if e.is_empty():
		_cl_state.rpc(pid, false, 0.0, 0, 0.0, 0.0)
	else:
		var progress: float = (t - e.revive_start) if e.reviver != 0 else 0.0
		_cl_state.rpc(pid, true, e.bleed_end - t, e.reviver, progress, e.revive_dur)


@rpc("authority", "call_local", "reliable")
func _cl_state(pid: int, is_down: bool, bleed_left: float, reviver: int, progress: float, dur: float) -> void:
	var t := now()
	var was_down := _was_shown.has(pid)
	if not multiplayer.is_server():
		if is_down:
			downed[pid] = {"bleed_end": t + bleed_left, "reviver": reviver, "revive_start": t - progress, "revive_dur": dur, "self_revive": 0.0}
		else:
			downed.erase(pid)
	var p: Player = game.players.get(pid)
	if p:
		p.set_downed(is_down)
	if is_down and not was_down:
		_was_shown[pid] = true
		if p:
			Audio.play_3d("player_down", p.global_position + Vector3.UP, 0.0, 0.0)
		if pid == multiplayer.get_unique_id():
			if GameState.state in [GameState.State.PLAYING, GameState.State.ROUND_END]:
				GameState.set_state(GameState.State.PLAYER_DOWN)
		else:
			game.hud.flash_message("%s EST À TERRE !" % Net.player_name(pid).to_upper())
	elif not is_down and was_down:
		_was_shown.erase(pid)
		if pid == multiplayer.get_unique_id() and GameState.state == GameState.State.PLAYER_DOWN:
			var pause := game.rounds.phase == RoundManager.Phase.INTERMISSION
			GameState.set_state(GameState.State.ROUND_END if pause else GameState.State.PLAYING)
	state_changed.emit(pid)


var _was_shown: Dictionary = {}


@rpc("authority", "call_local", "reliable")
func _cl_revived(pid: int) -> void:
	var p: Player = game.players.get(pid)
	if p:
		Audio.play_3d("revive", p.global_position + Vector3.UP, 0.0, 0.0)
	if pid == multiplayer.get_unique_id():
		game.hud.show_banner("RÉANIMÉ", 1.2)


## Toutes les machines : infos pour le HUD.
func bleed_left(pid: int) -> float:
	var e: Dictionary = downed.get(pid, {})
	return maxf(e.get("bleed_end", 0.0) - now(), 0.0)


func revive_progress(pid: int) -> float:
	var e: Dictionary = downed.get(pid, {})
	if e.is_empty() or e.reviver == 0 or e.revive_dur <= 0.0:
		return 0.0
	return clampf((now() - e.revive_start) / e.revive_dur, 0.0, 1.0)


func reviver_of(pid: int) -> int:
	return downed.get(pid, {}).get("reviver", 0)


## Serveur : une auto-réanimation (LAZARUS en solo) est-elle programmée ?
func will_self_revive(pid: int) -> bool:
	return downed.get(pid, {}).get("self_revive", 0.0) > 0.0
